<#
.SYNOPSIS
    Full refresh: pull repos, export DB2 schemas, convert code to markdown, rebuild RAG index.

.DESCRIPTION
    Pipeline script that:
    1. Runs Sync-DedgeCodeRepos.ps1 to clone/pull all Dedge repos into the RAG library code folder
    2. Runs Db2-ExportForRag.ps1 to export DB2 schemas directly into the RAG library
    3. Runs Import-DedgeCodeToRag.ps1 to convert changed code to markdown
    4. Builds the ChromaDB index (via Import script)

    Designed to be scheduled or run manually for periodic refresh.

.PARAMETER CloneRoot
    Path where repos are cloned. Default: library\Dedge-code\code under AiDocRoot.

.PARAMETER AiDocRoot
    Root of the AiDoc folder. Default: $env:OptPath\FkPythonApps\AiDoc

.PARAMETER SkipClone
    Skip the Azure DevOps clone/pull step.

.PARAMETER SkipDb2Export
    Skip the DB2 schema export step.

.PARAMETER ForceRebuild
    Force re-conversion of all code files and index rebuild even if no changes.

.PARAMETER Db2Databases
    Databases to export. Default: BASISPRO, BASISHST, FKKONTO, COBDOK.

.EXAMPLE
    pwsh.exe -File Refresh-DedgeCodeRag.ps1
.EXAMPLE
    pwsh.exe -File Refresh-DedgeCodeRag.ps1 -SkipClone
.EXAMPLE
    pwsh.exe -File Refresh-DedgeCodeRag.ps1 -SkipDb2Export
.EXAMPLE
    pwsh.exe -File Refresh-DedgeCodeRag.ps1 -ForceRebuild
#>
[CmdletBinding()]
param(
    [string]$CloneRoot,
    [string]$AiDocRoot,
    [switch]$SkipClone,
    [switch]$SkipDb2Export,
    [switch]$ForceRebuild,
    [string[]]$Db2Databases = @('BASISPRO', 'BASISHST', 'FKKONTO', 'COBDOK')
)

$ErrorActionPreference = 'Stop'

if (-not $env:OptPath) { throw 'Environment variable OptPath is not set.' }

if (-not $AiDocRoot) {
    if ($env:USERNAME -in @('FKGEISTA', 'FKSVEERI')) {
        $AiDocRoot = Join-Path $env:OptPath 'src\AiDoc'
    } else {
        $candidates = @(
            (Join-Path $env:OptPath 'FkPythonApps\AiDoc'),
            (Join-Path $env:OptPath 'src\AiDoc')
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath (Join-Path $c 'mcp-ai-docs')) {
                $AiDocRoot = $c
                break
            }
        }
        if (-not $AiDocRoot) { $AiDocRoot = Join-Path $env:OptPath 'FkPythonApps\AiDoc' }
    }
}
if (-not $CloneRoot) {
    $CloneRoot = Join-Path $AiDocRoot 'library\Dedge-code\code'
}

$ragDbDir = Join-Path $AiDocRoot 'library\Dedge-code\_databases'

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Dedge Code RAG Refresh' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "  AiDocRoot:  $AiDocRoot" -ForegroundColor DarkGray
Write-Host "  CloneRoot:  $CloneRoot" -ForegroundColor DarkGray
Write-Host "  RAG DB dir: $ragDbDir" -ForegroundColor DarkGray
Write-Host ''

# ── Step 1/4: Clone/update repos ────────────────────────────────────────
if (-not $SkipClone) {
    Write-Host '[1/4] Syncing repos into RAG library code folder...' -ForegroundColor Cyan

    $syncCandidates = @(
        (Join-Path $env:OptPath 'DedgePshApps\Sync-DedgeCodeRepos\Sync-DedgeCodeRepos.ps1'),
        (Join-Path $env:OptPath 'src\DedgePsh\DevTools\CodingTools\Sync-DedgeCodeRepos\Sync-DedgeCodeRepos.ps1')
    )
    $syncScript = $null
    foreach ($c in $syncCandidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { $syncScript = $c; break }
    }

    if (-not $syncScript) {
        Write-Host "       [WARN] Sync-DedgeCodeRepos.ps1 not found. Skipping clone step." -ForegroundColor Yellow
        Write-Host '       Repos must already exist in the code folder.' -ForegroundColor Yellow
    } else {
        try {
            & $syncScript -AiDocRoot $AiDocRoot
            Write-Host '       Sync complete.' -ForegroundColor Green
        } catch {
            Write-Host "       [WARN] Sync failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host '       Continuing with existing repo state.' -ForegroundColor Yellow
        }
    }
} else {
    Write-Host '[1/4] Clone skipped (-SkipClone).' -ForegroundColor DarkGray
}

Write-Host ''

# ── Step 2/4: Export DB2 schemas ─────────────────────────────────────────
if (-not $SkipDb2Export) {
    Write-Host "[2/4] Exporting DB2 schemas ($($Db2Databases -join ', '))..." -ForegroundColor Cyan

    $exportCandidates = @(
        (Join-Path $env:OptPath 'src\DedgePsh\DevTools\CodingTools\Db2-ExportForRag\Db2-ExportForRag.ps1'),
        (Join-Path $env:OptPath 'DedgePshApps\Db2-ExportForRag\Db2-ExportForRag.ps1')
    )
    $exportScript = $null
    foreach ($c in $exportCandidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { $exportScript = $c; break }
    }

    if (-not $exportScript) {
        Write-Host '       [WARN] Db2-ExportForRag.ps1 not found. Skipping DB2 export.' -ForegroundColor Yellow
    } else {
        Write-Host "       Script: $exportScript" -ForegroundColor DarkGray
        Write-Host "       Output: $ragDbDir" -ForegroundColor DarkGray
        try {
            & $exportScript -DatabaseNames $Db2Databases -RagLibraryPath $ragDbDir
            Write-Host '       DB2 export complete.' -ForegroundColor Green
        } catch {
            Write-Host "       [WARN] DB2 export failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host '       Continuing with existing database metadata.' -ForegroundColor Yellow
        }
    }
} else {
    Write-Host '[2/4] DB2 export skipped (-SkipDb2Export).' -ForegroundColor DarkGray
}

Write-Host ''

# ── Step 3/4: Convert code to markdown ──────────────────────────────────
Write-Host '[3/4] Converting code to markdown...' -ForegroundColor Cyan

$importCandidates = @(
    (Join-Path $PSScriptRoot 'Import-DedgeCodeToRag.ps1'),
    (Join-Path $env:OptPath 'DedgePshApps\AiDoc-RagScripts\Import-DedgeCodeToRag.ps1'),
    (Join-Path $AiDocRoot 'scripts\Import-DedgeCodeToRag.ps1')
)
$importScript = $null
foreach ($c in $importCandidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { $importScript = $c; break }
}
if (-not $importScript) { $importScript = $importCandidates[0] }
if (-not (Test-Path -LiteralPath $importScript)) {
    Write-Host "       [ERROR] Import script not found: $importScript" -ForegroundColor Red
    exit 1
}

$importParams = @{
    CloneRoot = $CloneRoot
    AiDocRoot = $AiDocRoot
}
if ($ForceRebuild) { $importParams['Force'] = $true }

& $importScript @importParams

Write-Host ''

# ── Step 4/4: Summary ───────────────────────────────────────────────────
$sw.Stop()
Write-Host '========================================' -ForegroundColor Cyan
Write-Host " Refresh complete in $($sw.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
