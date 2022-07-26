void main()
{
    const a1 = [
        builder
            .rebuild!((x, y, z) => x + y + z)
            .rebuild!(x => x)
            .rebuild!(x => x),
    ];

    const a2 = [
        builder
            .rebuild!(x => x)
            .rebuild!(x => x)
            .rebuild!(x => x),
        builder
            .rebuild!(x => x)
            .rebuild!(x => x)
            .rebuild!(x => x),
    ]; 

    foo([
            line1,
            value_line2_bla_bla_bla.propertyCallBlaBlaBla(a, b, c)
            .propertyCallBlaBlaBla(a, b, c, d).propertyCallBlaBlaBla(a, b, c)
            .propertyCallBlaBlaBla(a, b, c).value,
            ]);
}

void foo() {
    afdsafds
        .asdf
        .flub;
}
