Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module SoftwareUtils -Force

# $tempPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"
# if (Test-Path -Path $tempPath -PathType Container) {
#     Remove-Item -Path $tempPath -Recurse -Force
# }
$mfpath = "C:\Program Files (x86)\Micro Focus"
if (Test-Path -Path $mfpath -PathType Container) {
    $object = Get-RegListSearchResults -SearchString "Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\6EC9DDDF052905D4687BAC8742FB7E8E" -Recurse
    # Micro Focus Net Express 5.1

    $object.result | Format-Table -AutoSize -Property Name, Value, DataType, RelativePath
    #C:\Windows\Installer\{FDDD9CE6-9250-4D50-86B7-CA7824BFE7E8}\1033.MST
    $guid = $object.result | Where-Object { $_.Name -eq "Transforms" } | Select-Object -ExpandProperty Value
    Write-Host "GUID: $guid" -ForegroundColor Yellow
    # Extract GUID from the transforms path using regex
    $extractedGuid = $null
    if ($guid -match '\{([A-F0-9\-]{36})\}') {
        $extractedGuid = $matches[1]
    }
    if ($extractedGuid) {
        $command = "msiexec.exe /x {$extractedGuid} /quiet"
        Write-Host "Command: $command" -ForegroundColor Yellow
        Start-Process "msiexec.exe" -ArgumentList "/x {$extractedGuid} /quiet" -Wait

        Remove-Item -Path "C:\Program Files (x86)\Micro Focus" -Recurse -Force

        # HKEY_CURRENT_USER\Software\Micro Focus
        Remove-Item -Path "Registry::HKEY_CURRENT_USER\Software\Micro Focus" -Recurse -Force
        Write-Host "Restarting system in 10 seconds" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }

}
# try {
#     # 1. Uninstall MicroFocus NetExpress Pack
#     Write-LogMessage "Uninstalling MicroFocus NetExpress Pack" -Level INFO
#     $guid = "{6EC9DDDF052905D4687BAC8742FB7E8E}"
#     $command = "msiexec.exe /x $guid"
#     Write-LogMessage "Running command: $command" -Level INFO
#     Start-Process "msiexec.exe" -ArgumentList "/x $guid /quiet" -Wait
# }
# catch {
#     Write-LogMessage "Failed to uninstall MicroFocus NetExpress Pack" -Level ERROR -Exception $_
# }

try {
    # 2. Install MicroFocus NetExpress Pack
    Write-LogMessage "Reinstalling MicroFocus NetExpress Pack" -Level INFO
    $appName = "MicroFocus NetExpress Pack"
    Install-WindowsApps -AppName $appName -Force
}
catch {
    Write-LogMessage "Failed to reinstall MicroFocus NetExpress Pack" -Level ERROR -Exception $_
}

# # 1. Microsoft Visual C++ 2010  x64 Redistributable - 10.0.40219 [v10.0.40219]
# # 2. Microsoft Visual C++ 2010  x86 Redistributable - 10.0.40219 [v10.0.40219]
# # 3. Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211 [v14.44.35211.0]
# # 4. Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.44.35211 [v14.44.35211.0]

# Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\6EC9DDDF052905D4687BAC8742FB7E8E

