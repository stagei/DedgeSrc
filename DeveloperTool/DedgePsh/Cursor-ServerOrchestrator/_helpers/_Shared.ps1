<#
.SYNOPSIS
    Shared helpers for Cursor-ServerOrchestrator. Dot-source this file.

.DESCRIPTION
    Provides utility functions for the orchestrator and its project scripts:
    - Get-SlotSuffix: Builds a _username_project suffix for file naming
    - Get-OrchestratorDataPath: Returns the data folder path on the current server
    - Get-OrchestratorServerPath: Returns the UNC path to a server's data folder
    - Write-CommandFile: Writes a suffixed command JSON file to a target server
    - Read-ResultFile: Reads the last result JSON for a specific slot
    - Read-RunningCommand: Reads the running command info for a specific slot
    - Write-KillFile: Writes a kill signal for a specific slot
    - Stop-RunningCommand: Kills the running command for a specific slot
    - Wait-ForResult: Polls for a new result file for a specific slot
#>

function Get-SlotSuffix {
    param(
        [string]$Username,
        [string]$Project
    )
    $u = if ($Username) { $Username } else { $env:USERNAME }
    $p = if ($Project) { $Project } else { "default" }
    # Sanitize project name: only alphanumeric, underscore, hyphen
    # Regex: [^...] matches any char NOT in the set; replace with underscore
    $p = $p -replace '[^a-zA-Z0-9_\-]', '_'
    return "$($u)_$($p)"
}

function Get-OrchestratorDataPath {
    $optPath = $env:OptPath
    if ([string]::IsNullOrWhiteSpace($optPath)) {
        $optPath = "C:\opt"
    }
    return Join-Path $optPath "data" "Cursor-ServerOrchestrator"
}

function Get-OrchestratorServerPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName
    )
    $hostname = $ServerName.Split('.')[0]
    return "\\$($hostname)\opt\data\Cursor-ServerOrchestrator"
}

function Write-CommandFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = "",

        [Parameter(Mandatory = $false)]
        [string]$Project = "cursor-agent",

        [Parameter(Mandatory = $false)]
        [bool]$CaptureOutput = $true,

        [Parameter(Mandatory = $false)]
        [switch]$ShowWindow
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $commandFile = Join-Path $serverPath "next_command_$($suffix).json"

    $submissionId = [guid]::NewGuid().ToString("N").Substring(0, 12)

    $cmdObj = [ordered]@{
        command       = $Command
        arguments     = $Arguments
        project       = $Project
        requestedBy   = $env:USERNAME
        requestedAt   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        submissionId  = $submissionId
        captureOutput = $CaptureOutput
        showWindow    = [bool]$ShowWindow
    }

    $json = $cmdObj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($commandFile, $json, [System.Text.Encoding]::UTF8)

    Write-LogMessage "Command written to $($commandFile) (submissionId: $($submissionId))" -Level INFO
    return $submissionId
}

function Read-ResultFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [string]$Project = "cursor-agent"
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $resultFile = Join-Path $serverPath "last_result_$($suffix).json"

    if (-not (Test-Path $resultFile)) {
        return $null
    }

    $content = Get-Content $resultFile -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    return ($content | ConvertFrom-Json)
}

function Write-KillFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [string]$Project = "cursor-agent",

        [Parameter(Mandatory = $false)]
        [string]$Reason = "Kill requested by $($env:USERNAME)"
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $killFile = Join-Path $serverPath "kill_command_$($suffix).txt"

    [System.IO.File]::WriteAllText($killFile, $Reason, [System.Text.Encoding]::UTF8)
    Write-LogMessage "Kill signal written to $($killFile)" -Level WARN
}

function Read-RunningCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [string]$Project = "cursor-agent"
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $runningFile = Join-Path $serverPath "running_command_$($suffix).json"

    if (-not (Test-Path $runningFile)) {
        return $null
    }

    $content = Get-Content $runningFile -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    $running = $content | ConvertFrom-Json
    # ConvertFrom-Json in PS7+ auto-converts ISO dates to DateTime; handle both types
    $startedAt = if ($running.startedAt -is [datetime]) { $running.startedAt } else {
        [datetime]::Parse($running.startedAt, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $elapsed = (Get-Date) - $startedAt
    $running | Add-Member -NotePropertyName 'elapsedSeconds' -NotePropertyValue ([math]::Round($elapsed.TotalSeconds, 0)) -Force
    $elapsedFmt = '{0:D2}:{1:D2}:{2:D2}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
    $running | Add-Member -NotePropertyName 'elapsedFormatted' -NotePropertyValue $elapsedFmt -Force
    $running | Add-Member -NotePropertyName 'slotSuffix' -NotePropertyValue $suffix -Force
    return $running
}

function Stop-RunningCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [string]$Project = "cursor-agent",

        [Parameter(Mandatory = $false)]
        [string]$Reason = ""
    )

    $running = Read-RunningCommand -ServerName $ServerName -Project $Project
    if ($null -eq $running) {
        Write-Host "No command currently running on $($ServerName) for project '$($Project)'"
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Reason)) {
        $Reason = "Kill requested by $($env:USERNAME) for PID $($running.pid) (project: $($Project))"
    }

    Write-Host "Killing PID $($running.pid) on $($ServerName): $($running.command) (project: $($Project), running $($running.elapsedFormatted))"
    Write-KillFile -ServerName $ServerName -Project $Project -Reason $Reason
    return $true
}

function Wait-ForResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [string]$Project = "cursor-agent",

        [Parameter(Mandatory = $false)]
        [string]$SubmissionId = "",

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300,

        [Parameter(Mandatory = $false)]
        [int]$PollIntervalSeconds = 15
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $resultFile = Join-Path $serverPath "last_result_$($suffix).json"

    $initialModTime = $null
    if (Test-Path $resultFile) {
        $initialModTime = (Get-Item $resultFile).LastWriteTime
    }

    $startWait = Get-Date
    while (((Get-Date) - $startWait).TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $PollIntervalSeconds

        if (Test-Path $resultFile) {
            $currentModTime = (Get-Item $resultFile).LastWriteTime
            if ($null -eq $initialModTime -or $currentModTime -gt $initialModTime) {
                $result = Read-ResultFile -ServerName $ServerName -Project $Project
                if ($null -eq $result) { continue }

                if ($SubmissionId -and $result.submissionId -and $result.submissionId -ne $SubmissionId) {
                    Write-LogMessage "Result submissionId '$($result.submissionId)' does not match expected '$($SubmissionId)' - stale result from prior run, continuing to wait..." -Level WARN
                    $initialModTime = $currentModTime
                    continue
                }

                return $result
            }
        }
    }

    Write-LogMessage "Timed out waiting for result from $($ServerName) (project: $($Project)) after $($TimeoutSeconds)s" -Level WARN
    return $null
}
