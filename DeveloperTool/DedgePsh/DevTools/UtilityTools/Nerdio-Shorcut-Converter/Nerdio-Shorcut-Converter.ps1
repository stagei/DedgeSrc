[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({
            if ($_.Trim() -notlike "*.lnk") {
                throw "Filter must end with .lnk extension. Example: '*.lnk' or 'game*.lnk'"
            }
            return $true
        })]
    [string]$Filter = "*.lnk"
)

function Get-CompletionText {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CurrentPath,

        [Parameter(Mandatory=$true)]
        [string]$LogDir
    )

    return @"
`n=================================================================
                      Conversion Complete
=================================================================

Generated files:
1. CMD files in: $CurrentPath
2. Support files in: $LogDir
   - Check README.md for detailed file listing
   - PS1 files are ready to import into Nerdio Manager

Next steps:
1. Test the CMD files directly from current folder
2. Import the PS1 files from .\Nerdio-Shorcut-Converter-Output into Nerdio Manager
   as Scripted Actions

For Nerdio Manager setup:
1. Copy the PS1 and metadata files from .\Nerdio-Shorcut-Converter-Output to your
   Nerdio Manager scripts folder
2. Import them as Scripted Actions in Nerdio Manager

=================================================================
"@
}
function Get-NerdioScriptWithParametersTemplate {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ShortcutName,

        [Parameter(Mandatory=$true)]
        [string]$CmdPath,

        [Parameter(Mandatory=$true)]
        [__ComObject]$Shortcut
    )

    $cmdFileName = [System.IO.Path]::GetFileName($CmdPath)

    # Build optional settings string
    $optionalSettings = ""
    if ($Shortcut.Hotkey) {
        $optionalSettings += "    - Hotkey: $($Shortcut.Hotkey)`n"
    }
    if ($Shortcut.IconLocation) {
        $optionalSettings += "    - Icon Location: $($Shortcut.IconLocation)`n"
    }
    if ($Shortcut.Description) {
        $optionalSettings += "    - Description: $($Shortcut.Description)`n"
    }

    return @"
<#
.SYNOPSIS
    Nerdio Manager wrapper for $ShortcutName
.DESCRIPTION
    Executes the batch file $cmdFileName with original shortcut settings:
    - Target: $($Shortcut.TargetPath)
    - Arguments: $($Shortcut.Arguments)
    - Working Directory: $($Shortcut.WorkingDirectory)
    - Window Style: $($Shortcut.WindowStyle)
$optionalSettings.NOTES
    Generated for Nerdio Manager
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=`$false)]
    [int]`$WindowStyle = $($Shortcut.WindowStyle),

    [Parameter(Mandatory=`$false)]
    [string]`$WorkingDirectory = "$($Shortcut.WorkingDirectory)"
)

`$ErrorActionPreference = 'Stop'
`$scriptPath = Join-Path `$PSScriptRoot "..\$cmdFileName"

try {
    if (-not (Test-Path `$scriptPath -PathType Leaf)) {
        throw "Batch file not found at: `$scriptPath"
    }

    # Set working directory if specified
    if (![string]::IsNullOrWhiteSpace(`$WorkingDirectory)) {
        Set-Location -Path `$WorkingDirectory
    }

    # Execute the batch file with specified window style
    `$startInfo = New-Object System.Diagnostics.ProcessStartInfo
    `$startInfo.FileName = "cmd.exe"
    `$startInfo.Arguments = "/c `"`$scriptPath`""
    `$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]`$WindowStyle
    `$startInfo.UseShellExecute = `$false

    `$process = New-Object System.Diagnostics.Process
    `$process.StartInfo = `$startInfo
    [void]`$process.Start()
    `$process.WaitForExit()

    if (`$process.ExitCode -ne 0) {
        throw "Batch file execution failed with exit code: `$(`$process.ExitCode)"
    }

    Write-Host "Successfully executed $cmdFileName"
} catch {
    Write-Error "Error executing batch file: `$_"
    throw
}
"@
}

