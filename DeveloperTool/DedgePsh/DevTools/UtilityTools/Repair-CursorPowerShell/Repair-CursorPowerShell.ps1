<###
.SYNOPSIS
    Repairs Cursor IDE PowerShell language server issues (phantom linter errors, stale diagnostics).

.DESCRIPTION
    This script diagnoses and fixes common issues with the PowerShell extension in Cursor IDE,
    including phantom linter errors caused by the language server misattributing diagnostics.

    Available actions:
    - KillLanguageServer  : Kill PowerShell Editor Services processes to force a fresh restart
    - UpdateExtension     : Check for and install the latest PowerShell extension (VSIX)
    - UpdatePowerShell    : Check for and install the latest PowerShell 7 via winget
    - ClearDiagnosticsCache : Clear stale PSES logs, workspace storage, and PSScriptAnalyzer caches

    Run without parameters (or with -All) to execute all actions in sequence.
    After completion, close and restart Cursor for changes to take effect.

.PARAMETER Action
    The repair action to perform. If omitted, all actions run in sequence.

.PARAMETER All
    Run all repair actions in sequence (same as omitting -Action).

.EXAMPLE
    .\Repair-CursorPowerShell.ps1
    Runs all repair actions.

.EXAMPLE
    .\Repair-CursorPowerShell.ps1 -Action ClearDiagnosticsCache
    Clears only the diagnostics cache.

.EXAMPLE
    .\Repair-CursorPowerShell.ps1 -Action UpdateExtension
    Checks for and installs the latest PowerShell extension.

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Cursor IDE, PowerShell 7+
###>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('KillLanguageServer', 'UpdateExtension', 'UpdatePowerShell', 'ClearDiagnosticsCache')]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [switch]$All
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════
$extensionId = "ms-vscode.powershell"
$wingetPackageId = "Microsoft.PowerShell"

