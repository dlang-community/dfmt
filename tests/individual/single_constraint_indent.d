module single_constraint_indent;

private string dfmt_name;

static this()
{
    import std.path : dirName;
    dfmt_name = __FILE_FULL_PATH__.dirName ~ "/../../bin/dfmt";
}

private immutable input1 = q{
void foo()() if (dogs && pigs && birds && ants && foxes && flies && cats && bugs && bees && cows && sheeps && monkeys && whales)
{}};
private immutable expected1 = q{
void foo()()
    if (dogs && pigs && birds && ants && foxes && flies && cats && bugs && bees
        && cows && sheeps && monkeys && whales)
{
}};
private immutable input2 = q{
void foo()() if (dogs && pigs && birds)
{}};
private immutable expected21 = q{
void foo()() if (dogs && pigs && birds)
{
}};
private immutable expected22 = q{
void foo()()
    if (dogs && pigs && birds)
{
}};

private void test(string input, string expected, string[] dfmt_args)
{
    import std.array : array, join;
    import std.conv : to;
    import std.process : ProcessPipes, pipeProcess, wait;
    import std.stdio : stderr;

    ProcessPipes pp = pipeProcess(([dfmt_name] ~ dfmt_args));
    pp.stdin.write(input);
    pp.stdin.close;
    const r = wait(pp.pid);
    const e = pp.stderr.byLineCopy.array.join("\n");
    if (r == 0)
    {
        assert(e.length == 0, "unexpected stderr content: \n" ~ e);
        const auto formatted_output = "\n" ~ pp.stdout.byLineCopy.array.join("\n");
        assert(formatted_output == expected, formatted_output);
    }
    else assert(false, "abnormal dfmt termination : " ~ to!string(r) ~ "\n" ~ e);
}

void main()
{
    input1.test(expected1, [
        "--template_constraint_style=always_newline_indent",
        "--single_template_constraint_indent=true",
    ]);
    input1.test(expected1, [
        "--template_constraint_style=conditional_newline_indent",
        "--single_template_constraint_indent=true",
    ]);
    input2.test(expected21, [
        "--template_constraint_style=conditional_newline_indent",
        "--single_template_constraint_indent=true",
    ]);
    input2.test(expected22, [
        "--template_constraint_style=always_newline_indent",
        "--single_template_constraint_indent=true",
    ]);
}

