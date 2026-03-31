<#
.SYNOPSIS
    Installs (if needed) and starts the MCP Inspector developer tool.

.DESCRIPTION
    MCP Inspector is an interactive debugger for Model Context Protocol (MCP) servers.
    It provides a browser-based UI on http://localhost:<Port> where you can:
      - Connect to any MCP server (stdio or SSE transport)
      - List and call tools, read resources, sample prompts
      - Inspect request/response payloads in real time

    This script:
      1. Verifies Node.js >= 18 is installed.
      2. Installs @modelcontextprotocol/inspector globally if not present.
      3. Starts the inspector proxy (default port 3000) and opens a browser.

.PARAMETER Port
    Port for the MCP Inspector UI. Default: 3000.

.PARAMETER McpServerCommand
    Optional. Command to launch an MCP server directly from the inspector.
    Example: "node C:\opt\src\MyMcpServer\server.js"
    If omitted, the inspector starts without a pre-connected server.

.PARAMETER NoBrowser
    If set, suppresses automatic browser launch.

.PARAMETER SkipInstall
    If set, skips the npm install check (use when offline or already installed).

.EXAMPLE
    .\Start-McpInspector.ps1
    Start inspector UI on http://localhost:3000

.EXAMPLE
    .\Start-McpInspector.ps1 -Port 4000
    Start on a custom port.

.EXAMPLE
    .\Start-McpInspector.ps1 -McpServerCommand "node server.js"
    Start and connect to a local MCP server process.
#>
[CmdletBinding()]
param(
    [int]$Port = 3000,
    [string]$McpServerCommand = "",
    [switch]$NoBrowser,
    [switch]$SkipInstall
)

Import-Module GlobalFunctions -Force

$ErrorActionPreference = "Stop"

$banner = @"
========================================================
  MCP Inspector
  Model Context Protocol - Interactive Debugger
========================================================
"@
Write-Host $banner -ForegroundColor Cyan

# ─── 1. Verify Node.js ────────────────────────────────────────────────────────

Write-LogMessage "Checking Node.js..." -Level INFO
try {
    $nodeVersion = & node --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw "node not found" }
    $nodeMajor = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
    if ($nodeMajor -lt 18) {
        Write-LogMessage "Node.js $($nodeVersion) is too old. MCP Inspector requires Node >= 18." -Level ERROR
        exit 1
    }
    Write-LogMessage "Node.js $($nodeVersion) OK" -Level INFO
}
catch {
    Write-LogMessage "Node.js is not installed or not on PATH. Install from https://nodejs.org (LTS)" -Level ERROR
    exit 1
}

# ─── 2. Install MCP Inspector ─────────────────────────────────────────────────

$packageName = "@modelcontextprotocol/inspector"

if (-not $SkipInstall) {
    Write-LogMessage "Checking if $($packageName) is installed globally..." -Level INFO
    $installedVersion = & npm list -g $packageName --depth=0 2>&1 | Select-String "@modelcontextprotocol/inspector@"

    if (-not $installedVersion) {
        Write-LogMessage "$($packageName) not found. Installing latest..." -Level INFO
        & npm install -g $packageName
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "npm install failed. Try running as Administrator or check network access." -Level ERROR
            exit 1
        }
        Write-LogMessage "Installed $($packageName) successfully." -Level INFO
    }
    else {
        Write-LogMessage "Already installed: $($installedVersion.ToString().Trim())" -Level INFO
    }
}

# ─── 3. Build launch command ──────────────────────────────────────────────────

$uiUrl = "http://localhost:$($Port)"

Write-LogMessage "Starting MCP Inspector on $($uiUrl)" -Level INFO

if (-not $NoBrowser) {
    # Open browser after a short delay so the server has time to start
    Start-Job -ScriptBlock {
        param($url)
        Start-Sleep -Seconds 3
        Start-Process $url
    } -ArgumentList $uiUrl | Out-Null
    Write-LogMessage "Browser will open at $($uiUrl) in ~3 seconds..." -Level INFO
}

Write-Host ""
Write-Host "  Press Ctrl+C to stop the inspector." -ForegroundColor Yellow
Write-Host ""

# ─── 4. Start inspector ───────────────────────────────────────────────────────

if ($McpServerCommand) {
    Write-LogMessage "Launching with pre-connected server: $($McpServerCommand)" -Level INFO
    # Split command into executable + args for npx
    $cmdParts = $McpServerCommand -split " ", 2
    $serverExe  = $cmdParts[0]
    $serverArgs = if ($cmdParts.Count -gt 1) { $cmdParts[1] } else { "" }

    # MCP Inspector CLI: npx @modelcontextprotocol/inspector <command> [args]
    & npx $packageName $serverExe $serverArgs
}
else {
    # Start the inspector proxy only — connect to servers via the UI
    & npx $packageName
}
