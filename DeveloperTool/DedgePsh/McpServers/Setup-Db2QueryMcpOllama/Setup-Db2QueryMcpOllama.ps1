<#
.SYNOPSIS
    Configure Ollama to use the remote DB2 MCP server (via AiDocNew API).
.PARAMETER ApiBaseUrl
    AiDocNew API base URL. Default: http://dedge-server/AiDocNew
.PARAMETER Remove
    Remove Ask-Db2 from PowerShell profile.
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'http://dedge-server/AiDocNew',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-Db2 >>>'
$markerEnd   = '# <<< AiDoc Ask-Db2 <<<'

if ($Remove) {
    if (Test-Path -LiteralPath $profilePath) {
        $content = Get-Content -LiteralPath $profilePath -Raw
        $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
        $cleaned = [regex]::Replace($content, $pattern, '')
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-LogMessage "Removed Ask-Db2 from profile. Restart PowerShell." -Level INFO
    }
    return
}

Write-LogMessage "[1/3] Fetching DB2 Ollama config from API..." -Level INFO
$config = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/configuration/ollama-db2" -TimeoutSec 10

Write-LogMessage "[2/3] Checking Ollama..." -Level INFO
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCmd) {
    Write-LogMessage "Ollama not found. Install from https://ollama.com" -Level ERROR
    exit 1
}
Write-LogMessage "       Ollama OK" -Level INFO

Write-LogMessage "[3/3] Adding Ask-Db2 to profile..." -Level INFO
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

# Remove old config first (legacy or previous run) so we add clean
if (Test-Path -LiteralPath $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
    $cleaned = [regex]::Replace($content, $pattern, '')
    if ($content -ne $cleaned) {
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-LogMessage "       Removed old Ask-Db2 config." -Level INFO
    }
}

$functionBlock = "`n$($config.profileBlock)"

if (Test-Path -LiteralPath $profilePath) {
    Add-Content -LiteralPath $profilePath -Value $functionBlock -Encoding utf8
} else {
    Set-Content -LiteralPath $profilePath -Value $functionBlock.TrimStart() -Encoding utf8
}

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Installed Ask-Db2 in PowerShell profile"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
