void f()
{
    auto t = true ? 1 : 0;
    auto a = [true ? 1: 0];
    auto aa1 = [0: true ? 1: 0];
    auto aa2 = [0: true ? (false ? 1: 2): 3];
    auto aa3 = [0: true ? false ? 1: 2: 3];
}
