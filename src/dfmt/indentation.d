//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.indentation;

import dfmt.config;
import dfmt.editorconfig;
import dparse.lexer;

import std.bitmanip : bitfields;

/**
 * Returns: true if the given token type is a wrap indent type
 */
bool isWrapIndent(IdType type) pure nothrow @nogc @safe
{
    return type != tok!"{" && type != tok!"case" && type != tok!"@"
        && type != tok!"]" && type != tok!"(" && type != tok!")" && isOperator(type);
}

/**
 * Returns: true if the given token type is a temporary indent type
 */
bool isTempIndent(IdType type) pure nothrow @nogc @safe
{
    return type != tok!")" && type != tok!"{" && type != tok!"case" && type != tok!"@";
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
            bool, "wrap", 1,
            // temporary indentation which get's reverted when a block starts
            // generally true for all tokens except ), {, case, @
            bool, "temp", 1,
            // emit minimal newlines
            bool, "mini", 1,
            // for associative arrays or arrays containing them, break after every item
            bool, "breakEveryItem", 1,
            // when an item inside an array would break mid-item, definitely break at the comma first
            bool, "preferLongBreaking", 1,
            uint, "",     27));
    }

    /**
     * Get the indent size at the most recent occurrence of the given indent type
     */
    int indentToMostRecent(IdType item) const
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
            if (!details[i - 1].wrap && arr[i - 1] != tok!"]")
                break;
            tempIndentCount++;
        }
        return tempIndentCount;
    }

    /**
     * Pushes the given indent type on to the stack.
     */
    void push(IdType item) pure nothrow
    {
        Details detail;
        detail.wrap = isWrapIndent(item);
        detail.temp = isTempIndent(item);
        push(item, detail);
    }

    /**
     * Pushes the given indent type on to the stack.
     */
    void push(IdType item, Details detail) pure nothrow
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

    bool topAre(IdType[] types...)
    {
        if (types.length > index)
            return false;
        return arr[index - types.length .. index] == types;

    }

    /**
     * Returns: `true` if the top of the indent stack is the given indent type.
     */
    bool topIs(IdType type) const pure nothrow @safe @nogc
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
    bool topIsTemp(IdType item)
    {
        return index > 0 && index <= arr.length && arr[index - 1] == item && details[index - 1].temp;
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
    bool topIsWrap(IdType item)
    {
        return index > 0 && index <= arr.length && arr[index - 1] == item && details[index - 1].wrap;
    }

    /**
     * Returns: `true` if the top of the indent stack is one of the given token
     *     types.
     */
    bool topIsOneOf(IdType[] types...) const pure nothrow @safe @nogc
    {
        if (index == 0)
            return false;
        immutable topType = arr[index - 1];
        foreach (t; types)
            if (t == topType)
                return true;
        return false;
    }

    IdType top() const pure nothrow @property @safe @nogc
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
        import dparse.lexer : str;
        import std.algorithm.iteration : map;
        import std.stdio : stderr;

        if (pos == size_t.max)
            stderr.writefln("\033[31m%s:%d %(%s %)\033[0m", file, line, arr[0 .. index].map!(a => str(a)));
        else
            stderr.writefln("\033[31m%s:%d at %d %(%s %)\033[0m", file, line, pos, arr[0 .. index].map!(a => str(a)));
    }

private:

    size_t index;

    IdType[256] arr;
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
            immutable int pc = (arr[i] == tok!"!" || arr[i] == tok!"(" || arr[i] == tok!")") ? parenCount + 1
                : parenCount;
            if ((details[i].wrap || arr[i] == tok!"(") && parenCount > 1)
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
                    && details[i].temp && arr[i] != tok!")" && arr[i] != tok!"!";

                if (currentIsNonWrapTemp && arr[i + 1] == tok!"]")
                {
                    parenCount = pc;
                    continue;
                }
                if (arr[i] == tok!"static"
                    && arr[i + 1].among!(tok!"if", tok!"else", tok!"foreach", tok!"foreach_reverse")
                    && (i + 2 >= index || arr[i + 2] != tok!"{"))
                {
                    parenCount = pc;
                    continue;
                }
                if (currentIsNonWrapTemp && (arr[i + 1] == tok!"switch"
                        || arr[i + 1] == tok!"{" || arr[i + 1] == tok!")"))
                {
                    parenCount = pc;
                    continue;
                }
            }
            else if (parenCount == 0 && arr[i] == tok!"(" && config.dfmt_single_indent == OptionalBoolean.f)
                size++;

            if (arr[i] == tok!"!")
                size++;

            parenCount = pc;
            size++;
        }
        return size;
    }

    bool skipDoubleIndent(size_t i, int parenCount) const pure nothrow @safe @nogc
    {
        return (details[i + 1].wrap && arr[i] == tok!")")
            || (parenCount == 0 && arr[i + 1] == tok!"," && arr[i] == tok!"(");
    }
}

unittest
{
    IndentStack stack;
    stack.push(tok!"{");
    assert(stack.length == 1);
    assert(stack.indentLevel == 1);
    stack.pop();
    assert(stack.length == 0);
    assert(stack.indentLevel == 0);
    stack.push(tok!"if");
    assert(stack.topIsTemp());
    stack.popTempIndents();
    assert(stack.length == 0);
}
