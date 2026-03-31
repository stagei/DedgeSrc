param()
$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force

Write-LogMessage "=== Cleanup-OldRagServices ===" -Level JOB_STARTED

# 1. Find and remove ALL old AiDocRag* NSSM/Windows services
$nssmExe = Join-Path $env:OptPath 'DedgeWinApps\nssm\nssm.exe'
$ragServiceNames = @('AiDocRag', 'AiDocRagCobol', 'AiDocRagCode', 'AiDocRagDb2', 'AiDocRagVisualCobol')

foreach ($svcName in $ragServiceNames) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-LogMessage "Found service: $($svcName) ($($svc.Status))" -Level INFO

        if ($svc.Status -eq 'Running') {
            Write-LogMessage "Stopping $($svcName)..." -Level INFO
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        # Kill any processes the NSSM service may have spawned
        $processName = $svcName
        Get-Process -Name $processName -ErrorAction SilentlyContinue | ForEach-Object {
            Write-LogMessage "Killing process $($_.Name) PID $($_.Id)" -Level INFO
            try { $_.Kill(); $_.WaitForExit(3000) } catch {}
        }

        # Remove via NSSM first, then sc.exe as fallback
        if (Test-Path $nssmExe) {
            $out = & $nssmExe remove $svcName confirm 2>&1 | Out-String
            Write-LogMessage "nssm remove $($svcName): $($out.Trim())" -Level INFO
        } else {
            $out = & sc.exe delete $svcName 2>&1 | Out-String
            Write-LogMessage "sc delete $($svcName): $($out.Trim())" -Level INFO
        }
    } else {
        Write-LogMessage "Service $($svcName) does not exist, skipping" -Level INFO
    }
}

# 2. Kill any orphan python processes on RAG ports
foreach ($port in @(8484, 8485, 8486)) {
    try {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        foreach ($conn in $conns) {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($proc) {
                Write-LogMessage "Killing orphan process on port $($port): $($proc.Name) PID $($proc.Id)" -Level INFO
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-LogMessage "Port $($port) check: $($_.Exception.Message)" -Level WARN
    }
}

# 3. Remove old AiDoc-Web service
$oldWebSvc = Get-Service -Name 'AiDoc-Web' -ErrorAction SilentlyContinue
if ($oldWebSvc) {
    Write-LogMessage "Found old service: AiDoc-Web ($($oldWebSvc.Status))" -Level INFO
    if ($oldWebSvc.Status -eq 'Running') {
        Stop-Service -Name 'AiDoc-Web' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    $out = & sc.exe delete 'AiDoc-Web' 2>&1 | Out-String
    Write-LogMessage "sc delete AiDoc-Web: $($out.Trim())" -Level INFO
}

# 4. Remove old AiDoc deploy template
$oldTemplate = Join-Path $env:OptPath 'DedgePshApps\IIS-DeployApp\templates\AiDoc_WinApp.deploy.json'
if (Test-Path $oldTemplate) {
    Remove-Item -LiteralPath $oldTemplate -Force
    Write-LogMessage "Deleted old template: $($oldTemplate)" -Level INFO
} else {
    Write-LogMessage "Old template not found, skipping" -Level INFO
}

# 5. Remove old FkPythonApps\AiDoc.Python folder
$oldPythonDir = Join-Path $env:OptPath 'FkPythonApps\AiDoc.Python'
if (Test-Path $oldPythonDir) {
    Remove-Item -LiteralPath $oldPythonDir -Recurse -Force
    Write-LogMessage "Deleted old Python folder: $($oldPythonDir)" -Level INFO
} else {
    Write-LogMessage "Old Python folder not found, skipping" -Level INFO
}

# 6. Remove old AiDoc-Web staging folder
$oldStaging = Join-Path $env:OptPath 'DedgeWinApps\AiDoc-Web'
if (Test-Path $oldStaging) {
    Remove-Item -LiteralPath $oldStaging -Recurse -Force
    Write-LogMessage "Deleted old staging: $($oldStaging)" -Level INFO
}

# 7. Remove old DedgeCommon staging
$DedgeCommonStaging = "\\$($env:COMPUTERNAME)\DedgeCommon\Software\DedgeWinApps\AiDoc-Web"
if (Test-Path $DedgeCommonStaging) {
    Remove-Item -LiteralPath $DedgeCommonStaging -Recurse -Force
    Write-LogMessage "Deleted old DedgeCommon staging: $($DedgeCommonStaging)" -Level INFO
}

# 8. Remove old RAG firewall rules
foreach ($port in @(8484, 8485, 8486)) {
    foreach ($suffix in @('_Inbound', '_Outbound')) {
        $ruleName = "AiDocRag_$($port)$($suffix)"
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -DisplayName $ruleName
            Write-LogMessage "Removed firewall rule: $($ruleName)" -Level INFO
        }
    }
}

Write-LogMessage "=== Cleanup complete ===" -Level JOB_COMPLETED
