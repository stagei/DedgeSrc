<#
.SYNOPSIS
    Permanently sets VS Code and Cursor to use PowerShell 7+ (pwsh) instead of Windows PowerShell 5.1.

.DESCRIPTION
    Dynamically detects:
    - The installed pwsh.exe location (PATH, Program Files, winget, dotnet tool, scoop, chocolatey)
    - The VS Code and Cursor settings.json paths for the current user

    Then updates user-level settings.json for each detected editor to:
    - Set the default integrated terminal profile to "PowerShell" (pwsh 7+)
    - Set the PowerShell extension's default version to pwsh 7+
    - Register the pwsh.exe path in the extension's additional exe paths

    This eliminates the need to manually switch from "Windows PowerShell" to "PowerShell"
    each time a new terminal or extension host is opened.

.PARAMETER WhatIf
    Shows what changes would be made without actually writing to settings files.

.EXAMPLE
    .\Set-VsCodePwshDefault.ps1
    .\Set-VsCodePwshDefault.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Import-Module GlobalFunctions -Force

$ErrorActionPreference = 'Stop'

# ── Detect pwsh.exe ───────────────────────────────────────────────────────────
# Searches in order: PATH, standard install locations, package managers
function Find-PwshExe {
    # 1. Check PATH first (fastest, covers most installs)
    $fromPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if ($fromPath -and (Test-Path $fromPath)) { return $fromPath }

    # 2. Standard Program Files locations (MSI / winget / GitHub release installs)
    $standardPaths = @(
        Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe'
    )
    # 3. Find highest installed version folder under Program Files
    $pfPwshRoot = Join-Path $env:ProgramFiles 'PowerShell'
    if (Test-Path $pfPwshRoot) {
        Get-ChildItem $pfPwshRoot -Directory |
            Where-Object { $_.Name -match '^\d+$' } |
            Sort-Object { [int]$_.Name } -Descending |
            ForEach-Object { $standardPaths += Join-Path $_.FullName 'pwsh.exe' }
    }

    # 4. dotnet global tool
    $dotnetToolPath = Join-Path $env:USERPROFILE '.dotnet\tools\pwsh.exe'
    $standardPaths += $dotnetToolPath

    # 5. Scoop
    $scoopPath = Join-Path $env:USERPROFILE 'scoop\shims\pwsh.exe'
    $standardPaths += $scoopPath

    # 6. Chocolatey
    $chocoPath = Join-Path $env:ProgramData 'chocolatey\bin\pwsh.exe'
    $standardPaths += $chocoPath

    # 7. Microsoft Store / WindowsApps
    $windowsAppsPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
    $standardPaths += $windowsAppsPath

    foreach ($p in $standardPaths) {
        if ($p -and (Test-Path $p)) { return $p }
    }

    return $null
}

$pwshPath = Find-PwshExe
if (-not $pwshPath) {
    Write-LogMessage "pwsh.exe not found anywhere. Install PowerShell 7+ first: https://aka.ms/install-powershell" -Level ERROR
    exit 1
}

# Get version from the detected pwsh binary ("pwsh --version" outputs "PowerShell 7.5.4")
$pwshVersionRaw = (& $pwshPath --version) -replace '^PowerShell\s*', ''
$pwshMajor = ($pwshVersionRaw -split '\.')[0]
$pwshVersionLabel = "PowerShell $($pwshMajor)"
Write-LogMessage "Detected $($pwshVersionLabel) ($($pwshVersionRaw)) at: $($pwshPath)" -Level INFO

