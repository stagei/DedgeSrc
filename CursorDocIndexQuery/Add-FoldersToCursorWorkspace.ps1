#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or updates a Cursor multi-root workspace; list or remove indexed folders in that file.

.DESCRIPTION
    The Cursor CLI does not have an "add folder to index" command. Indexing happens when you
    open a workspace in the Cursor IDE. This script manages a .code-workspace file that
    lists the folders you want indexed; when you open that file in Cursor, all listed
    roots are indexed. You can list or remove folders from that workspace file.

.PARAMETER List
    List the folder paths currently in the workspace file. No create/remove.

.PARAMETER RemovePaths
    Paths to remove from the workspace file (resolved to absolute for matching). Save and exit.

.PARAMETER FoldersToIndex
    Full paths of folders to include in the workspace (replaces current list when not using -List/-RemovePaths).
    Default: this project (CursorDocIndexQuery) and its parent (DedgeSrc).

.PARAMETER WorkspaceFilePath
    Path for the .code-workspace file. Default: .\DedgeSrc-Indexed.code-workspace in this script's directory.

.PARAMETER OpenInCursor
    After creating/updating the workspace, open it in Cursor. Requires the "cursor" shell command.

.EXAMPLE
    pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -List
    pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -RemovePaths "C:\opt\src\DedgeSrc\CursorDocIndexQuery"
    pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -OpenInCursor
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch] $List,
    [Parameter()]
    [string[]] $RemovePaths = @(),
    [Parameter()]
    [string[]] $FoldersToIndex = @(
        (Split-Path $PSScriptRoot -Parent),
        $PSScriptRoot
    ),
    [string] $WorkspaceFilePath = (Join-Path $PSScriptRoot 'DedgeSrc-Indexed.code-workspace'),
    [switch] $OpenInCursor
)

$ErrorActionPreference = 'Stop'
$WorkspaceFilePath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspaceFilePath)

function Get-NormalizedPath {
    param([string] $p)
    $abs = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
    return [System.IO.Path]::GetFullPath($abs).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

# --- List: read workspace and output folder paths
if ($List) {
    if (-not (Test-Path -LiteralPath $WorkspaceFilePath -PathType Leaf)) {
        Write-Host "No workspace file at: $($WorkspaceFilePath)"
        exit 0
    }
    try {
        $json = Get-Content -LiteralPath $WorkspaceFilePath -Raw -Encoding utf8 | ConvertFrom-Json
        $folders = @($json.folders)
        if ($folders.Count -eq 0) {
            Write-Host "Workspace has no folders."
            exit 0
        }
        Write-Host "Indexed folders in $($WorkspaceFilePath):"
        foreach ($f in $folders) {
            $path = $f.path
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $resolvedPath = Get-NormalizedPath $path
                Write-Host "  $($resolvedPath)"
            }
        }
    } catch {
        Write-Error "Could not read workspace file: $_"
        exit 1
    }
    exit 0
}

# --- Remove: load workspace, remove matching paths, save
if ($RemovePaths.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $WorkspaceFilePath -PathType Leaf)) {
        Write-Error "Workspace file not found: $($WorkspaceFilePath)"
        exit 1
    }
    try {
        $json = Get-Content -LiteralPath $WorkspaceFilePath -Raw -Encoding utf8 | ConvertFrom-Json
        $toRemove = @($RemovePaths | ForEach-Object { Get-NormalizedPath $_ })
        $current = @($json.folders)
        $remaining = @($current | Where-Object {
            $p = Get-NormalizedPath $_.path
            $p -notin $toRemove
        })
        $json.folders = @($remaining)
        $json | ConvertTo-Json -Depth 3 | Out-File -LiteralPath $WorkspaceFilePath -Encoding utf8
        Write-Host "Removed $($RemovePaths -join ', ') from workspace. Remaining folders: $($remaining.Count)"
        foreach ($r in $remaining) { Write-Host "  $($r.path)" }
    } catch {
        Write-Error "Could not update workspace file: $_"
        exit 1
    }
    if ($OpenInCursor) {
        $cursorCmd = Get-Command -Name 'cursor' -ErrorAction SilentlyContinue
        if ($cursorCmd) { & cursor $WorkspaceFilePath }
    }
    exit 0
}

# --- Add/Set: create or overwrite workspace with FoldersToIndex
$resolved = @()
foreach ($folder in $FoldersToIndex) {
    $abs = Get-NormalizedPath $folder
    if (-not (Test-Path -LiteralPath $abs -PathType Container)) {
        Write-Warning "Folder not found, skipping: $($abs)"
        continue
    }
    $resolved += $abs
}

if ($resolved.Count -eq 0) {
    Write-Error "No valid folders to index."
    exit 1
}

$folderEntries = $resolved | ForEach-Object { @{ path = $_ } }
$workspace = @{ folders = @($folderEntries); settings = @{} } | ConvertTo-Json -Depth 3
$workspace | Out-File -LiteralPath $WorkspaceFilePath -Encoding utf8
Write-Host "Workspace file written: $($WorkspaceFilePath)"
Write-Host "Folders that will be indexed when you open this workspace:"
foreach ($f in $resolved) { Write-Host "  - $($f)" }

if ($OpenInCursor) {
    $cursorCmd = Get-Command -Name 'cursor' -ErrorAction SilentlyContinue
    if (-not $cursorCmd) {
        Write-Warning "Shell command 'cursor' not found. Open the workspace manually: File > Open Workspace from File > $($WorkspaceFilePath)"
        exit 0
    }
    Write-Host "Opening workspace in Cursor..."
    & cursor $WorkspaceFilePath
}
