<#
.SYNOPSIS
    Fetches full metadata for a work item from Azure DevOps and returns it in _azstory.json schema format.
.PARAMETER WorkItemId
    The Azure DevOps work item ID.
.EXAMPLE
    .\Get-AzStoryMetadata.ps1 -WorkItemId 12345
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
    $f = $wi.fields

    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $branch = git branch --show-current 2>$null

    $parentId = $null
    if ($wi.relations) {
        $parentRel = $wi.relations | Where-Object { $_.attributes.name -eq 'Parent' } | Select-Object -First 1
        if ($parentRel) {
            # Extract ID from URL: https://dev.azure.com/org/project/_apis/wit/workItems/12345
            if ($parentRel.url -match '/(\d+)$') {
                $parentId = [int]$matches[1]
            }
        }
    }

    $entry = [PSCustomObject]@{
        id            = $wi.id
        type          = $f.'System.WorkItemType'
        parentId      = $parentId
        title         = $f.'System.Title'
        state         = $f.'System.State'
        previousState = $null
        subProject    = $null
        assignedTo    = $f.'System.AssignedTo'.'displayName'
        areaPath      = $f.'System.AreaPath'
        iterationPath = $f.'System.IterationPath'
        tags          = $f.'System.Tags'
        created       = $f.'System.CreatedDate'
        updated       = $now
        registered    = $now
        branch        = $branch
        context       = $null
        linkedFiles   = @()
    }

    $entry | ConvertTo-Json -Depth 5
}
catch {
    Write-LogMessage "Error fetching metadata for WI-$($WorkItemId): $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
