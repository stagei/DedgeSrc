# Standalone script to set up both PowerShell and CMD profiles
# This script doesn't depend on the modules that have syntax issues
Import-Module -Name GlobalFunctions -Force

Write-LogMessage "Setting up both PowerShell and CMD profiles..." -Level INFO

# if (Test-IsServer) {
#     Write-LogMessage "Server detected, skipping profile setup" -Level INFO
#     exit 0
# }

# # Function to set up PowerShell profile
# function Add-PowerShell1Profile {
#     try {
#         Write-LogMessage "Setting up PowerShell 1 profile..." -Level INFO

#         # Set the profile path for Windows PowerShell 5.1 (system32 version)
#         # This is the correct path for C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
#         # Using OneDrive Documents folder as specified by user
#         $ps1ProfilePath = "$env:OneDrive\Dokumenter\PowerShell\Microsoft.PowerShell_profile.ps1"
#         $ps1ProfileFolder = Split-Path -Path $ps1ProfilePath -Parent

#         # Create the profile directory if it doesn't exist
#         if (-not (Test-Path $ps1ProfileFolder)) {
#             New-Item -Path $ps1ProfileFolder -ItemType Directory -Force | Out-Null
#             Write-LogMessage "Created Windows PowerShell profile directory: $ps1ProfileFolder" -Level INFO
#         }

#         # Copy the profile file
#         Copy-Item -Path (Join-Path $PSScriptRoot "Microsoft.PowerShell_profile.ps1") -Destination $ps1ProfilePath -Force
#         Write-LogMessage "PowerShell 1 profile copied to: $ps1ProfilePath" -Level INFO

#         # For Windows PowerShell 5.1, we need to enable profile loading
#         # The profile will be loaded automatically from the standard location
#         # We just need to ensure execution policy allows it
#         $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
#         if ($executionPolicy -eq "Restricted") {
#             Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
#             Write-LogMessage "Set execution policy to RemoteSigned for current user" -Level INFO
#         }

#         # Enable profile loading for Windows PowerShell 5.1
#         # Windows PowerShell uses different registry keys than PowerShell 7
#         $psWinKey = "HKCU:\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell"
#         if (-not (Test-Path $psWinKey)) {
#             New-Item -Path $psWinKey -Force | Out-Null
#         }

#         # Set NoProfile to 0 to enable profiles (0 = false, profiles enabled)
#         Set-ItemProperty -Path $psWinKey -Name "NoProfile" -Value 0 -Type DWord -Force
#         Write-LogMessage "Enabled profile loading for Windows PowerShell 5.1" -Level INFO

#         # Also set execution policy for the system Windows PowerShell specifically
#         try {
#             & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>$null
#             Write-LogMessage "Set execution policy for system Windows PowerShell" -Level INFO
#         }
#         catch {
#             Write-LogMessage "Could not set execution policy for system Windows PowerShell: $($_.Exception.Message)" -Level WARN
#         }

