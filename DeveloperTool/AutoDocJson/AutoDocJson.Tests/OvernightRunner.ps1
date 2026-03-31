<#
.SYNOPSIS
    AutoDoc Overnight Runner - Simplified and Robust Version
    
.DESCRIPTION
    Runs AutoDocBatchRunner.ps1 with Regenerate=Clean overnight and:
    - Monitors the global log file for errors
    - Tracks progress and errors
    - Applies bulk fixes if needed and restarts
    - Validates generated HTML files
    - Sends SMS notification when complete
    
.NOTES
    Author: AutoDoc Automation System
    Date: 2026-02-05
#>

#region Configuration
$script:Config = @{
    StartTime = Get-Date
    MinRunHours = 9
    MaxErrors = 200
    MaxIterations = 5
    DeadlineTime = (Get-Date).Date.AddDays(1).AddHours(8).AddMinutes(45)  # 08:45 AM tomorrow - send SMS before 9 AM
    
    # Paths
    AutoDocBatchRunner = "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1"
    OutputFolder = "C:\opt\Webs\AutoDoc"
    CSharpOutputFolder = "C:\opt\Webs\AutoDocNew"
    GlobalLogFolder = "C:\opt\data\AllPwshLog"
    ReportPath = "C:\opt\src\DedgePsh\AutoDocNew\AutoDocNew.Tests\OVERNIGHT_REPORT.md"
    
    # SMS
    SmsRecipient = "+4797188358"
    
    # Webserver
    WebserverPort = 8889
    
    # Validation
    HtmlSamplePercent = 0.05
    
    # Polling
    LogCheckIntervalSeconds = 30
    ProgressReportIntervalMinutes = 15
}

$script:State = @{
    IterationCount = 0
    TotalErrors = 0
    CurrentIterationErrors = 0
    ErrorList = [System.Collections.ArrayList]::new()
    FixesApplied = [System.Collections.ArrayList]::new()
    ProcessedFiles = 0
    ValidationResults = @()
    Status = "Starting"
    LastLogPosition = 0
    CompletionMarkers = @{}
}
#endregion

#region Logging - Simple console + file output
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    
    # Console output with color
    $color = switch ($Level) {
        "INFO" { "White" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "DEBUG" { "Gray" }
    }
    Write-Host $logLine -ForegroundColor $color
    
    # Append to report
    $reportLog = Join-Path (Split-Path $script:Config.ReportPath) "overnight_runner.log"
    Add-Content -Path $reportLog -Value $logLine -ErrorAction SilentlyContinue
}
#endregion

#region Report Generation
function Update-Report {
    param([string]$AdditionalNotes = "")
    
    $elapsed = (Get-Date) - $script:Config.StartTime
    $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
    
    $report = @"
# AutoDoc Overnight Runner Report

## Status: $($script:State.Status)

**Started:** $($script:Config.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
**Elapsed:** $elapsedStr
**Iterations:** $($script:State.IterationCount)

## Summary

| Metric | Value |
|--------|-------|
| Total Errors | $($script:State.TotalErrors) |
| Current Iteration Errors | $($script:State.CurrentIterationErrors) |
| Fixes Applied | $($script:State.FixesApplied.Count) |
| Files Processed | $($script:State.ProcessedFiles) |

## Completion Status

"@

    foreach ($key in $script:State.CompletionMarkers.Keys) {
        $report += "- **$key**: $($script:State.CompletionMarkers[$key])`n"
    }

    $report += @"

## Error Summary

"@
    if ($script:State.ErrorList.Count -gt 0) {
        $grouped = $script:State.ErrorList | Group-Object -Property ErrorType
        foreach ($group in $grouped) {
            $report += "- **$($group.Name)**: $($group.Count) occurrences`n"
        }
    } else {
        $report += "*No errors recorded*`n"
    }

    $report += @"

## Fixes Applied

"@
    if ($script:State.FixesApplied.Count -gt 0) {
        foreach ($fix in $script:State.FixesApplied) {
            $report += "- **$($fix.Timestamp.ToString('HH:mm:ss'))**: $($fix.Description)`n"
        }
    } else {
        $report += "*No fixes applied*`n"
    }

    $report += @"

## HTML Validation

"@
    if ($script:State.ValidationResults.Count -gt 0) {
        $passed = ($script:State.ValidationResults | Where-Object { $_.Passed }).Count
        $total = $script:State.ValidationResults.Count
        $report += "**Passed:** $passed / $total`n`n"
        
        $failed = $script:State.ValidationResults | Where-Object { -not $_.Passed }
        if ($failed) {
            $report += "### Failed Files`n"
            foreach ($f in $failed | Select-Object -First 20) {
                $report += "- $($f.FileName): $($f.Reason)`n"
            }
        }
    } else {
        $report += "*Validation pending*`n"
    }

    if ($AdditionalNotes) {
        $report += @"

## Notes

$AdditionalNotes
"@
    }

    $report += @"

---
*Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*
"@

    $report | Set-Content -Path $script:Config.ReportPath -Force -Encoding UTF8
}
#endregion

#region Error Detection and Fixing
function Get-LogFilePath {
    $date = Get-Date -Format 'yyyyMMdd'
    return Join-Path $script:Config.GlobalLogFolder "FkLog_$date.log"
}

function Read-NewLogEntries {
    $logPath = Get-LogFilePath
    if (-not (Test-Path $logPath)) {
        return @()
    }
    
    $content = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return @() }
    
    $newContent = $content.Substring([Math]::Min($script:State.LastLogPosition, $content.Length))
    $script:State.LastLogPosition = $content.Length
    
    return $newContent -split "`n" | Where-Object { $_ -match '\S' }
}

