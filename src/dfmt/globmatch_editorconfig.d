module dfmt.globmatch_editorconfig;

import std.path : CaseSensitive;
import std.range : isForwardRange, ElementEncodingType;
import std.traits : isSomeChar, isSomeString;
import std.range.primitives : empty, save, front, popFront;
import std.traits : Unqual;
import std.conv : to;
import std.path : filenameCharCmp, isDirSeparator;

// From std.path with changes:
// * changes meaning to match all characters except '/'
// ** added to take over the old meaning of *
bool globMatchEditorConfig(CaseSensitive cs = CaseSensitive.osDefault, C, Range)(
        Range path, const(C)[] pattern) @safe pure 
        if (isForwardRange!Range && isSomeChar!(ElementEncodingType!Range)
            && isSomeChar!C && is(Unqual!C == Unqual!(ElementEncodingType!Range)))
in
{
    // Verify that pattern[] is valid
    import std.algorithm : balancedParens;

    assert(balancedParens(pattern, '[', ']', 0));
    assert(balancedParens(pattern, '{', '}', 0));
}
do
{
    alias RC = Unqual!(ElementEncodingType!Range);

    static if (RC.sizeof == 1 && isSomeString!Range)
    {
        import std.utf : byChar;

        return globMatchEditorConfig!cs(path.byChar, pattern);
    }
    else static if (RC.sizeof == 2 && isSomeString!Range)
    {
        import std.utf : byWchar;

        return globMatchEditorConfig!cs(path.byWchar, pattern);
    }
    else
    {
        C[] pattmp;
        foreach (ref pi; 0 .. pattern.length)
        {
            const pc = pattern[pi];
            switch (pc)
            {
            case '*':
                if (pi < pattern.length - 1 && pattern[pi + 1] == '*')
                {
                    if (pi + 2 == pattern.length)
                        return true;
                    for (; !path.empty; path.popFront())
                    {
                        auto p = path.save;
                        if (globMatchEditorConfig!(cs, C)(p, pattern[pi + 2 .. pattern.length]))
                            return true;
                    }
                    return false;
                }
                else
                {
                    if (pi + 1 == pattern.length)
                        return true;
                    for (; !path.empty; path.popFront())
                    {
                        auto p = path.save;
                        //if (p[0].to!dchar.isDirSeparator() && !pattern[pi+1].isDirSeparator())
                        //    return false;
                        if (globMatchEditorConfig!(cs, C)(p, pattern[pi + 1 .. pattern.length]))
                            return true;
                        if (p[0].to!dchar.isDirSeparator())
                            return false;
                    }
                    return false;
                }
            case '?':
                if (path.empty)
                    return false;
                path.popFront();
                break;

            case '[':
                if (path.empty)
                    return false;
                auto nc = path.front;
                path.popFront();
                auto not = false;
                ++pi;
                if (pattern[pi] == '!')
                {
                    not = true;
                    ++pi;
                }
                auto anymatch = false;
                while (1)
                {
                    const pc2 = pattern[pi];
                    if (pc2 == ']')
                        break;
                    if (!anymatch && (filenameCharCmp!cs(nc, pc2) == 0))
                        anymatch = true;
                    ++pi;
                }
                if (anymatch == not)
                    return false;
                break;

            case '{':
                // find end of {} section
                auto piRemain = pi;
                for (; piRemain < pattern.length && pattern[piRemain] != '}'; ++piRemain)
                {
                }

                if (piRemain < pattern.length)
                    ++piRemain;
                ++pi;

                while (pi < pattern.length)
                {
                    const pi0 = pi;
                    C pc3 = pattern[pi];
                    // find end of current alternative
                    for (; pi < pattern.length && pc3 != '}' && pc3 != ','; ++pi)
                    {
                        pc3 = pattern[pi];
                    }

                    auto p = path.save;
                    if (pi0 == pi)
                    {
                        if (globMatchEditorConfig!(cs, C)(p, pattern[piRemain .. $]))
                        {
                            return true;
                        }
                        ++pi;
                    }
                    else
                    {
                        /* Match for:
                            *   pattern[pi0..pi-1] ~ pattern[piRemain..$]
                            */
                        if (pattmp.ptr == null) // Allocate this only once per function invocation.
                            // Should do it with malloc/free, but that would make it impure.
                            pattmp = new C[pattern.length];

                        const len1 = pi - 1 - pi0;
                        pattmp[0 .. len1] = pattern[pi0 .. pi - 1];

                        const len2 = pattern.length - piRemain;
                        pattmp[len1 .. len1 + len2] = pattern[piRemain .. $];

                        if (globMatchEditorConfig!(cs, C)(p, pattmp[0 .. len1 + len2]))
                        {
                            return true;
                        }
                    }
                    if (pc3 == '}')
                    {
                        break;
                    }
                }
                return false;

            default:
                if (path.empty)
                    return false;
                if (filenameCharCmp!cs(pc, path.front) != 0)
                    return false;
                path.popFront();
                break;
            }
        }
        return path.empty;
    }
}

