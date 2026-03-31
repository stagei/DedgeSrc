<#
.SYNOPSIS
    Gets the "db2nt" secret from Azure Key Vault and saves the result and password to a file.

.DESCRIPTION
    Retrieves the db2nt secret from the configured Key Vault and writes the full result
    plus the password to C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Az\Azure-KeyVaultManager\<computername>.txt

.PARAMETER KeyVaultName
    Key Vault name. Default from keyvault-config.json.

.PARAMETER OutputFolder
    Output folder. Default: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Az\Azure-KeyVaultManager
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Az\Azure-KeyVaultManager"
)

$ErrorActionPreference = "Stop"

Import-Module AzureFunctions -Force 
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
}
catch {
    function Write-LogMessage { param($Message, [string]$Level = "INFO") Write-Host $Message }
}

$secretName = "db2nt"

# Resolve vault from config if not provided
$kvName = $KeyVaultName
$subId = $null
$configPath = Join-Path $env:OptPath "DedgePshApps\Azure-KeyVaultManager\keyvault-config.json"
if (-not $kvName -and (Test-Path $configPath)) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $kvName = $config.defaultVault
        $vaultEntry = $config.vaults | Where-Object { $_.name -eq $kvName } | Select-Object -First 1
        if ($vaultEntry) { $subId = $vaultEntry.subscriptionId }
    }
    catch { }
}
if (-not $kvName) {
    Write-Error "KeyVaultName is required. Set -KeyVaultName or configure keyvault-config.json."
}

Assert-AzureCliLogin
Assert-AzureKeyVaultAccess -KeyVaultName $kvName -SubscriptionId $subId

Write-LogMessage "Getting secret '$secretName' from Key Vault '$kvName'..." -Level INFO
$raw = Get-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $secretName -SubscriptionId $subId
$obj = $raw | ConvertFrom-Json
$password = if ($obj.value) { $obj.value } else { "" }

$lines = @(
    "Key: $secretName",
    "Retrieved: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "ComputerName: $env:COMPUTERNAME",
    "",
    "Password: $password",
    "",
    "--- Full result ---",
    $raw
)

$fileName = "$env:COMPUTERNAME.txt"
$outPath = Join-Path $OutputFolder $fileName

if (-not (Test-Path $OutputFolder -PathType Container)) {
    try {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Error "Output folder does not exist and could not be created: $OutputFolder"
    }
}

$lines | Out-File -FilePath $outPath -Encoding utf8 -Force
Write-LogMessage "Saved result and password to: $outPath" -Level INFO
