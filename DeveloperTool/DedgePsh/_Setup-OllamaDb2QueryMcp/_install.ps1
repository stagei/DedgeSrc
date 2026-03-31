Import-Module GlobalFunctions -Force
Import-Module ScheduledTask-Handler -Force

Write-LogMessage "Installing scheduled task for Setup-OllamaDb2QueryMcp bridge startup" -Level INFO

New-ScheduledTask -SourceFolder $PSScriptRoot `
    -TaskName "Setup-OllamaDb2QueryMcp-Bridge" `
    -Executable "Start-OllamaDb2QueryMcpBridge.ps1" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass" `
    -TaskFolder "DevTools" `
    -RecreateTask $true `
    -RunFrequency "EveryMinute" `
    -RunAsUser $true `
    -RunLevel "Highest" `
    -WindowStyle "Hidden" `
    -RunAtOnce $true

try {
    Start-ScheduledTask -TaskName "DevTools\Setup-OllamaDb2QueryMcp-Bridge"
    Write-LogMessage "Scheduled task started: DevTools\Setup-OllamaDb2QueryMcp-Bridge" -Level INFO
}
catch {
    Write-LogMessage "Error starting scheduled task" -Level ERROR -Exception $_
}
