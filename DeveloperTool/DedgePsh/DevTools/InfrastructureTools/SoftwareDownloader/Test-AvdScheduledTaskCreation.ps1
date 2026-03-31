[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SendSms
)

Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module ScheduledTask-Handler -Force

$ErrorActionPreference = "Stop"

function Get-UserSmsNumber {
    switch ($env:USERNAME.ToUpper()) {
        "FKGEISTA" { return "+4797188358" }
        "FKSVEERI" { return "+4795762742" }
        "FKMISTA" { return "+4799348397" }
        "FKCELERI" { return "+4745269945" }
        default { return "+4797188358" }
    }
}

function Invoke-SchtasksCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaseName,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $false)]
        [string]$MaskValue = ""
    )

    $start = Get-Date
    $rawOutput = (& schtasks.exe @Arguments 2>&1 | Out-String).Trim()
    $exitCode = $LASTEXITCODE
    $end = Get-Date
    $durationMs = [math]::Round((New-TimeSpan -Start $start -End $end).TotalMilliseconds, 0)

    $argText = $Arguments -join " "
    if (-not [string]::IsNullOrWhiteSpace($MaskValue)) {
        $argText = $argText.Replace($MaskValue, "***MASKED***")
        $rawOutput = $rawOutput.Replace($MaskValue, "***MASKED***")
    }

    return [PSCustomObject]@{
        CaseName       = $CaseName
        ExitCode       = $exitCode
        Success        = ($exitCode -eq 0)
        DurationMs     = $durationMs
        Command        = "schtasks.exe $argText"
        Output         = $rawOutput
    }
}

