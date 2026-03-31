<#
.SYNOPSIS
    Ask a simple question and get the answer back as a PowerShell object.
#>
$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$result = & $invoker -Prompt "What are the SOLID principles in software engineering? List each with a one-sentence explanation."

Write-Host "`n=== Answer ===" -ForegroundColor Cyan
Write-Host $result.Result
Write-Host "`nModel: $($result.Model) | Duration: $($result.DurationMs)ms" -ForegroundColor DarkGray
