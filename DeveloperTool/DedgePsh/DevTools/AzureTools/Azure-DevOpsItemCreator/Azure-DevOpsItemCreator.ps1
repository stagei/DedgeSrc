
[CmdletBinding()]
param (
    [Parameter(ParameterSetName = 'JsonFile')]
    [string]$ConfigFile,

    [Parameter(ParameterSetName = 'Direct')]
    [int]$ParentId,

    [Parameter(ParameterSetName = 'Direct')]
    [ValidateSet('Epic', 'User Story', 'Task', 'Bug')]
    [string]$Type,

    [Parameter(ParameterSetName = 'Direct')]
    [string]$Title,

    [Parameter(ParameterSetName = 'Direct')]
    [string]$Description,

    [Parameter()]
    [string]$Organization,

    [Parameter()]
    [string]$Project
)
Import-Module AzureFunctions -Force

function Test-AzureCliRequirements {
    try {
        az --version | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Azure CLI is not installed. Auto installing..." -ForegroundColor Yellow
            Install-WingetPackage
        }

        $devopsExt = az extension list --query "[?name=='azure-devops'].version" -o tsv
        if (-not $devopsExt) {
            Write-Host "Installing Azure DevOps extension..."
            az extension add --name azure-devops
        }
        return $true
    }
    catch {
        Write-Error $_.Exception.Message
        return $false
    }
}

function Process-JsonConfig {
    param (
        [string]$ConfigFile
    )

    try {
        $config = Get-Content $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json

        foreach ($epic in $config.epics) {
            $epicItem = New-AdoWorkItem -Type 'Epic' -Title $epic.title -Description $epic.description -Organization $Organization -Project $Project
            if ($epicItem) {
                foreach ($story in $epic.stories) {
                    $storyItem = New-AdoWorkItem -Type 'User Story' -Title $story.title -Description $story.description -ParentId $epicItem.id -Organization $Organization -Project $Project
                    if ($storyItem) {
                        foreach ($task in $story.tasks) {
                            $taskItem = New-AdoWorkItem -Type 'Task' -Title $task.title -Description $task.description -ParentId $storyItem.id -Organization $Organization -Project $Project
                            if ($taskItem -and $task.PSObject.Properties.Name -contains 'subtasks') {
                                foreach ($subtask in $task.subtasks) {
                                    New-AdoWorkItem -Type 'Task' -Title $subtask.title -Description $subtask.description -ParentId $taskItem.id -Organization $Organization -Project $Project
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Failed to process JSON configuration: $_"
    }
}

if (-not (Test-AzureCliRequirements)) {
    exit 1
}

if (-not $Organization) { $Organization = Get-AzureDevOpsOrganization }
if (-not $Project) { $Project = Get-AzureDevOpsProject }

try {
    $orgUrl = "https://dev.azure.com/$Organization"
    $loggedIn = Assert-AzureDevOpsCliLogin -OrganizationUrl $orgUrl
    if (-not $loggedIn) {
        Write-Warning "Azure DevOps CLI login failed (PAT missing/invalid). az boards may fail."
    }
}
catch {
    Write-Warning "Could not load Azure DevOps PAT. az boards may prompt for authentication."
}

if ($PSCmdlet.ParameterSetName -eq 'JsonFile') {
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Configuration file not found: $ConfigFile"
        exit 1
    }
    Process-JsonConfig -ConfigFile $ConfigFile
}
else {
    New-AdoWorkItem -Type $Type -Title $Title -Description $Description -ParentId $ParentId -Organization $Organization -Project $Project
}
