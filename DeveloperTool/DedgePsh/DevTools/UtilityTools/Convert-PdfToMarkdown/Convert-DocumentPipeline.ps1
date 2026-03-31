# Convert-DocumentPipeline.ps1
# Automated Document Conversion Pipeline: PDF -> PNG -> Markdown
# Recursively processes folders and converts documents through the complete pipeline
#
# Author: Geir Helge Starholm, www.dEdge.no
# Created: 2025-08-29

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputFolder,

    [Parameter(Mandatory=$false)]
    [int]$DPI = 300,

    [Parameter(Mandatory=$false)]
    [switch]$Force,  # Force reinstall all dependencies

    [Parameter(Mandatory=$false)]
    [switch]$SkipOCR  # Skip OCR and just use basic text extraction
)

# Import required modules
Import-Module GlobalFunctions -Force

# Global variables
$script:PythonExe = ""
$script:PandocExe = ""
$script:WorkingDir = ""

function Write-Step {
    param([string]$StepNumber, [string]$Description)
    Write-LogMessage "`n=== STEP $($StepNumber): $($Description) ===" -Level INFO -ForegroundColor Magenta
}

function Test-PythonInstalled {
    Write-LogMessage "Checking Python installation..." -Level INFO -ForegroundColor Yellow

    # Check common Python installation paths
    $pythonPaths = @(
        "${env:LOCALAPPDATA}\Programs\Python\Python312\python.exe",
        "${env:LOCALAPPDATA}\Programs\Python\Python311\python.exe",
        "${env:LOCALAPPDATA}\Programs\Python\Python310\python.exe",
        "${env:ProgramFiles}\Python312\python.exe",
        "${env:ProgramFiles}\Python311\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe"
    )

    foreach ($path in $pythonPaths) {
        if (Test-Path $path) {
            $script:PythonExe = $path
            Write-LogMessage "  ✓ Found Python at: $path" -Level INFO -ForegroundColor Green
            return $true
        }
    }

    # Check if python is in PATH
    $pythonInPath = Get-Command "python.exe" -ErrorAction SilentlyContinue
    if ($pythonInPath) {
        $script:PythonExe = $pythonInPath.Source
        Write-LogMessage "  ✓ Found Python in PATH: $($pythonInPath.Source)" -Level INFO -ForegroundColor Green
        return $true
    }

    Write-LogMessage "  ✗ Python not found" -Level ERROR -ForegroundColor Red
    return $false
}

function Install-Python {
    Write-LogMessage "Installing Python..." -Level INFO -ForegroundColor Yellow

    try {
        winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements

        # Set the expected path
        $script:PythonExe = "${env:LOCALAPPDATA}\Programs\Python\Python312\python.exe"

        # Wait a moment and check
        Start-Sleep -Seconds 3

        if (Test-Path $script:PythonExe) {
            Write-LogMessage "  ✓ Python installed successfully!" -Level INFO -ForegroundColor Green
            return $true
        } else {
            Write-LogMessage "  ⚠ Python installation completed, but executable not found at expected location" -Level WARN -ForegroundColor Yellow
            # Try to find it again
            return Test-PythonInstalled
        }
    }
    catch {
        Write-LogMessage "  ✗ Failed to install Python: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $false
    }
}

function Install-PythonPackages {
    Write-LogMessage "Installing required Python packages..." -Level INFO -ForegroundColor Yellow

    $packages = @(
        "pymupdf",      # PDF processing
        "pytesseract",  # OCR
        "pillow",       # Image processing
        "requests"      # HTTP requests
    )

    try {
        foreach ($package in $packages) {
            Write-LogMessage "  Installing $package..." -Level DEBUG -ForegroundColor Gray
            & $script:PythonExe -m pip install $package --quiet

            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "  ⚠ Warning: Failed to install $package" -Level WARN -ForegroundColor Yellow
            } else {
                Write-LogMessage "  ✓ $package installed" -Level INFO -ForegroundColor Green
            }
        }

        Write-LogMessage "  ✓ Python packages installation completed" -Level INFO -ForegroundColor Green
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Failed to install Python packages: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $false
    }
}

