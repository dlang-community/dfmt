@echo off
setlocal enabledelayedexpansion

set DFLAGS=-g
set CORE=
set STD=
set STDD=

for %%x in (src\*.d) do set CORE=!CORE! %%x
for %%x in (libdparse\src\std\*.d) do set STD=!STD! %%x
for %%x in (libdparse\src\std\d\*.d) do set STDD=!STDD! %%x

@echo on
dmd %CORE% %STD% %STDD% %DFLAGS% -ofbin\dfmt.exe

