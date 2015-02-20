# dfmt
**dfmt** is a formatter for D source code

[![Build Status](https://travis-ci.org/Hackerpilot/dfmt.svg)](https://travis-ci.org/Hackerpilot/dfmt)

## Status
**dfmt** is alpha-quality. Make backups of your files or use source control.


## Building
### Using Make
* Clone the repository
* Run ```git submodule update --init``` in the dfmt directory
* To compile with DMD, run ```make``` in the dfmt directory. To compile with
  LDC, run ```make ldc``` instead. The generated binary will be placed in ```dfmt/bin/```.


## Using
By default, dfmt reads its input from ```stdin``` and writes to ```stdout```.
If a file name is specified on the command line, input will be read from the
file instead, and output will be written to ```stdout```.
### Options
* ```--inplace```: a file name is required and the file will be edited in-place.
* ```--braces=otbs```: Use ["The One True Brace Style"](https://en.wikipedia.org/wiki/Indent_style#Variant:_1TBS), placing open braces on
  the same line as the previous token.
* ```--braces=allman```: Use ["Allman Style"](https://en.wikipedia.org/wiki/Indent_style#Allman_style),
  placing opening braces on their own line. This is the default
* ```--tabs```: Use tabs for indentation instead of spaces
