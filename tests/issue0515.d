struct S
{
    ref S foo() return
    {
        return this;
    }
}
