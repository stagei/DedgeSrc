<#
.SYNOPSIS
    Remove old AiDoc RAG services and clean up the old FkPyApp folder.
.DESCRIPTION
    Stops and removes any Windows services whose executable path references
    FkPyApp\AiDoc, kills lingering Python processes from that path,
    and removes the old FkPyApp folder.
#>

Import-Module GlobalFunctions -Force

Write-LogMessage "=== Remove-OldRagServices starting ===" -Level INFO

# Find all services with AiDoc in the name
Write-LogMessage "Looking for AiDoc* services..." -Level INFO
$services = Get-Service -Name 'AiDoc*' -ErrorAction SilentlyContinue
if ($services) {
    foreach ($svc in $services) {
        Write-LogMessage "Found service: $($svc.Name) ($($svc.Status))" -Level INFO
        if ($svc.Status -eq 'Running') {
            Write-LogMessage "Stopping $($svc.Name)..." -Level INFO
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Write-LogMessage "Removing $($svc.Name)..." -Level INFO
        sc.exe delete $svc.Name
        Write-LogMessage "sc.exe delete result: $($LASTEXITCODE)" -Level INFO
    }
} else {
    Write-LogMessage "No AiDoc* services found." -Level INFO
}

# Kill any python processes from old FkPyApp path
Write-LogMessage "Checking for Python processes from old FkPyApp path..." -Level INFO
$oldPyProcs = Get-Process -Name python* -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -like '*FkPyApp*' }
if ($oldPyProcs) {
    foreach ($p in $oldPyProcs) {
        Write-LogMessage "Killing PID $($p.Id): $($p.Path)" -Level WARN
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
} else {
    Write-LogMessage "No Python processes from FkPyApp found." -Level INFO
}

# Also kill any python from FkPythonApps (new path) to unlock files
Write-LogMessage "Checking for Python processes from FkPythonApps path..." -Level INFO
$newPyProcs = Get-Process -Name python* -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -like '*FkPythonApps*' }
if ($newPyProcs) {
    foreach ($p in $newPyProcs) {
        Write-LogMessage "Killing PID $($p.Id): $($p.Path)" -Level WARN
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
} else {
    Write-LogMessage "No Python processes from FkPythonApps found." -Level INFO
}

# Try to remove old FkPyApp folder
if (-not $env:OptPath) {
    Write-LogMessage "OptPath not set, cannot locate old FkPyApp folder." -Level ERROR
} else {
    $oldFolder = Join-Path $env:OptPath "FkPyApp"
    Write-LogMessage "Checking for old folder: $($oldFolder)" -Level INFO
    if (Test-Path $oldFolder) {
        Write-LogMessage "Removing $($oldFolder)..." -Level WARN
        Remove-Item -Path $oldFolder -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $oldFolder) {
            Write-LogMessage "Folder still exists after Remove-Item. Some files may be locked." -Level ERROR
        } else {
            Write-LogMessage "Old FkPyApp folder removed successfully." -Level INFO
        }
    } else {
        Write-LogMessage "Old folder does not exist: $($oldFolder)" -Level INFO
    }
}

Write-LogMessage "=== Remove-OldRagServices finished ===" -Level INFO
