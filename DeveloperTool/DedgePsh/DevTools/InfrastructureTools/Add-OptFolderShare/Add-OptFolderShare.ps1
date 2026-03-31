Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module Deploy-Handler -Force
try {
    if (Test-IsServer) {
        $IsWorkstation = $false
    }
    else {
        $IsWorkstation = $true
    }

    $AdditionalAdmins = Get-AdditionalAdmins -AdditionalAdmins @()
    Add-Folder -Path $env:OptPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "Read" -IsWorkstation $IsWorkstation
    Add-SmbSharedFolder -Path $env:OptPath -ShareName "Opt" -Description "Shared folder for Opt"  -AdditionalAdmins $AdditionalAdmins
    Write-LogMessage "Opt folder share added" -Level INFO
}
catch {
    Write-LogMessage "Error adding Opt folder share" -Level ERROR -Exception $_
}

