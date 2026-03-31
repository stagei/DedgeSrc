<#
.SYNOPSIS
    Start or stop a local web server for Lillestrøm Osteopati site preview.

.DESCRIPTION
    Uses npx http-server to serve the site locally. Supports start, stop, and status actions.

.PARAMETER Action
    start  — Start the server and open the site in the default browser
    stop   — Stop the running server
    status — Check if the server is running

.EXAMPLE
    pwsh.exe -File server.ps1 start
    pwsh.exe -File server.ps1 stop
    pwsh.exe -File server.ps1 status
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status')]
    [string]$Action,

    [int]$Port = 8080
)

# If no action provided, prompt the user
if (-not $Action) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " Lillestrøm Osteopati — Local Server" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Start server" -ForegroundColor White
    Write-Host "  2) Stop server" -ForegroundColor White
    Write-Host "  3) Check status" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host -Prompt "Choose action (1/2/3)"
    switch ($choice) {
        '1' { $Action = 'start' }
        '2' { $Action = 'stop' }
        '3' { $Action = 'status' }
        default {
            Write-Host "[ERROR] Invalid choice. Use 1, 2, or 3." -ForegroundColor Red
            exit 1
        }
    }
}

$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $PSScriptRoot '.server.pid'
$siteUrl = "http://127.0.0.1:$($Port)"

# ============================================================
# Helper: Find running server process
# ============================================================
function Get-ServerProcess {
    if (Test-Path $pidFile) {
        $storedPid = Get-Content $pidFile -Raw
        $storedPid = $storedPid.Trim()
        if ($storedPid) {
            try {
                $proc = Get-Process -Id ([int]$storedPid) -ErrorAction SilentlyContinue
                if ($proc -and $proc.ProcessName -match 'node') {
                    return $proc
                }
            }
            catch { <# Process no longer exists #> }
        }
    }

    # Fallback: find any http-server on our port
    $proc = Get-Process -Name 'node' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
                $cmd -and $cmd -match 'http-server' -and $cmd -match "$($Port)"
            }
            catch { $false }
        } |
        Select-Object -First 1

    return $proc
}

# ============================================================
# Actions
# ============================================================
switch ($Action) {

    'start' {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host " Lillestrøm Osteopati — Local Server" -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host ""

        # Check if already running
        $existing = Get-ServerProcess
        if ($existing) {
            Write-Host "[INFO] Server is already running (PID: $($existing.Id))" -ForegroundColor Yellow
            Write-Host "  URL: $($siteUrl)" -ForegroundColor Green
            Write-Host ""
            Write-Host "Opening in browser..." -ForegroundColor Gray
            Start-Process $siteUrl
            exit 0
        }

        # Check if port is in use by something else
        $portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($portInUse) {
            Write-Host "[ERROR] Port $($Port) is already in use by another process (PID: $($portInUse.OwningProcess))." -ForegroundColor Red
            Write-Host "  Stop that process first, or use a different port:" -ForegroundColor Yellow
            Write-Host "  pwsh.exe -File server.ps1 start -Port 8888" -ForegroundColor Gray
            exit 1
        }

        # Start the server
        Write-Host "[INFO] Starting http-server on port $($Port)..." -ForegroundColor Yellow
        Write-Host "  Serving: $($PSScriptRoot)" -ForegroundColor Gray
        Write-Host ""

        $proc = Start-Process -FilePath 'npx.cmd' `
            -ArgumentList "http-server `"$($PSScriptRoot)`" -p $($Port) -c-1" `
            -WindowStyle Hidden `
            -PassThru

        # Save PID
        $proc.Id | Out-File -FilePath $pidFile -Force

        # Wait a moment for the server to start
        Start-Sleep -Seconds 3

        # Verify it started
        $running = Get-ServerProcess
        if ($running) {
            Write-Host "[OK] Server started successfully" -ForegroundColor Green
            Write-Host "  PID: $($running.Id)" -ForegroundColor Gray
            Write-Host "  URL: $($siteUrl)" -ForegroundColor Green
            Write-Host ""
            Write-Host "Opening in browser..." -ForegroundColor Gray
            Start-Process $siteUrl
            Write-Host ""
            Write-Host "Run 'pwsh.exe -File server.ps1 stop' to shut down." -ForegroundColor DarkGray
        }
        else {
            Write-Host "[WARN] Server process started but may not be ready yet." -ForegroundColor Yellow
            Write-Host "  Try opening $($siteUrl) manually in a few seconds." -ForegroundColor Gray
            Start-Process $siteUrl
        }
    }

    'stop' {
        Write-Host ""
        $proc = Get-ServerProcess
        if ($proc) {
            Write-Host "[INFO] Stopping server (PID: $($proc.Id))..." -ForegroundColor Yellow
            Stop-Process -Id $proc.Id -Force
            Write-Host "[OK] Server stopped." -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] No running server found." -ForegroundColor Gray
        }

        # Clean up PID file
        if (Test-Path $pidFile) {
            Remove-Item $pidFile -Force
        }
    }

    'status' {
        Write-Host ""
        $proc = Get-ServerProcess
        if ($proc) {
            Write-Host "[RUNNING] Server is active" -ForegroundColor Green
            Write-Host "  PID: $($proc.Id)" -ForegroundColor Gray
            Write-Host "  URL: $($siteUrl)" -ForegroundColor Gray
        }
        else {
            Write-Host "[STOPPED] No server running on port $($Port)." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
