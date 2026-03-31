@echo off
REM Synopsis Start
REM This script lists all instances in the current DB2 database.
REM Synopsis End
REM To echo a pipe (|) character in a batch file, use ^| (caret before pipe), e.g. echo a ^| b

call "%~dp0Db2Functions.bat" db2SetDatabaseFromInstance
echo %CURRENT_DATABASE%
set PWSH_FILE=c:\TEMPFK\Db2ListInst.ps1
del %PWSH_FILE% >nul 2>&1
echo Import-Module Db2-Handler -Force -ErrorAction Stop >> %PWSH_FILE%
echo $WorkObject = Add-WorkObjectFromParameters -InstanceName $env:DB2INSTANCE -DatabaseName $env:CURRENT_DATABASE >> %PWSH_FILE%
echo $WorkObject = Test-DatabaseGeneralSettings -WorkObject $WorkObject -GetAllDatabasesInfo >> %PWSH_FILE%
echo $WorkObject.ExistingDatabaseList ^| Format-Table -AutoSize >> %PWSH_FILE%
pwsh -File %PWSH_FILE%
goto :eof

