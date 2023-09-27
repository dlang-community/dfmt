//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.indentation;

import dfmt.config;
import dfmt.editorconfig;
import dmd.tokens;

import std.bitmanip : bitfields;

/**
 * Returns: true if the given token type is a wrap indent type
 */
bool isWrapIndent(TOK type) pure nothrow @nogc @safe
{
    switch (type)
    {
    case TOK.leftCurly:
    case TOK.case_:
    case TOK.at:
    case TOK.rightBracket:
    case TOK.leftParenthesis:
    case TOK.rightParenthesis:
        return false;

        // Operators
    case TOK.lessThan:
    case TOK.greaterThan:
    case TOK.lessOrEqual:
    case TOK.greaterOrEqual:
    case TOK.equal:
    case TOK.notEqual:
    case TOK.identity:
    case TOK.notIdentity:
    case TOK.is_:

    case TOK.leftShift:
    case TOK.rightShift:
    case TOK.leftShiftAssign:
    case TOK.rightShiftAssign:
    case TOK.unsignedRightShift:
    case TOK.unsignedRightShiftAssign:
    case TOK.concatenateAssign:
    case TOK.add:
    case TOK.min:
    case TOK.addAssign:
    case TOK.minAssign:
    case TOK.mul:
    case TOK.div:
    case TOK.mod:
    case TOK.mulAssign:
    case TOK.divAssign:
    case TOK.modAssign:
    case TOK.and:
    case TOK.or:
    case TOK.xor:
    case TOK.andAssign:
    case TOK.orAssign:
    case TOK.xorAssign:
    case TOK.assign:
    case TOK.not:
    case TOK.tilde:
    case TOK.plusPlus:
    case TOK.minusMinus:
    case TOK.dot:
    case TOK.comma:
    case TOK.question:
    case TOK.andAnd:
    case TOK.orOr:
        return true;
    default:
        return false;
    }
}

/**
 * Returns: true if the given token type is a temporary indent type
 */
bool isTempIndent(TOK type) pure nothrow @nogc @safe
{
    return type != TOK.rightParenthesis && type != TOK.leftCurly && type != TOK.case_ && type != TOK
        .at;
}

/**
 * Stack for managing indent levels.
 */
struct IndentStack
{
    /// Configuration
    private const Config* config;

    this(const Config* config)
    {
        this.config = config;
    }

    static struct Details
    {
        mixin(bitfields!(
                // generally true for all operators except {, case, @, ], (, )
                bool, "wrap", 1, // temporary indentation which get's reverted when a block starts
                // generally true for all tokens except ), {, case, @
                bool, "temp", 1, // emit minimal newlines
                bool, "mini", 1, // for associative arrays or arrays containing them, break after every item
                bool, "breakEveryItem", 1, // when an item inside an array would break mid-item, definitely break at the comma first
                bool, "preferLongBreaking", 1,
                uint, "", 27));
    }

    /**
     * Get the indent size at the most recent occurrence of the given indent type
     */
    int indentToMostRecent(TOK item) const
    {
        if (index == 0)
            return -1;
        size_t i = index - 1;
        while (true)
        {
            if (arr[i] == item)
                return indentSize(i);
            if (i > 0)
                i--;
            else
                return -1;
        }
    }

    int wrapIndents() const pure nothrow @property
    {
        if (index == 0)
            return 0;
        int tempIndentCount = 0;
        for (size_t i = index; i > 0; i--)
        {
            if (!details[i - 1].wrap && arr[i - 1] != TOK.rightBracket)
                break;
            tempIndentCount++;
        }
        return tempIndentCount;
    }

    /**
     * Pushes the given indent type on to the stack.
     */
    void push(TOK item) pure nothrow
    {
        Details detail;
        detail.wrap = isWrapIndent(item);
        detail.temp = isTempIndent(item);
        push(item, detail);
    }

    /**
     * Pushes the given indent type on to the stack.
     */
    void push(TOK item, Details detail) pure nothrow
    {
        arr[index] = item;
        details[index] = detail;
        //FIXME this is actually a bad thing to do,
        //we should not just override when the stack is
        //at it's limit
        if (index < arr.length)
        {
            index++;
        }
    }

    /**
     * Pops the top indent from the stack.
     */
    void pop() pure nothrow
    {
        if (index)
            index--;
    }

