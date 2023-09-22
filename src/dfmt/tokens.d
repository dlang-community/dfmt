//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.tokens;

import dmd.tokens;

/// Length of an invalid token
enum int INVALID_TOKEN_LENGTH = -1;

uint betweenParenLength(const Token[] tokens) @safe
in
{
    assert(tokens[0].value == TOK.leftParenthesis);
}
do
{
    uint length = 0;
    size_t i = 1;
    int depth = 1;
    while (i < tokens.length && depth > 0)
    {
        if (tokens[i].value == TOK.leftParenthesis)
            depth++;
        else if (tokens[i].value == TOK.rightParenthesis)
            depth--;
        length += tokenLength(tokens[i]);
        i++;
    }
    return length;
}

int tokenLength(ref const Token t) @safe
{
    import std.algorithm : countUntil;

    if (t.isKeyword())
        return cast(int) Token.toString(t.value).length;

    int c;
    switch (t.value)
    {
        // Numeric literals
    case TOK.int32Literal:
    case TOK.uns32Literal:
    case TOK.int64Literal:
    case TOK.uns64Literal:
    case TOK.int128Literal:
    case TOK.uns128Literal:
    case TOK.float32Literal:
    case TOK.float64Literal:
    case TOK.float80Literal:
    case TOK.imaginary32Literal:
    case TOK.imaginary64Literal:
    case TOK.imaginary80Literal:
        // Char constants
    case TOK.charLiteral:
    case TOK.wcharLiteral:
    case TOK.dcharLiteral:
        // Identifiers
    case TOK.identifier:
        return cast(int) Token.toString(t.value).length;
        // Spaced operators
    case TOK.add:
    case TOK.addAssign:
    case TOK.and:
    case TOK.andAnd:
    case TOK.andAssign:
    case TOK.arrow:
    case TOK.assign:
    case TOK.colon:
    case TOK.colonColon:
    case TOK.comma:
    case TOK.concatenateAssign:
    case TOK.div:
    case TOK.divAssign:
    case TOK.dot:
    case TOK.dotDotDot:
    case TOK.equal:
    case TOK.goesTo:
    case TOK.greaterOrEqual:
    case TOK.greaterThan:
    case TOK.identity:
    case TOK.is_:
    case TOK.leftShift:
    case TOK.leftShiftAssign:
    case TOK.lessOrEqual:
    case TOK.lessThan:
    case TOK.min:
    case TOK.minAssign:
    case TOK.minusMinus:
    case TOK.mod:
    case TOK.modAssign:
    case TOK.mul:
    case TOK.mulAssign:
    case TOK.not:
    case TOK.notEqual:
    case TOK.notIdentity:
    case TOK.or:
    case TOK.orAssign:
    case TOK.orOr:
    case TOK.plusPlus:
    case TOK.pound:
    case TOK.pow:
    case TOK.powAssign:
    case TOK.question:
    case TOK.rightShift:
    case TOK.rightShiftAssign:
    case TOK.semicolon:
    case TOK.slice:
    case TOK.tilde:
    case TOK.unsignedRightShift:
    case TOK.unsignedRightShiftAssign:
    case TOK.xor:
    case TOK.xorAssign:
        return cast(int) Token.toString(t.value).length + 1;
    case TOK.string_:
        // TODO: Unicode line breaks and old-Mac line endings
        c = cast(int) Token.toString(t.value).countUntil('\n');
        if (c == -1)
            return cast(int) Token.toString(t.value).length;
        else
            return c;

    default:
        return INVALID_TOKEN_LENGTH;
    }
}

bool isBreakToken(TOK t) pure nothrow @safe @nogc
{
    switch (t)
    {
    case TOK.orOr:
    case TOK.andAnd:
    case TOK.leftParenthesis:
    case TOK.leftBracket:
    case TOK.comma:
    case TOK.colon:
    case TOK.semicolon:
    case TOK.pow:
    case TOK.powAssign:
    case TOK.xor:
    case TOK.concatenateAssign:
    case TOK.leftShiftAssign:
    case TOK.leftShift:
    case TOK.lessOrEqual:
    case TOK.lessThan:
    case TOK.equal:
    case TOK.goesTo:
    case TOK.assign:
    case TOK.greaterOrEqual:
    case TOK.rightShiftAssign:
    case TOK.unsignedRightShift:
    case TOK.unsignedRightShiftAssign:
    case TOK.rightShift:
    case TOK.greaterThan:
    case TOK.orAssign:
    case TOK.or:
    case TOK.minAssign:
    case TOK.notEqual:
    case TOK.question:
    case TOK.divAssign:
    case TOK.div:
    case TOK.slice:
    case TOK.mulAssign:
    case TOK.mul:
    case TOK.andAssign:
    case TOK.modAssign:
    case TOK.mod:
    case TOK.addAssign:
    case TOK.dot:
    case TOK.tilde:
    case TOK.add:
    case TOK.min:
        return true;
    default:
        return false;
    }
}

int breakCost(TOK p, TOK c) pure nothrow @safe @nogc
{
    switch (c)
    {
    case TOK.orOr:
    case TOK.andAnd:
    case TOK.comma:
    case TOK.question:
        return 0;
    case TOK.leftParenthesis:
        return 60;
    case TOK.leftBracket:
        return 300;
    case TOK.semicolon:
    case TOK.pow:
    case TOK.xorAssign:
    case TOK.xor:
    case TOK.concatenateAssign:
    case TOK.leftShiftAssign:
    case TOK.leftShift:
    case TOK.lessOrEqual:
    case TOK.lessThan:
    case TOK.equal:
    case TOK.goesTo:
    case TOK.assign:
    case TOK.greaterOrEqual:
    case TOK.rightShiftAssign:
    case TOK.unsignedRightShiftAssign:
    case TOK.unsignedRightShift:
    case TOK.rightShift:
    case TOK.greaterThan:
    case TOK.orAssign:
    case TOK.or:
    case TOK.minAssign:
    case TOK.divAssign:
    case TOK.div:
    case TOK.slice:
    case TOK.mulAssign:
    case TOK.mul:
    case TOK.andAssign:
    case TOK.modAssign:
    case TOK.mod:
    case TOK.add:
    case TOK.min:
    case TOK.tilde:
    case TOK.addAssign:
        return 200;
    case TOK.colon:
        // colon could be after a label or an import, where it should normally wrap like before
        // for everything else (associative arrays) try not breaking around colons
        return p == TOK.identifier ? 0 : 300;
    case TOK.dot:
        return p == TOK.rightParenthesis ? 0 : 300;
    default:
        return 1000;
    }
}

pure nothrow @safe @nogc unittest
{
    foreach (ubyte u; 0 .. ubyte.max)
        if (isBreakToken(u))
            assert(breakCost(TOK.dot, u) != 1000);
}
