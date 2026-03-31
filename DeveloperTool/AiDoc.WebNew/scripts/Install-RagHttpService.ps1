#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Install the AiDoc RAG HTTP server as a Windows Service, or run it interactively.

.DESCRIPTION
    Two modes in one script:

    SERVICE MODE (default, requires Administrator):
      Creates and configures the AiDoc RAG HTTP service via NSSM that:
      - Finds or creates a working Python venv in AiDoc.Python\.venv.
      - If the venv is broken (created on another machine) or missing, recreates
        it from system Python (py launcher or installed Python) and installs
        requirements.txt automatically.
      - Runs server_http.py as a Windows Service (delayed-auto, auto-restart).
      Uses the same credential pattern as ServerMonitorAgent.

    INTERACTIVE MODE (-Interactive):
      Runs server_http.py directly in the foreground. No admin required, no
      service install, no firewall changes. Good for dev/testing.

.PARAMETER ServiceName
    Windows Service name (default: AiDocRag). Ignored with -Interactive.

.PARAMETER Port
    TCP port for the HTTP API (default: 8484).

.PARAMETER Rag
    RAG name / library subfolder (default: db2-docs).

.PARAMETER BindAddress
    Bind address (default: 0.0.0.0). Only used with -Interactive.

.PARAMETER AiDocRoot
    Root of the AiDoc folder. Default: $env:OptPath.

.PARAMETER Interactive
    Run the server interactively in the foreground instead of installing as a service.

.EXAMPLE
    .\Install-RagHttpService.ps1
.EXAMPLE
    .\Install-RagHttpService.ps1 -Port 8485 -Rag visual-cobol-docs -ServiceName AiDocRagCobol
.EXAMPLE
    .\Install-RagHttpService.ps1 -Interactive -Rag db2-docs
.EXAMPLE
    .\Install-RagHttpService.ps1 -Interactive -Rag db2-docs -Port 8766 -BindAddress 127.0.0.1
#>

param(
    [string]$ServiceName = "AiDocRag",
    [int]$Port = 8484,
    [string]$Rag = "db2-docs",
    [string]$BindAddress = "0.0.0.0",
    [string]$AiDocRoot,
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
Import-Module -Name SoftwareUtils -Force -ErrorAction Stop

if (-not $env:OptPath) {
    throw "Environment variable OptPath is not set."
}
if (-not $AiDocRoot) {
    $AiDocRoot = $env:OptPath
}

function Find-SystemPython {
    <# Finds a working system Python. Prefers 3.13 (chromadb breaks on 3.14). #>
    if (Get-Command py -ErrorAction SilentlyContinue) {
        foreach ($ver in @("3.13", "3.12", "3.14")) {
            try {
                $exe = (& py "-$ver" -c "import sys; print(sys.executable)" 2>$null)
                if ($exe -and (Test-Path -LiteralPath $exe)) {
                    Write-LogMessage "Found system Python via py -$($ver): $($exe)" -Level INFO
                    return $exe
                }
            } catch { }
        }
    }
    foreach ($candidate in @(
        "C:\Program Files\Python313\python.exe",
        "C:\Program Files\Python312\python.exe",
        "C:\Program Files\Python314\python.exe",
        "C:\Python313\python.exe",
        "C:\Python312\python.exe",
        "C:\Python314\python.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            Write-LogMessage "Found system Python at: $($candidate)" -Level INFO
            return $candidate
        }
    }
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p -and $p.Source -notmatch "WindowsApps") {
        Write-LogMessage "Found system Python command: $($p.Source)" -Level INFO
        return $p.Source
    }
    return $null
}

function Test-VenvHealthy {
    <# Returns $true if venv python works AND has key packages installed. #>
    param([string]$VenvPython)
    if (-not (Test-Path -LiteralPath $VenvPython)) { return $false }
    try {
        $output = & $VenvPython --version 2>&1
        if ($LASTEXITCODE -ne 0 -or $output -notmatch "Python \d") { return $false }
        $check = & $VenvPython -c "import chromadb; import mcp; print('OK')" 2>&1
        if ($LASTEXITCODE -ne 0 -or $check -notmatch "OK") {
            Write-LogMessage "Venv python works but packages missing (chromadb/mcp import failed)" -Level WARN
            return $false
        }
        return $true
    } catch { }
    return $false
}

