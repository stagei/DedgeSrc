<#
.SYNOPSIS
    Upserts a work item entry into a project's _azstory.json file.
.DESCRIPTION
    Creates the file if missing, updates existing entry if ID matches, or appends a new entry.
.PARAMETER Path
    Path to the git repository root where _azstory.json lives.
.PARAMETER WorkItemId
    The Azure DevOps work item ID.
.PARAMETER EntryJson
    JSON string representing the full entry to upsert.
.EXAMPLE
    .\Update-AzStoryJson.ps1 -Path "C:\opt\src\DedgePsh" -WorkItemId 12345 -EntryJson '{"id":12345,...}'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [int]$WorkItemId,

    [Parameter(Mandatory)]
    [string]$EntryJson
)

Import-Module GlobalFunctions -Force

$filePath = Join-Path $Path "_azstory.json"

if (Test-Path $filePath) {
    $entries = Get-Content -Path $filePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($null -eq $entries) { $entries = @() }
    if ($entries -isnot [System.Array]) { $entries = @($entries) }
}
else {
    $entries = @()
}

$newEntry = $EntryJson | ConvertFrom-Json

$existingIndex = -1
for ($i = 0; $i -lt $entries.Count; $i++) {
    if ($entries[$i].id -eq $WorkItemId) {
        $existingIndex = $i
        break
    }
}

if ($existingIndex -ge 0) {
    $existing = $entries[$existingIndex]
    $newEntry.registered = $existing.registered

    $entryList = [System.Collections.ArrayList]@($entries)
    $entryList[$existingIndex] = $newEntry
    $entries = $entryList.ToArray()

    Write-LogMessage "Updated entry for WI-$WorkItemId in $filePath" -Level INFO
}
else {
    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    if (-not $newEntry.registered) {
        $newEntry | Add-Member -NotePropertyName "registered" -NotePropertyValue $now -Force
    }

    $entries = @($entries) + @($newEntry)
    Write-LogMessage "Added new entry for WI-$WorkItemId to $filePath" -Level INFO
}

$entries | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding utf8 -Force
Write-LogMessage "Saved _azstory.json with $($entries.Count) entries" -Level INFO
