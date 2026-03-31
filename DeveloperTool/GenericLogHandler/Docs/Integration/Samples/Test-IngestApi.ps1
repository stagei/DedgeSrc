<#
.SYNOPSIS
    Stress-test the GenericLogHandler ingest API by sending 64,000 messages.

.DESCRIPTION
    Sends one log entry every 0.5 seconds using a single HttpClient (connection reuse
    to avoid ephemeral port exhaustion). Logs progress every 500 messages and sends
    an SMS when complete.

.PARAMETER MessageCount
    Total number of messages to send. Default: 64000.

.PARAMETER DelayMs
    Milliseconds between sends. Default: 500 (0.5s).

.PARAMETER BaseUrl
    GenericLogHandler base URL. Default: http://localhost/GenericLogHandler.
#>

[CmdletBinding()]
param(
    [int]$MessageCount = 64000,
    [int]$DelayMs = 500,
    [string]$BaseUrl = 'http://localhost/GenericLogHandler'
)

Import-Module GlobalFunctions -Force

$endpoint = "$($BaseUrl)/api/Logs/ingest"
$startTime = Get-Date
$successCount = 0
$failCount = 0
$lastProgressTime = $startTime

Write-LogMessage "============================================" -Level INFO
Write-LogMessage "Ingest API Stress Test" -Level INFO
Write-LogMessage "  Endpoint:  $($endpoint)" -Level INFO
Write-LogMessage "  Messages:  $($MessageCount)" -Level INFO
Write-LogMessage "  Delay:     $($DelayMs)ms" -Level INFO
Write-LogMessage "  ETA:       $('{0:N1}' -f ($MessageCount * $DelayMs / 3600000.0)) hours" -Level INFO
Write-LogMessage "============================================" -Level INFO

# Single HttpClient with connection pooling — prevents port exhaustion
$handler = [System.Net.Http.SocketsHttpHandler]::new()
$handler.PooledConnectionLifetime = [TimeSpan]::FromMinutes(10)
$handler.MaxConnectionsPerServer = 4
$http = [System.Net.Http.HttpClient]::new($handler)
$http.Timeout = [TimeSpan]::FromSeconds(15)

$levels  = @('DEBUG', 'INFO', 'INFO', 'INFO', 'WARN', 'ERROR', 'FATAL')
$sources = @('TestHarness', 'OrderService', 'BatchJob', 'Scheduler', 'DataLoader')
$jobs    = @('NightlySync', 'OrderImport', 'ReportGen', 'CleanupJob', 'IndexRebuild')
$statuses = @('Started', 'Running', 'Completed', 'Failed')

try {
    for ($i = 1; $i -le $MessageCount; $i++) {
        # Early feedback for first few messages
        if ($i -le 5) {
            Write-Host "Sending message $($i)..."
        }

        $level  = $levels[$i % $levels.Count]
        $source = $sources[$i % $sources.Count]

        $body = @{
            message      = "Test message $($i) of $($MessageCount) — $(Get-Date -Format 'HH:mm:ss.fff')"
            level        = $level
            source       = $source
            computerName = $env:COMPUTERNAME
            userName     = $env:USERNAME
            functionName = "Test-IngestApi"
            location     = "Test-IngestApi.ps1"
        }

        # Every 10th message is a job event
        if ($i % 10 -eq 0) {
            $body.jobName   = $jobs[($i / 10) % $jobs.Count]
            $body.jobStatus = $statuses[($i / 10) % $statuses.Count]
        }

        # Every 50th message is an error with details
        if ($i % 50 -eq 0) {
            $body.level         = 'ERROR'
            $body.errorId       = "TST-$('{0:D5}' -f $i)"
            $body.exceptionType = 'System.TimeoutException'
            $body.stackTrace    = "at TestHarness.Run() line $($i)"
        }

        $json = $body | ConvertTo-Json -Compress -Depth 3
        $content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')

        try {
            $response = $http.PostAsync($endpoint, $content).GetAwaiter().GetResult()
            if ($response.IsSuccessStatusCode) {
                $successCount++
                if ($i -le 10) {
                    Write-Host "Message $($i) queued OK (HTTP $($response.StatusCode))"
                }
            }
            else {
                $failCount++
                if ($failCount -le 10 -or $failCount % 100 -eq 0) {
                    Write-LogMessage "HTTP $($response.StatusCode) on message $($i)" -Level WARN
                }
            }
            $response.Dispose()
        }
        catch {
            $failCount++
            if ($failCount -le 10 -or $failCount % 100 -eq 0) {
                Write-LogMessage "Send failed on message $($i): $($_.Exception.Message)" -Level ERROR
            }
        }
        finally {
            $content.Dispose()
        }

        # Dot indicator every 10 messages to show activity
        if ($i % 10 -eq 0 -and $i % 100 -ne 0) {
            Write-Host "." -NoNewline
        }

        # Progress report every 100 messages
        if ($i % 100 -eq 0) {
            Write-Host ""
            $elapsed = (Get-Date) - $startTime
            $rate = $i / $elapsed.TotalSeconds
            $remaining = ($MessageCount - $i) / $rate
            Write-LogMessage ("Progress: {0:N0}/{1:N0} ({2:P1}) | OK: {3:N0} | Fail: {4:N0} | Rate: {5:N1}/s | ETA: {6}" -f `
                $i, $MessageCount, ($i / $MessageCount), $successCount, $failCount, $rate, `
                [TimeSpan]::FromSeconds($remaining).ToString('hh\:mm\:ss')) -Level INFO
        }

        if ($i -lt $MessageCount) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}
finally {
    $http.Dispose()
    $handler.Dispose()
}

$elapsed = (Get-Date) - $startTime
$elapsedStr = $elapsed.ToString('hh\:mm\:ss')

Write-LogMessage "============================================" -Level INFO
Write-LogMessage "Test Complete" -Level INFO
Write-LogMessage "  Duration:  $($elapsedStr)" -Level INFO
Write-LogMessage "  Sent:      $($MessageCount)" -Level INFO
Write-LogMessage "  Success:   $($successCount)" -Level INFO
Write-LogMessage "  Failed:    $($failCount)" -Level INFO
Write-LogMessage "  Rate:      $('{0:N1}' -f ($MessageCount / $elapsed.TotalSeconds))/s" -Level INFO
Write-LogMessage "============================================" -Level INFO

# Send SMS with result
$smsNumber = switch ($env:USERNAME) {
    "FKGEISTA" { "+4797188358" }
    "FKSVEERI" { "+4795762742" }
    "FKMISTA"  { "+4799348397" }
    "FKCELERI" { "+4745269945" }
    default    { "+4797188358" }
}

$status = if ($failCount -eq 0) { "ALL OK" } else { "$($failCount) FAILED" }
$smsMsg = "IngestAPI test done. $($successCount)/$($MessageCount) OK. $($status). $($elapsedStr)"
Send-Sms -Receiver $smsNumber -Message $smsMsg
Write-LogMessage "SMS sent to $($smsNumber)" -Level INFO
