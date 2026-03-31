# Document Conversion Pipeline - Technical Documentation

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2025-08-29

## Overview

The Document Conversion Pipeline is a comprehensive PowerShell-based solution that automatically converts PDF documents to Markdown format through a multi-stage process: **PDF → PNG → Markdown**. The system includes automatic dependency management, OCR capabilities, and maintains folder structure integrity throughout the conversion process.

## Architecture

### Core Components

1. **Convert-PdfToMarkdown.ps1** - Main user-facing wrapper script
2. **Convert-DocumentPipeline.ps1** - Core orchestration script
3. **convert_pdf_to_png.py** - Python-based PDF to PNG converter using PyMuPDF
4. **convert_png_to_markdown.py** - Python-based PNG to Markdown converter with OCR
5. **Convert-PdfToPng-AutoInstall.ps1** - Alternative PowerShell PDF converter with MuPDF

### System Dependencies

- **PowerShell 5.1+** (Windows PowerShell or PowerShell Core)
- **GlobalFunctions Module** - Custom logging and utility functions
- **Python 3.10+** - For PDF processing and OCR
- **Pandoc** - Document format conversion (optional)
- **Tesseract OCR** - Text extraction from images (optional)

### Python Dependencies

- **PyMuPDF (fitz)** - PDF rendering and manipulation
- **pytesseract** - Python wrapper for Tesseract OCR
- **Pillow (PIL)** - Image processing
- **requests** - HTTP client for downloads

## Technical Flow

### Stage 1: Environment Setup
```
Check Dependencies → Install Missing Components → Validate Installation
```

The pipeline automatically:
- Detects Python installation across common paths
- Installs Python via winget if missing
- Installs required Python packages via pip
- Checks for Pandoc and installs if needed
- Validates all installations before proceeding

### Stage 2: File Organization
```
Input Folder → Create Structure → Move Files (if needed)
```

Folder structure created:
```
InputFolder/
├── PDF/           # Original files (moved here OR already here)
├── PNG/           # Generated images
└── MD/            # Final markdown documents
```

**Smart Detection**: The system detects if PDFs are already organized in a `PDF/` subfolder and uses the existing structure without moving files.

### Stage 3: PDF to PNG Conversion
```
PDF Files → PyMuPDF Rendering → High-Resolution PNG Images
```

Technical details:
- Uses PyMuPDF for accurate PDF rendering
- Configurable DPI (default: 300)
- Multi-page support with sequential naming
- Maintains folder structure recursively
- Error handling with detailed logging

### Stage 4: PNG to Markdown Conversion
```
PNG Images → OCR Processing → Markdown Generation
```

Features:
- Groups related pages by document name
- Optional OCR text extraction using Tesseract
- Markdown formatting with embedded images
- Page consolidation into single documents
- Metadata inclusion (conversion date, page count)

## Code Architecture

### Logging System

All PowerShell scripts use the GlobalFunctions module for consistent logging:

```powershell
Import-Module GlobalFunctions -Force

Write-LogMessage "Message" -Level INFO -ForegroundColor Green
```

Log levels:
- `DEBUG` - Detailed progress information
- `INFO` - General information and success messages
- `WARN` - Warnings and non-critical issues
- `ERROR` - Errors and failures
- `FATAL` - Critical failures requiring termination

### Error Handling

The system implements comprehensive error handling:

1. **Graceful Degradation** - Continues processing when possible
2. **Detailed Error Reporting** - Logs specific failure reasons
3. **Rollback Prevention** - Validates each stage before proceeding
4. **User-Friendly Messages** - Clear instructions for manual intervention

### Python Integration

PowerShell scripts invoke Python with proper error handling:

```powershell
$result = & $script:PythonExe $pythonScript $arguments 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-LogMessage "Python script failed: $result" -Level ERROR
}
```

### File Naming Conventions

- **PDF Files**: Original names preserved in PDF/ folder
- **PNG Files**: `DocumentName Page (N).png` format
- **Markdown Files**: `DocumentName.md` with consolidated pages

## Configuration Options

### Pipeline Parameters

```powershell
.\Convert-PdfToMarkdown.ps1 "C:\Documents" -DPI 600 -Force -SkipOCR
```

