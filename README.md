# dfmt [![Build Status](https://github.com/dlang-community/dfmt/actions/workflows/d.yml/badge.svg)](https://github.com/dlang-community/dfmt/actions?query=workflow%3A%22D%22)

**dfmt** is a formatter for D source code

## Status
**dfmt** is beta quality. Make backups of your files or use source control
when using the **--inplace** option.

## Installation

### Installing with DUB

```sh
> dub run dfmt -- -h
```

### Building from source using Make
* Clone the repository
* Run ```git submodule update --init --recursive``` in the dfmt directory
* To compile with DMD, run ```make``` in the dfmt directory. To compile with
  LDC, run ```make ldc``` instead. The generated binary will be placed in ```dfmt/bin/```.

### Building from source using dub
* Clone the repository
* run `dub build --build=release`, optionally with `--compiler=ldc2`

## Using
By default, dfmt reads its input from **stdin** and writes to **stdout**.
If a file name is specified on the command line, input will be read from the
file instead, and output will be written to **stdout**.

**dfmt** uses [EditorConfig](http://editorconfig.org/) files for configuration. If you run **dfmt** on a
source file it will look for *.editorconfig* files that apply to that source file.
If no file is specified on the command line, **dfmt** will look for *.editorconfig*
files that would apply to a D file in the current working directory. Command
line options can be used instead of *.editorconfig* files, or to override options
found there.

### Options
* `--help | -h`: Display command line options.
* `--inplace | -i`: A file name is required and the file will be edited in-place.
* `--align_switch_statements`: *see dfmt_align_switch_statements [below](#dfmt-specific-properties)*
* `--brace_style`: *see dfmt_brace_style [below](#dfmt-specific-properties)*
* `--compact_labeled_statements`: *see dfmt_compact_labeled_statements [below](#dfmt-specific-properties)*
* `--end_of_line`: *see end_of_line [below](#standard-editorconfig-properties)*
* `--indent_size`: *see indent_size [below](#standard-editorconfig-properties)*
* `--indent_style | -t`: *see indent_style [below](#standard-editorconfig-properties)*
* `--max_line_length`: *see max_line_length [below](#standard-editorconfig-properties)*
* `--outdent_attributes`: *see dfmt_outdent_attributes [below](#dfmt-specific-properties)*
* `--selective_import_space`: *see dfmt_selective_import_space [below](#dfmt-specific-properties)*
* `--single_template_constraint_indent`: *see dfmt_single_template_constraint_indent [below](#dfmt-specific-properties)*
* `--soft_max_line_length`: *see dfmt_soft_max_line_length [below](#dfmt-specific-properties)*
* `--space_after_cast`: *see dfmt_space_after_cast [below](#dfmt-specific-properties)*
* `--space_before_aa_colon`: *see dfmt_space_before_aa_colon [below](#dfmt-specific-properties)*
* `--space_before_named_arg_colon`: *see dfmt_space_before_named_arg_colon [below](#dfmt-specific-properties)*
* `--space_before_function_parameters`: *see dfmt_space_before_function_parameters [below](#dfmt-specific-properties)*
* `--split_operator_at_line_end`: *see dfmt_split_operator_at_line_end [below](#dfmt-specific-properties)*
* `--tab_width`: *see tab_width [below](#standard-editorconfig-properties)*
* `--template_constraint_style`: *see dfmt_template_constraint_style [below](#dfmt-specific-properties)*
* `--keep_line_breaks`: *see dfmt_keep_line_breaks [below](#dfmt-specific-properties)*
* `--single_indent`: *see dfmt_single_indent [below](#dfmt-specific-properties)*
* `--reflow_property_chains`: *see dfmt_property_chains [below](#dfmt-specific-properties)*
* `--space_after_keywords`: *see dfmt_space_after_keywords [below](#dfmt-specific-properties)*

### Example
```
dfmt --inplace --space_after_cast=false --max_line_length=80 \
    --soft_max_line_length=70 --brace_style=otbs file.d
```

## Disabling formatting
Formatting can be temporarily disabled by placing the comments ```// dfmt off```
and ```// dfmt on``` around code that you do not want formatted.

```d
void main(string[] args)
{
    bool optionOne, optionTwo, optionThree;

    // dfmt has no way of knowing that "getopt" is special, so it wraps the
    // argument list normally
    getopt(args, "optionOne", &optionOne, "optionTwo", &optionTwo, "optionThree", &optionThree);

    // dfmt off
    getopt(args,
        "optionOne", &optionOne,
        "optionTwo", &optionTwo,
        "optionThree", &optionThree);
    // dfmt on
}
```

## Configuration
**dfmt** uses [EditorConfig](http://editorconfig.org/) configuration files.
**dfmt**-specific properties are prefixed with *dfmt_*.
### Standard EditorConfig properties
Property Name | Allowed Values | Description
--------------|----------------|------------
end_of_line | `cr`, `crlf` and `lf` | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#end_of_line) When not set, `dfmt` adopts the first line ending in the input.
insert_final_newline | **`true`** | Not supported. `dfmt` always inserts a final newline.
charset | **`UTF-8`** | Not supported. `dfmt` only works correctly on UTF-8.
indent_style | `tab`, **`space`** | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#indent_style)
indent_size | positive integers (**`4`**) | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#indent_size)
tab_width | positive integers (**`4`**) | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#tab_width)
trim_trailing_whitespace | **`true`** | Not supported. `dfmt` does not emit trailing whitespace.
max_line_length | positive integers (**`120`**) | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#max_line_length)
### dfmt-specific properties
Property Name | Allowed Values | Description
--------------|----------------|------------
dfmt_brace_style | **`allman`**, `otbs`, `stroustrup` or `knr` | [See Wikipedia](https://en.wikipedia.org/wiki/Brace_style)
dfmt_soft_max_line_length | positive integers (**`80`**) | The formatting process will usually keep lines below this length, but they may be up to *max_line_length* columns long.
dfmt_align_switch_statements | **`true`**, `false` | Align labels, cases, and defaults with their enclosing switch.
dfmt_outdent_attributes (Not yet implemented) | **`true`**, `false`| Decrease the indentation level of attributes.
dfmt_split_operator_at_line_end | `true`, **`false`** | Place operators on the end of the previous line when splitting lines.
dfmt_space_after_cast | **`true`**, `false` | Insert space after the closing paren of a `cast` expression.
dfmt_space_after_keywords (Not yet implemented) | **`true`**, `false` | Insert space after `if`, `while`, `foreach`, etc, and before the `(`.
dfmt_space_before_function_parameters | `true`, **`false`** | Insert space before the opening paren of a function parameter list.
dfmt_selective_import_space | **`true`**, `false` | Insert space after the module name and before the `:` for selective imports.
dfmt_compact_labeled_statements | **`true`**, `false` | Place labels on the same line as the labeled `switch`, `for`, `foreach`, or `while` statement.
dfmt_template_constraint_style | **`conditional_newline_indent`** `conditional_newline` `always_newline` `always_newline_indent` | Control the formatting of template constraints.
dfmt_single_template_constraint_indent | `true`, **`false`** | Set if the constraints are indented by a single tab instead of two. Has only an effect if the style set to `always_newline_indent` or `conditional_newline_indent`.
dfmt_space_before_aa_colon | `true`, **`false`** | Adds a space after an associative array key before the `:` like in older dfmt versions.
dfmt_space_before_named_arg_colon | `true`, **`false`** | Adds a space after a named function argument or named struct constructor argument before the `:`.
dfmt_keep_line_breaks | `true`, **`false`** | Keep existing line breaks if these don't violate other formatting rules.
dfmt_single_indent | `true`, **`false`** | Set if the code in parens is indented by a single tab instead of two.
dfmt_reflow_property_chains | **`true`**, `false` | Recalculate the splitting of property chains into multiple lines.
dfmt_space_after_keywords | **`true`**, `false` | Insert space after keywords (if,while,foreach,for, etc.).

## Terminology
* Braces - `{` and `}`
* Brackets - `[` and `]`
* Parenthesis / Parens  - `(` and `)`