function Get-FormatDifferencesText {
    param (
        [Parameter(Mandatory=$true)]
        [bool]$EncodingDiff,

        [Parameter(Mandatory=$true)]
        [bool]$LineEndingDiff
    )

    return @"
=================================================================
                  File Format Differences
=================================================================
The files are identical in content, but differ in format:
$(if ($EncodingDiff) {"- Different file encoding detected"})
$(if ($LineEndingDiff) {"- Different line endings detected (CRLF vs LF)"})

These differences don't affect functionality but may cause issues
with some text editors or version control systems.

Recommendation:
- Keep existing file to preserve current format
- Update file to standardize format across all files

=================================================================
"@
}
function Get-CmdGenReadmeText {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    return @"
# Shortcut to CMD and Nerdio Scripts Conversion Log

This folder contains conversion logs and Nerdio Manager integration files.
Last run: $Timestamp

## Generated Files
The CMD files are located in the parent directory. This folder contains:
- shortcut-conversion.log: Detailed conversion logs
- README.md: This documentation file
- *.ps1: Nerdio Manager PowerShell scripts
- *.metadata: Nerdio Manager metadata files
- import_instructions.md: Step-by-step guide for importing scripts to Nerdio Manager
"@
}

# Add this function at the end of the script with other text functions
function Get-ImportInstructionsText {
    return @"
# Nerdio Manager Script Import Instructions

This guide provides step-by-step instructions for importing the generated scripts into Nerdio Manager.

## Prerequisites

1. Access to Nerdio Manager portal with administrative privileges
2. Generated scripts from the conversion tool in .\Nerdio-Shorcut-Converter-Output folder:
   - PowerShell scripts (*.ps1)
   - Metadata files (*.metadata)

## Import Steps

### 1. Prepare the Files

1. Navigate to the .\Nerdio-Shorcut-Converter-Output folder where the scripts were generated
2. Verify you have matching pairs of files for each shortcut:
   - `{shortcut_name}.ps1`
   - `{shortcut_name}.metadata`

### 2. Copy Files to Nerdio Manager

1. Connect to your Nerdio Manager server
2. Navigate to the Scripted Actions folder:
   \`\`\`
   Default location: C:\ProgramData\Nerdio\ScriptedActions
   \`\`\`
3. Create a new folder for organization (optional):
   \`\`\`
   Example: C:\ProgramData\Nerdio\ScriptedActions\ConvertedShortcuts
   \`\`\`
4. Copy all .ps1 and .metadata files from .\Nerdio-Shorcut-Converter-Output to this location
5. Ensure file permissions are correct:
   - Right-click folder → Properties → Security
   - Verify SYSTEM and Administrators have full control

### 3. Import in Nerdio Manager Portal

1. Log in to Nerdio Manager portal
2. Navigate to:
   \`\`\`
   Settings → Scripted Actions
   \`\`\`
3. Click "Import Scripts"
4. Select the folder where you copied the scripts
5. Verify each script appears in the list with:
   - Correct name
   - Description showing original shortcut settings
   - Parameters (if any) properly displayed

### 4. Test the Scripts

1. Select one of the imported scripts
2. Click "Run Now" or "Test"
3. Verify:
   - Working directory is correct
   - Window style settings are applied
   - Command executes successfully

### 5. Configure Access (Optional)

1. For each script:
   - Click on script name
   - Select "Permissions"
   - Configure who can:
     - View the script
     - Execute the script
     - Modify the script

## Troubleshooting

### Common Issues

1. Script Not Visible
   - Verify files are in correct location
   - Check file permissions
   - Refresh Nerdio Manager portal

2. Execution Errors
   - Check shortcut-conversion.log in .\Nerdio-Shorcut-Converter-Output
   - Verify working directory exists
   - Ensure target application is installed

3. Permission Issues
   - Verify user has appropriate permissions
   - Check execution policy settings
   - Review Nerdio Manager logs

### Support Files

If you encounter issues, check these files:
1. .\Nerdio-Shorcut-Converter-Output\shortcut-conversion.log
2. .\Nerdio-Shorcut-Converter-Output\README.md
3. Original .metadata files for script settings

## Best Practices

1. Organization
   - Use meaningful folder names
   - Keep related scripts together
   - Maintain documentation

2. Testing
   - Test each script after import
   - Verify parameters work correctly
   - Test with different user permissions

3. Maintenance
   - Keep original conversion files as backup
   - Document any manual changes
   - Regular testing of critical scripts

## Notes

- Scripts maintain original shortcut settings
- Window styles can be modified via parameters
- Working directories can be changed if needed
- Each script includes detailed documentation in comments

For additional support, refer to:
- Nerdio Manager documentation
- Original conversion logs
- Generated README.md in .\Nerdio-Shorcut-Converter-Output folder
"@
}

# Add this function at the end of the script with other text functions
function Get-NerdioScriptTemplate {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ShortcutName,

        [Parameter(Mandatory = $true)]
        [string]$CmdPath
    )

    $cmdFileName = [System.IO.Path]::GetFileName($CmdPath)

    return @"
<#
.SYNOPSIS
    Nerdio Manager wrapper for $ShortcutName
.DESCRIPTION
    Executes the batch file $cmdFileName in the specified working directory
.NOTES
    Generated for Nerdio Manager
#>
[CmdletBinding()]
param()

`$ErrorActionPreference = 'Stop'
`$scriptPath = Join-Path `$PSScriptRoot "..\$cmdFileName"

try {
    if (-not (Test-Path `$scriptPath -PathType Leaf)) {
        throw "Batch file not found at: `$scriptPath"
    }

    # Execute the batch file
    `$process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`$scriptPath`"" -Wait -NoNewWindow -PassThru
    if (`$process.ExitCode -ne 0) {
        throw "Batch file execution failed with exit code: `$(`$process.ExitCode)"
    }

    Write-Host "Successfully executed $cmdFileName"
} catch {
    Write-Error "Error executing batch file: `$_"
    throw
}
"@
}

