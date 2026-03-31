Import-Module GlobalFunctions -Force
Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

function Test-CodeIsExecutingScript {
    [CmdletBinding()]
    param()

    $codeProcesses = @(Get-Process -Name "code" -ErrorAction SilentlyContinue)
    if (-not $codeProcesses) {
        return $false
    }

    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    if (-not $allProcesses) {
        return $false
    }

    $codeTreeProcessIds = @($codeProcesses | ForEach-Object { $_.Id })
    $changed = $true

    while ($changed) {
        $changed = $false
        foreach ($process in $allProcesses) {
            if ($process.ParentProcessId -in $codeTreeProcessIds -and $process.ProcessId -notin $codeTreeProcessIds) {
                $codeTreeProcessIds += $process.ProcessId
                $changed = $true
            }
        }
    }

    $pwshTerminals = @(
        $allProcesses |
            Where-Object { $_.Name -eq "pwsh.exe" -and $_.ProcessId -in $codeTreeProcessIds }
    )

    foreach ($pwshTerminal in $pwshTerminals) {
        $terminalChildren = @($allProcesses | Where-Object { $_.ParentProcessId -eq $pwshTerminal.ProcessId })
        if ($terminalChildren.Count -gt 0) {
            Write-LogMessage "Detected active command under VS Code terminal (pwsh PID $($pwshTerminal.ProcessId)); skipping code process termination" -Level WARN
            return $true
        }
    }

    return $false
}


try {
    Set-ServerInfoWallpaper
    Write-LogMessage "Successfully set server info wallpaper" -Level INFO
}
catch {
    Write-LogMessage "Failed to set wallpaper" -Level ERROR -Exception $_
    $failCounter++
}

# Kill VSCode and Edge processes (uses Infrastructure module function)
if (Test-CodeIsExecutingScript) {
    Write-LogMessage "Skipping VS Code shutdown because script execution appears active" -Level WARN
}
else {
    Stop-ProcessTree -ProcessName "code"
}
Stop-ProcessTree -ProcessName "msedge"
# Close File Explorer windows without killing the shell (uses Infrastructure module function)
$explorerResult = Close-ExplorerWindows
if (-not $explorerResult.Success) {
    $failCounter++
}

# Remove all scheduled tasks
try {
    $tasks = @(
        [pscustomobject]@{ TaskName = "agent"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "ServerMonitorAgent"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "ServerMonitorDashBoard"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "PortCheckTool"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "Agent-HandlerAutoDeploy"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "Agent-HandlerAutoDeploy"}
        [pscustomobject]@{ TaskName = "ServerMonitor-StopFileWatcher"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "Install-ServerMonitorService"; TaskFolder = "DevTools" }
        [pscustomobject]@{ TaskName = "Install-ServerMonitorDashboard"; TaskFolder = "DevTools" }
    )

    foreach ($task in $tasks) {
        Stop-ScheduledTask -TaskName $task.TaskName -TaskFolder $task.TaskFolder

        Remove-ScheduledTask -TaskName $task.TaskName -TaskFolder $task.TaskFolder
    }
}
catch {
    Write-LogMessage "Failed to remove tasks" -Level ERROR -Exception $_
    $failCounter++
}

# Install PshApps based on computer name patterns (uses PowerShell -like operator)
# Pattern examples:
#   "*-db"              = ends with -db (e.g., p-no1fkmprd-db, t-no1fkxtst-db)
#   "p-*"               = starts with p- (all production servers)
#   "t-*"               = starts with t- (all test servers)
#   "*batch*"           = contains 'batch' anywhere (e.g., p-no1batch-vm01)
#   "*fkm*-db"          = contains 'fkm' and ends with -db (e.g., p-no1fkmprd-db)
#   "p-no1fkmprd-db"    = exact match (only this specific server)
#   "*-app"             = ends with -app (all app servers)
#   "[pt]-*"            = starts with p- or t- (production or test)
#   "*-vm??"            = ends with -vm followed by 2 chars (e.g., p-no1batch-vm01)
#   "*"                 = matches all servers
# AppType: PshApp = Install-OurPshApp, WinApp = Install-OurWinApp. DisplayName optional for WinApp.


