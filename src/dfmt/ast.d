module dfmt.ast;

import dmd.visitor;
import dmd.astcodegen;
import dmd.astenums;
import dmd.tokens;
import dmd.parse;
import dmd.mtype;
import dmd.identifier;
import dmd.hdrgen;
import dmd.init;
import dmd.rootobject;
import dmd.target;
import dmd.root.string : toDString;
import dfmt.config;
import dfmt.editorconfig;
import std.range;
import std.format : format;
import std.stdio : writeln, File;

extern (C++) class FormatVisitor : SemanticTimeTransitiveVisitor
{
    File.LockingTextWriter buf;
    const Config* config;
    string eol;
    uint depth;
    bool declstring; // set while declaring alias for string,wstring or dstring

    this(File.LockingTextWriter buf, Config* config)
    {
        this.buf = buf;
        this.config = config;
        // Set newline character
        final switch (config.end_of_line)
        {
        case EOL.lf:
            eol = "\n";
            break;
        case EOL.cr:
            eol = "\r";
            break;
        case EOL.crlf:
            eol = "\r\n";
            break;
        case EOL._default:
            version (Windows)
            {
                eol = "\r\n";
            }
            else
            {
                eol = "\n";
            }
            break;
        case EOL._unspecified:
            assert(false, "end of line character is unspecified");
        }
    }

    alias visit = SemanticTimeTransitiveVisitor.visit;

    void indent()
    {
        if (depth)
        {
            auto indent = config.indent_style == IndentStyle.space ? ' '.repeat()
                .take(depth * 4) : '\t'.repeat().take(depth);
            buf.put(indent.array);
        }
    }

    pragma(inline)
    void newline()
    {
        buf.put(eol);
    }

    /*******************************************
    * Helpers to write different AST nodes to buffer
    */
    void writeStc(StorageClass stc)
    {
        bool writeSpace = false;

        if (stc & ASTCodegen.STC.scopeinferred)
        {
            stc &= ~(ASTCodegen.STC.scope_ | ASTCodegen.STC.scopeinferred);
        }
        if (stc & ASTCodegen.STC.returninferred)
        {
            stc &= ~(ASTCodegen.STC.return_ | ASTCodegen.STC.returninferred);
        }

        // Put scope ref return into a standard order
        string rrs;
        const isout = (stc & ASTCodegen.STC.out_) != 0;
        final switch (buildScopeRef(stc))
        {
        case ScopeRef.None:
        case ScopeRef.Scope:
        case ScopeRef.Ref:
        case ScopeRef.Return:
            break;

        case ScopeRef.ReturnScope:
            rrs = "return scope";
            goto L1;
        case ScopeRef.ReturnRef:
            rrs = isout ? "return out" : "return ref";
            goto L1;
        case ScopeRef.RefScope:
            rrs = isout ? "out scope" : "ref scope";
            goto L1;
        case ScopeRef.ReturnRef_Scope:
            rrs = isout ? "return out scope" : "return ref scope";
            goto L1;
        case ScopeRef.Ref_ReturnScope:
            rrs = isout ? "out return scope" : "ref return scope";
            goto L1;
        L1:
            buf.put(rrs);
            writeSpace = true;
            stc &= ~(
                ASTCodegen.STC.out_ | ASTCodegen.STC.scope_ | ASTCodegen.STC.ref_ | ASTCodegen
                    .STC.return_);
            break;
        }

        while (stc)
        {
            const s = stcToString(stc);
            if (!s.length)
                break;
            if (writeSpace)
                buf.put(' ');
            writeSpace = true;
            buf.put(s);
        }

        if (writeSpace)
            buf.put(' ');

    }

    void writeFloat(Type type, real value)
    {
        import dmd.root.ctfloat;
        import core.stdc.string : strlen;

        /** sizeof(value)*3 is because each byte of mantissa is max
            of 256 (3 characters). The string will be "-M.MMMMe-4932".
            (ie, 8 chars more than mantissa). Plus one for trailing \0.
            Plus one for rounding. */
        const(size_t) BUFFER_LEN = value.sizeof * 3 + 8 + 1 + 1;
        char[BUFFER_LEN] buffer = void;
        CTFloat.sprint(buffer.ptr, BUFFER_LEN, 'g', value);
        assert(strlen(buffer.ptr) < BUFFER_LEN);
        if (buffer.ptr[strlen(buffer.ptr) - 1] == '.')
            buffer.ptr[strlen(buffer.ptr) - 1] = char.init;
        buf.put(buffer.array);

        if (type)
        {
            Type t = type.toBasetype();
            switch (t.ty)
            {
            case Tfloat32:
            case Timaginary32:
            case Tcomplex32:
                buf.put('F');
                break;
            case Tfloat80:
            case Timaginary80:
            case Tcomplex80:
                buf.put('L');
                break;
            default:
                break;
            }
            if (t.isimaginary())
                buf.put('i');
        }
    }

    void writeExpr(ASTCodegen.Expression e)
    {
        import dmd.hdrgen : EXPtoString;

        void visit(ASTCodegen.Expression e)
        {
            buf.put(EXPtoString(e.op));
        }

        void visitInteger(ASTCodegen.IntegerExp e)
        {
            auto v = e.toInteger();
            if (e.type)
            {
                Type t = e.type;
            L1:
                switch (t.ty)
                {
                case Tenum:
                    {
                        TypeEnum te = cast(TypeEnum) t;
                        auto sym = te.sym;
                        if (sym && sym.members)
                        {
                            foreach (em; *sym.members)
                            {
                                if ((cast(ASTCodegen.EnumMember) em).value.toInteger == v)
                                {
                                    buf.put(format("%s.%s", sym.toString(), em.ident.toString()));
                                    return;
                                }
                            }
                        }

                        buf.put(format("cast(%s)", te.sym.toString()));
                        t = te.sym.memtype;
                        goto L1;
                    }
                case Tchar:
                case Twchar:
                case Tdchar:
                    {
                        buf.put(cast(dchar) v);
                        break;
                    }
                case Tint8:
                    buf.put("cast(byte)");
                    goto L2;
                case Tint16:
                    buf.put("cast(short)");
                    goto L2;
                case Tint32:
                L2:
                    buf.put(format("%d", cast(int) v));
                    break;
                case Tuns8:
                    buf.put("cast(ubyte)");
                    goto case Tuns32;
                case Tuns16:
                    buf.put("cast(ushort)");
                    goto case Tuns32;
                case Tuns32:
                    buf.put(format("%uu", cast(uint) v));
                    break;
                case Tint64:
                    if (v == long.min)
                    {
                        // https://issues.dlang.org/show_bug.cgi?id=23173
                        // This is a special case because - is not part of the
                        // integer literal and 9223372036854775808L overflows a long
                        buf.put("cast(long)-9223372036854775808");
                    }
                    else
                    {
                        buf.put(format("%lldL", v));
                    }
                    break;
                case Tuns64:
                    buf.put(format("%lluLU", v));
                    break;
                case Tbool:
                    buf.put(v ? "true" : "false");
                    break;
                case Tpointer:
                    buf.put("cast(");
                    buf.put(t.toString());
                    buf.put(')');
                    if (target.ptrsize == 8)
                        goto case Tuns64;
                    else if (target.ptrsize == 4 ||
                        target.ptrsize == 2)
                        goto case Tuns32;
                    else
                        assert(0);

                case Tvoid:
                    buf.put("cast(void)0");
                    break;
                default:
                    break;
                }
            }
            else if (v & 0x8000000000000000L)
                buf.put(format("0x%llx", v));
            else
                buf.put(format("%lu", v));
        }

        void visitError(ASTCodegen.ErrorExp _)
        {
            buf.put("__error");
        }

        void visitVoidInit(ASTCodegen.VoidInitExp _)
        {
            buf.put("void");
        }

        void visitReal(ASTCodegen.RealExp e)
        {
            writeFloat(e.type, e.value);
        }

        void visitComplex(ASTCodegen.ComplexExp e)
        {
            /* Print as:
         *  (re+imi)
         */
            buf.put('(');
            writeFloat(e.type, e.value.re);
            buf.put('+');
            writeFloat(e.type, e.value.im);
            buf.put("i)");
        }

        void visitIdentifier(ASTCodegen.IdentifierExp e)
        {
            /* writeln("writing ident"); */
            buf.put(e.ident.toString());
        }

        void visitDsymbol(ASTCodegen.DsymbolExp e)
        {
            buf.put(e.s.toString());
        }

        void visitThis(ASTCodegen.ThisExp _)
        {
            buf.put("this");
        }

        void visitSuper(ASTCodegen.SuperExp _)
        {
            buf.put("super");
        }

        void visitNull(ASTCodegen.NullExp _)
        {
            buf.put("null");
        }

        void visitString(ASTCodegen.StringExp e)
        {
            buf.put('"');
            foreach (i; 0 .. e.len)
            {
                buf.put(e.getCodeUnit(i));
            }
            buf.put('"');
            if (e.postfix)
                buf.put(e.postfix);
        }

        void visitArrayLiteral(ASTCodegen.ArrayLiteralExp e)
        {
            buf.put('[');
            writeArgs(e.elements, e.basis);
            buf.put(']');
        }

        void visitAssocArrayLiteral(ASTCodegen.AssocArrayLiteralExp e)
        {
            buf.put('[');
            foreach (i, key; *e.keys)
            {
                if (i)
                    buf.put(", ");
                writeExprWithPrecedence(key, PREC.assign);
                buf.put(':');
                auto value = (*e.values)[i];
                writeExprWithPrecedence(value, PREC.assign);
            }
            buf.put(']');
        }

        void visitStructLiteral(ASTCodegen.StructLiteralExp e)
        {
            import dmd.expression;

            buf.put(e.sd.toString());
            buf.put('(');
            // CTFE can generate struct literals that contain an AddrExp pointing
            // to themselves, need to avoid infinite recursion:
            // struct S { this(int){ this.s = &this; } S* s; }
            // const foo = new S(0);
            if (e.stageflags & stageToCBuffer)
                buf.put("<recursion>");
            else
            {
                const old = e.stageflags;
                e.stageflags |= stageToCBuffer;
                writeArgs(e.elements);
                e.stageflags = old;
            }
            buf.put(')');
        }

        void visitCompoundLiteral(ASTCodegen.CompoundLiteralExp e)
        {
            buf.put('(');
            writeTypeWithIdent(e.type, null);
            buf.put(')');
            writeInitializer(e.initializer);
        }

        void visitType(ASTCodegen.TypeExp e)
        {
            writeTypeWithIdent(e.type, null);
        }

        void visitScope(ASTCodegen.ScopeExp e)
        {
            import core.stdc.string : strlen;

            if (e.sds.isTemplateInstance())
            {
                e.sds.accept(this);
            }
            else
            {
                buf.put(e.sds.kind().toDString());
                buf.put(' ');
                buf.put(e.sds.toString());
            }
        }

        void visitTemplate(ASTCodegen.TemplateExp e)
        {
            buf.put(e.td.toString());
        }

        void visitNew(ASTCodegen.NewExp e)
        {
            if (e.thisexp)
            {
                writeExprWithPrecedence(e.thisexp, PREC.primary);
                buf.put('.');
            }
            buf.put("new ");
            writeTypeWithIdent(e.newtype, null);
            if (e.arguments && e.arguments.length)
            {
                buf.put('(');
                writeArgs(e.arguments, null, e.names);
                buf.put(')');
            }
        }

        void visitNewAnonClass(ASTCodegen.NewAnonClassExp e)
        {
            if (e.thisexp)
            {
                writeExprWithPrecedence(e.thisexp, PREC.primary);
                buf.put('.');
            }
            buf.put("new");
            buf.put(" class ");
            if (e.arguments && e.arguments.length)
            {
                buf.put('(');
                writeArgs(e.arguments);
                buf.put(')');
            }
            if (e.cd)
                e.cd.accept(this);
        }

        void visitSymOff(ASTCodegen.SymOffExp e)
        {
            if (e.offset)
                buf.put(format("(& %s%+lld)", e.var.toString(), e.offset));
            else if (e.var.isTypeInfoDeclaration())
                buf.put(e.var.toString());
            else
                buf.put(format("& %s", e.var.toString()));
        }

        void visitVar(ASTCodegen.VarExp e)
        {
            buf.put(e.var.toString());
        }

        void visitOver(ASTCodegen.OverExp e)
        {
            buf.put(e.vars.ident.toString());
        }

        void visitTuple(ASTCodegen.TupleExp e)
        {
            if (e.e0)
            {
                buf.put('(');
                writeExpr(e.e0);
                buf.put(", AliasSeq!(");
                writeArgs(e.exps);
                buf.put("))");
            }
            else
            {
                buf.put("AliasSeq!(");
                writeArgs(e.exps);
                buf.put(')');
            }
        }

        void visitFunc(ASTCodegen.FuncExp e)
        {
            /* writeln("stringifying func literal"); */
            e.fd.accept(this);
        }

        void visitDeclaration(ASTCodegen.DeclarationExp e)
        {
            /* Normal dmd execution won't reach here - regular variable declarations
         * are handled in visit(ASTCodegen.ExpStatement), so here would be used only when
         * we'll directly call Expression.toString() for debugging.
         */
            if (e.declaration)
            {
                if (auto var = e.declaration.isVarDeclaration())
                {
                    // For debugging use:
                    // - Avoid printing newline.
                    // - Intentionally use the format (Type var;)
                    //   which isn't correct as regular D code.
                    buf.put('(');

                    writeVarDecl(var, false);

                    buf.put(';');
                    buf.put(')');
                }
                else
                    e.declaration.accept(this);
            }
        }

        void visitTypeid(ASTCodegen.TypeidExp e)
        {
            buf.put("typeid(");
            writeObject(e.obj);
            buf.put(')');
        }

        void visitTraits(ASTCodegen.TraitsExp e)
        {
            buf.put("__traits(");
            if (e.ident)
                buf.put(e.ident.toString());
            if (e.args)
            {
                foreach (arg; *e.args)
                {
                    buf.put(", ");
                    writeObject(arg);
                }
            }
            buf.put(')');
        }

        void visitHalt(ASTCodegen.HaltExp _)
        {
            buf.put("halt");
        }

        void visitIs(ASTCodegen.IsExp e)
        {
            buf.put("is(");
            writeTypeWithIdent(e.targ, e.id);
            if (e.tok2 != TOK.reserved)
            {
                buf.put(format(" %s %s", Token.toChars(e.tok), Token.toChars(e.tok2)));
            }
            else if (e.tspec)
            {
                if (e.tok == TOK.colon)
                    buf.put(" : ");
                else
                    buf.put(" == ");
                writeTypeWithIdent(e.tspec, null);
            }
            if (e.parameters && e.parameters.length)
            {
                buf.put(", ");
                visitTemplateParameters(e.parameters);
            }
            buf.put(')');
        }

        void visitUna(ASTCodegen.UnaExp e)
        {
            buf.put(EXPtoString(e.op));
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitLoweredAssignExp(ASTCodegen.LoweredAssignExp e)
        {
            visit(cast(ASTCodegen.BinExp) e);
        }

        void visitBin(ASTCodegen.BinExp e)
        {
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            buf.put(' ');
            buf.put(EXPtoString(e.op));
            buf.put(' ');
            writeExprWithPrecedence(e.e2, cast(PREC)(precedence[e.op] + 1));
        }

        void visitComma(ASTCodegen.CommaExp e)
        {
            // CommaExp is generated by the compiler so it shouldn't
            // appear in error messages or header files.
            // For now, this treats the case where the compiler
            // generates CommaExp for temporaries by calling
            // the `sideeffect.copyToTemp` function.
            auto ve = e.e2.isVarExp();

            // not a CommaExp introduced for temporaries, go on
            // the old path
            if (!ve || !(ve.var.storage_class & STC.temp))
            {
                visitBin(cast(ASTCodegen.BinExp) e);
                return;
            }

            // CommaExp that contain temporaries inserted via
            // `copyToTemp` are usually of the form
            // ((T __temp = exp), __tmp).
            // Asserts are here to easily spot
            // missing cases where CommaExp
            // are used for other constructs
            auto vd = ve.var.isVarDeclaration();
            assert(vd && vd._init);

            if (auto ei = vd._init.isExpInitializer())
            {
                ASTCodegen.Expression commaExtract;
                auto exp = ei.exp;
                if (auto ce = exp.isConstructExp())
                    commaExtract = ce.e2;
                else if (auto se = exp.isStructLiteralExp())
                    commaExtract = se;

                if (commaExtract)
                {
                    writeExprWithPrecedence(commaExtract, precedence[exp.op]);
                    return;
                }
            }

            // not one of the known cases, go on the old path
            visitBin(cast(ASTCodegen.BinExp) e);
            return;
        }

        void visitMixin(ASTCodegen.MixinExp e)
        {
            buf.put("mixin(");
            writeArgs(e.exps);
            buf.put(')');
        }

        void visitImport(ASTCodegen.ImportExp e)
        {
            buf.put("import(");
            writeExprWithPrecedence(e.e1, PREC.assign);
            buf.put(')');
        }

        void visitAssert(ASTCodegen.AssertExp e)
        {
            buf.put("assert(");
            writeExprWithPrecedence(e.e1, PREC.assign);
            if (e.msg)
            {
                buf.put(", ");
                writeExprWithPrecedence(e.msg, PREC.assign);
            }
            buf.put(')');
        }

        void visitThrow(ASTCodegen.ThrowExp e)
        {
            buf.put("throw ");
            writeExprWithPrecedence(e.e1, PREC.unary);
        }

        void visitDotId(ASTCodegen.DotIdExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            if (e.arrow)
                buf.put("->");
            else
                buf.put('.');
            buf.put(e.ident.toString());
        }

        void visitDotTemplate(ASTCodegen.DotTemplateExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('.');
            buf.put(e.td.toString());
        }

        void visitDotVar(ASTCodegen.DotVarExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('.');
            buf.put(e.var.toString());
        }

        void visitDotTemplateInstance(ASTCodegen.DotTemplateInstanceExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('.');
            e.ti.accept(this);
        }

        void visitDelegate(ASTCodegen.DelegateExp e)
        {
            buf.put('&');
            if (!e.func.isNested() || e.func.needThis())
            {
                writeExprWithPrecedence(e.e1, PREC.primary);
                buf.put('.');
            }
            buf.put(e.func.toString());
        }

        void visitDotType(ASTCodegen.DotTypeExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('.');
            buf.put(e.sym.toString());
        }

        void visitCall(ASTCodegen.CallExp e)
        {
            /* writeln("stringifying func call"); */
            if (e.e1.op == EXP.type)
            {
                /* Avoid parens around type to prevent forbidden cast syntax:
             *   (sometype)(arg1)
             * This is ok since types in constructor calls
             * can never depend on parens anyway
             */
                /* writeln("stringifying func e1 expr"); */
                writeExpr(e.e1);
            }
            else /* writeln("stringifying func e1 expr with precedence"); */
                writeExprWithPrecedence(e.e1, precedence[e.op]);
            /* writeln("writing brace at indent level: ", depth); */
            buf.put('(');
            writeArgs(e.arguments, null, e.names);
            buf.put(')');
        }

        void visitPtr(ASTCodegen.PtrExp e)
        {
            buf.put('*');
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitDelete(ASTCodegen.DeleteExp e)
        {
            buf.put("delete ");
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitCast(ASTCodegen.CastExp e)
        {
            buf.put("cast(");
            if (e.to)
                writeTypeWithIdent(e.to, null);
            else
            {
                buf.put(MODtoString(e.mod));
            }
            buf.put(')');
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitVector(ASTCodegen.VectorExp e)
        {
            buf.put("cast(");
            writeTypeWithIdent(e.to, null);
            buf.put(')');
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitVectorArray(ASTCodegen.VectorArrayExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put(".array");
        }

        void visitSlice(ASTCodegen.SliceExp e)
        {
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            buf.put('[');
            if (e.upr || e.lwr)
            {
                if (e.lwr)
                    writeSize(e.lwr);
                else
                    buf.put('0');
                buf.put("..");
                if (e.upr)
                    writeSize(e.upr);
                else
                    buf.put('$');
            }
            buf.put(']');
        }

        void visitArrayLength(ASTCodegen.ArrayLengthExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put(".length");
        }

        void visitInterval(ASTCodegen.IntervalExp e)
        {
            writeExprWithPrecedence(e.lwr, PREC.assign);
            buf.put("..");
            writeExprWithPrecedence(e.upr, PREC.assign);
        }

        void visitDelegatePtr(ASTCodegen.DelegatePtrExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put(".ptr");
        }

        void visitDelegateFuncptr(ASTCodegen.DelegateFuncptrExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put(".funcptr");
        }

        void visitArray(ASTCodegen.ArrayExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('[');
            writeArgs(e.arguments);
            buf.put(']');
        }

        void visitDot(ASTCodegen.DotExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('.');
            writeExprWithPrecedence(e.e2, PREC.primary);
        }

        void visitIndex(ASTCodegen.IndexExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put('[');
            writeSize(e.e2);
            buf.put(']');
        }

        void visitPost(ASTCodegen.PostExp e)
        {
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            buf.put(EXPtoString(e.op));
        }

        void visitPre(ASTCodegen.PreExp e)
        {
            buf.put(EXPtoString(e.op));
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitRemove(ASTCodegen.RemoveExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            buf.put(".remove(");
            writeExprWithPrecedence(e.e2, PREC.assign);
            buf.put(')');
        }

        void visitCond(ASTCodegen.CondExp e)
        {
            writeExprWithPrecedence(e.econd, PREC.oror);
            buf.put(" ? ");
            writeExprWithPrecedence(e.e1, PREC.expr);
            buf.put(" : ");
            writeExprWithPrecedence(e.e2, PREC.cond);
        }

        void visitDefaultInit(ASTCodegen.DefaultInitExp e)
        {
            buf.put(EXPtoString(e.op));
        }

        void visitClassReference(ASTCodegen.ClassReferenceExp e)
        {
            buf.put(e.value.toString());
        }

        switch (e.op)
        {
        default:
            if (auto be = e.isBinExp())
                return visitBin(be);
            else if (auto ue = e.isUnaExp())
                return visitUna(ue);
            else if (auto de = e.isDefaultInitExp())
                return visitDefaultInit(e.isDefaultInitExp());
            return visit(e);

        case EXP.int64:
            return visitInteger(e.isIntegerExp());
        case EXP.error:
            return visitError(e.isErrorExp());
        case EXP.void_:
            return visitVoidInit(e.isVoidInitExp());
        case EXP.float64:
            return visitReal(e.isRealExp());
        case EXP.complex80:
            return visitComplex(e.isComplexExp());
        case EXP.identifier:
            return visitIdentifier(e.isIdentifierExp());
        case EXP.dSymbol:
            return visitDsymbol(e.isDsymbolExp());
        case EXP.this_:
            return visitThis(e.isThisExp());
        case EXP.super_:
            return visitSuper(e.isSuperExp());
        case EXP.null_:
            return visitNull(e.isNullExp());
        case EXP.string_:
            return visitString(e.isStringExp());
        case EXP.arrayLiteral:
            return visitArrayLiteral(e.isArrayLiteralExp());
        case EXP.assocArrayLiteral:
            return visitAssocArrayLiteral(e.isAssocArrayLiteralExp());
        case EXP.structLiteral:
            return visitStructLiteral(e.isStructLiteralExp());
        case EXP.compoundLiteral:
            return visitCompoundLiteral(e.isCompoundLiteralExp());
        case EXP.type:
            return visitType(e.isTypeExp());
        case EXP.scope_:
            return visitScope(e.isScopeExp());
        case EXP.template_:
            return visitTemplate(e.isTemplateExp());
        case EXP.new_:
            return visitNew(e.isNewExp());
        case EXP.newAnonymousClass:
            return visitNewAnonClass(e.isNewAnonClassExp());
        case EXP.symbolOffset:
            return visitSymOff(e.isSymOffExp());
        case EXP.variable:
            return visitVar(e.isVarExp());
        case EXP.overloadSet:
            return visitOver(e.isOverExp());
        case EXP.tuple:
            return visitTuple(e.isTupleExp());
        case EXP.function_:
            return visitFunc(e.isFuncExp());
        case EXP.declaration:
            return visitDeclaration(e.isDeclarationExp());
        case EXP.typeid_:
            return visitTypeid(e.isTypeidExp());
        case EXP.traits:
            return visitTraits(e.isTraitsExp());
        case EXP.halt:
            return visitHalt(e.isHaltExp());
        case EXP.is_:
            return visitIs(e.isExp());
        case EXP.comma:
            return visitComma(e.isCommaExp());
        case EXP.mixin_:
            return visitMixin(e.isMixinExp());
        case EXP.import_:
            return visitImport(e.isImportExp());
        case EXP.assert_:
            return visitAssert(e.isAssertExp());
        case EXP.throw_:
            return visitThrow(e.isThrowExp());
        case EXP.dotIdentifier:
            return visitDotId(e.isDotIdExp());
        case EXP.dotTemplateDeclaration:
            return visitDotTemplate(e.isDotTemplateExp());
        case EXP.dotVariable:
            return visitDotVar(e.isDotVarExp());
        case EXP.dotTemplateInstance:
            return visitDotTemplateInstance(e.isDotTemplateInstanceExp());
        case EXP.delegate_:
            return visitDelegate(e.isDelegateExp());
        case EXP.dotType:
            return visitDotType(e.isDotTypeExp());
        case EXP.call:
            return visitCall(e.isCallExp());
        case EXP.star:
            return visitPtr(e.isPtrExp());
        case EXP.delete_:
            return visitDelete(e.isDeleteExp());
        case EXP.cast_:
            return visitCast(e.isCastExp());
        case EXP.vector:
            return visitVector(e.isVectorExp());
        case EXP.vectorArray:
            return visitVectorArray(e.isVectorArrayExp());
        case EXP.slice:
            return visitSlice(e.isSliceExp());
        case EXP.arrayLength:
            return visitArrayLength(e.isArrayLengthExp());
        case EXP.interval:
            return visitInterval(e.isIntervalExp());
        case EXP.delegatePointer:
            return visitDelegatePtr(e.isDelegatePtrExp());
        case EXP.delegateFunctionPointer:
            return visitDelegateFuncptr(e.isDelegateFuncptrExp());
        case EXP.array:
            return visitArray(e.isArrayExp());
        case EXP.dot:
            return visitDot(e.isDotExp());
        case EXP.index:
            return visitIndex(e.isIndexExp());
        case EXP.minusMinus:
        case EXP.plusPlus:
            return visitPost(e.isPostExp());
        case EXP.preMinusMinus:
        case EXP.prePlusPlus:
            return visitPre(e.isPreExp());
        case EXP.remove:
            return visitRemove(e.isRemoveExp());
        case EXP.question:
            return visitCond(e.isCondExp());
        case EXP.classReference:
            return visitClassReference(e.isClassReferenceExp());
        case EXP.loweredAssignExp:
            return visitLoweredAssignExp(e.isLoweredAssignExp());
        }
    }

    void writeArgs(
        ASTCodegen.Expressions* expressions,
        ASTCodegen.Expression basis = null,
        ASTCodegen.Identifiers* names = null)
    {
        if (!expressions || !expressions.length)
            return;
        version (all)
        {
            foreach (i, el; *expressions)
            {
                if (i)
                    buf.put(", ");

                if (names && i < names.length && (*names)[i])
                {
                    buf.put((*names)[i].toString());
                    buf.put(": ");
                }
                if (!el)
                    el = basis;
                if (el)
                    writeExprWithPrecedence(el, PREC.assign);
            }
        }
        else
        {
            // Sparse style formatting, for debug use only
            //      [0..length: basis, 1: e1, 5: e5]
            if (basis)
            {
                buf.put("0..");
                buf.print(expressions.length);
                buf.put(": ");
                writeExprWithPrecedence(basis, PREC.assign);
            }
            foreach (i, el; *expressions)
            {
                if (el)
                {
                    if (basis)
                    {
                        buf.put(", ");
                        buf.put(i);
                        buf.put(": ");
                    }
                    else if (i)
                        buf.put(", ");
                    writeExprWithPrecedence(el, PREC.assign);
                }
            }
        }
    }

    void writeExprWithPrecedence(ASTCodegen.Expression e, PREC pr)
    {
        if (e.op == 0xFF)
        {
            buf.put("<FF>");
            return;
        }
        assert(precedence[e.op] != PREC.zero);
        assert(pr != PREC.zero);
        /* Despite precedence, we don't allow a<b<c expressions.
     * They must be parenthesized.
     */
        if (precedence[e.op] < pr || (pr == PREC.rel && precedence[e.op] == pr)
            || (pr >= PREC.or && pr <= PREC.and && precedence[e.op] == PREC.rel))
        {
            buf.put('(');
            writeExpr(e);
            buf.put(')');
        }
        else
        {
            writeExpr(e);
        }
    }

    void writeTypeWithIdent(ASTCodegen.Type t, const Identifier ident, ubyte modMask = 0)
    {
        if (auto tf = t.isTypeFunction())
        {
            writeFuncIdentWithPrefix(tf, ident, null);
            return;
        }
        writeWithMask(t, modMask);
        if (ident)
        {
            buf.put(' ');
            buf.put(ident.toString());
        }
    }

    void writeWithMask(Type t, ubyte modMask)
    {
        // Tuples and functions don't use the type constructor syntax
        if (modMask == t.mod || t.ty == Tfunction || t.ty == Ttuple)
        {
            writeType(t);
        }
        else
        {
            ubyte m = t.mod & ~(t.mod & modMask);
            if (m & MODFlags.shared_)
            {
                buf.put(MODtoString(MODFlags.shared_));
                buf.put('(');
            }
            if (m & MODFlags.wild)
            {
                buf.put(MODtoString(MODFlags.wild));
                buf.put('(');
            }
            if (m & (MODFlags.const_ | MODFlags.immutable_))
            {
                buf.put(MODtoString(m & (MODFlags.const_ | MODFlags.immutable_)));
                buf.put('(');
            }
            writeType(t);
            if (m & (MODFlags.const_ | MODFlags.immutable_))
                buf.put(')');
            if (m & MODFlags.wild)
                buf.put(')');
            if (m & MODFlags.shared_)
                buf.put(')');
        }
    }

    void writeStatement(ASTCodegen.Statement s)
    {
        void visitDefaultCase(ASTCodegen.Statement _)
        {
            assert(0, "unrecognized statement in writeStatement()");
        }

        void visitError(ASTCodegen.ErrorStatement _)
        {
            buf.put("__error__");
            newline();
        }

        void visitExp(ASTCodegen.ExpStatement s)
        {
            /* writeln("visiting exp decl"); */
            if (s.exp && s.exp.op == EXP.declaration &&
                (cast(ASTCodegen.DeclarationExp) s.exp).declaration)
            {
                (cast(ASTCodegen.DeclarationExp) s.exp).declaration.accept(this);
                return;
            }
            /* writeln("writing exp: ", s.exp.stringof); */
            if (s.exp)
                writeExpr(s.exp);
            buf.put(';');
            newline();
        }

        void visitDtorExp(ASTCodegen.DtorExpStatement s)
        {
            visitExp(s);
        }

        void visitMixin(ASTCodegen.MixinStatement s)
        {
            buf.put("mixin(");
            writeArgs(s.exps);
            buf.put(");");
        }

        void visitCompound(ASTCodegen.CompoundStatement s)
        {
            foreach (sx; *s.statements)
            {
                if (sx)
                {
                    writeStatement(sx);
                }
            }
        }

        void visitCompoundAsm(ASTCodegen.CompoundAsmStatement s)
        {
            visitCompound(s);
        }

        void visitCompoundDeclaration(ASTCodegen.CompoundDeclarationStatement s)
        {
            bool anywritten = false;
            foreach (sx; *s.statements)
            {
                auto ds = sx ? sx.isExpStatement() : null;
                if (ds && ds.exp.isDeclarationExp())
                {
                    auto d = ds.exp.isDeclarationExp().declaration;
                    if (auto v = d.isVarDeclaration())
                    {
                        writeVarDecl(v, anywritten);
                    }
                    else
                        d.accept(this);
                    anywritten = true;
                }
            }
            buf.put(';');
        }

        void visitUnrolledLoop(ASTCodegen.UnrolledLoopStatement s)
        {
            buf.put("/*unrolled*/ {");
            newline();
            depth++;
            foreach (sx; *s.statements)
            {
                if (sx)
                    writeStatement(sx);
            }
            depth--;
            buf.put('}');
            newline();
        }

        void visitScope(ASTCodegen.ScopeStatement s)
        {
            buf.put('{');
            newline();
            depth++;
            if (s.statement)
                writeStatement(s.statement);
            depth--;
            buf.put('}');
            newline();
        }

        void visitWhile(ASTCodegen.WhileStatement s)
        {
            buf.put("while (");
            if (auto p = s.param)
            {
                // Print condition assignment
                StorageClass stc = p.storageClass;
                if (!p.type && !stc)
                    stc = STC.auto_;
                writeStc(stc);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    buf.put(p.ident.toString());
                buf.put(" = ");
            }
            writeExpr(s.condition);
            buf.put(')');
            newline();
            if (s._body)
                writeStatement(s._body);
        }

        void visitDo(ASTCodegen.DoStatement s)
        {
            buf.put("do");
            newline();
            if (s._body)
                writeStatement(s._body);
            buf.put("while (");
            writeExpr(s.condition);
            buf.put(");");
            newline();
        }

        void visitFor(ASTCodegen.ForStatement s)
        {
            buf.put("for (");
            if (s._init)
            {
                writeStatement(s._init);
            }
            else
                buf.put(';');
            if (s.condition)
            {
                buf.put(' ');
                writeExpr(s.condition);
            }
            buf.put(';');
            if (s.increment)
            {
                buf.put(' ');
                writeExpr(s.increment);
            }
            buf.put(')');
            newline();
            buf.put('{');
            newline();
            depth++;
            if (s._body)
                writeStatement(s._body);
            depth--;
            buf.put('}');
            newline();
        }

        void visitForeachWithoutBody(ASTCodegen.ForeachStatement s)
        {
            buf.put(Token.toString(s.op));
            buf.put(" (");
            foreach (i, p; *s.parameters)
            {
                if (i)
                    buf.put(", ");
                writeStc(p.storageClass);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    buf.put(p.ident.toString());
            }
            buf.put("; ");
            writeExpr(s.aggr);
            buf.put(')');
            newline();
        }

        void visitForeach(ASTCodegen.ForeachStatement s)
        {
            visitForeachWithoutBody(s);
            buf.put('{');
            newline();
            depth++;
            if (s._body)
                writeStatement(s._body);
            depth--;
            buf.put('}');
            newline();
        }

        void visitForeachRangeWithoutBody(ASTCodegen.ForeachRangeStatement s)
        {
            buf.put(Token.toString(s.op));
            buf.put(" (");
            if (s.prm.type)
                writeTypeWithIdent(s.prm.type, s.prm.ident);
            else
                buf.put(s.prm.ident.toString());
            buf.put("; ");
            writeExpr(s.lwr);
            buf.put(" .. ");
            writeExpr(s.upr);
            buf.put(')');
            newline();
        }

        void visitForeachRange(ASTCodegen.ForeachRangeStatement s)
        {
            visitForeachRangeWithoutBody(s);
            buf.put('{');
            newline();
            depth++;
            if (s._body)
                writeStatement(s._body);
            depth--;
            buf.put('}');
            newline();
        }

        void visitStaticForeach(ASTCodegen.StaticForeachStatement s)
        {
            indent();
            buf.put("static ");
            if (s.sfe.aggrfe)
            {
                visitForeach(s.sfe.aggrfe);
            }
            else
            {
                assert(s.sfe.rangefe);
                visitForeachRange(s.sfe.rangefe);
            }
        }

        void visitForwarding(ASTCodegen.ForwardingStatement s)
        {
            writeStatement(s.statement);
        }

        void visitIf(ASTCodegen.IfStatement s)
        {
            buf.put("if (");
            if (Parameter p = s.prm)
            {
                StorageClass stc = p.storageClass;
                if (!p.type && !stc)
                    stc = STC.auto_;
                writeStc(stc);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    buf.put(p.ident.toString());
                buf.put(" = ");
            }
            writeExpr(s.condition);
            buf.put(')');
            newline();
            if (s.ifbody.isScopeStatement())
            {
                writeStatement(s.ifbody);
            }
            else
            {
                depth++;
                writeStatement(s.ifbody);
                depth--;
            }
            if (s.elsebody)
            {
                buf.put("else");
                if (!s.elsebody.isIfStatement())
                {
                    newline();
                }
                else
                {
                    buf.put(' ');
                }
                if (s.elsebody.isScopeStatement() || s.elsebody.isIfStatement())
                {
                    writeStatement(s.elsebody);
                }
                else
                {
                    depth++;
                    writeStatement(s.elsebody);
                    depth--;
                }
            }
        }

        void visitConditional(ASTCodegen.ConditionalStatement s)
        {
            s.condition.accept(this);
            newline();
            buf.put('{');
            newline();
            depth++;
            if (s.ifbody)
                writeStatement(s.ifbody);
            depth--;
            buf.put('}');
            newline();
            if (s.elsebody)
            {
                buf.put("else");
                newline();
                buf.put('{');
                depth++;
                newline();
                writeStatement(s.elsebody);
                depth--;
                buf.put('}');
            }
            newline();
        }

        void visitPragma(ASTCodegen.PragmaStatement s)
        {
            buf.put("pragma (");
            buf.put(s.ident.toString());
            if (s.args && s.args.length)
            {
                buf.put(", ");
                writeArgs(s.args);
            }
            buf.put(')');
            if (s._body)
            {
                newline();
                buf.put('{');
                newline();
                depth++;
                writeStatement(s._body);
                depth--;
                buf.put('}');
                newline();
            }
            else
            {
                buf.put(';');
                newline();
            }
        }

        void visitStaticAssert(ASTCodegen.StaticAssertStatement s)
        {
            s.sa.accept(this);
        }

        void visitSwitch(ASTCodegen.SwitchStatement s)
        {
            buf.put(s.isFinal ? "final switch (" : "switch (");
            if (auto p = s.param)
            {
                // Print condition assignment
                StorageClass stc = p.storageClass;
                if (!p.type && !stc)
                    stc = STC.auto_;
                writeStc(stc);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    buf.put(p.ident.toString());
                buf.put(" = ");
            }
            writeExpr(s.condition);
            buf.put(')');
            newline();
            if (s._body)
            {
                if (!s._body.isScopeStatement())
                {
                    buf.put('{');
                    newline();
                    depth++;
                    writeStatement(s._body);
                    depth--;
                    buf.put('}');
                    newline();
                }
                else
                {
                    writeStatement(s._body);
                }
            }
        }

        void visitCase(ASTCodegen.CaseStatement s)
        {
            buf.put("case ");
            writeExpr(s.exp);
            buf.put(':');
            newline();
            writeStatement(s.statement);
        }

        void visitCaseRange(ASTCodegen.CaseRangeStatement s)
        {
            buf.put("case ");
            writeExpr(s.first);
            buf.put(": .. case ");
            writeExpr(s.last);
            buf.put(':');
            newline();
            writeStatement(s.statement);
        }

        void visitDefault(ASTCodegen.DefaultStatement s)
        {
            buf.put("default:");
            newline();
            writeStatement(s.statement);
        }

        void visitGotoDefault(ASTCodegen.GotoDefaultStatement _)
        {
            buf.put("goto default;");
            newline();
        }

        void visitGotoCase(ASTCodegen.GotoCaseStatement s)
        {
            buf.put("goto case");
            if (s.exp)
            {
                buf.put(' ');
                writeExpr(s.exp);
            }
            buf.put(';');
            newline();
        }

        void visitSwitchError(ASTCodegen.SwitchErrorStatement _)
        {
            buf.put("SwitchErrorStatement::toCBuffer()");
            newline();
        }

        void visitReturn(ASTCodegen.ReturnStatement s)
        {
            buf.put("return ");
            if (s.exp)
                writeExpr(s.exp);
            buf.put(';');
            newline();
        }

        void visitBreak(ASTCodegen.BreakStatement s)
        {
            buf.put("break");
            if (s.ident)
            {
                buf.put(' ');
                buf.put(s.ident.toString());
            }
            buf.put(';');
            newline();
        }

        void visitContinue(ASTCodegen.ContinueStatement s)
        {
            buf.put("continue");
            if (s.ident)
            {
                buf.put(' ');
                buf.put(s.ident.toString());
            }
            buf.put(';');
            newline();
        }

        void visitSynchronized(ASTCodegen.SynchronizedStatement s)
        {
            buf.put("synchronized");
            if (s.exp)
            {
                buf.put('(');
                writeExpr(s.exp);
                buf.put(')');
            }
            if (s._body)
            {
                buf.put(' ');
                writeStatement(s._body);
            }
        }

        void visitWith(ASTCodegen.WithStatement s)
        {
            buf.put("with (");
            writeExpr(s.exp);
            buf.put(")");
            newline();
            if (s._body)
                writeStatement(s._body);
        }

        void visitTryCatch(ASTCodegen.TryCatchStatement s)
        {
            buf.put("try");
            newline();
            if (s._body)
            {
                if (s._body.isScopeStatement())
                {
                    writeStatement(s._body);
                }
                else
                {
                    depth++;
                    writeStatement(s._body);
                    depth--;
                }
            }
            foreach (c; *s.catches)
            {
                buf.put("catch");
                if (c.type)
                {
                    buf.put('(');
                    writeTypeWithIdent(c.type, c.ident);
                    buf.put(')');
                }
                newline();
                buf.put('{');
                newline();
                depth++;
                if (c.handler)
                    writeStatement(c.handler);
                depth--;
                buf.put('}');
                newline();
            }
        }

        void visitTryFinally(ASTCodegen.TryFinallyStatement s)
        {
            buf.put("try");
            newline();
            buf.put('{');
            newline();
            depth++;
            writeStatement(s._body);
            depth--;
            buf.put('}');
            newline();
            buf.put("finally");
            newline();
            if (s.finalbody.isScopeStatement())
            {
                writeStatement(s.finalbody);
            }
            else
            {
                depth++;
                writeStatement(s.finalbody);
                depth--;
            }
        }

        void visitScopeGuard(ASTCodegen.ScopeGuardStatement s)
        {
            buf.put(Token.toString(s.tok));
            buf.put(' ');
            if (s.statement)
                writeStatement(s.statement);
        }

        void visitThrow(ASTCodegen.ThrowStatement s)
        {
            buf.put("throw ");
            writeExpr(s.exp);
            buf.put(';');
            newline();
        }

        void visitDebug(ASTCodegen.DebugStatement s)
        {
            if (s.statement)
            {
                writeStatement(s.statement);
            }
        }

        void visitGoto(ASTCodegen.GotoStatement s)
        {
            buf.put("goto ");
            buf.put(s.ident.toString());
            buf.put(';');
            newline();
        }

        void visitLabel(ASTCodegen.LabelStatement s)
        {
            buf.put(s.ident.toString());
            buf.put(':');
            newline();
            if (s.statement)
                writeStatement(s.statement);
        }

        void visitAsm(ASTCodegen.AsmStatement s)
        {
            buf.put("asm { ");
            Token* t = s.tokens;
            depth++;
            while (t)
            {
                buf.put(Token.toString(t.value));
                if (t.next &&
                    t.value != TOK.min &&
                    t.value != TOK.comma && t.next.value != TOK.comma &&
                    t.value != TOK.leftBracket && t.next.value != TOK.leftBracket &&
                    t.next.value != TOK.rightBracket &&
                    t.value != TOK.leftParenthesis && t.next.value != TOK.leftParenthesis &&
                    t.next.value != TOK.rightParenthesis &&
                    t.value != TOK.dot && t.next.value != TOK.dot)
                {
                    buf.put(' ');
                }
                t = t.next;
            }
            depth--;
            buf.put("; }");
            newline();
        }

        void visitInlineAsm(ASTCodegen.InlineAsmStatement s)
        {
            visitAsm(s);
        }

        void visitGccAsm(ASTCodegen.GccAsmStatement s)
        {
            visitAsm(s);
        }

        void visitImport(ASTCodegen.ImportStatement s)
        {
            foreach (imp; *s.imports)
            {
                imp.accept(this);
            }
        }

        import dmd.statement;

        mixin VisitStatement!void visit;
        visit.VisitStatement(s);
    }

    void writeFuncBody(ASTCodegen.FuncDeclaration f)
    {
        if (!f.fbody)
        {
            if (f.fensures || f.frequires)
            {
                newline();
                writeContracts(f);
            }
            buf.put(';');
            newline();
            return;
        }

        newline();
        bool requireDo = writeContracts(f);

        if (requireDo)
        {
            buf.put("do");
            newline();
        }
        buf.put('{');
        newline();
        depth++;
        /* writeln("writing at depth ", depth); */
        writeStatement(f.fbody);
        depth--;
        /* writeln("finished writing, now depth ", depth); */
        buf.put('}');
        newline();
    }

    // Returns: whether `do` is needed to write the function body
    bool writeContracts(ASTCodegen.FuncDeclaration f)
    {
        bool requireDo = false;
        // in{}
        if (f.frequires)
        {
            foreach (frequire; *f.frequires)
            {
                buf.put("in");
                if (auto es = frequire.isExpStatement())
                {
                    assert(es.exp && es.exp.op == EXP.assert_);
                    buf.put(" (");
                    writeExpr((cast(ASTCodegen.AssertExp) es.exp).e1);
                    buf.put(')');
                    newline();
                    requireDo = false;
                }
                else
                {
                    newline();
                    writeStatement(frequire);
                    requireDo = true;
                }
            }
        }
        // out{}
        if (f.fensures)
        {
            foreach (fensure; *f.fensures)
            {
                buf.put("out");
                if (auto es = fensure.ensure.isExpStatement())
                {
                    assert(es.exp && es.exp.op == EXP.assert_);
                    buf.put(" (");
                    if (fensure.id)
                    {
                        buf.put(fensure.id.toString());
                    }
                    buf.put("; ");
                    writeExpr((cast(ASTCodegen.AssertExp) es.exp).e1);
                    buf.put(')');
                    newline();
                    requireDo = false;
                }
                else
                {
                    if (fensure.id)
                    {
                        buf.put('(');
                        buf.put(fensure.id.toString());
                        buf.put(')');
                    }
                    newline();
                    writeStatement(fensure.ensure);
                    requireDo = true;
                }
            }
        }
        return requireDo;
    }

    void writeInitializer(Initializer inx)
    {
        void visitError(ErrorInitializer _)
        {
            buf.put("__error__");
        }

        void visitVoid(VoidInitializer _)
        {
            buf.put("void");
        }

        void visitStruct(StructInitializer si)
        {
            //printf("StructInitializer::toCBuffer()\n");
            buf.put('{');
            foreach (i, const id; si.field)
            {
                if (i)
                    buf.put(", ");
                if (id)
                {
                    buf.put(id.toString());
                    buf.put(':');
                }
                if (auto iz = si.value[i])
                    writeInitializer(iz);
            }
            buf.put('}');
        }

        void visitArray(ArrayInitializer ai)
        {
            buf.put('[');
            foreach (i, ex; ai.index)
            {
                if (i)
                    buf.put(", ");
                if (ex)
                {
                    writeExpr(ex);
                    buf.put(':');
                }
                if (auto iz = ai.value[i])
                    writeInitializer(iz);
            }
            buf.put(']');
        }

        void visitExp(ExpInitializer ei)
        {
            writeExpr(ei.exp);
        }

        void visitC(CInitializer ci)
        {
            buf.put('{');
            foreach (i, ref DesigInit di; ci.initializerList)
            {
                if (i)
                    buf.put(", ");
                if (di.designatorList)
                {
                    foreach (ref Designator d; (*di.designatorList)[])
                    {
                        if (d.exp)
                        {
                            buf.put('[');
                            d.exp.accept(this);
                            buf.put(']');
                        }
                        else
                        {
                            buf.put('.');
                            buf.put(d.ident.toString());
                        }
                    }
                    buf.put('=');
                }
                writeInitializer(di.initializer);
            }
            buf.put('}');
        }

        mixin VisitInitializer!void visit;
        visit.VisitInitializer(inx);
    }

    void writeObject(RootObject oarg)
    {
        /* The logic of this should match what genIdent() does. The _dynamic_cast()
     * function relies on all the pretty strings to be unique for different classes
     * See https://issues.dlang.org/show_bug.cgi?id=7375
     * Perhaps it would be better to demangle what genIdent() does.
     */
        import dmd.dtemplate;
        import dmd.expression : WANTvalue;

        if (auto t = isType(oarg))
        {
            writeTypeWithIdent(t, null);
        }
        else if (auto e = isExpression(oarg))
        {
            if (e.op == EXP.variable)
                e = e.optimize(WANTvalue); // added to fix https://issues.dlang.org/show_bug.cgi?id=7375
            writeExprWithPrecedence(e, PREC.assign);
        }
        else if (ASTCodegen.Dsymbol s = isDsymbol(oarg))
        {
            const p = s.ident ? s.ident.toString() : s.toString();
            buf.put(p);
        }
        else if (auto v = isTuple(oarg))
        {
            auto args = &v.objects;
            foreach (i, arg; *args)
            {
                if (i)
                    buf.put(", ");
                writeObject(arg);
            }
        }
        else if (auto p = isParameter(oarg))
        {
            writeParam(p);
        }
        else if (!oarg)
        {
            buf.put("NULL");
        }
        else
        {
            assert(0);
        }
    }

    void writeVarDecl(ASTCodegen.VarDeclaration v, bool anywritten)
    {
        void vinit(ASTCodegen.VarDeclaration v)
        {
            auto ie = v._init.isExpInitializer();
            if (ie && (ie.exp.op == EXP.construct || ie.exp.op == EXP.blit))
                writeExpr((cast(ASTCodegen.AssignExp) ie.exp).e2);
            else
                writeInitializer(v._init);
        }

        if (anywritten)
        {
            buf.put(", ");
            buf.put(v.ident.toString());
        }
        else
        {
            auto stc = v.storage_class;
            writeStc(stc);
            if (v.type)
                writeTypeWithIdent(v.type, v.ident);
            else
                buf.put(v.ident.toString());
        }
        if (v._init)
        {
            buf.put(" = ");
            vinit(v);
        }
    }

    void writeSize(ASTCodegen.Expression e)
    {
        import dmd.expression : WANTvalue;

        if (e.type == Type.tsize_t)
        {
            ASTCodegen.Expression ex = (e.op == EXP.cast_ ? (cast(ASTCodegen.CastExp) e).e1 : e);
            ex = ex.optimize(WANTvalue);
            const ulong uval = ex.op == EXP.int64 ? ex.toInteger() : cast(ulong)-1;
            if (cast(long) uval >= 0)
            {
                ulong sizemax = void;
                if (target.ptrsize == 8)
                    sizemax = 0xFFFFFFFFFFFFFFFFUL;
                else if (target.ptrsize == 4)
                    sizemax = 0xFFFFFFFFU;
                else if (target.ptrsize == 2)
                    sizemax = 0xFFFFU;
                else
                    assert(0);
                if (uval <= sizemax && uval <= 0x7FFFFFFFFFFFFFFFUL)
                {
                    buf.put(format("%lu", uval));
                    return;
                }
            }
        }
        writeExprWithPrecedence(e, PREC.assign);
    }

    void writeFuncIdentWithPrefix(TypeFunction t, const Identifier ident, ASTCodegen
            .TemplateDeclaration td)
    {
        if (t.inuse)
        {
            t.inuse = 2; // flag error to caller
            return;
        }
        t.inuse++;

        /* Use 'storage class' (prefix) style for attributes
     */
        if (t.mod)
        {
            buf.put(MODtoString(t.mod));
            buf.put(' ');
        }

        void ignoreReturn(string str)
        {
            import dmd.id : Id;

            if (str != "return")
            {
                // don't write 'ref' for ctors
                if ((ident == Id.ctor) && str == "ref")
                    return;
                buf.put(str);
                buf.put(' ');
            }
        }

        t.attributesApply(&ignoreReturn);

        if (t.linkage > LINK.d)
        {
            writeLinkage(t.linkage);
            buf.put(' ');
        }
        if (ident && ident.toHChars2() != ident.toChars())
        {
            // Don't print return type for ctor, dtor, unittest, etc
        }
        else if (t.next)
        {
            writeTypeWithIdent(t.next, null);
            if (ident)
                buf.put(' ');
        }
        if (ident)
            buf.put(ident.toString());
        if (td)
        {
            buf.put('(');
            foreach (i, p; *td.origParameters)
            {
                if (i)
                    buf.put(", ");
                p.accept(this);
            }
            buf.put(')');
        }
        writeParamList(t.parameterList);
        if (t.isreturn)
        {
            buf.put(" return");
        }
        t.inuse--;
    }

    extern (D) void writeFuncIdentWithPostfix(TypeFunction t, const char[] ident, bool isStatic)
    {
        if (t.inuse)
        {
            t.inuse = 2; // flag error to caller
            return;
        }
        t.inuse++;
        if (t.linkage > LINK.d)
        {
            writeLinkage(t.linkage);
            buf.put(' ');
        }
        if (t.linkage == LINK.objc && isStatic)
            buf.put("static ");
        if (t.next)
        {
            writeTypeWithIdent(t.next, null);
            if (ident)
                buf.put(' ');
        }
        if (ident)
            buf.put(ident);
        writeParamList(t.parameterList);
        /* Use postfix style for attributes */
        if (t.mod)
        {
            buf.put(' ');
            buf.put(MODtoString(t.mod));
        }

        void dg(string str)
        {
            buf.put(' ');
            buf.put(str);
        }

        t.attributesApply(&dg);

        t.inuse--;
    }

    void writeType(Type t)
    {
        void visitType(Type _)
        {
            assert(0);
        }

        void visitError(TypeError _)
        {
            buf.put("_error_");
        }

        void visitBasic(TypeBasic t)
        {
            buf.put(t.toString());
        }

        void visitTraits(TypeTraits t)
        {
            writeExpr(t.exp);
        }

        void visitVector(TypeVector t)
        {
            buf.put("__vector(");
            writeWithMask(t.basetype, t.mod);
            buf.put(")");
        }

        void visitSArray(TypeSArray t)
        {
            writeWithMask(t.next, t.mod);
            buf.put('[');
            writeSize(t.dim);
            buf.put(']');
        }

        void visitDArray(TypeDArray t)
        {
            Type ut = t.castMod(0);
            if (declstring)
                goto L1;
            if (ut.equals(Type.tstring))
                buf.put("string");
            else if (ut.equals(Type.twstring))
                buf.put("wstring");
            else if (ut.equals(Type.tdstring))
                buf.put("dstring");
            else
            {
            L1:
                writeWithMask(t.next, t.mod);
                buf.put("[]");
            }
        }

        void visitAArray(TypeAArray t)
        {
            writeWithMask(t.next, t.mod);
            buf.put('[');
            writeWithMask(t.index, 0);
            buf.put(']');
        }

        void visitPointer(TypePointer t)
        {
            if (t.next.ty == Tfunction)
                writeFuncIdentWithPostfix(cast(TypeFunction) t.next, "function", false);
            else
            {
                writeWithMask(t.next, t.mod);
                buf.put('*');
            }
        }

        void visitReference(TypeReference t)
        {
            writeWithMask(t.next, t.mod);
            buf.put('&');
        }

        void visitFunction(TypeFunction t)
        {
            writeFuncIdentWithPostfix(t, null, false);
        }

        void visitDelegate(TypeDelegate t)
        {
            writeFuncIdentWithPostfix(cast(TypeFunction) t.next, "delegate", false);
        }

        void visitTypeQualifiedHelper(TypeQualified t)
        {
            foreach (id; t.idents)
            {
                switch (id.dyncast()) with (DYNCAST)
                {
                case dsymbol:
                    buf.put('.');
                    ASTCodegen.TemplateInstance ti = cast(ASTCodegen.TemplateInstance) id;
                    ti.accept(this);
                    break;
                case expression:
                    buf.put('[');
                    writeExpr(cast(ASTCodegen.Expression) id);
                    buf.put(']');
                    break;
                case type:
                    buf.put('[');
                    writeType(cast(Type) id);
                    buf.put(']');
                    break;
                default:
                    buf.put('.');
                    buf.put(id.toString());
                }
            }
        }

        void visitIdentifier(TypeIdentifier t)
        {
            buf.put(t.ident.toString());
            visitTypeQualifiedHelper(t);
        }

        void visitInstance(TypeInstance t)
        {
            t.tempinst.accept(this);
            visitTypeQualifiedHelper(t);
        }

        void visitTypeof(TypeTypeof t)
        {
            buf.put("typeof(");
            writeExpr(t.exp);
            buf.put(')');
            visitTypeQualifiedHelper(t);
        }

        void visitReturn(TypeReturn t)
        {
            buf.put("typeof(return)");
            visitTypeQualifiedHelper(t);
        }

        void visitEnum(TypeEnum t)
        {
            buf.put(t.sym.toString());
        }

        void visitStruct(TypeStruct t)
        {
            // https://issues.dlang.org/show_bug.cgi?id=13776
            // Don't use ti.toAlias() to avoid forward reference error
            // while printing messages.
            ASTCodegen.TemplateInstance ti = t.sym.parent ? t.sym.parent.isTemplateInstance() : null;
            if (ti && ti.aliasdecl == t.sym)
                buf.put(ti.toString());
            else
                buf.put(t.sym.toString());
        }

        void visitClass(TypeClass t)
        {
            // https://issues.dlang.org/show_bug.cgi?id=13776
            // Don't use ti.toAlias() to avoid forward reference error
            // while printing messages.
            ASTCodegen.TemplateInstance ti = t.sym.parent ? t.sym.parent.isTemplateInstance() : null;
            if (ti && ti.aliasdecl == t.sym)
                buf.put(ti.toString());
            else
                buf.put(t.sym.toString());
        }

        void visitTag(TypeTag t)
        {
            if (t.mod & MODFlags.const_)
                buf.put("const ");
            buf.put(Token.toString(t.tok));
            buf.put(' ');
            if (t.id)
                buf.put(t.id.toString());
            if (t.tok == TOK.enum_ && t.base && t.base.ty != TY.Tint32)
            {
                buf.put(" : ");
                writeWithMask(t.base, t.mod);
            }
        }

        void visitTuple(TypeTuple t)
        {
            writeParamList(ParameterList(t.arguments, VarArg.none));
        }

        void visitSlice(TypeSlice t)
        {
            writeWithMask(t.next, t.mod);
            buf.put('[');
            writeSize(t.lwr);
            buf.put(" .. ");
            writeSize(t.upr);
            buf.put(']');
        }

        void visitNull(TypeNull _)
        {
            buf.put("typeof(null)");
        }

        void visitMixin(TypeMixin t)
        {
            buf.put("mixin(");
            writeArgs(t.exps);
            buf.put(')');
        }

        void visitNoreturn(TypeNoreturn _)
        {
            buf.put("noreturn");
        }

        switch (t.ty)
        {
        default:
            return t.isTypeBasic() ?
                visitBasic(cast(TypeBasic) t) : visitType(t);

        case Terror:
            return visitError(cast(TypeError) t);
        case Ttraits:
            return visitTraits(cast(TypeTraits) t);
        case Tvector:
            return visitVector(cast(TypeVector) t);
        case Tsarray:
            return visitSArray(cast(TypeSArray) t);
        case Tarray:
            return visitDArray(cast(TypeDArray) t);
        case Taarray:
            return visitAArray(cast(TypeAArray) t);
        case Tpointer:
            return visitPointer(cast(TypePointer) t);
        case Treference:
            return visitReference(cast(TypeReference) t);
        case Tfunction:
            return visitFunction(cast(TypeFunction) t);
        case Tdelegate:
            return visitDelegate(cast(TypeDelegate) t);
        case Tident:
            return visitIdentifier(cast(TypeIdentifier) t);
        case Tinstance:
            return visitInstance(cast(TypeInstance) t);
        case Ttypeof:
            return visitTypeof(cast(TypeTypeof) t);
        case Treturn:
            return visitReturn(cast(TypeReturn) t);
        case Tenum:
            return visitEnum(cast(TypeEnum) t);
        case Tstruct:
            return visitStruct(cast(TypeStruct) t);
        case Tclass:
            return visitClass(cast(TypeClass) t);
        case Ttuple:
            return visitTuple(cast(TypeTuple) t);
        case Tslice:
            return visitSlice(cast(TypeSlice) t);
        case Tnull:
            return visitNull(cast(TypeNull) t);
        case Tmixin:
            return visitMixin(cast(TypeMixin) t);
        case Tnoreturn:
            return visitNoreturn(cast(TypeNoreturn) t);
        case Ttag:
            return visitTag(cast(TypeTag) t);
        }
    }

    void writeLinkage(LINK linkage)
    {
        const s = linkageToString(linkage);
        if (s.length)
        {
            buf.put("extern (");
            buf.put(s);
            buf.put(')');
        }
    }

    void writeParam(Parameter p)
    {
        if (p.userAttribDecl)
        {
            buf.put('@');

            bool isAnonymous = p.userAttribDecl.atts.length > 0 && !(*p.userAttribDecl.atts)[0].isCallExp();
            if (isAnonymous)
                buf.put('(');

            writeArgs(p.userAttribDecl.atts);

            if (isAnonymous)
                buf.put(')');
            buf.put(' ');
        }
        if (p.storageClass & STC.auto_)
            buf.put("auto ");

        StorageClass stc = p.storageClass;
        if (p.storageClass & STC.in_)
        {
            buf.put("in ");
        }
        else if (p.storageClass & STC.lazy_)
            buf.put("lazy ");
        else if (p.storageClass & STC.alias_)
            buf.put("alias ");

        if (p.type && p.type.mod & MODFlags.shared_)
            stc &= ~STC.shared_;

        writeStc(stc & (
                STC.const_ | STC.immutable_ | STC.wild | STC.shared_ |
                STC.return_ | STC.returninferred | STC.scope_ | STC.scopeinferred | STC.out_ | STC.ref_ | STC
                .returnScope));

        import core.stdc.string : strncmp;

        if (p.storageClass & STC.alias_)
        {
            if (p.ident)
                buf.put(p.ident.toString());
        }
        else if (p.type.ty == Tident &&
            (cast(TypeIdentifier) p.type)
                .ident.toString().length > 3 &&
            strncmp((cast(TypeIdentifier) p.type)
                .ident.toChars(), "__T", 3) == 0)
        {
            // print parameter name, instead of undetermined type parameter
            buf.put(p.ident.toString());
        }
        else
        {
            writeTypeWithIdent(p.type, p.ident, (stc & STC.in_) ? MODFlags.const_ : 0);
        }

        if (p.defaultArg)
        {
            buf.put(" = ");
            writeExprWithPrecedence(p.defaultArg, PREC.assign);
        }
    }

    void writeParamList(ParameterList pl)
    {
        buf.put('(');
        foreach (i; 0 .. pl.length)
        {
            if (i)
                buf.put(", ");
            writeParam(pl[i]);
        }
        final switch (pl.varargs)
        {
        case VarArg.none:
            break;

        case VarArg.variadic:
            if (pl.length)
                buf.put(", ");

            writeStc(pl.stc);
            goto case VarArg.typesafe;

        case VarArg.typesafe:
            buf.put("...");
            break;

        case VarArg.KRvariadic:
            break;
        }
        buf.put(')');
    }

    void writeVisibility(ASTCodegen.Visibility vis)
    {
        buf.put(visibilityToString(vis.kind));
        if (vis.kind == ASTCodegen.Visibility.Kind.package_ && vis.pkg)
        {
            buf.put('(');
            buf.put(vis.pkg.toPrettyChars(true).toDString());
            buf.put(')');
        }
    }

    extern (D) string visibilityToString(ASTCodegen.Visibility.Kind kind) nothrow pure @safe
    {
        with (ASTCodegen.Visibility.Kind)
        {
            immutable string[7] a = [
                none: "none",
                private_: "private",
                package_: "package",
                protected_: "protected",
                public_: "public",
                export_: "export"
            ];
            return a[kind];
        }
    }

    void writeTiArgs(ASTCodegen.TemplateInstance ti)
    {
        buf.put('!');
        if (ti.nest)
        {
            buf.put("(...)");
            return;
        }
        if (!ti.tiargs)
        {
            buf.put("()");
            return;
        }
        if (ti.tiargs.length == 1)
        {
            import dmd.dtemplate;

            RootObject oarg = (*ti.tiargs)[0];
            if (Type t = isType(oarg))
            {
                if ((t.equals(Type.tstring) || t.equals(Type.twstring) || t.equals(Type.tdstring) || t.mod == 0) && (
                        (t.isTypeBasic() || t.ty == Tident) && (cast(TypeIdentifier) t).idents.length == 0))
                {
                    buf.put(t.toString());
                    return;
                }
            }
            else if (ASTCodegen.Expression e = isExpression(oarg))
            {
                if (e.op == EXP.int64 || e.op == EXP.float64 || e.op == EXP.null_ || e.op == EXP.string_ || e.op == EXP
                    .this_)
                {
                    buf.put(e.toString());
                    return;
                }
            }
        }
        buf.put('(');
        ti.nestUp();
        foreach (i, arg; *ti.tiargs)
        {
            if (i)
                buf.put(", ");
            writeObject(arg);
        }
        ti.nestDown();
        buf.put(')');
    }
    /*******************************************
    * Visitors for AST nodes
    */
    void visitDsymbol(ASTCodegen.Dsymbol s)
    {
        /* writeln("visiting dsymbol"); */
        buf.put(s.toString());
    }

    void visitStaticAssert(ASTCodegen.StaticAssert s)
    {
        buf.put(s.kind().toDString());
        buf.put('(');
        writeExpr(s.exp);
        if (s.msgs)
        {
            foreach (m; (*s.msgs)[])
            {
                buf.put(", ");
                writeExpr(m);
            }
        }
        buf.put(");");
        newline();
    }

    void visitDebugSymbol(ASTCodegen.DebugSymbol s)
    {
        buf.put("debug = ");
        if (s.ident)
            buf.put(s.ident.toString());
        else
            buf.put(format("%d", s.level));
        buf.put(';');
        newline();
    }

    void visitVersionSymbol(ASTCodegen.VersionSymbol s)
    {
        buf.put("version = ");
        if (s.ident)
            buf.put(s.ident.toString());
        else
            buf.put(format("%d", s.level));
        buf.put(';');
        newline();
    }

    void visitEnumMember(ASTCodegen.EnumMember em)
    {
        if (em.type)
            writeTypeWithIdent(em.type, em.ident);
        else
            buf.put(em.ident.toString());
        if (em.value)
        {
            buf.put(" = ");
            writeExpr(em.value);
        }
    }

    void visitImport(ASTCodegen.Import imp)
    {
        if (imp.isstatic)
            buf.put("static ");
        buf.put("import ");
        if (imp.aliasId)
        {
            buf.put(imp.aliasId.toString());
            buf.put(" = ");
        }
        foreach (const pid; imp.packages)
        {
            buf.put(pid.toString());
            buf.put(".");
        }
        buf.put(imp.id.toString());
        if (imp.names.length)
        {
            buf.put(" : ");
            foreach (const i, const name; imp.names)
            {
                if (i)
                    buf.put(", ");
                const _alias = imp.aliases[i];
                if (_alias)
                {
                    buf.put(_alias.toString());
                    buf.put(" = ");
                    buf.put(name.toString());
                }
                else
                    buf.put(name.toString());
            }
        }

        buf.put(';');
        newline();
    }

    void visitAliasThis(ASTCodegen.AliasThis d)
    {
        buf.put("alias ");
        buf.put(d.ident.toString());
        buf.put(" this;");
        newline();
    }

    override void visitAttribDeclaration(ASTCodegen.AttribDeclaration d)
    {
        if (auto stcd = d.isStorageClassDeclaration)
        {
            writeStc(stcd.stc);
        }

        if (!d.decl)
        {
            buf.put(';');
            newline();
            return;
        }
        if (d.decl.length == 0)
        {
            buf.put("{}");
        }
        else if (d.decl.length == 1)
        {
            (*d.decl)[0].accept(this);
            return;
        }
        else
        {
            newline();
            buf.put('{');
            newline();
            depth++;
            foreach (de; *d.decl)
                de.accept(this);
            depth--;
            buf.put('}');
        }
        newline();
    }

    void visitStorageClassDeclaration(ASTCodegen.StorageClassDeclaration d)
    {
        visitAttribDeclaration(d);
    }

    void visitDeprecatedDeclaration(ASTCodegen.DeprecatedDeclaration d)
    {
        buf.put("deprecated(");
        writeExpr(d.msg);
        buf.put(") ");
        visitAttribDeclaration(d);
    }

    void visitLinkDeclaration(ASTCodegen.LinkDeclaration d)
    {
        buf.put("extern (");
        buf.put(linkageToString(d.linkage));
        buf.put(") ");
        visitAttribDeclaration(d);
    }

    void visitCPPMangleDeclaration(ASTCodegen.CPPMangleDeclaration d)
    {
        string s;
        final switch (d.cppmangle)
        {
        case CPPMANGLE.asClass:
            s = "class";
            break;
        case CPPMANGLE.asStruct:
            s = "struct";
            break;
        case CPPMANGLE.def:
            break;
        }
        buf.put("extern (C++, ");
        buf.put(s);
        buf.put(") ");
        visitAttribDeclaration(d);
    }

    void visitVisibilityDeclaration(ASTCodegen.VisibilityDeclaration d)
    {
        writeVisibility(d.visibility);
        ASTCodegen.AttribDeclaration ad = cast(ASTCodegen.AttribDeclaration) d;
        if (ad.decl.length <= 1)
            buf.put(' ');
        if (ad.decl.length == 1 && (*ad.decl)[0].isVisibilityDeclaration)
            visitAttribDeclaration((*ad.decl)[0].isVisibilityDeclaration);
        else
            visitAttribDeclaration(d);
    }

    void visitAlignDeclaration(ASTCodegen.AlignDeclaration d)
    {
        if (d.exps)
        {
            foreach (i, exp; (*d.exps)[])
            {
                if (i)
                    buf.put(' ');
                buf.put(format("align (%s)", exp.toString()));
            }
            if (d.decl && d.decl.length < 2)
                buf.put(' ');
        }
        else
            buf.put("align ");

        visitAttribDeclaration(d.isAttribDeclaration());
    }

    void visitAnonDeclaration(ASTCodegen.AnonDeclaration d)
    {
        buf.put(d.isunion ? "union" : "struct");
        newline();
        buf.put("{");
        newline();
        depth++;
        if (d.decl)
        {
            foreach (de; *d.decl)
                de.accept(this);
        }
        depth--;
        buf.put("}");
        newline();
    }

    void visitPragmaDeclaration(ASTCodegen.PragmaDeclaration d)
    {
        buf.put("pragma (");
        buf.put(d.ident.toString());
        if (d.args && d.args.length)
        {
            buf.put(", ");
            writeArgs(d.args);
        }

        buf.put(')');
        visitAttribDeclaration(d);
    }

    void visitConditionalDeclaration(ASTCodegen.ConditionalDeclaration d)
    {
        d.condition.accept(this);
        if (d.decl || d.elsedecl)
        {
            newline();
            buf.put('{');
            newline();
            depth++;
            if (d.decl)
            {
                foreach (de; *d.decl)
                    de.accept(this);
            }
            depth--;
            buf.put('}');
            if (d.elsedecl)
            {
                newline();
                buf.put("else");
                newline();
                buf.put('{');
                newline();
                depth++;
                foreach (de; *d.elsedecl)
                    de.accept(this);
                depth--;
                buf.put('}');
            }
        }
        else
            buf.put(':');
        newline();
    }

    void visitStaticForeachDeclaration(ASTCodegen.StaticForeachDeclaration s)
    {
        void foreachWithoutBody(ASTCodegen.ForeachStatement s)
        {
            buf.put(Token.toString(s.op));
            buf.put(" (");
            foreach (i, p; *s.parameters)
            {
                if (i)
                    buf.put(", ");
                writeStc(p.storageClass);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    buf.put(p.ident.toString());
            }
            buf.put("; ");
            writeExpr(s.aggr);
            buf.put(')');
            newline();
        }

        void foreachRangeWithoutBody(ASTCodegen.ForeachRangeStatement s)
        {
            /* s.op ( prm ; lwr .. upr )
             */
            buf.put(Token.toString(s.op));
            buf.put(" (");
            if (s.prm.type)
                writeTypeWithIdent(s.prm.type, s.prm.ident);
            else
                buf.put(s.prm.ident.toString());
            buf.put("; ");
            writeExpr(s.lwr);
            buf.put(" .. ");
            writeExpr(s.upr);
            buf.put(')');
            newline();
        }

        buf.put("static ");
        if (s.sfe.aggrfe)
        {
            foreachWithoutBody(s.sfe.aggrfe);
        }
        else
        {
            assert(s.sfe.rangefe);
            foreachRangeWithoutBody(s.sfe.rangefe);
        }
        buf.put('{');
        newline();
        depth++;
        visitAttribDeclaration(s);
        depth--;
        buf.put('}');
        newline();

    }

    void visitMixinDeclaration(ASTCodegen.MixinDeclaration d)
    {
        buf.put("mixin(");
        writeArgs(d.exps);
        buf.put(");");
        newline();
    }

    void visitUserAttributeDeclaration(ASTCodegen.UserAttributeDeclaration d)
    {
        buf.put("@(");
        writeArgs(d.atts);
        buf.put(')');
        visitAttribDeclaration(d);
    }

    void visitTemplateConstraint(ASTCodegen.Expression constraint)
    {
        if (!constraint)
            return;
        buf.put(" if (");
        writeExpr(constraint);
        buf.put(')');
    }

    override void visitBaseClasses(ASTCodegen.ClassDeclaration d)
    {
        if (!d || !d.baseclasses.length)
            return;
        if (!d.isAnonymous())
            buf.put(" : ");
        foreach (i, b; *d.baseclasses)
        {
            if (i)
                buf.put(", ");
            writeTypeWithIdent(b.type, null);
        }
    }

    override bool visitEponymousMember(ASTCodegen.TemplateDeclaration d)
    {
        if (!d.members || d.members.length != 1)
            return false;
        ASTCodegen.Dsymbol onemember = (*d.members)[0];
        if (onemember.ident != d.ident)
            return false;
        if (ASTCodegen.FuncDeclaration fd = onemember.isFuncDeclaration())
        {
            assert(fd.type);
            writeStc(fd.storage_class);
            writeFuncIdentWithPrefix(cast(TypeFunction) fd.type, d.ident, d);
            visitTemplateConstraint(d.constraint);
            writeFuncBody(fd);
            return true;
        }
        if (ASTCodegen.AggregateDeclaration ad = onemember.isAggregateDeclaration())
        {
            buf.put(ad.kind().toDString());
            buf.put(' ');
            buf.put(ad.ident.toString());
            buf.put('(');
            visitTemplateParameters(d.parameters);
            buf.put(')');
            visitTemplateConstraint(d.constraint);
            visitBaseClasses(ad.isClassDeclaration());
            if (ad.members)
            {
                newline();
                buf.put('{');
                newline();
                depth++;
                foreach (s; *ad.members)
                    s.accept(this);
                depth--;
                buf.put('}');
            }
            else
                buf.put(';');
            newline();
            return true;
        }
        if (ASTCodegen.VarDeclaration vd = onemember.isVarDeclaration())
        {
            if (d.constraint)
                return false;
            writeStc(vd.storage_class);
            if (vd.type)
                writeTypeWithIdent(vd.type, vd.ident);
            else
                buf.put(vd.ident.toString());
            buf.put('(');
            visitTemplateParameters(d.parameters);
            buf.put(')');
            if (vd._init)
            {
                buf.put(" = ");
                ExpInitializer ie = vd._init.isExpInitializer();
                if (ie && (ie.exp.op == EXP.construct || ie.exp.op == EXP.blit))
                    writeExpr((cast(ASTCodegen.AssignExp) ie.exp).e2);
                else
                    writeInitializer(vd._init);
            }
            buf.put(';');
            newline();
            return true;
        }
        return false;
    }

    void visitTemplateDeclaration(ASTCodegen.TemplateDeclaration d)
    {
        buf.put("template");
        buf.put(' ');
        buf.put(d.ident.toString());
        buf.put('(');
        visitTemplateParameters(d.parameters);
        buf.put(')');
        visitTemplateConstraint(d.constraint);
    }

    void visitTemplateInstance(ASTCodegen.TemplateInstance ti)
    {
        buf.put(ti.name.toString());
        writeTiArgs(ti);
    }

    void visitTemplateMixin(ASTCodegen.TemplateMixin tm)
    {
        buf.put("mixin ");
        writeTypeWithIdent(tm.tqual, null);
        writeTiArgs(tm);
        if (tm.ident && tm.ident.toString() != "__mixin")
        {
            buf.put(' ');
            buf.put(tm.ident.toString());
        }
        buf.put(';');
        newline();
    }

    void visitEnumDeclaration(ASTCodegen.EnumDeclaration d)
    {
        buf.put("enum ");
        if (d.ident)
        {
            buf.put(d.ident.toString());
        }
        if (d.memtype)
        {
            buf.put(" : ");
            writeTypeWithIdent(d.memtype, null);
        }
        if (!d.members)
        {
            buf.put(';');
            newline();
            return;
        }
        newline();
        buf.put('{');
        newline();
        depth++;
        foreach (em; *d.members)
        {
            if (!em)
                continue;
            em.accept(this);
            buf.put(',');
            newline();
        }
        depth--;
        buf.put('}');
        newline();
    }

    void visitNspace(ASTCodegen.Nspace d)
    {
        buf.put("extern (C++, ");
        buf.put(d.ident.toString());
        buf.put(')');
        newline();
        buf.put('{');
        newline();
        depth++;
        foreach (s; *d.members)
            s.accept(this);
        depth--;
        buf.put('}');
        newline();
    }

    void visitStructDeclaration(ASTCodegen.StructDeclaration d)
    {
        buf.put(d.kind().toDString());
        buf.put(' ');
        if (!d.isAnonymous())
            buf.put(d.toString());
        if (!d.members)
        {
            buf.put(';');
            newline();
            return;
        }
        newline();
        buf.put('{');
        newline();
        depth++;
        foreach (s; *d.members)
            s.accept(this);
        depth--;
        buf.put('}');
        newline();
    }

    void visitClassDeclaration(ASTCodegen.ClassDeclaration d)
    {
        if (!d.isAnonymous())
        {
            buf.put(d.kind().toDString());
            buf.put(' ');
            buf.put(d.ident.toString());
        }
        visitBaseClasses(d);
        if (d.members)
        {
            newline();
            buf.put('{');
            newline();
            depth++;
            foreach (s; *d.members)
                s.accept(this);
            depth--;
            buf.put('}');
        }
        else
            buf.put(';');
        newline();
    }

    void visitAliasDeclaration(ASTCodegen.AliasDeclaration d)
    {
        if (d.storage_class & STC.local)
            return;
        buf.put("alias ");
        if (d.aliassym)
        {
            buf.put(d.ident.toString());
            buf.put(" = ");
            writeStc(d.storage_class);
            /*
                https://issues.dlang.org/show_bug.cgi?id=23223
                https://issues.dlang.org/show_bug.cgi?id=23222
                This special case (initially just for modules) avoids some segfaults
                and nicer -vcg-ast output.
            */
            if (d.aliassym.isModule())
            {
                buf.put(d.aliassym.ident.toString());
            }
            else
            {
                d.aliassym.accept(this);
            }
        }
        else if (d.type.ty == Tfunction)
        {
            writeStc(d.storage_class);
            writeTypeWithIdent(d.type, d.ident);
        }
        else if (d.ident)
        {
            import dmd.id : Id;

            declstring = (d.ident == Id.string || d.ident == Id.wstring || d.ident == Id
                    .dstring);
            buf.put(d.ident.toString());
            buf.put(" = ");
            writeStc(d.storage_class);
            writeTypeWithIdent(d.type, null);
            declstring = false;
        }
        buf.put(';');
        newline();
    }

    void visitAliasAssign(ASTCodegen.AliasAssign d)
    {
        buf.put(d.ident.toString());
        buf.put(" = ");
        if (d.aliassym)
            d.aliassym.accept(this);
        else // d.type
            writeTypeWithIdent(d.type, null);
        buf.put(';');
        newline();
    }

    void visitVarDeclaration(ASTCodegen.VarDeclaration d)
    {
        if (d.storage_class & STC.local)
            return;
        writeVarDecl(d, false);
        buf.put(';');
        newline();
    }

    void visitFuncDeclaration(ASTCodegen.FuncDeclaration f)
    {
        newline();
        writeStc(f.storage_class);
        auto tf = cast(TypeFunction) f.type;
        writeTypeWithIdent(tf, f.ident);
        writeFuncBody(f);
        /* writeln("Wrote body"); */
    }

    void visitFuncLiteralDeclaration(ASTCodegen.FuncLiteralDeclaration f)
    {
        if (f.type.ty == Terror)
        {
            buf.put("__error");
            return;
        }
        if (f.tok != TOK.reserved)
        {
            buf.put(f.kind().toDString());
            buf.put(' ');
        }
        TypeFunction tf = cast(TypeFunction) f.type;

        if (!f.inferRetType && tf.next)
            writeTypeWithIdent(tf.next, null);
        writeParamList(tf.parameterList);

        // https://issues.dlang.org/show_bug.cgi?id=20074
        void printAttribute(string str)
        {
            buf.put(' ');
            buf.put(str);
        }

        tf.attributesApply(&printAttribute);

        ASTCodegen.CompoundStatement cs = f.fbody.isCompoundStatement();
        ASTCodegen.Statement s1;
        s1 = !cs ? f.fbody : null;
        ASTCodegen.ReturnStatement rs = s1 ? s1.endsWithReturnStatement() : null;
        if (rs && rs.exp)
        {
            buf.put(" => ");
            writeExpr(rs.exp);
        }
        else
        {
            writeFuncBody(f);
        }
    }

    void visitPostBlitDeclaration(ASTCodegen.PostBlitDeclaration d)
    {
        writeStc(d.storage_class);
        buf.put("this(this)");
        writeFuncBody(d);
    }

    void visitDtorDeclaration(ASTCodegen.DtorDeclaration d)
    {
        writeStc(d.storage_class);
        buf.put("~this()");
        writeFuncBody(d);
    }

    void visitStaticCtorDeclaration(ASTCodegen.StaticCtorDeclaration d)
    {
        writeStc(d.storage_class & ~STC.static_);
        if (d.isSharedStaticCtorDeclaration())
            buf.put("shared ");
        buf.put("static this()");
        writeFuncBody(d);
    }

    void visitStaticDtorDeclaration(ASTCodegen.StaticDtorDeclaration d)
    {
        writeStc(d.storage_class & ~STC.static_);
        if (d.isSharedStaticDtorDeclaration())
            buf.put("shared ");
        buf.put("static ~this()");
        writeFuncBody(d);
    }

    void visitInvariantDeclaration(ASTCodegen.InvariantDeclaration d)
    {
        writeStc(d.storage_class);
        buf.put("invariant");
        if (auto es = d.fbody.isExpStatement())
        {
            assert(es.exp && es.exp.op == EXP.assert_);
            buf.put(" (");
            writeExpr((cast(ASTCodegen.AssertExp) es.exp).e1);
            buf.put(");");
            newline();
        }
        else
        {
            writeFuncBody(d);
        }
    }

    void visitUnitTestDeclaration(ASTCodegen.UnitTestDeclaration d)
    {
        writeStc(d.storage_class);
        buf.put("unittest");
        writeFuncBody(d);
    }

    void visitBitFieldDeclaration(ASTCodegen.BitFieldDeclaration d)
    {
        writeStc(d.storage_class);
        Identifier id = d.isAnonymous() ? null : d.ident;
        writeTypeWithIdent(d.type, id);
        buf.put(" : ");
        writeExpr(d.width);
        buf.put(';');
        newline();
    }

    void visitNewDeclaration(ASTCodegen.NewDeclaration d)
    {
        writeStc(d.storage_class & ~STC.static_);
        buf.put("new();");
    }

    void visitModule(ASTCodegen.Module m)
    {
        if (m.md)
        {
            if (m.userAttribDecl)
            {
                buf.put("@(");
                writeArgs(m.userAttribDecl.atts);
                buf.put(')');
                newline();
            }
            if (m.md.isdeprecated)
            {
                if (m.md.msg)
                {
                    buf.put("deprecated(");
                    writeExpr(m.md.msg);
                    buf.put(") ");
                }
                else
                    buf.put("deprecated ");
            }
            buf.put("module ");
            buf.put(m.md.toString());
            buf.put(';');
            newline();
        }

        foreach (s; *m.members)
        {
            s.accept(this);
        }
    }

    void visitDebugCondition(ASTCodegen.DebugCondition c)
    {
        buf.put("debug (");
        if (c.ident)
            buf.put(c.ident.toString());
        else
            buf.put(format("%d", c.level));
        buf.put(')');
    }

    void visitVersionCondition(ASTCodegen.VersionCondition c)
    {
        buf.put("version (");
        if (c.ident)
            buf.put(c.ident.toString());
        else
            buf.put(format("%d", c.level));
        buf.put(')');
    }

    void visitStaticIfCondition(ASTCodegen.StaticIfCondition c)
    {
        buf.put("static if (");
        writeExpr(c.exp);
        buf.put(')');
    }

    void visitTemplateTypeParameter(ASTCodegen.TemplateTypeParameter tp)
    {
        buf.put(tp.ident.toString());
        if (tp.specType)
        {
            buf.put(" : ");
            writeTypeWithIdent(tp.specType, null);
        }
        if (tp.defaultType)
        {
            buf.put(" = ");
            writeTypeWithIdent(tp.defaultType, null);
        }
    }

    void visitTemplateThisParameter(ASTCodegen.TemplateThisParameter tp)
    {
        buf.put("this ");
        visit(cast(ASTCodegen.TemplateTypeParameter) tp);
    }

    void visitTemplateAliasParameter(ASTCodegen.TemplateAliasParameter tp)
    {
        buf.put("alias ");
        if (tp.specType)
            writeTypeWithIdent(tp.specType, tp.ident);
        else
            buf.put(tp.ident.toString());
        if (tp.specAlias)
        {
            buf.put(" : ");
            writeObject(tp.specAlias);
        }
        if (tp.defaultAlias)
        {
            buf.put(" = ");
            writeObject(tp.defaultAlias);
        }
    }

    void visitTemplateValueParameter(ASTCodegen.TemplateValueParameter tp)
    {
        writeTypeWithIdent(tp.valType, tp.ident);
        if (tp.specValue)
        {
            buf.put(" : ");
            writeExpr(tp.specValue);
        }
        if (tp.defaultValue)
        {
            buf.put(" = ");
            writeExpr(tp.defaultValue);
        }
    }

    void visitTemplateTupleParameter(ASTCodegen.TemplateTupleParameter tp)
    {
        buf.put(tp.ident.toString());
        buf.put("...");
    }

override:
    // dfmt off
    void visit(ASTCodegen.Dsymbol s)                  { visitDsymbol(s); }
    void visit(ASTCodegen.StaticAssert s)             { visitStaticAssert(s); }
    void visit(ASTCodegen.DebugSymbol s)              { visitDebugSymbol(s); }
    void visit(ASTCodegen.VersionSymbol s)            { visitVersionSymbol(s); }
    void visit(ASTCodegen.EnumMember em)              { visitEnumMember(em); }
    void visit(ASTCodegen.Import imp)                 { visitImport(imp); }
    void visit(ASTCodegen.AliasThis d)                { visitAliasThis(d); }
    void visit(ASTCodegen.AttribDeclaration d)        { visitAttribDeclaration(d); }
    void visit(ASTCodegen.StorageClassDeclaration d)  { visitStorageClassDeclaration(d); }
    void visit(ASTCodegen.DeprecatedDeclaration d)    { visitDeprecatedDeclaration(d); }
    void visit(ASTCodegen.LinkDeclaration d)          { visitLinkDeclaration(d); }
    void visit(ASTCodegen.CPPMangleDeclaration d)     { visitCPPMangleDeclaration(d); }
    void visit(ASTCodegen.VisibilityDeclaration d)    { visitVisibilityDeclaration(d); }
    void visit(ASTCodegen.AlignDeclaration d)         { visitAlignDeclaration(d); }
    void visit(ASTCodegen.AnonDeclaration d)          { visitAnonDeclaration(d); }
    void visit(ASTCodegen.PragmaDeclaration d)        { visitPragmaDeclaration(d); }
    void visit(ASTCodegen.ConditionalDeclaration d)   { visitConditionalDeclaration(d); }
    void visit(ASTCodegen.StaticForeachDeclaration s) { visitStaticForeachDeclaration(s); }
    void visit(ASTCodegen.MixinDeclaration d)         { visitMixinDeclaration(d); }
    void visit(ASTCodegen.UserAttributeDeclaration d) { visitUserAttributeDeclaration(d); }
    void visit(ASTCodegen.TemplateDeclaration d)      { visitTemplateDeclaration(d); }
    void visit(ASTCodegen.TemplateInstance ti)        { visitTemplateInstance(ti); }
    void visit(ASTCodegen.TemplateMixin tm)           { visitTemplateMixin(tm); }
    void visit(ASTCodegen.EnumDeclaration d)          { visitEnumDeclaration(d); }
    void visit(ASTCodegen.Nspace d)                   { visitNspace(d); }
    void visit(ASTCodegen.StructDeclaration d)        { visitStructDeclaration(d); }
    void visit(ASTCodegen.ClassDeclaration d)         { visitClassDeclaration(d); }
    void visit(ASTCodegen.AliasDeclaration d)         { visitAliasDeclaration(d); }
    void visit(ASTCodegen.AliasAssign d)              { visitAliasAssign(d); }
    void visit(ASTCodegen.VarDeclaration d)           { visitVarDeclaration(d); }
    void visit(ASTCodegen.FuncDeclaration f)          { visitFuncDeclaration(f); }
    void visit(ASTCodegen.FuncLiteralDeclaration f)   { visitFuncLiteralDeclaration(f); }
    void visit(ASTCodegen.PostBlitDeclaration d)      { visitPostBlitDeclaration(d); }
    void visit(ASTCodegen.DtorDeclaration d)          { visitDtorDeclaration(d); }
    void visit(ASTCodegen.StaticCtorDeclaration d)    { visitStaticCtorDeclaration(d); }
    void visit(ASTCodegen.StaticDtorDeclaration d)    { visitStaticDtorDeclaration(d); }
    void visit(ASTCodegen.InvariantDeclaration d)     { visitInvariantDeclaration(d); }
    void visit(ASTCodegen.UnitTestDeclaration d)      { visitUnitTestDeclaration(d); }
    void visit(ASTCodegen.BitFieldDeclaration d)      { visitBitFieldDeclaration(d); }
    void visit(ASTCodegen.NewDeclaration d)           { visitNewDeclaration(d); }
    void visit(ASTCodegen.Module m)                   { visitModule(m); }
    void visit(ASTCodegen.DebugCondition m)           { visitDebugCondition(m); }
    void visit(ASTCodegen.VersionCondition m)         { visitVersionCondition(m); }
    void visit(ASTCodegen.StaticIfCondition m)        { visitStaticIfCondition(m); }
    void visit(ASTCodegen.TemplateTypeParameter m)    { visitTemplateTypeParameter(m); }
    void visit(ASTCodegen.TemplateThisParameter m)    { visitTemplateThisParameter(m); }
    void visit(ASTCodegen.TemplateAliasParameter m)   { visitTemplateAliasParameter(m); }
    void visit(ASTCodegen.TemplateValueParameter m)   { visitTemplateValueParameter(m); }
    void visit(ASTCodegen.TemplateTupleParameter m)   { visitTemplateTupleParameter(m); }
    // dfmt on
}
