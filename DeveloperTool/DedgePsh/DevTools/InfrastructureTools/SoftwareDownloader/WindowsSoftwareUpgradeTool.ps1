[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeWinget,
    [Parameter(Mandatory = $false)]
    [switch]$IncludeWindowsApps,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    [Parameter(Mandatory = $false)]
    [switch]$ForceReinstall,
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ""
)

Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force

try {
    Write-LogMessage "WindowsSoftwareUpgradeTool started" -Level JOB_STARTED

    if (-not $IncludeWinget -and -not $IncludeWindowsApps) {
        $IncludeWinget = $true
        $IncludeWindowsApps = $true
    }

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ReportPath = Join-Path (Get-ScriptLogPath) "WindowsSoftwareUpgradeTool-$($timestamp).json"
    }

    $result = Update-InstalledSoftwareFromArchives `
        -IncludeWinget:$IncludeWinget `
        -IncludeWindowsApps:$IncludeWindowsApps `
        -WhatIf:$WhatIf `
        -ForceReinstall:$ForceReinstall `
        -ReportPath $ReportPath

    if ($null -eq $result -or $null -eq $result.Summary) {
        Write-LogMessage "WindowsSoftwareUpgradeTool did not receive a valid result object." -Level WARN
    }
    else {
        Write-LogMessage "Upgrade summary: Updated=$($result.Summary.UpdatedCount), UpToDate=$($result.Summary.UpToDateCount), SkippedUnknown=$($result.Summary.SkippedUnknownVersionCount), SkippedNoArchive=$($result.Summary.SkippedNoArchiveCount), Failed=$($result.Summary.FailedCount)" -Level INFO
        Write-LogMessage "Detailed report path: $($ReportPath)" -Level INFO
    }

    Write-LogMessage "WindowsSoftwareUpgradeTool completed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "WindowsSoftwareUpgradeTool failed: $($_.Exception.Message)" -Level JOB_FAILED -Exception $_
    throw
}