# Kill VSCode and Edge processes (uses Infrastructure module function)
if (Test-CodeIsExecutingScript) {
    Write-LogMessage "Skipping VS Code shutdown because script execution appears active" -Level WARN
}
else {
    Stop-ProcessTree -ProcessName "code"
}
Stop-ProcessTree -ProcessName "msedge"


# Close File Explorer windows without killing the shell (uses Infrastructure module function)
$explorerResult = Close-ExplorerWindows
if (-not $explorerResult.Success) {
    $failCounter++
}

# try {
#     $appsToInstall = @(
#         # [pscustomobject]@{ AppName = "Server-Restart"; ComputerPattern = "*-db"; AppType = "PshApp" }
#         [pscustomobject]@{ AppName = "ServerMonitorAgent"; ComputerPattern = $(Get-ValidServerNameList); AppType = "WinApp" }
#     )

#     foreach ($app in $appsToInstall) {
#         if ($app.ComputerPattern -and $env:COMPUTERNAME -like $app.ComputerPattern) {
#             $appType = if ($app.AppType) { $app.AppType } else { "PshApp" }
#             switch ($appType) {
#                 "PshApp" {
#                     Install-OurPshApp -AppName $app.AppName
#                 }
#                 "WinApp" {
#                     Install-OurWinApp -AppName $app.AppName
#                 }
#                 default {
#                     Write-LogMessage "Unknown AppType '$appType' for $($app.AppName), skipping" -Level WARN
#                     continue
#                 }
#             }
#             Write-LogMessage "Installed $($app.AppName) ($appType, matched pattern: $($app.ComputerPattern))" -Level INFO
#         }
#         else {
#             Write-LogMessage "Skipping $($app.AppName) - computer name does not match pattern '$($app.ComputerPattern)'" -Level INFO
#         }
#     }
# }
# catch {
#     Write-LogMessage "Failed to install PshApps/WinApps" -Level ERROR -Exception $_
#     $failCounter++
# }



# if (Test-IsServer) {
#     try {
#         Start-OurPshApp -AppName "ServerMonitorAgent"
#         Write-LogMessage "Successfully started ServerMonitorAgent" -Level INFO
#     }
#     catch {
#         Write-LogMessage "Failed to start ServerMonitorAgent" -Level ERROR -Exception $_
#         $failCounter++
#     }
# }



# if ($(Test-IsDb2Server) -and ($(Get-EnvironmentFromServerName) -eq "RAP" -or $(Get-EnvironmentFromServerName) -eq "PRD")) {
#     try {
#         Install-OurPshApp -AppName "Server-Restart"
#         Write-LogMessage "Successfully installed Server-Restart" -Level INFO
#     }
#     catch {
#         Write-LogMessage "Failed to install Server-Restart" -Level ERROR -Exception $_
#     }
# }
try {
    # Test global environment settings for current environment
    $filePath = Join-Path $env:OptPath "DedgePshApps\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
    Start-TestGlobalEnvironmentSettings -FilePath $filePath

    # Special handling for Forsprang environments
    if ($env:COMPUTERNAME -like "*fsp*") {
        $arrayOfFilePaths = @()
        $arrayOfFilePaths += Join-Path $env:OptPath "DedgePshApps\_KAT\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
        $arrayOfFilePaths += Join-Path $env:OptPath "DedgePshApps\_FUT\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
        $arrayOfFilePaths += Join-Path $env:OptPath "DedgePshApps\_VFK\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
        $arrayOfFilePaths += Join-Path $env:OptPath "DedgePshApps\_VFT\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
        $arrayOfFilePaths += Join-Path $env:OptPath "DedgePshApps\_PER\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
        # Test global  test global environment settings for all environments
        foreach ($filePath in $arrayOfFilePaths) {
            try {
                Start-TestGlobalEnvironmentSettings -FilePath $filePath
            }
            catch {
                Write-LogMessage "Failed to test global environment settings for $($filePath)" -Level ERROR -Exception $_
            }
        }
    }
}
catch {
    Write-LogMessage "Failed to test global environment settings" -Level ERROR -Exception $_
    $failCounter++
}

