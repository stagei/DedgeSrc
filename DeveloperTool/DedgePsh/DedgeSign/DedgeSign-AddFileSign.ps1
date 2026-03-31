<#
.SYNOPSIS
Signs a single file using Azure Trusted Signing.

.DESCRIPTION
This script signs a single file using Azure Trusted Signing. It is used by Sign-Files.ps1 but can also be called directly.

.NOTES
Developer: Geir Helge Starholm (Dedge AS)
Copyright: Dedge AS
This is part of Dedge's custom signing tools that use Azure Trusted Signing.

.PARAMETER FilePath
The path to the file to sign.

.EXAMPLE
.\Sign-SingleFile.ps1 -FilePath "C:\MyApp\bin\Release\MyApp.exe"
Signs the specified file using Azure Trusted Signing.

.NOTES
This is part of Dedge's custom signing tools that use Azure Trusted Signing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
    [string]$FilePath
)

Import-Module "$PSScriptRoot\DedgeSign.psm1"

# if path is not provided, show a help dialog related to usage of the script
if (-not $FilePath) {
    Write-Log "Usage: .\DedgeSign-AddFileSign.ps1 -FilePath <path>"
    exit
}

# Check if file exists
if (-not (Test-Path $FilePath -PathType Leaf)) {
    Write-Log "Error: File not found - $FilePath" -ForegroundColor Red
    exit 1
}

# Check if file is already signed
if (Test-FileSignature -FilePath $FilePath) {
    Write-Log "File is already signed." -ForegroundColor Yellow
    exit 0
}
$extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
if (-not $extension -match '\.(ps1|psm1|psd1|vbs|wsf|js|exe|dll|msi|sys|ocx|ax|cpl|drv|efi|mui|scr|tsp|plugin|xll|wll|pyd|pyo|pyc|jar|war|ear|class|xpi|crx|nex|xbap|application|manifest|appref-ms|gadget|widget|ipa|apk|xap|msix|msixbundle|appx|appxbundle|msp|mst|msu|tlb|com)$')
{
    Write-Log "Unsupported file type for signing: $extension" -ForegroundColor Yellow
    exit 0
}
# SignTool path
$signToolPath = Get-DefaultSignToolPath
$dlibPath = Get-DefaultDlibPath
$metadataPath = Get-MetadataFile

try {
    # Sign the file using internal Azure settings
    $signArgs = @(
        "sign",
        "/v",
        "/debug",
        "/fd", "SHA256",
        "/tr", "http://timestamp.acs.microsoft.com",
        "/td", "SHA256",
        "/dlib", $dlibPath,
        "/dmdf", $metadataPath,
        $FilePath
    )

    Write-Log "Running SignTool..."
    $result = & $signToolPath $signArgs 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Log "Successfully signed: $FilePath" -ForegroundColor Green
        exit 0
    } else {
        Write-Log "Failed to sign file. Exit code: $LASTEXITCODE. Output: $result" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
catch {
    Write-Log "Error signing file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

