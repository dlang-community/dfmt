# dfmt [![Build Status](https://travis-ci.org/dlang-community/dfmt.svg?branch=master)](https://travis-ci.org/dlang-community/dfmt)
**dfmt** is a formatter for D source code

## Status
**dfmt** is beta quality. Make backups of your files or use source control
when using the **--inplace** option.

## Building
### Using Make
* Clone the repository
* Run ```git submodule update --init --recursive``` in the dfmt directory
* To compile with DMD, run ```make``` in the dfmt directory. To compile with
  LDC, run ```make ldc``` instead. The generated binary will be placed in ```dfmt/bin/```.

### Installing with DUB

```sh
> dub fetch --version='~master' dfmt && dub run dfmt -- -h
```

## Using
By default, dfmt reads its input from **stdin** and writes to **stdout**.
If a file name is specified on the command line, input will be read from the
file instead, and output will be written to **stdout**.

**dfmt** uses EditorConfig files for configuration. If you run **dfmt** on a
source file it will look for .editorconfig files that apply to that source file.
If no file is specified on the command line, **dfmt** will look for .editorconfig
files that would apply to a D file in the current working directory. Command
line options can be used instead of .editorconfig files, or to override options
found in .editorconfig files.

### Options
* **--help | -h**: Display command line options
* **--inplace | -i**: A file name is required and the file will be edited in-place.
* **--align_switch_statements**: See **dfmt_align_switch_statements** below
* **--brace_style**: See **brace_style** below
* **--end_of_line**: See **end_of_line** below
* **--indent_size**: See **indent_size** below
* **--indent_style | -t**: See **indent_style** below
* **--max_line_length**: See **max_line_length** below
* **--soft_max_line_length**: See **dfmt_soft_max_line_length** below
* **--outdent_attributes**: See **dfmt_outdent_attributes** below
* **--space_after_cast**: See **dfmt_space_after_cast** below
* **--space_before_function_parameters**: See **dfmt_space_before_function_parameters** below
* **--split_operator_at_line_end**: See **dfmt_split_operator_at_line_end** below
* **--tab_width**: See **tab_width** below
* **--selective_import_space**: See **dfmt_selective_import_space** below
* **--compact_labeled_statements**: See **dfmt_compact_labeled_statements** below
* **--template_constraint_style**: See **dfmt_template_constraint_style** below

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
Property Name | Allowed Values | Default Value | Description
--------------|----------------|---------------|------------
end_of_line | `cr`, `crlf` and `lf` | `lf` | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#end_of_line)
insert_final_newline | | `true` | Not supported. `dfmt` always inserts a final newline.
charset | | `UTF-8` | Not supported. `dfmt` only works correctly on UTF-8.
indent_style | `tab`, `space` | `space` | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#indent_style)
indent_size | positive integers | `4` | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#indent_size)
tab_width | positive integers | `4` | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#tab_width)
trim_trailing_whitespace | | `true` | Not supported. `dfmt` does not emit trailing whitespace.
max_line_length | positive integers | `120` | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#max_line_length)
### dfmt-specific properties
Property Name | Allowed Values | Default Value | Description
--------------|----------------|---------------|------------
dfmt_brace_style | `allman`, `otbs`, or `stroustrup` | `allman` | [See Wikipedia](https://en.wikipedia.org/wiki/Brace_style)
dfmt_soft_max_line_length | positive integers | `80` | The formatting process will usually keep lines below this length, but they may be up to max_line_length columns long.
dfmt_align_switch_statements (Not yet implemented) | `true`, `false` | `true` | Align labels, cases, and defaults with their enclosing switch.
dfmt_outdent_attributes (Not yet implemented) | `true`, `false` | `true` | Decrease the indentation level of attributes.
dfmt_split_operator_at_line_end | `true`, `false` | `false` | Place operators on the end of the previous line when splitting lines.
dfmt_space_after_cast | `true`, `false` | `true` | Insert space after the closing paren of a `cast` expression.
dfmt_space_after_keywords (Not yet implemented) | `true`, `false` | `true` | Insert space after `if`, `while`, `foreach`, etc, and before the `(`.
dfmt_space_before_function_parameters | `true`, `false` | `false` | Insert space before the opening paren of a function parameter list.
dfmt_selective_import_space | `true`, `false` | `true` | Insert space after the module name and before the `:` for selective imports.
dfmt_compact_labeled_statements | `true`, `false` | `true` | Place labels on the same line as the labeled `switch`, `for`, `foreach`, or `while` statement.
dfmt_template_constraint_style | `conditional_newline_indent` `conditional_newline` `always_newline` `always_newline_indent` | `conditional_newline_indent` | Control the formatting of template constraints.

## Terminology
* Braces - `{` and `}`
* Brackets - `[` and `]`
* Parenthesis / Parens  - `(` and `)`
