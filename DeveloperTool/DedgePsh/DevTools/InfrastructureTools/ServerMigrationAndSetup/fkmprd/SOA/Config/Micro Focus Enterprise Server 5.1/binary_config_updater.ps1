<#
.SYNOPSIS
    Updates IP addresses and hostnames in binary Micro Focus Enterprise Server configuration files.
.DESCRIPTION
    This script replaces IP addresses or hostnames in binary .dat files with new values,
    handling cases where the replacement string is longer than the original.
.PARAMETER FilePath
    The path to the binary file to modify.
.PARAMETER OldValue
    The old IP address, hostname, or pattern to search for.
.PARAMETER NewValue
    The new IP address, hostname, or pattern to replace with.
.PARAMETER BackupFile
    Whether to create a backup of the original file before modifying. Default is true.
.PARAMETER Force
    Force the replacement even when the replacement string is longer, which may cause binary format issues.
.PARAMETER Context
    Number of bytes to show before and after the match for context. Default is 16.
.EXAMPLE
    .\binary_config_updater.ps1 -FilePath "file.dat" -OldValue ".16.11:86" -NewValue ".101.138:86" -Force
.EXAMPLE
    .\binary_config_updater.ps1 -FilePath "file.dat" -OldValue "oldserver" -NewValue "newserver"
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$true)]
    [string]$OldValue,

    [Parameter(Mandatory=$true)]
    [string]$NewValue,

    [Parameter(Mandatory=$false)]
    [bool]$BackupFile = $true,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [int]$Context = 16
)

# Function to create a hex dump of a byte array
function Get-HexDump {
    param (
        [byte[]]$Bytes,
        [int]$StartOffset = 0,
        [int]$Length = $Bytes.Length,
        [int]$Width = 16
    )

    $hexDump = New-Object System.Text.StringBuilder
    $asciiDump = New-Object System.Text.StringBuilder

    $endOffset = [Math]::Min($StartOffset + $Length, $Bytes.Length)

    for ($i = $StartOffset; $i -lt $endOffset; $i++) {
        if (($i - $StartOffset) % $Width -eq 0) {
            if ($i -gt $StartOffset) {
                $hexDump.Append("  ")
                $hexDump.AppendLine($asciiDump.ToString())
                $asciiDump.Clear() | Out-Null
            }
            $hexDump.Append(("{0:X8}  " -f $i))
        }

        $hexDump.Append(("{0:X2} " -f $Bytes[$i]))

        if ($Bytes[$i] -ge 32 -and $Bytes[$i] -le 126) {
            $asciiDump.Append([char]$Bytes[$i])
        } else {
            $asciiDump.Append(".")
        }
    }

    # Pad the last line if needed
    $remaining = $Width - (($endOffset - $StartOffset) % $Width)
    if ($remaining -ne $Width) {
        for ($i = 0; $i -lt $remaining; $i++) {
            $hexDump.Append("   ")
        }
    }

    $hexDump.Append("  ")
    $hexDump.Append($asciiDump.ToString())

    return $hexDump.ToString()
}

# Function to create a sanitized filename string
function Get-SafeFilenameString {
    param (
        [string]$Value
    )

    # Replace characters that are invalid in filenames
    $result = $Value -replace '[\\\/\:\*\?\"\<\>\|]', '_'
    # Limit length to avoid overly long filenames
    if ($result.Length -gt 20) {
        $result = $result.Substring(0, 20)
    }
    return $result
}

# Function to find all occurrences of a byte pattern in a byte array
function Find-BytePattern {
    param (
        [byte[]]$Source,
        [byte[]]$Pattern
    )

    $positions = @()

    for ($i = 0; $i -le $Source.Length - $Pattern.Length; $i++) {
        $match = $true

        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Source[$i + $j] -ne $Pattern[$j]) {
                $match = $false
                break
            }
        }

        if ($match) {
            $positions += $i
        }
    }

    return $positions
}

# Check if file exists
if (-not (Test-Path -Path $FilePath)) {
    Write-Host "Error: File not found: $FilePath" -ForegroundColor Red
    exit 1
}

