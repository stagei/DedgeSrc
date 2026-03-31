function Test-PathComponents {
    param([string[]]$PathArray, [string]$PathType)

    # Get existing environment variable for current type
    $existingPaths = switch ($PathType) {
        "Machine" { [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine) }
        "User" { [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User) }
        default { "" }
    }
    $combinedPaths = @()
    $existingOrder = 1
    $existingPaths = $existingPaths -split ';' | Sort-Object -Unique
    foreach ($path in $existingPaths) {
        $valid = $(Test-Path $path)
        $combinedPaths += [PSCustomObject]@{
            ExistingOrder = $existingOrder
            Valid         = $valid
            PathType      = $PathType
            Path          = $path
        }
        $existingOrder++
    }

    $pathString = $PathArray -join ";"
    $expandedPath = [Environment]::ExpandEnvironmentVariables($pathString)
    $pathComponents = $expandedPath -split ';'
    foreach ($component in $pathComponents) {
        if ($component.Trim().ToLower() -notin ($combinedPaths | ForEach-Object { $_.Path.Trim().ToLower() })) {
            $valid = $(Test-Path $component)
            $combinedPaths += [PSCustomObject]@{
                ExistingOrder = 999
                Valid         = $valid
                PathType      = $PathType
                Path          = $component
            }
        }
    }

    return $combinedPaths
}
function Test-PathsAndSetValid {
    param([switch]$Force)

    # Save current PATH environment variables to backup files
    Write-Host "Backing up current PATH environment variables..." -ForegroundColor Green

    # Create backup directory if it doesn't exist
    $backupDir = "C:\tempfk"
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }

    # Get current timestamp for filename
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # Backup Machine PATH
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
    if ($machinePath) {
        $machinePathFile = Join-Path $backupDir "MachinePath_$timestamp.txt"
        $machinePath | Out-File -FilePath $machinePathFile -Encoding UTF8
        Write-Host "  Machine PATH backed up to: $machinePathFile" -ForegroundColor Cyan
    }

    # Backup User PATH
    $userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    if ($userPath) {
        $userPathFile = Join-Path $backupDir "UserPath_$timestamp.txt"
        $userPath | Out-File -FilePath $userPathFile -Encoding UTF8
        Write-Host "  User PATH backed up to: $userPathFile" -ForegroundColor Cyan
    }
    # Get the computer name
    $computerName = $env:COMPUTERNAME

    # Define path configurations based on computer name suffix
    $pathConfigs = [pscustomobject[]] @(
        [PSCustomObject]@{
            ComputerType = "db"
            UserPath     = @(
                "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps"
                "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin"
                "$env:USERPROFILE\.dotnet\tools"
            )
            MachinePath  = @(
                "$env:SystemRoot\system32"
                "$env:SystemRoot"
                "$env:SystemRoot\System32\Wbem"
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0\"
                "$env:SystemRoot\System32\OpenSSH\"
                "C:\Program Files\dotnet\"
                "C:\Program Files\ibm\gsk8\lib64"
                "C:\Program Files (x86)\ibm\gsk8\lib"
                "C:\DbInst\BIN"
                "C:\DbInst\FUNCTION"
                "C:\DbInst\SAMPLES\REPL"
                "C:\Program Files\Git\cmd"
                "C:\Program Files\PowerShell\7\"
            )
        },
        [PSCustomObject]@{
            ComputerType = "app"
            UserPath     = @(
                "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps"
                "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin"
                "$env:USERPROFILE\.dotnet\tools"
            )
            MachinePath  = @(
                "$env:SystemRoot\system32"
                "$env:SystemRoot"
                "$env:SystemRoot\System32\Wbem"
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0\"
                "$env:SystemRoot\System32\OpenSSH\"
                "C:\Program Files\dotnet\"
                "C:\Program Files\Git\cmd"
                "C:\Program Files (x86)\IBM\SQLLIB\BIN"
                "C:\Program Files (x86)\IBM\SQLLIB\FUNCTION"
                "C:\Program Files (x86)\IBM\SQLLIB\SAMPLES\REPL"
                "C:\Program Files (x86)\ObjREXX"
                "C:\Program Files\PowerShell\7\"
            )
        },
        [PSCustomObject]@{
            ComputerType = "fkxprd-app"
            UserPath     = @(
                "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps"
                "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin"
                "$env:USERPROFILE\.dotnet\tools"
            )
            MachinePath  = @(
                "$env:SystemRoot\system32"
                "$env:SystemRoot"
                "$env:SystemRoot\System32\Wbem"
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0\"
                "$env:SystemRoot\System32\OpenSSH\"
                "C:\Program Files\dotnet\"
                "C:\Program Files\Git\cmd"
                "C:\Program Files (x86)\IBM\SQLLIB\BIN"
                "C:\Program Files (x86)\IBM\SQLLIB\FUNCTION"
                "C:\Program Files (x86)\IBM\SQLLIB\SAMPLES\REPL"
                "C:\Program Files (x86)\ObjREXX"
                "C:\Program Files\PowerShell\7\"
            )
        }
    )

    # Determine computer type based on suffix
    $computerType = $null
    if ($computerName.EndsWith("fkxprd-app")) {
        $computerType = "fkxprd-app"
    }
    elseif ($computerName.EndsWith("-app")) {
        $computerType = "app"
    }
    elseif ($computerName.EndsWith("-db")) {
        $computerType = "db"
    }
    elseif ($computerName.EndsWith("-soa")) {
        $computerType = "soa"
    }
    elseif ($computerName.EndsWith("-web")) {
        $computerType = "web"
    }
    elseif ($computerName.EndsWith("-mcl")) {
        $computerType = "mcl"
    }
    elseif ($computerName.EndsWith("-pos")) {
        $computerType = "pos"
    }

    if ($computerType) {
        Write-Host "Computer name: $computerName" -ForegroundColor Green
        Write-Host "Computer type: $computerType" -ForegroundColor Green

        $config = $pathConfigs | Where-Object { $_.ComputerType -eq $computerType }

        # Function to validate if path components exist
        $resultArray = @()
        Write-Host "`nValidating User PATH components:" -ForegroundColor Cyan
        $resultArray += Test-PathComponents -PathArray $config.UserPath -PathType "User"
        Write-Host "`nValidating Machine PATH components:" -ForegroundColor Cyan
        $resultArray += Test-PathComponents -PathArray $config.MachinePath -PathType "Machine"

        $resultArray | Sort-Object -Property PathType, ExistingOrder | ForEach-Object {
            $color = if ($_.ExistingOrder -eq 999 -and $_.Valid) { "Yellow" } elseif ($_.Valid) { "Green" } else { "Red" }
            Write-Host ("{0,-6} {1,-8} {2,-50} {3}" -f $_.Valid, $_.ExistingOrder, $_.PathType, $_.Path ) -ForegroundColor $color
        }

        if (-not $Force) {
            $response = Read-Host "`nWould you like to continue and apply these changes? (Y/N)"
            if ($response.ToUpper() -ne 'Y') {
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                return
            }
        }

        # Filter to only valid paths
        $validUserPaths = ($resultArray | Where-Object { $_.PathType -eq "User" -and $_.Valid }).Path
        $validMachinePaths = ($resultArray | Where-Object { $_.PathType -eq "Machine" -and $_.Valid }).Path

        # Set User PATH
        try {
            try {
                $validUserPaths = ($validUserPaths | ForEach-Object { $_.Trim() }) -join ";"
                Write-Host "User PATH: $validUserPaths" -ForegroundColor Cyan
                [Environment]::SetEnvironmentVariable('PATH', $validUserPaths, [EnvironmentVariableTarget]::User)
            }
            catch {
                Write-Host "Failed to set User PATH (requires administrator privileges): $_" -ForegroundColor Red
                throw
            }

            # Set Machine PATH (requires admin privileges)
            try {
                $validMachinePaths = ($validMachinePaths | ForEach-Object { $_.Trim() }) -join ";"
                Write-Host "Machine PATH: $validMachinePaths" -ForegroundColor Cyan
                [Environment]::SetEnvironmentVariable('PATH', $validMachinePaths, [EnvironmentVariableTarget]::Machine)
            }
            catch {
                Write-Host "Failed to set Machine PATH (requires administrator privileges): $_" -ForegroundColor Red
            }
            # Refresh the current session's PATH environment variable
            $env:PATH = $validUserPaths + ";" + $validMachinePaths
            Write-Host "PATH environment variable refreshed for current session" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to set PATH variables: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Computer name '$computerName' does not match expected patterns (*fkxprd-app, *-app, *-db, *-soa, *-web, *-mcl, *-pos)" -ForegroundColor Red
    }

}
Test-PathsAndSetValid -Force

