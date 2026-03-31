param (
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "FKKTOTST",
    [Parameter(Mandatory = $false)]
    [ValidateSet("Kerberos","KerberosServerEncrypt", "*", "Ntlm")]
    [string]$AuthenticationType = "KerberosServerEncrypt",
    [Parameter(Mandatory = $false)]
    [string]$Version = "*"
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name Db2-Handler -Force
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Add-RemoteCatalogingForDatabase -DatabaseName $DatabaseName -AuthenticationType $AuthenticationType -Version $Version
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED

    exit 1
}

