//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.main;

import std.string : strip;

static immutable VERSION = () {
    debug
    {
        enum DEBUG_SUFFIX = "-debug";
    }
    else
    {
        enum DEBUG_SUFFIX = "";
    }

    version (built_with_dub)
    {
        enum DFMT_VERSION = import("dubhash.txt").strip;
    }
    else
    {
        /**
         * Current build's Git commit hash
         */
        enum DFMT_VERSION = import("githash.txt").strip;
    }

    return DFMT_VERSION ~ DEBUG_SUFFIX;
} ();


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
            import std.exception : enforce;

            enforce!GetOptException(value == "true" || value == "false", "Invalid argument");
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
            case "space_before_function_parameters":
                optConfig.dfmt_space_before_function_parameters = optVal;
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
            case "single_template_constraint_indent":
                optConfig.dfmt_single_template_constraint_indent = optVal;
                break;
            case "space_before_aa_colon":
                optConfig.dfmt_space_before_aa_colon = optVal;
                break;
            case "keep_line_breaks":
                optConfig.dfmt_keep_line_breaks = optVal;
                break;
            case "single_indent":
                optConfig.dfmt_single_indent = optVal;
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
                "space_before_function_parameters", &handleBooleans,
                "split_operator_at_line_end", &handleBooleans,
                "compact_labeled_statements", &handleBooleans,
                "single_template_constraint_indent", &handleBooleans,
                "space_before_aa_colon", &handleBooleans,
                "tab_width", &optConfig.tab_width,
                "template_constraint_style", &optConfig.dfmt_template_constraint_style,
                "keep_line_breaks", &handleBooleans,
                "single_indent", &handleBooleans);
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
                import std.stdio : _O_BINARY;
                immutable fd = output.fileno;
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
            import std.file : exists, isDir;

            if (!exists(explicitConfigDir) || !isDir(explicitConfigDir))
            {
                stderr.writeln("--config|c must specify existing directory path");
                return 1;
            }
            explicitConfig = getConfigFor!Config(explicitConfigDir);
            explicitConfig.pattern = "*.d";
        }

        if (readFromStdin)
        {
            import std.file : getcwd;

            auto cwdDummyPath = buildPath(getcwd(), "dummy.d");

            Config config;
            config.initializeWithDefaults();
            if (explicitConfigDir != "")
            {
                config.merge(explicitConfig, buildPath(explicitConfigDir, "dummy.d"));
            }
            else
            {
                Config fileConfig = getConfigFor!Config(getcwd());
                fileConfig.pattern = "*.d";
                config.merge(fileConfig, cwdDummyPath);
            }
            config.merge(optConfig, cwdDummyPath);
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
            immutable bool formatSuccess = format("stdin", buffer,
                output.lockingTextWriter(), &config);
            return formatSuccess ? 0 : 1;
        }
        else
        {
            import std.file : dirEntries, isDir, SpanMode;

            if (args.length >= 2)
                inplace = true;
            int retVal;
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
                // ignore empty files
                if (f.size)
                {
                    buffer = new ubyte[](cast(size_t) f.size);
                    f.rawRead(buffer);
                    if (inplace)
                        output = File(path, "wb");
                    immutable bool formatSuccess = format(path, buffer, output.lockingTextWriter(), &config);
                    if (!formatSuccess)
                        retVal = 1;
                }
            }
            return retVal;
        }
    }
}

private version (Windows)
{
    version(CRuntime_DigitalMars)
    {
        extern(C) int setmode(int, int) nothrow @nogc;
        alias _setmode = setmode;
    }
    else version(CRuntime_Microsoft)
    {
        extern(C) int _setmode(int, int) nothrow @nogc;
    }
}

template optionsToString(E) if (is(E == enum))
{
    enum optionsToString = () {

        string result = "(";
        foreach (s; [__traits(allMembers, E)])
        {
            if (s != "unspecified")
                result ~= s ~ "|";
        }
        result = result[0 .. $ - 1] ~ ")";
        return result;
    } ();
}

private void printHelp()
{
    writeln(`dfmt `, VERSION, `
https://github.com/dlang-community/dfmt

Options:
    --help, -h          Print this help message
    --inplace, -i       Edit files in place
    --config, -c    Path to directory to load .editorconfig file from.
    --version           Print the version number and then exit

Formatting Options:
    --align_switch_statements
    --brace_style               `, optionsToString!(typeof(Config.dfmt_brace_style)),
            `
    --end_of_line               `, optionsToString!(typeof(Config.end_of_line)), `
    --indent_size
    --indent_style, -t          `,
            optionsToString!(typeof(Config.indent_style)), `
    --keep_line_breaks
    --soft_max_line_length
    --max_line_length
    --outdent_attributes
    --space_after_cast
    --space_before_function_parameters
    --selective_import_space
    --single_template_constraint_indent
    --split_operator_at_line_end
    --compact_labeled_statements
    --template_constraint_style
    --space_before_aa_colon
    --single_indent
        `,
            optionsToString!(typeof(Config.dfmt_template_constraint_style)));
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
