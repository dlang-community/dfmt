void temp(int v1, int v2)
{
}

int f(int i)
{
    return i;
}

struct S
{
    int i;
    int j;
}

void main()
{
    temp(v1: 1, v2: 2);
    temp(
        v1: 1,
        v2: 2,
    );

    auto s = S(5, j: 3);

    temp(v1: 1, v2: f(i: 2));

    temp(v1: true ? i : false ? 2 : f(i: 3), v2: 4);

    temp(v1: () { S s = S(i: 5); return s.i; }, v2: 1);
}

void g()
{
    tmp(namedArg1: "abc abc abc abc abc abc abc abc abc abc abc abc abc abc",
namedArg2: "abc abc abc abc abc abc abc abc abc abc abc abc abc abc abc",
namedArg3: "abc abc abc abc abc abc abc abc abc abc abc abc abc abc abc");
}
