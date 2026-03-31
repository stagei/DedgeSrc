<#
.SYNOPSIS
    Template main script for a Cursor-ServerOrchestrator project.

.DESCRIPTION
    Replace this with your actual logic. This script runs on the target server
    when triggered by the orchestrator.

    The script's working directory will be the orchestrator root on the server.
    Use $PSScriptRoot to reference files relative to this project folder.
#>

Import-Module GlobalFunctions -Force

$configPath = Join-Path $PSScriptRoot "config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-LogMessage "Project '$($config.projectName)' starting on $($env:COMPUTERNAME)" -Level INFO

# --- Your logic here ---

Write-LogMessage "Project '$($config.projectName)' completed" -Level INFO
