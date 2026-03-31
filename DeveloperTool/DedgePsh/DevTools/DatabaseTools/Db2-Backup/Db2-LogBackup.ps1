
<#
    PowerShell translation of the REXX script for DB2 log backup.
    This script copies DB2 log files to backup destinations, tracking the last copied log.
    Only the FKMPRD database is implemented, as in the original.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DbName
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name Infrastructure -Force
Import-Module -Name Db2-Handler -Force

# function Write-LogMessage {
#     param(
#         [string]$Message,
#         [string]$Level = "INFO"
#     )
#     $timestamp = Get-Date -Format "HH:mm:ss"
#     Write-Host "$timestamp $Message"
# }

# function Invoke-Db2ContentAsScript2 {
#     param(
#         [Parameter(Mandatory = $true)]
#         $Content,
#         [Parameter(Mandatory = $true)]
#         [string]$ExecutionType,
#         [string]$FileName = ""
#     )
#     $workFolder = Get-ApplicationDataPath
#     if ([string]::IsNullOrEmpty($FileName)) {
#         $getDate = Get-Date -Format "yyyyMMddHHmmss"
#         $FileName = Join-Path $workFolder "_gen_db2_script_$($getDate).bat"
#     }

#     if ($Content -is [array]) {
#         $Content = $Content -join "`n"
#     }
#     else {
#         $Content = [string] $Content
#     }

#     [System.IO.File]::WriteAllText($FileName, $Content, [System.Text.Encoding]::GetEncoding(1252))

#     if ($ExecutionType -eq "BAT") {
#         $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $FileName" -NoNewWindow -PassThru -Wait
#         if ($process.ExitCode -ne 0) {
#             Write-LogMessage "DB2 command failed with exit code $($process.ExitCode)" -Level ERROR
#             throw "DB2 command failed"
#         }
#     }
#     elseif ($ExecutionType -eq "SQL") {
#         $db2cmdExe = Get-CommandPathWithFallback -Name "db2cmd"
#         $db2cmdLocal = "$($db2cmdExe) -w -c $FileName"
#         Write-LogMessage "Executing command: $db2cmdLocal" -Level INFO
#         Invoke-Expression $db2cmdLocal
#     }

#     return $FileName
# }

function Copy-Db2Log {
    param(
        [string]$Db,
        [string]$Instance,
        [string]$SourceDir,
        [string]$TargetDir,
        [string]$Server
    )

    $logFile = "DB2LOGCOPY_${Db}.LOG"
    $sparFile = "DB2LOGCOPY_${Db}.SPAR"

    # Find latest log number
    $lognr = Get-LatestLogNumber -Db $Db -Instance $Instance
    if (-not $lognr) {
        Write-LogMessage "Fant ikke siste lognr!"
        return
    }
    $sisteLog = ("S{0:D7}.LOG" -f [int]$lognr)

    # Find last copied log number
    $sistKopiert = Get-LastCopiedLog -SparFile $sparFile
    if (-not $sistKopiert) { $sistKopiert = [int]$lognr - 10 }
    if ($sistKopiert -eq $lognr) {
        $currentMessage = "$Instance\$Db Siste log: $sisteLog. Ingen nye logger å kopiere."
        Write-LogMessage -Message $currentMessage -LogFilePath $logFile
        return
    }
    $currentMessage = "$Instance\$Db Siste log   : $sisteLog"
    Write-LogMessage -Message $currentMessage -LogFilePath $logFile
    $currentMessage = "$Instance\$Db Sist kopiert: S{0:D7}.LOG" -f [int]$sistKopiert
    Write-LogMessage -Message $currentMessage -LogFilePath $logFile

    for ($kopinr = $sistKopiert + 1; $kopinr -le $lognr; $kopinr++) {
        $kopierLog = ("S{0:D7}.LOG" -f $kopinr)
        $currentMessage = "$Instance\$Db Kopierer $kopierLog"
        Write-LogMessage -Message $currentMessage -LogFilePath $logFile

        $src = Join-Path $SourceDir $kopierLog
        $dst = $TargetDir

        # Use COPY command like in REXX script
        $copyCmd = "COPY `"$src`" `"$dst*.*`""
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $copyCmd" -NoNewWindow -PassThru -Wait

        if ($process.ExitCode -ne 0) {
            $currentMessage = "Feil ved kopiering av log fra $src til $dst Rc: $($process.ExitCode)"
            Write-LogMessage -Message $currentMessage -LogFilePath $logFile
            Send-FkAlert -Program "Db2-LogBackup" -Code "1300" -Message $currentMessage
            & "c:\report-Db2Backups.bat" $Server "log" "fail" "$Server-logcopy-$Db"
            break
        }

        # Success
        Send-FkAlert -Program "Db2-LogBackup" -Code "0000" -Message $currentMessage -Force
        Set-Content -Path $sparFile -Value $kopinr
    }
}

function Get-LastCopiedLog {
    param([string]$SparFile)
    $sistKopiert = 0
    if (Test-Path $SparFile) {
        $sistKopiert = Get-Content $SparFile | Select-Object -First 1
        return [int]$sistKopiert
    }
    return $sistKopiert
}

function Get-LatestLogNumber {
    param(
        [string]$Db,
        [string]$Instance
    )
    $lognr = ""
    $dbcfgFile = "C:\WKAKT\dbcfg_${Db}.txt"
    if (Test-Path $dbcfgFile) { Remove-Item $dbcfgFile -Force }

    # Attach to instance and get db config
    $db2Commands = @()
    $db2Commands += "db2 attach to $Instance"
    $db2Commands += "db2 +o -r$dbcfgFile get db configuration for $Db"
    $db2Commands += "db2 detach"

    $null = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors

    if (Test-Path $dbcfgFile -PathType Leaf) {
        $lines = Get-Content $dbcfgFile
        foreach ($line in $lines) {
            if ($line -match "Første aktive loggfil") {
                if ($line -match "S(\d+)\.LOG") {
                    $lognr = $matches[1]
                    break
                }
            }
        }
        Remove-Item $dbcfgFile -Force
    }
    return $lognr
}

############################################################################
# Main logic
############################################################################
Write-LogMessage "Db2-LogBackup started" -Level JOB_STARTED

$WKAKT = "C:\WKAKT\DB2LOGCOPY.AKT"
if (Test-Path $WKAKT -PathType Leaf) {
    Write-LogMessage "Avslutter da rutinen allerede er igang."
    Start-Sleep -Seconds 5
    exit
}
Set-Content -Path $WKAKT -Value "Vi er aktive!"

try {
    $db = $DbName.ToUpper()
    switch ($db) {
        "FKMPRD" {
            $srv = "p-no1fkmprd-db"
            $inst = "DB2"
            $fradir = "F:\Db2PrimaryLogs\NODE0000\LOGSTREAM0000\"
            $tildir1 = "\\p-no1bck-01\BackupDB2\$env:COMPUTERNAME\Log\"
            Copy-Db2Log -Db $db -Instance $inst -SourceDir $fradir -TargetDir $tildir1 -Server $srv
        }
        default {
            Write-LogMessage "Database $db is not supported in this script." "ERROR"
        }
    }
    Write-LogMessage "Db2-LogBackup completed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "Db2-LogBackup failed" -Level JOB_FAILED
    Send-FkAlert -Program "Db2-LogBackup" -Code "9999" -Message "Db2-LogBackup failed" -Force
}
finally {
    Remove-Item $WKAKT -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

