//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.config;

/// Brace styles
enum BraceStyle
{
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Allman_style)
    allman,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Variant:_1TBS)
    otbs,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Variant:_Stroustrup)
    stroustrup
}

/// Newline styles
enum Newlines
{
    /// Old Mac
    cr,
    /// UNIX, Linux, BSD, New Mac, iOS, Android, etc...
    lf,
    /// Windows
    crlf
}

template getHelp(alias S)
{
    enum getHelp = __traits(getAttributes, S)[0].text;
}

/// Configuration options for formatting
struct Config
{
    ///
    @Help("Number of spaces used for indentation")
    uint indentSize = 4;

    ///
    @Help("Use tabs or spaces")
    bool useTabs = false;

    ///
    @Help("Size of a tab character")
    uint tabSize = 4;

    ///
    @Help("Soft line wrap limit")
    uint columnSoftLimit = 80;

    ///
    @Help("Hard line wrap limit")
    uint columnHardLimit = 120;

    ///
    @Help("Brace style can be 'otbs', 'allman', or 'stroustrup'")
    BraceStyle braceStyle = BraceStyle.allman;

    ///
    @Help("Align labels, cases, and defaults with their enclosing switch")
    bool alignSwitchStatements = true;

    ///
    @Help("Decrease the indentation of labels")
    bool outdentLabels = true;

    ///
    @Help("Decrease the indentation level of attributes")
    bool outdentAttributes = true;

    ///
    @Help("Place operators on the end of the previous line when splitting lines")
    bool splitOperatorAtEnd = false;

    ///
    @Help("Insert spaces after the closing paren of a cast expression")
    bool spaceAfterCast = true;

    ///
    @Help("Newline style can be 'cr', 'lf', or 'crlf'")
    Newlines newlineType;

    /**
     * Returns:
     *     true if the configuration is valid
     */
    bool isValid()
    {
        import std.stdio : stderr;

        if (columnSoftLimit > columnHardLimit)
        {
            stderr.writeln("Column hard limit must be greater than or equal to column soft limit");
            return false;
        }
        return true;
    }
}

private struct Help
{
    string text;
}
