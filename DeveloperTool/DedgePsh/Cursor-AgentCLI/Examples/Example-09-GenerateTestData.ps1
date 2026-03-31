<#
.SYNOPSIS
    Generate realistic test data using the model.
    Demonstrates asking the model to produce structured output that can
    be used directly in tests or seed scripts.
#>
param(
    [int]$RowCount = 5,
    [string]$OutputFile = (Join-Path $env:TEMP 'test-customers.json')
)

$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$result = & $invoker -Prompt @"
Generate $RowCount realistic Norwegian customer records as a JSON array.
Each record must have:
- customerNumber (6-digit integer)
- name (realistic Norwegian company name)
- orgNumber (9-digit Norwegian organization number, valid format)
- address (Norwegian street address)
- postalCode (4-digit Norwegian postal code)
- city (real Norwegian city)
- email (matching the company name)
- phone (Norwegian format +47...)

Return ONLY the JSON array, no explanation.
"@

$jsonText = $result.Result.Trim() -replace '```json\s*', '' -replace '```\s*', ''

try {
    $customers = $jsonText | ConvertFrom-Json
    Write-Host "=== Generated $($customers.Count) test customers ===" -ForegroundColor Cyan
    $customers | Format-Table customerNumber, name, city, phone -AutoSize

    $jsonText | Set-Content $OutputFile -Encoding utf8
    Write-Host "Saved to $($OutputFile)" -ForegroundColor Green
} catch {
    Write-Warning "Could not parse as JSON:"
    Write-Host $result.Result
}
