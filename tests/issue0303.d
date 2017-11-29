static foreach (thing; things){pragma(msg,thing);}
static foreach_reverse (thing; things){pragma(msg,thing);}
static foreach (thing; things) pragma(msg,thing);
static foreach_reverse (thing; things) pragma(msg,thing);