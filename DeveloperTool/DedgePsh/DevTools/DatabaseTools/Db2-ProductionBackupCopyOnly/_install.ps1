Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (-not (Test-IsDb2Server)) {
    Write-LogMessage "Not a Db2 server, skipping Db2-ProductionBackupCopyOnly installation" -Level INFO
    exit 0
}

$configFile = Join-Path $PSScriptRoot "install-config.json"
if (-not (Test-Path $configFile)) {
    Write-LogMessage "install-config.json not found at $($configFile). Run _deploy.ps1 first." -Level ERROR
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json

# JSON stores yyyy-MM-dd; schtasks /SD requires dd/MM/yyyy on Norwegian-locale servers.
# InvariantCulture on ToString ensures / separator regardless of server locale (no dots).
$startDate = [datetime]::ParseExact(
    $config.StartDate, "yyyy-MM-dd",
    [System.Globalization.CultureInfo]::InvariantCulture
).ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

Write-LogMessage "Scheduling task for $($startDate) at $($config.StartHour.ToString('00')):$($config.StartMinute.ToString('00'))" -Level INFO

New-ScheduledTask `
    -SourceFolder  $PSScriptRoot `
    -TaskFolder    "DevTools" `
    -RecreateTask  $true `
    -RunFrequency  "Once" `
    -StartDate     $startDate `
    -StartHour     $config.StartHour `
    -StartMinute   $config.StartMinute `
    -RunAsUser     $true
