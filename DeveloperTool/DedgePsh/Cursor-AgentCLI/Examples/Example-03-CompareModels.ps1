<#
.SYNOPSIS
    Ask the same question to different models and compare their answers.
    Demonstrates -Model selection and timing differences.
#>
$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$question = "In exactly 3 bullet points, explain why immutability matters in concurrent programming."

$models = @(
    'gpt-5.4-nano-low'
    'composer-2'
    'claude-4.5-sonnet'
)

$results = @()
foreach ($model in $models) {
    Write-Host "`nQuerying $($model)..." -ForegroundColor Yellow
    $r = & $invoker -Prompt $question -Model $model
    $results += [PSCustomObject]@{
        Model      = $model
        DurationMs = $r.DurationMs
        Answer     = $r.Result.Trim()
    }
}

Write-Host "`n" -NoNewline
foreach ($r in $results) {
    Write-Host "=== $($r.Model) ($($r.DurationMs)ms) ===" -ForegroundColor Cyan
    Write-Host $r.Answer
    Write-Host ""
}

Write-Host "--- Timing Summary ---" -ForegroundColor Green
$results | Format-Table Model, DurationMs -AutoSize
