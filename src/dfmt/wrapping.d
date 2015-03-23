//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.wrapping;

import std.d.lexer;
import dfmt.tokens;
import dfmt.config;

version = WTF_DMD;

struct State
{
    this(uint breaks, const Token[] tokens, immutable short[] depths,
        const Config* config, int currentLineLength, int indentLevel) pure @safe
    {
        import std.math : abs;
        import core.bitop : popcnt, bsf;
        import std.algorithm : min;
        import std.algorithm : map, sum;

        // TODO: Figure out what is going on here.
        version (WTF_DMD)
        {
            enum int remainingCharsMultiplier = 40;
            enum int newlinePenalty = 800;
        }
        else
        {
            immutable int remainingCharsMultiplier = config.columnHardLimit - config.columnSoftLimit;
            immutable int newlinePenalty = remainingCharsMultiplier * 20;
            assert(remainingCharsMultiplier == 40);
            assert(newlinePenalty == 800);
        }

        int cost = 0;
        for (size_t i = 0; i != uint.sizeof * 8; ++i)
        {
            if (((1 << i) & breaks) == 0)
                continue;
            immutable b = tokens[i].type;
            immutable p = abs(depths[i]);
            immutable bc = breakCost(b) * (p == 0 ? 1 : p * 2);
            cost += bc;
        }
        int ll = currentLineLength;
        bool solved = true;
        if (breaks == 0)
        {
            immutable int l = currentLineLength + tokens.map!(a => tokenLength(a)).sum();
            cost = l;
            if (l > config.columnSoftLimit)
            {
                immutable int longPenalty = (l - config.columnSoftLimit) * remainingCharsMultiplier;
                cost += longPenalty;
                solved = longPenalty < newlinePenalty;
            }
            else
                solved = true;
        }
        else
        {
            size_t i = 0;
            foreach (_; 0 .. uint.sizeof * 8)
            {
                immutable size_t k = breaks >>> i;
                immutable bool b = k == 0;
                immutable size_t j = min(i + bsf(k) + 1, tokens.length);
                ll += tokens[i .. j].map!(a => tokenLength(a)).sum();
                if (ll > config.columnHardLimit)
                {
                    solved = false;
                    break;
                }
                else if (ll > config.columnSoftLimit)
                    cost += (ll - config.columnSoftLimit) * remainingCharsMultiplier;
                i = j;
                ll = indentLevel * config.indentSize;
                if (b)
                    break;
            }
        }
        cost += popcnt(breaks) * newlinePenalty;

        this.breaks = breaks;
        this._cost = cost;
        this._solved = solved;
    }

    int cost() const pure nothrow @safe @property
    {
        return _cost;
    }

    int solved() const pure nothrow @safe @property
    {
        return _solved;
    }

    int opCmp(ref const State other) const pure nothrow @safe
    {
        import core.bitop : bsf, popcnt;

        if (cost < other.cost || (cost == other.cost && ((popcnt(breaks)
                && popcnt(other.breaks) && bsf(breaks) > bsf(other.breaks))
                || (_solved && !other.solved))))
        {
            return -1;
        }
        return other.cost > _cost;
    }

    bool opEquals(ref const State other) const pure nothrow @safe
    {
        return other.breaks == breaks;
    }

    size_t toHash() const pure nothrow @safe
    {
        return breaks;
    }

    uint breaks;

private:
    int _cost;
    bool _solved;
}

size_t[] chooseLineBreakTokens(size_t index, const Token[] tokens,
    immutable short[] depths, const Config* config, int currentLineLength, int indentLevel)
{
    import std.container.rbtree : RedBlackTree;
    import std.algorithm : filter, min;
    import core.bitop : popcnt;

    static size_t[] genRetVal(uint breaks, size_t index) pure nothrow @safe
    {
        auto retVal = new size_t[](popcnt(breaks));
        size_t j = 0;
        foreach (uint i; 0 .. uint.sizeof * 8)
            if ((1 << i) & breaks)
                retVal[j++] = index + i;
        return retVal;
    }

    enum ALGORITHMIC_COMPLEXITY_SUCKS = uint.sizeof * 8;
    immutable size_t tokensEnd = min(tokens.length, ALGORITHMIC_COMPLEXITY_SUCKS);
    auto open = new RedBlackTree!State;
    open.insert(State(0, tokens[0 .. tokensEnd], depths[0 .. tokensEnd],
        config, currentLineLength, indentLevel));
    State lowest;
    while (!open.empty)
    {
        State current = open.front();
        if (current.cost < lowest.cost)
            lowest = current;
        open.removeFront();
        if (current.solved)
        {
            return genRetVal(current.breaks, index);
        }
        validMoves!(typeof(open))(open, tokens[0 .. tokensEnd],
            depths[0 .. tokensEnd], current.breaks, config, currentLineLength, indentLevel);
    }
    if (open.empty)
        return genRetVal(lowest.breaks, index);
    foreach (r; open[].filter!(a => a.solved))
        return genRetVal(r.breaks, index);
    assert(false);
}

void validMoves(OR)(auto ref OR output, const Token[] tokens,
    immutable short[] depths, uint current, const Config* config,
    int currentLineLength, int indentLevel)
    {
    import std.algorithm : sort, canFind;
    import std.array : insertInPlace;

    foreach (i, token; tokens)
    {
        if (!isBreakToken(token.type) || (((1 << i) & current) != 0))
            continue;
        immutable uint breaks = current | (1 << i);
        output.insert(State(breaks, tokens, depths, config,
            currentLineLength, indentLevel));
    }
}
