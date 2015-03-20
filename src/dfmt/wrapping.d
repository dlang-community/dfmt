//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.wrapping;

import std.d.lexer;
import dfmt.tokens;
import dfmt.config;

struct State
{
	this(size_t[] breaks, const Token[] tokens, immutable short[] depths, int depth,
		const FormatterConfig* formatterConfig, int currentLineLength, int indentLevel) pure @safe
	{
		import std.math : abs;

		immutable remainingCharsMultiplier = 40;
		immutable newlinePenalty = 800;

		this.breaks = breaks;
		this._depth = depth;
		import std.algorithm : map, sum;

		this._cost = 0;
		for (size_t i = 0; i != breaks.length; ++i)
		{
			immutable b = tokens[breaks[i]].type;
			immutable p = abs(depths[breaks[i]]);
			immutable bc = breakCost(b) * (p == 0 ? 1 : p * 2);
			this._cost += bc;
		}
		int ll = currentLineLength;
		size_t breakIndex = 0;
		size_t i = 0;
		this._solved = true;
		if (breaks.length == 0)
		{
			immutable int l = currentLineLength + tokens.map!(a => tokenLength(a)).sum();
			_cost = l;
			if (l > formatterConfig.columnSoftLimit)
			{
				immutable longPenalty = (l - formatterConfig.columnSoftLimit) * remainingCharsMultiplier;
				_cost += longPenalty;
				this._solved = longPenalty < newlinePenalty;
			}
			else
				this._solved = true;
		}
		else
		{
			do
			{
				immutable size_t j = breakIndex < breaks.length ? breaks[breakIndex] : tokens.length;
				ll += tokens[i .. j].map!(a => tokenLength(a)).sum();
				if (ll > formatterConfig.columnHardLimit)
				{
					this._solved = false;
					break;
				}
				else if (ll > formatterConfig.columnSoftLimit)
					_cost += (ll - formatterConfig.columnSoftLimit) * remainingCharsMultiplier;
				i = j;
				ll = indentLevel * formatterConfig.indentSize;
				breakIndex++;
			}
			while (i + 1 < tokens.length);
		}
		this._cost += breaks.length * newlinePenalty;
	}

	int cost() const pure nothrow @safe @property
	{
		return _cost;
	}

	int depth() const pure nothrow @safe @property
	{
		return _depth;
	}

	int solved() const pure nothrow @safe @property
	{
		return _solved;
	}

	int opCmp(ref const State other) const pure nothrow @safe
	{
		if (cost < other.cost || (cost == other.cost && ((breaks.length
				&& other.breaks.length && breaks[0] > other.breaks[0]) || (_solved && !other.solved))))
		{
			return -1;
		}
		return other.cost > _cost;
	}

	bool opEquals(ref const State other) const pure nothrow @safe
	{
		return other.breaks == breaks;
	}

	size_t toHash() const nothrow @safe
	{
		return typeid(breaks).getHash(&breaks);
	}

	size_t[] breaks;
private:
	int _cost;
	int _depth;
	bool _solved;
}

size_t[] chooseLineBreakTokens(size_t index, const Token[] tokens, immutable short[] depths,
	const FormatterConfig* formatterConfig, int currentLineLength, int indentLevel) pure
{
	import std.container.rbtree : RedBlackTree;
	import std.algorithm : filter, min;

	enum ALGORITHMIC_COMPLEXITY_SUCKS = 25;
	immutable size_t tokensEnd = min(tokens.length, ALGORITHMIC_COMPLEXITY_SUCKS);
	int depth = 0;
	auto open = new RedBlackTree!State;
	open.insert(State(cast(size_t[])[], tokens[0 .. tokensEnd],
		depths[0 .. tokensEnd], depth, formatterConfig, currentLineLength, indentLevel));
	State lowest;
	while (!open.empty)
	{
		State current = open.front();
		if (current.cost < lowest.cost)
			lowest = current;
		open.removeFront();
		if (current.solved)
		{
			current.breaks[] += index;
			return current.breaks;
		}
		foreach (next; validMoves(tokens[0 .. tokensEnd], depths[0 .. tokensEnd],
				current, formatterConfig, currentLineLength, indentLevel, depth))
		{
			open.insert(next);
		}
	}
	if (open.empty)
	{
		lowest.breaks[] += index;
		return lowest.breaks;
	}
	foreach (r; open[].filter!(a => a.solved))
	{
		r.breaks[] += index;
		return r.breaks;
	}
	assert(false);
}

State[] validMoves(const Token[] tokens, immutable short[] depths, ref const State current,
	const FormatterConfig* formatterConfig, int currentLineLength, int indentLevel,
	int depth) pure @safe
{
	import std.algorithm : sort, canFind;
	import std.array : insertInPlace;

	State[] states;
	foreach (i, token; tokens)
	{
		if (!isBreakToken(token.type) || current.breaks.canFind(i))
			continue;
		size_t[] breaks;
		breaks ~= current.breaks;
		breaks ~= i;
		sort(breaks);
		states ~= State(breaks, tokens, depths, depth + 1, formatterConfig,
			currentLineLength, indentLevel);
	}
	return states;
}
