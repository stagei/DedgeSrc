<#
.SYNOPSIS
    Look up and explain error codes from various systems.
    Demonstrates using the model as a knowledge base for debugging.
#>
param(
    [string]$ErrorCode = 'SQL30082N',
    [string]$Context = 'DB2 LUW connection from COBOL program on Windows'
)

$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$result = & $invoker -Prompt @"
Explain this error code: $ErrorCode

Context: $Context

Provide:
1. What the error means
2. Common causes (as a numbered list)
3. Step-by-step resolution
4. Example fix if applicable
"@ -Model 'composer-2'

Write-Host "=== $($ErrorCode) ===" -ForegroundColor Cyan
Write-Host $result.Result
Write-Host "`n$($result.DurationMs)ms" -ForegroundColor DarkGray