try {
    Set-EditorConfiguration -AppName "Microsoft.VisualStudioCode"
    Write-LogMessage "Successfully set editor configuration" -Level INFO
}
catch {
    Write-LogMessage "Failed to set editor configuration" -Level WARN
}

$failCounter = 0

Write-LogMessage "Starting Refresh-ServerSettings script" -Level INFO



try {
    Save-ScheduledTaskFiles
    Write-LogMessage "Successfully saved scheduled task files" -Level INFO
}
catch {
    Write-LogMessage "Failed to save scheduled task files" -Level ERROR -Exception $_
    $failCounter++
}

# Run the Entra metadata script as current user
Write-LogMessage "Running Entra User Metadata script as current user: $env:USERNAME" -Level INFO
Start-Process powershell -ArgumentList "-File $env:OptPath\DedgePshApps\Entra-GetCurrentUserMetaInfo.ps1" -Wait
Write-LogMessage "Importing Entra user metadata script" -Level INFO

# try {
#     # Check if db2admin local user exists
#     $db2AdminUser = Get-LocalUser -Name "db2admin" -ErrorAction SilentlyContinue
#     if ($db2AdminUser) {
#         Write-LogMessage "Running Entra User Metadata script as current user: $($db2AdminUser.Name)" -Level INFO
#         # Get password and create credential for db2admin user
#         $securePassword = Get-UserPasswordAsSecureString -Username "db2admin"
#         $credential = New-Object System.Management.Automation.PSCredential("db2admin", $securePassword)

#         # Run the Entra metadata script as db2admin user
#         Write-LogMessage "Running Entra metadata script as db2admin user" -Level INFO
#         Start-Process powershell -Credential $credential -ArgumentList "-File $env:OptPath\DedgePshApps\Entra-GetCurrentUserMetaInfo.ps1" -Wait
#         Write-LogMessage "DB2 Admin user exists on this system" -Level INFO
#     }
#     else {
#         Write-LogMessage "DB2 Admin user does not exist on this system" -Level INFO
#     }
# }
# catch {
#     # Log any errors checking db2admin user
#     Write-LogMessage "Failed to check for DB2 Admin user" -Level ERROR -Exception $_
#     $failCounter++
# }

# Or relative to current script's folder
# Test Get Db2nt Secret
try {
    Start-Process pwsh -ArgumentList "-File $env:OptPath\DedgePshApps\Azure-KeyVaultManager\Test-GetDb2ntSecret.ps1" -Wait
    Write-LogMessage "Successfully tested Get Db2nt Secret" -Level INFO
}
catch {
    Write-LogMessage "Failed to test Get Db2nt Secret" -Level ERROR -Exception $_
    $failCounter++
}

# try {
#     Start-Process pwsh -ArgumentList "-File $env:OptPath\DedgePshApps\Standardize-ServerConfig\Standardize-ServerConfig.ps1" 
#     Write-LogMessage "Successfully standardized server config" -Level INFO
# }
# catch {
#     Write-LogMessage "Failed to standardize server config" -Level ERROR -Exception $_
#     $failCounter++
# }

if ($failCounter -gt 0) {
    Write-LogMessage "Refresh-ServerSettings script completed with $failCounter failures" -Level ERROR
}
else {
    Write-LogMessage "Refresh-ServerSettings script completed successfully" -Level INFO
}

exit $failCounter

