@echo off
rem Setup Visual COBOL Environment
rem Create shorcut as this: C:\Windows\System32\cmd.exe /c start /min "" "%VCPATH%\cfg\VcRunWin.bat" GMSTART DB2DEV
set BIN_FOLDER="C:\Program Files (x86)\Micro Focus\Visual COBOL\bin"
set LIB_FOLDER ="C:\Program Files (x86)\Micro Focus\Visual COBOL\lib"
set COBDIR="C:\Program Files (x86)\Micro Focus\Visual COBOL\"
set COBCPY="%VCPATH%\src\cbl\cpy;%VCPATH%\src\cbl\cpy\sys\cpy;%VCPATH%\src\cbl;"
set COBPATH="%VCPATH%\int;%VCPATH%\gs;%VCPATH%\src\cbl;"
set PATH=%PATH%;%BIN_FOLDER%
set MFVSSW="/c /f"
set PATH=%PATH%;%BIN_FOLDER%
set MFVSSW="/c /f"
set LIB =%LIB_FOLDER%
set COBDIR=%COBDIR%;%COBPATH%
set COBMODE="32"
start /SEPARATE /B /min "" %BIN_FOLDER%\runw.exe %1 %2 %3 %4
exit

