<#
.SYNOPSIS
    Diagnose and fix RAG venv + service issues.
#>
param(
    [string]$ServiceName = "AiDocRagDb2",
    [int]$Port = 8484,
    [string]$Rag = "db2-docs"
)

Import-Module GlobalFunctions -Force

if (-not $env:OptPath) { throw "Environment variable OptPath is not set." }
$AiDocRoot = Join-Path $env:OptPath "FkPythonApps\AiDoc"
$mcpDir = Join-Path $AiDocRoot "mcp-ai-docs"
$venvDir = Join-Path $mcpDir ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"
$venvPip = Join-Path $venvDir "Scripts\pip.exe"
$reqFile = Join-Path $mcpDir "requirements.txt"
$serverHttp = Join-Path $mcpDir "server_http.py"

Write-LogMessage "=== Fix-RagVenvAndService ===" -Level INFO
Write-LogMessage "AiDocRoot: $($AiDocRoot)" -Level INFO
Write-LogMessage "mcpDir: $($mcpDir)" -Level INFO
Write-LogMessage "venvPython: $($venvPython) exists=$([System.IO.File]::Exists($venvPython))" -Level INFO
Write-LogMessage "venvPip: $($venvPip) exists=$([System.IO.File]::Exists($venvPip))" -Level INFO
Write-LogMessage "server_http.py: $($serverHttp) exists=$([System.IO.File]::Exists($serverHttp))" -Level INFO

# Check installed packages
Write-LogMessage "--- Installed packages ---" -Level INFO
$pkgList = & $venvPip list 2>&1
foreach ($line in $pkgList) { Write-LogMessage "pkg: $($line)" -Level INFO }

# Try installing requirements
Write-LogMessage "--- Installing requirements ---" -Level INFO
$pipOut = & $venvPip install -r $reqFile 2>&1
$pipExit = $LASTEXITCODE
foreach ($line in $pipOut) { Write-LogMessage "pip: $($line)" -Level INFO }
Write-LogMessage "pip exit: $($pipExit)" -Level INFO

if ($pipExit -ne 0) {
    Write-LogMessage "pip failed. Trying with --no-build-isolation" -Level WARN
    $pipOut2 = & $venvPip install --no-build-isolation -r $reqFile 2>&1
    $pipExit2 = $LASTEXITCODE
    foreach ($line in $pipOut2) { Write-LogMessage "pip2: $($line)" -Level INFO }
    Write-LogMessage "pip2 exit: $($pipExit2)" -Level INFO
}

# Check service binary path
Write-LogMessage "--- Service config ---" -Level INFO
$svcInfo = sc.exe qc $ServiceName 2>&1
foreach ($line in $svcInfo) { Write-LogMessage "sc: $($line)" -Level INFO }

# Try to start the service
Write-LogMessage "--- Attempting service start ---" -Level INFO
try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 5
    $svc = Get-Service -Name $ServiceName
    Write-LogMessage "Service status: $($svc.Status)" -Level INFO
} catch {
    Write-LogMessage "Start failed: $($_.Exception.Message)" -Level ERROR
}

# Check Windows Event Log for service errors
Write-LogMessage "--- Recent event log entries ---" -Level INFO
$events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Level=2; StartTime=(Get-Date).AddMinutes(-5)} -MaxEvents 5 -ErrorAction SilentlyContinue
if ($events) {
    foreach ($ev in $events) { Write-LogMessage "evt: $($ev.Message)" -Level INFO }
} else {
    Write-LogMessage "No recent SCM error events" -Level INFO
}

Write-LogMessage "=== Fix-RagVenvAndService done ===" -Level INFO
