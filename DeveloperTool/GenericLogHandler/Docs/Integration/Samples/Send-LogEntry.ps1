<#
.SYNOPSIS
    Send log entries to the Generic Log Handler ingest API.

.DESCRIPTION
    Fire-and-forget log submission. Entries are queued and processed asynchronously.
    Supports single entries and batch mode. Designed for use in scheduled tasks,
    deployment scripts, and monitoring jobs.

.PARAMETER BaseUrl
    The GenericLogHandler base URL. Defaults to the IIS virtual app on the test server.

.EXAMPLE
    # Minimal — just a message
    .\Send-LogEntry.ps1 -Message "Deployment completed"

.EXAMPLE
    # Full entry with job tracking
    .\Send-LogEntry.ps1 -Message "Nightly batch started" -Level INFO -Source "NightlyJob" `
        -JobName "OrderSync" -JobStatus "Started" -ComputerName $env:COMPUTERNAME

.EXAMPLE
    # Batch mode — send multiple entries at once
    $entries = @(
        @{ message = "Step 1 done"; level = "INFO"; source = "MyJob" },
        @{ message = "Step 2 failed"; level = "ERROR"; source = "MyJob"; errorId = "E-4501" }
    )
    .\Send-LogEntry.ps1 -Batch $entries
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Single')]
    [string]$Message,

    [Parameter(ParameterSetName = 'Single')]
    [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
    [string]$Level = 'INFO',

    [Parameter(ParameterSetName = 'Single')]
    [string]$Source,

    [Parameter(ParameterSetName = 'Single')]
    [string]$ComputerName,

    [Parameter(ParameterSetName = 'Single')]
    [string]$UserName,

    [Parameter(ParameterSetName = 'Single')]
    [string]$JobName,

    [Parameter(ParameterSetName = 'Single')]
    [ValidateSet('Started', 'Completed', 'Failed', 'Running')]
    [string]$JobStatus,

    [Parameter(ParameterSetName = 'Single')]
    [string]$ErrorId,

    [Parameter(ParameterSetName = 'Single')]
    [string]$FunctionName,

    [Parameter(ParameterSetName = 'Single')]
    [string]$Location,

    [Parameter(Mandatory, ParameterSetName = 'Batch')]
    [hashtable[]]$Batch,

    [string]$BaseUrl = 'http://dedge-server/GenericLogHandler'
)

function Send-Single {
    param([hashtable]$Entry, [string]$Url)

    $json = $Entry | ConvertTo-Json -Depth 5 -Compress
    try {
        $response = Invoke-RestMethod -Uri $Url -Method Post -Body $json `
            -ContentType 'application/json' -TimeoutSec 10 -ErrorAction Stop
        Write-Host "Queued: $($response.data.queued) entry"
    }
    catch {
        Write-Warning "Failed to send log entry: $($_.Exception.Message)"
    }
}

$singleUrl = "$($BaseUrl)/api/Logs/ingest"
$batchUrl  = "$($BaseUrl)/api/Logs/ingest/batch"

if ($PSCmdlet.ParameterSetName -eq 'Batch') {
    $json = $Batch | ConvertTo-Json -Depth 5 -Compress
    # Wrap in array if single item (ConvertTo-Json unwraps single-element arrays)
    if ($Batch.Count -eq 1) { $json = "[$json]" }

    try {
        $response = Invoke-RestMethod -Uri $batchUrl -Method Post -Body $json `
            -ContentType 'application/json' -TimeoutSec 30 -ErrorAction Stop
        Write-Host "Queued: $($response.data.queued) entries"
    }
    catch {
        Write-Warning "Failed to send batch: $($_.Exception.Message)"
    }
}
else {
    $entry = @{ message = $Message; level = $Level }

    if ($Source)       { $entry.source       = $Source }
    if ($ComputerName) { $entry.computerName = $ComputerName }
    if ($UserName)     { $entry.userName     = $UserName }
    if ($JobName)      { $entry.jobName      = $JobName }
    if ($JobStatus)    { $entry.jobStatus    = $JobStatus }
    if ($ErrorId)      { $entry.errorId      = $ErrorId }
    if ($FunctionName) { $entry.functionName = $FunctionName }
    if ($Location)     { $entry.location     = $Location }

    Send-Single -Entry $entry -Url $singleUrl
}


# ─────────────────────────────────────────────
# QUICK-USE FUNCTION (paste into your scripts)
# ─────────────────────────────────────────────
#
# function Write-IngestLog {
#     param(
#         [string]$Message,
#         [string]$Level = 'INFO',
#         [string]$Source = 'MyScript',
#         [string]$BaseUrl = 'http://dedge-server/GenericLogHandler'
#     )
#     $body = @{ message = $Message; level = $Level; source = $Source } | ConvertTo-Json -Compress
#     Invoke-RestMethod -Uri "$($BaseUrl)/api/Logs/ingest" -Method Post `
#         -Body $body -ContentType 'application/json' -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
# }
#
# Usage:
#   Write-IngestLog "Deployment started" -Level INFO -Source "Deploy-Script"
#   Write-IngestLog "Connection failed" -Level ERROR -Source "Deploy-Script"
