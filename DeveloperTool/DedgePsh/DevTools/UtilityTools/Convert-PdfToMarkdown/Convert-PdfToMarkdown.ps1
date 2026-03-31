# Convert-PdfToMarkdown.ps1
# Wrapper script for the Document Conversion Pipeline
# Provides a simple interface to convert PDF documents to Markdown format
#
# Author: Geir Helge Starholm, www.dEdge.no
# Created: 2025-08-29

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputFolder,

    [Parameter(Mandatory=$false)]
    [int]$DPI = 300,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$SkipOCR,

    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Import required modules
Import-Module GlobalFunctions -Force

function Show-Help {
    Write-LogMessage "Convert PDF to Markdown - Wrapper Script" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "=========================================" -Level INFO -ForegroundColor Magenta
    Write-LogMessage ""
    Write-LogMessage "This script converts PDF documents to Markdown format through a complete pipeline:" -Level INFO -ForegroundColor Gray
    Write-LogMessage "PDF → PNG → Markdown with OCR text extraction" -Level INFO -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Usage:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  .\Convert-PdfToMarkdown.ps1 <InputFolder> [Options]" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Examples:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  .\Convert-PdfToMarkdown.ps1 'C:\Documents'" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-PdfToMarkdown.ps1 'C:\Documents' -DPI 600" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-PdfToMarkdown.ps1 'C:\Documents' -SkipOCR" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  .\Convert-PdfToMarkdown.ps1 'C:\Documents' -Force" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Parameters:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  InputFolder : Folder containing PDF files to convert" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -DPI        : Image resolution in DPI (default: 300)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -Force      : Force reinstall all dependencies" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -SkipOCR    : Skip OCR text extraction for faster conversion" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  -Help       : Show this help message" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Output:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  Creates three folders in your input directory:" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  • PDF/  - Original PDF files (moved here)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  • PNG/  - High-resolution page images" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  • MD/   - Final Markdown documents with embedded images" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
    Write-LogMessage "Features:" -Level INFO -ForegroundColor Yellow
    Write-LogMessage "  ✓ Automatic dependency installation (Python, packages, etc.)" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  ✓ Multi-page PDF support" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  ✓ OCR text extraction from images" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  ✓ Preserves folder structure" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage "  ✓ High-quality image conversion" -Level DEBUG -ForegroundColor Gray
    Write-LogMessage ""
}

function Main {
    # Show help if requested
    if ($Help) {
        Show-Help
        exit 0
    }

    # Validate input folder
    if (-not $InputFolder) {
        Write-LogMessage "Error: InputFolder parameter is required." -Level ERROR -ForegroundColor Red
        Write-LogMessage "Use -Help for usage information." -Level INFO -ForegroundColor Yellow
        exit 1
    }

    if (-not (Test-Path $InputFolder)) {
        Write-LogMessage "Error: Input folder not found: $InputFolder" -Level ERROR -ForegroundColor Red
        exit 1
    }

    # Get the directory where this script is located
    $scriptDir = if ($MyInvocation.MyCommand.Path) {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $PSScriptRoot
    }
    $pipelineScript = Join-Path $scriptDir "Convert-DocumentPipeline.ps1"

    # Verify the main pipeline script exists
    if (-not (Test-Path $pipelineScript)) {
        Write-LogMessage "Error: Main pipeline script not found: $pipelineScript" -Level ERROR -ForegroundColor Red
        Write-LogMessage "Please ensure Convert-DocumentPipeline.ps1 is in the same directory." -Level INFO -ForegroundColor Yellow
        exit 1
    }

    Write-LogMessage "PDF to Markdown Converter" -Level INFO -ForegroundColor Magenta
    Write-LogMessage "=========================" -Level INFO -ForegroundColor Magenta
    Write-LogMessage ""
    Write-LogMessage "Starting conversion pipeline..." -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Input folder: $InputFolder" -Level INFO -ForegroundColor Gray
    Write-LogMessage "DPI setting: $DPI" -Level INFO -ForegroundColor Gray
    Write-LogMessage "OCR enabled: $(-not $SkipOCR)" -Level INFO -ForegroundColor Gray
    Write-LogMessage "Force reinstall: $Force" -Level INFO -ForegroundColor Gray
    Write-LogMessage ""

    # Build arguments for the main pipeline script
    $pipelineArgs = @{
        InputFolder = $InputFolder
        DPI = $DPI
    }

    if ($Force) {
        $pipelineArgs.Force = $true
    }

    if ($SkipOCR) {
        $pipelineArgs.SkipOCR = $true
    }

    try {
        # Execute the main pipeline script
        Write-LogMessage "Executing main conversion pipeline..." -Level INFO -ForegroundColor Yellow
        & $pipelineScript @pipelineArgs

        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage ""
            Write-LogMessage "✓ PDF to Markdown conversion completed successfully!" -Level INFO -ForegroundColor Green
            Write-LogMessage "Check the MD folder in your input directory for the converted documents." -Level INFO -ForegroundColor Green
        } else {
            Write-LogMessage ""
            Write-LogMessage "✗ Conversion pipeline failed with exit code: $LASTEXITCODE" -Level ERROR -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
    catch {
        Write-LogMessage "✗ Error executing conversion pipeline: $($_.Exception.Message)" -Level ERROR -ForegroundColor Red
        exit 1
    }
}

# Show help if no parameters provided
if ($args.Count -eq 0 -and -not $InputFolder) {
    Show-Help
    exit 0
}

# Execute main function
Main

