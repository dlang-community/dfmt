//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.wrapping;

import dparse.lexer;
import dfmt.tokens;
import dfmt.config;

struct State
{
    this(uint breaks, const Token[] tokens, immutable short[] depths,
            const Config* config, int currentLineLength, int indentLevel) pure @safe
    {
        import std.math : abs;
        import core.bitop : popcnt, bsf;
        import std.algorithm : min, map, sum;

        immutable int remainingCharsMultiplier = 25;
        immutable int newlinePenalty = 480;

        this.breaks = breaks;
        this._cost = 0;
        this._solved = true;

        if (breaks == 0)
        {
            immutable int l = currentLineLength + tokens.map!(a => tokenLength(a)).sum();
            if (l > config.dfmt_soft_max_line_length)
            {
                immutable int longPenalty = (l - config.dfmt_soft_max_line_length)
                    * remainingCharsMultiplier;
                this._cost += longPenalty;
                this._solved = longPenalty < newlinePenalty;
            }
        }
        else
        {
            foreach (size_t i; 0 .. (uint.sizeof * 8))
            {
                if (((1 << i) & breaks) == 0)
                    continue;
                immutable prevType = i > 0 ? tokens[i - 1].type : tok!"";
                immutable currentType = tokens[i].type;
                immutable p = abs(depths[i]);
                immutable bc = breakCost(prevType, currentType) * (p == 0 ? 1 : p * 2);
                this._cost += bc + newlinePenalty;
            }

            int ll = currentLineLength;
            size_t i = 0;
            foreach (_; 0 .. uint.sizeof * 8)
            {
                immutable uint k = breaks >>> i;
                immutable bool b = k == 0;
                immutable uint bits = b ? ALGORITHMIC_COMPLEXITY_SUCKS : bsf(k);
                immutable size_t j = min(i + bits + 1, tokens.length);
                ll += tokens[i .. j].map!(a => tokenLength(a)).sum();
                if (ll > config.dfmt_soft_max_line_length)
                {
                    immutable int longPenalty = (ll - config.dfmt_soft_max_line_length)
                        * remainingCharsMultiplier;
                    this._cost += longPenalty;
                }
                if (ll > config.max_line_length)
                {
                    this._solved = false;
                    break;
                }
                i = j;
                if (indentLevel < 0)
                    ll = (abs(indentLevel) + 1) * config.indent_size;
                else
                    ll = (indentLevel + (i == 0 ? 0 : 1)) * config.indent_size;
                if (b)
                    break;
            }
        }
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

        if (_cost < other._cost)
            return -1;
        if (_cost == other._cost && (breaks != 0 && other.breaks != 0
                && bsf(breaks) > bsf(other.breaks)))
            return -1;
        return _cost > other._cost;
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

private enum ALGORITHMIC_COMPLEXITY_SUCKS = uint.sizeof * 8;

/**
 * Note: Negative values for `indentLevel` are treated specially: costs for
 *     continuation indents are reduced. This is used for array literals.
 */
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

    immutable size_t tokensEnd = min(tokens.length, ALGORITHMIC_COMPLEXITY_SUCKS);
    auto open = new RedBlackTree!State;
    open.insert(State(0, tokens[0 .. tokensEnd], depths[0 .. tokensEnd], config,
            currentLineLength, indentLevel));
    State lowest;
    lowest._solved = false;
    int tries = 0;
    while (!open.empty && tries < 10_00)
    {
        tries++;
        State current = open.front();
        open.removeFront();
        if (current.solved)
            return genRetVal(current.breaks, index);
        if (current < lowest)
            lowest = current;
        validMoves!(typeof(open))(open, tokens[0 .. tokensEnd], depths[0 .. tokensEnd],
                current.breaks, config, currentLineLength, indentLevel);
    }
    foreach (r; open[].filter!(a => a.solved))
        return genRetVal(r.breaks, index);
    if (open[].front < lowest)
        return genRetVal(open[].front.breaks, index);
    else
        return genRetVal(lowest.breaks, index);
}

void validMoves(OR)(auto ref OR output, const Token[] tokens, immutable short[] depths,
        uint current, const Config* config, int currentLineLength, int indentLevel)
{
    foreach (i, token; tokens)
    {
        if (!isBreakToken(token.type) || (((1 << i) & current) != 0))
            continue;
        immutable uint breaks = current | (1 << i);
        output.insert(State(breaks, tokens, depths, config, currentLineLength, indentLevel));
    }
}
