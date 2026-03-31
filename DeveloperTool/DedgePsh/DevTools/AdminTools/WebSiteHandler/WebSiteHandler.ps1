#Requires -Version 5.1
<#
.SYNOPSIS
    Manages IIS websites with import/export functionality.
.DESCRIPTION
    This script provides a unified interface for exporting and importing IIS websites.
    It allows users to choose either export (with site selection) or import (with automatic processing).
.PARAMETER Mode
    Specify operation mode: "Export" or "Import"
.PARAMETER SelectedSites
    For Export mode, specify the websites to export (comma-separated list)
.PARAMETER NoGUI
    Run without graphical user interface (command-line mode)
.PARAMETER ImportPath
    For Import mode, specify the path to import from
.EXAMPLE
    .\WebSiteHandler.ps1 -Mode Export -SelectedSites "Default Web Site,MyApp" -NoGUI
    Export specific websites in command-line mode.
.EXAMPLE
    .\WebSiteHandler.ps1 -Mode Import -NoGUI
    Import all packages from the default import folder in command-line mode.
.NOTES
    Version:        1.2
    Author:         Admin Tools
    Creation Date:  Current date
#>
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("Export", "Import")]
    [string]$Mode = "",

    [Parameter(Mandatory=$false)]
    [string]$SelectedSites = "",

    [Parameter(Mandatory=$false)]
    [switch]$NoGUI = $false,

    [Parameter(Mandatory=$false)]
    [string]$ImportPath = ""
)

# Verify that $env:OptPath exists
if ([string]::IsNullOrEmpty($env:OptPath)) {
    Write-Host "ERROR: Environment variable OptPath is not set. Script cannot continue." -ForegroundColor Red
    exit 1
}

# Import common utility functions
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path $scriptPath "Common.ps1"
. $commonPath

# Check for admin privileges
if (-not (Test-AdminPrivileges)) {
    exit
}

# Get standard paths
$paths = Get-StandardPaths
$baseFolder = $paths.BaseFolder
$exportFolder = $paths.ExportFolder
$importFolder = $paths.ImportFolder
$archiveFolder = $paths.ArchiveFolder

# Create directories if they don't exist
Initialize-Folders

# Only import UI modules if needed
if (-not $NoGUI) {
    # Import required modules for UI
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

# Check if IIS is installed and initialize
Initialize-IIS -Verbose -Force

# Show a Windows Forms dialog to select websites for export
function Show-WebsiteSelectionDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Websites to Export"
    $form.Size = New-Object System.Drawing.Size(500, 400)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # Add instructions label
    $instructionsLabel = New-Object System.Windows.Forms.Label
    $instructionsLabel.Location = New-Object System.Drawing.Point(10, 10)
    $instructionsLabel.Size = New-Object System.Drawing.Size(460, 40)
    $instructionsLabel.Text = "Select the websites you want to export. Use the checkbox at the top to select/deselect all websites."
    $form.Controls.Add($instructionsLabel)

    # Create CheckedListBox for websites
    $checkedListBox = New-Object System.Windows.Forms.CheckedListBox
    $checkedListBox.Location = New-Object System.Drawing.Point(10, 60)
    $checkedListBox.Size = New-Object System.Drawing.Size(460, 250)
    $checkedListBox.CheckOnClick = $true
    $form.Controls.Add($checkedListBox)

    # Add Select All checkbox
    $selectAllCheckBox = New-Object System.Windows.Forms.CheckBox
    $selectAllCheckBox.Location = New-Object System.Drawing.Point(10, 320)
    $selectAllCheckBox.Size = New-Object System.Drawing.Size(100, 20)
    $selectAllCheckBox.Text = "Select All"
    $form.Controls.Add($selectAllCheckBox)

    # Add OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(310, 320)
    $okButton.Size = New-Object System.Drawing.Size(75, 23)
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    # Add Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(395, 320)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 23)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    # Get all websites
    $websites = Get-Website | Select-Object Name, ID, PhysicalPath

    # Populate the CheckedListBox
    foreach ($site in $websites) {
        $checkedListBox.Items.Add($site.Name, $false)
    }

    # Handle Select All checkbox
    $selectAllCheckBox.Add_CheckedChanged({
        for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
            $checkedListBox.SetItemChecked($i, $selectAllCheckBox.Checked)
        }
    })

    # Show the form and get result
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedSites = @()
        for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
            if ($checkedListBox.GetItemChecked($i)) {
                $selectedSites += $checkedListBox.Items[$i]
            }
        }
        return $selectedSites
    }
    return $null
}

