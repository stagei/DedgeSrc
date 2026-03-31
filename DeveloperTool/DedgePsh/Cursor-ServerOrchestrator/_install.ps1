Import-Module ScheduledTask-Handler -Force

New-ScheduledTask -SourceFolder $PSScriptRoot `
    -TaskName "Cursor-ServerOrchestrator" `
    -Executable "Invoke-CursorOrchestrator.ps1" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass" `
    -TaskFolder "DevTools" `
    -RecreateTask $true `
    -RunFrequency "EveryMinute" `
    -RunAsUser $true `
    -RunLevel "Highest" `
    -WindowStyle "Hidden" `
    -RunAtOnce $true

$scriptFolder = Join-Path $env:OptPath "DedgePshApps\Cursor-ServerOrchestrator"
& (Join-Path $scriptFolder "_helpers\Set-CommandFolderAcl.ps1")
try {
    Start-ScheduledTask -TaskName "DevTools\Cursor-ServerOrchestrator"
}
catch {
    Write-LogMessage "Error starting scheduled task" -Level ERROR -Exception $_
}
