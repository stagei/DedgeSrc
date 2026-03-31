<#
.SYNOPSIS
    Build and publish CursorDb2McpServer to the staging share.
.DESCRIPTION
    Publishes using the WebApp-FileSystem profile to the DedgeWinApps staging share.
    After publishing, run IIS-DeployApp.ps1 -SiteName CursorDb2McpServer to deploy.
.EXAMPLE
    pwsh.exe -NoProfile -File Build-And-Publish.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectPath = Join-Path $PSScriptRoot 'CursorDb2McpServer\CursorDb2McpServer.csproj'

if (-not (Test-Path -LiteralPath $projectPath)) {
    Write-Error "Project not found: $projectPath"
    exit 1
}

Write-Host "Publishing CursorDb2McpServer..."
dotnet publish $projectPath -c Release -p:PublishProfile=WebApp-FileSystem -v minimal

if ($LASTEXITCODE -ne 0) {
    Write-Error "Publish failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Published to staging share."
Write-Host "Deploy to IIS with:"
Write-Host '  pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName CursorDb2McpServer'
