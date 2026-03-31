$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module SoftwareUtils -Force
try {
    $scriptName = Split-Path -Path $MyInvocation.MyCommand.Path -Leaf
    Write-LogMessage $scriptName -Level JOB_STARTED

    Write-LogMessage "Reinstalling DB2 server" -Level INFO
    $installPath = ""
    $arrayOfStandardEditionComputerNames = @("p-no1fkmprd-db", "p-no1fkmrap-db", "p-no1inlprd-db")
    $arrayOfInstallPaths = @("C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition\SERVER_DEC\image", "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Community_Edition\SERVER_DEC\image")
    foreach ($installPath in $arrayOfInstallPaths) {
        foreach ($computerName in $arrayOfStandardEditionComputerNames) {
            if ($env:COMPUTERNAME.ToLower().Contains($computerName)) {
                $installPath = $installPath
                break
            }
        }
    }
    if ($installPath -eq "") {
        $installPath = $arrayOfInstallPaths[1]
    }

    if ($installPath -eq "") {
        Write-LogMessage "Install path not found" -Level ERROR
        if ($env:COMPUTERNAME.ToLower() -in $arrayOfStandardEditionComputerNames) {
            Install-WindowsApps -AppName "Db2 Server 12.1 Standard Edition"
            $installPath = $arrayOfInstallPaths[0]
        }
        else {
            Install-WindowsApps -AppName "Db2 Server 12.1 Community Edition"
            $installPath = $arrayOfInstallPaths[1]
        }
    }

    $commandLine = "$installPath\db2unins.bat -f"
    cmd.exe /c $commandLine
    Write-LogMessage "DB2 server uninstalled successfully" -Level INFO

    Write-LogMessage "Removing existing database and all files" -Level INFO
    $foldersToRemove = @("ProgramData\IBM\DB2", "Program Files\IBM\DB2", "Program Files (x86)\IBM\DB2")
    $comboStr = @("logs", "Tablespaces", "Logtarget", "RestLogs", "MirrorLogs", "PrimaryLogs")
    $possibleInstanceNames = @("Db2Hst", "Db2", "Db2Fed", "Db2HFed")
    foreach ($instanceName in $possibleInstanceNames) {
        foreach ($comboStr in $comboStr) {
            $foldersToRemove += "$instanceName$comboStr"
        }
    }
    $foldersToRemove += "TblSpace"
    $foldersToRemove += "ProgramData\IBM\DB2"
    $foldersToRemove += "Program Files\IBM\DB2"
    $foldersToRemove += "Program Files (x86)\IBM\DB2"

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

    Write-LogMessage "Installing DB2 server using path: $installPath" -Level INFO
    $commandLine = "$installPath\setup.exe /p C:\DbInst"
    cmd.exe /c $commandLine
    Write-LogMessage "DB2 server installed successfully" -Level INFO
    Write-LogMessage "Restarting system in 5 seconds" -Level INFO
    Write-LogMessage $scriptName -Level JOB_COMPLETED
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}
catch {
    Write-LogMessage "Error reinstalling DB2 server" -Level ERROR -Exception $_
    Write-LogMessage $MyInvocation.ScriptName -Level JOB_FAILED
    exit 1
}

