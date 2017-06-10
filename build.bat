@echo off
setlocal enabledelayedexpansion

IF "%DC%"=="" SET DC="dmd"

set DFLAGS=-g
set CORE=
set STD=
set STDD=
set STDE=
set OBIN=bin\dfmt

for %%x in (src\dfmt\*.d) do set CORE=!CORE! %%x
for %%x in (libdparse\src\std\experimental\*.d) do set STD=!STD! %%x
for %%x in (libdparse\src\dparse\*.d) do set STDD=!STDD! %%x
for %%x in (libdparse\experimental_allocator\src\std\experimental\allocator\*.d) do set STDE=!STDE! %%x
for %%x in (libdparse\experimental_allocator\src\std\experimental\allocator\building_blocks\*.d) do set STDE=!STDE! %%x

@echo on
%DC% %CORE% %STD% %STDD% %STDE% %DFLAGS% -of%OBIN%.exe

if exist %OBIN%.obj del %OBIN%.obj
