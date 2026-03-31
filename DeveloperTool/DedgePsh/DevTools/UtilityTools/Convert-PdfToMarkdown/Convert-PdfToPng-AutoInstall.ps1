# Convert-PdfToPng-AutoInstall.ps1
# PowerShell script that automatically downloads and installs MuPDF if missing
# Then converts PDF files to PNG images
#
# Author: Geir Helge Starholm, www.dEdge.no
# Created: 2025-08-29

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$PdfPath,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$OutputPath = "",

    [Parameter(Mandatory=$false)]
    [int]$DPI = 300,

    [Parameter(Mandatory=$false)]
    [int]$Page = 1,

    [Parameter(Mandatory=$false)]
    [switch]$AllPages,

    [Parameter(Mandatory=$false)]
    [switch]$Force  # Force reinstall MuPDF
)

# Import required modules
Import-Module GlobalFunctions -Force

# Global variables
$script:MuPDFInstallPath = "$env:LOCALAPPDATA\MuPDF"
$script:MudrawExe = "$script:MuPDFInstallPath\mudraw.exe"

function Test-MuPDFInstalled {
    # Check if mudraw.exe exists in our local installation
    if (Test-Path $script:MudrawExe) {
        return $true
    }

    # Check if MuPDF is in PATH
    $mudrawInPath = Get-Command "mudraw.exe" -ErrorAction SilentlyContinue
    if ($mudrawInPath) {
        $script:MudrawExe = $mudrawInPath.Source
        return $true
    }

    return $false
}

function Install-MuPDF {
    Write-LogMessage "Installing MuPDF..." -Level INFO -ForegroundColor Yellow

    try {
        # Create installation directory
        if (-not (Test-Path $script:MuPDFInstallPath)) {
            New-Item -ItemType Directory -Path $script:MuPDFInstallPath -Force | Out-Null
        }

        # MuPDF download URL (latest Windows x64 build)
        $downloadUrl = "https://mupdf.com/downloads/mupdf-1.24.10-windows.zip"
        $zipFile = "$env:TEMP\mupdf-windows.zip"
        $extractPath = "$env:TEMP\mupdf-extract"

        Write-LogMessage "  Downloading MuPDF from $downloadUrl..." -Level DEBUG -ForegroundColor Gray

        # Download MuPDF
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $zipFile)

        Write-LogMessage "  Download completed. Extracting..." -Level DEBUG -ForegroundColor Gray

        # Extract ZIP file
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractPath)

        # Find the extracted MuPDF directory
        $mupdfDir = Get-ChildItem $extractPath -Directory | Where-Object { $_.Name -like "mupdf-*" } | Select-Object -First 1

        if (-not $mupdfDir) {
            throw "Could not find extracted MuPDF directory"
        }

        Write-LogMessage "  Installing to $script:MuPDFInstallPath..." -Level DEBUG -ForegroundColor Gray

        # Copy executables to our installation directory
        $sourceDir = $mupdfDir.FullName
        Get-ChildItem "$sourceDir\*.exe" | ForEach-Object {
            Copy-Item $_.FullName $script:MuPDFInstallPath -Force
        }

        # Copy any DLL files
        Get-ChildItem "$sourceDir\*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName $script:MuPDFInstallPath -Force
        }

        # Clean up temporary files
        Remove-Item $zipFile -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        # Verify installation
        if (Test-Path $script:MudrawExe) {
            Write-LogMessage "  ✓ MuPDF installed successfully!" -Level INFO -ForegroundColor Green
            return $true
        } else {
            throw "Installation verification failed - mudraw.exe not found"
        }
    }
    catch {
        Write-LogMessage "  ✗ Failed to install MuPDF: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red

        # Fallback: Try to download from GitHub releases
        Write-LogMessage "  Trying alternative download source..." -Level WARN -ForegroundColor Yellow

        try {
            # Alternative download from GitHub (if available)
            $altUrl = "https://github.com/ArtifexSoftware/mupdf/releases/download/1.24.10/mupdf-1.24.10-windows.zip"
            Write-LogMessage "  Downloading from GitHub: $altUrl..." -Level DEBUG -ForegroundColor Gray

            $webClient.DownloadFile($altUrl, $zipFile)

            # Extract and install (same process as above)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractPath)
            $mupdfDir = Get-ChildItem $extractPath -Directory | Where-Object { $_.Name -like "mupdf-*" } | Select-Object -First 1

            if ($mupdfDir) {
                Get-ChildItem "$($mupdfDir.FullName)\*.exe" | ForEach-Object {
                    Copy-Item $_.FullName $script:MuPDFInstallPath -Force
                }

                if (Test-Path $script:MudrawExe) {
                    Write-LogMessage "  ✓ MuPDF installed successfully from alternative source!" -Level INFO -ForegroundColor Green
                    return $true
                }
            }
        }
        catch {
            Write-LogMessage "  ✗ Alternative download also failed: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        }

        return $false
    }
}

