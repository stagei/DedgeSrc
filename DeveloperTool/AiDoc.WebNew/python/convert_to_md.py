"""
Convert a file (.pdf, .docx, .txt) to Markdown.

Usage:
    python convert_to_md.py --input <file> --output <file.md>

Supports:
    .pdf  - text extraction via pypdf
    .docx - text extraction via python-docx
    .txt  - plain copy (no conversion needed)

Exit codes:
    0 - success
    1 - error (unsupported format, missing file, conversion failure)
"""
import argparse
import sys
from pathlib import Path


def convert_pdf(input_path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(str(input_path))
    pages = []
    for i, page in enumerate(reader.pages, 1):
        text = page.extract_text() or ""
        if text.strip():
            pages.append(f"## Page {i}\n\n{text.strip()}")
    return "\n\n---\n\n".join(pages) if pages else ""


def convert_docx(input_path: Path) -> str:
    from docx import Document

    doc = Document(str(input_path))
    lines = []
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text:
            continue
        if para.style and para.style.name.startswith("Heading"):
            try:
                level = int(para.style.name.replace("Heading", "").strip())
            except ValueError:
                level = 1
            lines.append(f"{'#' * level} {text}")
        else:
            lines.append(text)
    return "\n\n".join(lines)


def convert_txt(input_path: Path) -> str:
    return input_path.read_text(encoding="utf-8", errors="replace")


CONVERTERS = {
    ".pdf": convert_pdf,
    ".docx": convert_docx,
    ".txt": convert_txt,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert files to Markdown")
    parser.add_argument("--input", required=True, help="Input file path")
    parser.add_argument("--output", required=True, help="Output .md file path")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    ext = input_path.suffix.lower()
    converter = CONVERTERS.get(ext)
    if converter is None:
        print(f"Unsupported file type: {ext}", file=sys.stderr)
        sys.exit(1)

    try:
        markdown = converter(input_path)
    except Exception as e:
        print(f"Conversion error: {e}", file=sys.stderr)
        sys.exit(1)

    if not markdown.strip():
        print(f"Warning: no text extracted from {input_path.name}", file=sys.stderr)

    title = input_path.stem.replace("-", " ").replace("_", " ").title()
    header = f"# {title}\n\n"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(header + markdown, encoding="utf-8")
    print(f"Converted: {input_path.name} -> {output_path.name}")


if __name__ == "__main__":
    main()