# Get drive selection from user
function Show-DriveSelectionDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Destination Drive"
    $form.Size = New-Object System.Drawing.Size(400, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # Add instructions label
    $instructionsLabel = New-Object System.Windows.Forms.Label
    $instructionsLabel.Location = New-Object System.Drawing.Point(10, 10)
    $instructionsLabel.Size = New-Object System.Drawing.Size(360, 40)
    $instructionsLabel.Text = "Select the drive where the websites should be imported. The remaining path structure will be preserved."
    $form.Controls.Add($instructionsLabel)

    # Create ComboBox for drives
    $driveComboBox = New-Object System.Windows.Forms.ComboBox
    $driveComboBox.Location = New-Object System.Drawing.Point(10, 60)
    $driveComboBox.Size = New-Object System.Drawing.Size(360, 25)
    $driveComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $form.Controls.Add($driveComboBox)

    # Add Preview label
    $previewLabel = New-Object System.Windows.Forms.Label
    $previewLabel.Location = New-Object System.Drawing.Point(10, 90)
    $previewLabel.Size = New-Object System.Drawing.Size(360, 20)
    $previewLabel.Text = "Example path: "
    $form.Controls.Add($previewLabel)

    # Add OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(210, 120)
    $okButton.Size = New-Object System.Drawing.Size(75, 23)
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    # Add Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(295, 120)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 23)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    # Populate drives
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 }
    foreach ($drive in $drives) {
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        $driveComboBox.Items.Add("$($drive.Name): ($freeSpaceGB GB free)")
    }

    if ($driveComboBox.Items.Count -gt 0) {
        $driveComboBox.SelectedIndex = 0
    }

    # Update preview when selection changes
    $driveComboBox.Add_SelectedIndexChanged({
        $selectedDrive = $driveComboBox.SelectedItem
        if ($selectedDrive) {
            $driveLetter = $selectedDrive.ToString().Split(':')[0]
            $previewLabel.Text = "Example path: ${driveLetter}:\websites\site1"
        }
    })

    # Show the form and get result
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $driveComboBox.SelectedItem) {
        $selectedDrive = $driveComboBox.SelectedItem.ToString().Split(':')[0]
        return $selectedDrive
    }
    return $null
}

