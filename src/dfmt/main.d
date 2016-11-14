//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.main;

private enum VERSION = "0.5.0";

version (NoMain)
{
}
else
{
    import std.array : front, popFront;
    import std.stdio : stdout, stdin, stderr, writeln, File;
    import dfmt.config : Config;
    import dfmt.formatter : format;
    import std.path : buildPath, dirName, expandTilde;
    import dfmt.editorconfig : getConfigFor;
    import std.getopt : getopt, GetOptException;

    int main(string[] args)
    {
        bool inplace = false;
        Config optConfig;
        optConfig.pattern = "*.d";
        bool showHelp;
        bool showVersion;
        string explicitConfigDir;

        void handleBooleans(string option, string value)
        {
            import dfmt.editorconfig : OptionalBoolean;
            import std.exception : enforceEx;

            enforceEx!GetOptException(value == "true" || value == "false", "Invalid argument");
            immutable OptionalBoolean optVal = value == "true" ? OptionalBoolean.t
                : OptionalBoolean.f;
            switch (option)
            {
            case "align_switch_statements":
                optConfig.dfmt_align_switch_statements = optVal;
                break;
            case "outdent_attributes":
                optConfig.dfmt_outdent_attributes = optVal;
                break;
            case "space_after_cast":
                optConfig.dfmt_space_after_cast = optVal;
                break;
            case "split_operator_at_line_end":
                optConfig.dfmt_split_operator_at_line_end = optVal;
                break;
            case "selective_import_space":
                optConfig.dfmt_selective_import_space = optVal;
                break;
            case "compact_labeled_statements":
                optConfig.dfmt_compact_labeled_statements = optVal;
                break;
            default:
                assert(false, "Invalid command-line switch");
            }
        }

        try
        {
            // dfmt off
            getopt(args,
                "version", &showVersion,
                "align_switch_statements", &handleBooleans,
                "brace_style", &optConfig.dfmt_brace_style,
                "config|c", &explicitConfigDir,
                "end_of_line", &optConfig.end_of_line,
                "help|h", &showHelp,
                "indent_size", &optConfig.indent_size,
                "indent_style|t", &optConfig.indent_style,
                "inplace|i", &inplace,
                "max_line_length", &optConfig.max_line_length,
                "soft_max_line_length", &optConfig.dfmt_soft_max_line_length,
                "outdent_attributes", &handleBooleans,
                "space_after_cast", &handleBooleans,
                "selective_import_space", &handleBooleans,
                "split_operator_at_line_end", &handleBooleans,
                "compact_labeled_statements", &handleBooleans,
                "tab_width", &optConfig.tab_width,
                "template_constraint_style", &optConfig.dfmt_template_constraint_style);
            // dfmt on
        }
        catch (GetOptException e)
        {
            stderr.writeln(e.msg);
            return 1;
        }

        if (showVersion)
        {
            writeln(VERSION);
            return 0;
        }

        if (showHelp)
        {
            printHelp();
            return 0;
        }

        args.popFront();
        immutable bool readFromStdin = args.length == 0;

        File output = stdout;
        version (Windows)
        {
            // On Windows, set stdout to binary mode (needed for correct EOL writing)
            // See Phobos' stdio.File.rawWrite
            {
                import std.stdio : _fileno, _O_BINARY, _setmode;

                immutable fd = _fileno(output.getFP());
                _setmode(fd, _O_BINARY);
                version (CRuntime_DigitalMars)
                {
                    import core.atomic : atomicOp;
                    import core.stdc.stdio : __fhnd_info, FHND_TEXT;

                    atomicOp!"&="(__fhnd_info[fd], ~FHND_TEXT);
                }
            }
        }

        ubyte[] buffer;

        Config explicitConfig;
        if (explicitConfigDir)
        {
            import std.path : exists, isDir;

            if (!exists(explicitConfigDir) || !isDir(explicitConfigDir))
            {
                stderr.writeln("--config_dir|c must specify existing directory path");
                return 1;
            }
            explicitConfig = getConfigFor!Config(explicitConfigDir);
            explicitConfig.pattern = "*.d";
        }

        if (readFromStdin)
        {
            import std.file : getcwd;

            Config config;
            config.initializeWithDefaults();
            if (explicitConfigDir != "")
            {
                config.merge(explicitConfig, buildPath(explicitConfigDir, "dummy.d"));
            }
            config.merge(optConfig, buildPath(getcwd(), "dummy.d"));
            if (!config.isValid())
                return 1;
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
            format("stdin", buffer, output.lockingTextWriter(), &config);
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
                        args ~= name;
                    continue;
                }
                Config config;
                config.initializeWithDefaults();
                if (explicitConfigDir != "")
                {
                    config.merge(explicitConfig, buildPath(explicitConfigDir, "dummy.d"));
                }
                else
                {
                    Config fileConfig = getConfigFor!Config(path);
                    fileConfig.pattern = "*.d";
                    config.merge(fileConfig, path);
                }
                config.merge(optConfig, path);
                if (!config.isValid())
                    return 1;
                File f = File(path);
                buffer = new ubyte[](cast(size_t) f.size);
                f.rawRead(buffer);
                if (inplace)
                    output = File(path, "wb");
                format(path, buffer, output.lockingTextWriter(), &config);
            }
        }
        return 0;
    }
}

private string optionsToString(E)() if (is(E == enum))
{
    import std.traits : EnumMembers;
    import std.conv : to;

    string result = "(";
    foreach (i, option; EnumMembers!E)
    {
        immutable s = to!string(option);
        if (s != "unspecified")
            result ~= s ~ "|";
    }
    result = result[0 .. $ - 1] ~ ")";
    return result;
}

private void printHelp()
{
    writeln(`dfmt `, VERSION, `
https://github.com/Hackerpilot/dfmt

Options:
    --help, -h          Print this help message
    --inplace, -i       Edit files in place
    --config_dir, -c    Path to directory to load .editorconfig file from.
    --version           Print the version number and then exit

Formatting Options:
    --align_switch_statements
    --brace_style               `, optionsToString!(typeof(Config.dfmt_brace_style))(),
            `
    --end_of_line               `, optionsToString!(typeof(Config.end_of_line))(), `
    --indent_size
    --indent_style, -t          `,
            optionsToString!(typeof(Config.indent_style))(), `
    --soft_max_line_length
    --max_line_length
    --outdent_attributes
    --space_after_cast
    --selective_import_space
    --split_operator_at_line_end
    --compact_labeled_statements
    --template_constraint_style
        `,
            optionsToString!(typeof(Config.dfmt_template_constraint_style))());
}

private string createFilePath(bool readFromStdin, string fileName)
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
