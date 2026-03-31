<#
.SYNOPSIS
    Feed multiple files to the model and ask for a code review.
    Demonstrates -FilePaths with an array of files.
#>
$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

$filesToReview = @(
    (Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'),
    (Join-Path $PSScriptRoot '..\Cursor-Agent-CLI.md')
)

$result = & $invoker `
    -Prompt @"
Review these files. For the PowerShell script, check for:
- Error handling gaps
- Parameter validation issues
- Windows-specific edge cases

For the markdown doc, check for:
- Accuracy of the examples
- Missing important topics
- Clarity of explanations

Return a structured review with sections for each file.
"@ `
    -FilePaths $filesToReview `
    -Model 'claude-4.5-sonnet'

Write-Host "`n=== Code Review ===" -ForegroundColor Cyan
Write-Host $result.Result
Write-Host "`nReview completed in $($result.DurationMs)ms" -ForegroundColor DarkGray
