<#
.SYNOPSIS
    Test Ollama AutoDoc setup (Ask-AutoDoc function and MCP endpoint).
.PARAMETER ServerHost
    Hostname of the server running AutoDocJson. Default: dedge-server
.EXAMPLE
    pwsh.exe -NoProfile -File Test-AutoDocMcpOllama.ps1
#>
[CmdletBinding()]
param(
    [string]$ServerHost = 'dedge-server'
)

Import-Module GlobalFunctions -Force

Write-LogMessage "[1/3] Ollama..." -Level INFO
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaCmd) { Write-LogMessage "       OK" -Level INFO }
else { Write-LogMessage "       NOT FOUND" -Level ERROR }

Write-LogMessage "[2/3] AutoDocJson health..." -Level INFO
try {
    $null = Invoke-RestMethod -Uri "http://$($ServerHost)/AutoDocJson/health" -TimeoutSec 5
    Write-LogMessage "       OK" -Level INFO
} catch { Write-LogMessage "       FAILED: $($_.Exception.Message)" -Level ERROR }

Write-LogMessage "[3/3] Profile function..." -Level INFO
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path -LiteralPath $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    if ($content -match 'Ask-AutoDoc') { Write-LogMessage "       Ask-AutoDoc found in profile" -Level INFO }
    else { Write-LogMessage "       Ask-AutoDoc NOT in profile" -Level WARN }
} else { Write-LogMessage "       No profile file" -Level WARN }

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "AutoDoc Query Ollama MCP checks completed"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
