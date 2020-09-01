deprecated("foo")
void test()
{
}

package(foo)
void bar()
{
}

@uda()
void baz()
{
}

deprecated
deprecated_()
{
}

@uda
void uda_()
{
}

@property
void property()
{
}

deprecated("Reason") @uda
void propertyuda()
{
}

deprecated("Reason")
@uda
void udaproperty()
{
}
