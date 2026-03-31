#!/usr/bin/env python3
"""
PNG to Markdown Converter with OCR
=================================

This script converts PNG images to Markdown documents using OCR.
It automatically installs required dependencies if they're not available.

Author: Geir Helge Starholm, www.dEdge.no
Created: 2025-08-29

Usage:
    python convert_png_to_markdown.py <png_path> [options]

Examples:
    python convert_png_to_markdown.py "image.png"
    python convert_png_to_markdown.py "image.png" --output "document.md"
    python convert_png_to_markdown.py "folder/" --recursive
"""

import os
import sys
import subprocess
import argparse
import re
from pathlib import Path
from datetime import datetime

def install_package(package_name, import_name=None):
    """Install a Python package if it's not available."""
    if import_name is None:
        import_name = package_name
    
    try:
        __import__(import_name)
        return True
    except ImportError:
        print(f"{package_name} not found. Installing automatically...")
        try:
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", package_name
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f"✓ {package_name} installed successfully!")
            return True
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to install {package_name}: {e}")
            return False

def import_with_install(package_name, import_name=None, pip_name=None):
    """Import a package with auto-install if needed."""
    if import_name is None:
        import_name = package_name
    if pip_name is None:
        pip_name = package_name
    
    try:
        return __import__(import_name)
    except ImportError:
        if install_package(pip_name, import_name):
            try:
                return __import__(import_name)
            except ImportError:
                print(f"✗ Failed to import {import_name} after installation.")
                return None
        return None

def setup_tesseract():
    """Setup Tesseract OCR engine."""
    # Try to import pytesseract
    pytesseract = import_with_install("pytesseract")
    if not pytesseract:
        return None, None
    
    # Import PIL (Pillow)
    PIL = import_with_install("PIL", "PIL", "Pillow")
    if not PIL:
        return None, None
    
    from PIL import Image
    
    # Try to find Tesseract executable
    tesseract_paths = [
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        r"C:\Users\{}\AppData\Local\Programs\Tesseract-OCR\tesseract.exe".format(os.getenv('USERNAME', '')),
        "tesseract"  # In PATH
    ]
    
    tesseract_exe = None
    for path in tesseract_paths:
        if os.path.exists(path) or path == "tesseract":
            try:
                # Test if tesseract works
                result = subprocess.run([path, "--version"], 
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    tesseract_exe = path
                    break
            except:
                continue
    
    if tesseract_exe:
        pytesseract.pytesseract.tesseract_cmd = tesseract_exe
        print(f"[OK] Found Tesseract at: {tesseract_exe}")
        return pytesseract, Image
    else:
        print("[WARNING] Tesseract OCR not found. OCR functionality will be limited.")
        print("  To install Tesseract:")
        print("  1. Download from: https://github.com/UB-Mannheim/tesseract/wiki")
        print("  2. Or use: winget install UB-Mannheim.TesseractOCR")
        return None, Image

def extract_text_from_image(image_path, pytesseract=None, Image=None):
    """Extract text from an image using OCR."""
    if not pytesseract or not Image:
        return "[OCR not available - Tesseract not installed]"
    
    try:
        # Open and process the image
        image = Image.open(image_path)
        
        # Convert to RGB if necessary
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Extract text using OCR
        text = pytesseract.image_to_string(image, lang='eng')
        
        # Clean up the text
        text = text.strip()
        if not text:
            return "[No text detected in image]"
        
        # Basic cleanup
        lines = text.split('\n')
        cleaned_lines = []
        for line in lines:
            line = line.strip()
            if line:
                cleaned_lines.append(line)
        
        return '\n'.join(cleaned_lines)
        
    except Exception as e:
        return f"[OCR Error: {str(e)}]"

def group_png_files(png_files):
    """Group PNG files by base name (handling page numbering)."""
    file_groups = {}
    
    for png_file in png_files:
        file_name = png_file.name
        base_name = ""
        page_num = 1
        
        # Extract base name and page number
        if " Page (" in file_name:
            # Format: "document Page (1).png"
            match = re.match(r"^(.+?) Page \((\d+)\)\.png$", file_name)
            if match:
                base_name = match.group(1)
                page_num = int(match.group(2))
            else:
                base_name = Path(file_name).stem
        else:
            base_name = Path(file_name).stem
        
        # Group by directory and base name
        relative_path = png_file.parent
        group_key = str(relative_path / base_name)
        
        if group_key not in file_groups:
            file_groups[group_key] = []
        
        file_groups[group_key].append((png_file, page_num))
    
    # Sort files within each group by page number
    for group_key in file_groups:
        file_groups[group_key].sort(key=lambda x: x[1])
    
    return file_groups

def convert_png_group_to_markdown(file_group, output_path, use_ocr=True, pytesseract=None, Image=None):
    """Convert a group of PNG files to a single Markdown document."""
    try:
        # Extract document name from the first file
        first_file, _ = file_group[0]
        doc_name = Path(first_file.name).stem
        if " Page (" in doc_name:
            doc_name = doc_name.split(" Page (")[0]
        
        # Create markdown content
        markdown_lines = []
        markdown_lines.append(f"# {doc_name}")
        markdown_lines.append("")
        markdown_lines.append(f"*Converted from PNG images on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*")
        markdown_lines.append("")
        
        if len(file_group) > 1:
            markdown_lines.append(f"*This document contains {len(file_group)} pages*")
            markdown_lines.append("")
        
        # Process each page
        for i, (png_file, page_num) in enumerate(file_group, 1):
            if len(file_group) > 1:
                markdown_lines.append(f"## Page {i}")
                markdown_lines.append("")
            
            # Add image reference
            relative_image_path = png_file.name
            markdown_lines.append(f"![Page {i}]({relative_image_path})")
            markdown_lines.append("")
            
            # Add OCR text if enabled
            if use_ocr and pytesseract and Image:
                print(f"    Extracting text from {png_file.name}...")
                ocr_text = extract_text_from_image(str(png_file), pytesseract, Image)
                
                if ocr_text and not ocr_text.startswith("["):
                    markdown_lines.append("### Extracted Text")
                    markdown_lines.append("")
                    markdown_lines.append("```")
                    markdown_lines.append(ocr_text)
                    markdown_lines.append("```")
                else:
                    markdown_lines.append(f"*{ocr_text}*")
            else:
                markdown_lines.append("*[OCR disabled or not available]*")
            
            markdown_lines.append("")
            
            # Add separator between pages (except for the last page)
            if i < len(file_group):
                markdown_lines.append("---")
                markdown_lines.append("")
        
        # Write markdown file
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(markdown_lines))
        
        return True
        
    except Exception as e:
        print(f"  ✗ Error creating markdown: {e}")
        return False

