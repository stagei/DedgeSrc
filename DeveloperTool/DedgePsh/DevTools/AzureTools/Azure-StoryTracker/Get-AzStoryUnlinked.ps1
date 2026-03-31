<#
.SYNOPSIS
    Queries Azure DevOps for all open work items tagged 'AzStory' and returns them as JSON.
.DESCRIPTION
    Runs a WIQL query against Azure DevOps to find open items with the AzStory tag.
    Returns a JSON array of {id, title, type, state} objects.
.EXAMPLE
    .\Get-AzStoryUnlinked.ps1
#>
[CmdletBinding()]
param()

Import-Module GlobalFunctions -Force

$org = Get-AzureDevOpsOrganization
$proj = Get-AzureDevOpsProject

$wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType] FROM WorkItems WHERE [System.Tags] CONTAINS 'AzStory' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"

try {
    $rawResult = az boards query --wiql $wiql --org "https://dev.azure.com/$org" --project $proj --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-LogMessage "Failed to query Azure DevOps: $rawResult" -Level ERROR
        exit 1
    }

    $items = $rawResult | ConvertFrom-Json

    $output = $items | ForEach-Object {
        [PSCustomObject]@{
            id    = $_.fields.'System.Id'
            title = $_.fields.'System.Title'
            type  = $_.fields.'System.WorkItemType'
            state = $_.fields.'System.State'
        }
    }

    $output | ConvertTo-Json -Depth 5
}
catch {
    Write-LogMessage "Error querying AzStory items: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
