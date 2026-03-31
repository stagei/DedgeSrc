@echo off
rem Setup Visual COBOL Environment
set BIN_FOLDER=C:\Program Files (x86)\Micro Focus\Visual COBOL\bin
set COBDIR="C:\Program Files (x86)\Micro Focus\Visual COBOL\"
set COBPATH="%BASEPATH%\int;%BASEPATH%\gs"
set PATH=%PATH%;%COBDIR%\bin
set MFVSSW="/c /f"
set INCLUDE="%BASEPATH%\inc"
set COBDATA="%BASEPATH%\dat"
set LIB ="C:\Program Files (x86)\Micro Focus\Visual COBOL\lib"
set COBDIR=%COBDIR%;%COBPATH%
set COBMODE=32

@REM ECHO "COBPATH = " %COBPATH%
@REM ECHO "COBDIR = " %COBDIR%
@REM ECHO "MFVSSW = " %MFVSSW%
@REM ECHO "INCLUDE = " %INCLUDE%
@REM ECHO "COBDATA = " %COBDATA%
@REM ECHO "COBMODE = " %COBMODE%
@REM ECHO "LIB = " %LIB%
@REM ECHO "PATH = " %PATH%
@REM ECHO "VAR1 = " %1
@REM ECHO "VAR2 = " %2
@REM ECHO "VAR3 = " %3

@REM Run the COBOL Compiler

set BASEPATH=K:\fkavd\Dedge2

ECHO int"%BASEPATH%\int\%1.int"                            > "%BASEPATH%\dir\%1.dir"
ECHO noobj"%BASEPATH%\tmp\%1.int"                         >> "%BASEPATH%\dir\%1.dir"
ECHO DIRECTIVES"%BASEPATH%\cfg\VcCompilerDirectivesStd.dir"  >> "%BASEPATH%\dir\%1.dir"

findstr /i "EXEC SQL" "%BASEPATH%\src\cbl\%1.cbl" > nul

REM If the errorlevel is 0 (string found) then add the SQL directives
if %errorlevel% equ 0 (
   ECHO DIRECTIVES"%BASEPATH%\cfg\VcCompilerDirectivesSql.dir" >> "%BASEPATH%\dir\%1.dir"
)

@REM ECHO visualstudio"4"                 >> "%BASEPATH%\dir\%1.dir"
@REM ECHO anim                            >> "%BASEPATH%\dir\%1.dir"
@REM ECHO cobidy"%BASEPATH%\int\"         >> "%BASEPATH%\dir\%1.dir"
@REM ECHO sourcetabstop"4"                >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(DB)                         >> "%BASEPATH%\dir\%1.dir"
@REM ECHO sourceformat"Variable"          >> "%BASEPATH%\dir\%1.dir"
@REM ECHO noquery                         >> "%BASEPATH%\dir\%1.dir"
@REM ECHO warnings"1"                     >> "%BASEPATH%\dir\%1.dir"
@REM ECHO max-error"100"                  >> "%BASEPATH%\dir\%1.dir"
@REM ECHO noquery                         >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(DB=DB2DEV)                  >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(BINDDIR=%BASEPATH%\bnd)     >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(COPY)                       >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(NOINIT)                     >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(COLLECTION=DBM)             >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(UDB-VERSION=V9)             >> "%BASEPATH%\dir\%1.dir"
@REM ECHO DB2(BIND)                       >> "%BASEPATH%\dir\%1.dir"

ECHO "%BIN_FOLDER%\cobol.exe" "%BASEPATH%\src\cbl\%1.cbl", "%BASEPATH%\int\%1.int", "%BASEPATH%\lst\%1.lst", nul DIRECTIVES "%BASEPATH%\dir\%1.dir"

"%BIN_FOLDER%\cobol.exe" "%BASEPATH%\src\cbl\%1.cbl", "%BASEPATH%\int\%1.int", "%BASEPATH%\lst\%1.lst", nul DIRECTIVES "%BASEPATH%\dir\%1.dir"

