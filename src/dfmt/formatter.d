
//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.formatter;

import dparse.lexer;
import dparse.parser;
import dparse.rollback_allocator;
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
    LexerConfig config;
    config.stringBehavior = StringBehavior.source;
    config.whitespaceBehavior = WhitespaceBehavior.skip;
    LexerConfig parseConfig;
    parseConfig.stringBehavior = StringBehavior.source;
    parseConfig.whitespaceBehavior = WhitespaceBehavior.skip;
    StringCache cache = StringCache(StringCache.defaultBucketCount);
    ASTInformation astInformation;
    RollbackAllocator allocator;
    auto parseTokens = getTokensForParser(buffer, parseConfig, &cache);
    auto mod = parseModule(parseTokens, source_desc, &allocator);
    auto visitor = new FormatVisitor(&astInformation);
    visitor.visit(mod);
    astInformation.cleanup();
    auto tokenRange = byToken(buffer, config, &cache);
    auto app = appender!(Token[])();
    for (; !tokenRange.empty(); tokenRange.popFront())
        app.put(tokenRange.front());
    auto tokens = app.data;
    if (!tokenRange.messages.empty)
        return false;
    auto depths = generateDepthInfo(tokens);
    auto tokenFormatter = TokenFormatter!OutputRange(buffer, tokens, depths,
            output, &astInformation, formatterConfig);
    tokenFormatter.format();
    return true;
}