#         Write-LogMessage "Windows PowerShell profile configured to load from: $ps1ProfilePath" -Level INFO
#     }
#     catch {
#         Write-LogMessage "Error during PowerShell 1 profile setup: $($_.Exception.Message)" -Level ERROR -Exception $_
#     }
# }
function Add-PowerShell7Profile {
    try {
        Write-LogMessage "Setting up PowerShell profile..." -Level INFO

        # Set the profile path to the PowerShell profile.ps1 file
        $sourceProfileArray = @()
        $sourceProfileArray += "$env:OptPath\src\DedgePsh\DevTools\AdminTools\Setup-TerminalProfiles\profile.ps1"
        $sourceProfileArray += "$env:OptPath\DedgePshApps\Setup-TerminalProfiles\profile.ps1"
        foreach ($sourceProfile in $sourceProfileArray) {
            if (Test-Path $sourceProfile) {
                $sourcePwshProfilePath = $sourceProfile
                break
            }
        }

        $myDocumentsPath = [Environment]::GetFolderPath("MyDocuments")

        if ($sourcePwshProfilePath -eq "") {
            Write-LogMessage "No Source PowerShell profile found in $sourceProfileArray" -Level ERROR
            throw "No Source PowerShell profile found in $sourceProfileArray"
        }

        $profileArray = @()
        $profileArray += "$env:ProgramFiles\PowerShell\7\profile.ps1"
        $profileArray += "$myDocumentsPath\PowerShell\profile.ps1"
        $profileArray += "$myDocumentsPath\PowerShell\Microsoft.PowerShell_profile.ps1"
        $profileArray += "$myDocumentsPath\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        $profileArray += "$myDocumentsPath\PowerShell\Microsoft.VSCode_profile.ps1"
        foreach ($myProfile in $profileArray) {
            $parentFolder = Split-Path -Path $myProfile -Parent
            if (-not (Test-Path $parentFolder)) {
                New-Item -ItemType Directory -Path $parentFolder -Force | Out-Null
            }
            Remove-Item -Path $myProfile -Force -ErrorAction SilentlyContinue
            #New-Item -ItemType SymbolicLink -Path $myProfile -Target $sourcePwshProfilePath -Force
            Copy-Item -Path $sourcePwshProfilePath -Destination $myProfile -Force
            Write-LogMessage "Copied Source PowerShell profile to: $myProfile" -Level INFO
        }

        # $pwshProfilePath = ""
        # foreach ($profile in $profileArray) {
        #     if (Test-Path $profile) {
        #         $pwshProfilePath = $profile
        #         break
        #     }
        # }
        # if ($pwshProfilePath -eq "") {
        #     Write-LogMessage "No PowerShell profile found in $profileArray" -Level ERROR
        #     throw "No PowerShell profile found in $profileArray"
        # }

        # # Configure PowerShell to load our custom profile
        # $psCoreKey = "HKCU:\Software\Microsoft\PowerShellCore\ShellIds\Microsoft.PowerShell"
        # if (-not (Test-Path $psCoreKey)) {
        #     New-Item -Path $psCoreKey -Force | Out-Null
        # }

        # # Set ConsoleHostCommand to load our profile
        # Set-ItemProperty -Path $psCoreKey -Name "ConsoleHostCommand" -Value "-NoExit -File `"$pwshProfilePath`"" -Type String
        # Write-LogMessage "Configured PowerShell to load profile from: $pwshProfilePath" -Level INFO

    }
    catch {
        Write-LogMessage "Error during PowerShell profile setup: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# Function to set up CMD profile
function Add-CmdProfile {
    try {
        Write-LogMessage "Setting up CMD profile..." -Level INFO

        # Configure CMD profile by creating/updating autorun registry key
        # HKEY_CURRENT_USER\Software\Microsoft\Command Processor\AutoRun
        # This registry value is executed every time CMD.exe starts

        $array = @()
        $array += "$env:OptPath\src\DedgePsh\DevTools\AdminTools\Setup-TerminalProfiles\profile.cmd"
        $array += "$env:OptPath\DedgePshApps\Setup-TerminalProfiles\profile.cmd"

        foreach ($cmdProfilePath in $array) {
            if (Test-Path $cmdProfilePath) {
                $cmdProfilePath = $cmdProfilePath
                break
            }
        }

        # Configure the registry to run the profile
        $cmdAutoRunKey = "HKCU:\Software\Microsoft\Command Processor"
        if (-not (Test-Path $cmdAutoRunKey)) {
            New-Item -Path $cmdAutoRunKey -Force | Out-Null
        }
        # Set the AutoRun registry value to point to the local profile
        Set-ItemProperty -Path $cmdAutoRunKey -Name "AutoRun" -Value $cmdProfilePath -Type String

        # Configure the system-wide AutoRun for all users
        $allUsersAutoRunKey = "HKLM:\Software\Microsoft\Command Processor"
        if (-not (Test-Path $allUsersAutoRunKey)) {
            New-Item -Path $allUsersAutoRunKey -Force | Out-Null
        }
        $newAutoRun = "`"$cmdProfilePath`""
        Set-ItemProperty -Path $allUsersAutoRunKey -Name "AutoRun" -Value $newAutoRun -Type String

        Write-LogMessage "CMD profile setup completed successfully" -Level INFO

    }
    catch {
        Write-LogMessage "Error during CMD profile setup: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# Main execution
try {

    # Set up PowerShell 7 profile
    Add-PowerShell7Profile

    # # Set up PowerShell 1 profile
    # Add-PowerShell1Profile

    # Set up CMD profile
    Add-CmdProfile

    Write-LogMessage "Profile setup completed successfully!" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Both PowerShell and CMD profiles are now configured to run automatically." -Level INFO -ForegroundColor Cyan
    Write-LogMessage "To test the profiles:" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "1. Start a new PowerShell session (pwsh.exe)" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "2. Start a new CMD session (cmd.exe)" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "3. Both should automatically load the FK environment and map network drives" -Level INFO -ForegroundColor Cyan
}
catch {
    Write-LogMessage "Error during profile setup: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}

