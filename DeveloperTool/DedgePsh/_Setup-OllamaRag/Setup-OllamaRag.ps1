<#
.SYNOPSIS
    Configure Ollama to use the remote RAG doc servers.

.DESCRIPTION
    Sets up any machine so a user can ask documentation questions from the
    command line using Ollama + the central RAG. Auto-discovers available
    RAGs from the server's /rags registry endpoint. After running this:

        Ask-Rag "What does SQL30082N reason code 36 mean?"
        Ask-Rag "COBCH0779 compiler error" -Rag visual-cobol-docs

    Checks that Ollama is installed and has at least one model.
    Adds the Ask-Rag function to the user's PowerShell profile.

.PARAMETER RemoteHost
    RAG server hostname. Default: dedge-server

.PARAMETER RegistryPort
    Port to query for the /rags registry. Default: 8484

.PARAMETER Model
    Ollama model to use. Default: llama3.2

.PARAMETER Remove
    Remove Ask-Rag from the PowerShell profile.

.EXAMPLE
    pwsh.exe -File Setup-OllamaRag.ps1
.EXAMPLE
    pwsh.exe -File Setup-OllamaRag.ps1 -Model mistral
.EXAMPLE
    pwsh.exe -File Setup-OllamaRag.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$RemoteHost   = 'dedge-server',
    [int]$RegistryPort    = 8484,
    [string]$Model        = 'llama3.2',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-Rag >>>'
$markerEnd   = '# <<< AiDoc Ask-Rag <<<'

# ── Remove ──────────────────────────────────────────────────────────────
if ($Remove) {
    if (Test-Path -LiteralPath $profilePath) {
        $content = Get-Content -LiteralPath $profilePath -Raw
        # Regex: remove the marker block
        # \# >>> ... [\s\S]*? ... \# <<< - non-greedy match between markers
        # \r?\n? - optional trailing newline
        $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
        $cleaned = [regex]::Replace($content, $pattern, '')
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-Host '[OK] Removed Ask-Rag from profile. Restart PowerShell.' -ForegroundColor Green
    } else {
        Write-Host '[INFO] No profile file found, nothing to remove.' -ForegroundColor Yellow
    }
    return
}

# ── Discover RAGs from registry ─────────────────────────────────────────
Write-Host "[1/4] Discovering RAGs from http://$($RemoteHost):$($RegistryPort)/rags ..." -ForegroundColor Cyan

$registry = $null
try {
    $registry = Invoke-RestMethod -Uri "http://$($RemoteHost):$($RegistryPort)/rags" -TimeoutSec 10
} catch {
    Write-Host "       HTTP registry not reachable, trying UNC fallback..." -ForegroundColor Yellow
    $uncPath = "\\$($RemoteHost)\opt\FkPythonApps\AiDoc\rag-registry.json"
    if (Test-Path -LiteralPath $uncPath) {
        $registry = Get-Content -LiteralPath $uncPath -Raw | ConvertFrom-Json
    }
}
if (-not $registry -or -not $registry.rags -or $registry.rags.Count -eq 0) {
    Write-Host '[ERROR] No RAGs found. Is the RAG server running?' -ForegroundColor Red
    exit 1
}

$ragHost = if ($registry.host) { $registry.host } else { $RemoteHost }
Write-Host "       Found $($registry.rags.Count) RAG(s): $($registry.rags.name -join ', ')" -ForegroundColor DarkGray

# ── Check Ollama ────────────────────────────────────────────────────────
Write-Host '[2/4] Checking Ollama...' -ForegroundColor Cyan
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCmd) {
    Write-Host '[ERROR] Ollama not found. Install from https://ollama.com then rerun.' -ForegroundColor Red
    exit 1
}

$models = $null
try { $models = (ollama list 2>$null) } catch {}
if (-not $models -or ($models | Measure-Object).Count -le 1) {
    Write-Host "[WARN] No Ollama models found. Pulling $($Model)..." -ForegroundColor Yellow
    ollama pull $Model
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to pull $($Model). Run 'ollama pull $($Model)' manually." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "       Ollama OK, models available." -ForegroundColor DarkGray
}

