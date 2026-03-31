# Ensure the SQLite connection profile exists in connections.json
# Uses same path and DPAPI encryption as the app (Documents\DbExplorer\connections.json)

param(
    [string]$ProfileName = "SQLite_Local",
    [string]$DatabasePath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $DatabasePath) {
    $DatabasePath = Join-Path $projectRoot "SampleData\sample.db"
}

$userDataFolder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'DbExplorer'
$connectionsPath = Join-Path $userDataFolder 'connections.json'

if (-not (Test-Path $userDataFolder)) {
    New-Item -ItemType Directory -Path $userDataFolder -Force | Out-Null
}

# Load existing connections or create new container
$container = @{ connections = @() }
if (Test-Path $connectionsPath) {
    try {
        $json = Get-Content $connectionsPath -Raw -Encoding utf8
        $container = $json | ConvertFrom-Json
        if (-not $container.connections) { $container | Add-Member -NotePropertyName connections -NotePropertyValue @() -Force }
    } catch {
        $container = @{ connections = @() }
    }
}
if (-not $container.PSObject.Properties['connections']) {
    $container | Add-Member -NotePropertyName connections -NotePropertyValue @() -Force
}

# Remove existing profile with same name
$connList = @($container.connections) | Where-Object { $_.name -ne $ProfileName }

# Encrypt empty password with DPAPI (SQLite file-based; no password)
Add-Type -AssemblyName System.Security
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes("")
$encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
$encryptedBase64 = [Convert]::ToBase64String($encryptedBytes)

$newConnection = @{
    name              = $ProfileName
    provider          = "SQLITE"
    version           = "3"
    server            = ""
    port              = 0
    database          = $DatabasePath
    username          = "sqlite"
    password          = ""
    encryptedPassword = $encryptedBase64
    lastUsed          = (Get-Date -Format "o")
}

$connList = $connList + @($newConnection)
$container.connections = $connList
$container | ConvertTo-Json -Depth 5 | Set-Content -Path $connectionsPath -Encoding utf8

return $connectionsPath
