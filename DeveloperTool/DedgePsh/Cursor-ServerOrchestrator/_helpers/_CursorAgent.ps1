<#
.SYNOPSIS
    High-level helpers for Cursor AI agents. Dot-source this file.
    Depends on _Shared.ps1 (auto-loaded if not already sourced).

.DESCRIPTION
    Provides one-call functions for common server operations:
    - Invoke-ServerCommand:   Run a file on the server, wait for result
    - Invoke-ServerScript:    Run inline PowerShell on the server
    - Get-ServerLog:          Read recent log entries from server log files
    - Test-OrchestratorReady: Check if a specific slot is idle (shows PID if busy)
    - Get-RunningProcess:     Show PID and details of the running command for a slot
    - Get-AllRunningSlots:    List all active running_command_*.json slots on a server
    - Stop-ServerProcess:     Kill the running command for a specific slot
    - Get-ServerStdout:       Peek at stdout of a running command for a specific slot
#>

$_sharedPath = Join-Path $PSScriptRoot "_Shared.ps1"
if (-not (Get-Command -Name Write-CommandFile -ErrorAction SilentlyContinue)) {
    Import-Module GlobalFunctions -Force
    . $_sharedPath
}

$script:DefaultServer = "dedge-server"

function Invoke-ServerCommand {
    <#
    .SYNOPSIS
        Run a file-based command on the server and wait for the result.
        The server-side job runs until completion (no server timeout).
        -Timeout controls how long this client waits for a result (default 30 min).
    .EXAMPLE
        Invoke-ServerCommand -Command '%OptPath%\DedgePshApps\IIS-DeployApp\IIS-RedeployAll.ps1' -Project 'iis-deploy'
        Invoke-ServerCommand -Command '%OptPath%\DedgePshApps\SomeApp\Run.ps1' -Project 'some-app' -Timeout 7200 -ShowWindow
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string]$Arguments = "",
        [string]$ServerName = $script:DefaultServer,
        [string]$Project = "cursor-agent",
        [int]$Timeout = 1800,
        [int]$PollInterval = 15,
        [bool]$CaptureOutput = $true,
        [switch]$ShowWindow
    )

    $running = Read-RunningCommand -ServerName $ServerName -Project $Project
    if ($null -ne $running) {
        Write-Host "WARNING: Slot '$($Project)' on $($ServerName) is BUSY (PID $($running.pid), running $($running.elapsedFormatted)): $($running.command)"
        Write-Host "         Your command will queue and run after the current job finishes."
    }

    $cmdParams = @{
        ServerName    = $ServerName
        Command       = $Command
        Arguments     = $Arguments
        Project       = $Project
        CaptureOutput = $CaptureOutput
    }
    if ($ShowWindow) { $cmdParams.ShowWindow = $true }

    $submissionId = Write-CommandFile @cmdParams

    Write-Host "Command submitted to $($ServerName) (project: $($Project), submissionId: $($submissionId)). Waiting up to $($Timeout)s..."

    $result = Wait-ForResult -ServerName $ServerName -Project $Project `
        -SubmissionId $submissionId `
        -TimeoutSeconds $Timeout -PollIntervalSeconds $PollInterval

    if ($null -eq $result) {
        Write-Host "Timed out waiting. Check Get-ServerStdout -Project '$($Project)' for progress."
        return $null
    }

    Write-Host "[$($result.status)] exit=$($result.exitCode) elapsed=$($result.elapsedSeconds)s (project: $($Project))"

    if ($result.output) {
        $lines = $result.output -split "`n"
        if ($lines.Count -gt 30) {
            Write-Host "--- Output (last 30 of $($lines.Count) lines) ---"
            $lines | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "--- Output ---"
            $lines | ForEach-Object { Write-Host $_ }
        }
    }

    if ($result.errorOutput) {
        Write-Host "--- Errors ---"
        Write-Host $result.errorOutput
    }

    return $result
}

function Invoke-ServerScript {
    <#
    .SYNOPSIS
        Run inline PowerShell on the server via Run-InlineScript.ps1.
    .EXAMPLE
        Invoke-ServerScript -Script 'Get-Service W3SVC | Select-Object Status, Name'
        Invoke-ServerScript -Script 'hostname; ipconfig /all' -Project 'diagnostics'
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

        [string]$ServerName = $script:DefaultServer,
        [string]$Project = "cursor-agent-inline",
        [int]$Timeout = 300,
        [int]$PollInterval = 10
    )

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Script))

    $inlineScriptPath = '%OptPath%\DedgePshApps\Cursor-ServerOrchestrator\_helpers\Run-InlineScript.ps1'

    return Invoke-ServerCommand -Command $inlineScriptPath `
        -Arguments "-EncodedCommand $($encoded)" `
        -ServerName $ServerName -Project $Project `
        -Timeout $Timeout `
        -PollInterval $PollInterval -CaptureOutput $true
}

