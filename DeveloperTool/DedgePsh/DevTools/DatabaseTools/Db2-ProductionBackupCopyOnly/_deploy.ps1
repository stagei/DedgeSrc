Import-Module GlobalFunctions -Force
Import-Module Deploy-Handler -Force -ErrorAction Stop

# Get all reachable non-production DB servers (exclude p-no1*, keep *-db only)
Write-LogMessage "Fetching server list..." -Level INFO
$allServers  = Get-ValidServerNameList
$dbServers   = @($allServers | Where-Object { $_ -notlike "p-no1*" -and $_ -like "*-db" } | Sort-Object)

if ($dbServers.Count -eq 0) {
    Write-LogMessage "No non-production DB servers found" -Level ERROR
    exit 1
}

# ── Server menu (A-Z) ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Select target server ===" -ForegroundColor Cyan

$menu = @{}
for ($i = 0; $i -lt $dbServers.Count; $i++) {
    $letter        = [char](65 + $i)   # A, B, C, ...
    $menu[$letter.ToString()] = $dbServers[$i]
    Write-Host "  $($letter)) $($dbServers[$i])"
}

Write-Host ""
do {
    $serverChoice = (Read-Host "Enter letter").ToUpper().Trim()
} while (-not $menu.ContainsKey($serverChoice))

$chosenServer = $menu[$serverChoice]
Write-LogMessage "Selected server: $($chosenServer)" -Level INFO

# ── Date prompt ──────────────────────────────────────────────────────────────
Write-Host ""
$parsedDate = $null
do {
    $dateInput = (Read-Host "Enter run date (yyyy-MM-dd)").Trim()
    try {
        $parsedDate = [datetime]::ParseExact($dateInput, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        $parsedDate = $null
        Write-Host "  Invalid format. Use yyyy-MM-dd (e.g. 2026-02-25)" -ForegroundColor Yellow
    }
} while ($null -eq $parsedDate)

# ── Time prompt ──────────────────────────────────────────────────────────────
Write-Host ""
$parsedTime = $null
do {
    $timeInput = (Read-Host "Enter run time, 24h (HH:mm)").Trim()
    try {
        $parsedTime = [datetime]::ParseExact($timeInput, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        $parsedTime = $null
        Write-Host "  Invalid format. Use HH:mm (e.g. 03:00)" -ForegroundColor Yellow
    }
} while ($null -eq $parsedTime)

# ── Write config JSON (deployed together with the other files) ───────────────
$config = [ordered]@{
    StartDate    = $parsedDate.ToString("yyyy-MM-dd")
    StartHour    = $parsedTime.Hour
    StartMinute  = $parsedTime.Minute
    TargetServer = $chosenServer
}

$configFile = Join-Path $PSScriptRoot "install-config.json"
$config | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8
Write-LogMessage "Config written: $($configFile)" -Level INFO

# ── Deploy all files (including the new JSON) to chosen server ───────────────
Write-Host ""
Write-LogMessage "Deploying to $($chosenServer)..." -Level INFO
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @($chosenServer)

# ── Instructions ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host " Deploy complete" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Target server : $($chosenServer)"
Write-Host " Scheduled for : $($config.StartDate) at $($timeInput)"
Write-Host ""
Write-Host " Next step:"
Write-Host "   1. Log into: $($chosenServer)"
Write-Host "   2. Run    : Inst-Psh Db2-ProductionBackupCopyOnly"
Write-Host ""
Write-LogMessage "Done. Task scheduled for $($chosenServer) on $($config.StartDate) at $($timeInput)" -Level INFO

# Cursor Chat automation hint:
# To run the remote install from Cursor via orchestrator/autocur, ask:
# "Run %OptPath%\DedgePshApps\Db2-ProductionBackupCopyOnly\_install.ps1 on $($chosenServer) using --autocur"
