<#
.SYNOPSIS
    Test Ollama DB2 setup (via AiDocNew API).
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'http://dedge-server/AiDocNew'
)

Import-Module GlobalFunctions -Force

Write-LogMessage "[1/3] Ollama..." -Level INFO
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaCmd) { Write-LogMessage "       OK" -Level INFO }
else { Write-LogMessage "       NOT FOUND" -Level ERROR }

Write-LogMessage "[2/3] API health..." -Level INFO
try {
    $null = Invoke-RestMethod -Uri "$($ApiBaseUrl)/health" -TimeoutSec 5
    Write-LogMessage "       OK" -Level INFO
} catch { Write-LogMessage "       FAILED: $($_.Exception.Message)" -Level ERROR }

Write-LogMessage "[3/3] Profile function..." -Level INFO
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path -LiteralPath $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    if ($content -match 'Ask-Db2') { Write-LogMessage "       Ask-Db2 found in profile" -Level INFO }
    else { Write-LogMessage "       Ask-Db2 NOT in profile" -Level WARN }
} else { Write-LogMessage "       No profile file" -Level WARN }

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "DB2 Query Ollama MCP checks completed"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
