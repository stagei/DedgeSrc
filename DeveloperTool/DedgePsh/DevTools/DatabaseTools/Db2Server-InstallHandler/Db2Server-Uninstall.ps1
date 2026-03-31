$ErrorActionPreference = 'Stop'
Import-Module Infrastructure -Force
# Get-GroupMembers -GroupName "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full"
# Get-GroupMembers -GroupName "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere"

# Run DB2 uninstaller
if ( Test-Path "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Community_Edition\SERVER_DEC\image\db2unins.bat") {
    cmd.exe /c "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Community_Edition\SERVER_DEC\image\db2unins.bat -f"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "DB2 uninstaller failed with exit code $LASTEXITCODE"
        exit 1
    }
}
elseif ( Test-Path "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition\SERVER_DEC\image\db2unins.bat") {

    cmd.exe /c "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition\SERVER_DEC\image\db2unins.bat -f"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "DB2 uninstaller failed with exit code $LASTEXITCODE"
        exit 1
    }
}
else {
    Write-Host "DB2 uninstaller not found"
    exit 1
}

Write-LogMessage "Removing existing database and all files" -Level INFO
$foldersToRemove = @("Db2", "Db2logs", "Db2Tablespaces", "TblSpace", "Db2Logtarget", "DbInst", "Db2RestLogs", "Db2MirrorLogs", "Db2PrimaryLogs", "ProgramData\IBM\DB2", "Program Files\IBM\DB2", "Program Files (x86)\IBM\DB2")

$validDrives = Find-ValidDrives -SkipSystemDrive $false

do {
    $foldersFound = $false
    foreach ($folder in $foldersToRemove) {
        foreach ($drive in $validDrives) {
            $path = "$($drive):\$folder"
            if (Test-Path $path -PathType Container) {
                Write-LogMessage "Removing folder: $path" -Level INFO

                cmd.exe /c "RD.EXE /S /Q $path >nul 2>&1"
                $foldersFound = $true
            }
        }
    }
} while ($foldersFound)

$restart = Read-Host "Do you want to restart the system now? (y/n)"
if ($restart -eq 'y' -or $restart -eq 'Y') {
    Write-Host "Restarting system in 5 seconds"
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}
else {
    Write-Host "System restart skipped. Please restart manually when convenient."
}

