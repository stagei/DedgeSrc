#!/usr/bin/env pwsh
<#
.SYNOPSIS
    First-time server setup for AiDoc.WebNew.

.DESCRIPTION
    Run once on the server after IIS-DeployApp.ps1 has installed the app.
    Performs the following:
      1. Creates a Python virtual environment inside the deployed python\ folder.
      2. Installs Python dependencies from requirements.txt.
      3. Ensures the AiDoc.Library data folder exists under OptPath.

    The script locates all paths relative to its own location ($PSScriptRoot),
    which is the app's deployed root directory (e.g. %OptPath%\DedgeWinApps\AiDocNew-Web).

    Prerequisites:
      - Python 3.12 or 3.13 must be installed on the server (via py launcher or system Python).
      - $env:OptPath must be set.

.EXAMPLE
    pwsh.exe -NoProfile -File "C:\opt\DedgeWinApps\AiDocNew-Web\_install.ps1"
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$appRoot    = $PSScriptRoot
$pythonDir  = Join-Path $appRoot "python"
$venvDir    = Join-Path $pythonDir ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"
$reqFile    = Join-Path $pythonDir "requirements.txt"
$optPath    = $env:OptPath
if (-not $optPath) {
    Write-LogMessage "OptPath environment variable is not set." -Level ERROR
    exit 1
}

$libraryDir = Join-Path $optPath "data\AiDoc.Library"

Write-LogMessage "AiDoc.WebNew _install.ps1 — first-time setup" -Level INFO
Write-LogMessage "App root   : $($appRoot)" -Level INFO
Write-LogMessage "Python dir : $($pythonDir)" -Level INFO
Write-LogMessage "Library dir: $($libraryDir)" -Level INFO

# ── 1. Ensure library data folder exists ────────────────────────────────────

if (-not (Test-Path $libraryDir)) {
    New-Item -Path $libraryDir -ItemType Directory -Force | Out-Null
    Write-LogMessage "Created library dir: $($libraryDir)" -Level INFO
} else {
    Write-LogMessage "Library dir already exists." -Level INFO
}

# ── 2. Locate system Python ──────────────────────────────────────────────────

function Find-SystemPython {
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
        "C:\Program Files\Python314\python.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            Write-LogMessage "Found system Python at: $($candidate)" -Level INFO
            return $candidate
        }
    }
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p -and $p.Source -notmatch "WindowsApps") {
        Write-LogMessage "Found system Python: $($p.Source)" -Level INFO
        return $p.Source
    }
    return $null
}

# ── 3. Create or verify venv ─────────────────────────────────────────────────

function Test-VenvHealthy {
    param([string]$VenvPython)
    if (-not (Test-Path -LiteralPath $VenvPython)) { return $false }
    try {
        $out = & $VenvPython --version 2>&1
        if ($LASTEXITCODE -ne 0 -or $out -notmatch "Python \d") { return $false }
        $check = & $VenvPython -c "import chromadb; print('OK')" 2>&1
        return ($LASTEXITCODE -eq 0 -and $check -match "OK")
    } catch { return $false }
}

if (Test-VenvHealthy -VenvPython $venvPython) {
    Write-LogMessage "Existing venv is healthy — skipping venv creation." -Level INFO
} else {
    $systemPython = Find-SystemPython
    if (-not $systemPython) {
        Write-LogMessage "No system Python 3.12-3.14 found. Install Python and re-run." -Level ERROR
        exit 1
    }

    if (Test-Path -LiteralPath $venvDir) {
        Write-LogMessage "Removing existing broken venv..." -Level INFO
        Remove-Item -LiteralPath $venvDir -Recurse -Force
    }

    Write-LogMessage "Creating venv with $($systemPython)..." -Level INFO
    & $systemPython -m venv $venvDir
    if ($LASTEXITCODE -ne 0) {
        Write-LogMessage "venv creation failed (exit $($LASTEXITCODE))." -Level ERROR
        exit 1
    }

    $venvPip = Join-Path $venvDir "Scripts\pip.exe"

    # Bundled wheels are always present alongside requirements.txt
    $wheelsDir = Join-Path $pythonDir "wheels"
    if (-not (Test-Path -LiteralPath $wheelsDir)) {
        Write-LogMessage "Bundled wheels folder not found: $($wheelsDir)" -Level ERROR
        Write-LogMessage "The application package may be incomplete. Re-publish and re-deploy." -Level ERROR
        exit 1
    }

    Write-LogMessage "Installing from bundled wheels: $($wheelsDir)" -Level INFO
    & $venvPip install --no-index --find-links $wheelsDir -r $reqFile

    if ($LASTEXITCODE -ne 0) {
        Write-LogMessage "pip install failed (exit $($LASTEXITCODE))." -Level ERROR
        exit 1
    }

    Write-LogMessage "Venv created and packages installed successfully." -Level INFO
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-LogMessage "AiDoc.WebNew setup complete." -Level INFO
Write-LogMessage "  Python venv : $($venvPython)" -Level INFO
Write-LogMessage "  Library     : $($libraryDir)" -Level INFO
Write-LogMessage "Next step: run Install-RagHttpService.ps1 (in scripts\) for each RAG you want to host." -Level INFO
