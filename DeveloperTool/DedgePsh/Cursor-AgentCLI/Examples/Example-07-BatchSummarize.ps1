<#
.SYNOPSIS
    Summarize multiple files in a folder, producing a markdown report.
    Demonstrates batch processing: loop over files, call the model for each,
    and collect results into a single output document.
#>
param(
    [string]$FolderPath = 'C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-AgentCLI\Examples',
    [string]$FileFilter = '*.ps1',
    [string]$OutputFile = (Join-Path $env:TEMP 'script-summaries.md')
)

$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'
$files = Get-ChildItem $FolderPath -Filter $FileFilter | Where-Object { $_.Name -ne (Split-Path $MyInvocation.MyCommand.Path -Leaf) }

if ($files.Count -eq 0) {
    Write-Host "No $($FileFilter) files found in $($FolderPath)" -ForegroundColor Yellow
    exit 0
}

Write-Host "Summarizing $($files.Count) files..." -ForegroundColor Cyan

$report = "# Script Summaries`n`nGenerated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"

foreach ($file in $files) {
    Write-Host "  Processing $($file.Name)..." -ForegroundColor DarkGray
    $result = & $invoker `
        -Prompt "Summarize this script in 2-3 sentences. What does it demonstrate?" `
        -FilePaths $file.FullName `
        -Model 'gpt-5.4-nano-low'

    $report += "`n## $($file.Name)`n`n$($result.Result.Trim())`n`n*Model: $($result.Model) | $($result.DurationMs)ms*`n"
}

$report | Set-Content $OutputFile -Encoding utf8
Write-Host "`nReport saved to $($OutputFile)" -ForegroundColor Green
Write-Host $report
