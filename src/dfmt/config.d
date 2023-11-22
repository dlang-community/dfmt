//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.config;

import dfmt.editorconfig;

/// Brace styles
enum BraceStyle
{
    _unspecified,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Allman_style)
    allman,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Variant:_1TBS)
    otbs,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Variant:_Stroustrup)
    stroustrup,
    /// $(LINK https://en.wikipedia.org/wiki/Indentation_style#K&R_style)
    knr,
}

enum TemplateConstraintStyle
{
    _unspecified,
    conditional_newline_indent,
    conditional_newline,
    always_newline,
    always_newline_indent
}

/// Configuration options for formatting
struct Config
{
    ///
    OptionalBoolean dfmt_align_switch_statements;
    ///
    BraceStyle dfmt_brace_style;
    ///
    OptionalBoolean dfmt_outdent_attributes;
    ///
    int dfmt_soft_max_line_length = -1;
    ///
    OptionalBoolean dfmt_space_after_cast;
    ///
    OptionalBoolean dfmt_space_after_keywords;
    ///
    OptionalBoolean dfmt_space_before_function_parameters;
    ///
    OptionalBoolean dfmt_split_operator_at_line_end;
    ///
    OptionalBoolean dfmt_selective_import_space;
    ///
    OptionalBoolean dfmt_compact_labeled_statements;
    ///
    TemplateConstraintStyle dfmt_template_constraint_style;
    ///
    OptionalBoolean dfmt_single_template_constraint_indent;
    ///
    OptionalBoolean dfmt_space_before_aa_colon;
    ///
    OptionalBoolean dfmt_keep_line_breaks;
    ///
    OptionalBoolean dfmt_single_indent;
    ///
    OptionalBoolean dfmt_reflow_property_chains;
    ///
    OptionalBoolean dfmt_space_before_named_arg_colon;

    mixin StandardEditorConfigFields;

    /**
     * Initializes the standard EditorConfig properties with default values that
     * make sense for D code.
     */
    void initializeWithDefaults()
    {
        pattern = "*.d";
        end_of_line = EOL._default;
        indent_style = IndentStyle.space;
        indent_size = 4;
        tab_width = 4;
        max_line_length = 120;
        dfmt_align_switch_statements = OptionalBoolean.t;
        dfmt_brace_style = BraceStyle.allman;
        dfmt_outdent_attributes = OptionalBoolean.t;
        dfmt_soft_max_line_length = 80;
        dfmt_space_after_cast = OptionalBoolean.t;
        dfmt_space_after_keywords = OptionalBoolean.t;
        dfmt_space_before_function_parameters = OptionalBoolean.f;
        dfmt_split_operator_at_line_end = OptionalBoolean.f;
        dfmt_selective_import_space = OptionalBoolean.t;
        dfmt_compact_labeled_statements = OptionalBoolean.t;
        dfmt_template_constraint_style = TemplateConstraintStyle.conditional_newline_indent;
        dfmt_single_template_constraint_indent = OptionalBoolean.f;
        dfmt_space_before_aa_colon = OptionalBoolean.f;
        dfmt_keep_line_breaks = OptionalBoolean.f;
        dfmt_single_indent = OptionalBoolean.f;
        dfmt_reflow_property_chains = OptionalBoolean.t;
        dfmt_space_before_named_arg_colon = OptionalBoolean.f;
    }

    /**
     * Returns:
     *     true if the configuration is valid
     */
    bool isValid()
    {
        import std.stdio : stderr;

        if (dfmt_soft_max_line_length > max_line_length)
        {
            stderr.writefln("Column hard limit (%d) must be greater than or equal to column soft limit (%d)",
                max_line_length, dfmt_soft_max_line_length);
            return false;
        }
        return true;
    }
}
