@safe nothrow
@Read
@NonNull
public
int[] func(int argument_1_1, int argument_1_2,
        int argument_2_1, int argument_2_2,
        int argument_3_1, int argument_3_2)
{
    if (true && true
            && true && true
            && true && true)
    {
    }
    else if (true && true &&
            true && true &&
            true && true)
    {
    }

    func(argument_1_1).func(argument_1_2)
        .func(argument_2_1)
        .func(argument_2_2);

    return [
        3, 5,
        5, 7,
        11, 13,
    ];
}
