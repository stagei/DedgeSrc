<#
.SYNOPSIS
    Ensures the 'AzStory' tag exists on a work item. Idempotent — skips if already present.
.PARAMETER WorkItemId
    The Azure DevOps work item ID.
.EXAMPLE
    .\Set-AzStoryTag.ps1 -WorkItemId 12345
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$WorkItemId
)

Import-Module GlobalFunctions -Force

$org = Get-AzureDevOpsOrganization
$proj = Get-AzureDevOpsProject

try {
    $rawResult = az boards work-item show --id $WorkItemId --org "https://dev.azure.com/$org" --project $proj --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-LogMessage "Failed to fetch WI-$($WorkItemId): $rawResult" -Level ERROR
        exit 1
    }

    $wi = $rawResult | ConvertFrom-Json
    $currentTags = $wi.fields.'System.Tags'

    if ($currentTags -and $currentTags -match '\bAzStory\b') {
        Write-LogMessage "WI-$WorkItemId already has AzStory tag" -Level INFO
        exit 0
    }

    $managerScript = Join-Path $PSScriptRoot "..\Azure-DevOpsUserStoryManager\Azure-DevOpsUserStoryManager.ps1"
    if (Test-Path $managerScript) {
        & $managerScript -WorkItemId $WorkItemId -Action AddTags -Tags "AzStory"
    }
    else {
        $newTags = if ($currentTags) { "$currentTags; AzStory" } else { "AzStory" }
        az boards work-item update --id $WorkItemId --fields "System.Tags=$newTags" --org "https://dev.azure.com/$org" --project $proj --output json 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Failed to add AzStory tag to WI-$WorkItemId" -Level ERROR
            exit 1
        }
    }

    Write-LogMessage "Added AzStory tag to WI-$WorkItemId" -Level INFO
}
catch {
    Write-LogMessage "Error setting AzStory tag on WI-$($WorkItemId): $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