function Get-ServerLog {
    <#
    .SYNOPSIS
        Read recent log entries from server log files via UNC.
    .PARAMETER LogName
        One of: AllPwshLog, IISDeployApp, DedgeAuth
    .PARAMETER TailLines
        Number of lines from the end to return.
    .PARAMETER FilterPattern
        Optional regex to filter lines (e.g. 'ERROR|FAIL').
    .EXAMPLE
        Get-ServerLog -LogName IISDeployApp -TailLines 30 -FilterPattern 'ERROR'
        Get-ServerLog -LogName AllPwshLog -FilterPattern 'Cursor-ServerOrchestrator'
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AllPwshLog", "IISDeployApp", "DedgeAuth")]
        [string]$LogName,

        [string]$ServerName = $script:DefaultServer,
        [int]$TailLines = 50,
        [string]$FilterPattern = "",
        [string]$Date = ""
    )

    $hostname = $ServerName.Split('.')[0]
    $dateStr = if ($Date) { $Date } else { (Get-Date).ToString("yyyyMMdd") }

    $logPath = switch ($LogName) {
        "AllPwshLog"   { "\\$($hostname)\opt\data\AllPwshLog\FkLog_$($dateStr).log" }
        "IISDeployApp" { "\\$($hostname)\opt\data\IIS-DeployApp\FkLog_$($dateStr).log" }
        "DedgeAuth"       { "\\$($hostname)\opt\data\DedgeAuth\Logs\DedgeAuth-$($dateStr).log" }
    }

    if (-not (Test-Path $logPath)) {
        Write-Host "Log file not found: $($logPath)"
        return @()
    }

    $lines = Get-Content $logPath -Tail $TailLines -ErrorAction SilentlyContinue

    if ($FilterPattern) {
        $lines = $lines | Select-String -Pattern $FilterPattern | ForEach-Object { $_.Line }
    }

    return $lines
}

function Test-OrchestratorReady {
    <#
    .SYNOPSIS
        Check if a specific slot on the orchestrator is idle (no command running).
        Returns $true if idle, $false if busy. Shows PID and elapsed time if busy.
    .EXAMPLE
        Test-OrchestratorReady -Project 'shadow-pipeline'
        Test-OrchestratorReady -ServerName 't-no1fkmmig-db' -Project 'iis-deploy'
    #>
    param(
        [string]$ServerName = $script:DefaultServer,
        [string]$Project = "cursor-agent"
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $commandFile = Join-Path $serverPath "next_command_$($suffix).json"

    $busy = $false

    $running = Read-RunningCommand -ServerName $ServerName -Project $Project
    if ($null -ne $running) {
        Write-Host "Slot '$($Project)' is BUSY on $($ServerName):"
        Write-Host "  PID:     $($running.pid)"
        Write-Host "  Command: $($running.command)"
        Write-Host "  Args:    $($running.arguments)"
        Write-Host "  Project: $($running.project)"
        Write-Host "  Started: $($running.startedAt)"
        Write-Host "  Elapsed: $($running.elapsedFormatted)"
        $busy = $true
    }

    if (Test-Path $commandFile) {
        $content = Get-Content $commandFile -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            Write-Host "Command QUEUED for slot '$($Project)' (next_command_$($suffix).json has content)"
            $busy = $true
        }
    }

    if (-not $busy) {
        $result = Read-ResultFile -ServerName $ServerName -Project $Project
        if ($result) {
            Write-Host "Slot '$($Project)' IDLE on $($ServerName). Last: [$($result.status)] $($result.command) ($($result.completedAt))"
        } else {
            Write-Host "Slot '$($Project)' IDLE on $($ServerName). No previous results."
        }
    }

    return (-not $busy)
}

