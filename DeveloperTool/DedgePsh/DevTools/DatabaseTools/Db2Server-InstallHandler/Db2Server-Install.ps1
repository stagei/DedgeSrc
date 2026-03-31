Import-Module SoftwareUtils -Force
Import-Module Infrastructure -Force

Install-OurPshApp -AppName "Run-Psh"

$ErrorActionPreference = 'Stop'
# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be ran with administrator privileges. Please run as a administrator."
    exit 1
}
if ($env:COMPUTERNAME.ToLower().Contains("fkmprd-db") -or $env:COMPUTERNAME.ToLower().Contains("fkmrap-db")) {
    if (Test-Path "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition\SERVER_DEC\image\setup.exe") {
        cmd.exe /c "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition\SERVER_DEC\image\setup.exe /p C:\DbInst"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "DB2 installation failed with exit code: $LASTEXITCODE"
            Install-WindowsApps -AppName "Db2 Server 12.1 Standard Edition"
            cmd.exe /c "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition\SERVER_DEC\image\setup.exe /p C:\DbInst"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "DB2 installation failed with exit code: $LASTEXITCODE"
                exit $LASTEXITCODE
            }
        }
    }
}
elseif ($env:COMPUTERNAME.ToLower().EndsWith("-db")) {
    if (Test-Path "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Community_Edition\SERVER_DEC\image\setup.exe") {
        cmd.exe /c "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Community_Edition\SERVER_DEC\image\setup.exe /p C:\DbInst"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "DB2 installation failed with exit code: $LASTEXITCODE"
            Install-WindowsApps -AppName "Db2 Server 12.1 Community Edition"
            cmd.exe /c "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Community_Edition\SERVER_DEC\image\setup.exe /p C:\DbInst"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "DB2 installation failed with exit code: $LASTEXITCODE"
                exit $LASTEXITCODE
            }
        }
    }
}
else {
    Write-Host "This is not a DB2 server"
    exit 1
}

Write-Host "DB2 installation completed successfully"
Write-Host "Restarting system in 10 seconds"
$restart = Read-Host "Press Enter to restart now or N/n to skip restart"
if ($restart -eq "N" -or $restart -eq "n") {
    Write-Host "Restart skipped by user"
    exit 0
}
Start-Sleep -Seconds 10
Write-Host "Restarting system in 10 seconds"
Restart-Computer -Force

