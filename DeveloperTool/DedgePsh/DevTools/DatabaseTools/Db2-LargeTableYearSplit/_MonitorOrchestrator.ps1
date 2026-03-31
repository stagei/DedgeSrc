param(
    [string]$ServerName = "t-no1fkmmig-db",
    [string]$Project = "large-table-split",
    [int]$PollSeconds = 120,
    [int]$MaxHours = 6
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
. (Join-Path $PSScriptRoot "..\..\CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1")

$suffix = "$($env:USERNAME)_$($Project -replace '[^a-zA-Z0-9_\-]', '_')"
$resultUnc = "\\$ServerName\opt\data\Cursor-ServerOrchestrator\last_result_$suffix.json"
$deadline = (Get-Date).AddHours($MaxHours)

Write-Host "Monitoring: $resultUnc (poll every $PollSeconds s, max $MaxHours h)"

while ((Get-Date) -lt $deadline) {
    if (Test-Path $resultUnc) {
        $local = Join-Path $env:TEMP "orch_result_$suffix.json"
        Copy-Item -Path $resultUnc -Destination $local -Force
        $raw = Get-Content $local -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $j = $raw | ConvertFrom-Json
                if ($null -ne $j.PSObject.Properties["exitCode"] -or $null -ne $j.PSObject.Properties["status"]) {
                    Write-Host "RESULT:" ($j | ConvertTo-Json -Compress -Depth 6)
                    exit 0
                }
            }
            catch { }
        }
    }
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') still running..."
    Start-Sleep -Seconds $PollSeconds
}

Write-Host "TIMEOUT after $MaxHours hours"
exit 1
