# This file is a minimal dfmt sublime-integration. To install:
# - Change 'binary' if dfmt is not on the path (see below).
# - Put this file into your sublime Packages directory, e.g. on Linux:
#     ~/.config/sublime-text-2/Packages/User/dfmt-sublime.py
# - Add a key binding (only for D source files):
#     { "keys": ["ctrl+shift+c"], "command": "dfmt",
#       "context": [{ "key": "selector", "operator": "equal", "operand": "source.d" }]
#     }, 
#
# With this integration you can press the bound key and dfmt will
# format the whole file.
#
# It operates on the current, potentially unsaved buffer and does not create
# or save any files. To revert a formatting, just undo.
#
# Dfmt will try to search for a .editorconfig file starting from the current file's path. 

from __future__ import print_function
import sublime
import sublime_plugin
import subprocess

# Change this to the full path if dfmt is not on the path.
# E.g. 'E:\\tools\\bin\\dfmt' (mind the double \\ on Windows)
binary = 'dfmt'


class DfmtCommand(sublime_plugin.TextCommand):
  def run(self, edit):
    encoding = self.view.encoding()
    if encoding == 'Undefined':
      encoding = 'utf-8'
    command = [binary, '--assume_filename', str(self.view.file_name())]
    old_viewport_position = self.view.viewport_position()
    buf = self.view.substr(sublime.Region(0, self.view.size()))
    p = subprocess.Popen(command, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, stdin=subprocess.PIPE,
                         shell=True)
    output, error = p.communicate(buf.encode(encoding))
    if error:
      print(error.decode(encoding))
      return

    self.view.replace(
        edit, sublime.Region(0, self.view.size()),
        output.decode(encoding))
    self.view.sel().clear()
    # FIXME: Without the 10ms delay, the viewport sometimes jumps.
    sublime.set_timeout(lambda: self.view.set_viewport_position(
      old_viewport_position, False), 10)
