Import-Module GlobalFunctions -Force

# From now on, Db2-ShadowDatabase remote execution uses Cursor-ServerOrchestrator.
$cursorInstallScript = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "CodingTools\Cursor-ServerOrchestrator\_install.ps1"
if (-not (Test-Path $cursorInstallScript -PathType Leaf)) {
    throw "Cursor-ServerOrchestrator install script not found: $($cursorInstallScript)"
}

Write-LogMessage "Installing Cursor-ServerOrchestrator scheduled task from $($cursorInstallScript)" -Level INFO
& pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $cursorInstallScript
if ($LASTEXITCODE -ne 0) {
    throw "Cursor-ServerOrchestrator install failed with exit code $($LASTEXITCODE)"
}

Write-LogMessage "Cursor-ServerOrchestrator install completed" -Level INFO
