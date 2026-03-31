#!/usr/bin/env python3
"""
Convert PDF to Markdown via an intermediate Word (docx) step using pdf2docx and Pandoc.
The docx is created only as a temp file and is not written to the output folder.
Output: a single .md file in the given output folder (same base name as the input PDF).
Images are extracted from the temp docx and embedded in the markdown as base64 data URIs.
"""

import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

# MIME types for common image extensions in docx word/media/
MEDIA_MIME = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".emf": "image/x-emf",
    ".wmf": "image/x-wmf",
}


def find_pandoc() -> str:
    """Return path to pandoc executable, or 'pandoc' if on PATH."""
    exe = shutil.which("pandoc")
    return exe or "pandoc"


def convert_pdf_to_docx(pdf_path: Path, docx_path: Path) -> None:
    """Convert PDF to DOCX using pdf2docx. Writes to the given path (caller may use a temp file)."""
    from pdf2docx import Converter

    cv = Converter(str(pdf_path))
    try:
        cv.convert(str(docx_path))
    finally:
        cv.close()


def extract_images_from_docx(docx_path: Path) -> dict[str, tuple[bytes, str]]:
    """Extract images from a docx (zip) as name -> (raw_bytes, mime_type)."""
    result: dict[str, tuple[bytes, str]] = {}
    with zipfile.ZipFile(docx_path, "r") as z:
        for info in z.infolist():
            if not info.filename.startswith("word/media/"):
                continue
            name = info.filename.replace("word/media/", "")
            ext = Path(name).suffix.lower()
            mime = MEDIA_MIME.get(ext, "application/octet-stream")
            result[name] = (z.read(info), mime)
    return result


def embed_images_in_markdown(md_text: str, images: dict[str, tuple[bytes, str]]) -> str:
    """Replace media/... image refs with base64 data URIs using Markdown image syntax.

    Use ![alt](data:...) instead of <img> so previewers (VS Code, Cursor, etc.) render
    the image instead of showing raw HTML.
    """
    def repl(match: re.Match) -> str:
        src = match.group(1)
        if "media/" not in src:
            return match.group(0)
        name = src.split("media/")[-1].split("?")[0]
        if name not in images:
            return match.group(0)
        data, mime = images[name]
        b64 = base64.b64encode(data).decode("ascii")
        data_uri = f"data:{mime};base64,{b64}"
        return f"![{name}]({data_uri})"
    # Match <img src="media/..."> or <img src='media/...'> (full tag)
    md_text = re.sub(
        r'<img\s+src=["\']([^"\']+)["\']([^>]*)>',
        repl,
        md_text,
    )
    # Convert any remaining <img src="data:..."> (e.g. from prior run) to Markdown syntax
    # so previewers render them; data URI may span newlines
    def data_uri_repl(m: re.Match) -> str:
        uri = m.group(1).replace("\n", "").replace("\r", "")
        return f"![]({uri})"
    md_text = re.sub(
        r'<img\s+src="(data:image.*?)"[^>]*>',
        data_uri_repl,
        md_text,
        flags=re.DOTALL,
    )
    return md_text


def _normalize_toc_title(s: str) -> str:
    """Strip dots, extra spaces, and bold markers from a TOC title fragment."""
    s = re.sub(r"\s*\.\s*\.\s*\.?\s*", " ", s)  # dot leaders to space
    s = re.sub(r"\*+", "", s).strip()
    return re.sub(r"\s+", " ", s).strip()


