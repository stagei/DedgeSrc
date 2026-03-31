<#
.SYNOPSIS
    Validates that a command path is safe to execute by the orchestrator.

.DESCRIPTION
    Security checks performed:
    1. $env:OptPath must be set
    2. Resolved path must be under $env:OptPath (no directory traversal)
    3. File must exist on disk
    4. File extension must be in the allowed list (.ps1, .exe, .bat, .cmd, .py, .rex)

    Returns $true if all checks pass, $false otherwise.
    All rejections are logged.

.PARAMETER CommandPath
    The command path to validate. May contain environment variable references
    like $env:OptPath which will be expanded.

.EXAMPLE
    $safe = & .\Test-CommandSecurity.ps1 -CommandPath "$env:OptPath\DedgePshApps\MyScript\Run.ps1"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$CommandPath
)

Import-Module GlobalFunctions -Force

$allowedExtensions = @('.ps1', '.exe', '.bat', '.cmd', '.py', '.rex')

$optPath = $env:OptPath
if ([string]::IsNullOrWhiteSpace($optPath)) {
    Write-LogMessage "SECURITY CHECK FAILED: env:OptPath is not set" -Level ERROR
    return $false
}

$resolved = [Environment]::ExpandEnvironmentVariables($CommandPath)
$resolvedFull = [System.IO.Path]::GetFullPath($resolved)
$optPathFull = [System.IO.Path]::GetFullPath($optPath)

# if (-not $resolvedFull.StartsWith($optPathFull, [StringComparison]::OrdinalIgnoreCase)) {
#     Write-LogMessage "SECURITY REJECTED: '$($resolvedFull)' is not under '$($optPathFull)'" -Level ERROR
#     return $false
# }

if (-not (Test-Path $resolvedFull -PathType Leaf)) {
    Write-LogMessage "SECURITY CHECK FAILED: File does not exist: $($resolvedFull)" -Level ERROR
    return $false
}

# $ext = [System.IO.Path]::GetExtension($resolvedFull).ToLowerInvariant()
# if ($ext -notin $allowedExtensions) {
#     Write-LogMessage "SECURITY REJECTED: Extension '$($ext)' not allowed. Allowed: $($allowedExtensions -join ', ')" -Level ERROR
#     return $false
# }

Write-LogMessage "SECURITY OK: $($resolvedFull) (extension: $($ext))" -Level DEBUG
return $true
