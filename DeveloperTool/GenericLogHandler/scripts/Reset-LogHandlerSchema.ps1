#Requires -Version 5.1
<#
.SYNOPSIS
    Rebuilds the solution, starts the Web API, and calls POST /api/maintenance/recreate-schema.

.DESCRIPTION
    Performs the full dev reset flow:
    1. Optionally stops running Generic Log Handler / dotnet processes so the build can succeed.
    2. Builds GenericLogHandler.sln.
    3. Optionally starts the Web API in the background (serves API and web UI from wwwroot).
    4. Waits for the API to respond on /health.
    5. Calls POST /api/maintenance/recreate-schema (drops app tables and re-migrates to current model).

    Use this after pulling schema changes or when you want a clean database matching the latest EF model.

.PARAMETER RepoRoot
    Repository root containing GenericLogHandler.sln. Default: script's parent parent (e.g. scripts\..).

.PARAMETER ApiBaseUrl
    Base URL of the Web API. Default: http://localhost:8110

.PARAMETER SkipKill
    Do not stop existing Web API / dotnet processes before building. Use when nothing is running.

.PARAMETER SkipBuild
    Do not rebuild the solution. Use when binaries are already up to date.

.PARAMETER SkipStartApi
    Do not start the Web API. Assume it is already running (e.g. started in another window). Only wait and call recreate-schema.

.PARAMETER OpenBrowser
    After recreate-schema, open the default browser to the web UI (ApiBaseUrl).

.PARAMETER HealthTimeoutSeconds
    Max seconds to wait for /health before giving up. Default: 60

.EXAMPLE
    .\Reset-LogHandlerSchema.ps1
    Rebuild, start API, wait, call recreate-schema.

.EXAMPLE
    .\Reset-LogHandlerSchema.ps1 -SkipKill -SkipBuild -SkipStartApi
    Only call recreate-schema (API must already be running).

.EXAMPLE
    .\Reset-LogHandlerSchema.ps1 -OpenBrowser
    Same as default and open browser to the UI after.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),

    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "http://localhost:8110",

    [Parameter(Mandatory = $false)]
    [switch]$SkipKill,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [switch]$SkipStartApi,

    [Parameter(Mandatory = $false)]
    [switch]$OpenBrowser,

    [Parameter(Mandatory = $false)]
    [int]$HealthTimeoutSeconds = 60
)

# Import GlobalFunctions if available
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
} catch {
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

$ErrorActionPreference = "Stop"
$healthUrl = "$ApiBaseUrl/health"
$recreateUrl = "$ApiBaseUrl/api/maintenance/recreate-schema"
$slnPath = Join-Path $RepoRoot "GenericLogHandler.sln"
$webApiPath = Join-Path $RepoRoot "src\GenericLogHandler.WebApi"

function Stop-LogHandlerProcesses {
    Write-LogMessage "Stopping existing Generic Log Handler Web API (process on port 8110 or named process)..." -Level INFO
    $stopped = 0
    # Stop by display name when run as published exe
    Get-Process -Name "Generic Log Handler Web API" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $script:stopped++
    }
    # Stop process listening on API port (e.g. dotnet run)
    try {
        $conn = Get-NetTCPConnection -LocalPort 8110 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($conn -and $conn.OwningProcess) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            $script:stopped++
        }
    } catch {
        # Get-NetTCPConnection may not be available or port not in use
    }
    if ($stopped -gt 0) {
        Start-Sleep -Seconds 3
        Write-LogMessage "Stopped $stopped process(es)." -Level INFO
    } else {
        Write-LogMessage "No running Web API process found on port 8110." -Level INFO
    }
}

function Build-Solution {
    Write-LogMessage "Building $slnPath ..." -Level INFO
    Push-Location $RepoRoot
    try {
        $result = dotnet build $slnPath
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Build failed. Fix errors and run again." -Level ERROR
            throw "Build failed with exit code $LASTEXITCODE"
        }
        Write-LogMessage "Build succeeded." -Level INFO
    } finally {
        Pop-Location
    }
}

function Start-WebApiBackground {
    Write-LogMessage "Starting Web API in new window from $webApiPath ..." -Level INFO
    Start-Process -FilePath "dotnet" -ArgumentList "run", "--no-build" -WorkingDirectory $webApiPath -WindowStyle Normal
    Write-LogMessage "Web API process started. Waiting for API to respond..." -Level INFO
}

function Wait-ForApiHealth {
    $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                Write-LogMessage "API is ready ($healthUrl returned 200)." -Level INFO
                return $true
            }
        } catch {
            Start-Sleep -Seconds 2
            continue
        }
    }
    Write-LogMessage "API did not respond at $healthUrl within $HealthTimeoutSeconds seconds." -Level ERROR
    return $false
}

function Invoke-RecreateSchema {
    Write-LogMessage "Calling POST $recreateUrl ..." -Level INFO
    try {
        $response = Invoke-RestMethod -Uri $recreateUrl -Method POST
        if ($response.Success) {
            Write-LogMessage "Recreate-schema succeeded: $($response.Data.Message)." -Level INFO
            return $true
        } else {
            Write-LogMessage "Recreate-schema returned Success=false: $($response.Error)." -Level ERROR
            return $false
        }
    } catch {
        Write-LogMessage "Recreate-schema failed: $($_.Exception.Message)." -Level ERROR
        return $false
    }
}

# Main
try {
    if (-not (Test-Path -LiteralPath $slnPath)) {
        Write-LogMessage "Solution not found: $slnPath" -Level ERROR
        exit 1
    }

    if (-not $SkipKill) {
        Stop-LogHandlerProcesses
    }

    if (-not $SkipBuild) {
        Build-Solution
    }

    if (-not $SkipStartApi) {
        Start-WebApiBackground
    }

    if (-not (Wait-ForApiHealth)) {
        Write-LogMessage "Exiting. Start the Web API manually or run without -SkipStartApi." -Level ERROR
        exit 1
    }

    if (-not (Invoke-RecreateSchema)) {
        exit 1
    }

    if ($OpenBrowser) {
        Start-Process $ApiBaseUrl
        Write-LogMessage "Opened browser to $ApiBaseUrl" -Level INFO
    }

    Write-LogMessage "Done. API and web UI: $ApiBaseUrl" -Level INFO
} catch {
    Write-LogMessage "Script failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
