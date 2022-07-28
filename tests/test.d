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

            const outText = outFileName.readText;
            const refText = refFileName.readText;
            const outLines = outText.splitLines(Yes.keepTerminator);
            const refLines = refText.splitLines(Yes.keepTerminator);
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
