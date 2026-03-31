<#
.SYNOPSIS
    Scans all _azstory.json files under C:\opt\src and returns combined list of tracked work item IDs with project paths.
.DESCRIPTION
    Recursively searches for _azstory.json files (depth 2) and collects all tracked work item IDs
    along with the project path they belong to.
.EXAMPLE
    .\Get-AzStoryLinked.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = "C:\opt\src"
)

Import-Module GlobalFunctions -Force

$results = @()

$jsonFiles = Get-ChildItem -Path $Root -Filter "_azstory.json" -Recurse -Depth 2 -ErrorAction SilentlyContinue

foreach ($file in $jsonFiles) {
    try {
        $entries = Get-Content -Path $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json

        foreach ($entry in $entries) {
            $results += [PSCustomObject]@{
                id          = $entry.id
                title       = $entry.title
                state       = $entry.state
                type        = $entry.type
                projectPath = $file.DirectoryName
                subProject  = $entry.subProject
            }
        }
    }
    catch {
        Write-LogMessage "Failed to parse $($file.FullName): $($_.Exception.Message)" -Level WARN
    }
}

$results | ConvertTo-Json -Depth 5
