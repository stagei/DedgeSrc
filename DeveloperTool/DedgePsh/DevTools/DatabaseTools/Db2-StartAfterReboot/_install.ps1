Import-Module GlobalFunctions -Force
if (Test-IsServer) {
    Import-Module ScheduledTask-Handler -Force
    $xmlPath = Join-Path $env:OptPath "DedgePshApps\Db2-StartAfterReboot\Db2-StartAfterReboot.xml"
    $xmlPathTemp = Join-Path $env:Temp "Db2-StartAfterReboot.xml"
    $xmlContent = Get-Content -Path $xmlPath -Encoding UTF8
    $userSID = (New-Object System.Security.Principal.NTAccount("$($env:USERDOMAIN)\$($env:USERNAME)")).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $xmlContent = $xmlContent.Replace("<UserId>¤</UserId>", "<UserId>$($userSID)</UserId>")
    $xmlContent = $xmlContent.Replace("<Author>DEDGE\¤</Author>", "<Author>DEDGE\$($env:USERNAME)</Author>")
    $xmlContent | Out-File -FilePath $xmlPathTemp -Encoding UTF8
    New-ScheduledTask -SourceFolder $PSScriptRoot  -RecreateTask $true -XmlFile $xmlPathTemp
    Get-ProcessedScheduledCommands
    Write-LogMessage "Db2-StartAfterReboot installed successfully" -Level INFO
}
else {
    Write-LogMessage "This is not a server. Skipping installation of Db2-StartAfterReboot" -Level WARN
}

