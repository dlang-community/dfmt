//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.config;

/// The only good brace styles
enum BraceStyle
{
    allman,
    otbs
}

/// Configuration options for formatting
struct FormatterConfig
{
    /// Number of spaces used for indentation
    uint indentSize = 4;
    /// Use tabs or spaces
    bool useTabs = false;
    /// Size of a tab character
    uint tabSize = 4;
    /// Soft line wrap limit
    uint columnSoftLimit = 80;
    /// Hard line wrap limit
    uint columnHardLimit = 120;
    /// Use the One True Brace Style
    BraceStyle braceStyle = BraceStyle.allman;
}
