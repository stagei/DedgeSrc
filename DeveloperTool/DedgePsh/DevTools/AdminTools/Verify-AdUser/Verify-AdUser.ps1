param(
    [Parameter(Mandatory = $true)]
    [string]$Username
)

Import-Module Infrastructure -Force
Import-Module GlobalFunctions -Force

# $adUser = 'p1_srv_docprd_db'
if ([string]::IsNullOrEmpty($Username)) {
    Write-LogMessage "Username is required" -Level ERROR
    exit 1
}
Write-LogMessage "Verifying user $Username in Active Directory" -Level INFO
$result = Test-ADUser -Username $Username -Quiet
if ($result) {
    Write-LogMessage "User $Username verified successfully in Active Directory" -Level INFO
}
else {
    Write-LogMessage "User $Username not found in Active Directory" -Level ERROR
    exit 1
}

