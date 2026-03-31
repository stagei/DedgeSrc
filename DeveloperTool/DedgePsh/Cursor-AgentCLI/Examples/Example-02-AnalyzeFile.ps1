<#
.SYNOPSIS
    Feed a file to the model and ask it to analyze the contents.
    Demonstrates -FilePaths for embedding file content directly in the prompt.
#>
$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$targetFile = Join-Path $PSScriptRoot '..\_deploy.ps1'

$result = & $invoker `
    -Prompt "Explain what this PowerShell script does and list any modules it depends on." `
    -FilePaths $targetFile

Write-Host "`n=== Analysis ===" -ForegroundColor Cyan
Write-Host $result.Result
