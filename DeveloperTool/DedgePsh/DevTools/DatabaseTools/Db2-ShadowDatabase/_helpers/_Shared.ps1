<#
.SYNOPSIS
    Shared helper for shadow database scripts. Dot-source this file.

.DESCRIPTION
    Provides Get-ShadowDatabaseConfigPath to resolve which config.*.json file
    to use based on a case-insensitive search for the computer name in each file.
#>

function Get-ShadowDatabaseConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )
    $computerName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($computerName)) {
        $fallback = Join-Path $ScriptRoot "config.json"
        if (Test-Path $fallback) { return $fallback }
        throw "COMPUTERNAME is empty and config.json not found at $($fallback)"
    }
    $configFiles = Get-ChildItem -Path $ScriptRoot -Filter "config.*.json" -File -ErrorAction SilentlyContinue
    foreach ($file in $configFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($content)) { continue }
        if ($content.IndexOf($computerName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $file.FullName
        }
    }
    $fallback = Join-Path $ScriptRoot "config.json"
    if (Test-Path $fallback) { return $fallback }
    throw "No config.*.json contains computer name '$($computerName)' and config.json not found at $($fallback)"
}
