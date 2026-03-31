# Pdf2Markdown

Converts a PDF file to Word (DOCX) and then to Markdown. Uses [pdf2docx](https://pypi.org/project/pdf2docx/) for PDF→DOCX and [Pandoc](https://pandoc.org/) for DOCX→Markdown. Images from the Word file are extracted and embedded in the markdown as base64 data URIs so they display in markdown previewers (e.g. VS Code / Cursor).

## Requirements

- Python 3.8+
- [Pandoc](https://pandoc.org/installing.html) on PATH

## Install

```powershell
cd c:\opt\Src\Pdf2Markdown
pwsh -NoProfile -Command "py -m pip install -r requirements.txt"
```

## Usage

```text
python pdf2markdown.py <input_path> [-o OUTPUT] [-r] [--open]
```

- **input_path** – Input PDF file or folder containing PDF files.
- **-o / --output** – Output folder or full file path. Default: `./output` (single file), or the input folder (when input is a folder).
  - **Single-file input:** If a folder (no extension), output is `{folder}/{input_stem}.md`. If a full filename (e.g. `report.md`), markdown is written to that path (non-standard extension triggers a warning but is written anyway).
  - **Folder input:** Output must be a folder. If you pass a single file path, the program errors: "When input is a folder, output must be a folder, not a single file path."
- **-r / --recursive** – When input is a folder, search subfolders for PDF files. Without this, only PDFs directly in the folder are processed.
- **--open** – Open the generated .md file in the default editor (e.g. VSCode). When processing a folder, opens only the first output.

### Output when input is a folder

- **Same folder:** If the output folder is the same as the input folder (e.g. `-o` omitted or `-o` set to the input path), each `.md` is written next to its PDF (e.g. `in/doc.pdf` → `in/doc.md`).
- **Different folder:** If the output folder is different, the relative structure under the input folder is recreated under the output folder (e.g. input `C:\in`, output `C:\out`, and `C:\in\a\b\file.pdf` → `C:\out\a\b\file.md`).

## Examples

```powershell
# Single PDF
python pdf2markdown.py "C:\path\to\readme.pdf" -o C:\opt\Src\Pdf2Markdown\output --open

# Folder: .md next to each PDF (default -o = input folder)
python pdf2markdown.py "C:\path\to\pdfs"

# Folder: mirror structure under another folder
python pdf2markdown.py "C:\path\to\pdfs" -o C:\out\markdown

# Folder: recursive search
python pdf2markdown.py "C:\path\to\pdfs" -o C:\out\md -r
```