- `InputFolder` - Root folder containing documents
- `DPI` - Image resolution (default: 300)
- `Force` - Reinstall all dependencies
- `SkipOCR` - Disable OCR for faster processing

### Python Script Parameters

```bash
python convert_pdf_to_png.py "document.pdf" --all-pages --dpi 300
python convert_png_to_markdown.py "images/" --recursive --no-ocr
```

## Performance Considerations

### Optimization Strategies

1. **Parallel Processing** - Multiple files processed concurrently where possible
2. **Memory Management** - Documents processed individually to prevent memory issues
3. **Disk I/O** - Sequential file operations to minimize disk thrashing
4. **OCR Caching** - Results cached to avoid reprocessing

### Resource Requirements

- **CPU**: Multi-core recommended for PDF rendering
- **Memory**: 4GB+ recommended for large documents
- **Disk**: Temporary space ~3x input folder size
- **Network**: Required for dependency downloads

## Extensibility

### Adding New Converters

The modular architecture allows easy extension:

1. Create new Python converter script
2. Add PowerShell wrapper function
3. Integrate into main pipeline
4. Update logging and error handling

### Custom OCR Engines

Replace Tesseract with alternative OCR engines:

```python
def custom_ocr_engine(image_path):
    # Implement custom OCR logic
    return extracted_text
```

### Output Format Extensions

Support additional output formats by:

1. Adding new conversion functions
2. Updating file naming conventions
3. Extending folder structure
4. Implementing format-specific options

## Testing Strategy

### Unit Testing

Each component can be tested independently:

```powershell
# Test Python installation detection
Test-PythonInstalled

# Test PDF conversion
python convert_pdf_to_png.py "test.pdf" --page 1

# Test folder structure creation
Initialize-FolderStructure -BasePath "C:\Test"
```

### Integration Testing

Full pipeline testing with sample documents:

```powershell
.\Convert-PdfToMarkdown.ps1 "C:\TestDocuments" -DPI 150
```

### Performance Testing

Monitor resource usage and processing times:

```powershell
Measure-Command { .\Convert-PdfToMarkdown.ps1 "C:\LargeDocuments" }
```

## Security Considerations

### File System Access

- Scripts require write access to input folder
- Temporary files created in user temp directory
- No elevation required for normal operation

### Network Access

- Downloads dependencies from trusted sources
- Uses HTTPS for all external connections
- Validates downloaded file integrity where possible

### Code Execution

- Python scripts executed in controlled environment
- No dynamic code generation or evaluation
- Input validation prevents injection attacks

## Troubleshooting

### Common Issues

1. **Python Not Found** - Check PATH and installation
2. **Permission Denied** - Verify folder write permissions
3. **OCR Failures** - Install Tesseract or use -SkipOCR
4. **Large File Timeouts** - Increase timeout values

### Debug Mode

Enable verbose logging for troubleshooting:

```powershell
$VerbosePreference = "Continue"  
.\Convert-PdfToMarkdown.ps1 "C:\Documents" -Force
```

### Log Analysis

Logs include:
- Timestamp and log level
- Component identification
- Detailed error messages
- Performance metrics

## Maintenance

### Regular Updates

1. **Python Packages** - Update via pip regularly
2. **Tesseract** - Check for OCR accuracy improvements
3. **Dependencies** - Monitor for security updates
4. **Scripts** - Version control and change tracking

### Backup Strategy

- Input documents preserved in PDF/ folder
- Intermediate PNG files retained for reprocessing
- Markdown outputs versioned if needed

## Future Enhancements

### Planned Features

1. **Batch Processing** - Queue-based processing for large volumes
2. **Cloud Integration** - Support for cloud storage providers
3. **GUI Interface** - Windows Forms or WPF frontend
4. **Web API** - REST API for remote processing
5. **Advanced OCR** - Machine learning-based text extraction
6. **Format Support** - Additional input/output formats

### Performance Improvements

1. **GPU Acceleration** - CUDA support for PDF rendering
2. **Distributed Processing** - Multi-machine processing
3. **Caching System** - Intelligent caching of intermediate results
4. **Compression** - Optimized storage of temporary files
