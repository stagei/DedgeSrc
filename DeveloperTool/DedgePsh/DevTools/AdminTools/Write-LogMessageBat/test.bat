@echo off
echo =================================
echo Testing Write-LogMessageBat.bat
echo =================================

rem Set test log file
set "TESTLOG=%TEMP%\test-log.txt"

rem Clean up any existing test log
if exist "%TESTLOG%" del "%TESTLOG%"

echo.
echo Testing basic message logging...
call "%~dp0Write-LogMessageBat.bat" "This is a test INFO message"
call "%~dp0Write-LogMessageBat.bat" "This is a test WARNING message" WARNING
call "%~dp0Write-LogMessageBat.bat" "This is a test ERROR message" ERROR
call "%~dp0Write-LogMessageBat.bat" "This is a test SUCCESS message" SUCCESS
call "%~dp0Write-LogMessageBat.bat" "This is a test DEBUG message" DEBUG

echo.
echo Testing file logging...
call "%~dp0Write-LogMessageBat.bat" "This message goes to file" INFO "%TESTLOG%"
call "%~dp0Write-LogMessageBat.bat" "Another file message" WARNING "%TESTLOG%"

echo.
echo Testing options...
call "%~dp0Write-LogMessageBat.bat" "Message without timestamp" INFO "%TESTLOG%" NOTIMESTAMP
call "%~dp0Write-LogMessageBat.bat" "Message only to file" INFO "%TESTLOG%" NOCONSOLE

echo.
echo =================================
echo Test log file contents:
echo =================================
if exist "%TESTLOG%" (
    type "%TESTLOG%"
) else (
    echo No log file found!
)

echo.
echo =================================
echo Test completed!
echo =================================

pause

