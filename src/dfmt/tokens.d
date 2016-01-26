//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.tokens;

import dparse.lexer;

/// Length of an invalid token
enum int INVALID_TOKEN_LENGTH = -1;

uint betweenParenLength(const Token[] tokens) pure @safe @nogc
in
{
    assert(tokens[0].type == tok!"(");
}
body
{
    uint length = 0;
    size_t i = 1;
    int depth = 1;
    while (i < tokens.length && depth > 0)
    {
        if (tokens[i].type == tok!"(")
            depth++;
        else if (tokens[i].type == tok!")")
            depth--;
        length += tokenLength(tokens[i]);
        i++;
    }
    return length;
}

int tokenLength(ref const Token t) pure @safe @nogc
{
    import std.algorithm : countUntil;

    switch (t.type)
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
        return cast(int) t.text.length;
    case tok!"identifier":
    case tok!"stringLiteral":
    case tok!"wstringLiteral":
    case tok!"dstringLiteral":
        // TODO: Unicode line breaks and old-Mac line endings
        auto c = cast(int) t.text.countUntil('\n');
        if (c == -1)
            return cast(int) t.text.length;
        else
            return c;
        mixin(generateFixedLengthCases());
    default:
        return INVALID_TOKEN_LENGTH;
    }
}

bool isBreakToken(IdType t) pure nothrow @safe @nogc
{
    switch (t)
    {
    case tok!"||":
    case tok!"&&":
    case tok!"(":
    case tok!"[":
    case tok!",":
    case tok!":":
    case tok!";":
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
    case tok!"=":
    case tok!">=":
    case tok!">>=":
    case tok!">>>=":
    case tok!">>>":
    case tok!">>":
    case tok!">":
    case tok!"|=":
    case tok!"|":
    case tok!"-=":
    case tok!"!<=":
    case tok!"!<>=":
    case tok!"!<>":
    case tok!"!<":
    case tok!"!=":
    case tok!"!>=":
    case tok!"!>":
    case tok!"?":
    case tok!"/=":
    case tok!"/":
    case tok!"..":
    case tok!"*=":
    case tok!"*":
    case tok!"&=":
    case tok!"%=":
    case tok!"%":
    case tok!"+=":
    case tok!".":
    case tok!"~":
    case tok!"+":
    case tok!"-":
        return true;
    default:
        return false;
    }
}

int breakCost(IdType p, IdType c) pure nothrow @safe @nogc
{
    switch (c)
    {
    case tok!"||":
    case tok!"&&":
    case tok!",":
        return 0;
    case tok!"(":
        return 60;
    case tok!"[":
        return 300;
    case tok!":":
    case tok!";":
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
    case tok!"=":
    case tok!">=":
    case tok!">>=":
    case tok!">>>=":
    case tok!">>>":
    case tok!">>":
    case tok!">":
    case tok!"|=":
    case tok!"|":
    case tok!"-=":
    case tok!"!<=":
    case tok!"!<>=":
    case tok!"!<>":
    case tok!"!<":
    case tok!"!=":
    case tok!"!>=":
    case tok!"!>":
    case tok!"?":
    case tok!"/=":
    case tok!"/":
    case tok!"..":
    case tok!"*=":
    case tok!"*":
    case tok!"&=":
    case tok!"%=":
    case tok!"%":
    case tok!"+":
    case tok!"-":
    case tok!"~":
    case tok!"+=":
        return 200;
    case tok!".":
        return p == tok!")" ? 0 : 300;
    default:
        return 1000;
    }
}

pure nothrow @safe @nogc unittest
{
    foreach (ubyte u; 0 .. ubyte.max)
        if (isBreakToken(u))
            assert(breakCost(tok!".", u) != 1000);
}

private string generateFixedLengthCases()
{
    import std.algorithm : map;
    import std.string : format;
    import std.array : join;

    assert(__ctfe);

    string[] spacedOperatorTokens = [
        ",", "..", "...", "/", "/=", "!", "!<", "!<=", "!<>", "!<>=", "!=",
        "!>", "!>=", "%", "%=", "&", "&&", "&=", "*", "*=", "+", "+=", "-",
        "-=", ":", ";", "<", "<<", "<<=", "<=", "<>", "<>=", "=", "==", "=>",
        ">", ">=", ">>", ">>=", ">>>", ">>>=", "?", "@", "^", "^=", "^^",
        "^^=", "|", "|=", "||", "~", "~="
    ];
    immutable spacedOperatorTokenCases = spacedOperatorTokens.map!(
            a => format(`case tok!"%s": return %d + 1;`, a, a.length)).join("\n\t");

    string[] identifierTokens = [
        "abstract", "alias", "align", "asm", "assert", "auto", "body", "bool",
        "break", "byte", "case", "cast", "catch", "cdouble", "cent", "cfloat", "char", "class",
        "const", "continue", "creal", "dchar", "debug", "default", "delegate", "delete", "deprecated",
        "do", "double", "else", "enum", "export", "extern", "false", "final", "finally", "float",
        "for", "foreach", "foreach_reverse", "function", "goto", "idouble", "if", "ifloat", "immutable",
        "import", "in", "inout", "int", "interface", "invariant", "ireal", "is",
        "lazy", "long", "macro", "mixin", "module", "new", "nothrow", "null", "out", "override",
        "package", "pragma", "private", "protected", "public", "pure", "real", "ref", "return", "scope",
        "shared", "short", "static", "struct", "super", "switch", "synchronized", "template", "this",
        "throw", "true", "try", "typedef", "typeid", "typeof", "ubyte", "ucent", "uint", "ulong",
        "union", "unittest", "ushort", "version", "void", "volatile", "wchar",
        "while", "with", "__DATE__", "__EOF__", "__FILE__",
        "__FUNCTION__", "__gshared", "__LINE__", "__MODULE__", "__parameters",
        "__PRETTY_FUNCTION__", "__TIME__", "__TIMESTAMP__",
        "__traits", "__vector", "__VENDOR__", "__VERSION__", "$", "++", "--",
        ".", "[", "]", "(", ")", "{", "}"
    ];
    immutable identifierTokenCases = identifierTokens.map!(
            a => format(`case tok!"%s": return %d;`, a, a.length)).join("\n\t");
    return spacedOperatorTokenCases ~ identifierTokenCases;
}