    /**
     * Pops all wrapping indents from the top of the stack.
     */
    void popWrapIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && details[index - 1].wrap)
            index--;
    }

    /**
     * Pops all temporary indents from the top of the stack.
     */
    void popTempIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && details[index - 1].temp)
            index--;
    }

    bool topAre(TOK[] types...)
    {
        if (types.length > index)
            return false;
        return arr[index - types.length .. index] == types;

    }

    /**
     * Returns: `true` if the top of the indent stack is the given indent type.
     */
    bool topIs(TOK type) const pure nothrow @safe @nogc
    {
        return index > 0 && index <= arr.length && arr[index - 1] == type;
    }

    /**
     * Returns: `true` if the top of the indent stack is a temporary indent
     */
    bool topIsTemp()
    {
        return index > 0 && index <= arr.length && details[index - 1].temp;
    }

    /**
     * Returns: `true` if the top of the indent stack is a temporary indent with the specified token
     */
    bool topIsTemp(TOK item)
    {
        return index > 0 && index <= arr.length && arr[index - 1] == item && details[index - 1]
            .temp;
    }

    /**
     * Returns: `true` if the top of the indent stack is a wrapping indent
     */
    bool topIsWrap()
    {
        return index > 0 && index <= arr.length && details[index - 1].wrap;
    }

    /**
     * Returns: `true` if the top of the indent stack is a temporary indent with the specified token
     */
    bool topIsWrap(TOK item)
    {
        return index > 0 && index <= arr.length && arr[index - 1] == item && details[index - 1]
            .wrap;
    }

    /**
     * Returns: `true` if the top of the indent stack is one of the given token
     *     types.
     */
    bool topIsOneOf(TOK[] types...) const pure nothrow @safe @nogc
    {
        if (index == 0)
            return false;
        immutable topType = arr[index - 1];
        foreach (t; types)
            if (t == topType)
                return true;
        return false;
    }

    TOK top() const pure nothrow @property @safe @nogc
    {
        return arr[index - 1];
    }

    Details topDetails() const pure nothrow @property @safe @nogc
    {
        return details[index - 1];
    }

    int indentLevel() const pure nothrow @property @safe @nogc
    {
        return indentSize();
    }

    int length() const pure nothrow @property @safe @nogc
    {
        return cast(int) index;
    }

    /**
     * Dumps the current state of the indentation stack to `stderr`. Used for debugging.
     */
    void dump(size_t pos = size_t.max, string file = __FILE__, uint line = __LINE__) const
    {
        import std.algorithm.iteration : map;
        import std.stdio : stderr;

        if (pos == size_t.max)
            stderr.writefln("\033[31m%s:%d %(%s %)\033[0m", file, line, arr[0 .. index].map!(
                    a => Token.toString(a)));
        else
            stderr.writefln("\033[31m%s:%d at %d %(%s %)\033[0m", file, line, pos, arr[0 .. index].map!(
                    a => Token.toString(a)));
    }

private:

    size_t index;

    TOK[256] arr;
    Details[arr.length] details;

    int indentSize(const size_t k = size_t.max) const pure nothrow @safe @nogc
    {
        import std.algorithm : among;

        if (index == 0 || k == 0)
            return 0;
        immutable size_t j = k == size_t.max ? index : k;
        int size = 0;
        int parenCount;
        foreach (i; 0 .. j)
        {
            immutable int pc = (arr[i] == TOK.not || arr[i] == TOK.leftParenthesis || arr[i] == TOK
                    .rightParenthesis) ? parenCount + 1 : parenCount;
            if ((details[i].wrap || arr[i] == TOK.leftParenthesis) && parenCount > 1)
            {
                parenCount = pc;
                continue;
            }

            if (i + 1 < index)
            {
                if (config.dfmt_single_indent == OptionalBoolean.t && skipDoubleIndent(i, parenCount))
                {
                    parenCount = pc;
                    continue;
                }

                immutable currentIsNonWrapTemp = !details[i].wrap
                    && details[i].temp && arr[i] != TOK.rightParenthesis && arr[i] != TOK.not;

                if (currentIsNonWrapTemp && arr[i + 1] == TOK.rightBracket)
                {
                    parenCount = pc;
                    continue;
                }
                if (arr[i] == TOK.static_
                    && arr[i + 1].among!(TOK.if_, TOK.else_, TOK.foreach_, TOK.foreach_reverse_)
                    && (i + 2 >= index || arr[i + 2] != TOK.leftCurly))
                {
                    parenCount = pc;
                    continue;
                }

                if (currentIsNonWrapTemp && (arr[i + 1] == TOK.switch_
                        || arr[i + 1] == TOK.leftCurly || arr[i + 1] == TOK.rightParenthesis))
                {
                    parenCount = pc;
                    continue;
                }
            }
            else if (parenCount == 0 && arr[i] == TOK.leftParenthesis && config.dfmt_single_indent == OptionalBoolean
                .f)
                size++;

            if (arr[i] == TOK.not)
                size++;

            parenCount = pc;
            size++;
        }
        return size;
    }

    bool skipDoubleIndent(size_t i, int parenCount) const pure nothrow @safe @nogc
    {
        return (details[i + 1].wrap && arr[i] == TOK.rightParenthesis)
            || (parenCount == 0 && arr[i + 1] == TOK.comma && arr[i] == TOK.leftParenthesis);
    }
}

unittest
{
    IndentStack stack;
    stack.push(TOK.leftCurly);
    assert(stack.length == 1);
    assert(stack.indentLevel == 1);
    stack.pop();
    assert(stack.length == 0);
    assert(stack.indentLevel == 0);
    stack.push(TOK.if_);
    assert(stack.topIsTemp());
    stack.popTempIndents();
    assert(stack.length == 0);
}
