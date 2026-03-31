<#
.SYNOPSIS
    Remove Ask-Db2 from the PowerShell profile (Ollama DB2 Query MCP).
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-Db2QueryMcpOllama.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-Db2 >>>'
$markerEnd   = '# <<< AiDoc Ask-Db2 <<<'

Write-LogMessage "Removing Ask-Db2 from PowerShell profile..." -Level INFO

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
    Write-LogMessage "Removed Ask-Db2 from profile. Restart PowerShell." -Level INFO
} else {
    Write-LogMessage "Ask-Db2 not found in profile. Nothing to remove." -Level WARN
}
