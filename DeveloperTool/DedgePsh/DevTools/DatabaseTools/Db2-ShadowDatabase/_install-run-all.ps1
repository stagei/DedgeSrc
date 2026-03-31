Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (-not ($env:COMPUTERNAME -eq "t-no1fkmvft-db")) {
    Write-LogMessage "Not a server — run this script on the target server directly" -Level WARN
    exit 0
}

New-ScheduledTask -SourceFolder $PSScriptRoot `
    -Executable "Run-FullShadowPipeline.ps1" `
    -TaskName "Db2-ShadowDatabase-RunAll" `
    -TaskFolder "DevTools" `
    -RunFrequency "Once" `
    -RunAtOnce $true `
    -RecreateTask $true `
    -RunAsUser $true
