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
    uint depth; // the current indentation level
    uint length; // the length of the current line of code
    bool declString; // set while declaring alias for string,wstring or dstring
    bool isNewline; // used to indent before writing the line
    bool insideCase; // true if the node is a child of a CaseStatement
    bool insideIfOrDo; // true if the node is a child of an IfStatement or DoStatement

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
        if (!depth)
            return;
        auto indent = config.indent_style == IndentStyle.space ? ' '.repeat()
            .take(depth * 4) : '\t'.repeat().take(depth);
        buf.put(indent.array);
        length += indent.length;
    }

    void newline()
    {
        buf.put(eol);
        length = 0;
        // Indicate that the next write should be indented
        isNewline = true;
    }

    void conditionalNewline(T)(T data)
    {
        // If the current length is crosses the soft limit OR
        // if the current length + data length crosses the hard limit,
        // insert a newline.
        if (length > config.dfmt_soft_max_line_length
                || (length + data.length) > config.max_line_length)
            newline();
    }

    void write(T)(T data) if (is(T : char) || is(T : dchar))
    {
        if (isNewline)
        {
            indent();
            isNewline = false;
        }
        buf.put(data);
        length += 1;
    }

    extern (D) void write(T)(T data) if (!(is(T : char) || is(T : dchar)))
    {
        if (isNewline)
        {
            indent();
            isNewline = false;
        }
        buf.put(data);
        length += data.length;
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
            write(rrs);
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
                write(' ');
            writeSpace = true;
            write(s);
        }

        if (writeSpace)
            write(' ');

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
        write(buffer.array);

        if (type)
        {
            Type t = type.toBasetype();
            switch (t.ty)
            {
            case Tfloat32:
            case Timaginary32:
            case Tcomplex32:
                write('F');
                break;
            case Tfloat80:
            case Timaginary80:
            case Tcomplex80:
                write('L');
                break;
            default:
                break;
            }
            if (t.isimaginary())
                write('i');
        }
    }

    void writeExpr(ASTCodegen.Expression e)
    {
        import dmd.hdrgen : EXPtoString;

        void visit(ASTCodegen.Expression e)
        {
            write(EXPtoString(e.op));
        }

        void visitInteger(ASTCodegen.IntegerExp e)
        {
            import core.stdc.stdio : sprintf;

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
                                    write(format("%s.%s", sym.toString(), em.ident.toString()));
                                    return;
                                }
                            }
                        }

                        write(format("cast(%s)", te.sym.toString()));
                        t = te.sym.memtype;
                        goto L1;
                    }
                case Tchar:
                case Twchar:
                case Tdchar:
                    {
                        write(cast(dchar) v);
                        break;
                    }
                case Tint8:
                    write("cast(byte)");
                    goto L2;
                case Tint16:
                    write("cast(short)");
                    goto L2;
                case Tint32:
                L2:
                    write(format("%d", cast(int) v));
                    break;
                case Tuns8:
                    write("cast(ubyte)");
                    goto case Tuns32;
                case Tuns16:
                    write("cast(ushort)");
                    goto case Tuns32;
                case Tuns32:
                    write(format("%uu", cast(uint) v));
                    break;
                case Tint64:
                    if (v == long.min)
                    {
                        // https://issues.dlang.org/show_bug.cgi?id=23173
                        // This is a special case because - is not part of the
                        // integer literal and 9223372036854775808L overflows a long
                        write("cast(long)-9223372036854775808");
                    }
                    else
                    {
                        write(format("%uL", v));
                    }
                    break;
                case Tuns64:
                    write(format("%uLU", v));
                    break;
                case Tbool:
                    write(v ? "true" : "false");
                    break;
                case Tpointer:
                    write("cast(");
                    write(t.toString());
                    write(')');
                    if (target.ptrsize == 8)
                        goto case Tuns64;
                    else if (target.ptrsize == 4 ||
                        target.ptrsize == 2)
                        goto case Tuns32;
                    else
                        assert(0);

                case Tvoid:
                    write("cast(void)0");
                    break;
                default:
                    break;
                }
            }
            else if (v & 0x8000000000000000L)
                write(format("0x%u", v));
            else
                write(format("%u", v));
        }

        void visitError(ASTCodegen.ErrorExp _)
        {
            write("__error");
        }

        void visitVoidInit(ASTCodegen.VoidInitExp _)
        {
            write("void");
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
            write('(');
            writeFloat(e.type, e.value.re);
            write('+');
            writeFloat(e.type, e.value.im);
            write("i)");
        }

        void visitIdentifier(ASTCodegen.IdentifierExp e)
        {
            write(e.ident.toString());
        }

        void visitDsymbol(ASTCodegen.DsymbolExp e)
        {
            write(e.s.toString());
        }

        void visitThis(ASTCodegen.ThisExp _)
        {
            write("this");
        }

        void visitSuper(ASTCodegen.SuperExp _)
        {
            write("super");
        }

        void visitNull(ASTCodegen.NullExp _)
        {
            write("null");
        }

        void visitString(ASTCodegen.StringExp e)
        {
            write('"');
            foreach (i; 0 .. e.len)
            {
                write(e.getCodeUnit(i));
            }
            write('"');
            if (e.postfix)
                write(e.postfix);
        }

        void visitArrayLiteral(ASTCodegen.ArrayLiteralExp e)
        {
            write('[');
            writeArgs(e.elements, e.basis);
            write(']');
        }

        void visitAssocArrayLiteral(ASTCodegen.AssocArrayLiteralExp e)
        {
            write('[');
            foreach (i, key; *e.keys)
            {
                if (i)
                    write(", ");
                writeExprWithPrecedence(key, PREC.assign);
                if (config.dfmt_space_before_aa_colon)
                    write(' ');
                write(": ");
                auto value = (*e.values)[i];
                writeExprWithPrecedence(value, PREC.assign);
            }
            write(']');
        }

        void visitStructLiteral(ASTCodegen.StructLiteralExp e)
        {
            import dmd.expression;

            write(e.sd.toString());
            write('(');
            // CTFE can generate struct literals that contain an AddrExp pointing
            // to themselves, need to avoid infinite recursion:
            // struct S { this(int){ this.s = &this; } S* s; }
            // const foo = new S(0);
            if (e.stageflags & stageToCBuffer)
                write("<recursion>");
            else
            {
                const old = e.stageflags;
                e.stageflags |= stageToCBuffer;
                writeArgs(e.elements);
                e.stageflags = old;
            }
            write(')');
        }

        void visitCompoundLiteral(ASTCodegen.CompoundLiteralExp e)
        {
            write('(');
            writeTypeWithIdent(e.type, null);
            write(')');
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
                write(e.sds.kind().toDString());
                write(' ');
                write(e.sds.toString());
            }
        }

        void visitTemplate(ASTCodegen.TemplateExp e)
        {
            write(e.td.toString());
        }

        void visitNew(ASTCodegen.NewExp e)
        {
            if (e.thisexp)
            {
                writeExprWithPrecedence(e.thisexp, PREC.primary);
                write('.');
            }
            write("new ");
            writeTypeWithIdent(e.newtype, null);
            if (e.arguments && e.arguments.length)
            {
                write('(');
                writeArgs(e.arguments, null, e.names);
                write(')');
            }
        }

        void visitNewAnonClass(ASTCodegen.NewAnonClassExp e)
        {
            if (e.thisexp)
            {
                writeExprWithPrecedence(e.thisexp, PREC.primary);
                write('.');
            }
            write("new");
            write(" class ");
            if (e.arguments && e.arguments.length)
            {
                write('(');
                writeArgs(e.arguments);
                write(')');
            }
            if (e.cd)
                e.cd.accept(this);
        }

        void visitSymOff(ASTCodegen.SymOffExp e)
        {
            if (e.offset)
                write(format("(& %s%+lld)", e.var.toString(), e.offset));
            else if (e.var.isTypeInfoDeclaration())
                write(e.var.toString());
            else
                write(format("& %s", e.var.toString()));
        }

        void visitVar(ASTCodegen.VarExp e)
        {
            write(e.var.toString());
        }

        void visitOver(ASTCodegen.OverExp e)
        {
            write(e.vars.ident.toString());
        }

        void visitTuple(ASTCodegen.TupleExp e)
        {
            if (e.e0)
            {
                write('(');
                writeExpr(e.e0);
                write(", AliasSeq!(");
                writeArgs(e.exps);
                write("))");
            }
            else
            {
                write("AliasSeq!(");
                writeArgs(e.exps);
                write(')');
            }
        }

        void visitFunc(ASTCodegen.FuncExp e)
        {
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
                    write('(');

                    writeVarDecl(var, false);

                    write(';');
                    write(')');
                }
                else
                    e.declaration.accept(this);
            }
        }

        void visitTypeid(ASTCodegen.TypeidExp e)
        {
            write("typeid(");
            writeObject(e.obj);
            write(')');
        }

        void visitTraits(ASTCodegen.TraitsExp e)
        {
            write("__traits(");
            if (e.ident)
                write(e.ident.toString());
            if (e.args)
            {
                foreach (arg; *e.args)
                {
                    write(", ");
                    writeObject(arg);
                }
            }
            write(')');
        }

        void visitHalt(ASTCodegen.HaltExp _)
        {
            write("halt");
        }

        void visitIs(ASTCodegen.IsExp e)
        {
            write("is(");
            writeTypeWithIdent(e.targ, e.id);
            if (e.tok2 != TOK.reserved)
            {
                write(format(" %s %s", Token.toChars(e.tok), Token.toChars(e.tok2)));
            }
            else if (e.tspec)
            {
                if (e.tok == TOK.colon)
                    write(" : ");
                else
                    write(" == ");
                writeTypeWithIdent(e.tspec, null);
            }
            if (e.parameters && e.parameters.length)
            {
                write(", ");
                visitTemplateParameters(e.parameters);
            }
            write(')');
        }

        void visitUna(ASTCodegen.UnaExp e)
        {
            write(EXPtoString(e.op));
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitLoweredAssignExp(ASTCodegen.LoweredAssignExp e)
        {
            visit(cast(ASTCodegen.BinExp) e);
        }

        void visitBin(ASTCodegen.BinExp e)
        {
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            write(' ');
            write(EXPtoString(e.op));
            write(' ');
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
            write("mixin(");
            writeArgs(e.exps);
            write(')');
        }

        void visitImport(ASTCodegen.ImportExp e)
        {
            write("import(");
            writeExprWithPrecedence(e.e1, PREC.assign);
            write(')');
        }

        void visitAssert(ASTCodegen.AssertExp e)
        {
            write("assert(");
            writeExprWithPrecedence(e.e1, PREC.assign);
            if (e.msg)
            {
                write(", ");
                writeExprWithPrecedence(e.msg, PREC.assign);
            }
            write(')');
        }

        void visitThrow(ASTCodegen.ThrowExp e)
        {
            write("throw ");
            writeExprWithPrecedence(e.e1, PREC.unary);
        }

        void visitDotId(ASTCodegen.DotIdExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            if (e.arrow)
                write("->");
            else
                write('.');
            write(e.ident.toString());
        }

        void visitDotTemplate(ASTCodegen.DotTemplateExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('.');
            write(e.td.toString());
        }

        void visitDotVar(ASTCodegen.DotVarExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('.');
            write(e.var.toString());
        }

        void visitDotTemplateInstance(ASTCodegen.DotTemplateInstanceExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('.');
            e.ti.accept(this);
        }

        void visitDelegate(ASTCodegen.DelegateExp e)
        {
            write('&');
            if (!e.func.isNested() || e.func.needThis())
            {
                writeExprWithPrecedence(e.e1, PREC.primary);
                write('.');
            }
            write(e.func.toString());
        }

        void visitDotType(ASTCodegen.DotTypeExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('.');
            write(e.sym.toString());
        }

        void visitCall(ASTCodegen.CallExp e)
        {
            if (e.e1.op == EXP.type)
            {
                /* Avoid parens around type to prevent forbidden cast syntax:
             *   (sometype)(arg1)
             * This is ok since types in constructor calls
             * can never depend on parens anyway
             */
                writeExpr(e.e1);
            }
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            write('(');
            writeArgs(e.arguments, null, e.names);
            write(')');
        }

        void visitPtr(ASTCodegen.PtrExp e)
        {
            write('*');
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitDelete(ASTCodegen.DeleteExp e)
        {
            write("delete ");
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitCast(ASTCodegen.CastExp e)
        {
            write("cast(");
            if (e.to)
                writeTypeWithIdent(e.to, null);
            else
            {
                write(MODtoString(e.mod));
            }
            write(')');
            if (config.dfmt_space_after_cast)
            {
                write(' ');
            }
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitVector(ASTCodegen.VectorExp e)
        {
            write("cast(");
            writeTypeWithIdent(e.to, null);
            write(')');
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitVectorArray(ASTCodegen.VectorArrayExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write(".array");
        }

        void visitSlice(ASTCodegen.SliceExp e)
        {
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            write('[');
            if (e.upr || e.lwr)
            {
                if (e.lwr)
                    writeSize(e.lwr);
                else
                    write('0');
                write("..");
                if (e.upr)
                    writeSize(e.upr);
                else
                    write('$');
            }
            write(']');
        }

        void visitArrayLength(ASTCodegen.ArrayLengthExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write(".length");
        }

        void visitInterval(ASTCodegen.IntervalExp e)
        {
            writeExprWithPrecedence(e.lwr, PREC.assign);
            write("..");
            writeExprWithPrecedence(e.upr, PREC.assign);
        }

        void visitDelegatePtr(ASTCodegen.DelegatePtrExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write(".ptr");
        }

        void visitDelegateFuncptr(ASTCodegen.DelegateFuncptrExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write(".funcptr");
        }

        void visitArray(ASTCodegen.ArrayExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('[');
            writeArgs(e.arguments);
            write(']');
        }

        void visitDot(ASTCodegen.DotExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('.');
            writeExprWithPrecedence(e.e2, PREC.primary);
        }

        void visitIndex(ASTCodegen.IndexExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write('[');
            writeSize(e.e2);
            write(']');
        }

        void visitPost(ASTCodegen.PostExp e)
        {
            writeExprWithPrecedence(e.e1, precedence[e.op]);
            write(EXPtoString(e.op));
        }

        void visitPre(ASTCodegen.PreExp e)
        {
            write(EXPtoString(e.op));
            writeExprWithPrecedence(e.e1, precedence[e.op]);
        }

        void visitRemove(ASTCodegen.RemoveExp e)
        {
            writeExprWithPrecedence(e.e1, PREC.primary);
            write(".remove(");
            writeExprWithPrecedence(e.e2, PREC.assign);
            write(')');
        }

        void visitCond(ASTCodegen.CondExp e)
        {
            writeExprWithPrecedence(e.econd, PREC.oror);
            write(" ? ");
            writeExprWithPrecedence(e.e1, PREC.expr);
            write(" : ");
            writeExprWithPrecedence(e.e2, PREC.cond);
        }

        void visitDefaultInit(ASTCodegen.DefaultInitExp e)
        {
            write(EXPtoString(e.op));
        }

        void visitClassReference(ASTCodegen.ClassReferenceExp e)
        {
            write(e.value.toString());
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
                    write(", ");

                if (names && i < names.length && (*names)[i])
                {
                    write((*names)[i].toString());
                    if (config.dfmt_space_before_named_arg_colon)
                        write(' ');
                    write(": ");
                }
                if (!el)
                    el = basis;
                if (el)
                    writeExprWithPrecedence(el, PREC.assign);
            }
        }
        else
        {
            if (basis)
            {
                write("0..");
                buf.print(expressions.length);
                write(": ");
                writeExprWithPrecedence(basis, PREC.assign);
            }
            foreach (i, el; *expressions)
            {
                if (el)
                {
                    if (basis)
                    {
                        write(", ");
                        write(i);
                        write(": ");
                    }
                    else if (i)
                        write(", ");
                    writeExprWithPrecedence(el, PREC.assign);
                }
            }
        }
    }

    void writeExprWithPrecedence(ASTCodegen.Expression e, PREC pr)
    {
        if (e.op == 0xFF)
        {
            write("<FF>");
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
            write('(');
            writeExpr(e);
            write(')');
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
            write(' ');
            write(ident.toString());
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
                write(MODtoString(MODFlags.shared_));
                write('(');
            }
            if (m & MODFlags.wild)
            {
                write(MODtoString(MODFlags.wild));
                write('(');
            }
            if (m & (MODFlags.const_ | MODFlags.immutable_))
            {
                write(MODtoString(m & (MODFlags.const_ | MODFlags.immutable_)));
                write('(');
            }
            writeType(t);
            if (m & (MODFlags.const_ | MODFlags.immutable_))
                write(')');
            if (m & MODFlags.wild)
                write(')');
            if (m & MODFlags.shared_)
                write(')');
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
            write("__error__");
            newline();
        }

        void visitExp(ASTCodegen.ExpStatement s)
        {
            if (s.exp && s.exp.op == EXP.declaration &&
                (cast(ASTCodegen.DeclarationExp) s.exp).declaration)
            {
                (cast(ASTCodegen.DeclarationExp) s.exp).declaration.accept(this);
                return;
            }
            if (s.exp)
                writeExpr(s.exp);
            write(';');
            newline();
        }

        void visitDtorExp(ASTCodegen.DtorExpStatement s)
        {
            visitExp(s);
        }

        void visitMixin(ASTCodegen.MixinStatement s)
        {
            write("mixin(");
            writeArgs(s.exps);
            write(");");
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
            write(';');
        }

        void visitUnrolledLoop(ASTCodegen.UnrolledLoopStatement s)
        {
            write("/*unrolled*/ {");
            newline();
            depth++;
            foreach (sx; *s.statements)
            {
                if (sx)
                    writeStatement(sx);
            }
            depth--;
            write('}');
            newline();
        }

        void visitScope(ASTCodegen.ScopeStatement s)
        {
            if (!insideCase)
            {
                if (config.dfmt_brace_style != BraceStyle.knr || s.statement.isCompoundStatement.statements.length != 1)
                    write('{');
                newline();
            }
            depth++;
            if (s.statement)
                writeStatement(s.statement);
            depth--;
            if (!insideCase)
            {
                if (config.dfmt_brace_style != BraceStyle.knr || s.statement.isCompoundStatement.statements.length != 1)
                {
                    write('}');
                    if (!insideIfOrDo)
                        newline();
                }
            }
        }

        void visitWhile(ASTCodegen.WhileStatement s)
        {
            write("while");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
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
                    write(p.ident.toString());
                write(" = ");
            }
            writeExpr(s.condition);
            write(')');
            newline();
            if (s._body)
                writeStatement(s._body);
        }

        void visitDo(ASTCodegen.DoStatement s)
        {
            write("do");
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            if (s._body.isScopeStatement)
            {
                insideIfOrDo = true;
                writeStatement(s._body);
                insideIfOrDo = false;
            }
            else
            {
                depth++;
                writeStatement(s._body);
                depth--;
            }
            if (config.dfmt_brace_style == BraceStyle.otbs)
                write(' ');
            else if (config.dfmt_brace_style != BraceStyle.knr || s._body
                .isScopeStatement.statement.isCompoundStatement.statements.length > 1)
                newline();
            write("while");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            writeExpr(s.condition);
            write(");");
            newline();
        }

        void visitFor(ASTCodegen.ForStatement s)
        {
            write("for");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            if (s._init)
            {
                writeStatement(s._init);
            }
            else
                write(';');
            if (s.condition)
            {
                write(' ');
                writeExpr(s.condition);
            }
            write(';');
            if (s.increment)
            {
                write(' ');
                writeExpr(s.increment);
            }
            write(')');
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            write('{');
            newline();
            depth++;
            if (s._body)
                writeStatement(s._body);
            depth--;
            write('}');
            newline();
        }

        void visitForeachWithoutBody(ASTCodegen.ForeachStatement s)
        {
            write(Token.toString(s.op));
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            foreach (i, p; *s.parameters)
            {
                if (i)
                    write(", ");
                writeStc(p.storageClass);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    write(p.ident.toString());
            }
            write("; ");
            writeExpr(s.aggr);
            write(')');
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
        }

        void visitForeach(ASTCodegen.ForeachStatement s)
        {
            visitForeachWithoutBody(s);
            write('{');
            newline();
            depth++;
            if (s._body)
                writeStatement(s._body);
            depth--;
            write('}');
            newline();
        }

        void visitForeachRangeWithoutBody(ASTCodegen.ForeachRangeStatement s)
        {
            write(Token.toString(s.op));
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            if (s.prm.type)
                writeTypeWithIdent(s.prm.type, s.prm.ident);
            else
                write(s.prm.ident.toString());
            write("; ");
            writeExpr(s.lwr);
            write(" .. ");
            writeExpr(s.upr);
            write(')');
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
        }

        void visitForeachRange(ASTCodegen.ForeachRangeStatement s)
        {
            visitForeachRangeWithoutBody(s);
            write('{');
            newline();
            depth++;
            if (s._body)
                writeStatement(s._body);
            depth--;
            write('}');
            newline();
        }

        void visitStaticForeach(ASTCodegen.StaticForeachStatement s)
        {
            indent();
            write("static ");
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
            write("if");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            if (Parameter p = s.prm)
            {
                StorageClass stc = p.storageClass;
                if (!p.type && !stc)
                    stc = STC.auto_;
                writeStc(stc);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    write(p.ident.toString());
                write(" = ");
            }
            writeExpr(s.condition);
            write(')');
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            if (s.ifbody.isScopeStatement())
            {
                insideIfOrDo = true;
                writeStatement(s.ifbody);
                insideIfOrDo = false;
            }
            else
            {
                depth++;
                writeStatement(s.ifbody);
                depth--;
            }
            if (s.elsebody)
            {
                if (config.dfmt_brace_style == BraceStyle.otbs)
                    write(' ');
                else if (config.dfmt_brace_style != BraceStyle.knr ||
                    s.ifbody.isScopeStatement.statement.isCompoundStatement.statements.length > 1)
                    newline();
                write("else");
                if (!s.elsebody.isIfStatement() && config.dfmt_brace_style == BraceStyle.allman)
                {
                    newline();
                }
                else
                {
                    write(' ');
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
            else
            {
                newline();
            }
        }

        void visitConditional(ASTCodegen.ConditionalStatement s)
        {
            s.condition.accept(this);
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            write('{');
            newline();
            depth++;
            if (s.ifbody)
                writeStatement(s.ifbody);
            depth--;
            write('}');
            newline();
            if (s.elsebody)
            {
                write("else");
                if (config.dfmt_brace_style == BraceStyle.allman)
                    newline();
                else
                    write(' ');
                write('{');
                depth++;
                newline();
                writeStatement(s.elsebody);
                depth--;
                write('}');
                newline();
            }
        }

        void visitPragma(ASTCodegen.PragmaStatement s)
        {
            write("pragma");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            write(s.ident.toString());
            if (s.args && s.args.length)
            {
                write(", ");
                writeArgs(s.args);
            }
            write(')');
            if (s._body)
            {
                if (config.dfmt_brace_style == BraceStyle.allman)
                    newline();
                else
                    write(' ');
                write('{');
                newline();
                depth++;
                writeStatement(s._body);
                depth--;
                write('}');
                newline();
            }
            else
            {
                write(';');
                newline();
            }
        }

        void visitStaticAssert(ASTCodegen.StaticAssertStatement s)
        {
            s.sa.accept(this);
        }

        void visitSwitch(ASTCodegen.SwitchStatement s)
        {
            write(s.isFinal ? "final switch" : "switch");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
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
                    write(p.ident.toString());
                write(" = ");
            }
            writeExpr(s.condition);
            write(')');
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            if (s._body)
            {
                if (!s._body.isScopeStatement())
                {
                    write('{');
                    newline();
                    depth++;
                    writeStatement(s._body);
                    depth--;
                    write('}');
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
            if (config.dfmt_align_switch_statements)
                depth--;
            write("case ");
            writeExpr(s.exp);
            write(':');
            newline();
            insideCase = true;
            writeStatement(s.statement);
            insideCase = false;
            if (config.dfmt_align_switch_statements)
                depth++;
        }

        void visitCaseRange(ASTCodegen.CaseRangeStatement s)
        {
            write("case ");
            writeExpr(s.first);
            write(": .. case ");
            writeExpr(s.last);
            write(':');
            newline();
            writeStatement(s.statement);
        }

        void visitDefault(ASTCodegen.DefaultStatement s)
        {
            if (config.dfmt_align_switch_statements)
                depth--;
            write("default:");
            newline();
            writeStatement(s.statement);
            if (config.dfmt_align_switch_statements)
                depth++;
        }

        void visitGotoDefault(ASTCodegen.GotoDefaultStatement _)
        {
            write("goto default;");
            newline();
        }

        void visitGotoCase(ASTCodegen.GotoCaseStatement s)
        {
            write("goto case");
            if (s.exp)
            {
                write(' ');
                writeExpr(s.exp);
            }
            write(';');
            newline();
        }

        void visitReturn(ASTCodegen.ReturnStatement s)
        {
            write("return ");
            if (s.exp)
                writeExpr(s.exp);
            write(';');
            newline();
        }

        void visitBreak(ASTCodegen.BreakStatement s)
        {
            write("break");
            if (s.ident)
            {
                write(' ');
                write(s.ident.toString());
            }
            write(';');
            newline();
        }

        void visitContinue(ASTCodegen.ContinueStatement s)
        {
            write("continue");
            if (s.ident)
            {
                write(' ');
                write(s.ident.toString());
            }
            write(';');
            newline();
        }

        void visitSynchronized(ASTCodegen.SynchronizedStatement s)
        {
            write("synchronized");
            if (s.exp)
            {
                write('(');
                writeExpr(s.exp);
                write(')');
            }
            if (s._body)
            {
                write(' ');
                writeStatement(s._body);
            }
        }

        void visitWith(ASTCodegen.WithStatement s)
        {
            write("with");
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            writeExpr(s.exp);
            write(")");
            newline();
            if (s._body)
                writeStatement(s._body);
        }

        void visitTryCatch(ASTCodegen.TryCatchStatement s)
        {
            write("try");
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
                write("catch");
                if (c.type)
                {
                    write('(');
                    writeTypeWithIdent(c.type, c.ident);
                    write(')');
                }
                if (config.dfmt_brace_style == BraceStyle.allman)
                    newline();
                else
                    write(' ');
                write('{');
                newline();
                depth++;
                if (c.handler)
                    writeStatement(c.handler);
                depth--;
                write('}');
                newline();
            }
        }

        void visitTryFinally(ASTCodegen.TryFinallyStatement s)
        {
            write("try");
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            write('{');
            newline();
            depth++;
            writeStatement(s._body);
            depth--;
            write('}');
            newline();
            write("finally");
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
            write(Token.toString(s.tok));
            write(' ');
            if (s.statement)
                writeStatement(s.statement);
        }

        void visitThrow(ASTCodegen.ThrowStatement s)
        {
            write("throw ");
            writeExpr(s.exp);
            write(';');
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
            write("goto ");
            write(s.ident.toString());
            write(';');
            newline();
        }

        void visitLabel(ASTCodegen.LabelStatement s)
        {
            write(s.ident.toString());
            write(':');
            if (config.dfmt_compact_labeled_statements)
                write(' ');
            else
                newline();
            if (s.statement)
                writeStatement(s.statement);
        }

        void visitAsm(ASTCodegen.AsmStatement s)
        {
            write("asm { ");
            Token* t = s.tokens;
            depth++;
            while (t)
            {
                write(Token.toString(t.value));
                if (t.next &&
                    t.value != TOK.min &&
                    t.value != TOK.comma && t.next.value != TOK.comma &&
                    t.value != TOK.leftBracket && t.next.value != TOK.leftBracket &&
                    t.next.value != TOK.rightBracket &&
                    t.value != TOK.leftParenthesis && t.next.value != TOK.leftParenthesis &&
                    t.next.value != TOK.rightParenthesis &&
                    t.value != TOK.dot && t.next.value != TOK.dot)
                {
                    write(' ');
                }
                t = t.next;
            }
            depth--;
            write("; }");
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
        if (config.dfmt_brace_style == BraceStyle.allman || config.dfmt_brace_style == BraceStyle
            .knr)
            newline();
        else
            write(' ');
        writeContracts(f);
        write('{');
        newline();
        depth++;
        if (f.fbody)
        {
            writeStatement(f.fbody);
        }
        else
        {
            write('{');
            newline();
            write('}');
            newline();
        }
        depth--;
        write('}');
        newline();
    }

    void writeContracts(ASTCodegen.FuncDeclaration f)
    {
        bool requireDo = false;
        // in{}
        if (f.frequires)
        {
            foreach (frequire; *f.frequires)
            {
                write("in");
                if (auto es = frequire.isExpStatement())
                {
                    assert(es.exp && es.exp.op == EXP.assert_);
                    if (config.dfmt_space_after_keywords)
                        write(' ');
                    write('(');
                    writeExpr((cast(ASTCodegen.AssertExp) es.exp).e1);
                    write(')');
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
                write("out");
                if (auto es = fensure.ensure.isExpStatement())
                {
                    assert(es.exp && es.exp.op == EXP.assert_);
                    if (config.dfmt_space_after_keywords)
                        write(' ');
                    write('(');
                    if (fensure.id)
                    {
                        write(fensure.id.toString());
                    }
                    write("; ");
                    writeExpr((cast(ASTCodegen.AssertExp) es.exp).e1);
                    write(')');
                    newline();
                    requireDo = false;
                }
                else
                {
                    if (fensure.id)
                    {
                        write('(');
                        write(fensure.id.toString());
                        write(')');
                    }
                    newline();
                    writeStatement(fensure.ensure);
                    requireDo = true;
                }
            }
        }

        if (requireDo)
        {
            write("do");
            if (config.dfmt_brace_style == BraceStyle.allman || config.dfmt_brace_style == BraceStyle
                .knr)
                newline();
            else
                write(' ');
        }
    }

    void writeInitializer(Initializer inx)
    {
        void visitError(ErrorInitializer _)
        {
            write("__error__");
        }

        void visitVoid(VoidInitializer _)
        {
            write("void");
        }

        void visitStruct(StructInitializer si)
        {
            write('{');
            foreach (i, const id; si.field)
            {
                if (i)
                    write(", ");
                if (id)
                {
                    write(id.toString());
                    write(':');
                }
                if (auto iz = si.value[i])
                    writeInitializer(iz);
            }
            write('}');
        }

        void visitArray(ArrayInitializer ai)
        {
            write('[');
            foreach (i, ex; ai.index)
            {
                if (i)
                    write(", ");
                if (ex)
                {
                    writeExpr(ex);
                    if (config.dfmt_space_before_aa_colon)
                        write(' ');
                    write(": ");
                }
                if (auto iz = ai.value[i])
                    writeInitializer(iz);
            }
            write(']');
        }

        void visitExp(ExpInitializer ei)
        {
            writeExpr(ei.exp);
        }

        void visitC(CInitializer ci)
        {
            write('{');
            foreach (i, ref DesigInit di; ci.initializerList)
            {
                if (i)
                    write(", ");
                if (di.designatorList)
                {
                    foreach (ref Designator d; (*di.designatorList)[])
                    {
                        if (d.exp)
                        {
                            write('[');
                            d.exp.accept(this);
                            write(']');
                        }
                        else
                        {
                            write('.');
                            write(d.ident.toString());
                        }
                    }
                    write('=');
                }
                writeInitializer(di.initializer);
            }
            write('}');
        }

        void visitDefault(DefaultInitializer di)
        {
            write("{ }");
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
            writeExprWithPrecedence(e, PREC.assign);
        }
        else if (ASTCodegen.Dsymbol s = isDsymbol(oarg))
        {
            const p = s.ident ? s.ident.toString() : s.toString();
            write(p);
        }
        else if (auto v = isTuple(oarg))
        {
            auto args = &v.objects;
            foreach (i, arg; *args)
            {
                if (i)
                    write(", ");
                writeObject(arg);
            }
        }
        else if (auto p = isParameter(oarg))
        {
            writeParam(p);
        }
        else if (!oarg)
        {
            write("NULL");
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
            write(", ");
            write(v.ident.toString());
        }
        else
        {
            auto stc = v.storage_class;
            writeStc(stc);
            if (v.type)
                writeTypeWithIdent(v.type, v.ident);
            else
                write(v.ident.toString());
        }
        if (v._init)
        {
            write(" = ");
            vinit(v);
        }
    }

    void writeSize(ASTCodegen.Expression e)
    {
        import dmd.expression : WANTvalue;

        if (e.type == Type.tsize_t)
        {
            ASTCodegen.Expression ex = (e.op == EXP.cast_ ? (cast(ASTCodegen.CastExp) e).e1 : e);
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
                    write(format("%lu", uval));
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
            write(MODtoString(t.mod));
            write(' ');
        }

        void ignoreReturn(string str)
        {
            import dmd.id : Id;

            if (str != "return")
            {
                // don't write 'ref' for ctors
                if ((ident == Id.ctor) && str == "ref")
                    return;
                write(str);
                write(' ');
            }
        }

        t.attributesApply(&ignoreReturn);

        if (t.linkage > LINK.d)
        {
            writeLinkage(t.linkage);
            write(' ');
        }
        if (ident && ident.toHChars2() != ident.toChars())
        {
            // Don't print return type for ctor, dtor, unittest, etc
        }
        else if (t.next)
        {
            writeTypeWithIdent(t.next, null);
            if (ident)
                write(' ');
        }
        if (ident)
            write(ident.toString());
        if (td)
        {
            write('(');
            foreach (i, p; *td.origParameters)
            {
                if (i)
                    write(", ");
                p.accept(this);
            }
            write(')');
        }
        writeParamList(t.parameterList);
        if (t.isreturn)
        {
            write(" return");
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
            write(' ');
        }
        if (t.linkage == LINK.objc && isStatic)
            write("static ");
        if (t.next)
        {
            writeTypeWithIdent(t.next, null);
            if (ident)
                write(' ');
        }
        if (ident)
            write(ident);
        writeParamList(t.parameterList);
        /* Use postfix style for attributes */
        if (t.mod)
        {
            write(' ');
            write(MODtoString(t.mod));
        }

        void dg(string str)
        {
            write(' ');
            write(str);
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
            write("_error_");
        }

        void visitBasic(TypeBasic t)
        {
            write(t.toString());
        }

        void visitTraits(TypeTraits t)
        {
            writeExpr(t.exp);
        }

        void visitVector(TypeVector t)
        {
            write("__vector(");
            writeWithMask(t.basetype, t.mod);
            write(")");
        }

        void visitSArray(TypeSArray t)
        {
            writeWithMask(t.next, t.mod);
            write('[');
            writeSize(t.dim);
            write(']');
        }

        void visitDArray(TypeDArray t)
        {
            Type ut = t.castMod(0);
            if (declString)
                goto L1;
            if (ut.equals(Type.tstring))
                write("string");
            else if (ut.equals(Type.twstring))
                write("wstring");
            else if (ut.equals(Type.tdstring))
                write("dstring");
            else
            {
            L1:
                writeWithMask(t.next, t.mod);
                write("[]");
            }
        }

        void visitAArray(TypeAArray t)
        {
            writeWithMask(t.next, t.mod);
            write('[');
            writeWithMask(t.index, 0);
            write(']');
        }

        void visitPointer(TypePointer t)
        {
            if (t.next.ty == Tfunction)
                writeFuncIdentWithPostfix(cast(TypeFunction) t.next, "function", false);
            else
            {
                writeWithMask(t.next, t.mod);
                write('*');
            }
        }

        void visitReference(TypeReference t)
        {
            writeWithMask(t.next, t.mod);
            write('&');
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
                    write('.');
                    ASTCodegen.TemplateInstance ti = cast(ASTCodegen.TemplateInstance) id;
                    ti.accept(this);
                    break;
                case expression:
                    write('[');
                    writeExpr(cast(ASTCodegen.Expression) id);
                    write(']');
                    break;
                case type:
                    write('[');
                    writeType(cast(Type) id);
                    write(']');
                    break;
                default:
                    write('.');
                    write(id.toString());
                }
            }
        }

        void visitIdentifier(TypeIdentifier t)
        {
            write(t.ident.toString());
            visitTypeQualifiedHelper(t);
        }

        void visitInstance(TypeInstance t)
        {
            t.tempinst.accept(this);
            visitTypeQualifiedHelper(t);
        }

        void visitTypeof(TypeTypeof t)
        {
            write("typeof(");
            writeExpr(t.exp);
            write(')');
            visitTypeQualifiedHelper(t);
        }

        void visitReturn(TypeReturn t)
        {
            write("typeof(return)");
            visitTypeQualifiedHelper(t);
        }

        void visitEnum(TypeEnum t)
        {
            write(t.sym.toString());
        }

        void visitStruct(TypeStruct t)
        {
            // https://issues.dlang.org/show_bug.cgi?id=13776
            // Don't use ti.toAlias() to avoid forward reference error
            // while printing messages.
            ASTCodegen.TemplateInstance ti = t.sym.parent ? t.sym.parent.isTemplateInstance() : null;
            if (ti && ti.aliasdecl == t.sym)
                write(ti.toString());
            else
                write(t.sym.toString());
        }

        void visitClass(TypeClass t)
        {
            // https://issues.dlang.org/show_bug.cgi?id=13776
            // Don't use ti.toAlias() to avoid forward reference error
            // while printing messages.
            ASTCodegen.TemplateInstance ti = t.sym.parent ? t.sym.parent.isTemplateInstance() : null;
            if (ti && ti.aliasdecl == t.sym)
                write(ti.toString());
            else
                write(t.sym.toString());
        }

        void visitTag(TypeTag t)
        {
            if (t.mod & MODFlags.const_)
                write("const ");
            write(Token.toString(t.tok));
            write(' ');
            if (t.id)
                write(t.id.toString());
            if (t.tok == TOK.enum_ && t.base && t.base.ty != TY.Tint32)
            {
                write(" : ");
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
            write('[');
            writeSize(t.lwr);
            write(" .. ");
            writeSize(t.upr);
            write(']');
        }

        void visitNull(TypeNull _)
        {
            write("typeof(null)");
        }

        void visitMixin(TypeMixin t)
        {
            write("mixin(");
            writeArgs(t.exps);
            write(')');
        }

        void visitNoreturn(TypeNoreturn _)
        {
            write("noreturn");
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
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            write(s);
            write(')');
        }
    }

    void writeParam(Parameter p)
    {
        if (p.userAttribDecl)
        {
            write('@');

            bool isAnonymous = p.userAttribDecl.atts.length > 0 && !(*p.userAttribDecl.atts)[0].isCallExp();
            if (isAnonymous)
                write('(');

            writeArgs(p.userAttribDecl.atts);

            if (isAnonymous)
                write(')');
            write(' ');
        }
        if (p.storageClass & STC.auto_)
            write("auto ");

        StorageClass stc = p.storageClass;
        if (p.storageClass & STC.in_)
        {
            write("in ");
        }
        else if (p.storageClass & STC.lazy_)
            write("lazy ");
        else if (p.storageClass & STC.alias_)
            write("alias ");

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
                write(p.ident.toString());
        }
        else if (p.type.ty == Tident &&
            (cast(TypeIdentifier) p.type)
                .ident.toString().length > 3 &&
            strncmp((cast(TypeIdentifier) p.type)
                .ident.toChars(), "__T", 3) == 0)
        {
            // print parameter name, instead of undetermined type parameter
            write(p.ident.toString());
        }
        else
        {
            writeTypeWithIdent(p.type, p.ident, (stc & STC.in_) ? MODFlags.const_ : 0);
        }

        if (p.defaultArg)
        {
            write(" = ");
            writeExprWithPrecedence(p.defaultArg, PREC.assign);
        }
    }

    void writeParamList(ParameterList pl)
    {
        if (config.dfmt_space_before_function_parameters)
            write(' ');
        write('(');
        foreach (i; 0 .. pl.length)
        {
            if (i)
                write(", ");
            writeParam(pl[i]);
        }
        final switch (pl.varargs)
        {
        case VarArg.none:
            break;

        case VarArg.variadic:
            if (pl.length)
                write(", ");

            writeStc(pl.stc);
            goto case VarArg.typesafe;

        case VarArg.typesafe:
            write("...");
            break;

        case VarArg.KRvariadic:
            break;
        }
        write(')');
    }

    void writeVisibility(ASTCodegen.Visibility vis)
    {
        write(visibilityToString(vis.kind));
        if (vis.kind == ASTCodegen.Visibility.Kind.package_ && vis.pkg)
        {
            write('(');
            write(vis.pkg.toPrettyChars(true).toDString());
            write(')');
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
        write('!');
        if (ti.nest)
        {
            write("(...)");
            return;
        }
        if (!ti.tiargs)
        {
            write("()");
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
                    write(t.toString());
                    return;
                }
            }
            else if (ASTCodegen.Expression e = isExpression(oarg))
            {
                if (e.op == EXP.int64 || e.op == EXP.float64 || e.op == EXP.null_ || e.op == EXP.string_ || e.op == EXP
                    .this_)
                {
                    write(e.toString());
                    return;
                }
            }
        }
        write('(');
        ti.nestUp();
        foreach (i, arg; *ti.tiargs)
        {
            if (i)
                write(", ");
            writeObject(arg);
        }
        ti.nestDown();
        write(')');
    }
    /*******************************************
    * Visitors for AST nodes
    */
    void visitDsymbol(ASTCodegen.Dsymbol s)
    {
        write(s.toString());
    }

    void visitStaticAssert(ASTCodegen.StaticAssert s)
    {
        write(s.kind().toDString());
        write('(');
        writeExpr(s.exp);
        if (s.msgs)
        {
            foreach (m; (*s.msgs)[])
            {
                write(", ");
                writeExpr(m);
            }
        }
        write(");");
        newline();
    }

    void visitDebugSymbol(ASTCodegen.DebugSymbol s)
    {
        write("debug = ");
        write(s.ident.toString());
        write(';');
        newline();
    }

    void visitVersionSymbol(ASTCodegen.VersionSymbol s)
    {
        write("version = ");
        write(s.ident.toString());
        write(';');
        newline();
    }

    void visitEnumMember(ASTCodegen.EnumMember em)
    {
        if (em.type)
            writeTypeWithIdent(em.type, em.ident);
        else
            write(em.ident.toString());
        if (em.value)
        {
            write(" = ");
            writeExpr(em.value);
        }
    }

    void visitImport(ASTCodegen.Import imp)
    {
        if (imp.isstatic)
            write("static ");
        write("import ");
        if (imp.aliasId)
        {
            write(imp.aliasId.toString());
            write(" = ");
        }
        foreach (const pid; imp.packages)
        {
            write(pid.toString());
            write(".");
        }
        write(imp.id.toString());
        if (imp.names.length)
        {
            if (config.dfmt_selective_import_space)
                write(' ');
            write(": ");
            foreach (const i, const name; imp.names)
            {
                if (i)
                    write(", ");
                const _alias = imp.aliases[i];
                if (_alias)
                {
                    write(_alias.toString());
                    write(" = ");
                    write(name.toString());
                }
                else
                    write(name.toString());
            }
        }

        write(';');
        newline();
    }

    void visitAliasThis(ASTCodegen.AliasThis d)
    {
        write("alias ");
        write(d.ident.toString());
        write(" this;");
        newline();
    }

    override void visitAttribDeclaration(ASTCodegen.AttribDeclaration d)
    {
        if (isNewline)
        {
            newline();
        }
        if (auto stcd = d.isStorageClassDeclaration)
        {
            writeStc(stcd.stc);
        }

        if (!d.decl)
        {
            write(';');
            newline();
            return;
        }

        if (d.decl.length == 0)
        {
            write("{}");
        }
        else if (d.decl.length == 1)
        {
            (*d.decl)[0].accept(this);
            return;
        }
        else
        {
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            write('{');
            newline();
            depth++;
            foreach (de; *d.decl)
                de.accept(this);
            depth--;
            write('}');
        }
        newline();
    }

    void visitStorageClassDeclaration(ASTCodegen.StorageClassDeclaration d)
    {
        visitAttribDeclaration(d);
    }

    void visitDeprecatedDeclaration(ASTCodegen.DeprecatedDeclaration d)
    {
        write("deprecated(");
        writeExpr(d.msg);
        write(") ");
        visitAttribDeclaration(d);
    }

    void visitLinkDeclaration(ASTCodegen.LinkDeclaration d)
    {
        write("extern");
        if (config.dfmt_space_after_keywords)
            write(' ');
        write('(');
        write(linkageToString(d.linkage));
        write(") ");
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
        write("extern (C++, ");
        write(s);
        write(") ");
        visitAttribDeclaration(d);
    }

    void visitVisibilityDeclaration(ASTCodegen.VisibilityDeclaration d)
    {
        if (isNewline)
        {
            newline();
        }
        writeVisibility(d.visibility);
        ASTCodegen.AttribDeclaration ad = cast(ASTCodegen.AttribDeclaration) d;
        if (ad.decl.length <= 1)
            write(' ');
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
                    write(' ');
                write(format("align (%s)", exp.toString()));
            }
            if (d.decl && d.decl.length < 2)
                write(' ');
        }
        else
            write("align ");

        visitAttribDeclaration(d.isAttribDeclaration());
    }

    void visitAnonDeclaration(ASTCodegen.AnonDeclaration d)
    {
        write(d.isunion ? "union" : "struct");
        if (config.dfmt_brace_style == BraceStyle.allman)
            newline();
        else
            write(' ');
        write('{');
        newline();
        depth++;
        if (d.decl)
        {
            foreach (de; *d.decl)
                de.accept(this);
        }
        depth--;
        write('}');
        newline();
    }

    void visitPragmaDeclaration(ASTCodegen.PragmaDeclaration d)
    {
        write("pragma");
        if (config.dfmt_space_after_keywords)
            write(' ');
        write('(');
        write(d.ident.toString());
        if (d.args && d.args.length)
        {
            write(", ");
            writeArgs(d.args);
        }

        write(')');
        visitAttribDeclaration(d);
    }

    void visitConditionalDeclaration(ASTCodegen.ConditionalDeclaration d)
    {
        d.condition.accept(this);
        if (d.decl || d.elsedecl)
        {
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            write('{');
            newline();
            depth++;
            if (d.decl)
            {
                foreach (de; *d.decl)
                    de.accept(this);
            }
            depth--;
            write('}');
            if (d.elsedecl)
            {
                newline();
                write("else");
                if (config.dfmt_brace_style == BraceStyle.allman)
                    newline();
                else
                    write(' ');
                write('{');
                newline();
                depth++;
                foreach (de; *d.elsedecl)
                    de.accept(this);
                depth--;
                write('}');
            }
        }
        else
            write(':');
        newline();
    }

    void visitStaticForeachDeclaration(ASTCodegen.StaticForeachDeclaration s)
    {
        void foreachWithoutBody(ASTCodegen.ForeachStatement s)
        {
            write(Token.toString(s.op));
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            foreach (i, p; *s.parameters)
            {
                if (i)
                    write(", ");
                writeStc(p.storageClass);
                if (p.type)
                    writeTypeWithIdent(p.type, p.ident);
                else
                    write(p.ident.toString());
            }
            write("; ");
            writeExpr(s.aggr);
            write(')');
            newline();
        }

        void foreachRangeWithoutBody(ASTCodegen.ForeachRangeStatement s)
        {
            /* s.op ( prm ; lwr .. upr )
             */
            write(Token.toString(s.op));
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            if (s.prm.type)
                writeTypeWithIdent(s.prm.type, s.prm.ident);
            else
                write(s.prm.ident.toString());
            write("; ");
            writeExpr(s.lwr);
            write(" .. ");
            writeExpr(s.upr);
            write(')');
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
        }

        write("static ");
        if (s.sfe.aggrfe)
        {
            foreachWithoutBody(s.sfe.aggrfe);
        }
        else
        {
            assert(s.sfe.rangefe);
            foreachRangeWithoutBody(s.sfe.rangefe);
        }
        write('{');
        newline();
        depth++;
        visitAttribDeclaration(s);
        depth--;
        write('}');
        newline();

    }

    void visitMixinDeclaration(ASTCodegen.MixinDeclaration d)
    {
        write("mixin(");
        writeArgs(d.exps);
        write(");");
        newline();
    }

    void visitUserAttributeDeclaration(ASTCodegen.UserAttributeDeclaration d)
    {
        write("@(");
        writeArgs(d.atts);
        write(')');
        visitAttribDeclaration(d);
    }

    void visitTemplateConstraint(ASTCodegen.Expression constraint)
    {
        if (!constraint)
            return;

        final switch (config.dfmt_template_constraint_style)
        {
        case TemplateConstraintStyle._unspecified:
            // Fallthrough to the default case
        case TemplateConstraintStyle.conditional_newline_indent:
            conditionalNewline();
            depth++;
            break;
        case TemplateConstraintStyle.always_newline_indent:
            newline();
            depth++;
            break;
        case TemplateConstraintStyle.conditional_newline:
            conditionalNewline();
            break;
        case TemplateConstraintStyle.always_newline:
            newline();
            break;
        }

        write(" if");
        if (config.dfmt_space_after_keywords)
            write(' ');
        write('(');
        writeExpr(constraint);
        write(')');

        if (config.dfmt_template_constraint_style == TemplateConstraintStyle.always_newline_indent
            || config.dfmt_template_constraint_style
            == TemplateConstraintStyle.conditional_newline_indent)
            depth--;
    }

    override void visitBaseClasses(ASTCodegen.ClassDeclaration d)
    {
        if (!d || !d.baseclasses.length)
            return;
        if (!d.isAnonymous())
            write(" : ");
        foreach (i, b; *d.baseclasses)
        {
            if (i)
                write(", ");
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
            write(ad.kind().toDString());
            write(' ');
            write(ad.ident.toString());
            write('(');
            visitTemplateParameters(d.parameters);
            write(')');
            visitTemplateConstraint(d.constraint);
            visitBaseClasses(ad.isClassDeclaration());
            if (ad.members)
            {
                if (config.dfmt_brace_style == BraceStyle.allman)
                    newline();
                else
                    write(' ');
                write('{');
                newline();
                depth++;
                foreach (s; *ad.members)
                    s.accept(this);
                depth--;
                write('}');
            }
            else
                write(';');
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
                write(vd.ident.toString());
            write('(');
            visitTemplateParameters(d.parameters);
            write(')');
            if (vd._init)
            {
                write(" = ");
                ExpInitializer ie = vd._init.isExpInitializer();
                if (ie && (ie.exp.op == EXP.construct || ie.exp.op == EXP.blit))
                    writeExpr((cast(ASTCodegen.AssignExp) ie.exp).e2);
                else
                    writeInitializer(vd._init);
            }
            write(';');
            newline();
            return true;
        }
        return false;
    }

    void visitTemplateDeclaration(ASTCodegen.TemplateDeclaration d)
    {
        write("template");
        write(' ');
        write(d.ident.toString());
        write('(');
        visitTemplateParameters(d.parameters);
        write(')');
        visitTemplateConstraint(d.constraint);
    }

    void visitTemplateInstance(ASTCodegen.TemplateInstance ti)
    {
        write(ti.name.toString());
        writeTiArgs(ti);
    }

    void visitTemplateMixin(ASTCodegen.TemplateMixin tm)
    {
        write("mixin ");
        writeTypeWithIdent(tm.tqual, null);
        writeTiArgs(tm);
        if (tm.ident && tm.ident.toString() != "__mixin")
        {
            write(' ');
            write(tm.ident.toString());
        }
        write(';');
        newline();
    }

    void visitEnumDeclaration(ASTCodegen.EnumDeclaration d)
    {
        write("enum ");
        if (d.ident)
        {
            write(d.ident.toString());
        }
        if (d.memtype)
        {
            write(" : ");
            writeTypeWithIdent(d.memtype, null);
        }
        if (!d.members)
        {
            write(';');
            newline();
            return;
        }
        if (config.dfmt_brace_style == BraceStyle.allman)
            newline();
        else
            write(' ');
        write('{');
        newline();
        depth++;
        foreach (em; *d.members)
        {
            if (!em)
                continue;
            em.accept(this);
            write(',');
            newline();
        }
        depth--;
        write('}');
        newline();
    }

    void visitNspace(ASTCodegen.Nspace d)
    {
        write("extern (C++, ");
        write(d.ident.toString());
        write(')');
        if (config.dfmt_brace_style == BraceStyle.allman)
            newline();
        else
            write(' ');
        write('{');
        newline();
        depth++;
        foreach (s; *d.members)
            s.accept(this);
        depth--;
        write('}');
        newline();
    }

    void visitStructDeclaration(ASTCodegen.StructDeclaration d)
    {
        write(d.kind().toDString());
        write(' ');
        if (!d.isAnonymous())
            write(d.toString());
        if (!d.members)
        {
            write(';');
            newline();
            return;
        }
        if (config.dfmt_brace_style == BraceStyle.allman)
            newline();
        else
            write(' ');
        write('{');
        newline();
        depth++;
        foreach (s; *d.members)
            s.accept(this);
        depth--;
        write('}');
        newline();
    }

    void visitClassDeclaration(ASTCodegen.ClassDeclaration d)
    {
        if (!d.isAnonymous())
        {
            write(d.kind().toDString());
            write(' ');
            write(d.ident.toString());
        }
        visitBaseClasses(d);
        if (d.members)
        {
            if (config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else
                write(' ');
            write('{');
            newline();
            depth++;
            foreach (s; *d.members)
                s.accept(this);
            depth--;
            write('}');
        }
        else
            write(';');
        newline();
    }

    void visitAliasDeclaration(ASTCodegen.AliasDeclaration d)
    {
        if (d.storage_class & STC.local)
            return;
        write("alias ");
        if (d.aliassym)
        {
            write(d.ident.toString());
            write(" = ");
            writeStc(d.storage_class);
            /*
                https://issues.dlang.org/show_bug.cgi?id=23223
                https://issues.dlang.org/show_bug.cgi?id=23222
                This special case (initially just for modules) avoids some segfaults
                and nicer -vcg-ast output.
            */
            if (d.aliassym.isModule())
            {
                write(d.aliassym.ident.toString());
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

            declString = (d.ident == Id.string || d.ident == Id.wstring || d.ident == Id
                    .dstring);
            write(d.ident.toString());
            write(" = ");
            writeStc(d.storage_class);
            writeTypeWithIdent(d.type, null);
            declString = false;
        }
        write(';');
        newline();
    }

    void visitAliasAssign(ASTCodegen.AliasAssign d)
    {
        write(d.ident.toString());
        write(" = ");
        if (d.aliassym)
            d.aliassym.accept(this);
        else // d.type
            writeTypeWithIdent(d.type, null);
        write(';');
        newline();
    }

    void visitVarDeclaration(ASTCodegen.VarDeclaration d)
    {
        if (d.storage_class & STC.local)
            return;
        writeVarDecl(d, false);
        write(';');
        newline();
    }

    void visitFuncDeclaration(ASTCodegen.FuncDeclaration f)
    {
        if (isNewline)
        {
            newline();
        }
        writeStc(f.storage_class);
        auto tf = cast(TypeFunction) f.type;
        writeTypeWithIdent(tf, f.ident);
        writeFuncBody(f);
    }

    void visitFuncLiteralDeclaration(ASTCodegen.FuncLiteralDeclaration f)
    {
        if (f.type.ty == Terror)
        {
            write("__error");
            return;
        }
        if (f.tok != TOK.reserved)
        {
            write(f.kind().toDString());
            write(' ');
        }
        TypeFunction tf = cast(TypeFunction) f.type;

        if (!f.inferRetType && tf.next)
            writeTypeWithIdent(tf.next, null);
        writeParamList(tf.parameterList);

        // https://issues.dlang.org/show_bug.cgi?id=20074
        void printAttribute(string str)
        {
            write(' ');
            write(str);
        }

        tf.attributesApply(&printAttribute);

        ASTCodegen.CompoundStatement cs = f.fbody.isCompoundStatement();
        ASTCodegen.Statement s1;
        s1 = !cs ? f.fbody : null;
        ASTCodegen.ReturnStatement rs = s1 ? s1.endsWithReturnStatement() : null;
        if (rs && rs.exp)
        {
            write(" => ");
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
        write("this(this)");
        writeFuncBody(d);
    }

    void visitDtorDeclaration(ASTCodegen.DtorDeclaration d)
    {
        writeStc(d.storage_class);
        write("~this()");
        writeFuncBody(d);
    }

    void visitStaticCtorDeclaration(ASTCodegen.StaticCtorDeclaration d)
    {
        writeStc(d.storage_class & ~STC.static_);
        if (d.isSharedStaticCtorDeclaration())
            write("shared ");
        write("static this()");
        writeFuncBody(d);
    }

    void visitStaticDtorDeclaration(ASTCodegen.StaticDtorDeclaration d)
    {
        writeStc(d.storage_class & ~STC.static_);
        if (d.isSharedStaticDtorDeclaration())
            write("shared ");
        write("static ~this()");
        writeFuncBody(d);
    }

    void visitInvariantDeclaration(ASTCodegen.InvariantDeclaration d)
    {
        writeStc(d.storage_class);
        write("invariant");
        if (auto es = d.fbody.isExpStatement())
        {
            assert(es.exp && es.exp.op == EXP.assert_);
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            writeExpr((cast(ASTCodegen.AssertExp) es.exp).e1);
            write(");");
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
        write("unittest");
        writeFuncBody(d);
    }

    void visitBitFieldDeclaration(ASTCodegen.BitFieldDeclaration d)
    {
        writeStc(d.storage_class);
        Identifier id = d.isAnonymous() ? null : d.ident;
        writeTypeWithIdent(d.type, id);
        write(" : ");
        writeExpr(d.width);
        write(';');
        newline();
    }

    void visitNewDeclaration(ASTCodegen.NewDeclaration d)
    {
        writeStc(d.storage_class & ~STC.static_);
        write("new();");
    }

    void visitModule(ASTCodegen.Module m)
    {
        if (m.md)
        {
            if (m.userAttribDecl)
            {
                write("@(");
                writeArgs(m.userAttribDecl.atts);
                write(')');
                newline();
            }
            if (m.md.isdeprecated)
            {
                if (m.md.msg)
                {
                    write("deprecated(");
                    writeExpr(m.md.msg);
                    write(") ");
                }
                else
                    write("deprecated ");
            }
            write("module ");
            write(m.md.toString());
            write(';');
            newline();
            newline();
        }

        foreach (s; *m.members)
        {
            s.accept(this);
        }
    }

    void visitDebugCondition(ASTCodegen.DebugCondition c)
    {
        write("debug");
        if (c.ident)
        {
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            write(c.ident.toString());
            write(')');
        }
    }

    void visitVersionCondition(ASTCodegen.VersionCondition c)
    {
        write("version");
        if (c.ident)
        {
            if (config.dfmt_space_after_keywords)
                write(' ');
            write('(');
            write(c.ident.toString());
            write(')');
        }
    }

    void visitStaticIfCondition(ASTCodegen.StaticIfCondition c)
    {
        write("static if");
        if (config.dfmt_space_after_keywords)
            write(' ');
        write('(');
        writeExpr(c.exp);
        write(')');
    }

    void visitTemplateTypeParameter(ASTCodegen.TemplateTypeParameter tp)
    {
        write(tp.ident.toString());
        if (tp.specType)
        {
            write(" : ");
            writeTypeWithIdent(tp.specType, null);
        }
        if (tp.defaultType)
        {
            write(" = ");
            writeTypeWithIdent(tp.defaultType, null);
        }
    }

    void visitTemplateThisParameter(ASTCodegen.TemplateThisParameter tp)
    {
        write("this ");
        visit(cast(ASTCodegen.TemplateTypeParameter) tp);
    }

    void visitTemplateAliasParameter(ASTCodegen.TemplateAliasParameter tp)
    {
        write("alias ");
        if (tp.specType)
            writeTypeWithIdent(tp.specType, tp.ident);
        else
            write(tp.ident.toString());
        if (tp.specAlias)
        {
            write(" : ");
            writeObject(tp.specAlias);
        }
        if (tp.defaultAlias)
        {
            write(" = ");
            writeObject(tp.defaultAlias);
        }
    }

    void visitTemplateValueParameter(ASTCodegen.TemplateValueParameter tp)
    {
        writeTypeWithIdent(tp.valType, tp.ident);
        if (tp.specValue)
        {
            write(" : ");
            writeExpr(tp.specValue);
        }
        if (tp.defaultValue)
        {
            write(" = ");
            writeExpr(tp.defaultValue);
        }
    }

    void visitTemplateTupleParameter(ASTCodegen.TemplateTupleParameter tp)
    {
        write(tp.ident.toString());
        write("...");
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
