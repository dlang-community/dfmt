//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.formatter;

import dmd.tokens;
import dmd.parse;
import dmd.id;
import dmd.errorsink;
import dmd.identifier;
import dmd.astbase;
import dmd.transitivevisitor;
import dmd.permissivevisitor;
import dfmt.ast_info;
import dfmt.config;
import dfmt.indentation;
import dfmt.tokens;
import dfmt.wrapping;
import std.array;
import std.algorithm.comparison : among, max;

/**
 * Formats the code contained in `buffer` into `output`.
 * Params:
 *     source_desc = A description of where `buffer` came from. Usually a file name.
 *     buffer = The raw source code.
 *     output = The output range that will have the formatted code written to it.
 *     formatterConfig = Formatter configuration.
 * Returns: `true` if the formatting succeeded, `false` of a lexing error. This
 *     function can return `true` if parsing failed.
 */
bool format(OutputRange)(string source_desc, ubyte[] buffer, OutputRange output,
    Config* formatterConfig)
{
    Id.initialize();
    ASTBase.Type._init();

    auto id = Identifier.idPool(source_desc);
    auto m = new ASTBase.Module(&(source_desc.dup)[0], id, false, false);
    import std.file : readText;

    auto input = readText(source_desc);
    auto inp = cast(char[]) input;

    auto p = new Parser!ASTBase(m, inp, false, new ErrorSinkNull, null, false);
    /* p.nextToken(); */
    m.members = p.parseModule();

    ASTInformation astInformation;
    scope vis = new FormatVisitor!ASTBase(&astInformation);
    m.accept(vis);
    /* auto tokenRange = byToken(buffer, config, &cache); */
    /* auto app = appender!(Token[])(); */
    /* for (; !tokenRange.empty(); tokenRange.popFront()) */
    /*     app.put(tokenRange.front()); */
    /* auto tokens = app.data; */
    /* if (!tokenRange.messages.empty) */
    /*     return false; */
    /* auto depths = generateDepthInfo(tokens); */
    /* auto tokenFormatter = TokenFormatter!OutputRange(buffer, tokens, depths, */
    /*     output, &astInformation, formatterConfig); */
    /* tokenFormatter.format(); */
    return true;
}

immutable(short[]) generateDepthInfo(const Token[] tokens) pure nothrow @trusted
{
    import std.exception : assumeUnique;

    short[] retVal = new short[](tokens.length);
    short depth = 0;
    foreach (i, ref t; tokens)
    {
        switch (t.value)
        {
        case TOK.leftBracket:
            depth++;
            goto case;
        case TOK.leftCurly:
        case TOK.leftParenthesis:
            depth++;
            break;
        case TOK.rightBracket:
            depth--;
            goto case;
        case TOK.rightCurly:
        case TOK.rightParenthesis:
            depth--;
            break;
        default:
            break;
        }
        retVal[i] = depth;
    }
    return cast(immutable) retVal;
}

struct TokenFormatter(OutputRange)
{
    /**
     * Params:
     *     rawSource = ?
     *     tokens = the tokens to format
     *     depths = ?
     *     output = the output range that the code will be formatted to
     *     astInformation = information about the AST used to inform formatting
     *         decisions.
     *     config = ?
     */
    this(const ubyte[] rawSource, const(Token)[] tokens, immutable short[] depths,
        OutputRange output, ASTInformation* astInformation, Config* config)
    {
        this.rawSource = rawSource;
        this.tokens = tokens;
        this.depths = depths;
        this.output = output;
        this.astInformation = astInformation;
        this.config = config;
        this.indents = IndentStack(config);

        {
            auto eol = config.end_of_line;
            if (eol == eol.cr)
                this.eolString = "\r";
            else if (eol == eol.lf)
                this.eolString = "\n";
            else if (eol == eol.crlf)
                this.eolString = "\r\n";
            else if (eol == eol._unspecified)
                assert(false, "config.end_of_line was unspecified");
            else
            {
                assert(eol == eol._default);
                this.eolString = eolStringFromInput;
            }
        }
    }

    /// Runs the formatting process
    void format()
    {
        while (hasCurrent)
            formatStep();
    }

private:

    /// Current indentation level
    int indentLevel;

    /// Current index into the tokens array
    size_t index;

    /// Length of the current line (so far)
    uint currentLineLength = 0;

    /// Output to write output to
    OutputRange output;

    /// Used for skipping parts of the file with `dfmt off` and `dfmt on` comments
    const ubyte[] rawSource;

    /// Tokens being formatted
    const Token[] tokens;

    /// Paren depth info
    immutable short[] depths;

    /// Information about the AST
    const ASTInformation* astInformation;

    /// Token indices where line breaks should be placed
    size_t[] linebreakHints;

    /// Current indentation stack for the file
    IndentStack indents;

    /// Configuration
    const Config* config;

    /// chached end of line string
    const string eolString;

    /// Keep track of whether or not an extra newline was just added because of
    /// an import statement.
    bool justAddedExtraNewline;

    /// Current paren depth
    int parenDepth;

    /// Current special brace depth. Used for struct initializers and lambdas.
    int sBraceDepth;

    /// Current non-indented brace depth. Used for struct initializers and lambdas.
    int niBraceDepth;

    /// True if a space should be placed when parenDepth reaches zero
    bool spaceAfterParens;

    /// True if we're in an ASM block
    bool inAsm;

    /// True if the next "this" should have a space behind it
    bool thisSpace;

    /// True if the next "else" should be formatted as a single line
    bool inlineElse;

    /// Tracks paren depth on a single line. This information can be used to
    /// indent array literals inside parens, since arrays are indented only once
    /// and paren indentation is ignored. Line breaks and "[" reset the counter.
    int parenDepthOnLine;

    string eolStringFromInput() const
    {
        import std.algorithm : countUntil;

        // Intentional wraparound, -1 turns into uint.max when not found:
        const firstCR = cast(uint) rawSource.countUntil("\r");
        if (firstCR < cast(uint) rawSource.countUntil("\n"))
            return firstCR == rawSource.countUntil("\r\n") ? "\r\n" : "\r";
        return "\n";
    }

    void formatStep()
    {
        return;

        /* import std.range : assumeSorted; */

        /* assert(hasCurrent); */
        /* if (currentIs(TOK.comment)) */
        /* { */
        /*     formatComment(); */
        /* } */
        /* else if (isStringLiteral(current.value) */
        /*     || isNumberLiteral(current.value) || currentIs(TOK.charLiteral)) */
        /* { */
        /*     writeToken(); */
        /*     if (hasCurrent) */
        /*     { */
        /*         immutable t = tokens[index].value; */
        /*         if (t == TOK.identifier || isStringLiteral(t) */
        /*             || isNumberLiteral(t) || t == TOK.charLiteral // a!"b" function() */
        /*             || t == TOK.function_ || t == TOK.delegate_) */
        /*             write(" "); */
        /*     } */
        /* } */
        /* else if (currentIs(TOK.module_) || currentIs(TOK.import_)) */
        /* { */
        /*     formatModuleOrImport(); */
        /* } */
        /* else if (currentIs(TOK.return_)) */
        /* { */
        /*     writeToken(); */
        /*     if (hasCurrent && (!currentIs(TOK.semicolon) && !currentIs(TOK.rightParenthesis) && !currentIs( */
        /*             TOK.leftCurly) */
        /*             && !currentIs(TOK.in_) && !currentIs(TOK.out_) && !currentIs(TOK.do_) */
        /*             && tokens[index].text != "body")) */
        /*         write(" "); */
        /* } */
        /* else if (currentIs(TOK.with_)) */
        /* { */
        /*     if (indents.length == 0 || !indents.topIsOneOf(TOK.switch_, TOK.with_)) */
        /*         indents.push(TOK.with_); */
        /*     writeToken(); */
        /*     if (config.dfmt_space_after_keywords) */
        /*     { */
        /*         write(" "); */
        /*     } */
        /*     if (hasCurrent && currentIs(TOK.leftParenthesis)) */
        /*         writeParens(false); */
        /*     if (hasCurrent && !currentIs(TOK.switch_) && !currentIs(TOK.with_) */
        /*         && !currentIs(TOK.leftCurly) && !(currentIs(TOK.final_) && peekIs(TOK.switch_))) */
        /*     { */
        /*         newline(); */
        /*     } */
        /*     else if (hasCurrent && !currentIs(TOK.leftCurly)) */
        /*     { */
        /*         write(" "); */
        /*     } */
        /* } */
        /* else if (currentIs(TOK.switch_)) */
        /* { */
        /*     formatSwitch(); */
        /* } */
        /* else if (currentIs(TOK.extern_) && peekIs(TOK.leftParenthesis)) */
        /* { */
        /*     writeToken(); */
        /*     write(" "); */
        /*     while (hasCurrent) */
        /*     { */
        /*         if (currentIs(TOK.leftParenthesis)) */
        /*             formatLeftParenOrBracket(); */
        /*         else if (currentIs(TOK.rightParenthesis)) */
        /*         { */
        /*             formatRightParen(); */
        /*             break; */
        /*         } */
        /*         else */
        /*             writeToken(); */
        /*     } */
        /* } */
        /* else if (((isBlockHeader() || currentIs(TOK.version_)) && peekIs(TOK.leftParenthesis)) */
        /*     || (currentIs(TOK.debug_) && peekIs(TOK.leftCurly))) */
        /* { */
        /*     if (!assumeSorted(astInformation.constraintLocations).equalRange(current.index).empty) */
        /*         formatConstraint(); */
        /*     else */
        /*         formatBlockHeader(); */
        /* } */
        /* else if ((current.text == "body" || current == TOK.do_) && peekBackIsFunctionDeclarationEnding()) */
        /* { */
        /*     formatKeyword(); */
        /* } */
        /* else if (currentIs(TOK.do_)) */
        /* { */
        /*     formatBlockHeader(); */
        /* } */
        /* else if (currentIs(TOK.else_)) */
        /* { */
        /*     formatElse(); */
        /* } */
        /* else if (currentIs(TOK.asm_)) */
        /* { */
        /*     formatKeyword(); */
        /*     while (hasCurrent && !currentIs(TOK.leftCurly)) */
        /*         formatStep(); */
        /*     if (hasCurrent) */
        /*     { */
        /*         int depth = 1; */
        /*         formatStep(); */
        /*         inAsm = true; */
        /*         while (hasCurrent && depth > 0) */
        /*         { */
        /*             if (currentIs(TOK.leftCurly)) */
        /*                 ++depth; */
        /*             else if (currentIs(TOK.rightCurly)) */
        /*                 --depth; */
        /*             formatStep(); */
        /*         } */
        /*         inAsm = false; */
        /*     } */
        /* } */
        /* else if (currentIs(TOK.this_)) */
        /* { */
        /*     const thisIndex = current.index; */
        /*     formatKeyword(); */
        /*     if (config.dfmt_space_before_function_parameters */
        /*         && (thisSpace || astInformation.constructorDestructorLocations */
        /*             .canFindIndex(thisIndex))) */
        /*     { */
        /*         write(" "); */
        /*         thisSpace = false; */
        /*     } */
        /* } */
        /* else if (isKeyword(current.value)) */
        /* { */
        /*     if (currentIs(TOK.debug_)) */
        /*         inlineElse = true; */
        /*     formatKeyword(); */
        /* } */
        /* else if (isBasicType(current.value)) */
        /* { */
        /*     writeToken(); */
        /*     if (hasCurrent && (currentIs(TOK.identifier) || isKeyword(current.value) || inAsm)) */
        /*         write(" "); */
        /* } */
        /* else if (isOperator(current.value)) */
        /* { */
        /*     formatOperator(); */
        /* } */
        /* else if (currentIs(TOK.identifier)) */
        /* { */
        /*     writeToken(); */
        /*     //dfmt off */
        /*     if (hasCurrent && ( currentIs(TOK.identifier) */
        /*             || ( index > 1 && config.dfmt_space_before_function_parameters */
        /*                 && ( isBasicType(peekBack(2).value) */
        /*                     || peekBack2Is(TOK.identifier) */
        /*                     || peekBack2Is(TOK.rightParenthesis) */
        /*                     || peekBack2Is(TOK.rightBracket) ) */
        /*                 && currentIs(TOK.leftParenthesis) */
        /*             || isBasicType(current.value) || currentIs(TOK.at) */
        /*             || isNumberLiteral(tokens[index].value) */
        /*             || (inAsm  && peekBack2Is(TOK.semicolon) && currentIs(TOK.leftBracket)) */
        /*     ))) */
        /*                            //dfmt on */
        /*     { */
        /*         write(" "); */
        /*     } */
        /* } */
        /* else if (currentIs(TOK.line)) */
        /* { */
        /*     writeToken(); */
        /*     newline(); */
        /* } */
        /* else */
        /*     writeToken(); */
    }