def _parse_toc_block(block: str) -> list[tuple[str, int | None]]:
    """Parse a messy TOC block into (title, page) entries. Handles wrapped titles and dot leaders."""
    entries: list[tuple[str, int | None]] = []
    current_fragments: list[str] = []
    last_page: int | None = None

    # Already-cleaned line: "- **Title** (p. N)"
    already_clean = re.compile(r"^-\s*\*\*(.+?)\*\*\s*\(p\.\s*(\d+)\)\s*$")

    for raw_line in block.splitlines():
        line = raw_line.strip()
        if not line:
            if current_fragments and last_page is not None:
                entries.append((" ".join(current_fragments), last_page))
                current_fragments = []
            last_page = None
            continue
        if re.match(r"^[\s\.]+$", line):
            continue
        m_clean = already_clean.match(line)
        if m_clean:
            title = m_clean.group(1).strip()
            page = int(m_clean.group(2))
            # Handle line that got merged: " - Title1 (p. 3) - Title2 (p. 5) - ..."
            if " (p. " in title and " - " in title:
                for part in re.split(r"\s+-\s+", title):
                    part = part.strip()
                    pm = re.search(r"\(p\.\s*(\d+)\)\s*$", part)
                    if pm:
                        t = part[: pm.start()].strip().strip("*").lstrip("- ").strip()
                        if t:
                            entries.append((t, int(pm.group(1))))
                    elif part and not part.startswith("("):
                        entries.append((part.strip("*"), page))
            else:
                entries.append((title, page))
            continue

        # Trailing page number only (e.g. ".... 6" or ". . . . . . 22")
        page_match = re.search(r"\s+(\d{1,2})\s*$", line)
        page: int | None = int(page_match.group(1)) if page_match else None
        if page_match:
            title_part = line[: page_match.start()].strip()
        else:
            title_part = line

        # "N**" anywhere: page number in Word TOC style (e.g. "..... 5** Installation Notes" or "Title 5**")
        nstar = re.search(r"(\d{1,2})\s*\*+", title_part)
        if nstar:
            page = int(nstar.group(1))
            before = _normalize_toc_title(title_part[: nstar.start()].strip())
            after = _normalize_toc_title(title_part[nstar.end() :].strip())
            if before:
                current_fragments.append(before)
            if current_fragments:
                entries.append((" ".join(current_fragments), page))
                current_fragments = []
            title_part = after
        else:
            title_part = _normalize_toc_title(title_part)
        if not title_part:
            if page is not None and current_fragments:
                entries.append((" ".join(current_fragments), page))
                current_fragments = []
            last_page = page
            continue

        current_fragments.append(title_part)
        if page is not None:
            entries.append((" ".join(current_fragments), page))
            current_fragments = []
            last_page = None
        else:
            last_page = None

    if current_fragments:
        entries.append((" ".join(current_fragments), last_page))
    return entries


def _fix_toc_entries(entries: list[tuple[str, int | None]]) -> list[tuple[str, int | None]]:
    """Post-process entries to match Word TOC: strip leading page digits, split merged rows."""
    fixed: list[tuple[str, int | None]] = []
    # Pattern: " N SectionName" where N is page and SectionName is a known TOC heading
    section_pattern = re.compile(
        r"\s+(\d{1,2})\s+"
        r"(Significant Changes in Behavior or Usage|Resolved Issues|Other Resolved Issues|New Features)\s*",
        re.IGNORECASE,
    )

    for title, page in entries:
        if not title or not title.strip():
            continue
        # Strip leading digit+space (e.g. "5 Known Issues" -> "Known Issues")
        title = re.sub(r"^\d+\s+", "", title.strip())
        if not title:
            continue

        # Find all " N SectionName" in merged entry (to match Word TOC structure)
        matches = list(section_pattern.finditer(title))
        if matches:
            preamble = title[: matches[0].start()].strip()
            preamble = _normalize_toc_title(preamble)
            if preamble and preamble != ".":
                fixed.append((preamble, int(matches[0].group(1))))
            for m in matches:
                pnum, name = int(m.group(1)), m.group(2).strip()
                name = _normalize_toc_title(name)
                if name:
                    fixed.append((name, pnum))
            continue

        # Strip leading digit from title if still present
        title = re.sub(r"^\d+\s+", "", title)
        fixed.append((title, page))
    return fixed