function Get-PdfPageCount {
    param([string]$PdfFile)

    try {
        # Use mudraw to get PDF info
        $result = & $script:MudrawExe -I $PdfFile 2>&1

        # Look for page count in output
        foreach ($line in $result) {
            if ($line -match "pages:\s*(\d+)") {
                return [int]$Matches[1]
            }
        }

        # Fallback method: try to render pages until we get an error
        for ($i = 1; $i -le 100; $i++) {
            $testArgs = @("-r", "72", "-o", "$env:TEMP\test.png", $PdfFile, $i.ToString())
            $null = & $script:MudrawExe @testArgs 2>&1

            if ($LASTEXITCODE -ne 0) {
                Remove-Item "$env:TEMP\test.png" -ErrorAction SilentlyContinue
                return $i - 1
            }
            Remove-Item "$env:TEMP\test.png" -ErrorAction SilentlyContinue
        }

        return 1
    }
    catch {
        Write-LogMessage "Warning: Could not determine page count, assuming 1 page" -Level WARN -ForegroundColor Yellow
        return 1
    }
}

function Convert-PdfPageToPng {
    param(
        [string]$InputPdf,
        [string]$OutputPng,
        [int]$DPI,
        [int]$PageNumber
    )

    try {
        Write-LogMessage "  Converting page $PageNumber..." -Level INFO -ForegroundColor Cyan

        # Build mudraw command arguments
        $mudrawArgs = @(
            "-r", $DPI.ToString()     # Resolution
            "-o", $OutputPng          # Output file
            $InputPdf                 # Input PDF
            $PageNumber.ToString()    # Page number
        )

        # Execute mudraw
        $result = & $script:MudrawExe @mudrawArgs 2>&1

        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPng)) {
            $fileInfo = Get-Item $OutputPng
            $fileSizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
            Write-LogMessage "  ✓ Page $PageNumber converted successfully ($fileSizeKB KB)" -Level INFO -ForegroundColor Green
            return $true
        } else {
            Write-LogMessage "  ✗ Failed to convert page $PageNumber" -Level ERROR -ForegroundColor Red
            Write-LogMessage "    Error: $result" -Level ERROR -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error converting page $PageNumber : $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $false
    }
}

function Convert-PdfToPng {
    param(
        [string]$InputPdf,
        [string]$OutputPng,
        [int]$DPI,
        [int]$PageNumber,
        [bool]$ConvertAllPages
    )

    $successCount = 0

    if ($ConvertAllPages) {
        Write-LogMessage "Getting PDF page count..." -Level WARN -ForegroundColor Yellow
        $pageCount = Get-PdfPageCount -PdfFile $InputPdf
        Write-LogMessage "PDF has $pageCount pages" -Level DEBUG -ForegroundColor Gray
        Write-LogMessage ""

        for ($i = 1; $i -le $pageCount; $i++) {
            $pageOutput = $OutputPng -replace "\.png$", "_page$i.png"

            if (Convert-PdfPageToPng -InputPdf $InputPdf -OutputPng $pageOutput -DPI $DPI -PageNumber $i) {
                $successCount++
            }
        }

        Write-LogMessage ""
        if($successCount -eq $pageCount) {
            Write-LogMessage "Converted $successCount of $pageCount pages" -Level INFO -ForegroundColor Green
        } else {
            Write-LogMessage "Converted $successCount of $pageCount pages" -Level WARN -ForegroundColor Yellow
        }

        return $successCount -gt 0
    } else {
        return Convert-PdfPageToPng -InputPdf $InputPdf -OutputPng $OutputPng -DPI $DPI -PageNumber $PageNumber
    }
}

