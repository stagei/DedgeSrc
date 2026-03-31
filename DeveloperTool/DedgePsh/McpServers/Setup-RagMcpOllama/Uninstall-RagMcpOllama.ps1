<#
.SYNOPSIS
    Remove Ask-Rag from the PowerShell profile (Ollama RAG MCP).
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-RagMcpOllama.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-Rag >>>'
$markerEnd   = '# <<< AiDoc Ask-Rag <<<'

Write-LogMessage "Removing Ask-Rag from PowerShell profile..." -Level INFO

if (-not (Test-Path -LiteralPath $profilePath)) {
    Write-LogMessage "Profile not found at $($profilePath). Nothing to remove." -Level WARN
    exit 0
}

$content = Get-Content -LiteralPath $profilePath -Raw

# Regex: match everything between (and including) the marker lines
# (?m) = multiline; [\s\S]*? = non-greedy match across lines; \r?\n? = optional trailing newline
$pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"

if ($content -match [regex]::Escape($markerBegin)) {
    $cleaned = [regex]::Replace($content, $pattern, '')
    Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
    Write-LogMessage "Removed Ask-Rag from profile. Restart PowerShell." -Level INFO
} else {
    Write-LogMessage "Ask-Rag not found in profile. Nothing to remove." -Level WARN
}