try {
    Write-LogMessage "Test-AvdScheduledTaskCreation started" -Level JOB_STARTED

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $startTime = (Get-Date).AddMinutes(5)
    $startTimeText = $startTime.ToString("HH:mm")
    $taskFolderPath = "\DevTools\"
    $taskNames = @(
        "$($taskFolderPath)AVDProbe_NoCreds_Highest_$($suffix)"
        "$($taskFolderPath)AVDProbe_WithCreds_Highest_$($suffix)"
        "$($taskFolderPath)AVDProbe_NoCreds_Limited_$($suffix)"
        "$($taskFolderPath)AVDProbe_WithCreds_Limited_$($suffix)"
        "$($taskFolderPath)AVDProbe_Module_$($suffix)"
    )

    $runCommand = 'pwsh.exe -NoProfile -WindowStyle Hidden -Command "exit 0"'
    $username = "$($env:USERDOMAIN)\$($env:USERNAME)"
    $password = $null
    try {
        $password = Get-SecureStringUserPasswordAsPlainText
    }
    catch {
        Write-LogMessage "Could not resolve current user password for /RP tests" -Level WARN -Exception $_
    }

    $results = @()
    $isAvd = Test-AzureVirtualDesktopSessionHost
    Write-LogMessage "AVD detection result: $($isAvd)" -Level INFO

    $commonNoCreds = @("/Create", "/SC", "ONCE", "/ST", $startTimeText, "/TR", $runCommand, "/F")
    $results += Invoke-SchtasksCase -CaseName "NoCreds_HIGHEST" -Arguments (@($commonNoCreds + @("/TN", $taskNames[0], "/RL", "HIGHEST")))
    $results += Invoke-SchtasksCase -CaseName "NoCreds_LIMITED" -Arguments (@($commonNoCreds + @("/TN", $taskNames[2], "/RL", "LIMITED")))

    if ([string]::IsNullOrWhiteSpace($password)) {
        $results += [PSCustomObject]@{
            CaseName   = "WithCreds_HIGHEST"
            ExitCode   = -1
            Success    = $false
            DurationMs = 0
            Command    = "Skipped (password unavailable)"
            Output     = "Skipped because Get-SecureStringUserPasswordAsPlainText returned null/empty."
        }
        $results += [PSCustomObject]@{
            CaseName   = "WithCreds_LIMITED"
            ExitCode   = -1
            Success    = $false
            DurationMs = 0
            Command    = "Skipped (password unavailable)"
            Output     = "Skipped because Get-SecureStringUserPasswordAsPlainText returned null/empty."
        }
    }
    else {
        $commonWithCreds = @("/Create", "/SC", "ONCE", "/ST", $startTimeText, "/TR", $runCommand, "/RU", $username, "/RP", $password, "/F")
        $results += Invoke-SchtasksCase -CaseName "WithCreds_HIGHEST" -Arguments (@($commonWithCreds + @("/TN", $taskNames[1], "/RL", "HIGHEST"))) -MaskValue $password
        $results += Invoke-SchtasksCase -CaseName "WithCreds_LIMITED" -Arguments (@($commonWithCreds + @("/TN", $taskNames[3], "/RL", "LIMITED"))) -MaskValue $password
    }

    $moduleCase = [PSCustomObject]@{
        CaseName   = "Module_New-ScheduledTask_RunAsUserTrue"
        ExitCode   = 0
        Success    = $true
        DurationMs = 0
        Command    = "New-ScheduledTask -TaskName 'AVDProbe_Module_$($suffix)' -TaskFolder 'DevTools' -Executable '<temp script>' -RunFrequency 'Once' -StartHour $($startTime.Hour) -StartMinute $($startTime.Minute) -RunAsUser:$true -RecreateTask:$true"
        Output     = ""
    }
    $moduleStart = Get-Date
    $probeScriptPath = Join-Path $env:TEMP "AvdScheduledTaskProbe-$($suffix).ps1"
    Set-Content -Path $probeScriptPath -Value "Write-Output 'AVD ScheduledTask probe'" -Encoding UTF8
    try {
        New-ScheduledTask -TaskName "AVDProbe_Module_$suffix" -TaskFolder "DevTools" -Executable $probeScriptPath -RunFrequency "Once" -StartHour $startTime.Hour -StartMinute $startTime.Minute -RunAsUser:$true -RecreateTask:$true -RunAtOnce:$false
        $moduleCase.Output = "New-ScheduledTask call completed."
    }
    catch {
        $moduleCase.Success = $false
        $moduleCase.ExitCode = 1
        $moduleCase.Output = $_.Exception.Message
        Write-LogMessage "Module case failed" -Level WARN -Exception $_
    }
    $moduleCase.DurationMs = [math]::Round((New-TimeSpan -Start $moduleStart -End (Get-Date)).TotalMilliseconds, 0)
    $results += $moduleCase

    $cleanupResults = @()
    foreach ($taskName in $taskNames) {
        $deleteOutput = (& schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-String).Trim()
        $cleanupResults += [PSCustomObject]@{
            TaskName = $taskName
            ExitCode = $LASTEXITCODE
            Output   = $deleteOutput
        }
    }
    Remove-Item -Path $probeScriptPath -Force -ErrorAction SilentlyContinue

    $officialReferences = @(
        "https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create",
        "https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks",
        "https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/troubleshooting-task-scheduler-access-denied-error",
        "https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-desktop/troubleshoot-agent"
    )

    $summary = [PSCustomObject]@{
        ComputerName        = $env:COMPUTERNAME
        UserName            = "$($env:USERDOMAIN)\$($env:USERNAME)"
        IsAvdSessionHost    = $isAvd
        StartedAt           = (Get-Date).ToString("s")
        TestStartTimeValue  = $startTimeText
        Results             = $results
        Cleanup             = $cleanupResults
        References          = $officialReferences
    }

    $jsonPath = Join-Path $PSScriptRoot "AVD-ScheduledTask-Diagnostics-$($timestamp).json"
    $mdPath = Join-Path $PSScriptRoot "AVD-ScheduledTask-Diagnostics-$($timestamp).md"
    $summary | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    $worked = $results | Where-Object { $_.Success -eq $true }
    $failed = $results | Where-Object { $_.Success -ne $true }
    $mdLines = @()
    $mdLines += "# AVD Scheduled Task Diagnostics Report"
    $mdLines += ""
    $mdLines += "- Computer: $($summary.ComputerName)"
    $mdLines += "- User: $($summary.UserName)"
    $mdLines += "- AVD detected: $($summary.IsAvdSessionHost)"
    $mdLines += "- Planned start time used: $($summary.TestStartTimeValue)"
    $mdLines += "- Passed cases: $($worked.Count)"
    $mdLines += "- Failed cases: $($failed.Count)"
    $mdLines += ""
    $mdLines += "## Attempted cases"
    foreach ($r in $results) {
        $mdLines += "- $($r.CaseName): Success=$($r.Success), ExitCode=$($r.ExitCode), DurationMs=$($r.DurationMs)"
        if (-not [string]::IsNullOrWhiteSpace($r.Output)) {
            $mdLines += "  - Output: $($r.Output)"
        }
    }
    $mdLines += ""
    $mdLines += "## Official references"
    foreach ($url in $officialReferences) {
        $mdLines += "- $url"
    }
    $mdLines += ""
    $mdLines += "## Interpretation"
    $withCredsCases = $results | Where-Object { $_.CaseName -like "WithCreds_*" }
    $noCredsCases = $results | Where-Object { $_.CaseName -like "NoCreds_*" }
    if (($withCredsCases | Where-Object { $_.Success -eq $false }).Count -gt 0 -and ($noCredsCases | Where-Object { $_.Success -eq $true }).Count -gt 0) {
        $mdLines += "- The environment allows task creation without stored credentials but rejects one or more credential-backed registrations (/RU + /RP)."
        $mdLines += "- This matches AVD policy/elevation constraints; use interactive logged-on tasks on AVD."
    }
    elseif (($withCredsCases | Where-Object { $_.Success -eq $false }).Count -gt 0 -and ($noCredsCases | Where-Object { $_.Success -eq $false }).Count -gt 0) {
        $mdLines += "- Both credential and non-credential paths failed; this points to broader permission/elevation restrictions (not only /RU + /RP)."
    }
    else {
        $mdLines += "- Results are mixed; inspect case outputs above for exact failing argument sets."
    }
    Set-Content -Path $mdPath -Value ($mdLines -join [Environment]::NewLine) -Encoding UTF8

    Write-LogMessage "Diagnostics report written: $($mdPath)" -Level INFO
    Write-LogMessage "Diagnostics JSON written: $($jsonPath)" -Level INFO

    if ($SendSms) {
        $smsNumber = Get-UserSmsNumber
        $smsText = "AVD schedtask test on $($env:COMPUTERNAME): passed $($worked.Count), failed $($failed.Count). Report: $($mdPath)"
        try {
            Send-Sms $smsNumber $smsText
            Write-LogMessage "SMS sent to $($smsNumber)" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to send SMS notification" -Level WARN -Exception $_
        }
    }

    Write-LogMessage "Test-AvdScheduledTaskCreation completed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Test-AvdScheduledTaskCreation failed" -Level JOB_FAILED -Exception $_
    throw
}
