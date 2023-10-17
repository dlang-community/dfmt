struct S
{
    ulong x;
    ulong y;
    ulong z;
    ulong w;
}

immutable int function(int) f = (x) { return x + 1111; };

immutable S s = {
    1111111111111111111,
    1111111111111111111,
    1111111111111111111,
    1111111111111111111,};

    void main()
    {
    }
