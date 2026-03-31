#Requires -Version 7.0
<#
.SYNOPSIS
    Launches Visual Studio 2022.
#>
$paths = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe'
    'C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe'
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.exe'
    'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\devenv.exe'
)
$found = $null
foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
        $found = $p
        break
    }
}
if ($found) {
    Start-Process -FilePath $found
    Write-Host "Launched: $found"
} else {
    Write-Warning "Visual Studio 2022 devenv.exe not found in standard paths. Try Start menu: Visual Studio 2022"
    exit 1
}