function Test-LogForErrors {
    param([string[]]$LogLines)
    
    $errors = @()
    foreach ($line in $LogLines) {
        if ($line -match '\|ERROR\||\|FATAL\|') {
            $errors += @{
                Line = $line
                ErrorType = if ($line -match 'template') { "Template" }
                           elseif ($line -match 'encoding|1252|UTF') { "Encoding" }
                           elseif ($line -match 'git|clone') { "Git" }
                           elseif ($line -match 'locked|access') { "FileLock" }
                           else { "Other" }
            }
        }
        
        # Track completion markers
        if ($line -match 'Completed (CBL|REX|BAT|PS1|SQL|CSharp):?\s*(\d+)') {
            $type = $Matches[1]
            $count = $Matches[2]
            $script:State.CompletionMarkers[$type] = "$count files"
        }
        
        # Track file processing
        if ($line -match 'Generated|Parsing file|Processing:') {
            $script:State.ProcessedFiles++
        }
    }
    
    return $errors
}

function Invoke-BulkFixes {
    Write-Log "Applying bulk fixes..." -Level INFO
    
    # 1. Clear .err files
    $errFiles = Get-ChildItem -Path $script:Config.OutputFolder -Filter "*.err" -ErrorAction SilentlyContinue
    if ($errFiles) {
        $errFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        [void]$script:State.FixesApplied.Add(@{
            Timestamp = Get-Date
            Description = "Cleared $($errFiles.Count) .err files"
        })
    }
    
    # 2. Re-copy templates
    $templateSource = "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_templates"
    $templateDest = Join-Path $script:Config.OutputFolder "_templates"
    if (Test-Path $templateSource) {
        Copy-Item -Path "$templateSource\*" -Destination $templateDest -Force -Recurse -ErrorAction SilentlyContinue
        [void]$script:State.FixesApplied.Add(@{
            Timestamp = Get-Date
            Description = "Re-copied templates"
        })
    }
    
    # 3. Clear git locks
    $gitLocks = @(
        "C:\opt\data\AutoDoc\tmp\DedgeRepository\.git\index.lock",
        "C:\opt\data\AutoDoc\Sync\.git\index.lock"
    )
    foreach ($lock in $gitLocks) {
        if (Test-Path $lock) {
            Remove-Item $lock -Force -ErrorAction SilentlyContinue
            [void]$script:State.FixesApplied.Add(@{
                Timestamp = Get-Date
                Description = "Removed git lock: $(Split-Path $lock -Leaf)"
            })
        }
    }
    
    Write-Log "Bulk fixes complete" -Level INFO
}
#endregion

