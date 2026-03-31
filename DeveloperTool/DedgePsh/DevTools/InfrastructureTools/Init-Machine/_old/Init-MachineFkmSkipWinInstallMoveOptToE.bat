@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This script must be run as administrator
    echo Right click and select "Run as administrator"
    pause
    exit /b 1
)
echo Verifying PowerShell installation
if not exist "C:\Program Files\PowerShell\7" (
    echo Installing PowerShell
    for /f "delims=" %%i in ('dir /b /s "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WingetApps\Microsoft.PowerShell\*.msi" 2^>nul') do (
        "%%i" /passive ADD_PATH=1 REGISTER_MANIFEST=1 ENABLE_PSREMOTING=0 ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1
        goto :found
    )
    :found
    echo PowerShell installed
    goto :continue
)
set OldOptPath=C:\opt
set OptPath=E:\opt

if exist %OldOptPath% (
    echo Moving %OldOptPath% to %OptPath%
    robocopy %OldOptPath% %OptPath% /E /MOVE /R:3 /W:5 /NP
    if %errorlevel% leq 1 (
        echo Successfully moved %OldOptPath% to %OptPath%
    ) else (
        echo Error moving %OldOptPath% to %OptPath%. Error level: %errorlevel%
    )
)
rd /s /q %OldOptPath%
setx OptPath %OptPath% /m
rem Delete user environment variable OptPath from registry
reg delete "HKCU\Environment" /v OptPath /f

set PATH %USERPROFILE%\AppData\Local\Microsoft\WindowsApps;C:\Users\t1_srv_fkmvfk_db\AppData\Local\Programs\Microsoft VS Code\bin;%USERPROFILE%\.dotnet\tools
echo PowerShell already installed
:continue
echo Starting Init-Machine.ps1
"C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\Init-Machine\Init-Machine.ps1' -InstallType Fkm -SkipWinInstall"

