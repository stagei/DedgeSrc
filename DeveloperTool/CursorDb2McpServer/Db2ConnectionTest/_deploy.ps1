$ErrorActionPreference = 'Stop'

# Publish to staging folder, then deploy
$projectPath = Join-Path $PSScriptRoot 'Db2ConnectionTest.csproj'
$publishDir = Join-Path $PSScriptRoot 'publish'
Write-Host "Publishing Db2ConnectionTest..."
dotnet publish $projectPath -c Release -o $publishDir --self-contained -r win-x64
if ($LASTEXITCODE -ne 0) { throw "Publish failed." }

# Copy Run script into publish dir
Copy-Item -Path (Join-Path $PSScriptRoot 'Run-TestDb2Connection.ps1') -Destination $publishDir -Force

$server = 'dedge-server'
$targetPath = "\\$server\opt\DedgePshApps\Db2ConnectionTest"
if (-not (Test-Path "\\$server\opt" -PathType Container)) {
    throw "Cannot reach \\$server\opt. Check network and permissions."
}
New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
Copy-Item -Path (Join-Path $publishDir '*') -Destination $targetPath -Recurse -Force
Write-Host "Deployed to $targetPath"
