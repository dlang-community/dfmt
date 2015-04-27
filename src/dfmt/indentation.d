//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.indentation;

import std.d.lexer;

bool isWrapIndent(IdType type) pure nothrow @nogc @safe
{
    return type != tok!"{" && type != tok!":" && type != tok!"]" && isOperator(type);
}

bool isTempIndent(IdType type) pure nothrow @nogc @safe
{
    return type != tok!"{";
}

struct IndentStack
{
    int indentToMostRecent(IdType item)
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

    void push(IdType item) pure nothrow
    {
        index = index == 255 ? index : index + 1;
        arr[index] = item;
    }

    void pop() pure nothrow
    {
        index = index == 0 ? index : index - 1;
    }

    void popWrapIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && isWrapIndent(arr[index]))
            index--;
    }

    void popTempIndents() pure nothrow @safe @nogc
    {
        while (index > 0 && isTempIndent(arr[index]))
            index--;
    }

    bool topIs(IdType type) const pure nothrow @safe @nogc
    {
        return index > 0 && arr[index] == type;
    }

    bool topIsTemp()
    {
        return index > 0 && index < arr.length && isTempIndent(arr[index]);
    }

    bool topIsWrap()
    {
        return index > 0 && index < arr.length && isWrapIndent(arr[index]);
    }

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

    int indentSize(size_t k = size_t.max) const pure nothrow @safe @nogc
    {
        if (index == 0)
            return 0;
        immutable size_t j = k == size_t.max ? index : k - 1;
        int size = 0;
        foreach (i; 1 .. j + 1)
        {
            if ((i + 1 <= index && arr[i] != tok!"]" && !isWrapIndent(arr[i])
                    && isTempIndent(arr[i]) && (!isTempIndent(arr[i + 1])
                    || arr[i + 1] == tok!"switch")))
            {
                continue;
            }
            size++;
        }
        return size;
    }

    int length() const pure nothrow @property
    {
        return cast(int) index;
    }

private:
    size_t index;
    IdType[256] arr;
}
