<#
.SYNOPSIS
    Monitors DB2 backup progress by polling LIST UTILITIES SHOW DETAIL and shows a Windows Forms progress bar.

.DESCRIPTION
    Runs "db2 LIST UTILITIES SHOW DETAIL" (using Db2-Handler), searches for Type = BACKUP,
    extracts "Beregnet prosentdel fullført" (estimated percent complete) from the backup block,
    and updates a progress bar every 20 seconds until the backup reaches 100% or finishes.
    If no backup is running, exits with a log message. When a backup was being monitored,
    the final progress bar value is set to 100 before exit.

.EXAMPLE
    .\Db2-BackupProgress.ps1
    Starts monitoring and shows the progress form until backup completes or none is found.
#>

[CmdletBinding()]
param()

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$PollIntervalSeconds = 20

# Regex: find "Type = BACKUP" line in db2 LIST UTILITIES output
#   Type     - literal "Type"
#   \s+     - one or more whitespace (aligns with DB2 column output)
#   =       - literal equals
#   \s+     - optional spaces before value
#   BACKUP  - literal type name (match only backup utilities)
$RegexTypeBackup = 'Type\s+=\s+BACKUP'

# Regex: extract percent number from line containing "prosentdel" (Norwegian "percent")
#   prosentdel - literal text (Beregnet prosentdel fullført)
#   .*?       - non-greedy any chars up to =
#   =         - literal equals
#   \s*       - optional spaces
#   (\d+)     - capture group 1: one or more digits (the percentage 0-100)
$RegexProsentdelNumber = 'prosentdel.*?=\s*(\d+)'

function Get-Db2ListUtilitiesOutput {
    try {
        $output, $errorFound = Invoke-Db2CommandOld -Command "db2 LIST UTILITIES SHOW DETAIL" -IgnoreErrors:$true
        return $output
    }
    catch {
        Write-LogMessage "Failed to run db2 LIST UTILITIES SHOW DETAIL: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $null
    }
}

function Test-BackupBlockPresent {
    param([string]$Output)
    if ([string]::IsNullOrWhiteSpace($Output)) { return $false }
    return $Output -match $RegexTypeBackup
}

function Get-BackupBlockLines {
    param([string]$Output)
    $lines = $Output -split "`r?`n"
    $inBackupBlock = $false
    $blockLines = [System.Collections.ArrayList]@()
    foreach ($line in $lines) {
        if ($line -match $RegexTypeBackup) {
            $inBackupBlock = $true
            $null = $blockLines.Add($line)
            continue
        }
        if ($inBackupBlock) {
            if ($line -match '^\s*Type\s+=') { break }
            $null = $blockLines.Add($line)
        }
    }
    return $blockLines
}

function Get-BackupPercentFromBlock {
    param([System.Collections.ArrayList]$BlockLines)
    $blockText = $BlockLines -join "`n"
    if ($blockText -match $RegexProsentdelNumber) {
        return [int]$matches[1]
    }
    return $null
}

function Get-BackupProgressPercent {
    param([string]$Output)
    if (-not (Test-BackupBlockPresent -Output $Output)) { return $null }
    $blockLines = Get-BackupBlockLines -Output $Output
    return Get-BackupPercentFromBlock -BlockLines $blockLines
}

# --- Main ---
try {
    Write-LogMessage "$(Get-InitScriptName)" -Level JOB_STARTED

    $rawOutput = Get-Db2ListUtilitiesOutput
    if ($null -eq $rawOutput) {
        Write-LogMessage "No output from db2 LIST UTILITIES SHOW DETAIL." -Level WARN
        exit 1
    }

    if (-not (Test-BackupBlockPresent -Output $rawOutput)) {
        Write-LogMessage "No current backup job." -Level INFO
        exit 0
    }

    $blockLines = Get-BackupBlockLines -Output $rawOutput
    $percent = Get-BackupPercentFromBlock -BlockLines $blockLines
    if ($null -eq $percent) {
        Write-LogMessage "prosentdel not found in backup block." -Level WARN
        exit 1
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "DB2 backup progress"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.Size = New-Object System.Drawing.Size(420, 120)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Topmost = $true

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "DB2 backup in progress"
    $heading.Location = New-Object System.Drawing.Point(12, 12)
    $heading.AutoSize = $true
    $form.Controls.Add($heading)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = [Math]::Min(100, [Math]::Max(0, $percent))
    $progressBar.Location = New-Object System.Drawing.Point(12, 38)
    $progressBar.Size = New-Object System.Drawing.Size(380, 24)
    $form.Controls.Add($progressBar)

    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()

    $backupWasRunning = $true
    while ($backupWasRunning) {
        Start-Sleep -Seconds $PollIntervalSeconds
        [System.Windows.Forms.Application]::DoEvents()

        $rawOutput = Get-Db2ListUtilitiesOutput
        if ($null -eq $rawOutput) {
            $percent = 100
            $backupWasRunning = $false
            break
        }

        if (-not (Test-BackupBlockPresent -Output $rawOutput)) {
            $percent = 100
            $backupWasRunning = $false
            break
        }

        $percent = Get-BackupProgressPercent -Output $rawOutput
        if ($null -eq $percent) {
            $percent = $progressBar.Value
        }
        else {
            $progressBar.Value = [Math]::Min(100, [Math]::Max(0, $percent))
            $form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
            if ($percent -ge 100) {
                $backupWasRunning = $false
            }
        }
    }

    $progressBar.Value = 100
    $heading.Text = "DB2 backup complete"
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Seconds 2
    $form.Close()
    $form.Dispose()

    Write-LogMessage "$(Get-InitScriptName)" -Level JOB_COMPLETED
    exit 0
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_.Exception
    Write-LogMessage "$(Get-InitScriptName)" -Level JOB_FAILED
    exit 9
}
