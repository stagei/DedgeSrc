#Requires -Version 7.0
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Import-Module GlobalFunctions -Force

$shareName = "DedgeCommon"

Write-LogMessage "Checking CachingMode for SMB share '$($shareName)'" -Level INFO

try {
    $share = Get-SmbShare -Name $shareName -ErrorAction Stop
}
catch {
    Write-LogMessage "SMB share '$($shareName)' not found on this server" -Level ERROR -Exception $_
    exit 1
}

$currentMode = $share.CachingMode
Write-LogMessage "Share '$($shareName)' path: $($share.Path), current CachingMode: $($currentMode)" -Level INFO

if ($currentMode -eq "Manual") {
    Write-LogMessage "CachingMode is already 'Manual' - clients can pin files for offline access. No changes needed." -Level INFO
    exit 0
}

Write-LogMessage "CachingMode is '$($currentMode)' - changing to 'Manual' to allow client-side offline caching" -Level WARN

try {
    Set-SmbShare -Name $shareName -CachingMode Manual -Force -ErrorAction Stop
    $updated = Get-SmbShare -Name $shareName
    Write-LogMessage "CachingMode changed from '$($currentMode)' to '$($updated.CachingMode)'" -Level INFO
}
catch {
    Write-LogMessage "Failed to set CachingMode on share '$($shareName)'" -Level ERROR -Exception $_
    exit 1
}

Write-LogMessage "DedgeCommon share is now configured for client-side offline caching" -Level INFO
exit 0
