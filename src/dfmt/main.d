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
    import dfmt.config : Config;
    import dfmt.formatter : format;
    import std.path : buildPath, expandTilde;
    import dfmt.editorconfig : getConfigFor;
    import std.getopt : getopt;

    int main(string[] args)
    {
        bool inplace = false;
        Config optConfig;
        optConfig.pattern = "*.d";
        bool showHelp;
        getopt(args,
            "align_switch_statements", &optConfig.dfmt_align_switch_statements,
            "brace_style", &optConfig.dfmt_brace_style,
            "end_of_line", &optConfig.end_of_line,
            "help|h", &showHelp,
            "indent_size", &optConfig.indent_size,
            "indent_style|t", &optConfig.indent_style,
            "inplace", &inplace,
            "max_line_length", &optConfig.max_line_length,
            "max_line_length", &optConfig.max_line_length,
            "outdent_attributes", &optConfig.dfmt_outdent_attributes,
            "outdent_labels", &optConfig.dfmt_outdent_labels,
            "space_after_cast", &optConfig.dfmt_space_after_cast,
            "split_operator_at_line_end", &optConfig.dfmt_split_operator_at_line_end,
            "tab_width", &optConfig.tab_width);

        if (showHelp)
        {
            printHelp();
            return 0;
        }

        args.popFront();
        immutable bool readFromStdin = args.length == 0;
        immutable string filePath = createFilePath(readFromStdin, readFromStdin ? null : args[0]);
        Config config;
        config.initializeWithDefaults();
        Config fileConfig = getConfigFor!Config(filePath);
        fileConfig.pattern = "*.d";
        config.merge(fileConfig, filePath);
        config.merge(optConfig, filePath);

        if (!config.isValid())
            return 1;

        File output = stdout;
        ubyte[] buffer;

        if (readFromStdin)
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

private void printHelp()
{
    writeln(`dfmt 0.3.0-dev

Options:
    --help | -h            Print this help message
    --inplace              Edit files in place

Formatting Options:
    --align_switch_statements
    --brace_style
    --end_of_line
    --help|h
    --indent_size
    --indent_style|t
    --inplace
    --max_line_length
    --max_line_length
    --outdent_attributes
    --outdent_labels
    --space_after_cast
    --split_operator_at_line_end`);
}

private string createFilePath(bool readFromStdin, string fileName)
//out (result)
//{
//    stderr.writeln(__FUNCTION__, ": ", result);
//}
//body
{
    import std.file : getcwd;
    import std.path : isRooted;

    immutable string cwd = getcwd();
    if (readFromStdin)
        return buildPath(cwd, "dummy.d");
    if (isRooted(fileName))
        return fileName;
    else
        return buildPath(cwd, fileName);
}
