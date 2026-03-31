<#
.SYNOPSIS
    Manages DB2 client configuration and database connections for both NTLM and Kerberos authentication, and provides DB2 command-line interface utilities for executing commands and scripts with error handling.

.DESCRIPTION
    This module provides utilities for configuring DB2 client connections, handling both NTLM and
    Kerberos authentication methods. It includes functions for testing DB2 client installations,
    creating catalog configuration files, managing database connections, and verifying authentication setups.
    Supports automated catalog file generation and connection testing.

    Additionally, this module offers low-level DB2 command-line interface functionality for executing DB2 commands,
    SQL scripts, and batch files. It includes comprehensive error detection and handling for SQL/DB error codes,
    output parsing, and process management. Supports various script types (.bat, .sql, .ps1) with automatic
    command argument generation and execution monitoring.

.EXAMPLE
    Set-Db2KerberosClientConfig -ServerHostname "server.domain.com" -ServerPort "50000" -DatabaseName "MYDB" -NodeName "NODE1" -AliasName "MYALIAS"
    # Configures DB2 client for Kerberos authentication

.EXAMPLE
    Test-DB2Client
    # Tests if DB2 client is properly installed and configured

.EXAMPLE
    Test-KerberosConfiguration
    # Verifies Kerberos setup and ticket availability

.EXAMPLE
    Invoke-Db2CommandOld -Command "db2 connect to MYDB"
    # Executes a DB2 command and returns output with error checking

.EXAMPLE
    Invoke-Db2ScriptOld -ScriptFile "C:\Scripts\setup.sql" -IgnoreErrors $false
    # Executes a SQL script file through DB2 CLI with error handling
#>
$modulesToImport = @("GlobalFunctions", "Infrastructure", "OdbcHandler")
foreach ($moduleName in $modulesToImport) {
    $loadedModule = Get-Module -Name $moduleName
    if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
        Import-Module $moduleName -Force
    }
    else {
        Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
    }
}




function Get-ScriptCommandArguments {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptFile,
        [Parameter(Mandatory = $true)]
        [string]$TempOutFile,
        [Parameter(Mandatory = $true)]
        [string]$TempErrFile,
        [Parameter(Mandatory = $false)]
        [switch]$OutputToConsole = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false
    )

    if (-not (Test-Path $ScriptFile)) {
        throw "Script file not found: $ScriptFile"
    }
    $Db2CmdPath = Get-CommandPathWithFallback -Name "db2cmd"
    if (-not (Test-Path $Db2CmdPath -PathType Leaf)) {
        throw "db2cmd not found in any of the following paths: $($arrayOfPaths -join ", ")"
    }
    $Db2ExePath = Get-CommandPathWithFallback -Name "db2"
    if (-not (Test-Path $Db2ExePath -PathType Leaf)) {
        throw "db2 not found in any of the following paths: $($arrayOfPaths -join ", ")"
    }
    $extension = [System.IO.Path]::GetExtension($ScriptFile).ToLower()
    $object = [PSCustomObject]@{
        Command   = ""
        Arguments = ""
    }
    switch ($extension) {
        ".bat" {
            if ($OutputToConsole) {
                $returnString = "-w -c `"$ScriptFile`""
            }
            else {
                $returnString = "-w -c `"$ScriptFile`" >> `"$TempOutFile`" 2>> `"$TempErrFile`""
            }
            $object.Command = $Db2CmdPath
            $object.Arguments = $returnString
            return $object
        }
        ".sql" {
            if ($OutputToConsole) {
                $returnString = "-tvf `"$ScriptFile`""
            }
            else {
                $returnString = "-tvf `"$ScriptFile`" >> `"$TempOutFile`" 2>> `"$TempErrFile`""
            }
            $object.Command = $Db2ExePath
            $object.Arguments = $returnString
            return $object
        }
        ".ps1" {
            if ($OutputToConsole) {
                $returnString = "/c pwsh.exe -File `"$ScriptFile`""
            }
            else {
                $returnString = "/c pwsh.exe -File `"$ScriptFile`" >> `"$TempOutFile`" 2>> `"$TempErrFile`""
            }
            $object.Command = $Db2CmdPath
            $object.Arguments = $returnString
            return $object
        }
        default {
            Write-LogMessage "Invalid script file type: $extension" -Level ERROR
            throw "Invalid script file type: $extension. Supported types are: .bat, .sql, .ps1"
        }
    }
}
function Test-OutputForErrors {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Output,
        [Parameter(Mandatory = $false)]
        [switch]$IgnoreErrors = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )
    $errorFound = $false
    try {
        if ($Output -isnot [string]) {
            $Output = $Output -join "`n"
        }
        elseif ($Output -is [string]) {
            $Output = $Output.Replace("`r`n", "`n")
        }
        $tempArray = $Output -split "`n"
        $outputArray = @()
        $currentLine = ""

        foreach ($line in $tempArray) {
            if ([string]::IsNullOrEmpty($line)) {
                continue
            }

            # Check if this line starts with a SQL/DB error pattern
            if ($line -match "^(SQL|DB)(\d{4,5})([NWCIE])\s+" -or $line.StartsWith($env:OptPath) -or ($line -match "^[c-zC-Z]:\s+" -and $line -match ">db2")) {
                # If we have a previous line, add it to the array
                if ($currentLine -ne "") {
                    $outputArray += $currentLine
                    $currentLine = ""
                }
                # Start a new line
                $currentLine = $line
            }
            else {
                # This line doesn't start with SQL/DB pattern, so append it to current line
                if ($currentLine -ne "") {
                    $currentLine += "`n" + $line
                }
                else {
                    # No current line, start with this line
                    $currentLine = $line
                }
            }
        }

        # Don't forget to add the last line if there is one
        if ($currentLine -ne "") {
            $outputArray += $currentLine
        }

        foreach ($line in $outputArray) {
            if ([string]::IsNullOrEmpty($line)) {
                continue
            }
            # Match SQL error codes (SQLnnnnn) and DB error codes (DBnnnnn)
            #SQL1064N
            # This block checks if the current line contains a DB2 error or warning code, e.g. SQL1064N, DB21034E, etc.
            # The regex matches codes like SQLnnnnnN, DBnnnnnE, etc. The third capture group ([NWCIE]) is the severity letter.
            # $matches[3] will be:
            #   N = Error
            #   W = Warning
            #   C = Critical
            #   E = Error
            #   I = Informational
            # The switch below maps the severity letter to a log level.
            # If you want to treat a specific code (e.g. SQL1064N) as INFO instead of ERROR, you can add a check for that code below.
            if ($line -match "(SQL|DB)(\d{4,5})([NWCIE])\s+") {
                # Example: $matches[0] = "SQL1064N", $matches[1] = "SQL", $matches[2] = "1064", $matches[3] = "N"
                # To treat SQL1064N as INFO, add a check here:

                $errorCode = $matches[0].ToString().ToUpper().Trim()
                $errorLevelRaw = $matches[3]
                $errorLevel = switch ($errorLevelRaw) {
                    "N" { "ERROR" }   # Error
                    "W" { "WARN" }    # Warning
                    "C" { "ERROR" }   # Critical
                    "E" { "ERROR" }   # Error
                    "I" { "INFO" }    # Informational
                    default { "ERROR" }
                }
                # Override error level for specific SQL codes
                $overrideErrorLevelArray = @(
                    "SQL1026N", # SQL1026N  Databasesystemet er allerede aktivt
                    "SQL1063N", # SQL1063N  Behandlingen av DB2START var vellykket
                    "SQL1064N", # SQL1064N  Behandlingen av DB2STOP var vellykket
                    "SQL1112N", # SQL1112N  Hjelperutinen Export begynner å eksportere data til filen 
                    "SQL3105N"  # SQL3105N  Funksjonen Export har eksportert "n" rader.
                )
                $sqlCode = $matches[0].ToString().ToUpper().Trim()
                if ($sqlCode -in $overrideErrorLevelArray) {
                    $errorLevel = "INFO"
                }

                if ($UseNewConfigurations) {
                    # Downgrade bind message noise from Norwegian DB2 output (e.g. "LINJE MELDINGER TIL db2_adminotm.bnd")
                    if ($line -match 'MELDINGER\s+TIL\s+\S+\.(bnd|lst)') {
                        $errorLevel = "INFO"
                    }
                    # Downgrade SQL0598W (existing index reused for primary/unique key) — expected DB2 DDL behavior
                    if ($sqlCode -eq 'SQL0598W') {
                        $errorLevel = "INFO"
                    }
                    # Downgrade SQL3107W (generic LOAD warning) — actual details are in per-table .msg files
                    if ($sqlCode -eq 'SQL3107W') {
                        $errorLevel = "INFO"
                    }
                    # SQL1116N and SQL1117N are inherent transitional states during DB2 redirected restore.
                    # The database must pass through RESTORE_PENDING and ROLL-FORWARD_PENDING before activation.
                    if ($sqlCode -eq 'SQL1116N' -or $sqlCode -eq 'SQL1117N') {
                        $errorLevel = "INFO"
                    }
                }

                # # Override error level for DB20000I
                # if ($line.Contains("DB20000I")) {
                #     $errorLevel = "INFO"
                # }

                # # If the error level is ERROR, mark that we found an error and add to error output.
                # if ($errorLevel -eq "ERROR") {
                #     $errorFound = $true
                #     $errorOutput += "$line`n"
                # }

                # Only treat as error if it's an actual error code (N or C)

                if ($errorLevel -eq "ERROR") {
                    if ($errorFound -eq $false) {
                        $errorFound = $true
                    }
                    Write-LogMessage $($line.Trim()) -Level "ERROR" -LogOriginType "Db2" -Quiet:$Quiet
                    if ($IgnoreErrors -eq $false) {
                        throw $($line.Trim())
                    }
                }
                elseif ($errorLevel -eq "WARN") {
                    Write-LogMessage $($line.Trim()) -Level "WARN" -LogOriginType "Db2" -Quiet:$Quiet
                }
                else {
                    Write-LogMessage $($line.Trim()) -Level "INFO" -LogOriginType "Db2" -Quiet:$Quiet   
                }


                Write-LogMessage "Error code: $($errorCode) / Error level raw: $($errorLevelRaw) / Error level: $($errorLevel)" -Level TRACE -Quiet:$Quiet
            }
            # Also check for SQLSTATE errors
            # elseif ($line -match "SQLSTATE=(\d{5})") {
            #     #$sqlState = $matches[1]
            #     $sqlState = $matches[1]
            #     Write-LogMessage "SQL State: $($sqlState)" -Level INFO -Quiet:$Quiet  
            #     Write-LogMessage $line -Level $(if ($errorLevel -eq "ERROR") { "ERROR" } elseif ($errorLevel -eq "WARN") { "WARN" } else { "INFO" }) -ForegroundColor $(if ($errorLevel -eq "ERROR") { "Red" } elseif ($errorLevel -eq "WARN") { "Yellow" } else { "Green" })
            #     $errorFound = $true
            # }
            else {
                if (-not [string]::IsNullOrEmpty($line)) {
                    Write-LogMessage $($line.Trim()) -Level INFO -LogOriginType "Db2" -Quiet:$Quiet
                }
            }
        }
        return $errorFound
    }
    catch {
        # Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
        if (-not $IgnoreErrors) {
            throw $_
        }
        else {
            return $errorFound
        }
    }
}
function Get-Db2CmdPath {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Db2Path = "C:\DbInst\BIN"
    )
    $Db2CmdPath = Get-CommandPathWithFallback -Name "db2cmdadmin"
    if (-not (Test-Path $Db2CmdPath -PathType Leaf)) {
        throw "db2cmd.exe not found in any of the following paths: $($arrayOfPaths -join ", ")"
    }
    return $Db2CmdPath

    # $arrayOfPaths = @()
    # $arrayOfPaths += Join-Path $Db2Path "db2cmd.exe"
    # $arrayOfPaths += Join-Path ${env:ProgramFiles} "IBM\SQLLIB\BIN" "db2cmd.exe"
    # $arrayOfPaths += Join-Path ${env:ProgramFiles(x86)} "IBM\SQLLIB\BIN" "db2cmd.exe"
    # foreach ($path in $arrayOfPaths) {
    #     if (Test-Path $path -PathType Leaf) {
    #         return $path
    #     }
    # }
    # throw "db2cmd.exe not found in any of the following paths: $($arrayOfPaths -join ", ")"
}
function Invoke-Db2CommandOld {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $false)]
        [string]$Db2Path = "C:\DbInst\BIN",
        [Parameter(Mandatory = $false)]
        [bool]$IgnoreErrors = $false,
        [Parameter(Mandatory = $false)]
        [bool]$Force = $false

    )
    $tempOutFile = [System.IO.Path]::GetTempFileName()
    $tempErrFile = [System.IO.Path]::GetTempFileName()
    $Db2CmdPath = Get-Db2CmdPath
    $CommandArguments = "/c $Command > `"$tempOutFile`" 2> `"$tempErrFile`""
    Write-LogMessage ("Executing command: $Db2CmdPath $($CommandArguments.Split(" > ")[0].Trim())") -Level INFO -ForegroundColor Green
    $process = Start-Process -FilePath $Db2CmdPath -ArgumentList $CommandArguments -WindowStyle Normal -Wait -PassThru
    #$process = Start-Process -FilePath "db2cmd.exe" -ArgumentList $CommandArguments -WindowStyle Normal -RedirectStandardOutput $tempOutFile -RedirectStandardError $tempErrFile -Wait -PassThru


    $exitCode = $process.ExitCode
    $output = Get-Content -Path $tempOutFile -Raw
    $errorFound = Test-OutputForErrors -Output $output
    # Only throw an error if we found an error code and we're not ignoring errors
    if ($errorFound -and -not $IgnoreErrors) {
        Write-LogMessage "Failed to execute DB2 command due to SQL/DB errors" -Level ERROR
        throw "Failed to execute DB2 command due to SQL/DB errors"
    }
    elseif ($exitCode -ne 0 -and -not $IgnoreErrors) {
        Write-LogMessage ("Failed to execute DB2 command with exit code $exitCode") -Level ERROR
        throw "Failed to execute DB2 command with exit code $exitCode"
    }

    return $output, $errorFound
}

function Invoke-Db2ScriptOld {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptFile,
        [Parameter(Mandatory = $false)]
        [string]$Db2Path = "C:\DbInst\BIN",
        [Parameter(Mandatory = $false)]
        [bool]$IgnoreErrors = $false,
        [Parameter(Mandatory = $false)]
        [bool]$Force = $false
    )

    $contentCommand = ""
    $batCommandList = @()
    $output = @()
    if ($ScriptFile.EndsWith(".bat") -or $ScriptFile.EndsWith(".sql")) {
        if ($ScriptFile.EndsWith(".bat")) {
            $contentCommand = Get-Content -Path $ScriptFile
            foreach ($line in $contentCommand) {
                if (-not [string]::IsNullOrEmpty($line)) {
                    $batCommandList += $line
                }
            }
        }
        elseif ($ScriptFile.EndsWith(".sql")) {
            $contentCommand = Get-Content -Path $ScriptFile
            $splitContent = $contentCommand.Split(";")
            foreach ($line in $splitContent) {
                if (-not [string]::IsNullOrEmpty($line) -and -not $line.Trim().StartsWith("--")) {
                    $line = $line.Replace("`r`n", " ").Replace("`n", " ").Replace("`r", " ")
                    while ($line -match "  ") {
                        $line = $line.Replace("  ", " ")
                    }
                    $batCommandList += "db2 $line"
                }
            }
        }
        foreach ($item in $batCommandList) {
            $resoutput, $errorFound = Invoke-Db2CommandOld -Command $item -DB2Path $Db2Path -IgnoreErrors $IgnoreErrors -Force $Force
            $output += "$resoutput`n"
        }

        if ($ScriptFile.Contains(".genrun.")) {
            $outputJoin = $output -join " "
            $splitLine = $outputJoin.Split("'")
            foreach ($item in $splitLine) {
                if ($item -match "^[C-F]:\\") {
                    if (Test-Path $item -PathType Leaf) {
                        Write-LogMessage "Generated file found: $item" -Level INFO
                        $contentCommand = Get-Content -Path $item
                        $null = Invoke-Db2ScriptOld -ScriptFile $item -Force $Force -IgnoreErrors $IgnoreErrors
                        break
                    }
                }
            }
        }
    }

    elseif ($ScriptFile.EndsWith(".ps1")) {
        $resoutput, $errorFound = Invoke-Db2CommandOld -Command "db2 -tvf `"$ScriptFile`"" -DB2Path $Db2Path -IgnoreErrors $IgnoreErrors -Force $Force
        $output += "$resoutput`n"

    }

    $resultOutput = $output -join "`n"
    return $resultOutput
}

function Get-Output {
    param (
        [Parameter(Mandatory = $true)]
        [string]$OutFile,
        [Parameter(Mandatory = $true)]
        [string]$ErrFile,
        [Parameter(Mandatory = $false)]
        [switch]$IgnoreErrors = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )
    try {
        $newStdOutput = Get-Content -Path $OutFile -Raw
        $resultErrorFound = $false
        $localErrorFound = $false
        if ($null -ne $newStdOutput -and $null -ne $global:StdOutput -and $newStdOutput -ne $global:StdOutput -and $newStdOutput.Contains([Environment]::NewLine)) {

            $newLines = $newStdOutput.Split([Environment]::NewLine) | Where-Object { $_ -and (-not $global:StdOutput -or -not $global:StdOutput.Contains($_)) }
            if ($newLines) {
                # Write-Host $newLines -ForegroundColor Gray
                $localErrorFound = Test-OutputForErrors -Output $newLines -IgnoreErrors:$IgnoreErrors -Quiet:$Quiet -UseNewConfigurations:$UseNewConfigurations
                if ($localErrorFound -eq $true -and $resultErrorFound -eq $false) {
                    $resultErrorFound = $true
                }
                $global:StdOutput = $newStdOutput
            }
        }


        $newErrorOutput = Get-Content -Path $ErrFile -Raw
        if ($null -ne $newErrorOutput -and $null -ne $global:ErrorOutput -and $newErrorOutput -ne $global:ErrorOutput -and $newErrorOutput.Contains([Environment]::NewLine)) {
            $newLines = $newErrorOutput.Split([Environment]::NewLine) | Where-Object { $_ -and (-not $global:ErrorOutput -or -not $global:ErrorOutput.Contains($_)) }
            if ($newLines) {
                # Write-Host $newLines -ForegroundColor Cyan
                $localErrorFound = Test-OutputForErrors -Output $newLines -IgnoreErrors:$IgnoreErrors -Quiet:$Quiet -UseNewConfigurations:$UseNewConfigurations
                if ($localErrorFound -eq $true -and $resultErrorFound -eq $false) {
                    $resultErrorFound = $true
                }
                $global:ErrorOutput = $newErrorOutput
            }
        }
        return $resultErrorFound
    }
    catch {
        throw $_
    }

}

function Invoke-DB2ScriptCommand {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Command,
        [Parameter(Mandatory = $false)]
        [string]$ScriptFile,
        [Parameter(Mandatory = $false)]
        [string]$Db2Path = "C:\DbInst\BIN",
        [Parameter(Mandatory = $false)]
        [switch]$IgnoreErrors = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Force = $false,
        [Parameter(Mandatory = $false)]
        [switch]$OutputToConsole = $false,
        [Parameter(Mandatory = $false)]
        [switch]$OpenOutputFiles = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )
    try {
        $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
        if (Use-OverrideAppDataFolder) {
            $appDataPath = $global:OverrideAppDataFolder
        }
        else {
            $appDataPath = Get-ApplicationDataPath
        }
        New-Item -Path $appDataPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        Write-LogMessage "Application data path: $($appDataPath)" -Level INFO -Quiet:$Quiet

        # Get base name for temp files from script file
        $baseName = "db2_script_$processId"
        try {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptFile)
        }
        catch {
            Write-LogMessage "Could not get base name for temp files from script file: $($_.Exception.Message)" -Level WARN -Exception $_
            $baseName = "db2_script_$processId"
        }

        $tempOutFile = Join-Path $($appDataPath.ToString()) "$baseName.out"
        $tempErrFile = Join-Path $($appDataPath.ToString()) "$baseName.err"

        if (Test-Path $tempOutFile -PathType Leaf) {
            Remove-Item -Path $tempOutFile -Force -ErrorAction SilentlyContinue | Out-Null
        }
        if (Test-Path $tempErrFile -PathType Leaf) {
            Remove-Item -Path $tempErrFile -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -Path $tempOutFile -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item -Path $tempErrFile -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null

        # $tempCommandFile = [System.IO.Path]::GetTempFileName()
        if ([string]::IsNullOrEmpty($ScriptFile)) {
            $Db2CmdPath = Get-CommandPathWithFallback -Name "db2cmd"
            if (-not (Test-Path $Db2CmdPath -PathType Leaf)) {
                throw "db2cmd not found in any of the following paths: $($arrayOfPaths -join ", ")"
            }

            $Executable = $Db2CmdPath
            $CommandArguments = "/c $Command >> `"$tempOutFile`" 2>> `"$tempErrFile`""
            Write-LogMessage "Executing command: $Executable $($CommandArguments.Split(" > ")[0].Trim())" -Level INFO -Quiet:$Quiet
        }
        else {

            $objResult = Get-ScriptCommandArguments -ScriptFile $ScriptFile -TempOutFile $tempOutFile -TempErrFile $tempErrFile -OutputToConsole:$OutputToConsole -Quiet:$Quiet
            $Executable = $objResult.Command
            $CommandArguments = $objResult.Arguments
            Write-LogMessage "Executing script: $Executable $($CommandArguments.Split(" > ")[0].Trim())" -Level INFO -Quiet:$Quiet
        }


        $process = Start-Process -FilePath $Executable -ArgumentList $CommandArguments -WindowStyle Minimized -PassThru
        $errorFound = $false
        $global:StdOutput = ""
        $global:ErrorOutput = ""
        $counter = 0
        while ($process.HasExited -eq $false) {
            Start-Sleep -Milliseconds 500
            if ($Quiet -eq $true) {
                Start-Sleep -Milliseconds 500
                $counter++
                if ($counter % 100 -eq 0) {
                    Write-Host "." -NoNewline
                }
            }
            $resultErrorFound = Get-Output -OutFile $tempOutFile -ErrFile $tempErrFile -Quiet:$Quiet -IgnoreErrors:$IgnoreErrors -UseNewConfigurations:$UseNewConfigurations
            if ($resultErrorFound -eq $true) {
                $errorFound = $true

            }
        }

        $process.WaitForExit()
        if ($OpenOutputFiles) {
            Start-Process -FilePath $(Get-CommandPathWithFallback -Name "code") -ArgumentList "$tempOutFile"
            Start-Process -FilePath $(Get-CommandPathWithFallback -Name "code") -ArgumentList "$tempErrFile"
        }

        # $exitCode = $process.ExitCode



        $resultErrorFound = Get-Output -OutFile $tempOutFile -ErrFile $tempErrFile -IgnoreErrors:$IgnoreErrors -Quiet:$Quiet -UseNewConfigurations:$UseNewConfigurations
        if ($resultErrorFound -and -not $IgnoreErrors) {
            throw "Error occurred during processing"
        }

        if (Test-Path $tempOutFile -PathType Leaf) {
            # Read file as bytes (PowerShell 7+ compatible)
            $outputBytes = [System.IO.File]::ReadAllBytes($tempOutFile)
            # Convert from ANSI-1252 encoding to string
            $output = [System.Text.Encoding]::GetEncoding(1252).GetString($outputBytes)
        }
        else {
            $output = ""
        }
        if (Test-Path $tempErrFile -PathType Leaf) {
            $errorOutput = Get-Content -Path $tempErrFile -Raw
        }
        else {
            $errorOutput = ""
        }
        $output = $output -join "`n" + $(if ($errorOutput) { "`n" + $errorOutput -join "`n" })

        # Only throw an error if we found an error code and we're not ignoring errors
        if ($errorFound -and -not $IgnoreErrors) {
            Write-LogMessage "Failed to execute DB2 command due to SQL/DB errors" -Level ERROR -Quiet:$Quiet    
            throw "Failed to execute DB2 command due to SQL/DB errors"
        }
        # elseif ($exitCode -ne 0 -and -not $IgnoreErrors) {
        #     Write-LogMessage "Failed to execute DB2 command with exit code $exitCode" -Level ERROR -Quiet:$Quiet
        #     throw "Failed to execute DB2 command with exit code $exitCode"
        # }

        if ($ScriptFile.Contains(".genrun.")) {
            foreach ($line in $output) {
                $splitLine = $line.Split("'")
                foreach ($item in $splitLine) {
                    if ($item -match "^[C-F]:\\") {
                        if (Test-Path $item -PathType Leaf) {
                            Write-Host "Generated file found: $item" -Quiet:$Quiet
                            #$contentCommand = Get-Content -Path $item
                            $null = Invoke-DB2ScriptCommand -ScriptFile $item -Force $Force -IgnoreErrors $IgnoreErrors
                        }
                    }
                }
            }
        }
        return $output
    }
    catch {
        # Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_ -Quiet:$Quiet
        throw $_
    }

}

function Invoke-Db2ContentAsScript {
    param(
        [Parameter(Mandatory = $true)]
        $Content,
        [Parameter(Mandatory = $false)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [ValidateSet("SQL", "BAT", "PS1")]
        [string]$ExecutionType = "SQL",
        [Parameter(Mandatory = $false)]
        [switch]$IgnoreErrors = $false,
        [Parameter(Mandatory = $false)]
        [switch]$OutputToConsole = $false,
        [Parameter(Mandatory = $false)]
        [switch]$OpenScriptFile = $false,
        [Parameter(Mandatory = $false)]
        [string]$InstanceName = "DB2",
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )
    if (-not $FileName) {
        if (Use-OverrideAppDataFolder) {
            $FileName = Join-Path $global:OverrideAppDataFolder "db2_script_$(Get-Date -Format 'yyyyMMddHHmmssfff').$($ExecutionType)"
        }
        else {
            $FileName = "$($env:TEMP)\db2_script_$($PID)_$(Get-Date -Format 'yyyyMMddHHmmssfff').$($ExecutionType)"
        }
    }
    else {
        Add-FolderForFileIfNotExists -FileName $FileName
    }
    # $Content = ConvertTo-Ansi1252 -ConvertString $Content

    # set correct extension for file
    # $scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    # $scriptExtension = [System.IO.Path]::GetExtension($FileName).ToLower()
    $oldFileName = $FileName
    $extension = $scriptExtension
    if ($extension -eq ".sql") {
        $FileName = $FileName -replace "$extension$", ".$($ExecutionType.ToLower())"
    }
    elseif ($extension -eq ".bat") {
        $FileName = $FileName -replace "$extension$", ".$($ExecutionType.ToLower())"
    }
    elseif ($extension -eq ".ps1") {
        $FileName = $FileName -replace "$extension$", ".$($ExecutionType.ToLower())"
    }
    if ($FileName -ne $oldFileName) {
        Write-LogMessage "File extension changed from $extension to $($ExecutionType.ToLower()) to make Db2 CLI use correct arguments to execute the script" -Level INFO -Quiet:$Quiet
    }



    if ($Content -is [array]) {
        $Content = $Content -join "`n"
    }
    else {
        $Content = [string] $Content
    }

    if (Test-Path $FileName -PathType Leaf) {
        Remove-Item -Path $FileName -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Write-LogMessage "Saving script file: $FileName" -Level INFO -Quiet:$Quiet

    [System.IO.File]::WriteAllText($FileName, $Content, [System.Text.Encoding]::GetEncoding(1252))


    $sqlParseSolution = "Old"
    if ($ExecutionType -eq "SQL") {
        if ($sqlParseSolution -eq "Old") {
            $BatFileName = $FileName -replace ".sql$", ".bat"

            $BatContent = @()
            if (-not [string]::IsNullOrEmpty($InstanceName)) {
                $BatContent += "set DB2INSTANCE=$($InstanceName)"
            }
            $BatContent += $(Get-CommandPathWithFallback -Name "db2.exe") + " -tvf `"$FileName`""
            $BatContent += " "
            [System.IO.File]::WriteAllText($BatFileName, $($BatContent -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
            $FileName = $BatFileName
            $ExecutionType = "BAT"
            Write-LogMessage "Created script file to execute SQL script: $BatFileName" -Level INFO -Quiet:$Quiet
        }
        else {
            # 1 read the file content
            $fileContent = Get-Content -Path $FileName -Raw
            
            # 2 Split into array of lines
            $fileContentArray = $fileContent -split "`n"

            # 3 Remove all lines that start with line.trim().startswith("--")
            $fileContentArray = $fileContentArray | Where-Object { -not $_.Trim().StartsWith("--") }

            # 4 Remove all empty lines and trim the lines
            $fileContentArray = $fileContentArray | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) }

            # 5 Join the array of lines back into a string with `n delimiter
            $fileContent = $fileContentArray -join "`n"

            # 6 Remove all new line and carriage return characters
            $fileContent = $fileContent | ForEach-Object { $_.Replace("`r`n", " ").Replace("`n", " ").Replace("`r", " ") } 

            # 7 split the content into statements delimited by ;
            $statements = $fileContent -split ';'
            
            # 8 prefix all lines with "db2 " and remove the ; at end of the line
            $BatContent = @()
            if (-not [string]::IsNullOrEmpty($InstanceName)) {
                $BatContent += "set DB2INSTANCE=$($InstanceName)"
            }
            
            foreach ($statement in $statements) {
                $cleanStatement = $statement.Trim()
                if ($cleanStatement -ne '') {
                    $BatContent += "db2 $cleanStatement"
                }
            }
            
            # 8 save the content to a new bat file
            $BatFileName = $FileName -replace ".sql$", ".bat"
            [System.IO.File]::WriteAllText($BatFileName, $($BatContent -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
            
            # 5 set the file name to the new bat file
            $FileName = $BatFileName
            
            # 6 set the execution type to BAT
            $ExecutionType = "BAT"
            Write-LogMessage "Created script file to execute SQL script: $BatFileName" -Level INFO -Quiet:$Quiet
        }
    }


    if ($OpenScriptFile) {
        Start-Process -FilePath $(Get-CommandPathWithFallback -Name "code") -ArgumentList $FileName
        Read-Host "Press Enter to continue with script execution"
    }

    try {
        $output = Invoke-DB2ScriptCommand -ScriptFile $FileName -IgnoreErrors:$IgnoreErrors -OutputToConsole:$OutputToConsole -OpenOutputFiles:$OpenScriptFile -Quiet:$Quiet -UseNewConfigurations:$UseNewConfigurations
        Write-LogMessage "Output:`n $($output -join "`n")" -Level TRACE -Quiet:$Quiet
        return $output
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_ -Quiet:$Quiet
        throw $_
    }
    finally {
        if ($Filename.Contains("$env:TEMP")) {
            Remove-Item -Path $FileName -Force -ErrorAction SilentlyContinue | Out-Null
            Write-LogMessage "Removed temporary file: $FileName" -Level INFO -Quiet:$Quiet
        }
    }

}


<#
.SYNOPSIS
    Tests if a database supports online backup by checking log archiving configuration.

.DESCRIPTION
    Queries database configuration for LOGARCHMETH1 setting. Sets WorkObject.DatabaseRecoverable
    to false if LOGARCHMETH1=OFF (no online backup support), true otherwise. Databases without
    log archiving require offline backup or must have logging enabled first.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Test-DatabaseRecoverability -WorkObject $workObject
    # Sets workObject.DatabaseRecoverable to true/false

.NOTES
    Critical for backup operations: databases with LOGARCHMETH1=OFF cannot be backed up online.
#>
function Test-DatabaseRecoverability {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $WorkObject
    )

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
    $db2Commands += "db2start"
    $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
    $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
    $db2Commands += "db2 get database configuration for $($WorkObject.DatabaseName) | findstr `"LOGARCHMETH1`""
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
    $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

    if ($output -and ( $output -match "LOGARCHMETH1\s+=\s+OFF" -or $output.Contains("(LOGARCHMETH1) = OFF"))) {
        Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseRecoverable" -NotePropertyValue $false -Force
    }
    else {
        Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseRecoverable" -NotePropertyValue $true -Force
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Displays WorkObject properties in a formatted, human-readable structure.

.DESCRIPTION
    Recursively formats and displays all properties of a WorkObject (PSCustomObject) 
    with proper indentation and nesting. Excludes properties ending with 'output' or 
    'script' to focus on configuration data. Supports arrays, hashtables, and nested objects.

.PARAMETER WorkObject
    The PSCustomObject to display. Typically contains Db2 database configuration and state information.

.PARAMETER OutputToConsoleNoReturn
    When specified, outputs directly to console without returning the WorkObject.

.EXAMPLE
    Get-WorkObjectProperties -WorkObject $workObject
    # Displays formatted properties and returns the WorkObject

.EXAMPLE
    Get-WorkObjectProperties -WorkObject $workObject -OutputToConsoleNoReturn
    # Displays formatted properties to console only, no return value
#>
function Get-WorkObjectProperties {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$OutputToConsoleNoReturn = $false
    )
    try {
        Write-LogMessage "Displaying database object to console" -Level INFO
        $formattedOutput = Format-ObjectPropertiesRecursive -Object $WorkObject -IndentLevel 0
        Write-LogMessage $formattedOutput -Level INFO
    }
    catch {
        Write-LogMessage "Error displaying database object properties" -Level ERROR -Exception $_
        # throw $_
    }
    if ($OutputToConsoleNoReturn) {
        Format-ObjectPropertiesRecursive -Object $WorkObject -IndentLevel 0 -MaxArrayItems 10
        return
    }
    else {
        return $WorkObject
    }
}

function Format-ObjectPropertiesRecursive {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $false)]
        [int]$IndentLevel = 0,
        [Parameter(Mandatory = $false)]
        [int]$MaxArrayItems = 10
    )

    $indent = "   " * $IndentLevel  # Three spaces per indent level
    $output = @()

    if ($Object -is [PSCustomObject]) {
        $properties = $Object.PSObject.Properties | Where-Object {
            $_.MemberType -eq "NoteProperty" -and -not ($_.Name -match "(output|script)$")
        }

        foreach ($property in $properties) {
            $name = $property.Name
            $value = $property.Value

            if ($null -eq $value) {
                $output += "$indent$name`: [null]"
            }
            elseif ($value -is [array]) {
                $arrayCount = $value.Count
                if ($arrayCount -eq 0) {
                    $output += "$indent$name`: [empty array]"
                }
                elseif ($arrayCount -lt $MaxArrayItems) {
                    $output += "$indent$name`: [array with $arrayCount items]"
                    for ($i = 0; $i -lt $arrayCount; $i++) {
                        $arrayItem = $value[$i]
                        if ($arrayItem -is [PSCustomObject]) {
                            $output += "$indent   [$i]:"
                            $output += Format-ObjectPropertiesRecursive -Object $arrayItem -IndentLevel ($IndentLevel + 2)
                        }
                        else {
                            $arrayItemStr = if ($arrayItem -is [string]) { $arrayItem } else { $arrayItem.ToString() }
                            $output += "$indent   [$i]: $arrayItemStr"
                        }
                    }
                }
                else {
                    $output += "$indent$name`: [array with $arrayCount items - too large to display]"
                }
            }
            elseif ($value -is [PSCustomObject]) {
                $output += "$indent$name`: [PSCustomObject]"
                $output += Format-ObjectPropertiesRecursive -Object $value -IndentLevel ($IndentLevel + 1)
            }
            elseif ($value -is [hashtable]) {
                $output += "$indent$name`: [hashtable with $($value.Count) items]"
                foreach ($key in $value.Keys) {
                    $hashValue = $value[$key]
                    if ($hashValue -is [PSCustomObject]) {
                        $output += "$indent   $key`:"
                        $output += Format-ObjectPropertiesRecursive -Object $hashValue -IndentLevel ($IndentLevel + 2)
                    }
                    else {
                        $hashValueStr = if ($hashValue -is [string]) { $hashValue } else { $hashValue.ToString() }
                        $output += "$indent   $key`: $hashValueStr"
                    }
                }
            }
            else {
                # Handle primitive types and other objects
                $valueStr = if ($value -is [string]) { $value } else { $value.ToString() }
                $output += "$indent$name`: $valueStr"
            }
        }
    }
    else {
        # Handle non-PSCustomObject types
        $objectStr = if ($Object -is [string]) { $Object } else { $Object.ToString() }
        $output += "$indent$objectStr"
    }

    return $output -join "`n"
}
<#
.SYNOPSIS
    Creates and configures standard Db2 folder structure with SMB shares.

.DESCRIPTION
    Creates or finds existing Db2 folders based on instance name:
    - RestoreFolder: For database restore files (shared)
    - DataFolder: Primary database data location
    - TablespacesFolder: Tablespace container files
    - BackupFolder: Database backup files (shared)
    - LogtargetFolder: Archived transaction logs
    - PrimaryLogsFolder: Active transaction logs
    - MirrorLogsFolder: Mirrored transaction logs (shared)
    - LoadFolder: Data load files (shared)
    
    Creates SMB shares for folders requiring network access.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName and DatabaseName.

.PARAMETER FolderName
    Specific folder to create ("All", "RestoreFolder", "BackupFolder", etc.). Default is "All".

.PARAMETER Quiet
    Suppresses informational log messages.

.PARAMETER SkipRecreateDb2Folders
    Skips SMB share creation if folders already exist.

.EXAMPLE
    $workObject = Get-Db2Folders -WorkObject $workObject
    # Creates all standard Db2 folders and shares

.EXAMPLE
    $workObject = Get-Db2Folders -WorkObject $workObject -FolderName "BackupFolder"
    # Creates only the backup folder
#>
function Get-Db2Folders {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$FolderName = "All",
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipRecreateDb2Folders = $false
    )
    try {
        Write-LogMessage "Getting Db2 folders for instance $($WorkObject.InstanceName)" -Level INFO -Quiet:$Quiet
        # Find existing folders
        $validDrives = Find-ValidDrives
        Add-Member -InputObject $WorkObject -NotePropertyName "ValidDrives" -NotePropertyValue $validDrives -Force



        $folderArray = @()
        $workInstanceName = $WorkObject.InstanceName.Replace("DB2", "Db2 ").ToTitleCase().Replace(" ", "")
        # $workInstanceName = $WorkObject.InstanceName.ToUpper().Replace("DB2HST", "Db2Hst").Replace("DB2HFED", "Db2HFed").Replace("DB2H", "Db2H").Replace("DB2", "Db2").Replace("FED", "Fed")
        if ($FolderName -eq "All" -or $FolderName -eq "RestoreFolder") {
            $folderArray += [PSCustomObject]@{
                Name        = "RestoreFolder"
                ShareName   = "$($workInstanceName)Restore"
                Description = "$($workInstanceName)Restore is a shared folder for Db2 restore files for $($WorkObject.DatabaseName)"
                Path        = $(Find-ExistingFolder -Name "$($workInstanceName)Restore" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }
        if ($FolderName -eq "All" -or $FolderName -eq "DataFolder") {
            $folderArray += [PSCustomObject]@{
                Name = "DataFolder"
                Path = $(Find-ExistingFolder -Name "$($workInstanceName)" -PreferredDrive $($(Get-PrimaryDb2DataDisk).Replace(":", "")) -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
            $folderArray += [PSCustomObject]@{
                Name = "TablespacesFolder"
                Path = $(Find-ExistingFolder -Name "$($workInstanceName)Tablespaces" -PreferredDrive $($(Get-PrimaryDb2DataDisk).Replace(":", "")) -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }
        if ($FolderName -eq "All" -or $FolderName -eq "BackupFolder") {
            $folderArray += [PSCustomObject]@{
                Name        = "BackupFolder"
                ShareName   = "$($workInstanceName)Backup"
                Description = "$($workInstanceName)Backup is a shared folder for Db2 backup files for $($WorkObject.DatabaseName)"
                Path        = $(Find-ExistingFolder -Name "$($workInstanceName)Backup" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }
        if ($FolderName -eq "All" -or $FolderName -eq "LogtargetFolder") {
            $folderArray += [PSCustomObject]@{
                Name = "LogtargetFolder"
                Path = $(Find-ExistingFolder -Name "$($workInstanceName)Logtarget" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }
        if ($FolderName -eq "All" -or $FolderName -eq "PrimaryLogsFolder") {
            $folderArray += [PSCustomObject]@{
                Name = "PrimaryLogsFolder"
                Path = $(Find-ExistingFolder -Name "$($workInstanceName)PrimaryLogs" -PreferredDrive $($(Get-PrimaryDb2DataDisk).Replace(":", "")) -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }
        if ($FolderName -eq "All" -or $FolderName -eq "MirrorLogsFolder") {
            $folderArray += [PSCustomObject]@{
                Name        = "MirrorLogsFolder"
                ShareName   = "$($workInstanceName)MirrorLogs"
                Description = "$($workInstanceName)MirrorLogs is a shared folder for Db2 mirror logs for $($WorkObject.DatabaseName)"
                Path        = $(Find-ExistingFolder -Name "$($workInstanceName)MirrorLogs" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }

        if ($FolderName -eq "All" -or $FolderName -eq "LoadFolder") {
            $folderArray += [PSCustomObject]@{
                Name        = "LoadFolder"
                ShareName   = "$($workInstanceName)Load"
                Description = "$($workInstanceName)Load is a shared folder for Db2 load files for $($WorkObject.DatabaseName)"
                Path        = $(Find-ExistingFolder -Name "$($workInstanceName)Load" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateDb2Folders)
            }
        }
        foreach ($folder in $folderArray) {
            Add-Member -InputObject $WorkObject -NotePropertyName $($folder.Name) -NotePropertyValue $folder.Path -Force
            # Add-Folder -Path $folder.Path -AdditionalAdmins $WorkObject.AdditionalAdmins -EveryonePermission "Read"|
            if ($folder.ShareName -and -not $SkipRecreateDb2Folders) {
                Write-LogMessage "Adding SMB shared folder $($folder.ShareName) with path $($folder.Path)" -Level INFO
                $null = Add-SmbSharedFolder -Path $folder.Path -ShareName $folder.ShareName -Description $folder.Description
            }
        }

        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding db2 folders" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Generates appropriate Db2 connect command based on server/client context.

.DESCRIPTION
    Returns correct connect command:
    - On client: "db2 connect to <RemoteDatabaseName>"
    - On server: "db2 connect to <DatabaseName> user <DbUser> using <DbPassword>"
    
    Uses Test-IsServer to determine context.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, RemoteDatabaseName, DbUser, and DbPassword.

.EXAMPLE
    $connectCmd = Get-ConnectCommand -WorkObject $workObject
    # Returns "db2 connect to FKMPRD" (client) or "db2 connect to FKMPRD user db2nt using ntdb2" (server)

.NOTES
    Helper function used throughout module to ensure correct connect syntax.
#>
function Get-ConnectCommand {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    if (-not (Test-IsServer)) {
        return "db2 connect to $($WorkObject.RemoteDatabaseName)"    
    }
    else {
        return "db2 connect to $($WorkObject.DatabaseName) " + $(if ($WorkObject.DbUser) { "user $($WorkObject.DbUser) using $($WorkObject.DbPassword)" } else { "" })    
    }
}

<#
.SYNOPSIS
    Generates appropriate DB2INSTANCE set command based on server/client context.

.DESCRIPTION
    Returns correct instance command:
    - On client: "echo Not running on a server, no instance name needed"
    - On server: "set DB2INSTANCE=<InstanceName>"
    
    Uses Test-IsServer to determine context.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName.

.EXAMPLE
    $instanceCmd = Get-SetInstanceNameCommand -WorkObject $workObject
    # Returns "set DB2INSTANCE=DB2" (server) or echo message (client)

.NOTES
    Helper function used throughout module for correct instance switching in batch scripts.
#>
function Get-SetInstanceNameCommand {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    if (-not (Test-IsServer)) {
        return "echo Not running on a server, no instance name needed"
    }
    else {
        return "set DB2INSTANCE=$($WorkObject.InstanceName)"
    }
}
<#
.SYNOPSIS
    Creates a new Db2 database on the primary data disk.

.DESCRIPTION
    Creates a Db2 database with standard settings:
    - AUTOMATIC STORAGE on primary Db2 data disk
    - Codeset IBM-1252, Territory NO, Pagesize 4096
    - EXTENTSIZE 4/32 for catalog/user tablespaces
    - Optionally drops existing database first if WorkObject.DropExistingDatabase is true
    
    Handles existing database warning (SQL1005N) gracefully.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, InstanceName, and DropExistingDatabase flag.

.EXAMPLE
    $workObject = Add-Db2Database -WorkObject $workObject
    # Creates database or reports if already exists

.NOTES
    Requires Db2 instance to be running. Creates folders via Get-Db2Folders after creation.
#>
function Add-Db2Database {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Creating database $($WorkObject.DatabaseName) on disk $($(Get-PrimaryDb2DataDisk)) with instance $($WorkObject.InstanceName)" -Level INFO


        if ($WorkObject.DropExistingDatabase) {
            Write-LogMessage "Dropping existing database $($WorkObject.DatabaseName)" -Level INFO
            $db2Commands = @()
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            if ($WorkObject.InstanceCreated) {
                $db2Commands += "db2stop force"
            }
            $db2Commands += "db2start"
            if ($WorkObject.DatabaseExist -eq $true) {
                $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
                $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
                $db2Commands += "db2 deactivate database $($WorkObject.DatabaseName)"
                $db2Commands += "db2 connect reset"
                $db2Commands += "db2 drop database $($WorkObject.DatabaseName) 2>nul"
            }
            $db2Commands += "db2 uncatalog database $($WorkObject.DatabaseName)"
            $db2Commands += "db2stop force"
            $db2Commands += "db2start"

            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
            $WorkObject = Get-Db2Folders -WorkObject $WorkObject -Quiet:$true
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            # $db2Commands = @()
            # $db2Commands += "db2start"
            # $null = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "Db2-CreateInitialDatabases.DropDatabaseStart.bat")" -IgnoreErrors

        }


        $createTableContent = @()
        $createTableContent += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $createTableContent += "db2 CREATE DATABASE $($WorkObject.DatabaseName) AUTOMATIC STORAGE YES ON '$($(Get-PrimaryDb2DataDisk))'  DBPATH ON '$($(Get-PrimaryDb2DataDisk))' USING CODESET IBM-1252 TERRITORY NO COLLATE USING SYSTEM  PAGESIZE 4096 DFT_EXTENT_SZ 32 CATALOG TABLESPACE MANAGED BY AUTOMATIC STORAGE EXTENTSIZE 4 AUTORESIZE YES INITIALSIZE 32 M MAXSIZE NONE USER TABLESPACE MANAGED BY AUTOMATIC STORAGE EXTENTSIZE 32 AUTORESIZE YES INITIALSIZE 32 M MAXSIZE NONE"
        $createTableContent += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $createTableContent += $(Get-ConnectCommand -WorkObject $WorkObject)
        $createTableContent += "db2 COMMIT WORK"
        $createTableContent += "db2 CONNECT RESET"
        $createTableContent += "db2 TERMINATE"


        $dataFolder = $(Get-ApplicationDataPath)
        if (-not (Test-Path $dataFolder -PathType Container)) {
            New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null
        }


        $output = Invoke-Db2ContentAsScript -Content $createTableContent -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($createTableContent -join "`n") -Output $output
        if ($output -like "*SQL1005N*") {
            Write-LogMessage "Database $($WorkObject.DatabaseName) already exists." -Level WARN
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error creating database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}
<#
.SYNOPSIS
    Removes all database catalog entries for a database.

.DESCRIPTION
    Uncatalogs the database and all its aliases from the Db2 catalog. Restarts the
    instance after removal to ensure changes take effect.

.PARAMETER WorkObject
    PSCustomObject containing AliasAccessPoints with CatalogName properties.

.EXAMPLE
    $workObject = Remove-CatalogingForDatabase -WorkObject $workObject
    # Uncatalogs all database aliases and restarts instance

.NOTES
    Forces instance stop/start to clear catalog cache.
#>
function Remove-CatalogingForDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing existing database $($WorkObject.DatabaseName)" -Level INFO

        $db2Commands = @()
        foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
            $db2Commands += "db2 uncatalog database $($aliasAccessPoint.CatalogName)"
        }
        $db2Commands += "db2 terminate"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing existing database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Enables transaction log archiving for a database to support online backup.

.DESCRIPTION
    Configures database for online backup by:
    - Granting DBADM/DATAACCESS/ACCESSCTRL to current user
    - Setting LOGARCHMETH1 to DISK (primary logs folder)
    - Setting LOGARCHMETH2 to OFF
    - Configuring log file sizes (LOGPRIMARY=3, LOGSECOND=200, LOGFILSIZ=256)
    - Setting MIRRORLOGPATH
    - Performing offline backup to complete logging change
    - Removing the offline backup file after completion

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, PrimaryLogsFolder, MirrorLogsFolder, and BackupFolder.

.EXAMPLE
    $workObject = Add-LoggingToDatabase -WorkObject $workObject
    # Enables log archiving for online backup capability

.NOTES
    Required for databases created without logging. Sets WorkObject.OfflineBackupPerformed timestamp.
#>
function Add-LoggingToDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Configuring database logging for $($WorkObject.DatabaseName)" -Level INFO

        $db2Commands = @()

        Write-LogMessage "Adding logging to database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 grant dbadm on database to user $($env:USERNAME)"
        $db2Commands += "db2 grant dataaccess on database to user $($env:USERNAME)"
        $db2Commands += "db2 grant accessctrl on database to user $($env:USERNAME)"
        $db2Commands += "db2 terminate"
        $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
        $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using logarchmeth1 DISK:`"$($WorkObject.PrimaryLogsFolder)`" logarchmeth2 OFF logprimary 3 logsecond 200 logfilsiz 256 mirrorlogpath `"$($WorkObject.MirrorLogsFolder)`""
        $db2Commands += "db2 connect reset"
        $db2Commands += "db2 terminate"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"  
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 quiesce database immediate force connections"
        $db2Commands += "db2 connect reset"
        $db2Commands += "db2 deactivate database $($WorkObject.DatabaseName)"
        $db2Commands += "db2 backup database $($WorkObject.DatabaseName) to `"$($WorkObject.BackupFolder)`" without prompting"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 unquiesce database"
        $db2Commands += "db2 connect reset"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate database $($WorkObject.DatabaseName)"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        Add-Member -InputObject $WorkObject -NotePropertyName "OfflineBackupPerformed" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        # Find the most recent backup file in the Db2Backup folder, and delete it since it was done just to complete the logging change
        $backupFiles = Get-ChildItem -Path $WorkObject.BackupFolder -Filter "*.001" -File
        $mostRecentBackupFile = $backupFiles | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($mostRecentBackupFile) {
            Write-LogMessage "Removing most recent backup file $($mostRecentBackupFile.FullName)" -Level INFO
            Remove-Item -Path $mostRecentBackupFile.FullName -Force
            Add-Member -InputObject $WorkObject -NotePropertyName "OfflineBackupFileToCompleteLoggingChangeRemoved" -NotePropertyValue $mostRecentBackupFile.FullName -Force
        }

        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding logging to database $DatabaseName" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Removes Db2 Windows local groups and saves member lists.

.DESCRIPTION
    Retrieves and saves current members of DB2ADMNS, DB2USERS, and FKKONTO (for INL) groups,
    then removes the groups entirely. Member lists are stored in WorkObject for audit trail.

.PARAMETER WorkObject
    PSCustomObject containing Application property.

.EXAMPLE
    $workObject = Remove-Db2AccessGroups -WorkObject $workObject
    # Saves members and removes DB2ADMNS, DB2USERS, and FKKONTO groups

.NOTES
    Member lists stored in DB2ADMNSGroupMembersRemovedList, DB2USERSGroupMembersRemovedList,
    and FKKONTOGroupMembersRemovedList properties.
#>
function Remove-Db2AccessGroups {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing existing Db2 access groups from Windows groups" -Level INFO

        $getGroupMembers = Get-LocalGroupMember -Group DB2ADMNS
        Add-Member -InputObject $WorkObject -NotePropertyName "DB2ADMNSGroupMembersRemovedList" -NotePropertyValue $getGroupMembers -Force
        Remove-LocalGroup -Name DB2ADMNS -ErrorAction SilentlyContinue

        Remove-LocalGroup -Name DB2USERS -ErrorAction SilentlyContinue
        $getGroupMembers = Get-LocalGroupMember -Group DB2USERS
        Add-Member -InputObject $WorkObject -NotePropertyName "DB2USERSGroupMembersRemovedList" -NotePropertyValue $getGroupMembers -Force

        if ($WorkObject.Application -eq "INL") {
            $getGroupMembers = Get-LocalGroupMember -Group FKKONTO
            Add-Member -InputObject $WorkObject -NotePropertyName "FKKONTOGroupMembersRemovedList" -NotePropertyValue $getGroupMembers -Force
            Remove-LocalGroup -Name FKKONTO -ErrorAction SilentlyContinue
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing admin users for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}


<#
.SYNOPSIS
    Removes admin users from Db2 Windows local groups.

.DESCRIPTION
    Removes all users in WorkObject.AdminUsers from DB2ADMNS group, removes Domain Users
    from DB2USERS, and removes all members from FKKONTO group (for INL application).

.PARAMETER WorkObject
    PSCustomObject containing AdminUsers and Application.

.EXAMPLE
    $workObject = Remove-Db2AccessUsersFromGroups -WorkObject $workObject
    # Removes admin users from Db2 groups

.NOTES
    Groups remain but are emptied. Use Remove-Db2AccessGroups to delete groups entirely.
#>
function Remove-Db2AccessUsersFromGroups {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing existing admin users for database $($WorkObject.DatabaseName)" -Level INFO

        foreach ($user in $WorkObject.AdminUsers) {
            Remove-LocalGroupMember -Group DB2ADMNS -Member "$env:USERDOMAIN\$user" -ErrorAction SilentlyContinue
        }
        Remove-LocalGroupMember -Group DB2USERS -Member "$env:USERDOMAIN\Domain Users" -ErrorAction SilentlyContinue

        if ($WorkObject.Application -eq "INL") {
            $getGroupMembers = Get-LocalGroupMember -Group FKKONTO
            foreach ($member in $getGroupMembers) {
                Remove-LocalGroupMember -Group FKKONTO -Member "$env:USERDOMAIN\$member" -ErrorAction SilentlyContinue
            }
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing admin users for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}


<#
.SYNOPSIS
    Creates Windows local groups and adds admin users for Db2 access.

.DESCRIPTION
    Creates local Windows groups (DB2ADMNS, DB2USERS, and optionally FKKONTO for INL application)
    and populates them with admin users from WorkObject.AdminUsers. Adds Domain Users to DB2USERS.

.PARAMETER WorkObject
    PSCustomObject containing AdminUsers, Application, and DatabaseName.

.EXAMPLE
    $workObject = Add-Db2AccessGroups -WorkObject $workObject
    # Creates DB2ADMNS, DB2USERS groups and adds admin users

.NOTES
    For INL application on DB2 instance, also creates FKKONTO group.
    Sets WorkObject.DatabaseUsersAdded timestamp.
#>
function Add-Db2AccessGroups {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Adding admin users for database $($WorkObject.DatabaseName)" -Level INFO


        $null = New-LocalGroup -Name DB2ADMNS -Description "Db2 Administrators for $($WorkObject.DatabaseName)" -ErrorAction SilentlyContinue | Out-Null
        $null = New-LocalGroup -Name DB2USERS -Description "Db2 Users for $($WorkObject.DatabaseName)" -ErrorAction SilentlyContinue | Out-Null
        if ($WorkObject.Application -eq "INL") {
            $null = New-LocalGroup -Name FKKONTO -Description "Users for FKKONTO for $($WorkObject.DatabaseName)" -ErrorAction SilentlyContinue | Out-Null
        }

        foreach ($user in $WorkObject.AdminUsers) {
            $null = Add-LocalGroupMember -Group DB2ADMNS -Member "$env:USERDOMAIN\$user" -ErrorAction SilentlyContinue | Out-Null
        }

        Write-LogMessage "Adding Domain Users to DB2USERS group" -Level INFO
        Add-LocalGroupMember -Group DB2USERS -Member "$env:USERDOMAIN\Domain Users" -ErrorAction SilentlyContinue | Out-Null

        Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseUsersAdded" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        if ($WorkObject.Application -eq "INL" -and $WorkObject.InstanceName -eq "DB2") {
            $WorkObject = Add-FkkontoLocalGroup -WorkObject $WorkObject
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding admin users for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Tests and retrieves general database settings including instances, nodes, and databases.

.DESCRIPTION
    Comprehensive function that retrieves:
    - All existing instances on the server
    - All cataloged nodes for the current instance
    - All databases (current instance or all instances if GetAllDatabasesInfo is specified)
    
    Enriches WorkObject with complete overview of Db2 environment state.

.PARAMETER WorkObject
    PSCustomObject to enrich with database settings.

.PARAMETER GetAllDatabasesInfo
    When specified, retrieves database information for all instances, not just current instance.

.EXAMPLE
    $workObject = Test-DatabaseGeneralSettings -WorkObject $workObject
    # Retrieves settings for current instance only

.EXAMPLE
    $workObject = Test-DatabaseGeneralSettings -WorkObject $workObject -GetAllDatabasesInfo
    # Retrieves settings for all instances on server
#>
function Test-DatabaseGeneralSettings {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$GetAllDatabasesInfo = $false
    )
    try {
        Write-LogMessage "Testing database general settings for database $($WorkObject.DatabaseName)" -Level INFO
        # Get existing instances
        $WorkObject = Get-ExistingInstances -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
   
        # Get existing nodes for current instance
        $WorkObject = Get-ExistingNodes -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
   
        # Retreive existing database-information for all instances to get an overview of all databases
        if ($GetAllDatabasesInfo) {
            foreach ($instance in $WorkObject.ExistingInstanceList) {
                $WorkObject = Get-ExistingDatabasesList -WorkObject $WorkObject -OverrideInstanceName $instance
                if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            }
        }
        else {
            $WorkObject = Get-ExistingDatabasesList -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        }
    }
    catch {
        Write-LogMessage "Error testing database general settings for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Tests database state and sets appropriate credentials for post-restore operations.

.DESCRIPTION
    Performs comprehensive database validation and credential configuration:
    - Gets control SQL statement for the application
    - Tests general database settings (instances, nodes, databases)
    - Tests database and table existence
    - Sets post-restore credentials (DbUser/DbPassword) based on application type
    - Executes control SQL statement to verify database access
    
    Credentials are application-specific (e.g., db2nt/ntdb2 for FKM, srv_erp1/Db2admin for HST).

.PARAMETER WorkObject
    PSCustomObject containing Application, DatabaseType, DatabaseName, and InstanceName.

.PARAMETER GetAllDatabasesInfo
    Retrieves database information for all instances when specified.

.EXAMPLE
    $workObject = Test-AndSetRestoredCredentials -WorkObject $workObject
    # Sets DbUser/DbPassword and verifies database access
#>
function Test-AndSetRestoredCredentials {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$GetAllDatabasesInfo = $false
    )
    try {
        # Get control SQL statement
        $workObject = Get-ControlSqlStatement -WorkObject $workObject
        if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

        # Test database general settings
        $WorkObject = Test-DatabaseGeneralSettings -WorkObject $WorkObject -GetAllDatabasesInfo:$GetAllDatabasesInfo
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Test if database already exists for current instance
        $WorkObject = Test-DatabaseExistance -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Test if table already exists for current instance
        $WorkObject = Test-TableExistance -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }


        if (  $WorkObject.InstanceExist -eq $true -and $WorkObject.DatabaseExist -eq $true -and $WorkObject.TableExist -eq $true) {
            if ($WorkObject.DatabaseType -eq "PrimaryDb") {
                # Shadow instances (DB2SH / *SH) use Windows auth (service account)
                # instead of explicit db2nt credentials that may lack CONNECT privilege
                $isShadowInstance = $WorkObject.InstanceName -match 'SH$'
                if ($isShadowInstance) {
                    Write-LogMessage "Shadow instance $($WorkObject.InstanceName) detected — using Windows auth (no explicit DbUser)" -Level INFO
                }
                else {
                    switch ($WorkObject.Application) {

                        "INL" {
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbUser" -NotePropertyValue "db2nt" -Force
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbPassword" -NotePropertyValue "ntdb2" -Force
                        }
                        "FKM" {
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbUser" -NotePropertyValue "db2nt" -Force
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbPassword" -NotePropertyValue "ntdb2" -Force
                        }
                        "HST" {
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbUser" -NotePropertyValue "srv_erp1" -Force
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbPassword" -NotePropertyValue "Db2admin" -Force
                        }
                        "DOC" {
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbUser" -NotePropertyValue "db2nt" -Force
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbPassword" -NotePropertyValue "ntdb2" -Force
                        }
                        default {
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbUser" -NotePropertyValue "db2nt" -Force
                            Add-Member -InputObject $WorkObject -NotePropertyName "DbPassword" -NotePropertyValue "ntdb2" -Force
                        }
                    }
                }
                if ($WorkObject.UseNewConfigurations) {
                    Write-LogMessage "Setting post restore credentials for database $($WorkObject.DatabaseName). DbUser: $($WorkObject.DbUser)" -Level INFO
                } else {
                    Write-LogMessage "Setting post restore credentials for database $($WorkObject.DatabaseName). DbUser: $($WorkObject.DbUser), DbPassword: $($WorkObject.DbPassword)" -Level WARN
                }
                Start-Sleep -Seconds 5

                Write-LogMessage "Testing current Db2 configuration" -Level INFO

                # Execute control sql statement for current instance
                $WorkObject = Test-ControlSqlStatement -WorkObject $WorkObject
                if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            }
        }
        else {
            Write-LogMessage "Unable to set post restore credentials, because instance, database or table does not exist" -Level WARN
        }


    }
    catch {
        Write-LogMessage "Error setting post restore credentials for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Removes node catalog entries for a database.

.DESCRIPTION
    Uncatalogs TCPIP nodes based on access point type. For PrimaryDb, removes alias nodes
    (NODE2, NODE3, etc.). For FederatedDb, removes DB2FED node. Restarts instance after removal.

.PARAMETER WorkObject
    PSCustomObject containing PrimaryAccessPoint and AliasAccessPoints.

.EXAMPLE
    $workObject = Remove-CatalogingForNodes -WorkObject $workObject
    # Uncatalogs nodes and lists remaining node directory

.NOTES
    Stops and starts Db2 instance to ensure changes take effect.
#>
function Remove-CatalogingForNodes {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing existing nodes for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        if ($WorkObject.PrimaryAccessPoint.AccessPointType -eq "PrimaryDb") {
            $counter = 2
            foreach ($aliasAccessPoint in $($WorkObject.AliasAccessPoints)) {
                $db2Commands += "db2 uncatalog node $("NODE" + $counter)"
                $counter++
            }
        }
        elseif ($WorkObject.PrimaryAccessPoint.AccessPointType -eq "FederatedDb") {
            $db2Commands += "db2 uncatalog node DB2FED"
        }
        else {
            Write-LogMessage "Access point type not supported" -Level ERROR
            throw "Access point type not supported"
        }
        $db2Commands += "db2 terminate"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 list node directory"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error removing existing nodes for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Catalogs TCPIP nodes for database connectivity.

.DESCRIPTION
    Creates TCPIP node catalog entries for remote database access. Uncatalogs existing nodes
    first, then catalogs new nodes based on service method:
    - PrimaryDb: Catalogs primary node and all alias nodes
    - FederatedDb: Catalogs federated database node
    
    Nodes use FQDN (servername.DEDGE.fk.no) and ports from access points.

.PARAMETER WorkObject
    PSCustomObject containing PrimaryAccessPoint and AliasAccessPoints with node definitions.

.PARAMETER ServiceMethod
    Determines which nodes to catalog (PrimaryDb or FederatedDb).

.EXAMPLE
    $workObject = Add-CatalogingForNodes -WorkObject $workObject -ServiceMethod "PrimaryDb"
    # Catalogs primary and alias access point nodes
#>
function Add-CatalogingForNodes {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [ValidateSet("PrimaryDb", "FederatedDb")]
        #[ValidateSet("InitialNode", "PrimaryDb", "FederatedDb", "Alias", "SslPort", "Local")]
        [string]$ServiceMethod
    )
    try {
        $oldNodeList = @()
        Write-LogMessage "Creating nodes for database $($WorkObject.DatabaseName) with service method $ServiceMethod" -Level INFO

        $WorkObject = Get-ExistingNodes -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $oldNodeList = $WorkObject.ExistingNodeList


        # if ($ServiceMethod -eq "Local") {
        #     $nodesToAdd = @()
        #     $nodesToAdd += [PSCustomObject]@{
        #         NodeName = "NODE1"
        #         NodeType = "LOCAL"
        #         Port     = ""
        #     }
        # }
        # elseif ($ServiceMethod -eq "InitialNode") {
        #     $WorkObject = Get-ExistingNodes -WorkObject $WorkObject
        #     if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        #     $oldNodeList = $WorkObject.ExistingNodeList

        #     $nodesToAdd = @()
        #     $nodesToAdd += [PSCustomObject]@{
        #         NodeName = $WorkObject.PrimaryAccessPoint.NodeName
        #         NodeType = "TCPIP"
        #         Port     = $WorkObject.PrimaryAccessPoint.Port
        #     }
        # }
        # elseif
        if ($ServiceMethod -eq "PrimaryDb") {
            $nodesToAdd = @()
            $nodesToAdd += [PSCustomObject]@{
                NodeName    = $WorkObject.PrimaryAccessPoint.NodeName
                NodeType    = "TCPIP"
                Port        = $WorkObject.PrimaryAccessPoint.Port
                ServiceName = $WorkObject.PrimaryAccessPoint.ServiceName
            }
            foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
                $nodesToAdd += [PSCustomObject]@{
                    NodeName    = $aliasAccessPoint.NodeName
                    NodeType    = "TCPIP"
                    Port        = $aliasAccessPoint.Port
                    ServiceName = $aliasAccessPoint.ServiceName
                }
            }
        }
        elseif ($ServiceMethod -eq "FederatedDb") {
            $nodesToAdd = @()
            $nodesToAdd += [PSCustomObject]@{
                NodeName    = $WorkObject.PrimaryAccessPoint.NodeName
                NodeType    = "TCPIP"
                Port        = $WorkObject.PrimaryAccessPoint.Port
                ServiceName = $WorkObject.PrimaryAccessPoint.ServiceName
            }
            foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
                $nodesToAdd += [PSCustomObject]@{
                    NodeName    = $aliasAccessPoint.NodeName
                    NodeType    = "TCPIP"
                    Port        = $aliasAccessPoint.Port
                    ServiceName = $aliasAccessPoint.ServiceName
                }
            }
        }
        # elseif ($ServiceMethod -eq "Alias") {
        #     $nodesToAdd = @()
        #     $counter = 2
        #     foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
        #         $nodesToAdd += [PSCustomObject]@{
        #             NodeName = $aliasAccessPoint.NodeName
        #             NodeType = "TCPIP"
        #             Port     = $aliasAccessPoint.Port
        #         }
        #     }
        # }
        # elseif ($ServiceMethod -eq "SslPort") {
        #     $nodesToAdd = @()
        #     $nodesToAdd += [PSCustomObject]@{
        #         NodeName = $WorkObject.PrimaryAccessPoint.NodeName
        #         NodeType = "TCPIP"
        #         Port     = $WorkObject.PrimaryAccessPoint.Port
        #     }
        # }
        else {
            Write-LogMessage "Invalid service method: $ServiceMethod" -Level ERROR
            throw "Invalid service method: $ServiceMethod"
        }
        if ($nodesToAdd.Count -gt 0) {
            $db2Commands = @()
            $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
            $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
            foreach ($nodeToRemove in $oldNodeList) {
                $db2Commands += "db2 uncatalog node $($nodeToRemove)"
            }
            $db2Commands += "db2 terminate"
            $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
            $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
            foreach ($nodeToAdd in $nodesToAdd) {
                $db2Commands += "db2 catalog $($nodeToAdd.NodeType) node $($nodeToAdd.NodeName) remote $($env:COMPUTERNAME).DEDGE.fk.no server $($nodeToAdd.Port)"
            }
        }

        $db2Commands += "db2 terminate"
        # $db2Commands = @()

        # $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        # $counter = 1
        # $nodesToAdd = @()
        # $nodesToAdd += [PSCustomObject]@{
        #     NodeName = "NODE1"
        #     Port     = $WorkObject.PrimaryAccessPoint.Port
        # }
        # $counter = 2
        # foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
        #     $nodesToAdd += [PSCustomObject]@{
        #         NodeName = "NODE" + $counter
        #         Port     = $aliasAccessPoint.Port
        #     }
        #     $counter++
        # }
        # foreach ($nodeToAdd in $nodesToAdd) {
        #     $db2Commands += "db2 uncatalog node $($nodeToAdd.NodeName)"
        #     $db2Commands += "db2 catalog tcpip node $($nodeToAdd.NodeName) remote $($env:COMPUTERNAME).DEDGE.fk.no server $($nodeToAdd.Port)"
        # }

        # $db2Commands += "db2 terminate"
        # $db2Commands += "db2stop force"
        # $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 list node directory"
        $db2Commands += "db2 terminate"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error creating nodes for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Grants application-specific table and function privileges to service accounts.

.DESCRIPTION
    Applies predefined grants based on Application, InstanceName, and Environment:
    - FKM: Grants to SRV_KPDB, DB2NT, SRV_BIZTALKHIA, ISYS, FORIT, SRV_CRM on specific tables/functions
    - Grants schema-level permissions to SRV_DATAVAREHUS, DB2USERS, DB2ADMNS, and admin users
    - Handles environment-specific service accounts (e.g., SRV_BIZTALKHIA vs SRV_TST_BIZTALKHIA)

.PARAMETER WorkObject
    PSCustomObject containing Application, InstanceName, Environment, DatabaseName, and AdminUsers.

.EXAMPLE
    $workObject = Add-SpecificGrants -WorkObject $workObject
    # Applies application-specific grants for FKM/INL/DOC applications

.NOTES
    Grant definitions are hardcoded per application. Requires database connectivity.
#>
function Add-SpecificGrants {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    Write-LogMessage "Adding specific grants for database $($WorkObject.DatabaseName)" -Level INFO
    try {
        $grantArray = @()
        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2", "DB2FED")
            User             = "SRV_KPDB"
            Grants           = @(
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VARE_KATEGORI"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VARE_VAREBESKRIVELSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VAREBESKRIVELSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "H_ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "H_ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VAREHOVEDGRUPPER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "H_FAKT_ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "AH_ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "AH_ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT_STATUS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_DYRKER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT_TYPE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT_LIN"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ART"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ARTSORT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "P_AVREGNING"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KUNDER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ANLEGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_DYRKER_STATUS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "TEKSTER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_LOVL_ANLEGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_EIENDOM"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VAREREGISTER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_BESTILLING"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTSTAT_LOGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONT_LIN_LOGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_WEB_ART"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_WEB_ART_SORT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VAREADRESSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "FORDEL_KUNDE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "FORDEL_VARE2"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LOGISTIKK_GRP"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VARERUTEKALENDER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VARERUTE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MVA_SATSER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LASS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "TMS_STATUS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_KATEGORI"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VARE_KATEGORI"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VARE_VAREBESKRIVELSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VAREBESKRIVELSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VAREMELDING"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_ALTERNATIVVARE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VK_LINK"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "Z_PNRTAB"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "OKL_WEB"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KUNDESPES_VARER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "SILOINFO"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "SILOINFO_DETALJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "Z_KOMMUNER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "TV"; Name = "SALG_SISTE_10"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "TV"; Name = "ADR_FARETEKST"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "KP"; Name = "FPROVE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "KP"; Name = "KONTRAKT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                [PSCustomObject]@{ Schema = "KP"; Name = "MOTTAK"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
                # FUNCTIONS WITH EXECUTE
                [PSCustomObject]@{ Schema = "FK"; Name = "CD2D"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "D2CD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "D8AMD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "D8DMA"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "D10AMD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "D10DMA"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "D10MDA"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "DAGNAVN"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "DATE"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "DATE_AMD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "NCD2D"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "ND2CD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "PRNR"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "PRODUKT"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "SALGSGRUPPE"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "SALGSGRUPPE_TXT"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TID4"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TID4X"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TID6"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TID6X"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TID8"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TID8X"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TSD6AMD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TSD6DMA"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TSD8AMD"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "TSD8DMA"; Type = "Function"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "FK"; Name = "UKEDAG"; Type = "Function"; Privileges = @("Execute") }
            )
        }

        # $grantArray += [PSCustomObject]@{
        #     Application  = "FKM"
        #     InstancenameList = @("DB2FED")
        #     User         = "SRV_KPDB"
        #     Grants       = @(
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "H_ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "H_ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VAREHOVEDGRUPPER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "H_FAKT_ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "AH_ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "AH_ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT_STATUS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_DYRKER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT_TYPE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTRAKT_LIN"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "ART"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "ARTSORT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "P_AVREGNING"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KUNDER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "ANLEGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_DYRKER_STATUS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "TEKSTER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_LOVL_ANLEGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_EIENDOM"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VAREREGISTER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_BESTILLING"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONTSTAT_LOGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_KONT_LIN_LOGG"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_WEB_ART"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "KD_WEB_ART_SORT"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VAREADRESSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "FORDEL_KUNDE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "FORDEL_VARE2"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "LOGISTIKK_GRP"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VARERUTEKALENDER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VARERUTE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "ORDREHODE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "MVA_SATSER"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "LASS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "TMS_STATUS"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VK_KATEGORI"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VARE_KATEGORI"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VARE_VAREBESKRIVELSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VAREBESKRIVELSE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VK_VAREMELDING"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "VK_ALTERNATIVVARE"; Type = "Table"; Privileges = @("Select", "Update", "Delete", "Insert") }
        #     )
        # }
             
        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2FED")
            User             = "DB2NT"
            Grants           = @(
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_ORDER_HEAD"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_ORDER_LINE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_CUSTOMER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_PAYMENTCONFIRMATION"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_RETURNORDER_HEAD"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_RETURNORDER_LINE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_THERM_BEST"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_THERM_GPR"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_THERM_GPR_SJ"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_THERM_RES_INC"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "KD_THERM_RES_FEIL"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MOTTAK"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MOTTAK_DUBLETT"; Type = "Table"; Privileges = @("All") }
            )
        }
        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2", "DB2FED")
            User             = "SRV_CRM"
            Grants           = @(
                [PSCustomObject]@{ Schema = "CRM"; Name = "KUNDER_U"; Type = "Table"; Privileges = @("Select") }
            )
        }

        # ISYS USER
        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2", "DB2FED")
            User             = "ISYS"
            Grants           = @(
                [PSCustomObject]@{ Schema = "DBM"; Name = "OIN_HODE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "OIN_LINJER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_FAKT_HODE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_FAKT_LINJE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_FAKT_TILLEGG"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_HODE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_HODEMRK"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_LIN"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_LINMRK"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_PAKK_HODE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_PAKK_LINJER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_KONV_KUNDENR"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LEVERANDØR"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "GRUNNLAG_ISYS"; Type = "Table"; Privileges = @("All") }
            )
        }

        # FORIT USER
        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2", "DB2FED")
            User             = "FORIT"
            Grants           = @(
                [PSCustomObject]@{ Schema = "FORIT"; Name = "RESEPT_FKNR"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VARESTATUS"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "OLINSTAT"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "UTVE_BEVM_LINJENR"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "TRANSKODER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VAREMELLOMGRUPPER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VAREGRUPPER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VAREHOVEDGRUPPER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "BESTLIN"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "KOSTPRIS"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VAREBEVEGELSE"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "LASS"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "ORDRELINJER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "UTVEIING"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "PRODBEH_HIST"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "KRHLST1"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "ORDREHODE"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "BESTHODE"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "AARSAK"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VAREINNGANGER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "FAKTURERTE_ORDRE"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "PRODUKSJONSBEHOV"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "VAREREGISTER"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
                [PSCustomObject]@{ Schema = "FORIT"; Name = "PAKKEORDRE"; Type = "Table"; Privileges = @("Select", "Insert", "Update") }
            )
        }

        # $grantArray += [PSCustomObject]@{
        #     Application  = "FKM"
        #     InstancenameList = @("DB2FED")
        #     User         = "ISYS"
        #     Grants       = @(
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "OIN_HODE"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "OIN_LINJER"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_FAKT_HODE"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_FAKT_LINJE"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_FAKT_TILLEGG"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_HODE"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_HODEMRK"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_LIN"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_ORDBEK_LINMRK"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_PAKK_HODE"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_PAKK_LINJER"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "EDI_KONV_KUNDENR"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "LEVERANDØR"; Type = "Table"; Privileges = @("All") }
        #         [PSCustomObject]@{ Schema = "DBM"; Name = "GRUNNLAG_ISYS"; Type = "Table"; Privileges = @("All") }
        #     )
        # }
        
     
        
        if ($WorkObject.ENVIRONMENT -eq "PRD") {
            $srv_biztalkhia = "SRV_BIZTALKHIA"
        }
        else {
            $srv_biztalkhia = "SRV_TST_BIZTALKHIA"
        }

        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2", "DB2FED")
            User             = $srv_biztalkhia
            Grants           = @(
                [PSCustomObject]@{ Schema = "DBM"; Name = "PAKKEORDRE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "SJEKK_AKTIV_EIENDOM"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_CUSTOMERUPDATE"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_ORDERUPDATE"; Type = "PROCEDURE"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "VAREREGISTER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "SHOPPA_ARTIKKEL"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "SHOPPA_PRIS"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ORDRE_TIL_FABRIKK"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "PRO11_TO_PORTA"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "CRM_INT_LEV"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MSINT_MASKINER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MSINT_VSTAT"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "ONR_HNR_UPD"; Type = "PROCEDURE"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_SETTLEMENTPOSTING_TRANSACTION"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "EC_SETTLEMENTFEE_TRANSACTION"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "COLLECTOR_TRANSER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "RUNPROT_IDA"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "RUNPROT_MOR"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "PRO12_FROM_PORTA"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LDF_ORGNR_AVREGNING"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LDF_AVR_TRUNC"; Type = "PROCEDURE"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LDF_AVR_UPDATE"; Type = "PROCEDURE"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LDF_ORGNR_FAKTURA"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LDF_FAKT_TRUNC"; Type = "PROCEDURE"; Privileges = @("Execute") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "LDF_FAKT_UPDATE"; Type = "PROCEDURE"; Privileges = @("Execute") }
            )
        }
        
            

        
        $grantArray += [PSCustomObject]@{
            Application      = "FKM"
            InstancenameList = @("DB2", "DB2FED")
            User             = "SRV_CRM"
            Grants           = @(
                [PSCustomObject]@{ Schema = "CRM"; Name = "KUNDER_U"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "KUNDER"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "KRAFTFOR_BULK"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "FRAKTRATER"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "KREDITT"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "AH_ORDREHODE_MASKIN"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "AH_ORDRELINJER_MASKIN"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "A_ORDRELINJER_MASKIN2"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "CRM"; Name = "A_ORDREHODE_MASKIN"; Type = "Table"; Privileges = @("Select") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "CRM_PRODFORM"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "AD_BRUKER"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "CRM_Dedge"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MARKEDSDATA"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "DBM"; Name = "MASKINTILB_SPES"; Type = "Table"; Privileges = @("All") }
                [PSCustomObject]@{ Schema = "ESM"; Name = "MAS_MASKIN"; Type = "Table"; Privileges = @("Select") }
            )
        }
        $fkStandardUser = ""
        $fkStandardReadonlyUser = ""
        $fkStandardDbaUserName = ""
        if ($WorkObject.Environment -eq "PRD") {
            $fkStandardUser = "FKPRDUSR"
            $fkStandardReadonlyUser = "FKPRDRDO"
            $fkStandardDbaUserName = "FKPRDDBA"
        }
        elseif ($WorkObject.Environment -eq "DEV") {
            $fkStandardUser = "FKDEVUSR"
            $fkStandardReadonlyUser = "FKDEVDRDO"
            $fkStandardDbaUserName = "FKDEVDBA"
        }
        else {
            $fkStandardUser = "FKTSTSTD"
            $fkStandardReadonlyUser = "FKTSTDRDO"
            $fkStandardDbaUserName = "FKTSTDBA"
        }
        # Readonly user grants
        $grantArray += [PSCustomObject]@{
            Application           = "*"
            InstancenameList      = @("DB2", "DB2FED")
            User                  = $fkStandardReadonlyUser
            Privileges            = @("Select")
            AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST", "INL", "TMS", "LOG", "HST")
        }
        
        # DB2USERS group grants
        $grantArray += [PSCustomObject]@{
            Application           = "*"
            InstancenameList      = @("DB2", "DB2FED")
            Group                 = "DB2USERS"
            Privileges            = @("Select")
            AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST", "INL", "TMS", "LOG", "HST")
        }
        
        # DB2ADMNS group grants
        $grantArray += [PSCustomObject]@{
            Application           = "*"
            InstancenameList      = @("DB2", "DB2FED")
            Group                 = "DB2ADMNS"
            Privileges            = @("Select")
            AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST", "INL", "TMS", "LOG", "HST")
        }
        
        # SRV_DATAVAREHUS user grants
        $grantArray += [PSCustomObject]@{
            Application           = "*"
            InstancenameList      = @("DB2", "DB2FED")
            User                  = "SRV_DATAVAREHUS"
            Privileges            = @("Select")
            AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST", "INL", "TMS", "LOG", "HST")
        }
        
        # Admin users grants
        foreach ($adminUser in $WorkObject.AdminUsers) {
            $grantArray += [PSCustomObject]@{
                Application           = "*"
                InstancenameList      = @("DB2", "DB2FED")
                User                  = $adminUser
                Privileges            = @("Select")
                AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST", "INL", "TMS", "LOG", "HST")
            }
        }
        
        # Standard user grants (read/write)
        $grantArray += [PSCustomObject]@{
            Application           = "*"
            InstancenameList      = @("DB2", "DB2FED")
            User                  = $fkStandardUser
            Privileges            = @("Select", "Update", "Delete", "Insert")
            AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST", "INL", "TMS", "LOG", "HST")
        }
        
        # # # PUBLIC USER
        #  $grantArray += [PSCustomObject]@{
        #     Application           = "*"
        #     InstancenameList      = @("DB2")
        #     Group                 = "DB2USERS"
        #     Privileges            = @("Select")
        #     AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST")
        # }

        # # Admin users
        # $grantArray += [PSCustomObject]@{
        #     Application           = "*"
        #     InstancenameList      = @("DB2")
        #     Group                 = "DB2ADMNS"
        #     Privileges            = @("All")
        #     AllTablesSchemaFilter = @("CRM", "DBM", "ESM", "DV", "TV", "HST")
        # }

        $db2Commands = @()        
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)

        # Handle schema grants — use schema-level *IN privileges instead of per-table grants
        $grantAllArray = @()
        $grantAllArray += $grantArray | Where-Object { $_.Application -eq $WorkObject.Application -and $WorkObject.Instancename -in $_.InstancenameList -and $_.PSObject.Properties['AllTablesSchemaFilter'] }
        $grantAllArray += $grantArray | Where-Object { $_.Application -eq "*" -and $WorkObject.Instancename -in $_.InstancenameList -and $_.PSObject.Properties['AllTablesSchemaFilter'] }
        if ($grantAllArray.Count -gt 0) {
            $allSchemas = $grantAllArray | ForEach-Object { $_.AllTablesSchemaFilter } | Sort-Object -Unique
            Write-LogMessage "Granting schema-level privileges for $($grantAllArray.Count) grant entries, schemas: $($allSchemas -join ', ')" -Level INFO

            $schemaGrantCount = 0
            foreach ($grantAll in $grantAllArray) {
                $target = if ($grantAll.Group) { "group $($grantAll.Group)" } else { "user $($grantAll.User)" }
                foreach ($schema in $grantAll.AllTablesSchemaFilter) {
                    foreach ($priv in $grantAll.Privileges) {
                        # Map table-level privilege names to DB2 schema-level *IN equivalents
                        $schemaPrivileges = switch ($priv) {
                            "Select"  { @("SELECTIN") }
                            "Insert"  { @("INSERTIN") }
                            "Update"  { @("UPDATEIN") }
                            "Delete"  { @("DELETEIN") }
                            "Execute" { @("EXECUTEIN") }
                            "All"     { @("SELECTIN", "INSERTIN", "UPDATEIN", "DELETEIN") }
                        }
                        foreach ($sp in $schemaPrivileges) {
                            $db2Commands += "db2 grant $($sp) on schema $($schema) to $($target)"
                            $schemaGrantCount++
                        }
                    }
                }
            }
            Write-LogMessage "Generated $($schemaGrantCount) schema-level grant commands" -Level INFO

            # ---- START COMMENTED OUT 2026-03-17 - Replaced per-table grants with schema-level *IN grants ----
            # $allSchemas = $grantAllArray | ForEach-Object { $_.AllTablesSchemaFilter } | Sort-Object -Unique
            # Write-LogMessage "Querying table list once for $($grantAllArray.Count) grant entries, schemas: $($allSchemas -join ', ')" -Level INFO
            # $WorkObject = Get-DatabaseListOfTables -WorkObject $WorkObject -SchemaList $allSchemas
            # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            # Write-LogMessage "Found $($WorkObject.ListOfTables.Count) tables matching schema filter" -Level INFO
            #
            # foreach ($grantAll in $grantAllArray) {
            #     foreach ($table in $WorkObject.ListOfTables) {
            #         if ($table.SCHEMA -in $grantAll.AllTablesSchemaFilter) {
            #             if ($grantAll.Privileges -is [array]) {
            #                 $privileges = $grantAll.Privileges | ForEach-Object { $_ } | Join-String -Separator ","
            #             }
            #             else {
            #                 $privileges = $grantAll.Privileges
            #             }
            #             if ($grantAll.Group) {
            #                 $db2Commands += "db2 grant $($privileges) on table $($table.SCHEMA).$($table.NAME) to group $($grantAll.Group)"
            #             }
            #             else {
            #                 $db2Commands += "db2 grant $($privileges) on table $($table.SCHEMA).$($table.NAME) to user $($grantAll.User)"
            #             }
            #         }
            #     }
            # }
            # ---- END COMMENTED OUT 2026-03-17 ----
        }

        # Handle current grants and add to the db2Commands array
        $currentGrantArray = $grantArray | Where-Object { $_.Application -eq $WorkObject.Application -and $WorkObject.Instancename -in $_.InstancenameList -and $_.PSObject.Properties['Grants'] }
        foreach ($grantElement in $currentGrantArray) {
            foreach ($grant in $grantElement.Grants) {
                if ($grant.Privileges -is [array]) {
                    $privileges = $grantAll.Privileges | ForEach-Object { $_ } | Join-String -Separator ","
                }
                else {
                    $privileges = $grant.Privileges
                }
                $db2Commands += "db2 grant $($privileges) on $($grant.Type) $($grant.Schema).$($grant.Name) to user $($grantElement.User)"
            }
        }

        if ($WorkObject.DatabaseType -eq "FederatedDb") {
            $distinctUsers = $currentGrantArray | Select-Object -Property User -Unique
            foreach ($user in $distinctUsers) {
                $db2Commands += "db2 grant connect on database to user $($user.User)"
            }
        }



        # fkStandardDbaUserName
        $db2Commands += $(Get-CommandsForDatabasePermissions -UserName $fkStandardDbaUserName)
        
        $db2Commands += "db2 terminate"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors -Quiet
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        Add-Member -InputObject $WorkObject -NotePropertyName "GrantArray" -NotePropertyValue $currentGrantArray -Force


        
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error setting permissions for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}



<#
.SYNOPSIS
    Creates HST schema with empty history tables in FKM non-production databases.

.DESCRIPTION
    For FKM application in non-PRD environments on DB2 instance, creates HST schema with
    empty history tables:
    - HST.AH_BESTHODE, HST.AH_BESTLIN
    - HST.AH_VIHODE, HST.AH_VILIN
    - HST.H_BESTHODE, HST.H_BESTLIN
    - HST.H_VIHODE, HST.H_VILIN
    - HST.VAREBEVEGELSE
    
    Drops existing tables first, then creates with full schema definition.

.PARAMETER WorkObject
    PSCustomObject containing Application, Environment, DatabaseType, InstanceName, and DatabaseName.

.EXAMPLE
    $workObject = Add-HstSchemaFromFkmNonPrd -WorkObject $workObject
    # Creates empty HST schema tables for FKM test environment

.NOTES
    Only applies to FKM non-PRD on DB2 instance. Sets WorkObject.HstSchemaAddedFromFkmNonPrd timestamp.
    Production uses federation to actual FKMHST database instead.
#>
function Add-HstSchemaFromFkmNonPrd {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Adding HST schema from FKM non PRD" -Level INFO
        if ($WorkObject.Application -eq "FKM" -and $WorkObject.Environment -ne "PRD" -and $WorkObject.DatabaseType -eq "PrimaryDb" -and $WorkObject.InstanceName -eq "DB2") {
            $db2Commands = @"
            CONNECT TO $($WorkObject.DatabaseName);
            DROP NICKNAME HST.AH_BESTHODE;
            DROP NICKNAME HST.AH_BESTLIN;
            DROP NICKNAME HST.AH_VIHODE;
            DROP NICKNAME HST.AH_VILIN;
            DROP NICKNAME HST.H_BESTHODE;
            DROP NICKNAME HST.H_BESTLIN;
            DROP NICKNAME HST.H_VIHODE;
            DROP NICKNAME HST.H_VILIN;
            DROP NICKNAME HST.VAREBEVEGELSE;
            DROP TABLE HST.AH_BESTHODE;
            DROP TABLE HST.AH_BESTLIN;
            DROP TABLE HST.AH_VIHODE;
            DROP TABLE HST.AH_VILIN;
            DROP TABLE HST.H_BESTHODE;
            DROP TABLE HST.H_BESTLIN;
            DROP TABLE HST.H_VIHODE;
            DROP TABLE HST.H_VILIN;
            DROP TABLE HST.VAREBEVEGELSE;

            CREATE TABLE HST.AH_BESTHODE (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDREDATO          DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDREKL            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ORDRESTATUS        CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                VINNGSTATUS        CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                ORDREBEKR          CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                NETTOBELOP         DECIMAL     (13, 2)    NOT NULL WITH DEFAULT 0.0,
                BRUTTOBELOP        DECIMAL     (13, 2)    NOT NULL WITH DEFAULT 0.0,
                RESTORDREKODE      CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                AVSLUTT            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                OPPDATERING        CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ONSKETLEVUKE       DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ONSKETLEVDATO      DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVUKE         DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVDATO        DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                BESTPR             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                INNKJOPER          CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                HOVEDVAREGR        CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                TRANSPORTOR        DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                DIRLEVKUNDE        DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                REFERANSEORDRE     DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                TERMINAL           CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                FORMULAR           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTA             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                SENDESPR           CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                BETBET             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                LEVBET             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                LEVBETSTED         CHARACTER   (24)      NOT NULL WITH DEFAULT ' ',
                SISTELINJE         DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                OBEKRDATO          DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                DATOVINNGF         DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                DATOVINNGS         DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVORDRENR         CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                LEVREF             CHARACTER   (20)      NOT NULL WITH DEFAULT ' ',
                ORDRERABATT        DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                FORFDATO           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                FAKO               CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                SORT               CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VAREMERK           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                PRINTER            CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                LEVSECURITY        CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                REFTYPE            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                RESKLEVNR          DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                AVTALE             CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                KOMMENTAR          VARCHAR     (1024)    NOT NULL WITH DEFAULT '',
                SISTELEVDATO       DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LASTESTED          DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                SEPARAT_PAKKING    CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                EDI_TIDSPUNKT      TIMESTAMP             ,
                VALUTAKURS         DECIMAL     (8, 5)     NOT NULL WITH DEFAULT 0.0,
                SKRIV_PRIS         CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                SPEDNR             DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                AUTO_INNGANG       DECIMAL     (1, 0)     NOT NULL WITH DEFAULT 0.0,
                MOTTATT_EDI_OBK    CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                TRANSPORT_TYPE     CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                SAMPAKK_STATUS     CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                PROSJ_ID           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LAGERSTED          DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                PRIMARY KEY(AAR, ORDRENR)
            );
            CREATE TABLE HST.AH_BESTLIN (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LINJE              DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                LINJESTATUS        CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                VTYPE              CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                LEVVARENR          CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                FKNR               DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                VARENAVN           CHARACTER   (35)      NOT NULL WITH DEFAULT ' ',
                FORSLAG            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BESTANT            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                PRINTANT           DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BEKRANT            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                MOTTANT            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                PRIS               DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                KOSTPRIS           DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BRUTTOBELOP        DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                NETTOBELOP         DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                ONSKETLEVUKE       DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ONSKETLEVDATO      DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVUKE         DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVDATO        DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                PAKNKVANT          DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                PALLKVANT          DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                GRUNNRAB           DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRAB1            DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRAB2            DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                GRUNNRABKODE       CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ENHET              CHARACTER   (5)       NOT NULL WITH DEFAULT ' ',
                HVGR               CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                UVGR               CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                KGRADFK            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                KGRADAVD           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VARESTATUS         CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                AVTALELINJE        DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                ENHVEKT            DECIMAL     (9, 3)     NOT NULL WITH DEFAULT 0.0,
                PRISKODE           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ALTLEVVARE         CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                VARELEVNR          DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                KOMMENTAR          VARCHAR     (1024)    NOT NULL WITH DEFAULT '',
                PARTIVARE          CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                AVTALT_RABATT      DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                AVTALT_PRIS        DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                GRUNNPRISKODE      CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                NY_VAREGR          CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                KATEGORI           CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                PLASSNR            CHARACTER   (6)       NOT NULL WITH DEFAULT ' ',
                ENHETSNR           DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                REGION             DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                S_ORDRENR          DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                S_ORDRE_LNR        DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                DIREKTELEVERING    CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                KAMPANJE_ID        CHARACTER   (14)      NOT NULL WITH DEFAULT ' ',
                KAMPANJE_TYPE      DECIMAL     (2, 0)     NOT NULL WITH DEFAULT 0.0,
                INNKJ_ENHET        CHARACTER   (5)       NOT NULL WITH DEFAULT ' ',
                IENHET_FAKTOR      DECIMAL     (12, 4)    NOT NULL WITH DEFAULT 0.0,
                IENHET_ANTALL      DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                EKSTRA_RABATT      DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                PRIMARY KEY(AAR, ORDRENR, LINJE)
            );
            CREATE TABLE HST.AH_VIHODE (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGANGNR          DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                LAGERSTED          DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGDATO           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                PAKKSEDDEL         CHARACTER   (10)      NOT NULL WITH DEFAULT ' ',
                BILNR              DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                INNGANG_TYPE       CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                KOMMENTAR          VARCHAR     (1024)    NOT NULL WITH DEFAULT '',
                PRIMARY KEY(AAR, AVDNR, INNGANGNR)
            );
            CREATE TABLE HST.AH_VILIN (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGANGNR          DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGDATO           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LINJENR            DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                LAGERSTED          DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                FKNR               DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVVARENR          CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                PLASSNR            CHARACTER   (6)       NOT NULL WITH DEFAULT ' ',
                VARENAVN           CHARACTER   (35)      NOT NULL WITH DEFAULT ' ',
                ENHET              CHARACTER   (5)       NOT NULL WITH DEFAULT ' ',
                ENHETSVEKT         DECIMAL     (9, 3)     NOT NULL WITH DEFAULT 0.0,
                BESTANT            DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                MOTTATT            DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                KOSTPRIS           DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                PRIS               DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                PRISKODE           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTA             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                VAREGR             DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                NY_VAREGR          CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                VALUTANETTO        DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                GRUNNRABATT        DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRABATT1         DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRABATT2         DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                GRUNNRABKODE       CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTABRUTTO       DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BREKKASJE          DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                KODEBREKK          CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                SPLITT_DISPLAY     CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                REF_INNGANGNR      DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                MT015              CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                PRIMARY KEY(AAR, AVDNR, INNGANGNR, LINJENR)
            );
            CREATE TABLE HST.H_BESTHODE (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDREDATO          DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDREKL            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ORDRESTATUS        CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                VINNGSTATUS        CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                ORDREBEKR          CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                NETTOBELOP         DECIMAL     (13, 2)    NOT NULL WITH DEFAULT 0.0,
                BRUTTOBELOP        DECIMAL     (13, 2)    NOT NULL WITH DEFAULT 0.0,
                RESTORDREKODE      CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                AVSLUTT            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                OPPDATERING        CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ONSKETLEVUKE       DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ONSKETLEVDATO      DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVUKE         DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVDATO        DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                BESTPR             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                INNKJOPER          CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                HOVEDVAREGR        CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                TRANSPORTOR        DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                DIRLEVKUNDE        DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                REFERANSEORDRE     DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                TERMINAL           CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                FORMULAR           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTA             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                SENDESPR           CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                BETBET             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                LEVBET             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                LEVBETSTED         CHARACTER   (24)      NOT NULL WITH DEFAULT ' ',
                SISTELINJE         DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                OBEKRDATO          DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                DATOVINNGF         DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                DATOVINNGS         DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVORDRENR         CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                LEVREF             CHARACTER   (20)      NOT NULL WITH DEFAULT ' ',
                ORDRERABATT        DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                FORFDATO           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                FAKO               CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                SORT               CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VAREMERK           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                PRINTER            CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                LEVSECURITY        CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                REFTYPE            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                RESKLEVNR          DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                AVTALE             CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                KOMMENTAR          VARCHAR     (1024)    NOT NULL WITH DEFAULT '',
                SISTELEVDATO       DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LASTESTED          DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                OVERFORT_ALFRA     DECIMAL     (1, 0)     NOT NULL WITH DEFAULT 0.0,
                BAAT_NAVN          CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                SKRIV_PRIS         CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTAKURS         DECIMAL     (8, 5)     NOT NULL WITH DEFAULT 0.0,
                SPEDNR             DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                AUTO_INNGANG       DECIMAL     (1, 0)     NOT NULL WITH DEFAULT 0.0,
                MOTTATT_EDI_OBK    CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                PRIMARY KEY(AAR, ORDRENR)
            );
            CREATE TABLE HST.H_BESTLIN (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LINJE              DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                LINJESTATUS        CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                VTYPE              CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                LEVVARENR          CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                FKNR               DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                VARENAVN           CHARACTER   (24)      NOT NULL WITH DEFAULT ' ',
                FORSLAG            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BESTANT            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                PRINTANT           DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BEKRANT            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                MOTTANT            DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                PRIS               DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BRUTTOBELOP        DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                NETTOBELOP         DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                ONSKETLEVUKE       DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ONSKETLEVDATO      DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVUKE         DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                BEKRLEVDATO        DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                PAKNKVANT          DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                PALLKVANT          DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                GRUNNRAB           DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRAB1            DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRAB2            DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                GRUNNRABKODE       CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ENHET              CHARACTER   (5)       NOT NULL WITH DEFAULT ' ',
                HVGR               CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                UVGR               CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                KGRADFK            CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                KGRADAVD           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VARESTATUS         CHARACTER   (2)       NOT NULL WITH DEFAULT ' ',
                AVTALELINJE        DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                ENHVEKT            DECIMAL     (9, 3)     NOT NULL WITH DEFAULT 0.0,
                PRISKODE           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                ALTLEVVARE         CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                VARELEVNR          DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                KOMMENTAR          VARCHAR     (1024)    NOT NULL WITH DEFAULT '',
                PARTIVARE          CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                AVTALEID           CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                HOS_TIL_SPIDER     DECIMAL     (1, 0)     NOT NULL WITH DEFAULT 0.0,
                SUM_PLANLAGT       DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                LASSNR             DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                REF_LINJE          DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                PRIMARY KEY(AAR, ORDRENR, LINJE)
            );
            CREATE TABLE HST.H_VIHODE (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGANGNR          DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                LAGERSTED          DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGDATO           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                TRANSPORTOR        DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                PAKKSEDDEL         CHARACTER   (10)      NOT NULL WITH DEFAULT ' ',
                LASTESTED          DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                BILNR              DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                REF_INNGANGNR      DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                KONTRAKTNR         CHARACTER   (15)      NOT NULL WITH DEFAULT '',
                PRIMARY KEY(AAR, AVDNR, INNGANGNR)
            );
            CREATE TABLE HST.H_VILIN (
                AAR                DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                BRUKER             CHARACTER   (8)       NOT NULL WITH DEFAULT ' ',
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGANGNR          DECIMAL     (5, 0)     NOT NULL WITH DEFAULT 0.0,
                INNGDATO           DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                ORDRENR            DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LINJENR            DECIMAL     (4, 0)     NOT NULL WITH DEFAULT 0.0,
                LAGERSTED          DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                FKNR               DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                LEVVARENR          CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                PLASSNR            CHARACTER   (6)       NOT NULL WITH DEFAULT ' ',
                VARENAVN           CHARACTER   (24)      NOT NULL WITH DEFAULT ' ',
                ENHET              CHARACTER   (5)       NOT NULL WITH DEFAULT ' ',
                ENHETSVEKT         DECIMAL     (9, 3)     NOT NULL WITH DEFAULT 0.0,
                BESTANT            DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                MOTTATT            DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                PRIS               DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                PRISKODE           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTA             CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                LEVNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                VAREGR             DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                VALUTANETTO        DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                GRUNNRABATT        DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRABATT1         DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                EKSRABATT2         DECIMAL     (5, 2)     NOT NULL WITH DEFAULT 0.0,
                GRUNNRABKODE       CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                VALUTABRUTTO       DECIMAL     (11, 2)    NOT NULL WITH DEFAULT 0.0,
                BREKKASJE          DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                KODEBREKK          CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                LEV_ANT_ENHETER    DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                LEV_ENHETSVEKT     DECIMAL     (9, 3)     NOT NULL WITH DEFAULT 0.0,
                LEV_EMBALLASJEVEKT DECIMAL     (5, 3)     NOT NULL WITH DEFAULT 0.0,
                INNG_MAATE         CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                PARTINR            CHARACTER   (10)      NOT NULL WITH DEFAULT ' ',
                LASSNR             DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0,
                MT015              CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                PRIMARY KEY(AAR, AVDNR, INNGANGNR, LINJENR)
            );
            CREATE TABLE HST.VAREBEVEGELSE (
                AVDNR              DECIMAL     (6, 0)     NOT NULL WITH DEFAULT 0.0,
                FKNR               DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                TIDSPUNKT          TIMESTAMP             NOT NULL WITH DEFAULT CURRENT TIMESTAMP,
                TRANSKODE          DECIMAL     (3, 0)     NOT NULL WITH DEFAULT 0.0,
                FRA_LAGERSTED      DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                TIL_LAGERSTED      DECIMAL     (7, 0)     NOT NULL WITH DEFAULT 0.0,
                LAGERDATO          DECIMAL     (8, 0)     NOT NULL WITH DEFAULT 0.0,
                KVANTUM            DECIMAL     (13, 3)    NOT NULL WITH DEFAULT 0.0,
                OVERFORT           CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
                REFNR              DECIMAL     (11, 0)    NOT NULL WITH DEFAULT 0.0,
                BRUKERID           CHARACTER   (3)       NOT NULL WITH DEFAULT ' ',
                BERITAK            DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                ITAK               DECIMAL     (9, 2)     NOT NULL WITH DEFAULT 0.0,
                REFERANSE          CHARACTER   (12)      NOT NULL WITH DEFAULT ' ',
                IFAKT              DECIMAL     (6, 4)     NOT NULL WITH DEFAULT 0.0,
                LOKASJONID         CHARACTER   (15)      NOT NULL WITH DEFAULT ' ',
                PRIMARY KEY(AVDNR, FKNR, TIDSPUNKT, TRANSKODE, FRA_LAGERSTED, TIL_LAGERSTED)
            );

"@
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType SQL -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').sql")" -IgnoreErrors -InstanceName $WorkObject.InstanceName
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
            Add-Member -InputObject $WorkObject -NotePropertyName "HstSchemaAddedFromFkmNonPrd" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        }
        else {
            Write-LogMessage "No HST schema to add for database $($WorkObject.DatabaseName)" -Level INFO
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding HST schema from FKM non PRD" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Creates local and remote database catalog entries on the Db2 server.

.DESCRIPTION
    Catalogs the database locally and creates alias entries for remote access. For Kerberos
    authentication, adds TARGET PRINCIPAL specification. Creates both system and user ODBC
    data sources for each catalog entry.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, PrimaryAccessPoint, AliasAccessPoints, and AuthenticationType.

.EXAMPLE
    $workObject = Add-ServerCatalogingForLocalDatabase -WorkObject $workObject
    # Catalogs database and aliases with appropriate authentication settings

.NOTES
    Creates multiple catalog entries: one primary (local) and multiple aliases for remote access.
#>
function Add-ServerCatalogingForLocalDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Creating server cataloging for local database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $counter = 1

        if ($WorkObject.AuthenticationType -eq "Kerberos") {
            $db2Commands += "db2 uncatalog database $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 catalog database $($WorkObject.DatabaseName) as $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 catalog system odbc data source $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 catalog user odbc data source $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 terminate"
        }
        else {
            $db2Commands += "db2 uncatalog database $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 catalog database $($WorkObject.DatabaseName) as $($WorkObject.PrimaryAccessPoint.CatalogName)"
            # db2 catalog tcpip node $($CommonParamObject.NodeName) remote $($CommonParamObject.ServerName) server $($CommonParamObject.ServerPort)
            # db2 catalog database $($CommonParamObject.DatabaseName) as $($CommonParamObject.CatalogName) at node $($CommonParamObject.NodeName)


            $db2Commands += "db2 catalog system odbc data source $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 catalog user odbc data source $($WorkObject.PrimaryAccessPoint.CatalogName)"
            $db2Commands += "db2 terminate"
        }

        $counter++
        foreach ($aliasAccessPoint in $($WorkObject.AliasAccessPoints | Where-Object { $_.AccessPointType -eq "Alias" })) {
            $aliasAuth = $aliasAccessPoint.AuthenticationType
            $useKerberosCatalog = ($WorkObject.AuthenticationType -eq "Kerberos" -or $WorkObject.AuthenticationType -eq "KerberosServerEncrypt" -or $aliasAuth -eq "Kerberos" -or $aliasAuth -eq "KerberosServerEncrypt")
            if ($useKerberosCatalog) {
                $db2Commands += "db2 uncatalog database $($aliasAccessPoint.CatalogName)"
                $db2Commands += "db2 catalog database $($WorkObject.DatabaseName) as $($aliasAccessPoint.CatalogName) at node $($aliasAccessPoint.NodeName) AUTHENTICATION KERBEROS TARGET PRINCIPAL db2/$($env:COMPUTERNAME).DEDGE.fk.no@DEDGE.FK.NO"
                $db2Commands += "db2 catalog system odbc data source $($aliasAccessPoint.CatalogName)"
                $db2Commands += "db2 catalog user odbc data source $($aliasAccessPoint.CatalogName)"
                $db2Commands += "db2 terminate"
            }
            else {
                $db2Commands += "db2 uncatalog database $($aliasAccessPoint.CatalogName)"
                $db2Commands += "db2 catalog database $($WorkObject.DatabaseName) as $($aliasAccessPoint.CatalogName) at node $($aliasAccessPoint.NodeName)"
                $db2Commands += "db2 catalog system odbc data source $($aliasAccessPoint.CatalogName)"
                $db2Commands += "db2 catalog user odbc data source $($aliasAccessPoint.CatalogName)"
                $db2Commands += "db2 terminate"
            }
            $counter++
        }
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 list database directory"
        $db2Commands += "db2 terminate"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error creating alias for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}

# function Remove-Db2ServicesFromServiceFile {
#     param(
#         [Parameter(Mandatory = $true)]
#         [PSCustomObject]$WorkObject,
#         [Parameter(Mandatory = $true)]
#         [ValidateSet("Legacy", "PrimaryDb", "FederatedDb", "SslPort", "CompleteRange")]
#         [string]$ServicesMethod
#     )
#     try {
#         Write-LogMessage "Removing existing services from service file for primary database" -Level INFO
#         $servicesPattern = ""
#         if ($ServicesMethod -eq "Legacy") {
#             # Match "DB" followed by any characters (.*) until "25000/tcp"
#             # The .* will match zero or more of any character
#             $servicesPattern = "(DB.*25000/tcp)"
#         }
#         elseif ($ServicesMethod -eq "PrimaryDb") {
#             $servicesPattern = "(DB.*37[0-2][0-9]/tcp | DB.*50000/tcp | DB.*50020/tcp)"
#         }
#         elseif ($ServicesMethod -eq "FederatedDb") {
#             $servicesPattern = "(DB.*50010/tcp | DB.*50030/tcp)"
#         }
#         elseif ($ServicesMethod -eq "SslPort") {
#             $servicesPattern = "(DB.*50050/tcp)"
#         }
#         elseif ($ServicesMethod -eq "CompleteRange") {
#             $servicesPattern = "(DB2C_* | DB.*25000/tcp | DB.*37[0-2][0-9]/tcp | DB.*50(0[0-9][0-9] | 100 / tcp))"
#         }
#         else {
#             Write-LogMessage "Invalid services pattern: $servicesPattern" -Level ERROR
#             throw "Invalid services pattern: $servicesPattern"
#         }
#         if ($servicesPattern -ne "") {
#             $removeServicesScriptParameters = @{
#                 ServicesPattern        = $servicesPattern
#                 ServicesPatternIsRegex = $true
#                 Force                  = $true
#             }
#             Remove-ServicesFromServiceFile @removeServicesScriptParameters
#             Add-Member -InputObject $WorkObject -NotePropertyName "ServicesRemoved$ServicesMethod" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
#             #notepad "$env:SystemRoot\system32\drivers\etc\services"
#         }
#         else {
#             Write-LogMessage "No services to remove" -Level INFO
#         }

#         return $WorkObject
#     }
#     catch {
#         Write-LogMessage "Error removing existing services from service file for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
#         throw $_

#     }
# }

<#
.SYNOPSIS
    Removes all Db2-related services from Windows services file.

.DESCRIPTION
    Removes all Db2 service entries matching pattern: DB2C_*, DB.*25000/tcp, DB.*3718-3729/tcp,
    and DB.*50000-50100/tcp from %SystemRoot%\system32\drivers\etc\services.

.PARAMETER WorkObject
    PSCustomObject to track the operation.

.EXAMPLE
    $workObject = Remove-AllDb2ServicesFromServiceFile -WorkObject $workObject
    # Removes all Db2 services and sets workObject.ServicesRemovedAll timestamp

.NOTES
    Use with caution: removes ALL Db2 services, not just for current database.
#>
function Remove-AllDb2ServicesFromServiceFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing all existing services from service file for primary database" -Level INFO

        $servicesPattern = "(DB2C_* | DB.*25000/tcp | DB.*37[0-2][0-9]/tcp | DB.*50(0[0-9][0-9] | 100 / tcp))"

        $removeServicesScriptParameters = @{
            ServicesPattern        = $servicesPattern
            ServicesPatternIsRegex = $true
            Force                  = $true
        }
        Remove-ServicesFromServiceFile @removeServicesScriptParameters
        Add-Member -InputObject $WorkObject -NotePropertyName "ServicesRemovedAll" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        #notepad "$env:SystemRoot\system32\drivers\etc\services"

        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing existing services from service file for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_

    }
}

<#
.SYNOPSIS
    Removes Db2 services from Windows services file based on access point ports.

.DESCRIPTION
    Removes service entries from %SystemRoot%\system32\drivers\etc\services by building
    a pattern based on ports defined in WorkObject.AccessPoints. Removes legacy port 25000
    and all ports associated with current database access points.

.PARAMETER WorkObject
    PSCustomObject containing AccessPoints with Port properties and DatabaseType.

.EXAMPLE
    $workObject = Remove-Db2ServicesFromServiceFileSimplified -WorkObject $workObject
    # Removes services for ports in access points and stores removed entries

.NOTES
    Stores removed services in WorkObject.RemovedServices for audit trail.
#>
function Remove-Db2ServicesFromServiceFileSimplified {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing existing services from service file for primary database" -Level INFO
        $servicesPattern = ""
        $arrayOfServicesPattern = @()
        $arrayOfServicesPattern += "(DB.*25000/tcp)"
        #find all access points ports related to PrimaryDb
        foreach ($accessPoint in $WorkObject.AccessPoints) {
            if ($accessPoint.AccessPointType -ne "FederatedDb" -and $WorkObject.DatabaseType -eq "PrimaryDb") {
                $arrayOfServicesPattern += "(DB.*$($accessPoint.Port)/tcp)"
            }
            if ($accessPoint.AccessPointType -eq "FederatedDb" -and $WorkObject.DatabaseType -eq "FederatedDb") {
                $arrayOfServicesPattern += "(DB.*$($accessPoint.Port)/tcp)"
            }
        }
        $servicesPattern = $arrayOfServicesPattern -join "| "

        if ($servicesPattern -ne "") {
            $removeServicesScriptParameters = @{
                ServicesPattern        = $servicesPattern
                ServicesPatternIsRegex = $true
                Force                  = $true
            }
            $servicesToRemove = Get-ServicesFromServiceFile -ServicesPattern $servicesPattern -ServicesPatternIsRegex $true
            Remove-ServicesFromServiceFile @removeServicesScriptParameters
            Add-Member -InputObject $WorkObject -NotePropertyName "RemovedServices" -NotePropertyValue $servicesToRemove -Force
            # notepad "$env:SystemRoot\system32\drivers\etc\services"
            # Read-Host "Press Enter to continue"
        }
        else {
            Write-LogMessage "No services to remove" -Level INFO
        }

        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing existing services from service file for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_

    }
}


<#
.SYNOPSIS
    Adds Db2 service entries to Windows services file.

.DESCRIPTION
    Adds TCP/IP service entries to %SystemRoot%\system32\drivers\etc\services for Db2
    connectivity. Adds service names and ports from access points based on the method:
    - InitializeDb2Services: Adds temporary DB2C_TEMP on port 25000
    - PrimaryDb: Adds primary and alias access point services
    - FederatedDb: Adds federated instance service
    - SslPort: Adds SSL-enabled service

.PARAMETER WorkObject
    PSCustomObject containing PrimaryAccessPoint and AliasAccessPoints with service definitions.

.PARAMETER ServicesMethod
    Determines which services to add (InitializeDb2Services, PrimaryDb, FederatedDb, SslPort, CompleteRange).

.EXAMPLE
    $workObject = Add-Db2ServicesToServiceFile -WorkObject $workObject -ServicesMethod "PrimaryDb"
    # Adds primary and alias service entries to services file
#>
function Add-Db2ServicesToServiceFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [ValidateSet("InitializeDb2Services", "Legacy", "PrimaryDb", "FederatedDb", "SslPort", "CompleteRange")]
        [string]$ServicesMethod
    )
    try {
        Write-LogMessage "Adding services to service file for database $($WorkObject.DatabaseName)" -Level INFO
        $servicesToAdd = @()
        if ($ServicesMethod -eq "InitializeDb2Services") {
            $servicesToAdd += [PSCustomObject]@{
                ServiceName = "DB2C_TEMP"
                Port        = 25000
                Protocol    = "tcp"
                Description = "Db2 service name for $($WorkObject.DatabaseName)"
            }
        }
        elseif ($ServicesMethod -eq "PrimaryDb") {
            $servicesToAdd += [PSCustomObject]@{
                ServiceName = $WorkObject.PrimaryAccessPoint.ServiceName
                Port        = $WorkObject.PrimaryAccessPoint.Port
                Protocol    = "tcp"
                Description = "Db2 service name for $($WorkObject.DatabaseName)"
            }

            foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
                $servicesToAdd += [PSCustomObject]@{
                    ServiceName = $aliasAccessPoint.ServiceName
                    Port        = $aliasAccessPoint.Port
                    Protocol    = "tcp"
                    Description = "Db2 service name for $($WorkObject.DatabaseName)"
                }
            }
        }
        elseif ($ServicesMethod -eq "FederatedDb") {
            $servicesToAdd += [PSCustomObject]@{
                ServiceName = $WorkObject.PrimaryAccessPoint.ServiceName
                Port        = $WorkObject.PrimaryAccessPoint.Port
                Protocol    = "tcp"
                Description = "Db2 service name for $($WorkObject.DatabaseName)"
            }
        }
        elseif ($ServicesMethod -eq "SslPort") {
            $servicesToAdd += [PSCustomObject]@{
                ServiceName = $WorkObject.PrimaryAccessPoint.ServiceName
                Port        = $WorkObject.PrimaryAccessPoint.Port
                Protocol    = "tcp"
                Description = "Db2 service name for $($WorkObject.DatabaseName)"
            }
        }
        else {
            Write-LogMessage "Invalid services method: $ServicesMethod" -Level ERROR
            throw "Invalid services method: $ServicesMethod"
        }
        if ($servicesToAdd.Count -gt 0) {
            $null = Add-ServicesToServiceFile -Services $servicesToAdd
            # notepad "$env:SystemRoot\system32\drivers\etc\services"
            # Read-Host "Press Enter to continue"
        }
        #foreach ($serviceToAdd in $servicesToAdd) {
        #     Write-LogMessage "Adding service $serviceToAdd to service file" -Level INFO
        #     Add-Content -Path "$env:SystemRoot\system32\drivers\etc\services" -Value "$($serviceToAdd.ServiceName.PadRight(16)) $($($serviceToAdd.Port.ToString() + "/tcp").PadRight(36)) #$($serviceToAdd.Description)"
        # }

        Add-Member -InputObject $WorkObject -NotePropertyName "ServicesAdded$ServicesMethod" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        # notepad "$env:SystemRoot\system32\drivers\etc\services"
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding services to service file for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}




<#
.SYNOPSIS
    Retrieves Db2 service entries from Windows services file.

.DESCRIPTION
    Queries %SystemRoot%\system32\drivers\etc\services for Db2-related entries based on
    the specified method. Builds regex patterns to match service entries by port ranges.

.PARAMETER WorkObject
    PSCustomObject to track the operation.

.PARAMETER ServicesMethod
    Determines which services to retrieve: Legacy (25000), PrimaryDb (3718-3729, 50000, 50020),
    FederatedDb (50010, 50030), SslPort (50050), or CompleteRange (all Db2 services).

.EXAMPLE
    $workObject = Get-Db2ServicesToServiceFile -WorkObject $workObject -ServicesMethod "PrimaryDb"
    # Retrieves primary database service entries
#>
function Get-Db2ServicesToServiceFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Legacy", "PrimaryDb", "FederatedDb", "SslPort", "CompleteRange")]
        [string]$ServicesMethod    )
    try {
        Write-LogMessage "Removing existing services from service file for primary database" -Level INFO
        $servicesPattern = ""
        if ($ServicesMethod -eq "Legacy") {
            # Match "DB" followed by any characters (.*) until "25000/tcp"
            # The .* will match zero or more of any character
            $servicesPattern = "(DB.*25000/tcp)"
        }
        elseif ($ServicesMethod -eq "PrimaryDb") {
            $servicesPattern = "(DB.*37[0-2][0-9]/tcp|DB.*50000/tcp|DB.*50020/tcp)"
        }
        elseif ($ServicesMethod -eq "FederatedDb") {
            $servicesPattern = "(DB.*50010/tcp|DB.*50030/tcp)"
        }
        elseif ($ServicesMethod -eq "SslPort") {
            $servicesPattern = "(DB.*50050/tcp)"
        }
        elseif ($ServicesMethod -eq "CompleteRange") {
            $servicesPattern = "(DB2C_*|DB.*25000/tcp|DB.*37[0-2][0-9]/tcp|DB.*50(0[0-9][0-9]|100/tcp))"
        }
        else {
            Write-LogMessage "Invalid services pattern: $servicesPattern" -Level ERROR
            throw "Invalid services pattern: $servicesPattern"
        }
        if ($servicesPattern -ne "") {
            $getServicesScriptParameters = @{
                ServicesPattern        = $servicesPattern
                ServicesPatternIsRegex = $true
                Force                  = $true
            }
            Get-ServicesFromServiceFile @getServicesScriptParameters
            Add-Member -InputObject $WorkObject -NotePropertyName "ServicesGet$ServicesMethod" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
            #notepad "$env:SystemRoot\system32\drivers\etc\services"
        }
        else {
            Write-LogMessage "No services to get" -Level INFO
        }

        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing existing services from service file for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_

    }
}



<#
.SYNOPSIS
    Removes existing Windows Firewall rules for Db2 access points.

.DESCRIPTION
    Removes all TCP firewall rules matching the ports defined in AliasAccessPoints.
    Searches through all firewall rules and removes those with matching port and TCP protocol.

.PARAMETER WorkObject
    PSCustomObject containing AliasAccessPoints with Port properties.

.EXAMPLE
    $workObject = Remove-ExistingFirewallRules -WorkObject $workObject
    # Removes firewall rules for all alias access point ports

.NOTES
    Stores removal messages in WorkObject.FirewallRulesRemoved and FirewallRulesRemovedMessages.
#>
function Remove-ExistingFirewallRules {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing existing firewall rules for database $($WorkObject.DatabaseName)" -Level INFO

        # Remove rules by port
        $allRemovedRulesMessages = @()
        foreach ($aliasAccessPoint in $($WorkObject.AliasAccessPoints | Where-Object { $_.CatalogName })) {
            # Get firewall rules and filter by port and TCP protocol using Get-NetFirewallPortFilter
            # Get all firewall rules first
            $allRulesToRemoveFirewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue

            # Filter rules by checking port and protocol for each rule
            $rulesToRemove = @()
            foreach ($rule in $allRulesToRemoveFirewallRules) {
                $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
                if ($portFilter.LocalPort -eq $aliasAccessPoint.Port -and $portFilter.Protocol -eq "TCP") {
                    $rulesToRemove += $rule
                }
            }

            if ($rulesToRemove.Count -gt 0) {
                $allRemovedRulesMessages += "Removed TCP firewall rule $($rulesToRemove.DisplayName) for port $($aliasAccessPoint.Port)"
                $rulesToRemove | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            }
        }

        $allRemovedRulesString = $allRemovedRulesMessages | Format-Table -AutoSize | Out-String
        Write-LogMessage "Firewall rules removed: $allRemovedRulesString" -Level INFO

        Add-Member -InputObject $WorkObject -NotePropertyName "FirewallRulesRemoved" -NotePropertyValue $allRemovedRulesMessages -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "FirewallRulesRemovedMessages" -NotePropertyValue $($allRemovedRulesMessages -join "`n") -Force
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing firewall rules for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Creates Windows Firewall rules for Db2 remote access.

.DESCRIPTION
    Creates inbound TCP firewall rules for all access points (primary and aliases for PrimaryDb,
    or primary only for FederatedDb). Rules are named "DB2 Remote Access <CatalogName>".
    Updates existing rules if port/protocol doesn't match.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseType, PrimaryAccessPoint, and AliasAccessPoints.

.EXAMPLE
    $workObject = Add-FirewallRules -WorkObject $workObject
    # Creates firewall rules for all access point ports

.NOTES
    Stores created rules in WorkObject.FirewallRulesAdded. Verifies rules after creation.
#>
function Add-FirewallRules {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Adding firewall rules for database $($WorkObject.DatabaseName)" -Level INFO

        $accessPoints = @()
        if ($WorkObject.DatabaseType -eq "PrimaryDb") {
            $accessPoints += $WorkObject.PrimaryAccessPoint
            $accessPoints += $WorkObject.AliasAccessPoints
        }
        elseif ($WorkObject.DatabaseType -eq "FederatedDb") {
            $accessPoints += $WorkObject.PrimaryAccessPoint
        }

        $activeRules = @()
        # Add rules for alias access points
        foreach ($aliasAccessPoint in $accessPoints) {
            $portFilter = Get-NetFirewallPortFilter  | Where-Object -Property LocalPort -eq $aliasAccessPoint.Port | Where-Object -Property Protocol -eq TCP

            $displayName = "DB2 Remote Access $($aliasAccessPoint.CatalogName)"
            $existingRule = $portFilter | Get-NetFirewallRule
            if ($existingRule) {
                if ($existingRule.DisplayName -ne $displayName -or $existingRule.LocalPort -ne $aliasAccessPoint.Port -or $existingRule.Protocol -ne "TCP") {
                    Remove-NetFirewallRule -DisplayName $existingRule.DisplayName -ErrorAction SilentlyContinue
                    $null = New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $aliasAccessPoint.Port -ErrorAction SilentlyContinue
                }
                $activeRules += Get-NetFirewallRule -DisplayName $displayName
            }
            else {
                $null = New-NetFirewallRule -DisplayName "DB2 Remote Access $($aliasAccessPoint.CatalogName)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $aliasAccessPoint.Port -ErrorAction SilentlyContinue
                $activeRules += Get-NetFirewallRule -DisplayName "DB2 Remote Access $($aliasAccessPoint.CatalogName)"
            }
        }

        # Verify rules were added
        Write-LogMessage "Verifying firewall rules..." -Level INFO
        $rulesString = $activeRules | Format-Table -AutoSize | Out-String
        Write-LogMessage "Firewall rules added: $rulesString" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "FirewallRulesAdded" -NotePropertyValue $activeRules -Force
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding firewall rules for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}


<#
.SYNOPSIS
    Configures database and instance settings for authentication and connectivity.

.DESCRIPTION
    Sets comprehensive database configurations based on DatabaseType:
    - For PrimaryDb: Configures Kerberos authentication, TCPIP communication, service name
    - For FederatedDb: Configures NTLM authentication
    - Common settings: EXTBL_LOCATION, LOG_DDL_STMTS, SELF_TUNING_MEM, AUTO_MAINT
    - Updates Z_AVDTAB.DATABASENAVN for FKM application
    - Grants DBADM/DATAACCESS/ACCESSCTRL to DB2ADMNS and current user

.PARAMETER WorkObject
    PSCustomObject containing DatabaseType, DatabaseName, InstanceName, Application, and RemotePort.

.EXAMPLE
    $workObject = Add-DatabaseConfigurations -WorkObject $workObject
    # Applies standard database configurations

.NOTES
    Sets WorkObject.DatabaseConfigurationsSet timestamp. Restarts instance to apply changes.
#>
function Add-DatabaseConfigurations {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Setting authentication for database $($WorkObject.DatabaseName)" -Level INFO

        $db2Commands = @()

        if ($WorkObject.DatabaseType -eq "PrimaryDb") {
            $db2Commands = @()
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2set -g DB2ADMINSERVER=$env:COMPUTERNAME"
            $db2Commands += "db2set -g DB2COMM=TCPIP"
            $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2COMM=TCPIP"
            $db2Commands += "db2 update dbm cfg using SVCENAME $($WorkObject.RemotePort)"
            $db2Commands += "db2 update dbm cfg using DFTDBPATH $($(Get-PrimaryDb2DataDisk))"
            $db2Commands += "db2 update dbm cfg using SRVCON_PW_PLUGIN NULL"
            $db2Commands += "db2 update dbm cfg using TRUST_CLNTAUTH CLIENT"
            if ($WorkObject.UseNewConfigurations) {
                Write-LogMessage "UseNewConfigurations: Setting KRB_SERVER_ENCRYPT authentication (allows both Kerberos SSO and JDBC encrypted password)" -Level INFO
                $db2Commands += "db2 update dbm cfg using AUTHENTICATION KRB_SERVER_ENCRYPT"
                $db2Commands += "db2 update dbm cfg using SRVCON_AUTH KRB_SERVER_ENCRYPT"
                $db2Commands += "db2 update dbm cfg using ALTERNATE_AUTH_ENC AES_ONLY"
            }
            else {
                Write-LogMessage "Configuring Kerberos authentication" -Level INFO
                $db2Commands += "db2 update dbm cfg using AUTHENTICATION KERBEROS"
                $db2Commands += "db2 update dbm cfg using SRVCON_AUTH KERBEROS"
            }
            $db2Commands += "db2 update dbm cfg using CATALOG_NOAUTH NO"
            $db2Commands += "db2 update dbm cfg using TRUST_ALLCLNTS YES"
            $db2Commands += "db2 update dbm cfg using SRVCON_GSSPLUGIN_LIST IBMkrb5"
            $db2Commands += "db2 update dbm cfg using SYSADM_GROUP DB2ADMNS"
            $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
            $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
            $db2Commands += "db2 grant dbadm on database to group DB2ADMNS"
            $db2Commands += "db2 grant dataaccess on database to group DB2ADMNS"
            $db2Commands += "db2 grant accessctrl on database to group DB2ADMNS"
            $db2Commands += "db2 terminate"
            $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
            $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
            $db2Commands += "db2 grant dbadm on database to user $($env:USERNAME)"
            $db2Commands += "db2 grant dataaccess on database to user $($env:USERNAME)"
            $db2Commands += "db2 grant accessctrl on database to user $($env:USERNAME)"
            $db2Commands += "db2 terminate"
            $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using EXTBL_LOCATION $($(Get-PrimaryDb2DataDisk))"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using LOG_DDL_STMTS YES"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
            $db2Commands += "db2 terminate"
            $db2Commands += "db2 update dbm cfg using DFTDBPATH $($(Get-PrimaryDb2DataDisk))"
        }
        elseif ($WorkObject.DatabaseType -eq "FederatedDb") {
            Write-LogMessage "Configuring NTLM authentication" -Level INFO
            $db2Commands = @()
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2set -g DB2ADMINSERVER=$env:COMPUTERNAME"
            $db2Commands += "db2set -g DB2COMM=TCPIP"
            $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2COMM=TCPIP"
            $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
            $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
            $db2Commands += "db2 grant dbadm on database to user $($env:USERNAME)"
            $db2Commands += "db2 grant dataaccess on database to user $($env:USERNAME)"
            $db2Commands += "db2 grant accessctrl on database to user $($env:USERNAME)"
            $db2Commands += "db2 terminate"
            $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using EXTBL_LOCATION $($(Get-PrimaryDb2DataDisk))"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using LOG_DDL_STMTS YES"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
            $db2Commands += "db2 terminate"
            $db2Commands += "db2 update dbm cfg using DFTDBPATH $($(Get-PrimaryDb2DataDisk))"
        }
        else {
            Write-LogMessage "Authentication type not supported $($WorkObject.PrimaryAccessPoint.AccessPointType)" -Level ERROR
            throw "Database Type not supported"
        }




        # $db2Commands += "db2 alter bufferpool BIGTAB       size 10000"
        # $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
        $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using AUTO_MAINT OFF"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        if ($WorkObject.Application -eq "FKM" -and $WorkObject.InstanceName -eq "DB2") {
            #$db2Commands += "DB2 UPDATE DBM.Z_AVDTAB SET DATABASENAVN = '$($WorkObject.DatabaseName)' WHERE DATABASENAVN = 'BASISPRO'"
            $db2Commands += "db2 update DBM.Z_AVDTAB SET DATABASENAVN = '$($WorkObject.DatabaseName)'"
            $db2Commands += "db2 commit work"
        }

        $db2Commands += "db2 terminate"
        $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2_OVERRIDE_BPF="
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"


        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"
        $db2Commands += "db2 get dbm cfg | findstr /i SVCENAME"
        $db2Commands += "db2 get dbm cfg | findstr /i SRVCON_PW_PLUGIN"
        $db2Commands += "db2 get dbm cfg | findstr /i TRUST_CLNTAUTH"
        $db2Commands += "db2 get dbm cfg | findstr /i AUTHENTICATION"
        $db2Commands += "db2 get dbm cfg | findstr /i SRVCON_AUTH"
        $db2Commands += "db2 get dbm cfg | findstr /i CATALOG_NOAUTH"
        $db2Commands += "db2 get dbm cfg | findstr /i TRUST_ALLCLNTS"
        $db2Commands += "db2 get dbm cfg | findstr /i SRVCON_GSSPLUGIN_LIST"
        $db2Commands += "db2 get dbm cfg | findstr /i SYSADM_GROUP"
        $db2Commands += "db2 get dbm cfg | findstr /i DFTDBPATH"
        $db2Commands += "db2 get db cfg for $($WorkObject.DatabaseName) | findstr /i EXTBL_LOCATION"
        $db2Commands += "db2 get db cfg for $($WorkObject.DatabaseName) | findstr /i LOG_DDL_STMTS"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseConfigurationsSet" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error adding database configurations for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}
function Get-CommandsForDatabasePermissions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )
    $db2Commands = @()
    $db2Commands += "db2 grant bindadd on database to user $UserName"
    $db2Commands += "db2 grant connect on database to user $UserName"
    $db2Commands += "db2 grant createtab on database to user $UserName"
    $db2Commands += "db2 grant dbadm on database to user $UserName"
    $db2Commands += "db2 grant implicit_schema on database to user $UserName"
    $db2Commands += "db2 grant load on database to user $UserName"
    $db2Commands += "db2 grant quiesce_connect on database to user $UserName"
    $db2Commands += "db2 grant secadm on database to user $UserName"
    $db2Commands += "db2 grant sqladm on database to user $UserName"
    $db2Commands += "db2 grant wlmadm on database to user $UserName"
    $db2Commands += "db2 grant explain on database to user $UserName"
    $db2Commands += "db2 grant dataaccess on database to user $UserName"
    $db2Commands += "db2 grant accessctrl on database to user $UserName"
    $db2Commands += "db2 grant create_secure_object on database to user $UserName"
    $db2Commands += "db2 grant create_external_routine on database to user $UserName"
    $db2Commands += "db2 grant create_not_fenced_routine on database to user $UserName"
    return $db2Commands
}
<#
.SYNOPSIS
    Sets comprehensive database permissions for admin users and groups.

.DESCRIPTION
    Grants database-level permissions to admin users from WorkObject.AdminUsers:
    - Sets SYSADM_GROUP, SYSCTRL_GROUP, SYSMAINT_GROUP, SYSMON_GROUP to DB2ADMNS
    - Grants DBADM, DATAACCESS, ACCESSCTRL, CONNECT, LOAD, and other privileges
    - Skips duplicate grants for DbUser (service account) and current user
    - Grants permissions to $env:USERNAME

.PARAMETER WorkObject
    PSCustomObject containing AdminUsers, DatabaseName, InstanceName, and optionally DbUser.

.EXAMPLE
    $workObject = Set-DatabasePermissions -WorkObject $workObject
    # Grants comprehensive database permissions to all admin users

.NOTES
    Critical for post-restore operations. Ensures admin users have full database access.
#>
function Set-DatabasePermissions {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Setting database permissions for $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)

        # Set admin groups (no database connection required)
        if ($WorkObject.UseNewConfigurations) {
            if (-not [string]::IsNullOrEmpty($WorkObject.RemotePort)) {
                $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2COMM=TCPIP"
            }
        } else {
            $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2COMM=TCPIP"
        }
        $db2Commands += "db2 update dbm cfg using sysadm_group `"DB2ADMNS`""
        $db2Commands += "db2 update dbm cfg using sysctrl_group `"DB2ADMNS`""
        $db2Commands += "db2 update dbm cfg using sysmaint_group `"DB2ADMNS`""
        $db2Commands += "db2 update dbm cfg using sysmon_group `"DB2ADMNS`""

        # Connect to database for granting permissions.
        # Try service account first, then fall back to Windows auth
        # (after restore, DbUser may lack CONNECT until grants are applied).
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"

        foreach ($user in $WorkObject.AdminUsers) {
            if ([string]::IsNullOrEmpty($user)) {
                continue
            }

            # Skip granting permissions if the current user matches the database service account (DbUser)
            if (-not [string]::IsNullOrEmpty($WorkObject.DbUser) -and $user.ToLower().Trim() -eq $WorkObject.DbUser.ToLower().Trim()) {
                continue
            }

            # Skip granting permissions if an admin user matches the running user — on DB2 servers,
            # the running user is the instance owner (SYSADM) and granting to self produces SQL0554N.
            if ($user.ToLower().Trim() -eq $env:USERNAME.ToLower().Trim()) {
                continue
            }
            $db2Commands += $(Get-CommandsForDatabasePermissions -UserName $user)
        }

        # Environment specific permissions
        $db2Commands += "db2 terminate"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
        if ($WorkObject.UseNewConfigurations) {
            # On DB2 servers, $env:USERNAME is always the instance owner (SYSADM) who already
            # has all privileges. Granting to self produces SQL0554N. Skip entirely.
        } else {
            $db2Commands += $(Get-CommandsForDatabasePermissions -UserName $env:USERNAME)
        }
        $db2Commands += "db2 terminate"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error setting permissions for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


# Alternative function names considered but not used:
# - Restart-Db2AndActivateDb
# - Start-Db2AndActivateDb
# - Reset-Db2AndActivateDb
# - Initialize-Db2AndActivateDb
# - Invoke-Db2RestartAndActivate
# - Set-Db2RestartAndActivate
# - Update-Db2AndActivateDb
# - Enable-Db2AndActivateDb
# - Restart-Db2WithDatabaseActivation
# - Start-Db2WithDatabaseActivation
<#
.SYNOPSIS
    Restarts Db2 instance and activates the database.

.DESCRIPTION
    Performs full instance restart:
    - db2stop force
    - db2start
    - db2 activate db <DatabaseName>

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Restart-Db2AndActivateDb -WorkObject $workObject
    # Forces instance restart and activates database

.NOTES
    Use when configuration changes require instance restart to take effect.
#>
function Restart-Db2AndActivateDb {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Setting database permissions for $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error restarting and activating database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Starts Db2 instance and activates the database.

.DESCRIPTION
    Starts instance if stopped and activates database:
    - db2start
    - db2 activate db <DatabaseName>

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Start-Db2AndActivateDb -WorkObject $workObject
    # Starts instance and activates database

.NOTES
    Use when instance is stopped but no restart is needed.
#>
function Start-Db2AndActivateDb {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Setting database permissions for $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error restarting and activating database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Retrieves all federation wrappers from a database.

.DESCRIPTION
    Queries SYSCAT.WRAPPERS to get all federation wrappers (e.g., DRDA wrapper for DB2 connections).
    Stores results in WorkObject.AllWrappers.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Get-AllWrappers -WorkObject $workObject
    # Populates workObject.AllWrappers with wrapper information

.NOTES
    Used for federation diagnostics and setup verification.
#>
function Get-AllWrappers {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Getting all wrappers for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
        $db2Commands += "db2 select * from syscat.wrappers"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        $result = Get-SelectResult -SelectOutput $output -ReturnArray
        Add-Member -InputObject $WorkObject -NotePropertyName "AllWrappers" -NotePropertyValue $result -Force
    }
    catch {
        Write-LogMessage "Error getting all wrappers for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Retrieves federation server links matching hostname and port.

.DESCRIPTION
    Queries SYSCAT.SERVERS and SYSCAT.SERVEROPTIONS to find server links where HOST
    contains the specified ServerName and PORT equals the specified Port. Stores results
    in WorkObject.AllServers.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.PARAMETER ServerName
    Hostname to search for in server link HOST option (case-insensitive partial match).

.PARAMETER Port
    Port number to match exactly in server link PORT option.

.EXAMPLE
    $workObject = Get-AllServers -WorkObject $workObject -ServerName "fkmprd-db" -Port "3718"
    # Finds server links pointing to fkmprd-db on port 3718

.NOTES
    Used to identify existing federation server links before dropping/recreating.
#>
function Get-AllServers {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        [Parameter(Mandatory = $true)]
        [string]$Port
    )
    try {
        Write-LogMessage "Getting all servers for database $($WorkObject.DatabaseName)" -Level INFO 
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
        
        #$db2Commands += "db2 select SERVERNAME from syscat.servers x join syscat.serveroptions Y on .SERVERNAME = syscat.serveroptions.SERVERNAME"
        $db2Commands += "db2 select X.SERVERNAME FROM syscat.servers x JOIN syscat.serveroptions y ON x.SERVERNAME = y.SERVERNAME JOIN syscat.serveroptions z ON x.SERVERNAME = z.SERVERNAME WHERE y.OPTION = 'HOST' AND LOWER(y.setting) LIKE '%$($ServerName)%' AND Z.OPTION = 'PORT' AND Z.setting = '$($Port)' AND y.SERVERNAME = z.SERVERNAME"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        $result = Get-SelectResult -SelectOutput $output -ReturnArray
        Add-Member -InputObject $WorkObject -NotePropertyName "AllServers" -NotePropertyValue $result -Force
    }
    catch {
        Write-LogMessage "Error getting all servers for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
    

<#
.SYNOPSIS
    Retrieves federation user mapping options for server links.

.DESCRIPTION
    Queries SYSCAT.USEROPTIONS to get user mapping configuration for federation servers.
    Optionally filters by ServerName. Appends results to WorkObject.AllUserOptions.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.PARAMETER ServerName
    Optional server name to filter results.

.EXAMPLE
    $workObject = Get-AllUserOptions -WorkObject $workObject
    # Retrieves all user mapping options

.EXAMPLE
    $workObject = Get-AllUserOptions -WorkObject $workObject -ServerName "DB2LNK"
    # Retrieves user options for specific server link

.NOTES
    Results are appended to existing AllUserOptions array if it exists.
#>
function Get-AllUserOptions {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$ServerName
    )
    try {
        Write-LogMessage "Getting all user options for database $($WorkObject.DatabaseName) on server $($ServerName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
        if (-not [string]::IsNullOrEmpty($ServerName)) {
            $db2Commands += "db2 select * from syscat.useroptions where SERVERNAME = '$($ServerName)'"
        }
        else {
            $db2Commands += "db2 select * from syscat.useroptions"
        }
        $db2Commands += "db2 select * from syscat.useroptions"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        $result = Get-SelectResult -SelectOutput $output -ReturnArray $true
        if ($WorkObject.AllUserOptions -is [array]) {
            $WorkObject.AllUserOptions += $result
        }
        else {
            Add-Member -InputObject $WorkObject -NotePropertyName "AllUserOptions" -NotePropertyValue $result -Force
        }
    }
    catch {
        Write-LogMessage "Error getting all user options for database $($WorkObject.DatabaseName) on server $($ServerName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Enables federation and creates server link for federated database.

.DESCRIPTION
    Configures federated database to link to primary database:
    - Enables FEDERATED=YES on both primary and federated instances
    - Drops existing DRDA wrapper and server link
    - Creates new DRDA wrapper
    - Creates server link with DB2/LUW connection to primary database
    - Creates user mapping for PUBLIC with remote credentials

.PARAMETER WorkObject
    PSCustomObject containing LinkedPrimaryDatabaseName, LinkedPrimaryInstanceName,
    LinkedDatabaseName, LinkedServerName, LinkedDatabasePort, LinkedDbFedUser, LinkedDbFedPassword.

.EXAMPLE
    $workObject = Add-FederationSupport -WorkObject $workObject
    # Enables federation and creates server link

.NOTES
    Restarts both instances. Server link named from WorkObject.ServerLinkName (e.g., "DB2LNK").
#>
function Add-FederationSupport {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Adding federation support for database $($WorkObject.DatabaseName)" -Level INFO

        # $WorkObject = Get-AllWrappers -WorkObject $WorkObject
        # $WorkObject = Get-AllServers -WorkObject $WorkObject
        # foreach ($server in $WorkObject.AllServers) {
        #     $WorkObject = Get-AllUserOptions -WorkObject $WorkObject -ServerName $server.SERVERNAME
        # }


        $db2Commands = @()


        # if ($WorkObject.FederationType -eq "Standard") {
        #     $WorkObject = Add-LoggingToDatabase -WorkObject $WorkObject
        #     if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        # }


        # set DB2INSTANCE=DB2FED
        # db2stop force
        # db2start
        # db2 activate db XINLTST
        # db2 update dbm cfg using FEDERATED YES
        # db2 connect to XINLTST
        # db2 "DROP WRAPPER DRDA"
        # db2 "CREATE WRAPPER DRDA"



        
        $db2Commands += "set DB2INSTANCE=$($WorkObject.LinkedPrimaryInstanceName)"
        $db2Commands += "db2start"
        $db2Commands += "db2 update dbm cfg using FEDERATED YES"
        $db2Commands += "db2 terminate"
        $db2Commands += "db2 activate db $($WorkObject.LinkedPrimaryDatabaseName)"

        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"
        $db2Commands += "db2 update dbm cfg using FEDERATED YES"
        $db2Commands += "db2 terminate"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)

        # $WorkObject = Get-AllServers -WorkObject $WorkObject -ServerName $WorkObject.LinkedServerName -Port $WorkObject.LinkedDatabasePort
        # foreach ($server in $WorkObject.AllServers) {
        #     $WorkObject = Get-AllUserOptions -WorkObject $WorkObject -ServerName $server.SERVERNAME
        #     $db2Commands += "db2 `"DROP USER MAPPING FOR PUBLIC SERVER $($server.SERVERNAME)`" >nul 2>&1"
        #     $db2Commands += "db2 `"DROP SERVER $($server.SERVERNAME)`" >nul 2>&1"
        # }

        # $WorkObject = Get-AllWrappers -WorkObject $WorkObject
        # foreach ($wrapper in $WorkObject.AllWrappers) {
        #     $db2Commands += "db2 `"DROP WRAPPER $($wrapper.WRAPNAME)`" >nul 2>&1"
        # }


        # Temporary drop server link
        $db2Commands += "db2 quiesce database immediate force connections"
        $db2Commands += "db2 `"DROP USER MAPPING FOR PUBLIC SERVER $($WorkObject.LinkedPrimaryDatabaseName)`" >nul 2>&1"
        $db2Commands += "db2 `"DROP SERVER $($WorkObject.LinkedPrimaryDatabaseName)`" >nul 2>&1"
        $db2Commands += "db2 `"DROP WRAPPER DRDA`" >nul 2>&1"

        $db2Commands += "db2 `"DROP USER MAPPING FOR PUBLIC SERVER $($WorkObject.ServerLinkName)`" >nul 2>&1"
        $db2Commands += "db2 `"DROP SERVER $($WorkObject.ServerLinkName)`" >nul 2>&1"
        $db2Commands += "db2 `"DROP WRAPPER DRDA`" >nul 2>&1"
        $db2Commands += "db2 `"CREATE WRAPPER DRDA`""
        $db2Commands += "db2 `"CREATE SERVER $($WorkObject.ServerLinkName) TYPE DB2/LUW VERSION '12.1' WRAPPER DRDA AUTHORIZATION \`"$($WorkObject.LinkedDbFedUser)\`" PASSWORD \`"$($WorkObject.LinkedDbFedPassword)\`" OPTIONS (DBNAME '$($WorkObject.LinkedDatabaseName)', HOST '$($WorkObject.LinkedServerName).DEDGE.fk.no', PORT '$($WorkObject.LinkedDatabasePort)')`""
        $db2Commands += "db2 `"CREATE USER MAPPING FOR PUBLIC SERVER $($WorkObject.ServerLinkName) OPTIONS (REMOTE_AUTHID 'DB2NT', REMOTE_PASSWORD 'ntdb2')`""

        $db2Commands += "db2 commit work"
        $db2Commands += "db2 unquiesce database"

        $db2Commands += "db2 connect reset"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"

        Write-LogMessage "Commands for adding federation support: $($db2Commands -join "`n")" -Level INFO
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        # -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error setting authentication for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Retrieves database configuration parameters from Db2.

.DESCRIPTION
    Executes 'db2 get db cfg' to retrieve all database-level configuration parameters
    and parses the output into structured configuration objects. Captures settings like
    log paths, buffer pool sizes, code page, territory, and various database options.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName to query configuration for.

.EXAMPLE
    $workObject = Get-DatabaseConfiguration -WorkObject $workObject
    # Retrieves and stores database configuration in WorkObject.DatabaseConfiguration

.NOTES
    The configuration is stored as an array of objects with Key and Value properties.
    Handles both Norwegian and English language output from Db2.
#>
function Get-DatabaseConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Getting database configuration from db cfg for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "REM Get all DB2 database configuration from db cfg for $($WorkObject.DatabaseName)"
        $db2Commands += "db2 get db cfg for $($WorkObject.DatabaseName)"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output


        # $startIndex = $output.ToLower().IndexOf("databasekonfigurasjon for databasen")
        # if ($startIndex -ge 0) {
        #     $output = $output.Substring($startIndex)
        # }
        # $configObjectArray = @()
        # foreach ($line in $($output -split "`n") ) {
        #     $key = $null
        #     $value = $null
        #     $keyTemp = $null
        #     $valueTemp = $null
        #     $posLastEqual = $line.LastIndexOf("=")
        #     if ($posLastEqual -eq -1) {
        #         continue
        #     }
        #     $keyTemp = $line.Substring(0, $posLastEqual).Trim()
        #     $valueTemp = $line.Substring($posLastEqual + 1).Trim()
        #     if ($line -like "*Utgavenivå på databasekonfigurasjonen*=") {
        #         $key = "DB_CONFIG_VERSION_LEVEL"
        #     }
        #     elseif ($line -like "*Utgavenivå på databasen*=") {
        #         $key = "DB_VERSION_LEVEL"
        #     }
        #     elseif ($line -like "*Oppdatering til databasenivå venter*=") {
        #         $key = "DB_UPGRADE_PENDING"
        #     }
        #     elseif ($line -like "*Databaseområde*=") {
        #         $key = "DB_AREA"
        #     }
        #     elseif ($line -like "*Kodesett for database (code page)*=") {
        #         $key = "DB_CODEPAGE"
        #     }
        #     elseif ($line -like "*Kodesett for database (code set)*=") {
        #         $key = "DB_CODESET"
        #     }
        #     elseif ($line -like "*Land-/områdekode for database*=") {
        #         $key = "DB_TERRITORY"
        #     }
        #     elseif ($line -like "*Rangfølge for database*=") {
        #         $key = "DB_COLLATION"
        #     }
        #     elseif ($line -like "*Number-kompatibilitet*=") {
        #         $key = "DB_NUMBER_COMPATIBILITY"
        #     }
        #     elseif ($line -like "*Varchar2-kompatibilitet*=") {
        #         $key = "DB_VARCHAR2_COMPATIBILITY"
        #     }
        #     elseif ($line -like "*Datokompatibilitet*=") {
        #         $key = "DB_DATE_COMPATIBILITY"
        #     }
        #     elseif ($line -like "*Sidestørrelse for database*=") {
        #         $key = "DB_PAGESIZE"
        #     }
        #     elseif ($line -like "*Begrens tilgang*=") {
        #         $key = "DB_ACCESS_RESTRICTION"
        #     }
        #     elseif ($line -like "*Reservekopiering venter*=") {
        #         $key = "DB_BACKUP_PENDING"
        #     }
        #     elseif ($line -like "*Alle iverksatte transaksjoner er skrevet til disk*=") {
        #         $key = "DB_ALL_COMMITTED_TO_DISK"
        #     }
        #     elseif ($line -like "*Fremlengs rulling venter*=") {
        #         $key = "DB_FORWARD_RECOVERY_PENDING"
        #     }
        #     elseif ($line -like "*Gjenoppretting venter*=") {
        #         $key = "DB_RECOVERY_PENDING"
        #     }
        #     elseif ($line -like "*Oppgradering venter*=") {
        #         $key = "DB_UPGRADE_WAITING"
        #     }
        #     elseif ($line -like "*Filtildeling av flere sider er aktivert*=") {
        #         $key = "DB_MULTIPAGE_ALLOCATION"
        #     }
        #     elseif ($line -like "*Loggbevaring for gjenopprettingsstatus*=") {
        #         $key = "DB_LOG_RETAIN_STATUS"
        #     }
        #     elseif ($line -like "*Status for brukerutgang for logging*=") {
        #         $key = "DB_USER_EXIT_STATUS"
        #     }
        #     elseif ($line -like "*Standard antall containere*=") {
        #         $key = "DB_DEFAULT_NUM_CONTAINERS"
        #     }
        #     elseif ($line -like "*Første aktive loggfil*=") {
        #         $key = "DB_FIRST_ACTIVE_LOG"
        #     }
        #     elseif ($line -like "*Bane til loggfiler*=") {
        #         $key = "DB_LOGPATH"
        #     }
        #     elseif ($line -like "*Maks. antall åpne DB-filer per database*=") {
        #         $key = "DB_MAXFILOP"
        #     }
        #     elseif ($line -like "*Prosent maks. primærloggplass per transaksjon (MAX_LOG)*=") {
        #         $key = "DB_MAX_LOG_PERCENT"
        #     }
        #     elseif ($line -like "*Kryptert database*=") {
        #         $key = "DB_IS_ENCRYPTED"
        #     }
        #     elseif ($line -like "*Databasen har statusen utsatt skriving*=") {
        #         $key = "DB_DEFERRED_WRITING"
        #     }
        #     elseif ($line -like "*Innsamlingsinnstillinger for overvåker*") {
        #         $key = "DB_MONITOR_COLLECTION_SETTINGS"
        #     }
        #     else {
        #         $posStartParenthesis = $keyTemp.LastIndexOf("(")
        #         $posEndParenthesis = $keyTemp.LastIndexOf(")")
        #         $key = $keyTemp.Substring($posStartParenthesis + 1, $posEndParenthesis - $posStartParenthesis - 1)
        #     }

        #     if (-not [string]::IsNullOrWhiteSpace($key)) {
        #         $value = $valueTemp.Trim()
        #         $dbmConfigObject = [PSCustomObject]@{
        #             Key   = $key.ToUpper().Replace(" ", "")
        #             Value = $value.Trim()
        #         }
        #         $dbmConfigObjectArray += $dbmConfigObject
        #     }
        # }

        # Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseConfiguration" -NotePropertyValue $configObjectArray -Force

        # Lines WITHOUT '(' in them:
     

        # Original lines from selection:
        # Databasekonfigurasjon for databasen INLTST

        # Utgavenivå på databasekonfigurasjonen                   = 0x1600
        # Utgavenivå på databasen                                 = 0x1600
       
        # Oppdatering til databasenivå venter                     = NO (0x0)
        # Databaseområde                                          = NO
        # Kodesett for database (code page)                       = 1252
        # Kodesett for database (code set)                        = 1252
        # Land-/områdekode for database                           = 47
        # Rangfølge for database                                  = UNIQUE
        # Alternativ rangfølge                      (ALT_COLLATE) =
        # Number-kompatibilitet                                   = OFF
        # Varchar2-kompatibilitet                                 = OFF
        # Datokompatibilitet                                      = OFF
        # Sidestørrelse for database                              = 4096
       
        # Setningskonsentrator                        (STMT_CONC) = OFF
       
        # Begrens tilgang                                         = NO
        # Std. optimaliseringsklasse for spørring  (DFT_QUERYOPT) = 5
        # Grad av parallellitet                      (DFT_DEGREE) = 1
        # Fortsett ved aritmetiske unntak       (DFT_SQLMATHWARN) = NO
        # Standard fornyingsalder               (DFT_REFRESH_AGE) = 0
        # Stand. vedlikeh. tabelltyper for optim.(DFT_MTTB_TYPES) = SYSTEM
        # Antall hyppige verdier som er beholdt  (NUM_FREQVALUES) = 10
        # Antall kontrollverdier som er beholdt   (NUM_QUANTILES) = 20
       
        # Avrundingsmodus for desimalflytetall  (DECFLT_ROUNDING) = ROUND_HALF_EVEN
       
        # DECIMAL aritmetisk modus               (DEC_ARITHMETIC) =
        # Large aggregation                   (LARGE_AGGREGATION) = NO
       
        # Standard skjema-RMT                  (DFT_SCHEMAS_RMT) = NO
       
        # Reservekopiering venter                                 = NO
       
        # Alle iverksatte transaksjoner er skrevet til disk    = NO
        # Fremlengs rulling venter                                = NO
        # Gjenoppretting venter                                   = NO
       
        # Oppgradering venter                                     = NO
       
        # Filtildeling av flere sider er aktivert                 = NO
       
        # Loggbevaring for gjenopprettingsstatus                  = RECOVERY
        # Status for brukerutgang for logging                     = NO
       
        # Selvjusterende minne                  (SELF_TUNING_MEM) = OFF
        # Størrelse på delt databaseminne (4 kB)(DATABASE_MEMORY) = AUTOMATIC(818832)
        # Terskel for databaseminne               (DB_MEM_THRESH) = 10
        # Maksimalt lager for låslister (4 kB)         (LOCKLIST) = 200
        # Prosentdel av låslister per applikasjon     (MAXLOCKS) = 22
        # Størrelse på pakkehurtigbuffer (4 kB)      (PCKCACHESZ) = (MAXAPPLS*8)
        # Terskel for delt sort.minneomr. (4 kB) (SHEAPTHRES_SHR) = 10000
        # Minneområde for sorteringsliste (4 kB)       (SORTHEAP) = 256
       
        # Minneområde for database (4 kB)                (DBHEAP) = AUTOMATIC(600)
        # Størr. på kataloghurtigbuffer (4 kB)  (CATALOGCACHE_SZ) = ((MAXAPPLS+25)*10)
        # Størrelse på loggbuffer (4 kB)               (LOGBUFSZ) = 8
        # Minneområde for hjelpeprogrammer (4 kB)  (UTIL_HEAP_SZ) = 5000
        # Minneområde for SQL-setning (4 kB)           (STMTHEAP) = 4096
        # Standard minneområde for applikasjon (4 kB)(APPLHEAPSZ) = AUTOMATIC(128)
        # Applikasjonsminnestørrelse (4 kB)         (APPL_MEMORY) = AUTOMATIC(40000)
        # Minneområde for statistikk (4 kB)        (STAT_HEAP_SZ) = AUTOMATIC(4384)
       
        # Tidsintervall for kontroll av vranglås (ms) (DLCHKTIME) = 10000
        # Tidsbestemt utkobling av lås (sek)        (LOCKTIMEOUT) = 120
       
        # Terskel for endrede sider              (CHNGPGS_THRESH) = 60
        # Antall asynkrone sidetømmere           (NUM_IOCLEANERS) = 1
        # Antall I/U-tjenere                      (NUM_IOSERVERS) = 3
        # Sekvensielt gjenfinningsmerke               (SEQDETECT) = YES
        # Std. størr. på forhåndshenting (sider)(DFT_PREFETCH_SZ) = 16
       
        # Sporing av endrede sider                     (TRACKMOD) = NO
       
        # Standard antall containere                              = 1
        # Std. områdestr. for tabellplass (sider) (DFT_EXTENT_SZ) = 32
       
        # Maksimalt antall aktive applikasjoner        (MAXAPPLS) = 20
        # Gjennomsnittlig antall aktive applikasjoner (AVG_APPLS) = 1
        # Levetid på hurtigbufret legitimasjon (AUTHN_CACHE_DURATION) = 3
        # Maks antall brukere i hurtigbufferen (AUTHN_CACHE_USERS) = 0
        # Maks. antall åpne DB-filer per database     (MAXFILOP)  = 65535
       
        # Diskkapasitet for aktiv loggplass (MB)   (LOG_DISK_CAP) = 0
        # Størrelse på loggfil (4 kB)                 (LOGFILSIZ) = 250
        # Antall primære loggfiler                   (LOGPRIMARY) = 3
        # Antall sekundære loggfiler                  (LOGSECOND) = 50
        # Endret bane til loggfiler                  (NEWLOGPATH) =
        # Bane til loggfiler                                      = E:\Db2PrimaryLogs\NODE0000\LOGSTREAM0000\
        # Bane for loggoverflyt                 (OVERFLOWLOGPATH) =
        # Bane til speillogg                      (MIRRORLOGPATH) =
        # Første aktive loggfil                                   = S0031719.LOG
        # Blokklogg på lager full               (BLK_LOG_DSK_FUL) = NO
        # Blokker ikke-loggede operasjoner       (BLOCKNONLOGGED) = NO
        # Prosent maks. primærloggplass per transaksjon (MAX_LOG) = 0
        # Antall aktive loggfiler for 1 aktiv UOW(NUM_LOG_SPAN)   = 0
       
        # Prosent loggfil gjenoppbyg. før mykt ktrl.pkt.(SOFTMAX) = 100
        # Mål for eldste side i LBP           (PAGE_AGE_TRGT_MCR) = 240
       
        # HADR-databaserolle                                      = STANDARD
        # Navn på lokal vert for HADR           (HADR_LOCAL_HOST) =
        # Navn på lokal tjeneste for HADR        (HADR_LOCAL_SVC) =
        # Navn på fjernvert for HADR           (HADR_REMOTE_HOST) =
        # Navn på fjerntjeneste for HADR        (HADR_REMOTE_SVC) =
        # Navn på forek. og fj.tjener for HADR (HADR_REMOTE_INST) =
        # HADR-tidsutkoblingsverdi                 (HADR_TIMEOUT) = 120
        # HADR-målliste                        (HADR_TARGET_LIST) =
        # HADR-synkron.modus for loggskriving     (HADR_SYNCMODE) = NEARSYNC
        # Grense for HADR-køloggdata (4KB)     (HADR_SPOOL_LIMIT) = AUTOMATIC(0)
        # HADR-forsinkelse for loggavsp.(sek) (HADR_REPLAY_DELAY) = 0
        # Varighet på HADR peer-vindu (sek.)  (HADR_PEER_WINDOW)  = 0
       
        # Loggarkiveringsmetode 1                  (LOGARCHMETH1) = LOGRETAIN
        # Arkivkomprimering for logarchmeth1    (LOGARCHCOMPR1)   = OFF
        # Alternativer for loggarkiveringsmetode 1  (LOGARCHOPT1) =
        # Loggarkiveringsmetode 2                  (LOGARCHMETH2) = OFF
        # Arkivkomprimering for logarchmeth2    (LOGARCHCOMPR2)   = OFF
        # Alternativer for loggarkiveringsmetode 2  (LOGARCHOPT2) =
        # Loggarkivbane ved failover               (FAILARCHPATH) =
        # Antall forsøk på loggarkivering ved feil (NUMARCHRETRY) = 5
        # Forsink. nye forsøk på loggark. (sek)  (ARCHRETRYDELAY) = 20
        # Leverandøralternativer                      (VENDOROPT) =
       
        # Automatisk omstart aktivert               (AUTORESTART) = ON
        # Tidspunkt for ny indeksoppretting og bygging (INDEXREC) = SYSTEM (RESTART)
        # Logg sider under indeksbygging          (LOGINDEXBUILD) = OFF
        # Standard antall LOADREC-sesjoner      (DFT_LOADREC_SES) = 1
        # Ant. databaseres. som skal beholdes    (NUM_DB_BACKUPS) = 12
        # Beholde gjenopprett.historikk (dager) (REC_HIS_RETENTN) = 366
        # Auto-sletting av gjenoppr.objekter   (AUTO_DEL_REC_OBJ) = OFF
       
        # TSM-styringsklasse                      (TSM_MGMTCLASS) =
        # TSM-node                                 (TSM_NODENAME) =
        # TSM-eier                                    (TSM_OWNER) =
        # TSM-passord                              (TSM_PASSWORD) =
       
        # Automatisk vedlikehold                     (AUTO_MAINT) = OFF
        #   Automatisk reservekop. av database   (AUTO_DB_BACKUP) = OFF
        #   Automatisk tabellvedlikehold         (AUTO_TBL_MAINT) = ON
        #     Automatisk runstats                 (AUTO_RUNSTATS) = ON
        #       Sanntidsstatistikk              (AUTO_STMT_STATS) = OFF
        #       Statistikkutsnitt              (AUTO_STATS_VIEWS) = OFF
        #       Automatisk avlesing               (AUTO_SAMPLING) = OFF
        #       Automatisk kolonnegruppestatistikk(AUTO_CG_STATS) = OFF
        #     Automatisk omorganisering              (AUTO_REORG) = ON
        #   Automatisk AI-vedlikehold              (AUTO_AI_MAINT) = ON
        #     AI Optimizer                    (AUTO_AI_OPTIMIZER) = OFF
        #       Automatic Model Discovery   (AUTO_MODEL_DISCOVER) = ON
       
        # Auto-revalidering                          (AUTO_REVAL) = DISABLED
       
        # Iverksatt                                  (CUR_COMMIT) = DISABLED
        # CHAR-utdata med DECIMAL-inndata       (DEC_TO_CHAR_FMT) = V95
        # Aktiver XML-tegnoperasjoner            (ENABLE_XMLCHAR) = YES
        # Håndhev begrensning                 (DDL_CONSTRAINT_DEF) = YES
        # Aktiver radkomprimering som standard(DDL_COMPRESSION_DEF)= NO
        # Replikeringssteds-ID                      (REPL_SITE_ID) = 0
        # Innsamlingsinnstillinger for overvåker
        # Forespørselsmetrikk                   (MON_REQ_METRICS) = NONE
        # Aktivitetsmetrikk                     (MON_ACT_METRICS) = NONE
        # Objektmetrikk                         (MON_OBJ_METRICS) = NONE
        # Rutinedata                               (MON_RTN_DATA) = NONE
        #   Utførbar liste for rutine          (MON_RTN_EXECLIST) = OFF
        # Arbeidsenhetsaktiviteter                 (MON_UOW_DATA) = NONE
        #   UOW-hendelser med pakkeliste        (MON_UOW_PKGLIST) = OFF
        #   UOW-hendelser med utførbar liste   (MON_UOW_EXECLIST) = OFF
        # Tidsutkoblingsaktiviteter for lås     (MON_LOCKTIMEOUT) = NONE
        # Vranglåsaktiviteter                      (MON_DEADLOCK) = NONE
        # Venter på lås-aktivitetet                (MON_LOCKWAIT) = NONE
        # Venter på lås-aktivitetsterskel         (MON_LW_THRESH) = 4294967295
        # Antall pakkelisteposter                (MON_PKGLIST_SZ) = 32
        # Varselnivå for låseaktivitet          (MON_LCK_MSG_LVL) = 1
       
        # SMTP-tjener                               (SMTP_SERVER) =
        # Flagg for betinget SQL-kompilering        (SQL_CCFLAGS) =
        # Innstilling for faktiske seksjonsdata (SECTION_ACTUALS) = NONE
        # Tilkoblingsprosedyre                     (CONNECT_PROC) =
        # Juster midl. SYSTEM_TIME-periode (SYSTIME_PERIOD_ADJ)   = NO
        # Logg DDL-setninger                      (LOG_DDL_STMTS) = YES
        # Logg applikasjonsinformasjon            (LOG_APPL_INFO) = NO
        # Standard datafangst på nye skjemaer   (DFT_SCHEMAS_DCC) = NO
        # Strict I/O for EXTBL_LOCATION         (EXTBL_STRICT_IO) = NO
        # Tillatte baner for eksterne tabeller   (EXTBL_LOCATION) = E:
        # Standard tabellorganisasjon             (DFT_TABLE_ORG) = ROW
        # Standard strengenheter                   (STRING_UNITS) = SYSTEM
        # Tilordning av nasjonale tegnstrenger    (NCHAR_MAPPING) = NOT APPLICABLE
        # Databasen har statusen utsatt skriving                  = NO
        # Støtte for utvidet radstørrelse       (EXTENDED_ROW_SZ) = DISABLE
        # Krypteringsbibliotek for reservekopiering     (ENCRLIB) =
        # Krypteringsalternativer for reservekopiering (ENCROPTS) =
       
        # WLM-innsamlingsintervall (minutter)   (WLM_COLLECT_INT) = 0
        # Målagentlast per CPU-kjerne       (WLM_AGENT_LOAD_TRGT) = AUTOMATIC(12)
        # WLM-tilgangskontroll aktivert      (WLM_ADMISSION_CTRL) = NO
        # Tildelt del av CPU-ressurser           (WLM_CPU_SHARES) = 1000
        # Virkemåte for CPU-del (hard/myk)   (WLM_CPU_SHARE_MODE) = HARD
        # Maksimum tillatt CPU-utnyttelse (%)     (WLM_CPU_LIMIT) = 0
        # Sorteringsminnegrense for aktivitet (ACT_SORTMEM_LIMIT) = NONE
        # Control file recovery path       (CTRL_FILE_RECOV_PATH) =
        # Kryptert database                                       = NO
        # Stakksporing for prosedyrespråk        (PL_STACK_TRACE) = NONE
        # HADR SSL-sertifikatetikett             (HADR_SSL_LABEL) =
        # HADR SSL-vertsnavnvalidering        (HADR_SSL_HOST_VAL) = OFF
       
        # BUFFPAGE-størrelse som skal brukes av optimalisator (OPT_BUFFPAGE) = 0
        # LOCKLIST-størrelse som skal brukes av optimalisator (OPT_LOCKLIST) = 0
        # MAXLOCKS-størrelse som skal brukes av optimalisator (OPT_MAXLOCKS) = 0
        # SORTHEAP-størrelse som skal brukes av optimalisator (OPT_SORTHEAP) = 0


    }
    catch {
        Write-LogMessage "Error getting DB2 configuration for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


function Get-ContentBetweenGuid {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Guid,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnArray = $false
    )
    try {
        $result = @()
        $array = $($Output -split "`n") 
        # Find array elements that start with $Guid.
        $startCapture = $false
        for ($i = 0; $i -lt $array.Count; $i++) {
            if ($array[$i].Trim().StartsWith($Guid)) {
                $startCapture = $true
                continue
            }
            if ($startCapture) {
                if ($array[$i].Trim().StartsWith($Guid)) {
                    break
                }
                if ([string]::IsNullOrEmpty($array[$i].Trim())) {
                    continue
                }
                if ($array[$i].Trim().Replace(" ", "").Contains(">db2")) {
                    continue
                }
                $result += $array[$i]
            }
         
        }

        if ($ReturnArray) {
            return $result
        }
        else {
            return $result -join "`n"
        }
    }
    catch {
        Write-LogMessage "Error getting content between GUIDs $($Guid)" -Level ERROR -Exception $_
        if ($ReturnArray) {
            return @()
        }
        else {
            return ""
        }
    }
    
}

<#
.SYNOPSIS
    Retrieves Db2 instance-level configuration parameters.

.DESCRIPTION
    Executes 'db2 get dbm cfg' and 'db2set -all' to retrieve instance manager configuration
    parameters. Parses settings including INSTANCE_MEMORY, FEDERATED support, authentication
    settings, service names, and diagnostic paths into structured configuration objects.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName to query configuration for.

.EXAMPLE
    $workObject = Get-Db2InstanceConfiguration -WorkObject $workObject
    # Retrieves and stores instance configuration in WorkObject.DbmConfiguration

.NOTES
    Configuration stored as array with Key/Value pairs. Handles Norwegian/English output.
    Critical for understanding instance-level memory and authentication settings.
#>
function Get-Db2InstanceConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        # HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\GLOBAL_PROFILE
        # HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\DB2 Server Edition\Languages
        #HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\CurrentVersion\Default Language is set to no_NO
        #HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\CurrentVersion\Default Language is set to en_US
        $guidArray = @([guid]::NewGuid().ToString(), [guid]::NewGuid().ToString())
        
        Write-LogMessage "Getting DB2 server configuration from registry" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "REM Get all DB2 server configuration from registry"
        $db2Commands += "echo $($guidArray[0])"
        $db2Commands += "db2set -i $($WorkObject.InstanceName) -all"
        $db2Commands += "echo $($guidArray[0])"
        $db2Commands += "REM Get all DB2 server configuration from dbm cfg"
        $db2Commands += "echo $($guidArray[1])"
        $db2Commands += "db2 get dbm cfg"
        $db2Commands += "echo $($guidArray[1])"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output


        # $output1 = Get-ContentBetweenGuid -Output $output -Guid $guidArray[0]
        # $output2 = Get-ContentBetweenGuid -Output $output -Guid $guidArray[1]
       
        # # Parse DBM Configuration output
        # $dbmConfigObjectArray = @()
        # foreach ($line in $($output1 -split "`n") ) {
        #     $key = $null
        #     $value = $null
        #     $keyTemp = $null
        #     $valueTemp = $null
        #     $posLastEqual = $line.LastIndexOf("=")
        #     if ($posLastEqual -eq -1) {
        #         continue
        #     }

        #     $keyTemp = $line.Substring(0, $posLastEqual).Trim()
        #     $valueTemp = $line.Substring($posLastEqual + 1).Trim()

        #     if ($line -like "*Nodetype =*") {
        #         $key = "DBM_NODETYPE"
        #     }
        #     elseif ($line -like "*Behandlet DIAGPATH for gjeldende medlem*") {
        #         $key = "DBM_DIAGPATH"
        #     }
        #     elseif ($line -like "*Behandlet ALT_DIAGPATH for gjeldende medlem*") {
        #         $key = "DBM_ALT_DIAGPATH"
        #     }
        #     elseif ($line -like "*Størrelse på roterende db2diag- & varsellogger (MB)*") {
        #         $key = "DBM_DIAGSIZE"
        #     }
        #     elseif ($line -like "*Utgavenivå på konfigurasjonen av databasesystemet*") {
        #         $key = "DBM_VERSION_LEVEL"
        #     }
        #     else {
        #         $posStartParenthesis = $keyTemp.LastIndexOf("(")
        #         $posEndParenthesis = $keyTemp.LastIndexOf(")")
        #         $key = $keyTemp.Substring($posStartParenthesis + 1, $posEndParenthesis - $posStartParenthesis - 1)
        #     }

        #     if (-not [string]::IsNullOrWhiteSpace($key)) {
        #         $value = $valueTemp.Trim()
        #         $dbmConfigObject = [PSCustomObject]@{
        #             Key   = $key.ToUpper().Replace(" ", "")
        #             Value = $value.Trim()
        #         }
        #         $dbmConfigObjectArray += $dbmConfigObject
        #     }
        # }

        # Add-Member -InputObject $WorkObject -NotePropertyName "DbmConfiguration" -NotePropertyValue $dbmConfigObjectArray -Force

        # Write-Host "output2: `n$output2"
        # Original comment lines showing example DBM configuration output:
        # Nodetype = Enterprise Server Edition med lokale og fjerntilknyttede klienter

        # Utgavenivå på konfigurasjonen av databasesystemet       = 0x1600
       
        # CPU-hastighet (millisek/instruksjon)         (CPUSPEED) = 1,259585e-07
        # Kommunikasjonsbåndbredde (MB/sek)      (COMM_BANDWIDTH) = 1,000000e+02
       
        # Største ant. databaser som er aktive samtidig   (NUMDB) = 32
        # Støtte for forent databasesystem            (FEDERATED) = YES
        # TP-overvåker (Transaction Processor)      (TP_MON_NAME) =
       
        # Standard belastningskonto             (DFT_ACCOUNT_STR) =
       
        # Install.bane for Java Development Kit  (JDK_PATH)       = C:\DbInst\java\jdk
       
        # Registreringsnivå for feilsøking            (DIAGLEVEL) = 3
        # Varslingsnivå                             (NOTIFYLEVEL) = 3
        # Katalogbane for feilsøkingsdata              (DIAGPATH) = C:\PROGRAMDATA\IBM\DB2\DB2COPY1\DB2\ $m
        # Behandlet DIAGPATH for gjeldende medlem                 = C:\PROGRAMDATA\IBM\DB2\DB2COPY1\DB2\DIAG0000\
        # Alternativ katalogbane for feilsøkingsdata (ALT_DIAGPATH)      =
        # Behandlet ALT_DIAGPATH for gjeldende medlem             =
        # Størrelse på roterende db2diag- & varsellogger (MB) (DIAGSIZE) = 0
       
        # Standardparametere for databaseovervåking
        #   Bufferområde                        (DFT_MON_BUFPOOL) = OFF
        #   Lås                                    (DFT_MON_LOCK) = OFF
        #   Sortering                              (DFT_MON_SORT) = OFF
        #   Setning                                (DFT_MON_STMT) = OFF
        #   Tabell                                (DFT_MON_TABLE) = OFF
        #   Systemtid                         (DFT_MON_TIMESTAMP) = ON
        #   Arbeidsenhet                            (DFT_MON_UOW) = OFF
        # Overvåk helse for forekomst og databaser   (HEALTH_MON) = OFF
       
        # SYSADM-gruppenavn                        (SYSADM_GROUP) = DB2ADMNS
        # SYSCTRL-gruppenavn                      (SYSCTRL_GROUP) = DB2ADMNS
        # SYSMAINT-gruppenavn                    (SYSMAINT_GROUP) = DB2ADMNS
        # SYSMON-gruppenavn                        (SYSMON_GROUP) = DB2ADMNS
       
        # Bruker-ID/passord-till.modul klient    (CLNT_PW_PLUGIN) =
        # Kerberos-tilleggsmodul for klient     (CLNT_KRB_PLUGIN) = IBMkrb5
        # Gruppetilleggsmodul                      (GROUP_PLUGIN) =
        # GSS-till.modul for lokal autorisasjon (LOCAL_GSSPLUGIN) =
        # Modus for tjenertilleggsmodul         (SRV_PLUGIN_MODE) = UNFENCED
        # Tjenerliste med GSS-till.modul. (SRVCON_GSSPLUGIN_LIST) = IBMkrb5
        # Bruker-ID/passord-till.modul tjener  (SRVCON_PW_PLUGIN) =
        # Autentisering av tjenertilkobling         (SRVCON_AUTH) = KERBEROS
        # Klyngestyrer                                            =
       
        # Autentisering av databasesystemet      (AUTHENTICATION) = KERBEROS
        # Alternativ autentisering           (ALTERNATE_AUTH_ENC) = NOT_SPECIFIED
        # Katalogisering tillatt uten autorisasj. (CATALOG_NOAUTH)=NO
        # Stol på alle klienter                  (TRUST_ALLCLNTS) = YES
        # Autentisering av betrodde klienter     (TRUST_CLNTAUTH) = CLIENT
        # Standardbane til database                   (DFTDBPATH) = E:
       
        # Minneområde for databaseovervåker (4 kB)  (MON_HEAP_SZ) = AUTOMATIC(66)
        # Minneomr. for Java Virtual Machine (4 kB)(JAVA_HEAP_SZ) = 65536
        # Størrelse på revisjonsbuffer (4 kB)      (AUDIT_BUF_SZ) = 0
        # Globalt forekomstminne (% eller 4kB) (INSTANCE_MEMORY) = AUTOMATIC(2097152)
        # Medlemsforekomstminne (% eller 4kB)                    = GLOBAL
        # Størrelse på agentstakk                (AGENT_STACK_SZ) = 16
        # Minneområdeterskel for sortering (4 kB)    (SHEAPTHRES) = 0
       
        # Kataloghurtigbufring                        (DIR_CACHE) = YES
       
        # Minneområde for applikasjonsstøttelag (4 kB)(ASLHEAPSZ) = 15
        # Maks. I/U-blokkstørrelse (byte) for klient   (RQRIOBLK) = 65535
        # Arb.belastn.påv. fra strupede funksj. (UTIL_IMPACT_LIM) = 10
       
        # Prioritering av agenter                      (AGENTPRI) = SYSTEM
        # Størrelse på agentområde               (NUM_POOLAGENTS) = AUTOMATIC(100)
        # Opprinnelig antall agenter i område    (NUM_INITAGENTS) = 0
        # Maks. antall koordinerende agenter    (MAX_COORDAGENTS) = AUTOMATIC(200)
        # Maksimalt antall klienttilkoblinger   (MAX_CONNECTIONS) = AUTOMATIC(MAX_COORDAGENTS)
       
        # Behold beskyttet prosess                   (KEEPFENCED) = YES
        # Antall beskyttede prosesser i gruppen     (FENCED_POOL) = AUTOMATIC(MAX_COORDAGENTS)
        # Opprinnelig ant. beskyttede prosesser  (NUM_INITFENCED) = 0
       
        # Tidspunkt for ny indeksoppretting og bygging (INDEXREC) = RESTART
       
        # Databasenavn på transaksjonsstyrer        (TM_DATABASE) = 1ST_CONN
        # Resynk.intervall for transaksjon (sek) (RESYNC_INTERVAL)= 180
       
        # SPM-navn                                     (SPM_NAME) = T_NO1INL
        # SPM-loggstørrelse                     (SPM_LOG_FILE_SZ) = 256
        # Grense for SPM-resynkroniseringsagent  (SPM_MAX_RESYNC) = 20
        # SPM-loggbane                             (SPM_LOG_PATH) =
       
        # Navn på TCP/IP-tjeneste                      (SVCENAME) = 3718
       
        # Tastbordfil for SSL-tjener              (SSL_SVR_KEYDB) =
        # Stash-fil for SSL-tjener                (SSL_SVR_STASH) =
        # Sertifikatetikett for SSL-tjener        (SSL_SVR_LABEL) =
        # SSL-tjenestenavn                         (SSL_SVCENAME) =
        # SSL-chifferspes                       (SSL_CIPHERSPECS) =
        # SSL-versjoner                            (SSL_VERSIONS) =
        # Tastaturfil for SSL-klient             (SSL_CLNT_KEYDB) =
        # Stash-fil for SSL-klient               (SSL_CLNT_STASH) =
       
        # Maks. grad av parallellitet for spørr.(MAX_QUERYDEGREE) = ANY
        # Aktiver parall. innenfor partisjoner   (INTRA_PARALLEL) = NO
       
        # Maksimum asynkrone TQer per spørring  (FEDERATED_ASYNC) = 0
       
        # Antall FCM-buffere                    (FCM_NUM_BUFFERS) = AUTOMATIC(4096)
        # FCM-bufferstørrelse                   (FCM_BUFFER_SIZE) = 32768
        # Antall FCM-kanaler                   (FCM_NUM_CHANNELS) = AUTOMATIC(2048)
        # FCM-parallellitet                     (FCM_PARALLELISM) = AUTOMATIC(1)
        # Kjøretid (sek) ved nodetilkobling         (CONN_ELAPSE) = 10
        # Maks. antall forsøk på nodetilkobling (MAX_CONNRETRIES) = 5
        # Maks. tidsforskjell mellom noder (min)  (MAX_TIME_DIFF) = 60
       
        # db2start/db2stop-tidsutkobling (min)  (START_STOP_TIME) = 10
       
        # WLM-fordeler aktivert                  (WLM_DISPATCHER) = NO
        # WLM-fordelersamtidighet               (WLM_DISP_CONCUR) = COMPUTED
        # CPU-deling for WLM-ford. aktivert (WLM_DISP_CPU_SHARES) = NO
        # Min. utnyttelse av WLM-fordeler (%) (WLM_DISP_MIN_UTIL) = 5
       
        # Bibliotekliste for kommunikasjonsbufferavslutning (COMM_EXIT_LIST) =
        # Gjeldende effektive ark.nivå         (CUR_EFF_ARCH_LVL) = V:12 R:1 M:1 F:0 I:0 SB:0
        # Gjeldende effektive kodenivå         (CUR_EFF_CODE_LVL) = V:12 R:1 M:1 F:0 I:0 SB:0
       
        # Nøkkellagertype                         (KEYSTORE_TYPE) = NONE
        # Nøkkellagerplassering               (KEYSTORE_LOCATION) =
       
        # Bane til python-kjøretid                  (PYTHON_PATH) =
        # Bane til R-kjøretid                            (R_PATH) =
       
        # Multipart upload part size            (MULTIPARTSIZEMB) = 100



    }
    catch {
        Write-LogMessage "Error getting DB2 configuration for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Completely removes a Db2 instance and all associated files.

.DESCRIPTION
    Comprehensive instance removal that:
    - Stops instance
    - Drops instance using db2idrop
    - Removes instance directory from primary data disk
    - Removes Windows service
    - Removes ProgramData\IBM instance directory
    - Cleans up registry entries
    - Removes user profile sqllib directory
    
    Requires confirmation in PRD environment with 60-second timeout.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName.

.EXAMPLE
    $workObject = Remove-InstanceName -WorkObject $workObject
    # Completely removes the instance and all files

.NOTES
    DESTRUCTIVE operation. Cannot be undone. PRD environments require explicit confirmation.
    Sets WorkObject properties: InstanceDirectoryRemovedAndRecreated, WindowsServiceRemoved,
    ProgramDataRemoved, UserProfileRemoved.
#>
function Remove-InstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Removing DB2 instance $($WorkObject.InstanceName) completely" -Level WARN


        # First, stop the instance if it's running
        $db2Commands = @()
        if ($(Get-EnvironmentFromServerName) -in @("PRD")) {
            Get-UserConfirmationWithTimeout -PromptMessage "Existing instance will be removed. Abort within 60 seconds." -TimeoutSeconds 60 -DefaultResponse "N" -ThrowOnTimeout $true
        }
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2stop force"
        $db2Commands += "db2idrop $($WorkObject.InstanceName) -f"

        # Execute the commands
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors -OutputToConsole
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        # Remove the instance directory if it exists
        $instancePath = "$($(Get-PrimaryDb2DataDisk))\$($WorkObject.InstanceName)"
        if (Test-Path $instancePath -PathType Container) {
            Write-LogMessage "Removing instance directory: $instancePath" -Level INFO
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -Path $instancePath -ItemType Directory -Force | Out-Null
            Add-Member -InputObject $WorkObject -NotePropertyName "InstanceDirectoryRemovedAndRecreated" -NotePropertyValue $true -Force
        }
        else {
            Write-LogMessage "Instance directory not found: $instancePath" -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "InstanceDirectoryRemoved" -NotePropertyValue $false -Force
        }

        # Remove Windows service if it exists
        $allservices = Get-CimInstance -ClassName Win32_Service
        $services = @()
        $services += $allservices | Where-Object { $_.Caption.ToUpper().EndsWith($WorkObject.InstanceName.ToUpper()) -and $_.Caption.ToUpper().StartsWith("DB2") } | Select-Object -First 1
        foreach ($service in $services) {
            $service | Invoke-CimMethod -MethodName "StopService"
            $service | Remove-CimInstance
            Add-Member -InputObject $WorkObject -NotePropertyName "WindowsServiceRemoved" -NotePropertyValue $true -Force
        }

        # Remove instance from ProgramData\IBM directory
        $programDataPath = "C:\ProgramData\IBM"
        $instanceProgramDataPath = Join-Path $programDataPath $WorkObject.InstanceName
        if (Test-Path $instanceProgramDataPath -PathType Container) {
            Write-LogMessage "Removing instance from ProgramData: $instanceProgramDataPath" -Level INFO
            Remove-Item -Path $instanceProgramDataPath -Recurse -Force -ErrorAction SilentlyContinue
            Add-Member -InputObject $WorkObject -NotePropertyName "ProgramDataRemoved" -NotePropertyValue $true -Force
        }
        else {
            Write-LogMessage "Instance not found in ProgramData: $instanceProgramDataPath" -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "ProgramDataRemoved" -NotePropertyValue $false -Force
        }

        # Remove registry entries for the instance
        try {
            # Check for instance-specific registry entries
            $registryPaths = @(
                "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\InstalledCopies",
                "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\InstalledCopies\DB2COPY1",
                "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\IBM\DB2\DB2COPY1"
            )

            foreach ($regPath in $registryPaths) {
                if (Test-Path $regPath) {
                    try {
                        # Look for instance-specific entries and remove them
                        $instanceEntries = Get-ChildItem -Path $regPath -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.PSChildName -eq $WorkObject.InstanceName }

                        if ($instanceEntries) {
                            Write-LogMessage "Removing registry entries for instance $($WorkObject.InstanceName) from $regPath" -Level INFO
                            foreach ($entry in $instanceEntries) {
                                Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                    catch {
                        Write-LogMessage "Error removing registry entries from $regPath" -Level WARN -Exception $_
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Error accessing registry for cleanup: $($_.Exception.Message)" -Level WARN
        }

        # Remove user profile instance directory
        $userProfilePath = Join-Path $env:USERPROFILE "sqllib"
        if (Test-Path $userProfilePath -PathType Container) {
            Write-LogMessage "Removing user profile instance directory: $userProfilePath" -Level INFO
            Remove-Item -Path $userProfilePath -Recurse -Force -ErrorAction SilentlyContinue
            Add-Member -InputObject $WorkObject -NotePropertyName "UserProfileRemoved" -NotePropertyValue $true -Force
        }
        else {
            Write-LogMessage "User profile instance directory not found: $userProfilePath" -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "UserProfileRemoved" -NotePropertyValue $false -Force
        }

        Write-LogMessage "Successfully removed DB2 instance $($WorkObject.InstanceName)" -Level INFO
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error removing DB2 instance $($WorkObject.InstanceName)" -Level ERROR -Exception $_
        throw $_
    }
}
<#
.SYNOPSIS
    Configures Windows service credentials for Db2 instance services.

.DESCRIPTION
    Updates the service account and password for Db2 Windows services using CIM:
    - Main Db2 instance service (e.g., "DB2 - DB2")
    - Remote Command Server service (for PrimaryDb only)
    
    Stops services, updates credentials, and restarts them.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName, ServiceUserName, ServicePassword, and DatabaseType.

.EXAMPLE
    $workObject = Set-InstanceServiceUserNameAndPassword -WorkObject $workObject
    # Updates service credentials and restarts services

.NOTES
    Stores reconfigured services in WorkObject.ReconfiguredServices. Uses 4-second delays
    between stop/start operations for stability.
#>
function Set-InstanceServiceUserNameAndPassword {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Set-InstanceServiceUserNameAndPassword starting for instance $($WorkObject.InstanceName), DatabaseType=$($WorkObject.DatabaseType)" -Level INFO
        Write-LogMessage "Target ServiceUserName (raw): $($WorkObject.ServiceUserName)" -Level INFO
        if ([string]::IsNullOrWhiteSpace($WorkObject.ServiceUserName)) {
            Write-LogMessage "ServiceUserName is null or empty - skipping service account change" -Level WARN
            return $WorkObject
        }
        if ([string]::IsNullOrWhiteSpace($WorkObject.ServicePassword)) {
            Write-LogMessage "ServicePassword is null or empty - skipping service account change" -Level WARN
            return $WorkObject
        }

        $qualifiedUserName = $WorkObject.ServiceUserName
        if ($qualifiedUserName -notmatch '\\' -and $qualifiedUserName -notmatch '@') {
            $qualifiedUserName = "$($env:USERDOMAIN)\$($qualifiedUserName)"
            Write-LogMessage "ServiceUserName missing domain qualifier, resolved to: $($qualifiedUserName)" -Level INFO
        }

        $allservices = Get-CimInstance -ClassName Win32_Service
        $allDb2Services = $allservices | Where-Object { $_.Name.ToUpper().StartsWith("DB2") -or $_.Caption.ToUpper().StartsWith("DB2") }
        Write-LogMessage "All DB2-related services on this machine:" -Level INFO
        foreach ($svc in $allDb2Services) {
            Write-LogMessage "  Service: Name=$($svc.Name), DisplayName=$($svc.DisplayName), Caption=$($svc.Caption), StartName=$($svc.StartName), State=$($svc.State)" -Level INFO
        }

        $services = @()
        $instanceNameUpper = $WorkObject.InstanceName.ToUpper()

        # Match by Name (exact), DisplayName (EndsWith), or Caption (EndsWith)
        $db2Service = $allDb2Services | Where-Object {
            $_.Name.ToUpper() -eq $instanceNameUpper -or
            $_.DisplayName.ToUpper().EndsWith("- $($instanceNameUpper)") -or
            $_.Caption.ToUpper().EndsWith("- $($instanceNameUpper)")
        } | Select-Object -First 1

        if ($null -ne $db2Service) {
            $services += $db2Service
            Write-LogMessage "Matched DB2 instance service: Name=$($db2Service.Name), DisplayName=$($db2Service.DisplayName), CurrentStartName=$($db2Service.StartName), State=$($db2Service.State)" -Level INFO
        }
        else {
            Write-LogMessage "No DB2 service matched for InstanceName='$($WorkObject.InstanceName)'. Checked Name (exact), DisplayName (ends with '- $($instanceNameUpper)'), Caption (ends with '- $($instanceNameUpper)')" -Level WARN
        }
        if ($WorkObject.DatabaseType -eq "PrimaryDb") {
            # Match remote command server by Name pattern or DisplayName/Caption keywords
            $remoteService = $allDb2Services | Where-Object {
                ($_.Name.ToUpper() -match "REMOTECMD" -or $_.DisplayName.ToUpper() -match "REMOTE COMMAND" -or $_.Caption.ToUpper() -match "REMOTE COMMAND") -and
                ($_.Name.ToUpper().Contains($instanceNameUpper) -or $_.DisplayName.ToUpper().EndsWith("- $($instanceNameUpper)") -or $_.Caption.ToUpper().EndsWith("- $($instanceNameUpper)"))
            } | Select-Object -First 1
            if ($null -ne $remoteService) {
                $services += $remoteService
                Write-LogMessage "Matched Remote Command Server: Name=$($remoteService.Name), DisplayName=$($remoteService.DisplayName), CurrentStartName=$($remoteService.StartName), State=$($remoteService.State)" -Level INFO
            }
            else {
                Write-LogMessage "No Remote Command Server found for InstanceName='$($WorkObject.InstanceName)'" -Level WARN
            }
        }
        Write-LogMessage "Total services to reconfigure: $($services.Count)" -Level INFO
        if ($services.Count -eq 0) {
            Write-LogMessage "No services found to reconfigure - no changes made" -Level WARN
            return $WorkObject
        }

        $reconfiguredServices = @()
        foreach ($service in $services) {
            Write-LogMessage "Changing service $($service.Name) StartName from '$($service.StartName)' to '$($qualifiedUserName)'" -Level INFO
            $changeResult = $service | Invoke-CimMethod -MethodName Change -Arguments @{
                StartName     = $qualifiedUserName
                StartPassword = $WorkObject.ServicePassword
            }
            if ($changeResult.ReturnValue -eq 0) {
                Write-LogMessage "Service $($service.Name) credentials changed successfully" -Level INFO
            }
            else {
                Write-LogMessage "Failed to change credentials for service $($service.Name). Win32_Service.Change ReturnValue: $($changeResult.ReturnValue)" -Level ERROR
                continue
            }

            $stopResult = Invoke-CimMethod -InputObject $service -MethodName "StopService"
            if ($stopResult.ReturnValue -eq 0) {
                Write-LogMessage "Service $($service.Name) stopped successfully" -Level INFO
            }
            else {
                Write-LogMessage "Failed to stop service $($service.Name). Return code: $($stopResult.ReturnValue)" -Level WARN
            }
            Start-Sleep -Seconds 4
            $startResult = Invoke-CimMethod -InputObject $service -MethodName "StartService"
            if ($startResult.ReturnValue -eq 0) {
                Write-LogMessage "Service $($service.Name) started successfully" -Level INFO
                $reconfiguredServices += $service
            }
            else {
                Write-LogMessage "Failed to start service $($service.Name). Return code: $($startResult.ReturnValue)" -Level WARN
            }
            Start-Sleep -Seconds 4

            $updatedService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name)'"
            Write-LogMessage "Service $($service.Name) post-change verification: StartName=$($updatedService.StartName), State=$($updatedService.State)" -Level INFO
            if ($updatedService.StartName -ne $qualifiedUserName) {
                Write-LogMessage "MISMATCH: Service $($service.Name) StartName is '$($updatedService.StartName)' but expected '$($qualifiedUserName)'" -Level ERROR
            }
        }
        Write-LogMessage "Set-InstanceServiceUserNameAndPassword completed. Reconfigured $($reconfiguredServices.Count) of $($services.Count) services" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "ReconfiguredServices" -NotePropertyValue $reconfiguredServices -Force
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error setting DB2 instance service user name and password for instance $($WorkObject.InstanceName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Creates or recreates a Db2 instance with clean folder structure.

.DESCRIPTION
    Comprehensive instance setup that:
    - Uncatalogs existing databases and nodes
    - Drops instance if it exists and is not DB2
    - Removes and recreates instance folders (data, logs, tablespaces)
    - Creates instance with 'db2icrt' if needed
    - Verifies instance creation succeeded
    
    Prompts for confirmation before removing existing instances in PRD environment.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName, DatabaseName, and folder paths.

.EXAMPLE
    $workObject = Set-InstanceNameConfiguration -WorkObject $workObject
    # Recreates instance with clean folder structure

.NOTES
    DESTRUCTIVE: Removes existing instance folders. Sets WorkObject.InstanceExist to true on success.
    Exits with code 9 if instance creation fails.
#>
function Set-InstanceNameConfiguration {

    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Setting DB2 instance configuration for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        # Redirect both stdout and stderr to null to suppress output and error messages
        # This code has potential issues and needs careful handling:
        # 1. If PrimaryAccessPoint is null, this will still iterate once with a null value
        # 2. If AliasAccessPoints is null or empty array, it will be skipped
        # 3. If either object doesn't have a NodeName property, it will cause an error
        # 4. The parentheses create an array that includes both single object and array

        # Better approach would be to check for null values and handle arrays properly:


        if ($WorkObject.PrimaryAccessPoint) {
            if ($WorkObject.DatabaseExist -eq $true) {
                $db2Commands += "db2 uncatalog database $($WorkObject.PrimaryAccessPoint.CatalogName) 2>nul"
            }
        }

        if ($WorkObject.AliasAccessPoints) {
            foreach ($accessPoint in $WorkObject.AliasAccessPoints) {
                $db2Commands += "db2 uncatalog database $($accessPoint.CatalogName) 2>nul"
            }
        }

        foreach ($existingNode in $WorkObject.ExistingNodes) {
            $db2Commands += "db2 uncatalog node $($existingNode)"
        }

        $db2Commands += "db2 terminate"
        if ($WorkObject.InstanceExist -eq $true) {
            $db2Commands += "db2stop force"
        }
        if ($WorkObject.InstanceExist -eq $true -and $WorkObject.InstanceName -ne "DB2") {
            $db2Commands += "db2idrop $($WorkObject.InstanceName) -f"
            $WorkObject.InstanceExist = $false
        }
        # $WorkObject.DbUser = $null  
        # $WorkObject.DbPassword = $null

        $db2Commands += "rd /s /q $($WorkObject.DataFolder)"
        $db2Commands += "rd /s /q $($WorkObject.PrimaryLogsFolder)"
        $db2Commands += "md $($WorkObject.PrimaryLogsFolder)"
        $db2Commands += "rd /s /q $($WorkObject.MirrorLogsFolder)"
        $db2Commands += "md $($WorkObject.MirrorLogsFolder)"
        $db2Commands += "rd /s /q $($WorkObject.TablespacesFolder)"
        $db2Commands += "md $($WorkObject.TablespacesFolder)"
        $db2Commands += "rd /s /q $($WorkObject.LogtargetFolder)"
        $db2Commands += "md $($WorkObject.LogtargetFolder)"

        if ($WorkObject.InstanceExist -eq $false) {
            $db2Commands += "db2icrt $($WorkObject.InstanceName) -s wse"
            # Set InstanceCreated to true
            Add-Member -InputObject $WorkObject -NotePropertyName "InstanceExist" -NotePropertyValue $true -Force
        }
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2start"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output


        # Check if instance is exits 
        $instanceList = Get-Db2InstanceNames -IncludeFederated       
        if ($instanceList -contains $WorkObject.InstanceName) {
            Write-LogMessage "Instance $($WorkObject.InstanceName) exists" -Level INFO
            Add-Member -InputObject $WorkObject -NotePropertyName "InstanceExist" -NotePropertyValue $true -Force
        }
        else {
            Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist after attept to create it. Exiting process immediately." -Level FATAL
            exit 9
        }
    }
    catch {
        Write-LogMessage "Error setting DB2 instance configuration for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Checks if the specified database is currently active in the instance.

.DESCRIPTION
    Executes 'db2 list active databases' to determine if the database specified in
    WorkObject.DatabaseName is currently active. Sets WorkObject.DatabaseExist to true/false.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Get-ExistingDatabases -WorkObject $workObject
    # Sets workObject.DatabaseExist to true if database is active

.NOTES
    This function checks active databases only, not all cataloged databases.
#>
function Get-ExistingDatabases {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Checking if existing databases exists" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 list active databases"
        $db2Commands += ""
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        if ($output -like "*$($WorkObject.DatabaseName)*") {
            Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $true -Force
            Write-LogMessage "Database $($WorkObject.DatabaseName) exists" -Level INFO
        }
        else {
            Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force
            Write-LogMessage "Database $($WorkObject.DatabaseName) does not exist" -Level INFO
        }
    }
    catch {
        Write-LogMessage "Error checking if database $($WorkObject.DatabaseName) exists" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Retrieves list of all cataloged databases for an instance.

.DESCRIPTION
    Executes 'db2 list db directory' to get all cataloged databases for the specified instance.
    Parses the output to extract database alias, name, authentication type, and principal name.
    Appends results to WorkObject.ExistingDatabaseList.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName to query.

.PARAMETER OverrideInstanceName
    Optional instance name to query instead of WorkObject.InstanceName.

.EXAMPLE
    $workObject = Get-ExistingDatabasesList -WorkObject $workObject
    # Populates workObject.ExistingDatabaseList with all cataloged databases

.NOTES
    Results are appended to existing list if WorkObject.ExistingDatabaseList already exists.
#>
function Get-ExistingDatabasesList {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$OverrideInstanceName = $null
    )

    try {
        Write-LogMessage "Checking if existing databases list exists" -Level INFO
        $instanceName = $WorkObject.InstanceName
        if (-not [string]::IsNullOrEmpty($OverrideInstanceName)) {
            $instanceName = $OverrideInstanceName
        }
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($instanceName)"
        $db2Commands += "db2 list db directory"
        $db2Commands += ""
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        #     Systemets databasekatalog

        #     Antall poster i katalogen = 1

        #    Post i database 1:

        #    Databasealias                        = FKNTOTST
        #    Databasenavn                                 = INLTST
        #    Nodenavn                                       = NODE2
        #    Utgavenivå på databasen              = 16.00
        #    Kommentar                      =
        #    Katalogposttype                = Fjerntliggende
        #    Autentisering                  = KERBEROS
        #    Prinsipalnavn                        = db2/t-no1inltst-db.DEDGE.fk.no@DEDGE.FK.NO
        #    Katalog for databasepartisjonsnummer       = -1
        #    Alternativt vertsnavn på tjener      =
        #    Alternativt portnummer på tjener     =


        $splitOutput = $output -split "`n"
        $existingDatabases = @()
        $newObject = $null
        foreach ($line in $splitOutput) {

            if ($line.ToUpper().Contains("DATABASEALIAS")) {
                if ($null -ne $newObject) {
                    $existingDatabases += $newObject
                    $newObject = $null
                }
                $newObject = [PSCustomObject]@{
                    InstanceName   = $InstanceName
                    DatabaseAlias  = ""
                    DatabaseName   = ""
                    Authentication = ""
                    PrincipalName  = ""
                }
            }
            if ($null -ne $newObject -and $line.ToUpper().Contains("DATABASEALIAS")) {
                $newObject.DatabaseAlias = $line.Split("=")[1].Trim()
            }
            if ($null -ne $newObject -and ($line.ToUpper() -match "DATABASENAME|DATABASENAVN")) {
                $newObject.DatabaseName = $line.Split("=")[1].Trim()
            }
            if ($null -ne $newObject -and ($line.ToUpper() -match "AUTHENTICATION|AUTENTISERING")) {
                $newObject.Authentication = $line.Split("=")[1].Trim()
            }
            if ($null -ne $newObject -and ($line.ToUpper() -match "PRINCIPALNAME|PRINSIPALNAVN")) {
                $newObject.PrincipalName = $line.Split("=")[1].Trim()
            }
        }
        if ($null -ne $newObject) {
            $existingDatabases += $newObject
            $newObject = $null
        }

        $totalDatabases = Get-Member -InputObject $WorkObject -MemberType NoteProperty -Name "ExistingDatabaseList"
        if ($null -ne $totalDatabases) {
            $WorkObject.ExistingDatabaseList = @($WorkObject.ExistingDatabaseList) + @($existingDatabases)
            $WorkObject.ExistingDatabaseList = $WorkObject.ExistingDatabaseList | Sort-Object -Unique
            Add-Member -InputObject $WorkObject -NotePropertyName "ExistingDatabaseList" -NotePropertyValue $WorkObject.ExistingDatabaseList -Force
        }
        else {
            Add-Member -InputObject $WorkObject -NotePropertyName "ExistingDatabaseList" -NotePropertyValue $existingDatabases -Force
        }

    }
    catch {
        Write-LogMessage "Error checking if existing databases exists" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Tests if a database exists and is accessible by attempting a connection.

.DESCRIPTION
    Attempts to connect to the database and execute a simple query against sysibm.sysdummy1.
    Sets WorkObject.DatabaseExist to true if successful, false otherwise. Requires the
    instance to exist before testing.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName to test.

.EXAMPLE
    $workObject = Test-DatabaseExistance -WorkObject $workObject
    # Sets workObject.DatabaseExist to true/false based on connection test

.NOTES
    Returns immediately with DatabaseExist=false if InstanceExist=false.
#>
function Test-DatabaseExistance {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Retreiving existing database-information for instance $($WorkObject.InstanceName)" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force

        if ($WorkObject.InstanceExist -eq $false) {
            Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist. Unable to test database existence" -Level WARN
            return $WorkObject
        }

        if ($WorkObject.UseNewConfigurations) {
            # Use catalog directory listing instead of connect probe to avoid SQL1013N/SQL1024N
            # when the database doesn't exist, and SQL1031N when the catalog is empty.
            try {
                $catalogCmds = @()
                $catalogCmds += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
                $catalogCmds += "db2 list database directory"
                $catalogCmds += "db2 terminate"
                $catalogOutput = Invoke-Db2ContentAsScript -Content $catalogCmds -ExecutionType BAT `
                    -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_CatalogCheck_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
                if ($catalogOutput -match [regex]::Escape($WorkObject.DatabaseName)) {
                    Write-LogMessage "Database $($WorkObject.DatabaseName) found in catalog on instance $($WorkObject.InstanceName)" -Level INFO
                    Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $true -Force
                }
                else {
                    Write-LogMessage "Database $($WorkObject.DatabaseName) not found in catalog on instance $($WorkObject.InstanceName)" -Level INFO
                    Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force
                }
            }
            catch {
                Write-LogMessage "Catalog listing failed for instance $($WorkObject.InstanceName): $($_.Exception.Message)" -Level WARN
                Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force
            }
        } else {
            try {
                $db2Commands = @()
                $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
                $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
                $db2Commands += "db2 select current timestamp from sysibm.sysdummy1"
                $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
                $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
                Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $true -Force
            }
            catch {
                if ($_.Exception.Message -match "SQL1060N") {
                    Write-LogMessage "User lacks CONNECT privilege on $($WorkObject.DatabaseName) - checking catalog listing instead" -Level WARN
                    try {
                        $catalogCmds = @()
                        $catalogCmds += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
                        $catalogCmds += "db2 list database directory"
                        $catalogCmds += "db2 terminate"
                        $catalogOutput = Invoke-Db2ContentAsScript -Content $catalogCmds -ExecutionType BAT `
                            -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_CatalogCheck_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
                        if ($catalogOutput -match $WorkObject.DatabaseName) {
                            Write-LogMessage "Database $($WorkObject.DatabaseName) found in catalog on instance $($WorkObject.InstanceName) (CONNECT will be granted by Set-DatabasePermissions)" -Level INFO
                            Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $true -Force
                        }
                        else {
                            Write-LogMessage "Database $($WorkObject.DatabaseName) not found in catalog listing" -Level WARN
                            Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force
                        }
                    }
                    catch {
                        Write-LogMessage "Catalog check also failed: $($_.Exception.Message)" -Level WARN
                        Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force
                    }
                }
                else {
                    Write-LogMessage "Database $($WorkObject.DatabaseName) does not exist" -Level WARN
                    Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error checking if database $($WorkObject.DatabaseName) exists" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}
# function Test-DatabaseExistance {
#     param(
#         [Parameter(Mandatory = $true)]
#         [PSCustomObject]$WorkObject
#     )

#     try {
#         Write-LogMessage "Retreiving existing database-information for instance $($WorkObject.InstanceName)" -Level INFO
#         Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $false -Force

#         if ($WorkObject.InstanceExist -eq $false) {
#             Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist. Unable to test database existence" -Level WARN
#             return $WorkObject
#         }

#         foreach ($database in $WorkObject.ExistingDatabaseList) {
#             if ($database.DatabaseName -eq $WorkObject.DatabaseName) {
#                 if ($database.InstanceName -eq $WorkObject.InstanceName) {
#                     Add-Member -InputObject $WorkObject -NotePropertyName "DatabaseExist" -NotePropertyValue $true -Force
#                     Write-LogMessage "Database $($WorkObject.DatabaseName) exists" -Level INFO
#                 }
#                 else {
#                     Write-LogMessage "Database $($WorkObject.DatabaseName) exists on instance $($database.InstanceName)" -Level INFO
#                     throw "Database $($WorkObject.DatabaseName) exists on instance $($database.InstanceName)"
#                 }
#                 break
#             }
#         }

#     }
#     catch {
#         Write-LogMessage "Error checking if database $($WorkObject.DatabaseName) exists" -Level FATAL -Exception $_
#         throw $_
#     }
#     return $WorkObject
# }

<#
.SYNOPSIS
    Tests if a specific table exists in the database.

.DESCRIPTION
    Executes 'db2 describe table' on WorkObject.TableToCheck to verify table existence.
    Sets WorkObject.TableExist to true if successful, false otherwise. Requires both
    instance and database to exist.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, InstanceName, and TableToCheck.

.EXAMPLE
    $workObject = Test-TableExistance -WorkObject $workObject
    # Sets workObject.TableExist based on whether TableToCheck exists

.NOTES
    Returns false immediately if instance or database doesn't exist, or if TableToCheck is empty.
#>
function Test-TableExistance {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Testing if table $($WorkObject.TableToCheck) exists" -Level INFO
        if ([string]::IsNullOrEmpty($WorkObject.TableToCheck)) {
            Write-LogMessage "No table to check specified" -Level WARN
            return $WorkObject
        }
        elseif ($WorkObject.InstanceExist -eq $false) {
            Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist. Unable to test table existence" -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "TableExist" -NotePropertyValue $false -Force
            return $WorkObject
        }
        elseif ($WorkObject.DatabaseExist -eq $false) {
            Write-LogMessage "Database $($WorkObject.DatabaseName) does not exist. Unable to test table existence" -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "TableExist" -NotePropertyValue $false -Force
            return $WorkObject
        }

        Add-Member -InputObject $WorkObject -NotePropertyName "TableExist" -NotePropertyValue $false -Force


        Write-LogMessage "Executing control statement for instance $($WorkObject.InstanceName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 describe table $($WorkObject.TableToCheck)"

        try {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
            Add-Member -InputObject $WorkObject -NotePropertyName "TableExist" -NotePropertyValue $true -Force
            Write-LogMessage "Table $($WorkObject.TableToCheck) exists" -Level INFO
        }
        catch {
            Write-LogMessage "Error executing control statement for table $($WorkObject.TableToCheck)" -Level WARN -Exception $_
        }
        finally {
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        }
    }
    catch {
        Write-LogMessage "Error executing control statement for table $($WorkObject.TableToCheck)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

#SELECT * FROM SYSIBMADM.ENV_PROD_INFO where license_installed = 'Y'

<#
.SYNOPSIS
    Adds ODBC user data source catalog entry for a database.

.DESCRIPTION
    Executes 'db2 catalog user odbc data source' to register the database as an ODBC data source
    for the current user. Lists all user ODBC data sources after catalog operation.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName to catalog.

.PARAMETER Quiet
    Suppresses informational log messages.

.EXAMPLE
    $workObject = Add-OdbcCatalogEntry -WorkObject $workObject
    # Catalogs database as user ODBC data source

.NOTES
    Required for ODBC client connectivity to the database.
#>
function Add-OdbcCatalogEntry {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false
    )
    try {
        Write-LogMessage "Adding ODBC catalog entry for database $($WorkObject.DatabaseName)" -Level INFO -Quiet:$Quiet
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 catalog user odbc data source $($WorkObject.DatabaseName)"
        $db2Commands += "db2 list user odbc data sources"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -Quiet:$Quiet
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output


        Write-LogMessage "ODBC catalog entry added for database $($WorkObject.DatabaseName)" -Level INFO -Quiet:$Quiet
    }
    catch {
        Write-LogMessage "Error adding ODBC catalog entry for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Determines the Db2 edition (Standard or Community).

.DESCRIPTION
    Queries SYSIBMADM.ENV_PROD_INFO to determine if Db2 Standard Edition is installed.
    Falls back to environment-based detection if the query fails. Sets WorkObject.Db2Version
    to either "StandardEdition" or "CommunityEdition".

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Get-Db2Version -WorkObject $workObject
    # Sets workObject.Db2Version to "StandardEdition" or "CommunityEdition"

.NOTES
    Production databases (FKMPRD, FKMRAP, VISPRD) default to Standard Edition on query failure.
#>
function Get-Db2Version {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        if ($WorkObject.InstanceExist -eq $false) {
            Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist. Unable to get Db2 version. Defaulting to Community Edition." -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "Db2Version" -NotePropertyValue "CommunityEdition" -Force
            return $WorkObject
        }
        Write-LogMessage "Checking if instance $($WorkObject.InstanceName) exists" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 SELECT * FROM SYSIBMADM.ENV_PROD_INFO where license_installed = 'Y'"
        $db2Commands += "db2 connect reset"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output


        $temp = Get-SelectResult -SelectOutput $output -ReturnArray
        #DB2_STANDARD_EDITION
        $stdElement = $null
        foreach ($element in $temp) {
            if ($element.Contains("DB2_STANDARD_EDITION")) {
                $stdElement = $element
                break
            }
        }
        if ($null -ne $stdElement) {
            Add-Member -InputObject $WorkObject -NotePropertyName "Db2Version" -NotePropertyValue "StandardEdition" -Force
        }
        else {
            Add-Member -InputObject $WorkObject -NotePropertyName "Db2Version" -NotePropertyValue "CommunityEdition" -Force
        }
    }
    catch {
        if ($(Get-DatabaseNameFromServerName) -in @("FKMPRD", "FKMRAP", "VISPRD")) {
            Add-Member -InputObject $WorkObject -NotePropertyName "Db2Version" -NotePropertyValue "StandardEdition" -Force
        }
        else {
            Add-Member -InputObject $WorkObject -NotePropertyName "Db2Version" -NotePropertyValue "CommunityEdition" -Force
        }
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Returns the number of active databases for a given DB2 instance on this server.

.DESCRIPTION
    Queries DatabasesV2.json (via Get-DatabasesV2Json) for active PrimaryDb access points
    matching the current server name and the WorkObject.InstanceName. Used by
    Set-PostRestoreConfiguration to set NUMDB correctly so STMM sizes memory slices
    proportionally (one slice per active database).

    Falls back to 1 on any error, which is safe for single-database instances.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName.

.EXAMPLE
    $numDb = Get-ActiveDatabaseCountForInstance -WorkObject $workObject
    # Returns 1 for most test/prod instances; 2 for instances hosting multiple DBs
#>
function Get-ActiveDatabaseCountForInstance {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        $count = (Get-DatabasesV2Json | Where-Object {
            $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and
            $_.IsActive -eq $true -and
            ($_.AccessPoints | Where-Object { $_.InstanceName -eq $WorkObject.InstanceName -and $_.AccessPointType -eq "PrimaryDb" })
        }).Count
        Write-LogMessage "Get-ActiveDatabaseCountForInstance: $($count) active database(s) found for instance $($WorkObject.InstanceName) on $($env:COMPUTERNAME)" -Level INFO
        return [Math]::Max(1, $count)
    }
    catch {
        Write-LogMessage "Could not determine active database count from DatabasesV2.json for instance $($WorkObject.InstanceName). Defaulting to 1." -Level WARN
        return 1
    }
}

<#
.SYNOPSIS
    Retrieves all Db2 instances installed on the server.

.DESCRIPTION
    Executes 'db2ilist' to get all Db2 instances and checks if the instance specified
    in WorkObject.InstanceName exists. Sets WorkObject.InstanceExist and populates
    WorkObject.ExistingInstanceList with all found instances.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName to verify.

.EXAMPLE
    $workObject = Get-ExistingInstances -WorkObject $workObject
    # Sets workObject.ExistingInstanceList and workObject.InstanceExist

.NOTES
    Only instances starting with "DB2" are captured from the db2ilist output.
#>
function Get-ExistingInstances {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Getting existing instances" -Level INFO
        $db2Commands = @()
        $db2Commands += "db2ilist"
        $db2Commands += ""
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        Add-Member -InputObject $WorkObject -NotePropertyName "InstanceExist" -NotePropertyValue $false -Force
        $splitOutput = $output -split "`n"
        $instances = @()
        foreach ($line in $splitOutput) {
            if ([string]::IsNullOrEmpty($line) -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            if ($line.ToUpper().StartsWith("DB2")) {
                $instances += $line.Trim().ToUpper()
            }
        }
        Add-Member -InputObject $WorkObject -NotePropertyName "ExistingInstanceList" -NotePropertyValue $instances -Force


        Write-LogMessage "Testing if instance $($WorkObject.InstanceName) exists" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "InstanceExist" -NotePropertyValue $false -Force
        if ($WorkObject.ExistingInstanceList.Count -eq 0) {
            Write-LogMessage "No existing instances found. Unable to test instance existence" -Level WARN
        }
        else {
            Write-LogMessage "Checking if instance $($WorkObject.InstanceName) exists" -Level INFO
            foreach ($instance in $WorkObject.ExistingInstanceList) {
                if ($instance -eq $WorkObject.InstanceName) {
                    Write-LogMessage "Instance $($WorkObject.InstanceName) exists" -Level INFO
                    Add-Member -InputObject $WorkObject -NotePropertyName "InstanceExist" -NotePropertyValue $true -Force
                    break
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error checking if instance $($WorkObject.InstanceName) exists" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Tests if a Db2 instance exists on the server.

.DESCRIPTION
    Calls Get-Db2InstanceNames and checks if WorkObject.InstanceName is in the returned list.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName to verify.

.EXAMPLE
    $exists = Test-InstanceExistance -WorkObject $workObject
    # Returns $true if instance exists, $false otherwise

.NOTES
    Returns boolean value, does not modify WorkObject.
#>
function Test-InstanceExistance {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        $instanceList = Get-Db2InstanceNames        
        if ($instanceList -contains $WorkObject.InstanceName) {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        Write-LogMessage "Error checking if instance $($WorkObject.InstanceName) exists" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Retrieves all cataloged nodes for a Db2 instance.

.DESCRIPTION
    Executes 'db2 list node directory' to get all cataloged TCPIP nodes for the instance.
    Parses node names from the output and stores in WorkObject.ExistingNodeList.

.PARAMETER WorkObject
    PSCustomObject containing InstanceName to query nodes for.

.EXAMPLE
    $workObject = Get-ExistingNodes -WorkObject $workObject
    # Populates workObject.ExistingNodeList with node names (e.g., NODE1, NODE2)

.NOTES
    Returns empty array if instance doesn't exist or has no cataloged nodes.
#>
function Get-ExistingNodes {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Retrieving existing nodes for instance $($WorkObject.InstanceName)" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "ExistingNodeList" -NotePropertyValue @() -Force
        if ($WorkObject.InstanceExist -eq $false) {
            Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist. Unable to retrieve existing nodes" -Level WARN
            return $WorkObject
        }

        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 list node directory"
        $db2Commands += ""
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        $splitOutput = $output -split "`n"

        $existingNodes = @()
        foreach ($line in $splitOutput) {
            if ($line.ToUpper().Contains("NODENAVN")) {
                $existingNodes += $line.Trim().Split("=")[1].Trim()
            }
        }
        Write-LogMessage "Existing nodes:`n $($existingNodes -join "`n")" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "ExistingNodeList" -NotePropertyValue $existingNodes -Force

    }
    catch {
        Write-LogMessage "Error retrieving existing nodes for instance $($WorkObject.InstanceName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Displays all cataloged databases across all instances in formatted table.

.DESCRIPTION
    Formats and displays WorkObject.ExistingDatabaseList as a table. Validates that
    federated databases (starting with 'X') are not incorrectly placed on the DB2 instance.
    Exits with fatal error if misplacement is detected.

.PARAMETER WorkObject
    PSCustomObject containing ExistingDatabaseList to display.

.EXAMPLE
    $workObject = Show-AllDatabases -WorkObject $workObject
    # Displays all databases and validates their instance placement

.NOTES
    Enforces rule: Federated databases must not exist on DB2 instance (should be on DB2FED).
#>
function Show-AllDatabases {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Showing all databases for all instances" -Level INFO
        $output = $WorkObject.ExistingDatabaseList | Format-Table * -AutoSize | Out-String
        Write-LogMessage "Existing databases:`n $output" -Level INFO

        foreach ($element in $WorkObject.ExistingInstanceList) {
            if ($element.InstanceName -eq "DB2" -and $element.DatabaseName.StartsWith("X")) {
                Write-LogMessage "Instance $($element.InstanceName) has database $($element.DatabaseName). This is not a valid placement of the federated database. Drop the database and recreate it on the correct instance." -Level FATAL
                Exit 1
            }
        }


        Start-Sleep -Seconds 5

    }
    catch {
        Write-LogMessage "Error showing all databases for instance $($WorkObject.InstanceName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Executes a control SQL statement to verify database connectivity and data access.

.DESCRIPTION
    Runs the SQL statement from WorkObject.ControlSqlStatement and extracts the row count
    from the output. Sets WorkObject.ControlSqlStatementResult to "Success" or "Failed"
    and captures the row count. Requires instance, database, and table to exist unless Force is used.

.PARAMETER WorkObject
    PSCustomObject containing ControlSqlStatement, DatabaseName, InstanceName, and TableToCheck.

.PARAMETER Force
    Bypasses instance/database/table existence checks and attempts execution anyway.

.EXAMPLE
    $workObject = Test-ControlSqlStatement -WorkObject $workObject
    # Executes control query and sets workObject.ControlRowCount and ControlSqlStatementResult

.NOTES
    Typically used post-restore to verify database contains expected data.
#>
function Test-ControlSqlStatement {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$Force = $false
    )

    try {
        Write-LogMessage "Testing control sql statement for database $($WorkObject.DatabaseName)" -Level INFO

        if ([string]::IsNullOrEmpty($WorkObject.ControlSqlStatement)) {
            Write-LogMessage "No control sql statement specified" -Level WARN
            return $WorkObject
        }
        if (-not $Force) {
            if ($WorkObject.InstanceExist -eq $false) {
                Write-LogMessage "Instance $($WorkObject.InstanceName) does not exist. Unable to test control sql statement" -Level WARN
                Add-Member -InputObject $WorkObject -NotePropertyName "ControlSqlStatementResult" -NotePropertyValue "Failed" -Force
                return $WorkObject
            }
            elseif ($WorkObject.DatabaseExist -eq $false) {
                Write-LogMessage "Database $($WorkObject.DatabaseName) does not exist. Unable to test control sql statement" -Level WARN
                Add-Member -InputObject $WorkObject -NotePropertyName "ControlSqlStatementResult" -NotePropertyValue "Failed" -Force
                return $WorkObject
            }
            elseif ($WorkObject.TableExist -eq $false) {
                Write-LogMessage "Table $($WorkObject.TableToCheck) does not exist. Unable to test control sql statement" -Level WARN
                Add-Member -InputObject $WorkObject -NotePropertyName "ControlSqlStatementResult" -NotePropertyValue "Failed" -Force
                return $WorkObject
            }

            Add-Member -InputObject $WorkObject -NotePropertyName "ControlSqlStatementResult" -NotePropertyValue "Failed" -Force
        }
        # Test if control SQL statement is not empty, database exists, and instance exists and table exists
        Write-LogMessage "Executing control sql statement for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "$($WorkObject.ControlSqlStatement) "

        try {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"

            # Extract rowcount using regex pattern matching
            $rowCountPattern = '(\d+)\s+post\((\w+)\)\s+er\s+valgt\.' #  8 post(er) er valgt.
            $rowCountMatch = [regex]::Match($output, $rowCountPattern)
            if ($rowCountMatch.Success) {
                $extractedRowCount = [int] $rowCountMatch.Groups[1].Value
                Write-LogMessage "Found rowcount in output: $extractedRowCount" -Level INFO
                Add-Member -InputObject $WorkObject -NotePropertyName "ControlRowCount" -NotePropertyValue $extractedRowCount -Force
                Add-Member -InputObject $WorkObject -NotePropertyName "ControlSqlStatementResult" -NotePropertyValue "Success" -Force
            }
            else {
                Write-LogMessage "No rowcount found in output" -Level WARN
            }
        }
        catch {
            Write-LogMessage "Error executing control sql statement for database $($WorkObject.DatabaseName)" -Level WARN -Exception $_
        }
        finally {
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "ExecuteControlSqlStatement" -Script $($db2Commands -join "`n") -Output $output
        }
    }
    catch {
        Write-LogMessage "Error executing control sql statement for database $($WorkObject.DatabaseName)" -Level WARN -Exception $_
        throw $_
    }
    return $WorkObject
}

function MultiSplitString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$String,
        [Parameter(Mandatory = $true)]
        [string[]]$Delimiters
    )
    
    # Helper recursive function to split string with all delimiters
    function Split-Recursively {
        param(
            [string]$InputString,
            [string[]]$DelimiterList,
            [int]$DelimiterIndex = 0
        )
        
        # Base case: if we've processed all delimiters, return the string as single element
        if ($DelimiterIndex -ge $DelimiterList.Count) {
            return @($InputString.Trim())
        }
        
        $currentDelimiter = $DelimiterList[$DelimiterIndex]
        $splitResult = $InputString.Split($currentDelimiter, [System.StringSplitOptions]::RemoveEmptyEntries)
        
        $result = @()
        foreach ($item in $splitResult) {
            $trimmedItem = $item.Trim()
            if ($trimmedItem -ne '') {
                # Recursively split with remaining delimiters
                $recursiveResult = Split-Recursively -InputString $trimmedItem -DelimiterList $DelimiterList -DelimiterIndex ($DelimiterIndex + 1)
                $result += $recursiveResult
            }
        }
        
        return $result
    }
    
    # Start the recursive splitting process
    $result = Split-Recursively -InputString $String -DelimiterList $Delimiters
    return $result
}

function Get-DateTimeFromDb2Format {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Db2Format
    )
    try {
        if ([string]::IsNullOrWhiteSpace($Db2Format)) {
            Write-LogMessage "Get-DateTimeFromDb2Format received empty input. Returning null." -Level WARN
            return $null
        }

        $splitString = MultiSplitString -String $Db2Format -Delimiters @("-", ".", ":", " ")
        if ($null -eq $splitString -or $splitString.Count -lt 6) {
            $partCount = if ($null -eq $splitString) { 0 } else { $splitString.Count }
            Write-LogMessage "Unable to parse DB2 datetime string '$($Db2Format)'. Expected at least 6 parts (YYYY MM DD HH MM SS [ffffff]), got $($partCount). Returning null." -Level WARN
            return $null
        }

        $pad2 = { param($val) ([string]$val).PadLeft(2, '0') }
        $pad6 = { param($val) ([string]$val).PadLeft(6, '0') }
        $year = [string]$splitString[0]
        $month = (&$pad2 $splitString[1])
        $day = (&$pad2 $splitString[2])
        $hour = (&$pad2 $splitString[3])
        $minute = (&$pad2 $splitString[4])
        $second = (&$pad2 $splitString[5])
        $micro = if ($splitString.Count -ge 7) { (&$pad6 $splitString[6]) } else { "000000" }
        $resultDateTimeString = $year + $month + $day + $hour + $minute + $second + $micro

        $resultDateTime = [DateTime]::ParseExact(
            $resultDateTimeString,
            "yyyyMMddHHmmssffffff",
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None
        )

        Write-LogMessage ("Parsed string $($Db2Format) to datetime $($resultDateTime.ToString('yyyy-MM-dd HH:mm:ss.ffffff')). Components: year=$($resultDateTime.Year), month=$($resultDateTime.Month), day=$($resultDateTime.Day), hour=$($resultDateTime.Hour), minute=$($resultDateTime.Minute), second=$($resultDateTime.Second), microseconds=$($resultDateTime.ToString('ffffff'))") -Level DEBUG
        return $resultDateTime
    }
    catch {
        Write-LogMessage "Unable to parse DB2 datetime string '$($Db2Format)'. Returning null." -Level ERROR -Exception $_
        return $null
    }
}



<#
.SYNOPSIS
    Retrieves all functions from specified schemas in the database.

.DESCRIPTION
    Queries SYSCAT.FUNCTIONS to get all user-defined functions with their schema, name,
    specific name, and creation time. Optionally filters by schema list.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.PARAMETER SchemaList
    Optional array of schema names to filter results. If empty, returns all non-system functions.

.EXAMPLE
    $workObject = Get-DatabaseListOfFunctions -WorkObject $workObject
    # Retrieves all functions from DBM, FK, Dedge schemas

.EXAMPLE
    $workObject = Get-DatabaseListOfFunctions -WorkObject $workObject -SchemaList @("DBM")
    # Retrieves functions from DBM schema only
#>
function Get-DatabaseListOfFunctions {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [array]$SchemaList = @()
    )

    try {
        Write-LogMessage "Getting list of all functions for database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 `"SELECT '$($WorkObject.DatabaseName)' || CHR(9) || trim(X.FUNCSCHEMA) || CHR(9) || trim(X.FUNCNAME) || CHR(9) || trim(X.SPECIFICNAME) || CHR(9) || CHAR(X.CREATE_TIME) AS FEDERATED_NICKNAMES FROM SYSCAT.FUNCTIONS X WHERE X.FUNCSCHEMA IN ('DBM', 'FK', 'Dedge')`""
        $db2Commands += "db2 terminate"



        $db2Commands += ""
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff')" -Script $($db2Commands -join "`n") -Output $output


        $listOfFunctions = Get-SelectResult -SelectOutput $output
        $listOfFunctions = $listOfFunctions.Split("`n") | Where-Object { $_ -ne "" }
        $listOfFunctionsObjects = @()
        foreach ($function in $listOfFunctions) {
            $functionSplit = $function.Split("`t")
            if ($null -eq $functionSplit -or $functionSplit.Count -lt 4) {
                $functionPartCount = if ($null -eq $functionSplit) { 0 } else { $functionSplit.Count }
                Write-LogMessage "Skipping malformed function row in $($MyInvocation.MyCommand.Name). Expected >= 4 parts (SERVER, SCHEMA, NAME, SPECIFICNAME, CREATE_TIME), got $($functionPartCount). Row: '$($function)'" -Level WARN
                continue
            }
            $alterTime = Get-DateTimeFromDb2Format -Db2Format $functionSplit[4]
            $functionObject = [PSCustomObject]@{
                SERVERNAME = $functionSplit[0]
                SCHEMA     = $functionSplit[1]
                NAME       = $functionSplit[2]
                ALTER_TIME = $alterTime
            }
            if ($null -ne $SchemaList -and $SchemaList.Count -ne 0) {
                if ($functionObject.SCHEMA -notin $SchemaList) {
                    continue
                }
            }
            $listOfFunctionsObjects += $functionObject
        }     


        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfFunctions" -NotePropertyValue $listOfFunctionsObjects -Force
        Write-LogMessage "Number of functions in database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName): $($listOfFunctionsObjects.Count)" -Level INFO
    }
    catch {
        Write-LogMessage "Error getting list of all functions for database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName)" -Level ERROR -Exception $_
        throw "Error getting list of all functions for database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName): $($_.Exception.Message)"
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Retrieves all tables, views, and nicknames from the database with their metadata.

.DESCRIPTION
    Queries SYSCAT.TABLES to get all tables (T), views (V), and nicknames (N) with their
    schema, name, and alter time. Excludes system schemas and RDBI schemas. Optionally
    filters by schema list. Parses Db2 timestamp format into PowerShell DateTime objects.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.PARAMETER SchemaList
    Optional array of schema names to filter results.

.EXAMPLE
    $workObject = Get-DatabaseListOfTables -WorkObject $workObject
    # Retrieves all user tables/views from database

.EXAMPLE
    $workObject = Get-DatabaseListOfTables -WorkObject $workObject -SchemaList @("DBM","CRM")
    # Retrieves only tables/views from DBM and CRM schemas
#>
function Get-DatabaseListOfTables {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [array]$SchemaList = @()
    )

    try {
        Write-LogMessage "Getting list of all tables for database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        # Old dot-delimited query (replaced by CHR(9) tab-delimited version below to avoid parsing ambiguity with dots in timestamps and identifiers)
        $db2Commands += "db2 `"SELECT '$($WorkObject.InstanceName.Trim())LNK' || CHR(9) || trim(TABSCHEMA) || CHR(9) || trim(TABNAME) || CHR(9) || CHAR(ALTER_TIME) AS FEDERATED_NICKNAMES FROM SYSCAT.TABLES WHERE TYPE IN ('V', 'T', 'N') AND UPPER(TABNAME) NOT LIKE '%DBM.DRBI%' and TABSCHEMA NOT IN ('SYSCAT', 'SYSIBM', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC', 'Q', 'RDBI') ORDER BY TYPE DESC`""
        $db2Commands += "db2 terminate"




        $db2Commands += ""
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff')" -Script $($db2Commands -join "`n") -Output $output


        $listOfTables = Get-SelectResult -SelectOutput $output
        $listOfTables = $listOfTables.Split("`n") | Where-Object { $_ -ne "" }
        $listOfTablesObjects = @()
        foreach ($table in $listOfTables) {
            $trimmedTable = $table.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmedTable) -or
                $trimmedTable -match '^-+$' -or
                $trimmedTable -eq 'FEDERATED_NICKNAMES') {
                continue
            }
            $tableSplit = $trimmedTable.Split("`t")
            if ($null -eq $tableSplit -or $tableSplit.Count -lt 4) {
                $tablePartCount = if ($null -eq $tableSplit) { 0 } else { $tableSplit.Count }
                Write-LogMessage "Skipping malformed table row in $($MyInvocation.MyCommand.Name). Expected >= 4 parts (SERVER, SCHEMA, TABLE, ALTER_TIME), got $($tablePartCount). Row: '$($trimmedTable)'" -Level WARN
                continue
            }

            $alterTime = Get-DateTimeFromDb2Format -Db2Format $tableSplit[3]
            $tableObject = [PSCustomObject]@{
                SERVERNAME = $tableSplit[0]
                SCHEMA     = $tableSplit[1]
                NAME       = $tableSplit[2]
                ALTER_TIME = $alterTime
            }
            if ($null -ne $SchemaList -and $SchemaList.Count -ne 0) {
                if ($tableObject.SCHEMA -notin $SchemaList) {
                    continue
                }
            }
            if ($null -ne $tableObject) {
                $listOfTablesObjects += $tableObject
            }
        }     

        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfTables" -NotePropertyValue $listOfTablesObjects -Force
        Write-LogMessage "Number of tables in database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName): $($listOfTablesObjects.Count)" -Level INFO
    }
    catch {
        Write-LogMessage "Error getting list of all tables for database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName)" -Level ERROR -Exception $_
        throw "Error getting list of all tables for database $($WorkObject.DatabaseName) on instance $($WorkObject.InstanceName): $($_.Exception.Message)"
    }
    return $WorkObject
}



<#
.SYNOPSIS
    Retrieves all tables and views from a database using server-side execution.

.DESCRIPTION
    Queries SYSCAT.TABLES to get all tables (T) and views (V) excluding system schemas.
    Uses server-side ODBC connection for execution. Returns tables with schema, name, and alter time.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName.

.EXAMPLE
    $workObject = Get-DatabaseTableList -WorkObject $workObject
    # Populates workObject.ListOfTables with table information

.NOTES
    Requires running on Db2 server. Excludes system schemas (SYSIBM, SYSCAT, etc.).
#>
function Get-DatabaseTableList {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Getting list of all tables for primary database $($WorkObject.DatabaseName)" -Level INFO
        $result = Get-ExecuteSqlStatementServerSide  -DatabaseName $WorkObject.DatabaseName  -SqlStatement $("SELECT '$($WorkObject.DatabaseName)' As SERVER, X.TABSCHEMA, X.TABNAME, X.ALTER_TIME FROM ( SELECT X.TABSCHEMA, X.TABNAME, X.TYPE, X.ALTER_TIME FROM SYSCAT.TABLES X WHERE X.TYPE IN ('V', 'T') AND LOWER(x.TABNAME) NOT LIKE '%dbm.drbi%' ORDER BY X.TYPE DESC) X where X.TABSCHEMA is not null and X.TABNAME is not null and X.TABSCHEMA not in ('SYSCAT', 'SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC')")    
        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfTables" -NotePropertyValue $result -Force
    }
    catch { 
        Write-LogMessage "Error getting list of all tables in primary database for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error getting list of all tables in primary database for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Retrieves all user-defined schemas from a database.

.DESCRIPTION
    Queries SYSCAT.TABLES for distinct schema names, excluding system schemas.
    Uses server-side ODBC connection for execution.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName.

.EXAMPLE
    $workObject = Get-DatabaseSchemaList -WorkObject $workObject
    # Populates workObject.ListOfSchemas with schema names

.NOTES
    Requires running on Db2 server. Excludes SYSIBM, SYSCAT, SYSFUN, etc.
#>
function Get-DatabaseSchemaList {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Getting list of all schemas for primary database $($WorkObject.DatabaseName)" -Level INFO
        $result = Get-ExecuteSqlStatementServerSide  -DatabaseName $WorkObject.DatabaseName  -SqlStatement $("SELECT DISTINCT X.TABSCHEMA FROM SYSCAT.TABLES X WHERE X.TABSCHEMA not in ('SYSCAT', 'SYSIBM', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC')")    
        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfSchemas" -NotePropertyValue $result -Force
    }
    catch {
        Write-LogMessage "Error getting list of all schemas in primary database for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error getting list of all schemas in primary database for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Retrieves all tables and views with their metadata for grant operations.

.DESCRIPTION
    Queries SYSCAT.TABLES to get all tables and views excluding system schemas.
    Uses server-side ODBC execution. Results include server, schema, table name, and alter time.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName.

.EXAMPLE
    $workObject = Get-DatabaseGrantList -WorkObject $workObject
    # Populates workObject.ListOfGrants with table information

.NOTES
    Similar to Get-DatabaseTableList but specifically for grant management operations.
#>
function Get-DatabaseGrantList {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Getting list of all grants for primary database $($WorkObject.DatabaseName)" -Level INFO
        $result = Get-ExecuteSqlStatementServerSide  -DatabaseName $WorkObject.DatabaseName  -SqlStatement $("SELECT '$($WorkObject.DatabaseName)' As SERVER, X.TABSCHEMA, X.TABNAME, X.ALTER_TIME FROM ( SELECT X.TABSCHEMA, X.TABNAME, X.TYPE, X.ALTER_TIME FROM SYSCAT.TABLES X WHERE X.TYPE IN ('V', 'T') AND LOWER(x.TABNAME) NOT LIKE '%dbm.drbi%' ORDER BY X.TYPE DESC) X where X.TABSCHEMA is not null and X.TABNAME is not null and X.TABSCHEMA not in ('SYSCAT', 'SYSIBM', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC')")    
        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfGrants" -NotePropertyValue $result -Force
    }
    catch {
        Write-LogMessage "Error getting list of all tables in primary database for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error getting list of all tables in primary database for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}

function Get-Db2TableGrants {
    <#
    .SYNOPSIS
    Retrieves all table and view grants from DB2 system catalog tables.
    
    .DESCRIPTION
    This function queries the SYSCAT.TABAUTH system catalog table to find all existing grants
    on tables and views in the database. It provides comprehensive information about who has
    what privileges on which objects.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER SchemaName
    Optional filter to limit results to a specific schema
    
    .PARAMETER TableName
    Optional filter to limit results to a specific table/view
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2TableGrants -DatabaseName "SAMPLE"
    
    .EXAMPLE
    Get-Db2TableGrants -DatabaseName "SAMPLE" -SchemaName "DBM" -Grantee "SRV_KPDB"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $false)]
        [string]$TableName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting table/view grants for database $DatabaseName" -Level INFO
        
        # Build the SQL query with optional filters
        $sqlQuery = @"
SELECT 
    '$DatabaseName' AS DATABASE_NAME,
    T.TABSCHEMA,
    T.TABNAME,
    T.TYPE,
    A.GRANTEE,
    A.GRANTEETYPE,
    A.GRANTOR,
    A.GRANTORTYPE,
    A.SELECTAUTH,
    A.INSERTAUTH,
    A.UPDATEAUTH,
    A.DELETEAUTH,
    A.ALTERAUTH,
    A.INDEXAUTH,
    A.REFAUTH,
    A.CONTROLAUTH
FROM SYSCAT.TABAUTH A
INNER JOIN SYSCAT.TABLES T ON A.TABSCHEMA = T.TABSCHEMA AND A.TABNAME = T.TABNAME
WHERE T.TYPE IN ('T', 'V')
"@
        
        # Add optional filters
        if ($SchemaName) {
            $sqlQuery += " AND T.TABSCHEMA = '$SchemaName'"
        }
        
        if ($TableName) {
            $sqlQuery += " AND T.TABNAME = '$TableName'"
        }
        
        if ($Grantee) {
            $sqlQuery += " AND A.GRANTEE = '$Grantee'"
        }
        
        $sqlQuery += " ORDER BY T.TABSCHEMA, T.TABNAME, A.GRANTEE"
        
        $result = Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $sqlQuery
        Write-LogMessage "Retrieved $($result.Count) table/view grant records" -Level INFO
        
        return $result
    }
    catch {
        Write-LogMessage "Error getting table/view grants for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting table/view grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Get-Db2RoutineGrants {
    <#
    .SYNOPSIS
    Retrieves all routine (function/procedure) grants from DB2 system catalog tables.
    
    .DESCRIPTION
    This function queries the SYSCAT.ROUTINEAUTH system catalog table to find all existing grants
    on functions and procedures in the database.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER SchemaName
    Optional filter to limit results to a specific schema
    
    .PARAMETER RoutineName
    Optional filter to limit results to a specific routine
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2RoutineGrants -DatabaseName "SAMPLE"
    
    .EXAMPLE
    Get-Db2RoutineGrants -DatabaseName "SAMPLE" -SchemaName "FK" -Grantee "SRV_KPDB"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $false)]
        [string]$RoutineName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting routine grants for database $DatabaseName" -Level INFO
        
        # Build the SQL query with optional filters
        $sqlQuery = @"
SELECT 
    '$DatabaseName' AS DATABASE_NAME,
    R.ROUTINESCHEMA,
    R.ROUTINENAME,
    R.ROUTINETYPE,
    A.GRANTEE,
    A.GRANTEETYPE,
    A.GRANTOR,
    A.GRANTORTYPE,
    A.EXECUTEAUTH
FROM SYSCAT.ROUTINEAUTH A
INNER JOIN SYSCAT.ROUTINES R ON A.SCHEMA = R.ROUTINESCHEMA AND A.SPECIFICNAME = R.SPECIFICNAME
WHERE R.ROUTINETYPE IN ('F', 'P')
"@
        
        # Add optional filters
        if ($SchemaName) {
            $sqlQuery += " AND R.ROUTINESCHEMA = '$SchemaName'"
        }
        
        if ($RoutineName) {
            $sqlQuery += " AND R.ROUTINENAME = '$RoutineName'"
        }
        
        if ($Grantee) {
            $sqlQuery += " AND A.GRANTEE = '$Grantee'"
        }
        
        $sqlQuery += " ORDER BY R.ROUTINESCHEMA, R.ROUTINENAME, A.GRANTEE"
        
        $result = Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $sqlQuery
        Write-LogMessage "Retrieved $($result.Count) routine grant records" -Level INFO
        
        return $result
    }
    catch {
        Write-LogMessage "Error getting routine grants for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting routine grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Get-Db2SchemaGrants {
    <#
    .SYNOPSIS
    Retrieves all schema grants from DB2 system catalog tables.
    
    .DESCRIPTION
    This function queries the SYSCAT.SCHEMAAUTH system catalog table to find all existing grants
    on schemas in the database.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER SchemaName
    Optional filter to limit results to a specific schema
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2SchemaGrants -DatabaseName "SAMPLE"
    
    .EXAMPLE
    Get-Db2SchemaGrants -DatabaseName "SAMPLE" -SchemaName "DBM" -Grantee "SRV_KPDB"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting schema grants for database $DatabaseName" -Level INFO
        
        # Build the SQL query with optional filters
        $sqlQuery = @"
SELECT 
    '$DatabaseName' AS DATABASE_NAME,
    S.SCHEMANAME,
    A.GRANTEE,
    A.GRANTEETYPE,
    A.GRANTOR,
    A.GRANTORTYPE,
    A.CREATEINAUTH,
    A.ALTERINAUTH,
    A.DROPINAUTH
FROM SYSCAT.SCHEMAAUTH A
INNER JOIN SYSCAT.SCHEMATA S ON A.SCHEMANAME = S.SCHEMANAME
"@
        
        # Add optional filters
        if ($SchemaName) {
            $sqlQuery += " WHERE S.SCHEMANAME = '$SchemaName'"
        }
        
        if ($Grantee) {
            if ($SchemaName) {
                $sqlQuery += " AND A.GRANTEE = '$Grantee'"
            }
            else {
                $sqlQuery += " WHERE A.GRANTEE = '$Grantee'"
            }
        }
        
        $sqlQuery += " ORDER BY S.SCHEMANAME, A.GRANTEE"
        
        $result = Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $sqlQuery
        Write-LogMessage "Retrieved $($result.Count) schema grant records" -Level INFO
        
        return $result
    }
    catch {
        Write-LogMessage "Error getting schema grants for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting schema grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Get-Db2PackageGrants {
    <#
    .SYNOPSIS
    Retrieves all package grants from DB2 system catalog tables.
    
    .DESCRIPTION
    This function queries the SYSCAT.PACKAGEAUTH system catalog table to find all existing grants
    on packages in the database.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER SchemaName
    Optional filter to limit results to a specific schema
    
    .PARAMETER PackageName
    Optional filter to limit results to a specific package
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2PackageGrants -DatabaseName "SAMPLE"
    
    .EXAMPLE
    Get-Db2PackageGrants -DatabaseName "SAMPLE" -SchemaName "DBM" -Grantee "SRV_KPDB"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $false)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting package grants for database $DatabaseName" -Level INFO
        
        # Build the SQL query with optional filters
        $sqlQuery = @"
SELECT 
    '$DatabaseName' AS DATABASE_NAME,
    P.PKGSCHEMA,
    P.PKGNAME,
    A.GRANTEE,
    A.GRANTEETYPE,
    A.GRANTOR,
    A.GRANTORTYPE,
    A.CONTROLAUTH,
    A.BINDAUTH,
    A.EXECUTEAUTH
FROM SYSCAT.PACKAGEAUTH A
INNER JOIN SYSCAT.PACKAGES P ON A.PKGSCHEMA = P.PKGSCHEMA AND A.PKGNAME = P.PKGNAME
"@
        
        # Add optional filters
        if ($SchemaName) {
            $sqlQuery += " WHERE P.PKGSCHEMA = '$SchemaName'"
        }
        
        if ($PackageName) {
            if ($SchemaName) {
                $sqlQuery += " AND P.PKGNAME = '$PackageName'"
            }
            else {
                $sqlQuery += " WHERE P.PKGNAME = '$PackageName'"
            }
        }
        
        if ($Grantee) {
            if ($SchemaName -or $PackageName) {
                $sqlQuery += " AND A.GRANTEE = '$Grantee'"
            }
            else {
                $sqlQuery += " WHERE A.GRANTEE = '$Grantee'"
            }
        }
        
        $sqlQuery += " ORDER BY P.PKGSCHEMA, P.PKGNAME, A.GRANTEE"
        
        $result = Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $sqlQuery
        Write-LogMessage "Retrieved $($result.Count) package grant records" -Level INFO
        
        return $result
    }
    catch {
        Write-LogMessage "Error getting package grants for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting package grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Get-Db2IndexGrants {
    <#
    .SYNOPSIS
    Retrieves all index grants from DB2 system catalog tables.
    
    .DESCRIPTION
    This function queries the SYSCAT.INDEXAUTH system catalog table to find all existing grants
    on indexes in the database.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER SchemaName
    Optional filter to limit results to a specific schema
    
    .PARAMETER IndexName
    Optional filter to limit results to a specific index
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2IndexGrants -DatabaseName "SAMPLE"
    
    .EXAMPLE
    Get-Db2IndexGrants -DatabaseName "SAMPLE" -SchemaName "DBM" -Grantee "SRV_KPDB"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $false)]
        [string]$IndexName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting index grants for database $DatabaseName" -Level INFO
        
        # Build the SQL query with optional filters
        $sqlQuery = @"
SELECT 
    '$DatabaseName' AS DATABASE_NAME,
    I.INDSCHEMA,
    I.INDNAME,
    I.TABSCHEMA,
    I.TABNAME,
    A.GRANTEE,
    A.GRANTEETYPE,
    A.GRANTOR,
    A.GRANTORTYPE,
    A.CONTROLAUTH
FROM SYSCAT.INDEXAUTH A
INNER JOIN SYSCAT.INDEXES I ON A.INDSCHEMA = I.INDSCHEMA AND A.INDNAME = I.INDNAME
"@
        
        # Add optional filters
        if ($SchemaName) {
            $sqlQuery += " WHERE I.INDSCHEMA = '$SchemaName'"
        }
        
        if ($IndexName) {
            if ($SchemaName) {
                $sqlQuery += " AND I.INDNAME = '$IndexName'"
            }
            else {
                $sqlQuery += " WHERE I.INDNAME = '$IndexName'"
            }
        }
        
        if ($Grantee) {
            if ($SchemaName -or $IndexName) {
                $sqlQuery += " AND A.GRANTEE = '$Grantee'"
            }
            else {
                $sqlQuery += " WHERE A.GRANTEE = '$Grantee'"
            }
        }
        
        $sqlQuery += " ORDER BY I.INDSCHEMA, I.INDNAME, A.GRANTEE"
        
        $result = Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $sqlQuery
        Write-LogMessage "Retrieved $($result.Count) index grant records" -Level INFO
        
        return $result
    }
    catch {
        Write-LogMessage "Error getting index grants for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting index grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Get-Db2DatabaseGrants {
    <#
    .SYNOPSIS
    Retrieves database-level grants from SYSCAT.DBAUTH.
    
    .DESCRIPTION
    Queries SYSCAT.DBAUTH for all database-level privileges such as CONNECT, DBADM,
    CREATETAB, BINDADD, IMPLICIT_SCHEMA, LOAD, etc.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2DatabaseGrants -DatabaseName "FKMTST"
    
    .EXAMPLE
    Get-Db2DatabaseGrants -DatabaseName "FKMTST" -Grantee "PUBLIC"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting database-level grants for database $DatabaseName" -Level INFO
        
        $sqlQuery = @"
SELECT
    '$DatabaseName' AS DATABASE_NAME,
    GRANTEE,
    GRANTEETYPE,
    GRANTOR,
    GRANTORTYPE,
    CONNECTAUTH,
    CREATETABAUTH,
    DBADMAUTH,
    EXTERNALROUTINEAUTH,
    IMPLSCHEMAAUTH,
    LOADAUTH,
    NOFENCEAUTH,
    QUIESCECONNECTAUTH,
    BINDADDAUTH,
    DATAACCESSAUTH,
    ACCESSCTRLAUTH,
    SECURITYADMAUTH,
    SQLADMAUTH,
    WLMADMAUTH,
    EXPLAINAUTH
FROM SYSCAT.DBAUTH
WHERE 1=1
"@
        
        if ($Grantee) {
            $sqlQuery += " AND GRANTEE = '$Grantee'"
        }
        
        $sqlQuery += " ORDER BY GRANTEE"
        
        $result = Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $sqlQuery
        Write-LogMessage "Retrieved $($result.Count) database-level grant records" -Level INFO
        
        return $result
    }
    catch {
        Write-LogMessage "Error getting database-level grants for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting database-level grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Get-Db2AllGrants {
    <#
    .SYNOPSIS
    Retrieves all grants from DB2 system catalog tables in a comprehensive report.
    
    .DESCRIPTION
    This function provides a comprehensive view of all grants in the database by calling
    all the individual grant functions and combining the results.
    
    .PARAMETER DatabaseName
    The name of the DB2 database to query
    
    .PARAMETER SchemaName
    Optional filter to limit results to a specific schema
    
    .PARAMETER Grantee
    Optional filter to limit results to a specific grantee (user or role)
    
    .EXAMPLE
    Get-Db2AllGrants -DatabaseName "SAMPLE"
    
    .EXAMPLE
    Get-Db2AllGrants -DatabaseName "SAMPLE" -SchemaName "DBM" -Grantee "SRV_KPDB"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $false)]
        [string]$Grantee
    )
    
    try {
        Write-LogMessage "Getting comprehensive grant report for database $DatabaseName" -Level INFO
        
        $allGrants = [PSCustomObject] @{
            DatabaseGrants = @()
            TableGrants    = @()
            RoutineGrants  = @()
            SchemaGrants   = @()
            PackageGrants  = @()
            IndexGrants    = @()
        }
        
        # Get all types of grants
        $allGrants.DatabaseGrants = Get-Db2DatabaseGrants -DatabaseName $DatabaseName -Grantee $Grantee
        $allGrants.TableGrants = Get-Db2TableGrants -DatabaseName $DatabaseName -SchemaName $SchemaName -Grantee $Grantee
        $allGrants.RoutineGrants = Get-Db2RoutineGrants -DatabaseName $DatabaseName -SchemaName $SchemaName -Grantee $Grantee
        $allGrants.SchemaGrants = Get-Db2SchemaGrants -DatabaseName $DatabaseName -SchemaName $SchemaName -Grantee $Grantee
        $allGrants.PackageGrants = Get-Db2PackageGrants -DatabaseName $DatabaseName -SchemaName $SchemaName -Grantee $Grantee
        $allGrants.IndexGrants = Get-Db2IndexGrants -DatabaseName $DatabaseName -SchemaName $SchemaName -Grantee $Grantee
        
        $totalGrants = $allGrants.DatabaseGrants.Count + $allGrants.TableGrants.Count + $allGrants.RoutineGrants.Count + $allGrants.SchemaGrants.Count + $allGrants.PackageGrants.Count + $allGrants.IndexGrants.Count
        
        Write-LogMessage "Retrieved comprehensive grant report with $totalGrants total grant records" -Level INFO
        
        return $allGrants
    }
    catch {
        Write-LogMessage "Error getting comprehensive grant report for database $DatabaseName" -Level ERROR -Exception $_
        throw "Error getting comprehensive grant report for database $DatabaseName`: $($_.Exception.Message)"
    }
}


function Get-ExecuteSqlStatementServerSide {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $true)]
        [string]$SqlStatement
    )
    try {
        if (-not (Test-IsDb2Server)) {
            throw "This function must be run on a Db2 server"
        }
        if ($null -eq $DatabaseName) {
            $DatabaseName = $(Get-DatabaseNameFromServerName)
        }
        Write-LogMessage "Executing sql statement: $($SqlStatement) towards database $($DatabaseName)" -Level INFO
        try {
            $currAccessPoint = Get-DatabaseConfigFromDatabaseName -DatabaseName $DatabaseName
        }
        catch {
            Write-LogMessage "Error getting access point for database $($DatabaseName) on computer $($env:COMPUTERNAME)" -Level Error -Exception $_
            throw
        }
        $odbcConnectionName = $currAccessPoint.CatalogName

        Write-LogMessage "Access point found: $($currAccessPoint.CatalogName)" -Level DEBUG
        Write-LogMessage "Executing query: $($SqlStatement)" -Level DEBUG
        Write-LogMessage "DatabaseName: $($DatabaseName)" -Level DEBUG
        Write-LogMessage "ComputerName: $($env:COMPUTERNAME)" -Level DEBUG
        Write-LogMessage "OdbcConnectionName: $($odbcConnectionName)" -Level Info

        try {
            $result = ExecuteQuery -sqlStatement $SqlStatement -odbcConnectionName $odbcConnectionName
        }
        catch {
            Write-LogMessage "Error executing query: $($SqlStatement)" -Level Error -Exception $_
            return
        }
        $result = $result | Select-Object -Skip 1

    }
    catch {
        Write-LogMessage "Error executing sql statement server side for database $($DatabaseName)" -Level ERROR -Exception $_
        throw "Error executing sql statement server side for database $($DatabaseName): $($_.Exception.Message)"
    }
    if ($null -eq $result -or $result.Count -eq 0) {
        if ($SqlStatement.ToLower().Contains("select")) {
            Write-LogMessage "No rows returned for database $($DatabaseName)" -Level WARN
        }
        Write-LogMessage "Database: $($DatabaseName) / Computer: $($env:COMPUTERNAME) / OdbcConnectionName: $($odbcConnectionName) / Sql statement: $($SqlStatement)" -Level DEBUG
        return @()
    }
    else {
        return $result
    }
}
function Convert-XmlToPSCustomObject {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode[]]$XmlNodes,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeAttributes = $true,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeChildElements = $true,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeElementName = $true
    )
    
    return $XmlNodes | ForEach-Object {
        $obj = [PSCustomObject]@{}
        
        if ($IncludeAttributes) {
            foreach ($attr in $_.Attributes) {
                $obj | Add-Member -MemberType NoteProperty -Name $attr.Name -Value $attr.Value -Force
            }
        }
        
        if ($IncludeChildElements) {
            foreach ($child in $_.ChildNodes) {
                if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                    $obj | Add-Member -MemberType NoteProperty -Name $child.Name -Value $child.InnerText -Force
                }
            }
        }
        
        if ($IncludeElementName) {
            $obj | Add-Member -MemberType NoteProperty -Name "ElementName" -Value $_.Name -Force
        }
        
        $obj
    }
}


function Get-SelectResultV2 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectOutput,
        [Parameter(Mandatory = $false)]
        [string]$SqlSelectStatement,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnArray = $false
    )
    $filteredOutput = @()

    try {
        $startLine = $false
        # Ensure the string is handled as ANSI-1252 encoding
        # Convert the input string to bytes and back to string using ANSI-1252 encoding
        $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
        $selectOutputBytes = $ansiEncoding.GetBytes($SelectOutput)
        $ansiSelectOutput = $ansiEncoding.GetString($selectOutputBytes)

        $columnInfoArray = @()

        $validLineCounter = 0
        $columnItemNames = @()
        $columnItemNamesLength = 0
        foreach ($line in $($ansiSelectOutput -split "`n")) {
            if ($line.ToLower().Contains($SqlSelectStatement.ToLower())) {
                $startLine = $true
                continue
            }
            if ($line.Contains("post(er) er valgt.")) {
                break
            }
            if ($startLine) {
                if ([string]::IsNullOrEmpty($line) -or [string]::IsNullOrWhiteSpace($line)) {
                    continue
                }
                $validLineCounter ++
                if ($validLineCounter -eq 1) {
                    while ($line.Contains("  ")) {
                        $line = $line.Replace("  ", " ")
                    }
                    $columnItemNames = $line.Split(" ")
                    continue
                }
                elseif ($validLineCounter -eq 2) {
                    $columnItemNamesLength = $line.Split(" ") | ForEach-Object { $_.Trim().Length }
                    Write-LogMessage "Column item names length: $($columnItemNamesLength)" -Level INFO
                    Write-LogMessage "Column item names: $($columnItemNames)" -Level INFO
                    if ($columnItemNamesLength.Count -ne $columnItemNames.Count) {
                        Write-LogMessage "Column item names length does not match column item names count" -Level ERROR
                        throw "Column item names length does not match column item names count"
                    }
                    for ($i = 0; $i -lt $columnItemNames.Count; $i++) {
                        $columnInfoObject = [PSCustomObject]@{
                            ColumnName   = $columnItemNames[$i]
                            ColumnLength = $columnItemNamesLength[$i]
                        }
                        $columnInfoArray += $columnInfoObject
                    }
                    continue
                }
                else {
                    $filteredOutput += $line.Trim()
                }

                $filteredOutput += $line.Trim()
            }
        }

        if ($validLineCounter -eq 0) {

            if ($ReturnArray) {
                return @()
            }
            else {
                return ""
            }
        }
    }
    catch {
        Write-LogMessage "Error getting select result output: $($SelectOutput.Substring(0, 100))" -Level WARN -Exception $_
    }
    if ($ReturnArray) {
        return $filteredOutput
    }
    else {
        return $filteredOutput -join "`n"
    }
}
<#
.SYNOPSIS
    Executes SQL query and returns results as array.

.DESCRIPTION
    Executes a SQL SELECT statement via Db2 CLI and parses the output into an array.
    Uses Get-SelectResultV2 for enhanced parsing. Tracks script and output in WorkObject.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.PARAMETER SqlSelectStatement
    SQL SELECT statement to execute.

.EXAMPLE
    $result = Get-ArrayFromQuery -WorkObject $workObject -SqlSelectStatement "SELECT * FROM syscat.tables"
    # Executes query and returns array of results

.NOTES
    Automatically names the script output based on the FROM clause table name.
#>
function Get-ArrayFromQuery {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$SqlSelectStatement
    )
    try {
        $splitSqlSelectStatement = $SqlSelectStatement -split " FROM "
        $fromPart = $splitSqlSelectStatement[1].Trim().Split(" ")[0].ToUpper().Trim()
        

        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 $($SqlSelectStatement)"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
    
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "QueryFrom$fromPart" -Script $($db2Commands -join "`n") -Output $output
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        # # $result = Get-SelectResult -SelectOutput $output -ReturnArray 
        # $result 

        $result = Get-SelectResultV2 -SelectOutput $output  -SqlSelectStatement $SqlSelectStatement -ReturnArray
        $result
    }
    catch {
        Write-LogMessage "Error executing sql statement server side for database $($DatabaseName)" -Level ERROR -Exception $_
        throw "Error executing sql statement server side for database $($DatabaseName): $($_.Exception.Message)"
    }
    if ($null -eq $result -or $result.Count -eq 0) {
        if ($SqlStatement.ToLower().Contains("select")) {
            Write-LogMessage "No rows returned for database $($DatabaseName)" -Level WARN
        }
        Write-LogMessage "Database: $($DatabaseName) / Computer: $($env:COMPUTERNAME) / OdbcConnectionName: $($odbcConnectionName) / Sql statement: $($SqlStatement)" -Level DEBUG
        return @()
    }
    else {
        return $result
    }
}


<#
.SYNOPSIS
    Sets initial Db2 instance configuration after instance creation.

.DESCRIPTION
    Configures basic instance settings:
    - DB2_OVERRIDE_BPF for buffer pool tuning
    - DB2COMM for TCPIP communication
    - SVCENAME for service port
    - DFTDBPATH for default database path
    - Uncatalogs existing nodes that conflict with current access points
    - Sets instance service username and password

.PARAMETER WorkObject
    PSCustomObject containing InstanceName, RemotePort, and access point definitions.

.EXAMPLE
    $workObject = Set-Db2InitialConfiguration -WorkObject $workObject
    # Applies initial instance configuration

.NOTES
    Calls Set-InstanceServiceUserNameAndPassword to configure Windows service credentials.
#>
function Set-Db2InitialConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {

        Write-LogMessage "Setting DB2 initial configuration for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2_OVERRIDE_BPF=5000"
        $db2Commands += "db2set -g DB2COMM=TCPIP"
        $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2COMM="
        $db2Commands += "db2 update dbm cfg using SVCENAME $($WorkObject.RemotePort)"
        $db2Commands += "db2 update dbm cfg using DFTDBPATH $($(Get-PrimaryDb2DataDisk))"
        $db2Commands += "db2 terminate"

        $currentNodesInAccessPoints = @()
        $currentNodesInAccessPoints += $WorkObject.PrimaryAccessPoint.NodeName
        foreach ($aliasAccessPoint in $WorkObject.AliasAccessPoints) {
            $currentNodesInAccessPoints += $aliasAccessPoint.NodeName
        }
        foreach ($node in $WorkObject.ExistingNodes) {
            if ($currentNodesInAccessPoints -contains $node) {
                $db2Commands += "db2 uncatalog node $($node)"
                $db2Commands += "db2 terminate"
            }
        }
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"


        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        # Set Db2 instance service user name and password
        $WorkObject = Set-InstanceServiceUserNameAndPassword -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

    }
    catch {
        Write-LogMessage "Error setting DB2 initial configuration for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Configures database settings after restore operation.

.DESCRIPTION
    Applies post-restore configuration based on Db2 edition and application:
    - UseNewConfigurations: Skips hardcoded bufferpool sizing (uses AUTOSIZE), sets SELF_TUNING_MEM=ON
    - Standard Edition FKM: Creates/alters buffer pools (IBMDEFAULTBP=3GB, BIGTAB=2GB, USER32=5000 pages)
    - Community Edition FKM: Smaller buffer pools (IBMDEFAULTBP=100MB, BIGTAB=500MB)
    - Updates Z_AVDTAB.DATABASENAVN for FKM application
    - Legacy mode: Sets SELF_TUNING_MEM=OFF and AUTO_MAINT=OFF
    - Clears DB2_OVERRIDE_BPF and activates database

.PARAMETER WorkObject
    PSCustomObject containing Db2Version, Application, InstanceName, and DatabaseName.

.EXAMPLE
    $workObject = Set-PostRestoreConfiguration -WorkObject $workObject
    # Applies edition-appropriate buffer pool and database settings

.NOTES
    Critical for ensuring restored database operates correctly with proper memory allocation.
#>
function Set-PostRestoreConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Setting post restore configuration for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)

        if ($WorkObject.UseNewConfigurations) {
            # Detect edition if not already populated (queries SYSIBMADM.ENV_PROD_INFO)
            if ([string]::IsNullOrEmpty($WorkObject.Db2Version)) {
                $WorkObject = Get-Db2Version -WorkObject $WorkObject
            }
            $numDb = Get-ActiveDatabaseCountForInstance -WorkObject $WorkObject
            Write-LogMessage "UseNewConfigurations: Edition=$($WorkObject.Db2Version), numdb=$($numDb) — applying full DB2 12.1 STMM configuration" -Level INFO

            # ── Instance level (DBM CFG) ──────────────────────────────────────────────────
            # INSTANCE_MEMORY AUTOMATIC: Community Edition auto-caps at 8 GB license limit;
            #   Standard Edition uses available RAM. (db2_config_param_1212.md)
            # SHEAPTHRES 0: required for shared sort memory model and SORTHEAP AUTOMATIC.
            #   Without this, STMM cannot tune sortheap/sheapthres_shr. (db2_perf_tune_1212.md rule 3)
            # NUMDB: tells STMM how many databases share this instance's memory pool.
            $db2Commands += "db2 update dbm cfg using INSTANCE_MEMORY AUTOMATIC"
            $db2Commands += "db2 update dbm cfg using SHEAPTHRES 0"
            $db2Commands += "db2 update dbm cfg using NUMDB $($numDb)"
            $db2Commands += "db2 terminate"
            $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)

            # ── Database level (DB CFG) ───────────────────────────────────────────────────
            # SELF_TUNING_MEM ON: activates STMM. Requires 2+ consumers set to AUTOMATIC.
            # DATABASE_MEMORY AUTOMATIC: STMM controls total shared DB memory pool.
            # LOCKLIST AUTOMATIC: STMM tunes lock list; also implicitly enables MAXLOCKS tuning.
            # SHEAPTHRES_SHR AUTOMATIC: tuned together with SORTHEAP by STMM.
            # PCKCACHESZ AUTOMATIC: STMM tunes package cache.
            # SORTHEAP AUTOMATIC: STMM tunes per-agent sort heap (requires SHEAPTHRES=0 at DBM level).
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM ON"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using DATABASE_MEMORY AUTOMATIC"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using LOCKLIST AUTOMATIC"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SHEAPTHRES_SHR AUTOMATIC"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using PCKCACHESZ AUTOMATIC"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SORTHEAP AUTOMATIC"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using AUTO_MAINT OFF"

            # ── Buffer pool 3-step STMM pattern ──────────────────────────────────────────
            # (db2_perf_tune_1212.md) Exception entries in SYSCAT.BUFFERPOOLDBPARTITIONS block
            # STMM from managing a buffer pool even when SIZE AUTOMATIC is set.
            # Step 1: fixed SIZE 1000 — clears any exception entries for all pools
            # Step 2: SIZE AUTOMATIC — hands all pools to STMM
            # Step 3: deactivate + activate — STMM allocates actual pages from available RAM
            # Explicit connect required: db2 update db cfg does not need an active connection so
            # the CLP shared memory connection state can drift before the piped SELECT | db2 commands.
            $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
            $db2Commands += "db2 -x `"SELECT 'ALTER BUFFERPOOL ' || RTRIM(BPNAME) || ' SIZE 1000 ;' FROM SYSCAT.BUFFERPOOLS`" | db2 +p -"
            $db2Commands += "db2 -x `"SELECT 'ALTER BUFFERPOOL ' || RTRIM(BPNAME) || ' SIZE AUTOMATIC ;' FROM SYSCAT.BUFFERPOOLS`" | db2 +p -"
            $db2Commands += "db2 connect reset"
            $db2Commands += "db2 terminate"
            $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2_OVERRIDE_BPF="
            $db2Commands += "db2stop force"
            $db2Commands += "db2start"
            $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"
        }
        elseif ($WorkObject.Db2Version -eq "StandardEdition" -and $WorkObject.Application -eq "FKM" -and $WorkObject.InstanceName -eq "DB2") {
            $db2Commands += "db2 create bufferpool IBMDEFAULTBP size 3000000 PAGESIZE 4096 >nul 2>&1"
            $db2Commands += "if %errorlevel% neq 0 ("
            $db2Commands += "   db2 alter bufferpool IBMDEFAULTBP size 3000000 >nul 2>&1"

            $db2Commands += ")"
            $db2Commands += "db2 create bufferpool BIGTAB size 2000000 PAGESIZE 4096 >nul 2>&1"
            $db2Commands += "if %errorlevel% neq 0 ("
            $db2Commands += "   db2 alter bufferpool BIGTAB size 2000000 >nul 2>&1"
            $db2Commands += ")"
            $db2Commands += "db2 create bufferpool USER32 size 5000 PAGESIZE 4096 >nul 2>&1"
            $db2Commands += "if %errorlevel% neq 0 ("
            $db2Commands += "   db2 alter bufferpool USER32 size 5000 >nul 2>&1"
            $db2Commands += ")"
            $db2Commands += "db2 alter bufferpool BIGTAB size 2000000 >nul 2>&1"
            $db2Commands += "db2 alter bufferpool USER32 size 5000 >nul 2>&1"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using AUTO_MAINT OFF"
        }
        elseif ($WorkObject.Db2Version -ne "StandardEdition" -and $WorkObject.Application -eq "FKM" -and $WorkObject.InstanceName -eq "DB2") {
            $db2Commands += "db2 create bufferpool IBMDEFAULTBP size 100000 PAGESIZE 4096 >nul 2>&1"
            $db2Commands += "if %errorlevel% neq 0 ("
            $db2Commands += "   db2 alter bufferpool IBMDEFAULTBP size 100000 >nul 2>&1"
            $db2Commands += ")"
            $db2Commands += "db2 create bufferpool BIGTAB size 500000 PAGESIZE 4096"
            $db2Commands += "if %errorlevel% neq 0 ("
            $db2Commands += "   db2 alter bufferpool BIGTAB size 500000 >nul 2>&1"
            $db2Commands += ")"
            $db2Commands += "db2 create bufferpool USER32 size 5000 PAGESIZE 4096 >nul 2>&1"
            $db2Commands += "if %errorlevel% neq 0 ("
            $db2Commands += "   db2 alter bufferpool USER32 size 5000 >nul 2>&1"
            $db2Commands += ")"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using AUTO_MAINT OFF"
        }
        else {
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using AUTO_MAINT OFF"
        }
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        if ($WorkObject.Application -eq "FKM" -and $WorkObject.InstanceName -eq "DB2") {
            #$db2Commands += "DB2 UPDATE DBM.Z_AVDTAB SET DATABASENAVN = '$($WorkObject.DatabaseName)' WHERE DATABASENAVN = 'BASISPRO'"
            $db2Commands += "db2 update DBM.Z_AVDTAB SET DATABASENAVN = '$($WorkObject.DatabaseName)'"
            $db2Commands += "db2 commit work"
        }

        $db2Commands += "db2 terminate"
        $db2Commands += "db2set -i $($WorkObject.InstanceName) DB2_OVERRIDE_BPF="
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        # $WorkObject = Add-LoggingToDatabase -WorkObject $WorkObject
        # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
    }
    catch {
        Write-LogMessage "Error setting post restore configuration for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Deletes the FKKONTO local Windows group.

.DESCRIPTION
    Removes the FKKONTO local group if it exists. Sets WorkObject.FkkontoGroupRemoved timestamp.

.PARAMETER WorkObject
    PSCustomObject to track the operation.

.EXAMPLE
    $workObject = Remove-FkkontoLocalGroup -WorkObject $workObject
    # Deletes FKKONTO group

.NOTES
    Silently continues if group doesn't exist.
#>
function Remove-FkkontoLocalGroup {
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Handling FKKONTO local group for database $($WorkObject.DatabaseName) with action: $Action" -Level INFO

        # Create/Recreate the FKKONTO local group
        $netCommand = Get-CommandPathWithFallback -Name "net"

        # Remove existing group if it exists
        try {
            $command = "$netCommand localgroup FKKONTO /delete"
            Invoke-Expression $command -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # Group might not exist, which is fine
        }
        Write-LogMessage "Removed FKKONTO local group" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "FkkontoGroupRemoved" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error managing FKKONTO local group for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Creates FKKONTO local group and adds authorized users.

.DESCRIPTION
    Creates Windows local group FKKONTO and adds predefined list of FK users plus admin users
    from WorkObject. Used specifically for INL application on DB2 instance. Sets
    WorkObject.FkkontoGroupAdded timestamp and user list.

.PARAMETER WorkObject
    PSCustomObject containing AdminUsers.

.EXAMPLE
    $workObject = Add-FkkontoLocalGroup -WorkObject $workObject
    # Creates FKKONTO group and adds ~50 predefined FK users

.NOTES
    Only applicable for INL application. User list includes SRV_RPA*, ERP users, and developers.
#>
function Add-FkkontoLocalGroup {
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$WorkObject
    )

    try {
        Write-LogMessage "Handling FKKONTO local group for database $($WorkObject.DatabaseName) with action: Add" -Level INFO

        # Create/Recreate the FKKONTO local group
        $netCommand = Get-CommandPathWithFallback -Name "net"


        # Create new group
        try {
            $command = "$netCommand localgroup FKKONTO /add"
            Invoke-Expression $command -ErrorAction SilentlyContinue | Out-Null
            Write-LogMessage "Created net localgroup FKKONTO" -Level INFO
        }
        catch {
            Write-LogMessage "Group FKKONTO already exists" -Level INFO
        }

        # Define all users to add to FKKONTO
        $fkUsers = @(
            "DEDGE\AVN",
            "DEDGE\BEN",
            "DEDGE\BRU",
            "DEDGE\FKANNHOM",
            "DEDGE\FKANNJOR",
            "DEDGE\FKANNNYG",
            "DEDGE\FKANNROL",
            "DEDGE\FKANNSOR",
            "DEDGE\FKBJOTRO",
            "DEDGE\FKCHRBOH",
            "DEDGE\FKELIAAS",
            "DEDGE\FKEVGKRO",
            "DEDGE\FKFAIMUJ",
            "DEDGE\FKHILJOH",
            "DEDGE\FKKRIKRI",
            "DEDGE\FKLENBJE",
            "DEDGE\FKLENNIE",
            "DEDGE\FKLENWOL",
            "DEDGE\FKLINMEH",
            "DEDGE\FKLIVGAU",
            "DEDGE\FKMARHA3",
            "DEDGE\FKMARMOE",
            "DEDGE\FKMETKAR",
            "DEDGE\FKNINFRI",
            "DEDGE\FKPERTMY",
            "DEDGE\FKPHILON",
            "DEDGE\FKREIGRA",
            "DEDGE\FKSILAND",
            "DEDGE\FKSTILAR",
            "DEDGE\FKTHORII",
            "DEDGE\FKTOBERG",
            "DEDGE\FKTOMOTT",
            "DEDGE\FKTONSTO",
            "DEDGE\FKTORKVI",
            "DEDGE\FKUNNALL",
            "DEDGE\HEH",
            "DEDGE\HSN",
            "DEDGE\ICO",
            "DEDGE\LYSHEI",
            "DEDGE\MEH",
            "DEDGE\RIA",
            "DEDGE\SRV_RPA2",
            "DEDGE\SRV_RPA6",
            "DEDGE\SRVERP13",
            "DEDGE\SVEGUN",
            "DEDGE\TRU",
            "DEDGE\TTA",
            "DEDGE\VSN",
            "DEDGE\QMFRUN"
        )
        $fkUsers += $WorkObject.AdminUsers

        $fkUsers = $fkUsers | Sort-Object -Unique

        # Add users to FKKONTO group
        $counter = 0
        foreach ($user in $fkUsers) {
            try {
                $counter++
                $null = Add-LocalGroupMember -Group FKKONTO -member "$user" -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-LogMessage "Failed to $($Action.ToLower()) user $user to FKKONTO group: $($_.Exception.Message)" -Level INFO
            }
        }
        if ( $WorkObject) {
            Add-Member -InputObject $WorkObject -NotePropertyName "FkkontoGroupAdded" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force
            Add-Member -InputObject $WorkObject -NotePropertyName "FkkontoGroupAddedUsers" -NotePropertyValue $fkUsers -Force
            return $WorkObject
        }

    }
    catch {
        Write-LogMessage "Error adding FKKONTO local group for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw $_
    }
}

function Get-BackupSuccessFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$OverrideBackupFolder = ""
    )   
    $successFileName = "$($WorkObject.DatabaseName)$(Get-Date -Format "yyyyMMdd").BackupSuccess"
    Write-LogMessage "Backup success file name: $($successFileName)" -Level INFO
    if ([string]::IsNullOrEmpty($OverrideBackupFolder)) {
        $currentBackupFolder = $WorkObject.BackupFolder
    }
    else {
        $currentBackupFolder = $OverrideBackupFolder
    }
    $successFilePath = "$($currentBackupFolder)\$($successFileName)"
    Write-LogMessage "Backup success file path: $($successFilePath)" -Level INFO
    return $successFilePath
}

function Get-BackupFileNameFilter {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("Any", "WithDate", "WithoutDate")]
        [string]$FilterType = "Any",
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName
    )
    $returnFilter = ""
    $dateString = ""
    switch ($FilterType) {
        "Any" {
            $returnFilter = "*.001"
            break
        }
        "WithDate" {
            $dateString = "*$(Get-Date -Format "yyyyMMdd")"
            $returnFilter = "$($DatabaseName)$($dateString)*.001"
            break
        }
        "WithoutDate" {
            $returnFilter = "$($DatabaseName)*.001"
            break
        }
    }

    Write-LogMessage "Backup file filter name for $($DatabaseName): $($returnFilter)" -Level INFO
    return $returnFilter
}

function Wait-ForBackupSuccessFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    $sendSmsWhenWaitingForBackupJobMinutes = 180
    $lastSmsSentDateTime = $null

    while (-not (Test-Path -Path $WorkObject.BackupSuccessFilePath -PathType Leaf)) {
        Write-Host "." -NoNewLine
        Start-Sleep -Seconds 20

        # Check if backup job has been started
        if ($null -eq $backupJobStartedDateTime) {
            # Check if backup job has been started
            $currentBackupFile = Get-ChildItem -Path $WorkObject.RemoteBackupFolder -Filter $WorkObject.BackupFilterWithDate | Select-Object -First 1
            if ($null -ne $currentBackupFile) {
                # Get create date of the first file
                $backupJobStartedDateTime = $currentBackupFile.CreationTime
            }
        }
        # Check if backup job has been running for too long
        else {
            $currentDate = Get-Date
            $differenceInMinutes = ($currentDate - $backupJobStartedDateTime).Minutes
            # Check if the last SMS was sent more than 10 minutes ago
            if ($null -ne $lastSmsSentDateTime) {
                $differenceInMinutesSinceLastSms = ($currentDate - $lastSmsSentDateTime).Minutes
                if ($differenceInMinutesSinceLastSms -gt 10) {
                    $lastSmsSentDateTime = $null
                }
            }
            if ($differenceInMinutes -gt $sendSmsWhenWaitingForBackupJobMinutes -and $null -eq $lastSmsSentDateTime) {
                Write-LogMessage "Backup job on $($WorkObject.ServerName) has been running for $($differenceInMinutes) minutes. Sending SMS to $($WorkObject.SmsNumbers -join ", ")." -Level WARN
                foreach ($smsNumber in $WorkObject.SmsNumbers) {
                    Send-Sms -Receiver $smsNumber -Message "$($env:COMPUTERNAME) has been waiting for backup job on $($WorkObject.ServerName) for $($differenceInMinutes) minutes. No backup success file found yet. Please check the backup job on $($WorkObject.ServerName). Backup job started at $($WorkObject.BackupJobStartedDateTime)."
                }
                $lastSmsSentDateTime = $currentDate
            }
        }
    }
    $currentBackupFile = Get-ChildItem -Path $WorkObject.RemoteBackupFolder -Filter $WorkObject.BackupFilterWithDate | Select-Object -First 1
   

    if ($null -ne $currentBackupFile) {
        # Get last write time of the first file
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupJobStartedDateTime" -NotePropertyValue $currentBackupFile.CreationTime -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupJobCompletedDateTime" -NotePropertyValue $currentBackupFile.LastWriteTime -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupJobDurationMinutes" -NotePropertyValue ($currentBackupFile.LastWriteTime - $currentBackupFile.CreationTime).TotalMinutes -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupFileFileInfo" -NotePropertyValue $currentBackupFile -Force
    }

    return $WorkObject
}
function Get-RemoteBackupFiles {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        if ([string]::IsNullOrEmpty($WorkObject.GetBackupFromEnvironment) -or $WorkObject.GetBackupFromEnvironment -eq "SKIP") {
            Write-LogMessage "No backup environment specified. Skipping backup file retrieval." -Level INFO
            return $WorkObject
        }
        ##################################################################################################################
        # Initialize local work object
        ##################################################################################################################
       
        # Get remote work object
        $remoteDatabaseName = $WorkObject.Application + $WorkObject.GetBackupFromEnvironment
        if ($WorkObject.DatabaseType -eq "FederatedDb") {
            $remoteDatabaseName = "X" + $remoteDatabaseName
        }
        $remoteWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $remoteDatabaseName -DatabaseType $WorkObject.DatabaseType -QuickMode
        if ($remoteWorkObject -is [array]) { Write-LogMessage "Multiple database configurations returned" -Level WARN; $remoteWorkObject = $remoteWorkObject[-1] }          

        # Set remote backup folder
        $remoteBackupFolder = "\\" + $remoteWorkObject.ServerName + "\$($remoteWorkObject.InstanceName)Backup"
        Add-Member -InputObject $WorkObject -NotePropertyName "RemoteBackupFolder" -NotePropertyValue $remoteBackupFolder -Force
        
        # Set backup success file path
        $successFilePath = Get-BackupSuccessFilePath -WorkObject $remoteWorkObject -OverrideBackupFolder $remoteBackupFolder
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupSuccessFilePath" -NotePropertyValue $successFilePath -Force

        # Set backup filter with date
        $backupFilterWithDate = Get-BackupFileNameFilter -DatabaseName $remoteWorkObject.DatabaseName -FilterType "WithDate"
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupFilterWithDate" -NotePropertyValue $backupFilterWithDate -Force
        
        # Set backup filter any
        $backupFilterAny = Get-BackupFileNameFilter -DatabaseName $remoteWorkObject.DatabaseName -FilterType "Any"
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupFilterAny" -NotePropertyValue $backupFilterAny -Force

              
        if (-not (Test-Path -Path $WorkObject.RemoteBackupFolder -PathType Container)) {
            Write-LogMessage "Remote backup folder $($remoteWorkObject.RemoteBackupFolder) not found. Cannot continue with backup file retrieval." -Level WARN
            return $WorkObject
        }
    

        ##################################################################################################################
        # UseNewConfigurations: check restore folder first, then PRD backup share directly (no blocking wait)
        # Avoids the multi-hour Wait-ForBackupSuccessFile when a valid backup already exists locally.
        # IMPORTANT: Must also update BackupFilterWithDate to the found filename — Restore-SingleDatabase
        # uses that filter to locate the file; it does not use RestoreFilePath directly.
        ##################################################################################################################
        if ($WorkObject.UseNewConfigurations -eq $true) {
            # Priority 1: existing *.001 file already staged in the restore folder (e.g. from a previous run)
            $existingFile = Get-ChildItem -Path $WorkObject.RestoreFolder -Filter "*.001" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($existingFile) {
                Write-LogMessage "UseNewConfigurations: Reusing existing backup file $($existingFile.Name) from restore folder (no wait)" -Level INFO
                Add-Member -InputObject $WorkObject -NotePropertyName "RestoreFilePath" -NotePropertyValue $existingFile.FullName -Force
                # Set BackupFilterWithDate to the exact filename so Restore-SingleDatabase finds it
                Add-Member -InputObject $WorkObject -NotePropertyName "BackupFilterWithDate" -NotePropertyValue $existingFile.Name -Force
                return $WorkObject
            }
            # Priority 2: copy the latest *PRD*.001 from the remote backup share without waiting for .BackupSuccess
            if (Test-Path $WorkObject.RemoteBackupFolder -PathType Container) {
                $latestPrd = Get-ChildItem -Path $WorkObject.RemoteBackupFolder -Filter $WorkObject.BackupFilterAny -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latestPrd) {
                    Write-LogMessage "UseNewConfigurations: Staging $($latestPrd.Name) from PRD backup share to restore folder (no wait)" -Level INFO
                    Copy-Item -Path $latestPrd.FullName -Destination $WorkObject.RestoreFolder -Force
                    $staged = Join-Path $WorkObject.RestoreFolder $latestPrd.Name
                    Add-Member -InputObject $WorkObject -NotePropertyName "RestoreFilePath" -NotePropertyValue $staged -Force
                    # Set BackupFilterWithDate to the exact filename so Restore-SingleDatabase finds it
                    Add-Member -InputObject $WorkObject -NotePropertyName "BackupFilterWithDate" -NotePropertyValue $latestPrd.Name -Force
                    return $WorkObject
                }
            }
            # Priority 3: PRD share inaccessible — fall through to standard blocking wait below
            Write-LogMessage "UseNewConfigurations: No local file and PRD share not accessible — falling through to standard blocking wait" -Level WARN
        }

        ##################################################################################################################
        # Wait for backup success file
        ##################################################################################################################
        Write-LogMessage "Waiting for backup success file to be available in $($WorkObject.RemoteBackupFolder)" -Level INFO
        $WorkObject = Wait-ForBackupSuccessFile -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database configurations returned" -Level WARN; $WorkObject = $WorkObject[-1] }
      
        

        # Check if backup file already exists in restore folder, for example in test environment during multiple attempts to restore the backup file from remote server
        Write-LogMessage "Verifying if backup file $($WorkObject.BackupFileFileInfo.Name) already exists in restore folder $($WorkObject.RestoreFolder)" -Level INFO
        $localRestoreFolderFileName = Join-Path $WorkObject.RestoreFolder $WorkObject.BackupFileFileInfo.Name
        Add-Member -InputObject $WorkObject -NotePropertyName "RestoreFilePath" -NotePropertyValue $localRestoreFolderFileName -Force
        if (Test-Path -Path $localRestoreFolderFileName -PathType Leaf) {
            Write-LogMessage "Backup file $($WorkObject.BackupFileFileInfo.Name) already exists: $($localRestoreFolderFileName)" -Level INFO
            return $WorkObject
        }        
    
        ##################################################################################################################
        # Remove any old backup files until there is enough free space on the restore drive
        ##################################################################################################################
        Write-LogMessage "Removing any old backup files until there is enough free space on the restore drive to copy the new backup file locally." -Level INFO
        # Get free space on restore drive
        $localRestoreDrive = $WorkObject.RestoreFolder.Substring(0, 2)
        $localBackupDrive = $WorkObject.BackupFolder.Substring(0, 2)
        $driveInfo = New-Object System.IO.DriveInfo($localRestoreDrive)
        $freeSpace = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)
        $freeSpaceAfterCopy = $freeSpace

        # Get file size in GB for backup files
        $fileInfo = Get-ItemProperty -Path $WorkObject.BackupFileFileInfo.FullName -ErrorAction SilentlyContinue | Select-Object *
        $remoteBackupFileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
        Add-Member -InputObject $WorkObject -NotePropertyName "RemoteBackupFileSizeGB" -NotePropertyValue $remoteBackupFileSizeGB -Force
        Write-LogMessage "Backup file size: $($WorkObject.RemoteBackupFileSizeGB) GB" -Level INFO
        $freeSpaceAfterCopy -= $WorkObject.RemoteBackupFileSizeGB

        # Check if there is enough free space on the restore drive
        if ($freeSpaceAfterCopy -lt 0) {
            Write-LogMessage "Not enough free space on restore drive" -Level WARN
            # Remove oldest local backup and restore files until there is enough free space
            $oldestBackupRestoreFiles = @()
            if ($localBackupDrive -eq $localRestoreDrive) {
                $oldestBackupRestoreFiles += Get-ChildItem -Path $WorkObject.BackupFolder -Filter $WorkObject.BackupFilterAny
            }
            $oldestBackupRestoreFiles += Get-ChildItem -Path $WorkObject.RestoreFolder -Filter $WorkObject.BackupFilterAny
            $oldestBackupRestoreFiles = @($oldestBackupRestoreFiles | Sort-Object -Property LastWriteTime)

            foreach ($oldBackupFile in $oldestBackupRestoreFiles) {
                # Remove the oldest backup file from the list
                Write-LogMessage "Removing oldest local backup/restore file: $($oldBackupFile.FullName)" -Level INFO
                $freeSpaceAfterCopy += [math]::Round($oldBackupFile.Length / 1GB, 2)
                Remove-Item -Path $oldBackupFile.FullName -Force -ErrorAction SilentlyContinue | Out-Null

                if ($freeSpaceAfterCopy -ge 0) {
                    break
                }
            }

            if ($freeSpaceAfterCopy -lt 0) {
                Write-LogMessage "Not enough free space on restore drive after removing old backup/restore files" -Level ERROR
                throw "Not enough free space on restore drive after removing old backup/restore files"
            }
        }
        Add-Member -InputObject $WorkObject -NotePropertyName "FreeSpaceAfterCopy" -NotePropertyValue $freeSpaceAfterCopy -Force
        # Copy backup files to restore folder
        Write-LogMessage "Starting to copy remote backup file $($WorkObject.BackupFileFileInfo.Name) to $($WorkObject.RestoreFolder)" -Level INFO
        Copy-Item -Path $WorkObject.BackupFileFileInfo.FullName -Destination $WorkObject.RestoreFolder -Force -ErrorAction SilentlyContinue | Out-Null
        Add-Member -InputObject $WorkObject -NotePropertyName "RestoreFilePath" -NotePropertyValue $($WorkObject.RestoreFolder + "\" + $WorkObject.BackupFileFileInfo.Name) -Force
        Write-LogMessage "Copy completed and not avalible for restore: $($WorkObject.RestoreFilePath)" -Level INFO
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


# function Get-RemoteBackupFilesNew {
#     param(
#         [Parameter(Mandatory = $false)]
#         [string]$InstanceName = "DB2",
#         [Parameter(Mandatory = $true)]
#         [string]$GetBackupFromEnvironment,
#         [Parameter(Mandatory = $true)]
#         [string]$Filter,
#         [Parameter(Mandatory = $false)]
#         [ValidateSet("PrimaryDb", "FederatedDb")]
#         [string]$DatabaseType = "PrimaryDb",
#         [Parameter(Mandatory = $false)]
#         [string[]]$SmsNumbers = @()
#     )
#     try {
#         $numberOfRemoteBackupFiles = 0
#         $localRestoreFolder = $(Find-ExistingFolder -Name "$($InstanceName)Restore")
#         $localBackupFolder = $(Find-ExistingFolder -Name "$($InstanceName)Backup")
#         if ([string]::IsNullOrEmpty($GetBackupFromEnvironment) -or $GetBackupFromEnvironment -eq "SKIP") {
#             Write-LogMessage "No backup environment specified. Skipping backup file retrieval." -Level INFO
#             return
#         }

#         $remoteBackupFiles = @()
#         $remoteDatabaseName = $(Get-ApplicationNameFromInstanceName -InstanceName $InstanceName) + $GetBackupFromEnvironment

#         Write-LogMessage "Getting database port configuration from Get-DatabasesV2Json" -Level INFO
#         $fromComputerName = $(Get-DatabasesV2Json) | Where-Object { $_.Database -eq $remoteDatabaseName -and $_.Provider -eq "DB2" -and $_.Version -eq "2.0" } | Select-Object -ExpandProperty ServerName -First 1
#         Write-LogMessage "Source server name: $fromComputerName" -Level INFO

#         $fromComputerDb2BackupFolder = "\\" + $fromComputerName + "\$($InstanceName)Backup"
#         if (Test-Path -Path $fromComputerDb2BackupFolder -PathType Container) {
#             if (-not [string]::IsNullOrEmpty($GetBackupFromEnvironment)) {
#                 $primarySuccessFileName = Get-BackupSuccessFilePath -WorkObject $remoteWorkObject -OverrideBackupFolder $remoteBackupFolder
#                 $federatedSuccessFileName = Get-BackupSuccessFilePath -WorkObject $remoteWorkObject -OverrideBackupFolder $remoteBackupFolder
#                 #modify filter name to include YYYYMMDD

#                 $PrimaryFilter = $(Get-BackupFileNameFilter -DatabaseType "PrimaryDb" -Environment $GetBackupFromEnvironment -FilterType "WithDate")
#                 $FederatedFilter = $(Get-BackupFileNameFilter -DatabaseType "FederatedDb" -Environment $GetBackupFromEnvironment -FilterType "WithDate")
#                 # Get primary backup success file
#                 if ($DatabaseType -eq "PrimaryDb" -or $DatabaseType -eq "BothDatabases") {
#                     Write-LogMessage "Waiting for primary backup success file to be available in $fromComputerDb2BackupFolder" -Level INFO
#                     Wait-ForBackupSuccessFile -InstanceName $InstanceName -GetBackupFromEnvironment $GetBackupFromEnvironment -SuccessFilePath $primarySuccessFileName -BackupFolder $fromComputerDb2BackupFolder -ServerName $fromComputerName -SmsNumbers $SmsNumbers -DatabaseType "PrimaryDb"
#                     Write-LogMessage "Primary backup success file found in $fromComputerDb2BackupFolder. Waiting 10 seconds before continuing" -Level INFO
#                     Start-Sleep -Seconds 10
#                 }

#                 # Get federated backup success file
#                 if ($DatabaseType -eq "FederatedDb" -or $DatabaseType -eq "BothDatabases") {
#                     Write-LogMessage "Waiting for federated backup success file to be available in $fromComputerDb2BackupFolder" -Level INFO
#                     Wait-ForBackupSuccessFile -InstanceName $InstanceName -GetBackupFromEnvironment $GetBackupFromEnvironment -SuccessFilePath $federatedSuccessFileName -BackupFolder $fromComputerDb2BackupFolder -ServerName $fromComputerName -SmsNumbers $SmsNumbers -DatabaseType "FederatedDb"
#                     Write-LogMessage "Federated backup success file found in $fromComputerDb2BackupFolder. Waiting 10 seconds before continuing" -Level INFO
#                     Start-Sleep -Seconds 10
#                 }
#             }

#             # Get primary backup file
#             $latestBackupPrimaryarr = Get-ChildItem -Path $fromComputerDb2BackupFolder -Filter $PrimaryFilter | Sort-Object LastWriteTime -Descending
#             if ($latestBackupPrimaryarr.Count -ne 0) {
#                 $latestBackupPrimaryarr | Format-List -Property FullName, LastWriteTime
#                 $latestBackupPrimary = $latestBackupPrimaryarr | Select-Object -First 1
#                 $remoteBackupFiles += $latestBackupPrimary.FullName
#             }

#             # Get federated backup file
#             $latestBackupFederatedarr = Get-ChildItem -Path $fromComputerDb2BackupFolder -Filter $FederatedFilter | Sort-Object LastWriteTime -Descending
#             if ($latestBackupFederatedarr.Count -ne 0) {
#                 $latestBackupFederated | Format-List -Property FullName, LastWriteTime
#                 $latestBackupFederated = $latestBackupFederatedarr | Select-Object -First 1
#                 $remoteBackupFiles += $latestBackupFederated.FullName
#             }

#             if ($remoteBackupFiles.Count -eq 0) {
#                 Write-LogMessage "No backup files found in $fromComputerDb2BackupFolder" -Level INFO
#                 return
#             }

#             # Delete all files in the restore folder
#             Write-LogMessage "Verifying if backup files already exist in restore folder" -Level INFO
#             # Check if primary db file file exists in the restore folder
#             $restoreFolderFiles = Get-ChildItem -Path "$($localRestoreFolder)\*" -File
#             $foundPrimaryFile = $false
#             $foundFederatedFile = $false
#             if ($restoreFolderFiles.Count -gt 0) {
#                 foreach ($restoreFolderFile in $restoreFolderFiles) {
#                     if ($restoreFolderFile.Name -eq $($latestBackupPrimary.Name) -and -not $foundPrimaryFile) {
#                         Write-LogMessage "Backup file $($restoreFolderFile.Name) already exists in restore folder" -Level INFO
#                         $foundPrimaryFile = $true
#                     }
#                     if ($restoreFolderFile.Name -eq $($latestBackupFederated.Name) -and -not $foundFederatedFile) {
#                         Write-LogMessage "Backup file $($restoreFolderFile.Name) already exists in restore folder" -Level INFO
#                         $foundFederatedFile = $true
#                     }
#                 }
#             }
#             $newRemoteBackupFiles = @()

#             if (-not $foundPrimaryFile -and ($DatabaseType -eq "PrimaryDb" -or $DatabaseType -eq "BothDatabases")) {
#                 Write-LogMessage "Primary backup file $($latestBackupPrimary.Name) not found in restore folder. Deleting previous backup files for primary db" -Level INFO
#                 Get-ChildItem -Path "$($localRestoreFolder)\*" -File -Filter $PrimaryFilter -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
#                 $newRemoteBackupFiles += $latestBackupPrimary.FullName
#             }

#             if (-not $foundFederatedFile -and ($DatabaseType -eq "FederatedDb" -or $DatabaseType -eq "BothDatabases")) {
#                 Write-LogMessage "Federated backup file $($latestBackupFederated.Name) not found in restore folder. Deleting previous backup files for federated db" -Level INFO
#                 Get-ChildItem -Path "$($localRestoreFolder)\*" -File -Filter $FederatedFilter -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
#                 $newRemoteBackupFiles += $latestBackupFederated.FullName
#             }

#             if ($newRemoteBackupFiles.Count -eq 0) {
#                 Write-LogMessage "No new backup files found. Continuing with existing backup files" -Level INFO
#                 return
#             }

#             $remoteBackupFiles = $newRemoteBackupFiles

#             # Get free space on restore drive
#             $localRestoreDrive = $localRestoreFolder.Substring(0, 2)
#             $localBackupDrive = $localBackupFolder.Substring(0, 2)
#             $driveInfo = New-Object System.IO.DriveInfo($localRestoreDrive)
#             $freeSpace = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)
#             $freeSpaceAfterCopy = $freeSpace


#             foreach ($remoteBackupFile in $remoteBackupFiles) {
#                 # Get file size in GB for backup files
#                 $fileInfo = Get-ItemProperty -Path $remoteBackupFile | Select-Object *
#                 $remoteBackupFileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
#                 Write-LogMessage "Backup file size: $remoteBackupFileSizeGB GB" -Level INFO
#                 $freeSpaceAfterCopy -= $remoteBackupFileSizeGB
#             }



#             # Check if there is enough free space on the restore drive
#             if ($freeSpaceAfterCopy -lt 0) {
#                 Write-LogMessage "Not enough free space on restore drive" -Level WARN
#                 # Remove oldest local backup and restore files until there is enough free space
#                 $oldestBackupRestoreFiles = @()
#                 if ($localBackupDrive -eq $localRestoreDrive) {
#                     $oldestBackupRestoreFiles += Get-ChildItem -Path $localBackupFolder -Filter $(Get-BackupFileNameFilter -FilterType "Any")
#                 }
#                 $oldestBackupRestoreFiles += Get-ChildItem -Path $localRestoreFolder -Filter $(Get-BackupFileNameFilter -FilterType "Any")
#                 $oldestBackupRestoreFiles = @($oldestBackupRestoreFiles | Sort-Object LastWriteTime)

#                 foreach ($oldBackupFile in $oldestBackupRestoreFiles) {
#                     # Remove the oldest backup file from the list
#                     Write-LogMessage "Removing oldest local backup/restore file: $($oldBackupFile.FullName)" -Level INFO
#                     $freeSpaceAfterCopy += [math]::Round($oldBackupFile.Length / 1GB, 2)
#                     Remove-Item -Path $oldBackupFile.FullName -Force -ErrorAction SilentlyContinue | Out-Null

#                     if ($freeSpaceAfterCopy -ge 0) {
#                         break
#                     }
#                 }

#                 if ($freeSpaceAfterCopy -lt 0) {
#                     Write-LogMessage "Not enough free space on restore drive after removing old backup/restore files" -Level ERROR
#                     throw "Not enough free space on restore drive after removing old backup/restore files"
#                 }
#             }
#             # Copy backup files to restore folder
#             foreach ($remoteBackupFile in $remoteBackupFiles) {
#                 Write-LogMessage "Starting to copy remote backup file $remoteBackupFile to $localRestoreFolder" -Level INFO
#                 Copy-Item -Path $remoteBackupFile -Destination $localRestoreFolder -Force -ErrorAction SilentlyContinue | Out-Null
#                 Write-LogMessage "Completed copying remote backup file $remoteBackupFile to $localRestoreFolder" -Level INFO
#                 $numberOfRemoteBackupFiles++
#             }
#         }
#     }
#     catch {
#         Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
#         throw $_
#     }
# }


<#
.SYNOPSIS
    Performs backup of a single Db2 database (online or offline).

.DESCRIPTION
    Comprehensive backup operation that:
    - Checks for existing backups and keeps only most recent
    - Tests database recoverability (log archiving enabled)
    - Adds logging if needed to enable online backup
    - Performs online backup (with INCLUDE LOGS) or offline backup (EXCLUDE LOGS)
    - Creates backup success file on completion
    - Sends SMS notifications
    - Exports backup report to HTML and JSON
    
    Automatically switches to offline mode if database doesn't support online backup.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, InstanceName, BackupFolder, BackupType, and SmsNumbers.

.EXAMPLE
    $workObject = Backup-SingleDatabase -WorkObject $workObject
    # Performs database backup and sends SMS on completion

.NOTES
    Creates .BackupSuccess file and JSON report in BackupFolder. Handles both online
    and offline backup modes. Critical for production backup automation.
#>
function Backup-SingleDatabase {   
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $WorkObject
    )
    $Offline = $false
    # Reset override output folder
    Reset-OverrideAppDataFolder

    Write-LogMessage "Starting backup for $($WorkObject.DatabaseType) $($WorkObject.DatabaseName)" -Level INFO

    # Set override output folder
    Set-OverrideAppDataFolder -Path $WorkObject.WorkFolder

    # Check if there is an ok file for today
    if (Test-Path -Path $WorkObject.BackupSuccessFileName -PathType Leaf) {
        Write-LogMessage "Backup success file for today found. Removing it." -Level WARN
        Remove-Item -Path $WorkObject.BackupSuccessFileName -Force -ErrorAction SilentlyContinue
    }


    # Get all backup files starting with FKMPRD in the g:\Db2Backup folder
    $backupFiles = Get-ChildItem -Path "$($WorkObject.BackupFolder)" -Filter "$($WorkObject.DatabaseName)*"
    # Start logging
    Write-LogMessage "Starting backup cleanup process" -Level INFO
    Write-LogMessage "Looking for $($WorkObject.DatabaseName) backup files in $($WorkObject.BackupFolder)" -Level INFO

    # If there are multiple backup files
    if ($backupFiles.Count -gt 1) {
        Write-LogMessage "Found $($backupFiles.Count) backup files" -Level INFO

        # Sort files by last write time descending (newest first)
        $sortedFiles = $backupFiles | Sort-Object LastWriteTime -Descending
        Write-LogMessage "Keeping newest file: $($sortedFiles[0].Name)" -Level INFO

        # Skip the first (newest) file and delete the rest
        $filesToDelete = $sortedFiles | Select-Object -Skip 1
        Write-LogMessage "Will delete $($filesToDelete.Count) old backup files" -Level INFO


        foreach ($file in $filesToDelete) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Successfully deleted old backup file: $($file.Name)" -Level INFO
            }
            catch {
                Write-LogMessage "ERROR: Failed to delete file $($file.Name) - $($_.Exception.Message)" -Level ERROR
                if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
                    foreach ($smsNumber in $WorkObject.SmsNumbers) {
                        Send-Sms -Receiver $smsNumber -Message "Feil ved sletting av gammel backup-fil!"
                    }
                }
                Send-FkAlert -Program "Db2-Backup" -Code "9998" -Message "Feil ved sletting av gammel backup-fil!"
            }
        }
        $fileList = $filesToDelete | Select-Object -Property Name
        Add-Member -InputObject $WorkObject -NotePropertyName "DeletedBackupFiles" -NotePropertyValue $($fileList -join "`n") -Force
    }
    elseif ($backupFiles.Count -eq 1) {
        Write-LogMessage "Found only 1 backup file, no cleanup needed" -Level INFO
    }
    else {
        Write-LogMessage "WARNING: No $($WorkObject.DatabaseName) backup files found in $($WorkObject.BackupFolder)" -Level WARN
    }

    Write-LogMessage "Backup cleanup process completed" -Level INFO
    Add-Member -InputObject $WorkObject -NotePropertyName "LogFile" -NotePropertyValue "$($WorkObject.BackupFolder)\backup_$($WorkObject.DatabaseName).log" -Force
    Add-Member -InputObject $WorkObject -NotePropertyName "MsgFile" -NotePropertyValue "$($WorkObject.BackupFolder)\backup_$($WorkObject.DatabaseName).msg" -Force
    Remove-Item -Path $WorkObject.LogFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $WorkObject.MsgFile -Force -ErrorAction SilentlyContinue
    # if ($(Get-EnvironmentFromServerName) -eq "PRD" -And $(Get-ApplicationFromServerName) -eq "DOC") {
    #     Add-Member -InputObject $WorkObject -NotePropertyName "DbUser" -NotePropertyValue "SRV_SFKSS07" -Force
    #     Add-Member -InputObject $WorkObject -NotePropertyName "DbPassword" -NotePropertyValue "Mandag123" -Force
    # }

    # Check if database supports online backup
    $WorkObject = Test-DatabaseRecoverability -WorkObject $WorkObject
    if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
    $supportsOnlineBackup = $WorkObject.DatabaseRecoverable
    Add-Member -InputObject $WorkObject -NotePropertyName "SupportsOnlineBackup" -NotePropertyValue $supportsOnlineBackup -Force
    # Add logging to database
    if (-not $supportsOnlineBackup) {
        try {
            foreach ($smsNumber in $WorkObject.SmsNumbers) {
                Send-Sms -Receiver $smsNumber -Message "Database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME) does not support online backup.`nAdding logging to database $($WorkObject.DatabaseName) so it can be backed up online after the logging change is completed."
            }
            $WorkObject = Add-LoggingToDatabase -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

            # Check again if database supports online backup
            $WorkObject = Test-DatabaseRecoverability -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            if (-not $WorkObject.DatabaseRecoverable) {
                Write-LogMessage "Database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME) still does not support online backup after attempting to add logging during the restore process." -Level WARN
                foreach ($smsNumber in $WorkObject.SmsNumbers) {
                    Send-Sms -Receiver $smsNumber -Message "Database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME) still does not support online backup after attempting to add logging during the restore process."
                }
            }

        }
        catch {
            Write-LogMessage "Error adding logging to database $($WorkObject.DatabaseName): $($_.Exception.Message)" -Level ERROR -Exception $_.Exception
            foreach ($smsNumber in $WorkObject.SmsNumbers) {
                Send-Sms -Receiver $smsNumber -Message "Error adding logging to database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME): $($_.Exception.Message)"
            }
        }
    }
    if (-not $supportsOnlineBackup -and -not $Offline) {
        Write-LogMessage "Database $($WorkObject.DatabaseName) does not support online backup, switching to offline mode for this database" -Level  INFO
        $Offline = $true
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupTypeChangedToOffline" -NotePropertyValue $(Get-Date -Format "yyyyMMdd_HHmmss") -Force
    }
    Add-Member -InputObject $WorkObject -NotePropertyName "Offline" -NotePropertyValue $Offline.ToString() -Force
    $db2Commands = @()
    if ($Offline) {
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 quiesce database immediate force connections"
        $db2Commands += "db2 connect reset"
        # $db2Commands += "db2 deactivate database $($WorkObject.DatabaseName)"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 -l$($WorkObject.LogFile) -z$($WorkObject.MsgFile) backup database $($WorkObject.DatabaseName) to ""$($WorkObject.BackupFolder)"" exclude logs without prompting"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 unquiesce database"
        $db2Commands += "db2 connect reset"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate database $($WorkObject.DatabaseName)"
        $filename = Join-Path $WorkObject.WorkFolder "OfflineBackup_$($WorkObject.DatabaseName).bat"
    }
    else {
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 -l$($WorkObject.LogFile) -z$($WorkObject.MsgFile) backup database $($WorkObject.DatabaseName) online to $($WorkObject.BackupFolder) with 10 BUFFERS BUFFER 2050 PARALLELISM 10 UTIL_IMPACT_PRIORITY 75 include logs"
        $db2Commands += "set DB2INSTANCE=DB2"
        $filename = Join-Path $WorkObject.WorkFolder "OnlineBackup_$($WorkObject.DatabaseName).bat"
    }
    try {
        Write-LogMessage "Content: $($db2Commands -join "`n")" -Level INFO
        Write-LogMessage "Filename: $($filename)" -Level INFO
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $filename
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "Backup" -Script $($db2Commands -join "`n") -Output $output

        $msg = Get-Content -Path $WorkObject.MsgFile
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupMsg" -NotePropertyValue $msg -Force
        $log = Get-Content -Path $WorkObject.LogFile
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupLog" -NotePropertyValue $log -Force

        if ($($msg -join "`n") -match '(\d{14})') {
            $systemTime = $matches[1]
        }
        else {
            $systemTime = $null
        }
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupSystemTime" -NotePropertyValue $systemTime -Force


        Add-Content -Path $WorkObject.MsgFile -Value "BackupSystemTime: $($systemTime)"

        if ($systemTime) {
            $backupFile = Get-ChildItem -Path $WorkObject.BackupFolder -Filter "$($WorkObject.DatabaseName)*$($systemTime).001" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($backupFile) {
                # $backupMode = if ($Offline) { "OFFLINE" } else { "ONLINE" }
                # $renamedBackupFile = $backupFile.FullName.Replace($backupFile.Extension, ".$backupMode.001")
                # Rename-Item -Path $backupFile.FullName -NewName $renamedBackupFile
                # Write-LogMessage "Backup file renamed to $($renamedBackupFile)" -Level INFO
                Add-Member -InputObject $WorkObject -NotePropertyName "BackupFileFound" -NotePropertyValue $true.ToString() -Force
                New-Item -Path $WorkObject.BackupSuccessFileName -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
                Write-LogMessage "Backup success file created: $($WorkObject.BackupSuccessFileName) for $($WorkObject.DatabaseType) $($WorkObject.DatabaseName)" -Level INFO
                Add-Member -InputObject $WorkObject -NotePropertyName "Result" -NotePropertyValue "Success" -Force

            }
            else {
                Write-LogMessage "Backup file not found" -Level ERROR
                Add-Member -InputObject $WorkObject -NotePropertyName "BackupFileFound" -NotePropertyValue $false.ToString() -Force
                Add-Member -InputObject $WorkObject -NotePropertyName "Result" -NotePropertyValue "Backup file not found after backup" -Force
            }
        }

        # Export primary database object to html file
        Write-LogMessage "Exporting $($WorkObject.DatabaseType) database object to html file" -Level INFO
        $outputFileName = "$($WorkObject.WorkFolder)\Db2-Backup-Report-$($WorkObject.DatabaseName).html"
        Export-WorkObjectToHtmlFile -Title "Db2-Backup Report for $($WorkObject.DatabaseName) on $($env:COMPUTERNAME.ToUpper())" -WorkObject $WorkObject -FileName $outputFileName -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2/$($WorkObject.DatabaseName.ToUpper())"
        # Export primary database object to json file
        Write-LogMessage "Exporting $($WorkObject.DatabaseType) database object to json file" -Level INFO
        $outputFileName = "$($WorkObject.BackupFolder)\Db2-Backup_$($WorkObject.DatabaseName)_$($WorkObject.BackupSystemTime).json"
        Export-WorkObjectToJsonFile -WorkObject $WorkObject -FileName $outputFileName


        Write-LogMessage "Backup completed successfully" -Level INFO
        $message = "Db2-Backup SUCCESS on $($env:COMPUTERNAME).`nDatabase: $($WorkObject.DatabaseName.ToUpper()).`nBackupType: $($WorkObject.BackupType)`nBackupfileTimestamp: $($WorkObject.BackupSystemTime)"
        foreach ($smsNumber in $WorkObject.SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $message
        }
        Send-FkAlert -Program $(Get-InitScriptName) -Code "0000" -Message $message -Force
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_.Exception
        $message = "Db2-Backup FAILED on $($env:COMPUTERNAME).`nDatabase: $($WorkObject.DatabaseName.ToUpper()).`nBackupType: $($WorkObject.BackupType)`nBackupFileTimestamp: $($WorkObject.BackupSystemTime)`nErrorMessage: $($_.Exception.Message)"
        foreach ($smsNumber in $WorkObject.SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $message
        }
        Send-FkAlert -Program "Db2-Backup" -Code "9999" -Message $message -Force
    }
    finally {
        # Reset override output folder
        Reset-OverrideAppDataFolder
    }
}


function Start-Db2Backup {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $false)]
        [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
        [string]$DatabaseType = "PrimaryDb",
        [Parameter(Mandatory = $false)]
        [string]$BackupType = "Online",
        [Parameter(Mandatory = $false)]
        [string[]]$SmsNumbers = @(),
        [Parameter(Mandatory = $false)]
        [string]$OverrideWorkFolder = ""
    )
    try {
        Write-LogMessage "Initiating backup of Db2 databases on server $($env:COMPUTERNAME)" -Level INFO

        # Check if script is running on a server
        if (-not (Test-IsServer)) {
            Write-LogMessage "This script must be run on a server" -Level ERROR
            throw "This script must be run on a server"
        }

        #########################################################
        # Handle Primary database
        #########################################################
        if ($DatabaseType -eq "PrimaryDb" -or $DatabaseType -eq "BothDatabases") {
            Write-LogMessage "Starting backup for primary database" -Level INFO
            $workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers
            if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
            Add-Member -InputObject $workObject -NotePropertyName "BackupType" -NotePropertyValue $BackupType -Force
            Add-Member -InputObject $workObject -NotePropertyName "BackupSuccessFileName" -NotePropertyValue "" -Force
            Add-Member -InputObject $workObject -NotePropertyName "SmsNumbers" -NotePropertyValue $SmsNumbers -Force
            # $WorkObject = [PSCustomObject]@{
            #     BackupType            = $BackupType
            #     DatabaseName          = $(Get-DatabaseNameFromServerName)
            #     InstanceName          = "DB2"
            #     WorkFolder            = if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) { $OverrideWorkFolder } else { Get-ApplicationDataPath }
            #     BackupSuccessFileName = ""
            #     DatabaseType          = "PrimaryDb"
            #     SmsNumbers            = $SmsNumbers
            # }

            # # Get Db2 folders
            # Write-LogMessage "Getting Db2 folders" -Level INFO
            # $WorkObject = Get-Db2Folders -WorkObject $WorkObject
            # if ($WorkObject -is [array]) { $WorkObject = $WorkObject[-1] }

            # Add WorkFolder to database object
            # Write-LogMessage "Adding WorkFolder to database object" -Level INFO
            # $WorkObject.WorkFolder = $(Join-Path $(Get-ApplicationDataPath) $WorkObject.DatabaseName $(Get-Date -Format "yyyyMMdd-HHmmss"))
            $workObject.BackupSuccessFileName = Get-BackupSuccessFilePath -WorkObject $workObject 
            New-Item -Path $workObject.WorkFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

            # Start backup for primary database
            Write-LogMessage "Starting backup for $($workObject.DatabaseName)" -Level INFO
            $workObject = Backup-SingleDatabase -WorkObject $workObject
            if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

            Write-LogMessage "Backup of $($workObject.DatabaseType) $($workObject.DatabaseName) completed successfully" -Level INFO
        }
        #########################################################
        # Handle Federated database
        #########################################################
        if ($DatabaseType -eq "FederatedDb" -or $DatabaseType -eq "BothDatabases") {
            Write-LogMessage "Starting backup for federated database" -Level INFO
            $workObject = Get-DefaultWorkObjects -DatabaseType "FederatedDb" -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers
            if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
            Add-Member -InputObject $workObject -NotePropertyName "BackupType" -NotePropertyValue $BackupType -Force
            Add-Member -InputObject $workObject -NotePropertyName "BackupSuccessFileName" -NotePropertyValue "" -Force
            Add-Member -InputObject $workObject -NotePropertyName "SmsNumbers" -NotePropertyValue $SmsNumbers -Force
            Add-Member -InputObject $workObject -NotePropertyName "WorkFolder" -NotePropertyValue $(Join-Path $(Get-ApplicationDataPath) $workObject.DatabaseName $(Get-Date -Format "yyyyMMdd-HHmmss")) -Force
            #$WorkObject = [PSCustomObject]@{
            #     BackupType            = $BackupType
            #     DatabaseName          = "X" + $(Get-DatabaseNameFromServerName)
            #     InstanceName          = "DB2FED"
            #     WorkFolder            = if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) { $OverrideWorkFolder } else { Get-ApplicationDataPath }
            #     BackupSuccessFileName = ""
            #     DatabaseType          = "FederatedDb"
            #     SmsNumbers            = $SmsNumbers
            # }
            # # Get Db2 folders
            # Write-LogMessage "Getting Db2 folders" -Level INFO
            # $WorkObject = Get-Db2Folders -WorkObject $WorkObject -Quiet:$Quiet
            # if ($WorkObject -is [array]) { $WorkObject = $WorkObject[-1] }


            # Add WorkFolder to database object
            # Write-LogMessage "Adding WorkFolder to database object" -Level INFO
            # $workObject.WorkFolder = $(Join-Path $(Get-ApplicationDataPath) $workObject.DatabaseName $(Get-Date -Format "yyyyMMdd-HHmmss"))
            $workObject.BackupSuccessFileName = Get-BackupSuccessFilePath -WorkObject $workObject
            New-Item -Path $workObject.WorkFolder -ItemType Directory -Force -ErrorAction SilentlyContinue

            # Start backup for federated database
            Write-LogMessage "Starting backup for $($workObject.DatabaseName)" -Level INFO
            $workObject = Backup-SingleDatabase -WorkObject $workObject
            if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
        }
        Write-LogMessage "Db2 Backup of $($workObject.DatabaseType) completed successfully on $($env:COMPUTERNAME.ToUpper())" -Level INFO
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_.Exception
        throw "Db2-Backup failed"
    }
}


function Get-DefaultWorkObjectFromBackupFileName {
    param(
        [string]$DatabaseType,
        [string]$RestoreFile,
        [string]$Buffer,
        [string]$Parallelism,
        [string]$InstanceName,
        [string]$OverrideWorkFolder = "",
        [string[]]$SmsNumbers = @()
    )

    
    if ($DatabaseType -eq "PrimaryDb") {
        $databaseName = $(Get-PrimaryDbNameFromInstanceName -InstanceName $InstanceName)
    }
    else {
        $databaseName = $(Get-FederatedDbNameFromInstanceName -InstanceName $InstanceName)
        if ([string]::IsNullOrEmpty($databaseName)) {
            Write-LogMessage "Federated database not in config (e.g. UseNewConfigurations). Use PrimaryDb restore only." -Level ERROR
            throw "Federated database name not found for instance name $InstanceName. Use PrimaryDb restore only."
        }
    }
    Write-LogMessage "Starting Db2 Restore for $($RestoreFile) to $($databaseName)" -Level INFO

    # Common initialization
    $workFolder = if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) { $OverrideWorkFolder } else { Get-ApplicationDataPath }

    $workFolder = Join-Path $workFolder $databaseName $($(Get-Date -Format "yyyyMMdd-HHmmss"))
    if (-not (Test-Path -Path $workFolder -PathType Container)) {
        New-Item -Path $workFolder -ItemType Directory -Force | Out-Null
    }
    # Set override output folder
    if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) {
        Set-OverrideAppDataFolder -Path $workFolder
    }

    # Create restore job object from backup file metadata
    Write-LogMessage "Creating restore job object from restore file metadata: $($RestoreFile)" -Level INFO
    $splitRestoreFile = $RestoreFile.Split(".")
    $fromDatabaseNameWork = $splitRestoreFile[0]
    $fromDatabaseName = [string] $(Split-Path -Path $fromDatabaseNameWork -Leaf)
    # $fromApplication = $fromDatabaseName.Substring(0, 3)
    $fromEnvironment = $fromDatabaseName.Substring(3, 3)

    $fileDatabaseType = if ($splitRestoreFile.Count -gt 0) { if ($splitRestoreFile[0].ToUpper().StartsWith("X")) { "FederatedDb" } else { "PrimaryDb" } } else { $null }
    if ($fileDatabaseType -ne $DatabaseType) {
        Write-LogMessage "Database type mismatch between restore file and instance name. Restore file database type: $fileDatabaseType, Instance name database type: $DatabaseType" -Level ERROR
        throw "Database type mismatch between restore file and instance name. Restore file database type: $fileDatabaseType, Instance name database type: $DatabaseType"
    }

    $workObject = Get-DefaultWorkObjects -DatabaseType $fileDatabaseType -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

    Add-Member -InputObject $workObject -NotePropertyName "SourceDatabaseName" -NotePropertyValue $fromDatabaseName -Force
    Add-Member -InputObject $workObject -NotePropertyName "SourceEnvironment" -NotePropertyValue $fromEnvironment -Force
    Add-Member -InputObject $workObject -NotePropertyName "DatabasePart" -NotePropertyValue $(if ($splitRestoreFile.Count -gt 3) { $splitRestoreFile[3] } else { $null }) -Force
    Add-Member -InputObject $workObject -NotePropertyName "Timestamp" -NotePropertyValue $(if ($splitRestoreFile.Count -gt 4) { $splitRestoreFile[4] } else { $null }) -Force
    Add-Member -InputObject $workObject -NotePropertyName "BackupMode" -NotePropertyValue $(if ($splitRestoreFile.Count -gt 5) { if ($splitRestoreFile[5].ToUpper().Trim() -eq "ONLINE") { "Online" } elseif ($splitRestoreFile[5].ToUpper().Trim() -eq "OFFLINE") { "Offline" } else { "Online" } } else { "Online" }) -Force
    Add-Member -InputObject $workObject -NotePropertyName "BackupFile" -NotePropertyValue $RestoreFile -Force
    Add-Member -InputObject $workObject -NotePropertyName "Buffer" -NotePropertyValue $Buffer -Force
    Add-Member -InputObject $workObject -NotePropertyName "Parallelism" -NotePropertyValue $Parallelism -Force
    Add-Member -InputObject $workObject -NotePropertyName "ServerName" -NotePropertyValue $env:COMPUTERNAME -Force

    return $workObject
}

function Invoke-ModifiedRestoreContainerScript {
    param(
        [psobject]$workObject,
        [string]$Step3GeneratedRestoreContainerScriptFile
    )

    Write-LogMessage "Modifying the generated restore script to use the correct paths and parameters" -Level INFO
    if (-not (Test-Path -Path $Step3GeneratedRestoreContainerScriptFile -PathType Leaf)) {
        Write-LogMessage "Error: $($Step3GeneratedRestoreContainerScriptFile) not found" -Level ERROR
        throw "Error: $($Step3GeneratedRestoreContainerScriptFile) not found"
    }

    # Read the generated restore script and modify it to use the correct paths and parameters
    $cmd400ModifiedRestoreContainerScript = [System.IO.File]::ReadAllText($Step3GeneratedRestoreContainerScriptFile, [System.Text.Encoding]::GetEncoding(1252))
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- DBPATH ON '<målkatalog'", "DBPATH ON '$($(Get-PrimaryDb2DataDisk))'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- LOGTARGET '<katalog>'", "LOGTARGET '$($WorkObject.LogtargetFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- LOGTARGET DEFAULT", "LOGTARGET '$($WorkObject.LogtargetFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH '<katalog>'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH DEFAULT", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH 'E:\\Db2PrimaryLogs\\'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH 'F:\\Db2PrimaryLogs\\'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH 'G:\\Db2PrimaryLogs\\'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH 'E:\\Db2Logs\\'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH 'F:\\Db2Logs\\'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- NEWLOGPATH 'G:\\Db2Logs\\'", "NEWLOGPATH '$($WorkObject.PrimaryLogsFolder)\'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- BUFFER <bufferstørrelse>", "BUFFER $($workObject.Buffer)"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- REPLACE EXISTING", "REPLACE EXISTING"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- PARALLELISM <n>", "PARALLELISM $($workObject.Parallelism)"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- WITHOUT PROMPTING", "WITHOUT PROMPTING"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "^\s*PATH\s+'E:\\DB\\(.*)'", "  PATH   '$($WorkObject.TablespacesFolder)\$1'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript.Replace("  PATH   'E:\DB\BASISREG\", "  PATH   '$($WorkObject.TablespacesFolder)\$($workObject.DatabaseName)\")
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript.Replace("  PATH   'E:\DB\", "  PATH   '$($WorkObject.TablespacesFolder)\")
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript.Replace("  PATH   'F:\DB\", "  PATH   '$($WorkObject.TablespacesFolder)\")
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "(?i)SET TABLESPACE CONTAINERS FOR\s+(\d+)\s+USING\s*\(\s*PATH\s+'(?![C-G]:)([^']*)'\s*\)", "SET TABLESPACE CONTAINERS FOR `$1 USING ( PATH   '$($WorkObject.TablespacesFolder)\`$2' )"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "(?i)PATH\s+'(?![C-G]:)([^']+)'", "PATH   '$($WorkObject.TablespacesFolder)\`$1'"
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace "-- SET STOGROUP PATHS FOR IBMSTOGROUP", "SET STOGROUP PATHS FOR IBMSTOGROUP ON '$($(Get-PrimaryDb2DataDisk))\';"

    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript.Replace("Db2Tablespaces\RD", "Db2Tablespaces\$($WorkObject.DatabaseName)\RD")
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript.Replace("Db2Tablespaces\DS", "Db2Tablespaces\$($WorkObject.DatabaseName)\DS")
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript.Replace("Db2Tablespaces\RA", "Db2Tablespaces\$($WorkObject.DatabaseName)\RA")
        
        
    # Replace Ø with O in paths and ø with o
    $cmd400ModifiedRestoreContainerScript = $cmd400ModifiedRestoreContainerScript -replace '(?<=PATH\s+''[^'']*?)Ø', 'O' -replace '(?<=PATH\s+''[^'']*?)ø', 'o'
    $db2Commands = @()
    $db2Commands += $cmd400ModifiedRestoreContainerScript
    $db2Commands += " "

    # Run the modified restore container script to perform the actual restore
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType SQL -FileName $(Join-Path $workObject.WorkFolder "RestoreStep4ModifiedRestoreContainerScript.sql") -InstanceName $workObject.InstanceName
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "ModifiedRestoreContainer" -Script ($db2Commands -join "`n") -Output $output

    return $workObject
}

function Invoke-Db2OnlineRollforwardAndActivate {
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$WorkObject
    )
    $step5RollforwardAndActivateScriptFile = Join-Path $WorkObject.WorkFolder "RestoreStep5RollforwardAndActivateScript.bat"


    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"

    if ($WorkObject.SourceEnvironment -eq "PRD" -and $WorkObject.Environment -eq "RAP") {
        $db2Commands += "db2 rollforward db $($WorkObject.DatabaseName) to end of logs and stop overflow log path($($WorkObject.LogtargetFolder))"
    }
    else {
        $db2Commands += "db2 rollforward db $($WorkObject.DatabaseName) to end of logs and stop overflow log path($($WorkObject.LogtargetFolder))"
    }
    $db2Commands += "db2start"
    $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"
    $db2Commands += " "

    # Handle special cases where the rollforward and activate script fails, due to database not ready yet
    $errorCount = 0
    try {
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $step5RollforwardAndActivateScriptFile
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script ($db2Commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error executing rollforward and activate script. Waiting and retrying..." -Level ERROR -Exception $_
        $errorCount++
    }
    if ($errorCount -gt 0) {
        Write-LogMessage "Error executing rollforward and activate script. Waiting 60 seconds and retrying..." -Level INFO
        Start-Sleep -Seconds 60
        try {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $step5RollforwardAndActivateScriptFile
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script ($db2Commands -join "`n") -Output $output
            Add-Member -InputObject $WorkObject -NotePropertyName "RollforwardAndActivateOutput" -NotePropertyValue $output -Force
        }
        catch {
            Write-LogMessage "Error executing rollforward and activate script. Aborting.."
            throw "Error executing rollforward and activate script. Aborting: $($_.Exception.Message)"
        }
    }


    # Handle special when backup file integrity seems to be corrupted
    if ($WorkObject.RollforwardAndActivateOutput -like "*SQL1265N*") {
        Write-LogMessage "Initiating validation of the restore input file before aborting the restore. Check the logfiles for more details of the validation after completion." -Level INFO
        $result = Test-BackupFileIntegrity -BackupFile $WorkObject.BackupFile -WorkFolder $WorkObject.WorkFolder
        if ($result -eq "Failed") {
            throw "Backup file integrity failed. Provide a consistent backup file and try restore again. Result: $result"
        }
        else {
            throw "Backup file integrity verified, but still got SQL1265N error. Check the logfiles for more details of the validation after completion."
        }
    }

    # Extract timestamp from rollforward output
    if ($WorkObject.RollforwardAndActivateOutput -match "Siste iverksatte transaksjon\s*=\s*(\d{4}-\d{2}-\d{2}-\d{2}\.\d{2}\.\d{2}\.\d{6})") {
        try {
            $db2Timestamp = $matches[1]
            Write-LogMessage "Extracted DB2 timestamp: $db2Timestamp" -Level DEBUG
            # Convert DB2 timestamp format (2025-09-12-22.31.43.000000) to standard format
            if ($db2Timestamp -match "^(\d{4}-\d{2}-\d{2})-(\d{2})\.(\d{2})\.(\d{2})\.(\d{6})$") {
                $datePart = $matches[1]        # 2025-09-12
                $hour = $matches[2]            # 22
                $minute = $matches[3]          # 31
                $second = $matches[4]          # 43
                $microseconds = $matches[5]    # 000000

                # Convert microseconds to milliseconds (take first 3 digits)
                $milliseconds = $microseconds.Substring(0, 3)

                # Build standard datetime string
                $standardFormat = "$datePart $hour`:$minute`:$second.$milliseconds"
                Write-LogMessage "Converted to standard format: $standardFormat" -Level DEBUG

                # Parse as UTC and convert to local time
                $utcDateTime = [datetime]::ParseExact($standardFormat, "yyyy-MM-dd HH:mm:ss.fff", $null)
                $utcDateTime = [datetime]::SpecifyKind($utcDateTime, [System.DateTimeKind]::Utc)
                $localDateTime = $utcDateTime.ToLocalTime()

                Add-Member -InputObject $WorkObject -NotePropertyName "LastTransactionTimestamp" -NotePropertyValue $localDateTime -Force
                Write-LogMessage "Last transaction timestamp: $localDateTime (converted from UTC)" -Level INFO
            }
            else {
                Write-LogMessage "Unexpected DB2 timestamp format: $db2Timestamp" -Level WARN
            }
            

            # Detect the latest log target file by looking through the list of the log target files and find the file with the highest LastWriteTime.
            $latestLogTargetFile = $WorkObject.LogTargetFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $latestLogTargetFileInfo = [pscustomobject]@{
                Name          = $latestLogTargetFile.Name
                LastWriteTime = $latestLogTargetFile.LastWriteTime
            }
            Add-Member -InputObject $WorkObject -NotePropertyName "LatestLogTargetFileInfo" -NotePropertyValue $latestLogTargetFileInfo -Force
 
        }
        catch {
            Write-LogMessage "Error extracting timestamp from rollforward output: $($_.Exception.Message)" -Level ERROR
            Write-LogMessage "Raw timestamp value: $db2Timestamp" -Level ERROR
        }
    }
    return $WorkObject
}


function Invoke-Db2OfflineActivate {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$WorkObject
    )

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
    $db2Commands += "db2start"
    $db2Commands += "db2 activate db $($WorkObject.DatabaseName)"
    $db2Commands += " "

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "OfflineActivate.bat")" -IgnoreErrors
    $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "OfflineActivate" -Script ($db2Commands -join "`n") -Output $output

    if ($output -like "*SQL1117N*" -or $output -like "*SQL5099N*") {
        if ($output -like "*SQL1117N*") {
            Write-LogMessage "Database in ROLL-FORWARD PENDING - running rollforward to end of logs and complete" -Level WARN
        }
        if ($output -like "*SQL5099N*") {
            Write-LogMessage "Database config has invalid path (SQL5099N) - fixing log paths for target instance" -Level WARN
        }
        $rfCommands = @()
        $rfCommands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        if ($output -like "*SQL1117N*") {
            $rfCommands += "db2 rollforward db $($WorkObject.DatabaseName) to end of logs and complete"
        }
        if (-not [string]::IsNullOrEmpty($WorkObject.MirrorLogsFolder)) {
            $rfCommands += "db2 update db cfg for $($WorkObject.DatabaseName) using MIRRORLOGPATH `"$($WorkObject.MirrorLogsFolder)`""
        }
        if (-not [string]::IsNullOrEmpty($WorkObject.PrimaryLogsFolder)) {
            $rfCommands += "db2 update db cfg for $($WorkObject.DatabaseName) using NEWLOGPATH `"$($WorkObject.PrimaryLogsFolder)`""
        }
        $rfCommands += "db2 activate db $($WorkObject.DatabaseName)"
        $rfOutput = Invoke-Db2ContentAsScript -Content $rfCommands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "RollforwardFixPathsAndActivate.bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "RollforwardFixPathsAndActivate" -Script ($rfCommands -join "`n") -Output $rfOutput
        if ($rfOutput -like "*SQL1117N*" -or $rfOutput -like "*SQL5099N*") {
            throw "Database still has pending issues after rollforward/path fix: check logs"
        }
    }
    elseif ($output -like "*SQL1265N*") {
        Write-LogMessage "Initiating validation of the restore input file before aborting the restore. Check the logfiles for more details of the validation after completion." -Level INFO
        $result = Test-BackupFileIntegrity -BackupFile $WorkObject.BackupFile -WorkFolder $WorkObject.WorkFolder
        if ($result -eq "Failed") {
            throw "Backup file integrity failed. Provide a consistent backup file and try restore again. Result: $result"
        }
        else {
            throw "Backup file integrity verified, but still got SQL1265N error. Check the logfiles for more details of the validation after completion."
        }
    }
    return $WorkObject
}
# # TODO: Remove this once we have tested the new logic
# if (1 -eq 2) {
#     try {

#         # Backup log target files on local server to new folder
#         Send-Sms -Receiver "+4797188358" -Message "Klart for debug på $($env:COMPUTERNAME)"
#         Add-Member -InputObject $workObject -NotePropertyName "BackupLogTargetFolder" -NotePropertyValue $($WorkObject.LogtargetFolder + "_Backup") -Force
#         if (-not (Test-Path -Path $workObject.BackupLogTargetFolder -PathType Container)) {
#             New-Item -Path $workObject.BackupLogTargetFolder -ItemType Directory -Force | Out-Null
#         }
#         # Copy log target files to new folder
#         Copy-Item -Path "$($WorkObject.LogtargetFolder)\*" -Destination $workObject.BackupLogTargetFolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

#         if (($workObject.SourceEnvironment -eq "PRD" -and $workObject.Environment -eq "RAP") -or ($workObject.SourceEnvironment -eq "PRD" -and $workObject.Environment -eq "PRD")) {
#             # Read database port configuration from Get-DatabasesV2Json
#             Write-LogMessage "Getting database port configuration from Get-DatabasesV2Json" -Level INFO
#             $sourceServerName = $(Get-DatabasesV2Json) | Where-Object { $_.Database -eq $workObject.SourceDatabaseName -and $_.Provider -eq "DB2" -and $_.Version -eq "2.0" } | Select-Object -ExpandProperty ServerName -First 1
#             Write-LogMessage "Source server name: $sourceServerName" -Level INFO

#             if ($workObject.SourceEnvironment -eq "PRD" -and $workObject.Environment -eq "PRD") {
#                 Write-Host "Do you want to retrieve logs from backup server (p-no1bck-01) instead of local mirror logs on $($sourceServerName)? (Y/N)"
#                 Write-Host "Defaulting to local mirror logs in 30 seconds..."

#                 $timeoutJob = Start-Job -ScriptBlock {
#                     param($timeout)
#                     Start-Sleep -Seconds $timeout
#                 } -ArgumentList 30

#                 $useBackupServer = $null
#                 while ($null -eq $useBackupServer) {
#                     if (Wait-Job $timeoutJob -Timeout 1) {
#                         Write-Host "Timeout reached - using local mirror logs"
#                         $useBackupServer = "N"
#                         break
#                     }
#                     if ([Console]::KeyAvailable) {
#                         $key = [Console]::ReadKey($true)
#                         if ($key.Key -eq "Y" -or $key.Key -eq "y") {
#                             $useBackupServer = "Y"
#                         }
#                         elseif ($key.Key -eq "N" -or $key.Key -eq "n") {
#                             $useBackupServer = "N"
#                         }
#                     }
#                 }

#                 Stop-Job $timeoutJob
#                 Remove-Job $timeoutJob

#                 if ($useBackupServer -eq "Y") {
#                     $sourceServerAdditionalLogFiles = "\\p-no1bck-01\BackupDB2\$($sourceServerName)"
#                 }
#                 else {
#                     $sourceServerAdditionalLogFiles = "\\$($sourceServerName)\Db2MirrorLogs"
#                 }
#             }
#             else {
#                 $sourceServerAdditionalLogFiles = "\\$($sourceServerName)\Db2MirrorLogs"
#             }
#             #\\p-no1bck-01\BackupDB2\p-no1fkmprd-db
#             Write-LogMessage "Source server mirror log path: $sourceServerAdditionalLogFiles" -Level INFO
#             # Find files in sourceServerMirrorLogPath that are newer than $latestLogTargetFile.LastWriteTime
#             #$additionalLogTargetFiles = Get-ChildItem -Path $sourceServerAdditionalLogFiles -File | Where-Object { $_.LastWriteTime -gt $latestLogTargetFile.LastWriteTime }

#             $copyToFolder = ""
#             if ($logTargetFiles.Count) {
#                 $copyToFolder = $logTargetFiles[0].DirectoryName

#             }

#             $additionalLogTargetFiles = Get-ChildItem -Path $sourceServerAdditionalLogFiles -File -Recurse -Filter *.LOG | Where-Object {
#                 # Extract number from last log file name (e.g. S2800056 from S2800056.LOG)
#                 $latestLogNumber = [regex]::Match($latestLogTargetFileNameOnly, 'S(\d+)\.LOG').Groups[1].Value

#                 # Extract number from current file name
#                 $currentFileMatch = [regex]::Match($_.Name, 'S(\d+)\.LOG')
#                 if ($currentFileMatch.Success) {
#                     $currentNumber = $currentFileMatch.Groups[1].Value
#                     # Compare numeric values
#                     [int]$currentNumber -gt [int]$latestLogNumber
#                 }
#                 else {
#                     $false
#                 }
#             }


#             if ($additionalLogTargetFiles.Count -gt 0) {
#                 Write-LogMessage "New log target files found in $sourceServerAdditionalLogFiles" -Level INFO
#                 $additionalLogTargetFiles | Format-Table -Property FullName, LastWriteTime
#                 foreach ($additionalLogTargetFile in $additionalLogTargetFiles) {
#                     Copy-Item -Path $additionalLogTargetFile.FullName -Destination $copyToFolder -Force -ErrorAction SilentlyContinue | Out-Null
#                 }
#             }

#             # Attempt rollforward and activate
#             $tempOutput = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $Step5RollforwardAndActivateScriptFile
#             if (-not [string]::IsNullOrEmpty($workObject.RollforwardAndActivateOutput)) {
#                 Add-Member -InputObject $workObject -NotePropertyName "Step5-Result" -NotePropertyValue "Success" -Force
#             }
#             else {
#                 Add-Member -InputObject $workObject -NotePropertyName "Step5-Result" -NotePropertyValue "Failed" -Force
#             }
#             $db2Commands = @()
#             # Add the output to the backup job object, since if it failed it would be in the catch part
#             $workObject.RollforwardAndActivateOutput = $tempOutput

#         }
#     }
#     catch {
#         Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
#         # Rename the backup folder as standard log target folder
#         Remove-Item -Path $WorkObject.LogtargetFolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
#         Move-Item -Path $workObject.BackupLogTargetFolder -Destination $WorkObject.LogtargetFolder -Force -ErrorAction SilentlyContinue | Out-Null
#         $workObject.RollforwardAndActivateOutput = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $Step5RollforwardAndActivateScriptFile

#     }
# }
# else {
#     $workObject.RollforwardAndActivateOutput = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $Step5RollforwardAndActivateScriptFile
# }
<#
.SYNOPSIS
    Restores a single Db2 database from backup file.

.DESCRIPTION
    Comprehensive restore operation that:
    1. Retrieves remote backup file from source environment if specified
    2. Decodes backup file metadata (source DB, environment, timestamp, mode)
    3. Prepares target database (quiesce, deactivate, clean log folders)
    4. Generates restore container script
    5. Modifies script with correct paths (DBPATH, LOGTARGET, NEWLOGPATH, tablespace paths)
    6. Executes restore with container redirect
    7. Performs rollforward (online) or activate (offline)
    8. Applies standard configurations
    9. Exports restore report and sends SMS notifications
    
    Handles both online (with log rollforward) and offline (direct activate) restores.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, RestoreFolder, GetBackupFromEnvironment,
    WorkFolder, SmsNumbers, and folder paths (PrimaryLogsFolder, LogtargetFolder, TablespacesFolder).

.EXAMPLE
    $workObject = Restore-SingleDatabase -WorkObject $workObject
    # Restores database from backup file

.NOTES
    If GetOnlyBackupFilesFromEnvironment=true, only copies backup file without restoring.
    Validates backup file integrity on SQL1265N errors. Sends SMS on success/failure.
#>
function Restore-SingleDatabase {   
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$WorkObject
    )
    try {       
        # Get remote backup files
        $WorkObject = Get-RemoteBackupFiles -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        if ($WorkObject.GetOnlyBackupFilesFromEnvironment) {
            Write-LogMessage "Getting only backup files from environment for $($WorkObject.DatabaseName). Resultfile: $($WorkObject.RestoreFilePath)" -Level INFO
            return $WorkObject
        }
        if ($WorkObject.UseNewConfigurations -eq $true -and [string]::IsNullOrEmpty($WorkObject.BackupFilterWithDate)) {
            $datePart = (Get-Date).ToString("yyyyMMdd")
            $fallbackFilter = "*$($datePart)*.001"
            if (-not (Get-ChildItem -Path $WorkObject.RestoreFolder -Filter $fallbackFilter -ErrorAction SilentlyContinue)) { $fallbackFilter = "*.001" }
            Add-Member -InputObject $WorkObject -NotePropertyName "BackupFilterWithDate" -NotePropertyValue $fallbackFilter -Force
            Write-LogMessage "BackupFilterWithDate not set; using $($fallbackFilter) for shadow/local restore" -Level INFO
        }
        # Get latest restore file
        $latestRestoreFile = Get-ChildItem -Path $WorkObject.RestoreFolder -Filter $WorkObject.BackupFilterWithDate | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $latestRestoreFile) {
            Write-LogMessage "No backup files found in $($WorkObject.RestoreFolder) matching filter $($WorkObject.BackupFilterWithDate) - skipping restore" -Level WARN
            return $WorkObject
        }

        # Create restore job object from restore file metadata
        Write-LogMessage "Decoding restore file metadata: $($latestRestoreFile.FullName)" -Level INFO
        $splitRestoreFile = $latestRestoreFile.Name.Split(".")
        $fromDatabaseNameWork = $splitRestoreFile[0]
        $fromDatabaseName = [string] $(Split-Path -Path $fromDatabaseNameWork -Leaf)
        $fromEnvironment = $fromDatabaseName.Substring(3, 3)

        $fileDatabaseType = if ($splitRestoreFile.Count -gt 0) { if ($splitRestoreFile[0].ToUpper().StartsWith("X")) { "FederatedDb" } else { "PrimaryDb" } } else { $null }
        if ($fileDatabaseType -ne $WorkObject.DatabaseType) {
            Write-LogMessage "Database type mismatch between restore file and instance name. Restore file database type: $fileDatabaseType, Instance name database type: $WorkObject.DatabaseType" -Level ERROR
            return $WorkObject
        }

        Add-Member -InputObject $WorkObject -NotePropertyName "SourceDatabaseName" -NotePropertyValue $fromDatabaseName -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "SourceEnvironment" -NotePropertyValue $fromEnvironment -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "DatabasePart" -NotePropertyValue $(if ($splitRestoreFile.Count -gt 3) { $splitRestoreFile[3] } else { $null }) -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "Timestamp" -NotePropertyValue $(if ($splitRestoreFile.Count -gt 4) { $splitRestoreFile[4] } else { $null }) -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupMode" -NotePropertyValue $(if ($splitRestoreFile.Count -gt 5) { if ($splitRestoreFile[5].ToUpper().Trim() -eq "ONLINE") { "Online" } elseif ($splitRestoreFile[5].ToUpper().Trim() -eq "OFFLINE") { "Offline" } else { "Online" } } else { "Online" }) -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "BackupFile" -NotePropertyValue $latestRestoreFile.FullName -Force
        $remoteServer = if ($WorkObject.ServerName) { $WorkObject.ServerName } else { $env:COMPUTERNAME }
        Add-Member -InputObject $WorkObject -NotePropertyName "RemoteServerName" -NotePropertyValue $remoteServer -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "Buffer" -NotePropertyValue "2050" -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "Parallelism" -NotePropertyValue "10" -Force

        $smsMessage = "Db2-Restore STARTED of $($WorkObject.DatabaseName) `nfrom $($WorkObject.SourceDatabaseName) `non $($WorkObject.ServerName).`nRestorefileTimestamp: $($WorkObject.Timestamp)"
        foreach ($smsNumber in $WorkObject.SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $smsMessage
        }

        # Remove and create logtarget folder
        #Write-LogMessage "Removing and creating logtarget folder" -Level INFO
        # if (Test-Path -Path $WorkObject.LogtargetFolder) {
        #     Remove-Item -Path $WorkObject.LogtargetFolder -Recurse -Force -ErrorAction Stop | Out-Null
        #     $WorkObject = Get-Db2Folders -WorkObject $WorkObject -FolderName "LogtargetFolder"
        #     if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        # }
           

        # Generate pre-restore script
        Write-LogMessage "Generating pre-restore script" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2stop force"
        $db2Commands += "rd /s /q $($WorkObject.PrimaryLogsFolder)"
        $db2Commands += "md $($WorkObject.PrimaryLogsFolder)"
        $db2Commands += "rd /s /q $($WorkObject.MirrorLogsFolder)"
        $db2Commands += "md $($WorkObject.MirrorLogsFolder)"
        $db2Commands += "rd /s /q $($WorkObject.LogtargetFolder)"
        $db2Commands += "md $($WorkObject.LogtargetFolder)"

        $db2Commands += "db2start"
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 quiesce database immediate force connections"
        $db2Commands += "db2 connect reset"
        $db2Commands += "db2 deactivate database $($WorkObject.DatabaseName)"

        # Prepare target database for restore
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $(Join-Path $WorkObject.WorkFolder "RestoreStep1PrepareScript.bat") -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "PreRestore" -Script $($db2Commands -join "`n") -Output $output 
        if ($output -like "*SQL1092N*") {
            Write-LogMessage "Error during prepare step. Continuing with restore anyway." -Level WARN
        }

        $WorkObject = Get-Db2Folders -WorkObject $WorkObject -FolderName "LogtargetFolder"
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $WorkObject = Get-Db2Folders -WorkObject $WorkObject -FolderName "PrimaryLogsFolder"
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $WorkObject = Get-Db2Folders -WorkObject $WorkObject -FolderName "MirrorLogsFolder"
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Generate the restore container script
        Write-LogMessage "Generating the restore container script" -Level INFO
        $Step3GeneratedRestoreContainerScriptFile = Join-Path $WorkObject.WorkFolder "RestoreStep3GeneratedRestoreContainerScript.sql"
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2 restore database $($WorkObject.SourceDatabaseName) FROM '$($WorkObject.RestoreFolder)' TAKEN AT $($WorkObject.Timestamp) INTO $($WorkObject.DatabaseName) REDIRECT GENERATE SCRIPT '$($Step3GeneratedRestoreContainerScriptFile)'"
        $useIgnoreErrors = if ($WorkObject.UseNewConfigurations -eq $true) { @{ IgnoreErrors = $true } } else { @{} }
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $(Join-Path $WorkObject.WorkFolder "RestoreStep2RestoreContainerScript.bat") @useIgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "CreateRestoreContainer" -Script $($db2Commands -join "`n") -Output $output

        # SQL2532N: backup internal metadata has a different DB name than the filename
        # Regex: match "databasen "<DBNAME>"" (Norwegian) or "database "<DBNAME>"" (English)
        if ($WorkObject.UseNewConfigurations -eq $true -and $output -match "SQL2532N") {
            $actualDbMatch = [regex]::Match($output, '(?:databasen|database)\s+"([^"]+)"')
            if ($actualDbMatch.Success) {
                $actualSourceDb = $actualDbMatch.Groups[1].Value
                Write-LogMessage "SQL2532N: Backup is from '$($actualSourceDb)', not '$($WorkObject.SourceDatabaseName)'. Retrying." -Level WARN
                $WorkObject.SourceDatabaseName = $actualSourceDb
                $db2Commands = @()
                $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
                $db2Commands += "db2 restore database $($WorkObject.SourceDatabaseName) FROM '$($WorkObject.RestoreFolder)' TAKEN AT $($WorkObject.Timestamp) INTO $($WorkObject.DatabaseName) REDIRECT GENERATE SCRIPT '$($Step3GeneratedRestoreContainerScriptFile)'"
                $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $(Join-Path $WorkObject.WorkFolder "RestoreStep2RestoreContainerScript_Retry.bat")
                $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "CreateRestoreContainerRetry" -Script $($db2Commands -join "`n") -Output $output
            }
        }

        # Modify the generated restore script to use the correct paths and parameters
        $WorkObject = Invoke-ModifiedRestoreContainerScript -WorkObject $WorkObject -Step3GeneratedRestoreContainerScriptFile $Step3GeneratedRestoreContainerScriptFile

        # Count files in Logtarget folder to determine if the restore was online or offline
        $logTargetFiles = $(Get-ChildItem -Path $($WorkObject.LogtargetFolder) -File -Recurse -Filter *.LOG | Select-Object -Property FullName, LastWriteTime, DirectoryName )

        # Add log target file count to backup job object
        Add-Member -InputObject $WorkObject -NotePropertyName "LogTargetFiles" -NotePropertyValue $logTargetFiles -Force

        # Prepare for rollforward and activate, but do not execute, since we are trying to retrieve logs after backup was completed, and add it to the logtarget folder
        Write-LogMessage "Logtarget folder contains $($WorkObject.LogTargetFiles.Count) files" -Level INFO
        if ($WorkObject.LogTargetFiles.Count -gt 0) {
            $WorkObject.BackupMode = "Online"
            $WorkObject = Invoke-Db2OnlineRollforwardAndActivate -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WUERROR -WindowsFEATURE: "WindowsFeature_FilmLinkingDisplays"; $WorkObject = $WorkObject[-1] }
        }
        else {
            Write-LogMessage "Logtarget folder contains no files" -Level INFO
            $WorkObject.BackupMode = "Offline"
            $WorkObject = Invoke-Db2OfflineActivate -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WUERROR -WindowsFEATURE: "WindowsFeature_FilmLinkingDisplays"; $WorkObject = $WorkObject[-1] }
        }


        if (-not $SkipDbConfiguration) {            
            # Add Db2 standard configuration for current instance
            $WorkObject = Set-StandardConfigurations -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        }
      
        Write-LogMessage "Restore-SingleDatabase completed successfully for $($WorkObject.SourceDatabaseName) into $($WorkObject.DatabaseName)" -Level INFO
        $outputFileName = Join-Path $WorkObject.WorkFolder  $(Split-Path -Path $WorkObject.BackupFile -Leaf).Replace(".001", ".html")
        Export-WorkObjectToHtmlFile -Title "Db2-Restore Report for $($WorkObject.DatabaseName.ToUpper()) on $($env:COMPUTERNAME.ToUpper())" -WorkObject $WorkObject -FileName $outputFileName -AutoOpen $false -AddToDevToolsWebPath $false -DevToolsWebDirectory "Db2/$($WorkObject.DatabaseName.ToUpper())"

        # Send SMS to TechOps
        $smsMessage = ""
        $smsMessage += "Db2-Restore SUCCESS of $($WorkObject.DatabaseName) `nfrom $($WorkObject.SourceDatabaseName) `non $($env:COMPUTERNAME).`nBackupfileTimestamp: $($WorkObject.Timestamp)"
        if ($WorkObject.ControlRowCount -and $WorkObject.ControlRowCount -gt 0) {
            $smsMessage += "`nControlRowCount: $($WorkObject.ControlRowCount). "
        }
        $smsMessage += "`nCheck logfiles for more details: $($WorkObject.WorkFolder)"
        foreach ($smsNumber in $WorkObject.SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $smsMessage
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
        Write-LogMessage "Db2-Restore FAILED" -Level ERROR
        $smsMessage = "Db2-Restore FAILED of $($WorkObject.DatabaseName) `nfrom $($WorkObject.SourceDatabaseName) `non $($env:COMPUTERNAME).`nBackupfileTimestamp: $($WorkObject.Timestamp). `nErrorMessage: $($_.Exception.Message)"
        $smsMessage += "`nCheck logfiles for more details: $($WorkObject.WorkFolder)"
        foreach ($smsNumber in $WorkObject.SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $smsMessage
        }
        throw "Restore failed"
    }
    finally {
        # Reset override output folder
        Reset-OverrideAppDataFolder
    }
}


function Start-Db2Restore {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PrimaryInstanceName,
        [Parameter(Mandatory = $false)]
        [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
        [string]$DatabaseType = "BothDatabases",
        [Parameter(Mandatory = $false)]
        [string]$GetBackupFromEnvironment,
        [Parameter(Mandatory = $false)]
        [switch]$SkipDbConfiguration = $false,
        [Parameter(Mandatory = $false)]
        [string[]]$SmsNumbers = @(),
        [Parameter(Mandatory = $false)]
        [string]$OverrideWorkFolder = "",
        [Parameter(Mandatory = $false)]
        [switch]$GetOnlyBackupFilesFromEnvironment = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )

    try {
        Write-LogMessage "Restoring $($PrimaryInstanceName) for $($DatabaseType) from backup-file started" -Level INFO

        if ($GetBackupFromEnvironment -eq "SKIP") {
            $GetBackupFromEnvironment = ""
        }
        # Check if script is running on a server
        if (-not (Test-IsDb2Server -Quiet $true)) {
            Write-LogMessage "This script must be run on a server" -Level ERROR
            throw "This script must be run on a server"
        }

        # Check if script is running as administrator
        if (-not ( [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-LogMessage "This script must be run as administrator" -Level ERROR
            throw "This script must be run as administrator"
        }

        $primaryInstanceName = $PrimaryInstanceName
        $federatedInstanceName = if ($UseNewConfigurations) { "N/A" } else { $(try { Get-FederatedDbNameFromInstanceName -InstanceName $PrimaryInstanceName } catch { "N/A" }) }
        if ($null -eq $federatedInstanceName) { $federatedInstanceName = "N/A" }
        $workObjects = @()
        if ($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "PrimaryDb") {
            # Get local work object and set local restore and backup folders
            $primaryWorkObject = Get-DefaultWorkObjects -InstanceName $primaryInstanceName -GetBackupFromEnvironment $GetBackupFromEnvironment -DatabaseType "PrimaryDb" -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
            if ($primaryWorkObject -is [array]) { Write-LogMessage "Multiple database configurations returned" -Level WARN; $primaryWorkObject = $primaryWorkObject[-1] }
            Add-Member -InputObject $primaryWorkObject -NotePropertyName "GetOnlyBackupFilesFromEnvironment" -NotePropertyValue $GetOnlyBackupFilesFromEnvironment -Force
            if ($UseNewConfigurations -and [string]::IsNullOrEmpty($primaryWorkObject.BackupFilterWithDate) -and (Test-Path $primaryWorkObject.RestoreFolder)) {
                $any001 = Get-ChildItem -Path $primaryWorkObject.RestoreFolder -Filter "*.001" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($any001) {
                    $datePart = (Get-Date).ToString("yyyyMMdd")
                    $filter = "*$($datePart)*.001"
                    if (-not (Get-ChildItem -Path $primaryWorkObject.RestoreFolder -Filter $filter)) { $filter = "*.001" }
                    Add-Member -InputObject $primaryWorkObject -NotePropertyName "BackupFilterWithDate" -NotePropertyValue $filter -Force
                    Write-LogMessage "Set BackupFilterWithDate=$($filter) for shadow/empty env restore" -Level INFO
                }
            }
            $workObjects += $primaryWorkObject
        }
        if (($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") -and -not $UseNewConfigurations) {
            # Get local work object and set local restore and backup folders
            $federatedWorkObject = Get-DefaultWorkObjects -InstanceName $primaryInstanceName -GetBackupFromEnvironment $GetBackupFromEnvironment -DatabaseType "FederatedDb" -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
            if ($federatedWorkObject -is [array]) { Write-LogMessage "Multiple database configurations returned" -Level WARN; $federatedWorkObject = $federatedWorkObject[-1] }
            Add-Member -InputObject $federatedWorkObject -NotePropertyName "GetOnlyBackupFilesFromEnvironment" -NotePropertyValue $GetOnlyBackupFilesFromEnvironment -Force
            $workObjects += $federatedWorkObject
        }
        elseif (($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") -and $UseNewConfigurations) {
            Write-LogMessage "UseNewConfigurations: Skipping federated database — XINLTST is now an alias on the primary instance" -Level INFO
        }
      
        foreach ($workObject in $workObjects) {
            $workObject = Restore-SingleDatabase -WorkObject $workObject
            if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
            Write-LogMessage "Restoring $($federatedInstanceName) for $($DatabaseType) from backup-file completed" -Level INFO
        }
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Start-Db2Restore failed"
    }
    return $workObjects
}

<#
.SYNOPSIS
    Generates application-specific control SQL statement for database validation.

.DESCRIPTION
    Creates a control SQL statement based on Application type:
    - FKM: SELECT from DBM.Z_AVDTAB or DBM.AH_ORDREHODE
    - INL: SELECT from INL.KONTOTYPE
    - DOC: SELECT from DBM.MODUL
    - VIS: SELECT from V0001.ACTR_HOLSTAD
    
    Sets WorkObject.ControlSqlStatement and TableToCheck properties.

.PARAMETER WorkObject
    PSCustomObject containing Application and DatabaseType.

.PARAMETER SelectCount
    When true, generates "SELECT COUNT(*)" instead of "SELECT *".

.PARAMETER RowCount
    Number of rows to fetch. Default is 10 (uses FETCH FIRST n ROWS ONLY).

.PARAMETER ForceGetControlSqlStatement
    Generates statement even for FederatedDb (normally only for PrimaryDb).

.EXAMPLE
    $workObject = Get-ControlSqlStatement -WorkObject $workObject
    # Sets control SQL statement for database verification

.NOTES
    Used post-restore to verify database contains expected application tables and data.
#>
function Get-ControlSqlStatement {
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$SelectCount = $false,
        [Parameter(Mandatory = $false)]
        [int]$RowCount = 10,
        [Parameter(Mandatory = $false)]
        [switch]$ForceGetControlSqlStatement = $false
    )

    try {
        Write-LogMessage "Getting control SQL statement for application $($WorkObject.Application)" -Level INFO
        if ($WorkObject.DatabaseType -eq "PrimaryDb" -or $ForceGetControlSqlStatement) {
            switch ($WorkObject.Application) {
                "FKM" {
                    $controlSqlStatement = "db2 `"select "
                    if ($SelectCount) {
                        $controlSqlStatement += "count(*)"
                    }
                    else {
                        $controlSqlStatement += "*"
                    }
                    $controlSqlStatement += " from dbm.z_avdtab FETCH FIRST $RowCount ROWS ONLY`""
                    $tableToCheck = "dbm.z_avdtab"
                }

                "INL" {
                    $controlSqlStatement = "db2 `"select "
                    if ($SelectCount) {
                        $controlSqlStatement += "count(*)"
                    }
                    else {
                        $controlSqlStatement += "*"
                    }
                    $controlSqlStatement += " from inl.KONTOTYPE FETCH FIRST $RowCount ROWS ONLY`""
                    $tableToCheck = "inl.KONTOTYPE"
                }
                "DOC" {
                    $controlSqlStatement = "db2 `"select "
                    if ($SelectCount) {
                        $controlSqlStatement += "count(*)"
                    }
                    else {
                        $controlSqlStatement += "*"
                    }
                    $controlSqlStatement += " from dbm.modul FETCH FIRST $RowCount ROWS ONLY`""
                    $tableToCheck = "dbm.modul"
                }
                "FKM" {
                    $controlSqlStatement = "db2 `"select "
                    if ($SelectCount) {
                        $controlSqlStatement += "count(*)"
                    }
                    else {
                        $controlSqlStatement += "*"
                    }
                    $controlSqlStatement += " from dbm.AH_ORDREHODE FETCH FIRST $RowCount ROWS ONLY`""
                    $tableToCheck = "dbm.AH_ORDREHODE"
                }
                "VIS" {
                    $controlSqlStatement = "db2 `"select "
                    if ($SelectCount) {
                        $controlSqlStatement += "count(*)"
                    }
                    else {
                        $controlSqlStatement += "JNO, ENTNO, ACNO, VONO, VODT, VALDT, ACYR, ACPR"
                    }
                    $controlSqlStatement += " from v0001.ACTR_HOLSTAD FETCH FIRST $RowCount ROWS ONLY`""
                    $tableToCheck = "v0001.ACTR_HOLSTAD"
                }
            }
            Add-Member -InputObject $WorkObject -NotePropertyName "ControlSqlStatement" -NotePropertyValue $controlSqlStatement -Force
            Add-Member -InputObject $WorkObject -NotePropertyName "TableToCheck" -NotePropertyValue $tableToCheck -Force
        }
        return $WorkObject
    }
    catch {
        Write-LogMessage "Error getting control SQL statement for application $($WorkObject.Application)" -Level ERROR -Exception $_
        throw $_
    }
}

function Get-ControlDataAgeSqlStatement {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Application
    )

    try {
        Write-LogMessage "Getting control SQL statement for application $(if (-not [string]::IsNullOrEmpty($Application)) { $Application } else { Get-ApplicationFromServerName })" -Level INFO

        $controlSqlStatement = switch ($(if (-not [string]::IsNullOrEmpty($Application)) { $Application } else { Get-ApplicationFromServerName })) {
            "FKM" { "db2 `"SELECT max(MAX_DATE) FROM (SELECT CHAR(DATE(CHAR(RTRIM(max(FAKTDATO),',')))) AS MAX_DATE FROM tv.FAKTHIST UNION SELECT CHAR(DATE(CHAR(max(TIDSPUNKT)))) AS MAX_DATE FROM dbm.A_ORDREHODE ao WHERE tidspunkt > CURRENT timestamp - 3 days)`"" }
            "INL" { "db2 `"SELECT max(TIDSPUNKT) FROM INL.KUNDEKONTO`"" }
            default { "" }
        }
        Write-LogMessage "Control Data Age SQL statement: $controlSqlStatement" -Level INFO
        return $controlSqlStatement
    }
    catch {
        Write-LogMessage "Error getting control SQL statement" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Validates integrity of a Db2 backup file.

.DESCRIPTION
    Executes 'db2ckbkp' utility to verify backup file integrity. Checks for "Image Verification
    Complete - successful" in output to determine if backup is valid and not corrupted.

.PARAMETER WorkObject
    PSCustomObject to track the operation. BackupFile is taken from WorkObject.BackupFile if not specified.

.PARAMETER BackupFile
    Path to backup file to validate. If empty, uses WorkObject.BackupFile.

.EXAMPLE
    $isValid = Test-BackupFileIntegrity -WorkObject $workObject
    # Returns true if backup file is valid

.EXAMPLE
    $isValid = Test-BackupFileIntegrity -WorkObject $workObject -BackupFile "G:\Db2Backup\FKMPRD20250101.001"
    # Validates specific backup file

.NOTES
    Critical for diagnosing SQL1265N errors during restore. Returns boolean.
#>
function Test-BackupFileIntegrity {
    param (
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$BackupFile = ""

    )
    try {
        if ([string]::IsNullOrEmpty($BackupFile) -and -not [string]::IsNullOrEmpty($WorkObject.BackupFile)) {
            Write-LogMessage "Backup file is not specified, using WorkObject.BackupFile" -Level INFO
            $BackupFile = $WorkObject.BackupFile
        }
        Write-LogMessage "Testing backup file integrity for $($BackupFile)" -Level INFO
        $db2Commands = @()
        $db2Commands += "db2ckbkp $($BackupFile)"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name).bat")"
        Write-LogMessage "Backup file integrity test output: $($output)" -Level INFO

        if ($output -match ".*Image Verification Complete - successful*") {
            Write-LogMessage "Backup file integrity test passed" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "Backup file integrity test failed" -Level ERROR
            return $false
        }

    }
    catch {
        Write-LogMessage "Error testing backup file integrity" -Level ERROR -Exception $_
        throw $_
    }
}
function Get-DefaultDb2AdminUsers {
    return @("FKPRDADM", "FKTSTADM", "FKDEVADM", "FKPRDDBA", "FKTSTDBA", "FKDEVDBA", "FKGEISTA", "FKSVEERI", "FKMISTA", "FKCELERI")
}

<#
.SYNOPSIS
    Gets the common file path for DB2 catalog configuration files based on authentication type and client.

.DESCRIPTION
    Generates a standardized file path for DB2 catalog configuration files by combining the database name,
    authentication type (NTLM/Kerberos/Kerberos-SSL), platform (Digiplex/Azure), and client type.
    Creates the directory structure if it doesn't exist.

.PARAMETER AliasName
    The alias name for the database connection.

.PARAMETER AuthenticationType
    The authentication type to use. Valid values are "Ntlm", "Kerberos", or "Kerberos-SSL".

.PARAMETER ClientType
    The type of client accessing DB2. Valid values are "Db2Client", "Dbeaver", "Java", or "OleDb".
    Defaults to "Db2Client".

.PARAMETER Version
    The version of the catalog file. Defaults to "1.0". Version 1.0 uses Digiplex platform,
    while other versions use Azure platform.

.EXAMPLE
    Get-CommonPartOfCatalogFilePath -AliasName "MYDB" -AuthenticationType "Kerberos" -ClientType "Dbeaver" -Version "2.0"
    # Returns path to Kerberos catalog file for MYDB using Dbeaver client on Azure platform

.OUTPUTS
    Returns the full standardized file path as a string
#>
function Get-CommonPartOfCatalogFilePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Ntlm", "Kerberos", "Kerberos-SSL")]
        [string]$AuthenticationType,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Db2Client", "Dbeaver", "Java", "OleDb", "Odbc")]
        [string]$ClientType = "Db2Client",
        [Parameter(Mandatory = $false)]
        [string]$Platform = "Digiplex",
        [Parameter(Mandatory = $false)]
        [switch]$DirectExport = $false
    )

    $commonCatalogPath = Get-ClientConfigDirectory -Platform $Platform -AuthenticationType $AuthenticationType -DirectExport:$DirectExport
    $clientTypeText = ""
    if ($AuthenticationType -eq "Kerberos-SSL") {
        $prefixText = "Client-Config-For-"
    }
    else {
        $prefixText = "Catalog-Script-For-"
    }
    if ($ClientType) {
        $clientTypeText = "-For-$ClientType"
    }
    if ($AuthenticationType -eq "Ntlm" -and $Platform -eq "Azure") {
        $clientTypeText = "-For-Integration-$ClientType-Clients"
    }

    $commonConfigFile = $(Join-Path $commonCatalogPath "$prefixText$($Platform)-Db2-Database-$Name-Using-$AuthenticationType$clientTypeText.bat").ToString()

    return $commonConfigFile
}

<#
.SYNOPSIS
    Tests if DB2 client is properly installed and configured.

.DESCRIPTION
    Verifies the DB2 client installation by checking for the db2cmd.exe file
    and attempting to run a basic DB2 command (db2level).

.PARAMETER Db2Path
    The path to the DB2 installation directory. Defaults to "C:\DbInst\BIN".

.EXAMPLE
    Test-DB2Client
    # Tests DB2 client with default path

.EXAMPLE
    Test-DB2Client -Db2Path "C:\MyDB2\BIN"
    # Tests DB2 client with custom path

.OUTPUTS
    Returns $true if DB2 client is properly installed, $false otherwise
#>
function Test-DB2Client {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Db2Path = "C:\DbInst\BIN"
    )
    try {
        $db2cmdPath = Get-Db2CmdPath -Db2Path $Db2Path
        if (-Not (Test-Path $db2cmdPath)) {
            Write-Error "DB2 client is not properly installed or configured."
            return $false
        }
        try {
            $null = Invoke-Db2CommandOld "db2level"
            Write-Host "DB2 client is installed and available."
            return $true
        }
        catch {
            Write-Error "DB2 client is not properly installed or configured."
            return $false
        }
    }
    catch {
        Write-LogMessage "Error checking DB2 client" -Level ERROR -Exception $_
        return $false
    }
}

function Get-LocalTempClientFolderPath {
    $applicationDataPath = Get-ApplicationDataPath
    if (-not (Test-Path $applicationDataPath -PathType Container)) {
        New-Item -ItemType Directory -Path $applicationDataPath -Force | Out-Null
    }
    return Join-Path $applicationDataPath "Config\Db2\_tmp"
}

function Get-ClientFolderPath {
    #return Join-Path $(Get-SoftwarePath) "Config\Db2\TestClientConfig"
    return Join-Path $(Get-SoftwarePath) "Config\Db2\ClientConfig"
}

<#
.SYNOPSIS
    Gets the client configuration directory path for a specific platform.

.DESCRIPTION
    Constructs and returns the directory path where DB2 client configuration files
    are stored for a specific platform.

.PARAMETER Platform
    The platform of the configuration. Currently supports "Digiplex" or "Azure".

.EXAMPLE
    Get-ClientConfigDirectory -Platform "Azure"
    # Returns the directory path for Azure client configuration files

.EXAMPLE
    Get-ClientConfigDirectory -Platform "Digiplex"
    # Returns the directory path for Digiplex client configuration files

.NOTES
    This function constructs directory paths for DB2 client configuration files.
#>
function Get-ClientConfigDirectory {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Platform = "",
        [Parameter(Mandatory = $false)]
        [string]$AuthenticationType = "",
        [Parameter(Mandatory = $false)]
        [switch]$DirectExport = $false
    )
    if ($DirectExport) {
        # $commonCatalogPath = Join-Path $(Get-ClientFolderPath) $Platform $AuthenticationType
        $commonCatalogPath = Join-Path $(Get-ClientFolderPath) $AuthenticationType
    }
    else {
        # $commonCatalogPath = Join-Path $(Get-LocalTempClientFolderPath) $Platform $AuthenticationType
        $commonCatalogPath = Join-Path $(Get-LocalTempClientFolderPath) $AuthenticationType
    }
    if (-Not (Test-Path $commonCatalogPath -PathType Container)) {
        New-Item -ItemType Directory -Path $commonCatalogPath -Force | Out-Null
    }
    return $commonCatalogPath
}


# Function to verify Kerberos setup
<#
.SYNOPSIS
    Verifies Kerberos configuration and ticket availability.

.DESCRIPTION
    Checks for active Kerberos tickets using the klist command and verifies
    the presence of the krb5.ini configuration file in the Windows directory.

.EXAMPLE
    Test-KerberosConfiguration
    # Verifies Kerberos setup and reports status

.OUTPUTS
    Returns $true if Kerberos is properly configured, $false otherwise

.NOTES
    This function checks for Kerberos tickets and configuration files.
    Warnings are displayed if tickets or configuration files are missing.
#>
function Test-KerberosConfiguration {
    try {
        # Check if Kerberos ticket exists
        $output, $errorFound = Invoke-Db2CommandOld "klist"
        if ($output -match "Error") {
            Write-Warning "No Kerberos ticket found. You may need to run 'kinit' to obtain a ticket."
        }
        else {
            Write-Host "Kerberos ticket found. Continuing with configuration."
        }

        # Check for krb5.ini file
        if (Test-Path "C:\Windows\krb5.ini") {
            Write-Host "Kerberos configuration file (krb5.ini) found."
        }
        else {
            Write-Warning "Kerberos configuration file (krb5.ini) not found. You may need to create it."
        }

        return $true
    }
    catch {
        Write-Error "Error checking Kerberos configuration: $_"
        return $false
    }
}
<#
.SYNOPSIS
    Creates DB2 catalog configuration for Kerberos authentication using CommonParamObject.

.DESCRIPTION
    Creates a DB2 catalog configuration file for Kerberos authentication. The function
    generates a batch file that contains the necessary DB2 commands to catalog nodes,
    databases, and configure Kerberos settings for secure database connections.

.PARAMETER CommonParamObject
    PSCustomObject containing all required parameters for DB2 client configuration including:
    - ServerName: The hostname of the DB2 server (e.g., "server.domain.com")
    - ServerPort: The port number for the DB2 server connection (e.g., "50000")
    - DatabaseName: The name of the database to catalog
    - NodeName: The node name for the DB2 catalog
    - CatalogName: The catalog name for the database connection
    - ClientType: The type of client configuration (Db2Client, Odbc, etc.)

.EXAMPLE
    $paramObject = [PSCustomObject]@{
        ServerName = "server.domain.com"
        ServerPort = "50000"
        DatabaseName = "MYDB"
        NodeName = "NODE1"
        CatalogName = "MYALIAS"
        ClientType = "Db2Client"
    }
    Set-Db2KerberosClientConfig -CommonParamObject $paramObject
    # Creates Kerberos catalog configuration for MYDB

.NOTES
    This function requires Administrator privileges to run properly.
    Uses KERBEROS authentication type for secure database connections.
    Author: Geir Helge Starholm, www.dEdge.no
#>
function Set-Db2KerberosClientConfig {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$CommonParamObject
    )
    $authenticationType = if ($CommonParamObject.AuthenticationType -eq "KerberosServerEncrypt") {
        "KRB_SERVER_ENCRYPT"
    }
    else {
        "KERBEROS"
    }


    if ($CommonParamObject.ClientType -eq "Odbc") {
        $db2CatalogContent = @"

md C:\tempfk >nul 2>&1
powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Cyan"
powershell -Command "Write-Host Cataloging database $($CommonParamObject.DatabaseName) for $($CommonParamObject.ClientType) with name $($CommonParamObject.RemoteDatabaseName) towards $($CommonParamObject.ServerName) and port $($CommonParamObject.RemotePort) using $($authenticationType) -ForegroundColor Cyan"
powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Cyan"
powershell -Command "Write-Host"
db2 catalog system odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 catalog user odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 terminate
echo Testing ODBC connection to $($CommonParamObject.RemoteDatabaseName)...
powershell -Command "`$conn = New-Object System.Data.Odbc.OdbcConnection; `$conn.ConnectionString = 'DSN=$($CommonParamObject.RemoteDatabaseName)'; try { `$conn.Open(); Write-Host 'Successfully connected to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Green; `$cmd = `$conn.CreateCommand(); `$cmd.CommandText = 'select current timestamp from sysibm.sysdummy1'; `$reader = `$cmd.ExecuteReader(); if(`$reader.Read()) { Write-Host `$reader.GetValue(0) -ForegroundColor Green }; '$($CommonParamObject.RemoteDatabaseName): Odbc Test Success' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append; `$reader.Close(); `$conn.Close() } catch { Write-Host 'Failed to connect to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Yellow; '$($CommonParamObject.RemoteDatabaseName): Odbc Test Failed' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append }"


"@
    }
    else {
        $db2CatalogContent = @"


md C:\tempfk >nul 2>&1
powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Cyan"
powershell -Command "Write-Host Cataloging database $($CommonParamObject.DatabaseName) for $($CommonParamObject.ClientType) with name $($CommonParamObject.RemoteDatabaseName) towards $($CommonParamObject.ServerName) and port $($CommonParamObject.RemotePort) using $($authenticationType) -ForegroundColor Cyan"
powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Cyan"
powershell -Command "Write-Host"
echo %COMPUTERNAME% | findstr /I "\-db" >nul
if %ERRORLEVEL% EQU 0 (
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   powershell -Command "Write-Host 'This computer is a database server. Aborting cataloging .' -ForegroundColor Red"
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   pause
   exit /b
)
echo Uncataloging database $($CommonParamObject.RemoteDatabaseName)...
db2 uncatalog database $($CommonParamObject.RemoteDatabaseName)
db2 uncatalog node $($CommonParamObject.RemoteNodeName)
db2 terminate
db2 catalog tcpip node $($CommonParamObject.RemoteNodeName) remote $($CommonParamObject.ServerName) server $($CommonParamObject.RemotePort)
db2 catalog database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName) at node $($CommonParamObject.RemoteNodeName) AUTHENTICATION $($authenticationType) TARGET PRINCIPAL db2/$($CommonParamObject.ServerName)
db2 update cli cfg for section COMMON using CLNT_KRB_PLUGIN IBMkrb5
db2 update cli cfg for section COMMON using AUTHENTICATION KERBEROS_SSPI
db2 catalog system odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 catalog user odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 terminate
echo Testing ODBC connection to $($CommonParamObject.RemoteDatabaseName)...
powershell -Command "`$conn = New-Object System.Data.Odbc.OdbcConnection; `$conn.ConnectionString = 'DSN=$($CommonParamObject.RemoteDatabaseName)'; try { `$conn.Open(); Write-Host 'Successfully connected to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Green; `$cmd = `$conn.CreateCommand(); `$cmd.CommandText = 'select current timestamp from sysibm.sysdummy1'; `$reader = `$cmd.ExecuteReader(); if(`$reader.Read()) { Write-Host `$reader.GetValue(0) -ForegroundColor Green }; '$($CommonParamObject.RemoteDatabaseName): Odbc Test Success' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append; `$reader.Close(); `$conn.Close() } catch { Write-Host 'Failed to connect to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Yellow; '$($CommonParamObject.RemoteDatabaseName): $($CommonParamObject.DatabaseName) Odbc Test Failed' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append }"


echo Checking connection to database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName)...
db2 terminate
db2 connect to $($CommonParamObject.RemoteDatabaseName)
db2 select current timestamp from sysibm.sysdummy1
IF %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Successfully connected to database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Green; '$($CommonParamObject.RemoteDatabaseName): Db2Client Test Success' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append"
) ELSE (
    powershell -Command "Write-Host 'Failed to connect to database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Yellow; '$($CommonParamObject.RemoteDatabaseName): Db2Client Test Failed' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append"
)
db2 connect reset
powershell -Command "Write-Host"
"@
    }

    $clientType = [PSCustomObject]@{
        ClientType = $CommonParamObject.ClientType
        Result     = $($db2CatalogContent.Replace("`r`n", "`n").Replace("`r", "`n") -Split "`n" -Join "`n" )
    }
    $CommonParamObject.ClientTypeResultArray += $clientType
    return $CommonParamObject
}


<#
.SYNOPSIS
    Configures DB2 client for NTLM authentication using CommonParamObject.

.DESCRIPTION
    Creates a DB2 catalog configuration script for NTLM authentication. The function
    generates batch commands that contain the necessary DB2 commands to catalog nodes
    and databases using NTLM authentication for database connections. The function
    takes a CommonParamObject parameter that contains all necessary configuration
    details and returns the updated object with client type results.

.PARAMETER CommonParamObject
    A PSCustomObject containing all necessary configuration parameters including:
    - DatabaseName: The name of the database to catalog
    - RemoteDatabaseName: The catalog name for the database connection
    - ServerName: The hostname of the DB2 server
    - RemotePort: The port number for the DB2 server connection
    - RemoteNodeName: The node name for the DB2 catalog
    - ClientType: The type of client configuration
    - ClientTypeResultArray: Array to store client configuration results

.EXAMPLE
    $CommonParamObject = Set-Db2NtlmClientConfig -CommonParamObject $paramObject
    # Creates NTLM catalog configuration using the provided CommonParamObject

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    This function requires Administrator privileges to run properly.
    NTLM authentication is simpler than Kerberos but may be less secure.
    The function updates the CommonParamObject.ClientTypeResultArray with the generated configuration.
#>
function Set-Db2NtlmClientConfig {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$CommonParamObject
    )



    if ($CommonParamObject.ClientType -eq "Odbc") {
        $db2CatalogContent = @"


md C:\tempfk >nul 2>&1
powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Cyan"
powershell -Command "Write-Host Cataloging database $($CommonParamObject.DatabaseName) for $($CommonParamObject.ClientType) with name $($CommonParamObject.RemoteDatabaseName) towards $($CommonParamObject.ServerName) and port $($CommonParamObject.RemotePort) using $($authenticationType) -ForegroundColor Cyan"
powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Cyan"
powershell -Command "Write-Host"
db2 catalog system odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 catalog user odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 terminate
echo Testing ODBC connection to $($CommonParamObject.RemoteDatabaseName)...
powershell -Command "`$conn = New-Object System.Data.Odbc.OdbcConnection; `$conn.ConnectionString = 'DSN=$($CommonParamObject.RemoteDatabaseName)'; try { `$conn.Open(); Write-Host 'Successfully connected to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Green; `$cmd = `$conn.CreateCommand(); `$cmd.CommandText = 'select current timestamp from sysibm.sysdummy1'; `$reader = `$cmd.ExecuteReader(); if(`$reader.Read()) { Write-Host `$reader.GetValue(0) -ForegroundColor Green }; '$($CommonParamObject.RemoteDatabaseName): Odbc Test Success' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append; `$reader.Close(); `$conn.Close() } catch { Write-Host 'Failed to connect to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Yellow; '$($CommonParamObject.RemoteDatabaseName): Odbc Test Failed' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append }"


"@
    }
    else {
        $db2CatalogContent = @"


md C:\tempfk >nul 2>&1
powershell -Command "Write-Host '======================================================================================================================' -ForegroundColor Cyan"
powershell -Command "Write-Host 'Cataloging database $($CommonParamObject.DatabaseName) with name $($CommonParamObject.RemoteDatabaseName) towards $($CommonParamObject.ServerName) and port $($CommonParamObject.RemotePort) using Ntlm' -ForegroundColor Cyan"
powershell -Command "Write-Host '======================================================================================================================' -ForegroundColor Cyan"
powershell -Command "Write-Host"
echo %COMPUTERNAME% | findstr /I "\-db" >nul
if %ERRORLEVEL% EQU 0 (
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   powershell -Command "Write-Host 'This computer is a database server. Aborting cataloging .' -ForegroundColor Red"
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   powershell -Command "Write-Host ====================================================================================================================== -ForegroundColor Red"
   pause
   exit /b
)
echo Uncataloging database $($CommonParamObject.RemoteDatabaseName)...
db2 uncatalog database $($CommonParamObject.RemoteDatabaseName)
db2 uncatalog node $($CommonParamObject.RemoteNodeName)
db2 catalog tcpip node $($CommonParamObject.RemoteNodeName) remote $($CommonParamObject.ServerName) server $($CommonParamObject.RemotePort)
db2 catalog database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName) at node $($CommonParamObject.RemoteNodeName)
db2 catalog system odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 catalog user odbc data source $($CommonParamObject.RemoteDatabaseName)
db2 terminate
echo Testing ODBC connection to $($CommonParamObject.RemoteDatabaseName)...
powershell -Command "`$conn = New-Object System.Data.Odbc.OdbcConnection; `$conn.ConnectionString = 'DSN=$($CommonParamObject.RemoteDatabaseName)'; try { `$conn.Open(); Write-Host 'Successfully connected to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Green; `$cmd = `$conn.CreateCommand(); `$cmd.CommandText = 'select current timestamp from sysibm.sysdummy1'; `$reader = `$cmd.ExecuteReader(); if(`$reader.Read()) { Write-Host `$reader.GetValue(0) -ForegroundColor Green }; '$($CommonParamObject.RemoteDatabaseName): $($CommonParamObject.DatabaseName) Odbc Test Success' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append; `$reader.Close(); `$conn.Close() } catch { Write-Host 'Failed to connect to ODBC data source $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Yellow; '$($CommonParamObject.RemoteDatabaseName): $($CommonParamObject.DatabaseName) Odbc Test Failed' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append }"


echo Checking connection to database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName)...
db2 terminate
db2 connect to $($CommonParamObject.RemoteDatabaseName)
db2 select current timestamp from sysibm.sysdummy1
IF %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Successfully connected to database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Green; '$($CommonParamObject.RemoteDatabaseName): Db2Client Test Success' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append"
) ELSE (
    powershell -Command "Write-Host 'Failed to connect to database $($CommonParamObject.DatabaseName) as $($CommonParamObject.RemoteDatabaseName)' -ForegroundColor Yellow; '$($CommonParamObject.RemoteDatabaseName): Db2Client Test Failed' | Out-File -FilePath 'C:\tempfk\CatalogResults.txt' -Append"
)
db2 connect reset
powershell -Command "Write-Host"
"@
    }


    $clientType = [PSCustomObject]@{
        ClientType = $CommonParamObject.ClientType
        Result     = $($db2CatalogContent.Replace("`r`n", "`n").Replace("`r", "`n") -Split "`n" -Join "`n" )
    }
    $CommonParamObject.ClientTypeResultArray += $clientType
    return $CommonParamObject
}


<#
.SYNOPSIS
    Configures DB2 client for Kerberos authentication.

.DESCRIPTION
    Creates a DB2 catalog configuration file for Kerberos authentication. The function
    generates a batch file that contains the necessary DB2 commands to catalog nodes,
    databases, and configure Kerberos settings for secure database connections.

.PARAMETER ServerHostname
    The hostname of the DB2 server (e.g., "server.domain.com").

.PARAMETER ServerPort
    The port number for the DB2 server connection (e.g., "50000").

.PARAMETER DatabaseName
    The name of the database to catalog.

.PARAMETER NodeName
    The node name for the DB2 catalog. Default is typically "NODE1".

.PARAMETER Version
    The version of the catalog file. Defaults to "1.0".

.PARAMETER CreateCatalogFiles
    If true, only creates the catalog file without executing it. Defaults to $true.

.PARAMETER AliasName
    The alias name for the database connection.

.PARAMETER AppendToCommonCatalogFile
    Path to append the catalog commands to a common catalog file.

.EXAMPLE
    Set-Db2KerberosClientConfig -ServerHostname "server.domain.com" -ServerPort "50000" -DatabaseName "MYDB" -NodeName "NODE1" -AliasName "MYALIAS"
    # Creates Kerberos catalog configuration for MYDB

.NOTES
    This function requires Administrator privileges to run properly.
    Uses different authentication types based on the port number (KRB_SERVER_ENCRYPT for port 50010).
#>
function Set-Db2KerberosSslClientConfig {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$CommonParamObject
    )
    $sslDatabaseConfigBasePath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ServerConfigurationSSL\$Name"
    if (-not (Test-Path $sslDatabaseConfigBasePath)) {
        return
    }
    $clientConfigPaths = @(
        [PSCustomObject]@{
            Type = "Dbeaver"
            Path = Join-Path $sslDatabaseConfigBasePath "ClientConfig" "Dbeaver"
        },
        [PSCustomObject]@{
            Type = "Java"
            Path = Join-Path $sslDatabaseConfigBasePath "ClientConfig" "Java"
        },
        [PSCustomObject]@{
            Type = "OleDb"
            Path = Join-Path $sslDatabaseConfigBasePath "ClientConfig" "OleDb"
        }
    )
    $allDb2CatalogContent = ""
    foreach ($clientConfigPath in $clientConfigPaths) {

        # Get Install* folders and their contents
        $tempPath = $clientConfigPath.Path
        if (-not (Test-Path $tempPath)) {
            Write-LogMessage "Temp path $tempPath does not exist for $($clientConfigPath.Type) client configuration" -Level WARN
            continue
        }
        $installScriptName = $(Get-ChildItem -Path $clientConfigPath.Path -File -Filter "Install*").ResolvedTarget
        if ($installScriptName) {
            Write-LogMessage "Found Install script for $($clientConfigPath.Type) at $($installScriptName)" -Level INFO
            $db2CatalogContent = @"

echo -------------------------------------------------------------------------------------------------------------------------------------------------------------
echo Installing Kerberos-SSL for $($clientConfigPath.Type) client configuration for database $($CommonParamObject.DatabaseName) with alias $($CommonParamObject.AliasName) towards $($CommonParamObject.ServerName) and port $($CommonParamObject.ServerPort)
echo -------------------------------------------------------------------------------------------------------------------------------------------------------------
call $($installScriptName)
explorer.exe `"$($clientConfigPath.Path)`"
"@


            $allDb2CatalogContent += $db2CatalogContent
            $clientType = [PSCustomObject]@{
                ClientType = $clientConfigPath.Type
                Result     = $($db2CatalogContent.Replace("`r`n", "`n").Replace("`r", "`n") -Split "`n" -Join "`n" )
            }
            $CommonParamObject.ClientTypeResultArray += $clientType
        }
    }
    return $CommonParamObject
}
<#
.SYNOPSIS
    Gets the common catalog directory path for a specific platform and authentication type.

.DESCRIPTION
    Constructs and returns the directory path where DB2 client configuration files
    are stored for a specific platform and authentication type combination.

.PARAMETER Platform
    The platform of the configuration. Currently supports "Digiplex" or "Azure".

.PARAMETER AuthenticationType
    The type of authentication. Valid values are "Kerberos", "Kerberos-SSL", or "Ntlm".

.EXAMPLE
    Get-CommonMergedClientConfigFileName -Platform "Azure" -AuthenticationType "Kerberos"
    # Returns the directory path for Azure Kerberos configuration files

.EXAMPLE
    Get-CommonMergedClientConfigFileName -Platform "Digiplex" -AuthenticationType "Ntlm"
    # Returns the directory path for Digiplex NTLM configuration files

.NOTES
    This function constructs directory paths for DB2 client configuration files.
#>
function Get-CommonMergedClientConfigFileName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Platform,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Kerberos", "Kerberos-SSL", "Ntlm")]
        [string]$AuthenticationType,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Db2Client", "Dbeaver", "Java", "OleDb", "Odbc")]
        [string]$ClientType = "Db2Client"
    )

    $commonCatalogPath = Get-ClientConfigDirectory -Platform $Platform -AuthenticationType $AuthenticationType
    $clientTypeText = ""
    if ($AuthenticationType -eq "Kerberos-SSL") {
        $prefixText = "Client-Config-For-"
    }
    elseif ($AuthenticationType -eq "Kerberos") {
        $prefixText = "Catalog-Script-For-"
    }
    else {
        $prefixText = "Catalog-Script-For-"
    }
    if ($ClientType) {
        $clientTypeText = "-For-$ClientType"
    }
    if ($AuthenticationType -eq "Ntlm" -and $Platform -eq "Azure") {
        $clientTypeText = "-For-Integration-Clients"
    }
    $commonConfigFile = $(Join-Path $commonCatalogPath "$($prefixText)All-Db2-$($Platform)-Databases-Using-$AuthenticationType$clientTypeText.bat").ToString()

    return $commonConfigFile
}
function Get-CommonMergedCobolCatalogFileName {

    return $avdSpecializedConfigFile
}

<#
.SYNOPSIS
    Initializes common DB2 catalog configuration files for given authentication types.

.DESCRIPTION
    Creates the directory structure and initializes common DB2 catalog batch files
    for given authentication types. This function sets up
    the foundation files that individual database catalog configurations will append to.

.PARAMETER Platform
    The platform of the configuration. Currently supports "Digiplex" or "Azure".

.PARAMETER AuthenticationType
    The type of authentication to initialize. Valid values are "Kerberos", "Kerberos-SSL", "Ntlm", or "*" for all types.
    When "*" is specified, all existing files are cleared and recreated.

.EXAMPLE
    Initialize-CommonCatalogFile -Platform "Azure" -AuthenticationType "Kerberos"
    # Initializes the common Kerberos catalog file for given authentication types for Azure platform

.EXAMPLE
    Initialize-CommonCatalogFile -Platform "Azure" -AuthenticationType "*"
    # Initializes all common catalog files for given authentication types for Azure platform

.NOTES
    This function creates the base batch files that other catalog functions will append to.
    If files already exist, they are preserved unless AuthenticationType is "*".
#>
function Initialize-CommonCatalogFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Platform,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Kerberos", "Kerberos-SSL", "Ntlm")]
        [string]$AuthenticationType
    )

    $commonCatalogPath = Join-Path $(Get-SoftwarePath) "Config\Db2\TestClientConfig" $Platform $AuthenticationType

    if (-not (Test-Path $commonCatalogPath)) {
        New-Item -Path $commonCatalogPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Get path for the specified authentication type
    $commonConfigFilePath = Get-CommonMergedClientConfigFileName -Platform $Platform -AuthenticationType $AuthenticationType -ClientType $ClientType

    # Create directory and file for the specified authentication type
    Add-FolderForFileIfNotExists -FileName $commonConfigFilePath
    # if ($AuthenticationType -eq "Kerberos-SSL") {
    # }
    # if (-not (Test-Path $commonConfigFilePath -PathType Leaf)) {
    #     New-Item -Path $commonConfigFilePath -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
    # }
    # Add-Content -Path $commonConfigFilePath -Value "@echo off `n"

    # Write-Host "Common catalog file for $Platform $AuthenticationType initialized successfully."
    return $commonConfigFilePath
}



function New-CommonCatalogFileContent {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CatalogFileName,
        [Parameter(Mandatory = $true)]
        [string[]]$CatalogFileContent

    )
    $addArray = @()
    $addArray += "@echo off"
    $addArray += "md C:\tempfk >nul 2>&1"
    $addArray += "del c:\tempfk\CatalogResults.txt /q"
    $addArray += @($CatalogFileContent)
    $addArray += "powershell -Command `"Write-Host ====================================================================================================================== -ForegroundColor Cyan`""
    $addArray += "powershell -Command `"Write-Host Results from Cataloging -ForegroundColor Cyan`""
    $addArray += "powershell -Command `"Write-Host ====================================================================================================================== -ForegroundColor Cyan`""
    $addArray += "powershell -Command `"Get-Content 'c:\tempfk\CatalogResults.txt' | ForEach-Object { if (`$_ -match 'Success') { Write-Host `$_ -ForegroundColor Green } elseif (`$_ -match 'Failed') { Write-Host `$_ -ForegroundColor Red } else { Write-Host `$_ } }`""
    $addArray += "@echo on"
    Set-Content -Path $CatalogFileName -Value $($addArray -Join "`n")
    Write-LogMessage "Created primary Common catalog file $($CatalogFileName)" -Level INFO

    $fileInfo = Get-Item -Path $CatalogFileName
    $fileNameOnly = $fileInfo.Name
    $secondaryCatalogFileName = Join-Path "\\DEDGE.fk.no\erpprog" "COBNT" $fileNameOnly
    Set-Content -Path $secondaryCatalogFileName -Value $($addArray -Join "`n")
    Write-LogMessage "Created secondary common catalog file $($secondaryCatalogFileName)" -Level INFO
}


# Creates catalog files for all DB2 databases defined in Databases.json
# Valid alternatives:
# - New-AllDbCatalogFiles: More PowerShell-compliant verb-noun naming
# - Initialize-AllDbCatalogs: Alternative if focusing on initialization aspect
# - Set-AllDbCatalogs: Alternative if focusing on configuration aspect

<#
.SYNOPSIS
    Creates DB2 catalog configuration for a specific database.

.DESCRIPTION
    Generates DB2 catalog configuration files for a specified database using either
    Kerberos or NTLM authentication. Retrieves database connection information from
    the Databases.json configuration file.

.PARAMETER DatabaseName
    The name of the database to create catalog configuration for.

.PARAMETER AuthenticationType
    The type of authentication to use. Valid values are "Kerberos", "Ntlm", or "*" for both.
    Defaults to "Ntlm".

.EXAMPLE
    Add-RemoteCatalogingForDatabase -DatabaseName "FKMPRD" -AuthenticationType "Kerberos"
    # Creates Kerberos catalog configuration for FKMPRD database

.EXAMPLE
    Add-RemoteCatalogingForDatabase -DatabaseName "FKMTST" -AuthenticationType "*"
    # Creates both Kerberos and NTLM catalog configurations for FKMTST database

.NOTES
    This function reads database configuration from Databases.json.
    The function supports creating catalog files for both authentication types.
#>
function Add-RemoteCatalogingForDatabase {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName, # Eg. FKMPRD
        [Parameter(Mandatory = $false)]
        [ValidateSet("Kerberos", "KerberosServerEncrypt", "*", "Ntlm")]
        [string]$AuthenticationType = "Ntlm",
        [Parameter(Mandatory = $true)]
        [string]$Version = "2.0"
    )

    $jsonContent = Get-DatabasesV2Json  # Corrected function name
    if ( $Version -eq "*") {
        if ($DatabaseName -ne "*") {
            $serverDatabases = $jsonContent | Where-Object { $_.Provider -eq "DB2" -and $_.IsActive -eq $true -and ($_.Database -eq $DatabaseName -or $_.AccessPoints.CatalogName -contains $DatabaseName -and $_.AccessPoints.IsActive -eq $true) }
        }
        else {
            $serverDatabases = $jsonContent | Where-Object { $_.Provider -eq "DB2" -and $_.IsActive -eq $true }
        }
    }
    else {
        if ($DatabaseName -ne "*") {
            $serverDatabases = $jsonContent | Where-Object { $_.Provider -eq "DB2" -and $_.Version -eq $Version -and $_.IsActive -eq $true -and ($_.Database -eq $DatabaseName -or $_.AccessPoints.CatalogName -contains $DatabaseName -and $_.AccessPoints.IsActive -eq $true) }
        }
        else {
            $serverDatabases = $jsonContent | Where-Object { $_.Provider -eq "DB2" -and $_.Version -eq $Version -and $_.IsActive -eq $true }
        }
    }
    $addToCommonCatalogFile = $false
    if ($DatabaseName -eq "*" -and $AuthenticationType -eq "*" -and $Version -eq "*") {
        $addToCommonCatalogFile = $true
        Remove-Item -Path $(Get-ClientConfigDirectory) -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Removing all temporary common catalog files for full regeneration of all client config files" -Level INFO

        $tempDirectory = Get-LocalTempClientFolderPath
        if (Test-Path $tempDirectory -PathType Container) {
            Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null



        # If temp zip directory does not exist, create it
        $tempZipDirectory = Join-Path $(Get-LocalTempClientFolderPath) "Zip"
        if (-not (Test-Path $tempZipDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $tempZipDirectory -Force | Out-Null
        }

        # Copy current directory to temp zip directory
        Copy-Item -Path $(Get-ClientFolderPath) -Destination $tempZipDirectory -Force

        # Zip temp zip directory to archive directory
        $archiveDirectory = Join-Path $(Get-SoftwarePath) "Config\Db2\ClientConfigArchive"
        if (-not (Test-Path $archiveDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
        }

        # Zip temp zip directory to archive directory
        $zipFileName = Join-Path $archiveDirectory "ClientConfig_$(Get-Date -Format "yyyyMMdd_HHmmss").zip"
        Compress-Archive -Path "$tempZipDirectory\*" -DestinationPath $zipFileName
        Write-LogMessage "Zipped existing common catalog files to $zipFileName" -Level INFO

        # Remove temp zip directory
        Remove-Item -Path $tempZipDirectory -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

    }

    # Check for null AuthenticationType in AccessPoints and output to console
    $distinctConfigurations = @()
    $distinctConfigurations += [PSCustomObject]@{
        Version            = "1.0"
        AuthenticationType = "Ntlm"
        Platform           = "Digiplex"
    }
    $distinctConfigurations += [PSCustomObject]@{
        Version            = "2.0"
        AuthenticationType = "Ntlm"
        Platform           = "Azure"
    }
    $distinctConfigurations += [PSCustomObject]@{
        Version            = "2.0"
        AuthenticationType = "Kerberos"
        Platform           = "Azure"
    }
    $distinctConfigurations += [PSCustomObject]@{
        Version            = "2.0"
        AuthenticationType = "Kerberos-SSL"
        Platform           = "Azure"
    }
    $distinctConfigurations += [PSCustomObject]@{
        Version            = "2.0"
        AuthenticationType = "KerberosServerEncrypt"
        Platform           = "Azure"
    }
    $generationLogArray = @()
    foreach ($distinctConfiguration in $distinctConfigurations) {
        $filteredDatabases = $serverDatabases | Where-Object { $_.Version -eq $distinctConfiguration.Version }
        $totalDatabases = $filteredDatabases.Count
        $currentDatabaseIndex = 0
        foreach ($serverDatabase in $filteredDatabases) {
            $currentDatabaseIndex++
            Write-Progress -Activity "Processing DB2 Databases" -Status "Processing $($distinctConfiguration.Platform) $($distinctConfiguration.AuthenticationType) $($distinctConfiguration.Version) $($currentDatabaseIndex) of $($totalDatabases): $($serverDatabase.Database)" -PercentComplete (($currentDatabaseIndex / $totalDatabases) * 100)


         
            $computerInfo = Get-ComputerInfo -ComputerName $serverDatabase.ServerName
            if (-not $computerInfo) {
                Write-LogMessage "Failed to get computer info for $($serverDatabase.ServerName)" -Level ERROR
                continue
            }
          
            $filteredAccessPoints = $serverDatabase.AccessPoints | Where-Object { $_.AuthenticationType -eq $distinctConfiguration.AuthenticationType -and $_.IsActive -eq $true }
            foreach ($accessPoint in $filteredAccessPoints) {
                try {
                   
                    Write-LogMessage "Processing $($distinctConfiguration.Platform) $($distinctConfiguration.AuthenticationType) $($distinctConfiguration.Version) $($currentDatabaseIndex) of $($totalDatabases): $($serverDatabase.Database) $($accessPoint.CatalogName)" -Level INFO
                    
                    # Use RemoteDatabaseName as RemoteNodeName when NOT on a DB2 server to avoid node name conflicts
                    $nodeNameToUse = if (-not (Test-IsDb2Server)) { 
                        $accessPoint.CatalogName 
                    }
                    else { 
                        $accessPoint.NodeName 
                    }
                    
                    $commonParamObject = [PSCustomObject]@{
                        ServerName         = $serverDatabase.ServerName
                        Platform           = $distinctConfiguration.Platform
                        Version            = $distinctConfiguration.Version
                        DatabaseName       = $serverDatabase.Database
                        ServiceUserName    = $computerInfo.ServiceUserName
                        AuthenticationType = $distinctConfiguration.AuthenticationType
                        IsActive           = $accessPoint.IsActive
                        AccessPointType    = $accessPoint.AccessPointType
                        RemotePort         = $accessPoint.Port
                        RemoteServiceName  = $accessPoint.ServiceName
                        RemoteNodeName     = $nodeNameToUse
                        RemoteDatabaseName = $accessPoint.CatalogName
                    }

                    if ($commonParamObject.IsActive -eq $true -and $commonParamObject.AuthenticationType -eq $distinctConfiguration.AuthenticationType) {
                        $commonParamObject = Invoke-Db2ClientConfiguration -CommonParamObject $commonParamObject

                        Write-LogMessage "Client config for $($commonParamObject.Platform) $($commonParamObject.AuthenticationType) $($commonParamObject.Version) $($commonParamObject.DatabaseName) $($commonParamObject.RemoteDatabaseName) generated" -Level INFO
                    }

                    $generationLogArray += $commonParamObject
                }

                catch {
                    Write-LogMessage "Error processing $($distinctConfiguration.Platform) $($distinctConfiguration.AuthenticationType) $($distinctConfiguration.Version) $($currentDatabaseIndex) of $($totalDatabases): $($serverDatabase.Database) $($commonParamObject.RemoteDatabaseName): $_" -Level ERROR -Exception $_
                    throw $_
                }
            }
        }



    }

    ########################################################
    # Create temp directory and remove if it exists to prepare for new export
    ########################################################
    $tempDirectory = Get-LocalTempClientFolderPath
    if (Test-Path $tempDirectory -PathType Container) {
        Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

    ########################################################
    # Export to files from generationLogArray
    ########################################################
    $commonCobolCatalogFileContent = @()
    $commonFederatedCatalogFileContent = @()
    $WorkObject = [PSCustomObject]@{
        GeneratedFileNames     = @()
        DistinctConfigurations = $distinctConfigurations
        ScriptArray            = @()
    }
    $generatedFileNames = @()

    foreach ($distinctConfiguration in $distinctConfigurations) {
        $filteredObjects = $generationLogArray | Where-Object { $_.Version -eq $distinctConfiguration.Version -and $_.AuthenticationType -eq $distinctConfiguration.AuthenticationType -and $_.Platform -eq $distinctConfiguration.Platform }
        $currentDatabaseIndex = 0
        foreach ($commonParamObject in $filteredObjects) {
            foreach ($clientType in $commonParamObject.ClientTypeResultArray) {
                # Add to common catalog file
                if ($addToCommonCatalogFile -and (($commonParamObject.Platform -eq "Azure" -and $commonParamObject.AuthenticationType -eq "Kerberos" -and $commonParamObject.AccessPointType -eq "Alias"))) {
                    $commonCobolCatalogFileContent += $clientType.Result
                    $commonCobolCatalogFileContent += "`n"
                    $commonCobolCatalogFileContent += "`n"
                }        
                if ($addToCommonCatalogFile -and (($commonParamObject.Platform -eq "Azure" -and $commonParamObject.AuthenticationType -eq "KerberosServerEncrypt" -and $commonParamObject.AccessPointType -eq "Alias"))) {
                    $commonCobolCatalogFileContent += $clientType.Result
                    $commonCobolCatalogFileContent += "`n"
                    $commonCobolCatalogFileContent += "`n"
                }
                if ($addToCommonCatalogFile -and (($commonParamObject.Platform -eq "Azure" -and $commonParamObject.AuthenticationType -eq "Ntlm" -and $commonParamObject.AccessPointType -eq "FederatedDb"))) {
                    $commonFederatedCatalogFileContent += $clientType.Result
                    $commonFederatedCatalogFileContent += "`n"
                    $commonFederatedCatalogFileContent += "`n"
                }
                # Add to single client config file
                $db2CatalogContent = "@echo off`n" + $clientType.Result

                $db2ClientConfigFileName = Get-CommonPartOfCatalogFilePath -Name $commonParamObject.RemoteDatabaseName -AuthenticationType $commonParamObject.AuthenticationType -ClientType $clientType.ClientType -Platform $commonParamObject.Platform -DirectExport

                Start-Sleep -Milliseconds 300

                Set-Content -Path $db2ClientConfigFileName -Value $db2CatalogContent
                if (-not (Test-Path $db2ClientConfigFileName -PathType Leaf)) {
                    Write-LogMessage "Failed to create DB2 $($commonParamObject.AuthenticationType) catalog file: $db2ClientConfigFileName" -Level ERROR
                    throw
                }
                Write-LogMessage "DB2 $($commonParamObject.AuthenticationType) catalog file for $($commonParamObject.CatalogName) created at $($db2ClientConfigFileName)" -Level INFO
                $generatedFileNames += [PSCustomObject]@{
                    Platform           = $commonParamObject.Platform
                    AuthenticationType = $commonParamObject.AuthenticationType
                    Version            = $commonParamObject.Version
                    ClientType         = $clientType.ClientType
                    DatabaseName       = $commonParamObject.DatabaseName
                    RemoteDatabaseName = $commonParamObject.RemoteDatabaseName
                    FileName           = $db2ClientConfigFileName
                }
                $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "Added config for $($commonParamObject.AuthenticationType) / $($clientType.ClientType) / $($commonParamObject.CatalogName)" -Script $db2CatalogContent -Output "Successfully added $($commonParamObject.AuthenticationType) / $($commonParamObject.CatalogName) $($clientType.ClientType) client configuration file to $($db2ClientConfigFileName)"

            }
        }
    }


    ########################################################
    # Add to common catalog file for Cobol access
    ########################################################
    if ($addToCommonCatalogFile) {
        if ($commonCobolCatalogFileContent.Count -gt 0) {
            Write-LogMessage "Creating Common Azure Kerberos Cobol Catalog File for $($distinctConfiguration.Platform) $($distinctConfiguration.AuthenticationType)" -Level INFO
            $currentFileName = $(Join-Path $(Get-ClientFolderPath) "Catalog-Script-For-All-Cobol-Applications-For-All-Environments.bat").ToString()
            $commonCobolCatalogFileContent = New-CommonCatalogFileContent -CatalogFileName $currentFileName -CatalogFileContent $commonCobolCatalogFileContent
            $generatedFileNames += [PSCustomObject]@{
                Platform           = "Azure"
                AuthenticationType = "*"
                Version            = "*"
                ClientType         = "Cobol"
                DatabaseName       = "*"
                RemoteDatabaseName = "*"
                FileName           = $currentFileName
            }
        }
        if ($commonFederatedCatalogFileContent.Count -gt 0) {
            Write-LogMessage "Creating Azure Common Ntlm Federated Catalog File for $($distinctConfiguration.Platform) $($distinctConfiguration.AuthenticationType)" -Level INFO
            $currentFileName = $(Join-Path $(Get-ClientFolderPath) "Catalog-Script-For-All-External-Integration-Clients-For-All-Environments.bat").ToString()
            $generatedFileNames += [PSCustomObject]@{
                Platform           = "Azure"
                AuthenticationType = "*"
                Version            = "*"
                ClientType         = "Federated"
                DatabaseName       = "*"
                RemoteDatabaseName = "*"
                FileName           = $currentFileName
            }
            $commonFederatedCatalogFileContent = New-CommonCatalogFileContent -CatalogFileName $currentFileName -CatalogFileContent $commonFederatedCatalogFileContent
        }
        Write-LogMessage "Finished creating client configuration scripts for all databases: $(Get-ClientFolderPath)" -Level INFO
        if ($env:USERNAME -eq "FKGEISTA") {
            Start-Process "explorer.exe" $(Get-ClientFolderPath)
        }
    }
    $WorkObject.GeneratedFileNames = $generatedFileNames
    # Export database object to file
    Write-LogMessage "Exporting object to file" -Level INFO
    
    # FIXED: Use WorkFolder from WorkObject if available, otherwise fall back to Get-ApplicationDataPath
    if ($WorkObject.PSObject.Properties['WorkFolder'] -and -not [string]::IsNullOrEmpty($WorkObject.WorkFolder)) {
        $outputFileName = Join-Path $WorkObject.WorkFolder "Db2-AutoGeneratedCatalogsScripts_$(Get-Date -Format "yyyyMMdd_HHmmss").html"
    }
    else {
        $outputFileName = Join-Path $(Get-ApplicationDataPath) "Db2-AutoGeneratedCatalogsScripts_$(Get-Date -Format "yyyyMMdd_HHmmss").html"
    }
    
    Export-WorkObjectToHtmlFile -WorkObject $WorkObject -FileName $outputFileName -Title "Db2 Auto Generated Catalogs Scipts" -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2"
    Write-LogMessage "Finished creating client configuration scripts" -Level INFO

}

function Add-Db2GroupsAndUsersToDb2admnsAndDb2users {
    Remove-LocalGroupMember -Group DB2ADMNS -member "DEDGE\db2nt" -ErrorAction SilentlyContinue

    Remove-LocalGroupMember -Group DB2ADMNS -member "DEDGE\ACL_Dedge_Servere_Utviklere" -ErrorAction SilentlyContinue

    Remove-LocalGroupMember -Group DB2ADMNS -member "DEDGE\ACL_ERPUTV_Utvikling_Full" -ErrorAction SilentlyContinue

    Remove-LocalGroupMember -Group DB2USERS -member "DEDGE\Domain Users" -ErrorAction SilentlyContinue

    Add-LocalGroupMember -Group DB2ADMNS -member "DEDGE\db2nt" -ErrorAction Stop
    Write-LogMessage "Successfully added DEDGE\db2nt to DB2ADMNS" -Level INFO

    Add-LocalGroupMember -Group DB2ADMNS -member "DEDGE\ACL_Dedge_Servere_Utviklere" -ErrorAction Stop
    Write-LogMessage "Successfully added DEDGE\ACL_Dedge_Servere_Utviklere to DB2ADMNS" -Level INFO

    Add-LocalGroupMember -Group DB2ADMNS -member "DEDGE\ACL_ERPUTV_Utvikling_Full" -ErrorAction Stop
    Write-LogMessage "Successfully added DEDGE\ACL_ERPUTV_Utvikling_Full to DB2ADMNS" -Level INFO


    Add-LocalGroupMember -Group DB2USERS -member "DEDGE\Domain Users" -ErrorAction Stop
    Write-LogMessage "Successfully added DEDGE\Domain Users to DB2USERS" -Level INFO

    Get-LocalGroupMember -Group DB2ADMNS | Format-Table -AutoSize

    Get-LocalGroupMember -Group DB2USERS | Format-Table -AutoSize
}

function Start-Db2AutoCatalog {
    try {
        Write-LogMessage "Starting Db2 auto catalog" -Level INFO
        . "$env:OptPath\DedgePshApps\Db2-AutoCatalog\Db2-AutoCatalog.ps1"
    }
    catch {
        Write-LogMessage "Failed to start Db2 auto catalog: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

function Invoke-Db2ClientConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        $CommonParamObject
    )

    try {
        Add-Member -InputObject $CommonParamObject -MemberType NoteProperty -Name "ClientType" -Value $null -Force

        if (-not $(Get-Member -InputObject $CommonParamObject -Name "ClientTypeResultArray")) {
            Add-Member -InputObject $CommonParamObject -MemberType NoteProperty -Name "ClientTypeResultArray" -Value @() -Force
        }

        if ($CommonParamObject.AuthenticationType -eq "Kerberos" -or $CommonParamObject.AuthenticationType -eq "KerberosServerEncrypt") {
            $CommonParamObject.ClientType = "Db2Client"
            $CommonParamObject = Set-Db2KerberosClientConfig $CommonParamObject
            if ($CommonParamObject.AccessPointType -eq "Alias") {
                $CommonParamObject.ClientType = "Odbc"
                $CommonParamObject = Set-Db2KerberosClientConfig $CommonParamObject
            }
        }
        elseif ($CommonParamObject.AuthenticationType -eq "Ntlm") {
            $CommonParamObject.ClientType = "Db2Client"
            $CommonParamObject = Set-Db2NtlmClientConfig $CommonParamObject
            if ($CommonParamObject.AccessPointType -eq "FederatedDb") {
                $CommonParamObject.ClientType = "Odbc"
                $CommonParamObject = Set-Db2NtlmClientConfig $CommonParamObject
            }
        }

    }
    catch {
        Write-LogMessage "Error setting $($CommonParamObject.Platform) $($CommonParamObject.AuthenticationType) $($CommonParamObject.Version) $($CommonParamObject.DatabaseName) $($CommonParamObject.RemoteDatabaseName) client configuration: $_" -Level ERROR -Exception $_
    }
    return $CommonParamObject
}

function Get-WorkFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrimaryDatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$OverrideWorkFolder
    )
    $workFolder = ""
    if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) {
        # Use explicitly provided override folder
        $workFolder = $OverrideWorkFolder
    }
    else {
        # FIXED: Removed -Force flag to respect global override ($global:OverrideAppDataFolder)
        # This allows Set-OverrideAppDataFolder to control the base path
        $baseFolder = Get-ApplicationDataPath
        $workFolder = Join-Path $baseFolder $PrimaryDatabaseName $(Get-Date -Format "yyyyMMdd-HHmmss")
    }
    return $workFolder
}

function Test-Db2ServerAndAdmin {
    # Check if script is running on a server
    if (-not (Test-IsDb2Server -Quiet $true)) {
        Write-LogMessage "This script must be run on a server" -Level ERROR
        throw "This script must be run on a server"
    }

    # Check if script is running as administrator
    if (-not ( [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-LogMessage "This script must be run as administrator" -Level ERROR
        throw "This script must be run as administrator"
    }
}



function Get-DistinctEnviromentForInstance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $true)]
        [string]$DatabaseType
    )
    $distinctEnvironments = @()
    try {
        $foundDatabasePortConfiguration = $false
        $databasePortConfigurations = $(Get-DatabasesV2Json) | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.Provider -eq "DB2" }

        if ($null -eq $databasePortConfigurations) {
            Write-LogMessage "Database port configurations not found for $($env:COMPUTERNAME)" -Level ERROR
            throw "Database port configurations not found for $($env:COMPUTERNAME)"
        }
        $foundDatabasePortConfiguration = $false
        $databasePortConfiguration = $null
        foreach ($currentDatabasePortConfiguration in $databasePortConfigurations) {
            #AccessPoints

            foreach ($accessPoint in $currentDatabasePortConfiguration.AccessPoints) {
                if ($accessPoint.AccessPointType -eq $DatabaseType -and $accessPoint.IsActive -eq $true -and $accessPoint.InstanceName -eq $InstanceName) {
                    $primaryDatabaseName = $currentDatabasePortConfiguration.Database
                    $foundDatabasePortConfiguration = $true
                    $databasePortConfiguration = $currentDatabasePortConfiguration
                    break
                }
                if ($foundDatabasePortConfiguration -eq $true) {
                    break
                }
            }
        }
        if ($foundDatabasePortConfiguration -eq $false) {
            Write-LogMessage "Database port configuration not found for $($primaryDatabaseName)" -Level ERROR
            throw "Database port configuration not found for $($primaryDatabaseName)"
        }
        $distinctEnvironments = $(Get-DatabasesV2Json) | Where-Object { $_.Application.ToLower().Trim() -eq $databasePortConfiguration.Application.ToLower().Trim() -and $_.Provider -eq "DB2" } | Select-Object -ExpandProperty Environment -Unique

    }
    catch {
        Write-LogMessage "Error getting environment list: $_" -Level ERROR -Exception $_
        throw "Error getting environment list: $_"
    }
    return $distinctEnvironments
}
function Get-DatabaseConfigFromDatabaseName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName
    )
    try {
        # $databaseConfigurations = $(Get-DatabasesV2Json) | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.Provider -eq "DB2" -and $_.IsActive -eq $true }
        $databaseConfigurations = $(Get-DatabasesV2Json) | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.Provider -eq "DB2" }
        if ($databaseConfigurations.Count -eq 0) {
            Write-LogMessage "Database configurations not found for $($env:COMPUTERNAME)" -Level FATAL
            throw "Database configurations not found for $($env:COMPUTERNAME)"
        }
        if ($databaseConfigurations[0] |  Where-Object { $_.IsActive -eq $false }) {
            Write-LogMessage "Database configurations found for $($env:COMPUTERNAME), but is not active" -Level FATAL
            throw "Database configurations found for $($env:COMPUTERNAME), but is not active"
        }

        $databaseConfig = $databaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseName } } | Select-Object -First 1
        $databaseAccessPoint = $databaseConfig.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseName } | Select-Object -First 1
        $externalAccessPoint = $databaseConfig.AccessPoints | Where-Object { $_.CatalogName -eq $databaseConfig.PrimaryCatalogName } | Select-Object -First 1

        if ($null -eq $externalAccessPoint -and $null -ne $databaseAccessPoint) {
            $externalAccessPoint = $databaseAccessPoint
        }

        if ($null -eq $externalAccessPoint -and $null -eq $databaseAccessPoint) {
            Write-LogMessage "Database configuration not found for $($DatabaseName)" -Level ERROR
            throw "Database configuration not found for $($DatabaseName)"
        }

        # Add all properties to the databaseConfig
        foreach ($property in $databaseAccessPoint.PSObject.Properties) {
            Add-Member -InputObject $databaseConfig -MemberType NoteProperty -Name $($property.Name) -Value $property.Value -Force
        }
        Add-Member -InputObject $databaseConfig -MemberType NoteProperty -Name "ExternalAccessPoint" -Value $externalAccessPoint -Force
    }
    catch {
        Write-LogMessage "Error getting database configuration from database name: $_" -Level ERROR -Exception $_
        throw $_
    }
    return $databaseConfig
}


function Get-DatabaseConfigFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    try {
        $databaseConfigurations = $(Get-DatabasesV2Json) | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.Provider -eq "DB2" -and $_.IsActive -eq $true }
        if ($databaseConfigurations.Count -eq 0) {
            Write-LogMessage "Database configurations not found for $($env:COMPUTERNAME)" -Level ERROR
            throw "Database configurations not found for $($env:COMPUTERNAME)"
        }

        $databaseConfig = $databaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.InstanceName -eq $InstanceName -and $_.AccessPointType -eq "PrimaryDb" } } | Select-Object -First 1
        $databaseAccessPoint = $databaseConfig.AccessPoints | Where-Object { $_.CatalogName -eq $databaseConfig.Database } | Select-Object -First 1
        $externalAccessPoint = $databaseConfig.AccessPoints | Where-Object { $_.CatalogName -eq $databaseConfig.PrimaryCatalogName } | Select-Object -First 1

        if ($null -eq $externalAccessPoint -and $null -ne $databaseAccessPoint) {
            $externalAccessPoint = $databaseAccessPoint
        }

        if ($null -eq $externalAccessPoint -and $null -eq $databaseAccessPoint) {
            Write-LogMessage "Database configuration not found for $($DatabaseName)" -Level ERROR
            throw "Database configuration not found for $($DatabaseName)"
        }

        # Add all properties to the databaseConfig
        foreach ($property in $databaseAccessPoint.PSObject.Properties) {
            Add-Member -InputObject $databaseConfig -MemberType NoteProperty -Name $($property.Name) -Value $property.Value -Force
        }
        Add-Member -InputObject $databaseConfig -MemberType NoteProperty -Name "ExternalAccessPoint" -Value $externalAccessPoint -Force
    }
    catch {
        Write-LogMessage "Error getting database configuration from database name: $_" -Level ERROR -Exception $_
        throw $_
    }
    return $databaseConfig
}
# function Get-DatabaseConfigFromInstanceName {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$InstanceName
#     )
#     try {
#         $databaseConfiguration = $(Get-DatabasesV2Json) | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.InstanceName -eq $InstanceName -and $_.Provider -eq "DB2" -and $_.IsActive -eq $true }
#         if ($null -eq $databaseConfiguration) {
#             Write-LogMessage "Database configuration not found for $($InstanceName)" -Level ERROR
#             throw "Database configuration not found for $($InstanceName)"
#         }
#         if ($databaseConfiguration.Count -gt 1) {
#             Write-LogMessage "Multiple database configurations found for $($InstanceName)" -Level ERROR
#             throw "Multiple database configurations found for $($InstanceName)"
#         }
#         $databaseConfiguration = $databaseConfiguration[0]
#         $DatabaseAndAccessPointInfo = $null
#         foreach ($accessPoint in $databaseConfiguration.AccessPoints) {
#             if ($accessPoint.CatalogName -eq $DatabaseName) {
#                 $DatabaseAndAccessPointInfo = $accessPoint
#                 foreach ($accessPoint in $databaseConfiguration) {
#                     # Add all properties to the TargetDatabaseAndAccessPointInfo
#                     foreach ($property in $accessPoint.PSObject.Properties) {
#                         Add-Member -InputObject $DatabaseAndAccessPointInfo -MemberType NoteProperty -Name $($property.Name) -Value $property.Value -Force
#                     }
#                 }
#                 break
#             }
#         }
#     }
#     catch {
#         Write-LogMessage "Error getting database configuration from database name: $_" -Level ERROR -Exception $_
#         throw $_
#     }
#     return $DatabaseAndAccessPointInfo
# }
<#
.SYNOPSIS
    Restarts Db2 instance and activates database.

.DESCRIPTION
    Full instance restart sequence:
    - db2stop force
    - db2start  
    - db2 activate database <DatabaseName>

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Restart-InstanceAndActivateDatabase -WorkObject $workObject
    # Restarts instance and activates database

.NOTES
    Alias naming convention using "ReStart" instead of "Restart". Functionally identical to Restart-Db2AndActivateDb.
#>
function Restart-InstanceAndActivateDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Restarting Db2-Instance and activating database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $db2Commands += "db2stop force"
        $db2Commands += "db2start"
        $db2Commands += "db2 activate database $($WorkObject.DatabaseName)"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output         
    }
    catch {
        Write-LogMessage "Error restarting Db2-Instance and activating database: $_" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


function Get-DefaultWorkObjectsCommon {
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [ValidateSet("PrimaryDb", "FederatedDb")]
        [string]$DatabaseType,
        [Parameter(Mandatory = $false)]
        [string]$InstanceName,
        [Parameter(Mandatory = $false)]
        [string]$OverrideWorkFolder,
        [Parameter(Mandatory = $false)]
        [string[]]$SmsNumbers = @(),
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        # Server params
        [Parameter(Mandatory = $false)]
        [switch]$DropExistingDatabases = $false,
        [Parameter(Mandatory = $false)]
        [string]$GetBackupFromEnvironment = "",
        [Parameter(Mandatory = $false)]
        [switch]$SkipRecreateDb2Folders = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipDb2StateInfo = $false,
        [Parameter(Mandatory = $false)]
        [switch]$QuickMode = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )

    try {
        # Override params if not running on a Db2 server
        if (-not (Test-IsDb2Server)) {
            $DropExistingDatabases = $false
            $SkipRecreateDb2Folders = $true
            $GetBackupFromEnvironment = ""
            $SkipDb2StateInfo = $true
        }

        if ($QuickMode) {
            $Quiet = $true
            $SkipDb2StateInfo = $true
            $SkipRecreateDb2Folders = $true
            $DropExistingDatabases = $false
            $GetBackupFromEnvironment = ""
            $SmsNumbers = @()
        }
        $currentDatabaseConfigurations = $(Get-DatabasesV2Json) 
        if (Test-IsDb2Server) {
            $currentDatabaseConfigurations = $currentDatabaseConfigurations | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.Provider -eq "DB2" }
        }
        $shadowInstanceRequested = $false
        if ((Test-IsDb2Server) -and -not $QuickMode) {
            # Get database configuration for server
            if ($PSBoundParameters.ContainsKey("InstanceName") -and -not [string]::IsNullOrEmpty($InstanceName)) {
                if ($InstanceName -eq "DB2SH" -and $UseNewConfigurations) {
                    # Shadow instance: use this server's primary DB config, work object will override to DB2SH / CatalogName+SH
                    $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.InstanceName -eq "DB2" -and $_.AccessPointType -eq "PrimaryDb" -and $_.IsActive -eq $true } } | Select-Object -First 1
                    $shadowInstanceRequested = $true
                }
                elseif ($InstanceName.ToUpper().Contains("FED")) {
                    $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.InstanceName -eq $(Get-PrimaryInstanceNameFromFederatedInstanceName -FederatedInstanceName $InstanceName) -and $_.AccessPointType -eq "PrimaryDb" -and $_.IsActive -eq $true } }
                }   
                else {
                    $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.InstanceName -eq $InstanceName -and $_.AccessPointType -eq "PrimaryDb" -and $_.IsActive -eq $true } }
                }
            }
            elseif ($PSBoundParameters.ContainsKey("DatabaseName") -and -not [string]::IsNullOrEmpty($DatabaseName)) {
                # Expand access points and find the matching access point with same catalog name as $DatabaseName
                $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseName -and $_.IsActive -eq $true } }
                $accessPoint = $databaseConfiguration.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseName -and $_.IsActive -eq $true }
                $InstanceName = $accessPoint.InstanceName
                $DatabaseType = $accessPoint.AccessPointType
            }
            else {
                Write-LogMessage "Database name or instance name and database type must be set" -Level ERROR
                throw "Database name or instance name and database type must be set"
            }

            if ($null -eq $databaseConfiguration) {
                Write-LogMessage "Database configuration not found for $($env:COMPUTERNAME)" -Level ERROR
                throw "Database configuration not found for $($env:COMPUTERNAME)"
            }
        }
        else {
            
            if ($PSBoundParameters.ContainsKey("InstanceName") -and -not [string]::IsNullOrEmpty($InstanceName)) {
                if ($InstanceName.ToUpper().Contains("FED")) {
                    $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.InstanceName -eq $(Get-PrimaryInstanceNameFromFederatedInstanceName -FederatedInstanceName $InstanceName) -and $_.AccessPointType -eq "PrimaryDb" -and $_.IsActive -eq $true } }
                }   
                else {
                    $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.InstanceName -eq $InstanceName -and $_.AccessPointType -eq "PrimaryDb" -and $_.IsActive -eq $true } }
                }
            }
            elseif ($PSBoundParameters.ContainsKey("DatabaseName") -and -not [string]::IsNullOrEmpty($DatabaseName)) {
                # Get database configuration when not running on a Db2 server (same resolution as Test-IsDb2Server branch: by catalog, not by $DatabaseType — that param is often omitted and must not filter before it is known).
                $currentDatabaseConfigurations = $(Get-DatabasesV2Json) | Where-Object { $_.Provider -eq "DB2" }
                $databaseConfiguration = $currentDatabaseConfigurations | Where-Object { $_.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseName -and $_.IsActive -eq $true } }
                $accessPoint = @($databaseConfiguration.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseName -and $_.IsActive -eq $true }) | Select-Object -First 1
                if ($null -eq $accessPoint) {
                    Write-LogMessage "No active access point found for catalog $($DatabaseName) in DB2 database configuration." -Level ERROR
                    throw "No active access point found for catalog $($DatabaseName)."
                }
                $InstanceName = $accessPoint.InstanceName
                if ($PSBoundParameters.ContainsKey("DatabaseType") -and -not [string]::IsNullOrWhiteSpace($DatabaseType)) {
                    if ($accessPoint.AccessPointType -ne $DatabaseType) {
                        Write-LogMessage "Access point for $($DatabaseName) has type $($accessPoint.AccessPointType); expected $($DatabaseType)." -Level ERROR
                        throw "Access point type mismatch for catalog $($DatabaseName)."
                    }
                }
                else {
                    $DatabaseType = $accessPoint.AccessPointType
                }
            }
            else {
                Write-LogMessage "Database name or instance name and database type must be set" -Level ERROR
                throw "Database name or instance name and database type must be set"
            }

            if ($null -eq $databaseConfiguration) {
                Write-LogMessage "Database configuration not found for $($env:COMPUTERNAME)" -Level ERROR
                throw "Database configuration not found for $($env:COMPUTERNAME)"
            }
        }


        $computerInfo = Get-ComputerInfoJson | Where-Object { $_.Name -eq $databaseConfiguration.ServerName }
        # Get primary access point
        Write-LogMessage "Getting primary access point from database configuration" -Level INFO -Quiet:$Quiet
        $primaryAccessPoint = $databaseConfiguration.AccessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" } | Select-Object -First 1
        if ($null -eq $primaryAccessPoint) {
            Write-LogMessage "Primary access point not found for $($databaseConfiguration.DatabaseName)" -Level ERROR
            throw "Primary access point not found for $($databaseConfiguration.DatabaseName)"
        }

        # Get alias access points
        Write-LogMessage "Getting alias access points from database configuration" -Level INFO -Quiet:$Quiet
        $aliasAccessPoints = $databaseConfiguration.AccessPoints | Where-Object { $_.AccessPointType -eq "Alias" -and $_.IsActive -eq $true }
        $tempAliasAccessPoints = @()
        $RemoteAccessPoint = $aliasAccessPoints | Where-Object { $_.CatalogName -eq $databaseConfiguration.PrimaryCatalogName }
        $tempAliasAccessPoints += $RemoteAccessPoint

        $tempAliasAccessPoints += $aliasAccessPoints | Where-Object { $_.CatalogName -ne $databaseConfiguration.PrimaryCatalogName }
        $aliasAccessPoints = $tempAliasAccessPoints
        $dbDisplayName = $primaryAccessPoint.CatalogName
        if ($null -eq $aliasAccessPoints -or @($aliasAccessPoints).Count -eq 0) {
            if ($UseNewConfigurations) {
                Write-LogMessage "No alias access points configured for $($dbDisplayName) - skipping aliases" -Level INFO
            } else {
                Write-LogMessage "No alias access points configured for $($primaryDatabaseName) - skipping aliases" -Level WARN
            }
        }

        # Get federated access point (optional - not all databases have federation)
        Write-LogMessage "Getting federated access point from database port configuration" -Level INFO -Quiet:$Quiet
        $federatedAccessPoint = $databaseConfiguration.AccessPoints | Where-Object { $_.AccessPointType -eq "FederatedDb" -and $_.IsActive -eq $true } | Select-Object -First 1
        if ($null -eq $federatedAccessPoint) {
            if ($UseNewConfigurations) {
                Write-LogMessage "No federated access point configured for $($dbDisplayName) - skipping federation" -Level INFO
            } else {
                Write-LogMessage "No federated access point configured for $($primaryDatabaseName) - skipping federation" -Level WARN
            }
        }

        Add-Member -InputObject $databaseConfiguration -MemberType NoteProperty -Name "PrimaryAccessPoint" -Value $primaryAccessPoint -Force
        Add-Member -InputObject $databaseConfiguration -MemberType NoteProperty -Name "RemoteAccessPoint" -Value $RemoteAccessPoint -Force
        Add-Member -InputObject $databaseConfiguration -MemberType NoteProperty -Name "AliasAccessPoints" -Value $aliasAccessPoints -Force
        Add-Member -InputObject $databaseConfiguration -MemberType NoteProperty -Name "FederatedAccessPoint" -Value $federatedAccessPoint -Force    



        if ($DatabaseType -eq "PrimaryDb") {
            # Create database object (override to shadow instance/DB when UseNewConfigurations and DB2SH requested)
            $primaryCatalog = $databaseConfiguration.PrimaryAccessPoint.CatalogName
            $effectiveInstanceName = if ($shadowInstanceRequested) { "DB2SH" } else { $databaseConfiguration.PrimaryAccessPoint.InstanceName }
            $effectiveDatabaseName = if ($shadowInstanceRequested) { "$($primaryCatalog)SH" } else { $primaryCatalog }
            if ($shadowInstanceRequested) {
                Write-LogMessage "UseNewConfigurations: Building shadow work object for $($effectiveDatabaseName) on $($effectiveInstanceName)" -Level INFO -Quiet:$Quiet
            }
            $remoteAp = $databaseConfiguration.RemoteAccessPoint
            if ($null -eq $remoteAp) { $remoteAp = $databaseConfiguration.PrimaryAccessPoint }
            Write-LogMessage "Creating database object" -Level INFO -Quiet:$Quiet
            $workObject = [PSCustomObject]@{
                DatabaseType             = "PrimaryDb"
                DropExistingDatabase     = $DropExistingDatabases ? $true : $false
                CreationTimestamp        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                CreationUserName         = "$($env:USERDOMAIN)\$($env:USERNAME)"
                ServerName               = $databaseConfiguration.ServerName
                InternalDatabaseName     = $effectiveDatabaseName
                DatabaseName             = $effectiveDatabaseName
                Platform                 = "Azure"
                Version                  = $databaseConfiguration.Version
                PrimaryAccessPoint       = $databaseConfiguration.PrimaryAccessPoint
                AliasAccessPoints        = $databaseConfiguration.AliasAccessPoints
                RemoteAccessPoint        = $databaseConfiguration.RemoteAccessPoint
                RemoteDatabaseName       = $remoteAp.CatalogName
                RemoteServiceName        = $remoteAp.ServiceName
                RemoteNodeName           = $remoteAp.NodeName
                RemotePort               = $remoteAp.Port
                Application              = $databaseConfiguration.Application
                Environment              = $databaseConfiguration.Environment
                PrimaryDb2DataDisk       = if (Test-IsDb2Server) { $(Get-PrimaryDb2DataDisk) } else { "" }
                InstanceName             = $effectiveInstanceName
                SecondsToWait            = 1
                AuthenticationType       = $databaseConfiguration.PrimaryAccessPoint.AuthenticationType
                AdminUsers               = $(Get-DefaultDb2AdminUsers)
                WorkFolder               = $(Get-WorkFolder -PrimaryDatabaseName $databaseConfiguration.PrimaryAccessPoint.CatalogName -OverrideWorkFolder $OverrideWorkFolder)
                ServiceUserName          = $computerInfo.ServiceUserName
                ServicePassword          = $(if (Test-IsDb2Server) { $(Get-SecureStringUserPasswordAsPlainText) } else { "" })
                SmsNumbers               = $SmsNumbers
                GetBackupFromEnvironment = $GetBackupFromEnvironment
                ScriptArray              = @()
                UseNewConfigurations     = $UseNewConfigurations
            }
            # if (-not (Test-IsDb2Server)) {
            #     Write-LogMessage "Setting database name to remote database name" -Level INFO
            #     $workObject.DatabaseName = $workObject.RemoteDatabaseName
            # }
            if ((Test-IsDb2Server) -and -not $QuickMode) {
                if (-not $SkipDb2StateInfo) {
                    # Get current Db2 state info, that includes post-restore credentials, if possible
                    Write-LogMessage "Getting current Db2 state info, that includes post-restore credentials, if possible" -Level INFO -Quiet:$Quiet
                    $WorkObject = Get-CurrentDb2StateInfo -WorkObject $workObject -GetAllDatabasesInfo
                    if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN -Quiet:$Quiet; $WorkObject = $WorkObject[-1] }
                }
            }
            if ($workObject.ServerName.Trim().ToUpper() -eq $env:COMPUTERNAME.Trim().ToUpper()) {
                $workObject = Get-Db2Folders -WorkObject $workObject -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet
                if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
            }

            
        }
        elseif ($DatabaseType -eq "FederatedDb") {
            if ($null -eq $databaseConfiguration.FederatedAccessPoint) {
                Write-LogMessage "No FederatedDb access point in config for $($databaseConfiguration.Database) — federation removed (UseNewConfigurations). Returning null." -Level WARN
                return $null
            }
            # Create federated database
            $workObject = [PSCustomObject]@{
                DatabaseType             = "FederatedDb"
                DropExistingDatabase     = $DropExistingDatabases ? $true : $false
                CreationTimestamp        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                CreationUserName         = "$($env:USERDOMAIN)\$($env:USERNAME)"
                ServerName               = $databaseConfiguration.ServerName
                InternalDatabaseName     = $databaseConfiguration.FederatedAccessPoint.CatalogName
                DatabaseName             = $databaseConfiguration.FederatedAccessPoint.CatalogName
                Platform                 = "Azure"
                Version                  = $databaseConfiguration.Version
                PrimaryAccessPoint       = $databaseConfiguration.FederatedAccessPoint
                AliasAccessPoints        = @()
                RemoteAccessPoint        = $databaseConfiguration.FederatedAccessPoint
                RemoteDatabaseName       = $databaseConfiguration.FederatedAccessPoint.CatalogName
                RemoteServiceName        = $databaseConfiguration.FederatedAccessPoint.ServiceName
                RemoteNodeName           = $databaseConfiguration.FederatedAccessPoint.NodeName
                RemotePort               = $databaseConfiguration.FederatedAccessPoint.Port
                Application              = $databaseConfiguration.Application
                Environment              = $databaseConfiguration.Environment
                PrimaryDb2DataDisk       = if (Test-IsDb2Server) { $(Get-PrimaryDb2DataDisk) } else { "" }
                InstanceName             = $databaseConfiguration.FederatedAccessPoint.InstanceName
                SecondsToWait            = 1
                AuthenticationType       = $databaseConfiguration.FederatedAccessPoint.AuthenticationType
                AdminUsers               = $(Get-DefaultDb2AdminUsers)
                WorkFolder               = $(Get-WorkFolder -PrimaryDatabaseName $databaseConfiguration.FederatedAccessPoint.CatalogName -OverrideWorkFolder $OverrideWorkFolder)
                ServiceUserName          = $computerInfo.ServiceUserName
                ServicePassword          = $(if (Test-IsDb2Server) { $(Get-SecureStringUserPasswordAsPlainText) } else { "" })
                SmsNumbers               = $SmsNumbers
                GetBackupFromEnvironment = $GetBackupFromEnvironment
                ScriptArray              = @()
                UseNewConfigurations     = $UseNewConfigurations
            }
            if ((Test-IsDb2Server) -and -not $QuickMode) {
                if (-not $SkipDb2StateInfo) {
                    # Get current Db2 state info, that includes post-restore credentials, if possible
                    Write-LogMessage "Getting current Db2 state info, that includes post-restore credentials, if possible" -Level INFO -Quiet:$Quiet
                    $workObject = Get-CurrentDb2StateInfo -WorkObject $workObject -GetAllDatabasesInfo
                    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN -Quiet:$Quiet; $workObject = $workObject[-1] }
                }
            }
            if ($workObject.ServerName.Trim().ToUpper() -eq $env:COMPUTERNAME.Trim().ToUpper()) {
                $workObject = Get-Db2Folders -WorkObject $workObject -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet
                if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
            }
        }
    }
    catch {
        Write-LogMessage "Error getting database configuration from database name: $_" -Level ERROR -Exception $_
        throw $_
    }
    return $workObject
}
function Get-DefaultWorkObjects {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
        [string]$DatabaseType,
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$InstanceName,
        [Parameter(Mandatory = $false)]
        [switch]$DropExistingDatabases = $false,
        [Parameter(Mandatory = $false)]
        [string[]]$SmsNumbers = @(),
        [Parameter(Mandatory = $false)]
        [string]$GetBackupFromEnvironment = "",
        [Parameter(Mandatory = $false)]
        [string]$OverrideWorkFolder,
        [Parameter(Mandatory = $false)]
        [switch]$SkipRecreateDb2Folders = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$QuickMode = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipDb2StateInfo = $false,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewConfigurations = $false
    )
    Write-LogMessage "Creating default work object(s) for database type: $DatabaseType, instance name: $InstanceName" -Level INFO -Quiet:$Quiet

    if ( [string]::IsNullOrEmpty($DatabaseName) -and [string]::IsNullOrEmpty($InstanceName)) {
        Write-LogMessage "Database name and instance name are set. One of the parameters must be set. Aborting..." -Level ERROR
        throw "Database name and instance name are set. One of the parameters must be set. Aborting..."
    }


    $workObjects = @()

    # Get database configuration
    if ($DatabaseType -eq "PrimaryDb" -or $DatabaseType -eq "FederatedDb") {
        if (-not [string]::IsNullOrEmpty($DatabaseName)) {
            $workObjects += Get-DefaultWorkObjectsCommon -DatabaseName $DatabaseName -DatabaseType $DatabaseType -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet -QuickMode:$QuickMode -SkipDb2StateInfo:$SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
        }
        else {
            $workObjects += Get-DefaultWorkObjectsCommon -DatabaseType $DatabaseType -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet -QuickMode:$QuickMode -SkipDb2StateInfo:$SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
        }
        
    }
    elseif ($DatabaseType -eq "BothDatabases") {
        if (-not [string]::IsNullOrEmpty($DatabaseName)) {
            $workObjects += Get-DefaultWorkObjectsCommon -DatabaseName $DatabaseName -DatabaseType "PrimaryDb" -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet -QuickMode:$QuickMode -SkipDb2StateInfo:$SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
        }
        else {
            $workObjects += Get-DefaultWorkObjectsCommon -DatabaseType "PrimaryDb" -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet -QuickMode:$QuickMode -SkipDb2StateInfo:$SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
        }
        if (-not [string]::IsNullOrEmpty($DatabaseName)) {
            $workObjects += Get-DefaultWorkObjectsCommon -DatabaseName $DatabaseName -DatabaseType "FederatedDb" -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet -QuickMode:$QuickMode -SkipDb2StateInfo:$SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
        }
        else {
            $workObjects += Get-DefaultWorkObjectsCommon -DatabaseType "FederatedDb" -InstanceName $InstanceName -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SkipRecreateDb2Folders:$SkipRecreateDb2Folders -Quiet:$Quiet -QuickMode:$QuickMode -SkipDb2StateInfo:$SkipDb2StateInfo -UseNewConfigurations:$UseNewConfigurations
        }

    }
    return $workObjects
}

<#
.SYNOPSIS
    Applies complete standard Db2 configuration post-restore or post-creation.

.DESCRIPTION
    Comprehensive configuration function that orchestrates:
    - Directory permission setup
    - Current state info gathering
    - Services file management (remove old, add new)
    - Windows group and user configuration
    - Database permissions
    - Database configurations (authentication, memory, etc.)
    - Log archiving enablement
    - Firewall rules
    - Node and database cataloging
    - Federation support (for FederatedDb or FKM+HST scenarios)
    - Application-specific grants
    - Control SQL verification

.PARAMETER WorkObject
    PSCustomObject containing complete database configuration.

.EXAMPLE
    $workObject = Set-StandardConfigurations -WorkObject $workObject
    # Applies all standard configurations for the database

.NOTES
    Main orchestration function for database setup. Calls 10+ sub-functions in sequence.
#>

<#
.SYNOPSIS
    Validates and corrects database path configuration to match WorkObject paths.

.DESCRIPTION
    After a database restore from a different server (e.g. production to non-production),
    the database configuration may contain paths from the source server that do not exist
    on the target server. This function reads the current database configuration and
    corrects MIRRORLOGPATH, OVERFLOWLOGPATH, LOGARCHMETH1 (DISK path), and EXTBL_LOCATION
    to match the paths defined in WorkObject.

    Addresses DB2 CRITICAL: sqlpgCheckForLogPathChanges probe:1750 caused by
    MIRRORLOGPATH pointing to a non-existent drive after restore.

.PARAMETER WorkObject
    PSCustomObject containing MirrorLogsFolder, PrimaryLogsFolder, and DatabaseName.

.EXAMPLE
    $workObject = Repair-DatabasePathConfiguration -WorkObject $workObject
    # Validates and corrects all path-related database configuration
#>
function Repair-DatabasePathConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Validating database path configuration for $($WorkObject.DatabaseName)" -Level INFO

        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)

        $pathUpdates = @()

        if ($WorkObject.MirrorLogsFolder) {
            $expectedMirrorPath = $WorkObject.MirrorLogsFolder
            if (-not (Test-Path $expectedMirrorPath)) {
                Write-LogMessage "MirrorLogsFolder $expectedMirrorPath does not exist, creating it" -Level WARN
                New-Item -ItemType Directory -Path $expectedMirrorPath -Force | Out-Null
            }
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using MIRRORLOGPATH `"$expectedMirrorPath`""
            $pathUpdates += "MIRRORLOGPATH -> $expectedMirrorPath"
        }
        else {
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using MIRRORLOGPATH `"`""
            $pathUpdates += "MIRRORLOGPATH -> (cleared, no MirrorLogsFolder defined)"
        }

        if ($WorkObject.PrimaryLogsFolder) {
            $expectedPrimaryPath = $WorkObject.PrimaryLogsFolder
            if (-not (Test-Path $expectedPrimaryPath)) {
                Write-LogMessage "PrimaryLogsFolder $expectedPrimaryPath does not exist, creating it" -Level WARN
                New-Item -ItemType Directory -Path $expectedPrimaryPath -Force | Out-Null
            }
            $pathUpdates += "PrimaryLogsFolder verified: $expectedPrimaryPath"
        }

        $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using OVERFLOWLOGPATH `"`""
        $pathUpdates += "OVERFLOWLOGPATH -> (cleared)"

        $primaryDataDisk = $(Get-PrimaryDb2DataDisk)
        if ($primaryDataDisk) {
            $db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using EXTBL_LOCATION $primaryDataDisk"
            $pathUpdates += "EXTBL_LOCATION -> $primaryDataDisk"
        }

        $db2Commands += "db2 terminate"

        foreach ($update in $pathUpdates) {
            Write-LogMessage "Path update: $update" -Level INFO
        }

        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        Add-Member -InputObject $WorkObject -NotePropertyName "DatabasePathsRepaired" -NotePropertyValue $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") -Force

        Write-LogMessage "Database path configuration validated and corrected for $($WorkObject.DatabaseName)" -Level INFO
    }
    catch {
        Write-LogMessage "Error repairing database path configuration for $($WorkObject.DatabaseName): $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

function Set-StandardConfigurations {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Adding Db2 standard configuration for database $($WorkObject.DatabaseName)" -Level INFO
        # Add permissions to IBM DB2 directories
        Add-Db2DirectoryPermission 

        # Get Db2 info on current computer for all instances
        $WorkObject = Get-CurrentDb2StateInfo -WorkObject $WorkObject 
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }


        # Handle database not existing
        if ($WorkObject.DatabaseExist -eq $false) {
            Write-LogMessage "Database does not exist" -Level INFO
            throw "Database does not exist"
        }

        # Handle instance not existing
        if ($WorkObject.InstanceExist -eq $false) {
            Write-LogMessage "Instance does not exist" -Level INFO
            throw "Instance does not exist"
        }

        # # Remove all services from service file
        # $WorkObject = Remove-AllDb2ServicesFromServiceFile -WorkObject $WorkObject
        # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $WorkObject = Remove-Db2ServicesFromServiceFileSimplified -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        $WorkObject = Add-Db2ServicesToServiceFile -WorkObject $WorkObject -ServicesMethod $WorkObject.PrimaryAccessPoint.AccessPointType
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add database users to Windows group
        $WorkObject = Add-Db2AccessGroups -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add database permissions
        $WorkObject = Set-DatabasePermissions -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        
        # Add database configurations
        $WorkObject = Add-DatabaseConfigurations -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Test database recoverability
        $WorkObject = Test-DatabaseRecoverability -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add logging to database for current instance
        if (-not $WorkObject.DatabaseRecoverable) {
            $WorkObject = Add-LoggingToDatabase -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        }

        # Set post restore configuration
        $WorkObject = Set-PostRestoreConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Validate and correct database paths (fixes paths from source server after restore)
        $WorkObject = Repair-DatabasePathConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add firewall rules
        $WorkObject = Add-FirewallRules -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add cataloging for nodes
        $WorkObject = Add-CatalogingForNodes -WorkObject $WorkObject -ServiceMethod $WorkObject.PrimaryAccessPoint.AccessPointType
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add server cataloging for local database
        $WorkObject = Add-ServerCatalogingForLocalDatabase -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Remove legacy services from service file
        # $WorkObject = Remove-Db2ServicesFromServiceFile -WorkObject $WorkObject -ServicesMethod "Legacy"
        # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }




        # $WorkObject = Add-HstSchemaFromFkmNonPrd -WorkObject $WorkObject
        # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }


        

        # Start, stop and activate database
        $WorkObject = Restart-InstanceAndActivateDatabase -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        #backup work object
        $backupWorkObject = $WorkObject

        # Add federation support to databases
        if ($WorkObject.DatabaseType -eq "FederatedDb") {
            # Add-FederationSupportToDatabases -FederationType "Standard" -HandleType "SetupAndRefresh" -InstanceName "DB2" -RegenerateAllNicknames -SmsNumbers $WorkObject.SmsNumbers
            # $WorkObject = Get-ControlSqlStatement -WorkObject $WorkObject -ForceGetControlSqlStatement
            # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            
            # $WorkObject = Test-ControlSqlStatement -WorkObject $WorkObject
            # if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        }
        elseif ($WorkObject.DatabaseType -eq "PrimaryDb" -and $WorkObject.InstanceName -eq "DB2" -and $WorkObject.Application -eq "FKM" ) {
            if ($(Get-EnvironmentFromServerName) -eq "PRD") {
                # Setup and refresh federation support for history database to add HST schema
                try {
                    $result = Add-FederationSupportToDatabases -FederationType "History" -HandleType "SetupAndRefresh" -InstanceName "DB2HST" -RegenerateAllNicknames -SmsNumbers $WorkObject.SmsNumbers
                }
                catch {
                    Write-LogMessage "Error during adding federation support to history database. Adding HST schema using empty tables: $($_.Exception.Message)" -Level ERROR -Exception $_
                    $result = $false
                }
                if ($result -eq $false) {
                    $backupWorkObject = Add-HstSchemaFromFkmNonPrd -WorkObject $backupWorkObject
                    if ($backupWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $backupWorkObject = $backupWorkObject[-1] }
                }
            }
            else {
                # Add HST schema from FKM non PRD using empty tables
                $backupWorkObject = Add-HstSchemaFromFkmNonPrd -WorkObject $backupWorkObject
                if ($backupWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $backupWorkObject = $backupWorkObject[-1] }
            }
        }

        $WorkObject = $backupWorkObject
        try {
            # Add specific grants for given application and environment
            $WorkObject = Add-SpecificGrants -WorkObject $WorkObject
            if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        }
        catch {
            Write-LogMessage "Error adding specific grants for given application and environment" -Level WARN 
        }
        # Get current services from service file

        $currentServices = Get-ServicesFromServiceFile -ServicesPatternIsRegex
        Add-Member -InputObject $WorkObject -NotePropertyName "CurrentServices" -NotePropertyValue $currentServices -Force

        # Set DB2 instance service user name and password (ensures correct service account after restore)
        $WorkObject = Set-InstanceServiceUserNameAndPassword -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }


        # Get database configuration
        $WorkObject = Get-DatabaseConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Get Db2 server configuration
        $WorkObject = Get-Db2InstanceConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Execute control sql statement for current instance
        $WorkObject = Test-ControlSqlStatement -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

    }
    catch {
        Write-LogMessage "Error during adding standard configuration: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Error during adding standard configuration: $($_.Exception.Message)"
    }
    return $WorkObject
}

function ConvertTo-Ansi1252 {
    param(
        [Parameter(Mandatory = $true)]
        $ConvertString
    )
    if ($null -eq $ConvertString) {
        return $ConvertString
    }
    $inputAsArray = $false
    if ($ConvertString.GetType().BaseType -eq [array] -or $ConvertString -is [array]) {
        $inputAsArray = $true
        $ConvertString = $ConvertString -join "`n"
    }    


    # Define encoding objects
    $utf8Encoding = [System.Text.Encoding]::UTF8
    $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
    
    # Convert at byte level: If UTF-8 bytes were misread as ANSI-1252, recover them
    # Step 1: Get ANSI-1252 bytes from the string (if it contains garbled UTF-8, this recovers original UTF-8 bytes)
    $ansiBytes = $ansiEncoding.GetBytes($ConvertString)
    
    # Step 2: Try to interpret bytes as UTF-8 first (handles garbled UTF-8 → correct UTF-8)
    try {
        $utf8String = $utf8Encoding.GetString($ansiBytes)
        # Check if UTF-8 decoding made sense (no replacement characters)
        if ($utf8String.Contains([char]0xFFFD)) {
            # UTF-8 decoding failed, use original string
            Write-LogMessage "UTF-8 decoding produced replacement characters, using original string" -Level DEBUG
            $ansiSelectOutput = $ConvertString
        }
        else {
            # UTF-8 decoding succeeded, now ensure it's valid ANSI-1252
            $ansiSelectOutput = $utf8String
            Write-LogMessage "Successfully decoded UTF-8 from ANSI-1252 byte stream" -Level DEBUG
        }
    }
    catch {
        # If UTF-8 decoding fails completely, use original
        Write-LogMessage "UTF-8 decoding failed, using original string" -Level DEBUG
        $ansiSelectOutput = $ConvertString
    }
    
    # Define strings that should be properly converted
    $controlWordsArray = @(
        "LEVERANDØR",
        "TRANSPORTØR",
        "SJÅFØRLOGG"
    )


    # Define UTF-8 to ANSI-1252 character mappings
    # UTF-8 encoded characters appear as garbled text when read as ANSI-1252
    $replaceArray = @(
        [PSCustomObject]@{
            Utf8Pattern = 'Ã˜'  # UTF-8 Ø (C3 98)
            AnsiChar    = 'Ø'
            Description = "UTF-8 Ø → ANSI Ø"
        },
        [PSCustomObject]@{
            Utf8Pattern = 'Ã†'  # UTF-8 Æ (C3 86)
            AnsiChar    = 'Æ'
            Description = "UTF-8 Æ → ANSI Æ"
        },
        [PSCustomObject]@{
            Utf8Pattern = 'Ã…'  # UTF-8 Å (C3 85)
            AnsiChar    = 'Å'
            Description = "UTF-8 Å → ANSI Å"
        },
        [PSCustomObject]@{
            Utf8Pattern = 'Ã¸'  # UTF-8 ø (C3 B8)
            AnsiChar    = 'ø'
            Description = "UTF-8 ø → ANSI ø"
        },
        [PSCustomObject]@{
            Utf8Pattern = 'Ã¦'  # UTF-8 æ (C3 A6)
            AnsiChar    = 'æ'
            Description = "UTF-8 æ → ANSI æ"
        },
        [PSCustomObject]@{
            Utf8Pattern = 'Ã¥'  # UTF-8 å (C3 A5)
            AnsiChar    = 'å'
            Description = "UTF-8 å → ANSI å"
        }
    )
    
    # Replace UTF-8 encoded patterns with proper ANSI-1252 characters
    $replacementsMade = 0
    foreach ($mapping in $replaceArray) {
        if ($ansiSelectOutput.Contains($mapping.Utf8Pattern)) {
            $ansiSelectOutput = $ansiSelectOutput.Replace($mapping.Utf8Pattern, $mapping.AnsiChar)
            $replacementsMade++
            Write-LogMessage "Replaced UTF-8 pattern: $($mapping.Description)" -Level DEBUG
        }
    }
    
    if ($replacementsMade -gt 0) {
        Write-LogMessage "Converted $($replacementsMade) UTF-8 pattern(s) to ANSI-1252 characters" -Level INFO
    }
    
    # Verify control words are properly converted
    foreach ($word in $controlWordsArray) {
        if ($ConvertString.Contains($word)) {
            if ($ansiSelectOutput.Contains($word)) {
                Write-LogMessage "Control word '$($word)' verified in ANSI-1252 output" -Level DEBUG
            }
            else {
                Write-LogMessage "Warning: Control word '$($word)' found in input but missing in ANSI-1252 output" -Level WARN
            }
        }
    }
    
    # Verification: Check if UTF-8 encoded Norwegian characters still exist
    # UTF-8 encoded Ø is represented as Ã˜ (C3 98) in ANSI-1252
    # UTF-8 encoded Æ is represented as Ã† (C3 86) in ANSI-1252
    # UTF-8 encoded Å is represented as Ã… (C3 85) in ANSI-1252
    # UTF-8 encoded ø is represented as Ã¸ (C3 B8) in ANSI-1252
    # UTF-8 encoded æ is represented as Ã¦ (C3 A6) in ANSI-1252
    # UTF-8 encoded å is represented as Ã¥ (C3 A5) in ANSI-1252
    
    $utf8Patterns = @(
        'Ã˜',  # UTF-8 Ø
        'Ã†',  # UTF-8 Æ
        'Ã…',  # UTF-8 Å
        'Ã¸',  # UTF-8 ø
        'Ã¦',  # UTF-8 æ
        'Ã¥'   # UTF-8 å
    )
    
    $foundUtf8Chars = @()
    foreach ($pattern in $utf8Patterns) {
        if ($ansiSelectOutput -match [regex]::Escape($pattern)) {
            $foundUtf8Chars += $pattern
        }
    }
    
    # Throw exception if UTF-8 encoded characters are still present
    if ($foundUtf8Chars.Count -gt 0) {
        $errorMessage = "ANSI-1252 conversion failed. UTF-8 encoded characters still present in output: $($foundUtf8Chars -join ', '). Original length: $($ConvertString.Length), Converted length: $($ansiSelectOutput.Length)"
        Write-LogMessage $errorMessage -Level ERROR
        throw $errorMessage
    }
    
    # Check for valid ANSI-1252 Norwegian characters to verify conversion
    $norwegianChars = @('Ø', 'Æ', 'Å', 'ø', 'æ', 'å')
    $foundNorwegianChars = @()
    
    foreach ($char in $norwegianChars) {
        if ($ansiSelectOutput.Contains($char)) {
            $foundNorwegianChars += $char
        }
    }
    
    # Log a single warning showing which Norwegian characters are present
    if ($foundNorwegianChars.Count -gt 0) {
        Write-LogMessage "ANSI-1252 string contains Norwegian characters: $($foundNorwegianChars -join ', ') - Verify conversion is correct" -Level WARN
    }
    
    if ($inputAsArray) {
        return $ansiSelectOutput.Split("`n")
    }
    else {
        return $ansiSelectOutput
    }
}
# -------------------------------------------------------------------------------------------------------------------------------- ----------- ----------- ------------
# IBMDEFAULTBP                                                                                                                          100000        4096            1
# BP32K                                                                                                                                   1000       32768            2
# BIGTAB                                                                                                                                500000        4096            3
# USER32                                                                                                                                  5000        4096            4


function Get-SelectResultAsObjectArray {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectOutput
    )
    
    $filteredOutput = @()

    try {
        $startLine = $false
        $resultCount = 0
        # Ensure the string is handled as ANSI-1252 encoding
        # Convert the input string to bytes and back to string using ANSI-1252 encoding
        $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
        $selectOutputBytes = $ansiEncoding.GetBytes($SelectOutput)
        $ansiSelectOutput = $ansiEncoding.GetString($selectOutputBytes)

        # Regex to find the first line 


        foreach ($line in $($ansiSelectOutput -split "`n")) {
            if ($line.StartsWith("-------------------------------------------------")) {
                $startLine = $true
                continue
            }
            if ($line.Contains("post(er) er valgt.")) {
                break
            }

            if ($startLine) {
                $filteredOutput += $line.Trim()
                $resultCount++
            }

        }
    }
    catch {
        Write-LogMessage "Error getting select result output: $($SelectOutput.Substring(0, 100))" -Level WARN -Exception $_
    }
    $filteredOutput = $filteredOutput | Where-Object { [string]::IsNullOrEmpty($_) -eq $false }
    $filteredOutput
    # if ($filteredOutput.Count -gt 0) {
    #     $filteredOutput = ConvertTo-Ansi1252 -ConvertString $filteredOutput
    # }

    if ($filteredOutput.Count -eq 0 -or $null -eq $filteredOutput) {
        $filteredOutput = @()
    }
    if ($ReturnArray) {
        return $filteredOutput
    }
    else {
        return $filteredOutput -join "`n"
    }
}
function Get-SelectResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectOutput,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnArray = $false,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnNumberOfRows = $false
    )
    $filteredOutput = @()

    try {
        $startLine = $false
        $resultCount = 0
        # Ensure the string is handled as ANSI-1252 encoding
        # Convert the input string to bytes and back to string using ANSI-1252 encoding
        $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
        $selectOutputBytes = $ansiEncoding.GetBytes($SelectOutput)
        $ansiSelectOutput = $ansiEncoding.GetString($selectOutputBytes)
        $numberOfRowsFromSelect = 0
        foreach ($line in $($ansiSelectOutput -split "`n")) {
            # Regex: db2 + whitespace + optional quote + "select" (case-insensitive)
            # Matches both: db2 select ...  and  db2 "SELECT ...
            if ($line -match 'db2\s+"?select') {
                $startLine = $true
                continue
            }
            if ($line.Contains("post(er) er valgt.")) {
                $numberOfRowsFromSelect = [int] $line.Trim().Split(" ")[0]
                break
            }

            if ($startLine) {
                $filteredOutput += $line.Trim()
                $resultCount++
            }

        }
    }
    catch {
        Write-LogMessage "Error getting select result output: $($SelectOutput.Substring(0, 100))" -Level WARN -Exception $_
    }
    Write-LogMessage "Number of rows from select: $($numberOfRowsFromSelect)" -Level INFO
    $filteredOutput = $filteredOutput | Where-Object { [string]::IsNullOrEmpty($_) -eq $false }
    # if ($filteredOutput.Count -gt 0) {
    #     $filteredOutput = ConvertTo-Ansi1252 -ConvertString $filteredOutput
    # }

    if ($filteredOutput.Count -eq 0 -or $null -eq $filteredOutput) {
        $filteredOutput = @()
    }
    if ($ReturnNumberOfRows) {
        return $numberOfRowsFromSelect
    }
    if ($ReturnArray) {
        return $filteredOutput
    }
    else {
        return $filteredOutput -join "`n"
    }
}
<#
.SYNOPSIS
    Retrieves all existing nicknames from a federated database.

.DESCRIPTION
    Queries SYSCAT.NICKNAMES to get all federation nicknames with server name, schema,
    table name, and creation time. Parses Db2 timestamp format into DateTime objects.
    Stores results in WorkObject.ListOfExistingNicknames.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, InstanceName, and ServerLinkName.

.EXAMPLE
    $workObject = Get-ExistingNicknames -WorkObject $workObject
    # Populates workObject.ListOfExistingNicknames with nickname metadata

.NOTES
    Used for comparing existing nicknames against linked database tables to determine
    which nicknames to add, drop, or recreate.
#>
function Get-ExistingNicknames {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Getting list of existing nicknames for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 `"SELECT TRIM('$($WorkObject.ServerLinkName)') || CHR(9) || TRIM(TABSCHEMA) || CHR(9) || TRIM(TABNAME) || CHR(9) || CHAR(CREATE_TIME) AS NICKNAME FROM SYSCAT.NICKNAMES`""
        $db2Commands += "db2 commit work"
        $db2Commands += "db2 connect reset"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors  -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output

        $allCurrentNicknames = Get-SelectResult -SelectOutput $output -ReturnArray
        if ($allCurrentNicknames.Count -eq 0 -or $allCurrentNicknames -eq "") {
            $allCurrentNicknames = @()
        }
        $listOfNicknamesObjects = @()
        foreach ($nicknameString in $allCurrentNicknames) {
            $nicknameSplit = $nicknameString.Split("`t")
            try {
                $createTime = Get-DateTimeFromDb2Format -Db2Format $nicknameSplit[3]
            }
            catch {
                $createTime = [datetime]::Now.ToUniversalTime()
            }
            $listOfNicknamesObjects += [PSCustomObject]@{
                SERVERNAME  = $nicknameSplit[0]
                SCHEMA      = $nicknameSplit[1]
                NAME        = $nicknameSplit[2]
                CREATE_TIME = $createTime
            }            
        }     

        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfExistingNicknames" -NotePropertyValue $listOfNicknamesObjects -Force
        Write-LogMessage "Number of existing nicknames: $($listOfNicknamesObjects.Count)" -Level INFO
        # foreach ($nickname in $listOfNicknamesObjects) {
        #     Write-LogMessage "Nickname: $($nickname.TABSCHEMA).$($nickname.TABNAME) - Create Time: $($nickname.CREATE_TIME)" -Level INFO
        # }


    }
    catch {
        Write-LogMessage "Error getting list of existing nicknames for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error getting list of existing nicknames for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Alternative method to retrieve nicknames using array query parser.

.DESCRIPTION
    Queries SYSCAT.NICKNAMES and uses Get-ArrayFromQuery to parse results. Experimental
    alternative to Get-ExistingNicknames with different parsing approach.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName.

.EXAMPLE
    $workObject = Get-ExistingNicknamesNew -WorkObject $workObject
    # Retrieves nicknames using array parser

.NOTES
    Alternative implementation. Consider using Get-ExistingNicknames for standard operations.
#>
function Get-ExistingNicknamesNew {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Getting list of existing nicknames for database $($WorkObject.DatabaseName)" -Level INFO

        #        $command = "db2 export to " + $folderPath + "\" + $exportTableName + ".csv of del modified by coldel;  select tabschema ,tabname ,remarks, type, alter_time from syscat.tables where tabschema in('DBM','HST','CRM','LOG','TV')"

        # $csvModulArray = Import-Csv ($cobdokFolder + "\modul.csv") -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';'
        $result = Get-ArrayFromQuery -DatabaseName $WorkObject.DatabaseName -SelectOutput $("SELECT SERVERNAME , TABSCHEMA, TABNAME, CREATE_TIME FROM SYSCAT.NICKNAMES")
        
        # $result = Get-ExecuteSqlStatementServerSideNew -DatabaseName $WorkObject.DatabaseName -SqlStatement $("SELECT SERVERNAME , TABSCHEMA, TABNAME, CREATE_TIME FROM SYSCAT.NICKNAMES")
        Add-Member -InputObject $WorkObject -NotePropertyName "ListOfExistingNicknames" -NotePropertyValue $result -Force
    }
    catch {
        Write-LogMessage "Error getting list of existing nicknames for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error getting list of existing nicknames for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}

<#
.SYNOPSIS
    Synchronizes federation nicknames with linked database tables.

.DESCRIPTION
    Intelligent nickname management that:
    1. Gets existing nicknames from federated database
    2. Compares with tables in linked database (from WorkObject.ListOfTablesInLinkedDatabase)
    3. Identifies nicknames to ADD (in linked DB but not in federated DB)
    4. Identifies nicknames to DROP (in federated DB but not in linked DB)
    5. Identifies nicknames to RECREATE (ALTER_TIME > CREATE_TIME)
    6. Executes DROP NICKNAME and CREATE NICKNAME commands
    
    Handles schema mapping for History federation (DBM -> HST).

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, InstanceName, ListOfTablesInLinkedDatabase,
    ServerLinkName, LinkedDbFedUser, LinkedDbFedPassword, and RegenerateAllNicknames flag.

.PARAMETER UseNewMethod
    Reserved for alternative implementation (not currently used).

.PARAMETER WhatIf
    Shows commands without executing them. Opens script in code editor.

.EXAMPLE
    $workObject = Start-NicknameHandling -WorkObject $workObject
    # Synchronizes nicknames with linked database tables

.EXAMPLE
    $workObject = Start-NicknameHandling -WorkObject $workObject -WhatIf
    # Shows commands in editor without execution

.NOTES
    If WorkObject.RegenerateAllNicknames=true, drops ALL existing nicknames and recreates from scratch.
#>
function Start-NicknameHandling {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$UseNewMethod = $false,
        [Parameter(Mandatory = $false)]
        [switch]$WhatIf = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false
    )
    try {
        Write-LogMessage "Starting nickname handling for database $($WorkObject.DatabaseName)" -Level INFO


        $WorkObject = Get-ExistingNicknames -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        $replaceArray = @(
            "LEVERANDØR",
            "TRANSPORTØR",
            "SJÅFØRLOGG"
        )
        # 
        foreach ($nickname in $WorkObject.ListOfExistingNicknames) {
            if ([string]::IsNullOrEmpty($nickname.NAME)) { continue }
            foreach ($word in $replaceArray) {
                if ($nickname.NAME.Contains($word)) {
                    Write-LogMessage "Nickname '$($nickname.NAME)' contains word '$($word)'" -Level WARN
                }
            }
        }
        # Convert list of existing nicknames to structured object array
        if ($WorkObject.RegenerateAllNicknames -eq $true) {
            $nicknameArray = @()
        }
        else {
            $nicknameArray = $WorkObject.ListOfExistingNicknames | Where-Object {
                $null -ne $_ -and -not [string]::IsNullOrEmpty($_.NAME)
            }
        }
        
        # Add compare schema to existing nicknames
        foreach ($nickname in $nicknameArray) {
            if ([string]::IsNullOrEmpty($nickname.NAME)) {
                continue
            }
            if ($WorkObject.FederationType -eq "History") {
                $localSchema = "HST"
            }
            else {
                if ($nickname.SCHEMA.Trim().ToUpper() -eq "SYSCAT") {
                    $localSchema = $nickname.SCHEMA.Trim() + "X"
                }          
                else {
                    $localSchema = $nickname.SCHEMA.Trim()
                }
            }
            Add-Member -InputObject $nickname -NotePropertyName "LOCAL_SCHEMA" -NotePropertyValue $localSchema -Force
        }


        # Add compare schema to list of tables in linked database
        $listOfElementsInLinkedDatabase = $WorkObject.ListOfTablesInLinkedDatabase
        foreach ($element in $listOfElementsInLinkedDatabase) {
            if ([string]::IsNullOrEmpty($element.NAME)) {
                continue
            }
            if ($WorkObject.FederationType -eq "History") {
                $localSchema = "HST"
            }
            else {
                if ($element.SCHEMA.Trim().ToUpper() -eq "SYSCAT") {
                    $localSchema = $element.SCHEMA.Trim() + "X"
                }          
                else {
                    $localSchema = $element.SCHEMA.Trim()
                }
            }
            Add-Member -InputObject $element -NotePropertyName "LOCAL_SCHEMA" -NotePropertyValue $localSchema -Force
        }

        # Build string-keyed lookup structures (HashSet for O(1) contains, Dictionary for reverse lookup)
        Write-LogMessage "Building nickname comparison sets: $($nicknameArray.Count) existing nicknames, $($listOfElementsInLinkedDatabase.Count) linked DB elements" -Level INFO
        $nicknameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $nicknameLookup = @{}
        $skippedNicknames = 0
        foreach ($item in $nicknameArray) {
            if ([string]::IsNullOrEmpty($item.NAME) -or [string]::IsNullOrEmpty($item.LOCAL_SCHEMA)) {
                $skippedNicknames++
                continue
            }
            $key = "$($item.SERVERNAME.Trim()).$($item.LOCAL_SCHEMA.Trim()).$($item.NAME.Trim())"
            [void]$nicknameSet.Add($key)
            $nicknameLookup[$key] = $item
        }
        if ($skippedNicknames -gt 0) {
            Write-LogMessage "Skipped $($skippedNicknames) existing nicknames with null NAME or LOCAL_SCHEMA" -Level WARN
        }
        $linkedDbSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $linkedDbLookup = @{}
        $skippedLinked = 0
        foreach ($item in $listOfElementsInLinkedDatabase) {
            if ([string]::IsNullOrEmpty($item.NAME) -or [string]::IsNullOrEmpty($item.LOCAL_SCHEMA)) {
                $skippedLinked++
                continue
            }
            $key = "$($item.SERVERNAME.Trim()).$($item.LOCAL_SCHEMA.Trim()).$($item.NAME.Trim())"
            [void]$linkedDbSet.Add($key)
            $linkedDbLookup[$key] = $item
        }
        if ($skippedLinked -gt 0) {
            Write-LogMessage "Skipped $($skippedLinked) linked DB elements with null NAME or LOCAL_SCHEMA" -Level WARN
        }
        Write-LogMessage "Lookup sets built. Nickname set: $($nicknameSet.Count) keys, Linked DB set: $($linkedDbSet.Count) keys" -Level INFO

        $addNicknames = @()
        $dropNicknames = @()

        ########################################################################################################
        # Add nicknames that are present in the linked database but not in the target database
        ########################################################################################################
        $addCount = 0
        foreach ($key in $linkedDbSet) {
            if (-not $nicknameSet.Contains($key)) {
                $addNicknames += $linkedDbLookup[$key]
                $addCount++
            }
        }
        Write-LogMessage "Nicknames to ADD (in linked DB but not in target): $($addCount)" -Level INFO

        ########################################################################################################
        # Drop nicknames that are present in the target database but not in the linked database
        ########################################################################################################
        $dropCount = 0
        foreach ($key in $nicknameSet) {
            if (-not $linkedDbSet.Contains($key)) {
                $dropNicknames += $nicknameLookup[$key]
                $dropCount++
            }
        }
        Write-LogMessage "Nicknames to DROP (in target but not in linked DB): $($dropCount)" -Level INFO

        ########################################################################################################
        # Drop and re-add nicknames that are present in both but where ALTER_TIME >= CREATE_TIME
        ########################################################################################################
        $reAddCount = 0
        foreach ($key in $nicknameSet) {
            if ($linkedDbSet.Contains($key)) {
                $existingNickname = $nicknameLookup[$key]
                $linkedEntry = $linkedDbLookup[$key]
                if ($linkedEntry.ALTER_TIME -ge $existingNickname.CREATE_TIME) {
                    $dropNicknames += $existingNickname
                    $addNicknames += $linkedEntry
                    $reAddCount++
                }
            }
        }
        Write-LogMessage "Nicknames to RE-ADD (altered since created): $($reAddCount)" -Level INFO
        Write-LogMessage "Comparison complete. Total ADD: $($addNicknames.Count), Total DROP: $($dropNicknames.Count)" -Level INFO




        Add-Member -InputObject $WorkObject -NotePropertyName "NicknamesAdded" -NotePropertyValue $addNicknames.Count -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "NicknamesDropped" -NotePropertyValue $dropNicknames.Count -Force

        $db2Commands = @()

        # Drop nicknames
        if ($WorkObject.RegenerateAllNicknames -eq $true -or $dropNicknames.Count -gt 0 ) {
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2start"
            $db2Commands += "db2 activate database $($WorkObject.DatabaseName)"
            $db2Commands += "db2 terminate"
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2 connect to $($WorkObject.DatabaseName) user $($WorkObject.LinkedDbFedUser) using $($WorkObject.LinkedDbFedPassword)"
            if ($WorkObject.RegenerateAllNicknames -eq $true) {
                foreach ($nickname in $WorkObject.ListOfExistingNicknames) {
                    if (-not [string]::IsNullOrEmpty($nickname.LOCAL_SCHEMA)) {
                        # Bug fix: DROP NICKNAME requires two-part local name (schema.name), not three-part (server.schema.name)
                        # $localNickname = $(($nickname.SERVERNAME.Trim() + "." + $nickname.LOCAL_SCHEMA.Trim() + "." + $nickname.NAME.Trim()))
                        $localNickname = $($nickname.LOCAL_SCHEMA.Trim() + "." + $nickname.NAME.Trim())
                        $db2Commands += "db2 `"DROP NICKNAME $localNickname`""
                    }
                }
            }
            else {
                # Build list of commands to drop nicknames
                foreach ($nickname in $dropNicknames) {
                    # Bug fix: DROP NICKNAME requires two-part local name (schema.name), not three-part (server.schema.name)
                    # $localNickname = $(($nickname.SERVERNAME.Trim() + "." + $nickname.LOCAL_SCHEMA.Trim() + "." + $nickname.NAME.Trim()))
                    $localNickname = $($nickname.LOCAL_SCHEMA.Trim() + "." + $nickname.NAME.Trim())
                    $db2Commands += "db2 `"DROP NICKNAME $localNickname`""
                }
            }
            $db2Commands += "db2 commit work"
            $db2Commands += "db2 connect reset"
        }
        # Add nicknames
        if ($addNicknames.Count -gt 0 ) {
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2start"
            $db2Commands += "db2 activate database $($WorkObject.DatabaseName)"
            $db2Commands += "db2 terminate"

            # Ensure federation user has DBADM on the federated database (uses implicit OS auth = SYSADM authority)
            Write-LogMessage "Granting DBADM on $($WorkObject.DatabaseName) to $($WorkObject.LinkedDbFedUser)" -Level INFO
            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2 connect to $($WorkObject.DatabaseName)"
            $db2Commands += "db2 `"GRANT DBADM ON DATABASE TO USER $($WorkObject.LinkedDbFedUser)`""
            $db2Commands += "db2 commit work"
            $db2Commands += "db2 connect reset"

            $db2Commands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
            $db2Commands += "db2 connect to $($WorkObject.DatabaseName) user $($WorkObject.LinkedDbFedUser) using $($WorkObject.LinkedDbFedPassword)"


            foreach ($nickname in $addNicknames) {
                $localNickname = $($nickname.LOCAL_SCHEMA.Trim() + "." + $nickname.NAME.Trim())
                try {
                    $linkedServerLocation = $(($nickname.SERVERNAME.Trim() + "." + $nickname.SCHEMA.Trim() + "." + $nickname.NAME.Trim()))
                }
                catch {
                    Write-LogMessage ("Skipping element in addNicknames array. LogData: " +
                        "`nSERVER: $($nickname.SERVERNAME)" +
                        "`nSCHEMA: $($nickname.SCHEMA)" +
                        "`nLOCAL_SCHEMA: $($nickname.LOCAL_SCHEMA)" +
                        "`nNAME: $($nickname.NAME)" +
                        "`nCREATE_TIME: $($nickname.CREATE_TIME)" +
                        "`nLinkedDatabaseName: $($nickname.LinkedDatabaseName)"
                    ) -Level WARN -Exception $_
                }
                if (-not [string]::IsNullOrEmpty($nickname.LOCAL_SCHEMA)) {
                    $db2Commands += "db2 `"CREATE NICKNAME $localNickname FOR $linkedServerLocation`""
                }
            }

            $db2Commands += "db2 commit work"
            $db2Commands += "db2 connect reset"
        }
        # Execute commands
        $db2Commands += "db2 activate database $($WorkObject.DatabaseName)"
        $fileName = "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        if (-not $WhatIf) {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -Quiet:$Quiet -FileName $fileName
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
        }
        else {
            # Open script file in code
            $db2Commands | Set-Content -Path $fileName
            Start-Process -FilePath $(Get-CommandPathWithFallback -Name "code") -ArgumentList $fileName
            $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output "WhatIf mode: Opened script file in code editor"
        }


    }
    catch {
        Write-LogMessage "Error during starting nickname handling for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error during starting nickname handling for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}
function Restore-DuringDatabaseCreation {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Restoring during database creation for database $($WorkObject.DatabaseName)" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "RestoreStatus" -NotePropertyValue "NotStarted" -Force
        if ($WorkObject.DatabaseType -eq "PrimaryDb") {
            if ($WorkObject.GetBackupFromEnvironment -ne "") {
                Write-LogMessage "Restoring database from $($WorkObject.GetBackupFromEnvironment)" -Level INFO
            }
            else {
                Write-LogMessage "Restoring database from $($WorkObject.InstanceName) restore folder if any files exist" -Level INFO
            }
            Add-Member -InputObject $WorkObject -NotePropertyName "RestoreStatus" -NotePropertyValue "Initiated" -Force

            $restoreResultObject = Start-Db2Restore -PrimaryInstanceName $WorkObject.InstanceName -DatabaseType "PrimaryDb" -GetBackupFromEnvironment $($WorkObject.GetBackupFromEnvironment) -SkipDbConfiguration -SmsNumbers $WorkObject.SmsNumbers -OverrideWorkFolder $WorkObject.OverrideWorkFolder -UseNewConfigurations:($WorkObject.UseNewConfigurations -eq $true)
            $lastResult = if ($restoreResultObject -is [array]) { $restoreResultObject[-1] } else { $restoreResultObject }
            $successRestore = ($null -ne $lastResult -and ($lastResult.Result -eq "Success" -or $null -eq $lastResult.Result))

            if ($successRestore) {
                Add-Member -InputObject $WorkObject -NotePropertyName "RestoreStatus" -NotePropertyValue "Success" -Force
                Add-Member -InputObject $WorkObject -NotePropertyName "RestoreResultObject" -NotePropertyValue $restoreResultObject -Force

                $WorkObject = Get-CurrentDb2StateInfo -WorkObject $WorkObject
                if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

                Get-WorkObjectProperties -WorkObject $WorkObject
            }
            else {
                Add-Member -InputObject $WorkObject -NotePropertyName "RestoreStatus" -NotePropertyValue "ErrorDuringRestore" -Force
            }
        }
    }
    catch {
        Add-Member -InputObject $WorkObject -NotePropertyName "RestoreStatus" -NotePropertyValue "ErrorThrown" -Force
        Write-LogMessage "Error during restoring during database creation for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error during restoring during database creation for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}
 
<#
.SYNOPSIS
    Retrieves current Db2 state information including credentials, version, and database status.

.DESCRIPTION
    Gathers comprehensive state information about the current Db2 instance and database by:
    - Testing and setting post-restore credentials for the specified instance, database, and table
    - Determining the Db2 version (Standard Edition or Community Edition)
    - Optionally retrieving information about all databases across all instances
    
    This function enriches the WorkObject with critical state information needed for 
    database operations, configuration, and troubleshooting. It verifies instance existence,
    database existence, and table existence before attempting to set credentials.

.PARAMETER WorkObject
    PSCustomObject containing the database configuration including DatabaseName, InstanceName,
    and other properties. The object is enriched with state information and returned.

.PARAMETER GetAllDatabasesInfo
    Optional switch to retrieve information about all databases across all instances on the server.
    When enabled, provides a comprehensive overview of the entire Db2 environment.

.EXAMPLE
    $workObject = Get-CurrentDb2StateInfo -WorkObject $workObject
    # Retrieves state info for the database specified in WorkObject

.EXAMPLE
    $workObject = Get-CurrentDb2StateInfo -WorkObject $workObject -GetAllDatabasesInfo
    # Retrieves state info and comprehensive information about all databases

.NOTES
    The function updates the WorkObject with:
    - Db2Version: StandardEdition or CommunityEdition
    - DbUser/DbPassword: Post-restore credentials if database exists
    - ExistingInstanceList: List of all Db2 instances on the server
    - ExistingDatabaseList: Information about cataloged databases
    - InstanceExist/DatabaseExist/TableExist: Boolean flags for validation
#>
function Get-CurrentDb2StateInfo {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [switch]$GetAllDatabasesInfo = $false
    )
    try {
        # Set post restore credentials for current instance exists, database exists and table exists
        $WorkObject = Test-AndSetRestoredCredentials -WorkObject $WorkObject -GetAllDatabasesInfo:$GetAllDatabasesInfo
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Get Db2 version
        $workObject = Get-Db2Version -WorkObject $workObject
        if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
        $db2Version = $workObject.Db2Version
        Add-Member -InputObject $workObject -NotePropertyName "Db2Version" -NotePropertyValue $db2Version -Force

    }
    catch {
        Write-LogMessage "Error getting Db2 info on current computer" -Level ERROR -Exception $_
        throw "Error getting Db2 info on current computer: $($_.Exception.Message)"
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Orchestrates complete new database creation with all configurations.

.DESCRIPTION
    Master function for creating a new Db2 database from scratch:
    1. Gathers current Db2 state across all instances
    2. Displays all existing databases for validation
    3. Sets instance configuration
    4. Sets initial Db2 configuration
    5. Creates database
    6. Enables logging
    7. Optionally restores from backup
    8. Applies standard configurations
    9. Exports configuration report to HTML

.PARAMETER WorkObject
    PSCustomObject containing complete database specification.

.EXAMPLE
    $workObject = New-DatabaseAndConfigurations -WorkObject $workObject
    # Creates new database with full configuration

.NOTES
    Main entry point for database creation. Generates HTML report in WorkFolder.
#>
function New-DatabaseAndConfigurations {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    try {
        # Get Db2 info on current computer for all instances
        $WorkObject = Get-CurrentDb2StateInfo -WorkObject $WorkObject -GetAllDatabasesInfo
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Show all databases for all instances
        $WorkObject = Show-AllDatabases -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Set Db2 instance configuration for current instance
        $WorkObject = Set-InstanceNameConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Display database object to console for current instance
        $WorkObject = Get-WorkObjectProperties -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Set Db2 initial configuration for current instance
        $WorkObject = Set-Db2InitialConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Create database for current instance
        $WorkObject = Add-Db2Database -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add logging to database for current instance
        $WorkObject = Add-LoggingToDatabase -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Restore during database creation for current instance
        $WorkObject = Restore-DuringDatabaseCreation -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Add Db2 standard configuration for current instance
        $WorkObject = Set-StandardConfigurations -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # if ($WorkObject.DatabaseType -eq "PrimaryDb") {
        #     # Get primary database list of tables for current instance
        #     $WorkObject = Get-DatabaseListOfTables -WorkObject $WorkObject
        #     if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        # }

        # if ($WorkObject.DatabaseType -eq "FederatedDb") {
        #     # Add federation support for federated instance
        #     $WorkObject = Add-FederationSupport -WorkObject $WorkObject
        #     if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        #     # Start nickname handling for federated instance
        #     $WorkObject = Start-NicknameHandling -WorkObject $WorkObject
        #     if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        # }
     
    }
    catch {
        Write-LogMessage "Error during creating database and adding configurations: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Error during creating database and adding configurations: $($_.Exception.Message)"
    }
    # Export database object to file
    Write-LogMessage "Exporting database object to file" -Level INFO
    $outputFileName = "$($WorkObject.WorkFolder)\Db2-CreateInitialDatabase_$($WorkObject.DatabaseName).html"
    Export-WorkObjectToHtmlFile -WorkObject $WorkObject -FileName $outputFileName -Title "Db2 Create Initial Database for $($WorkObject.DatabaseName)" -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2/$($WorkObject.DatabaseName.ToUpper())"
    
    return $WorkObject
}

function Get-UserChoiceForInstanceName {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("PrimaryDb", "FederatedDb")]
        [string]$DatabaseType = "PrimaryDb",
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )
    $allowedResponses = $(Get-InstanceNameList -DatabaseType $DatabaseType)
    $promptMessage = "Choose $($DatabaseType) Instance Name: "
    $progressMessage = "Choose $($DatabaseType) instance name"
        
    if ($allowedResponses.Count -eq 1) {
        $InstanceName = $allowedResponses
        Write-LogMessage "$($DatabaseType) Instance Name defaulted to: $InstanceName" -Level INFO
        return $InstanceName
    }
    if ($allowedResponses.Count -eq 0) {
        Write-LogMessage "No $($DatabaseType) instance names found" -Level ERROR
        throw "No $($DatabaseType) instance names found"
    }
    $InstanceName = Get-UserConfirmationWithTimeout -PromptMessage $promptMessage -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage $progressMessage -ThrowOnTimeout:$ThrowOnTimeout
    Write-LogMessage "Chosen $($DatabaseType) Instance Name: $InstanceName" -Level INFO
 
    return $InstanceName
}

function Get-UserChoiceForDatabaseName {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$SkipAlias = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipFederated = $false,
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )
    $allowedResponses = $(Get-DatabaseNameList -SkipAlias:$SkipAlias -SkipFederated:$SkipFederated)
    $promptMessage = "Choose Database Name: "
    $progressMessage = "Choose database name"
        
    if ($allowedResponses.Count -eq 1) {
        $DatabaseName = $allowedResponses
        Write-LogMessage "Database Name defaulted to: $DatabaseName" -Level INFO
        return $DatabaseName
    }
    if ($allowedResponses.Count -eq 0) {
        Write-LogMessage "No database names found" -Level ERROR
        throw "No database names found"
    }
    $DatabaseName = Get-UserConfirmationWithTimeout -PromptMessage $promptMessage -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage $progressMessage -ThrowOnTimeout:$ThrowOnTimeout
    Write-LogMessage "Chosen Database Name: $DatabaseName" -Level INFO
 
    return $DatabaseName
}
function Get-UserChoiceForDatabaseType {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$AddBothDatabasesOption = $false,
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )

    # Handle automatic selection of database type
    $allowedResponses = @("PrimaryDb", "FederatedDb")
    if ($AddBothDatabasesOption) {
        $allowedResponses += "BothDatabases"
    }
    $DatabaseType = Get-UserConfirmationWithTimeout -PromptMessage "Choose Database Type: " -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage "Choose database type" -ThrowOnTimeout:$ThrowOnTimeout
    Write-LogMessage "Chosen Database Type: $DatabaseType" -Level INFO

    return $DatabaseType
}

function Get-UserChoiceForBackupEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $true)]
        [string]$DatabaseType,
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )

    # Handle automatic selection of backup environment
    $distinctEnvironments = @()
    if ($DatabaseType -eq "PrimaryDb" -or $DatabaseType -eq "BothDatabases") {
        $distinctEnvironments = Get-DistinctEnviromentForInstance -InstanceName $InstanceName -DatabaseType "PrimaryDb"
    }
    else {
        Write-LogMessage "Database type is $DatabaseType. Skipping backup environment selection." -Level WARN
        return ""

    }
    $addOptionElement = "Local $($InstanceName)Restore folder"

    $allowedResponses = @()
    $allowedResponses += $addOptionElement
    $allowedResponses += $distinctEnvironments
    $getBackupFromEnvironment = Get-UserConfirmationWithTimeout -PromptMessage "Choose Backup Environment: " -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage "Choose backup environment" -DefaultResponse $addOptionElement -ThrowOnTimeout:$ThrowOnTimeout
    if ($getBackupFromEnvironment -eq "Local $($InstanceName)Restore folder") {
        $getBackupFromEnvironment = ""
        Write-LogMessage "GetBackupFromEnvironment is set to blank. Will try to find restore files in $($InstanceName)Restore folder" -Level INFO
    }
    else {
        Write-LogMessage "GetBackupFromEnvironment is set to $getBackupFromEnvironment.`nWill try to find restore files in on backupfolder on corresponding server for $($getBackupFromEnvironment)" -Level INFO
    }


    return $getBackupFromEnvironment
}


function Test-ProductionUserChoiceConfirmation {

    # Check if environment is PRD or RAP and require confirmation
    if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
        $userConfirmationAnswer = Get-UserConfirmationWithTimeout -PromptMessage "Environment is PRD or RAP, so we need to confirm the action for $($env:COMPUTERNAME):" -TimeoutSeconds 60 -DefaultResponse "N"
        if ($userConfirmationAnswer.ToUpper() -ne "Y") {
            Write-LogMessage "User $($env:USERNAME) tried to perform action on $($env:COMPUTERNAME) but did not confirm. Skipping operation." -Level ERROR
            Exit 3
        }
        Write-LogMessage "User $($env:USERNAME) confirmed action on PRD or RAP environment $($env:COMPUTERNAME)" -Level INFO
    }

    return $true
}

function Get-UserChoiceForDropExistingDatabases {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )

    # Handle drop existing databases
    $dropExistingDatabasesString = Get-UserConfirmationWithTimeout -PromptMessage "Drop existing databases:" -TimeoutSeconds 30 -ProgressMessage "Drop existing databases" -ThrowOnTimeout:$ThrowOnTimeout
    Write-LogMessage "Chosen Drop Existing Databases: $dropExistingDatabasesString" -Level INFO
    $DropExistingDatabases = $dropExistingDatabasesString.ToUpper() -eq "Y"

    return $DropExistingDatabases
}


function Get-UserChoiceForFederationType {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )

    # Handle federation type
    $allowedResponses = @("Standard", "History")
    $federationType = Get-UserConfirmationWithTimeout -PromptMessage "Federation type:" -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage "Federation type" -ThrowOnTimeout:$ThrowOnTimeout
    Write-LogMessage "Chosen Federation Type: $federationType" -Level INFO

    return $federationType
}

function Get-UserChoiceForUseNewConfigurations {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false,
        [Parameter(Mandatory = $false)]
        [bool]$DefaultResponse = $false
    )

    $allowedResponses = @("Y", "N")
    $defaultVal = if ($DefaultResponse) { "Y" } else { "N" }
    $result = Get-UserConfirmationWithTimeout -PromptMessage "Use new configurations (automatic storage, AUTOSIZE bufferpools):" -TimeoutSeconds 30 -AllowedResponses $allowedResponses -DefaultResponse $defaultVal -ProgressMessage "Use new configurations" -ThrowOnTimeout:$ThrowOnTimeout
    $useNew = $result.ToUpper() -eq "Y"
    Write-LogMessage "Chosen UseNewConfigurations: $($useNew)" -Level INFO
    return $useNew
}

# Used from bat files
function Add-WorkObjectFromParameters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,  
        [Parameter(Mandatory = $false)]
        [string]$InstanceName,
        [Parameter(Mandatory = $true)]
        [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
        [string]$DatabaseType
    )
    
    # Get database configuration
    $workObjects = Get-DefaultWorkObjectsCommon -DatabaseName $DatabaseName -DatabaseType $DatabaseType

    $PrimaryWorkObject = $workObjects | Where-Object { $_.DatabaseType -eq "PrimaryDb" }
    $FederatedWorkObject = $workObjects | Where-Object { $_.DatabaseType -eq "FederatedDb" }
    Write-LogMessage "WorkObject:`n $($PrimaryWorkObject | ConvertTo-Json -Depth 100)" -Level INFO
    Write-LogMessage "WorkObject:`n $($FederatedWorkObject | ConvertTo-Json -Depth 100)" -Level INFO
    return $workObjects
    
}

<#
.SYNOPSIS
    Sets appropriate NTFS permissions on Db2 installation directories.

.DESCRIPTION
    Recursively applies permissions to C:\ProgramData\IBM and all subdirectories.
    Grants admin users full control and Everyone group read access to Db2 directories.

.PARAMETER WorkObject
    Optional PSCustomObject to track permission changes.

.EXAMPLE
    Add-Db2DirectoryPermission
    # Applies permissions to all IBM Db2 directories

.EXAMPLE
    $workObject = Add-Db2DirectoryPermission -WorkObject $workObject
    # Applies permissions and tracks changes in workObject.AddedDb2DirectoryPermission

.NOTES
    Critical for Db2 client and server functionality. Ensures proper file access.
#>
function Add-Db2DirectoryPermission {
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$WorkObject
    )
    # Main execution
    try {
        Write-LogMessage "Starting DB2 Directory Permission Fix Script" -Level INFO

        $arrayResult = @()    
        # Find all subfolders that are IBM DB2 directories
        $Db2BasePath = "C:\ProgramData\IBM"
        $db2Copies = Get-ChildItem -Path $Db2BasePath -Directory -ErrorAction SilentlyContinue -Recurse | Select-Object -ExpandProperty FullName
        $db2Copies += $Db2BasePath
    
        # Process each DB2 copy directory
        foreach ($copy in $db2Copies) {
            if (Test-Path $copy) {
                $additionalAdmins = Get-AdditionalAdmins
                Add-Folder -Path $copy -AdditionalAdmins $additionalAdmins -IsWorkstation:$false -EveryonePermission "Read"
                Write-LogMessage "Added permissions to $copy" -Level INFO
                if ($PSBoundParameters.ContainsKey('WorkObject')) {
                    $arrayResult += "$($copy): Added permissions"
                }
            }
            else {
                Write-LogMessage "Folder $copy does not exist" -Level WARN
                if ($PSBoundParameters.ContainsKey('WorkObject')) {
                    $arrayResult += "$($copy): Folder does not exist"
                }
            }
        }
        
    
        Write-LogMessage "DB2 Directory Permission Fix Script completed" -Level INFO
        if ($PSBoundParameters.ContainsKey('WorkObject')) {
            Add-Member -InputObject $WorkObject -NotePropertyName "AddedDb2DirectoryPermission" -NotePropertyValue $arrayResult -Force
            return $WorkObject
        }
    }
    catch {
        Write-LogMessage "Fatal error in script" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Removes obsolete user mappings for retired server links.

.DESCRIPTION
    Queries SYSCAT.USEROPTIONS for user mappings to obsolete servers (VISMABUS, BASISHST).
    Generates and executes DROP USER MAPPING commands for each obsolete mapping.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName.

.EXAMPLE
    $workObject = Remove-ObsoleteFederationUserMappings -WorkObject $workObject
    # Removes user mappings for VISMABUS and BASISHST servers

.NOTES
    Used during federation cleanup to remove references to old/retired server links.
#>
function Remove-ObsoleteFederationUserMappings {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Dropping obsolete user mappings for database $($WorkObject.DatabaseName)" -Level INFO
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 `"select distinct 'db2 DROP USER MAPPING FOR ' || AUTHID || ' SERVER ' || SERVERNAME  as script from syscat.useroptions where SERVERNAME in ('VISMABUS','BASISHST')`""
        $db2Commands += "db2 connect reset"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_List_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)_List" -Script $($db2Commands -join "`n") -Output $output
      

        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += Get-SelectResult -SelectOutput $output -ReturnArray
        $db2Commands += "db2 `"select distinct 'db2 DROP USER MAPPING FOR ' || AUTHID || ' SERVER ' || SERVERNAME  as script from syscat.useroptions where SERVERNAME in ('VISMABUS','BASISHST')`""
        $db2Commands += "db2 connect reset"
        $batFileName = "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_Execute_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFileName -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)_Execute" -Script $($db2Commands -join "`n") -Output $output
    }

    catch {
        Write-LogMessage "Error dropping obsolete user mappings for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error dropping obsolete user mappings for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}







function Add-FederationSupportToDatabases {
   
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstanceName = "DB2",
        [Parameter(Mandatory = $false)]
        [string]$TargetDatabaseName = "",
        [Parameter(Mandatory = $false)]
        [string]$LinkedDatabaseName = "",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Standard", "History")]
        [string]$FederationType = "Standard",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Setup", "Refresh", "SetupAndRefresh")]
        [string]$HandleType = "SetupAndRefresh", [Parameter(Mandatory = $false)]
        [string[]]$SmsNumbers = @(),
        [Parameter(Mandatory = $false)]
        [switch]$RegenerateAllNicknames = $false,
        [Parameter(Mandatory = $false)]
        [switch]$WhatIf = $false
    )

    # Standard: TargetDatabaseName eg. (XINLTST) linker til alle tabeller i LinkedDatabaseName (INLTST)
    # History: TargetDatabaseName eg. (INLTST) linker til alle tabeller i LinkedDatabaseName (INLHST)

    ########################################################################################################
    # Main
    ########################################################################################################
    try {
        Write-LogMessage "Adding federation support to databases" -Level INFO
    
        # Check if script is running on a db2 server and as administrator
        Test-Db2ServerAndAdmin

        Write-LogMessage "Federation type: $FederationType" -Level INFO


        ########################################################################################################
        # Get objects for target and linked database
        ########################################################################################################
        Write-LogMessage ("Database name: $TargetDatabaseName`n`nLinked database name: $LinkedDatabaseName") -Level INFO

        # Get Object for Linked Database - Source database to link to from target database and get list of all tables
        # Eg. INLTST
        if (-not [string]::IsNullOrEmpty($InstanceName) -and [string]::IsNullOrEmpty($LinkedDatabaseName) -and [string]::IsNullOrEmpty($TargetDatabaseName)) {
            if ($FederationType -eq "History" ) {
                if ($InstanceName -eq "DB2" -and $(Get-ApplicationFromServerName) -eq "FKM" -and $(Get-EnvironmentFromServerName) -eq "PRD") {
                    $TargetDatabaseName = "FKMPRD"                
                    $LinkedDatabaseName = "FKMHST"
                }
                else {
                    Write-LogMessage "Federation type is $FederationType. Only supported for Application FKM in Environmente PRD." -Level WARN
                    return $false
                }
            }
            elseif ($FederationType -eq "Standard") {
                $TargetDatabaseName = $(Get-FederatedDbNameFromInstanceName -InstanceName $InstanceName)
                if ([string]::IsNullOrEmpty($TargetDatabaseName)) {
                    Write-LogMessage "Federated database not in config (UseNewConfigurations). Skipping Standard federation." -Level WARN
                    return $false
                }
                $LinkedDatabaseName = $(Get-PrimaryDbNameFromInstanceName -InstanceName $InstanceName)
            }
            else {
                Write-LogMessage "Invalid federation type: $FederationType. Aborting..." -Level WARN
                return $false
            }
        }
    
        ########################################################################################################
        # Get list of all tables in linked database
        ########################################################################################################
        $linkedWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $LinkedDatabaseName -SkipRecreateDb2Folders -SkipDb2StateInfo
        if ($linkedWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $linkedWorkObject = $linkedWorkObject[-1] }  

        if ($FederationType -eq "History") {
            $linkedWorkObject = Get-DatabaseListOfTables -WorkObject $linkedWorkObject -SchemaList @("DBM")
            if ($linkedWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $linkedWorkObject = $linkedWorkObject[-1] }
            # $linkedWorkObject = Get-DatabaseListOfFunctions -WorkObject $linkedWorkObject -SchemaList @("DBM")
            # if ($linkedWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $linkedWorkObject = $linkedWorkObject[-1] }
        }
        else {
            $linkedWorkObject = Get-DatabaseListOfTables -WorkObject $linkedWorkObject
            if ($linkedWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $linkedWorkObject = $linkedWorkObject[-1] }
            # $linkedWorkObject = Get-DatabaseListOfFunctions -WorkObject $linkedWorkObject
            # if ($linkedWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $linkedWorkObject = $linkedWorkObject[-1] }
        }

        ########################################################################################################
        # Get Object for Target Database and refresh nickname handling
        ########################################################################################################
        $targetWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $TargetDatabaseName -SkipRecreateDb2Folders -SkipDb2StateInfo
        if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }  

        Add-Member -InputObject $targetWorkObject -NotePropertyName "FederationType" -NotePropertyValue $FederationType -Force

        # $targetWorkObject = Add-ServerCatalogingForLocalDatabase -WorkObject $targetWorkObject
        # if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }

        # Add list of tables in linked database to target database
        if ($HandleType -eq "SetupAndRefresh" -or $HandleType -eq "Refresh") {
            Write-LogMessage "Number of tables in linked database: $($linkedWorkObject.ListOfTables.Count)" -Level INFO
            Add-Member -InputObject $targetWorkObject -NotePropertyName "ListOfTablesInLinkedDatabase" -NotePropertyValue $linkedWorkObject.ListOfTables -Force
        }
        # if ($HandleType -eq "SetupAndRefresh" -or $HandleType -eq "Refresh") {
        #     Write-LogMessage "Number of functions in linked database: $($linkedWorkObject.ListOfFunctions.Count)" -Level INFO
        #     Add-Member -InputObject $targetWorkObject -NotePropertyName "ListOfFunctionsInLinkedDatabase" -NotePropertyValue $linkedWorkObject.ListOfFunctions -Force
        # }
    
        # Add federation-related properties to the targetWorkObject using Add-Member
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedPrimaryDatabaseName" -NotePropertyValue $linkedWorkObject.DatabaseName -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedPrimaryInstanceName" -NotePropertyValue $linkedWorkObject.InstanceName -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDatabaseName" -NotePropertyValue $linkedWorkObject.DatabaseName -Force
        #Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDatabaseName" -NotePropertyValue $linkedWorkObject.RemoteDatabaseName -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDatabasePort" -NotePropertyValue $linkedWorkObject.RemotePort -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedServerName" -NotePropertyValue $linkedWorkObject.ServerName -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDbFedUser" -NotePropertyValue "db2nt" -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDbFedPassword" -NotePropertyValue "ntdb2" -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "RegenerateAllNicknames" -NotePropertyValue $RegenerateAllNicknames -Force
        Add-Member -InputObject $targetWorkObject -NotePropertyName "ServerLinkName" -NotePropertyValue $($targetWorkObject.LinkedPrimaryInstanceName.Trim() + "LNK") -Force
 
        if ($null -eq $targetWorkObject.LinkedDbFedUser) {
            $targetWorkObject.LinkedDbFedUser = "db2nt"
            $targetWorkObject.LinkedDbFedPassword = "ntdb2"
        }

        # Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDbFedUser" -NotePropertyValue $linkedWorkObject.DbUser -Force
        # Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedDbFedPassword" -NotePropertyValue $linkedWorkObject.DbPassword -Force

        # Add federation support for linked database   
        if ($HandleType -eq "SetupAndRefresh" -or $HandleType -eq "Setup") {    
            $targetWorkObject = Add-FederationSupport -WorkObject $targetWorkObject
            if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }  
        }

        if ($HandleType -eq "SetupAndRefresh" -or $HandleType -eq "Refresh") {
            $targetWorkObject = Start-NicknameHandling -WorkObject $targetWorkObject -WhatIf:$WhatIf
            if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }
        }

        if (($HandleType -eq "SetupAndRefresh" -or $HandleType -eq "Refresh") -and $FederationType -eq "Standard") {
            $targetWorkObject = Sync-FederatedRoutines -WorkObject $targetWorkObject
            if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }
        }

        # $targetWorkObject = Remove-ObsoleteFederationUserMappings -WorkObject $targetWorkObject
        # if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }


        # Export database object to file
        Write-LogMessage "Exporting database object to file" -Level INFO
        $outputFileName = "$($targetWorkObject.WorkFolder)\Db2-FederationHandler_$($targetWorkObject.DatabaseName).html"
        Export-WorkObjectToHtmlFile -WorkObject $targetWorkObject -Title "Db2 Federation Generation and Nickname Handling" -FileName $outputFileName -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2\$($targetWorkObject.DatabaseName.ToUpper())"

        # Send SMS message to notify success
        $added = $targetWorkObject.NicknamesAdded
        $dropped = $targetWorkObject.NicknamesDropped
        $routinesAdded = if ($targetWorkObject.RoutinesAdded) { $targetWorkObject.RoutinesAdded } else { 0 }
        $routinesDropped = if ($targetWorkObject.RoutinesDropped) { $targetWorkObject.RoutinesDropped } else { 0 }
        $message = "Federation $($targetWorkObject.DatabaseName)->$($targetWorkObject.LinkedDatabaseName) on $($env:COMPUTERNAME): nicknames $($added) added/$($dropped) dropped, routines $($routinesAdded) added/$($routinesDropped) dropped"
        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $message
        }
        Write-LogMessage "Adding federation support to databases completed" -Level INFO
        return $true
    }
    catch {
        # Send SMS message about error
        $message = "Error during refreshing federation nicknames in Db2 database $($targetWorkObject.DatabaseName) towards database $($targetWorkObject.LinkedDatabaseName) on $($env:COMPUTERNAME): $($_.Exception.Message)"
        Write-LogMessage $message -Level ERROR
        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $message
        }
        Write-LogMessage "Error during adding federation support to databases" -Level ERROR -Exception $_
        return $false
    }
    finally {
        Reset-OverrideAppDataFolder
    }
}

########################################################################################################
# Memory Configuration Analysis Functions - Added for Db2-AnalyzeMemoryConfig
########################################################################################################

function Get-SystemInfoAsObject {
    <#
    .SYNOPSIS
    Converts systeminfo command output to a structured PSCustomObject
    
    .DESCRIPTION
    Parses the output of the systeminfo command and returns relevant system information as a PSCustomObject.
    Useful when WMI or CIM cmdlets are not available or preferred.
    
    .PARAMETER SystemInfoOutput
    The raw output from systeminfo command. If not provided, will execute systeminfo.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$SystemInfoOutput
    )
    
    try {
        Write-LogMessage "Parsing system information..." -Level INFO
        
        # Execute systeminfo if output not provided
        if ([string]::IsNullOrEmpty($SystemInfoOutput)) {
            $SystemInfoOutput = systeminfo | Out-String
        }
        $SystemInfoOutput | Out-File -FilePath $(Join-Path $PSScriptRoot "SystemInfoOutput.txt")
        Write-LogMessage "System information output saved to $(Join-Path $PSScriptRoot "SystemInfoOutput.txt")" -Level INFO
        
        # Initialize result object
        $systemInfo = [PSCustomObject]@{
            ComputerName              = $env:COMPUTERNAME
            OSName                    = $null
            OSVersion                 = $null
            OSManufacturer            = $null
            OSConfiguration           = $null
            OSBuildType               = $null
            SystemManufacturer        = $null
            SystemModel               = $null
            SystemType                = $null
            Processor                 = $null
            BIOSVersion               = $null
            TotalPhysicalMemoryMB     = 0
            AvailablePhysicalMemoryMB = 0
            VirtualMemoryMaxSizeMB    = 0
            VirtualMemoryAvailableMB  = 0
            VirtualMemoryInUseMB      = 0
            PageFileLocation          = $null
            Domain                    = $null
            LogonServer               = $null
            Hotfixes                  = @()
            NetworkAdapters           = @()
        }
        
        # Parse memory information (language-independent - looks for numbers and "MB")
        if ($SystemInfoOutput -match "Total Physical Memory:\s+([0-9,]+)\s+MB") {
            $systemInfo.TotalPhysicalMemoryMB = [int]($matches[1] -replace ',', '')
        }
        if ($SystemInfoOutput -match "Available Physical Memory:\s+([0-9,]+)\s+MB") {
            $systemInfo.AvailablePhysicalMemoryMB = [int]($matches[1] -replace ',', '')
        }
        if ($SystemInfoOutput -match "Virtual Memory: Max Size:\s+([0-9,]+)\s+MB") {
            $systemInfo.VirtualMemoryMaxSizeMB = [int]($matches[1] -replace ',', '')
        }
        if ($SystemInfoOutput -match "Virtual Memory: Available:\s+([0-9,]+)\s+MB") {
            $systemInfo.VirtualMemoryAvailableMB = [int]($matches[1] -replace ',', '')
        }
        if ($SystemInfoOutput -match "Virtual Memory: In Use:\s+([0-9,]+)\s+MB") {
            $systemInfo.VirtualMemoryInUseMB = [int]($matches[1] -replace ',', '')
        }
        
        # Parse OS information
        if ($SystemInfoOutput -match "OS Name:\s+(.+)") {
            $systemInfo.OSName = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "OS Version:\s+(.+)") {
            $systemInfo.OSVersion = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "OS Manufacturer:\s+(.+)") {
            $systemInfo.OSManufacturer = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "OS Configuration:\s+(.+)") {
            $systemInfo.OSConfiguration = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "OS Build Type:\s+(.+)") {
            $systemInfo.OSBuildType = $matches[1].Trim()
        }
        
        # Parse system information
        if ($SystemInfoOutput -match "System Manufacturer:\s+(.+)") {
            $systemInfo.SystemManufacturer = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "System Model:\s+(.+)") {
            $systemInfo.SystemModel = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "System Type:\s+(.+)") {
            $systemInfo.SystemType = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "Processor\(s\):\s+\d+\s+Processor\(s\) Installed\.\s+\[01\]:\s+(.+)") {
            $systemInfo.Processor = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "BIOS Version:\s+(.+)") {
            $systemInfo.BIOSVersion = $matches[1].Trim()
        }
        
        # Parse domain information
        if ($SystemInfoOutput -match "Domain:\s+(.+)") {
            $systemInfo.Domain = $matches[1].Trim()
        }
        if ($SystemInfoOutput -match "Logon Server:\s+(.+)") {
            $systemInfo.LogonServer = $matches[1].Trim()
        }
        
        # Parse page file location
        if ($SystemInfoOutput -match "Page File Location\(s\):\s+(.+)") {
            $systemInfo.PageFileLocation = $matches[1].Trim()
        }
        
        # Parse hotfixes - only capture KB numbers from the Hotfix section
        $hotfixMatches = [regex]::Matches($SystemInfoOutput, "(?<=Hotfix\(s\):.*?)\[(\d+)\]:\s+(KB\d+)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $systemInfo.Hotfixes = @($hotfixMatches | ForEach-Object { $_.Groups[2].Value })
        
        # Parse network adapters - only capture adapter names from the Network Card section
        # Network adapters appear with moderate indentation, while IP addresses have more indentation
        # Example:
        #                                  [01]: Intel(R) Wi-Fi 6E AX211 160MHz
        #                                        Connection Name: Wi-Fi
        #                                        IP address(es)
        #                                        [01]: 192.168.50.147  <-- More indented
        
        $adapters = @()
        
        # Find all lines that match the network adapter pattern
        # - Must have [number]: followed by text
        # - Must have moderate indentation (around 30-35 spaces)
        # - Must NOT be an IP address
        $lines = $SystemInfoOutput -split '\r?\n'
        $inNetworkSection = $false
        
        foreach ($line in $lines) {
            # Check if we've entered the Network Card section
            if ($line -match 'Network Card\(s\):') {
                $inNetworkSection = $true
                continue
            }
            
            # Stop if we hit an empty line or next major section
            if ($inNetworkSection -and ($line -match '^\s*$' -or $line -match '^[A-Z][\w\s]+:\s+' -and $line -notmatch '^\s{20,}')) {
                break
            }
            
            # Only process lines in the network section
            if ($inNetworkSection) {
                # Match adapter lines: moderate indentation + [number]: + text
                # Adapter lines have ~33 spaces, IP lines have ~39+ spaces
                if ($line -match '^\s{30,38}\[(\d+)\]:\s+(.+)$') {
                    $adapterName = $matches[2].Trim()
                    
                    # Exclude IP addresses (IPv4 and IPv6)
                    if ($adapterName -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and
                        $adapterName -notmatch '^fe80::[0-9a-fA-F:]+$' -and
                        $adapterName -notmatch '^[0-9a-fA-F:]+$') {
                        $adapters += $adapterName
                    }
                }
            }
        }
        
        $systemInfo.NetworkAdapters = $adapters
        
        Write-LogMessage "System information parsed successfully" -Level INFO
        return $systemInfo
    }
    catch {
        Write-LogMessage "Error parsing system information: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
}

function Get-Db2BufferPoolsInfo {
    <#
    .SYNOPSIS
    Retrieves buffer pool information from a Db2 database
    
    .DESCRIPTION
    Queries SYSCAT.BUFFERPOOLS to get buffer pool configuration including sizes and page sizes
    
    .PARAMETER WorkObject
    WorkObject containing the database name and instance name
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Retrieving buffer pool information for database $($WorkObject.DatabaseName)" -Level INFO
        $results = Get-QueryResult -WorkObject $WorkObject -Query "SELECT BPNAME, NPAGES, PAGESIZE, BUFFERPOOLID FROM SYSCAT.BUFFERPOOLS ORDER BY BUFFERPOOLID"
        Add-Member -InputObject $WorkObject -NotePropertyName "BufferPools" -NotePropertyValue $results -Force




        # $db2Commands = @()
        # $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
        # $db2Commands += Get-ConnectCommand -WorkObject $WorkObject
        # $db2Commands += "db2 `"SELECT BPNAME, NPAGES, PAGESIZE, BUFFERPOOLID FROM SYSCAT.BUFFERPOOLS ORDER BY BUFFERPOOLID`""
        # $db2Commands += "db2 terminate"
        # $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        # $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff')" -Script $($db2Commands -join "`n") -Output $output
        
        # # Parse output to extract buffer pool information
        # $output = Get-SelectResultAsObjectArray -SelectOutput $output
        # $bufferPools = @()
        # $lines = $output -split "`n"
        
        # foreach ($line in $lines) {
        #     if ($line -match "^[A-Z0-9_]+\s+\d+\s+\d+\s+\d+") {
        #         $parts = $line -split '\s+' | Where-Object { $_ -ne "" }
        #         if ($parts.Count -ge 4) {
        #             $bufferPools += [PSCustomObject]@{
        #                 BpName       = $parts[0]
        #                 NPages       = [int]$parts[1]
        #                 PageSize     = [int]$parts[2]
        #                 BufferPoolId = [int]$parts[3]
        #                 SizeMB       = [math]::Round(([int]$parts[1] * [int]$parts[2]) / 1MB, 2)
        #             }
        #         }
        #     }
        # }
        
        # Write-LogMessage "Found $($bufferPools.Count) buffer pools" -Level INFO
    }
    catch {
        Write-LogMessage "Error retrieving buffer pool information: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

function Get-Db2MemoryConfiguration {
    <#
    .SYNOPSIS
    Retrieves memory configuration from Db2 instance and database
    
    .DESCRIPTION
    Gets INSTANCE_MEMORY, DATABASE_MEMORY, SELF_TUNING_MEM and other memory-related parameters
    
    .PARAMETER DatabaseName
    Name of the database to query
    
    .PARAMETER InstanceName
    Name of the Db2 instance
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    
    try {
        Write-LogMessage "Retrieving memory configuration for database $($WorkObject.DatabaseName)" -Level INFO
        

        # Get database configuration
        $WorkObject = Get-DatabaseConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $instanceOutput = $WorkObject.ScriptAndOutput.ScriptAndOutput | Where-Object { $_.Name -eq "Get-DatabaseConfiguration" } | Select-Object -ExpandProperty Output

        # Get Db2 server configuration
        $WorkObject = Get-Db2InstanceConfiguration -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $dbOutput = $WorkObject.ScriptAndOutput.ScriptAndOutput | Where-Object { $_.Name -eq "Get-Db2InstanceConfiguration" } | Select-Object -ExpandProperty Output
        

        # Parse INSTANCE_MEMORY - look for (INSTANCE_MEMORY) followed by = sign (language-independent)
        $instanceMemory = "UNKNOWN"
        $instanceMemoryValue = 0
        if ($instanceOutput -match "\(INSTANCE_MEMORY\)\s*=\s*(.+)") {
            $instanceMemory = $matches[1].Trim()
            if ($instanceMemory -match "AUTOMATIC\((\d+)\)") {
                $instanceMemoryValue = [int]$matches[1]
            }
            elseif ($instanceMemory -match "^(\d+)$") {
                $instanceMemoryValue = [int]$matches[1]
            }
        }
        
        # Parse DATABASE_MEMORY - look for (DATABASE_MEMORY) followed by = sign (language-independent)
        $databaseMemory = "UNKNOWN"
        $databaseMemoryValue = 0
        if ($dbOutput -match "\(DATABASE_MEMORY\)\s*=\s*(.+)") {
            $databaseMemory = $matches[1].Trim()
            if ($databaseMemory -match "AUTOMATIC\((\d+)\)") {
                $databaseMemoryValue = [int]$matches[1]
            }
            elseif ($databaseMemory -match "^(\d+)$") {
                $databaseMemoryValue = [int]$matches[1]
            }
        }
        
        # Parse SELF_TUNING_MEM - look for (SELF_TUNING_MEM) followed by = sign (language-independent)
        $selfTuningMem = "UNKNOWN"
        if ($dbOutput -match "\(SELF_TUNING_MEM\)\s*=\s*(.+)") {
            $selfTuningMem = $matches[1].Trim()
        }
        
        $memoryConfig = [PSCustomObject]@{
            InstanceMemory      = $instanceMemory
            InstanceMemoryPages = $instanceMemoryValue
            InstanceMemoryMB    = [math]::Round(($instanceMemoryValue * 4) / 1024, 2)
            DatabaseMemory      = $databaseMemory
            DatabaseMemoryPages = $databaseMemoryValue
            DatabaseMemoryMB    = [math]::Round(($databaseMemoryValue * 4) / 1024, 2)
            SelfTuningMem       = $selfTuningMem
            InstanceRawOutput   = $instanceOutput
            DatabaseRawOutput   = $dbOutput
        }
        
        Write-LogMessage "Memory configuration retrieved: INSTANCE_MEMORY=$($memoryConfig.InstanceMemoryMB)MB, DATABASE_MEMORY=$($memoryConfig.DatabaseMemoryMB)MB, SELF_TUNING_MEM=$selfTuningMem" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "MemoryConfiguration" -NotePropertyValue $memoryConfig -Force
    }
    catch {
        Write-LogMessage "Error retrieving memory configuration: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

function Get-Db2TablespaceInfo {
    <#
    .SYNOPSIS
    Retrieves tablespace information and their buffer pool assignments
    
    .DESCRIPTION
    Queries SYSCAT.TABLESPACES to get tablespace details and which buffer pools they use
    
    .PARAMETER DatabaseName
    Name of the database to query
    
    .PARAMETER InstanceName
    Name of the Db2 instance
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    
    try {
        Write-LogMessage "Retrieving tablespace information for database $DatabaseName" -Level INFO
        
        $db2Commands = @()
        $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
        $db2Commands += Get-ConnectCommand -WorkObject $WorkObject
        $db2Commands += "db2 `"SELECT SUBSTR(TBSPACE,1,30) AS TBSPACE, BUFFERPOOLID, PAGESIZE, DATATYPE FROM SYSCAT.TABLESPACES ORDER BY BUFFERPOOLID, PAGESIZE`""
        $db2Commands += "db2 terminate"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff')" -Script $($db2Commands -join "`n") -Output $output
        
        # Parse output to extract tablespace information
        $output = Get-SelectResult -SelectOutput $output
        $tablespaces = @()
        $lines = $output -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match "^[A-Z0-9_]+\s+\d+\s+\d+\s+[A-Z]") {
                $parts = $line -split '\s+' | Where-Object { $_ -ne "" }
                if ($parts.Count -ge 4) {
                    $tablespaces += [PSCustomObject]@{
                        TablespaceName = $parts[0]
                        BufferPoolId   = [int]$parts[1]
                        PageSize       = [int]$parts[2]
                        DataType       = $parts[3]
                    }
                }
            }
        }
        
        Write-LogMessage "Found $($tablespaces.Count) tablespaces" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "Tablespaces" -NotePropertyValue $tablespaces -Force
    }
    catch {
        Write-LogMessage "Error retrieving tablespace information: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

function Test-Db2MemoryConfiguration {
    <#
    .SYNOPSIS
    Analyzes Db2 memory configuration and identifies issues
    
    .DESCRIPTION
    Analyzes buffer pools, memory settings, and tablespace usage to identify configuration problems
    
    .PARAMETER WorkObject
    WorkObject containing the buffer pool, memory configuration, and tablespace information
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    
    try {
        Write-LogMessage "Analyzing Db2 memory configuration" -Level INFO
        
        $BufferPools = $WorkObject.BufferPools
        $MemoryConfig = $WorkObject.MemoryConfiguration
        $Tablespaces = $WorkObject.Tablespaces
        $SystemMemoryMB = $WorkObject.SystemTotalMemoryMB

        $issues = @()
        $warnings = @()
        
        # Calculate total buffer pool allocation
        $totalBufferPoolMB = ($BufferPools | Measure-Object -Property SizeMB -Sum).Sum
        
        # Issue 1: Check if total buffer pools exceed DATABASE_MEMORY
        if ($MemoryConfig.DatabaseMemoryMB -gt 0) {
            $bufferPoolPercentage = [math]::Round(($totalBufferPoolMB / $MemoryConfig.DatabaseMemoryMB) * 100, 2)
            
            if ($totalBufferPoolMB -gt ($MemoryConfig.DatabaseMemoryMB * 0.8)) {
                $issues += [PSCustomObject]@{
                    Severity       = "CRITICAL"
                    Category       = "BufferPoolSize"
                    Description    = "Total buffer pools ($([math]::Round($totalBufferPoolMB, 2)) MB) exceed 80% of DATABASE_MEMORY ($($MemoryConfig.DatabaseMemoryMB) MB)"
                    Impact         = "Buffer pools may fail to start (SQL1478W error)"
                    Recommendation = "Reduce buffer pool sizes to fit within DATABASE_MEMORY"
                }
            }
            elseif ($totalBufferPoolMB -gt ($MemoryConfig.DatabaseMemoryMB * 0.5)) {
                $warnings += [PSCustomObject]@{
                    Severity       = "WARNING"
                    Category       = "BufferPoolSize"
                    Description    = "Total buffer pools ($([math]::Round($totalBufferPoolMB, 2)) MB) use $bufferPoolPercentage% of DATABASE_MEMORY ($($MemoryConfig.DatabaseMemoryMB) MB)"
                    Impact         = "Limited memory available for other database operations"
                    Recommendation = "Consider if buffer pools can be optimized"
                }
            }
        }
        
        # Issue 2: Check if DATABASE_MEMORY >= INSTANCE_MEMORY
        if ($MemoryConfig.DatabaseMemoryMB -gt 0 -and $MemoryConfig.InstanceMemoryMB -gt 0) {
            if ($MemoryConfig.DatabaseMemoryMB -ge $MemoryConfig.InstanceMemoryMB) {
                $issues += [PSCustomObject]@{
                    Severity       = "CRITICAL"
                    Category       = "MemoryConfiguration"
                    Description    = "DATABASE_MEMORY ($($MemoryConfig.DatabaseMemoryMB) MB) equals or exceeds INSTANCE_MEMORY ($($MemoryConfig.InstanceMemoryMB) MB)"
                    Impact         = "Database activation will fail (SQL1643C error)"
                    Recommendation = "DATABASE_MEMORY should be 50-70% of INSTANCE_MEMORY"
                }
            }
            elseif ($MemoryConfig.DatabaseMemoryMB -gt ($MemoryConfig.InstanceMemoryMB * 0.8)) {
                $warnings += [PSCustomObject]@{
                    Severity       = "WARNING"
                    Category       = "MemoryConfiguration"
                    Description    = "DATABASE_MEMORY ($($MemoryConfig.DatabaseMemoryMB) MB) uses $(([math]::Round(($MemoryConfig.DatabaseMemoryMB / $MemoryConfig.InstanceMemoryMB) * 100, 2)))% of INSTANCE_MEMORY"
                    Impact         = "Limited memory for instance overhead (FCM, agents, etc.)"
                    Recommendation = "Consider reducing DATABASE_MEMORY to 50-70% of INSTANCE_MEMORY"
                }
            }
        }
        
        # Issue 3: Check for unused or underutilized buffer pools
        $bufferPoolUsage = $Tablespaces | Group-Object -Property BufferPoolId | Select-Object @{N = 'BufferPoolId'; E = { $_.Name } }, @{N = 'TablespaceCount'; E = { $_.Count } }
        
        foreach ($bp in $BufferPools) {
            $usage = $bufferPoolUsage | Where-Object { $_.BufferPoolId -eq $bp.BufferPoolId.ToString() }
            $tablespaceCount = if ($usage) { $usage.TablespaceCount } else { 0 }
            
            if ($tablespaceCount -eq 0) {
                $issues += [PSCustomObject]@{
                    Severity       = "WARNING"
                    Category       = "UnusedBufferPool"
                    Description    = "Buffer pool '$($bp.BpName)' (ID: $($bp.BufferPoolId)) allocates $($bp.SizeMB) MB but serves ZERO tablespaces"
                    Impact         = "Wasted memory allocation"
                    Recommendation = "Consider dropping this buffer pool or reducing to minimal size (1000 pages)"
                }
            }
            elseif ($tablespaceCount -eq 1 -and $bp.SizeMB -gt 1000) {
                $warnings += [PSCustomObject]@{
                    Severity       = "INFO"
                    Category       = "LargeBufferPoolForSingleTablespace"
                    Description    = "Buffer pool '$($bp.BpName)' allocates $($bp.SizeMB) MB but serves only 1 tablespace"
                    Impact         = "Potentially oversized allocation"
                    Recommendation = "Verify if this tablespace requires such a large buffer pool"
                }
            }
        }
        
        # Issue 4: Check SELF_TUNING_MEM status
        if ($MemoryConfig.SelfTuningMem -match "OFF") {
            $warnings += [PSCustomObject]@{
                Severity       = "WARNING"
                Category       = "SelfTuningDisabled"
                Description    = "Self-tuning memory (SELF_TUNING_MEM) is disabled"
                Impact         = "Db2 cannot dynamically adjust memory allocation"
                Recommendation = "Enable SELF_TUNING_MEM for automatic memory management"
            }
        }
        
        # Issue 5: Check if buffer pools are too large relative to system memory
        if ($SystemMemoryMB -gt 0) {
            if ($totalBufferPoolMB -gt ($SystemMemoryMB * 0.5)) {
                $issues += [PSCustomObject]@{
                    Severity       = "CRITICAL"
                    Category       = "SystemMemory"
                    Description    = "Total buffer pools ($([math]::Round($totalBufferPoolMB, 2)) MB) exceed 50% of system memory ($SystemMemoryMB MB)"
                    Impact         = "May cause system-wide memory pressure"
                    Recommendation = "Reduce buffer pool sizes to reasonable levels"
                }
            }
        }
        
        # Combine all findings
        $analysis = [PSCustomObject]@{
            TotalBufferPoolMB         = [math]::Round($totalBufferPoolMB, 2)
            BufferPoolCount           = $BufferPools.Count
            TablespaceCount           = $Tablespaces.Count
            CriticalIssues            = @($issues | Where-Object { $_.Severity -eq "CRITICAL" })
            Warnings                  = @($issues | Where-Object { $_.Severity -eq "WARNING" }) + @($warnings)
            InfoMessages              = @($issues | Where-Object { $_.Severity -eq "INFO" })
            AllIssues                 = $issues + $warnings
            HasCriticalIssues         = (@($issues | Where-Object { $_.Severity -eq "CRITICAL" }).Count -gt 0)
            DatabaseMemoryUtilization = if ($MemoryConfig.DatabaseMemoryMB -gt 0) { [math]::Round(($totalBufferPoolMB / $MemoryConfig.DatabaseMemoryMB) * 100, 2) } else { 0 }
        }
        
        Write-LogMessage "Analysis complete: $($analysis.CriticalIssues.Count) critical issues, $($analysis.Warnings.Count) warnings" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "MemoryAnalysis" -NotePropertyValue $analysis -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "HasCriticalMemoryIssues" -NotePropertyValue $analysis.HasCriticalIssues -Force
    }
    catch {
        Write-LogMessage "Error analyzing memory configuration: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

function Get-Db2MemoryRecommendations {
    <#
    .SYNOPSIS
    Generates specific recommendations and commands to fix memory configuration issues
    
    .DESCRIPTION
    Based on analysis results, generates concrete commands that can be executed to fix issues
    
    .PARAMETER WorkObject
    WorkObject containing the memory analysis results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    
    try {
        Write-LogMessage "Generating recommendations for database $($WorkObject.DatabaseName)" -Level INFO
        $Analysis = $WorkObject.MemoryAnalysis
        $MemoryConfig = $WorkObject.MemoryConfiguration
        $DatabaseName = $WorkObject.DatabaseName
        $BufferPools = $WorkObject.BufferPools
        $commands = @()
        $recommendations = @()
        
        # Recommendation 1: Enable SELF_TUNING_MEM if disabled
        if ($MemoryConfig.SelfTuningMem -match "OFF") {
            $recommendations += "Enable self-tuning memory for automatic memory management"
            $commands += "db2 `"UPDATE DB CFG FOR $DatabaseName USING SELF_TUNING_MEM ON`""
        }
        
        # Recommendation 2: Adjust DATABASE_MEMORY if needed
        if ($MemoryConfig.DatabaseMemoryMB -ge $MemoryConfig.InstanceMemoryMB) {
            $targetDatabaseMemory = [math]::Floor($MemoryConfig.InstanceMemoryPages * 0.5)
            $recommendations += "Reduce DATABASE_MEMORY to 50% of INSTANCE_MEMORY"
            $commands += "db2 `"UPDATE DB CFG FOR $DatabaseName USING DATABASE_MEMORY $targetDatabaseMemory`""
        }
        elseif ($Analysis.DatabaseMemoryUtilization -gt 80) {
            $targetDatabaseMemory = [math]::Floor($MemoryConfig.InstanceMemoryPages * 0.6)
            $recommendations += "Increase DATABASE_MEMORY to accommodate buffer pools with overhead"
            $commands += "db2 `"UPDATE DB CFG FOR $DatabaseName USING DATABASE_MEMORY $targetDatabaseMemory`""
        }
        
        # Recommendation 3: Reduce oversized buffer pools
        foreach ($issue in $Analysis.AllIssues) {
            if ($issue.Category -eq "UnusedBufferPool") {
                $bpName = ($issue.Description -match "'([^']+)'") ? $matches[1] : ""
                if ($bpName) {
                    $recommendations += "Reduce unused buffer pool $bpName to minimal size"
                    $commands += "db2 `"ALTER BUFFERPOOL $bpName SIZE 1000`""
                }
            }
            elseif ($issue.Category -eq "BufferPoolSize" -and $issue.Severity -eq "CRITICAL") {
                # Calculate target buffer pool sizes
                $targetTotalMB = $MemoryConfig.DatabaseMemoryMB * 0.4  # Target 40% of DATABASE_MEMORY
                $scaleFactor = $targetTotalMB / $Analysis.TotalBufferPoolMB
                
                $recommendations += "Reduce all buffer pools proportionally to fit within DATABASE_MEMORY"
                foreach ($bp in $BufferPools) {
                    $newPages = [math]::Max(1000, [math]::Floor($bp.NPages * $scaleFactor))
                    $commands += "db2 `"ALTER BUFFERPOOL $($bp.BpName) SIZE $newPages`""
                }
            }
        }
        
        # Add restart commands
        if ($commands.Count -gt 0) {
            $commands += ""
            $commands += "REM === Restart Db2 to apply changes ==="
            $commands += "db2stop force"
            $commands += "db2start"
            $commands += "db2 activate db $($WorkObject.DatabaseName)"
        }
        
        $result = [PSCustomObject]@{
            Recommendations = $recommendations
            Commands        = $commands
            CommandCount    = $commands.Count
        }
        
        Write-LogMessage "Generated $($recommendations.Count) recommendations and $($commands.Count) commands" -Level INFO
        Add-Member -InputObject $WorkObject -NotePropertyName "MemoryRecommendations" -NotePropertyValue $result -Force
    }
    catch {
        Write-LogMessage "Error generating recommendations: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Handle SQL0668N (table in Set Integrity Pending No Access state) for a given table.

.DESCRIPTION
    Generates and runs the commands needed to recover a table from SQL0668N errors,
    using SET INTEGRITY and REORG commands for the specific table name from the WorkObject.
    Adds recommendations and executed script/output into the WorkObject.

.PARAMETER WorkObject
    [PSCustomObject] The object describing the target database and table, and accumulates history.

.EXAMPLE
    $WorkObject = Handle-SQL0668NError -WorkObject $WorkObject

.NOTES
    The WorkObject must include at least DatabaseName and TableName fields.

#>
function Start-SetIntegrityAndReorgTable {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$TableSchema
    )
    try {
        Write-LogMessage "Running SET INTEGRITY and REORG TABLE for $TableSchema.$TableName to resolve SQL0668N" -Level INFO
        $commands = @()
        $commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $commands += "db2 `"SET INTEGRITY FOR $TableSchema.$TableName IMMEDIATE CHECKED`""
        $commands += "db2 `"REORG TABLE $TableSchema.$TableName`""
        $commands += "db2 activate db $($WorkObject.DatabaseName)"
        $commands += "db2 terminate"

        $output = Invoke-Db2ContentAsScript -Content $commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script ($commands -join "`n") -Output $output
    }
    catch {
        Write-LogMessage "Error handling SQL0668N for table $TableSchema.$TableName in $($WorkObject.DatabaseName): $($_.Exception.Message)" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}


<#
.SYNOPSIS
    Query a database using ODBC and return results as JSON.

.DESCRIPTION
    This script demonstrates how to use PowerShell 7.x to connect to a database
    via ODBC and return query results as JSON. You can use either a connection string
    or a System DSN.

.PARAMETER ConnectionString
    The ODBC connection string for the database. Cannot be used with -Dsn.

.PARAMETER Dsn
    The System DSN name to use for the connection. Cannot be used with -ConnectionString.

.PARAMETER Query
    The SQL query to execute.

.PARAMETER OutputFile
    Optional path to save the JSON output to a file.

.EXAMPLE
    $connStr = "Driver={ODBC Driver 17 for SQL Server};Server=localhost;Database=MyDB;Trusted_Connection=yes;"
    .\Query-Database.ps1 -ConnectionString $connStr -Query "SELECT * FROM Users"

.EXAMPLE
    .\Query-Database.ps1 -Dsn "MyDatabaseDSN" -Query "SELECT * FROM products" -OutputFile "results.json"

.EXAMPLE
    $connStr = "Driver={PostgreSQL Unicode};Server=localhost;Database=mydb;Uid=user;Pwd=pass;"
    .\Query-Database.ps1 -ConnectionString $connStr -Query "SELECT * FROM products" -OutputFile "results.json"
#>

function Get-QueryResult {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
    
        [Parameter(Mandatory = $true)]
        [string]$Query,
    
        [Parameter(Mandatory = $false)]
        [string]$OutputFile = ""
    )
    try {

        $actualConnectionString = "DSN=$($WorkObject.RemoteDatabaseName);Driver=/opt/ibm/db2/clidriver/lib/libdb2o.so;Hostname=$($WorkObject.ServerName);Port=$($WorkObject.RemotePort);Database=$($WorkObject.DatabaseName);Protocol=TCPIP;UID=$($WorkObject.UserName);PWD=$($WorkObject.Password)"
        # try {
        #     $connection = New-Object System.Data.Odbc.OdbcConnection($actualConnectionString)
        #     $connection.Open()
        # }
        # catch {
        Write-LogMessage "Error opening connection: $($_.Exception.Message). Trying to catalog user odbc data source $($WorkObject.RemoteDatabaseName)" -Level WARN 
        # Get cataloging commands from 







        # $db2Commands = @()
        # $db2Commands += "db2 uncatalog user odbc data source $($WorkObject.RemoteDatabaseName) >nul 2>&1"
        # $db2Commands += "db2 catalog user odbc data source $($WorkObject.RemoteDatabaseName)"
        # $db2Commands += "db2 terminate"
        # $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        # $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script ($db2Commands -join "`n") -Output $output





        # [DB2_SAMPLE_REMOTE]
        # Description=Connection to remote Db2 server
        # Driver=/opt/ibm/db2/clidriver/lib/libdb2o.so
        # Hostname=db2server.example.com
        # Port=50000
        # Database=SAMPLEDB
        # Protocol=TCPIP
        # UID=db2admin
        # PWD=secret


        $connection = New-Object System.Data.Odbc.OdbcConnection($actualConnectionString)
        $connection.Open()
        Write-LogMessage "Connection opened successfully" -Level INFO

        # }
    
        Write-LogMessage "Connection opened successfully" -Level INFO
    
        # Create command
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
    
        # Execute query and get data reader
        $reader = $command.ExecuteReader()
    
        # Get column names
        $columnCount = $reader.FieldCount
        $columnNames = @()
        for ($i = 0; $i -lt $columnCount; $i++) {
            $columnNames += $reader.GetName($i)
        }
    
        # Read all rows and convert to objects
        $results = @()
        while ($reader.Read()) {
            $row = [ordered]@{}
            for ($i = 0; $i -lt $columnCount; $i++) {
                $columnName = $columnNames[$i]
                $value = $reader.GetValue($i)
            
                # Handle DBNull values
                if ([DBNull]::Value.Equals($value)) {
                    $row[$columnName] = $null
                }
                else {
                    $row[$columnName] = $value
                }
            }
            $results += [PSCustomObject]$row
        }
    
        # Close reader and connection
        $reader.Close()
        $connection.Close()
    
        Write-LogMessage "Retrieved $($results.Count) rows" -Level INFO
        if (-not [string]::IsNullOrEmpty($OutputFile)) {
            # Convert to JSON
            $jsonOutput = $results | ConvertTo-Json -Depth 10 -Compress:$false
            Write-LogMessage $jsonOutput -Level INFO
            $jsonOutput | Out-File -FilePath $OutputFile -Encoding utf8
            Write-LogMessage "Results saved to $OutputFile" -Level INFO
        }    
    }
    catch {
        Write-LogMessage "Error executing query:`n$Query" -Level ERROR -Exception $_
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
        throw $_
    }
    return $results
}


function Get-QueryResultDirect {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteDatabaseName,
    
        [Parameter(Mandatory = $true)]
        [string]$Query,
    
        [Parameter(Mandatory = $false)]
        [string]$OutputFile = ""
    )
    try {

        $actualConnectionString = "DSN=$($RemoteDatabaseName)"
        # try {
        #     $connection = New-Object System.Data.Odbc.OdbcConnection($actualConnectionString)
        #     $connection.Open()
        # }
        # catch {
        #Write-LogMessage "Error opening connection: $($_.Exception.Message). Trying to catalog user odbc data source $($RemoteDatabaseName)" -Level WARN 
        # Get cataloging commands from 







        # $db2Commands = @()
        # $db2Commands += "db2 uncatalog user odbc data source $($WorkObject.RemoteDatabaseName) >nul 2>&1"
        # $db2Commands += "db2 catalog user odbc data source $($WorkObject.RemoteDatabaseName)"
        # $db2Commands += "db2 terminate"
        # $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
        # $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "$($MyInvocation.MyCommand.Name)" -Script ($db2Commands -join "`n") -Output $output





        # [DB2_SAMPLE_REMOTE]
        # Description=Connection to remote Db2 server
        # Driver=/opt/ibm/db2/clidriver/lib/libdb2o.so
        # Hostname=db2server.example.com
        # Port=50000
        # Database=SAMPLEDB
        # Protocol=TCPIP
        # UID=db2admin
        # PWD=secret


        $connection = New-Object System.Data.Odbc.OdbcConnection($actualConnectionString)
        $connection.Open()
        Write-LogMessage "Connection opened successfully" -Level INFO

        # }
    
        Write-LogMessage "Connection opened successfully" -Level INFO
    
        # Create command
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
    
        # Execute query and get data reader
        $reader = $command.ExecuteReader()
    
        # Get column names
        $columnCount = $reader.FieldCount
        $columnNames = @()
        for ($i = 0; $i -lt $columnCount; $i++) {
            $columnNames += $reader.GetName($i)
        }
    
        # Read all rows and convert to objects
        $results = @()
        while ($reader.Read()) {
            $row = [ordered]@{}
            for ($i = 0; $i -lt $columnCount; $i++) {
                $columnName = $columnNames[$i]
                $value = $reader.GetValue($i)
            
                # Handle DBNull values
                if ([DBNull]::Value.Equals($value)) {
                    $row[$columnName] = $null
                }
                else {
                    $row[$columnName] = $value
                }
            }
            $results += [PSCustomObject]$row
        }
    
        # Close reader and connection
        $reader.Close()
        $connection.Close()
    
        Write-LogMessage "Retrieved $($results.Count) rows" -Level INFO
        if (-not [string]::IsNullOrEmpty($OutputFile)) {
            # Convert to JSON
            $jsonOutput = $results | ConvertTo-Json -Depth 10 -Compress:$false
            Write-LogMessage $jsonOutput -Level INFO
            $jsonOutput | Out-File -FilePath $OutputFile -Encoding utf8
            Write-LogMessage "Results saved to $OutputFile" -Level INFO
        }    
    }
    catch {
        Write-LogMessage "Error executing query:`n$Query" -Level ERROR -Exception $_
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
        throw $_
    }
    return $results
}


<#
.SYNOPSIS
    Extracts column names from a SQL SELECT statement.

.DESCRIPTION
    Parses a SQL SELECT statement to determine the columns being queried.
    If the query contains "SELECT *", the function:
    - Extracts table name(s) from the FROM clause
    - Queries SYSCAT.COLUMNS to retrieve all column names for those tables
    - Returns an array of column names in the order they appear in the database
    
    If the query specifies explicit column names, those are parsed and returned.
    Handles:
    - SELECT * FROM single_table
    - SELECT * FROM schema.table
    - SELECT * FROM table1, table2 (multiple tables)
    - SELECT col1, col2, col3 FROM table
    - SELECT with WHERE, ORDER BY, GROUP BY clauses

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName and InstanceName for database access.

.PARAMETER Query
    SQL SELECT statement to parse for column information.

.EXAMPLE
    $columns = Get-ColumnsFromQuery -WorkObject $workObject -Query "SELECT * FROM SYSCAT.TABLES"
    # Returns array of all column names from SYSCAT.TABLES

.EXAMPLE
    $columns = Get-ColumnsFromQuery -WorkObject $workObject -Query "SELECT TABSCHEMA, TABNAME FROM SYSCAT.TABLES"
    # Returns @("TABSCHEMA", "TABNAME")

.EXAMPLE
    $columns = Get-ColumnsFromQuery -WorkObject $workObject -Query "SELECT * FROM DBM.CUSTOMER, DBM.ORDERS"
    # Returns array of all columns from both CUSTOMER and ORDERS tables

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Uses SYSCAT.COLUMNS system catalog to retrieve column metadata.
    Columns are returned in COLNO order (natural database order).
#>
function Get-ColumnsFromQuery {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    
    try {
        Write-LogMessage "Parsing query to extract column information" -Level DEBUG
        
        # Initialize column array
        $columnArray = @()
        
        # Normalize query: remove extra whitespace, convert to uppercase for parsing
        $normalizedQuery = $Query -replace '\s+', ' '
        $upperQuery = $normalizedQuery.ToUpper()
        
        # Check if this is a SELECT * query
        # Regex explanation:
        # SELECT\s+\*      - Match "SELECT" followed by whitespace and asterisk
        # \s+FROM          - Match whitespace and "FROM"
        if ($upperQuery -match 'SELECT\s+\*\s+FROM') {
            Write-LogMessage "Detected SELECT * query - extracting table names from FROM clause" -Level INFO
            
            # Extract the FROM clause
            # Regex explanation:
            # \sFROM\s+        - Match " FROM " with surrounding whitespace
            # ([^\s,WHERE,GROUP,ORDER,HAVING,UNION,INTERSECT,EXCEPT]+)  - Capture table name(s) until clause keywords
            # The split handles multiple scenarios: WHERE, GROUP BY, ORDER BY, etc.
            $fromMatch = $normalizedQuery -match '\sFROM\s+(.*?)(?:\s+WHERE|\s+GROUP|\s+ORDER|\s+HAVING|\s+UNION|\s+INTERSECT|\s+EXCEPT|\s*$)'
            
            if ($fromMatch) {
                $fromClause = $matches[1].Trim()
                Write-LogMessage "FROM clause extracted: $($fromClause)" -Level DEBUG
                
                # Split by comma to handle multiple tables
                # Regex explanation:
                # ,\s*  - Match comma followed by optional whitespace
                $tableNames = $fromClause -split ',\s*'
                
                # Process each table to extract schema and table name
                foreach ($tableName in $tableNames) {
                    $tableName = $tableName.Trim()
                    
                    # Handle table aliases (e.g., "SYSCAT.TABLES AS T" or "SYSCAT.TABLES T")
                    # Regex explanation:
                    # \s+AS\s+|\s+  - Match " AS " or just whitespace (for alias)
                    # Take only the first part (before alias)
                    if ($tableName -match '\s+AS\s+|\s+') {
                        $tableName = $tableName -split '\s+AS\s+|\s+' | Select-Object -First 1
                        $tableName = $tableName.Trim()
                    }
                    
                    # Parse schema and table name
                    # Regex explanation:
                    # ^           - Start of string
                    # ([^.]+)     - Capture group 1: schema name (anything except period)
                    # \.          - Literal period separator
                    # ([^.]+)     - Capture group 2: table name (anything except period)
                    # $           - End of string
                    if ($tableName -match '^([^.]+)\.([^.]+)$') {
                        $schema = $matches[1].Trim()
                        $table = $matches[2].Trim()
                    }
                    else {
                        # No schema specified - table name only
                        # We'll need to query without schema filter
                        $schema = $null
                        $table = $tableName.Trim()
                    }
                    
                    Write-LogMessage "Querying SYSCAT.COLUMNS for table: $($schema).$($table)" -Level INFO
                    
                    # Build query to get columns from SYSCAT.COLUMNS
                    if ($null -ne $schema) {
                        $columnQuery = "SELECT COLNAME, COLNO FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '$($schema)' AND TABNAME = '$($table)' ORDER BY COLNO"
                    }
                    else {
                        $columnQuery = "SELECT COLNAME, COLNO FROM SYSCAT.COLUMNS WHERE TABNAME = '$($table)' ORDER BY COLNO"
                    }
                    
                    Write-LogMessage "Executing query: $($columnQuery)" -Level DEBUG
                    
                    # Execute query using existing Get-ArrayFromQuery function
                    $columnResults = Get-ArrayFromQuery -WorkObject $WorkObject -SqlSelectStatement $columnQuery
                    
                    if ($null -ne $columnResults -and $columnResults.Count -gt 0) {
                        foreach ($col in $columnResults) {
                            # Extract COLNAME from result
                            # Results come back as objects with properties
                            if ($col -is [PSCustomObject] -and $col.PSObject.Properties['COLNAME']) {
                                $columnArray += $col.COLNAME.Trim()
                            }
                            elseif ($col -is [string]) {
                                # If it's a string, split by whitespace and take first element
                                $colName = ($col -split '\s+')[0].Trim()
                                $columnArray += $colName
                            }
                        }
                        Write-LogMessage "Retrieved $($columnResults.Count) columns from $($schema).$($table)" -Level INFO
                    }
                    else {
                        Write-LogMessage "No columns found for table $($schema).$($table)" -Level WARN
                    }
                }
            }
            else {
                Write-LogMessage "Could not parse FROM clause from query: $($Query)" -Level ERROR
                throw "Unable to extract FROM clause from SELECT * query"
            }
        }
        else {
            # Not a SELECT * query - parse explicit column list
            Write-LogMessage "Parsing explicit column list from SELECT statement" -Level INFO
            
            # Extract column list between SELECT and FROM
            # Regex explanation:
            # SELECT\s+       - Match "SELECT" and whitespace
            # (.*?)           - Capture group: column list (non-greedy)
            # \s+FROM         - Match whitespace and "FROM"
            $selectMatch = $upperQuery -match 'SELECT\s+(.*?)\s+FROM'
            
            if ($selectMatch) {
                $columnList = $matches[1].Trim()
                
                # Split by comma to get individual columns
                $columns = $columnList -split ','
                
                foreach ($col in $columns) {
                    $col = $col.Trim()
                    
                    # Handle column aliases (e.g., "TABSCHEMA AS SCHEMA" or "COUNT(*) AS CNT")
                    # Regex explanation:
                    # \s+AS\s+    - Match " AS " (case insensitive due to uppercase conversion)
                    if ($col -match '\s+AS\s+') {
                        # Take the alias (last part)
                        $colName = ($col -split '\s+AS\s+')[-1].Trim()
                    }
                    else {
                        # No alias - use column name as-is
                        # Remove table prefix if present (e.g., "T.TABSCHEMA" -> "TABSCHEMA")
                        if ($col -match '\.') {
                            $colName = ($col -split '\.')[-1].Trim()
                        }
                        else {
                            $colName = $col
                        }
                    }
                    
                    $columnArray += $colName
                }
                
                Write-LogMessage "Extracted $($columnArray.Count) columns from SELECT list" -Level INFO
            }
            else {
                Write-LogMessage "Could not parse SELECT column list from query: $($Query)" -Level ERROR
                throw "Unable to extract column list from SELECT statement"
            }
        }
        
        Write-LogMessage "Successfully extracted $($columnArray.Count) columns: $($columnArray -join ', ')" -Level INFO
        return $columnArray
    }
    catch {
        Write-LogMessage "Error extracting columns from query: $($Query)" -Level ERROR -Exception $_
        throw "Error extracting columns from query: $($_.Exception.Message)"
    }
}
<#
.SYNOPSIS
    Executes a SQL query and returns results as CSV with proper column headers.

.DESCRIPTION
    Executes a SQL query using DB2 export functionality and imports the result as CSV.
    Automatically determines column headers from the query:
    - For SELECT * queries, retrieves column names from SYSCAT.COLUMNS
    - For explicit SELECT queries, extracts column names from the SELECT clause
    
    Uses DB2's native CSV export for optimal performance with large result sets.

.PARAMETER WorkObject
    PSCustomObject containing DatabaseName, InstanceName, and WorkFolder.

.PARAMETER Query
    SQL SELECT statement to execute.

.EXAMPLE
    $workObject = Get-QueryResultDirectCsv -WorkObject $workObject -Query "SELECT * FROM SYSCAT.TABLES"
    # Executes query and returns results with proper column headers

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Uses DB2 export command with semicolon delimiter for CSV generation.
#>
function Get-QueryResultDirectCsv {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    try {
        Write-LogMessage "Executing query and exporting to CSV for database $($WorkObject.DatabaseName)" -Level INFO

        # Get column headers from query using the new Get-ColumnsFromQuery function
        Write-LogMessage "Extracting column headers from query" -Level DEBUG
        $columnHeaders = Get-ColumnsFromQuery -WorkObject $WorkObject -Query $Query
        
        if ($null -eq $columnHeaders -or $columnHeaders.Count -eq 0) {
            Write-LogMessage "No column headers found in query, using default import" -Level WARN
        }
        else {
            Write-LogMessage "Found $($columnHeaders.Count) column headers: $($columnHeaders -join ', ')" -Level INFO
        }

        # Export query results to CSV using DB2's native export
        $outputFile = Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').csv"
        $db2Commands = @()
        $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $WorkObject)
        $db2Commands += $(Get-ConnectCommand -WorkObject $WorkObject)
        $db2Commands += "db2 export to $($outputFile) of del modified by coldel; $($Query)"
        
        Write-LogMessage "Executing DB2 export command" -Level DEBUG
        $null = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $WorkObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")"
        
        # Import CSV with proper headers
        if ($null -ne $columnHeaders -and $columnHeaders.Count -gt 0) {
            Write-LogMessage "Importing CSV with header names: $($columnHeaders -join ', ')" -Level DEBUG
            $result = Import-Csv -Path $outputFile -Delimiter ';' -Header $columnHeaders
        }
        else {
            # Fallback: import without explicit headers (first row becomes headers)
            Write-LogMessage "Importing CSV without explicit headers" -Level DEBUG
            $result = Import-Csv -Path $outputFile -Delimiter ';'
        }
        
        Write-LogMessage "Successfully imported $($result.Count) rows from CSV" -Level INFO
        
        # Add results to WorkObject
        Add-Member -InputObject $WorkObject -NotePropertyName "QueryResultCsv" -NotePropertyValue $result -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "QueryResultCsvFile" -NotePropertyValue $outputFile -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "QueryResultColumns" -NotePropertyValue $columnHeaders -Force
    }
    catch {
        Write-LogMessage "Error executing query and exporting to CSV for database $($WorkObject.DatabaseName)" -Level ERROR -Exception $_
        throw "Error executing query and exporting to CSV for database $($WorkObject.DatabaseName): $($_.Exception.Message)"
    }
    return $WorkObject
}
<#
.SYNOPSIS
    Generates a comprehensive DB2 error diagnosis report.

.DESCRIPTION
    Collects DB2 configuration, security plugins, Kerberos tickets, SPNs, services,
    connection test, db2diag.log, event log, database config, log paths, federation info,
    authentication config, network info, and instance list into a single report file.

.PARAMETER DatabaseName
    The database name to diagnose. Required.

.PARAMETER InstanceName
    The DB2 instance name. Defaults to "DB2".

.PARAMETER OutputFolder
    Folder to write the report and temporary files to. If not specified, uses Get-ApplicationDataPath.

.EXAMPLE
    New-Db2ErrorDiagnosisReport -DatabaseName "FKMKAT"

.EXAMPLE
    New-Db2ErrorDiagnosisReport -DatabaseName "FKMKAT" -InstanceName "DB2" -OutputFolder "C:\temp"

.NOTES
    Returns the full path to the generated report file.
#>
function New-Db2ErrorDiagnosisReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$InstanceName = "DB2",
        [Parameter(Mandatory = $false)]
        [string]$OutputFolder
    )

    if (-not $OutputFolder) {
        $OutputFolder = Get-ApplicationDataPath
    }
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    $reportFile = Join-Path $OutputFolder "Db2-ErrorDiagnosisReport_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $separator = "=" * 80

    function Write-DiagSection {
        param([string]$Title, [string]$Content)
        $section = @"

$separator
  $Title
$separator
$Content

"@
        Add-Content -Path $reportFile -Value $section -Encoding UTF8
        Write-LogMessage "Collected: $Title" -Level INFO
    }

    function Invoke-Db2DiagCmd {
        param(
            [Parameter(Mandatory = $true)]
            $Commands,
            [string]$Instance = "DB2"
        )
        try {
            $db2Commands = @()
            $db2Commands += "set DB2INSTANCE=$Instance"
            if ($Commands -is [array]) {
                $db2Commands += $Commands
            }
            else {
                $db2Commands += $Commands -split "`n" | Where-Object { $_.Trim() -ne "" }
            }
            $batFile = Join-Path $OutputFolder "db2diag_$($PID)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFile -IgnoreErrors -Quiet
            return ($output | Out-String)
        }
        catch {
            return "ERROR: $($_.Exception.Message)"
        }
    }

    $header = @"
DB2 Error Diagnosis Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer:  $($env:COMPUTERNAME)
User:      $($env:USERDOMAIN)\$($env:USERNAME)
Instance:  $InstanceName
Database:  $DatabaseName
OS:        $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)
"@
    Set-Content -Path $reportFile -Value $header -Encoding UTF8

    # ── 1. DB2 Instance & Version ──
    $db2level = Invoke-Db2DiagCmd -Commands @("db2level") -Instance $InstanceName
    Write-DiagSection -Title "DB2 LEVEL (Version)" -Content $db2level

    $db2version = Invoke-Db2DiagCmd -Commands @(
        "db2 connect to $DatabaseName",
        "db2 `"SELECT * FROM SYSIBMADM.ENV_PROD_INFO WHERE LICENSE_INSTALLED = 'Y'`"",
        "db2 connect reset"
    ) -Instance $InstanceName
    Write-DiagSection -Title "DB2 VERSION (ENV_PROD_INFO)" -Content $db2version

    # ── 2. DB2 Environment Variables ──
    $db2set = Invoke-Db2DiagCmd -Commands @("db2set -all") -Instance $InstanceName
    Write-DiagSection -Title "DB2 REGISTRY VARIABLES (db2set -all)" -Content $db2set

    # ── 3. DBM Configuration (Authentication & Security) ──
    $dbmCfgFull = Invoke-Db2DiagCmd -Commands @("db2 get dbm cfg") -Instance $InstanceName
    Write-DiagSection -Title "DATABASE MANAGER CONFIGURATION (Full)" -Content $dbmCfgFull

    # ── 4. DB2 CLI Configuration ──
    $cliCfg = Invoke-Db2DiagCmd -Commands @("db2 get cli cfg") -Instance $InstanceName
    Write-DiagSection -Title "DB2 CLI CONFIGURATION" -Content $cliCfg

    # ── 5. Node Directory ──
    $nodeDir = Invoke-Db2DiagCmd -Commands @("db2 list node directory show detail") -Instance $InstanceName
    Write-DiagSection -Title "NODE DIRECTORY (detailed)" -Content $nodeDir

    # ── 6. Database Directory ──
    $dbDir = Invoke-Db2DiagCmd -Commands @("db2 list database directory") -Instance $InstanceName
    Write-DiagSection -Title "DATABASE DIRECTORY" -Content $dbDir

    # ── 7. Security Plugin Files ──
    $db2InstallRoot = $null
    $db2Exe = Get-Command "db2.exe" -ErrorAction SilentlyContinue
    if ($db2Exe) {
        $db2InstallRoot = (Split-Path (Split-Path $db2Exe.Source -Parent) -Parent)
    }
    $pluginBasePaths = @("C:\DbInst", "${env:ProgramFiles}\IBM\SQLLIB")
    if ($db2InstallRoot -and $pluginBasePaths -notcontains $db2InstallRoot) {
        $pluginBasePaths = @($db2InstallRoot) + $pluginBasePaths
    }
    $pluginInfo = ""
    if ($db2InstallRoot) {
        $pluginInfo += "Detected DB2 install root: $db2InstallRoot`n"
    }

    $securityRoots = @("security", "security64")
    foreach ($base in $pluginBasePaths) {
        foreach ($secRoot in $securityRoots) {
            $securityDir = Join-Path $base $secRoot
            $pluginInfo += "`n--- $securityDir ---`n"
            if (Test-Path $securityDir) {
                $allFiles = Get-ChildItem -Path $securityDir -Recurse -File -ErrorAction SilentlyContinue
                if ($allFiles) {
                    foreach ($f in $allFiles) {
                        $relativePath = $f.FullName.Substring($securityDir.Length + 1)
                        $pluginInfo += "  $($relativePath)  ($($f.Length) bytes, $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))`n"
                    }
                }
                else {
                    $pluginInfo += "  (directory exists but contains no files)`n"
                }
            }
            else {
                $pluginInfo += "  (directory does NOT exist)`n"
            }
        }
    }

    $pluginInfo += "`n--- IBMkrb5.dll search ---`n"
    $ibmKrb5Found = $false
    foreach ($base in $pluginBasePaths) {
        $krb5Files = Get-ChildItem -Path $base -Filter "IBMkrb5.dll" -Recurse -ErrorAction SilentlyContinue
        foreach ($k in $krb5Files) {
            $pluginInfo += "  FOUND: $($k.FullName)  ($($k.Length) bytes, $($k.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))`n"
            $ibmKrb5Found = $true
        }
    }
    if (-not $ibmKrb5Found) {
        $pluginInfo += "  IBMkrb5.dll NOT FOUND in any search path`n"
    }
    Write-DiagSection -Title "SECURITY PLUGIN FILES (IBMkrb5, etc.)" -Content $pluginInfo

    # ── 8. Kerberos Tickets (klist) ──
    try {
        $klistOutput = & klist 2>&1 | Out-String
    }
    catch {
        $klistOutput = "ERROR running klist: $($_.Exception.Message)"
    }
    Write-DiagSection -Title "KERBEROS TICKETS (klist)" -Content $klistOutput

    # ── 9. SPN Registrations for this server ──
    try {
        $spnOutput = & setspn -L $env:COMPUTERNAME 2>&1 | Out-String
    }
    catch {
        $spnOutput = "ERROR running setspn: $($_.Exception.Message)"
    }
    $spnDb2 = ""
    try {
        $spnDb2 = & setspn -Q "db2/$($env:COMPUTERNAME)" 2>&1 | Out-String
        $spnDb2Fqdn = & setspn -Q "db2/$($env:COMPUTERNAME).DEDGE.fk.no" 2>&1 | Out-String
        $spnDb2 += "`n--- FQDN query ---`n$spnDb2Fqdn"
    }
    catch {
        $spnDb2 = "ERROR running setspn -Q: $($_.Exception.Message)"
    }
    Write-DiagSection -Title "SPN REGISTRATIONS (this computer)" -Content $spnOutput
    Write-DiagSection -Title "SPN QUERY FOR db2/ SERVICE" -Content $spnDb2

    # ── 10. DB2 Service Account ──
    $db2Services = Get-CimInstance Win32_Service | Where-Object { $_.Name -like "*DB2*" -or $_.Name -like "*IBM*" } |
    Select-Object Name, State, StartMode, StartName, PathName |
    Format-List | Out-String
    Write-DiagSection -Title "DB2 WINDOWS SERVICES" -Content $(if ($db2Services) { $db2Services } else { "(no DB2 services found)" })

    # ── 11. Connection Test ──
    $connectTest = Invoke-Db2DiagCmd -Commands @(
        "db2 connect to $DatabaseName",
        "db2 values current timestamp",
        "db2 connect reset"
    ) -Instance $InstanceName
    Write-DiagSection -Title "CONNECTION TEST ($DatabaseName)" -Content $connectTest

    # ── 12. DB2 Diagnostic Log (last 50 lines) ──
    $diagBasePaths = @("C:\DbInst", "C:\ProgramData\IBM\DB2\DB2COPY1", "${env:ProgramFiles}\IBM\SQLLIB")
    if ($db2InstallRoot -and $diagBasePaths -notcontains $db2InstallRoot) {
        $diagBasePaths = @($db2InstallRoot) + $diagBasePaths
    }
    $diagPaths = @()
    foreach ($base in $diagBasePaths) {
        $diagPaths += Join-Path $base $InstanceName
        if ($InstanceName -ne "DB2") { $diagPaths += Join-Path $base "DB2" }
    }
    $diagContent = ""
    foreach ($diagPath in $diagPaths) {
        $diagLog = Join-Path $diagPath "db2diag.log"
        $diagContent += "`nChecking: $diagLog`n"
        if (Test-Path $diagLog -PathType Leaf) {
            $diagContent += "  File size: $((Get-Item $diagLog).Length / 1KB) KB`n"
            $diagContent += "  Last modified: $((Get-Item $diagLog).LastWriteTime)`n"
            $diagContent += "`n--- Last 50 lines ---`n"
            $lastLines = Get-Content -Path $diagLog -Tail 50 -ErrorAction SilentlyContinue
            $diagContent += ($lastLines -join "`n")
        }
        else {
            $diagContent += "  (file does not exist)`n"
        }
    }
    Write-DiagSection -Title "DB2 DIAGNOSTIC LOG (db2diag.log)" -Content $diagContent

    # ── 13. Windows Event Log (DB2 errors last 24h) ──
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -like "*DB2*" -or $_.ProviderName -like "*IBM*" } |
        Select-Object -First 20 TimeCreated, LevelDisplayName, Id, Message |
        Format-List | Out-String
        Write-DiagSection -Title "WINDOWS EVENT LOG (DB2-related, last 24h)" -Content $(if ($events) { $events } else { "(no DB2 events in last 24h)" })
    }
    catch {
        Write-DiagSection -Title "WINDOWS EVENT LOG (DB2-related, last 24h)" -Content "ERROR: $($_.Exception.Message)"
    }

    # ── 14. DB Configuration ──
    $dbCfg = Invoke-Db2DiagCmd -Commands @(
        "db2 connect to $DatabaseName",
        "db2 get db cfg for $DatabaseName",
        "db2 connect reset"
    ) -Instance $InstanceName
    Write-DiagSection -Title "DATABASE CONFIGURATION ($DatabaseName)" -Content $dbCfg

    # ── 14a. Log Path Configuration (sqlpgCheckForLogPathChanges diagnosis) ──
    $logPathCfg = ($dbCfg -split "`n") | Where-Object {
        $_ -match "LOGARCHMETH|LOGPATH|NEWLOGPATH|OVERFLOWLOGPATH|MIRRORLOGPATH|LOGPRIMARY|LOGSECOND|LOGFILSIZ|LOGBUFSZ|BLK_LOG_DSK_FUL|loggfil|logg"
    }
    $logPathInfo = "--- Log-related DB CFG parameters ---`n"
    $logPathInfo += ($logPathCfg -join "`n")
    $logPathInfo += "`n`n--- Verify log paths exist on disk ---`n"
    foreach ($line in $logPathCfg) {
        if ($line -match "=\s*(.:\\[^\s]+)") {
            $path = $matches[1].Trim()
            if (Test-Path $path) {
                $logPathInfo += "  OK:      $path`n"
            }
            else {
                $logPathInfo += "  MISSING: $path  <-- potential cause of sqlpgCheckForLogPathChanges probe:1750`n"
            }
        }
    }
    Write-DiagSection -Title "LOG PATH CONFIGURATION ($DatabaseName)" -Content $logPathInfo

    # ── 15. Federation & Wrapper info (server-side) ──
    $fedInfo = Invoke-Db2DiagCmd -Commands @(
        "db2 connect to $DatabaseName",
        "db2 `"SELECT WRAPNAME, WRAPTYPE, LIBRARY, REMARKS FROM SYSCAT.WRAPPERS`"",
        "db2 `"SELECT SERVERNAME, SERVERTYPE, WRAPNAME, SERVERVERSION FROM SYSCAT.SERVERS`"",
        "db2 `"SELECT SUBSTR(TABSCHEMA,1,20) AS SCHEMA, SUBSTR(TABNAME,1,40) AS NICKNAME, SUBSTR(SERVERNAME,1,20) AS SERVER, SUBSTR(REMOTE_SCHEMA,1,20) AS REM_SCHEMA, SUBSTR(REMOTE_TABLE,1,40) AS REM_TABLE FROM SYSCAT.NICKNAMES FETCH FIRST 50 ROWS ONLY`"",
        "db2 connect reset"
    ) -Instance $InstanceName
    Write-DiagSection -Title "FEDERATION INFO ($DatabaseName) - Wrappers, Servers, Nicknames" -Content $fedInfo

    # ── 16. Authentication-related DBM cfg extract ──
    $authCfg = Invoke-Db2DiagCmd -Commands @(
        "db2 get dbm cfg"
    ) -Instance $InstanceName
    $authLines = ($authCfg -split "`n") | Where-Object {
        $_ -match "AUTHENTICATION|SRVCON_AUTH|TRUST_CLNTAUTH|TRUST_ALLCLNTS|CATALOG_NOAUTH|CLNT_KRB_PLUGIN|SRVCON_GSSPLUGIN_LIST|SRVCON_PW_PLUGIN|LOCAL_GSSPLUGIN|GROUP_PLUGIN|SVCENAME"
    }
    Write-DiagSection -Title "AUTHENTICATION-RELATED DBM CFG (summary)" -Content ($authLines -join "`n")

    # ── 17. Network Connectivity ──
    $netInfo = ""
    $netInfo += "--- ipconfig ---`n"
    $netInfo += (ipconfig | Out-String)
    $netInfo += "`n--- Domain Info ---`n"
    try {
        $domainInfo = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $netInfo += "Domain: $($domainInfo.Name)`n"
        $netInfo += "Forest: $($domainInfo.Forest.Name)`n"
        $netInfo += "Domain Controllers:`n"
        foreach ($dc in $domainInfo.DomainControllers) {
            $netInfo += "  $($dc.Name) ($($dc.IPAddress))`n"
        }
    }
    catch {
        $netInfo += "Could not get domain info: $($_.Exception.Message)`n"
    }
    Write-DiagSection -Title "NETWORK & DOMAIN INFO" -Content $netInfo

    # ── 18. DB2 Instances on this server ──
    $instances = Invoke-Db2DiagCmd -Commands @("db2ilist") -Instance $InstanceName
    Write-DiagSection -Title "DB2 INSTANCES (db2ilist)" -Content $instances

    Write-LogMessage "Report saved to: $reportFile" -Level INFO
    return $reportFile
}

<#
.SYNOPSIS
    Sets DEDGE DB2 user grants (RDO read-only, DBA admin) across all databases on the server.

.DESCRIPTION
    Uses Get-InstanceNameList and Get-DatabaseNameList for multi-database traversal (no UseNewConfigurations).
    - RDO users (FKPRDRDO, FKTSTDRDO, FKDEVDRDO): GRANT CONNECT + SELECT on application schemas
    - DBA users (FKPRDDBA, FKTSTDBA, FKDEVDBA): Full DBADM privileges (same as DB2NT)
    Standard users (FKPRDUSR, FKTSTUSR, FKDEVUSR) are handled by Add-SpecificGrants / DB2USERS group.

.PARAMETER InstanceName
    DB2 instance name. Default "DB2".

.EXAMPLE
    Set-DEDGEDb2UserGrants -InstanceName "DB2"
    # Grants RDO and DBA privileges across all databases
#>

<#
.SYNOPSIS
    Synchronizes SQL procedures and functions from a primary database to a federated database.

.DESCRIPTION
    Uses db2look to extract full DDL from the primary database, splits each routine into
    individual files (schema.name.prc/.fcn), then applies each file to the federated
    database using db2 -tvf. Skips schemas starting with SYS.

.PARAMETER WorkObject
    PSCustomObject containing:
    - DatabaseName: Federated database name (e.g. XFKMTST)
    - InstanceName: Federated instance name (e.g. DB2FED)
    - LinkedPrimaryDatabaseName: Primary database name (e.g. FKMTST)
    - LinkedPrimaryInstanceName: Primary instance name (e.g. DB2)
    - WorkFolder: Path for temporary files

.EXAMPLE
    $workObject = Sync-FederatedRoutines -WorkObject $workObject
#>
function Sync-FederatedRoutines {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    try {
        Write-LogMessage "Starting routine sync: $($WorkObject.LinkedPrimaryDatabaseName) -> $($WorkObject.DatabaseName) (db2look)" -Level INFO

        $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
        $routinesFolder = Join-Path $WorkObject.WorkFolder "routines"
        if (-not (Test-Path $routinesFolder)) { New-Item -Path $routinesFolder -ItemType Directory -Force | Out-Null }

        # ─── Phase 1: db2look on primary instance ───
        $db2lookFile = Join-Path $WorkObject.WorkFolder "db2look_routines_$($timestamp).sql"

        $lookCommands = @()
        $lookCommands += "set DB2INSTANCE=$($WorkObject.LinkedPrimaryInstanceName)"
        $lookCommands += "db2look -d $($WorkObject.LinkedPrimaryDatabaseName) -e -a -td @ -noview -o `"$($db2lookFile)`""

        $output = Invoke-Db2ContentAsScript -Content $lookCommands -ExecutionType BAT -IgnoreErrors -FileName (Join-Path $WorkObject.WorkFolder "RoutineSync_Db2look_$($timestamp).bat")
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "RoutineSync_Db2look" -Script ($lookCommands -join "`n") -Output $output

        if (-not (Test-Path $db2lookFile)) {
            throw "db2look output file not found: $($db2lookFile)"
        }

        $db2lookSizeKB = [math]::Round((Get-Item $db2lookFile).Length / 1KB, 2)
        Write-LogMessage "db2look output file size: $($db2lookSizeKB) KB" -Level INFO

        # ─── Phase 2: Parse db2look, split each routine into its own file ───
        $rawDdl = [System.IO.File]::ReadAllText($db2lookFile, $ansiEncoding)
        $statements = $rawDdl -split '@'
        $routineFiles = @()
        $skippedSys = 0
        $skippedOther = 0

        foreach ($stmt in $statements) {
            $trimmed = $stmt.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

            # Regex: match CREATE PROCEDURE or CREATE FUNCTION with quoted schema.name
            #   CREATE\s+  - the CREATE keyword
            #   (PROCEDURE|FUNCTION)\s+  - captures routine type
            #   "([^"]+)"\s*\.\s*"([^"]+)"  - captures "SCHEMA"."NAME"
            if ($trimmed -match '(?mi)^\s*CREATE\s+(PROCEDURE|FUNCTION)\s+"([^"]+)"\s*\.\s*"([^"]+)"') {
                $routineType = $Matches[1].ToUpper()
                $schema = $Matches[2].Trim()
                $name = $Matches[3].Trim()

                if ($schema -like 'SYS*') {
                    $skippedSys++
                    continue
                }

                $ext = if ($routineType -eq 'PROCEDURE') { 'prc' } else { 'fcn' }
                $fileName = "$($schema).$($name).$($ext).sql"
                $filePath = Join-Path $routinesFolder $fileName

                [System.IO.File]::WriteAllText($filePath, "$trimmed`n@`n", $ansiEncoding)
                $routineFiles += [PSCustomObject]@{
                    Schema = $schema
                    Name   = $name
                    Type   = $routineType
                    File   = $filePath
                }
            }
            else {
                $skippedOther++
            }
        }

        Write-LogMessage "db2look split: $($routineFiles.Count) routine files created, $($skippedSys) SYS* skipped, $($skippedOther) non-routine skipped" -Level INFO

        if ($routineFiles.Count -eq 0) {
            Write-LogMessage "No routines found in db2look output for $($WorkObject.LinkedPrimaryDatabaseName)" -Level WARN
            Add-Member -InputObject $WorkObject -NotePropertyName "RoutinesAdded" -NotePropertyValue 0 -Force
            Add-Member -InputObject $WorkObject -NotePropertyName "RoutinesDropped" -NotePropertyValue 0 -Force
            return $WorkObject
        }

        # ─── Phase 3: Connect to fed DB and apply each routine file (@ terminator for SQL PL bodies) ───
        $applyCommands = @()
        $applyCommands += "set DB2INSTANCE=$($WorkObject.InstanceName)"
        $applyCommands += "db2 connect to $($WorkObject.DatabaseName)"

        foreach ($rf in $routineFiles) {
            $typeWord = if ($rf.Type -eq 'PROCEDURE') { 'PROCEDURE' } else { 'FUNCTION' }
            $rtCode = if ($rf.Type -eq 'PROCEDURE') { 'P' } else { 'F' }
            $applyCommands += "db2 -x `"SELECT 1 FROM SYSCAT.ROUTINES WHERE SPECIFICNAME='$($rf.Name)' AND ROUTINESCHEMA='$($rf.Schema)' AND ROUTINETYPE='$($rtCode)' FETCH FIRST 1 ROW ONLY`" >nul 2>&1 && db2 `"DROP SPECIFIC $($typeWord) \`"$($rf.Schema)\`".\`"$($rf.Name)\`"`""
            $applyCommands += "db2 -td@ -vf `"$($rf.File)`""
            $applyCommands += "db2 `"GRANT EXECUTE ON $($typeWord) \`"$($rf.Schema)\`".\`"$($rf.Name)\`" TO PUBLIC`""
        }

        $applyCommands += "db2 connect reset"

        $output = Invoke-Db2ContentAsScript -Content $applyCommands -ExecutionType BAT -IgnoreErrors -FileName (Join-Path $WorkObject.WorkFolder "RoutineSync_Apply_$($timestamp).bat")
        $WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $WorkObject -Name "RoutineSync_Apply" -Script ($applyCommands -join "`n") -Output $output

        Add-Member -InputObject $WorkObject -NotePropertyName "RoutinesAdded" -NotePropertyValue $routineFiles.Count -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "RoutinesDropped" -NotePropertyValue $routineFiles.Count -Force

        Write-LogMessage "Routine sync completed: $($routineFiles.Count) routines applied to $($WorkObject.DatabaseName)" -Level INFO
    }
    catch {
        Write-LogMessage "Error during routine sync for $($WorkObject.DatabaseName): $($_.Exception.Message)" -Level ERROR -Exception $_
        Add-Member -InputObject $WorkObject -NotePropertyName "RoutinesAdded" -NotePropertyValue 0 -Force
        Add-Member -InputObject $WorkObject -NotePropertyName "RoutinesDropped" -NotePropertyValue 0 -Force
        throw "Error during routine sync: $($_.Exception.Message)"
    }
    return $WorkObject
}

function Export-Db2GrantsViaCli {
    <#
    .SYNOPSIS
    Collects all grant data via DB2 CLI EXPORT TO DEL, bypassing ODBC.

    .DESCRIPTION
    Fallback for Export-Db2Grants when ODBC DSNs are not configured on the server.
    Runs db2 EXPORT TO <file> OF DEL for each SYSCAT grant table and parses the
    resulting comma-delimited files into PSCustomObjects matching the ODBC output format.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    $tempDir = Join-Path $env:TEMP "Db2GrantExport_$($DatabaseName)_$(Get-Date -Format 'yyyyMMddHHmmssfff')"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    $grantQueries = @{
        DatabaseGrants = @{
            File    = Join-Path $tempDir "dbauth.del"
            Headers = @("DATABASE_NAME","GRANTEE","GRANTEETYPE","GRANTOR","GRANTORTYPE","CONNECTAUTH","CREATETABAUTH","DBADMAUTH","EXTERNALROUTINEAUTH","IMPLSCHEMAAUTH","LOADAUTH","NOFENCEAUTH","QUIESCECONNECTAUTH","BINDADDAUTH","DATAACCESSAUTH","ACCESSCTRLAUTH","SECURITYADMAUTH","SQLADMAUTH","WLMADMAUTH","EXPLAINAUTH")
            Sql     = "SELECT '$DatabaseName',GRANTEE,GRANTEETYPE,GRANTOR,GRANTORTYPE,CONNECTAUTH,CREATETABAUTH,DBADMAUTH,EXTERNALROUTINEAUTH,IMPLSCHEMAAUTH,LOADAUTH,NOFENCEAUTH,QUIESCECONNECTAUTH,BINDADDAUTH,DATAACCESSAUTH,ACCESSCTRLAUTH,SECURITYADMAUTH,SQLADMAUTH,WLMADMAUTH,EXPLAINAUTH FROM SYSCAT.DBAUTH ORDER BY GRANTEE"
        }
        TableGrants = @{
            File    = Join-Path $tempDir "tabauth.del"
            Headers = @("DATABASE_NAME","TABSCHEMA","TABNAME","TYPE","GRANTEE","GRANTEETYPE","GRANTOR","GRANTORTYPE","SELECTAUTH","INSERTAUTH","UPDATEAUTH","DELETEAUTH","ALTERAUTH","INDEXAUTH","REFAUTH","CONTROLAUTH")
            Sql     = "SELECT '$DatabaseName',T.TABSCHEMA,T.TABNAME,T.TYPE,A.GRANTEE,A.GRANTEETYPE,A.GRANTOR,A.GRANTORTYPE,A.SELECTAUTH,A.INSERTAUTH,A.UPDATEAUTH,A.DELETEAUTH,A.ALTERAUTH,A.INDEXAUTH,A.REFAUTH,A.CONTROLAUTH FROM SYSCAT.TABAUTH A INNER JOIN SYSCAT.TABLES T ON A.TABSCHEMA=T.TABSCHEMA AND A.TABNAME=T.TABNAME WHERE T.TYPE IN ('T','V') ORDER BY T.TABSCHEMA,T.TABNAME,A.GRANTEE"
        }
        RoutineGrants = @{
            File    = Join-Path $tempDir "routineauth.del"
            Headers = @("DATABASE_NAME","ROUTINESCHEMA","ROUTINENAME","ROUTINETYPE","GRANTEE","GRANTEETYPE","GRANTOR","GRANTORTYPE","EXECUTEAUTH")
            Sql     = "SELECT '$DatabaseName',R.ROUTINESCHEMA,R.ROUTINENAME,R.ROUTINETYPE,A.GRANTEE,A.GRANTEETYPE,A.GRANTOR,A.GRANTORTYPE,A.EXECUTEAUTH FROM SYSCAT.ROUTINEAUTH A INNER JOIN SYSCAT.ROUTINES R ON A.SCHEMA=R.ROUTINESCHEMA AND A.SPECIFICNAME=R.SPECIFICNAME WHERE R.ROUTINETYPE IN ('F','P') ORDER BY R.ROUTINESCHEMA,R.ROUTINENAME,A.GRANTEE"
        }
        SchemaGrants = @{
            File    = Join-Path $tempDir "schemaauth.del"
            Headers = @("DATABASE_NAME","SCHEMANAME","GRANTEE","GRANTEETYPE","GRANTOR","GRANTORTYPE","CREATEINAUTH","ALTERINAUTH","DROPINAUTH")
            Sql     = "SELECT '$DatabaseName',S.SCHEMANAME,A.GRANTEE,A.GRANTEETYPE,A.GRANTOR,A.GRANTORTYPE,A.CREATEINAUTH,A.ALTERINAUTH,A.DROPINAUTH FROM SYSCAT.SCHEMAAUTH A INNER JOIN SYSCAT.SCHEMATA S ON A.SCHEMANAME=S.SCHEMANAME ORDER BY S.SCHEMANAME,A.GRANTEE"
        }
        PackageGrants = @{
            File    = Join-Path $tempDir "packageauth.del"
            Headers = @("DATABASE_NAME","PKGSCHEMA","PKGNAME","GRANTEE","GRANTEETYPE","GRANTOR","GRANTORTYPE","CONTROLAUTH","BINDAUTH","EXECUTEAUTH")
            Sql     = "SELECT '$DatabaseName',P.PKGSCHEMA,P.PKGNAME,A.GRANTEE,A.GRANTEETYPE,A.GRANTOR,A.GRANTORTYPE,A.CONTROLAUTH,A.BINDAUTH,A.EXECUTEAUTH FROM SYSCAT.PACKAGEAUTH A INNER JOIN SYSCAT.PACKAGES P ON A.PKGSCHEMA=P.PKGSCHEMA AND A.PKGNAME=P.PKGNAME ORDER BY P.PKGSCHEMA,P.PKGNAME,A.GRANTEE"
        }
        IndexGrants = @{
            File    = Join-Path $tempDir "indexauth.del"
            Headers = @("DATABASE_NAME","INDSCHEMA","INDNAME","TABSCHEMA","TABNAME","GRANTEE","GRANTEETYPE","GRANTOR","GRANTORTYPE","CONTROLAUTH")
            Sql     = "SELECT '$DatabaseName',I.INDSCHEMA,I.INDNAME,I.TABSCHEMA,I.TABNAME,A.GRANTEE,A.GRANTEETYPE,A.GRANTOR,A.GRANTORTYPE,A.CONTROLAUTH FROM SYSCAT.INDEXAUTH A INNER JOIN SYSCAT.INDEXES I ON A.INDSCHEMA=I.INDSCHEMA AND A.INDNAME=I.INDNAME ORDER BY I.INDSCHEMA,I.INDNAME,A.GRANTEE"
        }
    }

    # Run each EXPORT in its own connect block so failures are isolated
    foreach ($entry in $grantQueries.GetEnumerator()) {
        $delFile = $entry.Value.File -replace '\\', '/'
        $grantType = $entry.Key
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$InstanceName"
        $db2Commands += "db2 connect to $DatabaseName"
        $db2Commands += "db2 `"EXPORT TO '$delFile' OF DEL $($entry.Value.Sql)`""
        $db2Commands += "db2 connect reset"

        $batFile = Join-Path $tempDir "export_$($grantType).bat"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName $batFile -Quiet
        Write-LogMessage "CLI EXPORT $grantType output: $output" -Level INFO
    }

    # Parse each DEL file into PSCustomObjects
    $result = [PSCustomObject]@{
        DatabaseGrants = @()
        TableGrants    = @()
        RoutineGrants  = @()
        SchemaGrants   = @()
        PackageGrants  = @()
        IndexGrants    = @()
    }

    foreach ($entry in $grantQueries.GetEnumerator()) {
        $delFile = $entry.Value.File
        $headers = $entry.Value.Headers
        $grantType = $entry.Key

        if (-not (Test-Path $delFile)) {
            Write-LogMessage "DEL file not found for $grantType — retrying with db2 -x tab-delimited fallback" -Level WARN
            $tabSql = $entry.Value.Sql
            # Replace SELECT col,col,... with SELECT RTRIM(col)||CHR(9)||RTRIM(col)...
            if ($tabSql -match '^SELECT\s+(.+?)\s+FROM\s+(.+)$') {
                $colPart = $Matches[1]
                $fromPart = $Matches[2]
                $cols = $colPart -split ',' | ForEach-Object { $_.Trim() }
                $tabColExpr = ($cols | ForEach-Object { "RTRIM(COALESCE(CHAR($_),' '))" }) -join " || CHR(9) || "
                $tabQuery = "SELECT $tabColExpr FROM $fromPart"
            }
            else {
                Write-LogMessage "Could not parse SQL for tab fallback on $grantType" -Level ERROR
                continue
            }

            $fbCommands = @()
            $fbCommands += "set DB2INSTANCE=$InstanceName"
            $fbCommands += "db2 connect to $DatabaseName"
            $fbCommands += "db2 -x `"$tabQuery`""
            $fbCommands += "db2 connect reset"
            $fbBat = Join-Path $tempDir "fallback_$($grantType).bat"
            $fbOutput = Invoke-Db2ContentAsScript -Content $fbCommands -ExecutionType BAT -IgnoreErrors -FileName $fbBat
            Write-LogMessage "Fallback output for $grantType`: $fbOutput" -Level DEBUG

            $objects = @()
            if ($fbOutput) {
                $fbLines = ($fbOutput -split "`n") | Where-Object {
                    $trimmed = $_.Trim()
                    -not [string]::IsNullOrWhiteSpace($trimmed) -and
                    $trimmed -notmatch '^(DB2\d|SQL\d|Datab|C:\\|set |db2 |$)' -and
                    $trimmed -notmatch '^\-+$' -and
                    $trimmed -notmatch '^(Tilkoplingsinfo|Autorisasjons|Lokalt|CONNECT RESET)'
                }
                foreach ($fbLine in $fbLines) {
                    $values = $fbLine -split "`t"
                    if ($values.Count -ge $headers.Count) {
                        $obj = [PSCustomObject]@{}
                        for ($i = 0; $i -lt $headers.Count; $i++) {
                            $obj | Add-Member -NotePropertyName $headers[$i] -NotePropertyValue $values[$i].Trim()
                        }
                        $objects += $obj
                    }
                }
            }
            $result.$grantType = $objects
            Write-LogMessage "CLI fallback: $grantType = $($objects.Count) records" -Level INFO
            continue
        }

        $lines = Get-Content -Path $delFile -Encoding utf8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $objects = @()
        foreach ($line in $lines) {
            $values = @()
            # Regex: each field is "value" separated by commas in DB2 DEL format
            $fieldMatches = [regex]::Matches($line, '"([^"]*)"')
            if ($fieldMatches.Count -eq $headers.Count) {
                foreach ($m in $fieldMatches) { $values += $m.Groups[1].Value }
            }
            else {
                $values = $line -split ',' | ForEach-Object { $_.Trim('"', ' ') }
            }

            if ($values.Count -ge $headers.Count) {
                $obj = [PSCustomObject]@{}
                for ($i = 0; $i -lt $headers.Count; $i++) {
                    $obj | Add-Member -NotePropertyName $headers[$i] -NotePropertyValue $values[$i]
                }
                $objects += $obj
            }
        }

        $result.$grantType = $objects
        Write-LogMessage "CLI export: $grantType = $($objects.Count) records from $delFile" -Level INFO
    }

    # Cleanup temp directory
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    return $result
}

function Export-Db2Grants {
    <#
    .SYNOPSIS
    Exports all database grants to a JSON file that can be used to recreate them.
    
    .DESCRIPTION
    Collects all grant types (database, table, routine, schema, package, index) from the
    specified database and writes them to a JSON file. The file is named using the PrimaryDb
    name from DatabasesV2.json and a timestamp.
    
    .PARAMETER DatabaseName
    The catalog name of the database to export grants from (e.g. FKMTST, XFKMTST)
    
    .PARAMETER OutputFolder
    Folder to write the JSON file to. Defaults to C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants
    
    .EXAMPLE
    Export-Db2Grants -DatabaseName "FKMTST"
    
    .EXAMPLE
    Export-Db2Grants -DatabaseName "XFKMTST" -OutputFolder "C:\temp\grants"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFolder = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants"
    )
    
    try {
        Write-LogMessage "Exporting grants for database $DatabaseName" -Level INFO
        
        # Resolve database config to get PrimaryDb name and instance
        $dbConfig = Get-DatabaseConfigFromDatabaseName -DatabaseName $DatabaseName
        $primaryDbName = $dbConfig.Database
        $instanceName = $dbConfig.InstanceName
        $serverName = $dbConfig.ServerName
        
        Write-LogMessage "Resolved: PrimaryDb=$($primaryDbName), Instance=$($instanceName), Server=$($serverName)" -Level INFO
        
        # Try ODBC first, fall back to DB2 CLI EXPORT TO DEL if ODBC returns empty (no DSN configured)
        $allGrants = Get-Db2AllGrants -DatabaseName $DatabaseName
        $totalFromOdbc = $allGrants.DatabaseGrants.Count + $allGrants.TableGrants.Count + $allGrants.RoutineGrants.Count + $allGrants.SchemaGrants.Count + $allGrants.PackageGrants.Count + $allGrants.IndexGrants.Count

        if ($totalFromOdbc -eq 0 -and (Test-IsDb2Server)) {
            Write-LogMessage "ODBC returned 0 grants — falling back to DB2 CLI EXPORT TO DEL" -Level WARN
            $allGrants = Export-Db2GrantsViaCli -DatabaseName $DatabaseName -InstanceName $instanceName
        }
        
        # Build export object with metadata
        $exportObject = [PSCustomObject]@{
            ExportMetadata = [PSCustomObject]@{
                DatabaseName    = $DatabaseName
                PrimaryDbName   = $primaryDbName
                ServerName      = $serverName
                InstanceName    = $instanceName
                ExportTimestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                ExportedBy      = $env:USERNAME
            }
            DatabaseGrants = $allGrants.DatabaseGrants
            TableGrants    = $allGrants.TableGrants
            RoutineGrants  = $allGrants.RoutineGrants
            SchemaGrants   = $allGrants.SchemaGrants
            PackageGrants  = $allGrants.PackageGrants
            IndexGrants    = $allGrants.IndexGrants
        }
        
        # Ensure output folder exists
        if (-not (Test-Path $OutputFolder)) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created output folder: $OutputFolder" -Level INFO
        }
        
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $fileName = Join-Path $OutputFolder "$($primaryDbName)_$($timestamp).json"
        
        $exportObject | ConvertTo-Json -Depth 10 | Set-Content -Path $fileName -Encoding utf8
        
        $totalGrants = $allGrants.DatabaseGrants.Count + $allGrants.TableGrants.Count + $allGrants.RoutineGrants.Count + $allGrants.SchemaGrants.Count + $allGrants.PackageGrants.Count + $allGrants.IndexGrants.Count
        Write-LogMessage "Exported $($totalGrants) grants to $fileName (DB=$($allGrants.DatabaseGrants.Count), Table=$($allGrants.TableGrants.Count), Routine=$($allGrants.RoutineGrants.Count), Schema=$($allGrants.SchemaGrants.Count), Package=$($allGrants.PackageGrants.Count), Index=$($allGrants.IndexGrants.Count))" -Level INFO
        
        return $fileName
    }
    catch {
        Write-LogMessage "Error exporting grants for database $DatabaseName`: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Error exporting grants for database $DatabaseName`: $($_.Exception.Message)"
    }
}

function Import-Db2Grants {
    <#
    .SYNOPSIS
    Imports database grants from a previously exported JSON file.
    
    .DESCRIPTION
    Reads a JSON grant export file and re-applies all grants to the target database.
    Supports lookup by database name (finds newest export file) or by explicit file path.
    Grant operations are idempotent — duplicate grants produce warnings, not errors.
    
    .PARAMETER DatabaseName
    The catalog name of the target database (e.g. XFKMTST, FKMTST). 
    Used to resolve the instance and to find the newest export file.
    
    .PARAMETER FilePath
    Full path to a specific JSON export file. Overrides automatic file lookup.
    
    .EXAMPLE
    Import-Db2Grants -DatabaseName "XFKMTST"
    
    .EXAMPLE
    Import-Db2Grants -FilePath "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants\FKMTST_20260313-150000.json"
    
    .EXAMPLE
    Import-Db2Grants -DatabaseName "FKMTST" -FilePath "C:\temp\grants\FKMTST_20260313-150000.json"
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$GrantFolder = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants"
    )
    
    try {
        if ([string]::IsNullOrEmpty($DatabaseName) -and [string]::IsNullOrEmpty($FilePath)) {
            throw "Either -DatabaseName or -FilePath must be specified"
        }
        
        # Resolve the JSON file to import
        if (-not [string]::IsNullOrEmpty($FilePath)) {
            if (-not (Test-Path $FilePath)) {
                throw "Grant file not found: $FilePath"
            }
            $importFile = $FilePath
        }
        else {
            # Find newest file matching the database's PrimaryDb name
            $dbConfig = Get-DatabaseConfigFromDatabaseName -DatabaseName $DatabaseName
            $primaryDbName = $dbConfig.Database
            Write-LogMessage "Looking for newest grant export for PrimaryDb=$($primaryDbName) in $GrantFolder" -Level INFO
            
            $matchingFiles = Get-ChildItem -Path $GrantFolder -Filter "$($primaryDbName)_*.json" -ErrorAction Stop | Sort-Object LastWriteTime -Descending
            if ($matchingFiles.Count -eq 0) {
                throw "No grant export files found for $($primaryDbName) in $GrantFolder"
            }
            $importFile = $matchingFiles[0].FullName
            Write-LogMessage "Found $($matchingFiles.Count) export file(s), using newest: $importFile" -Level INFO
        }
        
        # Read and parse the JSON file
        $jsonContent = Get-Content -Path $importFile -Raw -Encoding utf8 | ConvertFrom-Json
        Write-LogMessage "Loaded grant export from $importFile (exported $($jsonContent.ExportMetadata.ExportTimestamp) by $($jsonContent.ExportMetadata.ExportedBy))" -Level INFO
        
        # Resolve target database instance
        $targetDb = if (-not [string]::IsNullOrEmpty($DatabaseName)) { $DatabaseName } else { $jsonContent.ExportMetadata.DatabaseName }
        $targetConfig = Get-DatabaseConfigFromDatabaseName -DatabaseName $targetDb
        $targetInstance = $targetConfig.InstanceName
        
        Write-LogMessage "Importing grants to database $targetDb on instance $targetInstance" -Level INFO
        
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$targetInstance"
        $db2Commands += "db2 connect to $targetDb"
        
        $grantCount = 0
        
        # Database-level grants
        foreach ($g in $jsonContent.DatabaseGrants) {
            $grantee = $g.GRANTEE.Trim()
            $granteeClause = Get-GranteeClause -Grantee $grantee -GranteeType $g.GRANTEETYPE
            
            $dbPrivileges = @()
            if ($g.CONNECTAUTH -eq 'Y') { $dbPrivileges += "CONNECT" }
            if ($g.CREATETABAUTH -eq 'Y') { $dbPrivileges += "CREATETAB" }
            if ($g.DBADMAUTH -eq 'Y') { $dbPrivileges += "DBADM" }
            if ($g.EXTERNALROUTINEAUTH -eq 'Y') { $dbPrivileges += "CREATE_EXTERNAL_ROUTINE" }
            if ($g.IMPLSCHEMAAUTH -eq 'Y') { $dbPrivileges += "IMPLICIT_SCHEMA" }
            if ($g.LOADAUTH -eq 'Y') { $dbPrivileges += "LOAD" }
            if ($g.NOFENCEAUTH -eq 'Y') { $dbPrivileges += "CREATE_NOT_FENCED_ROUTINE" }
            if ($g.QUIESCECONNECTAUTH -eq 'Y') { $dbPrivileges += "QUIESCE_CONNECT" }
            if ($g.BINDADDAUTH -eq 'Y') { $dbPrivileges += "BINDADD" }
            if ($g.DATAACCESSAUTH -eq 'Y') { $dbPrivileges += "DATAACCESS" }
            if ($g.ACCESSCTRLAUTH -eq 'Y') { $dbPrivileges += "ACCESSCTRL" }
            if ($g.SECURITYADMAUTH -eq 'Y') { $dbPrivileges += "SECADM" }
            
            foreach ($priv in $dbPrivileges) {
                $db2Commands += "db2 `"GRANT $priv ON DATABASE TO $granteeClause`""
                $grantCount++
            }
        }
        
        # Table grants
        foreach ($g in $jsonContent.TableGrants) {
            $grantee = $g.GRANTEE.Trim()
            $granteeClause = Get-GranteeClause -Grantee $grantee -GranteeType $g.GRANTEETYPE
            $qualifiedName = "$($g.TABSCHEMA.Trim()).$($g.TABNAME.Trim())"
            
            $tablePrivs = @()
            if ($g.SELECTAUTH -eq 'Y') { $tablePrivs += "SELECT" }
            if ($g.INSERTAUTH -eq 'Y') { $tablePrivs += "INSERT" }
            if ($g.UPDATEAUTH -eq 'Y') { $tablePrivs += "UPDATE" }
            if ($g.DELETEAUTH -eq 'Y') { $tablePrivs += "DELETE" }
            if ($g.ALTERAUTH -eq 'Y') { $tablePrivs += "ALTER" }
            if ($g.INDEXAUTH -eq 'Y') { $tablePrivs += "INDEX" }
            if ($g.REFAUTH -eq 'Y') { $tablePrivs += "REFERENCES" }
            if ($g.CONTROLAUTH -eq 'Y') { $tablePrivs += "CONTROL" }
            
            if ($tablePrivs.Count -gt 0) {
                $privList = $tablePrivs -join ", "
                $db2Commands += "db2 `"GRANT $privList ON $qualifiedName TO $granteeClause`""
                $grantCount++
            }
        }
        
        # Routine grants
        foreach ($g in $jsonContent.RoutineGrants) {
            $grantee = $g.GRANTEE.Trim()
            $granteeClause = Get-GranteeClause -Grantee $grantee -GranteeType $g.GRANTEETYPE
            $routineType = if ($g.ROUTINETYPE.Trim() -eq 'P') { "PROCEDURE" } else { "FUNCTION" }
            $qualifiedName = "$($g.ROUTINESCHEMA.Trim()).$($g.ROUTINENAME.Trim())"
            
            if ($g.EXECUTEAUTH -eq 'Y') {
                $db2Commands += "db2 `"GRANT EXECUTE ON $routineType $qualifiedName TO $granteeClause`""
                $grantCount++
            }
        }
        
        # Schema grants
        foreach ($g in $jsonContent.SchemaGrants) {
            $grantee = $g.GRANTEE.Trim()
            $granteeClause = Get-GranteeClause -Grantee $grantee -GranteeType $g.GRANTEETYPE
            $schemaName = $g.SCHEMANAME.Trim()
            
            $schemaPrivs = @()
            if ($g.CREATEINAUTH -eq 'Y') { $schemaPrivs += "CREATEIN" }
            if ($g.ALTERINAUTH -eq 'Y') { $schemaPrivs += "ALTERIN" }
            if ($g.DROPINAUTH -eq 'Y') { $schemaPrivs += "DROPIN" }
            
            foreach ($priv in $schemaPrivs) {
                $db2Commands += "db2 `"GRANT $priv ON SCHEMA $schemaName TO $granteeClause`""
                $grantCount++
            }
        }
        
        # Package grants
        foreach ($g in $jsonContent.PackageGrants) {
            $grantee = $g.GRANTEE.Trim()
            $granteeClause = Get-GranteeClause -Grantee $grantee -GranteeType $g.GRANTEETYPE
            $qualifiedName = "$($g.PKGSCHEMA.Trim()).$($g.PKGNAME.Trim())"
            
            $pkgPrivs = @()
            if ($g.CONTROLAUTH -eq 'Y') { $pkgPrivs += "CONTROL" }
            if ($g.BINDAUTH -eq 'Y') { $pkgPrivs += "BIND" }
            if ($g.EXECUTEAUTH -eq 'Y') { $pkgPrivs += "EXECUTE" }
            
            if ($pkgPrivs.Count -gt 0) {
                $privList = $pkgPrivs -join ", "
                $db2Commands += "db2 `"GRANT $privList ON PACKAGE $qualifiedName TO $granteeClause`""
                $grantCount++
            }
        }
        
        # Index grants
        foreach ($g in $jsonContent.IndexGrants) {
            $grantee = $g.GRANTEE.Trim()
            $granteeClause = Get-GranteeClause -Grantee $grantee -GranteeType $g.GRANTEETYPE
            $qualifiedName = "$($g.INDSCHEMA.Trim()).$($g.INDNAME.Trim())"
            
            if ($g.CONTROLAUTH -eq 'Y') {
                $db2Commands += "db2 `"GRANT CONTROL ON INDEX $qualifiedName TO $granteeClause`""
                $grantCount++
            }
        }
        
        $db2Commands += "db2 commit work"
        $db2Commands += "db2 connect reset"
        
        Write-LogMessage "Generated $grantCount GRANT commands for $targetDb" -Level INFO
        
        # Execute all grant commands
        $workFolder = Join-Path $env:OptPath "data\Db2-GrantHandler"
        if (-not (Test-Path $workFolder)) {
            New-Item -Path $workFolder -ItemType Directory -Force | Out-Null
        }
        
        $fileName = Join-Path $workFolder "ImportGrants_$($targetDb)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName $fileName
        
        Write-LogMessage "Grant import completed for $targetDb`: $grantCount grant commands executed from $importFile" -Level INFO
        
        return [PSCustomObject]@{
            DatabaseName = $targetDb
            SourceFile   = $importFile
            GrantCount   = $grantCount
            Output       = $output
        }
    }
    catch {
        Write-LogMessage "Error importing grants: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Error importing grants: $($_.Exception.Message)"
    }
}

function Import-Db2GrantsAsRoles {
    <#
    .SYNOPSIS
    Imports grants from an export JSON and converts them to role-based privileges.

    .DESCRIPTION
    Reads a standard grant export JSON (produced by Export-Db2Grants), auto-derives
    DB2 roles from the privilege patterns, and replaces direct user/group grants with
    role-based grants. Grantees with identical privilege fingerprints share a single role.

    This function is ONLY called when Db2-GrantsImport.ps1 is invoked with
    -UseNewConfigurations:$true. It does not affect any other code path.

    PUBLIC grants are preserved as-is (PUBLIC cannot receive role membership in DB2).
    System accounts (SYSIBM, SYSIBMINTERNAL) are skipped.

    .PARAMETER DatabaseName
    The catalog name of the target database (e.g. XFKMTST, FKMTST).
    Used to resolve the instance and to find the newest export file.

    .PARAMETER FilePath
    Full path to a specific JSON export file. Overrides automatic file lookup.

    .PARAMETER GrantFolder
    Folder to search for export files. Defaults to C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants

    .EXAMPLE
    Import-Db2GrantsAsRoles -DatabaseName "FKMTST"

    .EXAMPLE
    Import-Db2GrantsAsRoles -FilePath "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants\FKMTST_20260313-150000.json"
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $false)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string]$GrantFolder = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants"
    )

    # System grantees whose grants are DB2-internal and must never be touched
    $systemGrantees = @("SYSIBM", "SYSIBMINTERNAL")

    try {
        if ([string]::IsNullOrEmpty($DatabaseName) -and [string]::IsNullOrEmpty($FilePath)) {
            throw "Either -DatabaseName or -FilePath must be specified"
        }

        # ── Resolve the JSON file ──────────────────────────────────────────────
        if (-not [string]::IsNullOrEmpty($FilePath)) {
            if (-not (Test-Path $FilePath)) {
                throw "Grant file not found: $FilePath"
            }
            $importFile = $FilePath
        }
        else {
            $dbConfig = Get-DatabaseConfigFromDatabaseName -DatabaseName $DatabaseName
            $primaryDbName = $dbConfig.Database
            Write-LogMessage "Looking for newest grant export for PrimaryDb=$($primaryDbName) in $GrantFolder" -Level INFO
            $matchingFiles = Get-ChildItem -Path $GrantFolder -Filter "$($primaryDbName)_*.json" -ErrorAction Stop | Sort-Object LastWriteTime -Descending
            if ($matchingFiles.Count -eq 0) {
                throw "No grant export files found for $($primaryDbName) in $GrantFolder"
            }
            $importFile = $matchingFiles[0].FullName
            Write-LogMessage "Found $($matchingFiles.Count) export file(s), using newest: $importFile" -Level INFO
        }

        $jsonContent = Get-Content -Path $importFile -Raw -Encoding utf8 | ConvertFrom-Json
        Write-LogMessage "Loaded grant export from $importFile (exported $($jsonContent.ExportMetadata.ExportTimestamp) by $($jsonContent.ExportMetadata.ExportedBy))" -Level INFO

        # ── Resolve target database and instance ───────────────────────────────
        $targetDb = if (-not [string]::IsNullOrEmpty($DatabaseName)) { $DatabaseName } else { $jsonContent.ExportMetadata.DatabaseName }
        $targetConfig = Get-DatabaseConfigFromDatabaseName -DatabaseName $targetDb
        $targetInstance = $targetConfig.InstanceName

        Write-LogMessage "Import-Db2GrantsAsRoles: Converting direct grants to role-based for $targetDb on $targetInstance" -Level INFO

        # ── Phase 1: Build per-grantee fingerprints ────────────────────────────
        $granteeMap = @{}

        foreach ($g in $jsonContent.DatabaseGrants) {
            $grantee = $g.GRANTEE.Trim()
            if ($grantee.ToUpper() -eq "PUBLIC" -or $grantee.ToUpper() -in $systemGrantees) { continue }
            $granteeType = if ($g.PSObject.Properties['GRANTEETYPE']) { $g.GRANTEETYPE.Trim() } else { "" }
            $key = "$($granteeType)|$($grantee)"
            if (-not $granteeMap.ContainsKey($key)) {
                $granteeMap[$key] = @{ Grantee = $grantee; GranteeType = $granteeType; DatabaseGrants = @(); TableGrants = @(); RoutineGrants = @(); SchemaGrants = @(); PackageGrants = @(); IndexGrants = @() }
            }
            $granteeMap[$key].DatabaseGrants += $g
        }

        foreach ($g in $jsonContent.TableGrants) {
            $grantee = $g.GRANTEE.Trim()
            if ($grantee.ToUpper() -eq "PUBLIC" -or $grantee.ToUpper() -in $systemGrantees) { continue }
            $granteeType = if ($g.PSObject.Properties['GRANTEETYPE']) { $g.GRANTEETYPE.Trim() } else { "" }
            $key = "$($granteeType)|$($grantee)"
            if (-not $granteeMap.ContainsKey($key)) {
                $granteeMap[$key] = @{ Grantee = $grantee; GranteeType = $granteeType; DatabaseGrants = @(); TableGrants = @(); RoutineGrants = @(); SchemaGrants = @(); PackageGrants = @(); IndexGrants = @() }
            }
            $granteeMap[$key].TableGrants += $g
        }

        foreach ($g in $jsonContent.RoutineGrants) {
            $grantee = $g.GRANTEE.Trim()
            if ($grantee.ToUpper() -eq "PUBLIC" -or $grantee.ToUpper() -in $systemGrantees) { continue }
            $granteeType = if ($g.PSObject.Properties['GRANTEETYPE']) { $g.GRANTEETYPE.Trim() } else { "" }
            $key = "$($granteeType)|$($grantee)"
            if (-not $granteeMap.ContainsKey($key)) {
                $granteeMap[$key] = @{ Grantee = $grantee; GranteeType = $granteeType; DatabaseGrants = @(); TableGrants = @(); RoutineGrants = @(); SchemaGrants = @(); PackageGrants = @(); IndexGrants = @() }
            }
            $granteeMap[$key].RoutineGrants += $g
        }

        foreach ($g in $jsonContent.SchemaGrants) {
            $grantee = $g.GRANTEE.Trim()
            if ($grantee.ToUpper() -eq "PUBLIC" -or $grantee.ToUpper() -in $systemGrantees) { continue }
            $granteeType = if ($g.PSObject.Properties['GRANTEETYPE']) { $g.GRANTEETYPE.Trim() } else { "" }
            $key = "$($granteeType)|$($grantee)"
            if (-not $granteeMap.ContainsKey($key)) {
                $granteeMap[$key] = @{ Grantee = $grantee; GranteeType = $granteeType; DatabaseGrants = @(); TableGrants = @(); RoutineGrants = @(); SchemaGrants = @(); PackageGrants = @(); IndexGrants = @() }
            }
            $granteeMap[$key].SchemaGrants += $g
        }

        foreach ($g in $jsonContent.PackageGrants) {
            $grantee = $g.GRANTEE.Trim()
            if ($grantee.ToUpper() -eq "PUBLIC" -or $grantee.ToUpper() -in $systemGrantees) { continue }
            $granteeType = if ($g.PSObject.Properties['GRANTEETYPE']) { $g.GRANTEETYPE.Trim() } else { "" }
            $key = "$($granteeType)|$($grantee)"
            if (-not $granteeMap.ContainsKey($key)) {
                $granteeMap[$key] = @{ Grantee = $grantee; GranteeType = $granteeType; DatabaseGrants = @(); TableGrants = @(); RoutineGrants = @(); SchemaGrants = @(); PackageGrants = @(); IndexGrants = @() }
            }
            $granteeMap[$key].PackageGrants += $g
        }

        foreach ($g in $jsonContent.IndexGrants) {
            $grantee = $g.GRANTEE.Trim()
            if ($grantee.ToUpper() -eq "PUBLIC" -or $grantee.ToUpper() -in $systemGrantees) { continue }
            $granteeType = if ($g.PSObject.Properties['GRANTEETYPE']) { $g.GRANTEETYPE.Trim() } else { "" }
            $key = "$($granteeType)|$($grantee)"
            if (-not $granteeMap.ContainsKey($key)) {
                $granteeMap[$key] = @{ Grantee = $grantee; GranteeType = $granteeType; DatabaseGrants = @(); TableGrants = @(); RoutineGrants = @(); SchemaGrants = @(); PackageGrants = @(); IndexGrants = @() }
            }
            $granteeMap[$key].IndexGrants += $g
        }

        Write-LogMessage "Built fingerprints for $($granteeMap.Count) grantees" -Level INFO

        # ── Phase 2: Compute fingerprint hash and classify ─────────────────────
        # The fingerprint hash is a deterministic string derived from all privileges.
        # Grantees with identical hashes share a role.
        # IMPORTANT: DBADM implicitly provides all table, routine, schema, package,
        # and index privileges. When a user has DBADM, only database-level flags
        # are included in the fingerprint. This ensures all DBADM holders share
        # the same FK_DBA role regardless of any additional explicit grants.
        $fingerprintGroups = @{}

        foreach ($entry in $granteeMap.GetEnumerator()) {
            $fp = $entry.Value
            $hashParts = @()

            # Database-level privileges (sorted columns)
            $isDbadmHolder = $false
            foreach ($dbg in ($fp.DatabaseGrants | Sort-Object { "$($_.GRANTEE)" })) {
                $dbFlags = @()
                foreach ($col in @('CONNECTAUTH','CREATETABAUTH','DBADMAUTH','EXTERNALROUTINEAUTH','IMPLSCHEMAAUTH','LOADAUTH','NOFENCEAUTH','QUIESCECONNECTAUTH','BINDADDAUTH','DATAACCESSAUTH','ACCESSCTRLAUTH','SECURITYADMAUTH','SQLADMAUTH','WLMADMAUTH','EXPLAINAUTH')) {
                    if ($dbg.PSObject.Properties[$col] -and $dbg.$col -eq 'Y') { $dbFlags += $col }
                }
                if ($dbFlags -contains 'DBADMAUTH') { $isDbadmHolder = $true }
                if ($dbFlags.Count -gt 0) { $hashParts += "DB:$($dbFlags -join ',')" }
            }

            # DBADM grants implicit access to all tables, routines, schemas, packages,
            # and indexes. Skip lower-level grants in the fingerprint so that all DBADM
            # holders (FKPRDADM, FKTSTADM, FKGEISTA, FKSVEERI, etc.) get the same hash
            # and share the FK_DBA role, even if some have additional explicit grants.
            if (-not $isDbadmHolder) {
                # Table-level privileges (sorted by schema.table)
                foreach ($tg in ($fp.TableGrants | Sort-Object { "$($_.TABSCHEMA.Trim()).$($_.TABNAME.Trim())" })) {
                    $tblFlags = @()
                    foreach ($col in @('SELECTAUTH','INSERTAUTH','UPDATEAUTH','DELETEAUTH','ALTERAUTH','INDEXAUTH','REFAUTH','CONTROLAUTH')) {
                        if ($tg.PSObject.Properties[$col] -and $tg.$col -eq 'Y') { $tblFlags += $col }
                    }
                    if ($tblFlags.Count -gt 0) { $hashParts += "TBL:$($tg.TABSCHEMA.Trim()).$($tg.TABNAME.Trim()):$($tblFlags -join ',')" }
                }

                # Routine-level privileges (sorted by schema.routine)
                foreach ($rg in ($fp.RoutineGrants | Sort-Object { "$($_.ROUTINESCHEMA.Trim()).$($_.ROUTINENAME.Trim())" })) {
                    if ($rg.PSObject.Properties['EXECUTEAUTH'] -and $rg.EXECUTEAUTH -eq 'Y') {
                        $rType = if ($rg.ROUTINETYPE.Trim() -eq 'P') { 'PROC' } else { 'FUNC' }
                        $hashParts += "RTN:$($rType):$($rg.ROUTINESCHEMA.Trim()).$($rg.ROUTINENAME.Trim())"
                    }
                }

                # Schema-level privileges
                foreach ($sg in ($fp.SchemaGrants | Sort-Object { $_.SCHEMANAME.Trim() })) {
                    $schFlags = @()
                    foreach ($col in @('CREATEINAUTH','ALTERINAUTH','DROPINAUTH')) {
                        if ($sg.PSObject.Properties[$col] -and $sg.$col -eq 'Y') { $schFlags += $col }
                    }
                    if ($schFlags.Count -gt 0) { $hashParts += "SCH:$($sg.SCHEMANAME.Trim()):$($schFlags -join ',')" }
                }

                # Package-level privileges
                foreach ($pg in ($fp.PackageGrants | Sort-Object { "$($_.PKGSCHEMA.Trim()).$($_.PKGNAME.Trim())" })) {
                    $pkgFlags = @()
                    foreach ($col in @('CONTROLAUTH','BINDAUTH','EXECUTEAUTH')) {
                        if ($pg.PSObject.Properties[$col] -and $pg.$col -eq 'Y') { $pkgFlags += $col }
                    }
                    if ($pkgFlags.Count -gt 0) { $hashParts += "PKG:$($pg.PKGSCHEMA.Trim()).$($pg.PKGNAME.Trim()):$($pkgFlags -join ',')" }
                }

                # Index-level privileges
                foreach ($ig in ($fp.IndexGrants | Sort-Object { "$($_.INDSCHEMA.Trim()).$($_.INDNAME.Trim())" })) {
                    if ($ig.PSObject.Properties['CONTROLAUTH'] -and $ig.CONTROLAUTH -eq 'Y') {
                        $hashParts += "IDX:$($ig.INDSCHEMA.Trim()).$($ig.INDNAME.Trim())"
                    }
                }
            }

            $fpString = $hashParts -join "|"
            $fpHash = [System.BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($fpString)
                )
            ).Replace("-", "").Substring(0, 12)

            if (-not $fingerprintGroups.ContainsKey($fpHash)) {
                $fingerprintGroups[$fpHash] = @{
                    FingerprintString = $fpString
                    Members           = @()
                    SampleGrants      = $fp
                }
            }
            $fingerprintGroups[$fpHash].Members += @{ Grantee = $fp.Grantee; GranteeType = $fp.GranteeType }
        }

        Write-LogMessage "Classified grantees into $($fingerprintGroups.Count) unique privilege groups" -Level INFO

        # ── Phase 3: Determine role names ──────────────────────────────────────
        $roleAssignments = @{}
        $usedRoleNames = @{}

        foreach ($group in $fingerprintGroups.GetEnumerator()) {
            $members = $group.Value.Members
            $sample = $group.Value.SampleGrants
            $fpStr = $group.Value.FingerprintString

            # Classify the dominant pattern
            $hasDbadm = $fpStr -match "DBADMAUTH"
            $tableEntries = ($fpStr -split '\|') | Where-Object { $_ -match "^TBL:" }
            $allSelectOnly = ($tableEntries.Count -gt 0) -and ($tableEntries | Where-Object { $_ -notmatch "SELECTAUTH" -or $_ -match "(INSERTAUTH|UPDATEAUTH|DELETEAUTH|ALTERAUTH|INDEXAUTH|REFAUTH|CONTROLAUTH)" }).Count -eq 0
            $allSiud = ($tableEntries.Count -gt 0) -and (($tableEntries | Where-Object { $_ -match "SELECTAUTH" -and $_ -match "INSERTAUTH" -and $_ -match "UPDATEAUTH" -and $_ -match "DELETEAUTH" }).Count -eq $tableEntries.Count)

            $roleName = $null
            if ($hasDbadm) {
                $candidateName = "FK_DBA"
                if ($usedRoleNames.ContainsKey($candidateName)) {
                    # Another group already took FK_DBA with a different fingerprint
                    $firstMember = ($members | Select-Object -First 1).Grantee.ToUpper()
                    $roleName = "FK_DBA_$firstMember"
                }
                else {
                    $roleName = $candidateName
                }
            }
            elseif ($allSelectOnly -and -not $allSiud) {
                $candidateName = "FK_READONLY"
                if ($usedRoleNames.ContainsKey($candidateName)) {
                    $firstMember = ($members | Select-Object -First 1).Grantee.ToUpper()
                    $roleName = "FK_READONLY_$firstMember"
                }
                else {
                    $roleName = $candidateName
                }
            }
            elseif ($allSiud) {
                $candidateName = "FK_READWRITE"
                if ($usedRoleNames.ContainsKey($candidateName)) {
                    $firstMember = ($members | Select-Object -First 1).Grantee.ToUpper()
                    $roleName = "FK_READWRITE_$firstMember"
                }
                else {
                    $roleName = $candidateName
                }
            }
            else {
                $firstMember = ($members | Select-Object -First 1).Grantee.ToUpper()
                $granteeTypeCode = ($members | Select-Object -First 1).GranteeType.Trim().ToUpper()
                # SRV_ prefix → service account role
                if ($firstMember -match "^SRV_") {
                    $svcName = $firstMember -replace "^SRV_", ""
                    $roleName = "FK_SVC_$svcName"
                }
                elseif ($granteeTypeCode -eq "G") {
                    $roleName = "FK_GRP_$firstMember"
                }
                else {
                    $roleName = "FK_CUSTOM_$firstMember"
                }
            }

            # Ensure uniqueness
            $originalName = $roleName
            $suffix = 2
            while ($usedRoleNames.ContainsKey($roleName)) {
                $roleName = "$($originalName)_$suffix"
                $suffix++
            }
            $usedRoleNames[$roleName] = $true

            $roleAssignments[$group.Key] = @{
                RoleName = $roleName
                Members  = $members
                Grants   = $sample
            }

            $memberNames = ($members | ForEach-Object { $_.Grantee }) -join ", "
            Write-LogMessage "Role $roleName -> members: $memberNames" -Level INFO
        }

        # ── Phase 4: Generate DB2 commands ─────────────────────────────────────
        $db2Commands = @()
        $db2Commands += "set DB2INSTANCE=$targetInstance"
        $db2Commands += "db2 connect to $targetDb"

        $createRoleCount = 0
        $grantToRoleCount = 0
        $membershipCount = 0
        $revokeCount = 0

        foreach ($assignment in $roleAssignments.GetEnumerator()) {
            $roleName = $assignment.Value.RoleName
            $members = $assignment.Value.Members
            $grants = $assignment.Value.Grants

            # Check if this role is for DBADM holders — DBADM implicitly covers all
            # table/routine/schema/package/index privileges, so we only need to grant
            # database-level privileges and skip the rest.
            $roleIsDbadm = $false
            foreach ($dbg in $grants.DatabaseGrants) {
                if ($dbg.PSObject.Properties['DBADMAUTH'] -and $dbg.DBADMAUTH -eq 'Y') {
                    $roleIsDbadm = $true
                    break
                }
            }

            # 4a. CREATE ROLE (idempotent — will warn SQL0601N if exists)
            $db2Commands += "db2 `"CREATE ROLE $roleName`""
            $createRoleCount++

            # 4b. GRANT privileges TO ROLE

            # Database-level grants
            foreach ($dbg in $grants.DatabaseGrants) {
                $dbPrivileges = @()
                if ($dbg.CONNECTAUTH -eq 'Y') { $dbPrivileges += "CONNECT" }
                if ($dbg.CREATETABAUTH -eq 'Y') { $dbPrivileges += "CREATETAB" }
                if ($dbg.DBADMAUTH -eq 'Y') { $dbPrivileges += "DBADM" }
                if ($dbg.EXTERNALROUTINEAUTH -eq 'Y') { $dbPrivileges += "CREATE_EXTERNAL_ROUTINE" }
                if ($dbg.IMPLSCHEMAAUTH -eq 'Y') { $dbPrivileges += "IMPLICIT_SCHEMA" }
                if ($dbg.LOADAUTH -eq 'Y') { $dbPrivileges += "LOAD" }
                if ($dbg.NOFENCEAUTH -eq 'Y') { $dbPrivileges += "CREATE_NOT_FENCED_ROUTINE" }
                if ($dbg.QUIESCECONNECTAUTH -eq 'Y') { $dbPrivileges += "QUIESCE_CONNECT" }
                if ($dbg.BINDADDAUTH -eq 'Y') { $dbPrivileges += "BINDADD" }
                if ($dbg.DATAACCESSAUTH -eq 'Y') { $dbPrivileges += "DATAACCESS" }
                if ($dbg.ACCESSCTRLAUTH -eq 'Y') { $dbPrivileges += "ACCESSCTRL" }
                if ($dbg.SECURITYADMAUTH -eq 'Y') { $dbPrivileges += "SECADM" }
                if ($dbg.PSObject.Properties['SQLADMAUTH'] -and $dbg.SQLADMAUTH -eq 'Y') { $dbPrivileges += "SQLADM" }
                if ($dbg.PSObject.Properties['WLMADMAUTH'] -and $dbg.WLMADMAUTH -eq 'Y') { $dbPrivileges += "WLMADM" }
                if ($dbg.PSObject.Properties['EXPLAINAUTH'] -and $dbg.EXPLAINAUTH -eq 'Y') { $dbPrivileges += "EXPLAIN" }
                foreach ($priv in $dbPrivileges) {
                    $db2Commands += "db2 `"GRANT $priv ON DATABASE TO ROLE $roleName`""
                    $grantToRoleCount++
                }
            }

            if (-not $roleIsDbadm) {
                # Table grants (skip for DBADM roles — DBADM covers all table privileges)
                foreach ($tg in $grants.TableGrants) {
                    $qualifiedName = "$($tg.TABSCHEMA.Trim()).$($tg.TABNAME.Trim())"
                    $tablePrivs = @()
                    if ($tg.SELECTAUTH -eq 'Y') { $tablePrivs += "SELECT" }
                    if ($tg.INSERTAUTH -eq 'Y') { $tablePrivs += "INSERT" }
                    if ($tg.UPDATEAUTH -eq 'Y') { $tablePrivs += "UPDATE" }
                    if ($tg.DELETEAUTH -eq 'Y') { $tablePrivs += "DELETE" }
                    if ($tg.ALTERAUTH -eq 'Y') { $tablePrivs += "ALTER" }
                    if ($tg.INDEXAUTH -eq 'Y') { $tablePrivs += "INDEX" }
                    if ($tg.REFAUTH -eq 'Y') { $tablePrivs += "REFERENCES" }
                    if ($tg.CONTROLAUTH -eq 'Y') { $tablePrivs += "CONTROL" }
                    if ($tablePrivs.Count -gt 0) {
                        $privList = $tablePrivs -join ", "
                        $db2Commands += "db2 `"GRANT $privList ON $qualifiedName TO ROLE $roleName`""
                        $grantToRoleCount++
                    }
                }

                # Routine grants
                foreach ($rg in $grants.RoutineGrants) {
                    if ($rg.EXECUTEAUTH -eq 'Y') {
                        $routineType = if ($rg.ROUTINETYPE.Trim() -eq 'P') { "PROCEDURE" } else { "FUNCTION" }
                        $qualifiedName = "$($rg.ROUTINESCHEMA.Trim()).$($rg.ROUTINENAME.Trim())"
                        $db2Commands += "db2 `"GRANT EXECUTE ON $routineType $qualifiedName TO ROLE $roleName`""
                        $grantToRoleCount++
                    }
                }

                # Schema grants
                foreach ($sg in $grants.SchemaGrants) {
                    $schemaName = $sg.SCHEMANAME.Trim()
                    $schemaPrivs = @()
                    if ($sg.CREATEINAUTH -eq 'Y') { $schemaPrivs += "CREATEIN" }
                    if ($sg.ALTERINAUTH -eq 'Y') { $schemaPrivs += "ALTERIN" }
                    if ($sg.DROPINAUTH -eq 'Y') { $schemaPrivs += "DROPIN" }
                    foreach ($priv in $schemaPrivs) {
                        $db2Commands += "db2 `"GRANT $priv ON SCHEMA $schemaName TO ROLE $roleName`""
                        $grantToRoleCount++
                    }
                }

                # Package grants
                foreach ($pg in $grants.PackageGrants) {
                    $qualifiedName = "$($pg.PKGSCHEMA.Trim()).$($pg.PKGNAME.Trim())"
                    $pkgPrivs = @()
                    if ($pg.CONTROLAUTH -eq 'Y') { $pkgPrivs += "CONTROL" }
                    if ($pg.BINDAUTH -eq 'Y') { $pkgPrivs += "BIND" }
                    if ($pg.EXECUTEAUTH -eq 'Y') { $pkgPrivs += "EXECUTE" }
                    if ($pkgPrivs.Count -gt 0) {
                        $privList = $pkgPrivs -join ", "
                        $db2Commands += "db2 `"GRANT $privList ON PACKAGE $qualifiedName TO ROLE $roleName`""
                        $grantToRoleCount++
                    }
                }

                # Index grants
                foreach ($ig in $grants.IndexGrants) {
                    if ($ig.CONTROLAUTH -eq 'Y') {
                        $qualifiedName = "$($ig.INDSCHEMA.Trim()).$($ig.INDNAME.Trim())"
                        $db2Commands += "db2 `"GRANT CONTROL ON INDEX $qualifiedName TO ROLE $roleName`""
                        $grantToRoleCount++
                    }
                }
            } else {
                Write-LogMessage "Role $roleName has DBADM — skipping $($grants.TableGrants.Count) table, $($grants.RoutineGrants.Count) routine, $($grants.SchemaGrants.Count) schema, $($grants.PackageGrants.Count) package, $($grants.IndexGrants.Count) index grants (all implied by DBADM)" -Level INFO
            }

            # 4c. GRANT ROLE TO each member
            foreach ($member in $members) {
                $memberClause = Get-GranteeClause -Grantee $member.Grantee -GranteeType $member.GranteeType
                $db2Commands += "db2 `"GRANT ROLE $roleName TO $memberClause`""
                $membershipCount++
            }

            # 4d. REVOKE original direct grants from each member
            foreach ($member in $members) {
                $memberClause = Get-GranteeClause -Grantee $member.Grantee -GranteeType $member.GranteeType

                foreach ($dbg in $grants.DatabaseGrants) {
                    $dbPrivileges = @()
                    if ($dbg.CONNECTAUTH -eq 'Y') { $dbPrivileges += "CONNECT" }
                    if ($dbg.CREATETABAUTH -eq 'Y') { $dbPrivileges += "CREATETAB" }
                    if ($dbg.DBADMAUTH -eq 'Y') { $dbPrivileges += "DBADM" }
                    if ($dbg.EXTERNALROUTINEAUTH -eq 'Y') { $dbPrivileges += "CREATE_EXTERNAL_ROUTINE" }
                    if ($dbg.IMPLSCHEMAAUTH -eq 'Y') { $dbPrivileges += "IMPLICIT_SCHEMA" }
                    if ($dbg.LOADAUTH -eq 'Y') { $dbPrivileges += "LOAD" }
                    if ($dbg.NOFENCEAUTH -eq 'Y') { $dbPrivileges += "CREATE_NOT_FENCED_ROUTINE" }
                    if ($dbg.QUIESCECONNECTAUTH -eq 'Y') { $dbPrivileges += "QUIESCE_CONNECT" }
                    if ($dbg.BINDADDAUTH -eq 'Y') { $dbPrivileges += "BINDADD" }
                    if ($dbg.DATAACCESSAUTH -eq 'Y') { $dbPrivileges += "DATAACCESS" }
                    if ($dbg.ACCESSCTRLAUTH -eq 'Y') { $dbPrivileges += "ACCESSCTRL" }
                    if ($dbg.SECURITYADMAUTH -eq 'Y') { $dbPrivileges += "SECADM" }
                    if ($dbg.PSObject.Properties['SQLADMAUTH'] -and $dbg.SQLADMAUTH -eq 'Y') { $dbPrivileges += "SQLADM" }
                    if ($dbg.PSObject.Properties['WLMADMAUTH'] -and $dbg.WLMADMAUTH -eq 'Y') { $dbPrivileges += "WLMADM" }
                    if ($dbg.PSObject.Properties['EXPLAINAUTH'] -and $dbg.EXPLAINAUTH -eq 'Y') { $dbPrivileges += "EXPLAIN" }
                    foreach ($priv in $dbPrivileges) {
                        $db2Commands += "db2 `"REVOKE $priv ON DATABASE FROM $memberClause`""
                        $revokeCount++
                    }
                }

                if (-not $roleIsDbadm) {
                    # Only revoke lower-level grants for non-DBADM roles. For DBADM holders,
                    # revoking DBADM (above) automatically removes all implicit privileges.
                    foreach ($tg in $grants.TableGrants) {
                        $qualifiedName = "$($tg.TABSCHEMA.Trim()).$($tg.TABNAME.Trim())"
                        $tablePrivs = @()
                        if ($tg.SELECTAUTH -eq 'Y') { $tablePrivs += "SELECT" }
                        if ($tg.INSERTAUTH -eq 'Y') { $tablePrivs += "INSERT" }
                        if ($tg.UPDATEAUTH -eq 'Y') { $tablePrivs += "UPDATE" }
                        if ($tg.DELETEAUTH -eq 'Y') { $tablePrivs += "DELETE" }
                        if ($tg.ALTERAUTH -eq 'Y') { $tablePrivs += "ALTER" }
                        if ($tg.INDEXAUTH -eq 'Y') { $tablePrivs += "INDEX" }
                        if ($tg.REFAUTH -eq 'Y') { $tablePrivs += "REFERENCES" }
                        if ($tg.CONTROLAUTH -eq 'Y') { $tablePrivs += "CONTROL" }
                        if ($tablePrivs.Count -gt 0) {
                            $privList = $tablePrivs -join ", "
                            $db2Commands += "db2 `"REVOKE $privList ON $qualifiedName FROM $memberClause`""
                            $revokeCount++
                        }
                    }

                    foreach ($rg in $grants.RoutineGrants) {
                        if ($rg.EXECUTEAUTH -eq 'Y') {
                            $routineType = if ($rg.ROUTINETYPE.Trim() -eq 'P') { "PROCEDURE" } else { "FUNCTION" }
                            $qualifiedName = "$($rg.ROUTINESCHEMA.Trim()).$($rg.ROUTINENAME.Trim())"
                            $db2Commands += "db2 `"REVOKE EXECUTE ON $routineType $qualifiedName FROM $memberClause`""
                            $revokeCount++
                        }
                    }

                    foreach ($sg in $grants.SchemaGrants) {
                        $schemaName = $sg.SCHEMANAME.Trim()
                        $schemaPrivs = @()
                        if ($sg.CREATEINAUTH -eq 'Y') { $schemaPrivs += "CREATEIN" }
                        if ($sg.ALTERINAUTH -eq 'Y') { $schemaPrivs += "ALTERIN" }
                        if ($sg.DROPINAUTH -eq 'Y') { $schemaPrivs += "DROPIN" }
                        foreach ($priv in $schemaPrivs) {
                            $db2Commands += "db2 `"REVOKE $priv ON SCHEMA $schemaName FROM $memberClause`""
                            $revokeCount++
                        }
                    }

                    foreach ($pg in $grants.PackageGrants) {
                        $qualifiedName = "$($pg.PKGSCHEMA.Trim()).$($pg.PKGNAME.Trim())"
                        $pkgPrivs = @()
                        if ($pg.CONTROLAUTH -eq 'Y') { $pkgPrivs += "CONTROL" }
                        if ($pg.BINDAUTH -eq 'Y') { $pkgPrivs += "BIND" }
                        if ($pg.EXECUTEAUTH -eq 'Y') { $pkgPrivs += "EXECUTE" }
                        if ($pkgPrivs.Count -gt 0) {
                            $privList = $pkgPrivs -join ", "
                            $db2Commands += "db2 `"REVOKE $privList ON PACKAGE $qualifiedName FROM $memberClause`""
                            $revokeCount++
                        }
                    }

                    foreach ($ig in $grants.IndexGrants) {
                        if ($ig.CONTROLAUTH -eq 'Y') {
                            $qualifiedName = "$($ig.INDSCHEMA.Trim()).$($ig.INDNAME.Trim())"
                            $db2Commands += "db2 `"REVOKE CONTROL ON INDEX $qualifiedName FROM $memberClause`""
                            $revokeCount++
                        }
                    }
                }
            }
        }

        # ── Preserve PUBLIC grants as direct grants (no role conversion) ───────
        $publicGrantCount = 0
        foreach ($g in $jsonContent.DatabaseGrants) {
            if ($g.GRANTEE.Trim().ToUpper() -ne "PUBLIC") { continue }
            $dbPrivileges = @()
            if ($g.CONNECTAUTH -eq 'Y') { $dbPrivileges += "CONNECT" }
            if ($g.CREATETABAUTH -eq 'Y') { $dbPrivileges += "CREATETAB" }
            if ($g.IMPLSCHEMAAUTH -eq 'Y') { $dbPrivileges += "IMPLICIT_SCHEMA" }
            if ($g.BINDADDAUTH -eq 'Y') { $dbPrivileges += "BINDADD" }
            foreach ($priv in $dbPrivileges) {
                $db2Commands += "db2 `"GRANT $priv ON DATABASE TO PUBLIC`""
                $publicGrantCount++
            }
        }
        foreach ($g in $jsonContent.TableGrants) {
            if ($g.GRANTEE.Trim().ToUpper() -ne "PUBLIC") { continue }
            $tablePrivs = @()
            if ($g.SELECTAUTH -eq 'Y') { $tablePrivs += "SELECT" }
            if ($g.INSERTAUTH -eq 'Y') { $tablePrivs += "INSERT" }
            if ($g.UPDATEAUTH -eq 'Y') { $tablePrivs += "UPDATE" }
            if ($g.DELETEAUTH -eq 'Y') { $tablePrivs += "DELETE" }
            if ($tablePrivs.Count -gt 0) {
                $privList = $tablePrivs -join ", "
                $qualifiedName = "$($g.TABSCHEMA.Trim()).$($g.TABNAME.Trim())"
                $db2Commands += "db2 `"GRANT $privList ON $qualifiedName TO PUBLIC`""
                $publicGrantCount++
            }
        }
        foreach ($g in $jsonContent.RoutineGrants) {
            if ($g.GRANTEE.Trim().ToUpper() -ne "PUBLIC") { continue }
            if ($g.EXECUTEAUTH -eq 'Y') {
                $routineType = if ($g.ROUTINETYPE.Trim() -eq 'P') { "PROCEDURE" } else { "FUNCTION" }
                $qualifiedName = "$($g.ROUTINESCHEMA.Trim()).$($g.ROUTINENAME.Trim())"
                $db2Commands += "db2 `"GRANT EXECUTE ON $routineType $qualifiedName TO PUBLIC`""
                $publicGrantCount++
            }
        }

        $db2Commands += "db2 commit work"
        $db2Commands += "db2 connect reset"

        Write-LogMessage "Generated commands: $createRoleCount CREATE ROLE, $grantToRoleCount GRANT TO ROLE, $membershipCount GRANT ROLE TO member, $revokeCount REVOKE direct, $publicGrantCount PUBLIC (preserved)" -Level INFO

        # ── Phase 5: Execute ───────────────────────────────────────────────────
        $workFolder = Join-Path $env:OptPath "data\Db2-GrantsImport"
        if (-not (Test-Path $workFolder)) {
            New-Item -Path $workFolder -ItemType Directory -Force | Out-Null
        }

        $fileName = Join-Path $workFolder "ImportGrantsAsRoles_$($targetDb)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName $fileName

        Write-LogMessage "Role-based grant import completed for $targetDb" -Level INFO

        # Build role mapping for result
        $roleMapping = @()
        foreach ($assignment in $roleAssignments.GetEnumerator()) {
            $memberNames = ($assignment.Value.Members | ForEach-Object { $_.Grantee }) -join ", "
            $roleMapping += [PSCustomObject]@{
                RoleName = $assignment.Value.RoleName
                Members  = $memberNames
            }
        }

        return [PSCustomObject]@{
            DatabaseName     = $targetDb
            SourceFile       = $importFile
            RolesCreated     = $createRoleCount
            GrantsToRoles    = $grantToRoleCount
            Memberships      = $membershipCount
            RevokesIssued    = $revokeCount
            PublicGrants     = $publicGrantCount
            RoleMapping      = $roleMapping
            Output           = $output
        }
    }
    catch {
        Write-LogMessage "Error in Import-Db2GrantsAsRoles: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Error in Import-Db2GrantsAsRoles: $($_.Exception.Message)"
    }
}

function New-DbqaPrivilegeViews {
    <#
    .SYNOPSIS
    Creates TV.V_DBQA_ALL_PRIVS and TV.V_DBQA_ROLE_MEMBERS views for grant validation.

    .DESCRIPTION
    V_DBQA_ALL_PRIVS: Normalized view — one row per (grantee, object, privilege).
    Covers DBAUTH, TABAUTH, ROUTINEAUTH, SCHEMAAUTH, PACKAGEAUTH, INDEXAUTH.
    Only rows where AUTH_VALUE <> 'N' (i.e. Y or G) are included.

    V_DBQA_ROLE_MEMBERS: Role membership map from SYSCAT.ROLEAUTH.

    Both views are created in schema TV with CREATE OR REPLACE so they are safe to re-run.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName
    )

    $granteeDesc = "CASE {0}GRANTEETYPE WHEN 'U' THEN 'USER' WHEN 'G' THEN 'GROUP' WHEN 'R' THEN 'ROLE' END"
    $gDescRoot = $granteeDesc -f ''
    $gDescA    = $granteeDesc -f 'A.'

    # --- Database-level privileges (unpivoted via UNION ALL) ---
    $dbPrivs = @(
        'CONNECT','CREATETAB','DBADM','DATAACCESS','ACCESSCTRL',
        'SECADM','LOAD','EXTERNALROUTINE','IMPLSCHEMA','NOFENCE',
        'QUIESCECONNECT','BINDADD','SQLADM','WLMADM','EXPLAIN'
    )
    $dbAuthCol = @{
        CONNECT='CONNECTAUTH'; CREATETAB='CREATETABAUTH'; DBADM='DBADMAUTH'
        DATAACCESS='DATAACCESSAUTH'; ACCESSCTRL='ACCESSCTRLAUTH'; SECADM='SECURITYADMAUTH'
        LOAD='LOADAUTH'; EXTERNALROUTINE='EXTERNALROUTINEAUTH'; IMPLSCHEMA='IMPLSCHEMAAUTH'
        NOFENCE='NOFENCEAUTH'; QUIESCECONNECT='QUIESCECONNECTAUTH'; BINDADD='BINDADDAUTH'
        SQLADM='SQLADMAUTH'; WLMADM='WLMADMAUTH'; EXPLAIN='EXPLAINAUTH'
    }
    $dbParts = foreach ($p in $dbPrivs) {
        $col = $dbAuthCol[$p]
        "SELECT GRANTEE, GRANTEETYPE, $gDescRoot, GRANTOR, 'DATABASE', '', CURRENT SERVER, '$p', $col FROM SYSCAT.DBAUTH WHERE $col <> 'N'"
    }

    # --- Table/view privileges ---
    $tabPrivs = @{SELECT='SELECTAUTH';INSERT='INSERTAUTH';UPDATE='UPDATEAUTH';DELETE='DELETEAUTH';ALTER='ALTERAUTH';INDEX='INDEXAUTH';REFERENCES='REFAUTH';CONTROL='CONTROLAUTH'}
    $tabParts = foreach ($kv in $tabPrivs.GetEnumerator()) {
        "SELECT A.GRANTEE, A.GRANTEETYPE, $gDescA, A.GRANTOR, CASE T.TYPE WHEN 'T' THEN 'TABLE' WHEN 'V' THEN 'VIEW' ELSE 'TABLE' END, RTRIM(T.TABSCHEMA), T.TABNAME, '$($kv.Key)', A.$($kv.Value) FROM SYSCAT.TABAUTH A INNER JOIN SYSCAT.TABLES T ON A.TABSCHEMA=T.TABSCHEMA AND A.TABNAME=T.TABNAME WHERE A.$($kv.Value) <> 'N'"
    }

    # --- Routine privileges ---
    $routinePart = "SELECT A.GRANTEE, A.GRANTEETYPE, $gDescA, A.GRANTOR, CASE R.ROUTINETYPE WHEN 'F' THEN 'FUNCTION' WHEN 'P' THEN 'PROCEDURE' ELSE 'ROUTINE' END, RTRIM(R.ROUTINESCHEMA), R.ROUTINENAME, 'EXECUTE', A.EXECUTEAUTH FROM SYSCAT.ROUTINEAUTH A INNER JOIN SYSCAT.ROUTINES R ON A.SCHEMA=R.ROUTINESCHEMA AND A.SPECIFICNAME=R.SPECIFICNAME WHERE A.EXECUTEAUTH <> 'N'"

    # --- Schema privileges ---
    $schemaParts = foreach ($kv in @{CREATEIN='CREATEINAUTH';ALTERIN='ALTERINAUTH';DROPIN='DROPINAUTH'}.GetEnumerator()) {
        "SELECT A.GRANTEE, A.GRANTEETYPE, $gDescA, A.GRANTOR, 'SCHEMA', RTRIM(A.SCHEMANAME), A.SCHEMANAME, '$($kv.Key)', A.$($kv.Value) FROM SYSCAT.SCHEMAAUTH A WHERE A.$($kv.Value) <> 'N'"
    }

    # --- Package privileges ---
    $pkgParts = foreach ($kv in @{CONTROL='CONTROLAUTH';BIND='BINDAUTH';EXECUTE='EXECUTEAUTH'}.GetEnumerator()) {
        "SELECT A.GRANTEE, A.GRANTEETYPE, $gDescA, A.GRANTOR, 'PACKAGE', RTRIM(A.PKGSCHEMA), A.PKGNAME, '$($kv.Key)', A.$($kv.Value) FROM SYSCAT.PACKAGEAUTH A WHERE A.$($kv.Value) <> 'N'"
    }

    # --- Index privileges ---
    $indexPart = "SELECT A.GRANTEE, A.GRANTEETYPE, $gDescA, A.GRANTOR, 'INDEX', RTRIM(I.INDSCHEMA), I.INDNAME, 'CONTROL', A.CONTROLAUTH FROM SYSCAT.INDEXAUTH A INNER JOIN SYSCAT.INDEXES I ON A.INDSCHEMA=I.INDSCHEMA AND A.INDNAME=I.INDNAME WHERE A.CONTROLAUTH <> 'N'"

    $allParts = @()
    $allParts += $dbParts
    $allParts += $tabParts
    $allParts += $routinePart
    $allParts += $schemaParts
    $allParts += $pkgParts
    $allParts += $indexPart

    $viewBody = $allParts -join " UNION ALL "
    $createAllPrivs = "CREATE OR REPLACE VIEW TV.V_DBQA_ALL_PRIVS (GRANTEE, GRANTEETYPE, GRANTEE_DESC, GRANTOR, OBJ_TYPE, OBJ_SCHEMA, OBJ_NAME, PRIVILEGE, AUTH_VALUE) AS $viewBody"

    $createRoleMembers = "CREATE OR REPLACE VIEW TV.V_DBQA_ROLE_MEMBERS (ROLENAME, GRANTEE, GRANTEETYPE, GRANTEE_DESC, GRANTOR, ADMIN) AS SELECT R.ROLENAME, R.GRANTEE, R.GRANTEETYPE, CASE R.GRANTEETYPE WHEN 'U' THEN 'USER' WHEN 'G' THEN 'GROUP' WHEN 'R' THEN 'ROLE' END, R.GRANTOR, R.ADMIN FROM SYSCAT.ROLEAUTH R"

    Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $createAllPrivs
    Get-ExecuteSqlStatementServerSide -DatabaseName $DatabaseName -SqlStatement $createRoleMembers
}

function Get-GranteeClause {
    <#
    .SYNOPSIS
    Converts GRANTEE + GRANTEETYPE to a DB2 GRANT target clause.
    #>
    param(
        [string]$Grantee,
        [string]$GranteeType
    )
    
    if ($Grantee.Trim().ToUpper() -eq "PUBLIC") {
        return "PUBLIC"
    }
    
    # GRANTEETYPE: '' or ' ' = user, 'G' = group, 'R' = role
    $typeKeyword = switch ($GranteeType.Trim().ToUpper()) {
        'G' { "GROUP" }
        'R' { "ROLE" }
        default { "USER" }
    }
    
    return "$typeKeyword $($Grantee.Trim())"
}

#region DDL Export / Import — Generic table DDL capture, persistence, and replay

function Invoke-Db2MultiStatement {
    <#
    .SYNOPSIS
    Execute one or more db2 CLI commands within a single connect/disconnect session.
    .DESCRIPTION
    Wraps the supplied commands in SET INSTANCE + CONNECT + <commands> + CONNECT RESET + TERMINATE,
    writes a BAT file, and runs it via Invoke-Db2ContentAsScript.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string[]]$Db2Commands,
        [switch]$IgnoreErrors
    )

    $batLines = @()
    $batLines += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $batLines += Get-ConnectCommand -WorkObject $WorkObject
    foreach ($cmd in $Db2Commands) {
        $batLines += $cmd
    }
    $batLines += "db2 connect reset"
    $batLines += "db2 terminate"

    return Invoke-Db2ContentAsScript -Content $batLines -ExecutionType BAT -IgnoreErrors:$IgnoreErrors
}

function Get-Db2OutputBetweenMarkers {
    <#
    .SYNOPSIS
    Extract non-empty output lines between echo START/END markers in db2cmd output.
    .DESCRIPTION
    Used to isolate db2 -x query results from surrounding db2cmd noise (prompts,
    status messages). Filters out DB20000I lines and Windows command-prompt lines.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Output,
        [Parameter(Mandatory)]
        [string]$StartMarker,
        [Parameter(Mandatory)]
        [string]$EndMarker
    )

    $lines = $Output -split "`r?`n"
    $inside = $false
    [string[]]$result = @()
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -eq $StartMarker) { $inside = $true; continue }
        if ($t -eq $EndMarker) { break }
        if ($inside -and -not [string]::IsNullOrWhiteSpace($t) -and $t -notlike "DB20000I*") {
            if ($t -match '^[A-Za-z]:\\.*>\s*') { continue }
            $result += $t
        }
    }
    return ,$result
}

function Invoke-Db2QueryTsv {
    <#
    .SYNOPSIS
    Run a single SELECT query and return parsed TSV output lines.
    .DESCRIPTION
    Wraps the query in echo markers (__QSTART__/__QEND__), executes via db2 -x,
    and extracts result lines using Get-Db2OutputBetweenMarkers-style parsing.
    Each result line is a whitespace- or tab-separated row from the query.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SqlQuery
    )

    $db2Commands = @()
    $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $db2Commands += Get-ConnectCommand -WorkObject $WorkObject
    $db2Commands += "echo __QSTART__"
    $db2Commands += "db2 -x `"$SqlQuery`""
    $db2Commands += "echo __QEND__"
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors:$false
    $lines = $output -split "`r?`n"
    $results = @()
    $inside = $false
    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq "__QSTART__") { $inside = $true; continue }
        if ($trimmedLine -eq "__QEND__") { break }
        if ($inside -and -not [string]::IsNullOrWhiteSpace($trimmedLine)) {
            if ($trimmedLine -like "DB20000I*") { continue }
            if ($trimmedLine -match '^[A-Za-z]:\\.*>\s*') { continue }
            $results += $trimmedLine
        }
    }

    return $results
}

function Get-Db2ScalarValue {
    <#
    .SYNOPSIS
    Execute a SELECT that returns a single value and return it as a trimmed string.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SqlQuery
    )

    $rows = @(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $SqlQuery)
    if ($rows.Count -eq 0) { return "" }
    return ([string]$rows[0]).Trim()
}

function Get-Db2IndexDdlFromCatalog {
    <#
    .SYNOPSIS
    Capture index DDL for a table from SYSCAT.INDEXES / SYSCAT.INDEXCOLUSE.
    .DESCRIPTION
    Returns an array of DDL strings:
      - ALTER TABLE schema.table ADD PRIMARY KEY (cols) for UNIQUERULE='P'
      - CREATE UNIQUE INDEX schema.name ON schema.table (cols) for UNIQUERULE='U'
      - CREATE INDEX schema.name ON schema.table (cols) for UNIQUERULE='D'
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    $query = "SELECT I.INDNAME, I.UNIQUERULE, IC.COLNAME, IC.COLORDER, IC.COLSEQ FROM SYSCAT.INDEXES I JOIN SYSCAT.INDEXCOLUSE IC ON I.INDSCHEMA = IC.INDSCHEMA AND I.INDNAME = IC.INDNAME WHERE I.TABSCHEMA = '$Schema' AND I.TABNAME = '$TableName' ORDER BY I.INDNAME, IC.COLSEQ FETCH FIRST 500 ROWS ONLY"

    $db2Commands = @(
        "echo __IDX_START__",
        "db2 -x `"$query`"",
        "echo __IDX_END__"
    )
    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $lines = Get-Db2OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__IDX_START__" -EndMarker "__IDX_END__"

    $indexes = @{}
    $indexRules = @{}
    foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 5) { continue }
        $indName = $parts[0].Trim()
        $uniqueRule = $parts[1].Trim()
        $colName = $parts[2].Trim()
        $colOrder = $parts[3].Trim()

        if (-not $indexes.ContainsKey($indName)) {
            $indexes[$indName] = @()
            $indexRules[$indName] = $uniqueRule
        }
        $direction = if ($colOrder -eq "D") { "DESC" } else { "ASC" }
        $indexes[$indName] += "$colName $direction"
    }

    $statements = @()
    foreach ($indName in ($indexes.Keys | Sort-Object)) {
        $rule = $indexRules[$indName]
        $colList = $indexes[$indName] -join ", "
        $colListNaked = ($indexes[$indName] | ForEach-Object { ($_ -replace ' ASC$', '' -replace ' DESC$', '') }) -join ", "

        if ($rule -eq "P") {
            $statements += "ALTER TABLE $Schema.$TableName ADD PRIMARY KEY ($colListNaked)"
        }
        elseif ($rule -eq "U") {
            $statements += "CREATE UNIQUE INDEX $Schema.$indName ON $Schema.$TableName ($colList)"
        }
        else {
            $statements += "CREATE INDEX $Schema.$indName ON $Schema.$TableName ($colList)"
        }
    }

    Write-LogMessage "  Captured $($statements.Count) index DDL statement(s) from SYSCAT for $($Schema).$($TableName)" -Level INFO
    return $statements
}

function Get-Db2GrantDdlFromCatalog {
    <#
    .SYNOPSIS
    Capture table-level GRANT statements from SYSCAT.TABAUTH.
    .DESCRIPTION
    Returns an array of GRANT DDL strings. Skips SYSIBM grants.
    CONTROL grants are emitted separately; other privileges are combined per grantee.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    $query = "SELECT GRANTEE, SELECTAUTH, INSERTAUTH, UPDATEAUTH, DELETEAUTH, CONTROLAUTH, REFAUTH FROM SYSCAT.TABAUTH WHERE TABSCHEMA = '$Schema' AND TABNAME = '$TableName' ORDER BY GRANTEE FETCH FIRST 100 ROWS ONLY"

    $db2Commands = @(
        "echo __GR_START__",
        "db2 -x `"$query`"",
        "echo __GR_END__"
    )
    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $lines = Get-Db2OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__GR_START__" -EndMarker "__GR_END__"

    $statements = @()
    $processedGrantees = @{}
    foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 7) { continue }
        $grantee = $parts[0].Trim()
        if ($grantee -eq "SYSIBM" -or $processedGrantees.ContainsKey($grantee)) { continue }
        $processedGrantees[$grantee] = $true

        $selectAuth  = $parts[1].Trim()
        $insertAuth  = $parts[2].Trim()
        $updateAuth  = $parts[3].Trim()
        $deleteAuth  = $parts[4].Trim()
        $controlAuth = $parts[5].Trim()
        $refAuth     = $parts[6].Trim()

        if ($controlAuth -in @("Y", "G")) {
            $statements += "GRANT CONTROL ON $Schema.$TableName TO $grantee"
            continue
        }
        $privs = @()
        if ($selectAuth  -in @("Y", "G")) { $privs += "SELECT" }
        if ($insertAuth  -in @("Y", "G")) { $privs += "INSERT" }
        if ($updateAuth  -in @("Y", "G")) { $privs += "UPDATE" }
        if ($deleteAuth  -in @("Y", "G")) { $privs += "DELETE" }
        if ($refAuth     -in @("Y", "G")) { $privs += "REFERENCES" }

        if ($privs.Count -gt 0) {
            $statements += "GRANT $($privs -join ', ') ON $Schema.$TableName TO $grantee"
        }
    }

    Write-LogMessage "  Captured $($statements.Count) grant statement(s) from SYSCAT for $($Schema).$($TableName)" -Level INFO
    return $statements
}

function Get-Db2ViewDdlFromCatalog {
    <#
    .SYNOPSIS
    Capture DDL for all views that depend on a given base table.
    .DESCRIPTION
    Queries SYSCAT.TABDEP (DTYPE='V') to find dependent views, then retrieves each
    view's TEXT from SYSCAT.VIEWS. Strips leading SQL comments and wraps with
    CREATE OR REPLACE VIEW if needed.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    $depQuery = "SELECT TABSCHEMA, TABNAME FROM SYSCAT.TABDEP WHERE BSCHEMA='$Schema' AND BNAME='$TableName' AND BTYPE='T' AND DTYPE='V' ORDER BY TABNAME FETCH FIRST 50 ROWS ONLY"

    $db2Commands = @(
        "echo __VD_START__",
        "db2 -x `"$depQuery`"",
        "echo __VD_END__"
    )
    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $depLines = Get-Db2OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__VD_START__" -EndMarker "__VD_END__"

    $viewStatements = @()
    foreach ($depLine in $depLines) {
        $parts = $depLine -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $viewSchema = $parts[0].Trim()
        $viewName = $parts[1].Trim()

        $viewQuery = "SELECT TEXT FROM SYSCAT.VIEWS WHERE VIEWSCHEMA='$viewSchema' AND VIEWNAME='$viewName'"
        $viewCommands = @(
            "echo __VW_START__",
            "db2 -x `"$viewQuery`"",
            "echo __VW_END__"
        )
        $viewOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $viewCommands -IgnoreErrors
        $viewLines = Get-Db2OutputBetweenMarkers -Output ($viewOutput -join "`n") -StartMarker "__VW_START__" -EndMarker "__VW_END__"

        if ($viewLines.Count -gt 0) {
            $viewText = ($viewLines -join "`n").Trim()
            # SYSCAT.VIEWS.TEXT can start with comment lines (e.g. "-- ViewName source").
            # Strip leading SQL comments so the ^CREATE regex matches the actual DDL.
            $cleanText = $viewText -replace '(?m)^--[^\r\n]*[\r\n]*', ''
            $cleanText = $cleanText.TrimStart()
            if ($cleanText -match '(?i)^CREATE\s') {
                $viewStatements += $cleanText
            }
            else {
                $viewStatements += "CREATE OR REPLACE VIEW $viewSchema.$viewName AS $cleanText"
            }
            Write-LogMessage "  Captured view DDL for $($viewSchema).$($viewName)" -Level INFO
        }
    }

    Write-LogMessage "  Captured $($viewStatements.Count) dependent view(s) from SYSCAT for $($Schema).$($TableName)" -Level INFO
    return $viewStatements
}

function Get-Db2FkDropStatements {
    <#
    .SYNOPSIS
    Capture ALTER TABLE … DROP CONSTRAINT statements for foreign keys related to a table.
    .PARAMETER Direction
    'Incoming' = FKs where this table is the parent (REFTABNAME).
    'Outgoing' = FKs where this table is the child (TABNAME).
    'All' = both.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName,
        [ValidateSet('Incoming', 'Outgoing', 'All')]
        [string]$Direction = 'All'
    )

    $statements = @()

    if ($Direction -in @('Incoming', 'All')) {
        $q = "SELECT RTRIM(TABSCHEMA) || CHR(9) || RTRIM(TABNAME) || CHR(9) || RTRIM(CONSTNAME) FROM SYSCAT.REFERENCES WHERE RTRIM(REFTABSCHEMA)='$Schema' AND RTRIM(REFTABNAME)='$TableName' FETCH FIRST 100 ROWS ONLY"
        $lines = @(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $q)
        foreach ($line in $lines) {
            $parts = $line -split "`t"
            if ($parts.Count -lt 3) { continue }
            $ts = $parts[0].Trim(); $tn = $parts[1].Trim(); $cn = $parts[2].Trim()
            if ([string]::IsNullOrWhiteSpace($cn)) { continue }
            $statements += "ALTER TABLE $ts.$tn DROP CONSTRAINT $cn"
        }
        Write-LogMessage "  Captured $($statements.Count) FK DROP (incoming, child->parent) for $($Schema).$($TableName)" -Level INFO
    }

    $outCount = 0
    if ($Direction -in @('Outgoing', 'All')) {
        $q = "SELECT RTRIM(TABSCHEMA) || CHR(9) || RTRIM(TABNAME) || CHR(9) || RTRIM(CONSTNAME) FROM SYSCAT.REFERENCES WHERE RTRIM(TABSCHEMA)='$Schema' AND RTRIM(TABNAME)='$TableName' FETCH FIRST 100 ROWS ONLY"
        $lines = @(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $q)
        foreach ($line in $lines) {
            $parts = $line -split "`t"
            if ($parts.Count -lt 3) { continue }
            $ts = $parts[0].Trim(); $tn = $parts[1].Trim(); $cn = $parts[2].Trim()
            if ([string]::IsNullOrWhiteSpace($cn)) { continue }
            $statements += "ALTER TABLE $ts.$tn DROP CONSTRAINT $cn"
            $outCount++
        }
        Write-LogMessage "  Captured $outCount FK DROP (outgoing, table-as-child) for $($Schema).$($TableName)" -Level INFO
    }

    return $statements
}

function Get-Db2FkAddStatements {
    <#
    .SYNOPSIS
    Build ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY … REFERENCES statements.
    .DESCRIPTION
    Queries SYSCAT.REFERENCES, resolves FK and PK columns via SYSCAT.KEYCOLUSE / INDEXCOLUSE,
    and maps DELETERULE/UPDATERULE to ON DELETE/ON UPDATE clauses.
    .PARAMETER Direction
    'Incoming' = FKs where this table is the parent (REFTABNAME).
    'Outgoing' = FKs where this table is the child (TABNAME).
    'All' = both.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName,
        [ValidateSet('Incoming', 'Outgoing', 'All')]
        [string]$Direction = 'All'
    )

    $statements = @()

    $queries = @()
    if ($Direction -in @('Incoming', 'All')) {
        $queries += @{ Label = "incoming (child->parent)"; Sql = "SELECT RTRIM(TABSCHEMA) || CHR(9) || RTRIM(TABNAME) || CHR(9) || RTRIM(CONSTNAME) || CHR(9) || RTRIM(REFTABSCHEMA) || CHR(9) || RTRIM(REFTABNAME) || CHR(9) || DELETERULE || CHR(9) || UPDATERULE FROM SYSCAT.REFERENCES WHERE RTRIM(REFTABSCHEMA)='$Schema' AND RTRIM(REFTABNAME)='$TableName' FETCH FIRST 100 ROWS ONLY" }
    }
    if ($Direction -in @('Outgoing', 'All')) {
        $queries += @{ Label = "outgoing (table-as-child)"; Sql = "SELECT RTRIM(TABSCHEMA) || CHR(9) || RTRIM(TABNAME) || CHR(9) || RTRIM(CONSTNAME) || CHR(9) || RTRIM(REFTABSCHEMA) || CHR(9) || RTRIM(REFTABNAME) || CHR(9) || DELETERULE || CHR(9) || UPDATERULE FROM SYSCAT.REFERENCES WHERE RTRIM(TABSCHEMA)='$Schema' AND RTRIM(TABNAME)='$TableName' FETCH FIRST 100 ROWS ONLY" }
    }

    foreach ($entry in $queries) {
        $lines = @(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $entry.Sql)
        $batch = @()
        foreach ($line in $lines) {
            $parts = $line -split "`t"
            if ($parts.Count -lt 7) { continue }
            $cts = $parts[0].Trim(); $ctn = $parts[1].Trim(); $cn  = $parts[2].Trim()
            $rts = $parts[3].Trim(); $rtn = $parts[4].Trim()
            $del = $parts[5].Trim(); $upd = $parts[6].Trim()

            $fkColQ = "SELECT RTRIM(COLNAME) FROM SYSCAT.KEYCOLUSE WHERE TABSCHEMA='$cts' AND TABNAME='$ctn' AND CONSTNAME='$cn' ORDER BY COLSEQ FETCH FIRST 32 ROWS ONLY"
            $fkCols = @(@(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $fkColQ) | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            $pkInd = (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery "SELECT RTRIM(INDNAME) FROM SYSCAT.INDEXES WHERE TABSCHEMA='$rts' AND TABNAME='$rtn' AND UNIQUERULE='P' FETCH FIRST 1 ROW ONLY").Trim()
            if ([string]::IsNullOrWhiteSpace($pkInd)) {
                Write-LogMessage "  Could not find PK index for $rts.$rtn — skip FK $cn" -Level WARN
                continue
            }
            $pkColQ = "SELECT RTRIM(COLNAME) FROM SYSCAT.INDEXCOLUSE WHERE RTRIM(INDSCHEMA)='$rts' AND RTRIM(INDNAME)='$pkInd' ORDER BY COLSEQ FETCH FIRST 32 ROWS ONLY"
            $pkCols = @(@(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $pkColQ) | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            if ($fkCols.Count -eq 0 -or $pkCols.Count -eq 0 -or $fkCols.Count -ne $pkCols.Count) {
                Write-LogMessage "  FK column mismatch for $cn (fk=$($fkCols.Count) pk=$($pkCols.Count)) — skip" -Level WARN
                continue
            }

            $fkList = $fkCols -join ", "
            $pkList = $pkCols -join ", "
            $delClause = switch ($del) { "C" { " ON DELETE CASCADE" } "R" { " ON DELETE RESTRICT" } "N" { " ON DELETE SET NULL" } "A" { " ON DELETE NO ACTION" } Default { "" } }
            $updClause = switch ($upd) { "R" { " ON UPDATE RESTRICT" } "C" { " ON UPDATE CASCADE" } "N" { " ON UPDATE SET NULL" } "A" { " ON UPDATE NO ACTION" } Default { "" } }
            $batch += "ALTER TABLE $cts.$ctn ADD CONSTRAINT $cn FOREIGN KEY ($fkList) REFERENCES $rts.$rtn ($pkList)$delClause$updClause"
        }
        Write-LogMessage "  Built $($batch.Count) FK ADD statement(s) ($($entry.Label)) for $($Schema).$($TableName)" -Level INFO
        $statements += $batch
    }

    return $statements
}

function Test-Db2TableDependencies {
    <#
    .SYNOPSIS
    Check whether a table has foreign keys or triggers in SYSCAT.
    .OUTPUTS
    PSCustomObject with FkCount and TrigCount.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    $fkSql   = "SELECT CHAR(COUNT(1)) FROM SYSCAT.REFERENCES WHERE (REFTABSCHEMA='$Schema' AND REFTABNAME='$TableName') OR (TABSCHEMA='$Schema' AND TABNAME='$TableName')"
    $trigSql = "SELECT CHAR(COUNT(1)) FROM SYSCAT.TRIGGERS WHERE TABSCHEMA='$Schema' AND TABNAME='$TableName'"

    $fkCount   = [int](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $fkSql)
    $trigCount = [int](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $trigSql)

    if ($fkCount -gt 0) {
        Write-LogMessage "  $($Schema).$($TableName) has $fkCount foreign key constraint(s)" -Level WARN
    }
    if ($trigCount -gt 0) {
        Write-LogMessage "  $($Schema).$($TableName) has $trigCount trigger(s)" -Level WARN
    }

    return [PSCustomObject]@{
        FkCount   = $fkCount
        TrigCount = $trigCount
    }
}

function Invoke-Db2ViewDdlViaFile {
    <#
    .SYNOPSIS
    Execute a CREATE VIEW DDL statement by writing it to a temp .sql file and running db2 -tvf.
    .DESCRIPTION
    Writes UTF-8 no-BOM, appends trailing semicolon if missing, executes, and cleans up.
    .PARAMETER OutputDirectory
    Directory for temp .sql files. Defaults to $env:TEMP.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$ViewDdlText,
        [string]$OutputDirectory = $env:TEMP,
        [string]$ActionLabel = "recreate"
    )

    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    $ddlFile = Join-Path $OutputDirectory "view_ddl_$(Get-Date -Format 'yyyyMMddHHmmssfff').sql"

    try {
        if ([string]::IsNullOrWhiteSpace($ViewDdlText)) {
            Write-LogMessage "    View $($ActionLabel) skipped: empty DDL text" -Level WARN
            return
        }
        $ddl = $ViewDdlText.Trim()
        if (-not $ddl.EndsWith(";")) { $ddl += ";" }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($ddlFile, $ddl, $utf8NoBom)
        $fileCommands = @("db2 -tvf `"$ddlFile`"")
        $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $fileCommands
        # Regex: match CREATE [OR REPLACE] VIEW schema.viewname
        #   (?i)           — case-insensitive
        #   CREATE\s+      — literal CREATE followed by whitespace
        #   (?:OR\s+REPLACE\s+)?  — optional OR REPLACE
        #   VIEW\s+        — literal VIEW followed by whitespace
        #   (\S+)          — capture group 1: schema.viewname (no spaces)
        if ($ViewDdlText -match '(?i)CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(\S+)') {
            Write-LogMessage "    View $($ActionLabel) OK: $($matches[1])" -Level INFO
        }
    }
    catch {
        Write-LogMessage "    View $($ActionLabel) FAILED: $($_.Exception.Message)" -Level ERROR
        throw
    }
    finally {
        if (Test-Path $ddlFile) { Remove-Item $ddlFile -Force -ErrorAction SilentlyContinue }
    }
}

function Rename-Db2TableIndexes {
    <#
    .SYNOPSIS
    Rename all indexes on a table by appending a suffix (e.g. '_TMP').
    .DESCRIPTION
    After RENAME TABLE, named indexes (including PK/UNIQUE backing indexes) travel
    with the table. This function renames them to free the original names for a new
    table. Db2 index names are unique per schema; constraint names are per table and
    do not need renaming.
    .PARAMETER Suffix
    Suffix to append (e.g. '_TMP'). Indexes already ending with this suffix are skipped.
    Db2 128-byte identifier limit is respected by truncation.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName,
        [Parameter(Mandatory)]
        [string]$Suffix
    )

    $query = "SELECT RTRIM(INDSCHEMA), RTRIM(INDNAME) FROM SYSCAT.INDEXES WHERE RTRIM(TABSCHEMA)='$Schema' AND TABNAME='$TableName' ORDER BY INDNAME FETCH FIRST 500 ROWS ONLY"
    $db2Commands = @(
        "echo __RNIDX_START__",
        "db2 -x `"$query`"",
        "echo __RNIDX_END__"
    )
    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $lines = Get-Db2OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__RNIDX_START__" -EndMarker "__RNIDX_END__"

    $renamed = 0
    $maxBase = 128 - $Suffix.Length
    foreach ($line in $lines) {
        $parts = $line.Trim() -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $idxSchema = $parts[0]
        $idxName = $parts[1]
        if ($idxName -match [regex]::Escape($Suffix) + '$') { continue }

        $newName = if ($idxName.Length -gt $maxBase) { $idxName.Substring(0, $maxBase) + $Suffix } else { "$($idxName)$Suffix" }
        try {
            $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands @("db2 `"RENAME INDEX $($idxSchema).$($idxName) TO $newName`"")
            $renamed++
            Write-LogMessage "    Renamed: $($idxSchema).$($idxName) -> $($idxSchema).$($newName)" -Level INFO
        }
        catch {
            Write-LogMessage "    Failed to rename index $($idxSchema).$($idxName): $($_.Exception.Message)" -Level WARN
        }
    }
    Write-LogMessage "  Renamed $renamed index(es) on $($Schema).$($TableName) with suffix '$Suffix'" -Level INFO
    return $renamed
}

function Export-Db2TableDdl {
    <#
    .SYNOPSIS
    Capture all DDL for a table (indexes, grants, views, FKs) and optionally save to JSON.
    .DESCRIPTION
    Aggregates output from Get-Db2IndexDdlFromCatalog, Get-Db2GrantDdlFromCatalog,
    Get-Db2ViewDdlFromCatalog, Get-Db2FkDropStatements, Get-Db2FkAddStatements.
    Returns a PSCustomObject and optionally persists to a JSON file.
    .PARAMETER OutputFile
    Optional file path to save the captured DDL as JSON. Parent directory is created if needed.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$Schema,
        [Parameter(Mandatory)]
        [string]$TableName,
        [string]$OutputFile
    )

    $indexStatements = @(Get-Db2IndexDdlFromCatalog -WorkObject $WorkObject -Schema $Schema -TableName $TableName)
    $grantStatements = @(Get-Db2GrantDdlFromCatalog -WorkObject $WorkObject -Schema $Schema -TableName $TableName)
    $viewStatements  = @(Get-Db2ViewDdlFromCatalog  -WorkObject $WorkObject -Schema $Schema -TableName $TableName)
    $fkDropStatements = @(Get-Db2FkDropStatements    -WorkObject $WorkObject -Schema $Schema -TableName $TableName -Direction All)
    $fkAddStatements  = @(Get-Db2FkAddStatements     -WorkObject $WorkObject -Schema $Schema -TableName $TableName -Direction All)

    $notEmpty = { $null -ne $_ -and ("$_").Trim() -ne '' }
    $indexStatements  = @($indexStatements  | Where-Object $notEmpty)
    $grantStatements  = @($grantStatements  | Where-Object $notEmpty)
    $viewStatements   = @($viewStatements   | Where-Object $notEmpty)
    $fkDropStatements = @($fkDropStatements | Where-Object $notEmpty)
    $fkAddStatements  = @($fkAddStatements  | Where-Object $notEmpty)

    $capturedDdl = [PSCustomObject]@{
        Table            = "$Schema.$TableName"
        Schema           = $Schema
        TableName        = $TableName
        CapturedAt       = (Get-Date).ToString('o')
        IndexStatements  = $indexStatements
        GrantStatements  = $grantStatements
        ViewStatements   = $viewStatements
        FkDropStatements = $fkDropStatements
        FkAddStatements  = $fkAddStatements
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
        $parentDir = Split-Path $OutputFile -Parent
        if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        $capturedDdl | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputFile -Encoding utf8 -Force
        Write-LogMessage "  Captured DDL saved to $OutputFile (indexes: $($indexStatements.Count), grants: $($grantStatements.Count), views: $($viewStatements.Count), FKs: $($fkAddStatements.Count))" -Level INFO
    }

    return $capturedDdl
}

function Import-Db2TableDdl {
    <#
    .SYNOPSIS
    Replay previously captured DDL (indexes, grants, views, FKs) onto the current database.
    .DESCRIPTION
    Accepts either a PSCustomObject (from Export-Db2TableDdl) or a JSON file path.
    Replays in order: indexes, views, grants, foreign keys.
    Returns a PSCustomObject with OK counts and totals for each category.
    .PARAMETER InputFile
    Path to a *_captured_ddl.json file produced by Export-Db2TableDdl.
    .PARAMETER DdlObject
    A PSCustomObject with IndexStatements, GrantStatements, ViewStatements, FkAddStatements arrays.
    .PARAMETER ViewOutputDirectory
    Directory for temp view .sql files during replay. Defaults to $env:TEMP.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [string]$InputFile,
        [PSCustomObject]$DdlObject,
        [string]$ViewOutputDirectory = $env:TEMP
    )

    if ($null -eq $DdlObject -and [string]::IsNullOrWhiteSpace($InputFile)) {
        throw "Import-Db2TableDdl: supply either -InputFile or -DdlObject."
    }

    if ($null -eq $DdlObject) {
        if (-not (Test-Path $InputFile)) {
            throw "Import-Db2TableDdl: file not found: $InputFile"
        }
        $DdlObject = Get-Content -Path $InputFile -Raw | ConvertFrom-Json
    }

    $indexStatements = @($DdlObject.IndexStatements  | Where-Object { $null -ne $_ -and ("$_").Trim() -ne '' })
    $viewStatements  = @($DdlObject.ViewStatements   | Where-Object { $null -ne $_ -and ("$_").Trim() -ne '' })
    $grantStatements = @($DdlObject.GrantStatements  | Where-Object { $null -ne $_ -and ("$_").Trim() -ne '' })
    $fkAddStatements = @($DdlObject.FkAddStatements  | Where-Object { $null -ne $_ -and ("$_").Trim() -ne '' })

    Write-LogMessage "  Replaying DDL: $($indexStatements.Count) indexes, $($viewStatements.Count) views, $($grantStatements.Count) grants, $($fkAddStatements.Count) FKs" -Level INFO

    $idxOk = 0
    foreach ($stmt in $indexStatements) {
        $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands @("db2 `"$stmt`"")
        $idxOk++
        Write-LogMessage "    Index OK: $stmt" -Level INFO
    }

    $viewOk = 0
    foreach ($viewDdl in $viewStatements) {
        $ddlText = ($viewDdl | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($ddlText)) {
            throw "Import-Db2TableDdl: empty view DDL text in replay list."
        }
        Invoke-Db2ViewDdlViaFile -WorkObject $WorkObject -ViewDdlText $ddlText -OutputDirectory $ViewOutputDirectory -ActionLabel "recreate"
        $viewOk++
    }

    $grantOk = 0
    foreach ($stmt in $grantStatements) {
        $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands @("db2 `"$stmt`"")
        $grantOk++
        Write-LogMessage "    Grant OK: $stmt" -Level INFO
    }

    $fkOk = 0
    if ($fkAddStatements.Count -gt 0) {
        Write-LogMessage "  Replaying foreign keys..." -Level INFO
        foreach ($stmt in $fkAddStatements) {
            $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands @("db2 `"$stmt`"")
            $fkOk++
            Write-LogMessage "    FK ADD OK: $stmt" -Level INFO
        }
    }

    $summary = [PSCustomObject]@{
        IndexesOk  = $idxOk;  IndexesTotal  = $indexStatements.Count
        ViewsOk    = $viewOk; ViewsTotal    = $viewStatements.Count
        GrantsOk   = $grantOk; GrantsTotal  = $grantStatements.Count
        FksOk      = $fkOk;   FksTotal      = $fkAddStatements.Count
    }
    Write-LogMessage "  DDL replay complete: Indexes $($idxOk)/$($indexStatements.Count) | Views $($viewOk)/$($viewStatements.Count) | Grants $($grantOk)/$($grantStatements.Count) | FKs $($fkOk)/$($fkAddStatements.Count)" -Level INFO
    return $summary
}

#endregion DDL Export / Import

#region Large Table Year-Split — Shared utility and data movement functions

function Get-Db2DatabaseContext {
    <#
    .SYNOPSIS
    Look up a Db2 database in DatabasesV2.json and return context (instance, application, environment).
    .PARAMETER LocalServerOnly
    When set, filters by current server hostname and matches on AccessPoint CatalogName.
    When not set, matches on the Database field (generic/client mode).
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$RequestedDatabaseName = "",
        [switch]$LocalServerOnly
    )

    $selectedDatabaseName = $RequestedDatabaseName
    if ([string]::IsNullOrWhiteSpace($selectedDatabaseName)) {
        $selectedDatabaseName = Get-UserChoiceForDatabaseName -SkipAlias -SkipFederated -ThrowOnTimeout
    }

    $allDbs = Get-DatabasesV2Json | Where-Object { $_.Provider -eq "DB2" -and $_.IsActive -eq $true }

    if ($LocalServerOnly) {
        $dbConfig = $allDbs |
            Where-Object { $_.ServerName -eq $env:COMPUTERNAME } |
            Where-Object {
                $_.AccessPoints | Where-Object {
                    $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" -and $_.CatalogName -eq $selectedDatabaseName
                }
            } |
            Select-Object -First 1
    }
    else {
        $dbConfig = $allDbs |
            Where-Object { $_.Database.ToUpper() -eq $selectedDatabaseName.ToUpper() } |
            Select-Object -First 1
    }

    if ($null -eq $dbConfig) {
        $suffix = if ($LocalServerOnly) { " for server $($env:COMPUTERNAME)" } else { "" }
        throw "Database $($selectedDatabaseName) not found in DatabasesV2.json$suffix."
    }

    $primaryAccessPoint = if ($LocalServerOnly) {
        $dbConfig.AccessPoints |
            Where-Object { $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" -and $_.CatalogName -eq $selectedDatabaseName } |
            Select-Object -First 1
    }
    else {
        $dbConfig.AccessPoints |
            Where-Object { $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" } |
            Select-Object -First 1
    }

    if ($null -eq $primaryAccessPoint) {
        throw "PrimaryDb access point missing for database $($selectedDatabaseName)."
    }

    return [PSCustomObject]@{
        DatabaseName       = if ($LocalServerOnly) { $selectedDatabaseName } else { $dbConfig.Database }
        Application        = $dbConfig.Application
        Environment        = if ($null -ne $dbConfig.PSObject.Properties['Environment']) { $dbConfig.Environment } else { "" }
        ServerName         = if ($null -ne $dbConfig.PSObject.Properties['ServerName']) { $dbConfig.ServerName } else { "" }
        PrimaryCatalogName = if ($null -ne $dbConfig.PSObject.Properties['PrimaryCatalogName']) { $dbConfig.PrimaryCatalogName } else { "" }
        InstanceName       = $primaryAccessPoint.InstanceName
        Port               = if ($null -ne $primaryAccessPoint.PSObject.Properties['Port']) { $primaryAccessPoint.Port } else { "" }
        UserName           = if ($null -ne $primaryAccessPoint.PSObject.Properties['UID']) { $primaryAccessPoint.UID } else { "" }
        Password           = if ($null -ne $primaryAccessPoint.PSObject.Properties['PWD']) { $primaryAccessPoint.PWD } else { "" }
    }
}

function Split-Db2QualifiedTableName {
    <#
    .SYNOPSIS
    Split a schema-qualified table name (SCHEMA.TABLE) into SchemaName and BaseName.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$QualifiedTableName
    )

    $parts = $QualifiedTableName.Split(".")
    if ($parts.Count -ne 2) {
        throw "TableName must be schema-qualified: $($QualifiedTableName)"
    }

    return [PSCustomObject]@{
        SchemaName = $parts[0].Trim().ToUpper()
        BaseName   = $parts[1].Trim().ToUpper()
    }
}

function Test-Db2TableColumnExists {
    <#
    .SYNOPSIS
    Check whether a table and a specific column exist in the Db2 catalog.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$TableName,
        [Parameter(Mandatory)]
        [string]$ColumnName
    )

    $tableExistsSql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$SchemaName' AND TABNAME='$TableName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    $columnExistsSql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.COLUMNS WHERE TABSCHEMA='$SchemaName' AND TABNAME='$TableName' AND COLNAME='$ColumnName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"

    $tableExists = (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $tableExistsSql) -eq "1"
    $columnExists = (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $columnExistsSql) -eq "1"

    return $tableExists -and $columnExists
}

function Test-Db2TableExistsSimple {
    <#
    .SYNOPSIS
    Quick check if a table exists by querying SYSCAT.TABLES with a scalar EXISTS.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    $existsSql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$SchemaName' AND TABNAME='$TableName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    return ((Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $existsSql) -eq "1")
}

function Get-Db2RowCount {
    <#
    .SYNOPSIS
    Return the row count for a schema-qualified table.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$QualifiedTable
    )

    $sql = "SELECT CHAR(COUNT(1)) FROM $QualifiedTable"
    $val = Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sql
    if ([string]::IsNullOrWhiteSpace($val)) { return [int64]0 }
    return [int64]$val
}

function Get-Db2YearCountsForTable {
    <#
    .SYNOPSIS
    Return year-based row counts for a table partitioned by a timestamp column.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$QualifiedTableName,
        [Parameter(Mandatory)]
        [string]$TimestampColumn
    )

    $sql = "SELECT CHAR(YEAR($TimestampColumn)) || CHR(9) || CHAR(COUNT(1)) FROM $QualifiedTableName WHERE $TimestampColumn IS NOT NULL GROUP BY YEAR($TimestampColumn) ORDER BY YEAR($TimestampColumn)"
    $rows = Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $sql

    $result = @()
    foreach ($row in $rows) {
        $parts = $row.Split("`t")
        if ($parts.Count -ge 2) {
            $result += [PSCustomObject]@{
                Year     = [int]$parts[0].Trim()
                RowCount = [int64]$parts[1].Trim()
            }
        }
    }

    return $result
}

function Invoke-Db2BatchDmlAndCount {
    <#
    .SYNOPSIS
    Execute a DML statement with COMMIT and return the count from a follow-up query.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$DmlStatement,
        [Parameter(Mandatory)]
        [string]$CountQuery
    )

    $db2Commands = @()
    $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $db2Commands += Get-ConnectCommand -WorkObject $WorkObject
    $db2Commands += "db2 `"$DmlStatement`""
    $db2Commands += "db2 commit work"
    $db2Commands += "echo __QSTART__"
    $db2Commands += "db2 -x `"$CountQuery`""
    $db2Commands += "echo __QEND__"
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors:$false
    $lines = $output -split "`r?`n"
    $inside = $false
    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq "__QSTART__") { $inside = $true; continue }
        if ($trimmedLine -eq "__QEND__") { break }
        if ($inside -and -not [string]::IsNullOrWhiteSpace($trimmedLine) -and $trimmedLine -notlike "DB20000I*") {
            if ($trimmedLine -match '^[A-Za-z]:\\.*>\s*') { continue }
            return [int64]$trimmedLine.Trim()
        }
    }
    return [int64]0
}

function Invoke-Db2SingleStatement {
    <#
    .SYNOPSIS
    Execute a single SQL statement with connect/disconnect wrapper.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SqlStatement
    )

    $commands = @()
    $commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $commands += Get-ConnectCommand -WorkObject $WorkObject
    $commands += "db2 `"$SqlStatement`""
    $commands += "db2 connect reset"
    $commands += "db2 terminate"
    $null = Invoke-Db2ContentAsScript -Content $commands -ExecutionType BAT -IgnoreErrors:$false
}

function Get-Db2YearSplitTables {
    <#
    .SYNOPSIS
    Discover existing TABLE_YYYY year-partitioned tables for a given base table name.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName
    )

    $sql = "SELECT RTRIM(TABNAME) FROM SYSCAT.TABLES WHERE TABSCHEMA='$SchemaName' AND TYPE='T' AND TABNAME LIKE '$($BaseName)_%' ORDER BY TABNAME"
    $rows = @(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $sql)
    $yearTables = @()
    # Regex: ^BASENAME_(\d{4})$
    #   ^              — start of string
    #   BASENAME_      — literal base name + underscore (escaped for regex)
    #   (\d{4})        — capture group 1: exactly 4 digits (year)
    #   $              — end of string
    foreach ($row in $rows) {
        $tableName = $row.Trim().ToUpper()
        if ($tableName -match "^$([regex]::Escape($BaseName))_(\d{4})$") {
            $yearTables += [PSCustomObject]@{
                SchemaName = $SchemaName
                TableName  = $tableName
                Year       = [int]$matches[1]
            }
        }
    }
    return $yearTables
}

function Get-Db2TmpTablesForBase {
    <#
    .SYNOPSIS
    Check if a TABLE_TMP table exists for a given base table name.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName
    )

    $tmpName = "$($BaseName)_TMP"
    $sql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$SchemaName' AND TYPE='T' AND TABNAME='$tmpName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    $exists = (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sql) -eq "1"
    if ($exists) {
        return @($tmpName)
    }
    return @()
}

function Test-Db2ServerLinkExists {
    <#
    .SYNOPSIS
    Check if a federation server link exists in SYSCAT.SERVERS.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$ServerLinkName
    )

    $sql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.SERVERS WHERE SERVERNAME='$ServerLinkName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    return (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sql) -eq "1"
}

function New-Db2NicknameAndTargetTable {
    <#
    .SYNOPSIS
    Create a federation nickname and, if needed, a target table using DEFINITION ONLY.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$TargetWorkObject,
        [Parameter(Mandatory)]
        [string]$ServerLinkName,
        [Parameter(Mandatory)]
        [string]$RemoteSchema,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    $localNickname = "HST.$($TableName)"
    $targetTable = "$($RemoteSchema).$($TableName)"

    $tableExistsSql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$RemoteSchema' AND TABNAME='$TableName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    $targetExists = (Get-Db2ScalarValue -WorkObject $TargetWorkObject -SqlQuery $tableExistsSql) -eq "1"

    $commands = @()
    $commands += Get-SetInstanceNameCommand -WorkObject $TargetWorkObject
    $commands += Get-ConnectCommand -WorkObject $TargetWorkObject
    $commands += "db2 `"DROP NICKNAME $($localNickname)`" >nul 2>&1"
    $commands += "db2 `"CREATE NICKNAME $($localNickname) FOR $($ServerLinkName).$($RemoteSchema).$($TableName)`""
    if (-not $targetExists) {
        $commands += "db2 `"CREATE TABLE $($targetTable) AS (SELECT * FROM $($localNickname)) DEFINITION ONLY`""
    }
    $commands += "db2 connect reset"
    $commands += "db2 terminate"
    $null = Invoke-Db2ContentAsScript -Content $commands -ExecutionType BAT -IgnoreErrors:$false
}

function New-Db2YearTable {
    <#
    .SYNOPSIS
    Create a TABLE_YYYY year table using CREATE TABLE LIKE if it doesn't exist.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName,
        [Parameter(Mandatory)]
        [int]$ArchiveYear
    )

    $targetBaseName = "$($BaseName)_$($ArchiveYear)"
    $existsSql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$SchemaName' AND TABNAME='$targetBaseName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    $existsValue = Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $existsSql
    if ($existsValue -eq "1") {
        return "$SchemaName.$targetBaseName"
    }

    $createSql = "CREATE TABLE $SchemaName.$targetBaseName LIKE $SchemaName.$BaseName"
    $db2Commands = @()
    $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $db2Commands += Get-ConnectCommand -WorkObject $WorkObject
    $db2Commands += "db2 `"$createSql`""
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 terminate"
    $null = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors:$false

    return "$SchemaName.$targetBaseName"
}

function Remove-Db2YearDataBatched {
    <#
    .SYNOPSIS
    Delete rows for a specific year from a table in batches.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SourceTable,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int]$ArchiveYear,
        [int]$DeleteBatchSize = 50000,
        [int64]$ExpectedRowCount = 0
    )

    $deleteSql = "DELETE FROM (SELECT * FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear FETCH FIRST $DeleteBatchSize ROWS ONLY)"
    $remainSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear"

    $totalDeleted = [int64]0
    $deleteRound = 0
    $remaining = $ExpectedRowCount

    while ($remaining -gt 0) {
        $deleteRound++
        $numDeletes = [Math]::Min(10, [Math]::Ceiling($remaining / $DeleteBatchSize))
        $deleteCommands = @()
        for ($i = 0; $i -lt $numDeletes; $i++) {
            $deleteCommands += "db2 `"$deleteSql`""
            $deleteCommands += "db2 commit work"
        }
        $deleteCommands += "echo __REMAIN_START__"
        $deleteCommands += "db2 -x `"$remainSql`""
        $deleteCommands += "echo __REMAIN_END__"

        $delOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $deleteCommands
        $remainLines = Get-Db2OutputBetweenMarkers -Output $delOutput -StartMarker "__REMAIN_START__" -EndMarker "__REMAIN_END__"
        $newRemaining = if ($remainLines.Count -gt 0) { [int64]$remainLines[0].Trim() } else { [int64]0 }
        $batchDeleted = $remaining - $newRemaining
        $totalDeleted += $batchDeleted
        $remaining = $newRemaining
        Write-LogMessage "  Delete round $($deleteRound): removed $batchDeleted rows ($remaining remaining)" -Level INFO
    }

    return $totalDeleted
}

function Move-Db2YearDataExportLoad {
    <#
    .SYNOPSIS
    Move one year of data from source to target table via EXPORT+LOAD, then delete from source.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SourceTable,
        [Parameter(Mandatory)]
        [string]$TargetTable,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int]$ArchiveYear,
        [int]$DeleteBatchSize = 50000
    )

    $sourceCountSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear"
    $totalSourceRows = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sourceCountSql)
    if ($totalSourceRows -le 0) {
        Write-LogMessage "Year $($ArchiveYear): no rows in $SourceTable to archive." -Level INFO
        return [PSCustomObject]@{ Year = $ArchiveYear; SourceRows = 0; Inserted = 0; Deleted = 0 }
    }

    Write-LogMessage "Year $($ArchiveYear): $totalSourceRows rows in $SourceTable. Using EXPORT+LOAD method." -Level INFO

    $existingTargetSql = "SELECT CHAR(COUNT(1)) FROM $TargetTable"
    $existingTargetCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $existingTargetSql)
    if ($existingTargetCount -ge $totalSourceRows) {
        Write-LogMessage "  Target $TargetTable already has $existingTargetCount rows (source has $($totalSourceRows)). Skipping EXPORT+LOAD, proceeding to delete." -Level INFO
        $targetCount = $existingTargetCount
    }
    else {
        $exportDir = Join-Path (Get-ApplicationDataPath) "YearSplitExport"
        New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
        $tableSafe = $SourceTable.Replace(".", "_")
        $ixfFile = Join-Path $exportDir "$($tableSafe)_$($ArchiveYear).ixf"
        $exportMsgFile = Join-Path $exportDir "$($tableSafe)_$($ArchiveYear)_export.msg"
        $loadMsgFile = Join-Path $exportDir "$($tableSafe)_$($ArchiveYear)_load.msg"

        $phase1Commands = @(
            "db2 export to `"$ixfFile`" of ixf messages `"$exportMsgFile`" select * from $SourceTable where YEAR($TimestampColumn) = $ArchiveYear",
            "db2 load from `"$ixfFile`" of ixf messages `"$loadMsgFile`" insert into $TargetTable nonrecoverable",
            "echo __VERIFY_START__",
            "db2 -x `"SELECT CHAR(COUNT(1)) FROM $TargetTable`"",
            "echo __VERIFY_END__"
        )

        try {
            $phase1Output = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $phase1Commands -IgnoreErrors
        }
        catch {
            Write-LogMessage "  EXPORT+LOAD failed for year $($ArchiveYear): $($_.Exception.Message)" -Level ERROR
            foreach ($f in @($ixfFile, $exportMsgFile, $loadMsgFile)) {
                if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
            }
            throw
        }

        $verifyLines = Get-Db2OutputBetweenMarkers -Output $phase1Output -StartMarker "__VERIFY_START__" -EndMarker "__VERIFY_END__"
        $targetCount = if ($verifyLines.Count -gt 0) { [int64]$verifyLines[0].Trim() } else { [int64]0 }
        Write-LogMessage "  EXPORT+LOAD complete. Target $TargetTable now has $targetCount rows." -Level INFO

        if ($targetCount -eq 0 -and $totalSourceRows -gt 0) {
            Write-LogMessage "  LOAD produced 0 rows. Check load message file: $loadMsgFile" -Level ERROR
            if (Test-Path $loadMsgFile) {
                $loadMessages = Get-Content -Path $loadMsgFile -Raw -ErrorAction SilentlyContinue
                Write-LogMessage "  LOAD messages: $loadMessages" -Level ERROR
            }
            throw "LOAD into $TargetTable failed: 0 rows loaded from $totalSourceRows exported. Aborting delete phase."
        }

        if ($targetCount -lt $totalSourceRows) {
            Write-LogMessage "  Target count $targetCount < source count $($totalSourceRows). Check message files in $exportDir" -Level WARN
        }
    }

    $totalDeleted = Remove-Db2YearDataBatched -WorkObject $WorkObject -SourceTable $SourceTable -TimestampColumn $TimestampColumn -ArchiveYear $ArchiveYear -DeleteBatchSize $DeleteBatchSize -ExpectedRowCount $totalSourceRows
    Write-LogMessage "Year $ArchiveYear archive done (EXPORT+LOAD): $targetCount loaded, $totalDeleted deleted from $SourceTable." -Level INFO

    foreach ($f in @($ixfFile, $exportMsgFile, $loadMsgFile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }

    return [PSCustomObject]@{
        Year       = $ArchiveYear
        SourceRows = $totalSourceRows
        Inserted   = $targetCount
        Deleted    = $totalDeleted
    }
}

function Move-Db2YearDataInsertSelect {
    <#
    .SYNOPSIS
    Move one year of data via INSERT SELECT with NOT LOGGED INITIALLY, then delete from source.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SourceTable,
        [Parameter(Mandatory)]
        [string]$TargetTable,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int]$ArchiveYear,
        [int]$DeleteBatchSize = 50000
    )

    $sourceCountSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear"
    $totalSourceRows = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sourceCountSql)
    if ($totalSourceRows -le 0) {
        Write-LogMessage "Year $($ArchiveYear): no rows in $SourceTable to archive." -Level INFO
        return [PSCustomObject]@{ Year = $ArchiveYear; SourceRows = 0; Inserted = 0; Deleted = 0 }
    }

    Write-LogMessage "Year $($ArchiveYear): $totalSourceRows rows in $SourceTable. Using INSERT SELECT method." -Level INFO

    $insertCommands = @(
        "db2 `"ALTER TABLE $TargetTable ACTIVATE NOT LOGGED INITIALLY`"",
        "db2 `"INSERT INTO $TargetTable SELECT * FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear`"",
        "db2 commit work",
        "echo __COUNT_START__",
        "db2 -x `"SELECT CHAR(COUNT(1)) FROM $TargetTable`"",
        "echo __COUNT_END__"
    )

    $insertOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $insertCommands -IgnoreErrors
    $countLines = Get-Db2OutputBetweenMarkers -Output $insertOutput -StartMarker "__COUNT_START__" -EndMarker "__COUNT_END__"
    $targetCount = if ($countLines.Count -gt 0) { [int64]$countLines[0].Trim() } else { [int64]0 }
    Write-LogMessage "  INSERT SELECT complete. Target $TargetTable now has $targetCount rows." -Level INFO

    if ($targetCount -eq 0 -and $totalSourceRows -gt 0) {
        Write-LogMessage "  INSERT SELECT produced 0 rows. Table $TargetTable may be unavailable if NOT LOGGED INITIALLY rolled back." -Level ERROR
        Write-LogMessage "  Check table state: SELECT STATUS FROM SYSCAT.TABLES WHERE TABNAME='...' -- 'X' means unavailable (must DROP and recreate)." -Level ERROR
        throw "INSERT SELECT into $TargetTable failed: 0 rows inserted from $totalSourceRows source rows. Aborting delete phase."
    }

    if ($targetCount -lt $totalSourceRows) {
        Write-LogMessage "  Target count $targetCount < source count $($totalSourceRows). INSERT may have partially failed." -Level WARN
    }

    $totalDeleted = Remove-Db2YearDataBatched -WorkObject $WorkObject -SourceTable $SourceTable -TimestampColumn $TimestampColumn -ArchiveYear $ArchiveYear -DeleteBatchSize $DeleteBatchSize -ExpectedRowCount $totalSourceRows
    Write-LogMessage "Year $ArchiveYear archive done (INSERT SELECT): $targetCount in target, $totalDeleted deleted from $SourceTable." -Level INFO

    return [PSCustomObject]@{
        Year       = $ArchiveYear
        SourceRows = $totalSourceRows
        Inserted   = $targetCount
        Deleted    = $totalDeleted
    }
}

function Move-Db2YearDataLegacy {
    <#
    .SYNOPSIS
    Move one year of data using batched INSERT+EXCEPT+DELETE (legacy method).
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SourceTable,
        [Parameter(Mandatory)]
        [string]$TargetTable,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int]$ArchiveYear,
        [int]$BatchSize = 10000
    )

    $sourceYearCountSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear"
    $totalSourceRows = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sourceYearCountSql)
    if ($totalSourceRows -le 0) {
        Write-LogMessage "Year $($ArchiveYear): no rows in $SourceTable to archive." -Level INFO
        return [PSCustomObject]@{ Year = $ArchiveYear; SourceRows = 0; Inserted = 0; Deleted = 0 }
    }

    Write-LogMessage "Year $($ArchiveYear): $totalSourceRows rows in $SourceTable to archive in batches of $BatchSize (Legacy method)" -Level INFO

    $insertSql = "INSERT INTO $TargetTable SELECT * FROM (SELECT * FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear EXCEPT SELECT * FROM $TargetTable) AS DIFF FETCH FIRST $BatchSize ROWS ONLY"
    $targetCountSql = "SELECT CHAR(COUNT(1)) FROM $TargetTable"

    $prevTargetCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $targetCountSql)
    $totalInserted = [int64]0
    $insertBatch = 0
    while ($true) {
        $insertBatch++
        $newTargetCount = Invoke-Db2BatchDmlAndCount -WorkObject $WorkObject -DmlStatement $insertSql -CountQuery $targetCountSql
        $batchInserted = $newTargetCount - $prevTargetCount
        if ($batchInserted -le 0) { break }
        $totalInserted += $batchInserted
        $prevTargetCount = $newTargetCount
        $estRemaining = [Math]::Max(0, $totalSourceRows - $totalInserted)
        Write-LogMessage "  Insert batch $($insertBatch): $batchInserted rows -> $TargetTable (target total: $newTargetCount, ~$estRemaining est. remaining)" -Level INFO
    }
    Write-LogMessage "  Insert phase complete: $totalInserted rows copied to $TargetTable." -Level INFO

    $deleteSql = "DELETE FROM (SELECT * FROM $SourceTable WHERE YEAR($TimestampColumn) = $ArchiveYear FETCH FIRST $BatchSize ROWS ONLY)"
    $totalDeleted = [int64]0
    $deleteBatch = 0
    $prevDeleteRemaining = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $sourceYearCountSql)
    while ($prevDeleteRemaining -gt 0) {
        $deleteBatch++
        $newRemaining = Invoke-Db2BatchDmlAndCount -WorkObject $WorkObject -DmlStatement $deleteSql -CountQuery $sourceYearCountSql
        $batchDeleted = $prevDeleteRemaining - $newRemaining
        $totalDeleted += $batchDeleted
        $prevDeleteRemaining = $newRemaining
        Write-LogMessage "  Delete batch $($deleteBatch): $batchDeleted rows removed from $SourceTable ($newRemaining remaining)" -Level INFO
    }
    Write-LogMessage "  Delete phase complete: $totalDeleted rows removed from $SourceTable." -Level INFO

    Write-LogMessage "Year $ArchiveYear archive done (Legacy): $totalInserted inserted into $TargetTable, $totalDeleted deleted from $SourceTable." -Level INFO

    return [PSCustomObject]@{
        Year       = $ArchiveYear
        SourceRows = $totalSourceRows
        Inserted   = $totalInserted
        Deleted    = $totalDeleted
    }
}

function Invoke-Db2RenameAndReload {
    <#
    .SYNOPSIS
    Rename original table to TABLE_TMP, create a new table with LIKE, LOAD only kept rows, replay DDL.
    .DESCRIPTION
    The RenameAndReload method: capture DDL, EXPORT kept rows to IXF, drop FKs/views, RENAME to _TMP,
    rename indexes on _TMP, CREATE LIKE + LOAD, replay all DDL (indexes, views, grants, FKs).
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SourceTable,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int]$CutoffYear
    )

    $tableParts = Split-Db2QualifiedTableName -QualifiedTableName $SourceTable
    $schema = $tableParts.SchemaName
    $baseName = $tableParts.BaseName
    $tmpName = "$($baseName)_TMP"
    $tmpTable = "$schema.$tmpName"

    Write-LogMessage "=== RenameAndReload for $SourceTable ===" -Level INFO
    Write-LogMessage "  Strategy: RENAME original to $tmpTable, CREATE LIKE, EXPORT+LOAD rows where YEAR($TimestampColumn) >= $CutoffYear" -Level INFO

    $tmpExistsSql = "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$schema' AND TABNAME='$tmpName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1"
    if ((Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $tmpExistsSql) -eq "1") {
        throw "Table $tmpTable already exists. A previous RenameAndReload may be incomplete. Resolve manually before retrying."
    }

    $keepCountSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable WHERE YEAR($TimestampColumn) >= $CutoffYear"
    $totalCountSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable"
    $keepCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $keepCountSql)
    $totalCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $totalCountSql)
    $moveOutCount = $totalCount - $keepCount

    Write-LogMessage "  Total rows: $totalCount | Rows to KEEP (year >= $($CutoffYear)): $keepCount | Rows moving to TMP: $moveOutCount" -Level INFO

    if ($keepCount -le 0) {
        Write-LogMessage "  No rows to keep. Skipping RenameAndReload (would create empty table)." -Level WARN
        return [PSCustomObject]@{
            Table = $SourceTable; TotalRows = $totalCount; KeptRows = 0; TmpTableRows = $totalCount
            TmpTable = ""; Method = "RenameAndReload"; Status = "Skipped"
        }
    }

    if ($moveOutCount -le 0) {
        Write-LogMessage "  All rows are already within retention (year >= $CutoffYear). Nothing to move out." -Level INFO
        return [PSCustomObject]@{
            Table = $SourceTable; TotalRows = $totalCount; KeptRows = $keepCount; TmpTableRows = 0
            TmpTable = ""; Method = "RenameAndReload"; Status = "Skipped"
        }
    }

    Write-LogMessage "  Step 1/7: Pre-flight check (FK, triggers)..." -Level INFO
    $preCheck = Test-Db2TableDependencies -WorkObject $WorkObject -Schema $schema -TableName $baseName

    Write-LogMessage "  Steps 2-3c/7: Capturing all DDL (indexes, grants, views, FKs) from SYSCAT..." -Level INFO
    $exportDir = Join-Path (Get-ApplicationDataPath) "RenameAndReload"
    $ddlFile = Join-Path $exportDir "$($schema)_$($baseName)_captured_ddl.json"
    $ddlCapture = Export-Db2TableDdl -WorkObject $WorkObject -Schema $schema -TableName $baseName -OutputFile $ddlFile

    $indexStatements  = @($ddlCapture.IndexStatements)
    $grantStatements  = @($ddlCapture.GrantStatements)
    $viewStatements   = @($ddlCapture.ViewStatements)
    $fkDropStatements = @($ddlCapture.FkDropStatements)
    $fkAddStatements  = @($ddlCapture.FkAddStatements)

    Write-LogMessage "  Step 4/7: EXPORT kept rows to IXF..." -Level INFO
    $ixfFile = Join-Path $exportDir "$($schema)_$($baseName)_keep.ixf"
    $exportMsgFile = Join-Path $exportDir "$($schema)_$($baseName)_export.msg"
    $loadMsgFile = Join-Path $exportDir "$($schema)_$($baseName)_load.msg"

    $exportCommands = @(
        "db2 export to `"$ixfFile`" of ixf messages `"$exportMsgFile`" select * from $SourceTable where YEAR($TimestampColumn) BETWEEN $CutoffYear AND 9999"
    )
    $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $exportCommands -IgnoreErrors
    if (-not (Test-Path $ixfFile)) {
        throw "EXPORT failed: IXF file not created at $ixfFile. Check $exportMsgFile for details."
    }
    $ixfSizeMb = [Math]::Round((Get-Item $ixfFile).Length / 1MB, 1)
    Write-LogMessage "  EXPORT complete: $ixfFile ($($ixfSizeMb) MB)" -Level INFO

    if ($fkDropStatements.Count -gt 0) {
        Write-LogMessage "  Step 4a/7: DROP $($fkDropStatements.Count) foreign key constraint(s) (required before RENAME)..." -Level INFO
        foreach ($stmt in $fkDropStatements) {
            $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands @("db2 `"$stmt`"")
            Write-LogMessage "    FK DROP OK: $stmt" -Level INFO
        }
    }

    Write-LogMessage "  Step 4b+5/7: DROP dependent views then RENAME (with retry loop)..." -Level INFO
    $maxRenameAttempts = 10
    $renameSucceeded = $false
    $allDroppedViews = @()

    for ($attempt = 1; $attempt -le $maxRenameAttempts; $attempt++) {
        $depViewQuery = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) AS VNAME FROM SYSCAT.TABDEP WHERE BSCHEMA='$schema' AND BNAME='$baseName' AND DTYPE='V' ORDER BY TABNAME FETCH FIRST 50 ROWS ONLY"
        $depViewNames = @(Invoke-Db2QueryTsv -WorkObject $WorkObject -SqlQuery $depViewQuery)

        if ($depViewNames.Count -gt 0) {
            Write-LogMessage "    Attempt $($attempt): Found $($depViewNames.Count) dependent view(s), dropping..." -Level INFO
            foreach ($vn in $depViewNames) {
                $viewFullName = $vn.Trim()
                if ([string]::IsNullOrWhiteSpace($viewFullName)) { continue }

                if ($viewFullName -notin $allDroppedViews) {
                    $newViewDdl = @(Get-Db2ViewDdlFromCatalog -WorkObject $WorkObject -Schema ($viewFullName.Split('.')[0]) -TableName ($viewFullName.Split('.')[1]))
                    if ($newViewDdl.Count -gt 0) {
                        foreach ($ddl in $newViewDdl) {
                            $ddlStr = ($ddl | Out-String).Trim()
                            if ($ddlStr -notin ($viewStatements | ForEach-Object { ($_ | Out-String).Trim() })) {
                                $viewStatements += $ddlStr
                            }
                        }
                    }
                }

                $dropCmd = @("db2 `"DROP VIEW $viewFullName`"")
                try {
                    $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $dropCmd -IgnoreErrors
                    Write-LogMessage "    Dropped view $viewFullName" -Level INFO
                    if ($viewFullName -notin $allDroppedViews) { $allDroppedViews += $viewFullName }
                }
                catch {
                    Write-LogMessage "    Failed to drop view $($viewFullName): $($_.Exception.Message)" -Level WARN
                }
            }
        }

        Write-LogMessage "    Attempt $($attempt): RENAME TABLE $SourceTable TO $tmpName..." -Level INFO
        $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands @("db2 `"RENAME TABLE $SourceTable TO $tmpName`"") -IgnoreErrors

        $tmpExistsAfter = (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$schema' AND TABNAME='$tmpName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1") -eq "1"
        $origGone = (Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery "SELECT CASE WHEN EXISTS(SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA='$schema' AND TABNAME='$baseName') THEN '1' ELSE '0' END FROM SYSIBM.SYSDUMMY1") -eq "0"

        if ($tmpExistsAfter -and $origGone) {
            $renameSucceeded = $true
            Write-LogMessage "  RENAME complete on attempt $attempt. Original table is now $tmpTable." -Level INFO
            break
        }
        Write-LogMessage "    Attempt $($attempt): RENAME not yet successful (TMP exists=$tmpExistsAfter, orig gone=$origGone). Retrying..." -Level WARN
    }

    if (-not $renameSucceeded) {
        Write-LogMessage "  RENAME failed after $maxRenameAttempts attempts. Recovering dropped views..." -Level ERROR
        foreach ($viewDdl in $viewStatements) {
            $recoverText = ($viewDdl | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($recoverText)) { continue }
            Invoke-Db2ViewDdlViaFile -WorkObject $WorkObject -ViewDdlText $recoverText -OutputDirectory $exportDir -ActionLabel "recover"
        }
        foreach ($f in @($ixfFile, $exportMsgFile)) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
        throw "RENAME TABLE $SourceTable TO $tmpName failed after $maxRenameAttempts attempts."
    }

    Write-LogMessage "  Step 5b/7: Renaming indexes on $tmpTable to free original names..." -Level INFO
    $null = Rename-Db2TableIndexes -WorkObject $WorkObject -Schema $schema -TableName $tmpName -Suffix '_TMP'

    Write-LogMessage "  Step 6/7: CREATE TABLE $SourceTable LIKE $tmpTable + LOAD..." -Level INFO
    $createAndLoadCommands = @(
        "db2 `"CREATE TABLE $SourceTable LIKE $tmpTable`"",
        "db2 load from `"$ixfFile`" of ixf messages `"$loadMsgFile`" replace into $SourceTable nonrecoverable"
    )

    try {
        $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $createAndLoadCommands
    }
    catch {
        Write-LogMessage "  CREATE+LOAD failed: $($_.Exception.Message)" -Level ERROR
        Write-LogMessage "  *** RECOVERY INSTRUCTIONS ***" -Level ERROR
        Write-LogMessage "  The original data is safe in $tmpTable." -Level ERROR
        Write-LogMessage "  To recover: DROP TABLE $SourceTable (if it was partially created)" -Level ERROR
        Write-LogMessage "  Then: RENAME TABLE $tmpTable TO $baseName" -Level ERROR
        throw
    }

    $newCountSql = "SELECT CHAR(COUNT(1)) FROM $SourceTable"
    $newCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $newCountSql)
    Write-LogMessage "  LOAD complete. New $SourceTable has $newCount rows (expected $keepCount)." -Level INFO

    if ($newCount -eq 0 -and $keepCount -gt 0) {
        Write-LogMessage "  LOAD produced 0 rows. Check $loadMsgFile for errors." -Level ERROR
        Write-LogMessage "  *** RECOVERY INSTRUCTIONS ***" -Level ERROR
        Write-LogMessage "  To recover: DROP TABLE $SourceTable" -Level ERROR
        Write-LogMessage "  Then: RENAME TABLE $tmpTable TO $baseName" -Level ERROR
        if (Test-Path $loadMsgFile) {
            $loadMsg = Get-Content -Path $loadMsgFile -Raw -ErrorAction SilentlyContinue
            Write-LogMessage "  LOAD messages: $loadMsg" -Level ERROR
        }
        throw "LOAD into $SourceTable failed: 0 rows loaded from $keepCount exported."
    }

    Write-LogMessage "  Step 7/7: Replaying captured DDL (indexes, views, grants, FKs)..." -Level INFO
    $ddlCapture.ViewStatements = $viewStatements
    $replayResult = Import-Db2TableDdl -WorkObject $WorkObject -DdlObject $ddlCapture -ViewOutputDirectory $exportDir
    $idxOk = $replayResult.IndexesOk
    $viewOk = $replayResult.ViewsOk
    $grantOk = $replayResult.GrantsOk
    $fkOk = $replayResult.FksOk

    foreach ($f in @($ixfFile, $exportMsgFile, $loadMsgFile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }

    $tmpCountSql = "SELECT CHAR(COUNT(1)) FROM $tmpTable"
    $tmpCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $tmpCountSql)

    Write-LogMessage " " -Level INFO
    Write-LogMessage "=== RenameAndReload COMPLETE ===" -Level INFO
    Write-LogMessage "  New $($SourceTable): $newCount rows (kept year >= $CutoffYear)" -Level INFO
    Write-LogMessage "  TMP $($tmpTable): $tmpCount rows (all original data, for offline year-splitting or DROP)" -Level INFO
    Write-LogMessage "  Indexes: $($idxOk)/$($indexStatements.Count) OK | Views: $($viewOk)/$($viewStatements.Count) OK | Grants: $($grantOk)/$($grantStatements.Count) OK | FK: $($fkOk)/$($fkAddStatements.Count) OK" -Level INFO
    if ($preCheck.TrigCount -gt 0) {
        Write-LogMessage "  ATTENTION: triggers ($($preCheck.TrigCount)) require manual recreation (CREATE TABLE LIKE does not restore trigger bodies)." -Level WARN
    }

    return [PSCustomObject]@{
        Table = $SourceTable; TotalRows = $totalCount; KeptRows = $newCount; TmpTableRows = $tmpCount
        TmpTable = $tmpTable; Indexes = $idxOk; IndexesFail = 0; Grants = $grantOk; GrantsFail = 0
        Views = $viewOk; ViewsFail = 0; FkOk = $fkOk; FkFail = 0; Method = "RenameAndReload"; Status = "Completed"
    }
}

function Move-Db2YearData {
    <#
    .SYNOPSIS
    Dispatcher: move one year of data using the specified method.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SourceTable,
        [Parameter(Mandatory)]
        [string]$TargetTable,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int]$ArchiveYear,
        [string]$Method = "ExportLoad",
        [int]$BatchSize = 10000,
        [int]$DeleteBatchSize = 50000
    )

    switch ($Method) {
        "ExportLoad" {
            return Move-Db2YearDataExportLoad -WorkObject $WorkObject -SourceTable $SourceTable -TargetTable $TargetTable -TimestampColumn $TimestampColumn -ArchiveYear $ArchiveYear -DeleteBatchSize $DeleteBatchSize
        }
        "InsertSelect" {
            return Move-Db2YearDataInsertSelect -WorkObject $WorkObject -SourceTable $SourceTable -TargetTable $TargetTable -TimestampColumn $TimestampColumn -ArchiveYear $ArchiveYear -DeleteBatchSize $DeleteBatchSize
        }
        default {
            return Move-Db2YearDataLegacy -WorkObject $WorkObject -SourceTable $SourceTable -TargetTable $TargetTable -TimestampColumn $TimestampColumn -ArchiveYear $ArchiveYear -BatchSize $BatchSize
        }
    }
}

#endregion Large Table Year-Split

#region Table Shrink — Test-environment table shrink operations

function Invoke-Db2TableShrinkExportLoad {
    <#
    .SYNOPSIS
    Shrink a table by EXPORTing kept rows, renaming original, recreating, and LOADing.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int[]]$KeepYears,
        [switch]$SkipApply,
        [switch]$KeepTmpTable
    )

    $sourceTable = "$($SchemaName).$($BaseName)"
    $keepYearsCsv = ($KeepYears -join ",")

    $keepCountSql = "SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)"
    $expectedRowsToKeep = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $keepCountSql)
    Write-LogMessage "Table $($sourceTable): rows to keep for years $keepYearsCsv = $($expectedRowsToKeep). Using EXPORT+LOAD method." -Level INFO

    if ($SkipApply) {
        Write-LogMessage "SkipApply: would export kept rows to IXF, drop $($sourceTable), recreate and LOAD." -Level WARN
        return [PSCustomObject]@{
            TableName = $sourceTable; TmpTable = ""; ExpectedRows = $expectedRowsToKeep
            CopiedRows = [int64]0; Applied = $false; VerificationOk = $false
        }
    }

    $exportDir = Join-Path (Get-ApplicationDataPath) "ShrinkExport"
    New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
    $tableSafe = $sourceTable.Replace(".", "_")
    $ixfFile = Join-Path $exportDir "$($tableSafe)_keep.ixf"
    $exportMsgFile = Join-Path $exportDir "$($tableSafe)_export.msg"
    $loadMsgFile = Join-Path $exportDir "$($tableSafe)_load.msg"

    $exportCommands = @(
        "db2 export to `"$ixfFile`" of ixf messages `"$exportMsgFile`" select * from $sourceTable where YEAR($TimestampColumn) IN ($keepYearsCsv)",
        "echo __EXPORT_COUNT_START__",
        "db2 -x `"SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)`"",
        "echo __EXPORT_COUNT_END__"
    )
    $exportOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $exportCommands
    $exportCountLines = Get-Db2OutputBetweenMarkers -Output $exportOutput -StartMarker "__EXPORT_COUNT_START__" -EndMarker "__EXPORT_COUNT_END__"
    $verifiedSourceCount = if ($exportCountLines.Count -gt 0) { [int64]$exportCountLines[0].Trim() } else { $expectedRowsToKeep }
    Write-LogMessage "  Exported kept rows to IXF. Source verify count: $verifiedSourceCount" -Level INFO

    $confirmation = Get-UserConfirmationWithTimeout -PromptMessage "Drop original table $($sourceTable) and reload from IXF? (Y/N)" -TimeoutSeconds 60 -AllowedResponses @("Y", "N") -DefaultResponse "N" -ProgressMessage "Confirm table shrink"
    if ($confirmation -ne "Y") {
        throw "User did not confirm shrink for $($sourceTable). IXF file kept at $ixfFile."
    }

    $bkpTable = "$($SchemaName).BKP_$($BaseName)"
    $rebuildCommands = @(
        "db2 `"RENAME TABLE $sourceTable TO BKP_$($BaseName)`"",
        "db2 `"CREATE TABLE $sourceTable LIKE $bkpTable`"",
        "db2 load from `"$ixfFile`" of ixf messages `"$loadMsgFile`" replace into $sourceTable nonrecoverable",
        "echo __LOAD_COUNT_START__",
        "db2 -x `"SELECT CHAR(COUNT(1)) FROM $sourceTable`"",
        "echo __LOAD_COUNT_END__"
    )
    if (-not $KeepTmpTable) {
        $rebuildCommands += "db2 `"DROP TABLE $bkpTable`""
    }

    try {
        $rebuildOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $rebuildCommands -IgnoreErrors
    }
    catch {
        Write-LogMessage "  Rebuild failed for $($sourceTable): $($_.Exception.Message). Backup table BKP_$($BaseName) may still exist." -Level ERROR
        foreach ($f in @($ixfFile, $exportMsgFile, $loadMsgFile)) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
        throw
    }

    $loadCountLines = Get-Db2OutputBetweenMarkers -Output $rebuildOutput -StartMarker "__LOAD_COUNT_START__" -EndMarker "__LOAD_COUNT_END__"
    $loadedRows = if ($loadCountLines.Count -gt 0) { [int64]$loadCountLines[0].Trim() } else { [int64]0 }

    if ($loadedRows -eq 0 -and $expectedRowsToKeep -gt 0) {
        Write-LogMessage "  LOAD produced 0 rows for $($sourceTable). Check load message file: $loadMsgFile" -Level ERROR
        if (Test-Path $loadMsgFile) {
            $loadMessages = Get-Content -Path $loadMsgFile -Raw -ErrorAction SilentlyContinue
            Write-LogMessage "  LOAD messages: $loadMessages" -Level ERROR
        }
    }

    $verificationOk = ($loadedRows -eq $expectedRowsToKeep)
    if ($verificationOk) {
        Write-LogMessage "Verification OK for $($sourceTable): kept rows = $loadedRows." -Level INFO
    } else {
        Write-LogMessage "Verification mismatch for $($sourceTable): expected $($expectedRowsToKeep), got $loadedRows." -Level WARN
    }

    if ($KeepTmpTable) {
        Write-LogMessage "  KeepTmpTable: backup table $bkpTable retained with all original data for offline splitting." -Level INFO
    }

    foreach ($f in @($ixfFile, $exportMsgFile, $loadMsgFile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }

    $returnTmpTable = if ($KeepTmpTable) { $bkpTable } else { "" }
    return [PSCustomObject]@{
        TableName = $sourceTable; TmpTable = $returnTmpTable; ExpectedRows = $expectedRowsToKeep
        CopiedRows = $loadedRows; Applied = $true; VerificationOk = $verificationOk
    }
}

function Invoke-Db2TableShrinkInsertSelect {
    <#
    .SYNOPSIS
    Shrink a table by INSERT SELECT into a TMP table, then drop+rename swap.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int[]]$KeepYears,
        [switch]$SkipApply
    )

    $sourceTable = "$($SchemaName).$($BaseName)"
    $tmpBaseName = "TMP_$($BaseName)"
    $tmpTable = "$($SchemaName).$($tmpBaseName)"
    $keepYearsCsv = ($KeepYears -join ",")

    $keepCountSql = "SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)"
    $expectedRowsToKeep = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $keepCountSql)
    Write-LogMessage "Table $($sourceTable): rows to keep for years $keepYearsCsv = $($expectedRowsToKeep). Using INSERT SELECT method." -Level INFO

    if ($SkipApply) {
        Write-LogMessage "SkipApply: would create $($tmpTable), single INSERT SELECT, drop $($sourceTable), rename." -Level WARN
        return [PSCustomObject]@{
            TableName = $sourceTable; TmpTable = $tmpTable; ExpectedRows = $expectedRowsToKeep
            CopiedRows = [int64]0; Applied = $false; VerificationOk = $false
        }
    }

    if (Test-Db2TableExistsSimple -WorkObject $WorkObject -SchemaName $SchemaName -TableName $tmpBaseName) {
        throw "TMP table already exists: $($tmpTable). Clean up or rename it before rerun."
    }

    $copyCommands = @(
        "db2 `"CREATE TABLE $tmpTable LIKE $sourceTable`"",
        "db2 `"ALTER TABLE $tmpTable ACTIVATE NOT LOGGED INITIALLY`"",
        "db2 `"INSERT INTO $tmpTable SELECT * FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)`"",
        "db2 commit work",
        "echo __COPY_COUNT_START__",
        "db2 -x `"SELECT CHAR(COUNT(1)) FROM $tmpTable`"",
        "echo __COPY_COUNT_END__"
    )

    $copyOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $copyCommands -IgnoreErrors
    $copyCountLines = Get-Db2OutputBetweenMarkers -Output $copyOutput -StartMarker "__COPY_COUNT_START__" -EndMarker "__COPY_COUNT_END__"
    $copiedRows = if ($copyCountLines.Count -gt 0) { [int64]$copyCountLines[0].Trim() } else { [int64]0 }
    Write-LogMessage "  INSERT SELECT complete: $copiedRows rows in $tmpTable." -Level INFO

    if ($copiedRows -eq 0 -and $expectedRowsToKeep -gt 0) {
        Write-LogMessage "  INSERT SELECT produced 0 rows. Table $tmpTable may be unavailable if NOT LOGGED INITIALLY rolled back." -Level ERROR
        Write-LogMessage "  Check table state: SELECT STATUS FROM SYSCAT.TABLES WHERE TABNAME='$($tmpBaseName)' -- 'X' means unavailable (must DROP and recreate)." -Level ERROR
        throw "INSERT SELECT into $tmpTable failed: 0 rows copied. TMP table may need to be dropped manually."
    }

    if ($copiedRows -lt $expectedRowsToKeep) {
        Write-LogMessage "  Copied $copiedRows < expected $($expectedRowsToKeep). Check for INSERT errors." -Level WARN
    }

    $confirmation = Get-UserConfirmationWithTimeout -PromptMessage "Drop original table $($sourceTable) and rename $($tmpTable) to $($BaseName)? (Y/N)" -TimeoutSeconds 60 -AllowedResponses @("Y", "N") -DefaultResponse "N" -ProgressMessage "Confirm table swap"
    if ($confirmation -ne "Y") {
        throw "User did not confirm drop/rename for $($sourceTable). TMP table kept at $($tmpTable)."
    }

    $swapCommands = @(
        "db2 `"DROP TABLE $sourceTable`"",
        "db2 `"RENAME TABLE $tmpTable TO $BaseName`""
    )
    $null = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $swapCommands

    Write-LogMessage "Dropped $sourceTable and renamed $tmpTable -> $($BaseName)" -Level INFO

    $newCountSql = "SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)"
    $newKeptRows = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $newCountSql)
    $verificationOk = ($newKeptRows -eq $expectedRowsToKeep)
    if ($verificationOk) {
        Write-LogMessage "Verification OK for $($sourceTable): kept rows = $newKeptRows." -Level INFO
    } else {
        Write-LogMessage "Verification mismatch for $($sourceTable): expected $($expectedRowsToKeep), got $newKeptRows." -Level WARN
    }

    return [PSCustomObject]@{
        TableName = $sourceTable; TmpTable = $tmpTable; ExpectedRows = $expectedRowsToKeep
        CopiedRows = $copiedRows; Applied = $true; VerificationOk = $verificationOk
    }
}

function Invoke-Db2TableShrinkLegacy {
    <#
    .SYNOPSIS
    Shrink a table using batched INSERT+EXCEPT copy, then drop+rename swap.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int[]]$KeepYears,
        [int]$BatchSize = 100000,
        [switch]$SkipApply
    )

    $sourceTable = "$($SchemaName).$($BaseName)"
    $tmpBaseName = "TMP_$($BaseName)"
    $tmpTable = "$($SchemaName).$($tmpBaseName)"
    $keepYearsCsv = ($KeepYears -join ",")

    $keepCountSql = "SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)"
    $expectedRowsToKeep = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $keepCountSql)
    Write-LogMessage "Table $($sourceTable): rows to keep for years $keepYearsCsv = $($expectedRowsToKeep) (Legacy method)" -Level INFO

    if ($SkipApply) {
        Write-LogMessage "SkipApply: would create $($tmpTable), copy rows in batches of $($BatchSize), drop $($sourceTable), then rename TMP to original." -Level WARN
        return [PSCustomObject]@{
            TableName = $sourceTable; TmpTable = $tmpTable; ExpectedRows = $expectedRowsToKeep
            CopiedRows = [int64]0; Applied = $false; VerificationOk = $false
        }
    }

    if (Test-Db2TableExistsSimple -WorkObject $WorkObject -SchemaName $SchemaName -TableName $tmpBaseName) {
        throw "TMP table already exists: $($tmpTable). Clean up or rename it before rerun."
    }

    $createSql = "CREATE TABLE $tmpTable LIKE $sourceTable"
    Invoke-Db2SingleStatement -WorkObject $WorkObject -SqlStatement $createSql
    Write-LogMessage "Created TMP table: $($tmpTable)" -Level INFO

    $insertSql = "INSERT INTO $tmpTable SELECT * FROM (SELECT * FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv) EXCEPT SELECT * FROM $tmpTable) AS DIFF FETCH FIRST $BatchSize ROWS ONLY"
    $tmpCountSql = "SELECT CHAR(COUNT(1)) FROM $tmpTable"
    $prevTmpCount = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $tmpCountSql)
    $copiedRows = [int64]0
    $batchNo = 0

    while ($true) {
        $batchNo++
        $newTmpCount = Invoke-Db2BatchDmlAndCount -WorkObject $WorkObject -DmlStatement $insertSql -CountQuery $tmpCountSql
        $batchInserted = $newTmpCount - $prevTmpCount
        if ($batchInserted -le 0) { break }
        $copiedRows += $batchInserted
        $prevTmpCount = $newTmpCount
        $remaining = [Math]::Max(0, $expectedRowsToKeep - $copiedRows)
        Write-LogMessage "  Copy batch $($batchNo): inserted $batchInserted, TMP total $newTmpCount, estimated remaining $remaining" -Level INFO
    }

    Write-LogMessage "Copy phase complete for $($sourceTable): copied $copiedRows rows." -Level INFO

    $confirmation = Get-UserConfirmationWithTimeout -PromptMessage "Drop original table $($sourceTable) and rename $($tmpTable) to $($BaseName)? (Y/N)" -TimeoutSeconds 60 -AllowedResponses @("Y", "N") -DefaultResponse "N" -ProgressMessage "Confirm table swap"
    if ($confirmation -ne "Y") {
        throw "User did not confirm drop/rename for $($sourceTable). TMP table kept at $($tmpTable)."
    }

    $dropSql = "DROP TABLE $sourceTable"
    Invoke-Db2SingleStatement -WorkObject $WorkObject -SqlStatement $dropSql
    Write-LogMessage "Dropped original table: $($sourceTable)" -Level WARN

    $renameSql = "RENAME TABLE $tmpTable TO $BaseName"
    Invoke-Db2SingleStatement -WorkObject $WorkObject -SqlStatement $renameSql
    Write-LogMessage "Renamed $($tmpTable) -> $($sourceTable)" -Level INFO

    $newCountSql = "SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($TimestampColumn) IN ($keepYearsCsv)"
    $newKeptRows = [int64](Get-Db2ScalarValue -WorkObject $WorkObject -SqlQuery $newCountSql)
    $verificationOk = ($newKeptRows -eq $expectedRowsToKeep)
    if ($verificationOk) {
        Write-LogMessage "Verification OK for $($sourceTable): kept rows = $newKeptRows." -Level INFO
    } else {
        Write-LogMessage "Verification mismatch for $($sourceTable): expected $($expectedRowsToKeep), got $newKeptRows." -Level WARN
    }

    return [PSCustomObject]@{
        TableName = $sourceTable; TmpTable = $tmpTable; ExpectedRows = $expectedRowsToKeep
        CopiedRows = $copiedRows; Applied = $true; VerificationOk = $verificationOk
    }
}

function Invoke-Db2TableShrink {
    <#
    .SYNOPSIS
    Dispatcher: shrink a table using the specified method (ExportLoad, InsertSelect, or Legacy).
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory)]
        [string]$SchemaName,
        [Parameter(Mandatory)]
        [string]$BaseName,
        [Parameter(Mandatory)]
        [string]$TimestampColumn,
        [Parameter(Mandatory)]
        [int[]]$KeepYears,
        [int]$BatchSize = 100000,
        [string]$Method = "ExportLoad",
        [switch]$SkipApply,
        [switch]$KeepTmpTable
    )

    switch ($Method) {
        "ExportLoad" {
            return Invoke-Db2TableShrinkExportLoad -WorkObject $WorkObject -SchemaName $SchemaName -BaseName $BaseName -TimestampColumn $TimestampColumn -KeepYears $KeepYears -SkipApply:$SkipApply -KeepTmpTable:$KeepTmpTable
        }
        "InsertSelect" {
            return Invoke-Db2TableShrinkInsertSelect -WorkObject $WorkObject -SchemaName $SchemaName -BaseName $BaseName -TimestampColumn $TimestampColumn -KeepYears $KeepYears -SkipApply:$SkipApply
        }
        default {
            return Invoke-Db2TableShrinkLegacy -WorkObject $WorkObject -SchemaName $SchemaName -BaseName $BaseName -TimestampColumn $TimestampColumn -KeepYears $KeepYears -BatchSize $BatchSize -SkipApply:$SkipApply
        }
    }
}

#endregion Table Shrink

#region Backup Header and Archived Log Helpers

function Get-Db2BackupHeaderInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupFilePath,
        [Parameter(Mandatory = $false)]
        [string]$WorkFolder = $env:TEMP
    )

    if (-not (Test-Path -Path $BackupFilePath -PathType Leaf)) {
        throw "Backup file not found: $($BackupFilePath)"
    }

    Write-LogMessage "Parsing backup header from: $($BackupFilePath)" -Level INFO

    $db2Commands = @()
    $db2Commands += "db2ckbkp -H `"$($BackupFilePath)`""

    $scriptFile = Join-Path $WorkFolder "Get-Db2BackupHeaderInfo_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $scriptFile -IgnoreErrors

    $headerInfo = [PSCustomObject]@{
        Timestamp    = ""
        DatabaseName = ""
        InstanceName = ""
        IncludesLogs = $false
        BackupMode   = "Unknown"
        FirstLog     = ""
        LastLog      = ""
        RawOutput    = $output
    }

    if ($output -match "(?i)Backup\s+Timestamp\s*[:\-=]\s*(\d{14})") {
        $headerInfo.Timestamp = $Matches[1]
    }
    elseif ($output -match "(?i)tidsstempel\s*[:\-=]\s*(\d{14})") {
        $headerInfo.Timestamp = $Matches[1]
    }

    if ($output -match "(?i)Database\s+Name\s*[:\-=]\s*(\S+)") {
        $headerInfo.DatabaseName = $Matches[1].Trim()
    }
    elseif ($output -match "(?i)Databasenavn\s*[:\-=]\s*(\S+)") {
        $headerInfo.DatabaseName = $Matches[1].Trim()
    }

    if ($output -match "(?i)Instance\s*[:\-=]\s*(\S+)") {
        $headerInfo.InstanceName = $Matches[1].Trim()
    }
    elseif ($output -match "(?i)Instans\s*[:\-=]\s*(\S+)") {
        $headerInfo.InstanceName = $Matches[1].Trim()
    }

    if ($output -match "(?i)Includes\s+Logs\s*[:\-=]\s*(Yes|1|True)") {
        $headerInfo.IncludesLogs = $true
    }
    elseif ($output -match "(?i)Inkluderer\s+logger\s*[:\-=]\s*(Ja|Yes|1|True)") {
        $headerInfo.IncludesLogs = $true
    }

    if ($output -match "(?i)Backup\s+Mode\s*[:\-=]\s*(Online|Offline)") {
        $headerInfo.BackupMode = $Matches[1]
    }
    elseif ($output -match "(?i)Sikkerhetskopieringsmodus\s*[:\-=]\s*(Online|Offline)") {
        $headerInfo.BackupMode = $Matches[1]
    }

    # Extract first/last log file numbers from header
    if ($output -match "(?i)First\s+log\s+file\s*[:\-=]\s*(S\d+\.LOG)") {
        $headerInfo.FirstLog = $Matches[1]
    }
    if ($output -match "(?i)Last\s+log\s+file\s*[:\-=]\s*(S\d+\.LOG)") {
        $headerInfo.LastLog = $Matches[1]
    }

    Write-LogMessage "Backup header: DB=$($headerInfo.DatabaseName), Timestamp=$($headerInfo.Timestamp), Mode=$($headerInfo.BackupMode), IncludesLogs=$($headerInfo.IncludesLogs)" -Level INFO
    return $headerInfo
}

function Copy-Db2ArchivedLogFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceLogPath,
        [Parameter(Mandatory = $true)]
        [string]$TargetLogPath,
        [Parameter(Mandatory = $false)]
        [string]$LogFileFilter = "S*.LOG",
        [Parameter(Mandatory = $false)]
        [int]$MinLogSequence = -1
    )

    if (-not (Test-Path -Path $SourceLogPath -PathType Container)) {
        throw "Source log path not found: $($SourceLogPath)"
    }

    if (-not (Test-Path -Path $TargetLogPath -PathType Container)) {
        Write-LogMessage "Creating target log path: $($TargetLogPath)" -Level INFO
        New-Item -Path $TargetLogPath -ItemType Directory -Force | Out-Null
    }

    $logFiles = @(Get-ChildItem -Path $SourceLogPath -Filter $LogFileFilter -File -ErrorAction SilentlyContinue)

    if ($MinLogSequence -ge 0) {
        $logFiles = $logFiles | Where-Object {
            # Regex: extract the numeric sequence from SnnnnNNN.LOG
            #   S       — literal prefix
            #   (\d+)   — one or more digits (the log sequence number)
            #   \.LOG   — literal extension
            if ($_.Name -match '^S(\d+)\.LOG$') {
                [int]$Matches[1] -ge $MinLogSequence
            }
            else { $true }
        }
    }

    if ($logFiles.Count -eq 0) {
        Write-LogMessage "No archived log files found in $($SourceLogPath) matching filter $($LogFileFilter) (MinLogSequence=$($MinLogSequence))" -Level WARN
        return 0
    }

    $totalSize = ($logFiles | Measure-Object -Property Length -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-LogMessage "Copying $($logFiles.Count) archived log files ($($totalSizeMB) MB) from $($SourceLogPath) to $($TargetLogPath)" -Level INFO

    foreach ($logFile in $logFiles) {
        Copy-Item -Path $logFile.FullName -Destination $TargetLogPath -Force
    }

    $copiedCount = @(Get-ChildItem -Path $TargetLogPath -Filter $LogFileFilter -File -ErrorAction SilentlyContinue).Count
    Write-LogMessage "Copied $($copiedCount) log files to $($TargetLogPath)" -Level INFO
    return $logFiles.Count
}

#endregion Backup Header and Archived Log Helpers

Export-ModuleMember -Function *
