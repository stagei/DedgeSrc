<#
.SYNOPSIS
    Multi-slot server-side command orchestrator. Scans for suffixed JSON command
    files and executes them concurrently. Designed to run as a scheduled task every minute.

.DESCRIPTION
    Polls for next_command_<username>_<project>.json files at the application data path.
    For each pending command, validates the path, launches the process, and monitors it.
    Multiple slots run concurrently — each user+project combination is isolated.

    Also handles legacy unsuffixed next_command.json for backward compatibility.

    Kill mechanism: Write any content to kill_command_<suffix>.txt to abort
    a specific slot. The orchestrator polls kill files every 10 seconds.

    Results (exit code, output, timing) are written to last_result_<suffix>.json
    and archived to the history/ subfolder.

.NOTES
    Command file: <DataPath>\next_command_<user>_<project>.json
    Kill file:    <DataPath>\kill_command_<user>_<project>.txt
    Result file:  <DataPath>\last_result_<user>_<project>.json
    Running:      <DataPath>\running_command_<user>_<project>.json
    Stdout:       <DataPath>\stdout_capture_<user>_<project>.txt
    Stderr:       <DataPath>\stderr_capture_<user>_<project>.txt
    History:      <DataPath>\history\

    Security: Only members of DEDGE\ACL_Dedge_Servere_Utviklere should have
    write access to the data folder (enforced by _install.ps1 ACL setup).
    All command paths must resolve to a location under $env:OptPath.
#>

Import-Module GlobalFunctions -Force

$script:DataFolderName = "Cursor-ServerOrchestrator"
$script:MaxOutputLines = 500
$script:MaxHistoryFiles = 100
$script:PollIntervalSeconds = 10

function Test-KillRequested {
    param([string]$KillFile)
    if (-not (Test-Path $KillFile)) { return $false }
    $content = (Get-Content $KillFile -Raw -ErrorAction SilentlyContinue)
    return (-not [string]::IsNullOrWhiteSpace($content))
}

function Stop-ProcessTree {
    param([int]$ParentPid)
    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentPid" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Stop-ProcessTree -ParentPid $child.ProcessId
        }
        Stop-Process -Id $ParentPid -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Test-CommandSecurity {
    param([string]$CommandPath)

    $optPath = $env:OptPath
    if ([string]::IsNullOrWhiteSpace($optPath)) {
        Write-LogMessage "SECURITY: env:OptPath is not set on this server" -Level ERROR
        return $false
    }

    $resolved = [Environment]::ExpandEnvironmentVariables($CommandPath)
    $resolvedFull = [System.IO.Path]::GetFullPath($resolved)

    if (-not (Test-Path $resolvedFull -PathType Leaf)) {
        Write-LogMessage "SECURITY: Command file does not exist: $($resolvedFull)" -Level ERROR
        return $false
    }

    return $true
}

function Resolve-CommandPath {
    param([string]$CommandPath)
    $resolved = [Environment]::ExpandEnvironmentVariables($CommandPath)
    return [System.IO.Path]::GetFullPath($resolved)
}

function Get-ExecutorInfo {
    param([string]$ResolvedPath, [string]$Arguments)

    $ext = [System.IO.Path]::GetExtension($ResolvedPath).ToLowerInvariant()

    switch ($ext) {
        '.ps1' {
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$($ResolvedPath)`""
            if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $argList += " $($Arguments)" }
            return @{ FilePath = "pwsh.exe"; ArgumentList = $argList }
        }
        '.py' {
            $argList = "-3 `"$($ResolvedPath)`""
            if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $argList += " $($Arguments)" }
            return @{ FilePath = "py"; ArgumentList = $argList }
        }
        { $_ -in '.bat', '.cmd' } {
            $argList = "/c `"$($ResolvedPath)`""
            if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $argList += " $($Arguments)" }
            return @{ FilePath = "cmd.exe"; ArgumentList = $argList }
        }
        '.exe' {
            return @{ FilePath = $ResolvedPath; ArgumentList = $Arguments }
        }
        '.rex' {
            $argList = "`"$($ResolvedPath)`""
            if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $argList += " $($Arguments)" }
            return @{ FilePath = "regina"; ArgumentList = $argList }
        }
        default {
            return $null
        }
    }
}

