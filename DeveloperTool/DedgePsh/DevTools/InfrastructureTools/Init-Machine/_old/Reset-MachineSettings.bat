@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This script must be run as administrator
    echo Right click and select "Run as administrator"
    pause
    exit /b 1
)

echo Removing C:\opt folder recursively...
if exist "C:\opt" (
    rmdir /s /q "C:\opt"
    if %errorLevel% equ 0 (
        echo Successfully removed C:\opt folder
    ) else (
        echo Failed to remove C:\opt folder
    )
) else (
    echo C:\opt folder does not exist
)
REM setx "PSModulePath" "C:\Users\%USERNAME%\Documents\PowerShell\Modules;c:\program files\powershell\7\Modules;C:\Program Files\WindowsPowerShell\Modules;c:\Users\%USERNAME%\.cursor\extensions\ms-vscode.powershell-2025.1.0\modules" /m
setx "PSModulePath" "C:\Users\%USERNAME%\Documents\PowerShell\Modules;c:\program files\powershell\7\Modules;C:\Program Files\WindowsPowerShell\Modules;c:\Users\%USERNAME%\.cursor\extensions\ms-vscode.powershell-2025.1.0\modules;C:\opt\src\DedgePsh\_Modules;C:\opt\DedgePshApps\CommonModules;C:\opt\DedgePshApps\_Modules" /m

echo Removing OptPath environment variable...
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v OptPath /f
if %errorLevel% equ 0 (
    echo Successfully removed OptPath environment variable
) else (
    echo Failed to remove OptPath environment variable
)

echo Removing OptUncPath environment variable...
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v OptUncPath /f
if %errorLevel% equ 0 (
    echo Successfully removed OptPath environment variable
) else (
    echo Failed to remove OptPath environment variable
)

echo DONE
exit /b 0
