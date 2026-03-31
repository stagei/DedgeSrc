<#
.SYNOPSIS
    Manages Service Principal Names (SPNs) for DB2 servers in Active Directory.
    Generates a script to add/remove SPNs for DB2 servers based on computer info from JSON configuration.
    The script is saved to a file that can be executed by domain administrators.

    - Will generate a script to add/remove SPNs for DB2 servers based on computer info from JSON configuration.

        setspn -D db2/p-no1docprd-db.DEDGE.fk.no "p1_srv_docprd_db"
        setspn -A db2/p-no1docprd-db.DEDGE.fk.no "p1_srv_docprd_db"
        setspn -D db2/p-no1docprd-db "p1_srv_docprd_db"
        setspn -A db2/p-no1docprd-db "p1_srv_docprd_db"

    - How to find all db2 spns:
        setspn -Q db2/*

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

Import-Module -Name GlobalFunctions -Force
Import-Module -Name Infrastructure -Force

# setspn -a db2/p-no1docprd-db.DEDGE.fk.no "p1_srv_docprd_db"
# setspn -a db2/p-no1docprd-db "p1_srv_docprd_db"
# setspn -Q db2/*

try {
    Write-LogMessage  $(Get-InitScriptName) -Level JOB_STARTED

    $jsonResult = [PSCustomObject[]](Get-ComputerInfoJson | Where-Object { $_.Type -eq "Server" -and $_.Platform -eq "Azure" -and $_.IsActive -eq $true -and $_.Name.EndsWith("-db") } | Select-Object Name, ServiceUserName)

    $workingArray = @()
    foreach ($item in $jsonResult) {
        $workingArray += [PSCustomObject]@{
            ServerName = $item.Name
            Usernames  = @($item.ServiceUserName, $(if ($item.Name.ToUpper().Contains("PRD")) { "FKPRDADM" } elseif ($item.Name.ToUpper().Contains("RAP")) { "FKPRDADM" }  elseif ($item.Name.ToUpper().Contains("DEV")) { "FKDEVADM" } else { "FKTSTADM" }))
        }
    }
    $workingArray = $workingArray | Sort-Object -Property ServerName

    # Generate script to be sent to the domain administrator
    $script = @()
    foreach ($arrElement in $workingArray) {
        foreach ($username in $arrElement.Usernames) {
            if (Test-ADUser -Username $username -Quiet) {
                $script += "setspn -D db2/$($arrElement.ServerName).DEDGE.fk.no $username >nul 2>&1"
                $script += "setspn -A db2/$($arrElement.ServerName).DEDGE.fk.no $username"
                $script += "setspn -D db2/$($arrElement.ServerName) $username >nul 2>&1"
                $script += "setspn -A db2/$($arrElement.ServerName) $username"
                break
                # It is NOT allowed to have the same SPN assigned to multiple usernames. This is a fundamental security principle in Active Directory.
            }
            else {
                Write-LogMessage "User $username not found in Active Directory" -Level WARN
            }
        }
    }
    $dataFolderPath = Get-ApplicationDataPath
    Write-LogMessage "Data folder path: $dataFolderPath" -Level INFO
    $fileName = Join-Path -Path $dataFolderPath -ChildPath "Spn-Handler-$((Get-Date).ToString("yyyyMMddHHmmss")).txt"
    $script | Set-Content -Path $fileName
    Write-LogMessage "Script saved to file: $fileName" -Level INFO
    explorer.exe $dataFolderPath
    Write-LogMessage  $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error" -Level ERROR -Exception $_
    Write-LogMessage  $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}