function Show-Usage {
    Write-LogMessage "PDF to PNG Converter with Auto-Install" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "=====================================" -Level INFO -ForegroundColor Magenta
    Write-LogMessage ""
    Write-LogMessage "This script automatically downloads and installs MuPDF if needed," -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "then converts PDF files to high-quality PNG images." -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Usage:" -Level WARN -ForegroundColor Yellow
    Write-LogMessage "  .\Convert-PdfToPng-AutoInstall.ps1 <PdfPath> [OutputPath] [Options]" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Examples:" -Level WARN -ForegroundColor Yellow
    Write-LogMessage "  .\Convert-PdfToPng-AutoInstall.ps1 'document.pdf'" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-PdfToPng-AutoInstall.ps1 'document.pdf' 'output.png' -DPI 600" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-PdfToPng-AutoInstall.ps1 'document.pdf' -AllPages -DPI 300" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-PdfToPng-AutoInstall.ps1 'document.pdf' -Page 2" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Parameters:" -Level WARN -ForegroundColor Yellow
    Write-LogMessage "  PdfPath     : Path to the input PDF file" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  OutputPath  : Path for the output PNG file (optional)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -DPI        : Resolution in DPI (default: 300)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -Page       : Page number to convert (default: 1)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -AllPages   : Convert all pages to separate PNG files" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -Force      : Force reinstall MuPDF even if present" -Level DEBUG -ForegroundColor Gray
}

function Main {
    Write-LogMessage "PDF to PNG Converter with Auto-Install" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "=====================================" -Level INFO -ForegroundColor Magenta
    Write-LogMessage ""

    # Validate input file
    if (-not (Test-Path $PdfPath)) {
        Write-LogMessage "✗ PDF file not found: $PdfPath" -Level ERROR -ForegroundColor Red
        exit 1
    }

    # Set output path if not specified
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($PdfPath)
        $directory = [System.IO.Path]::GetDirectoryName($PdfPath)
        $OutputPath = Join-Path $directory "$baseName.png"
    }

    # Display conversion parameters
    Write-LogMessage "Input PDF: $PdfPath" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Output PNG: $OutputPath" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Resolution: $DPI DPI" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Page(s): $(if($AllPages) { 'All Pages' } else { $Page })" -Level INFO -ForegroundColor Cyan
    Write-LogMessage ""

    # Check if MuPDF is installed or install it
    if ($Force -or -not (Test-MuPDFInstalled)) {
        if ($Force) {
            Write-LogMessage "Force reinstalling MuPDF..." -Level WARN -ForegroundColor Yellow
        } else {
            Write-LogMessage "MuPDF not found. Installing automatically..." -Level WARN -ForegroundColor Yellow
        }

        if (-not (Install-MuPDF)) {
            Write-LogMessage "✗ Failed to install MuPDF. Cannot proceed." -Level ERROR -ForegroundColor Red
            Write-LogMessage ""
            Write-LogMessage "Manual installation options:" -Level WARN -ForegroundColor Yellow
            Write-LogMessage "1. Download from: https://mupdf.com/downloads/" -Level DEBUG -ForegroundColor Gray
            Write-LogMessage "2. Extract mudraw.exe to: $script:MuPDFInstallPath" -Level DEBUG -ForegroundColor Gray
            exit 1
        }
        Write-LogMessage ""
    } else {
        Write-LogMessage "✓ MuPDF found at: $script:MudrawExe" -Level INFO -ForegroundColor Green
        Write-LogMessage ""
    }

    # Perform conversion
    Write-LogMessage "Starting conversion..." -Level WARN -ForegroundColor Yellow
    $success = Convert-PdfToPng -InputPdf $PdfPath -OutputPng $OutputPath -DPI $DPI -PageNumber $Page -ConvertAllPages $AllPages.IsPresent

    Write-LogMessage ""
    if ($success) {
        Write-LogMessage "✓ Conversion completed successfully!" -Level INFO -ForegroundColor Green

        # Show output file(s)
        if ($AllPages) {
            $outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
            $outputFiles = Get-ChildItem "$outputDir\$baseName*.png" -ErrorAction SilentlyContinue

            if ($outputFiles) {
                Write-LogMessage ""
                Write-LogMessage "Output files:" -Level INFO -ForegroundColor Cyan
                foreach ($file in $outputFiles) {
                    $sizeKB = [math]::Round($file.Length / 1KB, 2)
                    Write-LogMessage "  $($file.Name) ($sizeKB KB)" -Level DEBUG -ForegroundColor Gray
                }
            }
        } else {
            if (Test-Path $OutputPath) {
                $fileInfo = Get-Item $OutputPath
                $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
                Write-LogMessage "Output file: $($fileInfo.Name) ($sizeKB KB)" -Level DEBUG -ForegroundColor Gray
            }
        }
    } else {
        Write-LogMessage "✗ Conversion failed!" -Level ERROR -ForegroundColor Red
        exit 1
    }
}

# Show usage if no parameters provided
if (-not $PdfPath) {
    Show-Usage
    exit 0
}

# Execute main function
Main

