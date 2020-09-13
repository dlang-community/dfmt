string f()
{
    return duration.total!"seconds".to!string;
}

string g()
{
    return duration.total!"seconds"().to!string;
}

string h()
{
    return duration.total!"seconds"().to!string.to!string.to!string.to!string.to!string.to!string.to!string.to!string.to!string;
}
