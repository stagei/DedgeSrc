<#
.SYNOPSIS
    Extract structured JSON data from unstructured text using the model.
    Demonstrates how to parse the model's text output into PowerShell objects.
#>
$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$logSnippet = @"
2026-03-25 08:14:02 ERROR [AuthService] Failed login for user john.doe@company.com from 10.0.1.55 - Invalid credentials
2026-03-25 08:14:15 WARN  [RateLimiter] User john.doe@company.com approaching rate limit (48/50)
2026-03-25 08:15:01 ERROR [AuthService] Failed login for user admin@company.com from 192.168.1.100 - Account locked
2026-03-25 08:15:33 INFO  [AuthService] Successful login for user jane.smith@company.com from 10.0.1.42
2026-03-25 08:16:00 ERROR [DbConnection] Connection timeout to BASISTST after 30000ms - retrying (attempt 2/3)
2026-03-25 08:16:05 ERROR [DbConnection] Connection timeout to BASISTST after 30000ms - retrying (attempt 3/3)
2026-03-25 08:16:10 CRITICAL [DbConnection] All retry attempts exhausted for BASISTST. Service degraded.
"@

$result = & $invoker -Prompt @"
Parse these log entries into a JSON array. For each entry extract:
- timestamp (ISO 8601)
- level (ERROR, WARN, INFO, CRITICAL)
- component (the part in brackets)
- summary (short description)
- severity_score (1-10, where 10 is most severe)

Return ONLY the JSON array, no explanation.

LOG:
$logSnippet
"@

$jsonText = $result.Result.Trim()
# Strip markdown fences if the model wraps them
$jsonText = $jsonText -replace '```json\s*', '' -replace '```\s*', ''

try {
    $entries = $jsonText | ConvertFrom-Json
    Write-Host "=== Parsed $($entries.Count) log entries ===" -ForegroundColor Cyan
    $entries | Format-Table timestamp, level, component, severity_score, summary -AutoSize
    
    $critical = $entries | Where-Object { $_.severity_score -ge 8 }
    if ($critical) {
        Write-Host "`nHigh-severity items:" -ForegroundColor Red
        $critical | ForEach-Object { Write-Host "  [$($_.level)] $($_.summary)" -ForegroundColor Red }
    }
} catch {
    Write-Warning "Could not parse model output as JSON. Raw response:"
    Write-Host $result.Result
}