function New-PythonVenv {
    <# Creates a venv and installs requirements. Returns the venv python path. #>
    param([string]$SystemPython, [string]$VenvDir, [string]$RequirementsFile)

    if (Test-Path -LiteralPath $VenvDir) {
        Write-LogMessage "Removing broken/old venv at $($VenvDir)" -Level INFO
        Remove-Item -LiteralPath $VenvDir -Recurse -Force
    }

    Write-LogMessage "Creating venv with $($SystemPython)..." -Level INFO
    & $SystemPython -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw "venv creation failed (exit $($LASTEXITCODE))" }

    $venvPip = Join-Path $VenvDir "Scripts\pip.exe"
    $venvPython = Join-Path $VenvDir "Scripts\python.exe"

    if (Test-Path -LiteralPath $RequirementsFile) {
        Write-LogMessage "Installing requirements from $($RequirementsFile)..." -Level INFO
        Write-LogMessage "Using pip: $($venvPip)" -Level INFO
        $pyDir = Split-Path $RequirementsFile -Parent
        # Check both 'wheels' (AiDocNew bundled layout) and legacy 'offline_wheels'
        $wheelsDir = Join-Path $pyDir 'wheels'
        if (-not (Test-Path -LiteralPath $wheelsDir)) {
            $wheelsDir = Join-Path $pyDir 'offline_wheels'
        }
        if (Test-Path -LiteralPath $wheelsDir) {
            Write-LogMessage "Bundled wheels found at $($wheelsDir), using --no-index --find-links" -Level INFO
            $pipOut = & $venvPip install --no-index --find-links $wheelsDir -r $RequirementsFile 2>&1
        } else {
            Write-LogMessage "No bundled wheels found, trying online install" -Level INFO
            $pipOut = & $venvPip install -r $RequirementsFile 2>&1
        }
        $pipExit = $LASTEXITCODE
        foreach ($line in $pipOut) { Write-LogMessage "pip-install: $($line)" -Level INFO }
        Write-LogMessage "pip install exit code: $($pipExit)" -Level INFO
        if ($pipExit -ne 0) { throw "pip install -r requirements.txt failed (exit $($pipExit))" }
    }

    Write-LogMessage "Venv created successfully at $($VenvDir)" -Level INFO
    return $venvPython
}

