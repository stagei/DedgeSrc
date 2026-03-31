@echo off
echo Getting values from PowerShell function...

REM Call PowerShell function with different parameters
for /f "delims=" %%i in ('pwsh -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-Commands\PowershellToBatVariableFromFunction.ps1" time') do set "CURRENT_TIME=%%i"
for /f "delims=" %%i in ('pwsh -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-Commands\PowershellToBatVariableFromFunction.ps1" date') do set "CURRENT_DATE=%%i"
for /f "delims=" %%i in ('pwsh -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-Commands\PowershellToBatVariableFromFunction.ps1" computer') do set "COMPUTER_NAME=%%i"
for /f "delims=" %%i in ('pwsh -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-Commands\PowershellToBatVariableFromFunction.ps1" user') do set "CURRENT_USER=%%i"

echo Current time: %CURRENT_TIME%
echo Current date: %CURRENT_DATE%
echo Computer: %COMPUTER_NAME%
echo User: %CURRENT_USER%
echo.
echo Test completed!

