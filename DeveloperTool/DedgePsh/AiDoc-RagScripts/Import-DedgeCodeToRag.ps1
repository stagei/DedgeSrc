<#
.SYNOPSIS
    Convert Dedge source code to markdown and build the RAG index.

.DESCRIPTION
    Walks all configured repos under CloneRoot, converts each source file to a
    markdown document with metadata headers, and places the result under
    library/Dedge-code/code/<repo>/<path>.md.

    Uses mtime comparison to skip unchanged files. Removes orphaned markdown
    when the corresponding source file no longer exists. Optionally builds
    the ChromaDB index via build_index.py.

.PARAMETER CloneRoot
    Path where repos were cloned. Default: $env:OptPath\src

.PARAMETER AiDocRoot
    Root of the AiDoc folder. Default: $env:OptPath\FkPythonApps\AiDoc

.PARAMETER NoBuildIndex
    Skip the build_index.py step after conversion.

.PARAMETER Force
    Re-convert all files regardless of mtime.

.EXAMPLE
    pwsh.exe -File Import-DedgeCodeToRag.ps1
.EXAMPLE
    pwsh.exe -File Import-DedgeCodeToRag.ps1 -CloneRoot C:\code\repos -Force
#>
[CmdletBinding()]
param(
    [string]$CloneRoot,
    [string]$AiDocRoot,
    [switch]$NoBuildIndex,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $AiDocRoot) {
    if (-not $env:OptPath) { throw 'Environment variable OptPath is not set.' }
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
if (-not $CloneRoot) {
    $CloneRoot = Join-Path $env:OptPath 'src'
}

$ragName    = 'Dedge-code'
$ragDir     = Join-Path $AiDocRoot "library\$ragName"
$codeDir    = Join-Path $ragDir 'code'
$configFile = Join-Path $ragDir '.Dedge-rag-config.json'

if (-not (Test-Path -LiteralPath $configFile)) {
    Write-Host '[ERROR] Config not found. Run Setup-DedgeCodeRag.ps1 first.' -ForegroundColor Red
    exit 1
}

$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json

$includeExts = @{}
foreach ($ext in $config.includeExtensions) { $includeExts[$ext.ToLower()] = $true }

$excludeDirs = @{}
foreach ($dir in $config.excludeDirs) { $excludeDirs[$dir.ToLower()] = $true }

$langMap = @{}
foreach ($prop in $config.languageMap.PSObject.Properties) { $langMap[$prop.Name.ToLower()] = $prop.Value }

$ansiExts = @{}
if ($config.ansiExtensions) {
    foreach ($ext in $config.ansiExtensions) { $ansiExts[$ext.ToLower()] = $true }
}
$cp1252 = [System.Text.Encoding]::GetEncoding(1252)

# ── Counters ────────────────────────────────────────────────────────────
$stats = @{ Added = 0; Updated = 0; Skipped = 0; Orphaned = 0; Errors = 0 }
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ── Track all generated markdown paths for orphan detection ─────────────
$generatedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

Write-Host "Import-DedgeCodeToRag starting" -ForegroundColor Cyan
Write-Host "  CloneRoot: $CloneRoot" -ForegroundColor DarkGray
Write-Host "  RAG dir:   $ragDir" -ForegroundColor DarkGray
Write-Host "  Repos:     $($config.repos.Count)" -ForegroundColor DarkGray
Write-Host ''

foreach ($repoName in $config.repos) {
    $repoPath = Join-Path $CloneRoot $repoName
    if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) {
        Write-Host "  [SKIP] Repo not found: $repoName" -ForegroundColor Yellow
        continue
    }

    $repoCodeDir = Join-Path $codeDir $repoName
    if (-not (Test-Path -LiteralPath $repoCodeDir)) {
        New-Item -ItemType Directory -Path $repoCodeDir -Force | Out-Null
    }

    $repoFiles = 0
    $repoSkipped = 0

    Get-ChildItem -LiteralPath $repoPath -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $file = $_
        $ext = $file.Extension.ToLower()

        if (-not $includeExts.ContainsKey($ext)) { return }

        # Check if any parent directory is excluded
        $relDir = $file.DirectoryName
        if ($relDir.Length -gt $repoPath.Length) {
            $relParts = $relDir.Substring($repoPath.Length + 1).Split([IO.Path]::DirectorySeparatorChar)
            foreach ($part in $relParts) {
                if ($excludeDirs.ContainsKey($part.ToLower())) { return }
            }
        }

        $relPath = $file.FullName.Substring($repoPath.Length + 1)
        $mdRelPath = "$relPath.md"
        $mdFullPath = Join-Path $repoCodeDir $mdRelPath

        $null = $generatedPaths.Add($mdFullPath)

        # Mtime-based skip
        if (-not $Force -and (Test-Path -LiteralPath $mdFullPath)) {
            $mdMtime = (Get-Item -LiteralPath $mdFullPath).LastWriteTimeUtc
            if ($file.LastWriteTimeUtc -le $mdMtime) {
                $repoSkipped++
                $stats.Skipped++
                return
            }
        }

        try {
            $mdDir = Split-Path $mdFullPath -Parent
            if (-not (Test-Path -LiteralPath $mdDir)) {
                New-Item -ItemType Directory -Path $mdDir -Force | Out-Null
            }

            $lang = if ($langMap.ContainsKey($ext)) { $langMap[$ext] } else { '' }

            if ($ansiExts.ContainsKey($ext)) {
                $bytes   = [System.IO.File]::ReadAllBytes($file.FullName)
                $content = $cp1252.GetString($bytes)
            } else {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            }

            # Extract DB2 database reference from COBOL $SET directive
            $dbRef = ''
            $dbProd = ''
            if ($ext -in '.cbl', '.cpy', '.cpb', '.cpx') {
                $firstLine = ($content -split "`n", 2)[0]
                # Regex: match DB= followed by word characters inside a $SET directive
                # DB=       - literal "DB="
                # (\w+)     - capture group: one or more word chars (the database name)
                if ($firstLine -match 'DB=(\w+)') {
                    $dbRef = $Matches[1]
                }
            }

            # Map dev/test aliases to their production database name
            $dbAliasMap = @{
                'FKAVDNT'  = 'BASISPRO'
                'BASISTST' = 'BASISPRO'
                'BASISMIG' = 'BASISPRO'
                'BASISVFT' = 'BASISPRO'
                'BASISKAT' = 'BASISPRO'
                'BASISPER' = 'BASISPRO'
                'BASISFUT' = 'BASISPRO'
                'BASISVFK' = 'BASISPRO'
                'BASISRAP' = 'BASISPRO'
            }
            if ($dbRef -and $dbAliasMap.ContainsKey($dbRef.ToUpper())) {
                $dbProd = $dbAliasMap[$dbRef.ToUpper()]
            }

            $header = "# $($file.Name)`n`n"
            $header += "- **Repository:** $repoName`n"
            $header += "- **Language:** $lang`n"
            $header += "- **Path:** $relPath`n"
            if ($dbRef -and $dbProd) {
                $header += "- **Database:** $dbRef (= $dbProd)`n"
            } elseif ($dbRef) {
                $header += "- **Database:** $dbRef`n"
            }
            $header += "`n"

            $fenceLang = if ($lang) { $lang } else { '' }
            $md = "$header``````$fenceLang`n$content`n```````n"

            Set-Content -LiteralPath $mdFullPath -Value $md -Encoding utf8 -NoNewline

            if ($file.LastWriteTimeUtc -gt [datetime]::MinValue) {
                $isNew = -not (Test-Path -LiteralPath $mdFullPath -ErrorAction SilentlyContinue) -or $repoSkipped -eq $repoSkipped
            }
            $repoFiles++
            if ($stats.Added -eq $stats.Added) {
                $stats.Updated++
            }
        } catch {
            $stats.Errors++
            Write-Host "  [ERR] $($repoName)/$($relPath): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $totalForRepo = $repoFiles + $repoSkipped
    if ($totalForRepo -gt 0) {
        Write-Host "  $($repoName.PadRight(30)) $repoFiles converted, $repoSkipped unchanged" -ForegroundColor White
    }
}

# ── Orphan cleanup ──────────────────────────────────────────────────────
Write-Host ''
Write-Host 'Checking for orphaned files...' -ForegroundColor Cyan

if ($generatedPaths.Count -eq 0) {
    Write-Host '  No repos were processed -- skipping orphan cleanup to protect existing files.' -ForegroundColor Yellow
} elseif (Test-Path -LiteralPath $codeDir) {
    Get-ChildItem -LiteralPath $codeDir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $generatedPaths.Contains($_.FullName)) {
            Remove-Item -LiteralPath $_.FullName -Force
            $stats.Orphaned++
        }
    }

    # Remove empty directories left after orphan cleanup
    Get-ChildItem -LiteralPath $codeDir -Directory -Recurse -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0 } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse }
}