    /*     void formatConstraint() */
    /*     { */
    /*         import dfmt.editorconfig : OB = OptionalBoolean; */

    /*         with (TemplateConstraintStyle) final switch (config.dfmt_template_constraint_style) */
    /*         { */
    /*         case _unspecified: */
    /*             assert(false, "Config was not validated properly"); */
    /*         case conditional_newline: */
    /*             immutable l = currentLineLength + betweenParenLength(tokens[index + 1 .. $]); */
    /*             if (l > config.dfmt_soft_max_line_length) */
    /*                 newline(); */
    /*             else if (peekBackIs(TOK.rightParenthesis) || peekBackIs(TOK.identifier)) */
    /*                 write(" "); */
    /*             break; */
    /*         case always_newline: */
    /*             newline(); */
    /*             break; */
    /*         case conditional_newline_indent: */
    /*             immutable l = currentLineLength + betweenParenLength(tokens[index + 1 .. $]); */
    /*             if (l > config.dfmt_soft_max_line_length) */
    /*             { */
    /*                 config.dfmt_single_template_constraint_indent == OB.t ? */
    /*                     pushWrapIndent() : pushWrapIndent(TOK.not); */
    /*                 newline(); */
    /*             } */
    /*             else if (peekBackIs(TOK.rightParenthesis) || peekBackIs(TOK.identifier)) */
    /*                 write(" "); */
    /*             break; */
    /*         case always_newline_indent: */
    /*             { */
    /*                 config.dfmt_single_template_constraint_indent == OB.t ? */
    /*                     pushWrapIndent() : pushWrapIndent(TOK.not); */
    /*                 newline(); */
    /*             } */
    /*             break; */
    /*         } */
    /*         // if */
    /*         writeToken(); */
    /*         // assume that the parens are present, otherwise the parser would not */
    /*         // have told us there was a constraint here */
    /*         write(" "); */
    /*         writeParens(false); */
    /*     } */

    /*     string commentText(size_t i) */
    /*     { */
    /*         import std.string : strip; */

    /*         assert(tokens[i].value == TOK.comment); */
    /*         string commentText = tokens[i].text; */
    /*         if (commentText[0 .. 2] == "//") */
    /*             commentText = commentText[2 .. $]; */
    /*         else */
    /*         { */
    /*             if (commentText.length > 3) */
    /*                 commentText = commentText[2 .. $ - 2]; */
    /*             else */
    /*                 commentText = commentText[2 .. $]; */
    /*         } */
    /*         return commentText.strip(); */
    /*     } */

    /*     void skipFormatting() */
    /*     { */
    /*         size_t dfmtOff = index; */
    /*         size_t dfmtOn = index; */
    /*         foreach (i; dfmtOff + 1 .. tokens.length) */
    /*         { */
    /*             dfmtOn = i; */
    /*             if (tokens[i].value != TOK.comment) */
    /*                 continue; */
    /*             immutable string commentText = commentText(i); */
    /*             if (commentText == "dfmt on") */
    /*                 break; */
    /*         } */
    /*         write(cast(string) rawSource[tokens[dfmtOff].index .. tokens[dfmtOn].index]); */
    /*         index = dfmtOn; */
    /*     } */

    /*     void formatComment() */
    /*     { */
    /*         if (commentText(index) == "dfmt off") */
    /*         { */
    /*             skipFormatting(); */
    /*             return; */
    /*         } */

    /*         immutable bool currIsSlashSlash = tokens[index].text[0 .. 2] == "//"; */
    /*         immutable prevTokenEndLine = index == 0 ? size_t.max : tokenEndLine(tokens[index - 1]); */
    /*         immutable size_t currTokenLine = tokens[index].line; */
    /*         if (index > 0) */
    /*         { */
    /*             immutable t = tokens[index - 1].value; */
    /*             immutable canAddNewline = currTokenLine - prevTokenEndLine < 1; */
    /*             if (peekBackIsOperator() && !isSeparationToken(t)) */
    /*                 pushWrapIndent(t); */
    /*             else if (peekBackIs(TOK.comma) && prevTokenEndLine == currTokenLine */
    /*                 && indents.indentToMostRecent(TOK.enum_) == -1) */
    /*                 pushWrapIndent(TOK.comma); */
    /*             if (peekBackIsOperator() && !peekBackIsOneOf(false, TOK.comment, */
    /*                     TOK.leftCurly, TOK.rightCurly, TOK.colon, TOK.semicolon, TOK.comma, TOK.leftBracket, TOK */
    /*                     .leftParenthesis) */
    /*                 && !canAddNewline && prevTokenEndLine < currTokenLine) */
    /*                 write(" "); */
    /*             else if (prevTokenEndLine == currTokenLine || (t == TOK.rightParenthesis && peekIs( */
    /*                     TOK.leftCurly))) */
    /*                 write(" "); */
    /*             else if (peekBackIsOneOf(false, TOK.else_, TOK.identifier)) */
    /*                 write(" "); */
    /*             else if (canAddNewline || (peekIs(TOK.leftCurly) && t == TOK.rightCurly)) */
    /*                 newline(); */

    /*             if (peekIs(TOK.leftParenthesis) && (peekBackIs(TOK.rightParenthesis) || peekBack2Is( */
    /*                     TOK.not))) */
    /*                 pushWrapIndent(TOK.leftParenthesis); */

    /*             if (peekIs(TOK.dot) && !indents.topIs(TOK.dot)) */
    /*                 indents.push(TOK.dot); */
    /*         } */
    /*         writeToken(); */
    /*         immutable j = justAddedExtraNewline; */
    /*         if (currIsSlashSlash) */
    /*         { */
    /*             newline(); */
    /*             justAddedExtraNewline = j; */
    /*         } */
    /*         else if (hasCurrent) */
    /*         { */
    /*             if (prevTokenEndLine == tokens[index].line) */
    /*             { */
    /*                 if (currentIs(TOK.rightCurly)) */
    /*                 { */
    /*                     if (indents.topIs(TOK.leftCurly)) */
    /*                         indents.pop(); */
    /*                     write(" "); */
    /*                 } */
    /*                 else if (!currentIs(TOK.leftCurly)) */
    /*                     write(" "); */
    /*             } */
    /*             else if (!currentIs(TOK.leftCurly) && !currentIs(TOK.in_) && !currentIs(TOK.out_)) */
    /*             { */
    /*                 if (currentIs(TOK.rightParenthesis) && indents.topIs(TOK.comma)) */
    /*                     indents.pop(); */
    /*                 else if (peekBack2Is(TOK.comma) && !indents.topIs(TOK.comma) */
    /*                     && indents.indentToMostRecent(TOK.enum_) == -1) */
    /*                     pushWrapIndent(TOK.comma); */
    /*                 newline(); */
    /*             } */
    /*         } */
    /*         else */
    /*             newline(); */
    /*     } */

    /*     void formatModuleOrImport() */
    /*     { */
    /*         immutable t = current.value; */
    /*         writeToken(); */
    /*         if (currentIs(TOK.leftParenthesis)) */
    /*         { */
    /*             writeParens(false); */
    /*             return; */
    /*         } */
    /*         write(" "); */
    /*         while (hasCurrent) */
    /*         { */
    /*             if (currentIs(TOK.semicolon)) */
    /*             { */
    /*                 indents.popWrapIndents(); */
    /*                 indentLevel = indents.indentLevel; */
    /*                 writeToken(); */
    /*                 if (index >= tokens.length) */
    /*                 { */
    /*                     newline(); */
    /*                     break; */
    /*                 } */
    /*                 if (currentIs(TOK.comment) && current.line == peekBack().line) */
    /*                 { */
    /*                     break; */
    /*                 } */
    /*                 else if (currentIs(TOK.leftCurly) && config.dfmt_brace_style == BraceStyle.allman) */
    /*                     break; */
    /*                 else if (t == TOK.import_ && !currentIs(TOK.import_) */
    /*                     && !currentIs(TOK.rightCurly) */
    /*                     && !((currentIs(TOK.public_) */
    /*                         || currentIs(TOK.private_) */
    /*                         || currentIs(TOK.static_)) */
    /*                         && peekIs(TOK.import_)) && !indents.topIsOneOf(TOK.if_, */
    /*                         TOK.debug_, TOK.version_)) */
    /*                 { */
    /*                     simpleNewline(); */
    /*                     currentLineLength = 0; */
    /*                     justAddedExtraNewline = true; */
    /*                     newline(); */
    /*                 } */
    /*                 else */
    /*                     newline(); */
    /*                 break; */
    /*             } */
    /*             else if (currentIs(TOK.colon)) */
    /*             { */
    /*                 if (config.dfmt_selective_import_space) */
    /*                     write(" "); */
    /*                 writeToken(); */
    /*                 if (!currentIs(TOK.comment)) */
    /*                     write(" "); */
    /*                 pushWrapIndent(TOK.comma); */
    /*             } */
    /*             else if (currentIs(TOK.comment)) */
    /*             { */
    /*                 if (peekBack.line != current.line) */
    /*                 { */
    /*                     // The comment appears on its own line, keep it there. */
    /*                     if (!peekBackIs(TOK.comment)) // Comments are already properly separated. */
    /*                         newline(); */
    /*                 } */
    /*                 formatStep(); */
    /*             } */
    /*             else */
    /*                 formatStep(); */
    /*         } */
    /*     } */

    /*     void formatLeftParenOrBracket() */
    /*     in */
    /*     { */
    /*         assert(currentIs(TOK.leftParenthesis) || currentIs(TOK.leftBracket)); */
    /*     } */
    /*     do */
    /*     { */
    /*         import dfmt.editorconfig : OptionalBoolean; */

