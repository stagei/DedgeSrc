@echo off
rem Setup Visual COBOL Environment
set BIN_FOLDER=C:\Program Files (x86)\Micro Focus\Visual COBOL\bin
set COBDIR="C:\Program Files (x86)\Micro Focus\Visual COBOL\"
set COBPATH="K:\fkavd\Dedge2\int;K:\fkavd\Dedge2\gs"
set PATH=%PATH%;%COBDIR%\bin
set MFVSSW=""
set INCLUDE=""
set COBDATA=""
set LIB =""
REM set COBDIR=%COBDIR%;%COBPATH%

ECHO "COBPATH = " %COBPATH%
ECHO "COBDIR = " %COBDIR%
ECHO "MFVSSW = " %MFVSSW%
ECHO "INCLUDE = " %INCLUDE%
ECHO "COBDATA = " %COBDATA%
ECHO "COBMODE = " %COBMODE%
ECHO "LIB = " %LIB%
ECHO "PATH = " %PATH%

"C:\Program Files (x86)\Micro Focus\Visual COBOL\bin\dswin.exe"
pause