# Add this function at the end of the script with other text functions
function Get-MetadataDescriptionText {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$ShortcutInfo,

        [Parameter(Mandatory = $true)]
        [string]$CmdPath,

        [Parameter(Mandatory = $true)]
        [__ComObject]$Shortcut
    )

    $description = @"
Executes $([System.IO.Path]::GetFileName($CmdPath)) batch file
Original shortcut name: $($ShortcutInfo.Name)

Original Shortcut Settings:
- Target: $($Shortcut.TargetPath)
- Arguments: $($Shortcut.Arguments)
- Working Directory: $($Shortcut.WorkingDirectory)
- Window Style: $($Shortcut.WindowStyle)
"@

    # Add optional settings if they exist
    if ($Shortcut.Hotkey) {
        $description += "- Hotkey: $($Shortcut.Hotkey)`n"
    }
    if ($Shortcut.IconLocation) {
        $description += "- Icon Location: $($Shortcut.IconLocation)`n"
    }
    if ($Shortcut.Description) {
        $description += "- Description: $($Shortcut.Description)`n"
    }

    return $description
}

function GetInitialDialogText {
    param (
        [Parameter(Mandatory = $true)]
        [int]$FileCount,

        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$CurrentPath
    )

    return @"
=================================================================
           Shortcut to CMD and Nerdio Scripts Converter
=================================================================

PLEASE READ CAREFULLY - Important Information:

This tool will process all matching shortcuts ($FileCount files):
Filter: $Filter

Output will be generated as follows:

1. In current folder ($CurrentPath):
   - CMD files converted from your shortcuts
   - These can be run directly from this location

2. In subfolder .\Nerdio-Shorcut-Converter-Output:
   - shortcut-conversion.log: Detailed conversion logs
   - README.md: Documentation and file listing
   - {shortcut_name}.ps1: Nerdio Manager script for each CMD
   - {shortcut_name}.metadata: Nerdio Manager metadata files

Note: For Nerdio Manager integration, copy the PS1 and metadata
files from .\Nerdio-Shorcut-Converter-Output to your Nerdio Manager scripts folder.

=================================================================
"@
}
function Write-Message {
    param([string]$Message)
    [System.IO.File]::AppendAllText($logFile, "$timestamp - $Message`n", $UTF8NoBOM)
}

