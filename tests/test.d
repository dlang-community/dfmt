#!/usr/bin/env rdmd
/**
Platform independent port of `test.sh`. Runs the tests in this directory.

Ignores differences in line endings, unless the test uses `--end_of_line`.
**/
import std.algorithm, std.array, std.conv, std.file, std.path, std.process;
import std.stdio, std.string, std.typecons, std.range, std.uni;

version (Windows)
    enum dfmt = `..\bin\dfmt.exe`;
else
    enum dfmt = `../bin/dfmt`;

int main()
{
    foreach (braceStyle; ["allman", "otbs", "knr"])
        foreach (entry; dirEntries(".", "*.d", SpanMode.shallow).filter!(e => e.baseName(".d") != "test"))
        {
            const source = entry.baseName;
            const outFileName = buildPath(braceStyle, source ~ ".out");
            const refFileName = buildPath(braceStyle, source ~ ".ref");
            const argsFile = source.stripExtension ~ ".args";
            const dfmtCommand = 
                [dfmt, "--brace_style=" ~ braceStyle] ~ 
                (argsFile.exists ? readText(argsFile).split : []) ~
                [source];
            writeln(dfmtCommand.join(" "));
            if (const result = spawnProcess(dfmtCommand, stdin, File(outFileName, "w")).wait)
                return result;

            // As long as dfmt defaults to LF line endings (issue #552), we'll have to default to ignore
            // the line endings in our verification with the reference.
            const keepTerminator = dfmtCommand.any!(a => a.canFind("--end_of_line")).to!(Flag!"keepTerminator");
            const outText = outFileName.readText;
            const refText = refFileName.readText;
            const outLines = outText.splitLines(keepTerminator);
            const refLines = refText.splitLines(keepTerminator);
            foreach (i; 0 .. min(refLines.length, outLines.length))
                if (outLines[i] != refLines[i])
                {
                    writeln("Found difference between ", outFileName, " and ", refFileName, " on line ", i + 1, ":");
                    writefln("out: %(%s%)", [outLines[i]]); // Wrapping in array shows line endings.
                    writefln("ref: %(%s%)", [refLines[i]]);
                    return 1;
                }
            if (outLines.length < refLines.length)
            {
                writeln("Line ", outLines.length + 1, " in ", refFileName, " not found in ", outFileName, ":");
                writefln("%(%s%)", [refLines[outLines.length]]);
                return 1;
            }
            if (outLines.length > refLines.length)
            {
                writeln("Line ", outLines.length + 1, " in ", outFileName, " not present in ", refFileName, ":");
                writefln("%(%s%)", [outLines[refLines.length]]);
                return 1;
            }

            // As long as dfmt defaults to LF line endings (issue #552) we need an explicit trailing newline check.
            // because a) splitLines gives the same number of lines regardless whether the last line ends with a newline,
            // and b) when line endings are ignored the trailing endline is of course also ignored.
            if (outText.endsWithNewline)
            {
                if (!refText.endsWithNewline)
                {
                    writeln(outFileName, " ends with a newline, but ", refFileName, " does not.");
                    return 1;
                }
            }
            else
            {
                if (refText.endsWithNewline)
                {
                    writeln(refFileName, " ends with a newline, but ", outFileName, " does not.");
                    return 1;
                }
            }
        }

    foreach (entry; dirEntries("expected_failures", "*.d", SpanMode.shallow))
        if (execute([dfmt, entry]).status == 0)
        {
            stderr.writeln("Expected failure on test ", entry, " but passed.");
            return 1;
        }

    writeln("All tests succeeded.");
    return 0;
}

bool endsWithNewline(string text) pure
{
    // Same criteria as https://dlang.org/phobos/std_string.html#.lineSplitter
    return
        text.endsWith('\n') ||
        text.endsWith('\r') ||
        text.endsWith(lineSep) ||
        text.endsWith(paraSep) ||
        text.endsWith('\u0085') ||
        text.endsWith('\v') ||
        text.endsWith('\f');
}