immutable(short[]) generateDepthInfo(const Token[] tokens) pure nothrow @trusted
{
    import std.exception : assumeUnique;

    short[] retVal = new short[](tokens.length);
    short depth = 0;
    foreach (i, ref t; tokens)
    {
        switch (t.type)
        {
        case tok!"[":
            depth++;
            goto case;
        case tok!"{":
        case tok!"(":
            depth++;
            break;
        case tok!"]":
            depth--;
            goto case;
        case tok!"}":
        case tok!")":
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
                assert (eol == eol._default);
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
        import std.range : assumeSorted;

        assert(hasCurrent);
        if (currentIs(tok!"comment"))
        {
            formatComment();
        }
        else if (isStringLiteral(current.type)
                || isNumberLiteral(current.type) || currentIs(tok!"characterLiteral"))
        {
            writeToken();
            if (hasCurrent)
            {
                immutable t = tokens[index].type;
                if (t == tok!"identifier" || isStringLiteral(t)
                        || isNumberLiteral(t) || t == tok!"characterLiteral"
                        // a!"b" function()
                        || t == tok!"function" || t == tok!"delegate")
                    write(" ");
            }
        }
        else if (currentIs(tok!"module") || currentIs(tok!"import"))
        {
            formatModuleOrImport();
        }
        else if (currentIs(tok!"return"))
        {
            writeToken();
            if (!currentIs(tok!";") && !currentIs(tok!")") && !currentIs(tok!"{")
                    && !currentIs(tok!"in") && !currentIs(tok!"out") && !currentIs(tok!"do")
                    && (hasCurrent && tokens[index].text != "body"))
                write(" ");
        }
        else if (currentIs(tok!"with"))
        {
            if (indents.length == 0 || !indents.topIsOneOf(tok!"switch", tok!"with"))
                indents.push(tok!"with");
            writeToken();
            write(" ");
            if (currentIs(tok!"("))
                writeParens(false);
            if (!currentIs(tok!"switch") && !currentIs(tok!"with")
                    && !currentIs(tok!"{") && !(currentIs(tok!"final") && peekIs(tok!"switch")))
            {
                newline();
            }
            else if (!currentIs(tok!"{"))
                write(" ");
        }
        else if (currentIs(tok!"switch"))
        {
            formatSwitch();
        }
        else if (currentIs(tok!"extern") && peekIs(tok!"("))
        {
            writeToken();
            write(" ");
            while (hasCurrent)
            {
                if (currentIs(tok!"("))
                    formatLeftParenOrBracket();
                else if (currentIs(tok!")"))
                {
                    formatRightParen();
                    break;
                }
                else
                    writeToken();
            }
        }
        else if (((isBlockHeader() || currentIs(tok!"version")) && peekIs(tok!"("))
                || (currentIs(tok!"debug") && peekIs(tok!"{")))
        {
            if (!assumeSorted(astInformation.constraintLocations).equalRange(current.index).empty)
                formatConstraint();
            else
                formatBlockHeader();
        }
        else if ((current.text == "body" || current == tok!"do") && peekBackIsFunctionDeclarationEnding())
        {
            formatKeyword();
        }
        else if (currentIs(tok!"do"))
        {
            formatBlockHeader();
        }
        else if (currentIs(tok!"else"))
        {
            formatElse();
        }
        else if (currentIs(tok!"asm"))
        {
            formatKeyword();
            while (hasCurrent && !currentIs(tok!"{"))
                formatStep();
            if (hasCurrent)
            {
                int depth = 1;
                formatStep();
                inAsm = true;
                while (hasCurrent && depth > 0)
                {
                    if (currentIs(tok!"{"))
                        ++depth;
                    else if (currentIs(tok!"}"))
                        --depth;
                    formatStep();
                }
                inAsm = false;
            }
        }
        else if (currentIs(tok!"this"))
        {
            const thisIndex = current.index;
            formatKeyword();
            if (config.dfmt_space_before_function_parameters
                && (thisSpace || astInformation.constructorDestructorLocations
                    .canFindIndex(thisIndex)))
            {
                write(" ");
                thisSpace = false;
            }
        }
        else if (isKeyword(current.type))
        {
            if (currentIs(tok!"debug"))
                inlineElse = true;
            formatKeyword();
        }
        else if (isBasicType(current.type))
        {
            writeToken();
            if (currentIs(tok!"identifier") || isKeyword(current.type) || inAsm)
                write(" ");
        }
        else if (isOperator(current.type))
        {
            formatOperator();
        }
        else if (currentIs(tok!"identifier"))
        {
            writeToken();
            //dfmt off
            if (hasCurrent && ( currentIs(tok!"identifier")
                    || ( index > 1 && config.dfmt_space_before_function_parameters
                        && ( isBasicType(peekBack(2).type)
                            || peekBack2Is(tok!"identifier")
                            || peekBack2Is(tok!")")
                            || peekBack2Is(tok!"]") )
                        && currentIs(tok!("(") )
                    || isBasicType(current.type) || currentIs(tok!"@")
                    || isNumberLiteral(tokens[index].type)
                    || (inAsm  && peekBack2Is(tok!";") && currentIs(tok!"["))
            )))
            //dfmt on
            {
                write(" ");
            }
        }
        else if (currentIs(tok!"scriptLine") || currentIs(tok!"specialTokenSequence"))
        {
            writeToken();
            newline();
        }
        else
            writeToken();
    }

    void formatConstraint()
    {
        import dfmt.editorconfig : OB = OptionalBoolean;
        with (TemplateConstraintStyle) final switch (config.dfmt_template_constraint_style)
        {
        case _unspecified:
            assert(false, "Config was not validated properly");
        case conditional_newline:
            immutable l = currentLineLength + betweenParenLength(tokens[index + 1 .. $]);
            if (l > config.dfmt_soft_max_line_length)
                newline();
            else if (peekBackIs(tok!")") || peekBackIs(tok!"identifier"))
                write(" ");
            break;
        case always_newline:
            newline();
            break;
        case conditional_newline_indent:
            immutable l = currentLineLength + betweenParenLength(tokens[index + 1 .. $]);
            if (l > config.dfmt_soft_max_line_length)
            {
                config.dfmt_single_template_constraint_indent == OB.t ?
                    pushWrapIndent() : pushWrapIndent(tok!"!");
                newline();
            }
            else if (peekBackIs(tok!")") || peekBackIs(tok!"identifier"))
                write(" ");
            break;
        case always_newline_indent:
            {
                config.dfmt_single_template_constraint_indent == OB.t ?
                    pushWrapIndent() : pushWrapIndent(tok!"!");
                newline();
            }
            break;
        }
        // if
        writeToken();
        // assume that the parens are present, otherwise the parser would not
        // have told us there was a constraint here
        write(" ");
        writeParens(false);
    }

    string commentText(size_t i)
    {
        import std.string : strip;

        assert(tokens[i].type == tok!"comment");
        string commentText = tokens[i].text;
        if (commentText[0 .. 2] == "//")
            commentText = commentText[2 .. $];
        else
        {
            if (commentText.length > 3)
                commentText = commentText[2 .. $ - 2];
            else
                commentText = commentText[2 .. $];
        }
        return commentText.strip();
    }

    void skipFormatting()
    {
        size_t dfmtOff = index;
        size_t dfmtOn = index;
        foreach (i; dfmtOff + 1 .. tokens.length)
        {
            dfmtOn = i;
            if (tokens[i].type != tok!"comment")
                continue;
            immutable string commentText = commentText(i);
            if (commentText == "dfmt on")
                break;
        }
        write(cast(string) rawSource[tokens[dfmtOff].index .. tokens[dfmtOn].index]);
        index = dfmtOn;
    }

    void formatComment()
    {
        if (commentText(index) == "dfmt off")
        {
            skipFormatting();
            return;
        }

        immutable bool currIsSlashSlash = tokens[index].text[0 .. 2] == "//";
        immutable prevTokenEndLine = index == 0 ? size_t.max : tokenEndLine(tokens[index - 1]);
        immutable size_t currTokenLine = tokens[index].line;
        if (index > 0)
        {
            immutable t = tokens[index - 1].type;
            immutable canAddNewline = currTokenLine - prevTokenEndLine < 1;
            if (peekBackIsOperator() && !isSeparationToken(t))
                pushWrapIndent(t);
            else if (peekBackIs(tok!",") && prevTokenEndLine == currTokenLine
                    && indents.indentToMostRecent(tok!"enum") == -1)
                pushWrapIndent(tok!",");
            if (peekBackIsOperator() && !peekBackIsOneOf(false, tok!"comment",
                    tok!"{", tok!"}", tok!":", tok!";", tok!",", tok!"[", tok!"(")
                    && !canAddNewline && prevTokenEndLine < currTokenLine)
                write(" ");
            else if (prevTokenEndLine == currTokenLine || (t == tok!")" && peekIs(tok!"{")))
                write(" ");
            else if (peekBackIsOneOf(false, tok!"else", tok!"identifier"))
                write(" ");
            else if (canAddNewline || (peekIs(tok!"{") && t == tok!"}"))
                newline();

            if (peekIs(tok!"(") && (peekBackIs(tok!")") || peekBack2Is(tok!"!")))
                pushWrapIndent(tok!"(");

            if (peekIs(tok!".") && !indents.topIs(tok!"."))
                indents.push(tok!".");
        }
        writeToken();
        immutable j = justAddedExtraNewline;
        if (currIsSlashSlash)
        {
            newline();
            justAddedExtraNewline = j;
        }
        else if (hasCurrent)
        {
            if (prevTokenEndLine == tokens[index].line)
            {
                if (currentIs(tok!"}"))
                {
                    if (indents.topIs(tok!"{"))
                        indents.pop();
                    write(" ");
                }
                else if (!currentIs(tok!"{"))
                    write(" ");
            }
            else if (!currentIs(tok!"{") && !currentIs(tok!"in") && !currentIs(tok!"out"))
            {
                if (currentIs(tok!")") && indents.topIs(tok!","))
                    indents.pop();
                else if (peekBack2Is(tok!",") && !indents.topIs(tok!",")
                        && indents.indentToMostRecent(tok!"enum") == -1)
                    pushWrapIndent(tok!",");
                newline();
            }
        }
        else
            newline();
    }

    void formatModuleOrImport()
    {
        immutable t = current.type;
        writeToken();
        if (currentIs(tok!"("))
        {
            writeParens(false);
            return;
        }
        write(" ");
        while (hasCurrent)
        {
            if (currentIs(tok!";"))
            {
                indents.popWrapIndents();
                indentLevel = indents.indentLevel;
                writeToken();
                if (index >= tokens.length)
                {
                    newline();
                    break;
                }
                if (currentIs(tok!"comment") && current.line == peekBack().line)
                {
                    break;
                }
                else if (currentIs(tok!"{") && config.dfmt_brace_style == BraceStyle.allman)
                    break;
                else if (t == tok!"import" && !currentIs(tok!"import")
                        && !currentIs(tok!"}")
                            && !((currentIs(tok!"public")
                                || currentIs(tok!"private")
                                || currentIs(tok!"static"))
                            && peekIs(tok!"import")) && !indents.topIsOneOf(tok!"if",
                            tok!"debug", tok!"version"))
                {
                    simpleNewline();
                    currentLineLength = 0;
                    justAddedExtraNewline = true;
                    newline();
                }
                else
                    newline();
                break;
            }
            else if (currentIs(tok!":"))
            {
                if (config.dfmt_selective_import_space)
                    write(" ");
                writeToken();
                if (!currentIs(tok!"comment"))
                    write(" ");
                pushWrapIndent(tok!",");
            }
            else if (currentIs(tok!"comment"))
            {
                if (peekBack.line != current.line)
                {
                    // The comment appears on its own line, keep it there.
                    if (!peekBackIs(tok!"comment"))
                        // Comments are already properly separated.
                        newline();
                }
                formatStep();
            }
            else
                formatStep();
        }
    }

    void formatLeftParenOrBracket()
    in
    {
        assert(currentIs(tok!"(") || currentIs(tok!"["));
    }
    do
    {
        import dfmt.editorconfig : OptionalBoolean;

        immutable p = current.type;
        regenLineBreakHintsIfNecessary(index);
        writeToken();
        if (p == tok!"(")
        {
            ++parenDepthOnLine;
            // If the file starts with an open paren, just give up. This isn't
            // valid D code.
            if (index < 2)
                return;
            if (isBlockHeaderToken(tokens[index - 2].type))
                indents.push(tok!")");
            else
                indents.push(p);
            spaceAfterParens = true;
            parenDepth++;
        }
        // No heuristics apply if we can't look before the opening paren/bracket
        if (index < 1)
            return;
        immutable bool arrayInitializerStart = p == tok!"["
            && astInformation.arrayStartLocations.canFindIndex(tokens[index - 1].index);

        if (arrayInitializerStart && isMultilineAt(index - 1))
        {
            revertParenIndentation();

            // Use the close bracket as the indent token to distinguish
            // the array initialiazer from an array index in the newline
            // handling code
            IndentStack.Details detail;
            detail.wrap = false;
            detail.temp = false;

            // wrap and temp are set manually to the values it would actually
            // receive here because we want to set breakEveryItem for the ] token to know if
            // we should definitely always new-line after every comma for a big AA
            detail.breakEveryItem = astInformation.assocArrayStartLocations.canFindIndex(
                    tokens[index - 1].index);
            detail.preferLongBreaking = true;

            indents.push(tok!"]", detail);
            newline();
            immutable size_t j = expressionEndIndex(index);
            linebreakHints = chooseLineBreakTokens(index, tokens[index .. j],
                    depths[index .. j], config, currentLineLength, indentLevel);
        }
        else if (p == tok!"[" && config.dfmt_keep_line_breaks == OptionalBoolean.t)
        {
            revertParenIndentation();
            IndentStack.Details detail;

            detail.wrap = false;
            detail.temp = false;
            detail.breakEveryItem = false;
            detail.mini = tokens[index].line == tokens[index - 1].line;

            indents.push(tok!"]", detail);
            if (!detail.mini)
            {
                newline();
            }
        }
        else if (arrayInitializerStart)
        {
            // This is a short (non-breaking) array/AA value
            IndentStack.Details detail;
            detail.wrap = false;
            detail.temp = false;

            detail.breakEveryItem = astInformation.assocArrayStartLocations.canFindIndex(tokens[index - 1].index);
            // array of (possibly associative) array, let's put each item on its own line
            if (!detail.breakEveryItem && currentIs(tok!"["))
                detail.breakEveryItem = true;

            // the '[' is immediately followed by an item instead of a newline here so
            // we set mini, that the ']' also follows an item immediately without newline.
            detail.mini = true;

            indents.push(tok!"]", detail);
        }
        else if (p == tok!"[")
        {
            // array item access
            IndentStack.Details detail;
            detail.wrap = false;
            detail.temp = true;
            detail.mini = true;
            indents.push(tok!"]", detail);
        }
        else if (!currentIs(tok!")") && !currentIs(tok!"]")
                && (linebreakHints.canFindIndex(index - 1) || (linebreakHints.length == 0
                    && currentLineLength > config.max_line_length)))
        {
            newline();
        }
        else if (onNextLine)
        {
            newline();
        }
    }

    void revertParenIndentation()
    {
        if (parenDepthOnLine)
        {
            foreach (i; 0 .. parenDepthOnLine)
            {
                indents.pop();
            }
        }
        parenDepthOnLine = 0;
    }

    void formatRightParen()
    in
    {
        assert(currentIs(tok!")"));
    }
    do
    {
        parenDepthOnLine = max(parenDepthOnLine - 1, 0);
        parenDepth--;
        indents.popWrapIndents();
        while (indents.topIsOneOf(tok!"!", tok!")"))
            indents.pop();
        if (indents.topIs(tok!"("))
            indents.pop();
        if (indents.topIs(tok!"."))
            indents.pop();

        if (onNextLine)
        {
            newline();
        }
        if (parenDepth == 0 && (peekIs(tok!"is") || peekIs(tok!"in")
            || peekIs(tok!"out") || peekIs(tok!"do") || peekIsBody))
        {
            writeToken();
        }
        else if (peekIsLiteralOrIdent() || peekIsBasicType())
        {
            writeToken();
            if (spaceAfterParens || parenDepth > 0)
                writeSpace();
        }
        else if ((peekIsKeyword() || peekIs(tok!"@")) && spaceAfterParens
                && !peekIs(tok!"in") && !peekIs(tok!"is") && !peekIs(tok!"if"))
        {
            writeToken();
            writeSpace();
        }
        else
            writeToken();
    }

    void formatRightBracket()
    in
    {
        assert(currentIs(tok!"]"));
    }
    do
    {
        indents.popWrapIndents();
        if (indents.topIs(tok!"]"))
        {
            if (!indents.topDetails.mini && !indents.topDetails.temp)
                newline();
            else
                indents.pop();
        }
        writeToken();
        if (currentIs(tok!"identifier"))
            write(" ");
    }

    void formatAt()
    {
        immutable size_t atIndex = tokens[index].index;
        writeToken();
        if (currentIs(tok!"identifier"))
            writeToken();
        if (currentIs(tok!"("))
        {
            writeParens(false);
            if (tokens[index].type == tok!"{")
                return;

            if (hasCurrent && tokens[index - 1].line < tokens[index].line
                    && astInformation.atAttributeStartLocations.canFindIndex(atIndex))
                newline();
            else
                write(" ");
        }
        else if (hasCurrent && (currentIs(tok!"@")
                || isBasicType(tokens[index].type)
                || currentIs(tok!"invariant")
                || currentIs(tok!"extern")
                || currentIs(tok!"identifier"))
                && !currentIsIndentedTemplateConstraint())
        {
            writeSpace();
        }
    }

    void formatColon()
    {
        import dfmt.editorconfig : OptionalBoolean;
        import std.algorithm : canFind, any;

        immutable bool isCase = astInformation.caseEndLocations.canFindIndex(current.index);
        immutable bool isAttribute = astInformation.attributeDeclarationLines.canFindIndex(
                current.line);
        immutable bool isStructInitializer = astInformation.structInfoSortedByEndLocation
            .canFind!(st => st.startLocation < current.index && current.index < st.endLocation);

        if (isCase || isAttribute)
        {
            writeToken();
            if (!currentIs(tok!"{"))
            {
                if (isCase && !indents.topIs(tok!"case")
                        && config.dfmt_align_switch_statements == OptionalBoolean.f)
                    indents.push(tok!"case");
                else if (isAttribute && !indents.topIs(tok!"@")
                        && config.dfmt_outdent_attributes == OptionalBoolean.f)
                    indents.push(tok!"@");
                newline();
            }
        }
        else if (indents.topIs(tok!"]")) // Associative array
        {
            write(config.dfmt_space_before_aa_colon ? " : " : ": ");
            ++index;
        }
        else if (peekBackIs(tok!"identifier")
                && [tok!"{", tok!"}", tok!";", tok!":", tok!","]
                .any!((ptrdiff_t token) => peekBack2Is(cast(IdType)token, true))
                && (!isBlockHeader(1) || peekIs(tok!"if")))
        {
            writeToken();
            if (isStructInitializer)
                write(" ");
            else if (!currentIs(tok!"{"))
                newline();
        }
        else
        {
            regenLineBreakHintsIfNecessary(index);
            if (peekIs(tok!".."))
                writeToken();
            else if (isBlockHeader(1) && !peekIs(tok!"if"))
            {
                writeToken();
                if (config.dfmt_compact_labeled_statements)
                    write(" ");
                else
                    newline();
            }
            else if (linebreakHints.canFindIndex(index))
            {
                pushWrapIndent();
                newline();
                writeToken();
                write(" ");
            }
            else
            {
                write(" : ");
                index++;
            }
        }
    }

    void formatSemicolon()
    {
        if (inlineElse && !peekIs(tok!"else"))
            inlineElse = false;

        if ((parenDepth > 0 && sBraceDepth == 0) || (sBraceDepth > 0 && niBraceDepth > 0))
        {
            if (currentLineLength > config.dfmt_soft_max_line_length)
            {
                writeToken();
                pushWrapIndent(tok!";");
                newline();
            }
            else
            {
                if (!(peekIs(tok!";") || peekIs(tok!")") || peekIs(tok!"}")))
                    write("; ");
                else
                    write(";");
                index++;
            }
        }
        else
        {
            writeToken();
            indents.popWrapIndents();
            linebreakHints = [];
            while (indents.topIsOneOf(tok!"enum", tok!"try", tok!"catch", tok!"finally", tok!"debug"))
                indents.pop();
            if (indents.topAre(tok!"static", tok!"else"))
            {
                indents.pop();
                indents.pop();
            }
            indentLevel = indents.indentLevel;
            if (config.dfmt_brace_style == BraceStyle.allman)
            {
                if (!currentIs(tok!"{"))
                    newline();
            }
            else
            {
                if (currentIs(tok!"{"))
                    indents.popTempIndents();
                indentLevel = indents.indentLevel;
                newline();
            }
        }
    }

    void formatLeftBrace()
    {
        import std.algorithm : map, sum, canFind;

        auto tIndex = tokens[index].index;

        if (astInformation.structInitStartLocations.canFindIndex(tIndex))
        {
            sBraceDepth++;
            immutable bool multiline = isMultilineAt(index);
            writeToken();
            if (multiline)
            {
                import std.algorithm.searching : find;

                auto indentInfo = astInformation.indentInfoSortedByEndLocation
                    .find!((a,b) => a.startLocation == b)(tIndex);
                assert(indentInfo.length > 0);
                cast()indentInfo[0].flags |= BraceIndentInfoFlags.tempIndent;
                cast()indentInfo[0].beginIndentLevel = indents.indentLevel;

                indents.push(tok!"{");
                newline();
            }
            else
                niBraceDepth++;
        }
        else if (astInformation.funLitStartLocations.canFindIndex(tIndex))
        {
            indents.popWrapIndents();

            sBraceDepth++;
            if (peekBackIsOneOf(true, tok!")", tok!"identifier"))
                write(" ");
            immutable bool multiline = isMultilineAt(index);
            writeToken();
            if (multiline)
            {
                indents.push(tok!"{");
                newline();
            }
            else
            {
                niBraceDepth++;
                if (!currentIs(tok!"}"))
                    write(" ");
            }
        }
        else
        {
            if (peekBackIsSlashSlash())
            {
                if (peekBack2Is(tok!";"))
                {
                    indents.popTempIndents();
                    indentLevel = indents.indentLevel - 1;
                }
                writeToken();
            }
            else
            {
                if (indents.topIsTemp && indents.indentToMostRecent(tok!"static") == -1)
                    indentLevel = indents.indentLevel - 1;
                else
                    indentLevel = indents.indentLevel;
                if (config.dfmt_brace_style == BraceStyle.allman
                        || peekBackIsOneOf(true, tok!"{", tok!"}"))
                    newline();
                else if (config.dfmt_brace_style == BraceStyle.knr
                        && astInformation.funBodyLocations.canFindIndex(tIndex)
                        && (peekBackIs(tok!")") || (!peekBackIs(tok!"do") && peekBack().text != "body")))
                    newline();
                else if (!peekBackIsOneOf(true, tok!"{", tok!"}", tok!";"))
                    write(" ");
                writeToken();
            }
            indents.push(tok!"{");
            if (!currentIs(tok!"{"))
                newline();
            linebreakHints = [];
        }
    }

    void formatRightBrace()
    {
        void popToBeginIndent(BraceIndentInfo indentInfo)
        {
            foreach(i; indentInfo.beginIndentLevel .. indents.indentLevel)
            {
                indents.pop();
            }

            indentLevel = indentInfo.beginIndentLevel;
        }

        size_t pos;
        if (astInformation.structInitEndLocations.canFindIndex(tokens[index].index, &pos))
        {
            if (sBraceDepth > 0)
                sBraceDepth--;
            if (niBraceDepth > 0)
                niBraceDepth--;

            auto indentInfo = astInformation.indentInfoSortedByEndLocation[pos];
            if (indentInfo.flags & BraceIndentInfoFlags.tempIndent)
            {
                popToBeginIndent(indentInfo);
                simpleNewline();
                indent();
            }
            writeToken();
        }
        else if (astInformation.funLitEndLocations.canFindIndex(tokens[index].index, &pos))
        {
            if (niBraceDepth > 0)
            {
                if (!peekBackIsSlashSlash() && !peekBackIs(tok!"{"))
                    write(" ");
                niBraceDepth--;
            }
            if (sBraceDepth > 0)
                sBraceDepth--;
            writeToken();
        }
        else
        {
            // Silly hack to format enums better.
            if ((peekBackIsLiteralOrIdent() || peekBackIsOneOf(true, tok!")",
                    tok!",")) && !peekBackIsSlashSlash())
                newline();
            write("}");
            if (index + 1 < tokens.length
                    && astInformation.doubleNewlineLocations.canFindIndex(tokens[index].index)
                    && !peekIs(tok!"}") && !peekIs(tok!"else")
                    && !peekIs(tok!";") && !peekIs(tok!"comment", false))
            {
                simpleNewline();
                currentLineLength = 0;
                justAddedExtraNewline = true;
            }
            if (config.dfmt_brace_style.among(BraceStyle.otbs, BraceStyle.knr)
                    && ((peekIs(tok!"else")
                            && !indents.topAre(tok!"static", tok!"if")
                            && !indents.topIs(tok!"foreach") && !indents.topIs(tok!"for")
                            && !indents.topIs(tok!"while") && !indents.topIs(tok!"do"))
                        || peekIs(tok!"catch") || peekIs(tok!"finally")))
            {
                write(" ");
                index++;
            }
            else
            {
                if (!peekIs(tok!",") && !peekIs(tok!")")
                        && !peekIs(tok!";") && !peekIs(tok!"{"))
                {
                    index++;
                    if (indents.topIs(tok!"static"))
                        indents.pop();
                    newline();
                }
                else
                    index++;
            }
        }
    }

    void formatSwitch()
    {
        while (indents.topIs(tok!"with"))
            indents.pop();
        indents.push(tok!"switch");
        writeToken(); // switch
        write(" ");
    }

    void formatBlockHeader()
    {
        if (indents.topIs(tok!"!"))
            indents.pop();
        immutable bool a = !currentIs(tok!"version") && !currentIs(tok!"debug");
        immutable bool b = a
            || astInformation.conditionalWithElseLocations.canFindIndex(current.index);
        immutable bool c = b
            || astInformation.conditionalStatementLocations.canFindIndex(current.index);
        immutable bool shouldPushIndent = (c || peekBackIs(tok!"else"))
            && !(currentIs(tok!"if") && indents.topIsWrap());
        if (currentIs(tok!"out") && !peekBackIs(tok!"}"))
            newline();
        if (shouldPushIndent)
        {
            if (peekBackIs(tok!"static"))
            {
                if (indents.topIs(tok!"else"))
                    indents.pop();
                if (!indents.topIs(tok!"static"))
                    indents.push(tok!"static");
            }
            indents.push(current.type);
        }
        writeToken();

        if (currentIs(tok!"("))
        {
            write(" ");
            writeParens(false);
        }

        if (hasCurrent)
        {
            if (currentIs(tok!"switch") || (currentIs(tok!"final") && peekIs(tok!"switch")))
                write(" ");
            else if (currentIs(tok!"comment"))
                formatStep();
            else if (!shouldPushIndent)
            {
                if (!currentIs(tok!"{") && !currentIs(tok!";"))
                    write(" ");
            }
            else if (hasCurrent && !currentIs(tok!"{") && !currentIs(tok!";") && !currentIs(tok!"in") &&
                !currentIs(tok!"out") && !currentIs(tok!"do") && current.text != "body")
            {
                newline();
            }
            else if (currentIs(tok!"{") && indents.topAre(tok!"static", tok!"if"))
            {
                // Hacks to format braced vs non-braced static if declarations.
                indents.pop();
                indents.pop();
                indents.push(tok!"if");
                formatLeftBrace();
            }
            else if (currentIs(tok!"{") && indents.topAre(tok!"static", tok!"foreach"))
            {
                indents.pop();
                indents.pop();
                indents.push(tok!"foreach");
                formatLeftBrace();
            }
            else if (currentIs(tok!"{") && indents.topAre(tok!"static", tok!"foreach_reverse"))
            {
                indents.pop();
                indents.pop();
                indents.push(tok!"foreach_reverse");
                formatLeftBrace();
            }
        }
    }

    void formatElse()
    {
        writeToken();
        if (inlineElse || currentIs(tok!"if") || currentIs(tok!"version")
                || (currentIs(tok!"static") && peekIs(tok!"if")))
        {
            if (indents.topIs(tok!"if") || indents.topIs(tok!"version"))
                indents.pop();
            inlineElse = false;
            write(" ");
        }
        else if (currentIs(tok!":"))
        {
            writeToken();
            newline();
        }
        else if (!currentIs(tok!"{") && !currentIs(tok!"comment"))
        {
            //indents.dump();
            while (indents.topIsOneOf(tok!"foreach", tok!"for", tok!"while"))
                indents.pop();
            if (indents.topIsOneOf(tok!"if", tok!"version"))
                indents.pop();
            indents.push(tok!"else");
            newline();
        }
        else if (currentIs(tok!"{") && indents.topAre(tok!"static", tok!"if"))
        {
            indents.pop();
            indents.pop();
            indents.push(tok!"else");
        }
    }

    void formatKeyword()
    {
        import dfmt.editorconfig : OptionalBoolean;

        switch (current.type)
        {
        case tok!"default":
            writeToken();
            break;
        case tok!"cast":
            writeToken();
            if (currentIs(tok!"("))
                writeParens(config.dfmt_space_after_cast == OptionalBoolean.t);
            break;
        case tok!"out":
            if (!peekBackIsSlashSlash) {
                if (!peekBackIs(tok!"}")
                        && astInformation.contractLocations.canFindIndex(current.index))
                    newline();
                else if (peekBackIsKeyword)
                    write(" ");
            }
            writeToken();
            if (!currentIs(tok!"{") && !currentIs(tok!"comment"))
                write(" ");
            break;
        case tok!"try":
        case tok!"finally":
            indents.push(current.type);
            writeToken();
            if (!currentIs(tok!"{"))
                newline();
            break;
        case tok!"identifier":
            if (current.text == "body")
                goto case tok!"do";
            else
                goto default;
        case tok!"do":
            if (!peekBackIs(tok!"}"))
                newline();
            writeToken();
            break;
        case tok!"in":
            immutable isContract = astInformation.contractLocations.canFindIndex(current.index);
            if (!peekBackIsSlashSlash) {
                if (isContract)
                {
                    indents.popTempIndents();
                    newline();
                }
                else if (!peekBackIsOneOf(false, tok!"(", tok!",", tok!"!"))
                    write(" ");
            }
            writeToken();
            immutable isFunctionLit = astInformation.funLitStartLocations.canFindIndex(
                    current.index);
            if (isFunctionLit && config.dfmt_brace_style == BraceStyle.allman)
                newline();
            else if (!isContract || currentIs(tok!"("))
                write(" ");
            break;
        case tok!"is":
            if (!peekBackIsOneOf(false, tok!"!", tok!"(", tok!",",
                    tok!"}", tok!"=", tok!"&&", tok!"||") && !peekBackIsKeyword())
                write(" ");
            writeToken();
            if (!currentIs(tok!"(") && !currentIs(tok!"{") && !currentIs(tok!"comment"))
                write(" ");
            break;
        case tok!"case":
            writeToken();
            if (!currentIs(tok!";"))
                write(" ");
            break;
        case tok!"enum":
            if (peekIs(tok!")") || peekIs(tok!"=="))
            {
                writeToken();
            }
            else
            {
                if (peekBackIs(tok!"identifier"))
                    write(" ");
                indents.push(tok!"enum");
                writeToken();
                if (!currentIs(tok!":") && !currentIs(tok!"{"))
                    write(" ");
            }
            break;
        case tok!"static":
            {
                if (astInformation.staticConstructorDestructorLocations
                    .canFindIndex(current.index))
                {
                    thisSpace = true;
                }
            }
            goto default;
        case tok!"shared":
            {
                if (astInformation.sharedStaticConstructorDestructorLocations
                    .canFindIndex(current.index))
                {
                    thisSpace = true;
                }
            }
            goto default;
        case tok!"invariant":
            writeToken();
            if (currentIs(tok!"("))
                write(" ");
            break;
        default:
            if (peekBackIs(tok!"identifier"))
            {
                writeSpace();
            }
            if (index + 1 < tokens.length)
            {
                if (!peekIs(tok!"@") && (peekIsOperator()
                        || peekIs(tok!"out") || peekIs(tok!"in")))
                {
                    writeToken();
                }
                else
                {
                    writeToken();
                    if (!currentIsIndentedTemplateConstraint())
                    {
                        writeSpace();
                    }
                }
            }
            else
                writeToken();
            break;
        }
    }

    bool currentIsIndentedTemplateConstraint()
    {
        return hasCurrent
            && astInformation.constraintLocations.canFindIndex(current.index)
            && (config.dfmt_template_constraint_style == TemplateConstraintStyle.always_newline
                || config.dfmt_template_constraint_style == TemplateConstraintStyle.always_newline_indent
                || currentLineLength >= config.dfmt_soft_max_line_length);
    }

    void formatOperator()
    {
        import dfmt.editorconfig : OptionalBoolean;
        import std.algorithm : canFind;

        switch (current.type)
        {
        case tok!"*":
            if (astInformation.spaceAfterLocations.canFindIndex(current.index))
            {
                writeToken();
                if (!currentIs(tok!"*") && !currentIs(tok!")")
                        && !currentIs(tok!"[") && !currentIs(tok!",") && !currentIs(tok!";"))
                {
                    write(" ");
                }
                break;
            }
            else if (astInformation.unaryLocations.canFindIndex(current.index))
            {
                writeToken();
                break;
            }
            regenLineBreakHintsIfNecessary(index);
            goto binary;
        case tok!"~":
            if (peekIs(tok!"this") && peek2Is(tok!"("))
            {
                if (!(index == 0 || peekBackIs(tok!"{", true)
                        || peekBackIs(tok!"}", true) || peekBackIs(tok!";", true)))
                {
                    write(" ");
                }
                writeToken();
                break;
            }
            goto case;
        case tok!"&":
        case tok!"+":
        case tok!"-":
            if (astInformation.unaryLocations.canFindIndex(current.index))
            {
                writeToken();
                break;
            }
            regenLineBreakHintsIfNecessary(index);
            goto binary;
        case tok!"[":
        case tok!"(":
            formatLeftParenOrBracket();
            break;
        case tok!")":
            formatRightParen();
            break;
        case tok!"@":
            formatAt();
            break;
        case tok!"!":
            if (((peekIs(tok!"is") || peekIs(tok!"in"))
                    && !peekBackIsOperator()) || peekBackIs(tok!")"))
                write(" ");
            goto case;
        case tok!"...":
        case tok!"++":
        case tok!"--":
        case tok!"$":
            writeToken();
            break;
        case tok!":":
            formatColon();
            break;
        case tok!"]":
            formatRightBracket();
            break;
        case tok!";":
            formatSemicolon();
            break;
        case tok!"{":
            formatLeftBrace();
            break;
        case tok!"}":
            formatRightBrace();
            break;
        case tok!".":
            regenLineBreakHintsIfNecessary(index);
            immutable bool ufcsWrap = astInformation.ufcsHintLocations.canFindIndex(current.index);
            if (ufcsWrap || linebreakHints.canFind(index) || onNextLine
                    || (linebreakHints.length == 0 && currentLineLength + nextTokenLength() > config.max_line_length))
            {
                if (!indents.topIs(tok!"."))
                    indents.push(tok!".");
                if (!peekBackIs(tok!"comment"))
                    newline();
                if (ufcsWrap || onNextLine)
                    regenLineBreakHints(index);
            }
            writeToken();
            break;
        case tok!",":
            formatComma();
            break;
        case tok!"&&":
        case tok!"||":
        case tok!"|":
            regenLineBreakHintsIfNecessary(index);
            goto case;
        case tok!"=":
        case tok!">=":
        case tok!">>=":
        case tok!">>>=":
        case tok!"|=":
        case tok!"-=":
        case tok!"/=":
        case tok!"*=":
        case tok!"&=":
        case tok!"%=":
        case tok!"+=":
        case tok!"^^":
        case tok!"^=":
        case tok!"^":
        case tok!"~=":
        case tok!"<<=":
        case tok!"<<":
        case tok!"<=":
        case tok!"<>=":
        case tok!"<>":
        case tok!"<":
        case tok!"==":
        case tok!"=>":
        case tok!">>>":
        case tok!">>":
        case tok!">":
        case tok!"!<=":
        case tok!"!<>=":
        case tok!"!<>":
        case tok!"!<":
        case tok!"!=":
        case tok!"!>=":
        case tok!"!>":
        case tok!"?":
        case tok!"/":
        case tok!"..":
        case tok!"%":
        binary:
            immutable bool isWrapToken = linebreakHints.canFind(index);
            if (config.dfmt_keep_line_breaks == OptionalBoolean.t && index > 0)
            {
                const operatorLine = tokens[index].line;
                const rightOperandLine = tokens[index + 1].line;

                if (tokens[index - 1].line < operatorLine)
                {
                    if (!indents.topIs(tok!"enum"))
                        pushWrapIndent();
                    if (!peekBackIs(tok!"comment"))
                        newline();
                }
                else
                {
                    write(" ");
                }
                if (rightOperandLine > operatorLine
                        && !indents.topIs(tok!"enum"))
                {
                    pushWrapIndent();
                }
                writeToken();

                if (rightOperandLine > operatorLine)
                {
                    if (!peekBackIs(tok!"comment"))
                        newline();
                }
                else
                {
                    write(" ");
                }
            }
            else if (config.dfmt_split_operator_at_line_end)
            {
                if (isWrapToken)
                {
                    if (!indents.topIs(tok!"enum"))
                        pushWrapIndent();
                    write(" ");
                    writeToken();
                    newline();
                }
                else
                {
                    write(" ");
                    writeToken();
                    if (!currentIs(tok!"comment"))
                        write(" ");
                }
            }
            else
            {
                if (isWrapToken)
                {
                    if (!indents.topIs(tok!"enum"))
                        pushWrapIndent();
                    newline();
                    writeToken();
                }
                else
                {
                    write(" ");
                    writeToken();
                }
                if (!currentIs(tok!"comment"))
                    write(" ");
            }
            break;
        default:
            writeToken();
            break;
        }
    }

    void formatComma()
    {
        import dfmt.editorconfig : OptionalBoolean;
        import std.algorithm : canFind;

        if (config.dfmt_keep_line_breaks == OptionalBoolean.f)
            regenLineBreakHintsIfNecessary(index);
        if (indents.indentToMostRecent(tok!"enum") != -1
                && !peekIs(tok!"}") && indents.topIs(tok!"{") && parenDepth == 0)
        {
            writeToken();
            newline();
        }
        else if (indents.topIs(tok!"]") && indents.topDetails.breakEveryItem
                && !indents.topDetails.mini)
        {
            writeToken();
            newline();
            regenLineBreakHints(index - 1);
        }
        else if (indents.topIs(tok!"]") && indents.topDetails.preferLongBreaking
                && !currentIs(tok!")") && !currentIs(tok!"]") && !currentIs(tok!"}")
                && !currentIs(tok!"comment") && index + 1 < tokens.length
                && isMultilineAt(index + 1, true))
        {
            writeToken();
            newline();
            regenLineBreakHints(index - 1);
        }
        else if (config.dfmt_keep_line_breaks == OptionalBoolean.t)
        {
            const commaLine = tokens[index].line;

            writeToken();
            if (indents.topIs(tok!"."))
            {
                indents.pop;
            }
            if (!currentIs(tok!")") && !currentIs(tok!"]")
                    && !currentIs(tok!"}") && !currentIs(tok!"comment"))
            {
                if (tokens[index].line == commaLine)
                {
                    write(" ");
                }
                else
                {
                    newline();
                }
            }
        }
        else if (!peekIs(tok!"}") && (linebreakHints.canFind(index)
                || (linebreakHints.length == 0 && currentLineLength > config.max_line_length)))
        {
            pushWrapIndent();
            writeToken();
            if (indents.topIs(tok!"."))
            {
                indents.pop;
            }
            newline();
        }
        else
        {
            writeToken();
            if (!currentIs(tok!")") && !currentIs(tok!"]")
                    && !currentIs(tok!"}") && !currentIs(tok!"comment"))
            {
                write(" ");
            }
        }
        regenLineBreakHintsIfNecessary(index - 1);
    }

    void regenLineBreakHints(immutable size_t i)
    {
        import std.range : assumeSorted;
        import std.algorithm.comparison : min;
        import std.algorithm.searching : canFind, countUntil;

        // The end of the tokens considered by the line break algorithm is
        // either the expression end index or the next mandatory line break
        // or a newline inside a string literal, whichever is first.
        auto r = assumeSorted(astInformation.ufcsHintLocations).upperBound(tokens[i].index);
        immutable ufcsBreakLocation = r.empty
            ? size_t.max
            : tokens[i .. $].countUntil!(t => t.index == r.front) + i;
        immutable multilineStringLocation = tokens[i .. $]
            .countUntil!(t => t.text.canFind('\n'));
        immutable size_t j = min(
                expressionEndIndex(i),
                ufcsBreakLocation,
                multilineStringLocation == -1 ? size_t.max : multilineStringLocation + i + 1);
        // Use magical negative value for array literals and wrap indents
        immutable inLvl = (indents.topIsWrap() || indents.topIs(tok!"]")) ? -indentLevel
            : indentLevel;
        linebreakHints = chooseLineBreakTokens(i, tokens[i .. j], depths[i .. j],
                config, currentLineLength, inLvl);
    }

    void regenLineBreakHintsIfNecessary(immutable size_t i)
    {
        if (linebreakHints.length == 0 || linebreakHints[$ - 1] <= i - 1)
            regenLineBreakHints(i);
    }

    void simpleNewline()
    {
        import dfmt.editorconfig : EOL;

        output.put(eolString);
    }

    void newline()
    {
        import std.range : assumeSorted;
        import std.algorithm : max, canFind;
        import dfmt.editorconfig : OptionalBoolean;

        if (currentIs(tok!"comment") && index > 0 && current.line == tokenEndLine(tokens[index - 1]))
            return;

        immutable bool hasCurrent = this.hasCurrent;

        if (niBraceDepth > 0 && !peekBackIsSlashSlash() && hasCurrent && tokens[index].type == tok!"}"
                && !assumeSorted(astInformation.funLitEndLocations).equalRange(
                    tokens[index].index).empty)
        {
            return;
        }

        simpleNewline();

        if (!justAddedExtraNewline && index > 0 && hasCurrent
                && tokens[index].line - tokenEndLine(tokens[index - 1]) > 1)
        {
            simpleNewline();
        }

        justAddedExtraNewline = false;
        currentLineLength = 0;

        if (hasCurrent)
        {
            if (currentIs(tok!"else"))
            {
                immutable i = indents.indentToMostRecent(tok!"if");
                immutable v = indents.indentToMostRecent(tok!"version");
                immutable mostRecent = max(i, v);
                if (mostRecent != -1)
                    indentLevel = mostRecent;
            }
            else if (currentIs(tok!"identifier") && peekIs(tok!":"))
            {
                if (peekBackIs(tok!"}", true) || peekBackIs(tok!";", true))
                    indents.popTempIndents();
                immutable l = indents.indentToMostRecent(tok!"switch");
                if (l != -1 && config.dfmt_align_switch_statements == OptionalBoolean.t)
                    indentLevel = l;
                else if (astInformation.structInfoSortedByEndLocation
                    .canFind!(st => st.startLocation < current.index && current.index < st.endLocation)) {
                    immutable l2 = indents.indentToMostRecent(tok!"{");
                    assert(l2 != -1, "Recent '{' is not found despite being in struct initializer");
                    indentLevel = l2 + 1;
                }
                else if ((config.dfmt_compact_labeled_statements == OptionalBoolean.f
                        || !isBlockHeader(2) || peek2Is(tok!"if")) && !indents.topIs(tok!"]"))
                {
                    immutable l2 = indents.indentToMostRecent(tok!"{");
                    indentLevel = l2 != -1 ? l2 : indents.indentLevel - 1;
                }
                else
                    indentLevel = indents.indentLevel;
            }
            else if (currentIs(tok!"case") || currentIs(tok!"default"))
            {

                if (peekBackIs(tok!"}", true) || peekBackIs(tok!";", true)
                    /**
                     * The following code is valid and should be indented flatly
                     * case A:
                     * case B:
                     */
                    || peekBackIs(tok!":", true))
                {
                    indents.popTempIndents();
                    if (indents.topIs(tok!"case"))
                        indents.pop();
                }
                immutable l = indents.indentToMostRecent(tok!"switch");
                if (l != -1)
                    indentLevel = config.dfmt_align_switch_statements == OptionalBoolean.t
                        ? l : indents.indentLevel;
            }
            else if (currentIs(tok!")"))
            {
                if (indents.topIs(tok!"("))
                    indents.pop();
                indentLevel = indents.indentLevel;
            }
            else if (currentIs(tok!"{"))
            {
                indents.popWrapIndents();
                if ((peekBackIsSlashSlash() && peekBack2Is(tok!";")) || indents.topIs(tok!"]"))
                {
                    indents.popTempIndents();
                    indentLevel = indents.indentLevel;
                }
            }
            else if (currentIs(tok!"}"))
            {
                indents.popTempIndents();
                while (indents.topIsOneOf(tok!"case", tok!"@", tok!"static"))
                    indents.pop();
                if (indents.topIs(tok!"{"))
                {
                    indentLevel = indents.indentToMostRecent(tok!"{");
                    indents.pop();
                }
                if (indents.topIsOneOf(tok!"try", tok!"catch"))
                {
                    indents.pop();
                }
                else while (sBraceDepth == 0 && indents.topIsTemp()
                        && ((!indents.topIsOneOf(tok!"else", tok!"if",
                            tok!"static", tok!"version")) || !peekIs(tok!"else")))
                {
                    indents.pop();
                }
            }
            else if (currentIs(tok!"]"))
            {
                indents.popWrapIndents();
                if (indents.topIs(tok!"]"))
                {
                    indents.pop();
                }
                // Find the initial indentation of constructs like "if" and
                // "foreach" without removing them from the stack, since they
                // still can be used later to indent "else".
                auto savedIndents = IndentStack(config);
                while (indents.length >= 0 && indents.topIsTemp) {
                    savedIndents.push(indents.top, indents.topDetails);
                    indents.pop;
                }
                indentLevel = indents.indentLevel;
                while (savedIndents.length > 0) {
                    indents.push(savedIndents.top, savedIndents.topDetails);
                    savedIndents.pop;
                }
            }
            else if (astInformation.attributeDeclarationLines.canFindIndex(current.line))
            {
                if (config.dfmt_outdent_attributes == OptionalBoolean.t)
                {
                    immutable l = indents.indentToMostRecent(tok!"{");
                    if (l != -1)
                        indentLevel = l;
                }
                else
                {
                    if (indents.topIs(tok!"@"))
                        indents.pop();
                    indentLevel = indents.indentLevel;
                }
            }
            else if (currentIs(tok!"catch") || currentIs(tok!"finally"))
            {
                indentLevel = indents.indentLevel;
            }
            else
            {
                if (indents.topIsTemp() && (peekBackIsOneOf(true, tok!"}",
                        tok!";") && !indents.topIs(tok!";")))
                    indents.popTempIndents();
                indentLevel = indents.indentLevel;
            }
            indent();
        }
        parenDepthOnLine = 0;
    }

    void write(string str)
    {
        currentLineLength += str.length;
        output.put(str);
    }

    void writeToken()
    {
        import std.range:retro;
        import std.algorithm.searching:countUntil;
        import std.algorithm.iteration:joiner;
        import std.string:lineSplitter;

        if (current.text is null)
        {
            immutable s = str(current.type);
            currentLineLength += s.length;
            output.put(str(current.type));
        }
        else
        {
            output.put(current.text.lineSplitter.joiner(eolString));
            switch (current.type)
            {
            case tok!"stringLiteral":
            case tok!"wstringLiteral":
            case tok!"dstringLiteral":
                immutable o = current.text.retro().countUntil('\n');
                if (o == -1) {
                    currentLineLength += current.text.length;
                } else {
                    currentLineLength = cast(uint) o;
                }
                break;
            default:
                currentLineLength += current.text.length;
                break;
            }
        }
        index++;
    }

    void writeParens(bool spaceAfter)
    in
    {
        assert(currentIs(tok!"("), str(current.type));
    }
    do
    {
        immutable int depth = parenDepth;
        immutable int startingNiBraceDepth = niBraceDepth;
        immutable int startingSBraceDepth = sBraceDepth;
        parenDepth = 0;

        do
        {
            spaceAfterParens = spaceAfter;
            if (currentIs(tok!";") && niBraceDepth <= startingNiBraceDepth
                    && sBraceDepth <= startingSBraceDepth)
            {
                if (currentLineLength >= config.dfmt_soft_max_line_length)
                {
                    pushWrapIndent();
                    writeToken();
                    newline();
                }
                else
                {
                    writeToken();
                    if (!currentIs(tok!")") && !currentIs(tok!";"))
                        write(" ");
                }
            }
            else
                formatStep();
        }
        while (hasCurrent && parenDepth > 0);

        if (indents.topIs(tok!"!"))
            indents.pop();
        parenDepth = depth;
        spaceAfterParens = spaceAfter;
    }

    void indent()
    {
        import dfmt.editorconfig : IndentStyle;

        if (config.indent_style == IndentStyle.tab)
        {
            foreach (i; 0 .. indentLevel)
            {
                currentLineLength += config.tab_width;
                output.put("\t");
            }
        }
        else
        {
            foreach (i; 0 .. indentLevel)
                foreach (j; 0 .. config.indent_size)
                {
                    output.put(" ");
                    currentLineLength++;
                }
        }
    }

    void pushWrapIndent(IdType type = tok!"")
    {
        immutable t = type == tok!"" ? tokens[index].type : type;
        IndentStack.Details detail;
        detail.wrap = isWrapIndent(t);
        detail.temp = isTempIndent(t);
        pushWrapIndent(t, detail);
    }

    void pushWrapIndent(IdType type, IndentStack.Details detail)
    {
        if (parenDepth == 0)
        {
            if (indents.wrapIndents == 0)
                indents.push(type, detail);
        }
        else if (indents.wrapIndents < 1)
            indents.push(type, detail);
    }

    void writeSpace()
    {
        if (onNextLine)
        {
            newline();
        }
        else
        {
            write(" ");
        }
    }

const pure @safe @nogc:

    size_t expressionEndIndex(size_t i, bool matchComma = false) nothrow
    {
        immutable bool braces = i < tokens.length && tokens[i].type == tok!"{";
        immutable bool brackets = i < tokens.length && tokens[i].type == tok!"[";
        immutable d = depths[i];
        while (true)
        {
            if (i >= tokens.length)
                break;
            if (depths[i] < d)
                break;
            if (!braces && !brackets && matchComma && depths[i] == d && tokens[i].type == tok!",")
                break;
            if (!braces && !brackets && (tokens[i].type == tok!";" || tokens[i].type == tok!"{"))
                break;
            i++;
        }
        return i;
    }

    /// Returns: true when the expression starting at index goes over the line length limit.
    /// Uses matching `{}` or `[]` or otherwise takes everything up until a semicolon or opening brace using expressionEndIndex.
    bool isMultilineAt(size_t i, bool matchComma = false)
    {
        import std.algorithm : map, sum, canFind;

        auto e = expressionEndIndex(i, matchComma);
        immutable int l = currentLineLength + tokens[i .. e].map!(a => tokenLength(a)).sum();
        return l > config.dfmt_soft_max_line_length || tokens[i .. e].canFind!(
                a => a.type == tok!"comment" || isBlockHeaderToken(a.type))();
    }

    bool peekIsKeyword() nothrow
    {
        return index + 1 < tokens.length && isKeyword(tokens[index + 1].type);
    }

    bool peekIsBasicType() nothrow
    {
        return index + 1 < tokens.length && isBasicType(tokens[index + 1].type);
    }

    bool peekIsLabel() nothrow
    {
        return peekIs(tok!"identifier") && peek2Is(tok!":");
    }

    int currentTokenLength()
    {
        return tokenLength(tokens[index]);
    }

    int nextTokenLength()
    {
        immutable size_t i = index + 1;
        if (i >= tokens.length)
            return INVALID_TOKEN_LENGTH;
        return tokenLength(tokens[i]);
    }

    bool hasCurrent() nothrow const
    {
        return index < tokens.length;
    }

    ref current() nothrow
    in
    {
        assert(hasCurrent);
    }
    do
    {
        return tokens[index];
    }

    const(Token) peekBack(uint distance = 1) nothrow
    {
        assert(index >= distance, "Trying to peek before the first token");
        return tokens[index - distance];
    }

    bool peekBackIsLiteralOrIdent() nothrow
    {
        if (index == 0)
            return false;
        switch (tokens[index - 1].type)
        {
        case tok!"doubleLiteral":
        case tok!"floatLiteral":
        case tok!"idoubleLiteral":
        case tok!"ifloatLiteral":
        case tok!"intLiteral":
        case tok!"longLiteral":
        case tok!"realLiteral":
        case tok!"irealLiteral":
        case tok!"uintLiteral":
        case tok!"ulongLiteral":
        case tok!"characterLiteral":
        case tok!"identifier":
        case tok!"stringLiteral":
        case tok!"wstringLiteral":
        case tok!"dstringLiteral":
        case tok!"true":
        case tok!"false":
            return true;
        default:
            return false;
        }
    }

    bool peekIsLiteralOrIdent() nothrow
    {
        if (index + 1 >= tokens.length)
            return false;
        switch (tokens[index + 1].type)
        {
        case tok!"doubleLiteral":
        case tok!"floatLiteral":
        case tok!"idoubleLiteral":
        case tok!"ifloatLiteral":
        case tok!"intLiteral":
        case tok!"longLiteral":
        case tok!"realLiteral":
        case tok!"irealLiteral":
        case tok!"uintLiteral":
        case tok!"ulongLiteral":
        case tok!"characterLiteral":
        case tok!"identifier":
        case tok!"stringLiteral":
        case tok!"wstringLiteral":
        case tok!"dstringLiteral":
            return true;
        default:
            return false;
        }
    }

    bool peekBackIs(IdType tokenType, bool ignoreComments = false) nothrow
    {
        return peekImplementation(tokenType, -1, ignoreComments);
    }

    bool peekBackIsKeyword(bool ignoreComments = true) nothrow
    {
        if (index == 0)
            return false;
        auto i = index - 1;
        if (ignoreComments)
            while (tokens[i].type == tok!"comment")
            {
                if (i == 0)
                    return false;
                i--;
            }
        return isKeyword(tokens[i].type);
    }

    bool peekBackIsOperator() nothrow
    {
        return index == 0 ? false : isOperator(tokens[index - 1].type);
    }

    bool peekBackIsOneOf(bool ignoreComments, IdType[] tokenTypes...) nothrow
    {
        if (index == 0)
            return false;
        auto i = index - 1;
        if (ignoreComments)
            while (tokens[i].type == tok!"comment")
            {
                if (i == 0)
                    return false;
                i--;
            }
        immutable t = tokens[i].type;
        foreach (tt; tokenTypes)
            if (tt == t)
                return true;
        return false;
    }

    bool peekBack2Is(IdType tokenType, bool ignoreComments = false) nothrow
    {
        return peekImplementation(tokenType, -2, ignoreComments);
    }

    bool peekImplementation(IdType tokenType, int n, bool ignoreComments = true) nothrow
    {
        auto i = index + n;
        if (ignoreComments)
            while (n != 0 && i < tokens.length && tokens[i].type == tok!"comment")
                i = n > 0 ? i + 1 : i - 1;
        return i < tokens.length && tokens[i].type == tokenType;
    }

    bool peek2Is(IdType tokenType, bool ignoreComments = true) nothrow
    {
        return peekImplementation(tokenType, 2, ignoreComments);
    }

    bool peekIsOperator() nothrow
    {
        return index + 1 < tokens.length && isOperator(tokens[index + 1].type);
    }

    bool peekIs(IdType tokenType, bool ignoreComments = true) nothrow
    {
        return peekImplementation(tokenType, 1, ignoreComments);
    }

    bool peekIsBody() nothrow
    {
        return index + 1 < tokens.length && tokens[index + 1].text == "body";
    }

    bool peekBackIsFunctionDeclarationEnding() nothrow
    {
        return peekBackIsOneOf(false, tok!")", tok!"const", tok!"immutable",
            tok!"inout", tok!"shared", tok!"@", tok!"pure", tok!"nothrow",
            tok!"return", tok!"scope");
    }

    bool peekBackIsSlashSlash() nothrow
    {
        return index > 0 && tokens[index - 1].type == tok!"comment"
            && tokens[index - 1].text[0 .. 2] == "//";
    }

    bool currentIs(IdType tokenType) nothrow
    {
        return hasCurrent && tokens[index].type == tokenType;
    }

    bool onNextLine() @nogc nothrow pure @safe
    {
        import dfmt.editorconfig : OptionalBoolean;
        import std.algorithm.searching : count;
        import std.string : representation;

        if (config.dfmt_keep_line_breaks == OptionalBoolean.f || index <= 0)
        {
            return false;
        }
        // To compare whether 2 tokens are on same line, we need the end line
        // of the first token (tokens[index - 1]) and the start line of the
        // second one (tokens[index]). If a token takes multiple lines (e.g. a
        // multi-line string), we can sum the number of the newlines in the
        // token and tokens[index - 1].line, the start line.
        const previousTokenEndLineNo = tokens[index - 1].line
                + tokens[index - 1].text.representation.count('\n');

        return previousTokenEndLineNo < tokens[index].line;
    }

    /// Bugs: not unicode correct
    size_t tokenEndLine(const Token t)
    {
        import std.algorithm : count;

        switch (t.type)
        {
        case tok!"comment":
        case tok!"stringLiteral":
        case tok!"wstringLiteral":
        case tok!"dstringLiteral":
            return t.line + t.text.count('\n');
        default:
            return t.line;
        }
    }

    bool isBlockHeaderToken(const IdType t)
    {
        return t == tok!"for" || t == tok!"foreach" || t == tok!"foreach_reverse"
            || t == tok!"while" || t == tok!"if" || t == tok!"in"|| t == tok!"out"
            || t == tok!"do" || t == tok!"catch" || t == tok!"with"
            || t == tok!"synchronized" || t == tok!"scope" || t == tok!"debug";
    }

    bool isBlockHeader(int i = 0) nothrow
    {
        if (i + index < 0 || i + index >= tokens.length)
            return false;
        const t = tokens[i + index].type;
        bool isExpressionContract;

        if (i + index + 3 < tokens.length)
        {
            isExpressionContract = (t == tok!"in" && peekImplementation(tok!"(", i + 1, true))
                || (t == tok!"out" && (peekImplementation(tok!"(", i + 1, true)
                    && (peekImplementation(tok!";", i + 2, true)
                        || (peekImplementation(tok!"identifier", i + 2, true)
                            && peekImplementation(tok!";", i + 3, true)))));
        }

        return isBlockHeaderToken(t) && !isExpressionContract;
    }

    bool isSeparationToken(IdType t) nothrow
    {
        return t == tok!"," || t == tok!";" || t == tok!":" || t == tok!"("
            || t == tok!")" || t == tok!"[" || t == tok!"]" || t == tok!"{" || t == tok!"}";
    }
}

bool canFindIndex(const size_t[] items, size_t index, size_t* pos = null) pure @safe @nogc
{
    import std.range : assumeSorted;
    if (!pos)
    {
        return !assumeSorted(items).equalRange(index).empty;
    }
    else
    {
        auto trisection_result = assumeSorted(items).trisect(index);
        if (trisection_result[1].length == 1)
        {
            *pos = trisection_result[0].length;
            return true;
        }
        else if (trisection_result[1].length == 0)
        {
            return false;
        }
        else
        {
            assert(0, "the constraint of having unique locations has been violated");
        }
    }
}
