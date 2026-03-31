<#
.SYNOPSIS
    Translate text between languages.
    Demonstrates a practical non-coding use case for the agent.
#>
param(
    [string]$Text = 'Denne COBOL-modulen behandler kornmottak ved siloene og beregner trekk basert på fuktighet og urenheter.',
    [string]$FromLang = 'Norwegian',
    [string]$ToLang = 'English'
)

$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$result = & $invoker -Prompt @"
Translate the following $FromLang text to $ToLang.
Return ONLY the translation, nothing else.

$Text
"@ -Model 'gpt-5.4-nano-low'

Write-Host "=== Translation ($($FromLang) -> $($ToLang)) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Original:    $($Text)" -ForegroundColor DarkGray
Write-Host "Translated:  $($result.Result.Trim())" -ForegroundColor White
Write-Host ""
Write-Host "$($result.DurationMs)ms" -ForegroundColor DarkGray
