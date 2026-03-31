Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module Deploy-Handler -Force -ErrorAction Stop

$configFiles = Get-ChildItem -Path $PSScriptRoot -Filter "config.*.json" -File -ErrorAction SilentlyContinue
$computerNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($file in $configFiles) {
    $cfg = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($cfg.ServerFqdn) {
        $hostname = $cfg.ServerFqdn.Split('.')[0]
        if (-not [string]::IsNullOrWhiteSpace($hostname)) {
            [void]$computerNames.Add($hostname)
        }
    }
}

$computerList = [string[]]$computerNames
if ($computerList.Count -eq 0) {
    throw "No computer names found in config.*.json files. Ensure each config has ServerFqdn."
}



Write-LogMessage "Deploy targets from config files: $($computerList -join ', ')" -Level INFO

Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $computerList

$createInitialDbFolder = Join-Path (Split-Path $PSScriptRoot -Parent) "Db2-CreateInitialDatabases"
if (Test-Path $createInitialDbFolder) {
    Deploy-Files -FromFolder $createInitialDbFolder -ComputerNameList $computerList
}

$createInitialDbFolder = Join-Path (Split-Path $PSScriptRoot -Parent) "Db2-Backup"
if (Test-Path $createInitialDbFolder) {
    Deploy-Files -FromFolder $createInitialDbFolder -ComputerNameList $computerList
}

$createInitialDbFolder = Join-Path (Split-Path $PSScriptRoot -Parent) "Db2-Restore"
if (Test-Path $createInitialDbFolder) {
    Deploy-Files -FromFolder $createInitialDbFolder -ComputerNameList $computerList
}
$createInitialDbFolder = Join-Path (Split-Path $PSScriptRoot -Parent) "Db2-GrantsExport"
if (Test-Path $createInitialDbFolder) {
    Deploy-Files -FromFolder $createInitialDbFolder -ComputerNameList $computerList
}
$createInitialDbFolder = Join-Path (Split-Path $PSScriptRoot -Parent) "Db2-GrantsImport"
if (Test-Path $createInitialDbFolder) {
    Deploy-Files -FromFolder $createInitialDbFolder -ComputerNameList $computerList
}