#region HTML Validation
function Test-HtmlFile {
    param([string]$FilePath)
    
    $result = @{
        FileName = Split-Path $FilePath -Leaf
        Passed = $true
        Reason = "OK"
    }
    
    try {
        $fileInfo = Get-Item $FilePath
        if ($fileInfo.Length -lt 1024) {
            $result.Passed = $false
            $result.Reason = "Too small ($($fileInfo.Length) bytes)"
            return $result
        }
        
        $content = Get-Content $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
        
        if (-not ($content -match '<html' -and $content -match '</html>')) {
            $result.Passed = $false
            $result.Reason = "Missing HTML tags"
        }
    }
    catch {
        $result.Passed = $false
        $result.Reason = $_.Exception.Message
    }
    
    return $result
}

function Invoke-HtmlValidation {
    Write-Log "Starting HTML validation (5% sample)..." -Level INFO
    
    $htmlFiles = Get-ChildItem -Path $script:Config.OutputFolder -Filter "*.html" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "index.html" }
    
    if ($htmlFiles.Count -eq 0) {
        Write-Log "No HTML files found for validation" -Level WARN
        return @()
    }
    
    $sampleSize = [Math]::Max(5, [Math]::Ceiling($htmlFiles.Count * $script:Config.HtmlSamplePercent))
    $sample = $htmlFiles | Get-Random -Count ([Math]::Min($sampleSize, $htmlFiles.Count))
    
    Write-Log "Validating $($sample.Count) of $($htmlFiles.Count) HTML files" -Level INFO
    
    $results = @()
    foreach ($file in $sample) {
        $result = Test-HtmlFile -FilePath $file.FullName
        $results += $result
        if (-not $result.Passed) {
            Write-Log "  FAIL: $($result.FileName) - $($result.Reason)" -Level WARN
        }
    }
    
    $passed = ($results | Where-Object { $_.Passed }).Count
    Write-Log "HTML Validation: $passed / $($results.Count) passed" -Level INFO
    
    $script:State.ValidationResults = $results
    return $results
}
#endregion

#region Webserver
function Start-PythonWebserver {
    $port = $script:Config.WebserverPort
    $folder = $script:Config.CSharpOutputFolder
    
    Write-Log "Starting Python webserver on port $port" -Level INFO
    
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    
    try {
        $job = Start-Job -ScriptBlock {
            param($folder, $port)
            Set-Location $folder
            python -m http.server $port
        } -ArgumentList $folder, $port
        
        Start-Sleep -Seconds 2
        Write-Log "Webserver started: http://localhost:$port" -Level INFO
        return $job
    }
    catch {
        Write-Log "Failed to start webserver: $($_.Exception.Message)" -Level WARN
        return $null
    }
}
#endregion

#region SMS Notification
function Send-StatusSms {
    $elapsed = (Get-Date) - $script:Config.StartTime
    $elapsedHours = $elapsed.TotalHours
    
    $passed = if ($script:State.ValidationResults) { 
        ($script:State.ValidationResults | Where-Object { $_.Passed }).Count 
    } else { 0 }
    $total = if ($script:State.ValidationResults) { 
        $script:State.ValidationResults.Count 
    } else { 0 }
    
    $msg = "AutoDocJson: $($script:State.Status). Files: $($script:State.ProcessedFiles), Errors: $($script:State.TotalErrors), Validation: $passed/$total. Time: $($elapsedHours.ToString('F1'))h"
    
    if ($msg.Length -gt 1024) {
        $msg = $msg.Substring(0, 1021) + "..."
    }
    
    Write-Log "Sending SMS: $msg" -Level INFO
    
    try {
        Import-Module GlobalFunctions -Force -ErrorAction Stop
        Send-Sms -Receiver $script:Config.SmsRecipient -Message $msg
        Write-Log "SMS sent successfully" -Level INFO
    }
    catch {
        Write-Log "Failed to send SMS: $($_.Exception.Message)" -Level ERROR
    }
}
#endregion