# ── Detect editor settings.json paths ────────────────────────────────────────
# Handles standard, Snap, Flatpak, and portable installs
function Find-EditorSettings {
    $editors = [System.Collections.Generic.List[hashtable]]::new()

    $candidates = @(
        @{ Name = 'VS Code';           Sub = 'Code\User\settings.json' }
        @{ Name = 'VS Code Insiders';  Sub = 'Code - Insiders\User\settings.json' }
        @{ Name = 'Cursor';            Sub = 'Cursor\User\settings.json' }
        @{ Name = 'VSCodium';          Sub = 'VSCodium\User\settings.json' }
    )

    foreach ($c in $candidates) {
        $settingsPath = Join-Path $env:APPDATA $c.Sub
        if (Test-Path $settingsPath) {
            $editors.Add(@{ Name = $c.Name; Path = $settingsPath })
        }
    }

    # Portable installs: check for a 'data' folder next to the editor executable
    $portableDirs = @(
        (Get-Command code -ErrorAction SilentlyContinue),
        (Get-Command cursor -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ } | ForEach-Object {
        $editorDir = Split-Path $_.Source -Parent
        $portableSettings = Join-Path $editorDir 'data\user-data\User\settings.json'
        if (Test-Path $portableSettings) {
            $editors.Add(@{ Name = "$($_.Name) (portable)"; Path = $portableSettings })
        }
    }

    return $editors
}

$editorTargets = Find-EditorSettings
if ($editorTargets.Count -eq 0) {
    Write-LogMessage "No VS Code or Cursor installations found for the current user." -Level ERROR
    exit 1
}

Write-LogMessage "Found $($editorTargets.Count) editor(s): $($editorTargets.Name -join ', ')" -Level INFO

# ── Settings to inject ────────────────────────────────────────────────────────
# "PowerShell"        = pwsh 7+ profile name used by VS Code's built-in terminal
# "Windows PowerShell" = legacy 5.1 profile name
$settingsToApply = [ordered]@{
    'terminal.integrated.defaultProfile.windows' = 'PowerShell'
    'powershell.powerShellDefaultVersion'        = $pwshVersionLabel
    'powershell.powerShellAdditionalExePaths'    = @{
        $pwshVersionLabel = $pwshPath
    }
}

# ── Apply to each editor ─────────────────────────────────────────────────────
$anyUpdated = $false

foreach ($target in $editorTargets) {
    $settingsFile = $target.Path

    Write-LogMessage "Processing $($target.Name): $($settingsFile)" -Level INFO

    $json = Get-Content $settingsFile -Raw -Encoding utf8
    $settings = $json | ConvertFrom-Json -AsHashtable

    $changed = $false
    foreach ($key in $settingsToApply.Keys) {
        $newValue = $settingsToApply[$key]
        $existingValue = $settings[$key]

        if ($key -eq 'powershell.powerShellAdditionalExePaths') {
            if ($null -eq $existingValue -or $existingValue -isnot [hashtable]) {
                $existingValue = @{}
            }
            $mergeNeeded = $false
            foreach ($vName in $newValue.Keys) {
                if ($existingValue[$vName] -ne $newValue[$vName]) {
                    $existingValue[$vName] = $newValue[$vName]
                    $mergeNeeded = $true
                }
            }
            if ($mergeNeeded) {
                $settings[$key] = $existingValue
                $changed = $true
                Write-LogMessage "  SET $($key).$($pwshVersionLabel) = $($pwshPath)" -Level INFO
            }
            else {
                Write-LogMessage "  OK  $($key).$($pwshVersionLabel) already set" -Level INFO
            }
        }
        else {
            if ($existingValue -ne $newValue) {
                $settings[$key] = $newValue
                $changed = $true
                $oldDisplay = if ($null -eq $existingValue) { '(not set)' } else { $existingValue }
                Write-LogMessage "  SET $($key): $($oldDisplay) -> $($newValue)" -Level INFO
            }
            else {
                Write-LogMessage "  OK  $($key) already '$($newValue)'" -Level INFO
            }
        }
    }

    if ($changed) {
        if ($PSCmdlet.ShouldProcess($settingsFile, "Update PowerShell defaults")) {
            $backupPath = "$($settingsFile).bak"
            Copy-Item -Path $settingsFile -Destination $backupPath -Force
            Write-LogMessage "  Backup saved to $($backupPath)" -Level INFO

            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding utf8 -Force
            Write-LogMessage "  Settings updated successfully" -Level INFO
            $anyUpdated = $true
        }
    }
    else {
        Write-LogMessage "  No changes needed for $($target.Name)" -Level INFO
    }
}

if ($anyUpdated) {
    Write-LogMessage "Done. Restart your editor(s) for changes to take effect." -Level INFO
}
else {
    Write-LogMessage "All editors already configured for $($pwshVersionLabel). No changes made." -Level INFO
}
