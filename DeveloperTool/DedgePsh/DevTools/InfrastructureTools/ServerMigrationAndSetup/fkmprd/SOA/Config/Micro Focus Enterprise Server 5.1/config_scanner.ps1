<#
.SYNOPSIS
    Scans Micro Focus Enterprise Server configuration files for IP addresses and hostnames.
.DESCRIPTION
    This script recursively searches through .dat files in a specified directory and
    identifies potential IP addresses and hostnames without modifying any files.
    It also creates text copies of each file in a subfolder while preserving the directory structure.
.PARAMETER Directory
    The directory containing the configuration files to scan.
.PARAMETER OutputDirectory
    The directory where text copies will be created. Defaults to "TextCopies" subfolder.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$Directory = "$env:OptPath\src\DedgePsh\DevTools\InfrastructureTools\ServerSetup\fkmprd\SOA\Config\Micro Focus Enterprise Server 5.1",

    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = "TextCopies"
)

# Function to find potential IP addresses in text
function Find-IPAddresses {
    param (
        [string]$Content
    )

    # Regular expression for IPv4 addresses
    $ipPattern = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'

    $matches = [regex]::Matches($Content, $ipPattern)
    $uniqueIPs = @()

    foreach ($match in $matches) {
        if ($uniqueIPs -notcontains $match.Value) {
            $uniqueIPs += $match.Value
        }
    }

    return $uniqueIPs
}

# Function to find potential hostnames in text
function Find-Hostnames {
    param (
        [string]$Content
    )

    # Look for potential hostname patterns
    # This is a basic pattern that might need adjustment based on your specific hostname format
    $hostnamePattern = '\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b'

    $matches = [regex]::Matches($Content, $hostnamePattern)
    $uniqueHostnames = @()

    foreach ($match in $matches) {
        if ($uniqueHostnames -notcontains $match.Value) {
            $uniqueHostnames += $match.Value
        }
    }

    # Also look for potential non-FQDN hostnames (simple names without dots)
    $simpleHostPattern = '(?<=\bhost(?:name)?=|\bserver=|\bURL=|\bscheme=)[a-zA-Z0-9\-]{2,}(?!\.[a-zA-Z0-9])'

    $matches = [regex]::Matches($Content, $simpleHostPattern)
    foreach ($match in $matches) {
        if ($uniqueHostnames -notcontains $match.Value) {
            $uniqueHostnames += $match.Value
        }
    }

    return $uniqueHostnames
}

# Function to create text copy of a file
function Create-TextCopy {
    param (
        [string]$SourcePath,
        [string]$BaseSourceDir,
        [string]$OutputDir
    )

    # Get the relative path to maintain directory structure
    $relativePath = (Get-Item $SourcePath).DirectoryName.Substring($BaseSourceDir.Length)
    if ($relativePath.StartsWith("\")) {
        $relativePath = $relativePath.Substring(1)
    }

    # Create the target directory if it doesn't exist
    $targetDir = Join-Path -Path $OutputDir -ChildPath $relativePath
    if (-not (Test-Path -Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }

    # Create the target file path with .txt extension
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath) + ".txt"
    $targetPath = Join-Path -Path $targetDir -ChildPath $fileName

    try {
        # Read the binary file as bytes
        $bytes = [System.IO.File]::ReadAllBytes($SourcePath)

        # Convert binary content to hex representation
        $hexOutput = New-Object System.Text.StringBuilder

        # Add header
        $hexOutput.AppendLine("Binary file converted to text format") | Out-Null
        $hexOutput.AppendLine("Original file: $SourcePath") | Out-Null
        $hexOutput.AppendLine("Conversion date: $(Get-Date)") | Out-Null
        $hexOutput.AppendLine("") | Out-Null
        $hexOutput.AppendLine("Offset    00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  ASCII") | Out-Null
        $hexOutput.AppendLine("--------  -----------------------------------------------  ----------------") | Out-Null

        # Process 16 bytes per line
        for ($i = 0; $i -lt $bytes.Length; $i += 16) {
            # Offset
            $hexOutput.Append(("{0:X8}  " -f $i)) | Out-Null

            $asciiLine = ""

            # Process each byte in the current line
            for ($j = 0; $j -lt 16; $j++) {
                if ($i + $j -lt $bytes.Length) {
                    # Hex representation
                    $hexOutput.Append(("{0:X2} " -f $bytes[$i + $j])) | Out-Null

                    # ASCII representation (printable characters only)
                    $byte = $bytes[$i + $j]
                    if ($byte -ge 32 -and $byte -le 126) {
                        $asciiLine += [char]$byte
                    } else {
                        $asciiLine += "."
                    }
                } else {
                    # Padding for incomplete lines
                    $hexOutput.Append("   ") | Out-Null
                    $asciiLine += " "
                }
            }

            # Add ASCII representation
            $hexOutput.AppendLine(" $asciiLine") | Out-Null
        }

        # Write the hex dump to the target file
        Set-Content -Path $targetPath -Value $hexOutput.ToString() -Encoding UTF8
        Write-Host "  Created text copy: $targetPath" -ForegroundColor Cyan
    }
    catch {
        Write-Host "  Error creating text copy: $_" -ForegroundColor Red
    }
}

# Function to process a single file
function Process-ConfigFile {
    param (
        [string]$FilePath,
        [string]$BaseDir,
        [string]$OutputDir
    )

    Write-Host "`nProcessing: $FilePath"

    try {
        # Read the file content
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop

        # Check if the file is empty
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Host "  Skipping empty file." -ForegroundColor Yellow
            return
        }

        # Find IP addresses
        $ipAddresses = Find-IPAddresses -Content $content

        if ($ipAddresses.Count -gt 0) {
            Write-Host "  Found potential IP addresses:" -ForegroundColor Green
            foreach ($ip in $ipAddresses) {
                Write-Host "    - $ip"
            }
        } else {
            Write-Host "  No IP addresses found." -ForegroundColor Yellow
        }

        # Find hostnames
        $hostnames = Find-Hostnames -Content $content

        if ($hostnames.Count -gt 0) {
            Write-Host "  Found potential hostnames:" -ForegroundColor Green
            foreach ($hostname in $hostnames) {
                Write-Host "    - $hostname"
            }
        } else {
            Write-Host "  No hostnames found." -ForegroundColor Yellow
        }

        # Create text copy of the file
        Create-TextCopy -SourcePath $FilePath -BaseSourceDir $BaseDir -OutputDir $OutputDir

    } catch {
        Write-Host "  Error processing file: $_" -ForegroundColor Red
    }
}

# Main script execution

# Verify the directory exists
if (-not (Test-Path -Path $Directory)) {
    Write-Host "Directory not found: $Directory" -ForegroundColor Red
    exit 1
}

# Create full path for output directory
$fullOutputPath = Join-Path -Path $Directory -ChildPath $OutputDirectory

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $fullOutputPath)) {
    New-Item -Path $fullOutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory: $fullOutputPath" -ForegroundColor Cyan
}

# Find all .dat files recursively
$configFiles = Get-ChildItem -Path $Directory -Filter "*.dat" -Recurse -File

if ($configFiles.Count -eq 0) {
    Write-Host "No .dat files found in: $Directory" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($configFiles.Count) configuration files" -ForegroundColor Cyan

# Process each file
foreach ($file in $configFiles) {
    Process-ConfigFile -FilePath $file.FullName -BaseDir $Directory -OutputDir $fullOutputPath
}

Write-Host "`nScan completed. Processed $($configFiles.Count) files." -ForegroundColor Cyan
Write-Host "Text copies created in: $fullOutputPath" -ForegroundColor Cyan

