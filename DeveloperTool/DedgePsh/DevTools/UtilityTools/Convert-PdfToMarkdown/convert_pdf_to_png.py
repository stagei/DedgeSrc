#!/usr/bin/env python3
"""
PDF to PNG Converter with Auto-Install
=====================================

This script converts PDF files to PNG images using PyMuPDF.
It automatically installs PyMuPDF if it's not available.

Author: Geir Helge Starholm, www.dEdge.no
Created: 2025-08-29

Usage:
    python convert_pdf_to_png.py <pdf_path> [options]

Examples:
    python convert_pdf_to_png.py "document.pdf"
    python convert_pdf_to_png.py "document.pdf" --output "output.png" --dpi 600
    python convert_pdf_to_png.py "document.pdf" --all-pages --dpi 300
    python convert_pdf_to_png.py "document.pdf" --page 2
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

def install_pymupdf():
    """Install PyMuPDF if it's not available."""
    print("PyMuPDF not found. Installing automatically...")
    try:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", "pymupdf"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("✓ PyMuPDF installed successfully!")
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ Failed to install PyMuPDF: {e}")
        return False

def import_fitz():
    """Import fitz (PyMuPDF) with auto-install if needed."""
    try:
        import fitz
        return fitz
    except ImportError:
        if install_pymupdf():
            try:
                import fitz
                return fitz
            except ImportError:
                print("✗ Failed to import PyMuPDF after installation.")
                return None
        return None

def get_pdf_info(pdf_path, fitz):
    """Get information about the PDF file."""
    try:
        doc = fitz.open(pdf_path)
        page_count = len(doc)
        doc.close()
        return page_count
    except Exception as e:
        print(f"✗ Error reading PDF: {e}")
        return 0

def convert_pdf_page_to_png(pdf_path, output_path, page_number, dpi, fitz):
    """Convert a single PDF page to PNG."""
    try:
        doc = fitz.open(pdf_path)
        
        if page_number > len(doc):
            print(f"✗ Page {page_number} does not exist. PDF has {len(doc)} pages.")
            doc.close()
            return False
        
        # Load the specific page (0-indexed)
        page = doc.load_page(page_number - 1)
        
        # Create a transformation matrix for the desired DPI
        # Default is 72 DPI, so we scale by dpi/72
        mat = fitz.Matrix(dpi / 72, dpi / 72)
        
        # Render page to an image
        pix = page.get_pixmap(matrix=mat)
        
        # Save as PNG
        pix.save(output_path)
        
        doc.close()
        
        # Get file size
        file_size = os.path.getsize(output_path)
        file_size_kb = round(file_size / 1024, 2)
        
        print(f"  [OK] Page {page_number} converted successfully ({file_size_kb} KB)")
        return True
        
    except Exception as e:
        print(f"  [ERROR] Error converting page {page_number}: {e}")
        return False

def convert_pdf_to_png(pdf_path, output_path, dpi=300, page_number=1, all_pages=False):
    """Convert PDF to PNG with the specified parameters."""
    
    # Import fitz with auto-install
    fitz = import_fitz()
    if not fitz:
        return False
    
    # Validate input file
    if not os.path.exists(pdf_path):
        print(f"[ERROR] PDF file not found: {pdf_path}")
        return False
    
    # Get PDF information
    page_count = get_pdf_info(pdf_path, fitz)
    if page_count == 0:
        return False
    
    print(f"PDF has {page_count} pages")
    print("")
    
    success_count = 0
    
    if all_pages:
        print("Converting all pages...")
        
        # Create output directory if converting all pages
        output_dir = os.path.dirname(output_path)
        output_base = os.path.splitext(os.path.basename(output_path))[0]
        
        for i in range(1, page_count + 1):
            page_output = os.path.join(output_dir, f"{output_base} Page ({i}).png")
            
            if convert_pdf_page_to_png(pdf_path, page_output, i, dpi, fitz):
                success_count += 1
        
        print("")
        print(f"Converted {success_count} of {page_count} pages")
        
    else:
        print(f"Converting page {page_number}...")
        
        if convert_pdf_page_to_png(pdf_path, output_path, page_number, dpi, fitz):
            success_count = 1
    
    return success_count > 0

def main():
    parser = argparse.ArgumentParser(
        description="Convert PDF files to PNG images with auto-install of dependencies",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python convert_pdf_to_png.py "document.pdf"
  python convert_pdf_to_png.py "document.pdf" --output "output.png" --dpi 600
  python convert_pdf_to_png.py "document.pdf" --all-pages --dpi 300
  python convert_pdf_to_png.py "document.pdf" --page 2
        """
    )
    
    parser.add_argument("pdf_path", help="Path to the input PDF file")
    parser.add_argument("--output", "-o", help="Output PNG file path (optional)")
    parser.add_argument("--dpi", type=int, default=300, help="Resolution in DPI (default: 300)")
    parser.add_argument("--page", "-p", type=int, default=1, help="Page number to convert (default: 1)")
    parser.add_argument("--all-pages", "-a", action="store_true", help="Convert all pages")
    
    args = parser.parse_args()
    
    # Set output path if not specified
    if not args.output:
        pdf_path = Path(args.pdf_path)
        # Use original PDF filename as base
        args.output = str(pdf_path.with_suffix('.png'))
    
    # Display conversion parameters
    print("PDF to PNG Converter with Auto-Install")
    print("=====================================")
    print("")
    print(f"Input PDF: {args.pdf_path}")
    print(f"Output PNG: {args.output}")
    print(f"Resolution: {args.dpi} DPI")
    print(f"Page(s): {'All Pages' if args.all_pages else args.page}")
    print("")
    
    # Perform conversion
    print("Starting conversion...")
    success = convert_pdf_to_png(
        args.pdf_path, 
        args.output, 
        args.dpi, 
        args.page, 
        args.all_pages
    )
    
    print("")
    if success:
        print("[SUCCESS] Conversion completed successfully!")
        
        # Show output files
        if args.all_pages:
            output_dir = os.path.dirname(args.output)
            output_base = os.path.splitext(os.path.basename(args.output))[0]
            # Look for files with the new naming pattern
            output_files = [f for f in os.listdir(output_dir) 
                          if f.startswith(output_base) and " Page (" in f and f.endswith('.png')]
            
            if output_files:
                print("")
                print("Output files:")
                # Sort by page number
                def extract_page_num(filename):
                    try:
                        return int(filename.split(" Page (")[1].split(")")[0])
                    except:
                        return 0
                
                for filename in sorted(output_files, key=extract_page_num):
                    filepath = os.path.join(output_dir, filename)
                    file_size_kb = round(os.path.getsize(filepath) / 1024, 2)
                    print(f"  {filename} ({file_size_kb} KB)")
        else:
            if os.path.exists(args.output):
                file_size_kb = round(os.path.getsize(args.output) / 1024, 2)
                print(f"Output file: {os.path.basename(args.output)} ({file_size_kb} KB)")
    else:
        print("[FAILED] Conversion failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
