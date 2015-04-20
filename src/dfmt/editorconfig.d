module dfmt.editorconfig;
import std.regex : ctRegex;

private auto headerRe = ctRegex!(`^\s*\[([^\n]+)\]\s*(:?#.*)?$`);
private auto propertyRe = ctRegex!(`^\s*([\w_]+)\s*=\s*([\w_]+)\s*[#;]?.*$`);
private auto commentRe = ctRegex!(`^\s*[#;].*$`);

enum OptionalBoolean : ubyte
{
    unspecified = 3,
    t = 1,
    f = 0
}

enum IndentStyle : ubyte
{
    unspecified,
    tab,
    space
}

enum EOL : ubyte
{
    unspecified,
    lf,
    cr,
    crlf
}

mixin template StandardEditorConfigFields()
{
    string pattern;
    OptionalBoolean root;
    EOL end_of_line;
    OptionalBoolean insert_final_newline;
    string charset;
    IndentStyle indent_style;
    int indent_size = -1;
    int tab_width = -1;
    OptionalBoolean trim_trailing_whitespace;
    int max_line_length = -1;

    void merge(ref const typeof(this) other, const string fileName)
    {
        import std.path : globMatch;
        import std.traits : FieldNameTuple;

        if (other.pattern is null || !fileName.globMatch(other.pattern))
            return;
        foreach (N; FieldNameTuple!(typeof(this)))
        {
            alias T = typeof(mixin(N));
            const otherN = mixin("other." ~ N);
            auto thisN = &mixin("this." ~ N);
            static if (N == "pattern")
                continue;
            else static if (is (T == enum))
                *thisN = otherN != T.unspecified ? otherN : *thisN;
            else static if (is (T == int))
                *thisN = otherN != -1 ? otherN : *thisN;
            else static if (is (T == string))
                *thisN = otherN !is null ? otherN : *thisN;
            else
                static assert(false);
        }
    }
}

/**
 * Params:
 *     path = the path to the file
 * Returns:
 *     The configuration for the file at the given path
 */
EC getConfigFor(EC)(string path)
{
    import std.stdio : File;
    import std.regex : regex, match;
    import std.path : globMatch, dirName, baseName, pathSplitter, buildPath;
    import std.algorithm : reverse, map, filter, each;
    import std.array : array;

    EC result;
    EC[][] configs;
    string dir = dirName(path);
    immutable string fileName = baseName(path);
    string[] pathParts = cast(string[]) pathSplitter(dir).array();
    for (size_t i = pathParts.length; i > 1; i--)
    {
        EC[] sections = parseConfig!EC(buildPath(pathParts[0 .. i]));
        if (sections.length)
            configs ~= sections;
        if (!sections.map!(a => a.root).filter!(a => a == OptionalBoolean.t).empty)
            break;
    }
    reverse(configs);
    configs.each!(a => a.each!(b => result.merge(b, fileName)))();
    return result;
}

private EC[] parseConfig(EC)(string dir)
{
    import std.stdio : File;
    import std.file : exists;
    import std.path : buildPath;
    import std.regex : matchAll;
    import std.traits : FieldNameTuple;
    import std.conv : to;
    import std.uni : toLower;

    EC section;
    EC[] sections;
    immutable string path = buildPath(dir, ".editorconfig");
    if (!exists(path))
        return sections;

    File f = File(path);
    foreach (line; f.byLineCopy())
    {
        auto headerMatch = line.matchAll(headerRe);
        if (headerMatch)
        {
            sections ~= section;
            section = EC.init;
            auto c = headerMatch.captures;
            c.popFront();
            section.pattern = c.front();
        }
        else
        {
            auto propertyMatch = line.matchAll(propertyRe);
            if (propertyMatch)
            {
                auto c = propertyMatch.captures;
                c.popFront();
                immutable string propertyName = c.front();
                c.popFront();
                immutable string propertyValue = toLower(c.front());
                foreach (F; FieldNameTuple!EC)
                {
                    enum configDot = "section." ~ F;
                    alias FieldType = typeof(mixin(configDot));
                    if (F == propertyName)
                    {
                        static if (is(FieldType == OptionalBoolean))
                            mixin(configDot) = propertyValue == "true" ? OptionalBoolean.t
                                : OptionalBoolean.f;
                        else
                                    mixin(configDot) = to!(FieldType)(propertyValue);
                    }
                }
            }
        }
    }
    sections ~= section;
    return sections;
}