try {
    # Detect if we're working with an IP or hostname
    $valueType = if ($OldValue -match "\d+\.\d+\.\d+") { "IP address" } else { "hostname" }

    # Read the binary file
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    Write-Host "File Size: $($fileBytes.Length) bytes" -ForegroundColor Cyan

    # Convert strings to byte arrays
    $oldBytes = [System.Text.Encoding]::ASCII.GetBytes($OldValue)
    $newBytes = [System.Text.Encoding]::ASCII.GetBytes($NewValue)

    # Check length difference
    $lengthDifference = $newBytes.Length - $oldBytes.Length
    if ($lengthDifference -gt 0) {
        Write-Host "Warning: New $valueType is $lengthDifference byte(s) longer than the original." -ForegroundColor Yellow
        if (-not $Force) {
            Write-Host "This might corrupt the binary file structure. Use -Force to override." -ForegroundColor Yellow
            Write-Host "Operation canceled." -ForegroundColor Red
            exit 1
        } else {
            Write-Host "Forcing replacement despite length difference. This may corrupt the file." -ForegroundColor Red
        }
    } elseif ($lengthDifference -lt 0) {
        Write-Host "Note: New $valueType is $(-$lengthDifference) byte(s) shorter. Padding with nulls (0x00)." -ForegroundColor Yellow
    }

    # Find all occurrences of the pattern
    $positions = Find-BytePattern -Source $fileBytes -Pattern $oldBytes

    if ($positions.Count -eq 0) {
        Write-Host "No matches found for '$OldValue'" -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Found $($positions.Count) occurrence(s) of '$OldValue'" -ForegroundColor Green

    # Display each occurrence with context
    foreach ($pos in $positions) {
        $contextStart = [Math]::Max(0, $pos - $Context)
        $contextLength = $Context + $oldBytes.Length + $Context
        Write-Host "`nMatch at offset: 0x$($pos.ToString("X8"))" -ForegroundColor Green
        Write-Host "Context before modification:" -ForegroundColor Cyan
        Write-Host (Get-HexDump -Bytes $fileBytes -StartOffset $contextStart -Length $contextLength)
    }

    # Confirm replacement
    $confirmation = Read-Host "`nReplace all occurrences? (Y/N)"
    if ($confirmation -ne "Y" -and $confirmation -ne "y") {
        Write-Host "Operation canceled." -ForegroundColor Yellow
        exit 0
    }

    # Create backup if requested
    if ($BackupFile) {
        # Extract file information for creating the backup name
        $fileInfo = Get-Item -Path $FilePath
        $directory = $fileInfo.DirectoryName
        $filename = $fileInfo.BaseName
        $extension = $fileInfo.Extension

        # Create a safe version of the values for the filename
        $safeOldValue = Get-SafeFilenameString -Value $OldValue
        $safeNewValue = Get-SafeFilenameString -Value $NewValue

        # Get the current timestamp in a filename-friendly format
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

        # Create the backup path with replacement info
        $backupPath = Join-Path -Path $directory -ChildPath "$filename`_$safeOldValue`_to_$safeNewValue`_$timestamp$extension"

        # Save the backup
        [System.IO.File]::WriteAllBytes($backupPath, $fileBytes)
        Write-Host "Created backup at: $backupPath" -ForegroundColor Green
    }

    # Create new byte array for the modified file
    if ($lengthDifference -eq 0) {
        # Same length - simple replacement
        $newFileBytes = $fileBytes.Clone()

        # Replace each occurrence
        foreach ($pos in $positions) {
            for ($i = 0; $i -lt $newBytes.Length; $i++) {
                $newFileBytes[$pos + $i] = $newBytes[$i]
            }
        }
    } else {
        # Different length - need to build a new array
        $modifiedFile = New-Object System.Collections.Generic.List[byte]
        $lastPos = 0

        foreach ($pos in $positions) {
            # Add bytes before the match
            for ($i = $lastPos; $i -lt $pos; $i++) {
                $modifiedFile.Add($fileBytes[$i])
            }

            # Add the replacement bytes
            $modifiedFile.AddRange($newBytes)

            # If new string is shorter, pad with nulls to maintain structure
            if ($lengthDifference -lt 0) {
                for ($i = 0; $i -lt (-$lengthDifference); $i++) {
                    $modifiedFile.Add(0)
                }
            }

            $lastPos = $pos + $oldBytes.Length
        }

        # Add remaining bytes after the last match
        for ($i = $lastPos; $i -lt $fileBytes.Length; $i++) {
            $modifiedFile.Add($fileBytes[$i])
        }

        $newFileBytes = $modifiedFile.ToArray()
    }

    # Save the modified file
    [System.IO.File]::WriteAllBytes($FilePath, $newFileBytes)
    Write-Host "`nFile updated successfully." -ForegroundColor Green

    # Display first match again for confirmation
    if ($positions.Count -gt 0) {
        $pos = $positions[0]
        $contextStart = [Math]::Max(0, $pos - $Context)
        $contextLength = $Context + $newBytes.Length + $Context
        Write-Host "`nVerifying first match at offset: 0x$($pos.ToString("X8"))" -ForegroundColor Green
        Write-Host "Context after modification:" -ForegroundColor Cyan
        Write-Host (Get-HexDump -Bytes $newFileBytes -StartOffset $contextStart -Length $contextLength)
    }

} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

