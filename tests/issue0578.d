void f()
{
    auto t = true ? 1 : 0;
    auto a = [true ? 1: 0];
    auto aa1 = [0: true ? 1: 0];
    auto aa2 = [0: true ? (false ? 1: 2): 3];

    auto aa3 = [0: true ? false ? 1: 2: 3];
    /+
    READ IF THIS TEST FAILS

    Bug in dparse:
    (Formatting before fix issue 578)
    int[int] aa3 = [0: true ? false ? 1: 2: 3];
                                       ^

    EXPLANATION:
    The marked colon is not is not recognized as a TernaryExpression by
    dparse:
    If you write a `writeln(ternaryExpression.colon.index)` in the overloaded
    ASTInformation visit function, which should get called once for every
    encountered ternary colon, only the second index is printed:
    override void visit(const TernaryExpression ternaryExpression) { ... }

    This bug can be ignored (formatting error is localized and should be rarely
    encountered).


    FIX:
    Should this get fixed by dparse or when the migration to dmd is completed,
    the formatting in the .ref files can be updated to the correct one and this
    comment can be removed.


    Current formatting after applying fix issue 578:
    auto aa3 = [0: true ? false ? 1: 2 : 3];
                                   ^

    Correct formatting after fix dparse:
    auto aa3 = [0: true ? false ? 1 : 2 : 3];
                                    ^
    +/
}
