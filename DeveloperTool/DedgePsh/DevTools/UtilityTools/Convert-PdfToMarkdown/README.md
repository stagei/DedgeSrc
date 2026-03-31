# Document Conversion Pipeline - User Guide

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2025-08-29

## What This Does

This tool automatically converts PDF documents to Markdown format, making them easier to edit, version control, and integrate into documentation systems. The conversion process extracts text using OCR (Optical Character Recognition) and preserves document structure.

## Quick Start

1. **Download the files** to your computer
2. **Open PowerShell** as Administrator
3. **Navigate** to the folder containing the scripts
4. **Run the conversion**:
   ```powershell
   .\Convert-PdfToMarkdown.ps1 "C:\Your\Documents\Folder"
   ```

The tool will automatically install everything it needs and convert your documents!

## What You Get

After conversion, your folder will look like this:

```
Your Documents Folder/
├── PDF/           # Your original PDF files (safely moved here OR already here)
├── PNG/           # High-quality images of each page
└── MD/            # Final Markdown documents with OCR text (what you want!)
```

**Note**: If your PDFs are already organized in a `PDF/` subfolder, the tool will detect this and use the existing structure without moving files.

## Installation

### Automatic Installation (Recommended)

The script automatically installs everything needed:
- ✅ Python (if not installed)
- ✅ Required Python packages
- ✅ Pandoc document converter  
- ✅ Tesseract OCR for text extraction
- ✅ All dependencies

**Just run the script - it handles everything!**

### Manual Installation (If Winget is Not Available)

If the automatic installation doesn't work, install manually:

#### 1. Install Python
- **Download**: [Python 3.12](https://www.python.org/downloads/)
- **During installation**: ✅ Check "Add Python to PATH"
- **Verify**: Open Command Prompt and type `python --version`

#### 2. Install Python Packages
Open Command Prompt and run:
```cmd
pip install pymupdf pytesseract pillow requests
```

#### 3. Install Pandoc (Optional)
- **Download**: [Pandoc](https://pandoc.org/installing.html)
- **Or use Chocolatey**: `choco install pandoc`

#### 4. Install Tesseract OCR (Optional, for better text extraction)
- **Download**: [Tesseract OCR](https://github.com/UB-Mannheim/tesseract/wiki)
- **Or use Chocolatey**: `choco install tesseract`

## Usage Examples

### Basic Usage
Convert all PDFs in a folder:
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\MyDocuments"
```

### High Quality Images
Convert with higher resolution (better for detailed documents):
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\MyDocuments" -DPI 600
```

### Skip Text Extraction (Faster)
Convert without OCR text extraction:
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\MyDocuments" -SkipOCR
```

### Force Reinstall Dependencies
Reinstall all dependencies and convert:
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\MyDocuments" -Force
```

## Options Explained

| Option | Description | Example |
|--------|-------------|---------|
| `InputFolder` | Folder containing your PDF files | `"C:\Documents"` |
| `-DPI` | Image quality (higher = better quality, larger files) | `-DPI 600` |
| `-SkipOCR` | Skip text extraction (faster conversion) | `-SkipOCR` |
| `-Force` | Reinstall all dependencies | `-Force` |

## What Happens During Conversion

1. **🔍 Check Dependencies** - Installs Python, packages, Tesseract OCR, etc.
2. **📁 Organize Files** - Creates PDF, PNG, MD folders (or uses existing PDF folder)
3. **🖼️ Create Images** - Converts PDF pages to high-quality PNG images  
4. **📝 Extract Text** - Uses Tesseract OCR to read text from images
5. **📄 Generate Markdown** - Creates final Markdown documents with embedded images and extracted text

## Troubleshooting

### "Python not found"
**Solution**: Install Python manually or run PowerShell as Administrator

### "Permission denied"
**Solution**: 
- Run PowerShell as Administrator
- Check that you can write to the target folder

### "Conversion failed"
**Solutions**:
- Try with `-SkipOCR` flag for faster processing
- Check that PDF files aren't corrupted
- Ensure enough disk space (needs ~3x input folder size)

### "OCR not working"
**Solutions**:
- Install Tesseract OCR manually
- Use `-SkipOCR` to skip text extraction
- Images will still be embedded in Markdown

### Script won't run
**Solution**: Enable PowerShell script execution:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## File Formats Supported

### Input Formats
- ✅ **PDF** - All standard PDF files
- ✅ **Multi-page PDFs** - Automatically handles multiple pages

### Output Formats
- 📄 **Markdown (.md)** - Main output format
- 🖼️ **PNG Images** - High-quality page images
- 📁 **Preserved Structure** - Maintains folder organization

## Performance Tips

### For Large Documents
- Use lower DPI (e.g., `-DPI 150`) for faster processing
- Use `-SkipOCR` to skip text extraction
- Process folders in smaller batches

### For Better Quality
- Use higher DPI (e.g., `-DPI 600`) for detailed documents
- Ensure good lighting in scanned documents
- Use high-quality source PDFs

## Advanced Usage

### Convert Single File
Use the individual Python scripts:
```powershell
python convert_pdf_to_png.py "document.pdf" --all-pages
python convert_png_to_markdown.py "document_folder/" --recursive
```

### Custom Processing
Modify the Python scripts to:
- Change image formats
- Adjust OCR settings
- Customize Markdown output

## Getting Help

### Built-in Help
```powershell
.\Convert-DocumentPipeline.ps1
# Shows usage information and examples
```

### Common Solutions

**Q: Can I convert Word documents?**  
A: Not directly. Convert to PDF first using Word's "Save as PDF" feature.

**Q: Will this work on Mac/Linux?**  
A: The Python scripts will work, but you'll need to adapt the PowerShell parts.

**Q: Can I process password-protected PDFs?**  
A: No, remove password protection first.

**Q: How do I improve text extraction quality?**  
A: Use higher DPI settings and ensure source documents are clear.

## Examples

### Convert Invoice Documents
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\Invoices\2024" -DPI 300
```

### Convert Technical Manuals (High Quality)
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\Manuals" -DPI 600
```

### Quick Conversion (No Text Extraction)
```powershell
.\Convert-PdfToMarkdown.ps1 "C:\QuickDocs" -SkipOCR -DPI 150
```

## What's Created

### Markdown Document Structure
Each converted document includes:
- Document title (from filename)
- Conversion timestamp
- Page count information
- High-quality page images
- Extracted text (if OCR enabled)
- Proper Markdown formatting

### Example Output
```markdown
# test_invoice

*Converted from PNG images on 2025-08-29 19:23:37*

*This document contains 3 pages*

## Page 1

![Page 1](test_invoice Page (1).png)

### Extracted Text
```
Elkjop Norge AS
Nydalsveien 12B , NO-0484 Oslo
Dedge AS
ELKJOP
Baglergata 18 Kvittering
N-2004 LILLESTROM Fakturanummer 9238522362
Fakturadato 21. juni 2025
...
```

---

## Page 2
...
```

## Support

If you encounter issues:

1. **Check the logs** - The script shows detailed progress
2. **Try basic options** - Start with simple conversion
3. **Manual installation** - Install dependencies manually if needed
4. **Test with small files** - Verify with single PDF first

Remember: The tool is designed to be user-friendly and handle most situations automatically!
