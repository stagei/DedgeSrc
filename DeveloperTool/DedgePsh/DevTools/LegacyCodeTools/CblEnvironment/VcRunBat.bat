@echo off
rem Setup Visual COBOL Environment
rem Create shorcut as this: C:\Windows\System32\cmd.exe /c start /min "" "K:\fkavd\Dedge2\cfg\VcRunBat.bat" GMSTART DB2DEV
set BIN_FOLDER="C:\Program Files (x86)\Micro Focus\Visual COBOL\bin64"
set COBDIR="C:\Program Files (x86)\Micro Focus\Visual COBOL\"
set COBPATH="K:\fkavd\Dedge2\int;K:\fkavd\Dedge2\gs;K:\fkavd\Dedge2\src\cbl;"
set PATH=%PATH%;%BIN_FOLDER%
set MFVSSW="/c /f"
@REM set INCLUDE="K:\fkavd\Dedge2\inc"
@REM set COBDATA="K:\fkavd\Dedge2\dat"
set LIB ="C:\Program Files (x86)\Micro Focus\Visual COBOL\lib64"
set COBDIR=%COBDIR%;%COBPATH%

start /SEPARATE /B /min "" %BIN_FOLDER%\runw.exe %1 %2 %3 %4
exit