def clean_table_of_contents(md_text: str) -> str:
    """Find a 'Table of contents' block and replace only that block with a clean list. Preserve body after TOC."""
    toc_start = re.search(
        r"\*\*Table of contents\*\*|^#+\s*Table of contents",
        md_text,
        re.IGNORECASE | re.MULTILINE,
    )
    if not toc_start:
        return md_text

    start_pos = toc_start.start()
    rest = md_text[start_pos:]
    # End after the last TOC line (trailing page number), not at the next image, so we keep the body.
    lines = rest.split("\n")
    last_toc_line_idx = -1
    for i, line in enumerate(lines):
        # Line must end with a page number (1–2 digits)
        if not re.search(r"\d{1,2}\s*$", line.strip()):
            continue
        # TOC line: has bold, or many dots, or is only dots/spaces + number
        if "**" in line or line.count(".") >= 3 or re.match(r"^[\s\.]+\d{1,2}\s*$", line.strip()):
            last_toc_line_idx = i
    if last_toc_line_idx >= 0:
        end_in_rest = len("\n".join(lines[: last_toc_line_idx + 1]))
    else:
        end_in_rest = len(rest)
    end_pos = start_pos + end_in_rest
    block = md_text[start_pos:end_pos]

    # Keep the heading line; parse the rest
    first_line_match = re.match(r"^([^\n]+)\n?", block)
    heading = first_line_match.group(1).strip() if first_line_match else "**Table of contents**"
    content = block[len(heading) :].lstrip("\n") if first_line_match else block

    entries = _parse_toc_block(content)
    if not entries:
        return md_text
    entries = _fix_toc_entries(entries)

    new_toc_lines = [heading, ""]
    for title, page in entries:
        if not title:
            continue
        title = title.lstrip("- ").strip()
        if not title:
            continue
        # Skip image markdown, blockquote fragments, or other non-TOC noise
        if title.startswith("![") or "](data:" in title or len(title) > 200:
            continue
        if title.startswith(">") or "<u>" in title or "Back to " in title:
            continue
        # Normalize trailing " ." from conversion artifacts
        title = re.sub(r"\s+\.\s*$", "", title)
        if page is not None:
            new_toc_lines.append(f"- **{title}** (p. {page})")
            print(f"  TOC entry -> md: p. {page} ({title[:50]}{'...' if len(title) > 50 else ''})")
        else:
            new_toc_lines.append(f"- **{title}**")
    new_toc = "\n".join(new_toc_lines) + "\n\n"

    return md_text[:start_pos] + new_toc + md_text[end_pos:]


