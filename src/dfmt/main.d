//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.main;

version (NoMain)
{
}
else
{
    import std.array : front, popFront;
    import std.stdio : stdout, stdin, stderr, writeln, File;
    import dfmt.config : Config, getHelp;
    import dfmt.formatter : format;

    int main(string[] args)
    {
        bool inplace = false;
        Config config;
        static if (__VERSION__ >= 2067)
        {
            import std.getopt : getopt, defaultGetoptPrinter;
            auto getOptResult = getopt(args,
                "inplace", "Modify files in-place", &inplace,
                "tabs|t", getHelp!(Config.useTabs), &config.useTabs,
                "braces", getHelp!(Config.braceStyle), &config.braceStyle,
                "colSoft", getHelp!(Config.columnSoftLimit), &config.columnSoftLimit,
                "colHard", getHelp!(Config.columnHardLimit), &config.columnHardLimit,
                "tabSize", getHelp!(Config.tabSize), &config.tabSize,
                "indentSize", getHelp!(Config.indentSize), &config.indentSize,
                "alignSwitchCases", getHelp!(Config.alignSwitchStatements), &config.alignSwitchStatements,
                "outdentLabels", getHelp!(Config.outdentLabels), &config.outdentLabels,
                "outdentAttributes", getHelp!(Config.outdentAttributes), &config.outdentAttributes,
                "splitOperatorAtEnd", getHelp!(Config.splitOperatorAtEnd), &config.splitOperatorAtEnd,
                "spaceAfterCast", getHelp!(Config.spaceAfterCast), &config.spaceAfterCast,
                "newlineType", getHelp!(Config.newlineType), &config.newlineType);

            if (getOptResult.helpWanted)
            {
                defaultGetoptPrinter("dfmt 0.3.0-dev\n\nOptions:", getOptResult.options);
                return 0;
            }
        }
        else
        {
            import std.getopt : getopt;
            bool showHelp;
            getopt(args,
                "help|h", &showHelp,
                "inplace", &inplace,
                "tabs|t", &config.useTabs,
                "braces", &config.braceStyle,
                "colSoft", &config.columnSoftLimit,
                "colHard", &config.columnHardLimit,
                "tabSize", &config.tabSize,
                "indentSize", &config.indentSize,
                "alignSwitchCases", &config.alignSwitchStatements,
                "outdentLabels", &config.outdentLabels,
                "outdentAttributes", &config.outdentAttributes,
                "splitOperatorAtEnd", &config.splitOperatorAtEnd,
                "spaceAfterCast", &config.spaceAfterCast,
                "newlineType", &config.newlineType);
            if (showHelp)
            {
                writeln(`dfmt 0.3.0-dev

Options:
    --help | -h            Print this help message
    --inplace              Edit files in place
    --tabs | -t            Use tabs instead of spaces
    --braces               Brace style can be 'otbs', 'allman', or 'stroustrup'
    --colSoft              Column soft limit
    --colHard              Column hard limit
    --tabSize              Size of tabs
    --indentSize           Number of spaces used for indentation
    --alignSwitchCases     Align cases, defaults, and labels with enclosing
                           switches
    --outdentLabels        Outdent labels
    --outdentAttributes    Outdent attribute declarations
    --splitOperatorAtEnd   Place operators at the end of the previous line when
                           wrapping
    --spaceAfterCast       Insert spaces after cast expressions
    --newlineType          Newline type can be 'cr', 'lf', or 'crlf'`);
                return 0;
            }
        }

        if (!config.isValid())
            return 1;

        File output = stdout;
        ubyte[] buffer;
        args.popFront();
        if (args.length == 0)
        {
            ubyte[4096] inputBuffer;
            ubyte[] b;
            while (true)
            {
                b = stdin.rawRead(inputBuffer);
                if (b.length)
                    buffer ~= b;
                else
                    break;
            }
            dfmt.formatter.format("stdin", buffer, output.lockingTextWriter(), &config);
        }
        else
        {
            import std.file : dirEntries, isDir, SpanMode;

            if (args.length >= 2)
                inplace = true;
            while (args.length > 0)
            {
                const path = args.front;
                args.popFront();
                if (isDir(path))
                {
                    inplace = true;
                    foreach (string name; dirEntries(path, "*.d", SpanMode.depth))
                    {
                        args ~= name;
                    }
                    continue;
                }
                File f = File(path);
                buffer = new ubyte[](cast(size_t) f.size);
                f.rawRead(buffer);
                if (inplace)
                    output = File(path, "wb");
                dfmt.formatter.format(path, buffer, output.lockingTextWriter(), &config);
            }
        }
        return 0;
    }
}
