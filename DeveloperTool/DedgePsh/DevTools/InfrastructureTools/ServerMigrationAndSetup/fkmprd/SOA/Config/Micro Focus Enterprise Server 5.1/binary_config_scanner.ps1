<#
.SYNOPSIS
    Scans binary Micro Focus Enterprise Server configuration files for IP addresses and hostnames.
.DESCRIPTION
    This script recursively searches through binary .dat files in a specified directory and
    identifies potential IP addresses and hostnames without modifying any files.
.PARAMETER Directory
    The directory containing the configuration files to scan.
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$Directory
)

# Function to find potential IP addresses in binary content
function Find-IPAddresses {
    param (
        [byte[]]$BinaryContent,
        [string]$AsciiContent
    )

    # Regular expression for IPv4 addresses in ASCII representation
    $ipPattern = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'

    $matches = [regex]::Matches($AsciiContent, $ipPattern)
    $uniqueIPs = @()

    foreach ($match in $matches) {
        if ($uniqueIPs -notcontains $match.Value) {
            $uniqueIPs += $match.Value
        }
    }

    return $uniqueIPs
}

# Function to find potential hostnames in binary content
function Find-Hostnames {
    param (
        [byte[]]$BinaryContent,
        [string]$AsciiContent
    )

    # Look for potential hostname patterns in ASCII representation
    $hostnamePattern = '\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b'

    $matches = [regex]::Matches($AsciiContent, $hostnamePattern)
    $uniqueHostnames = @()

    foreach ($match in $matches) {
        if ($uniqueHostnames -notcontains $match.Value) {
            $uniqueHostnames += $match.Value
        }
    }

    # Also look for potential non-FQDN hostnames
    # For binary files, we'll look for sequences that look like hostnames
    $simpleHostPattern = '\b[a-zA-Z0-9][a-zA-Z0-9\-]{2,}[a-zA-Z0-9]\b'

    $matches = [regex]::Matches($AsciiContent, $simpleHostPattern)
    foreach ($match in $matches) {
        # Filter out common words that might match the pattern but aren't hostnames
        $commonWords = @("http", "https", "file", "soap", "region", "client", "scheme", "accept", "listener")
        $isCommonWord = $false
        foreach ($word in $commonWords) {
            if ($match.Value -eq $word) {
                $isCommonWord = $true
                break
            }
        }

        if (-not $isCommonWord -and $uniqueHostnames -notcontains $match.Value) {
            $uniqueHostnames += $match.Value
        }
    }

    return $uniqueHostnames
}

# Function to process a single binary file
function Process-BinaryConfigFile {
    param (
        [string]$FilePath
    )

    Write-Host "`nProcessing: $FilePath"

    try {
        # Read the file as binary
        $binaryContent = [System.IO.File]::ReadAllBytes($FilePath)

        # Check if the file is empty
        if ($binaryContent.Length -eq 0) {
            Write-Host "  Skipping empty file." -ForegroundColor Yellow
            return
        }

        # Convert binary content to ASCII for pattern matching
        # This is a simplified approach that may not work for all binary formats
        $asciiContent = [System.Text.Encoding]::ASCII.GetString($binaryContent)

        # Find IP addresses
        $ipAddresses = Find-IPAddresses -BinaryContent $binaryContent -AsciiContent $asciiContent

        if ($ipAddresses.Count -gt 0) {
            Write-Host "  Found potential IP addresses:" -ForegroundColor Green
            foreach ($ip in $ipAddresses) {
                Write-Host "    - $ip"
            }
        } else {
            Write-Host "  No IP addresses found." -ForegroundColor Yellow
        }

        # Find hostnames
        $hostnames = Find-Hostnames -BinaryContent $binaryContent -AsciiContent $asciiContent

        if ($hostnames.Count -gt 0) {
            Write-Host "  Found potential hostnames:" -ForegroundColor Green
            foreach ($hostname in $hostnames) {
                Write-Host "    - $hostname"
            }
        } else {
            Write-Host "  No hostnames found." -ForegroundColor Yellow
        }

        # Additionally, show a hex dump of the first few bytes to help identify the file format
        Write-Host "  First 32 bytes (hex):" -ForegroundColor Cyan
        $hexDump = ""
        $asciiDump = ""
        for ($i = 0; $i -lt [Math]::Min(32, $binaryContent.Length); $i++) {
            $hexDump += " " + $binaryContent[$i].ToString("X2")
            # Display ASCII representation for printable characters
            if ($binaryContent[$i] -ge 32 -and $binaryContent[$i] -le 126) {
                $asciiDump += [char]$binaryContent[$i]
            } else {
                $asciiDump += "."
            }
        }
        Write-Host "    Hex:$hexDump" -ForegroundColor Cyan
        Write-Host "    ASCII: $asciiDump" -ForegroundColor Cyan

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

# Find all .dat files recursively
$configFiles = Get-ChildItem -Path $Directory -Filter "*.dat" -Recurse -File

if ($configFiles.Count -eq 0) {
    Write-Host "No .dat files found in: $Directory" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($configFiles.Count) configuration files" -ForegroundColor Cyan

# Process each file
foreach ($file in $configFiles) {
    Process-BinaryConfigFile -FilePath $file.FullName
}

Write-Host "`nScan completed. Processed $($configFiles.Count) files." -ForegroundColor Cyan

