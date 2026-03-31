<#
.SYNOPSIS
    Configure Ollama to use remote RAG doc servers (via AiDocNew API).
.EXAMPLE
    pwsh.exe -NoProfile -File Setup-RagMcpOllama.ps1
.PARAMETER ApiBaseUrl
    AiDocNew API base URL. Default: http://dedge-server/AiDocNew
.PARAMETER Remove
    Remove Ask-Rag from PowerShell profile.
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'http://dedge-server/AiDocNew',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-Rag >>>'
$markerEnd   = '# <<< AiDoc Ask-Rag <<<'

if ($Remove) {
    if (Test-Path -LiteralPath $profilePath) {
        $content = Get-Content -LiteralPath $profilePath -Raw
        $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
        $cleaned = [regex]::Replace($content, $pattern, '')
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-LogMessage "Removed Ask-Rag from profile. Restart PowerShell." -Level INFO
    }
    return
}

Write-LogMessage "[1/4] Fetching Ollama RAG config from $($ApiBaseUrl)..." -Level INFO
$config = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/Rags/setup/ollama-rag" -TimeoutSec 10

if (-not $config.availableRags -or $config.availableRags.Count -eq 0) {
    Write-LogMessage "No RAGs returned from API." -Level ERROR
    exit 1
}
Write-LogMessage "       Found $($config.availableRags.Count) RAG(s): $($config.availableRags -join ', ')" -Level INFO

Write-LogMessage "[2/4] Checking Ollama..." -Level INFO
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCmd) {
    Write-LogMessage "Ollama not found. Install from https://ollama.com" -Level ERROR
    exit 1
}
Write-LogMessage "       Ollama OK" -Level INFO

Write-LogMessage "[3/4] Checking RAG servers..." -Level INFO
try {
    $services = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/Rags/setup/services" -TimeoutSec 10
    foreach ($svc in $services) {
        $level = if ($svc.status -eq 'running') { 'INFO' } else { 'WARN' }
        Write-LogMessage "       $($svc.name): $($svc.status)" -Level $level
    }
} catch { Write-LogMessage "       Could not check services" -Level WARN }

Write-LogMessage "[4/4] Adding Ask-Rag to profile..." -Level INFO
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

# Remove old config first (legacy or previous run) so we add clean
if (Test-Path -LiteralPath $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
    $cleaned = [regex]::Replace($content, $pattern, '')
    if ($content -ne $cleaned) {
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-LogMessage "       Removed old Ask-Rag config." -Level INFO
    }
}

$functionBlock = "`n$($config.profileBlock)"

if (Test-Path -LiteralPath $profilePath) {
    Add-Content -LiteralPath $profilePath -Value $functionBlock -Encoding utf8
} else {
    Set-Content -LiteralPath $profilePath -Value $functionBlock.TrimStart() -Encoding utf8
}

Write-LogMessage "Done. Restart PowerShell." -Level INFO
foreach ($rag in $config.availableRags) {
    Write-LogMessage "  Ask-Rag `"your question`" -Rag $($rag)" -Level INFO
}

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Installed Ask-Rag in PowerShell profile"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
