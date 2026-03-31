<#
.SYNOPSIS
    Exports NTFS ACL (security permissions) for a folder to a JSON file.

.DESCRIPTION
    Reads the Access Control List for the given path and writes a JSON file
    with one entry per principal (Identity, FileSystemRights, Allow/Deny,
    InheritanceFlags, PropagationFlags). The output format matches the
    permissions template format used by IIS-DeployApp so the file can be
    used as PermissionsTemplatePath or merged into deploy templates.

    Intended to be copied to a server and run there (e.g. to capture
    C:\inetpub\wwwroot permissions and reuse them as a template).

.PARAMETER Path
    Folder path to read ACL from. Default: C:\inetpub\wwwroot

.PARAMETER OutputPath
    Full path for the output JSON file. Default: script folder or current
    directory, filename FolderPermissions_<sanitized-path>.json

.EXAMPLE
    .\Export-FolderPermissions.ps1
    Exports C:\inetpub\wwwroot to JSON in the script directory.

.EXAMPLE
    .\Export-FolderPermissions.ps1 -Path "C:\inetpub\wwwroot" -OutputPath "C:\temp\wwwroot.permissions.json"
    Exports wwwroot ACL to a specific file.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path = "C:\inetpub\wwwroot",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $null
)

$ErrorActionPreference = "Stop"

# Optional: use GlobalFunctions for logging when available (e.g. run from repo).
try {
    Import-Module GlobalFunctions -Force -ErrorAction Stop
    $script:UseLog = $true
}
catch {
    $script:UseLog = $false
}

function Write-Message {
    param([string]$Text, [string]$Level = "INFO")
    if ($script:UseLog) {
        Write-LogMessage $Text -Level $Level
    }
    else {
        Write-Host $Text
    }
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Message "Path does not exist or is not a directory: $($Path)" -Level ERROR
    exit 1
}

Write-Message "Reading ACL for: $($Path)" -Level INFO

try {
    $acl = Get-Acl -Path $Path -ErrorAction Stop
}
catch {
    Write-Message "Get-Acl failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}

$entries = [System.Collections.ArrayList]::new()
foreach ($access in $acl.Access) {
    if ($access -isnot [System.Security.AccessControl.FileSystemAccessRule]) {
        continue
    }
    $identity = $access.IdentityReference.Value
    $rights = $access.FileSystemRights.ToString()
    $accessControlType = $access.AccessControlType.ToString()
    $inheritanceFlags = $access.InheritanceFlags.ToString()
    $propagationFlags = $access.PropagationFlags.ToString()

    $entries.Add([PSCustomObject]@{
            Identity           = $identity
            FileSystemRights   = $rights
            AccessControlType  = $accessControlType
            InheritanceFlags   = $inheritanceFlags
            PropagationFlags   = $propagationFlags
        }) | Out-Null
}

$payload = [PSCustomObject]@{
    Description = "Exported from $($Path) on $($env:COMPUTERNAME) at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Path        = $Path
    Entries     = @($entries)
}

if (-not $OutputPath) {
    $safeName = $Path -replace '[\\/:*?"<>|]', '_'
    $fileName = "FolderPermissions_$($safeName).json"
    $OutputPath = Join-Path $PSScriptRoot $fileName
    if (-not (Test-Path $PSScriptRoot)) {
        $OutputPath = Join-Path (Get-Location) $fileName
    }
}

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$json = $payload | ConvertTo-Json -Depth 5
Set-Content -Path $OutputPath -Value $json -Encoding UTF8 -Force

Write-Message "Wrote $($entries.Count) permission entries to: $($OutputPath)" -Level INFO
