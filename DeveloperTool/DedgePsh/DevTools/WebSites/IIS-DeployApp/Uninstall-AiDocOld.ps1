<#
.SYNOPSIS
    Removes the old AiDoc web app completely from the server (IIS + Windows service + files).
.DESCRIPTION
    - Runs IIS-UninstallApp -SiteName AiDoc -RemoveFiles -Force
    - Stops and deletes AiDoc-Web Windows service via sc.exe
    - Deletes staging folder \\server\DedgeCommon\Software\DedgeWinApps\AiDoc-Web
    Does NOT remove RAG HTTP services (db2-docs, visual-cobol-docs, Dedge-code).
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-AiDocOld.ps1
#>

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force
Import-Module IIS-Handler -Force
Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "Uninstall-AiDocOld" -Level JOB_STARTED

try {
    # 1. Stop and delete AiDoc-Web Windows service FIRST (avoids file locks)
    $svcName = "AiDoc-Web"
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-LogMessage "Step 2: Stopping and deleting service $($svcName)" -Level INFO
        if ($svc.Status -eq "Running") {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        $scResult = & sc.exe delete $svcName 2>&1 | Out-String
        Write-LogMessage "sc delete $($svcName): $($scResult.Trim())" -Level INFO
    } else {
        Write-LogMessage "Step 2: Service $($svcName) not found, skipping" -Level INFO
    }

    # 3. Delete staging folder (source for Install-OurWinApp)
    $stagingPath = Join-Path $env:OptPath "DedgeWinApps\AiDoc-Web"
    if (Test-Path $stagingPath) {
        Write-LogMessage "Step 3: Deleting staging folder: $($stagingPath)" -Level INFO
        Remove-Item -Path $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Staging folder deleted" -Level INFO
    } else {
        $DedgeCommonPath = "\\$($env:COMPUTERNAME)\DedgeCommon\Software\DedgeWinApps\AiDoc-Web"
        if (Test-Path $DedgeCommonPath) {
            Write-LogMessage "Step 3: Deleting DedgeCommon staging: $($DedgeCommonPath)" -Level INFO
            Remove-Item -Path $DedgeCommonPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-LogMessage "Staging path not found at $($stagingPath), skipped" -Level INFO
    }

    Write-LogMessage "Uninstall-AiDocOld" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "Uninstall-AiDocOld" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
