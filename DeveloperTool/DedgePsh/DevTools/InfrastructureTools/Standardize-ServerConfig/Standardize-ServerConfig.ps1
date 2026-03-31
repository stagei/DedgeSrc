
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module ScheduledTask-Handler -Force
Import-Module Deploy-Handler -Force
Import-Module SoftwareUtils -Force


if (-not (Test-IsAdmin)) {
    Write-LogMessage "This script must be run as administrator. Please run as administrator and run the script again." -Level ERROR
    exit 1
}

if (-not (Test-IsServer)) {
    Write-LogMessage "This script is only supported on servers" -Level ERROR
    exit 1
}

# VALIDATION: Database servers must be logged in with the OLD service username OR admin accounts
# This allows migration FROM admin accounts (FKPRDADM/FKTSTADM/FKDEVADM) TO the old service account
$oldServiceUsername = Get-OldServiceUsernameFromServerName
$validDbServerUsers = @("FKPRDADM", "FKTSTADM", "FKDEVADM") + $oldServiceUsername
if ($env:COMPUTERNAME.ToLower().Contains("-db") -and $env:USERNAME -notin $validDbServerUsers) {
    Write-LogMessage "Database servers must be logged in with the old service username or admin accounts.`nCurrent user: $($env:USERNAME)`nValid users: $($validDbServerUsers -join ', ')" -Level ERROR
    exit 1
}

# VALIDATION: Application servers must be logged in with ADMIN accounts (NOT old service username)
# This allows migration FROM old service account TO admin accounts
# FIX: Changed -notcontains to -notmatch (correct operator for string matching)
# FIX: Removed extra closing parenthesis from $(Get-OldServiceUsernameFromServerName))
# FIX: Corrected error message to indicate admin login required
if ($env:COMPUTERNAME.ToLower() -notmatch "-db" -and $env:USERNAME -eq $(Get-OldServiceUsernameFromServerName)) {
    Write-LogMessage "Application servers must be logged in with admin accounts (FKPRDADM/FKTSTADM/FKDEVADM).`nCurrent user: $($env:USERNAME)`nLog off and log in as one of the admin accounts." -Level ERROR
    exit 1
}


# Get existing password
$existingPasswordPlainText = Get-SecureStringUserPasswordAsPlainText 
if ($null -eq $existingPasswordPlainText) {
    Set-UserPasswordAsSecureString -Force 
}

try {
    # Initialize server
    Initialize-Server -AdditionalAdmins @("$env:USERDOMAIN\$env:USERNAME") -SkipWinInstall $true
}
catch {
    Write-LogMessage "Error initializing server" -Level ERROR -Exception $_
}

Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module ScheduledTask-Handler -Force
Import-Module Deploy-Handler -Force
Import-Module SoftwareUtils -Force

try {
    Remove-ScheduledTask -TaskName "Agent-HandlerAutoDeploy" -TaskFolder "DevTools"
    Remove-Item -Path "$env:OptPath\DedgePshApps\Agent-HandlerAutoDeploy" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:OptPath\DedgeWinApps\Agent-HandlerAutoDeploy" -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-LogMessage "Error removing scheduled task" -Level ERROR -Exception $_
}

try {
    if (Test-IsDb2Server) {
        Install-OurPshApp -AppName "Db2-DiagInstanceFolderShare"
        Start-OurPshApp -AppName "Db2-DiagInstanceFolderShare"
    }
}
catch {
    Write-LogMessage "Error installing or starting PshApps" -Level ERROR -Exception $_
}
try {
    Install-OurPshApp -AppName "Cursor-ServerOrchestrator"
}
catch {
    Write-LogMessage "Error installing or starting PshApps" -Level ERROR -Exception $_
}
try {
    Install-OurPshApp -AppName "Server-AlertOnShutdown"
}
catch {
    Write-LogMessage "Error installing or starting PshApps" -Level ERROR -Exception $_
}
try {
    Install-OurPshApp -AppName "Db2-FederationHandler"
}
catch {
    Write-LogMessage "Error installing or starting Db2-FederationHandler PshApps" -Level ERROR -Exception $_
}
try {
    Install-OurPshApp -AppName "Refresh-ServerSettings"
}
catch {
    Write-LogMessage "Error installing or starting PshApps" -Level ERROR -Exception $_
}
try {
    Install-OurPshApp -AppName "LogFile-Remover"
}
catch {
    Write-LogMessage "Error installing or starting PshApps" -Level ERROR -Exception $_
}
try {
    Start-ScheduledTask -TaskName "Cursor-ServerOrchestrator" -TaskFolder "DevTools"
}
catch {
    Write-LogMessage "Error starting scheduled task" -Level ERROR -Exception $_
}
try {
    Install-OurPshApp -AppName "Db2-StartAfterReboot"
}
catch {
    Write-LogMessage "Error installing or starting Db2-StartAfterReboot PshApps" -Level ERROR -Exception $_
}

# Get existing password
$existingPasswordPlainText = Get-SecureStringUserPasswordAsPlainText 

# Convert plain text password to SecureString (required by Update-ScheduledTaskCredentials)
$existingPassword = if ($existingPasswordPlainText) {
    ConvertTo-SecureString -String $existingPasswordPlainText -AsPlainText -Force
}

$ChangeFromUserName = @()
# When appserver the FKPRDADM, FKTSTADM, or FKDEVADM should be the current user
if ($env:COMPUTERNAME.ToLower().Contains("-db")) {
    $ChangeFromUserName += @("FKPRDADM", "FKDEVADM", "FKTSTADM")
}
else {
    $ChangeFromUserName += @($($env:USERDOMAIN + "\" + $(Get-OldServiceUsernameFromServerName)))    
}

if ($null -ne $existingPassword) {
    try {            
        # Update-ServiceCredentials -Password $existingPassword -Username $env:USERNAME -ChangeFromUserName $ChangeFromUserName
        Update-ScheduledTaskCredentials -Password $existingPassword -Username ($env:USERDOMAIN + "\" + $env:USERNAME) -ChangeFromUserName $ChangeFromUserName
    }
    catch {
        Write-LogMessage "Error updating service credentials" -Level ERROR -Exception $_
    }
}
else {
    Write-LogMessage "No existing password found" -Level ERROR
}


Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module ScheduledTask-Handler -Force
Import-Module Deploy-Handler -Force
Import-Module SoftwareUtils -Force
try {
    # Add specific grants for database
    if (Test-IsDb2Server) {
        # Find all primary databases related to this server
        $currentDatabaseConfigurations = Get-DatabasesV2Json
    
        # Filter: current server with PrimaryDb access point
        $currentDatabaseConfigurations = $currentDatabaseConfigurations | Where-Object {
            $_.ServerName -ieq $env:COMPUTERNAME -and
            $_.AccessPoints.AccessPointType -contains "PrimaryDb"
        }
    
        foreach ($databaseConfiguration in $currentDatabaseConfigurations) {
            $workObjects = Get-DefaultWorkObjects -DatabaseName $databaseConfiguration.Database -DatabaseType "BothDatabases"
            foreach ($workObject in $workObjects) {
                Add-SpecificGrants -WorkObject $workObject
            }
        }
    }
}
catch {
    Write-LogMessage "Error adding specific grants" -Level ERROR -Exception $_
}

Send-Sms -Receiver "+4797188358" -Message "Server configuration standardized on $($env:COMPUTERNAME)"

# if servername starts with t-no1 then reboot the server
# if ($env:COMPUTERNAME.ToLower().StartsWith("t-no1")) {
#     Restart-Computer -Force
# }