Write-Host "  Removed $($stats.Orphaned) orphaned file(s)" -ForegroundColor DarkGray

# ── Build index ─────────────────────────────────────────────────────────
if (-not $NoBuildIndex -and ($stats.Updated -gt 0 -or $stats.Orphaned -gt 0 -or $Force)) {
    Write-Host ''
    Write-Host 'Building RAG index...' -ForegroundColor Cyan

    $mcpCandidates = @(Join-Path $AiDocRoot 'mcp-ai-docs')
    if ($env:OptPath) {
        $mcpCandidates += (Join-Path $env:OptPath 'FkPythonApps\AiDoc\mcp-ai-docs')
        $mcpCandidates += (Join-Path $env:OptPath 'src\AiDoc\mcp-ai-docs')
    }
    $mcpDir = $null
    foreach ($d in $mcpCandidates) {
        if ($d -and (Test-Path -LiteralPath $d)) { $mcpDir = $d; break }
    }
    if (-not $mcpDir) { $mcpDir = Join-Path $AiDocRoot 'mcp-ai-docs' }

    $pythonExe = $null
    $venvPython = Join-Path $mcpDir '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venvPython) {
        $pythonExe = $venvPython
        Write-Host "  Using venv Python: $pythonExe" -ForegroundColor DarkGray
    } else {
        foreach ($ver in @('3.14', '3.13', '3.12', '3.11')) {
            try { $pythonExe = (py "-$ver" -c "import sys; print(sys.executable)" 2>$null) } catch {}
            if ($pythonExe -and (Test-Path -LiteralPath $pythonExe)) { break }
            $pythonExe = $null
        }
        if (-not $pythonExe) {
            $p = Get-Command python -ErrorAction SilentlyContinue
            if ($p -and $p.Source -notmatch 'WindowsApps') { $pythonExe = $p.Source }
        }
    }

    if ($pythonExe) {
        Push-Location -LiteralPath $mcpDir
        try {
            & $pythonExe build_index.py --rag $ragName
            if ($LASTEXITCODE -ne 0) {
                Write-Host '[ERROR] build_index.py failed.' -ForegroundColor Red
            } else {
                Write-Host '  Index built successfully.' -ForegroundColor Green
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host '[WARN] Python not found, skipping index build.' -ForegroundColor Yellow
    }
} elseif (-not $NoBuildIndex) {
    Write-Host ''
    Write-Host 'No changes detected, index build skipped.' -ForegroundColor DarkGray
}

$sw.Stop()
Write-Host ''
Write-Host "Done in $($sw.Elapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
Write-Host "  Updated:  $($stats.Updated)" -ForegroundColor White
Write-Host "  Skipped:  $($stats.Skipped)" -ForegroundColor White
Write-Host "  Orphaned: $($stats.Orphaned)" -ForegroundColor White
if ($stats.Errors -gt 0) {
    Write-Host "  Errors:   $($stats.Errors)" -ForegroundColor Red
}
Write-Host ''