function Test-PandocInstalled {
    Write-LogMessage "Checking Pandoc installation..." -Level INFO -ForegroundColor Yellow

    # Check if pandoc is in PATH
    $pandocInPath = Get-Command "pandoc.exe" -ErrorAction SilentlyContinue
    if ($pandocInPath) {
        $script:PandocExe = $pandocInPath.Source
        Write-LogMessage "  ✓ Found Pandoc in PATH: $($pandocInPath.Source)" -Level INFO -ForegroundColor Green
        return $true
    }

    # Check common installation paths
    $pandocPaths = @(
        "${env:LOCALAPPDATA}\Pandoc\pandoc.exe",
        "${env:ProgramFiles}\Pandoc\pandoc.exe",
        "${env:ProgramFiles(x86)}\Pandoc\pandoc.exe"
    )

    foreach ($path in $pandocPaths) {
        if (Test-Path $path) {
            $script:PandocExe = $path
            Write-LogMessage "  ✓ Found Pandoc at: $path" -Level INFO -ForegroundColor Green
            return $true
        }
    }

    Write-LogMessage "  ✗ Pandoc not found" -Level ERROR -ForegroundColor Red
    return $false
}

function Install-Pandoc {
    Write-LogMessage "Installing Pandoc..." -Level INFO -ForegroundColor Yellow

    try {
        winget install JohnMacFarlane.Pandoc --accept-source-agreements --accept-package-agreements

        # Wait a moment for installation to complete
        Start-Sleep -Seconds 3

        # Try to find Pandoc again
        if (Test-PandocInstalled) {
            Write-LogMessage "  ✓ Pandoc installed successfully!" -Level INFO -ForegroundColor Green
            return $true
        } else {
            Write-LogMessage "  ⚠ Pandoc installation may have completed, but executable not found" -Level WARN -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Failed to install Pandoc: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $false
    }
}

function Test-TesseractInstalled {
    Write-LogMessage "Checking Tesseract OCR installation..." -Level INFO -ForegroundColor Yellow

    # Check if tesseract is in PATH
    $tesseractInPath = Get-Command "tesseract.exe" -ErrorAction SilentlyContinue
    if ($tesseractInPath) {
        Write-LogMessage "  ✓ Found Tesseract in PATH: $($tesseractInPath.Source)" -Level INFO -ForegroundColor Green
        return $true
    }

    # Check common installation paths
    $tesseractPaths = @(
        "${env:ProgramFiles}\Tesseract-OCR\tesseract.exe",
        "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe",
        "${env:LOCALAPPDATA}\Programs\Tesseract-OCR\tesseract.exe"
    )

    foreach ($path in $tesseractPaths) {
        if (Test-Path $path) {
            Write-LogMessage "  ✓ Found Tesseract at: $path" -Level INFO -ForegroundColor Green
            return $true
        }
    }

    Write-LogMessage "  ✗ Tesseract OCR not found" -Level ERROR -ForegroundColor Red
    return $false
}

function Install-Tesseract {
    Write-LogMessage "Installing Tesseract OCR..." -Level INFO -ForegroundColor Yellow

    try {
        winget install UB-Mannheim.TesseractOCR --accept-source-agreements --accept-package-agreements

        # Wait a moment for installation to complete
        Start-Sleep -Seconds 5

        # Try to find Tesseract again
        if (Test-TesseractInstalled) {
            Write-LogMessage "  ✓ Tesseract OCR installed successfully!" -Level INFO -ForegroundColor Green
            return $true
        } else {
            Write-LogMessage "  ⚠ Tesseract installation may have completed, but executable not found" -Level WARN -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Failed to install Tesseract OCR: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $false
    }
}

function Initialize-FolderStructure {
    param([string]$BasePath)

    Write-LogMessage "Creating folder structure..." -Level INFO -ForegroundColor Yellow

    # Define folder paths
    $pdfFolder = Join-Path $BasePath "PDF"
    $pngFolder = Join-Path $BasePath "PNG"
    $mdFolder = Join-Path $BasePath "MD"

    try {
        # Create PDF folder if it doesn't exist
        if (-not (Test-Path $pdfFolder)) {
            New-Item -ItemType Directory -Path $pdfFolder -Force | Out-Null
            Write-LogMessage "  Created PDF folder" -Level DEBUG -ForegroundColor Gray
        } else {
            Write-LogMessage "  PDF folder already exists" -Level DEBUG -ForegroundColor Gray
        }

        # Check if PDF folder already contains files
        $existingPdfFiles = Get-ChildItem $pdfFolder -Filter "*.pdf" -Recurse -ErrorAction SilentlyContinue

        if ($existingPdfFiles.Count -eq 0) {
            # PDF folder is empty, move files from base directory
            Write-LogMessage "  Moving files to PDF folder..." -Level DEBUG -ForegroundColor Gray

            # Get all files and folders (excluding the target folders we're creating)
            $itemsToMove = Get-ChildItem $BasePath | Where-Object {
                $_.Name -notin @("PDF", "PNG", "MD")
            }

            foreach ($item in $itemsToMove) {
                $destination = Join-Path $pdfFolder $item.Name

                if ($item.PSIsContainer) {
                    # It's a directory
                    if (Test-Path $destination) {
                        Write-LogMessage "    Directory already exists: $($item.Name)" -Level WARN -ForegroundColor Yellow
                    } else {
                        Move-Item $item.FullName $destination -Force
                        Write-LogMessage "    Moved directory: $($item.Name)" -Level DEBUG -ForegroundColor Gray
                    }
                } else {
                    # It's a file
                    if (Test-Path $destination) {
                        Write-LogMessage "    File already exists: $($item.Name)" -Level WARN -ForegroundColor Yellow
                    } else {
                        Move-Item $item.FullName $destination -Force
                        Write-LogMessage "    Moved file: $($item.Name)" -Level DEBUG -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-LogMessage "  PDF folder already contains $($existingPdfFiles.Count) PDF files - using existing structure" -Level INFO -ForegroundColor Green
        }

        # Create PNG and MD folders
        Write-LogMessage "  Creating PNG folder..." -Level DEBUG -ForegroundColor Gray
        if (-not (Test-Path $pngFolder)) {
            New-Item -ItemType Directory -Path $pngFolder -Force | Out-Null
        }

        Write-LogMessage "  Creating MD folder..." -Level DEBUG -ForegroundColor Gray
        if (-not (Test-Path $mdFolder)) {
            New-Item -ItemType Directory -Path $mdFolder -Force | Out-Null
        }

        Write-LogMessage "  ✓ Folder structure created successfully" -Level INFO -ForegroundColor Green
        return @{
            PDF = $pdfFolder
            PNG = $pngFolder
            MD = $mdFolder
        }
    }
    catch {
        Write-LogMessage "  ✗ Failed to create folder structure: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $null
    }
}

function Convert-PdfsToImages {
    param(
        [string]$SourceFolder,
        [string]$DestinationFolder,
        [int]$DPI
    )

    Write-LogMessage "Converting PDFs to PNG images..." -Level INFO -ForegroundColor Yellow

    # Get all PDF files recursively
    $pdfFiles = Get-ChildItem -Path $SourceFolder -Filter "*.pdf" -Recurse

    if ($pdfFiles.Count -eq 0) {
        Write-LogMessage "  ⚠ No PDF files found in $SourceFolder" -Level WARN -ForegroundColor Yellow
        return $true
    }

    Write-LogMessage "  Found $($pdfFiles.Count) PDF files to convert" -Level DEBUG -ForegroundColor Gray

    $successCount = 0
    $totalCount = $pdfFiles.Count

    foreach ($pdfFile in $pdfFiles) {
        try {
            # Calculate relative path from source folder
            $relativePath = $pdfFile.FullName.Substring($SourceFolder.Length + 1)
            $relativeDir = [System.IO.Path]::GetDirectoryName($relativePath)
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($pdfFile.Name)

            # Create destination directory structure
            $destDir = if ($relativeDir) {
                Join-Path $DestinationFolder $relativeDir
            } else {
                $DestinationFolder
            }

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            # Convert PDF using Python script
            $outputPath = Join-Path $destDir "$baseName.png"

            Write-LogMessage "    Converting: $($pdfFile.Name)" -Level DEBUG -ForegroundColor Gray

            # Use the Python script to convert PDF
            $pythonScript = Join-Path $PSScriptRoot "convert_pdf_to_png.py"
            $result = & $script:PythonExe $pythonScript $pdfFile.FullName --output $outputPath --all-pages --dpi $DPI 2>&1

            if ($LASTEXITCODE -eq 0) {
                $successCount++
                Write-LogMessage "      ✓ Converted successfully" -Level INFO -ForegroundColor Green
            } else {
                Write-LogMessage "      ✗ Conversion failed: $result" -Level ERROR -ForegroundColor Red
            }
        }
        catch {
            Write-LogMessage "      ✗ Error converting $($pdfFile.Name): $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        }
    }

    Write-LogMessage "  ✓ PDF conversion completed: $successCount/$totalCount files converted" -Level INFO -ForegroundColor Green
    return $successCount -gt 0
}

function Convert-ImagesToMarkdown {
    param(
        [string]$SourceFolder,
        [string]$DestinationFolder,
        [bool]$UseOCR = $true
    )

    Write-LogMessage "Converting PNG images to Markdown..." -Level INFO -ForegroundColor Yellow

    # Get all PNG files recursively
    $pngFiles = Get-ChildItem -Path $SourceFolder -Filter "*.png" -Recurse

    if ($pngFiles.Count -eq 0) {
        Write-LogMessage "  ⚠ No PNG files found in $SourceFolder" -Level WARN -ForegroundColor Yellow
        return $true
    }

    Write-LogMessage "  Found $($pngFiles.Count) PNG files to convert" -Level DEBUG -ForegroundColor Gray

    # Use the Python script for OCR conversion
    $pythonScript = Join-Path $PSScriptRoot "convert_png_to_markdown.py"

    if (-not (Test-Path $pythonScript)) {
        Write-LogMessage "  ✗ Python OCR script not found: $pythonScript" -Level ERROR -ForegroundColor Red
        return $false
    }

    try {
        # Build arguments for the Python script
        $pythonArgs = @($SourceFolder, "--output", $DestinationFolder, "--recursive")

        if (-not $UseOCR) {
            $pythonArgs += "--no-ocr"
        }

        Write-LogMessage "  Executing Python OCR script..." -Level DEBUG -ForegroundColor Gray

        # Execute the Python OCR script
        $result = & $script:PythonExe $pythonScript @pythonArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "  ✓ Python OCR conversion completed successfully" -Level INFO -ForegroundColor Green

            # Count created markdown files
            $mdFiles = Get-ChildItem -Path $DestinationFolder -Filter "*.md" -Recurse
            Write-LogMessage "  ✓ Markdown conversion completed: $($mdFiles.Count) documents created" -Level INFO -ForegroundColor Green
            return $true
        } else {
            Write-LogMessage "  ✗ Python OCR script failed: $result" -Level ERROR -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-LogMessage "  ✗ Error executing Python OCR script: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        return $false
    }
}

function Show-Summary {
    param([hashtable]$Folders, [string]$InputFolder)

    Write-LogMessage "`n=== CONVERSION SUMMARY ===" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "Input folder: $InputFolder" -Level INFO -ForegroundColor Cyan
    Write-LogMessage ""

    # Count files in each folder
    $pdfCount = (Get-ChildItem -Path $Folders.PDF -Filter "*.pdf" -Recurse).Count
    $pngCount = (Get-ChildItem -Path $Folders.PNG -Filter "*.png" -Recurse).Count
    $mdCount = (Get-ChildItem -Path $Folders.MD -Filter "*.md" -Recurse).Count

    Write-LogMessage "📁 PDF folder: $($Folders.PDF)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "   └─ $pdfCount PDF files" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "📁 PNG folder: $($Folders.PNG)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "   └─ $pngCount PNG files" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "📁 MD folder: $($Folders.MD)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "   └─ $mdCount Markdown files" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""

    if ($mdCount -gt 0) {
        Write-LogMessage "✓ Pipeline completed successfully!" -Level INFO -ForegroundColor Green
        Write-LogMessage "Your converted documents are ready in the MD folder." -Level INFO -ForegroundColor Green
    } else {
        Write-LogMessage "⚠ Pipeline completed with warnings. Check the logs above." -Level WARN -ForegroundColor Yellow
    }
}

function Main {
    Write-LogMessage "Document Conversion Pipeline" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "===========================" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "PDF → PNG → Markdown Converter" -Level INFO -ForegroundColor Magenta
    Write-LogMessage ""

    # Validate input folder
    if (-not (Test-Path $InputFolder)) {
        Write-LogMessage "✗ Input folder not found: $InputFolder" -Level ERROR -ForegroundColor Red
        exit 1
    }

    $InputFolder = (Resolve-Path $InputFolder).Path
    Write-LogMessage "Input folder: $InputFolder" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "DPI setting: $DPI" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "OCR enabled: $(-not $SkipOCR)" -Level INFO -ForegroundColor Cyan
    Write-LogMessage ""

    # Step 1: Check/Install Python
    Write-Step "1" "Python Installation Check"
    if ($Force -or -not (Test-PythonInstalled)) {
        if (-not (Install-Python)) {
            Write-LogMessage "✗ Failed to install Python. Cannot continue." -Level ERROR -ForegroundColor Red
            exit 1
        }
    }

    # Step 2: Install Python packages
    Write-Step "2" "Python Package Installation"
    if (-not (Install-PythonPackages)) {
        Write-LogMessage "⚠ Some Python packages failed to install. Continuing anyway..." -Level WARN -ForegroundColor Yellow
    }

    # Step 3: Check/Install Pandoc
    Write-Step "3" "Pandoc Installation Check"
    if ($Force -or -not (Test-PandocInstalled)) {
        if (-not (Install-Pandoc)) {
            Write-LogMessage "⚠ Pandoc installation failed. Some features may not work." -Level WARN -ForegroundColor Yellow
        }
    }

    # Step 3.5: Check/Install Tesseract OCR
    Write-Step "3.5" "Tesseract OCR Installation Check"
    if ($Force -or -not (Test-TesseractInstalled)) {
        if (-not (Install-Tesseract)) {
            Write-LogMessage "⚠ Tesseract OCR installation failed. OCR functionality will be limited." -Level WARN -ForegroundColor Yellow
        }
    }

    # Step 4-6: Initialize folder structure
    Write-Step "4-6" "Folder Structure Setup"
    $folders = Initialize-FolderStructure -BasePath $InputFolder
    if (-not $folders) {
        Write-LogMessage "✗ Failed to create folder structure. Cannot continue." -Level ERROR -ForegroundColor Red
        exit 1
    }

    # Step 7: Convert PDFs to PNGs
    Write-Step "7" "PDF to PNG Conversion"
    $pdfSuccess = Convert-PdfsToImages -SourceFolder $folders.PDF -DestinationFolder $folders.PNG -DPI $DPI

    # Step 8: Convert PNGs to Markdown
    Write-Step "8" "PNG to Markdown Conversion"
    $mdSuccess = Convert-ImagesToMarkdown -SourceFolder $folders.PNG -DestinationFolder $folders.MD -UseOCR (-not $SkipOCR)

    # Check overall success
    if (-not $pdfSuccess) {
        Write-LogMessage "⚠ PDF conversion had issues. Some files may not have been processed." -Level WARN -ForegroundColor Yellow
    }

    if (-not $mdSuccess) {
        Write-LogMessage "⚠ Markdown conversion had issues. Some documents may not have been created." -Level WARN -ForegroundColor Yellow
    }

    # Show summary
    Show-Summary -Folders $folders -InputFolder $InputFolder
}

# Show usage if no parameters
if (-not $InputFolder) {
    Write-LogMessage "Document Conversion Pipeline" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "===========================" -Level INFO -ForegroundColor Magenta
    Write-LogMessage ""
    Write-LogMessage "Usage:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  .\Convert-DocumentPipeline.ps1 <InputFolder> [Options]" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Examples:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  .\Convert-DocumentPipeline.ps1 'C:\TEMPFK\DocConvert\'" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-DocumentPipeline.ps1 'C:\TEMPFK\DocConvert\' -DPI 600" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-DocumentPipeline.ps1 'C:\TEMPFK\DocConvert\' -Force -SkipOCR" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Parameters:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  InputFolder : Root folder containing documents to convert" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -DPI        : Image resolution (default: 300)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -Force      : Force reinstall all dependencies" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -SkipOCR    : Skip OCR processing for faster conversion" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Pipeline Steps:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  1. Install Python if needed" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  2. Install Python packages (PyMuPDF, etc.)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  3. Install Pandoc if needed" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  4. Move files to PDF subfolder" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  5. Create PNG subfolder" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  6. Create MD subfolder" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  7. Convert PDFs to PNG images" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  8. Convert PNG images to Markdown documents" -Level DEBUG -ForegroundColor Gray
    exit 0
}

# Execute main function
Main

