//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.formatter;

import dmd.tokens;
import dmd.parse;
import dmd.id;
import dmd.errorsink;
import dmd.identifier;
import dmd.astcodegen;
import dmd.transitivevisitor;
import dmd.permissivevisitor;
import dmd.frontend;
import dfmt.ast;
import dfmt.config;
import std.array;
import std.algorithm.comparison : among, max;
import std.stdio : File;

/**
 * Formats the code contained in `buffer` into `output`.
 * Params:
 *     source_desc = A description of where `buffer` came from. Usually a file name.
 *     buffer = The raw source code.
 *     output = The output range that will have the formatted code written to it.
 *     formatterConfig = Formatter configuration.
 * Returns: `true` if the formatting succeeded, `false` if any error
 */
bool format(string source_desc, ubyte[] buffer, File.LockingTextWriter output,
    Config* formatterConfig)
{
    initDMD();
    auto module_ = parseModule(source_desc);
    scope v = new FormatVisitor(output, formatterConfig);
    v.visit(module_[0]);

    return true;
}
