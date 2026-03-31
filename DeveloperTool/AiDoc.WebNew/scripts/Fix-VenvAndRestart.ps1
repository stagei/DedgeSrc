$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force

Write-LogMessage "=== Fix-VenvAndRestart ===" -Level JOB_STARTED

# 1. Stop all RAG services to release file locks
foreach ($svc in @('AiDocRagDb2', 'AiDocRagCobol', 'AiDocRagCode')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') {
        Write-LogMessage "Stopping $($svc)..." -Level INFO
        Stop-Service -Name $svc -Force
        Start-Sleep -Seconds 2
    }
}

# Kill any leftover python processes on RAG ports
foreach ($port in @(8484, 8485, 8486)) {
    try {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}
Start-Sleep -Seconds 3

# 2. Delete old broken venv
# Use cmd /c rmdir /s /q — more reliable than Remove-Item -Recurse -Force on Windows
# (Remove-Item can fail with "directory not empty" on deep trees with locked files)
$venvDir = Join-Path $env:OptPath 'DedgeWinApps\AiDocNew-Web\python\.venv'
if (Test-Path $venvDir) {
    Write-LogMessage "Deleting old venv at $($venvDir)..." -Level INFO
    & cmd /c "rmdir /s /q `"$venvDir`""
    if (Test-Path $venvDir) {
        Write-LogMessage "rmdir /s /q did not fully remove venv; retrying..." -Level WARN
        Start-Sleep -Seconds 2
        & cmd /c "rmdir /s /q `"$venvDir`""
    }
    if (Test-Path $venvDir) {
        Write-LogMessage "WARNING: venv directory still exists after cleanup. Proceeding anyway." -Level WARN
    } else {
        Write-LogMessage "Old venv deleted" -Level INFO
    }
}

# 3. Recreate venv using _install.ps1
$installScript = Join-Path $env:OptPath 'DedgeWinApps\AiDocNew-Web\_install.ps1'
Write-LogMessage "Running _install.ps1..." -Level INFO
& $installScript
Write-LogMessage "_install.ps1 completed" -Level INFO

# 4. Restart RAG services
foreach ($svc in @('AiDocRagDb2', 'AiDocRagCobol', 'AiDocRagCode')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Write-LogMessage "Starting $($svc)..." -Level INFO
        Start-Service -Name $svc
        Start-Sleep -Seconds 2
        $status = (Get-Service -Name $svc).Status
        Write-LogMessage "$($svc): $($status)" -Level INFO
    } else {
        Write-LogMessage "$($svc) not found, skipping" -Level WARN
    }
}

# 5. Deep readiness check — /ready verifies chromadb collection is actually openable
#    (unlike /health which only confirms the process is alive)
Start-Sleep -Seconds 5
foreach ($port in @(8484, 8485, 8486)) {
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:$($port)/ready" -TimeoutSec 15
        if ($r.ready) {
            Write-LogMessage "Port $($port): READY (rag=$($r.rag))" -Level INFO
        } else {
            Write-LogMessage "Port $($port): NOT READY - $($r.error)" -Level WARN
        }
    } catch {
        Write-LogMessage "Port $($port): FAILED - $($_.Exception.Message)" -Level WARN
    }
}

Write-LogMessage "=== Fix-VenvAndRestart complete ===" -Level JOB_COMPLETED
