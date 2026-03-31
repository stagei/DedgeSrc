Import-Module -Name GlobalFunctions -Force
Import-Module -Name SoftwareUtils -Force
Import-Module -Name Db2-Handler -Force

if (-not (Test-IsServer)) {
    Write-LogMessage "This script must be run on a server" -Level ERROR
    Exit 1
}

# Install the application
$appName = "Db2 Server 12.1 Standard Edition Activation"
Install-WindowsApps -AppName $appName

$fromLicensePath = "C:\TEMPFK\TempInstallFiles\Db2_Server_12.1_Standard_Edition_Activation\std_vpc\db2\license\db2std_vpc.lic"

$Db2InstallPath = "C:\DbInst"
$licensePath = Join-Path $Db2InstallPath "license"
$toLicensePath = Join-Path $licensePath "db2std_vpc.lic"

Copy-Item -Path $fromLicensePath -Destination $toLicensePath -Force

Set-Location -Path $( "$Db2InstallPath\bin" )
$db2Commands = @()
$db2Commands += "db2licm -a $toLicensePath"
$db2Commands += "db2licm -l"

$output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors
Write-LogMessage "Output:`n $($output -join "`n")" -Level TRACE