#region Main Runner
function Start-AutoDocRun {
    Write-Log "Starting AutoDocBatchRunner (Iteration $($script:State.IterationCount + 1))..." -Level INFO
    
    $script:State.CurrentIterationErrors = 0
    $script:State.IterationCount++
    $script:State.LastLogPosition = (Get-Item (Get-LogFilePath) -ErrorAction SilentlyContinue).Length
    
    $scriptPath = $script:Config.AutoDocBatchRunner
    
    # Start the process
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "pwsh"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Regenerate Clean -Parallel:`$true -ThreadPercentage 75"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = Split-Path $scriptPath
    
    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        Write-Log "AutoDocBatchRunner started (PID: $($process.Id))" -Level INFO
        return $process
    }
    catch {
        Write-Log "Failed to start AutoDocBatchRunner: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Wait-ForCompletion {
    param([System.Diagnostics.Process]$Process)
    
    if (-not $Process) {
        return "NO_PROCESS"
    }
    
    Write-Log "Monitoring AutoDocBatchRunner (PID: $($Process.Id))..." -Level INFO
    
    $lastReportTime = Get-Date
    $startTime = Get-Date
    $maxWaitHours = 6
    
    while (-not $Process.HasExited) {
        Start-Sleep -Seconds $script:Config.LogCheckIntervalSeconds
        
        # Check log for errors and progress
        $newLines = Read-NewLogEntries
        if ($newLines.Count -gt 0) {
            $errors = Test-LogForErrors -LogLines $newLines
            foreach ($err in $errors) {
                [void]$script:State.ErrorList.Add(@{
                    Timestamp = Get-Date
                    ErrorType = $err.ErrorType
                    Line = $err.Line.Substring(0, [Math]::Min(200, $err.Line.Length))
                })
                $script:State.TotalErrors++
                $script:State.CurrentIterationErrors++
            }
        }
        
        # Check error threshold
        if ($script:State.CurrentIterationErrors -ge $script:Config.MaxErrors) {
            Write-Log "Error threshold exceeded ($($script:State.CurrentIterationErrors) errors)" -Level WARN
            $Process.Kill()
            return "THRESHOLD_EXCEEDED"
        }
        
        # Periodic progress report
        if ((Get-Date) - $lastReportTime -gt [TimeSpan]::FromMinutes($script:Config.ProgressReportIntervalMinutes)) {
            Update-Report
            $lastReportTime = Get-Date
            Write-Log "Progress: $($script:State.ProcessedFiles) files, $($script:State.CurrentIterationErrors) errors" -Level INFO
        }
        
        # Timeout check
        if ((Get-Date) - $startTime -gt [TimeSpan]::FromHours($maxWaitHours)) {
            Write-Log "Timeout after $maxWaitHours hours" -Level WARN
            $Process.Kill()
            return "TIMEOUT"
        }
    }
    
    $exitCode = $Process.ExitCode
    Write-Log "AutoDocBatchRunner completed (exit code: $exitCode)" -Level INFO
    
    # Read any remaining log entries
    $finalLines = Read-NewLogEntries
    if ($finalLines.Count -gt 0) {
        $errors = Test-LogForErrors -LogLines $finalLines
        foreach ($err in $errors) {
            [void]$script:State.ErrorList.Add(@{
                Timestamp = Get-Date
                ErrorType = $err.ErrorType
                Line = $err.Line.Substring(0, [Math]::Min(200, $err.Line.Length))
            })
            $script:State.TotalErrors++
            $script:State.CurrentIterationErrors++
        }
    }
    
    return if ($exitCode -eq 0) { "COMPLETE" } else { "FAILED" }
}

function Start-OvernightRunner {
    Write-Log ("=" * 70) -Level INFO
    Write-Log "AutoDoc Overnight Runner Starting" -Level INFO
    Write-Log "Start Time: $($script:Config.StartTime)" -Level INFO
    Write-Log "Min Run Hours: $($script:Config.MinRunHours)" -Level INFO
    Write-Log ("=" * 70) -Level INFO
    
    $script:State.Status = "Running"
    Update-Report
    
    try {
        $continueRunning = $true
        
        while ($continueRunning -and $script:State.IterationCount -lt $script:Config.MaxIterations) {
            Write-Log "" -Level INFO
            Write-Log ("=" * 50) -Level INFO
            Write-Log "Starting Iteration $($script:State.IterationCount + 1)" -Level INFO
            Write-Log ("=" * 50) -Level INFO
            
            $process = Start-AutoDocRun
            
            if (-not $process) {
                Write-Log "Failed to start - waiting 60s before retry" -Level ERROR
                Start-Sleep -Seconds 60
                continue
            }
            
            $result = Wait-ForCompletion -Process $process
            Write-Log "Iteration result: $result" -Level INFO
            
            switch ($result) {
                "COMPLETE" {
                    $continueRunning = $false
                    $script:State.Status = "Complete"
                }
                "THRESHOLD_EXCEEDED" {
                    Write-Log "Applying fixes and restarting..." -Level WARN
                    Invoke-BulkFixes
                    Start-Sleep -Seconds 10
                }
                "TIMEOUT" {
                    $continueRunning = $false
                    $script:State.Status = "Timeout"
                }
                "FAILED" {
                    if ($script:State.IterationCount -lt $script:Config.MaxIterations) {
                        Write-Log "Applying fixes and retrying..." -Level WARN
                        Invoke-BulkFixes
                        Start-Sleep -Seconds 10
                    } else {
                        $continueRunning = $false
                        $script:State.Status = "Failed"
                    }
                }
                default {
                    $continueRunning = $false
                    $script:State.Status = "Unknown"
                }
            }
            
            Update-Report
        }
        
        # HTML Validation
        Write-Log "" -Level INFO
        Write-Log ("=" * 50) -Level INFO
        Write-Log "Running HTML Validation" -Level INFO
        Write-Log ("=" * 50) -Level INFO
        
        $validation = Invoke-HtmlValidation
        
        # Start webserver
        Write-Log "" -Level INFO
        Write-Log ("=" * 50) -Level INFO
        Write-Log "Starting Webserver" -Level INFO
        Write-Log ("=" * 50) -Level INFO
        
        $webJob = Start-PythonWebserver
        
        # Determine final status
        $passRate = if ($validation.Count -gt 0) {
            ($validation | Where-Object { $_.Passed }).Count / $validation.Count * 100
        } else { 0 }
        
        if ($script:State.Status -eq "Complete" -and $passRate -ge 90) {
            $script:State.Status = "SUCCESS"
        } elseif ($passRate -ge 70) {
            $script:State.Status = "PARTIAL_SUCCESS"
        } elseif ($script:State.Status -ne "Complete") {
            $script:State.Status = "NEEDS_ATTENTION"
        }
        
        Update-Report -AdditionalNotes @"
## Final Summary

- Iterations: $($script:State.IterationCount)
- Total Errors: $($script:State.TotalErrors)
- Files Processed: $($script:State.ProcessedFiles)
- Validation Pass Rate: $($passRate.ToString('F1'))%
- Webserver: $(if ($webJob) { "Running on http://localhost:$($script:Config.WebserverPort)" } else { "Not started" })

**Final Status: $($script:State.Status)**
"@
        
        # Wait for minimum time before sending SMS, but respect deadline
        $elapsed = (Get-Date) - $script:Config.StartTime
        $remainingHours = $script:Config.MinRunHours - $elapsed.TotalHours
        $deadline = $script:Config.DeadlineTime
        
        if ($remainingHours -gt 0 -and $script:State.Status -ne "SUCCESS") {
            Write-Log "Waiting until min run time or deadline (08:45 AM)..." -Level INFO
            
            while ((Get-Date) -lt $script:Config.StartTime.AddHours($script:Config.MinRunHours) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 300
                Update-Report
                
                # Check if deadline approaching
                if ((Get-Date) -ge $deadline.AddMinutes(-5)) {
                    Write-Log "Deadline approaching - preparing final report" -Level WARN
                    break
                }
            }
        }
        
        # Force completion check at deadline
        if ((Get-Date) -ge $deadline) {
            Write-Log "Deadline reached (08:45 AM) - sending final status" -Level INFO
        }
        
        # Send SMS
        Write-Log "" -Level INFO
        Write-Log ("=" * 50) -Level INFO
        Write-Log "Sending SMS Notification" -Level INFO
        Write-Log ("=" * 50) -Level INFO
        
        Send-StatusSms
        
        Write-Log "" -Level INFO
        Write-Log ("=" * 70) -Level INFO
        Write-Log "AutoDoc Overnight Runner Complete" -Level INFO
        Write-Log "Final Status: $($script:State.Status)" -Level INFO
        Write-Log ("=" * 70) -Level INFO
        
    }
    catch {
        Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
        $script:State.Status = "FATAL_ERROR"
        Update-Report -AdditionalNotes "Fatal Error: $($_.Exception.Message)"
        Send-StatusSms
    }
    finally {
        if ($webJob) {
            Stop-Job $webJob -ErrorAction SilentlyContinue
            Remove-Job $webJob -ErrorAction SilentlyContinue
        }
    }
    
    return $script:State.Status
}
#endregion

# Entry point
Start-OvernightRunner
