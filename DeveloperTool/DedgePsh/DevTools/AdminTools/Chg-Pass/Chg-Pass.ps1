param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "",
    [Parameter(Mandatory = $false)]
    [string]$InputPw = $null
)

Import-Module Infrastructure -Force

$result = Set-UserPasswordAsSecureString -Username $Username -Force -InputPw $InputPw -ForceUpdateServiceCredentials $true

if ($result) {
    Write-LogMessage "Password changed successfully for $($Username): $result" -Level INFO
}
else {
    Write-LogMessage "Failed to change password for $($Username): $result" -Level ERROR
}

 $plainPassword = Get-SecureStringUserPasswordAsPlainText -Username $Username
 Write-Host "Plain password: $plainPassword" -ForegroundColor Green