# Add this function at the start, after the Write-Message function
function Compare-FileContent {
    param (
        [string]$ExistingPath,
        [string]$NewContent,
        [string]$FileType
    )

    if (-not (Test-Path $ExistingPath -PathType Leaf)) {
        Write-Host "Creating new $FileType file."
        Write-Message "Creating new $FileType file: $ExistingPath"
        return $true
    }

    $existingContent = Get-Content $ExistingPath -Raw

    if ($existingContent -eq $NewContent) {
        Write-Host "No changes detected in $FileType file."
        Write-Message "No changes detected in $FileType file: $ExistingPath"
        return $false
    }

    # Convert both contents to arrays for comparison
    $existingLines = @()
    $newLines = @()

    if (-not [string]::IsNullOrEmpty($existingContent)) {
        $existingLines = @($existingContent -split "`n" | ForEach-Object { $_.TrimEnd() })
    }

    if (-not [string]::IsNullOrEmpty($NewContent)) {
        $newLines = @($NewContent -split "`n" | ForEach-Object { $_.TrimEnd() })
    }

    Write-Host "`nDifferences in $FileType file:"
    Write-Host "================================================================="
    Write-Message "Differences detected in $FileType file: $ExistingPath"

    $diffCount = 0
    $maxLines = [Math]::Max($existingLines.Count, $newLines.Count)
    $lineNumberWidth = $maxLines.ToString().Length

    for ($i = 0; $i -lt $maxLines; $i++) {
        $lineNumber = ($i + 1).ToString().PadLeft($lineNumberWidth)
        $existingLine = if ($i -lt $existingLines.Count) { $existingLines[$i] } else { "" }
        $newLine = if ($i -lt $newLines.Count) { $newLines[$i] } else { "" }

        if ($existingLine -ne $newLine) {
            if ($existingLine -ne "") {
                Write-Host "$lineNumber - " -NoNewline
                Write-Host $existingLine -ForegroundColor Red
                Write-Message "Line $lineNumber - Removed: $existingLine"
            }
            if ($newLine -ne "") {
                Write-Host "$lineNumber + " -NoNewline
                Write-Host $newLine -ForegroundColor Green
                Write-Message "Line $lineNumber - Added: $newLine"
            }
            $diffCount++

            # Show a few lines of context if available
            $contextLines = 2
            $contextStart = [Math]::Max(0, $i - $contextLines)
            $contextEnd = [Math]::Min($maxLines - 1, $i + $contextLines)

            Write-Host "Context:" -ForegroundColor Yellow
            for ($j = $contextStart; $j -le $contextEnd; $j++) {
                if ($j -eq $i) { continue } # Skip the different line we just showed
                $contextLineNumber = ($j + 1).ToString().PadLeft($lineNumberWidth)
                $contextLine = if ($j -lt $existingLines.Count) { $existingLines[$j] } else { "" }
                Write-Host "$contextLineNumber   $contextLine" -ForegroundColor DarkGray
            }
            Write-Host "-----------------------------------------------------------------"
        }
    }

    Write-Host "`nTotal differences: $diffCount"
    Write-Host "================================================================="
    Write-Message "Total differences: $diffCount"

    if ($diffCount -eq 0) {
        Write-Host "No changes detected in $FileType file. Overwriting anyway."
        Write-Message "No changes detected in $FileType file: $ExistingPath. Overwrite."
        return $false, "Y"
    }

    $overwrite = Read-Host "Do you want to overwrite the existing $FileType file? (Y/N)"
    if ($overwrite -notmatch '^[Yy]') {
        Write-Host "Skipping $FileType file update"
        Write-Message "User chose not to overwrite $FileType file: $ExistingPath"
        return $false
    }
    else {
        Write-Host "Overwriting $FileType file"
        Write-Message "User chose to overwrite $FileType file: $ExistingPath"
    }
    return $true, $overwrite
}