def convert_docx_to_markdown(docx_path: Path, md_path: Path, pandoc_exe: str) -> None:
    """Convert DOCX to Markdown using Pandoc."""
    result = subprocess.run(
        [pandoc_exe, str(docx_path), "-o", str(md_path), "-f", "docx", "-t", "gfm"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Pandoc failed: {result.stderr or result.stdout or 'unknown error'}"
        )


def collect_pdfs(input_dir: Path, recursive: bool) -> list[Path]:
    """Return list of PDF paths under input_dir. If not recursive, only top-level."""
    input_dir = input_dir.resolve()
    if recursive:
        found = [p for p in input_dir.rglob("*.pdf") if p.is_file()]
    else:
        found = [p for p in input_dir.iterdir() if p.is_file() and p.suffix.lower() == ".pdf"]
    return sorted(found)


def convert_one_pdf(pdf_path: Path, md_path: Path, pandoc_exe: str) -> bool:
    """Convert one PDF to one Markdown file. Returns True on success, False on failure."""
    fd, temp_docx = tempfile.mkstemp(suffix=".docx", prefix="pdf2md_")
    os.close(fd)
    docx_path = Path(temp_docx)
    try:
        print(f"Input PDF:  {pdf_path}")
        print(f"Output:     {md_path}")
        print("Converting PDF -> DOCX (temp)...")
        convert_pdf_to_docx(pdf_path, docx_path)
        print("Converting DOCX -> Markdown...")
        convert_docx_to_markdown(docx_path, md_path, pandoc_exe)
        md_text = md_path.read_text(encoding="utf-8", errors="replace")
        images = extract_images_from_docx(docx_path)
        if images:
            md_text = embed_images_in_markdown(md_text, images)
            print(f"Embedded {len(images)} image(s) as base64 in markdown.")
        try:
            md_text = clean_table_of_contents(md_text)
        except Exception as e:
            print(f"Warning: TOC restructuring failed ({e}); outputting markdown unchanged.", file=sys.stderr)
        md_path.write_text(md_text, encoding="utf-8")
        print(f"Done. MD:   {md_path}")
        return True
    except Exception as e:
        print(f"Error converting {pdf_path}: {e}", file=sys.stderr)
        return False
    finally:
        try:
            docx_path.unlink(missing_ok=True)
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert PDF to Word and Markdown (PDF -> docx -> md)."
    )
    parser.add_argument(
        "input_path",
        type=Path,
        help="Input PDF file or folder containing PDF files.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output folder (then filename = input stem + .md) or full output file path. Default: ./output (or input folder when input is a folder).",
    )
    parser.add_argument(
        "-r",
        "--recursive",
        action="store_true",
        help="When input is a folder, search subfolders for PDF files.",
    )
    parser.add_argument(
        "--open",
        action="store_true",
        help="Open the generated .md file in the default editor (e.g. VSCode). When processing a folder, opens the first output only.",
    )
    args = parser.parse_args()

    input_path = args.input_path.resolve()
    if not input_path.exists():
        print(f"Error: Input path does not exist: {input_path}", file=sys.stderr)
        return 1
    if not input_path.is_file() and not input_path.is_dir():
        print(f"Error: Input path is not a file or directory: {input_path}", file=sys.stderr)
        return 1

    out = args.output
    if out is None:
        # Single file: default output = same folder as input; folder input: default = input folder
        out = input_path.parent if input_path.is_file() else input_path
    out = out.resolve()

    pandoc_exe = find_pandoc()
    if not shutil.which(pandoc_exe):
        print("Warning: 'pandoc' not found on PATH. Docx->Markdown may fail.", file=sys.stderr)

    if input_path.is_file():
        # Single-file mode: output can be folder or file
        if out.suffix:
            md_path = out
            out.parent.mkdir(parents=True, exist_ok=True)
            if md_path.suffix.lower() not in (".md", ".markdown", ".mkd", ".mkdn", ".mdwn"):
                print(f"Warning: Output suffix '{md_path.suffix}' is not a standard markdown extension (.md, .markdown). Writing anyway.", file=sys.stderr)
        else:
            out.mkdir(parents=True, exist_ok=True)
            md_path = out / f"{input_path.stem}.md"
        success = convert_one_pdf(input_path, md_path, pandoc_exe)
        if not success:
            return 1
        first_md = md_path
    else:
        # Folder mode: output must be a folder
        if out.suffix:
            print("Error: When input is a folder, output must be a folder, not a single file path.", file=sys.stderr)
            return 1
        out.mkdir(parents=True, exist_ok=True)
        pdf_list = collect_pdfs(input_path, args.recursive)
        if not pdf_list:
            print("No PDF files found.", file=sys.stderr)
            return 0
        input_dir = input_path
        output_dir = out
        same_folder = output_dir == input_dir
        first_md = None
        for pdf_path in pdf_list:
            if same_folder:
                md_path = pdf_path.parent / f"{pdf_path.stem}.md"
            else:
                rel = pdf_path.relative_to(input_dir)
                md_path = output_dir / rel.with_suffix(".md")
                md_path.parent.mkdir(parents=True, exist_ok=True)
            if convert_one_pdf(pdf_path, md_path, pandoc_exe):
                if first_md is None:
                    first_md = md_path
        if first_md is None:
            return 1

    if args.open and first_md is not None:
        if sys.platform == "win32":
            for editor in ("code", "cursor"):
                editor_exe = shutil.which(editor)
                if editor_exe:
                    subprocess.Popen([editor_exe, str(first_md)], start_new_session=True)
                    break
            else:
                os.startfile(str(first_md))
        else:
            subprocess.run(["xdg-open", str(first_md)], check=False)

    return 0


if __name__ == "__main__":
    sys.exit(main())
