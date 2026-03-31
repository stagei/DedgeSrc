<#
.SYNOPSIS
    Verify Ollama RAG setup (via AiDocNew API).
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'http://dedge-server/AiDocNew'
)

Import-Module GlobalFunctions -Force

Write-LogMessage "[1/4] Ollama..." -Level INFO
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaCmd) { Write-LogMessage "       OK" -Level INFO }
else { Write-LogMessage "       NOT FOUND" -Level ERROR }

Write-LogMessage "[2/4] API health..." -Level INFO
try {
    $null = Invoke-RestMethod -Uri "$($ApiBaseUrl)/health" -TimeoutSec 5
    Write-LogMessage "       OK" -Level INFO
} catch { Write-LogMessage "       FAILED: $($_.Exception.Message)" -Level ERROR }

Write-LogMessage "[3/4] Remote RAG services..." -Level INFO
try {
    $services = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/Rags/setup/services" -TimeoutSec 10
    foreach ($svc in $services) {
        $level = if ($svc.status -eq 'running') { 'INFO' } else { 'WARN' }
        Write-LogMessage "       $($svc.name): $($svc.status) (port $($svc.port))" -Level $level
    }
} catch { Write-LogMessage "       Could not check services" -Level ERROR }

Write-LogMessage "[4/4] Profile function..." -Level INFO
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path -LiteralPath $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    if ($content -match 'Ask-Rag') { Write-LogMessage "       Ask-Rag found in profile" -Level INFO }
    else { Write-LogMessage "       Ask-Rag NOT in profile" -Level WARN }
} else { Write-LogMessage "       No profile file" -Level WARN }

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "RAG Ollama MCP checks completed"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
