# Get installed programs
function Get-InstalledPrograms {
    $programs = @()

    # Get regular programs
    if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*") {
        $programs += Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    }

    # Get 32-bit programs on 64-bit systems
    if (Test-Path "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*") {
        $programs += Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    }

    # Get user-installed programs
    if (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*") {
        $programs += Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    }

    # Filter out entries without DisplayName and sort them
    return $programs | Where-Object DisplayName -ne $null | Sort-Object DisplayName
}

function Remove-RegistryEntry {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Program
    )

    try {
        # Determine registry path
        $regPath = $Program.PSPath

        if ($regPath) {
            Write-Host "Removing registry entry for: $($Program.DisplayName)" -ForegroundColor Yellow
            Remove-Item -Path $regPath -Force
            Write-Host "Registry entry removed successfully." -ForegroundColor Green
            return $true
        } else {
            Write-Host "Could not determine registry path." -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error removing registry entry: $_" -ForegroundColor Red
        return $false
    }
}

function Show-UninstallMenu {
    param (
        [string]$NameFilter = ""
    )

    Clear-Host
    Write-Host "=== Program Uninstaller ===" -ForegroundColor Cyan
    Write-Host "Loading installed programs..." -ForegroundColor Yellow

    $installedPrograms = Get-InstalledPrograms
    $validPrograms = @()

    # Apply name filter if provided
    if ($NameFilter) {
        Write-Host "Filter active: '$NameFilter'" -ForegroundColor Yellow
        $installedPrograms = $installedPrograms | Where-Object { $_.DisplayName -like "*$NameFilter*" }
    }

    # Display programs with numbers
    $index = 1
    foreach ($program in $installedPrograms) {
        if ($program.DisplayName -and $program.UninstallString) {
            $fileExists = $true
            if ($program.DisplayName -like "*DB2*") {
                Write-Host "DB2 UninstallString: $($program.UninstallString)" -ForegroundColor Yellow
                if ($program.UninstallString -match "MsiExec\.exe /X{([A-F0-9-]+)}") {
                    $guid = $matches[1]
                    Write-Host "Found MSI GUID: $guid" -ForegroundColor Yellow

                    # Look up the GUID in both 32-bit and 64-bit registry paths
                    $paths = @(
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$($guid.Replace('-',''))",
                        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$($guid.Replace('-',''))"
                    )

                    foreach ($path in $paths) {
                        if (Test-Path $path) {
                            $msiData = Get-ItemProperty -Path $path
                            Write-Host "MSI Details found in: $path" -ForegroundColor Cyan
                            $msiData | Select-Object -Property * -ExcludeProperty PS* | Format-List
                        }
                    }
                }
            }
            # Check if the uninstall path exists (for .exe based uninstallers)
            if ($program.UninstallString -notmatch "msiexec") {
                if ($program.UninstallString -match '^"([^"]+)"') {
                    $exePath = $matches[1]
                    $fileExists = Test-Path $exePath

                }
            }

            # Add a marker for potentially ghost entries
            $ghostMarker = if (-not $fileExists) { " [!]" } else { "" }

            Write-Host "$index. $($program.DisplayName) [v$($program.DisplayVersion)]$ghostMarker" -ForegroundColor White
            $validPrograms += $program
            $index++
        }
    }

    Write-Host ""
    Write-Host "F. Filter by name" -ForegroundColor Green
    if ($NameFilter) {
        Write-Host "C. Clear filter" -ForegroundColor Green
    }
    Write-Host "R. Refresh List" -ForegroundColor Green
    Write-Host "Q. Quit" -ForegroundColor Red
    Write-Host ""
    Write-Host "Note: [!] indicates the uninstall file doesn't exist (may be a registry ghost)" -ForegroundColor Yellow
    Write-Host ""

    # Get user choice
    $choice = Read-Host "Enter number to uninstall, or 'X' followed by number to remove registry entry only (F to filter, R to refresh, Q to quit)"

    if ($choice -eq "Q" -or $choice -eq "q") {
        return
    }
    elseif ($choice -eq "R" -or $choice -eq "r") {
        Show-UninstallMenu -NameFilter $NameFilter
        return
    }
    elseif ($choice -eq "F" -or $choice -eq "f") {
        $newFilter = Read-Host "Enter text to filter program names"
        if ($newFilter) {
            Show-UninstallMenu -NameFilter $newFilter
        } else {
            Write-Host "Filter cannot be empty" -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-UninstallMenu -NameFilter $NameFilter
        }
        return
    }
    elseif (($choice -eq "C" -or $choice -eq "c") -and $NameFilter) {
        Show-UninstallMenu
        return
    }

    # Handle registry entry removal (X followed by number)
    if ($choice -match '^[Xx](\d+)$') {
        $removalIndex = [int]$matches[1]

        if ($removalIndex -ge 1 -and $removalIndex -le $validPrograms.Count) {
            $selectedProgram = $validPrograms[$removalIndex-1]

            Write-Host ""
            Write-Host "You selected to REMOVE REGISTRY ENTRY ONLY for: $($selectedProgram.DisplayName)" -ForegroundColor Yellow
            $confirm = Read-Host "Are you sure you want to remove this registry entry? (Y/N)"

            if ($confirm -eq "Y" -or $confirm -eq "y") {
                $success = Remove-RegistryEntry -Program $selectedProgram

                if ($success) {
                    Write-Host "Registry entry removed. The program will no longer appear in the list." -ForegroundColor Green
                } else {
                    Write-Host "Failed to remove registry entry." -ForegroundColor Red
                }

                Read-Host "Press Enter to continue"
                Show-UninstallMenu -NameFilter $NameFilter
                return
            }

            Show-UninstallMenu -NameFilter $NameFilter
            return
        } else {
            Write-Host "Invalid number. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-UninstallMenu -NameFilter $NameFilter
            return
        }
    }

    # Validate choice is a number within range
    try {
        $choiceNum = [int]$choice
        if ($choiceNum -ge 1 -and $choiceNum -le $validPrograms.Count) {
            $selectedProgram = $validPrograms[$choiceNum-1]

            # Confirm uninstallation
            Write-Host ""
            Write-Host "You selected: $($selectedProgram.DisplayName)" -ForegroundColor Yellow
            $confirm = Read-Host "Are you sure you want to uninstall? (Y/N)"

            if ($confirm -eq "Y" -or $confirm -eq "y") {
                # Uninstall based on type
                Write-Host "Uninstalling $($selectedProgram.DisplayName)..." -ForegroundColor Cyan

                if ($selectedProgram.UninstallString -match "msiexec") {
                    # MSI uninstall - directly call msiexec without additional elevation
                    $guid = $selectedProgram.PSChildName
                    $command = "msiexec.exe /x $guid /quiet"
                    Write-Host "Running command: $command" -ForegroundColor Yellow

                    Start-Process "msiexec.exe" -ArgumentList "/x $guid" -Wait
                } else {
                    # Regular uninstall - directly launch without additional elevation
                    $uninstallCmd = $selectedProgram.UninstallString
                    # Handle potential parameters in uninstall string
                    if ($uninstallCmd -match '^"([^"]+)"(.*)$') {
                        $exe = $matches[1]
                        $myargs = $matches[2]
                        Start-Process $exe -ArgumentList $myargs -Wait
                    } else {
                        Start-Process $uninstallCmd -Wait
                    }
                }

                Write-Host "Uninstall process completed." -ForegroundColor Green
                Read-Host "Press Enter to continue"
            }
        } else {
            Write-Host "Invalid number. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }

    # Return to menu
    Show-UninstallMenu -NameFilter $NameFilter
}

# Start the menu
Show-UninstallMenu