    /*         immutable p = current.value; */
    /*         regenLineBreakHintsIfNecessary(index); */
    /*         writeToken(); */
    /*         if (p == TOK.leftParenthesis) */
    /*         { */
    /*             ++parenDepthOnLine; */
    /*             // If the file starts with an open paren, just give up. This isn't */
    /*             // valid D code. */
    /*             if (index < 2) */
    /*                 return; */
    /*             if (isBlockHeaderToken(tokens[index - 2].value)) */
    /*                 indents.push(TOK.rightParenthesis); */
    /*             else */
    /*                 indents.push(p); */
    /*             spaceAfterParens = true; */
    /*             parenDepth++; */
    /*         } */
    /*         // No heuristics apply if we can't look before the opening paren/bracket */
    /*         if (index < 1) */
    /*             return; */
    /*         immutable bool arrayInitializerStart = p == TOK.leftBracket */
    /*             && astInformation.arrayStartLocations.canFindIndex(tokens[index - 1].index); */

    /*         if (arrayInitializerStart && isMultilineAt(index - 1)) */
    /*         { */
    /*             revertParenIndentation(); */

    /*             // Use the close bracket as the indent token to distinguish */
    /*             // the array initialiazer from an array index in the newline */
    /*             // handling code */
    /*             IndentStack.Details detail; */
    /*             detail.wrap = false; */
    /*             detail.temp = false; */

    /*             // wrap and temp are set manually to the values it would actually */
    /*             // receive here because we want to set breakEveryItem for the ] token to know if */
    /*             // we should definitely always new-line after every comma for a big AA */
    /*             detail.breakEveryItem = astInformation.assocArrayStartLocations.canFindIndex( */
    /*                 tokens[index - 1].index); */
    /*             detail.preferLongBreaking = true; */

    /*             indents.push(TOK.rightBracket, detail); */
    /*             newline(); */
    /*             immutable size_t j = expressionEndIndex(index); */
    /*             linebreakHints = chooseLineBreakTokens(index, tokens[index .. j], */
    /*                 depths[index .. j], config, currentLineLength, indentLevel); */
    /*         } */
    /*         else if (p == TOK.leftBracket && config.dfmt_keep_line_breaks == OptionalBoolean.t) */
    /*         { */
    /*             revertParenIndentation(); */
    /*             IndentStack.Details detail; */

    /*             detail.wrap = false; */
    /*             detail.temp = false; */
    /*             detail.breakEveryItem = false; */
    /*             detail.mini = tokens[index].line == tokens[index - 1].line; */

    /*             indents.push(TOK.rightBracket, detail); */
    /*             if (!detail.mini) */
    /*             { */
    /*                 newline(); */
    /*             } */
    /*         } */
    /*         else if (arrayInitializerStart) */
    /*         { */
    /*             // This is a short (non-breaking) array/AA value */
    /*             IndentStack.Details detail; */
    /*             detail.wrap = false; */
    /*             detail.temp = false; */

    /*             detail.breakEveryItem = astInformation.assocArrayStartLocations.canFindIndex( */
    /*                 tokens[index - 1].index); */
    /*             // array of (possibly associative) array, let's put each item on its own line */
    /*             if (!detail.breakEveryItem && currentIs(TOK.leftBracket)) */
    /*                 detail.breakEveryItem = true; */

    /*             // the '[' is immediately followed by an item instead of a newline here so */
    /*             // we set mini, that the ']' also follows an item immediately without newline. */
    /*             detail.mini = true; */

    /*             indents.push(TOK.rightBracket, detail); */
    /*         } */
    /*         else if (p == TOK.leftBracket) */
    /*         { */
    /*             // array item access */
    /*             IndentStack.Details detail; */
    /*             detail.wrap = false; */
    /*             detail.temp = true; */
    /*             detail.mini = true; */
    /*             indents.push(TOK.rightBracket, detail); */
    /*         } */
    /*         else if (!currentIs(TOK.rightParenthesis) && !currentIs(TOK.rightBracket) */
    /*             && (linebreakHints.canFindIndex(index - 1) || (linebreakHints.length == 0 */
    /*                 && currentLineLength > config.max_line_length))) */
    /*         { */
    /*             newline(); */
    /*         } */
    /*         else if (onNextLine) */
    /*         { */
    /*             newline(); */
    /*         } */
    /*     } */

    /*     void revertParenIndentation() */
    /*     { */
    /*         import std.algorithm.searching : canFind, until; */

    /*         if (tokens[index .. $].until!(tok => tok.line != current.line) */
    /*             .canFind!(x => x.value == TOK.rightBracket)) */
    /*         { */
    /*             return; */
    /*         } */
    /*         if (parenDepthOnLine) */
    /*         { */
    /*             foreach (i; 0 .. parenDepthOnLine) */
    /*             { */
    /*                 indents.pop(); */
    /*             } */
    /*         } */
    /*         parenDepthOnLine = 0; */
    /*     } */

    /*     void formatRightParen() */
    /*     in */
    /*     { */
    /*         assert(currentIs(TOK.rightParenthesis)); */
    /*     } */
    /*     do */
    /*     { */
    /*         parenDepthOnLine = max(parenDepthOnLine - 1, 0); */
    /*         parenDepth--; */
    /*         indents.popWrapIndents(); */
    /*         while (indents.topIsOneOf(TOK.not, TOK.rightParenthesis)) */
    /*             indents.pop(); */
    /*         if (indents.topIs(TOK.leftParenthesis)) */
    /*             indents.pop(); */
    /*         if (indents.topIs(TOK.dot)) */
    /*             indents.pop(); */

    /*         if (onNextLine) */
    /*         { */
    /*             newline(); */
    /*         } */
    /*         if (parenDepth == 0 && (peekIs(TOK.is_) || peekIs(TOK.in_) */
    /*                 || peekIs(TOK.out_) || peekIs(TOK.do_) || peekIsBody)) */
    /*         { */
    /*             writeToken(); */
    /*         } */
    /*         else if (peekIsLiteralOrIdent() || peekIsBasicType()) */
    /*         { */
    /*             writeToken(); */
    /*             if (spaceAfterParens || parenDepth > 0) */
    /*                 writeSpace(); */
    /*         } */
    /*         else if ((peekIsKeyword() || peekIs(TOK.at)) && spaceAfterParens */
    /*             && !peekIs(TOK.in_) && !peekIs(TOK.is_) && !peekIs(TOK.if_)) */
    /*         { */
    /*             writeToken(); */
    /*             writeSpace(); */
    /*         } */
    /*         else */
    /*             writeToken(); */
    /*     } */

    /*     void formatRightBracket() */
    /*     in */
    /*     { */
    /*         assert(currentIs(TOK.rightBracket)); */
    /*     } */
    /*     do */
    /*     { */
    /*         indents.popWrapIndents(); */
    /*         if (indents.topIs(TOK.rightBracket)) */
    /*         { */
    /*             if (!indents.topDetails.mini && !indents.topDetails.temp) */
    /*                 newline(); */
    /*             else */
    /*                 indents.pop(); */
    /*         } */
    /*         writeToken(); */
    /*         if (currentIs(TOK.identifier)) */
    /*             write(" "); */
    /*     } */

    /*     void formatAt() */
    /*     { */
    /*         immutable size_t atIndex = tokens[index].index; */
    /*         writeToken(); */
    /*         if (currentIs(TOK.identifier)) */
    /*             writeToken(); */
    /*         if (currentIs(TOK.leftParenthesis)) */
    /*         { */
    /*             writeParens(false); */
    /*             if (tokens[index].value == TOK.leftCurly) */
    /*                 return; */

    /*             if (hasCurrent && tokens[index - 1].line < tokens[index].line */
    /*                 && astInformation.atAttributeStartLocations.canFindIndex(atIndex)) */
    /*                 newline(); */
    /*             else */
    /*                 write(" "); */
    /*         } */
    /*         else if (hasCurrent && (currentIs(TOK.at) */
    /*                 || isBasicType(tokens[index].value) */
    /*                 || currentIs(TOK.invariant_) */
    /*                 || currentIs(TOK.extern_) */
    /*                 || currentIs(TOK.identifier)) */
    /*             && !currentIsIndentedTemplateConstraint()) */
    /*         { */
    /*             writeSpace(); */
    /*         } */
    /*     } */

    /*     void formatColon() */
    /*     { */
    /*         import dfmt.editorconfig : OptionalBoolean; */
    /*         import std.algorithm : canFind, any; */

    /*         immutable bool isCase = astInformation.caseEndLocations.canFindIndex(current.index); */
    /*         immutable bool isAttribute = astInformation.attributeDeclarationLines.canFindIndex( */
    /*             current.line); */
    /*         immutable bool isStructInitializer = astInformation.structInfoSortedByEndLocation */
    /*             .canFind!(st => st.startLocation < current.index && current.index < st.endLocation); */

    /*         if (isCase || isAttribute) */
    /*         { */
    /*             writeToken(); */
    /*             if (!currentIs(TOK.leftCurly)) */
    /*             { */
    /*                 if (isCase && !indents.topIs(TOK.case_) */
    /*                     && config.dfmt_align_switch_statements == OptionalBoolean.f) */
    /*                     indents.push(TOK.case_); */
    /*                 else if (isAttribute && !indents.topIs(TOK.at) */
    /*                     && config.dfmt_outdent_attributes == OptionalBoolean.f) */
    /*                     indents.push(TOK.at); */
    /*                 newline(); */
    /*             } */
    /*         } */
    /*         else if (indents.topIs(TOK.rightBracket)) // Associative array */
    /*         { */
    /*             write(config.dfmt_space_before_aa_colon ? " : " : ": "); */
    /*             ++index; */
    /*         } */
    /*         else if (peekBackIs(TOK.identifier) */
    /*             && [ */
    /*                 TOK.leftCurly, TOK.rightCurly, TOK.semicolon, TOK.colon, TOK.comma */
    /*             ] */
    /*                 .any!((ptrdiff_t token) => peekBack2Is(cast(TOK) token, true)) */
    /*             && (!isBlockHeader(1) || peekIs(TOK.if_))) */
    /*         { */
    /*             writeToken(); */
    /*             if (isStructInitializer) */
    /*                 write(" "); */
    /*             else if (!currentIs(TOK.leftCurly)) */
    /*                 newline(); */
    /*         } */
    /*         else */
    /*         { */
    /*             regenLineBreakHintsIfNecessary(index); */
    /*             if (peekIs(TOK.slice)) */
    /*                 writeToken(); */
    /*             else if (isBlockHeader(1) && !peekIs(TOK.if_)) */
    /*             { */
    /*                 writeToken(); */
    /*                 if (config.dfmt_compact_labeled_statements) */
    /*                     write(" "); */
    /*                 else */
    /*                     newline(); */
    /*             } */
    /*             else if (linebreakHints.canFindIndex(index)) */
    /*             { */
    /*                 pushWrapIndent(); */
    /*                 newline(); */
    /*                 writeToken(); */
    /*                 write(" "); */
    /*             } */
    /*             else */
    /*             { */
    /*                 write(" : "); */
    /*                 index++; */
    /*             } */
    /*         } */
    /*     } */

    /*     void formatSemicolon() */
    /*     { */
    /*         if (inlineElse && !peekIs(TOK.else_)) */
    /*             inlineElse = false; */

