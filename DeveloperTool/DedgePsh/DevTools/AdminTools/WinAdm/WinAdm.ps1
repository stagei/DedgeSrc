# Requires administrator privileges to run
#"Requires -RunAsAdministrator
#Requires -Version 3.0

# Add these parameters at the start of the script
param(
    [string]$Choice,
    [string]$Path
)

# Add this function before Show-AdminMenu
function Start-DevTool {
    param(
        [string]$Choice,
        [string]$Path
    )

    # Validate path exists
    if (-not (Test-Path $Path)) {
        Write-Host "Path not found: $Path" -ForegroundColor Red
        exit 1
    }

    # Determine if path is file or folder
    $isFile = Test-Path $Path -PathType Leaf
    $workingDirectory = if ($isFile) { Split-Path $Path -Parent } else { $Path }

    # Set location to working directory
    Set-Location $workingDirectory

    # Start process with appropriate arguments
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.UseShellExecute = $true
    $startInfo.WorkingDirectory = $workingDirectory
    $startInfo.Verb = "runas"

    switch ($Choice) {
        "1" { $startInfo.FileName = "C:\Users\fkgeista\AppData\Local\Programs\cursor\Cursor.exe"; $startInfo.Arguments = "`"$Path`"" }
        "2" { $startInfo.FileName = "C:\Program Files\Microsoft VS Code\Code.exe"; $startInfo.Arguments = "`"$Path`"" }
        "3" { $startInfo.FileName = "powershell_ise.exe"; $startInfo.Arguments = "`"$Path`"" }
        "4" { $startInfo.FileName = "C:\Program Files\PowerShell\7\pwsh.exe"; $startInfo.Arguments = "`"$Path`"" }
        default { Write-Host "Invalid choice for direct execution." -ForegroundColor Red; return }
    }

    [System.Diagnostics.Process]::Start($startInfo)
}

# Add this before Show-AdminMenu call
if ($Choice -and $Path) {
    if ($Choice -in "1", "2", "3", "4") {
        Start-DevTool -Choice $Choice -Path $Path
        return
    }
    Write-Host "Direct execution only supported for choices 1-4" -ForegroundColor Red
    exit 1
}

function Register-CursorContextMenu {
    $cursorPath = "C:\Users\fkgeista\AppData\Local\Programs\cursor\Cursor.exe"

    if (-not (Test-Path $cursorPath)) {
        Write-Host "Cursor.exe not found at expected path. Please update the path." -ForegroundColor Red
        return
    }

    try {
        # Create registry key for all files
        $registryPath = "Registry::HKEY_CLASSES_ROOT\*\shell\OpenWithCursor"
        New-Item -Path $registryPath -Force | Out-Null
        Set-ItemProperty -Path $registryPath -Name "(Default)" -Value "Open with Cursor"

        # Set the icon from Cursor.exe
        Set-ItemProperty -Path $registryPath -Name "Icon" -Value "`"$cursorPath`""

        # Create command subkey
        $commandPath = "$registryPath\command"
        New-Item -Path $commandPath -Force | Out-Null
        Set-ItemProperty -Path $commandPath -Name "(Default)" -Value "`"$cursorPath`" `"%1`""

        Write-Host "Successfully added 'Open with Cursor' to context menu." -ForegroundColor Green
    }
    catch {
        Write-Host "Error adding context menu: $_" -ForegroundColor Red
    }
}

function Start-PowerShell7 {
    $pwsh7Path = "C:\Program Files\PowerShell\7\pwsh.exe"
    if (Test-Path $pwsh7Path) {
        Start-Process $pwsh7Path -Verb RunAs
    }
    else {
        Write-Host "PowerShell 7 not found at expected path." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Set-PowerShell7MaxWindow {
    $profilePath = "C:\Users\$env:USERNAME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    $configDir = Split-Path $profilePath -Parent

    # Create PowerShell directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Create or load existing profile
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $currentContent = Get-Content $profilePath -Raw
    $windowConfig = @'

# FKAdmin Window Size Configuration
$maxWidth = $Host.UI.RawUI.MaxWindowSize.Width
$maxHeight = $Host.UI.RawUI.MaxWindowSize.Height
$bufferWidth = [math]::Min($maxWidth * 2, 500)  # Double width but cap at 500
$Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($bufferWidth, 9999)
$Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($maxWidth, $maxHeight)
# End FKAdmin Window Size Configuration

'@

    if ($currentContent -notmatch "FKAdmin Window Size Configuration") {
        Add-Content -Path $profilePath -Value $windowConfig
        Write-Host "PowerShell 7 window size configuration added successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Configuration already exists." -ForegroundColor Green
    }
    Start-Sleep -Seconds 2
}

function Remove-PowerShell7MaxWindow {
    $profilePath = "C:\Users\$env:USERNAME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content -match "(?ms)# FKAdmin Window Size Configuration.*# End FKAdmin Window Size Configuration\s*\r?\n?") {
            $newContent = $content -replace "(?ms)# FKAdmin Window Size Configuration.*# End FKAdmin Window Size Configuration\s*\r?\n?", ""
            Set-Content -Path $profilePath -Value $newContent
            Write-Host "PowerShell 7 window size configuration removed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "No window size configuration found." -ForegroundColor Green
        }
    }
    else {
        Write-Host "PowerShell profile not found." -ForegroundColor Green
    }
    Start-Sleep -Seconds 2
}

function Start-WingetUpgrade {
    $pwsh7Path = "C:\Program Files\PowerShell\7\pwsh.exe"
    if (Test-Path $pwsh7Path) {
        Start-Process $pwsh7Path -ArgumentList "-NoExit -Command `"Write-Host 'Starting system upgrade...' -ForegroundColor Green; winget upgrade --all`"" -Verb RunAs
    }
    else {
        Start-Process powershell -ArgumentList "-NoExit -Command `"Write-Host 'Starting system upgrade...' -ForegroundColor Green; winget upgrade --all`"" -Verb RunAs
    }
}

function Start-FkAppConfig {
    $pwsh7Path = "C:\Program Files\PowerShell\7\pwsh.exe"
    if (Test-Path $pwsh7Path) {
        Start-Process $pwsh7Path -ArgumentList "-NoExit -Command `"& '$env:OptPath\src\DedgePsh\DevTools\FkAppConfig\FkAppConfig.ps1'`"" -Verb RunAs
    }
    else {
        Write-Host "PowerShell 7 not found at expected path." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

# Add this at the start of the script
$menuItems = @(
    @{
        Category = "Command Line Tools"
        Items    = @(
            @{ Name = "Cmd.exe (Admin)"; Command = "cmd.exe"; AllowFolders = $true }
            @{ Name = "Powershell 7 (Admin)"; Command = "pwsh.exe"; AllowFolders = $true }
            @{ Name = "PowerShell.exe (Admin)"; Command = "powershell.exe"; AllowFolders = $true }
            @{ Name = "DB2 CLI (Admin)"; Command = "C:\Program Files\IBM\SQLLIB\BIN\db2cmd.exe" }
        )
    }
    @{
        Category = "Development Tools"
        Items    = @(
            @{ Name = "Cursor AI - Code Editor"; Command = { C:\Users\fkgeista\AppData\Local\Programs\cursor\Cursor.exe }; AllowFolders = $true }
            @{ Name = "VS Code - Code Editor"; Command = { C:\Program Files\Microsoft VS Code\Code.exe }; AllowFolders = $true }
            @{ Name = "Windows PowerShell ISE - PowerShell editor and debugger"; Command = { powershell_ise.exe }; AllowFolders = $true }
        )
    }
    @{
        Category = "Internal System Management Tools"
        Items    = @(
            @{ Name = "WinUninstall"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\WinUninstall\WinUninstall.ps1" -Verb RunAs } }
            @{ Name = "Add-Task"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\Add-Task\Add-Task.ps1" -Verb RunAs } }
            @{ Name = "Get-App"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\Get-App\Get-App.ps1" -Verb RunAs } }
            @{ Name = "SoftwareDownloader"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\SoftwareDownloader\SoftwareDownloader.ps1" -Verb RunAs } }
            @{ Name = "ComputerAvailabilityStatus"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\ComputerAvailabilityStatus\ComputerAvailabilityStatus.ps1" -Verb RunAs } }
            @{ Name = "NetworkAccessOverviewReport"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\NetworkAccessOverviewReport\NetworkAccessOverviewReport.ps1" -Verb RunAs } }
            @{ Name = "ActiveServerList"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\ActiveServerList\ActiveServerList.ps1" -Verb RunAs } }
            @{ Name = "PortCheckTool Platform Mode"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\PortCheckTool\PortCheckTool.ps1 -ReportType Platform" -Verb RunAs } }
            @{ Name = "PortCheckTool Computer Mode"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\PortCheckTool\PortCheckTool.ps1 -ReportType Computer" -Verb RunAs } }
            @{ Name = "Add-FkUserAsLocalAdmin"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\Add-FkUserAsLocalAdmin\Add-FkUserAsLocalAdmin.ps1" -Verb RunAs } }
            @{ Name = "DisableNtlmPolicyRestriction"; Command = { Start-Process "pwsh.exe" -ArgumentList "$env:OptPath\DedgePshApps\DisableNtlmPolicyRestriction\DisableNtlmPolicyRestriction.ps1" -Verb RunAs } }
        )
    }
    @{
        Category = "System Management"
        Items    = @(
            @{ Name = "Explorer (Downloads)"; Command = { Start-Process explorer.exe -ArgumentList $([Environment]::GetFolderPath("UserProfile") + "\Downloads") -Verb RunAs } }
            @{ Name = "Control Panel"; Command = { control.exe } }
            @{ Name = "Environment Variables"; Command = { rundll32.exe -ArgumentList "sysdm.cpl,EditEnvironmentVariables" } }
            @{ Name = "Computer Management (compmgmt.msc)"; Command = { Start-Process "compmgmt.msc" -Verb RunAs } }
            @{ Name = "System Properties"; Command = { Start-Process "sysdm.cpl" -Verb RunAs } }
            @{ Name = "Windows Features"; Command = { Start-Process "optionalfeatures" -Verb RunAs } }
            @{ Name = "Performance Monitor"; Command = { Start-Process "perfmon.msc" -Verb RunAs } }
            @{ Name = "Upgrade All Applications (winget)"; Command = { Start-WingetUpgrade } }
            @{ Name = "Task Manager"; Command = { Start-Process "taskmgr.exe" -Verb RunAs } }

            @{ Name = "System Configuration"; Command = { Start-Process "msconfig.exe" -Verb RunAs } }
            @{ Name = "Disk Cleanup"; Command = { Start-Process "cleanmgr.exe" -Verb RunAs } }
            @{ Name = "Power Options"; Command = { Start-Process "powercfg.cpl" -Verb RunAs } }
            @{ Name = "Programs and Features"; Command = { Start-Process "appwiz.cpl" -Verb RunAs } }
            @{ Name = "Windows Security"; Command = { Start-Process "windowsdefender:" -Verb RunAs } }
            @{ Name = "Sound Settings"; Command = { Start-Process "mmsys.cpl" -Verb RunAs } }
        )
    }
    @{
        Category = "Security & Users"
        Items    = @(
            @{ Name = "Local Users and Groups"; Command = { Start-Process "lusrmgr.msc" -Verb RunAs } }
            @{ Name = "Local Security Policy"; Command = { Start-Process "secpol.msc" -Verb RunAs } }
            @{ Name = "Group Policy Editor"; Command = { Start-Process "gpedit.msc" -Verb RunAs } }
            @{ Name = "Certificate Manager"; Command = { Start-Process "certmgr.msc" -Verb RunAs } }
            @{ Name = "Windows Firewall"; Command = { Start-Process "wf.msc" -Verb RunAs } }
            @{ Name = "Registry Editor"; Command = { Start-Process "regedit.exe" -Verb RunAs } }
        )
    }
    @{
        Category = "Services & Monitoring"
        Items    = @(
            @{ Name = "Services"; Command = { Start-Process "services.msc" -Verb RunAs } }
            @{ Name = "Task Scheduler"; Command = { Start-Process "taskschd.msc" -Verb RunAs } }
            @{ Name = "Event Viewer"; Command = { Start-Process "eventvwr.msc" -Verb RunAs } }
        )
    }
    @{
        Category = "Networking"
        Items    = @(
            @{ Name = "Network Connections"; Command = { Start-Process "ncpa.cpl" -Verb RunAs } }
            @{ Name = "Remote Desktop Connection"; Command = { Start-Process "mstsc.exe" -Verb RunAs } }
            @{ Name = "Shared Folders"; Command = { Start-Process "fsmgmt.msc" -Verb RunAs } }
        )
    }
)
# lOOP AND ADD PROPERTY MENU ITEM INDEX TO EACH ITEM STARTING AT 1 FOR ALL ITEMS IN menuItems
$menuIndex = 1
foreach ($category in $menuItems) {
    foreach ($item in $category.Items) {
        $item.MenuIndex = $menuIndex
        $menuIndex++
    }
}

function Show-AdminMenu {
    do {
        Clear-Host
        Write-Host "================ Windows Administrative Tools ================" -ForegroundColor Green
        Write-Host "Tip: For options 1-4, add 'F' to select from recent folders (e.g., '1F' or '2f')" -ForegroundColor Cyan

        foreach ($category in $menuItems) {
            Write-Host "`n$($category.Category):" -ForegroundColor Green
            foreach ($item in $category.Items) {
                Write-Host "$($item.MenuIndex). $($item.Name)" -ForegroundColor White
            }
        }

        Write-Host "`nEnter your choice (1-$($menuIndex-1)) or 'Q' to quit: " -ForegroundColor Green
        Write-Host "=======================================================" -ForegroundColor Green

        $choice = Read-Host

        if ([string]::IsNullOrWhiteSpace($choice)) { continue }
        if ($choice -eq 'Q' -or $choice -eq 'q') { return }

        $showFolders = $choice -match '[fF]'
        $cleanChoice = [int]($choice -replace '[fF]', '' -replace '\s', '')

        #FIND THE MENU ITEM INDEX IN menuItems.MenuIndex WHICE STATRTS AT 1 AND ENDS AT $menuIndex
        $menuItemIndex = $cleanChoice
        $found = $false
        $foundItem = $null
        foreach ($category in $menuItems) {
            foreach ($item in $category.Items) {
                if ($item.MenuIndex -eq $menuItemIndex) {
                    $found = $true
                    $foundItem = $item
                    break
                }
            }
        }
        if ($found) {
            if ($showFolders -and $foundItem.AllowFolders) {
                Show-FolderSelectionMenu $foundItem.Command $foundItem.Name
            }
            elseif ($foundItem.Command -is [scriptblock]) {
                & $foundItem.Command
            }
            else {
                Start-Job -ScriptBlock {
                    param($cmd)
                    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $startInfo.UseShellExecute = $true
                    $startInfo.Verb = "runas"
                    $startInfo.FileName = $cmd
                    [System.Diagnostics.Process]::Start($startInfo)
                } -ArgumentList $foundItem.Command | Wait-Job -Timeout 1 | Remove-Job
            }
        }
        else {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }

        Start-Sleep -Milliseconds 500
    } while ($true)
}

function Get-FoldersWithRecentFiles {
    param (
        [int]$days
    )

    $cacheFile = Join-Path $env:TEMP "FKAdmin_RecentFolders.json"

    # Check if cache file exists and is less than 1 minute old
    if (Test-Path $cacheFile) {
        $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($cacheAge.TotalMinutes -lt 5) {
            try {
                $cachedFolders = Get-Content $cacheFile | ConvertFrom-Json
                return $cachedFolders | ForEach-Object {
                    [PSCustomObject]@{
                        FullName     = $_.FullName
                        LastModified = [DateTime]::Parse($_.LastModified)
                    }
                }
            }
            catch {
                Write-Host "Cache read error, refreshing..." -ForegroundColor Yellow
            }
        }
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    $cutoffDate = (Get-Date).AddDays(-$days)
    $maxAge = [math]::Ceiling(((Get-Date) - $cutoffDate).TotalDays)

    # Use robocopy with modified options to get clearer output
    robocopy "$env:OptPath\src" NULL /L /S /FP /TS /NP /NS /NC /NDL /NJH /NJS `
        /XD "*old*" "*_old*" "obj" "bin" ".vs" ".git" ".vscode" `
        /IF "*.ps1" "*.psm1" "*.psd1" "*.ps1xml" "*.pssc" "*.psrc" ".cdxml" `
        "*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs" "*.vue" "*.svelte" `
        "*.json" "*.jsonc" "*.json5" `
        "*.cbl"  "*.cpx" "*.dcl" "*.cpy" "*.cpb" "*.cfg" "*.mfs" `
        "*.html" "*.htm" "*.cshtml" "*.razor" "*.css" "*.scss" "*.less" `
        "*.cs" "*.csx" "*.vb" "*.fs" "*.config" "*.xaml" "*.resx" "*.settings" `
        "*.csproj" "*.sln" "*.props" "*.targets" "*.nuspec" "*.nswag" `
        "*.xml" "*.yml" "*.yaml" "*.ini" "*.conf" "*.cfg" "*.reg" "*.env" `
        "*.cmd" "*.bat" "*.sh" "*.bash" "*.zsh" "*.fish" `
        "*.md" "*.markdown" "*.rdoc" "*.txt" "*.rst" `
        "*.sql" "*.sqlproj" "*.dbml" `
        "*.cpp" "*.h" "*.hpp" "*.py" "*.rb" "*.php" `
        "*.tf" "*.hcl" "*.dockerfile" "*.dockerignore" "*.gitignore" `
        "*.template" "*.tpl" "*.tmpl" `
        /MAXAGE:$maxAge /R:0 /W:0 | Out-File $tempFile

    try {
        $content = Get-Content $tempFile
        $folders = $content |
        Where-Object {
            $_ -match '(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$' -and
            ![string]::IsNullOrWhiteSpace($matches[2])
        } |
        ForEach-Object {
            if (-not ($matches[2] -imatch "\\(?:_)?old\\?" -or
                    ($matches[2] -split '\\')[-2] -imatch "^(?:_)?old$" -or
                    ($matches[2] -split '\\')[-1] -imatch "^(?:_)?old$")) {
                try {
                    [PSCustomObject]@{
                        FullName     = Split-Path $matches[2].Trim() -Parent
                        LastModified = [DateTime]::Parse($matches[1])
                    }
                }
                catch {
                    Write-Host "Error processing line: $_" -ForegroundColor Red
                    $null
                }
            }
        } |
        Where-Object { $null -ne $_ -and $null -ne $_.LastModified } |
        Group-Object FullName |
        ForEach-Object {
            [PSCustomObject]@{
                FullName     = $_.Name
                LastModified = ($_.Group | Sort-Object LastModified -Descending | Select-Object -First 1).LastModified
            }
        } |
        Sort-Object LastModified -Descending |
        Select-Object -First 30

        # Save results to cache file
        if ($null -ne $folders -and $folders.Count -gt 0) {
            $folders | ConvertTo-Json | Set-Content $cacheFile
        }

        return $folders
    }
    finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

function Show-FolderSelectionMenu {
    param (
        [string]$programPath,
        [string]$programName
    )

    Clear-Host
    Write-Host ("Select a folder to open in " + $programName + ":") -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Green
    Write-Host "Retrieving folder list..." -ForegroundColor Cyan

    $folders = Get-FoldersWithRecentFiles -days 7
    if ($null -eq $folders -or $folders.Count -eq 0) {
        Write-Host "No folders with changes in last 7 days, checking last 14 days..." -ForegroundColor Green
        Start-Sleep -Seconds 1
        $folders = Get-FoldersWithRecentFiles -days 14
    }

    Clear-Host
    Write-Host ("Select a folder to open in " + $programName + ":") -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Green

    if ($null -eq $folders -or $folders.Count -eq 0) {
        Write-Host "No recently modified folders found." -ForegroundColor Green
        Start-Sleep -Seconds 2
        return
    }

    $validFolders = $folders | Where-Object { $null -ne $_.LastModified }
    $menuIndex = 1

    # Calculate maximum path length plus padding
    $maxLength = ($validFolders | ForEach-Object { $_.FullName.Length } | Measure-Object -Maximum).Maximum + 5
    $numberPadding = $validFolders.Count.ToString().Length

    foreach ($folder in $validFolders) {
        $lastModified = $folder.LastModified.ToString("yyyy-MM-dd HH:mm:ss")
        $paddedPath = $folder.FullName.PadRight($maxLength)
        $paddedNumber = $menuIndex.ToString().PadLeft($numberPadding)
        Write-Host "$paddedNumber. $paddedPath[$lastModified]" -ForegroundColor White
        $menuIndex++
    }
    Write-Host "Q. Return to main menu" -ForegroundColor Green

    $choice = Read-Host "`nSelect folder number"

    if ($choice -eq 'Q' -or $choice -eq 'q') {
        return
    }

    if ([int]::TryParse($choice, [ref]$null)) {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $validFolders.Count) {
            $folderPath = $validFolders[$index].FullName
            $exePath = $programPath
            Start-Job -ScriptBlock {
                param($path, $exe)
                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.UseShellExecute = $true
                $startInfo.WorkingDirectory = $path
                $startInfo.Verb = "runas"
                $startInfo.FileName = $exe
                $startInfo.Arguments = "`"$path`""
                [System.Diagnostics.Process]::Start($startInfo)
            } -ArgumentList $folderPath, $exePath | Wait-Job -Timeout 1 | Remove-Job
        }
    }
}

function Stop-PowerToysProcesses {
    Start-Job -ScriptBlock {
        $processes = Get-Process -Name "PowerToys" -ErrorAction SilentlyContinue
        if ($processes) {
            foreach ($process in $processes) {
                try {
                    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $startInfo.FileName = "taskkill.exe"
                    $startInfo.Arguments = "/F /IM PowerToys.exe"
                    $startInfo.UseShellExecute = $true
                    $startInfo.Verb = "runas"
                    [System.Diagnostics.Process]::Start($startInfo).WaitForExit(3000)
                }
                catch {
                    Write-Host "Error stopping PowerToys process: $_" -ForegroundColor Red
                }
            }
        }
    } | Wait-Job -Timeout 5 | Remove-Job
}

# Start the menu
Show-AdminMenu

