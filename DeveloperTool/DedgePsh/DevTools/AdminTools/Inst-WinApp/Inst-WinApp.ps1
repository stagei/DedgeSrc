param (
    [string]$appName
)

if ($appName) {
    Import-Module SoftwareUtils -Force
    Set-Location $env:OptPath\DedgeWinApps\$appName
    Install-OurWinApp -AppName $appName
} else {
    Import-Module SoftwareUtils -Force
    Update-AllOurWinApps
    Start-OurWinApp -AppName "Get-App"
}