    /*         if ((parenDepth > 0 && sBraceDepth == 0) || (sBraceDepth > 0 && niBraceDepth > 0)) */
    /*         { */
    /*             if (currentLineLength > config.dfmt_soft_max_line_length) */
    /*             { */
    /*                 writeToken(); */
    /*                 pushWrapIndent(TOK.semicolon); */
    /*                 newline(); */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (!(peekIs(TOK.semicolon) || peekIs(TOK.rightParenthesis) || peekIs( */
    /*                         TOK.rightCurly))) */
    /*                     write("; "); */
    /*                 else */
    /*                     write(";"); */
    /*                 index++; */
    /*             } */
    /*         } */
    /*         else */
    /*         { */
    /*             writeToken(); */
    /*             indents.popWrapIndents(); */
    /*             linebreakHints = []; */
    /*             while (indents.topIsOneOf(TOK.enum_, TOK.try_, TOK.catch_, TOK.finally_, TOK.debug_)) */
    /*                 indents.pop(); */
    /*             if (indents.topAre(TOK.static_, TOK.else_)) */
    /*             { */
    /*                 indents.pop(); */
    /*                 indents.pop(); */
    /*             } */
    /*             indentLevel = indents.indentLevel; */
    /*             if (config.dfmt_brace_style == BraceStyle.allman) */
    /*             { */
    /*                 if (!currentIs(TOK.leftCurly)) */
    /*                     newline(); */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (currentIs(TOK.leftCurly)) */
    /*                     indents.popTempIndents(); */
    /*                 indentLevel = indents.indentLevel; */
    /*                 newline(); */
    /*             } */
    /*         } */
    /*     } */

    /*     void formatLeftBrace() */
    /*     { */
    /*         import std.algorithm : map, sum, canFind; */

    /*         auto tIndex = tokens[index].index; */

    /*         if (astInformation.structInitStartLocations.canFindIndex(tIndex)) */
    /*         { */
    /*             sBraceDepth++; */
    /*             immutable bool multiline = isMultilineAt(index); */
    /*             writeToken(); */
    /*             if (multiline) */
    /*             { */
    /*                 import std.algorithm.searching : find; */

    /*                 auto indentInfo = astInformation.indentInfoSortedByEndLocation */
    /*                     .find!((a, b) => a.startLocation == b)(tIndex); */
    /*                 assert(indentInfo.length > 0); */
    /*                 cast() indentInfo[0].flags |= BraceIndentInfoFlags.tempIndent; */
    /*                 cast() indentInfo[0].beginIndentLevel = indents.indentLevel; */

    /*                 indents.push(TOK.leftCurly); */
    /*                 newline(); */
    /*             } */
    /*             else */
    /*                 niBraceDepth++; */
    /*         } */
    /*         else if (astInformation.funLitStartLocations.canFindIndex(tIndex)) */
    /*         { */
    /*             indents.popWrapIndents(); */

    /*             sBraceDepth++; */
    /*             if (peekBackIsOneOf(true, TOK.rightParenthesis, TOK.identifier)) */
    /*                 write(" "); */
    /*             immutable bool multiline = isMultilineAt(index); */
    /*             writeToken(); */
    /*             if (multiline) */
    /*             { */
    /*                 indents.push(TOK.leftCurly); */
    /*                 newline(); */
    /*             } */
    /*             else */
    /*             { */
    /*                 niBraceDepth++; */
    /*                 if (!currentIs(TOK.rightCurly)) */
    /*                     write(" "); */
    /*             } */
    /*         } */
    /*         else */
    /*         { */
    /*             if (peekBackIsSlashSlash()) */
    /*             { */
    /*                 if (peekBack2Is(TOK.semicolon)) */
    /*                 { */
    /*                     indents.popTempIndents(); */
    /*                     indentLevel = indents.indentLevel - 1; */
    /*                 } */
    /*                 writeToken(); */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (indents.topIsTemp && indents.indentToMostRecent(TOK.static_) == -1) */
    /*                     indentLevel = indents.indentLevel - 1; */
    /*                 else */
    /*                     indentLevel = indents.indentLevel; */
    /*                 if (config.dfmt_brace_style == BraceStyle.allman */
    /*                     || peekBackIsOneOf(true, TOK.leftCurly, TOK.rightCurly)) */
    /*                     newline(); */
    /*                 else if (config.dfmt_brace_style == BraceStyle.knr */
    /*                     && astInformation.funBodyLocations.canFindIndex(tIndex) */
    /*                     && (peekBackIs(TOK.rightParenthesis) || (!peekBackIs(TOK.do_) && peekBack().text != "body"))) */
    /*                     newline(); */
    /*                 else if (!peekBackIsOneOf(true, TOK.leftCurly, TOK.rightCurly, TOK.semicolon)) */
    /*                     write(" "); */
    /*                 writeToken(); */
    /*             } */
    /*             indents.push(TOK.leftCurly); */
    /*             if (!currentIs(TOK.leftCurly)) */
    /*                 newline(); */
    /*             linebreakHints = []; */
    /*         } */
    /*     } */

    /*     void formatRightBrace() */
    /*     { */
    /*         void popToBeginIndent(BraceIndentInfo indentInfo) */
    /*         { */
    /*             foreach (i; indentInfo.beginIndentLevel .. indents.indentLevel) */
    /*             { */
    /*                 indents.pop(); */
    /*             } */

    /*             indentLevel = indentInfo.beginIndentLevel; */
    /*         } */

    /*         size_t pos; */
    /*         if (astInformation.structInitEndLocations.canFindIndex(tokens[index].index, &pos)) */
    /*         { */
    /*             if (sBraceDepth > 0) */
    /*                 sBraceDepth--; */
    /*             if (niBraceDepth > 0) */
    /*                 niBraceDepth--; */

    /*             auto indentInfo = astInformation.indentInfoSortedByEndLocation[pos]; */
    /*             if (indentInfo.flags & BraceIndentInfoFlags.tempIndent) */
    /*             { */
    /*                 popToBeginIndent(indentInfo); */
    /*                 simpleNewline(); */
    /*                 indent(); */
    /*             } */
    /*             writeToken(); */
    /*         } */
    /*         else if (astInformation.funLitEndLocations.canFindIndex(tokens[index].index, &pos)) */
    /*         { */
    /*             if (niBraceDepth > 0) */
    /*             { */
    /*                 if (!peekBackIsSlashSlash() && !peekBackIs(TOK.leftCurly)) */
    /*                     write(" "); */
    /*                 niBraceDepth--; */
    /*             } */
    /*             if (sBraceDepth > 0) */
    /*                 sBraceDepth--; */
    /*             writeToken(); */
    /*         } */
    /*         else */
    /*         { */
    /*             // Silly hack to format enums better. */
    /*             if ((peekBackIsLiteralOrIdent() || peekBackIsOneOf(true, TOK.rightParenthesis, */
    /*                     TOK.comma)) && !peekBackIsSlashSlash()) */
    /*                 newline(); */
    /*             write("}"); */
    /*             if (index + 1 < tokens.length */
    /*                 && astInformation.doubleNewlineLocations.canFindIndex(tokens[index].index) */
    /*                 && !peekIs(TOK.rightCurly) && !peekIs(TOK.else_) */
    /*                 && !peekIs(TOK.semicolon) && !peekIs(TOK.comment, false)) */
    /*             { */
    /*                 simpleNewline(); */
    /*                 currentLineLength = 0; */
    /*                 justAddedExtraNewline = true; */
    /*             } */
    /*             if (config.dfmt_brace_style.among(BraceStyle.otbs, BraceStyle.knr) */
    /*                 && ((peekIs(TOK.else_) */
    /*                     && !indents.topAre(TOK.static_, TOK.if_) */
    /*                     && !indents.topIs(TOK.foreach_) && !indents.topIs(TOK.for_) */
    /*                     && !indents.topIs(TOK.while_) && !indents.topIs(TOK.do_)) */
    /*                     || peekIs(TOK.catch_) || peekIs(TOK.finally_))) */
    /*             { */
    /*                 write(" "); */
    /*                 index++; */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (!peekIs(TOK.comma) && !peekIs(TOK.rightParenthesis) */
    /*                     && !peekIs(TOK.semicolon) && !peekIs(TOK.leftCurly)) */
    /*                 { */
    /*                     index++; */
    /*                     if (indents.topIs(TOK.static_)) */
    /*                         indents.pop(); */
    /*                     newline(); */
    /*                 } */
    /*                 else */
    /*                     index++; */
    /*             } */
    /*         } */
    /*     } */

    /*     void formatSwitch() */
    /*     { */
    /*         while (indents.topIs(TOK.with_)) */
    /*             indents.pop(); */
    /*         indents.push(TOK.switch_); */
    /*         writeToken(); // switch */
    /*         if (config.dfmt_space_after_keywords) */
    /*         { */
    /*             write(" "); */
    /*         } */
    /*     } */

    /*     void formatBlockHeader() */
    /*     { */
    /*         if (indents.topIs(TOK.not)) */
    /*             indents.pop(); */
    /*         immutable bool a = !currentIs(TOK.version_) && !currentIs(TOK.debug_); */
    /*         immutable bool b = a */
    /*             || astInformation.conditionalWithElseLocations.canFindIndex(current.index); */
    /*         immutable bool c = b */
    /*             || astInformation.conditionalStatementLocations.canFindIndex(current.index); */
    /*         immutable bool shouldPushIndent = (c || peekBackIs(TOK.else_)) */
    /*             && !(currentIs(TOK.if_) && indents.topIsWrap()); */
    /*         if (currentIs(TOK.out_) && !peekBackIs(TOK.rightCurly)) */
    /*             newline(); */
    /*         if (shouldPushIndent) */
    /*         { */
    /*             if (peekBackIs(TOK.static_)) */
    /*             { */
    /*                 if (indents.topIs(TOK.else_)) */
    /*                     indents.pop(); */
    /*                 if (!indents.topIs(TOK.static_)) */
    /*                     indents.push(TOK.static_); */
    /*             } */
    /*             indents.push(current.value); */
    /*         } */
    /*         writeToken(); */

    /*         if (currentIs(TOK.leftParenthesis)) */
    /*         { */
    /*             if (config.dfmt_space_after_keywords) */
    /*             { */
    /*                 write(" "); */
    /*             } */
    /*             writeParens(false); */
    /*         } */

    /*         if (hasCurrent) */
    /*         { */
    /*             if (currentIs(TOK.switch_) || (currentIs(TOK.final_) && peekIs(TOK.switch_))) */
    /*             { */
    /*                 if (config.dfmt_space_after_keywords) */
    /*                 { */
    /*                     write(" "); */
    /*                 } */
    /*             } */
    /*             else if (currentIs(TOK.comment)) */
    /*             { */
    /*                 formatStep(); */
    /*             } */
    /*             else if (!shouldPushIndent) */
    /*             { */
    /*                 if (!currentIs(TOK.leftCurly) && !currentIs(TOK.semicolon)) */
    /*                     write(" "); */
    /*             } */
    /*             else if (hasCurrent && !currentIs(TOK.leftCurly) && !currentIs(TOK.semicolon) && !currentIs(TOK.in_) && */
    /*                 !currentIs(TOK.out_) && !currentIs(TOK.do_) && current.text != "body") */
    /*             { */
    /*                 newline(); */
    /*             } */
    /*             else if (currentIs(TOK.leftCurly) && indents.topAre(tok.static_, TOK.if_)) */
    /*             { */
    /*                 // Hacks to format braced vs non-braced static if declarations. */
    /*                 indents.pop(); */
    /*                 indents.pop(); */
    /*                 indents.push(TOK.if_); */
    /*                 formatLeftBrace(); */
    /*             } */
    /*             else if (currentIs(TOK.leftCurly) && indents.topAre(TOK.static_, TOK.foreach_)) */
    /*             { */
    /*                 indents.pop(); */
    /*                 indents.pop(); */
    /*                 indents.push(TOK.foreach_); */
    /*                 formatLeftBrace(); */
    /*             } */
    /*             else if (currentIs(TOK.leftCurly) && indents.topAre(TOK.static_, TOK.foreach_reverse_)) */
    /*             { */
    /*                 indents.pop(); */
    /*                 indents.pop(); */
    /*                 indents.push(TOK.foreach_reverse_); */
    /*                 formatLeftBrace(); */
    /*             } */
    /*         } */
    /*     } */

    /*     void formatElse() */
    /*     { */
    /*         writeToken(); */
    /*         if (inlineElse || currentIs(TOK.if_) || currentIs(TOK.version_) */
    /*             || (currentIs(TOK.static_) && peekIs(TOK.if_))) */
    /*         { */
    /*             if (indents.topIs(TOK.if_) || indents.topIs(TOK.version_)) */
    /*                 indents.pop(); */
    /*             inlineElse = false; */
    /*             write(" "); */
    /*         } */
    /*         else if (currentIs(TOK.colon)) */
    /*         { */
    /*             writeToken(); */
    /*             newline(); */
    /*         } */
    /*         else if (!currentIs(TOK.leftCurly) && !currentIs(TOK.comment)) */
    /*         { */
    /*             //indents.dump(); */
    /*             while (indents.topIsOneOf(TOK.foreach_, TOK.for_, TOK.while_)) */
    /*                 indents.pop(); */
    /*             if (indents.topIsOneOf(TOK.if_, TOK.version_)) */
    /*                 indents.pop(); */
    /*             indents.push(TOK.else_); */
    /*             newline(); */
    /*         } */
    /*         else if (currentIs(TOK.leftCurly) && indents.topAre(TOK.static_, TOK.if_)) */
    /*         { */
    /*             indents.pop(); */
    /*             indents.pop(); */
    /*             indents.push(TOK.else_); */
    /*         } */
    /*     } */

    /*     void formatKeyword() */
    /*     { */
    /*         import dfmt.editorconfig : OptionalBoolean; */

    /*         switch (current.value) */
    /*         { */
    /*         case TOK.default_: */
    /*             writeToken(); */
    /*             break; */
    /*         case TOK.cast_: */
    /*             writeToken(); */
    /*             if (hasCurrent && currentIs(TOK.leftParenthesis)) */
    /*                 writeParens(config.dfmt_space_after_cast == OptionalBoolean.t); */
    /*             break; */
    /*         case TOK.out_: */
    /*             if (!peekBackIsSlashSlash) */
    /*             { */
    /*                 if (!peekBackIs(TOK.rightCurly) */
    /*                     && astInformation.contractLocations.canFindIndex(current.index)) */
    /*                     newline(); */
    /*                 else if (peekBackIsKeyword) */
    /*                     write(" "); */
    /*             } */
    /*             writeToken(); */
    /*             if (hasCurrent && !currentIs(TOK.leftCurly) && !currentIs(TOK.comment)) */
    /*                 write(" "); */
    /*             break; */
    /*         case TOK.try_: */
    /*         case TOK.finally_: */
    /*             indents.push(current.value); */
    /*             writeToken(); */
    /*             if (hasCurrent && !currentIs(TOK.leftCurly)) */
    /*                 newline(); */
    /*             break; */
    /*         case TOK.identifier: */
    /*             if (current.text == "body") */
    /*                 goto case TOK.do_; */
    /*             else */
    /*                 goto default; */
    /*         case TOK.do_: */
    /*             if (!peekBackIs(TOK.rightCurly)) */
    /*                 newline(); */
    /*             writeToken(); */
    /*             break; */
    /*         case TOK.in_: */
    /*             immutable isContract = astInformation.contractLocations.canFindIndex(current.index); */
    /*             if (!peekBackIsSlashSlash) */
    /*             { */
    /*                 if (isContract) */
    /*                 { */
    /*                     indents.popTempIndents(); */
    /*                     newline(); */
    /*                 } */
    /*                 else if (!peekBackIsOneOf(false, TOK.leftParenthesis, TOK.comma, TOK.not)) */
    /*                     write(" "); */
    /*             } */
    /*             writeToken(); */
    /*             if (!hasCurrent) */
    /*                 return; */
    /*             immutable isFunctionLit = astInformation.funLitStartLocations.canFindIndex( */
    /*                 current.index); */
    /*             if (isFunctionLit && config.dfmt_brace_style == BraceStyle.allman) */
    /*                 newline(); */
    /*             else if (!isContract || currentIs(TOK.leftParenthesis)) */
    /*                 write(" "); */
    /*             break; */
    /*         case TOK.is_: */
    /*             if (!peekBackIsOneOf(false, TOK.not, TOK.leftParenthesis, TOK.comma, */
    /*                     TOK.rightCurly, TOK.assign, TOK.andAnd, TOK.orOr) && !peekBackIsKeyword()) */
    /*                 write(" "); */
    /*             writeToken(); */
    /*             if (hasCurrent && !currentIs(TOK.leftParenthesis) && !currentIs(TOK.leftCurly) && !currentIs( */
    /*                     TOK.comment)) */
    /*                 write(" "); */
    /*             break; */
    /*         case TOK.case_: */
    /*             writeToken(); */
    /*             if (hasCurrent && !currentIs(TOK.semicolon)) */
    /*                 write(" "); */
    /*             break; */
    /*         case TOK.enum_: */
    /*             if (peekIs(TOK.rightParenthesis) || peekIs(TOK.equal)) */
    /*             { */
    /*                 writeToken(); */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (peekBackIs(TOK.identifier)) */
    /*                     write(" "); */
    /*                 indents.push(TOK.enum_); */
    /*                 writeToken(); */
    /*                 if (hasCurrent && !currentIs(TOK.colon) && !currentIs(TOK.leftCurly)) */
    /*                     write(" "); */
    /*             } */
    /*             break; */
    /*         case TOK.static_: */
    /*             { */
    /*                 if (astInformation.staticConstructorDestructorLocations */
    /*                     .canFindIndex(current.index)) */
    /*                 { */
    /*                     thisSpace = true; */
    /*                 } */
    /*             } */
    /*             goto default; */
    /*         case TOK.shared_: */
    /*             { */
    /*                 if (astInformation.sharedStaticConstructorDestructorLocations */
    /*                     .canFindIndex(current.index)) */
    /*                 { */
    /*                     thisSpace = true; */
    /*                 } */
    /*             } */
    /*             goto default; */
    /*         case TOK.invariant_: */
    /*             writeToken(); */
    /*             if (hasCurrent && currentIs(TOK.leftParenthesis)) */
    /*                 write(" "); */
    /*             break; */
    /*         default: */
    /*             if (peekBackIs(TOK.identifier)) */
    /*             { */
    /*                 writeSpace(); */
    /*             } */
    /*             if (index + 1 < tokens.length) */
    /*             { */
    /*                 if (!peekIs(TOK.at) && (peekIsOperator() */
    /*                         || peekIs(TOK.out_) || peekIs(TOK.in_))) */
    /*                 { */
    /*                     writeToken(); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     writeToken(); */
    /*                     if (!currentIsIndentedTemplateConstraint()) */
    /*                     { */
    /*                         writeSpace(); */
    /*                     } */
    /*                 } */
    /*             } */
    /*             else */
    /*                 writeToken(); */
    /*             break; */
    /*         } */
    /*     } */

    /*     bool currentIsIndentedTemplateConstraint() */
    /*     { */
    /*         return hasCurrent */
    /*             && astInformation.constraintLocations.canFindIndex(current.index) */
    /*             && (config.dfmt_template_constraint_style == TemplateConstraintStyle.always_newline */
    /*                     || config.dfmt_template_constraint_style == TemplateConstraintStyle.always_newline_indent */
    /*                     || currentLineLength >= config.dfmt_soft_max_line_length); */
    /*     } */

    /*     void formatOperator() */
    /*     { */
    /*         import dfmt.editorconfig : OptionalBoolean; */
    /*         import std.algorithm : canFind; */

    /*         switch (current.value) */
    /*         { */
    /*         case TOK.mul: */
    /*             if (astInformation.spaceAfterLocations.canFindIndex(current.index)) */
    /*             { */
    /*                 writeToken(); */
    /*                 if (!currentIs(TOK.mul) && !currentIs(TOK.rightParenthesis) */
    /*                     && !currentIs(TOK.leftBracket) && !currentIs(TOK.comma) && !currentIs( */
    /*                         TOK.semicolon)) */
    /*                 { */
    /*                     write(" "); */
    /*                 } */
    /*                 break; */
    /*             } */
    /*             else if (astInformation.unaryLocations.canFindIndex(current.index)) */
    /*             { */
    /*                 writeToken(); */
    /*                 break; */
    /*             } */
    /*             regenLineBreakHintsIfNecessary(index); */
    /*             goto binary; */
    /*         case TOK.tilde: */
    /*             if (peekIs(TOK.this_) && peek2Is(TOK.leftParenthesis)) */
    /*             { */
    /*                 if (!(index == 0 || peekBackIs(TOK.leftCurly, true) */
    /*                         || peekBackIs(TOK.rightCurly, true) || peekBackIs(TOK.semicolon, true))) */
    /*                 { */
    /*                     write(" "); */
    /*                 } */
    /*                 writeToken(); */
    /*                 break; */
    /*             } */
    /*             goto case; */
    /*         case TOK.and: */
    /*         case TOK.add: */
    /*         case TOK.min: */
    /*             if (astInformation.unaryLocations.canFindIndex(current.index)) */
    /*             { */
    /*                 writeToken(); */
    /*                 break; */
    /*             } */
    /*             regenLineBreakHintsIfNecessary(index); */
    /*             goto binary; */
    /*         case TOK.leftBracket: */
    /*         case TOK.leftParenthesis: */
    /*             formatLeftParenOrBracket(); */
    /*             break; */
    /*         case TOK.rightParenthesis: */
    /*             formatRightParen(); */
    /*             break; */
    /*         case TOK.at: */
    /*             formatAt(); */
    /*             break; */
    /*         case TOK.not: */
    /*             if (((peekIs(TOK.is_) || peekIs(TOK.in_)) */
    /*                     && !peekBackIsOperator()) || peekBackIs(TOK.rightParenthesis)) */
    /*                 write(" "); */
    /*             goto case; */
    /*         case tok!"...": */
    /*         case tok!"++": */
    /*         case tok!"--": */
    /*         case TOK.dollar: */
    /*             writeToken(); */
    /*             break; */
    /*         case TOK.colon: */
    /*             formatColon(); */
    /*             break; */
    /*         case TOK.rightBracket: */
    /*             formatRightBracket(); */
    /*             break; */
    /*         case TOK.semicolon: */
    /*             formatSemicolon(); */
    /*             break; */
    /*         case TOK.leftCurly: */
    /*             formatLeftBrace(); */
    /*             break; */
    /*         case TOK.rightCurly: */
    /*             formatRightBrace(); */
    /*             break; */
    /*         case TOK.dot: */
    /*             regenLineBreakHintsIfNecessary(index); */
    /*             immutable bool ufcsWrap = config.dfmt_reflow_property_chains == OptionalBoolean.t */
    /*                 && astInformation.ufcsHintLocations.canFindIndex(current.index); */
    /*             if (ufcsWrap || linebreakHints.canFind(index) || onNextLine */
    /*                 || (linebreakHints.length == 0 && currentLineLength + nextTokenLength() > config */
    /*                     .max_line_length)) */
    /*             { */
    /*                 if (!indents.topIs(TOK.dot)) */
    /*                     indents.push(TOK.dot); */
    /*                 if (!peekBackIs(TOK.comment)) */
    /*                     newline(); */
    /*                 if (ufcsWrap || onNextLine) */
    /*                     regenLineBreakHints(index); */
    /*             } */
    /*             writeToken(); */
    /*             break; */
    /*         case TOK.comma: */
    /*             formatComma(); */
    /*             break; */
    /*         case tok!"&&": */
    /*         case tok!"||": */
    /*         case TOK.or: */
    /*             regenLineBreakHintsIfNecessary(index); */
    /*             goto case; */
    /*         case TOK.assign: */
    /*         case tok!">=": */
    /*         case tok!">>=": */
    /*         case tok!">>>=": */
    /*         case tok!"|=": */
    /*         case tok!"-=": */
    /*         case tok!"/=": */
    /*         case tok!"*=": */
    /*         case tok!"&=": */
    /*         case tok!"%=": */
    /*         case tok!"+=": */
    /*         case tok!"^^": */
    /*         case tok!"^=": */
    /*         case TOK.xor: */
    /*         case tok!"~=": */
    /*         case tok!"<<=": */
    /*         case tok!"<<": */
    /*         case tok!"<=": */
    /*         case tok!"<>=": */
    /*         case tok!"<>": */
    /*         case TOK.lessThan: */
    /*         case tok!"==": */
    /*         case tok!"=>": */
    /*         case tok!">>>": */
    /*         case tok!">>": */
    /*         case TOK.greaterThan: */
    /*         case tok!"!<=": */
    /*         case tok!"!<>=": */
    /*         case tok!"!<>": */
    /*         case tok!"!<": */
    /*         case tok!"!=": */
    /*         case tok!"!>=": */
    /*         case tok!"!>": */
    /*         case TOK.question: */
    /*         case TOK.div: */
    /*         case tok!"..": */
    /*         case TOK.mod: */
    /*         binary: */
    /*             immutable bool isWrapToken = linebreakHints.canFind(index); */
    /*             if (config.dfmt_keep_line_breaks == OptionalBoolean.t && index > 0) */
    /*             { */
    /*                 const operatorLine = tokens[index].line; */
    /*                 const rightOperandLine = tokens[index + 1].line; */

    /*                 if (tokens[index - 1].line < operatorLine) */
    /*                 { */
    /*                     if (!indents.topIs(tok!"enum")) */
    /*                         pushWrapIndent(); */
    /*                     if (!peekBackIs(TOK.comment)) */
    /*                         newline(); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     write(" "); */
    /*                 } */
    /*                 if (rightOperandLine > operatorLine */
    /*                     && !indents.topIs(tok!"enum")) */
    /*                 { */
    /*                     pushWrapIndent(); */
    /*                 } */
    /*                 writeToken(); */

    /*                 if (rightOperandLine > operatorLine) */
    /*                 { */
    /*                     if (!peekBackIs(TOK.comment)) */
    /*                         newline(); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     write(" "); */
    /*                 } */
    /*             } */
    /*             else if (config.dfmt_split_operator_at_line_end) */
    /*             { */
    /*                 if (isWrapToken) */
    /*                 { */
    /*                     if (!indents.topIs(tok!"enum")) */
    /*                         pushWrapIndent(); */
    /*                     write(" "); */
    /*                     writeToken(); */
    /*                     newline(); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     write(" "); */
    /*                     writeToken(); */
    /*                     if (!currentIs(TOK.comment)) */
    /*                         write(" "); */
    /*                 } */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (isWrapToken) */
    /*                 { */
    /*                     if (!indents.topIs(tok!"enum")) */
    /*                         pushWrapIndent(); */
    /*                     newline(); */
    /*                     writeToken(); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     write(" "); */
    /*                     writeToken(); */
    /*                 } */
    /*                 if (!currentIs(TOK.comment)) */
    /*                     write(" "); */
    /*             } */
    /*             break; */
    /*         default: */
    /*             writeToken(); */
    /*             break; */
    /*         } */
    /*     } */

    /*     void formatComma() */
    /*     { */
    /*         import dfmt.editorconfig : OptionalBoolean; */
    /*         import std.algorithm : canFind; */

    /*         if (config.dfmt_keep_line_breaks == OptionalBoolean.f) */
    /*             regenLineBreakHintsIfNecessary(index); */
    /*         if (indents.indentToMostRecent(TOK.enum_) != -1 */
    /*             && !peekIs(TOK.rightCurly) && indents.topIs(TOK.leftCurly) && parenDepth == 0) */
    /*         { */
    /*             writeToken(); */
    /*             newline(); */
    /*         } */
    /*         else if (indents.topIs(TOK.rightBracket) && indents.topDetails.breakEveryItem */
    /*             && !indents.topDetails.mini) */
    /*         { */
    /*             writeToken(); */
    /*             newline(); */
    /*             regenLineBreakHints(index - 1); */
    /*         } */
    /*         else if (indents.topIs(TOK.rightBracket) && indents.topDetails.preferLongBreaking */
    /*             && !currentIs(TOK.rightParenthesis) && !currentIs(TOK.rightBracket) && !currentIs( */
    /*                 TOK.rightCurly) */
    /*             && !currentIs(TOK.comment) && index + 1 < tokens.length */
    /*             && isMultilineAt(index + 1, true)) */
    /*         { */
    /*             writeToken(); */
    /*             newline(); */
    /*             regenLineBreakHints(index - 1); */
    /*         } */
    /*         else if (config.dfmt_keep_line_breaks == OptionalBoolean.t) */
    /*         { */
    /*             const commaLine = tokens[index].line; */

    /*             writeToken(); */
    /*             if (indents.topIsWrap && !indents.topIs(TOK.comma)) */
    /*             { */
    /*                 indents.pop; */
    /*             } */
    /*             if (!currentIs(TOK.rightParenthesis) && !currentIs(TOK.rightBracket) */
    /*                 && !currentIs(TOK.rightCurly) && !currentIs(TOK.comment)) */
    /*             { */
    /*                 if (tokens[index].line == commaLine) */
    /*                 { */
    /*                     write(" "); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     newline(); */
    /*                 } */
    /*             } */
    /*         } */
    /*         else if (!peekIs(TOK.rightCurly) && (linebreakHints.canFind(index) */
    /*                 || (linebreakHints.length == 0 && currentLineLength > config.max_line_length))) */
    /*         { */
    /*             pushWrapIndent(); */
    /*             writeToken(); */
    /*             if (indents.topIsWrap && !indents.topIs(TOK.comma)) */
    /*             { */
    /*                 indents.pop; */
    /*             } */
    /*             newline(); */
    /*         } */
    /*         else */
    /*         { */
    /*             writeToken(); */
    /*             if (!currentIs(TOK.rightParenthesis) && !currentIs(TOK.rightBracket) */
    /*                 && !currentIs(TOK.rightCurly) && !currentIs(TOK.comment)) */
    /*             { */
    /*                 write(" "); */
    /*             } */
    /*         } */
    /*         regenLineBreakHintsIfNecessary(index - 1); */
    /*     } */

    /*     void regenLineBreakHints(immutable size_t i) */
    /*     { */
    /*         import std.range : assumeSorted; */
    /*         import std.algorithm.comparison : min; */
    /*         import std.algorithm.searching : canFind, countUntil; */

    /*         // The end of the tokens considered by the line break algorithm is */
    /*         // either the expression end index or the next mandatory line break */
    /*         // or a newline inside a string literal, whichever is first. */
    /*         auto r = assumeSorted(astInformation.ufcsHintLocations).upperBound(tokens[i].index); */
    /*         immutable ufcsBreakLocation = r.empty */
    /*             ? size_t.max */
    /*             : tokens[i .. $].countUntil!(t => t.index == r.front) + i; */
    /*         immutable multilineStringLocation = tokens[i .. $] */
    /*             .countUntil!(t => t.text.canFind('\n')); */
    /*         immutable size_t j = min( */
    /*             expressionEndIndex(i), */
    /*             ufcsBreakLocation, */
    /*             multilineStringLocation == -1 ? size_t.max : multilineStringLocation + i + 1); */
    /*         // Use magical negative value for array literals and wrap indents */
    /*         immutable inLvl = (indents.topIsWrap() || indents.topIs(TOK.rightBracket)) ? -indentLevel */
    /*             : indentLevel; */
    /*         linebreakHints = chooseLineBreakTokens(i, tokens[i .. j], depths[i .. j], */
    /*             config, currentLineLength, inLvl); */
    /*     } */

    /*     void regenLineBreakHintsIfNecessary(immutable size_t i) */
    /*     { */
    /*         if (linebreakHints.length == 0 || linebreakHints[$ - 1] <= i - 1) */
    /*             regenLineBreakHints(i); */
    /*     } */

    /*     void simpleNewline() */
    /*     { */
    /*         import dfmt.editorconfig : EOL; */

    /*         output.put(eolString); */
    /*     } */

    /*     void newline() */
    /*     { */
    /*         import std.range : assumeSorted; */
    /*         import std.algorithm : max, canFind; */
    /*         import dfmt.editorconfig : OptionalBoolean; */

    /*         if (currentIs(TOK.comment) && index > 0 && current.line == tokenEndLine(tokens[index - 1])) */
    /*             return; */

    /*         immutable bool hasCurrent = this.hasCurrent; */

    /*         if (niBraceDepth > 0 && !peekBackIsSlashSlash() && hasCurrent && tokens[index].value == TOK.rightCurly */
    /*             && !assumeSorted(astInformation.funLitEndLocations).equalRange( */
    /*                 tokens[index].index) */
    /*                 .empty) */
    /*         { */
    /*             return; */
    /*         } */

    /*         simpleNewline(); */

    /*         if (!justAddedExtraNewline && index > 0 && hasCurrent */
    /*             && tokens[index].line - tokenEndLine(tokens[index - 1]) > 1) */
    /*         { */
    /*             simpleNewline(); */
    /*         } */

    /*         justAddedExtraNewline = false; */
    /*         currentLineLength = 0; */

    /*         if (hasCurrent) */
    /*         { */
    /*             if (currentIs(TOK.else_)) */
    /*             { */
    /*                 immutable i = indents.indentToMostRecent(TOK.if_); */
    /*                 immutable v = indents.indentToMostRecent(TOK.version_); */
    /*                 immutable mostRecent = max(i, v); */
    /*                 if (mostRecent != -1) */
    /*                     indentLevel = mostRecent; */
    /*             } */
    /*             else if (currentIs(TOK.identifier) && peekIs(TOK.colon)) */
    /*             { */
    /*                 if (peekBackIs(TOK.rightCurly, true) || peekBackIs(TOK.semicolon, true)) */
    /*                     indents.popTempIndents(); */
    /*                 immutable l = indents.indentToMostRecent(TOK.switch_); */
    /*                 if (l != -1 && config.dfmt_align_switch_statements == OptionalBoolean.t) */
    /*                     indentLevel = l; */
    /*                 else if (astInformation.structInfoSortedByEndLocation */
    /*                     .canFind!(st => st.startLocation < current.index && current.index < st */
    /*                         .endLocation)) */
    /*                 { */
    /*                     immutable l2 = indents.indentToMostRecent(TOK.leftCurly); */
    /*                     assert(l2 != -1, "Recent '{' is not found despite being in struct initializer"); */
    /*                     indentLevel = l2 + 1; */
    /*                 } */
    /*                 else if ((config.dfmt_compact_labeled_statements == OptionalBoolean.f */
    /*                         || !isBlockHeader(2) || peek2Is(TOK.if_)) && !indents.topIs( */
    /*                         TOK.rightBracket)) */
    /*                 { */
    /*                     immutable l2 = indents.indentToMostRecent(TOK.leftCurly); */
    /*                     indentLevel = l2 != -1 ? l2 : indents.indentLevel - 1; */
    /*                 } */
    /*                 else */
    /*                     indentLevel = indents.indentLevel; */
    /*             } */
    /*             else if (currentIs(TOK.case_) || currentIs(TOK.default_)) */
    /*             { */

    /*                 if (peekBackIs(TOK.rightCurly, true) || peekBackIs(TOK.semicolon, true) /** */
    /*                      * The following code is valid and should be indented flatly */
    /*                      * case A: */
    /*                      * case B: */
    /*                      *1/ */
    /*                     || peekBackIs(TOK.colon, true)) */
    /*                 { */
    /*                     indents.popTempIndents(); */
    /*                     if (indents.topIs(TOK.case_)) */
    /*                         indents.pop(); */
    /*                 } */
    /*                 immutable l = indents.indentToMostRecent(TOK.switch_); */
    /*                 if (l != -1) */
    /*                     indentLevel = config.dfmt_align_switch_statements == OptionalBoolean.t */
    /*                         ? l : indents.indentLevel; */
    /*             } */
    /*             else if (currentIs(TOK.rightParenthesis)) */
    /*             { */
    /*                 if (indents.topIs(TOK.leftParenthesis)) */
    /*                     indents.pop(); */
    /*                 indentLevel = indents.indentLevel; */
    /*             } */
    /*             else if (currentIs(TOK.leftCurly)) */
    /*             { */
    /*                 indents.popWrapIndents(); */
    /*                 if ((peekBackIsSlashSlash() && peekBack2Is(TOK.semicolon)) || indents.topIs( */
    /*                         TOK.rightBracket)) */
    /*                 { */
    /*                     indents.popTempIndents(); */
    /*                     indentLevel = indents.indentLevel; */
    /*                 } */
    /*             } */
    /*             else if (currentIs(TOK.rightCurly)) */
    /*             { */
    /*                 indents.popTempIndents(); */
    /*                 while (indents.topIsOneOf(TOK.case_, TOK.at, tok.static_)) */
    /*                     indents.pop(); */
    /*                 if (indents.topIs(TOK.leftCurly)) */
    /*                 { */
    /*                     indentLevel = indents.indentToMostRecent(TOK.leftCurly); */
    /*                     indents.pop(); */
    /*                 } */
    /*                 if (indents.topIsOneOf(TOK.try_, TOK.catch_)) */
    /*                 { */
    /*                     indents.pop(); */
    /*                 } */
    /*                 else */
    /*                     while (sBraceDepth == 0 && indents.topIsTemp() */
    /*                         && ((!indents.topIsOneOf(TOK.else_, TOK.if_, */
    /*                             TOK.static_, TOK.version_)) || !peekIs(TOK.else_))) */
    /*                     { */
    /*                         indents.pop(); */
    /*                     } */
    /*             } */
    /*             else if (currentIs(TOK.rightBracket)) */
    /*             { */
    /*                 indents.popWrapIndents(); */
    /*                 if (indents.topIs(TOK.rightBracket)) */
    /*                 { */
    /*                     indents.pop(); */
    /*                 } */
    /*                 // Find the initial indentation of constructs like "if" and */
    /*                 // "foreach" without removing them from the stack, since they */
    /*                 // still can be used later to indent "else". */
    /*                 auto savedIndents = IndentStack(config); */
    /*                 while (indents.length >= 0 && indents.topIsTemp) */
    /*                 { */
    /*                     savedIndents.push(indents.top, indents.topDetails); */
    /*                     indents.pop; */
    /*                 } */
    /*                 indentLevel = indents.indentLevel; */
    /*                 while (savedIndents.length > 0) */
    /*                 { */
    /*                     indents.push(savedIndents.top, savedIndents.topDetails); */
    /*                     savedIndents.pop; */
    /*                 } */
    /*             } */
    /*             else if (astInformation.attributeDeclarationLines.canFindIndex(current.line)) */
    /*             { */
    /*                 if (config.dfmt_outdent_attributes == OptionalBoolean.t) */
    /*                 { */
    /*                     immutable l = indents.indentToMostRecent(TOK.leftCurly); */
    /*                     if (l != -1) */
    /*                         indentLevel = l; */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     if (indents.topIs(TOK.at)) */
    /*                         indents.pop(); */
    /*                     indentLevel = indents.indentLevel; */
    /*                 } */
    /*             } */
    /*             else if (currentIs(TOK.catch_) || currentIs(TOK.finally_)) */
    /*             { */
    /*                 indentLevel = indents.indentLevel; */
    /*             } */
    /*             else */
    /*             { */
    /*                 if (indents.topIsTemp() && (peekBackIsOneOf(true, TOK.rightCurly, */
    /*                         TOK.semicolon) && !indents.topIs(TOK.semicolon))) */
    /*                     indents.popTempIndents(); */
    /*                 indentLevel = indents.indentLevel; */
    /*             } */
    /*             indent(); */
    /*         } */
    /*         parenDepthOnLine = 0; */
    /*     } */

    /*     void write(string str) */
    /*     { */
    /*         currentLineLength += str.length; */
    /*         output.put(str); */
    /*     } */

    /*     void writeToken() */
    /*     { */
    /*         import std.range : retro; */
    /*         import std.algorithm.searching : countUntil; */
    /*         import std.algorithm.iteration : joiner; */
    /*         import std.string : lineSplitter; */

    /*         if (current.text is null) */
    /*         { */
    /*             immutable s = str(current.value); */
    /*             currentLineLength += s.length; */
    /*             output.put(str(current.value)); */
    /*         } */
    /*         else */
    /*         { */
    /*             output.put(current.text.lineSplitter.joiner(eolString)); */
    /*             switch (current.value) */
    /*             { */
    /*             case TOK.string_: */
    /*                 immutable o = current.text.retro().countUntil('\n'); */
    /*                 if (o == -1) */
    /*                 { */
    /*                     currentLineLength += current.text.length; */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     currentLineLength = cast(uint) o; */
    /*                 } */
    /*                 break; */
    /*             default: */
    /*                 currentLineLength += current.text.length; */
    /*                 break; */
    /*             } */
    /*         } */
    /*         index++; */
    /*     } */

    /*     void writeParens(bool spaceAfter) */
    /*     in */
    /*     { */
    /*         assert(currentIs(TOK.leftParenthesis), str(current.value)); */
    /*     } */
    /*     do */
    /*     { */
    /*         immutable int depth = parenDepth; */
    /*         immutable int startingNiBraceDepth = niBraceDepth; */
    /*         immutable int startingSBraceDepth = sBraceDepth; */
    /*         parenDepth = 0; */

    /*         do */
    /*         { */
    /*             spaceAfterParens = spaceAfter; */
    /*             if (currentIs(TOK.semicolon) && niBraceDepth <= startingNiBraceDepth */
    /*                 && sBraceDepth <= startingSBraceDepth) */
    /*             { */
    /*                 if (currentLineLength >= config.dfmt_soft_max_line_length) */
    /*                 { */
    /*                     pushWrapIndent(); */
    /*                     writeToken(); */
    /*                     newline(); */
    /*                 } */
    /*                 else */
    /*                 { */
    /*                     writeToken(); */
    /*                     if (!currentIs(TOK.rightParenthesis) && !currentIs(TOK.semicolon)) */
    /*                         write(" "); */
    /*                 } */
    /*             } */
    /*             else */
    /*                 formatStep(); */
    /*         } */
    /*         while (hasCurrent && parenDepth > 0); */

    /*         if (indents.topIs(TOK.not)) */
    /*             indents.pop(); */
    /*         parenDepth = depth; */
    /*         spaceAfterParens = spaceAfter; */
    /*     } */

    /*     void indent() */
    /*     { */
    /*         import dfmt.editorconfig : IndentStyle; */

    /*         if (config.indent_style == IndentStyle.tab) */
    /*         { */
    /*             foreach (i; 0 .. indentLevel) */
    /*             { */
    /*                 currentLineLength += config.tab_width; */
    /*                 output.put("\t"); */
    /*             } */
    /*         } */
    /*         else */
    /*         { */
    /*             foreach (i; 0 .. indentLevel) */
    /*                 foreach (j; 0 .. config.indent_size) */
    /*                 { */
    /*                     output.put(" "); */
    /*                     currentLineLength++; */
    /*                 } */
    /*         } */
    /*     } */

    /*     void pushWrapIndent(TOK type = TOK.error) */
    /*     { */
    /*         immutable t = type == TOK.error ? tokens[index].value : type; */
    /*         IndentStack.Details detail; */
    /*         detail.wrap = isWrapIndent(t); */
    /*         detail.temp = isTempIndent(t); */
    /*         pushWrapIndent(t, detail); */
    /*     } */

    /*     void pushWrapIndent(TOK type, IndentStack.Details detail) */
    /*     { */
    /*         if (parenDepth == 0) */
    /*         { */
    /*             if (indents.wrapIndents == 0) */
    /*                 indents.push(type, detail); */
    /*         } */
    /*         else if (indents.wrapIndents < 1) */
    /*             indents.push(type, detail); */
    /*     } */

    /*     void writeSpace() */
    /*     { */
    /*         if (onNextLine) */
    /*         { */
    /*             newline(); */
    /*         } */
    /*         else */
    /*         { */
    /*             write(" "); */
    /*         } */
    /*     } */

    /* const pure @safe @nogc: */

    /*     size_t expressionEndIndex(size_t i, bool matchComma = false) nothrow */
    /*     { */
    /*         immutable bool braces = i < tokens.length && tokens[i].value == TOK.leftCurly; */
    /*         immutable bool brackets = i < tokens.length && tokens[i].value == TOK.leftBracket; */
    /*         immutable d = depths[i]; */
    /*         while (true) */
    /*         { */
    /*             if (i >= tokens.length) */
    /*                 break; */
    /*             if (depths[i] < d) */
    /*                 break; */
    /*             if (!braces && !brackets && matchComma && depths[i] == d && tokens[i].value == TOK */
    /*                 .comma) */
    /*                 break; */
    /*             if (!braces && !brackets && (tokens[i].value == TOK.semicolon || tokens[i].value == TOK */
    /*                     .leftCurly)) */
    /*                 break; */
    /*             i++; */
    /*         } */
    /*         return i; */
    /*     } */

    /*     /// Returns: true when the expression starting at index goes over the line length limit. */
    /*     /// Uses matching `{}` or `[]` or otherwise takes everything up until a semicolon or opening brace using expressionEndIndex. */
    /*     bool isMultilineAt(size_t i, bool matchComma = false) */
    /*     { */
    /*         import std.algorithm : map, sum, canFind; */

    /*         auto e = expressionEndIndex(i, matchComma); */
    /*         immutable int l = currentLineLength + tokens[i .. e].map!(a => tokenLength(a)).sum(); */
    /*         return l > config.dfmt_soft_max_line_length || tokens[i .. e].canFind!( */
    /*             a => a.value == TOK.comment || isBlockHeaderToken(a.value))(); */
    /*     } */

    /*     bool peekIsKeyword() nothrow */
    /*     { */
    /*         return index + 1 < tokens.length && isKeyword(tokens[index + 1].value); */
    /*     } */

    /*     bool peekIsBasicType() nothrow */
    /*     { */
    /*         return index + 1 < tokens.length && isBasicType(tokens[index + 1].value); */
    /*     } */

    /*     bool peekIsLabel() nothrow */
    /*     { */
    /*         return peekIs(TOK.identifier) && peek2Is(TOK.colon); */
    /*     } */

    /*     int currentTokenLength() */
    /*     { */
    /*         return tokenLength(tokens[index]); */
    /*     } */

    /*     int nextTokenLength() */
    /*     { */
    /*         immutable size_t i = index + 1; */
    /*         if (i >= tokens.length) */
    /*             return INVALID_TOKEN_LENGTH; */
    /*         return tokenLength(tokens[i]); */
    /*     } */

    bool hasCurrent() nothrow const
    {
        return index < tokens.length;
    }

    /*     ref current() nothrow */
    /*     in */
    /*     { */
    /*         assert(hasCurrent); */
    /*     } */
    /*     do */
    /*     { */
    /*         return tokens[index]; */
    /*     } */

    /*     const(Token) peekBack(uint distance = 1) nothrow */
    /*     { */
    /*         assert(index >= distance, "Trying to peek before the first token"); */
    /*         return tokens[index - distance]; */
    /*     } */

    /*     bool peekBackIsLiteralOrIdent() nothrow */
    /*     { */
    /*         if (index == 0) */
    /*             return false; */
    /*         switch (tokens[index - 1].value) */
    /*         { */
    /*         case TOK.int32Literal: */
    /*         case TOK.uns32Literal: */
    /*         case TOK.int64Literal: */
    /*         case TOK.uns64Literal: */
    /*         case TOK.int128Literal: */
    /*         case TOK.uns128Literal: */
    /*         case TOK.float32Literal: */
    /*         case TOK.float64Literal: */
    /*         case TOK.float80Literal: */
    /*         case TOK.imaginary32Literal: */
    /*         case TOK.imaginary64Literal: */
    /*         case TOK.imaginary80Literal: */
    /*         case TOK.charLiteral: */
    /*         case TOK.wcharLiteral: */
    /*         case TOK.dcharLiteral: */
    /*         case TOK.identifier: */
    /*         case TOK.string_: */
    /*             return true; */
    /*         default: */
    /*             return false; */
    /*         } */
    /*     } */

    /*     bool peekIsLiteralOrIdent() nothrow */
    /*     { */
    /*         if (index + 1 >= tokens.length) */
    /*             return false; */
    /*         switch (tokens[index + 1].value) */
    /*         { */
    /*         case TOK.int32Literal: */
    /*         case TOK.uns32Literal: */
    /*         case TOK.int64Literal: */
    /*         case TOK.uns64Literal: */
    /*         case TOK.int128Literal: */
    /*         case TOK.uns128Literal: */
    /*         case TOK.float32Literal: */
    /*         case TOK.float64Literal: */
    /*         case TOK.float80Literal: */
    /*         case TOK.imaginary32Literal: */
    /*         case TOK.imaginary64Literal: */
    /*         case TOK.imaginary80Literal: */
    /*         case TOK.charLiteral: */
    /*         case TOK.wcharLiteral: */
    /*         case TOK.dcharLiteral: */
    /*         case TOK.identifier: */
    /*         case TOK.string_: */
    /*             return true; */
    /*         default: */
    /*             return false; */
    /*         } */
    /*     } */

    /*     bool peekBackIs(TOK tokenType, bool ignoreComments = false) nothrow */
    /*     { */
    /*         return peekImplementation(tokenType, -1, ignoreComments); */
    /*     } */

    /*     bool peekBackIsKeyword(bool ignoreComments = true) nothrow */
    /*     { */
    /*         if (index == 0) */
    /*             return false; */
    /*         auto i = index - 1; */
    /*         if (ignoreComments) */
    /*             while (tokens[i].value == TOK.comment) */
    /*             { */
    /*                 if (i == 0) */
    /*                     return false; */
    /*                 i--; */
    /*             } */
    /*         return isKeyword(tokens[i].value); */
    /*     } */

    /*     bool peekBackIsOperator() nothrow */
    /*     { */
    /*         return index == 0 ? false : isOperator(tokens[index - 1].value); */
    /*     } */

    /*     bool peekBackIsOneOf(bool ignoreComments, TOK[] tokenTypes...) nothrow */
    /*     { */
    /*         if (index == 0) */
    /*             return false; */
    /*         auto i = index - 1; */
    /*         if (ignoreComments) */
    /*             while (tokens[i].value == TOK.comment) */
    /*             { */
    /*                 if (i == 0) */
    /*                     return false; */
    /*                 i--; */
    /*             } */
    /*         immutable t = tokens[i].value; */
    /*         foreach (tt; tokenTypes) */
    /*             if (tt == t) */
    /*                 return true; */
    /*         return false; */
    /*     } */

    /*     bool peekBack2Is(TOK tokenType, bool ignoreComments = false) nothrow */
    /*     { */
    /*         return peekImplementation(tokenType, -2, ignoreComments); */
    /*     } */

    /*     bool peekImplementation(TOK tokenType, int n, bool ignoreComments = true) nothrow */
    /*     { */
    /*         auto i = index + n; */
    /*         if (ignoreComments) */
    /*             while (n != 0 && i < tokens.length && tokens[i].value == TOK.comment) */
    /*                 i = n > 0 ? i + 1 : i - 1; */
    /*         return i < tokens.length && tokens[i].value == tokenType; */
    /*     } */

    /*     bool peek2Is(TOK tokenType, bool ignoreComments = true) nothrow */
    /*     { */
    /*         return peekImplementation(tokenType, 2, ignoreComments); */
    /*     } */

    /*     bool peekIsOperator() nothrow */
    /*     { */
    /*         return index + 1 < tokens.length && isOperator(tokens[index + 1].value); */
    /*     } */

    /*     bool peekIs(TOK tokenType, bool ignoreComments = true) nothrow */
    /*     { */
    /*         return peekImplementation(tokenType, 1, ignoreComments); */
    /*     } */

    /*     bool peekIsBody() nothrow */
    /*     { */
    /*         return index + 1 < tokens.length && tokens[index + 1].text == "body"; */
    /*     } */

    /*     bool peekBackIsFunctionDeclarationEnding() nothrow */
    /*     { */
    /*         return peekBackIsOneOf(false, TOK.rightParenthesis, TOK.const_, TOK.immutable_, */
    /*             TOK.inout_, TOK.shared_, TOK.at, TOK.pure_, TOK.nothrow_, */
    /*             TOK.return_, TOK.scope_); */
    /*     } */

    /*     bool peekBackIsSlashSlash() nothrow */
    /*     { */
    /*         return index > 0 && tokens[index - 1].value == TOK.comment */
    /*             && tokens[index - 1].text[0 .. 2] == "//"; */
    /*     } */

    /*     bool currentIs(TOK tokenType) nothrow */
    /*     { */
    /*         return hasCurrent && tokens[index].value == tokenType; */
    /*     } */

    /*     bool onNextLine() @nogc nothrow pure @safe */
    /*     { */
    /*         import dfmt.editorconfig : OptionalBoolean; */
    /*         import std.algorithm.searching : count; */
    /*         import std.string : representation; */

    /*         if (config.dfmt_keep_line_breaks == OptionalBoolean.f || index <= 0) */
    /*         { */
    /*             return false; */
    /*         } */
    /*         // To compare whether 2 tokens are on same line, we need the end line */
    /*         // of the first token (tokens[index - 1]) and the start line of the */
    /*         // second one (tokens[index]). If a token takes multiple lines (e.g. a */
    /*         // multi-line string), we can sum the number of the newlines in the */
    /*         // token and tokens[index - 1].line, the start line. */
    /*         const previousTokenEndLineNo = tokens[index - 1].line */
    /*             + tokens[index - 1].text.representation.count('\n'); */

    /*         return previousTokenEndLineNo < tokens[index].line; */
    /*     } */

    /*     /// Bugs: not unicode correct */
    /*     size_t tokenEndLine(const Token t) */
    /*     { */
    /*         import std.algorithm : count; */

    /*         switch (t.value) */
    /*         { */
    /*         case TOK.comment: */
    /*         case TOK.string_: */
    /*             return t.line + t.text.count('\n'); */
    /*         default: */
    /*             return t.line; */
    /*         } */
    /*     } */

    /*     bool isBlockHeaderToken(const TOK t) */
    /*     { */
    /*         return t == TOK.for_ || t == TOK.foreach_ || t == TOK.foreach_reverse_ */
    /*             || t == TOK.while_ || t == TOK.if_ || t == TOK.in_ || t == TOK.out_ */
    /*             || t == TOK.do_ || t == TOK.catch_ || t == TOK.with_ */
    /*             || t == TOK.synchronized_ || t == TOK.scope_ || t == TOK.debug_; */
    /*     } */

    /*     bool isBlockHeader(int i = 0) nothrow */
    /*     { */
    /*         if (i + index < 0 || i + index >= tokens.length) */
    /*             return false; */
    /*         const t = tokens[i + index].value; */
    /*         bool isExpressionContract; */

    /*         if (i + index + 3 < tokens.length) */
    /*         { */
    /*             isExpressionContract = (t == TOK.in_ && peekImplementation(TOK.leftParenthesis, i + 1, true)) */
    /*                 || (t == TOK.out_ && (peekImplementation(TOK.leftParenthesis, i + 1, true) */
    /*                         && (peekImplementation(TOK.semicolon, i + 2, true) */
    /*                         || (peekImplementation(TOK.identifier, i + 2, true) */
    /*                         && peekImplementation(TOK.semicolon, i + 3, true))))); */
    /*         } */

    /*         return isBlockHeaderToken(t) && !isExpressionContract; */
    /*     } */

    /*     bool isSeparationToken(TOK t) nothrow */
    /*     { */
    /*         return t == TOK.comma || t == TOK.semicolon || t == TOK.colon */
    /*             || t == TOK.leftParenthesis || t == TOK.rightParenthesis */
    /*             || t == TOK.leftBracket || t == TOK.rightBracket */
    /*             || t == TOK.leftCurly || t == TOK.rightCurly; */
    /*     } */
    /* } */

    /* bool canFindIndex(const size_t[] items, size_t index, size_t* pos = null) pure @safe @nogc */
    /* { */
    /*     import std.range : assumeSorted; */

    /*     if (!pos) */
    /*     { */
    /*         return !assumeSorted(items).equalRange(index).empty; */
    /*     } */
    /*     else */
    /*     { */
    /*         auto trisection_result = assumeSorted(items).trisect(index); */
    /*         if (trisection_result[1].length == 1) */
    /*         { */
    /*             *pos = trisection_result[0].length; */
    /*             return true; */
    /*         } */
    /*         else if (trisection_result[1].length == 0) */
    /*         { */
    /*             return false; */
    /*         } */
    /*         else */
    /*         { */
    /*             assert(0, "the constraint of having unique locations has been violated"); */
    /*         } */
    /*     } */
}
