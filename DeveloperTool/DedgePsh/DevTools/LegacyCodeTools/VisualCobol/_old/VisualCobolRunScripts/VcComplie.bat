@ECHO OFF
rem Setup Visual COBOL Environment
set IN_BASENAME=%1
IF "%IN_BASENAME%"=="" (
   ECHO Usage: VcCompile.bat FILENAME COBMODE
   GOTO :EOF
)
set IN_COBMODE=%2

IF "%IN_COBMODE%"=="64" (
   set COBMODE="64"
   set BIN_FOLDER="C:\Program Files (x86)\Micro Focus\Visual COBOL\bin64"
   set COBOLCOMPILECMD="C:\Program Files (x86)\Micro Focus\Visual COBOL\bin64\cobol.exe"
   set LIB ="C:\Program Files (x86)\Micro Focus\Visual COBOL\lib64"
) ELSE (
   set COBMODE="32"
   set BIN_FOLDER="C:\Program Files (x86)\Micro Focus\Visual COBOL\bin"
   set COBOLCOMPILECMD="C:\Program Files (x86)\Micro Focus\Visual COBOL\bin\cobol.exe"
   set LIB ="C:\Program Files (x86)\Micro Focus\Visual COBOL\lib"
)
set COBDIR="C:\Program Files (x86)\Micro Focus\Visual COBOL\"

set COBPATH="%VCPATH%\int;%VCPATH%\gs;%VCPATH%\src\cbl"
set COBCPY="%VCPATH%\src\cbl\cpy;%VCPATH%\src\cbl\cpy\sys\cpy;%VCPATH%\src\cbl;"
set PATH=%PATH%;%BIN_FOLDER%
set MFVSSW="/c /f"
set COBDIR=%COBDIR%;%COBPATH%

del %VCPATH%\int\%IN_BASENAME%.*
del %VCPATH%\lst\%IN_BASENAME%.lst
del %VCPATH%\bnd\%IN_BASENAME%.bnd
del %VCPATH%\dir\%IN_BASENAME%.dir

@REM Run the COBOL Compiler
ECHO int"%VCPATH%\int\%IN_BASENAME%.int"                               > "%VCPATH%\dir\%IN_BASENAME%.dir"
ECHO noobj"%VCPATH%\tmp\%IN_BASENAME%.int"                            >> "%VCPATH%\dir\%IN_BASENAME%.dir"
ECHO DIRECTIVES"%VCPATH%\cfg\VcCompilerDirectivesStd.dir"  >> "%VCPATH%\dir\%IN_BASENAME%.dir"

findstr /i "EXEC SQL" "%VCPATH%\src\cbl\%IN_BASENAME%.cbl" > nul

REM If the errorlevel is 0 (string found) then add the SQL directives
if %errorlevel% equ 0 (
   ECHO DIRECTIVES"%VCPATH%\cfg\VcCompilerDirectivesSql.dir" >> "%VCPATH%\dir\%IN_BASENAME%.dir"
)

ECHO "%BIN_FOLDER%\cobol.exe" "%VCPATH%\src\cbl\%IN_BASENAME%.cbl", "%VCPATH%\int\%IN_BASENAME%.int", "%VCPATH%\lst\%IN_BASENAME%.lst", nul DIRECTIVES "%VCPATH%\dir\%IN_BASENAME%.dir"

@REM "%BIN_FOLDER%\cobol.exe" "%VCPATH%\src\cbl\%IN_BASENAME%.cbl", "%VCPATH%\int\%IN_BASENAME%.int", "%VCPATH%\lst\%IN_BASENAME%.lst", nul DIRECTIVES "%VCPATH%\dir\%IN_BASENAME%.dir"
%COBOLCOMPILECMD% "%VCPATH%\src\cbl\%IN_BASENAME%.cbl", "%VCPATH%\int\%IN_BASENAME%.int", "%VCPATH%\lst\%IN_BASENAME%.lst", nul DIRECTIVES "%VCPATH%\dir\%IN_BASENAME%.dir"

REM Label for end of file
:EOF

