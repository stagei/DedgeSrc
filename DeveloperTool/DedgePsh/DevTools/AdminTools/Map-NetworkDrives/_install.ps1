if ((Test-IsServer) -or $env:COMPUTERNAME.ToLower().StartsWith("p-no1avd")) {
    $scriptPath = Join-Path -Path $env:OptPath -ChildPath "DedgePshApps\Map-NetworkDrives\Map-NetworkDrives.bat"
    # Add to startup/login
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $valueName = "Map-NetworkDrives"
    Set-ItemProperty -Path $runKey -Name $valueName -Value $scriptPath -Type String -Force
    Write-Host "Added $scriptPath to startup/login" -ForegroundColor Green
}
else {
    Import-Module ScheduledTask-Handler -Force
    $xmlPath = Join-Path $env:OptPath "DedgePshApps\Map-NetworkDrives\Map-NetworkDrives.xml"
    $xmlPathTemp = Join-Path $env:Temp "Map-NetworkDrives.xml"
    $xmlContent = Get-Content -Path $xmlPath -Encoding UTF8
    $userSID = (New-Object System.Security.Principal.NTAccount("$($env:USERDOMAIN)\$($env:USERNAME)")).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $xmlContent = $xmlContent.Replace("S-1-5-21-707222023-3458345710-300467842-74293", $userSID)
    $xmlContent | Out-File -FilePath $xmlPathTemp -Encoding UTF8
    New-ScheduledTask -SourceFolder $PSScriptRoot  -RecreateTask $true -XmlFile $xmlPathTemp
    Get-ProcessedScheduledCommands
}

