//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.indentation;

import std.d.lexer;

/**
 * Returns: true if the given token type is a wrap indent type
 */
bool isWrapIndent(IdType type) pure nothrow @nogc @safe
{
	return type != tok!"{" && type != tok!"case" && type != tok!"@"
		&& type != tok!"]" && isOperator(type);
}

/**
 * Returns: true if the given token type is a wrap indent type
 */
bool isTempIndent(IdType type) pure nothrow @nogc @safe
{
    return type != tok!"{" && type != tok!"case" && type != tok!"@";
}

/**
 * Stack for managing indent levels.
 */
struct IndentStack
{
    /**
     * Modifies the indent stack to match the state that it had at the most
     * recent appearance of the given token type.
     */
    int indentToMostRecent(IdType item) const
    {
        size_t i = index;
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
            if (!isWrapIndent(arr[i]) && arr[i] != tok!"]")
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
        index = index == 255 ? index : index + 1;
        arr[index] = item;
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
        while (index > 0 && isWrapIndent(arr[index]))
            index--;
    }

    /**
     * Pops all temporary indents from the top of the stack.
     */
    void popTempIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && isTempIndent(arr[index]))
            index--;
    }

    /**
     * Returns: `true` if the top of the indent stack is the given indent type.
     */
    bool topIs(IdType type) const pure nothrow @safe @nogc
    {
        return index > 0 && arr[index] == type;
    }

    /**
     * Returns: `true` if the top of the indent stack is a temporary indent
     */
    bool topIsTemp()
    {
        return index > 0 && index < arr.length && isTempIndent(arr[index]);
    }

    /**
     * Returns: `true` if the top of the indent stack is a wrapping indent
     */
    bool topIsWrap()
    {
        return index > 0 && index < arr.length && isWrapIndent(arr[index]);
    }

    /**
     * Returns: `true` if the top of the indent stack is one of the given token
     *     types.
     */
    bool topIsOneOf(IdType[] types...) const pure nothrow @safe @nogc
    {
        if (index <= 0)
            return false;
        immutable topType = arr[index];
        foreach (t; types)
            if (t == topType)
                return true;
        return false;
    }

    IdType top() const pure nothrow @property @safe @nogc
    {
        return arr[index];
    }

    int indentLevel() const pure nothrow @safe @nogc @property
    {
        return indentSize();
    }

    int length() const pure nothrow @property
    {
        return cast(int) index;
    }

private:

    size_t index;

    IdType[256] arr;

    int indentSize(size_t k = size_t.max) const pure nothrow @safe @nogc
    {
        if (index == 0)
            return 0;
        immutable size_t j = k == size_t.max ? index : k - 1;
        int size = 0;
        foreach (i; 1 .. j + 1)
        {
            if (i + 1 <= index)
            {
                if (arr[i] == tok!"]")
                    continue;
                immutable bool currentIsTemp = isTempIndent(arr[i]);
                immutable bool nextIsTemp = isTempIndent(arr[i + 1]);
                immutable bool nextIsSwitch = arr[i + 1] == tok!"switch";
                if (currentIsTemp && (!nextIsTemp || nextIsSwitch))
                    continue;
            }
            size++;
        }
        return size;
    }
}