unittest
{
    assert(globMatchEditorConfig!(CaseSensitive.no)("foo", "Foo"));
    assert(!globMatchEditorConfig!(CaseSensitive.yes)("foo", "Foo"));

    assert(globMatchEditorConfig("foo", "*"));
    assert(globMatchEditorConfig("foo.bar"w, "*"w));
    assert(globMatchEditorConfig("foo.bar"d, "*.*"d));
    assert(globMatchEditorConfig("foo.bar", "foo*"));
    assert(globMatchEditorConfig("foo.bar"w, "f*bar"w));
    assert(globMatchEditorConfig("foo.bar"d, "f*b*r"d));
    assert(globMatchEditorConfig("foo.bar", "f???bar"));
    assert(globMatchEditorConfig("foo.bar"w, "[fg]???bar"w));
    assert(globMatchEditorConfig("foo.bar"d, "[!gh]*bar"d));

    assert(!globMatchEditorConfig("foo", "bar"));
    assert(!globMatchEditorConfig("foo"w, "*.*"w));
    assert(!globMatchEditorConfig("foo.bar"d, "f*baz"d));
    assert(!globMatchEditorConfig("foo.bar", "f*b*x"));
    assert(!globMatchEditorConfig("foo.bar", "[gh]???bar"));
    assert(!globMatchEditorConfig("foo.bar"w, "[!fg]*bar"w));
    assert(!globMatchEditorConfig("foo.bar"d, "[fg]???baz"d));
    assert(!globMatchEditorConfig("foo.di", "*.d")); // test issue 6634: triggered bad assertion

    assert(globMatchEditorConfig("foo.bar", "{foo,bif}.bar"));
    assert(globMatchEditorConfig("bif.bar"w, "{foo,bif}.bar"w));

    assert(globMatchEditorConfig("bar.foo"d, "bar.{foo,bif}"d));
    assert(globMatchEditorConfig("bar.bif", "bar.{foo,bif}"));

    assert(globMatchEditorConfig("bar.fooz"w, "bar.{foo,bif}z"w));
    assert(globMatchEditorConfig("bar.bifz"d, "bar.{foo,bif}z"d));

    assert(globMatchEditorConfig("bar.foo", "bar.{biz,,baz}foo"));
    assert(globMatchEditorConfig("bar.foo"w, "bar.{biz,}foo"w));
    assert(globMatchEditorConfig("bar.foo"d, "bar.{,biz}foo"d));
    assert(globMatchEditorConfig("bar.foo", "bar.{}foo"));

    assert(globMatchEditorConfig("bar.foo"w, "bar.{ar,,fo}o"w));
    assert(globMatchEditorConfig("bar.foo"d, "bar.{,ar,fo}o"d));
    assert(globMatchEditorConfig("bar.o", "bar.{,ar,fo}o"));

    assert(!globMatchEditorConfig("foo", "foo?"));
    assert(!globMatchEditorConfig("foo", "foo[]"));
    assert(!globMatchEditorConfig("foo", "foob"));
    assert(!globMatchEditorConfig("foo", "foo{b}"));

    assert(globMatchEditorConfig(`foo/foo\bar`, "f**b**r"));
    assert(globMatchEditorConfig("foo", "**"));
    assert(globMatchEditorConfig("foo/bar", "foo/bar"));
    assert(globMatchEditorConfig("foo/bar", "foo/*"));
    assert(globMatchEditorConfig("foo/bar", "*/bar"));
    assert(globMatchEditorConfig("/foo/bar/gluu/sar.png", "**/sar.png"));
    assert(globMatchEditorConfig("/foo/bar/gluu/sar.png", "**/*.png"));
    assert(!globMatchEditorConfig("/foo/bar/gluu/sar.png", "*/sar.png"));
    assert(!globMatchEditorConfig("/foo/bar/gluu/sar.png", "*/*.png"));

    static assert(globMatchEditorConfig("foo.bar", "[!gh]*bar"));
}
