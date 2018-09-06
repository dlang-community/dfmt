@echo off
setlocal enabledelayedexpansion

IF "%DC%"=="" SET DC="dmd"

set DFLAGS=-g
set CORE=
set STD=
set STDD=
set STDXALLOCATOR=
set STDXALLOCATORBLOCKS=
set OBIN=bin\dfmt

:: git might not be installed, so we provide 0.0.0 as a fallback or use
:: the existing githash file if existent
if not exist "bin" mkdir bin
git describe --tags > bin\githash_.txt
for /f %%i in ("bin\githash_.txt") do set githashsize=%%~zi
if %githashsize% == 0 (
	if not exist "bin\githash.txt" (
		echo v0.0.0 > bin\githash.txt
	)
) else (
	move /y bin\githash_.txt bin\githash.txt
)


for %%x in (src\dfmt\*.d) do set CORE=!CORE! %%x
for %%x in (libdparse\src\std\experimental\*.d) do set STD=!STD! %%x
for %%x in (libdparse\src\dparse\*.d) do set STDD=!STDD! %%x
for %%x in (stdx-allocator\source\stdx\allocator\*.d) do set STDXALLOCATOR=!STDXALLOCATOR! %%x
for %%x in (stdx-allocator\source\stdx\allocator\building_blocks\*.d) do set STDXALLOCATORBLOCKS=!STDXALLOCATORBLOCKS! %%x

@echo on
%DC% %CORE% %STD% %STDD% %STDE% %STDXALLOCATOR% %STDXALLOCATORBLOCKS% -I"stdx-allocator\source" -I"libdparse\src" -Jbin %DFLAGS% -of%OBIN%.exe

if exist %OBIN%.obj del %OBIN%.obj