def convert_png_to_markdown(input_path, output_path=None, recursive=False, use_ocr=True):
    """Convert PNG files to Markdown documents."""
    
    # Setup OCR if enabled
    pytesseract = None
    Image = None
    if use_ocr:
        print("Setting up OCR engine...")
        pytesseract, Image = setup_tesseract()
        print("")
    
    input_path = Path(input_path)
    
    # Collect PNG files
    png_files = []
    if input_path.is_file() and input_path.suffix.lower() == '.png':
        png_files = [input_path]
    elif input_path.is_dir():
        if recursive:
            png_files = list(input_path.rglob("*.png"))
        else:
            png_files = list(input_path.glob("*.png"))
    else:
        print(f"✗ Invalid input: {input_path}")
        return False
    
    if not png_files:
        print(f"✗ No PNG files found in: {input_path}")
        return False
    
    print(f"Found {len(png_files)} PNG files")
    
    # Group files by document
    file_groups = group_png_files(png_files)
    print(f"Grouped into {len(file_groups)} documents")
    print("")
    
    success_count = 0
    
    # Process each group
    for group_key, file_group in file_groups.items():
        group_path = Path(group_key)
        doc_name = group_path.name
        
        print(f"Processing: {doc_name} ({len(file_group)} pages)")
        
        # Determine output path
        if output_path:
            if len(file_groups) == 1:
                # Single document, use specified output path
                md_output = Path(output_path)
            else:
                # Multiple documents, create files in output directory
                output_dir = Path(output_path)
                if not output_dir.suffix:
                    # It's a directory
                    output_dir.mkdir(parents=True, exist_ok=True)
                    md_output = output_dir / f"{doc_name}.md"
                else:
                    # It's a file, use its directory
                    output_dir = output_dir.parent
                    output_dir.mkdir(parents=True, exist_ok=True)
                    md_output = output_dir / f"{doc_name}.md"
        else:
            # Use same directory as PNG files
            first_file, _ = file_group[0]
            md_output = first_file.parent / f"{doc_name}.md"
        
        # Ensure output directory exists
        md_output.parent.mkdir(parents=True, exist_ok=True)
        
        # Convert the group
        if convert_png_group_to_markdown(file_group, md_output, use_ocr, pytesseract, Image):
            success_count += 1
            file_size_kb = round(md_output.stat().st_size / 1024, 2)
            print(f"  [OK] Created: {md_output.name} ({file_size_kb} KB)")
        else:
            print(f"  [ERROR] Failed to create: {md_output.name}")
        
        print("")
    
    print(f"[SUCCESS] Conversion completed: {success_count}/{len(file_groups)} documents converted")
    return success_count > 0

def main():
    parser = argparse.ArgumentParser(
        description="Convert PNG images to Markdown documents with OCR",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python convert_png_to_markdown.py "image.png"
  python convert_png_to_markdown.py "image.png" --output "document.md"
  python convert_png_to_markdown.py "folder/" --recursive --no-ocr
  python convert_png_to_markdown.py "folder/" --output "output_folder/" --recursive
        """
    )
    
    parser.add_argument("input_path", help="Path to PNG file or directory")
    parser.add_argument("--output", "-o", help="Output path (file or directory)")
    parser.add_argument("--recursive", "-r", action="store_true", help="Process subdirectories recursively")
    parser.add_argument("--no-ocr", action="store_true", help="Disable OCR text extraction")
    
    args = parser.parse_args()
    
    # Display conversion parameters
    print("PNG to Markdown Converter with OCR")
    print("==================================")
    print("")
    print(f"Input: {args.input_path}")
    print(f"Output: {args.output or 'Same as input'}")
    print(f"Recursive: {args.recursive}")
    print(f"OCR enabled: {not args.no_ocr}")
    print("")
    
    # Perform conversion
    print("Starting conversion...")
    success = convert_png_to_markdown(
        args.input_path,
        args.output,
        args.recursive,
        not args.no_ocr
    )
    
    if not success:
        print("✗ Conversion failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
