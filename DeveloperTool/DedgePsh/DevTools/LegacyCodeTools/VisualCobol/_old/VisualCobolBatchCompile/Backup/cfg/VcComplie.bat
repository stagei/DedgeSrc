@echo off
rem Setup Visual COBOL Environment
set BIN_FOLDER=C:\Program Files (x86)\Micro Focus\Visual COBOL\bin
set COBDIR="C:\Program Files (x86)\Micro Focus\Visual COBOL\"
set COBPATH="K:\fkavd\Dedge2\int;K:\fkavd\Dedge2\gs"
set PATH=%PATH%;%COBDIR%\bin
set MFVSSW="/c /f"
set INCLUDE="K:\fkavd\Dedge2\inc"
set COBDATA="K:\fkavd\Dedge2\dat"
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
ECHO "%BIN_FOLDER%\cobol.exe" %1, %2, %3, nul DIRECTIVES "K:\fkavd\Dedge2\VCdirectives.dir"
"%BIN_FOLDER%\cobol.exe" %1, %2, %3, nul DIRECTIVES "K:\fkavd\Dedge2\VCdirectives.dir"