# ═══════════════════════════════════════════════════════════════════════════════
# Action: KillLanguageServer
# ═══════════════════════════════════════════════════════════════════════════════
function Stop-PowerShellLanguageServer {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "━━━ KillLanguageServer ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-LogMessage "Searching for PowerShell Editor Services processes..." -Level INFO

    $killedCount = 0

    try {
        # Find pwsh.exe processes whose command line contains PowerShellEditorServices or the extension path
        # Regex: match command lines referencing PSES module or the extension folder
        #   PowerShellEditorServices  - the PSES module name loaded by the extension
        #   ms-vscode\.powershell     - the extension folder name (escaped dot)
        $psesProcesses = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'PowerShellEditorServices|ms-vscode\.powershell' }

        if ($psesProcesses) {
            foreach ($proc in $psesProcesses) {
                Write-LogMessage "  Killing PSES process PID $($proc.ProcessId): $($proc.CommandLine.Substring(0, [Math]::Min(120, $proc.CommandLine.Length)))..." -Level INFO
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                $killedCount++
            }
        }

        # Also look for any orphaned EditorServices host processes
        $editorServicesProcs = Get-Process -Name "*EditorServices*" -ErrorAction SilentlyContinue
        if ($editorServicesProcs) {
            foreach ($proc in $editorServicesProcs) {
                Write-LogMessage "  Killing orphaned EditorServices process PID $($proc.Id): $($proc.ProcessName)" -Level INFO
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $killedCount++
            }
        }

        if ($killedCount -eq 0) {
            Write-LogMessage "  No PowerShell Editor Services processes found (language server may not be running)" -Level INFO
        }
        else {
            Write-LogMessage "  Killed $($killedCount) language server process(es)" -Level INFO
        }
    }
    catch {
        Write-LogMessage "Error killing language server processes: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Action: UpdateExtension
# ═══════════════════════════════════════════════════════════════════════════════
function Update-PowerShellExtension {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "━━━ UpdateExtension ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

    try {
        # ── 1. Get currently installed version ──────────────────────────────────
        $extensionsDir = Join-Path $env:USERPROFILE ".cursor\extensions"
        $installedVersion = $null

        if (Test-Path $extensionsDir) {
            $installedFolders = Get-ChildItem -Path $extensionsDir -Directory -Filter "$($extensionId)-*" -ErrorAction SilentlyContinue
            if ($installedFolders) {
                # Pick the highest version if multiple exist
                # Regex: extract the semantic version (digits.digits.digits) after the extension id prefix
                #   (\d+\.\d+\.\d+)  - captures major.minor.patch version number
                $versions = $installedFolders | ForEach-Object {
                    if ($_.Name -match "$([regex]::Escape($extensionId))-(\d+\.\d+\.\d+)") {
                        [version]$matches[1]
                    }
                } | Sort-Object -Descending
                if ($versions) {
                    $installedVersion = $versions[0]
                    Write-LogMessage "  Installed version: $($installedVersion)" -Level INFO
                }
            }
        }

        if (-not $installedVersion) {
            Write-LogMessage "  PowerShell extension not found in Cursor extensions folder" -Level WARN
        }

        # ── 2. Query the VS Marketplace for the latest version ──────────────────
        Write-LogMessage "  Querying VS Marketplace for latest version..." -Level INFO

        $headers = @{
            'Content-Type' = 'application/json'
            'Accept'       = 'application/json;api-version=7.1-preview.1'
            'User-Agent'   = 'Mozilla/5.0'
        }

        $body = @{
            filters = @(
                @{
                    criteria = @(
                        @{
                            filterType = 7
                            value      = $extensionId
                        }
                    )
                }
            )
            flags   = 2047
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" `
            -Method Post -Headers $headers -Body $body

        if (-not $response.results -or -not $response.results[0].extensions) {
            Write-LogMessage "  Could not query marketplace for $($extensionId)" -Level ERROR
            return
        }

        $marketplaceVersionStr = $response.results[0].extensions[0].versions[0].version
        $marketplaceVersion = [version]$marketplaceVersionStr
        Write-LogMessage "  Marketplace version: $($marketplaceVersion)" -Level INFO

        # ── 3. Compare and install if newer ─────────────────────────────────────
        if ($installedVersion -and $marketplaceVersion -le $installedVersion) {
            Write-LogMessage "  PowerShell extension is up to date ($($installedVersion))" -Level INFO
            return
        }

        Write-LogMessage "  Newer version available: $($marketplaceVersion) (installed: $($installedVersion ?? 'none'))" -Level INFO
        Write-LogMessage "  Downloading latest VSIX from marketplace..." -Level INFO

        $vsixPath = Get-VSCodeExtension -ExtensionId $extensionId
        if (-not $vsixPath -or -not (Test-Path $vsixPath -ErrorAction SilentlyContinue)) {
            Write-LogMessage "  Failed to download extension VSIX" -Level ERROR
            return
        }

        Write-LogMessage "  Installing extension into Cursor..." -Level INFO
        Install-CursorExtension -ExtensionId $extensionId
        Write-LogMessage "  PowerShell extension updated to $($marketplaceVersion)" -Level INFO
    }
    catch {
        Write-LogMessage "Error updating PowerShell extension: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Action: UpdatePowerShell
# ═══════════════════════════════════════════════════════════════════════════════
function Update-PowerShell7 {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "━━━ UpdatePowerShell ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

    try {
        # ── 1. Current version ──────────────────────────────────────────────────
        $currentVersion = $PSVersionTable.PSVersion
        Write-LogMessage "  Current PowerShell version: $($currentVersion)" -Level INFO

        # ── 2. Find winget ──────────────────────────────────────────────────────
        $wingetPath = Get-CommandPathWithFallback -Name "winget"
        if ([string]::IsNullOrEmpty($wingetPath) -or $wingetPath -eq "winget") {
            Write-LogMessage "  winget not found -- cannot check for PowerShell updates" -Level WARN
            return
        }

        # ── 3. Check available version via winget ───────────────────────────────
        Write-LogMessage "  Checking winget for available PowerShell version..." -Level INFO
        $showOutput = & $wingetPath show $wingetPackageId --accept-source-agreements 2>&1 | Out-String

        $availableVersion = $null
        # Regex: extract version from winget show output
        #   Version:\s+  - matches the "Version:" label followed by whitespace
        #   ([\d.]+)     - captures the version number (digits and dots)
        if ($showOutput -match 'Version:\s+([\d.]+)') {
            $availableVersion = [version]$matches[1]
            Write-LogMessage "  Available version from winget: $($availableVersion)" -Level INFO
        }
        else {
            Write-LogMessage "  Could not determine available version from winget" -Level WARN
            Write-LogMessage "  winget output: $($showOutput.Substring(0, [Math]::Min(300, $showOutput.Length)))" -Level DEBUG
            return
        }

        # ── 4. Compare and upgrade ──────────────────────────────────────────────
        if ($availableVersion -le $currentVersion) {
            Write-LogMessage "  PowerShell is up to date ($($currentVersion))" -Level INFO
            return
        }

        Write-LogMessage "  Newer PowerShell version available: $($availableVersion) (current: $($currentVersion))" -Level INFO
        Write-LogMessage "  Upgrading via winget..." -Level INFO

        $upgradeResult = & $wingetPath upgrade $wingetPackageId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        Write-LogMessage "  Winget upgrade output: $($upgradeResult.Trim())" -Level INFO

        if ($upgradeResult -match 'Successfully installed|No applicable update found') {
            Write-LogMessage "  PowerShell upgrade completed" -Level INFO
        }
        else {
            Write-LogMessage "  Winget upgrade may have encountered issues -- review output above" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Error updating PowerShell: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Action: ClearDiagnosticsCache
# ═══════════════════════════════════════════════════════════════════════════════
function Clear-DiagnosticsCache {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "━━━ ClearDiagnosticsCache ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

    $totalFiles = 0
    $totalBytes = 0

    # Helper to remove items and track stats
    function Remove-CacheItems {
        param(
            [string]$Path,
            [string]$Label
        )
        if (Test-Path $Path) {
            $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            $itemBytes = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            $itemCount = $items.Count

            try {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
                Write-LogMessage "  Cleared $($Label): $($itemCount) files, $([math]::Round(($itemBytes / 1KB), 1)) KB" -Level INFO
                $script:totalFiles += $itemCount
                $script:totalBytes += $itemBytes
            }
            catch {
                Write-LogMessage "  Failed to clear $($Label): $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-LogMessage "  $($Label): not found (skipped)" -Level DEBUG
        }
    }

    try {
        # ── 1. PowerShell Editor Services logs in TEMP ──────────────────────────
        Write-LogMessage "  Scanning for stale caches..." -Level INFO

        $pesLogPaths = Get-ChildItem -Path $env:TEMP -Filter "PowerShellEditorServices*" -Directory -ErrorAction SilentlyContinue
        if ($pesLogPaths) {
            foreach ($logDir in $pesLogPaths) {
                Remove-CacheItems -Path $logDir.FullName -Label "PSES log: $($logDir.Name)"
            }
        }
        else {
            Write-LogMessage "  PSES temp logs: none found (skipped)" -Level DEBUG
        }

        # ── 2. Cursor workspace storage (PSES-related) ─────────────────────────
        $workspaceStorageRoot = Join-Path $env:APPDATA "Cursor\User\workspaceStorage"
        if (Test-Path $workspaceStorageRoot) {
            $psesWorkspaceDirs = Get-ChildItem -Path $workspaceStorageRoot -Directory -Recurse -Filter "ms-vscode.powershell*" -ErrorAction SilentlyContinue
            if ($psesWorkspaceDirs) {
                foreach ($dir in $psesWorkspaceDirs) {
                    Remove-CacheItems -Path $dir.FullName -Label "Workspace storage: $($dir.FullName)"
                }
            }
            else {
                Write-LogMessage "  PSES workspace storage: none found (skipped)" -Level DEBUG
            }
        }

        # ── 3. Cursor CachedData (extension host cache) ────────────────────────
        $cachedDataRoot = Join-Path $env:APPDATA "Cursor\CachedData"
        if (Test-Path $cachedDataRoot) {
            $cachedItems = Get-ChildItem -Path $cachedDataRoot -Directory -ErrorAction SilentlyContinue
            $cachedBytes = 0
            $cachedCount = 0
            foreach ($dir in $cachedItems) {
                $dirItems = Get-ChildItem -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $cachedBytes += ($dirItems | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                $cachedCount += $dirItems.Count
            }
            if ($cachedCount -gt 0) {
                try {
                    Remove-Item -Path "$($cachedDataRoot)\*" -Recurse -Force -ErrorAction Stop
                    Write-LogMessage "  Cleared Cursor CachedData: $($cachedCount) files, $([math]::Round(($cachedBytes / 1KB), 1)) KB" -Level INFO
                    $totalFiles += $cachedCount
                    $totalBytes += $cachedBytes
                }
                catch {
                    Write-LogMessage "  Failed to clear CachedData (Cursor may be locking files): $($_.Exception.Message)" -Level WARN
                }
            }
            else {
                Write-LogMessage "  Cursor CachedData: empty (skipped)" -Level DEBUG
            }
        }
        else {
            Write-LogMessage "  Cursor CachedData: not found (skipped)" -Level DEBUG
        }

        # ── 4. PSScriptAnalyzer cache ───────────────────────────────────────────
        $psaCache = Join-Path $env:LOCALAPPDATA "Microsoft\PowerShell\PSScriptAnalyzer"
        if (Test-Path $psaCache) {
            Remove-CacheItems -Path $psaCache -Label "PSScriptAnalyzer cache"
        }
        else {
            Write-LogMessage "  PSScriptAnalyzer cache: not found (skipped)" -Level DEBUG
        }

        # ── Summary ─────────────────────────────────────────────────────────────
        Write-LogMessage "" -Level INFO
        if ($totalFiles -gt 0) {
            Write-LogMessage "  Total cleared: $($totalFiles) files, $([math]::Round(($totalBytes / 1MB), 2)) MB" -Level INFO
        }
        else {
            Write-LogMessage "  No stale cache files found -- caches are clean" -Level INFO
        }
    }
    catch {
        Write-LogMessage "Error clearing diagnostics cache: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════════

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "Repair Cursor PowerShell Language Server" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "Computer: $($env:COMPUTERNAME)" -Level INFO
Write-LogMessage "Date:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
Write-LogMessage "User:     $($env:USERNAME)" -Level INFO

$runAll = (-not $Action) -or $All

if ($runAll -or $Action -eq 'KillLanguageServer') {
    Stop-PowerShellLanguageServer
}

if ($runAll -or $Action -eq 'UpdateExtension') {
    Update-PowerShellExtension
}

if ($runAll -or $Action -eq 'UpdatePowerShell') {
    Update-PowerShell7
}

if ($runAll -or $Action -eq 'ClearDiagnosticsCache') {
    Clear-DiagnosticsCache
}

# ═══════════════════════════════════════════════════════════════════════════════
# Final instructions
# ═══════════════════════════════════════════════════════════════════════════════
Write-LogMessage "" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "ALL DONE -- Please close Cursor completely and restart it." -Level WARN
Write-LogMessage "This ensures the language server starts fresh with cleared caches." -Level WARN
Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
