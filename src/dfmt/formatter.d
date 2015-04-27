//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.formatter;

import std.d.lexer;
import std.d.parser;
import dfmt.config;
import dfmt.ast_info;
import dfmt.indentation;
import dfmt.tokens;
import dfmt.wrapping;
import std.array;

void format(OutputRange)(string source_desc, ubyte[] buffer, OutputRange output,
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
    auto parseTokens = getTokensForParser(buffer, parseConfig, &cache);
    auto mod = parseModule(parseTokens, source_desc);
    auto visitor = new FormatVisitor(&astInformation);
    visitor.visit(mod);
    astInformation.cleanup();
    auto tokens = byToken(buffer, config, &cache).array();
    auto depths = generateDepthInfo(tokens);
    auto tokenFormatter = TokenFormatter!OutputRange(tokens, depths, output,
        &astInformation, formatterConfig);
    tokenFormatter.format();
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
        case tok!"{":
        case tok!"(":
        case tok!"[":
            depth++;
            break;
        case tok!"}":
        case tok!")":
        case tok!"]":
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
     *     tokens = the tokens to format
     *     output = the output range that the code will be formatted to
     *     astInformation = information about the AST used to inform formatting
     *         decisions.
     */
    this(const(Token)[] tokens, immutable short[] depths, OutputRange output,
        ASTInformation* astInformation, Config* config)
    {
        this.tokens = tokens;
        this.depths = depths;
        this.output = output;
        this.astInformation = astInformation;
        this.config = config;
    }

    /// Runs the foramtting process
    void format()
    {
        while (index < tokens.length)
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

    /// Tokens being formatted
    const Token[] tokens;

    /// Paren depth info
    immutable short[] depths;

    /// Information about the AST
    const ASTInformation* astInformation;

    /// token indicies where line breaks should be placed
    size_t[] linebreakHints;

    /// Current indentation stack for the file
    IndentStack indents;

    /// Configuration
    const Config* config;

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

    void formatStep()
    {
        assert(index < tokens.length);
        if (currentIs(tok!"comment"))
        {
            formatComment();
        }
        else if (isStringLiteral(current.type) || isNumberLiteral(current.type)
                || currentIs(tok!"characterLiteral"))
        {
            writeToken();
            if (index < tokens.length)
            {
                immutable t = tokens[index].type;
                if (t == tok!"identifier" || isStringLiteral(t)
                        || isNumberLiteral(t) || t == tok!"characterLiteral")
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
            if (!currentIs(tok!";") && !currentIs(tok!")"))
                write(" ");
        }
        else if (currentIs(tok!"with"))
        {
            if (indents.length == 0 || indents.top != tok!"switch")
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
        }
        else if ((isBlockHeader() || currentIs(tok!"version")
                || currentIs(tok!"debug")) && peekIs(tok!"(", false))
        {
            formatBlockHeader();
        }
        else if (currentIs(tok!"else"))
        {
            formatElse();
        }
        else if (isKeyword(current.type))
        {
            formatKeyword();
        }
        else if (isBasicType(current.type))
        {
            writeToken();
            if (currentIs(tok!"identifier") || isKeyword(current.type))
                write(" ");
        }
        else if (isOperator(current.type))
        {
            formatOperator();
        }
        else if (currentIs(tok!"identifier"))
        {
            writeToken();
            if (index < tokens.length && (currentIs(tok!"identifier")
                    || isBasicType(current.type) || currentIs(tok!"@") || currentIs(tok!"if")))
            {
                write(" ");
            }
        }
        else if (currentIs(tok!"scriptLine"))
        {
            writeToken();
            newline();
        }
        else
            writeToken();
    }

    void formatComment()
    {
        immutable bool currIsSlashSlash = tokens[index].text[0 .. 2] == "//";
        immutable prevTokenEndLine = index == 0 ? size_t.max : tokenEndLine(tokens[index - 1]);
        immutable size_t currTokenLine = tokens[index].line;
        if (index > 0)
        {
            immutable t = tokens[index - 1].type;
            immutable canAddNewline = currTokenLine - prevTokenEndLine < 1;
            if (prevTokenEndLine == currTokenLine || (t == tok!")" && peekIs(tok!"{")))
                write(" ");
            else if (t != tok!";" && t != tok!"}" && canAddNewline)
            {
                newline();
            }
        }
        writeToken();
        immutable j = justAddedExtraNewline;
        if (currIsSlashSlash)
        {
            newline();
            justAddedExtraNewline = j;
        }
        else if (index < tokens.length)
        {
            if (index < tokens.length && prevTokenEndLine == tokens[index].line)
            {
                if (!currentIs(tok!"{"))
                    write(" ");
            }
            else if (!currentIs(tok!"{"))
                newline();
        }
        else
            newline();
    }

    void formatModuleOrImport()
    {
        auto t = current.type;
        writeToken();
        if (currentIs(tok!"("))
        {
            writeParens(false);
            return;
        }
        write(" ");
        while (index < tokens.length)
        {
            if (currentIs(tok!";"))
            {
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
                else if ((t == tok!"import" && !currentIs(tok!"import") && !currentIs(tok!"}")))
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
            else if (currentIs(tok!","))
            {
                // compute length until next , or ;
                int lengthOfNextChunk = INVALID_TOKEN_LENGTH;
                for (size_t i = index + 1; i < tokens.length; i++)
                {
                    if (tokens[i].type == tok!"," || tokens[i].type == tok!";")
                        break;
                    const len = tokenLength(tokens[i]);
                    assert(len >= 0);
                    lengthOfNextChunk += len;
                }
                assert(lengthOfNextChunk > 0);
                writeToken();
                if (currentLineLength + 1 + lengthOfNextChunk >= config.dfmt_soft_max_line_length)
                {
                    pushWrapIndent(tok!",");
                    newline();
                }
                else
                    write(" ");
            }
            else
                formatStep();
        }
    }

    void formatLeftParenOrBracket()
    {
        immutable p = tokens[index].type;
        regenLineBreakHintsIfNecessary(index);
        writeToken();
        if (p == tok!"(")
        {
            spaceAfterParens = true;
            parenDepth++;
        }
        immutable bool arrayInitializerStart = p == tok!"[" && linebreakHints.length != 0
            && astInformation.arrayStartLocations.canFindIndex(tokens[index - 1].index);
        if (arrayInitializerStart)
        {
            // Use the close bracket as the indent token to distinguish
            // the array initialiazer from an array index in the newling
            // handling code
            pushWrapIndent(tok!"]");
            newline();
            immutable size_t j = expressionEndIndex(index);
            linebreakHints = chooseLineBreakTokens(index, tokens[index .. j],
                depths[index .. j], config, currentLineLength, indentLevel);
        }
        else if (!currentIs(tok!")") && !currentIs(tok!"]")
                && (linebreakHints.canFindIndex(index - 1) || (linebreakHints.length == 0
                && currentLineLength > config.max_line_length)))
        {
            pushWrapIndent(p);
            newline();
        }
    }

    void formatRightParen()
    {
        parenDepth--;
        if (parenDepth == 0)
            indents.popWrapIndents();
        if (parenDepth == 0 && (peekIs(tok!"in") || peekIs(tok!"out") || peekIs(tok!"body")))
        {
            writeToken(); // )
            newline();
            writeToken(); // in/out/body
        }
        else if (peekIsLiteralOrIdent() || peekIsBasicType())
        {
            writeToken();
            if (spaceAfterParens || parenDepth > 0)
                write(" ");
        }
        else if ((peekIsKeyword() || peekIs(tok!"@")) && spaceAfterParens)
        {
            writeToken();
            write(" ");
        }
        else
            writeToken();
    }

    void formatAt()
    {
        writeToken();
        if (currentIs(tok!"identifier"))
            writeToken();
        if (currentIs(tok!"("))
        {
            writeParens(false);
            if (index < tokens.length && tokens[index - 1].line < tokens[index].line)
                newline();
            else
                write(" ");
        }
        else if (index < tokens.length && (currentIs(tok!"@") || !isOperator(tokens[index].type)))
            write(" ");
    }

    void formatColon()
    {
        if (astInformation.caseEndLocations.canFindIndex(current.index)
                || astInformation.attributeDeclarationLines.canFindIndex(current.line))
        {
            writeToken();
            if (!currentIs(tok!"{"))
                newline();
        }
        else if (peekBackIs(tok!"identifier") && (peekBack2Is(tok!"{", true)
                || peekBack2Is(tok!"}", true) || peekBack2Is(tok!";", true)
                || peekBack2Is(tok!":", true)) && !(isBlockHeader(1) && !peekIs(tok!"if")))
        {
            writeToken();
            if (!currentIs(tok!"{"))
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
                write(" ");
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
            linebreakHints = [];
            while (indents.topIs(tok!"enum"))
                indents.pop();
            if (config.dfmt_brace_style == BraceStyle.allman)
            {
                if (!currentIs(tok!"{"))
                    newline();
            }
            else
            {
                if (currentIs(tok!"{"))
                    indents.popTempIndents();
                indentLevel = indents.indentSize;
                newline();
            }
        }
    }

    void formatLeftBrace()
    {
        import std.algorithm : map, sum;

        if (astInformation.structInitStartLocations.canFindIndex(tokens[index].index))
        {
            sBraceDepth++;
            auto e = expressionEndIndex(index);
            immutable int l = currentLineLength + tokens[index .. e].map!(a => tokenLength(a)).sum();
            writeToken();
            if (l > config.dfmt_soft_max_line_length)
            {
                indents.push(tok!"{");
                newline();
            }
            else
                niBraceDepth++;
        }
        else if (astInformation.funLitStartLocations.canFindIndex(tokens[index].index))
        {
            sBraceDepth++;
            if (peekBackIs(tok!")"))
                write(" ");
            auto e = expressionEndIndex(index);
            immutable int l = currentLineLength + tokens[index .. e].map!(a => tokenLength(a)).sum();
            writeToken();
            if (l > config.dfmt_soft_max_line_length)
            {
                indents.push(tok!"{");
                newline();
            }
            else
            {
                niBraceDepth++;
                write(" ");
            }
        }
        else
        {
            indents.popWrapIndents();
            if (indents.length && isTempIndent(indents.top))
                indentLevel = indents.indentSize - 1;
            else
                indentLevel = indents.indentSize;

            if (!peekBackIsSlashSlash())
            {
                if (config.dfmt_brace_style == BraceStyle.allman || peekBackIsOneOf(true, tok!"{", tok!"}"))
                    newline();
                else if (!peekBackIsOneOf(true, tok!"{", tok!"}", tok!";"))
                    write(" ");
                writeToken();
            }
            else
            {
                writeToken();
                indents.popTempIndents();
                indentLevel = indents.indentSize - 1;
            }
            indents.push(tok!"{");
            if (!currentIs(tok!"{"))
                newline();
            linebreakHints = [];
        }
    }

    void formatRightBrace()
    {
        if (astInformation.structInitEndLocations.canFindIndex(tokens[index].index))
        {
            if (sBraceDepth > 0)
                sBraceDepth--;
            if (niBraceDepth > 0)
                niBraceDepth--;
            writeToken();
        }
        else if (astInformation.funLitEndLocations.canFindIndex(tokens[index].index))
        {
            if (niBraceDepth > 0)
            {
                if (!peekBackIsSlashSlash())
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
                    && !peekIs(tok!"}") && !peekIs(tok!";"))
            {
                simpleNewline();
                currentLineLength = 0;
                justAddedExtraNewline = true;
            }
            if (config.dfmt_brace_style != BraceStyle.allman && currentIs(tok!"else"))
                write(" ");
            if (!peekIs(tok!",") && !peekIs(tok!")") && !peekIs(tok!";") && !peekIs(tok!"{"))
            {
                index++;
                newline();
            }
            else
                index++;
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
        immutable bool a = !currentIs(tok!"version") && !currentIs(tok!"debug");
        immutable bool b = a
            || astInformation.conditionalWithElseLocations.canFindIndex(current.index);
        immutable bool shouldPushIndent = b
            || astInformation.conditionalStatementLocations.canFindIndex(current.index);
        if (shouldPushIndent)
            indents.push(current.type);
        writeToken();
        write(" ");
        writeParens(false);
        if (currentIs(tok!"switch") || (currentIs(tok!"final") && peekIs(tok!"switch")))
            write(" ");
        else if (currentIs(tok!"comment"))
            formatStep();
        else if (!shouldPushIndent)
        {
            if (!currentIs(tok!"{") && !currentIs(tok!";"))
                write(" ");
        }
        else if (!currentIs(tok!"{") && !currentIs(tok!";"))
            newline();
    }

    void formatElse()
    {
        writeToken();
        if (currentIs(tok!"if") || currentIs(tok!"version")
                || (currentIs(tok!"static") && peekIs(tok!"if")))
        {
            if (indents.top() == tok!"if" || indents.top == tok!"version")
                indents.pop();
            write(" ");
        }
        else if (!currentIs(tok!"{") && !currentIs(tok!"comment"))
        {
            if (indents.top() == tok!"if" || indents.top == tok!"version")
                indents.pop();
            indents.push(tok!"else");
            newline();
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
            if (!peekBackIs(tok!"}") && astInformation.contractLocations.canFindIndex(current.index))
                newline();
            else if (peekBackIsKeyword)
                write(" ");
            writeToken();
            if (!currentIs(tok!"(") && !currentIs(tok!"{"))
                write(" ");
            break;
        case tok!"try":
            if (peekIs(tok!"{"))
                writeToken();
            else
            {
                writeToken();
                indents.push(tok!"try");
                newline();
            }
            break;
        case tok!"in":
            auto isContract = astInformation.contractLocations.canFindIndex(current.index);
            if (isContract)
                newline();
            else if (!peekBackIsOneOf(false, tok!"(", tok!",", tok!"!"))
                write(" ");
            writeToken();
            if (!isContract)
                write(" ");
            break;
        case tok!"is":
            if (!peekBackIsOneOf(false, tok!"!", tok!"(", tok!",", tok!"}") && !peekBackIsKeyword())
                write(" ");
            writeToken();
            if (!currentIs(tok!"(") && !currentIs(tok!"{"))
                write(" ");
            break;
        case tok!"case":
            writeToken();
            if (!currentIs(tok!";"))
                write(" ");
            break;
        case tok!"enum":
            indents.push(tok!"enum");
            writeToken();
            if (!currentIs(tok!":"))
                write(" ");
            break;
        default:
            if (index + 1 < tokens.length)
            {
                if (!peekIs(tok!"@") && (peekIsOperator() || peekIs(tok!"out") || peekIs(tok!"in")))
                    writeToken();
                else
                {
                    writeToken();
                    write(" ");
                }
            }
            else
                writeToken();
            break;
        }
    }

    void formatOperator()
    {
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
            else if (!astInformation.unaryLocations.canFindIndex(current.index))
                goto binary;
            else
                writeToken();
            break;
        case tok!"~":
            if (peekIs(tok!"this"))
            {
                if (!(index == 0 || peekBackIs(tok!"{", true)
                        || peekBackIs(tok!"}", true) || peekBackIs(tok!";", true)))
                {
                    write(" ");
                }
                writeToken();
                break;
            }
            else
                goto case;
        case tok!"&":
        case tok!"+":
        case tok!"-":
            if (astInformation.unaryLocations.canFindIndex(current.index))
            {
                writeToken();
                break;
            }
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
            if ((peekIs(tok!"is") || peekIs(tok!"in")) && !peekBackIsOneOf(false, tok!"(", tok!"="))
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
            indents.popWrapIndents();
            if (indents.topIs(tok!"]"))
                newline();
            writeToken();
            if (currentIs(tok!"identifier"))
                write(" ");
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
            if (linebreakHints.canFind(index) || (linebreakHints.length == 0
                    && currentLineLength + nextTokenLength() > config.max_line_length))
            {
                pushWrapIndent();
                newline();
            }
            writeToken();
            break;
        case tok!",":
            formatComma();
            break;
        case tok!"&&":
        case tok!"||":
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
        case tok!"|":
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
            immutable bool isWrapToken = linebreakHints.canFind(index) || peekIs(tok!"comment", false);
            if (config.dfmt_split_operator_at_line_end)
            {
                if (isWrapToken)
                {
                    pushWrapIndent();
                    write(" ");
                    writeToken();
                    newline();
                }
                else
                {
                    write(" ");
                    writeToken();
                    write(" ");
                }
            }
            else
            {
                if (isWrapToken)
                {
                    pushWrapIndent();
                    newline();
                }
                else
                    write(" ");
                writeToken();
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
        import std.algorithm : canFind;

        regenLineBreakHintsIfNecessary(index);
        if (indents.indentToMostRecent(tok!"enum") != -1 && !peekIs(tok!"}")
                && indents.top == tok!"{" && parenDepth == 0)
        {
            writeToken();
            newline();
        }
        else if (!peekIs(tok!"}") && (linebreakHints.canFind(index)
                || (linebreakHints.length == 0 && currentLineLength > config.dfmt_soft_max_line_length)))
        {
            writeToken();
            pushWrapIndent(tok!",");
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
        immutable size_t j = expressionEndIndex(i);
        linebreakHints = chooseLineBreakTokens(i, tokens[i .. j], depths[i .. j],
            config, currentLineLength, indentLevel);
    }

    void regenLineBreakHintsIfNecessary(immutable size_t i)
    {
        if (linebreakHints.length == 0 || linebreakHints[$ - 1] <= i - 1)
            regenLineBreakHints(i);
    }

    void simpleNewline()
    {
        import dfmt.editorconfig : EOL;

        final switch (config.end_of_line)
        {
        case EOL.cr: output.put("\r"); break;
        case EOL.lf: output.put("\n"); break;
        case EOL.crlf: output.put("\r\n"); break;
        case EOL.unspecified: assert(false, "config.end_of_line was unspecified");
        }
    }

    void newline()
    {
        import std.range : assumeSorted;
        import std.algorithm : max;
        import dfmt.editorconfig : OptionalBoolean;

        if (currentIs(tok!"comment") && index > 0 && current.line == tokenEndLine(tokens[index - 1]))
            return;

        immutable bool hasCurrent = index < tokens.length;

        if (niBraceDepth > 0 && !peekBackIsSlashSlash() && hasCurrent
                && tokens[index].type == tok!"}" && !assumeSorted(
                astInformation.funLitEndLocations).equalRange(tokens[index].index).empty)
        {
            write(" ");
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
            bool switchLabel = false;
            if (currentIs(tok!"else"))
            {
                auto i = indents.indentToMostRecent(tok!"if");
                auto v = indents.indentToMostRecent(tok!"version");
                auto mostRecent = max(i, v);
                if (mostRecent != -1)
                    indentLevel = mostRecent;
            }
            else if (currentIs(tok!"identifier") && peekIs(tok!":"))
            {
                while ((peekBackIs(tok!"}", true) || peekBackIs(tok!";", true))
                        && indents.length && isTempIndent(indents.top()))
                {
                    indents.pop();
                }
                auto l = indents.indentToMostRecent(tok!"switch");
                if (l != -1)
                {
                    indentLevel = l;
                    switchLabel = true;
                }
                else if (!isBlockHeader(2) || peek2Is(tok!"if"))
                {
                    auto l2 = indents.indentToMostRecent(tok!"{");
                    indentLevel = l2 == -1 ? indentLevel : l2;
                }
                else
                    indentLevel = indents.indentSize;
            }
            else if (currentIs(tok!"case") || currentIs(tok!"default"))
            {
                while (indents.length && (peekBackIs(tok!"}", true)
                        || peekBackIs(tok!";", true)) && isTempIndent(indents.top()))
                {
                    indents.pop();
                }
                auto l = indents.indentToMostRecent(tok!"switch");
                if (l != -1)
                    indentLevel = l;
            }
            else if (currentIs(tok!"{"))
            {
                indents.popWrapIndents();
                if (peekBackIsSlashSlash())
                {
                    indents.popTempIndents();
                    indentLevel = indents.indentSize;
                }
            }
            else if (currentIs(tok!"}"))
            {
                indents.popTempIndents();
                if (indents.top == tok!"{")
                {
                    indentLevel = indents.indentToMostRecent(tok!"{");
                    indents.pop();
                }
                while (indents.topIsTemp() && ((indents.top != tok!"if"
                        && indents.top != tok!"version") || !peekIs(tok!"else")))
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
                    indentLevel = indents.indentSize;
                }
            }
            else if (astInformation.attributeDeclarationLines.canFindIndex(current.line))
            {
                auto l = indents.indentToMostRecent(tok!"{");
                if (l != -1)
                    indentLevel = l;
            }
            else
            {
                while (indents.topIsTemp() && (peekBackIsOneOf(true, tok!"}", tok!";") && indents.top != tok!";"))
                {
                    indents.pop();
                }
                indentLevel = indents.indentSize;
            }
            indent();
        }
    }

    void write(string str)
    {
        currentLineLength += str.length;
        output.put(str);
    }

    void writeToken()
    {
        if (current.text is null)
        {
            auto s = str(current.type);
            currentLineLength += s.length;
            output.put(str(current.type));
        }
        else
        {
            // You know what's awesome? Windows can't handle its own line
            // endings correctly.
            version (Windows)
                output.put(current.text.replace("\r", ""));
            else
                output.put(current.text);
            currentLineLength += current.text.length;
        }
        index++;
    }

    void writeParens(bool spaceAfter)
    in
    {
        assert(currentIs(tok!"("), str(current.type));
    }
    body
    {
        immutable int depth = parenDepth;
        parenDepth = 0;
        do
        {
            spaceAfterParens = spaceAfter;
            formatStep();
        }
        while (index < tokens.length && parenDepth > 0);
        parenDepth = depth;
        spaceAfterParens = spaceAfter;
    }

    void indent()
    {
        import dfmt.editorconfig : IndentStyle;
        if (config.indent_style == IndentStyle.tab)
            foreach (i; 0 .. indentLevel)
            {
                currentLineLength += config.tab_width;
                output.put("\t");
            }
        else
            foreach (i; 0 .. indentLevel)
                foreach (j; 0 .. config.indent_size)
                {
                    output.put(" ");
                    currentLineLength++;
                }
    }

    void pushWrapIndent(IdType type = tok!"")
    {
        immutable t = type == tok!"" ? tokens[index].type : type;
        if (parenDepth == 0)
        {
            if (indents.wrapIndents == 0)
                indents.push(t);
        }
        else if (indents.wrapIndents < 1)
            indents.push(t);
    }

const pure @safe @nogc:

    size_t expressionEndIndex(size_t i) nothrow
    {
        immutable bool braces = i < tokens.length && tokens[i].type == tok!"{";
        immutable d = depths[i];
        while (true)
        {
            if (i >= tokens.length)
                break;
            if (depths[i] < d)
                break;
            if (!braces && tokens[i].type == tok!";")
                break;
            i++;
        }
        return i;
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

    ref current() nothrow in
    {
        assert(index < tokens.length);
    }
    body
    {
        return tokens[index];
    }

    const(Token) peekBack() nothrow
    {
        assert(index > 0);
        return tokens[index - 1];
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

	bool peekBackIsKeyword(bool ignoreComments = true)
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

    bool peekBackIsOneOf(bool ignoreComments, IdType[] tokenTypes...)
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

    bool peekBackIsSlashSlash() nothrow
    {
        return index > 0 && tokens[index - 1].type == tok!"comment"
            && tokens[index - 1].text[0 .. 2] == "//";
    }

    bool currentIs(IdType tokenType) nothrow
    {
        return index < tokens.length && tokens[index].type == tokenType;
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

    bool isBlockHeader(int i = 0) nothrow
    {
        if (i + index < 0 || i + index >= tokens.length)
            return false;
        auto t = tokens[i + index].type;
        return t == tok!"for" || t == tok!"foreach" || t == tok!"foreach_reverse"
            || t == tok!"while" || t == tok!"if" || t == tok!"out"
            || t == tok!"catch" || t == tok!"with" || t == tok!"synchronized";
    }
}

bool canFindIndex(const size_t[] items, size_t index) pure @safe @nogc
{
    import std.range : assumeSorted;

    return !assumeSorted(items).equalRange(index).empty;
}
