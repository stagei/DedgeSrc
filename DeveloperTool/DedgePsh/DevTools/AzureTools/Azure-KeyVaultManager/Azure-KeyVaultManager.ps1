<#
.SYNOPSIS
    Manages Azure Key Vault secrets: create, update, get, list, delete, undelete, import, and export.

.DESCRIPTION
    Uses Azure CLI to perform Key Vault operations. Supports subscription-aware vaults via keyvault-config.json.
    Set: create or update a secret.
    Get: retrieve a secret value.
    List: list secret names (not values).
    Delete: soft-delete a secret.
    Undelete: recover a soft-deleted secret.
    Import: bulk import from TSV file with columns contentType, key, secret.
    Export: export all secrets to TSV file in script folder (PasswordExport.tsv).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Set", "Get", "List", "Delete", "Undelete", "Import", "Export")]
    [string]$Action = "Set",

    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName = "p-we1int-apps-shared-kv",

    [Parameter(Mandatory = $false)]
    [string]$SecretName,

    [Parameter(Mandatory = $false)]
    [string]$SecretValue,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ImportPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# Import modules early (needed for ConvertTo-KeyVaultSecretName in validation)
Import-Module AzureFunctions -Force -ErrorAction Stop

# Load config for default vault and subscription
$configPath = Join-Path $scriptRoot "keyvault-config.json"
$defaultVault = $null
$defaultSubscription = $null
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $defaultVault = $config.defaultVault
        $vaultEntry = $config.vaults | Where-Object { $_.name -eq $defaultVault } | Select-Object -First 1
        if ($vaultEntry) {
            $defaultSubscription = $vaultEntry.subscriptionId
        }
    }
    catch {
        # Ignore config errors
    }
}

# Resolve parameters
$kvName = if ($KeyVaultName) { $KeyVaultName } elseif ($defaultVault) { $defaultVault } else { $null }
$subId = if ($SubscriptionId) { $SubscriptionId } elseif ($defaultSubscription) { $defaultSubscription } else { $null }

# Validate required params per action
$needsVault = $Action -in "Set", "Get", "List", "Delete", "Undelete", "Import", "Export"
$needsSecret = $Action -in "Set", "Get", "Delete", "Undelete"
$needsValue = $Action -eq "Set"

if ($needsVault -and [string]::IsNullOrWhiteSpace($kvName)) {
    Write-Error "KeyVaultName is required for action '$Action'. Set -KeyVaultName or configure keyvault-config.json."
}
if ($needsSecret -and [string]::IsNullOrWhiteSpace($SecretName)) {
    Write-Error "SecretName is required for action '$Action'."
}
# Normalize secret names for Get, Set, Delete, Undelete (same as Import)
if ($needsSecret -and $SecretName) {
    $SecretName = ConvertTo-KeyVaultSecretName -Name $SecretName
}
if ($needsValue -and [string]::IsNullOrWhiteSpace($SecretValue)) {
    Write-Error "SecretValue is required for action 'Set'."
}
if ($Action -eq "Import" -and [string]::IsNullOrWhiteSpace($ImportPath)) {
    Write-Error "ImportPath is required for action 'Import'. Specify -ImportPath with path to TSV file."
}

# Optional: Import GlobalFunctions (script may run standalone)
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
}
catch {
    function Write-LogMessage { param($Message, [string]$Level = "INFO") Write-Host $Message }
}

# Ensure Azure login and Key Vault access
Write-LogMessage "Azure Key Vault Manager - Action: $Action" -Level INFO
Assert-AzureCliLogin
if ($needsVault) {
    Assert-AzureKeyVaultAccess -KeyVaultName $kvName -SubscriptionId $subId
}

switch ($Action) {
    "Set" {
        $out = Set-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $SecretName -SecretValue $SecretValue -SubscriptionId $subId
        if ($out) { $out | ConvertFrom-Json | ConvertTo-Json -Depth 3 }
    }

    "Get" {
        $out = Get-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $SecretName -SubscriptionId $subId
        $out | ConvertFrom-Json | ConvertTo-Json
    }

    "List" {
        $list = Get-AzureKeyVaultSecretList -KeyVaultName $kvName -SubscriptionId $subId
        $list | ConvertTo-Json
    }

    "Delete" {
        Remove-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $SecretName -SubscriptionId $subId
    }

    "Undelete" {
        Restore-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $SecretName -SubscriptionId $subId
    }

    "Import" {
        Import-AzureKeyVaultSecretsFromTsv -KeyVaultName $kvName -ImportPath $ImportPath -SubscriptionId $subId -ScriptRoot $scriptRoot
    }

    "Export" {
        $exportPath = Join-Path $scriptRoot "PasswordExport.tsv"
        Export-AzureKeyVaultSecretsToTsv -KeyVaultName $kvName -OutputPath $exportPath -SubscriptionId $subId
    }
}