try {
    # Resolve python root: prefer the embedded folder next to this script (AiDocNew self-contained layout),
    # then fall back to the legacy FkPythonApps location for backwards compatibility.
    $scriptDir   = Split-Path -Parent $PSCommandPath
    $appRoot     = Split-Path -Parent $scriptDir   # <appRoot>\scripts\ → <appRoot>
    $embeddedPy  = Join-Path $appRoot 'python'

    if (Test-Path -LiteralPath (Join-Path $embeddedPy 'server_http.py')) {
        $pythonRoot = $embeddedPy
    } elseif (Test-Path -LiteralPath (Join-Path $env:OptPath 'FkPythonApps\AiDoc.Python\server_http.py')) {
        $pythonRoot = Join-Path $env:OptPath 'FkPythonApps\AiDoc.Python'
    } elseif (Test-Path -LiteralPath (Join-Path $AiDocRoot 'AiDoc.Python\server_http.py')) {
        $pythonRoot = Join-Path $AiDocRoot 'AiDoc.Python'
    } else {
        $pythonRoot = $embeddedPy
    }

    $serverHttpPy    = Join-Path $pythonRoot 'server_http.py'
    $requirementsTxt = Join-Path $pythonRoot 'requirements.txt'
    $venvDir         = Join-Path $pythonRoot '.venv'
    $venvPython      = Join-Path $venvDir 'Scripts\python.exe'

    if (-not (Test-Path -LiteralPath $serverHttpPy)) {
        throw "server_http.py not found at: $($serverHttpPy). Expected embedded at $($embeddedPy) — re-publish the app."
    }

    # --- Python / venv resolution ---
    $pythonExe = $null

    if (Test-VenvHealthy -VenvPython $venvPython) {
        $pythonExe = $venvPython
        Write-LogMessage "Existing venv is healthy: $($pythonExe)" -Level INFO
    } else {
        if (Test-Path -LiteralPath $venvPython) {
            Write-LogMessage "Venv exists but is broken (created on another machine?). Will recreate." -Level WARN
        } else {
            Write-LogMessage "No venv found. Will create one." -Level INFO
        }

        $systemPython = Find-SystemPython
        if (-not $systemPython) {
            throw "No system Python (3.12-3.14) found. Install Python and retry."
        }

        $pythonExe = New-PythonVenv -SystemPython $systemPython -VenvDir $venvDir -RequirementsFile $requirementsTxt

        if (-not (Test-VenvHealthy -VenvPython $pythonExe)) {
            throw "Venv creation succeeded but python.exe is not healthy. Check logs."
        }
        Write-LogMessage "Venv ready: $($pythonExe)" -Level INFO
    }

    # ── Interactive mode: run in foreground and exit ──────────────────────
    if ($Interactive) {
        Write-LogMessage "Starting RAG HTTP server interactively: Rag=$($Rag), Host=$($BindAddress), Port=$($Port)" -Level INFO
        Write-LogMessage "Python: $($pythonExe)" -Level INFO
        Write-LogMessage "Press Ctrl+C to stop." -Level INFO

        Push-Location -LiteralPath $pythonRoot
        try {
            & $pythonExe $serverHttpPy --rag $Rag --host $BindAddress --port $Port
        } finally {
            Pop-Location
        }
        return
    }

    # ── Service mode: install as Windows Service ─────────────────────────
    Write-LogMessage "AiDoc RAG HTTP Service - Installation" -Level INFO

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "WARNING: Not running as Administrator. Service install may fail." -Level WARN
    }

    # --- Service cleanup ---
    Write-LogMessage "Cleaning up existing $($ServiceName) service..." -Level INFO
    $existingSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingSvc) {
        if ($existingSvc.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
        Get-Process -Name $ServiceName -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill(); $_.WaitForExit(3000) } catch { }
        }
        $nssmPath = Join-Path $env:OptPath "DedgeWinApps\nssm\nssm.exe"
        if (Test-Path $nssmPath) {
            $null = & $nssmPath remove $ServiceName confirm 2>&1
        } else {
            $null = & sc.exe delete $ServiceName 2>&1
        }
        Write-LogMessage "Removed existing service: $($ServiceName)" -Level INFO
        Start-Sleep -Seconds 2
    }

    # --- Free port ---
    Write-LogMessage "Freeing port $($Port)..." -Level INFO
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        foreach ($conn in $conns) {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($proc) {
                Write-LogMessage "Killing process holding port $($Port): $($proc.Name) PID $($proc.Id)" -Level INFO
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
        }
    }
    catch {
        Write-LogMessage "Could not check port $($Port): $($_.Exception.Message)" -Level WARN
    }

    # --- Logon rights ---
    Write-LogMessage "Granting logon rights..." -Level INFO
    Grant-BatchLogonRight
    Grant-ServiceLogonRight

    # --- Service account ---
    $serviceAccount = $null
    $servicePassword = $null
    if (Test-IsServer) {
        $serviceAccount = "$($env:USERDOMAIN)\$($env:USERNAME)"
        Write-LogMessage "Server detected - using domain account '$($serviceAccount)'" -Level INFO
        $servicePassword = Get-SecureStringUserPasswordAsPlainText
        if ([string]::IsNullOrEmpty($servicePassword)) {
            Write-LogMessage "Could not retrieve password - falling back to LocalSystem" -Level WARN
            $serviceAccount = $null
            $servicePassword = $null
        }
    }
    else {
        Write-LogMessage "Workstation detected - using LocalSystem" -Level INFO
    }

    # --- Create service via NSSM (python.exe isn't a native Windows service) ---
    $nssmExe = Join-Path $env:OptPath "DedgeWinApps\nssm\nssm.exe"
    if (-not (Test-Path $nssmExe)) { throw "NSSM not found at $($nssmExe). Deploy it first." }

    $displayName = "AiDoc RAG HTTP Service ($($Rag) :$($Port))"
    Write-LogMessage "Registering service '$($ServiceName)' via NSSM..." -Level INFO

    $nssmInstall = & $nssmExe install $ServiceName $pythonExe $serverHttpPy "--rag $Rag --host 0.0.0.0 --port $Port" 2>&1
    Write-LogMessage "nssm install: $($nssmInstall)" -Level INFO

    & $nssmExe set $ServiceName DisplayName $displayName 2>&1 | Out-Null
    & $nssmExe set $ServiceName Start SERVICE_DELAYED_AUTO_START 2>&1 | Out-Null
    $logsDir = Join-Path $env:OptPath "data\AiDoc.Library\logs"
    New-Item -Path $logsDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    & $nssmExe set $ServiceName AppStdout (Join-Path $logsDir "$($ServiceName)_stdout.log") 2>&1 | Out-Null
    & $nssmExe set $ServiceName AppStderr (Join-Path $logsDir "$($ServiceName)_stderr.log") 2>&1 | Out-Null

    if ($serviceAccount) {
        & $nssmExe set $ServiceName ObjectName $serviceAccount $servicePassword 2>&1 | Out-Null
        Write-LogMessage "Service account set to: $($serviceAccount)" -Level INFO
    }

    $null = & sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-LogMessage "Auto-restart on failure configured" -Level INFO
    }

    & sc.exe description $ServiceName "RAG HTTP API for AiDoc documentation search ($($Rag) on port $($Port))" 2>&1 | Out-Null

    # --- Firewall ---
    Write-LogMessage "Configuring firewall for port $($Port)..." -Level INFO
    $firewallRuleName = "AiDocRag_$Port"
    try {
        Get-NetFirewallRule -DisplayName "$($firewallRuleName)_Inbound" -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
        Get-NetFirewallRule -DisplayName "$($firewallRuleName)_Outbound" -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue

        New-NetFirewallRule -DisplayName "$($firewallRuleName)_Inbound" `
            -Direction Inbound -Protocol TCP -LocalPort $Port `
            -Action Allow -Profile Domain, Private `
            -Description "AiDoc RAG HTTP inbound on port $($Port)" `
            -ErrorAction Stop | Out-Null
        Write-LogMessage "Inbound firewall rule created for port $($Port)" -Level INFO

        New-NetFirewallRule -DisplayName "$($firewallRuleName)_Outbound" `
            -Direction Outbound -Protocol TCP -LocalPort $Port `
            -Action Allow -Profile Domain, Private `
            -Description "AiDoc RAG HTTP outbound on port $($Port)" `
            -ErrorAction Stop | Out-Null
        Write-LogMessage "Outbound firewall rule created for port $($Port)" -Level INFO
    }
    catch {
        Write-LogMessage "Could not configure firewall: $($_.Exception.Message). Open port $($Port) manually." -Level WARN
    }

    # --- Start service ---
    Write-LogMessage "Starting service '$($ServiceName)'..." -Level INFO
    Start-Service -Name $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 3
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service.Status -eq "Running") {
        Write-LogMessage "Service started successfully." -Level INFO
    }
    else {
        Write-LogMessage "Service status: $($service.Status)" -Level WARN
    }

    $hostname = $env:COMPUTERNAME
    $summary = @"

  AiDoc RAG HTTP Service - Installation Summary

  Service:  $ServiceName ($displayName)
  Status:   $($service.Status)
  Port:     $Port
  RAG:      $Rag
  Python:   $pythonExe
  API:      http://$($hostname):$($Port)/query
  Health:   http://$($hostname):$($Port)/health

"@
    Write-LogMessage $summary -Level INFO
}
catch {
    Write-LogMessage "Installation failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
