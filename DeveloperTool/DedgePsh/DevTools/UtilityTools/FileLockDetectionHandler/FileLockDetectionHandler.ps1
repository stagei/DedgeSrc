[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [switch]$Recurse
)

#Requires -RunAsAdministrator

function Initialize-HandleUtility {
    $handlePath = Join-Path $env:OptPath "Programs" "SysinternalsSuite" "handle64.exe"

    if (-not (Test-Path $handlePath) -and -not (Test-IsServer)) {
        Write-Host "Downloading Handle utility from Sysinternals..."
        $url = "https://download.sysinternals.com/files/Handle.zip"
        $zipPath = Join-Path $env:TEMP "Handle.zip"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zipPath
            Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
            Remove-Item $zipPath -Force

            # Accept EULA
            & $handlePath -accepteula -nobanner -a 2>&1 | Out-Null
        }
        catch {
            Write-Error "Failed to download or extract Handle utility: $_"
            throw
        }
    }

    if (-not (Test-Path $handlePath)) {
        Write-Error "Handle utility not found at expected location: $handlePath"
        throw "Handle utility not found"
    }

    Write-Verbose "Using Handle utility from: $handlePath"
    return $handlePath
}

function Get-ProcessWithOpenFile {
    param (
        [string]$FilePath
    )

    try {
        $query = "SELECT * FROM Win32_Process"
        $processes = Get-CimInstance -Query $query

        foreach ($process in $processes) {
            try {
                $handles = Get-CimInstance -Query "SELECT * FROM Win32_Handle WHERE ProcessId='$($process.ProcessId)'"
                foreach ($handle in $handles) {
                    if ($handle.Name -eq $FilePath) {
                        return $process
                    }
                }
            }
            catch {
                continue
            }
        }
    }
    catch {
        Write-Verbose "WMI query failed: $_"
    }
    return $null
}

