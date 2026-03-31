<#
.SYNOPSIS
    Silent MSI install for IIS-AutoDeploy.Tray.
    Called by Install-OurWinApp when it finds _install.ps1 in the app folder.
.DESCRIPTION
    Locates the MSI in the same directory and runs msiexec /i /qn.
    The process running this script (IIS-DeployApp / IIS-RedeployAll) is
    already elevated, so no UAC prompt appears.
#>

$msiFile = Get-ChildItem -Path $PSScriptRoot -Filter "*.msi" -File -ErrorAction SilentlyContinue |
Select-Object -First 1

if (-not $msiFile) {
    Write-LogMessage "IIS-AutoDeploy-Tray _install.ps1: No MSI found in $($PSScriptRoot), skipping" -Level WARN
    return
}

$msiPath = $msiFile.FullName
Write-LogMessage "IIS-AutoDeploy-Tray _install.ps1: Installing $($msiFile.Name) silently..." -Level INFO

$proc = Start-Process -FilePath "msiexec.exe" `
    -ArgumentList "/i `"$($msiPath)`" /qn" `
    -Wait -PassThru -WindowStyle Hidden

if ($proc.ExitCode -eq 0) {
    Write-LogMessage "IIS-AutoDeploy-Tray _install.ps1: MSI installed successfully (exit code 0)" -Level INFO
}
elseif ($proc.ExitCode -eq 3010) {
    Write-LogMessage "IIS-AutoDeploy-Tray _install.ps1: MSI installed, reboot required (exit code 3010)" -Level WARN
}
else {
    Write-LogMessage "IIS-AutoDeploy-Tray _install.ps1: MSI install failed with exit code $($proc.ExitCode)" -Level ERROR
}

Import-Module ScheduledTask-Handler -Force
New-ScheduledTask -SourceFolder (Join-Path $env:OptPath "DedgeWinApps\IIS-AutoDeploy-Tray") -Executable "IIS-AutoDeploy.Tray.exe" -TaskFolder "DevTools" -RecreateTask:$true -RunFrequency "EveryMinute" -StartHour 1 -RunAsUser:$true -RunAtOnce:$true
