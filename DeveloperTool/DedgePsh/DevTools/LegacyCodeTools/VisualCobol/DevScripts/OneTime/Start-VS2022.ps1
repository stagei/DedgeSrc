#Requires -Version 7.0
<#
.SYNOPSIS
    Launches Visual Studio 2022.
.DESCRIPTION
    Searches standard edition install paths (Community, Professional, Enterprise, BuildTools)
    and launches the first devenv.exe found.
#>
[CmdletBinding()]
param()

Import-Module GlobalFunctions -Force

$paths = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe'
    'C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe'
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.exe'
    'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\devenv.exe'
)

$found = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($found) {
    Start-Process -FilePath $found
    Write-LogMessage "Launched: $($found)" -Level INFO
} else {
    Write-LogMessage "Visual Studio 2022 devenv.exe not found in standard paths." -Level ERROR
    exit 1
}
