//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.indentation;

import dparse.lexer;

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
    /**
     * Get the indent size at the most recent occurence of the given indent type
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
            if (!isWrapIndent(arr[i - 1]) && arr[i - 1] != tok!"]")
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
        arr[index] = item;
        index = index + 1 == arr.length ? index : index + 1;
    }

    /**
     * Pops the top indent from the stack.
     */
    void pop() pure nothrow
    {
        index = index == 0 ? index : index - 1;
    }

    /**
     * Pops all wrapping indents from the top of the stack.
     */
    void popWrapIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && isWrapIndent(arr[index - 1]))
            index--;
    }

    /**
     * Pops all temporary indents from the top of the stack.
     */
    void popTempIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && isTempIndent(arr[index - 1]))
            index--;
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
        return index > 0 && index <= arr.length && isTempIndent(arr[index - 1]);
    }

    /**
     * Returns: `true` if the top of the indent stack is a wrapping indent
     */
    bool topIsWrap()
    {
        return index > 0 && index <= arr.length && isWrapIndent(arr[index - 1]);
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

    int indentLevel() const pure nothrow @property @safe @nogc
    {
        return indentSize();
    }

    int length() const pure nothrow @property @safe @nogc
    {
        return cast(int) index;
    }

    /+void dump()
    {
        import std.stdio : stderr;
        import dparse.lexer : str;
        import std.algorithm.iteration : map;

        stderr.writefln("\033[31m%(%s %)\033[0m", arr[0 .. index].map!(a => str(a)));
    }+/

private:

    size_t index;

    IdType[256] arr;

    int indentSize(const size_t k = size_t.max) const pure nothrow @safe @nogc
    {
        if (index == 0 || k == 0)
            return 0;
        immutable size_t j = k == size_t.max ? index : k;
        int size = 0;
        int parenCount;
        foreach (i; 0 .. j)
        {
            immutable int pc = (arr[i] == tok!"!" || arr[i] == tok!"(" || arr[i] == tok!")") ? parenCount + 1
                : parenCount;
            if ((isWrapIndent(arr[i]) || arr[i] == tok!"(") && parenCount > 1)
            {
                parenCount = pc;
                continue;
            }
            if (i + 1 < index)
            {
                if (arr[i] == tok!"]")
                    continue;
                immutable currentIsNonWrapTemp = !isWrapIndent(arr[i])
                    && isTempIndent(arr[i]) && arr[i] != tok!")" && arr[i] != tok!"!";
                if (currentIsNonWrapTemp && (arr[i + 1] == tok!"switch"
                        || arr[i + 1] == tok!"{" || arr[i + 1] == tok!")"))
                {
                    parenCount = pc;
                    continue;
                }
            }
            if (arr[i] == tok!"!")
                size++;
            parenCount = pc;
            size++;
        }
        return size;
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