function Get-AllRunningSlots {
    <#
    .SYNOPSIS
        List all active running_command_*.json slots on a server.
        Returns an array of running command objects with slot suffix info.
    .EXAMPLE
        Get-AllRunningSlots -ServerName 'dedge-server'
    #>
    param(
        [string]$ServerName = $script:DefaultServer
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $runningFiles = Get-ChildItem -Path $serverPath -Filter "running_command_*.json" -File -ErrorAction SilentlyContinue

    if (-not $runningFiles -or $runningFiles.Count -eq 0) {
        Write-Host "No running slots on $($ServerName)"
        return @()
    }

    $slots = @()
    foreach ($file in $runningFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content)) { continue }

        try {
            $running = $content | ConvertFrom-Json
            # ConvertFrom-Json in PS7+ auto-converts ISO dates to DateTime; handle both types
            $startedAt = if ($running.startedAt -is [datetime]) { $running.startedAt } else {
                [datetime]::Parse($running.startedAt, [System.Globalization.CultureInfo]::InvariantCulture)
            }
            $elapsed = (Get-Date) - $startedAt
            $running | Add-Member -NotePropertyName 'elapsedSeconds' -NotePropertyValue ([math]::Round($elapsed.TotalSeconds, 0)) -Force
            $elapsedFmt = '{0:D2}:{1:D2}:{2:D2}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
            $running | Add-Member -NotePropertyName 'elapsedFormatted' -NotePropertyValue $elapsedFmt -Force

            # Extract suffix from filename: running_command_<suffix>.json
            # Regex: after "running_command_" capture everything before ".json"
            $suffixMatch = $file.Name -replace '^running_command_(.+)\.json$', '$1'
            $running | Add-Member -NotePropertyName 'slotSuffix' -NotePropertyValue $suffixMatch -Force
            $running | Add-Member -NotePropertyName 'fileName' -NotePropertyValue $file.Name -Force

            $slots += $running

            Write-Host "  Slot [$($suffixMatch)] PID=$($running.pid) $($running.command) ($($elapsedFmt))"
        } catch {
            Write-Host "  (failed to parse $($file.Name))"
        }
    }

    Write-Host "$($slots.Count) running slot(s) on $($ServerName)"
    return $slots
}

function Get-RunningProcess {
    <#
    .SYNOPSIS
        Show the currently running command for a specific slot on a server.
        Returns the running command object or $null if idle.
    .EXAMPLE
        Get-RunningProcess -ServerName 't-no1fkmmig-db' -Project 'shadow-pipeline'
    #>
    param(
        [string]$ServerName = $script:DefaultServer,
        [string]$Project = "cursor-agent"
    )

    $running = Read-RunningCommand -ServerName $ServerName -Project $Project
    if ($null -eq $running) {
        Write-Host "No command running on $($ServerName) for project '$($Project)'"
        return $null
    }

    Write-Host "Running on $($ServerName) (project: $($Project)):"
    Write-Host "  PID:         $($running.pid)"
    Write-Host "  Command:     $($running.command)"
    Write-Host "  Arguments:   $($running.arguments)"
    Write-Host "  Project:     $($running.project)"
    Write-Host "  RequestedBy: $($running.requestedBy)"
    Write-Host "  Started:     $($running.startedAt)"
    Write-Host "  Elapsed:     $($running.elapsedFormatted) ($($running.elapsedSeconds)s)"
    return $running
}

function Stop-ServerProcess {
    <#
    .SYNOPSIS
        Kill the running command for a specific slot on a server.
    .EXAMPLE
        Stop-ServerProcess -ServerName 't-no1fkmmig-db' -Project 'shadow-pipeline' -Reason 'Stuck on phase 2b'
    #>
    param(
        [string]$ServerName = $script:DefaultServer,
        [string]$Project = "cursor-agent",
        [string]$Reason = ""
    )

    return Stop-RunningCommand -ServerName $ServerName -Project $Project -Reason $Reason
}

function Get-ServerStdout {
    <#
    .SYNOPSIS
        Peek at the live stdout of a running orchestrator command for a specific slot.
    .PARAMETER TailLines
        Number of lines from the end to show.
    .EXAMPLE
        Get-ServerStdout -Project 'shadow-pipeline' -TailLines 50
    #>
    param(
        [string]$ServerName = $script:DefaultServer,
        [string]$Project = "cursor-agent",
        [int]$TailLines = 30
    )

    $serverPath = Get-OrchestratorServerPath -ServerName $ServerName
    $suffix = Get-SlotSuffix -Project $Project
    $stdoutFile = Join-Path $serverPath "stdout_capture_$($suffix).txt"

    if (-not (Test-Path $stdoutFile)) {
        Write-Host "No stdout file for slot '$($Project)' (stdout_capture_$($suffix).txt does not exist)"
        return @()
    }

    $lines = Get-Content $stdoutFile -Tail $TailLines -ErrorAction SilentlyContinue
    if ($lines) {
        $lines | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "(stdout file exists but is empty or locked)"
    }
    return $lines
}
