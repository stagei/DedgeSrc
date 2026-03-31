<#
.SYNOPSIS
Removes digital signature from a single file.

.DESCRIPTION
This script removes digital signature from a single file. It is used by Remove-Signature.ps1 but can also be called directly.

.NOTES
Developer: Geir Helge Starholm (Dedge AS)
Copyright: Dedge AS
This is part of Dedge's custom signing tools that use Azure Trusted Signing.

.PARAMETER FilePath
The path to the file to remove signature from.

.EXAMPLE
.\Remove-SingleSignature.ps1 -FilePath "C:\MyApp\bin\Release\MyApp.exe"
Removes digital signature from the specified file.

.NOTES
This is part of Dedge's custom signing tools that use Azure Trusted Signing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
    [string]$FilePath
)
function Get-SignDataFolder {
    $dataFolder = Join-Path $env:OptPath "data" "DedgeSign"
    if (-not (Test-Path $dataFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $dataFolder | Out-Null
    }
    return $dataFolder
}
Import-Module "$PSScriptRoot\DedgeSign.psm1"

# if path is not provided, show a help dialog related to usage of the script
if (-not $FilePath) {
    Write-Log "Usage: .\DedgeSign-RemoveFileSign.ps1 -FilePath <path>"
    exit
}

# Check if file exists
if (-not (Test-Path $FilePath -PathType Leaf)) {
    Write-Log "Error: File not found - $FilePath" -ForegroundColor Red
    exit 1
}

# Check if file has a signature to remove
if (-not (Test-FileSignature -FilePath $FilePath)) {
    Write-Log "File is not signed." -ForegroundColor Yellow
    exit 0
}

# SignTool path (updated to match your environment)
$signToolPath = Get-DefaultSignToolPath

try {
    # Remove signature from the file
    Write-Log "Running signature removal..."

    # Check file extension
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

    # Script files use content replacement
    if ($extension -match '\.(ps1|psm1|psd1|vbs|wsf|js)$') {
        Write-Log "Using script signature removal method..."
        $content = Get-Content -Path $FilePath -Raw
        $newContent = $content -replace '# SIG # Begin signature block[\s\S]*# SIG # End signature block', ''
        $newContent | Set-Content -Path $FilePath -NoNewline
    }
    # Binary/Executable files use SignTool
    elseif ($extension -match '\.(exe|dll|msi|sys|ocx|ax|cpl|drv|efi|mui|scr|tsp|plugin|xll|wll|pyd|pyo|pyc|jar|war|ear|class|xpi|crx|nex|xbap|application|manifest|appref-ms|gadget|widget|ipa|apk|xap|msix|msixbundle|appx|appxbundle|msp|mst|msu|tlb|com)$') {
        Write-Log "Using SignTool removal method..."
        $result = & $signToolPath remove /s $FilePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "SignTool Error: $result" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
    # Unknown file type
    else {
        Write-Log "Unsupported file type for signature removal: $extension" -ForegroundColor Yellow
        exit 1
    }

    Write-Log "Successfully removed signature from: $FilePath" -ForegroundColor Green
    exit 0
}
catch {
    Write-Log "Error removing signature: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

