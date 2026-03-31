# Script to remove both PowerShell and CMD profile mappings
# This script cleans up registry settings and removes profile files

Import-Module -Name GlobalFunctions -Force

Write-LogMessage "Removing PowerShell and CMD profile mappings..." -Level INFO

# Function to remove PowerShell profile
function Remove-PowerShellProfile {
    try {
        Write-LogMessage "Removing PowerShell profile..." -Level INFO

        $myDocumentsPath = [Environment]::GetFolderPath("MyDocuments")

        $profileArray = @()
        $profileArray += "$env:ProgramFiles\PowerShell\7\profile.ps1"
        $profileArray += "$myDocumentsPath\PowerShell\profile.ps1"
        $profileArray += "$myDocumentsPath\PowerShell\Microsoft.PowerShell_profile.ps1"
        $profileArray += "$myDocumentsPath\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        $profileArray += "$myDocumentsPath\PowerShell\Microsoft.VSCode_profile.ps1"
        foreach ($myProfile in $profileArray) {

            if (Test-Path $myProfile) {
                Remove-Item -Path $myProfile -Force -ErrorAction SilentlyContinue
                New-Item -ItemType File -Path $myProfile -Target $myProfile -Force
                Write-LogMessage "Removed symbolic link and added a blank file to: $myProfile" -Level INFO
            }

        }

        Remove-Item -Path "$env:ProgramFiles\PowerShell\7\profile.ps1" -Force -ErrorAction SilentlyContinue
        New-Item -ItemType File -Path "$env:ProgramFiles\PowerShell\7\profile.ps1" -Force

        # Remove PowerShell registry settings
        $psCoreKey = "HKCU:\Software\Microsoft\PowerShellCore\ShellIds\Microsoft.PowerShell"

        Remove-ItemProperty -Path $psCoreKey -Name "ConsoleHostCommand" -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Removed ConsoleHostCommand from PowerShell registry" -Level INFO

        # Reset NoProfile to default (1 = true, which disables profiles)
        Set-ItemProperty -Path $psCoreKey -Name "NoProfile" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Reset PowerShell NoProfile setting to default" -Level INFO

        Write-LogMessage "PowerShell profile removal completed" -Level INFO
    }
    catch {
        Write-LogMessage "Error during PowerShell profile removal: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# Function to remove CMD profile
function Remove-CmdProfile {
    try {
        Write-LogMessage "Removing CMD profile..." -Level INFO

        # Remove CMD profile files
        $cmdProfileArray = @(
            "$env:OptPath\Data\Cmd\profile.cmd",
            "$env:ProgramData\FK\profile.cmd"
        )
        foreach ($cmdProfilePath in $cmdProfileArray) {
            Write-LogMessage "Removing CMD profile files..." -Level INFO
            Remove-Item  -Path $cmdProfilePath -Force -ErrorAction SilentlyContinue
            $parentPath = Split-Path -Path $cmdProfilePath -Parent
            if (Test-Path $parentPath) {
                Remove-Item -Path $parentPath -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType File -Path $cmdProfilePath -Target $cmdProfilePath -Force
            Write-LogMessage "Removed: $cmdProfilePath" -Level INFO
        }

        # Remove CMD registry settings
        $cmdAutoRunKey = "HKCU:\Software\Microsoft\Command Processor"
        Remove-ItemProperty -Path $cmdAutoRunKey -Name "AutoRun" -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Removed AutoRun from user CMD user registry" -Level INFO

        # Remove system-wide AutoRun setting (requires admin privileges)
        $allUsersAutoRunKey = "HKLM:\Software\Microsoft\Command Processor"
        Remove-ItemProperty -Path $allUsersAutoRunKey -Name "AutoRun" -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Removed AutoRun from system CMD machine registry" -Level INFO

        Write-LogMessage "CMD profile removal completed" -Level INFO
    }
    catch {
        Write-LogMessage "Error during CMD profile removal: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

# Main execution
try {
    Write-LogMessage "This will remove all FK terminal profile configurations." -Level INFO
    Write-LogMessage "This includes:" -Level INFO
    Write-LogMessage "- PowerShell profile files and registry settings" -Level INFO
    Write-LogMessage "- CMD profile files and registry settings" -Level INFO
    Write-LogMessage "- Empty directories" -Level INFO

    $myDocumentsPath = [Environment]::GetFolderPath("MyDocuments")

    # Remove PowerShell profile
    # Remove-PowerShellProfile
    Remove-Item -Path "$env:ProgramFiles\PowerShell\7\profile.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$myDocumentsPath\PowerShell\profile.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$myDocumentsPath\PowerShell\Microsoft.PowerShell_profile.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$myDocumentsPath\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$myDocumentsPath\PowerShell\Microsoft.VSCode_profile.ps1" -Force -ErrorAction SilentlyContinue

    # Verify if PowerShell profile files still exist
    $psProfilePaths = @(
        "$env:ProgramFiles\PowerShell\7\profile.ps1",
        "$myDocumentsPath\PowerShell\profile.ps1",
        "$myDocumentsPath\PowerShell\Microsoft.PowerShell_profile.ps1",
        "$myDocumentsPath\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
        "$myDocumentsPath\PowerShell\Microsoft.VSCode_profile.ps1"
    )

    foreach ($profilePath in $psProfilePaths) {
        if (Test-Path $profilePath) {
            Write-LogMessage "Warning: PowerShell profile still exists at: $profilePath" -Level WARN
        }
        else {
            Write-LogMessage "Successfully removed PowerShell profile at: $profilePath" -Level INFO
        }
    }

    Set-Content -Path "$env:ProgramFiles\PowerShell\7\profile.ps1" -Value "" -Force -ErrorAction SilentlyContinue

    # Remove CMD profile
    $null = Remove-CmdProfile

    Write-LogMessage "Profile removal completed successfully!" -Level INFO
    Write-LogMessage "Both PowerShell and CMD profiles have been removed." -Level INFO
    Write-LogMessage "To restore profiles, run: Setup-TerminalProfiles.ps1" -Level INFO
    Write-LogMessage "Script execution completed" -Level INFO
}
catch {
    Write-LogMessage "Error during profile removal: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}

