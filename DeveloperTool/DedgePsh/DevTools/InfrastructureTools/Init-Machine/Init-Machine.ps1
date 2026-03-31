param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Other", "Fkm")]
    [string]$InstallType = "Fkm",
    [Parameter(Mandatory = $false)]
    [switch]$SkipWinInstall = $false,
    [Parameter(Mandatory = $false)]
    [bool]$UseOverrideLogPath = $true
)

Get-Module | Where-Object { $_.Path -like "*\opt\*" } | Remove-Module -Force

function Start-ModuleRefresh {
    $allModules = Get-Module -ListAvailable -Refresh
    $optModules = $allModules | Where-Object { $_.Path -like "*\opt\*" }
    # Add LastWriteTime property to each module object
    $optModules = $optModules | Select-Object *, @{
        Name       = 'LastChanged'
        Expression = {
            $modulePath = $_.Path
            if (Test-Path $modulePath) {
                (Get-Item $modulePath).LastWriteTime
            }
            else {
                $null
            }
        }
    }

    $optModules | Format-Table -AutoSize -Property Name, Path, LastChanged
}

function Set-PSModulePathLocal {
    [CmdletBinding()]
    param([bool]$IsServer = $false)
    # Build remove list across all possible drive letters to handle disk migration
    $removeSuffixes = @("\src\DedgePsh\_Modules", "\Apps\CommonModules", "\DedgePshApps\CommonModules", "\DedgePshApps\_Modules", "\psh\_Modules")
    $RemovePSModulePaths = @()
    foreach ($suffix in $removeSuffixes) {
        foreach ($drive in "C", "D", "E", "F") {
            $RemovePSModulePaths += "${drive}:\opt$suffix"
        }
    }
    $AddPSModulePaths = @("$env:OptPath\src\DedgePsh\_Modules", "$env:OptPath\DedgePshApps\CommonModules")
    $PSModulePathWork = [Environment]::GetEnvironmentVariable("PSModulePath", [EnvironmentVariableTarget]::Machine)

    # First remove paths we don't want
    $validPaths = @()
    foreach ($path in ($PSModulePathWork -split ";")) {
        $skipPath = $false
        foreach ($removePath in $RemovePSModulePaths) {
            if ($path -like "*$removePath*") {
                $skipPath = $true
                break
            }
        }
        if (-not $skipPath -and (Test-Path $path -PathType Container)) {
            $validPaths += $path
        }
    }

    foreach ($path in $AddPSModulePaths) {
        if (Test-Path $path -PathType Container) {
            $validPaths += $path
        }
    }

    # Join back into single string
    $PSModulePathWork = $validPaths -join ";"

    if ($PSModulePathWork) {
        [System.Environment]::SetEnvironmentVariable('PsModulePath', $PSModulePathWork, [System.EnvironmentVariableTarget]::Machine)
        Write-Host "Updated PSModulePath environment variable for Machine"

        $env:PSModulePath = $PSModulePathWork
        [System.Environment]::SetEnvironmentVariable('PsModulePath', $PSModulePathWork, [System.EnvironmentVariableTarget]::Process)
        Write-Host "Updated PSModulePath environment variable for Session"

        reg delete "HKCU\Environment" /v PSModulePath /f
        Write-Host "Deleted PSModulePath environment variable for User"
    }

    Write-Host "PSModulePath search order:"
    $paths = [System.Environment]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::Machine) -split ";"
    for ($i = 0; $i -lt $paths.Count; $i++) {
        Write-Host "  $($i + 1). $($paths[$i])"
    }
    Write-Host "Refresh PowerShell modules"
    Start-ModuleRefresh
    Write-Host "PSModulePath: $env:PSModulePath"
}
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
            Path          = $path.Trim().TrimEnd("\")
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
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0"
                "$env:SystemRoot\System32\OpenSSH"
                "C:\Program Files\dotnet"
                "C:\Program Files\ibm\gsk8\lib64"
                "C:\Program Files (x86)\ibm\gsk8\lib"
                "C:\DbInst\BIN"
                "C:\DbInst\FUNCTION"
                "C:\DbInst\SAMPLES\REPL"
                "C:\Program Files\Git\cmd"
                "C:\Program Files\PowerShell\7"
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
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0"
                "$env:SystemRoot\System32\OpenSSH"
                "C:\Program Files\dotnet"
                "C:\Program Files\Git\cmd"
                "C:\Program Files (x86)\IBM\SQLLIB\BIN"
                "C:\Program Files (x86)\IBM\SQLLIB\FUNCTION"
                "C:\Program Files (x86)\IBM\SQLLIB\SAMPLES\REPL"
                "C:\Program Files (x86)\ObjREXX"
                "C:\Program Files\PowerShell\7"
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
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0"
                "$env:SystemRoot\System32\OpenSSH"
                "C:\Program Files\dotnet"
                "C:\Program Files\Git\cmd"
                "C:\Program Files (x86)\IBM\SQLLIB\BIN"
                "C:\Program Files (x86)\IBM\SQLLIB\FUNCTION"
                "C:\Program Files (x86)\IBM\SQLLIB\SAMPLES\REPL"
                "C:\Program Files (x86)\ObjREXX"
                "C:\Program Files\PowerShell\7"
            )
        },
        [PSCustomObject]@{
            ComputerType = "default"
            UserPath     = @(
                "$env:SystemRoot\system32"
                "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps"
                "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin"
                "$env:USERPROFILE\.dotnet\tools"
            )
            MachinePath  = @(
                "$env:SystemRoot\system32"
                "$env:SystemRoot"
                "$env:SystemRoot\System32\Wbem"
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0"
                "$env:SystemRoot\System32\OpenSSH"
                "C:\Program Files\dotnet"
                "C:\Program Files\Git\cmd"
                "C:\Program Files (x86)\IBM\SQLLIB\BIN"
                "C:\Program Files (x86)\IBM\SQLLIB\FUNCTION"
                "C:\Program Files (x86)\IBM\SQLLIB\SAMPLES\REPL"
                "C:\Program Files\PowerShell\7"
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
    else {
        $computerType = "default"
    }

    if ($computerType) {
        Write-Host "Computer name: $computerName" -ForegroundColor Green
        Write-Host "Computer type: $computerType" -ForegroundColor Green

        $config = $pathConfigs | Where-Object { $_.ComputerType -eq $computerType }
        if (-not $config) {
            $config = $pathConfigs | Where-Object { $_.ComputerType -eq "default" }
        }

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
                $validUserPaths = ($validUserPaths | ForEach-Object { $_.Trim().TrimEnd("\") }) -join ";"
                Write-Host "User PATH: $validUserPaths" -ForegroundColor Cyan
                [Environment]::SetEnvironmentVariable('PATH', $validUserPaths, [EnvironmentVariableTarget]::User)
            }
            catch {
                Write-Host "Failed to set User PATH (requires administrator privileges): $_" -ForegroundColor Red
                throw
            }

            # Set Machine PATH (requires admin privileges)
            try {
                $validMachinePaths = ($validMachinePaths | ForEach-Object { $_.Trim().TrimEnd("\") }) -join ";"
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

function Stop-ProcessesInFolder {
    param([string]$FolderPath)

    $normalizedPath = $FolderPath.TrimEnd('\').ToLower()
    Write-Host "Stopping processes with executables or command lines in '$($normalizedPath)'..." -ForegroundColor Yellow

    # Use Stop-ProcessTree for known process names that commonly lock opt folders
    $knownProcessNames = @("pwsh", "powershell", "ServerMonitorAgent", "Cursor", "Code")
    foreach ($procName in $knownProcessNames) {
        $running = Get-Process -Name $procName -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.ToLower().StartsWith($normalizedPath) }
        if ($running) {
            Write-Host "  Found $(@($running).Count) '$($procName)' process(es) in old opt — killing tree" -ForegroundColor DarkYellow
            Stop-ProcessTree -ProcessName $procName | Out-Null
        }
    }

    # Sweep remaining processes by CIM (catches anything not in the known list)
    $killed = 0
    try {
        $wmiProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.ExecutablePath -and $_.ExecutablePath.ToLower().StartsWith($normalizedPath)) -or
                ($_.CommandLine -and $_.CommandLine.ToLower().Contains($normalizedPath))
            }

        foreach ($proc in $wmiProcesses) {
            $currentPid = [int]$proc.ProcessId
            if ($currentPid -eq $PID) { continue }
            try {
                $psProc = Get-Process -Id $currentPid -ErrorAction SilentlyContinue
                if ($psProc) {
                    Write-Host "  Killing remaining PID $($currentPid): $($proc.Name)" -ForegroundColor DarkYellow
                    $psProc | Stop-Process -Force -ErrorAction SilentlyContinue
                    $killed++
                }
            }
            catch { }
        }
    }
    catch {
        Write-Host "  Warning: Could not enumerate processes via CIM — $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    if ($killed -gt 0) {
        Write-Host "  Killed $killed additional process(es). Waiting 3 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}

function Disable-ScheduledTasksInFolder {
    param([string]$FolderPath)

    $normalizedPath = $FolderPath.TrimEnd('\').ToLower()
    $disabledTasks = @()

    try {
        $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne 'Disabled' }

        foreach ($task in $allTasks) {
            try {
                $actions = $task.Actions
                foreach ($action in $actions) {
                    $exe = if ($action.Execute) { $action.Execute.ToLower() } else { "" }
                    $args = if ($action.Arguments) { $action.Arguments.ToLower() } else { "" }
                    $workDir = if ($action.WorkingDirectory) { $action.WorkingDirectory.ToLower() } else { "" }
                    if ($exe.Contains($normalizedPath) -or $args.Contains($normalizedPath) -or $workDir.Contains($normalizedPath)) {
                        $taskFullName = "$($task.TaskPath)$($task.TaskName)"
                        Write-Host "  Disabling scheduled task: $($taskFullName)" -ForegroundColor DarkYellow
                        $task | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                        $disabledTasks += $taskFullName
                        break
                    }
                }
            }
            catch { }
        }
    }
    catch {
        Write-Host "  Warning: Could not enumerate scheduled tasks — $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    if ($disabledTasks.Count -gt 0) {
        Write-Host "  Disabled $($disabledTasks.Count) scheduled task(s) referencing '$($normalizedPath)'" -ForegroundColor Yellow
    }
    else {
        Write-Host "  No scheduled tasks reference '$($normalizedPath)'" -ForegroundColor Green
    }

    return $disabledTasks
}

function Enable-ScheduledTasksByName {
    param([string[]]$TaskNames)

    if (-not $TaskNames -or $TaskNames.Count -eq 0) { return }

    foreach ($taskFullName in $TaskNames) {
        try {
            $parts = $taskFullName -split '(?<=\\)(?=[^\\]+$)'
            $taskPath = $parts[0]
            $taskName = $parts[1]
            $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {
                $task | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  Re-enabled scheduled task: $($taskFullName)" -ForegroundColor Green
            }
            else {
                Write-Host "  Scheduled task no longer exists (skipping): $($taskFullName)" -ForegroundColor DarkYellow
            }
        }
        catch {
            Write-Host "  Failed to re-enable task '$($taskFullName)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

$script:disabledScheduledTasks = @()

function Move-OptFolder {
    param (
        [string]$OldOptPath,
        [string]$OptPath
    )

    $tasksBefore = Disable-ScheduledTasksInFolder -FolderPath $OldOptPath
    if ($tasksBefore.Count -gt 0) {
        $script:disabledScheduledTasks += $tasksBefore
    }

    Stop-ProcessesInFolder -FolderPath $OldOptPath

    # Ensure CWD is not inside the source path — a directory lock prevents /MOVE from deleting it
    $cwd = (Get-Location).Path.TrimEnd('\').ToLower()
    $normalizedOld = $OldOptPath.TrimEnd('\').ToLower()
    if ($cwd.StartsWith($normalizedOld)) {
        Write-Host "  Relocating CWD from $((Get-Location).Path) to $($env:SystemRoot)" -ForegroundColor Yellow
        Set-Location $env:SystemRoot
    }

    $robocopyArgs = @($OldOptPath, $OptPath, "/E", "/MOVE", "/R:3", "/W:5", "/NP")
    $result = Start-Process -FilePath "$env:SystemRoot\System32\robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow

    if ($result.ExitCode -le 1) {
        Write-Host "Successfully moved $OldOptPath to $OptPath" -ForegroundColor Green
    }
    else {
        Write-Host "Error moving $OldOptPath to $OptPath. Error level: $($result.ExitCode)" -ForegroundColor Red
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or higher. Please upgrade to PowerShell 7 or higher." -ForegroundColor Red
    exit
}
else {
    Write-Host "PowerShell 7 or higher is installed" -ForegroundColor Green
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Please restart PowerShell as Administrator." -ForegroundColor Red
    exit
}
###############################################################################################
# Main script
###############################################################################################
Write-Host ("=" * 75)
Write-Host "Dedge Computer Setup - Configuring initial settings..." -ForegroundColor Green
Write-Host ("=" * 75)
Write-Host ""

# Get operating system name using CIM
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Host "Operating System: $($osInfo.Caption)" -ForegroundColor Cyan
Write-Host ""
if ($osInfo.Caption -like "*Server*") {
    $isServer = $true
}
else {
    $isServer = $false
}

[System.Environment]::SetEnvironmentVariable('IsServer', $isServer, [System.EnvironmentVariableTarget]::Machine)
$env:IsServer = $isServer
Write-Host "Set temporary IsServer environment variable to: $isServer"
Write-Host ""

# Remove misplaced DedgePshApps folders on drive roots (bug from workstation init)
foreach ($drive in "C", "D", "E", "F") {
    $strayPath = "${drive}:\DedgePshApps"
    if (Test-Path $strayPath) {
        Write-Host "Found misplaced folder $strayPath — removing" -ForegroundColor Yellow
        Remove-Item -Path $strayPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $strayPath) {
            Write-Host "WARNING: Could not remove $strayPath" -ForegroundColor Red
        }
        else {
            Write-Host "Removed $strayPath" -ForegroundColor Green
        }
    }
}

# Determine target OptPath based on machine role
if ($isServer) {
    if ($env:COMPUTERNAME.ToUpper().EndsWith('-DB')) {
        # DB servers: prefer F:\opt, fall back to E:\opt
        if (Test-Path "F:" -PathType Container) {
            $TargetOptPath = "F:\opt"
        }
        else {
            $TargetOptPath = "E:\opt"
        }
        Write-Host "DB server detected — target OptPath: $TargetOptPath" -ForegroundColor Cyan
    }
    else {
        $TargetOptPath = "E:\opt"
        Write-Host "Non-DB server detected — target OptPath: $TargetOptPath" -ForegroundColor Cyan
    }
}
else {
    $TargetOptPath = "C:\opt"
    Write-Host "Workstation detected — target OptPath: $TargetOptPath" -ForegroundColor Cyan
}

# Search for existing opt folders across drives
$optFolders = @()
foreach ($drive in "C", "D", "E", "F") {
    $optPath = "${drive}:\opt"
    if (Test-Path $optPath) {
        $optFolders += $optPath
    }
}

Write-Host "Existing opt folders: $(($optFolders | Sort-Object) -join ', ')" -ForegroundColor Cyan
Write-Host "isServer: $isServer" -ForegroundColor Cyan
Start-Sleep -Seconds 5

# Relocate CWD away from any opt folder BEFORE attempting moves or module loads.
# If the invoking shell (e.g. Cursor-ServerOrchestrator) set CWD inside an opt folder,
# that directory lock prevents Robocopy /MOVE from deleting the source.
$currentDir = (Get-Location).Path.TrimEnd('\').ToLower()
foreach ($folder in $optFolders) {
    if ($currentDir.StartsWith($folder.TrimEnd('\').ToLower())) {
        Write-Host "Current directory ($((Get-Location).Path)) is inside opt folder $folder — relocating to $($env:SystemRoot)" -ForegroundColor Yellow
        Set-Location $env:SystemRoot
        break
    }
}

$OptPath = $TargetOptPath

if ($isServer) {
    # Move any opt folders found on the wrong disk to the target location
    foreach ($folder in $optFolders) {
        if ($folder -ne $OptPath) {
            Write-Host "Misplaced opt folder at $folder — moving to $OptPath" -ForegroundColor Yellow
            Move-OptFolder -OldOptPath $folder -OptPath $OptPath
        }
    }
    if ($optFolders.Count -eq 0) {
        Write-Host "No existing opt folders found. Creating $OptPath" -ForegroundColor Yellow
    }
}
else {
    # Workstation: interactive selection if multiple folders exist
    if ($optFolders.Count -eq 1) {
        $OptPath = $optFolders[0]
    }
    elseif ($optFolders.Count -gt 1) {
        Write-Host "Multiple opt folders found:" -ForegroundColor Yellow
        $optFolders | ForEach-Object { Write-Host "  $_" }
        $OptPath = Read-Host "Enter preferred opt path (default: $TargetOptPath)"
        if ([string]::IsNullOrWhiteSpace($OptPath)) {
            $OptPath = $TargetOptPath
        }
        $OptPath = $OptPath.TrimEnd('\')
        if (-not $OptPath.EndsWith('\opt', [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "The path must end with 'opt'. Please restart the script and try again." -ForegroundColor Yellow
            exit 1
        }
        foreach ($folder in $optFolders) {
            if ($folder -ne $OptPath) {
                Move-OptFolder -OldOptPath $folder -OptPath $OptPath
            }
        }
    }
    elseif ($optFolders.Count -eq 0) {
        Write-Host "No existing opt folders found. Using $OptPath as default." -ForegroundColor Yellow
    }
}

$env:OptPath = $OptPath
Write-Host "Using OptPath: $OptPath" -ForegroundColor Green

# Remove OptPath environment variable for current user
$ClearRegistryEntries = @("PsModulePath", "OptPath", "OptUncPath", "PsWorkPath")
foreach ($entry in $ClearRegistryEntries) {
    #REG DELETE "HKEY_LOCAL_MACHINE\Environment" /f /v $entry 2>&1 | Out-Null
    $command = "$env:SystemRoot\System32\reg.exe delete "
    if ($isServer) {
        $command += "HKEY_LOCAL_MACHINE\Environment"
    }
    else {
        $command += "HKEY_CURRENT_USER\Environment"
    }
    try {
        $command += " /f /v $entry"
        $null = Invoke-Expression $command 2>$null | Out-Null
    }
    catch {
    }
}
$ClearRegistryEntries += @("DedgeCommonPath", "DedgeCommonVersion")
foreach ($entry in $ClearRegistryEntries) {
    try {
        #REG DELETE "HKEY_CURRENT_USER\Environment" /f /v $entry 2>&1 | Out-Null
        $command = "$env:SystemRoot\System32\reg.exe delete "
        if ($isServer) {
            $command += "HKEY_LOCAL_MACHINE\Environment"
        }
        else {
            $command += "HKEY_CURRENT_USER\Environment"
        }
        $command += " /f /v $entry"
        $null = Invoke-Expression $command 2>$null | Out-Null
    }
    catch {
    }
}
# Set OptPath environment variable for all users
[System.Environment]::SetEnvironmentVariable('OptPath', $OptPath, [System.EnvironmentVariableTarget]::Machine)
$env:OptPath = $OptPath

# Create base OptPath directory if it doesn't exist
Write-Host "Copying necessary files to $env:OptPath"
New-Item -Path $env:OptPath -ItemType Directory -Force | Out-Null
New-Item -Path "$env:OptPath\DedgePshApps" -ItemType Directory -Force | Out-Null

# Recreate and copy Init-Machine
Remove-Item -Path "$env:OptPath\DedgePshApps\Init-Machine" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path "$env:OptPath\DedgePshApps\Init-Machine" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
Copy-Item -Path "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\Init-Machine\*" -Destination "$env:OptPath\DedgePshApps\Init-Machine" -Recurse -Force
# Remove existing CommonModules folder if it exists
Remove-Item -Path "$env:OptPath\DedgePshApps\CommonModules" -Recurse -Force -ErrorAction SilentlyContinue

# Create CommonModules directory
New-Item -Path "$env:OptPath\DedgePshApps\CommonModules" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Copy all files and folders from network location, preserving directory structure
$sourcePath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\CommonModules"
$destPath = "$env:OptPath\DedgePshApps\CommonModules"

Copy-Item -Path "$sourcePath\*" -Destination $destPath -Recurse -Force -ErrorAction SilentlyContinue

# Update Machine PATH
$machinePath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
$machinePath = $machinePath -replace "^(C|D|E|F):\\opt", $env:OptPath
[Environment]::SetEnvironmentVariable("PATH", $machinePath, [EnvironmentVariableTarget]::Machine)
$userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
$userPath = $userPath -replace "^(C|D|E|F):\\opt", $env:OptPath
[Environment]::SetEnvironmentVariable("PATH", $userPath, [EnvironmentVariableTarget]::User)
$env:PATH = $machinePath + ";" + $userPath

if ($osInfo.Caption -like "*Server*") {
    $isServer = $true
    Write-Host "Running server configuration" -ForegroundColor Cyan
    Test-PathsAndSetValid -Force
}
else {
    $isServer = $false
    Write-Host "Running workstation configuration" -ForegroundColor Cyan
    Test-PathsAndSetValid -Force
}

# Set PSModulePath environment variable
Set-PSModulePathLocal -IsServer $isServer

# Verify modules exist before importing
$modulesToImport = @("GlobalFunctions", "Deploy-Handler", "SoftwareUtils", "ScheduledTask-Handler", "Infrastructure", "DedgeSign")
$modulesAvailable = Get-Module -ListAvailable -Refresh

# Clear any existing modules from opt path to avoid conflicts
Get-Module | Where-Object { $_.Path -like "*\opt\*" } | Where-Object { $_.Path -like "*.psm1*" } | Remove-Module -Force
$Global:GetGlobalEnvironmentSettings = $false
# Import only modules that exist
$modulesToImport = @("GlobalFunctions", "Deploy-Handler", "SoftwareUtils", "ScheduledTask-Handler", "Infrastructure", "DedgeSign")
foreach ($moduleName in $modulesToImport) {
    $moduleExists = $modulesAvailable | Where-Object { $_.Name -eq $moduleName }
    if ($moduleExists) {
        Write-Host "Importing module: $moduleName" -ForegroundColor Green
        try {
            Import-Module $moduleName -Force -ErrorAction Continue
        }
        catch {
            $modulePath = $env:OptPath + "\DedgePshApps\CommonModules\" + $moduleName + "\" + $moduleName + ".psm1"
            Import-Module $modulePath -Force -ErrorAction Stop
        }
    }
    else {
        Write-Host "Module not found: $moduleName" -ForegroundColor Yellow
    }
}
$Global:GetGlobalEnvironmentSettings = $true

# Optional: send Init-Machine logs to shared UNC with custom filename
if ($UseOverrideLogPath -and (Get-Command Set-OverrideAppDataFolder -ErrorAction SilentlyContinue)) {
    $overrideLogDir = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Software\Init-Machine'
    Set-OverrideAppDataFolder -Path $overrideLogDir
    $overrideLogFileName = '{0:yyyyMMdd-HHmm}_{1}_{2}.log' -f (Get-Date), $env:USERNAME, $env:COMPUTERNAME
    Set-OverrideLogFileName -FileName $overrideLogFileName
}

try {
    $currentUser = $env:USERDOMAIN + "\" + $env:USERNAME

    # Add network drive to common folder
    Write-Progress -Completed

    if ($InstallType -eq "Fkm") {
        if ($isServer) {
            $file = Join-Path $env:OptPath "DedgePshApps\Init-Machine\ShareOptFolderPowershell51.ps1"
            powershell.exe -File $file -Path $env:OptPath -ShareName "opt" -EveryonePermission ""
        }

        $file = Join-Path $env:OptPath "DedgePshApps\Init-Machine\SetRegionTimeCulture.ps1"
        powershell.exe -File $file

        Import-Module Infrastructure -Force

        Set-UserPasswordAsSecureString -Force
        $environments = @()
        if ($isServer) {
            if ($env:COMPUTERNAME.ToUpper().Contains('PRD')) {
                $environments += @("PRD")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('TST')) {
                $environments += @("TST")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('VCT')) {
                $environments += @("VCT")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('FSP')) {
                $environments += @("MIG")
                $environments += @("SIT")
                $environments += @("VFK")
                $environments += @("VFT")
                $environments += @("PER")
                $environments += @("FUT")
                $environments += @("KAT")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('MIG')) {
                $environments += @("MIG")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('SIT')) {
                $environments += @("SIT")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('VFK')) {
                $environments += @("VFK")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('VFT')) {
                $environments += @("VFT")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('PER')) {
                $environments += @("PER")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('FUT')) {
                $environments += @("FUT")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('KAT')) {
                $environments += @("KAT")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('DEV')) {
                $environments += @("DEV")
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains('RAP')) {
                $environments += @("RAP")
            }
            else {
                Write-LogMessage "Computer name '$($env:COMPUTERNAME)' does not match expected patterns (*prd, *tst, *vct, *dev, *rap, *mig, *sit, *vft, *vfk, *per, *fut, *kat). Aborting..." -Level ERROR
                exit 2
            }

            $applications = @()
            if ($env:COMPUTERNAME.ToUpper().Contains('FKM')) {
                $applications += @("FKM")
            }
            if ($env:COMPUTERNAME.ToUpper().Contains('INL')) {
                $applications += @("INL")
            }
            if ($env:COMPUTERNAME.ToUpper().Contains('DOC')) {
                $applications += @("DOC")
            }
            if ($env:COMPUTERNAME.ToUpper().Contains('HST')) {
                $applications += @("HST")
            }
            if ($env:COMPUTERNAME.ToUpper().Contains('VIS')) {
                $applications += @("VIS")
            }
            Add-CurrentComputer -AutoConfirm $true -Type "Server" -Environments $environments -Purpose "Server for $($environments -join ", ")" -Comments "" -Applications $applications

            Write-LogMessage "Initializing new server..." -Level INFO
            Initialize-Server -AdditionalAdmins @($currentUser, "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")

        }
        else {
            $environments = @("DEV")
            $applications = @("FKM", "INL")

            Add-CurrentComputer -AutoConfirm $true -Type "Developer Machine" -Environments $environments -Purpose "Dedge and Innlån developer workstation" -Comments "" -Applications $applications -SingleUser $true
            Write-LogMessage "Initializing new workstation..." -Level INFO
            if ($SkipWinInstall) {
                Initialize-Workstation -AdditionalAdmins @($currentUser) -SkipWinInstall $true
            }
            else {
                Initialize-Workstation -AdditionalAdmins @($currentUser) -SkipWinInstall $false
            }
        }
    }
    else {
        Write-LogMessage "Initializing new workstation..." -Level INFO
        if ($SkipWinInstall) {
            Initialize-WorkstationOther -AdditionalAdmins @($currentUser) -SkipWinInstall $true
        }
        else {
            Initialize-WorkstationOther -AdditionalAdmins @($currentUser) -SkipWinInstall $false
        }
    }
}
catch {
    Write-Host "--------------------------------------------------------------------------------------------------------------------------" -ForegroundColor White
    Write-Host "Error initializing new server:" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error Location: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host "--------------------------------------------------------------------------------------------------------------------------" -ForegroundColor White
    Write-Host "--- Module Diagnostics ---" -ForegroundColor Yellow
    Write-Host "PSModulePath: $($env:PSModulePath)" -ForegroundColor Yellow
    Write-Host "Loaded modules from opt:" -ForegroundColor Yellow
    Get-Module | Where-Object { $_.Path -like "*\opt\*" } | ForEach-Object {
        Write-Host "  $($_.Name) -> $($_.Path)" -ForegroundColor Yellow
    }
    Write-Host "GlobalFunctions available: $(($null -ne (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)))" -ForegroundColor Yellow
    Write-Host "--------------------------" -ForegroundColor Yellow
    exit 1
}

# End-of-job: verify misplaced DedgePshApps folders have not reappeared
$strayFolders = @()
foreach ($drive in "C", "D", "E", "F") {
    $strayPath = "${drive}:\DedgePshApps"
    if (Test-Path $strayPath) {
        $strayFolders += $strayPath
        Write-Host "WARNING: Misplaced folder $strayPath reappeared after init" -ForegroundColor Red
    }
}
if ($strayFolders.Count -gt 0) {
    $msg = "Init-Machine WARNING: Misplaced DedgePshApps folder(s) reappeared on $($env:COMPUTERNAME): $($strayFolders -join ', '). Bug is still present."
    Write-Host $msg -ForegroundColor Red
    try {
        if (Get-Command Send-Sms -ErrorAction SilentlyContinue) {
            $smsNumber = switch ($env:USERNAME) {
                "FKGEISTA" { "+4797188358" }
                "FKSVEERI" { "+4795762742" }
                "FKMISTA"  { "+4799348397" }
                "FKCELERI" { "+4745269945" }
                default    { "+4797188358" }
            }
            Send-Sms -Receiver $smsNumber -Message $msg
        }
    }
    catch {
        Write-Host "Failed to send SMS alert: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "Verified: No misplaced DedgePshApps folders on drive roots" -ForegroundColor Green
}

# Re-enable any scheduled tasks that were disabled during opt folder migration
if ($script:disabledScheduledTasks -and $script:disabledScheduledTasks.Count -gt 0) {
    Write-Host "Re-enabling $($script:disabledScheduledTasks.Count) scheduled task(s) disabled during opt move..." -ForegroundColor Cyan
    Enable-ScheduledTasksByName -TaskNames $script:disabledScheduledTasks
}
