# dfmt [![Build Status](https://travis-ci.org/Hackerpilot/dfmt.svg)](https://travis-ci.org/Hackerpilot/dfmt)
**dfmt** is a formatter for D source code

## Status
**dfmt** is alpha-quality. Make backups of your files or use source control.


## Building
### Using Make
* Clone the repository
* Run ```git submodule update --init``` in the dfmt directory
* To compile with DMD, run ```make``` in the dfmt directory. To compile with
  LDC, run ```make ldc``` instead. The generated binary will be placed in ```dfmt/bin/```.


## Using
By default, dfmt reads its input from **stdin** and writes to **stdout**.
If a file name is specified on the command line, input will be read from the
file instead, and output will be written to **stdout**.
### Options
* **--help**: Display command line options
* **--inplace**: A file name is required and the file will be edited in-place.
* **--align_switch_statements**: See **dfmt_align_switch_statements** below
* **--brace_style**: See ``brace_style** below
* **--end_of_line**: See **end_of_line** below
* **--indent_size**: See **indent_size** below
* **--indent_style**: See **indent_style** below
* **--max_line_length**: See **max_line_length** below
* **--soft_max_line_length**: See **dfmt_soft_max_line_length** below
* **--outdent_attributes**: See **dfmt_outdent_attributes** below
* **--outdent_labels**: See **dfmt_outdent_labels** below
* **--space_after_cast**: See **dfmt_space_after_cast** below
* **--split_operator_at_line_end**: See **dfmt_split_operator_at_line_end** below
* **--tab_width**: See **tab_width** below

### Example
```dfmt --inplace --space_after_cast=false --max_line_length=80 --soft_max_line_length=70 file.d```

## Configuration
**dfmt** uses [EditorConfig](http://editorconfig.org/) configuration files.
**dfmt**-specific properties are prefixed with *dfmt_*.
### Standard EditorConfig properties
Property Name | Allowed Values | Default Value | Description
--------------|----------------|---------------|------------
end_of_line | **cr**, **crlf** and **lf** | **lf** | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#end_of_line)
insert_final_newline | | **true** | Not supported. **dfmt** always inserts a final newline.
charset | | **UTf-8** | Not supported. **dfmt** only works correctly on UTF-8.
indent_style | **tab**, **space** | **space** | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#indent_style)
indent_size | positive integers | **4** | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#indent_size)
tab_width | positive integers | **8** | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#tab_width)
trim_trailing_whitespace | | **true** | Not supported. **dfmt** does not emit trailing whitespace.
max_line_length | positive integers | **120** | [See EditorConfig documentation.](https://github.com/editorconfig/editorconfig/wiki/EditorConfig-Properties#max_line_length)
### dfmt-specific properties
Property Name | Allowed Values | Default Value | Description
--------------|----------------|---------------|------------
dfmt_brace_style | **allman**, **otbs**, or **stroustrup** | **allman** | [See Wikipedia](https://en.wikipedia.org/wiki/Brace_style)
dfmt_soft_max_line_length | positive integers | **80** | The formatting process will usually keep lines below this length, but they may be up to max_line_length columns long.
dfmt_outdent_labels (Not yet implemented) | **true**, **false** | **true** | Decrease the indentation of labels
dfmt_align_switch_statements (Not yet implemented) | **true**, **false** | **true** | Align labels, cases, and defaults with their enclosing switch
dfmt_outdent_attributes (Not yet implemented) | **true**, **false** | **true** | Decrease the indentation level of attributes
dfmt_split_operator_at_line_end (Not yet implemented) | **true**, **false** | **false** | Place operators on the end of the previous line when splitting lines
dfmt_space_after_cast | **true**, **false** | **false** | Insert space after the closing paren of a **cast** expression
dfmt_space_after_keywords (Not yet implemented) | **true**, **false** | **true** | Insert space after **if**, **while**, **foreach**, etc, and before the **(**

## Terminology
* Braces - `{` and `}`
* Brackets - `[` and `]`
* Parenthesis / Parens  - `(` and `)`
