param (
    [string]$appName
)

if ($appName) {
    Import-Module SoftwareUtils -Force
    Install-OurPshApp $appName
    set-location $env:OptPath\DedgePshApps\$appName
} else {
    Import-Module SoftwareUtils -Force
    Update-AllOurPshApps
    Start-OurWinApp -AppName "Get-App"
}