# Show Mode Selection Dialog
function Show-ModeSelectionDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "IIS Website Handler"
    $form.Size = New-Object System.Drawing.Size(350, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # Add title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(10, 10)
    $titleLabel.Size = New-Object System.Drawing.Size(310, 30)
    $titleLabel.Text = "IIS Website Handler"
    $titleLabel.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)

    # Add instructions label
    $instructionsLabel = New-Object System.Windows.Forms.Label
    $instructionsLabel.Location = New-Object System.Drawing.Point(10, 50)
    $instructionsLabel.Size = New-Object System.Drawing.Size(310, 20)
    $instructionsLabel.Text = "Select operation mode:"
    $form.Controls.Add($instructionsLabel)

    # Add Export button
    $exportButton = New-Object System.Windows.Forms.Button
    $exportButton.Location = New-Object System.Drawing.Point(40, 80)
    $exportButton.Size = New-Object System.Drawing.Size(120, 50)
    $exportButton.Text = "Export Websites"
    $exportButton.Add_Click({
        $form.Tag = "Export"
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $form.Controls.Add($exportButton)

    # Add Import button
    $importButton = New-Object System.Windows.Forms.Button
    $importButton.Location = New-Object System.Drawing.Point(170, 80)
    $importButton.Size = New-Object System.Drawing.Size(120, 50)
    $importButton.Text = "Import Websites"
    $importButton.Add_Click({
        $form.Tag = "Import"
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $form.Controls.Add($importButton)

    # Show the form and get result
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $form.Tag
    }
    return $null
}

# Run the main function - this will be implemented in separate script files
function Start-Export {
    param (
        [string[]]$SelectedSites,
        [switch]$NoGUI
    )

    # This will be delegated to ExportIISSites.ps1
    $scriptPath = Join-Path $PSScriptRoot "ExportIISSites.ps1"

    # Pass the selected sites to the export script
    $sitesParam = $SelectedSites -join ","
    $params = @{}

    if (-not [string]::IsNullOrEmpty($sitesParam)) {
        $params.Add("SelectedSites", $sitesParam)
    }

    if ($NoGUI) {
        $params.Add("NoGUI", $true)
    }

    & $scriptPath @params
}

function Start-Import {
    param (
        [string]$ImportPath,
        [switch]$NoGUI
    )

    # This will be delegated to ImportIISSites.ps1
    $scriptPath = Join-Path $PSScriptRoot "ImportIISSites.ps1"

    # Pass parameters to the import script
    $params = @{}

    if (-not [string]::IsNullOrEmpty($ImportPath)) {
        $params.Add("ImportPath", $ImportPath)
    }

    if ($NoGUI) {
        $params.Add("NoGUI", $true)
    }

    & $scriptPath @params
}

# Main execution flow
try {
    # Verify that necessary IIS components are installed
    Write-Host "Verifying IIS installation and components..." -ForegroundColor Cyan
    $iisInitialized = Initialize-IIS -Verbose -Force
    if (-not $iisInitialized) {
        Write-Host "ERROR: Failed to initialize IIS. Cannot continue." -ForegroundColor Red
        Write-Host "Please ensure IIS is properly installed and that you've restarted your computer after installation." -ForegroundColor Yellow
        Write-Host "You can use CheckIISStatus.ps1 for detailed diagnostics." -ForegroundColor Yellow
        exit 1
    }

    # WebAdministration module is already checked by Initialize-IIS, no need for separate check
    # The rest of the function stays the same

    # Check if we're running in command-line mode
    if ($NoGUI -or (-not [string]::IsNullOrEmpty($Mode))) {
        # Command-line mode
        if ([string]::IsNullOrEmpty($Mode)) {
            Write-Host "Error: Mode parameter is required when using NoGUI." -ForegroundColor Red
            Write-Host "Please specify either 'Export' or 'Import'." -ForegroundColor Yellow
            exit
        }

        if ($Mode -eq "Export") {
            # No need to parse SelectedSites, it's already a parameter
            Write-Host "Running in command-line mode: Export" -ForegroundColor Cyan
            if (-not [string]::IsNullOrEmpty($SelectedSites)) {
                Write-Host "Selected websites for export: $SelectedSites" -ForegroundColor Cyan
            } else {
                Write-Host "Exporting all valid websites" -ForegroundColor Cyan
                $SelectedSites = "*"  # Use wildcard to export all valid sites
            }

            $sitesArray = $SelectedSites -split ","
            Start-Export -SelectedSites $sitesArray -NoGUI
        }
        elseif ($Mode -eq "Import") {
            Write-Host "Running in command-line mode: Import" -ForegroundColor Cyan
            if (-not [string]::IsNullOrEmpty($ImportPath)) {
                Write-Host "Using import path: $ImportPath" -ForegroundColor Cyan
            } else {
                Write-Host "Using default import folder" -ForegroundColor Cyan
            }

            Start-Import -ImportPath $ImportPath -NoGUI
        }
    }
    else {
        # GUI Mode - Show mode selection dialog
        $mode = Show-ModeSelectionDialog

        if ($mode -eq "Export") {
            # Get user selection of websites to export
            $selectedSites = Show-WebsiteSelectionDialog

            if ($selectedSites -and $selectedSites.Count -gt 0) {
                Write-Host "Selected websites for export: $($selectedSites -join ", ")" -ForegroundColor Cyan
                Start-Export -SelectedSites $selectedSites
            }
            else {
                Write-Host "No websites selected for export. Using wildcard to export all valid sites." -ForegroundColor Yellow
                Start-Export -SelectedSites @("*")
            }
        }
        elseif ($mode -eq "Import") {
            # Start import without destination drive parameter
            Start-Import
        }
        else {
            Write-Host "Operation cancelled. Exiting." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red

    # Provide guidance based on error type
    if ($_.Exception.Message -match "WebAdministration") {
        Write-Host "This appears to be an issue with the IIS WebAdministration module." -ForegroundColor Yellow
        Write-Host "Try running the following command in an elevated PowerShell prompt:" -ForegroundColor Yellow
        Write-Host "dism /online /enable-feature /featurename:IIS-WebServerManagementTools /featurename:IIS-ManagementScriptingTools /all" -ForegroundColor Yellow
    }
    elseif ($_.Exception.Message -match "permission") {
        Write-Host "This appears to be a permissions issue. Make sure you're running as Administrator." -ForegroundColor Yellow
    }
}
finally {
    Write-Host "Process completed." -ForegroundColor Green
}