# ── Check RAG servers reachable ─────────────────────────────────────────
Write-Host '[3/4] Checking RAG servers...' -ForegroundColor Cyan
foreach ($rag in $registry.rags) {
    try {
        $null = Invoke-RestMethod -Uri "http://$($ragHost):$($rag.port)/health" -TimeoutSec 5
        Write-Host "       $($rag.name) OK (port $($rag.port))" -ForegroundColor DarkGray
    } catch {
        Write-Host "       [WARN] $($rag.name) not reachable on port $($rag.port)" -ForegroundColor Yellow
    }
}

# ── Build ragUrls hashtable string from registry ────────────────────────
$ragUrlEntries = ($registry.rags | ForEach-Object {
    "        '$($_.name)' = 'http://$($ragHost):$($_.port)'"
}) -join "`n"

$ragListStr = ($registry.rags | ForEach-Object { $_.name }) -join ', '

# ── Add Ask-Rag to profile ──────────────────────────────────────────────
Write-Host '[4/4] Adding Ask-Rag to PowerShell profile...' -ForegroundColor Cyan

$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

$functionTemplate = @'
function Ask-Rag {
    <#
    .SYNOPSIS
        Ask a question using remote RAG + Ollama.
    .EXAMPLE
        Ask-Rag "What does SQL30082N reason code 36 mean?"
        Ask-Rag "COBCH0779 error" -Rag visual-cobol-docs
        Ask-Rag "DB2 SSL setup" -Model mistral -Chunks 8
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Question,
        [string]$Rag     = 'db2-docs',
        [string]$Model   = '%%MODEL%%',
        [int]$Chunks     = 6
    )

    $ragUrls = @{
%%RAGURLS%%
    }
    $baseUrl = $ragUrls[$Rag]
    if (-not $baseUrl) { Write-Host "Unknown RAG: $Rag. Available: %%RAGLIST%%" -ForegroundColor Red; return }

    Write-Host "Searching $Rag..." -ForegroundColor DarkGray
    try {
        $body = @{ query = $Question; n_results = $Chunks } | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri "$baseUrl/query" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
        $context = $resp.result
    } catch {
        Write-Host "RAG query failed: $($_.Exception.Message)" -ForegroundColor Red; return
    }
    if (-not $context) { Write-Host 'No results from RAG.' -ForegroundColor Yellow; return }

    $prompt = "You are a technical assistant. Answer the question using ONLY the documentation excerpts below. Cite the source file.`n`n--- DOCUMENTATION ---`n$context`n--- END ---`n`nQuestion: $Question"

    Write-Host "Asking Ollama ($Model)..." -ForegroundColor DarkGray
    $prompt | ollama run $Model
}
'@

$functionBody = $functionTemplate -replace '%%MODEL%%', $Model -replace '%%RAGURLS%%', $ragUrlEntries -replace '%%RAGLIST%%', $ragListStr
$functionBlock = "`n$markerBegin`n$functionBody`n$markerEnd"

if (Test-Path -LiteralPath $profilePath) {
    $existing = Get-Content -LiteralPath $profilePath -Raw
    if ($existing -match [regex]::Escape($markerBegin)) {
        # Regex: replace existing marker block
        # Same pattern as removal
        $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))"
        # Escape '$' as '$$' in replacement string so [regex]::Replace does not
        # treat $_ or $(...) as regex backreferences (which caused recursive nesting).
        $safeReplacement = $functionBlock.Trim().Replace('$', '$$')
        $updated = [regex]::Replace($existing, $pattern, $safeReplacement)
        Set-Content -LiteralPath $profilePath -Value $updated -Encoding utf8
        Write-Host '       Updated existing Ask-Rag in profile.' -ForegroundColor DarkGray
    } else {
        Add-Content -LiteralPath $profilePath -Value $functionBlock -Encoding utf8
    }
} else {
    Set-Content -LiteralPath $profilePath -Value $functionBlock.TrimStart() -Encoding utf8
}

Write-Host ''
Write-Host 'Done. Restart PowerShell, then:' -ForegroundColor Green
Write-Host ''
foreach ($rag in $registry.rags) {
    Write-Host "  Ask-Rag `"your question`" -Rag $($rag.name)" -ForegroundColor White
}
Write-Host ''
