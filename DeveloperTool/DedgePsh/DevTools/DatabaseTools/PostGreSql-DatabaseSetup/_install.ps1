Import-Module GlobalFunctions -Force

$setupScript = Join-Path $env:OptPath "DedgePshApps\PostGreSql-DatabaseSetup\PostGreSql-DatabaseSetup.ps1"

Write-LogMessage "Running PostgreSQL Database Setup..." -Level INFO
& $setupScript