function Test-FileLock {
    param (
        [string]$Path
    )

    $locked = $false
    $stream = $null

    try {
        $stream = [System.IO.File]::Open($Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException] {
        $locked = $true
    }
    finally {
        if ($stream) {
            $stream.Close()
            $stream.Dispose()
        }
    }

    return $locked
}

function Get-LockedFiles {
    param (
        [string]$Path,
        [bool]$Recurse
    )

    $handleExe = Initialize-HandleUtility

    if (-not (Test-Path $Path)) {
        Write-Error "Specified path does not exist: $Path"
        return
    }

    $files = if ($Recurse) {
        Get-ChildItem -Path $Path -Recurse -File
    } else {
        if (Test-Path -Path $Path -PathType Container) {
            Get-ChildItem -Path $Path -File
        } else {
            Get-Item -Path $Path
        }
    }

    $lockedFiles = @()
    $index = 1

    foreach ($file in $files) {
        Write-Verbose "Checking file: $($file.FullName)"

        if (Test-FileLock -Path $file.FullName) {
            Write-Verbose "Found locked file: $($file.FullName)"

            # First try using handle.exe with full path
            Write-Verbose "Trying handle.exe..."
            $handleOutput = & $handleExe -accepteula -nobanner -a $file.FullName 2>&1
            $foundProcess = $false

            Write-Verbose "Handle output: $($handleOutput -join "`n")"

            if ($handleOutput -notmatch "No matching handles found") {
                foreach ($line in $handleOutput) {
                    Write-Verbose "Processing handle output: $line"
                    if ($line -match "(?<proc>.+?)\s+pid:\s+(?<pid>\d+)\s+type:\s+(?<type>\w+)\s+\w+:\s+(?<handle>.+)") {
                        try {
                            $process = Get-Process -Id $Matches.pid -ErrorAction SilentlyContinue
                            if ($process) {
                                try {
                                    $owner = $process.GetOwner().User
                                }
                                catch {
                                    $owner = "Unknown"
                                }

                                $lockInfo = [PSCustomObject]@{
                                    Index = $index
                                    FileName = $file.Name
                                    FilePath = $file.FullName
                                    ProcessName = $process.ProcessName
                                    ProcessId = $Matches.pid
                                    LockType = $Matches.type
                                    Handle = $Matches.handle
                                    LastWriteTime = $file.LastWriteTime
                                    Owner = $owner
                                    MachineName = $env:COMPUTERNAME
                                    UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                                }

                                Write-Verbose "Found locking process: $($process.ProcessName) (PID: $($Matches.pid))"
                                $lockedFiles += $lockInfo
                                $index++
                                $foundProcess = $true
                            }
                        }
                        catch {
                            Write-Verbose "Error getting process details: $_"
                        }
                    }
                }
            }

            # If handle.exe didn't find anything, try using tasklist
            if (-not $foundProcess) {
                Write-Verbose "Trying tasklist..."
                $tasklistOutput = tasklist /FI "MODULES eq $($file.Name)" /FO CSV | ConvertFrom-Csv
                Write-Verbose "Tasklist output: $($tasklistOutput | ConvertTo-Json)"

                foreach ($task in $tasklistOutput) {
                    try {
                        $processId = [int]($task.'PID')
                        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue

                        if ($process) {
                            try {
                                $owner = $process.GetOwner().User
                            }
                            catch {
                                $owner = "Unknown"
                            }

                            $lockInfo = [PSCustomObject]@{
                                Index = $index
                                FileName = $file.Name
                                FilePath = $file.FullName
                                ProcessName = $process.ProcessName
                                ProcessId = $processId
                                LockType = "File"
                                Handle = "N/A"
                                LastWriteTime = $file.LastWriteTime
                                Owner = $owner
                                MachineName = $env:COMPUTERNAME
                                UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                            }

                            Write-Verbose "Found locking process through tasklist: $($process.ProcessName) (PID: $processId)"
                            $lockedFiles += $lockInfo
                            $index++
                            $foundProcess = $true
                        }
                    }
                    catch {
                        Write-Verbose "Error processing tasklist output: $_"
                    }
                }
            }

            # If we still haven't found the process, try one more method
            if (-not $foundProcess) {
                Write-Verbose "Trying to find process by enumerating all processes..."
                Get-Process | ForEach-Object {
                    try {
                        $proc = $_
                        $proc.Modules | Where-Object { $_.FileName -eq $file.FullName } | ForEach-Object {
                            try {
                                $owner = $proc.GetOwner().User
                            }
                            catch {
                                $owner = "Unknown"
                            }

                            $lockInfo = [PSCustomObject]@{
                                Index = $index
                                FileName = $file.Name
                                FilePath = $file.FullName
                                ProcessName = $proc.ProcessName
                                ProcessId = $proc.Id
                                LockType = "Module"
                                Handle = "N/A"
                                LastWriteTime = $file.LastWriteTime
                                Owner = $owner
                                MachineName = $env:COMPUTERNAME
                                UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                            }

                            Write-Verbose "Found locking process through module enumeration: $($proc.ProcessName) (PID: $($proc.Id))"
                            $lockedFiles += $lockInfo
                            $index++
                            $foundProcess = $true
                        }
                    }
                    catch {
                        Write-Verbose "Error checking process modules: $_"
                    }
                }
            }

            # If we still haven't found the process, add an unknown entry
            if (-not $foundProcess) {
                Write-Verbose "Could not determine locking process, adding unknown entry"
                $lockInfo = [PSCustomObject]@{
                    Index = $index
                    FileName = $file.Name
                    FilePath = $file.FullName
                    ProcessName = "Unknown"
                    ProcessId = 0
                    LockType = "Unknown"
                    Handle = "N/A"
                    LastWriteTime = $file.LastWriteTime
                    Owner = "Unknown"
                    MachineName = $env:COMPUTERNAME
                    UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                }

                $lockedFiles += $lockInfo
                $index++
            }
        }
    }

    return $lockedFiles
}

function Remove-FileLock {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$LockInfo
    )

    $handleExe = Initialize-HandleUtility

    Write-Host "`nAttempting to unlock file: $($LockInfo.FileName)"
    Write-Host "Process: $($LockInfo.ProcessName) (PID: $($LockInfo.ProcessId))"

    $confirmation = Read-Host "Are you sure you want to unlock this file? (Y/N)"
    if ($confirmation -eq 'Y') {
        try {
            & $handleExe -c $LockInfo.Handle -p $LockInfo.ProcessId -y
            Write-Host "File lock has been successfully removed." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to remove file lock: $_"
        }
    }
    else {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    }
}

# Main execution
try {
    Write-Host "Scanning for locked files..." -ForegroundColor Cyan
    $lockedFiles = Get-LockedFiles -Path $Path -Recurse $Recurse

    if ($lockedFiles.Count -eq 0) {
        Write-Host "No locked files found." -ForegroundColor Green
        return
    }

    Write-Host "`nLocked Files Report:" -ForegroundColor Cyan
    $lockedFiles | Format-Table -AutoSize -Property Index, FileName, ProcessName, ProcessId, LockType, Owner, MachineName, UserName, Handle

    do {
        Write-Host "`nOptions:"
        Write-Host "1. Unlock a file (enter the index number)"
        Write-Host "Q. Quit"

        $choice = Read-Host "`nEnter your choice"

        if ($choice -eq 'Q') {
            break
        }

        if ($choice -match '^\d+$') {
            $selectedFile = $lockedFiles | Where-Object { $_.Index -eq $choice }
            if ($selectedFile) {
                Remove-FileLock -LockInfo $selectedFile
            }
            else {
                Write-Host "Invalid index number." -ForegroundColor Yellow
            }
        }
    } while ($true)
}
catch {
    Write-Error "An error occurred: $_"
}

