<#
.SYNOPSIS
    Creates a ZIP file of the Lillestrøm Osteopati WordPress theme, ready for upload.

.DESCRIPTION
    Compresses the lillestrom-osteopati-v2 theme folder into a ZIP file that can be
    uploaded via WordPress admin (Appearance > Themes > Add New > Upload Theme).

.EXAMPLE
    pwsh.exe -File deploy.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$themeFolder = Join-Path $scriptRoot 'lillestrom-osteopati-v2'
$zipFile = Join-Path $scriptRoot 'lillestrom-osteopati-v2.zip'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Lillestrøm Osteopati — Theme Packager" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Verify theme folder exists
if (-not (Test-Path $themeFolder)) {
    Write-Host "[ERROR] Theme folder not found: $($themeFolder)" -ForegroundColor Red
    exit 1
}

# Remove existing ZIP if present
if (Test-Path $zipFile) {
    Write-Host "[INFO] Removing existing ZIP file..." -ForegroundColor Yellow
    Remove-Item $zipFile -Force
}

# Create ZIP
Write-Host "[INFO] Creating theme ZIP..." -ForegroundColor Yellow
Write-Host "  Source: $($themeFolder)" -ForegroundColor Gray
Write-Host "  Output: $($zipFile)" -ForegroundColor Gray
Write-Host ""

Compress-Archive -Path $themeFolder -DestinationPath $zipFile -CompressionLevel Optimal

if (Test-Path $zipFile) {
    $zipInfo = Get-Item $zipFile
    $sizeMB = '{0:N2}' -f ($zipInfo.Length / 1MB)
    Write-Host "[OK] Theme ZIP created successfully" -ForegroundColor Green
    Write-Host "  File: $($zipFile)" -ForegroundColor Gray
    Write-Host "  Size: $($sizeMB) MB" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Log in to WordPress at lillestrom-osteopati.no/wp-admin" -ForegroundColor White
    Write-Host "  2. Install Contact Form 7 plugin (Plugins > Add New)" -ForegroundColor White
    Write-Host "  3. Upload this ZIP (Appearance > Themes > Add New > Upload Theme)" -ForegroundColor White
    Write-Host "  4. Activate the theme" -ForegroundColor White
    Write-Host ""
}
else {
    Write-Host "[ERROR] Failed to create ZIP file." -ForegroundColor Red
    exit 1
}