# Add this at the beginning of the script, after the param block
$UTF8NoBOM = New-Object System.Text.UTF8Encoding $false

# Count files to process
$filesToProcess = @(Get-ChildItem -Path $PWD -Filter $Filter)
$fileCount = $filesToProcess.Count

Write-Host "Debug: Found $fileCount files matching filter '$Filter'"
Write-Host "Debug: Files found:"
foreach ($file in $filesToProcess) {
    Write-Host "- $($file.FullName)"
}

if ($fileCount -eq 0) {
    Write-Host (Get-NoFilesFoundText -Filter $Filter)
    exit
}

# Show initial dialog
$initialDialogText = (GetInitialDialogText -FileCount $fileCount -Filter $Filter -CurrentPath $PWD)
Write-Host $initialDialogText

# Simple confirmation
$continue = Read-Host "Do you understand and want to proceed? (Y/N)"
if ($continue -notmatch '^[Yy]') {
    Write-Host "Operation cancelled by user"
    exit
}

Write-Host "`nStarting conversion...`n"

# Create Nerdio-Shorcut-Converter-Output directory for logs and documentation
$logDir = Join-Path $PWD "Nerdio-Shorcut-Converter-Output"
if (-not (Test-Path $logDir -PathType Container)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

# Initialize logging
$logFile = Join-Path $logDir "shortcut-conversion.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Create or update README.md
$readmePath = Join-Path $logDir "README.md"
Get-CmdGenReadmeText -Timestamp $timestamp | Out-File -FilePath $readmePath -Encoding UTF8

# Create import instructions file
$importInstructionsPath = Join-Path $logDir "import_instructions.md"
Get-ImportInstructionsText | Out-File -FilePath $importInstructionsPath -Encoding UTF8

Write-Message "Generated import instructions at: $importInstructionsPath"

try {
    # Load Windows Script Host COM object
    $shell = New-Object -ComObject WScript.Shell

    # Get all shortcuts matching the filter in current directory
    $shortcuts = Get-ChildItem -Path $PWD -Filter $Filter
    foreach ($shortcutFile in $shortcuts) {
        Write-Host "`nProcessing file: $($shortcutFile.FullName)"

        # Clean up filename to handle spaces safely
        $shortcutPath = $shortcutFile.FullName
        $scriptName = $shortcutFile.BaseName.Trim()

        Write-Host "Shortcut path: $shortcutPath"
        Write-Host "Script name: $scriptName"

        # Create safe filenames (replace multiple spaces with single underscore)
        $safeScriptName = $scriptName -replace '\s+', '_'
        $cmdPath = [System.IO.Path]::ChangeExtension($shortcutPath, "cmd")
        $nerdioScriptPath = Join-Path $logDir "$safeScriptName.ps1"
        $metadataPath = Join-Path $logDir "$safeScriptName.metadata"

        Write-Message "Processing shortcut: $($shortcutFile.Name)"
        Write-Message "Generated safe script name: $safeScriptName"

        try {
            $shortcutObj = $shell.CreateShortcut($shortcutPath)
            $cmdContent = New-Object System.Text.StringBuilder

            # Add original filename as comment
            [void]$cmdContent.AppendLine(":: Original shortcut: $($shortcutFile.Name)")

            # Add header comments for non-default settings
            $headerComments = New-Object System.Collections.ArrayList

            if ($shortcutObj.WindowStyle -ne 1) {
                [void]$headerComments.Add(":: Window Style: $($shortcutObj.WindowStyle)")
            }
            if ($shortcutObj.Hotkey) {
                [void]$headerComments.Add(":: Hotkey: $($shortcutObj.Hotkey)")
            }
            if ($shortcutObj.IconLocation) {
                [void]$headerComments.Add(":: Icon Location: $($shortcutObj.IconLocation)")
            }
            if ($shortcutObj.Description) {
                [void]$headerComments.Add(":: Description: $($shortcutObj.Description)")
            }

            # Add comments to the batch file
            if ($headerComments.Count -gt 0) {
                [void]$cmdContent.AppendLine("@echo off")
                foreach ($comment in $headerComments) {
                    [void]$cmdContent.AppendLine($comment)
                }
                [void]$cmdContent.AppendLine()
            }

            # Add CD command if StartIn directory is specified
            if (![string]::IsNullOrWhiteSpace($shortcutObj.WorkingDirectory)) {
                [void]$cmdContent.AppendLine("CD /D `"$($shortcutObj.WorkingDirectory)`"")
            }

            # Add the target command with arguments
            $command = "start " + $shortcutObj.TargetPath
            if (![string]::IsNullOrWhiteSpace($shortcutObj.Arguments)) {
                $command += " " + $shortcutObj.Arguments
            }

            [void]$cmdContent.AppendLine("`"$command`"")

            # Prepare CMD content
            $cmdContent = $cmdContent.ToString()

            # Check if CMD file exists and compare
            if (Test-Path $cmdPath -PathType Leaf) {
                $hasDiffs, $overwrite = Compare-FileContent -ExistingPath $cmdPath -NewContent $cmdContent -FileType "CMD"
                if ($hasDiffs -and $overwrite -notmatch '^[Yy]') {
                    continue
                }
            }

            # Save the CMD file
            $cmdContent | Out-File -FilePath $cmdPath -Encoding ASCII
            Write-Message "Successfully saved/updated CMD file: $cmdPath"

            # Create Nerdio Manager PowerShell script
            $nerdioScript = Get-NerdioScriptTemplate -ShortcutName $shortcutFile.Name -CmdPath $cmdPath

            # Check if Nerdio script exists and compare
            if (Test-Path $nerdioScriptPath -PathType Leaf) {
                $hasDiffs, $overwrite = Compare-FileContent -ExistingPath $nerdioScriptPath -NewContent $nerdioScript -FileType "Nerdio PowerShell"
                if ($hasDiffs -and $overwrite -notmatch '^[Yy]') {
                    continue
                }
            }
            # Save Nerdio script
            $nerdioScript | Out-File -FilePath $nerdioScriptPath -Encoding UTF8
            Write-Message "Successfully saved/updated Nerdio script: $nerdioScriptPath"

            # Create Nerdio metadata file with enhanced settings
            $metadata = @{
                name        = $safeScriptName
                description = Get-MetadataDescriptionText -ShortcutInfo $shortcutFile -CmdPath $cmdPath -Shortcut $shortcutObj
                script_type = "PowerShell"
                os_type     = "Windows"
                parameters  = $parameters
            }

            # Save metadata file with enhanced settings
            $metadata | ConvertTo-Json -Depth 10 | Out-File -FilePath $metadataPath -Encoding UTF8

            # Update the Nerdio script to use parameters
            $nerdioScript = Get-NerdioScriptWithParametersTemplate -ShortcutName $shortcutFile.Name -CmdPath $cmdPath -Shortcut $shortcutObj

            # Save Nerdio script
            $nerdioScript | Out-File -FilePath $nerdioScriptPath -Encoding UTF8

            # Update README with processed file
            "- Processed: $($shortcutFile.Name)" | Add-Content -Path $readmePath
            "  - CMD file: $([System.IO.Path]::GetFileName($cmdPath))" | Add-Content -Path $readmePath
            "  - Nerdio script: $safeScriptName.ps1" | Add-Content -Path $readmePath

        }
        catch {
            Write-Host "Error processing shortcut $($shortcutFile.Name): $($_.Exception.Message)"
            Write-Message "Error processing shortcut $($shortcutFile.Name): $($_.Exception.Message)"
            if (Test-Path $cmdPath -PathType Leaf) {
                Remove-Item $cmdPath -Force
            }
            throw
        }
    }

}
catch {
    Write-Message "Critical error: $($_.Exception.Message)"
    throw
}
finally {
    if ($null -ne $shell) {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
}

Write-Host (Get-CompletionText -CurrentPath $PWD -LogDir $logDir)
# Add this function at the end of the script with other text functions

