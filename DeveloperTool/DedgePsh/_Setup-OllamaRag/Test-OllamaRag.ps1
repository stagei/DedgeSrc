<#
.SYNOPSIS
    Verify that the Ollama RAG setup is working after restart.

.DESCRIPTION
    Checks:
    1. Ollama is installed and has models available
    2. Remote RAG HTTP servers respond to /health
    3. Each RAG returns results for a test query
    4. Ask-Rag function exists in the PowerShell profile
    5. Ask-Rag is callable in the current session

.EXAMPLE
    pwsh.exe -File Test-OllamaRag.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-Rag >>>'
$registryHost = 'dedge-server'
$registryPort = 8484

$passed = 0
$failed = 0

function Write-Pass { param([string]$Msg) $script:passed++; Write-Host "  [PASS] $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) $script:failed++; Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

Write-Host ''
Write-Host '=== Ollama RAG Setup Verification ===' -ForegroundColor Cyan
Write-Host ''

# ── 1. Ollama ────────────────────────────────────────────────────────────
Write-Host '[1/5] Checking Ollama...' -ForegroundColor White
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaCmd) {
    Write-Pass "Ollama found at $($ollamaCmd.Source)"
} else {
    Write-Fail 'Ollama not found in PATH. Install from https://ollama.com'
}

if ($ollamaCmd) {
    $models = $null
    try { $models = (ollama list 2>$null) } catch {}
    if ($models -and ($models | Measure-Object).Count -gt 1) {
        $modelCount = ($models | Measure-Object).Count - 1
        Write-Pass "Ollama has $($modelCount) model(s) available"
    } else {
        Write-Fail "No Ollama models found. Run: ollama pull llama3.2"
    }
}

# ── 2. Remote RAG health ────────────────────────────────────────────────
Write-Host '[2/5] Checking remote RAG servers...' -ForegroundColor White
$registry = $null
try {
    $registry = Invoke-RestMethod -Uri "http://$($registryHost):$($registryPort)/rags" -TimeoutSec 10
    Write-Pass "Registry reachable, $($registry.rags.Count) RAG(s) registered"
} catch {
    Write-Fail "Registry unreachable at http://$($registryHost):$($registryPort)/rags"
}

$ragHost = if ($registry -and $registry.host) { $registry.host } else { $registryHost }

if ($registry -and $registry.rags) {
    foreach ($rag in $registry.rags) {
        try {
            $null = Invoke-RestMethod -Uri "http://$($ragHost):$($rag.port)/health" -TimeoutSec 5
            Write-Pass "$($rag.name) health OK (port $($rag.port))"
        } catch {
            Write-Fail "$($rag.name) health FAILED on port $($rag.port)"
        }
    }
}

# ── 3. Test queries ─────────────────────────────────────────────────────
Write-Host '[3/5] Running test queries (RAG only, no Ollama)...' -ForegroundColor White

$testQueries = @{
    'db2-docs'          = 'SQL30082N'
    'visual-cobol-docs' = 'COBCH0779'
    'Dedge-code'       = 'Deploy-Files'
}

if ($registry -and $registry.rags) {
    foreach ($rag in $registry.rags) {
        $query = $testQueries[$rag.name]
        if (-not $query) { $query = 'test' }
        try {
            $url = "http://$($ragHost):$($rag.port)/query?q=$([uri]::EscapeDataString($query))&n=1"
            $result = Invoke-RestMethod -Uri $url -TimeoutSec 15
            if ($result) {
                Write-Pass "$($rag.name) query '$($query)' returned results"
            } else {
                Write-Fail "$($rag.name) query '$($query)' returned empty"
            }
        } catch {
            Write-Fail "$($rag.name) query failed: $($_.Exception.Message)"
        }
    }
}

# ── 4. Profile contains Ask-Rag ─────────────────────────────────────────
Write-Host '[4/5] Checking PowerShell profile...' -ForegroundColor White
if (Test-Path -LiteralPath $profilePath) {
    Write-Pass "Profile exists: $($profilePath)"
    $content = Get-Content -LiteralPath $profilePath -Raw
    if ($content -match [regex]::Escape($markerBegin)) {
        Write-Pass 'Ask-Rag block found in profile'

        if ($content -match 'function Ask-Rag') {
            Write-Pass 'Ask-Rag function definition present'
        } else {
            Write-Fail 'Ask-Rag function definition missing from marker block'
        }

        $ragNames = @()
        if ($registry -and $registry.rags) {
            foreach ($rag in $registry.rags) {
                if ($content -match [regex]::Escape("'$($rag.name)'")) {
                    $ragNames += $rag.name
                } else {
                    Write-Fail "RAG '$($rag.name)' not found in Ask-Rag ragUrls"
                }
            }
        }
        if ($ragNames.Count -gt 0) {
            Write-Pass "Profile has $($ragNames.Count) RAG URL(s): $($ragNames -join ', ')"
        }
    } else {
        Write-Fail 'Ask-Rag block not found in profile. Run Setup-OllamaRag.ps1'
    }
} else {
    Write-Fail "Profile not found: $($profilePath). Run Setup-OllamaRag.ps1"
}

# ── 5. Ask-Rag callable ─────────────────────────────────────────────────
Write-Host '[5/5] Checking Ask-Rag in current session...' -ForegroundColor White

if (Test-Path -LiteralPath $profilePath) {
    try {
        . $profilePath 2>$null
    } catch {}
}

$askRagCmd = Get-Command Ask-Rag -ErrorAction SilentlyContinue
if ($askRagCmd) {
    Write-Pass 'Ask-Rag function is callable'
} else {
    Write-Fail 'Ask-Rag function not loaded. Restart PowerShell after running Setup-OllamaRag.ps1'
}

# ── Summary ─────────────────────────────────────────────────────────────
Write-Host ''
Write-Host "=== Results: $($passed) passed, $($failed) failed ===" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })

if ($failed -eq 0) {
    Write-Host 'All checks passed. Ask-Rag is ready to use.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Try it:' -ForegroundColor White
    Write-Host '  Ask-Rag "What does SQL30082N reason code 36 mean?"' -ForegroundColor DarkGray
    Write-Host '  Ask-Rag "COBCH0779 error" -Rag visual-cobol-docs' -ForegroundColor DarkGray
    Write-Host '  Ask-Rag "Deploy-Files" -Rag Dedge-code' -ForegroundColor DarkGray
} else {
    Write-Host 'Some checks failed. Run Setup-OllamaRag.ps1 to fix, then retest.' -ForegroundColor Yellow
}
Write-Host ''