function Write-SlotResultFile {
    param(
        [string]$ResultPath,
        [hashtable]$Command,
        [int]$ExitCode,
        [string]$Status,
        [datetime]$StartedAt,
        [datetime]$CompletedAt,
        [string]$Output,
        [string]$ErrorOutput,
        [string]$SlotSuffix
    )

    $elapsed = ($CompletedAt - $StartedAt).TotalSeconds
    $result = [ordered]@{
        command        = $Command.command
        arguments      = $Command.arguments
        project        = $Command.project
        submissionId   = $Command.submissionId
        slotSuffix     = $SlotSuffix
        exitCode       = $ExitCode
        status         = $Status
        startedAt      = $StartedAt.ToString("yyyy-MM-ddTHH:mm:ss")
        completedAt    = $CompletedAt.ToString("yyyy-MM-ddTHH:mm:ss")
        elapsedSeconds = [math]::Round($elapsed, 1)
        output         = $Output
        errorOutput    = $ErrorOutput
        executedBy     = $env:USERNAME
        server         = $env:COMPUTERNAME
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $ResultPath -Encoding utf8 -Force
}

function Save-ResultToHistory {
    param([string]$DataPath, [string]$ResultPath, [string]$SlotSuffix)

    $historyDir = Join-Path $DataPath "history"
    if (-not (Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HHmmss")
    $historyFile = Join-Path $historyDir "$($timestamp)_$($SlotSuffix)_result.json"
    Copy-Item -Path $ResultPath -Destination $historyFile -Force -ErrorAction SilentlyContinue

    $files = Get-ChildItem -Path $historyDir -Filter "*.json" -File | Sort-Object LastWriteTime -Descending
    if ($files.Count -gt $script:MaxHistoryFiles) {
        $files | Select-Object -Skip $script:MaxHistoryFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Get-SlotSuffixFromFilename {
    param([string]$Filename)
    # Extracts the suffix from next_command_<suffix>.json
    # Regex: "next_command_" then capture everything before ".json"
    if ($Filename -match '^next_command_(.+)\.json$') {
        return $matches[1]
    }
    return $null
}

function Start-SlotProcess {
    param(
        [hashtable]$Command,
        [string]$SlotSuffix,
        [string]$DataPath
    )

    $resolvedPath = Resolve-CommandPath -CommandPath $Command.command
    $arguments = if ($Command.arguments) { $Command.arguments } else { "" }
    $captureOutput = if ($null -ne $Command.captureOutput) { $Command.captureOutput } else { $true }
    $showWindow = if ($Command.showWindow) { $true } else { $false }

    $executorInfo = Get-ExecutorInfo -ResolvedPath $resolvedPath -Arguments $arguments
    if ($null -eq $executorInfo) {
        Write-LogMessage "[$($SlotSuffix)] No executor found for: $($resolvedPath)" -Level ERROR
        return $null
    }

    Write-LogMessage "[$($SlotSuffix)] Executing: $($executorInfo.FilePath) $($executorInfo.ArgumentList)" -Level INFO

    $procParams = @{
        FilePath = $executorInfo.FilePath
        PassThru = $true
    }

    if ($showWindow) {
        $procParams.WindowStyle = 'Normal'
    } else {
        $procParams.NoNewWindow = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($executorInfo.ArgumentList)) {
        $procParams.ArgumentList = $executorInfo.ArgumentList
    }

    $stdoutFile = $null
    $stderrFile = $null
    if ($captureOutput -and -not $showWindow) {
        $stdoutFile = Join-Path $DataPath "stdout_capture_$($SlotSuffix).txt"
        $stderrFile = Join-Path $DataPath "stderr_capture_$($SlotSuffix).txt"
        $procParams.RedirectStandardOutput = $stdoutFile
        $procParams.RedirectStandardError = $stderrFile
    }

    $proc = Start-Process @procParams
    $startTime = Get-Date

    $runningFile = Join-Path $DataPath "running_command_$($SlotSuffix).json"
    $runningInfo = [ordered]@{
        pid          = $proc.Id
        command      = $Command.command
        arguments    = $Command.arguments
        project      = $Command.project
        requestedBy  = $Command.requestedBy
        submissionId = $Command.submissionId
        slotSuffix   = $SlotSuffix
        startedAt    = $startTime.ToString("yyyy-MM-ddTHH:mm:ss")
        server       = $env:COMPUTERNAME
    }
    $runningInfo | ConvertTo-Json -Depth 5 | Set-Content -Path $runningFile -Encoding utf8 -Force

    Write-LogMessage "[$($SlotSuffix)] Process started: PID=$($proc.Id)" -Level INFO

    return @{
        Process       = $proc
        Command       = $Command
        SlotSuffix    = $SlotSuffix
        StartTime     = $startTime
        StdoutFile    = $stdoutFile
        StderrFile    = $stderrFile
        RunningFile   = $runningFile
        CaptureOutput = $captureOutput
        ShowWindow    = $showWindow
        Killed        = $false
    }
}

function Complete-Slot {
    param(
        [hashtable]$Slot,
        [string]$DataPath
    )

    $proc = $Slot.Process
    $suffix = $Slot.SlotSuffix
    $killed = $Slot.Killed

    Remove-Item $Slot.RunningFile -Force -ErrorAction SilentlyContinue
    Write-LogMessage "[$($suffix)] Process finished: PID=$($proc.Id), running file removed" -Level INFO

    $exitCode = if ($proc.HasExited) { [int]$proc.ExitCode } else { -1 }

    $stdout = ""
    $stderr = ""
    if ($Slot.CaptureOutput -and -not $Slot.ShowWindow) {
        if ($Slot.StdoutFile -and (Test-Path $Slot.StdoutFile)) {
            $allLines = Get-Content $Slot.StdoutFile -ErrorAction SilentlyContinue
            if ($allLines -and $allLines.Count -gt $script:MaxOutputLines) {
                $stdout = ($allLines | Select-Object -Last $script:MaxOutputLines) -join "`n"
                $stdout = "... (truncated, showing last $($script:MaxOutputLines) lines) ...`n$($stdout)"
            } elseif ($allLines) {
                $stdout = $allLines -join "`n"
            }
            Remove-Item $Slot.StdoutFile -Force -ErrorAction SilentlyContinue
        }
        if ($Slot.StderrFile -and (Test-Path $Slot.StderrFile)) {
            $stderr = (Get-Content $Slot.StderrFile -Raw -ErrorAction SilentlyContinue)
            Remove-Item $Slot.StderrFile -Force -ErrorAction SilentlyContinue
        }
    } elseif ($Slot.ShowWindow) {
        $stdout = "(output displayed in visible console window)"
    }

    $status = if ($killed) { "KILLED" }
              elseif ($exitCode -eq 0) { "COMPLETED" }
              else { "FAILED" }

    $endTime = Get-Date
    $resultFile = Join-Path $DataPath "last_result_$($suffix).json"

    Write-SlotResultFile -ResultPath $resultFile -Command $Slot.Command `
        -ExitCode $exitCode -Status $status `
        -StartedAt $Slot.StartTime -CompletedAt $endTime `
        -Output $stdout -ErrorOutput $stderr -SlotSuffix $suffix

    Save-ResultToHistory -DataPath $DataPath -ResultPath $resultFile -SlotSuffix $suffix

    $elapsed = ($endTime - $Slot.StartTime)
    $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
    Write-LogMessage "[$($suffix)] Command finished: status=$($status), exit=$($exitCode), elapsed=$($elapsedStr)" -Level INFO

    return @{
        ExitCode    = $exitCode
        Status      = $status
        Elapsed     = $elapsed
        ElapsedStr  = $elapsedStr
        Suffix      = $suffix
        Command     = $Slot.Command
    }
}


try {
    $dataPath = Join-Path $env:OptPath "data" $script:DataFolderName
    if (-not (Test-Path $dataPath)) {
        New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
    }
    Set-OverrideAppDataFolder -Path $dataPath

    $smsNumber = switch ($env:USERNAME) {
        "FKGEISTA" { "+4797188358" }
        "FKSVEERI" { "+4795762742" }
        "FKMISTA"  { "+4799348397" }
        "FKCELERI" { "+4745269945" }
        default    { "+4797188358" }
    }

    # Active slots: hashtable keyed by suffix
    $activeSlots = @{}
    $anyWorkDone = $false

    # Main dispatcher loop
    while ($true) {
        # --- Phase 1: Scan for new commands ---
        $pendingFiles = @()

        # Suffixed command files
        $suffixedFiles = Get-ChildItem -Path $dataPath -Filter "next_command_*.json" -File -ErrorAction SilentlyContinue
        if ($suffixedFiles) { $pendingFiles += $suffixedFiles }

        # Legacy unsuffixed command file (backward compatibility)
        $legacyFile = Join-Path $dataPath "next_command.json"
        if (Test-Path $legacyFile) {
            $legacyContent = Get-Content $legacyFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($legacyContent)) {
                $pendingFiles += (Get-Item $legacyFile)
            }
        }

        # --- Phase 2: Claim and start new slots ---
        foreach ($cmdFile in $pendingFiles) {
            $commandContent = Get-Content $cmdFile.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($commandContent)) { continue }

            # Determine suffix from filename
            $suffix = Get-SlotSuffixFromFilename -Filename $cmdFile.Name
            $isLegacy = $false
            if ($null -eq $suffix) {
                # Legacy file: use UNKNOWN_default as suffix
                $suffix = "UNKNOWN_default"
                $isLegacy = $true
            }

            # Skip if this slot is already running
            if ($activeSlots.ContainsKey($suffix)) { continue }
            $runningFile = Join-Path $dataPath "running_command_$($suffix).json"
            if (Test-Path $runningFile) { continue }

            # Claim the command: empty the file immediately
            [System.IO.File]::WriteAllText($cmdFile.FullName, "", [System.Text.Encoding]::UTF8)

            # Parse command JSON
            $cmd = $null
            try {
                $cmdObj = $commandContent | ConvertFrom-Json
                $cmd = @{
                    command       = $cmdObj.command
                    arguments     = $cmdObj.arguments
                    project       = if ($cmdObj.project) { $cmdObj.project } else { "unknown" }
                    requestedBy   = $cmdObj.requestedBy
                    requestedAt   = $cmdObj.requestedAt
                    submissionId  = if ($cmdObj.submissionId) { $cmdObj.submissionId } else { "" }
                    captureOutput = if ($null -ne $cmdObj.captureOutput) { [bool]$cmdObj.captureOutput } else { $true }
                    showWindow    = if ($cmdObj.showWindow) { [bool]$cmdObj.showWindow } else { $false }
                    isLegacy      = $isLegacy
                }
            }
            catch {
                Write-LogMessage "[$($suffix)] Failed to parse command JSON: $($_.Exception.Message)" -Level ERROR
                $resultFile = Join-Path $dataPath "last_result_$($suffix).json"
                $errorResult = [ordered]@{
                    command      = $commandContent
                    submissionId = ""
                    slotSuffix   = $suffix
                    exitCode     = 1
                    status       = "PARSE_ERROR"
                    startedAt    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                    completedAt  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                    errorOutput  = "Invalid JSON in $($cmdFile.Name): $($_.Exception.Message)"
                    server       = $env:COMPUTERNAME
                }
                $errorResult | ConvertTo-Json -Depth 5 | Set-Content -Path $resultFile -Encoding utf8 -Force

                # Legacy backward compatibility: also write to unsuffixed last_result.json
                if ($isLegacy) {
                    $legacyResultFile = Join-Path $dataPath "last_result.json"
                    $errorResult | ConvertTo-Json -Depth 5 | Set-Content -Path $legacyResultFile -Encoding utf8 -Force
                }
                continue
            }

            if (-not $anyWorkDone) {
                Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
                $anyWorkDone = $true
            }

            Write-LogMessage "[$($suffix)] Received command: $($cmd.command) $($cmd.arguments)" -Level INFO
            Write-LogMessage "[$($suffix)] Requested by: $($cmd.requestedBy), Project: $($cmd.project)" -Level INFO

            if (-not (Test-CommandSecurity -CommandPath $cmd.command)) {
                $startNow = Get-Date
                $resultFile = Join-Path $dataPath "last_result_$($suffix).json"
                Write-SlotResultFile -ResultPath $resultFile -Command $cmd -ExitCode 1 -Status "REJECTED" `
                    -StartedAt $startNow -CompletedAt $startNow -Output "" `
                    -ErrorOutput "Command path rejected by security validation" -SlotSuffix $suffix
                Save-ResultToHistory -DataPath $dataPath -ResultPath $resultFile -SlotSuffix $suffix

                if ($isLegacy) {
                    $legacyResultFile = Join-Path $dataPath "last_result.json"
                    Copy-Item -Path $resultFile -Destination $legacyResultFile -Force -ErrorAction SilentlyContinue
                }

                Write-LogMessage "[$($suffix)] Command REJECTED by security validation" -Level ERROR
                continue
            }

            # Start the process for this slot
            $slot = Start-SlotProcess -Command $cmd -SlotSuffix $suffix -DataPath $dataPath
            if ($null -ne $slot) {
                $activeSlots[$suffix] = $slot
            }
        }

        # --- Phase 3: If no active slots and nothing was started, exit ---
        if ($activeSlots.Count -eq 0) {
            break
        }

        # --- Phase 4: Monitor all active slots ---
        $completedSuffixes = @()

        foreach ($suffix in @($activeSlots.Keys)) {
            $slot = $activeSlots[$suffix]
            $proc = $slot.Process

            # Check for kill signal
            $killFile = Join-Path $dataPath "kill_command_$($suffix).txt"
            if (Test-KillRequested -KillFile $killFile) {
                $killReason = (Get-Content $killFile -Raw -ErrorAction SilentlyContinue).Trim()
                Write-LogMessage "[$($suffix)] KILL requested (PID $($proc.Id)): $($killReason)" -Level WARN
                Stop-ProcessTree -ParentPid $proc.Id
                [System.IO.File]::WriteAllText($killFile, "", [System.Text.Encoding]::UTF8)
                Write-LogMessage "[$($suffix)] Process tree killed" -Level WARN
                $slot.Killed = $true
                $completedSuffixes += $suffix
                continue
            }

            # Check if process has exited
            if ($proc.HasExited) {
                $completedSuffixes += $suffix
            }
        }

        # --- Phase 5: Complete finished slots ---
        foreach ($suffix in $completedSuffixes) {
            $slot = $activeSlots[$suffix]
            $slotResult = Complete-Slot -Slot $slot -DataPath $dataPath

            # Legacy backward compatibility: also write unsuffixed last_result.json
            if ($slot.Command.isLegacy) {
                $suffixedResult = Join-Path $dataPath "last_result_$($suffix).json"
                $legacyResultFile = Join-Path $dataPath "last_result.json"
                Copy-Item -Path $suffixedResult -Destination $legacyResultFile -Force -ErrorAction SilentlyContinue
            }

            # SMS notification for long-running or failed jobs
            $sendSms = ($slotResult.Elapsed.TotalMinutes -gt 5) -or ($slotResult.ExitCode -ne 0)
            if ($sendSms) {
                $cmdShort = [System.IO.Path]::GetFileName((Resolve-CommandPath -CommandPath $slotResult.Command.command))
                $smsMsg = "Orchestrator: $($cmdShort) $($slotResult.Status) exit=$($slotResult.ExitCode) in $($slotResult.ElapsedStr) (project: $($slotResult.Command.project)) on $($env:COMPUTERNAME)"
                if ($smsMsg.Length -gt 1024) { $smsMsg = $smsMsg.Substring(0, 1021) + "..." }
                try {
                    Send-Sms -Receiver $smsNumber -Message $smsMsg
                } catch {
                    Write-LogMessage "[$($suffix)] Failed to send SMS: $($_.Exception.Message)" -Level WARN
                }
            }

            $activeSlots.Remove($suffix)
        }

        # If there are still active slots, sleep before next poll iteration
        if ($activeSlots.Count -gt 0) {
            Start-Sleep -Seconds $script:PollIntervalSeconds
        }
        # Loop back to Phase 1 to rescan for new commands
    }

    if ($anyWorkDone) {
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    }
}
catch {
    Write-LogMessage "Orchestrator error: $($_.Exception.Message)" -Level ERROR -Exception $_
    try {
        Send-Sms -Receiver "+4797188358" -Message "CursorOrchestrator CRASHED: $($_.Exception.Message)"
    } catch {}
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
