# Ensure the local PostgreSQL 18 connection profile exists in connections.json
# Uses same path and DPAPI encryption as the app (Documents\DbExplorer\connections.json)

param(
    [string]$ProfileName = "PostgreSQL_Local",
    [string]$Server = "localhost",
    [int]$Port = 5432,
    [string]$Database = "postgres",
    [string]$Username = "postgres",
    [string]$Password = "postgres"
)

$ErrorActionPreference = "Stop"

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
    $container = @{ connections = @() }
}

# Remove existing profile with same name (so we always update host/port/password)
$connList = @($container.connections) | Where-Object { $_.name -ne $ProfileName }

# Encrypt password with DPAPI (same as app)
Add-Type -AssemblyName System.Security
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
$encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
$encryptedBase64 = [Convert]::ToBase64String($encryptedBytes)

$newConnection = @{
    name              = $ProfileName
    provider          = "POSTGRESQL"
    version           = "18"
    server            = $Server
    port              = $Port
    database          = $Database
    username          = $Username
    password          = ""
    encryptedPassword = $encryptedBase64
    lastUsed          = (Get-Date -Format "o")
}

$connList = $connList + @($newConnection)
$container.connections = $connList
$container | ConvertTo-Json -Depth 5 | Set-Content -Path $connectionsPath -Encoding utf8

return $connectionsPath
