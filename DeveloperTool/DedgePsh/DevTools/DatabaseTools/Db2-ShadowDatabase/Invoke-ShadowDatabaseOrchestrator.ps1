<#
.SYNOPSIS
    Orchestrator for shadow database operations. Reads a command file and executes
    step scripts in sequence. Designed to run as a scheduled task every minute.

.DESCRIPTION
    Checks for a command file at the application data path. Supports two modes:

    1. RUN_ALL: Runs the full step chain:
       Step-1 (create instance/DB) -> Step-2 (DDL + data) ->
       Step-3 (verify schema objects) -> Step-5 (verify row counts)
       Stops on first failure. Sends SMS on completion.
    2. Single command: Runs one specified script (existing behavior).

    Kill mechanism: Write any content to <AppDataPath>\kill_command.txt to abort
    a running step. The orchestrator polls this file every 10 seconds. When detected,
    it kills the child process tree, logs the abort, and exits with code 2.

    All environment settings (instances, databases, disk) are loaded from
    config.json in the script folder. Edit that file to switch environments.

.NOTES
    Command file: <AppDataPath>\next_command.txt
    Kill file:    <AppDataPath>\kill_command.txt
    Config file:  <ScriptRoot>\config.json

    Write "RUN_ALL" to the command file to trigger the full chain.
    Write a script name (e.g. "Step-2-CopyDatabaseContent.ps1") for single execution.
    Write anything to kill_command.txt to abort the currently running step.
#>

Import-Module GlobalFunctions -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$configPath = Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot
$env:Db2ShadowConfigPath = $configPath
$cfg = Get-Content $configPath -Raw | ConvertFrom-Json

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

function Invoke-StepScript {
    param(
        [string]$ScriptFolder,
        [string]$ScriptName,
        [string]$ScriptParams = "",
        [string]$KillFile = ""
    )

    $scriptPath = Join-Path $ScriptFolder $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Write-LogMessage "Script not found: $($scriptPath)" -Level ERROR
        return 1
    }

    Write-LogMessage "Executing: $($scriptPath) $($ScriptParams)" -Level INFO

    if ([string]::IsNullOrEmpty($ScriptParams)) {
        $proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile -File `"$scriptPath`"" `
            -NoNewWindow -PassThru
    }
    else {
        $fullCommand = "& '$($scriptPath)' $($ScriptParams)"
        $proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile -Command `"$fullCommand`"" `
            -NoNewWindow -PassThru
    }

    # Poll: wait for process exit or kill signal (check every 10 seconds)
    while (-not $proc.HasExited) {
        if (-not [string]::IsNullOrEmpty($KillFile) -and (Test-KillRequested -KillFile $KillFile)) {
            $killReason = (Get-Content $KillFile -Raw -ErrorAction SilentlyContinue).Trim()
            Write-LogMessage "KILL requested for $($ScriptName) (PID $($proc.Id)): $($killReason)" -Level WARN
            Stop-ProcessTree -ParentPid $proc.Id
            [System.IO.File]::WriteAllText($KillFile, "")
            Write-LogMessage "Process tree for $($ScriptName) killed" -Level WARN
            return 99
        }
        Start-Sleep -Seconds 10
    }

    $exitCode = [int]$proc.ExitCode
    Write-LogMessage "Script $($ScriptName) finished with exit code: $($exitCode)" -Level INFO
    return $exitCode
}

try {
    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    $commandFile = Join-Path $appDataPath "next_command.txt"
    $scriptFolder = $PSScriptRoot

    if (-not (Test-Path $commandFile)) {
        Write-LogMessage "No command file found at $($commandFile) - nothing to do" -Level DEBUG
        exit 0
    }

    $commandContent = (Get-Content $commandFile -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace($commandContent)) {
        Write-LogMessage "Command file is empty at $($commandFile) - nothing to do" -Level DEBUG
        exit 0
    }

    $commandLine = $commandContent.Trim()

    [System.IO.File]::WriteAllText($commandFile, "")

    $killFile = Join-Path $appDataPath "kill_command.txt"

    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Orchestrator received command: $($commandLine)" -Level INFO

    $smsNumber = switch ($env:USERNAME) {
        "FKGEISTA" { "+4797188358" }
        "FKSVEERI" { "+4795762742" }
        "FKMISTA"  { "+4799348397" }
        "FKCELERI" { "+4745269945" }
        default    { "+4797188358" }
    }

    if ($commandLine -match '^RUN_ALL\b') {
        #########################################################
        # RUN_ALL delegates to Run-FullShadowPipeline.ps1 so both
        # manual and orchestrated runs use the same pipeline.
        #########################################################
        $runAllParams = ""
        if ($commandLine.Length -gt 7) {
            $runAllParams = $commandLine.Substring(7).Trim()
        }

        Write-LogMessage "RUN_ALL: Delegating to Run-FullShadowPipeline.ps1 $($runAllParams)" -Level INFO
        $exitCode = Invoke-StepScript -ScriptFolder $scriptFolder -ScriptName "Run-FullShadowPipeline.ps1" -ScriptParams $runAllParams -KillFile $killFile

        if ($exitCode -eq 99) {
            $smsMsg = "Shadow DB KILLED: Run-FullShadowPipeline.ps1 aborted by kill command."
            Write-LogMessage $smsMsg -Level WARN
            Send-Sms -Receiver $smsNumber -Message $smsMsg
        }
        elseif ($exitCode -ne 0) {
            $smsMsg = "Shadow DB FAILED: Run-FullShadowPipeline.ps1 exit=$($exitCode)."
            Write-LogMessage $smsMsg -Level ERROR
            Send-Sms -Receiver $smsNumber -Message $smsMsg
        }
        else {
            Write-LogMessage "RUN_ALL completed via Run-FullShadowPipeline.ps1" -Level INFO
        }
    }
    else {
        #########################################################
        # Single command mode (existing behavior)
        #########################################################
        $parts = $commandLine -split '\s+', 2
        $scriptName = $parts[0]
        $scriptParams = if ($parts.Count -gt 1) { $parts[1] } else { "" }

        $exitCode = Invoke-StepScript -ScriptFolder $scriptFolder -ScriptName $scriptName -ScriptParams $scriptParams -KillFile $killFile

        if ($exitCode -eq 99) {
            Write-LogMessage "Script $($scriptName) was KILLED by kill_command.txt" -Level WARN
        }
        elseif ($exitCode -ne 0) {
            Write-LogMessage "Script $($scriptName) FAILED with exit code $($exitCode)" -Level ERROR
        }
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Orchestrator error: $($_.Exception.Message)" -Level ERROR -Exception $_
    try {
        Send-Sms -Receiver "+4797188358" -Message "Orchestrator CRASHED: $($_.Exception.Message)"
    } catch {}
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
