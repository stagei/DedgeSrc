"""
Chunk markdown files for vector search.
Splits by approximate token size with overlap so semantic search finds relevant sections.
Supports multiple source roots and recursive **/*.md with optional exclude patterns.
"""
from pathlib import Path
import hashlib
import fnmatch

# Target chunk size in characters (~500-800 tokens at ~4 chars/token)
CHUNK_SIZE = 2400
OVERLAP = 300


def _path_matches_exclude(file_path: Path, exclude_patterns: list[str]) -> bool:
    """True if file_path should be excluded (e.g. node_modules, .git, index.md)."""
    path_str = str(file_path).replace("\\", "/")
    name = file_path.name.lower()
    parts = file_path.parts
    for pat in exclude_patterns:
        # **/segment/** or **/segment -> any path containing that segment
        if "**" in pat:
            segment = pat.replace("**", "").strip("/").strip("\\")
            if segment and segment in parts:
                return True
            if segment and segment in path_str:
                return True
        if fnmatch.fnmatch(path_str, pat) or fnmatch.fnmatch(name, pat):
            return True
    return False


def iter_file_chunks(path: Path, source_name: str | None = None) -> list[tuple[str, dict]]:
    """Yield (chunk_text, metadata) for one file. Streams to handle large files."""
    chunks: list[tuple[str, dict]] = []
    buf = []
    buf_len = 0
    meta = {"source": path.name, "path": str(path)}
    if source_name is not None:
        meta["source_name"] = source_name

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            buf.append(line)
            buf_len += len(line)
            if buf_len >= CHUNK_SIZE:
                text = "".join(buf)
                # Try to break at paragraph boundary
                if buf_len > CHUNK_SIZE + 500:
                    last_break = text.rfind("\n\n", CHUNK_SIZE - 500, CHUNK_SIZE + 500)
                    if last_break > CHUNK_SIZE // 2:
                        chunk_text = text[: last_break + 1].strip()
                        overlap_start = max(0, last_break - OVERLAP)
                        remainder = text[overlap_start:].lstrip()
                    else:
                        chunk_text = text[:CHUNK_SIZE].strip()
                        remainder = text[CHUNK_SIZE - OVERLAP :].lstrip()
                else:
                    chunk_text = text.strip()
                    remainder = ""

                if chunk_text:
                    chunks.append((chunk_text, {**meta, "chunk_id": len(chunks)}))
                buf = [remainder] if remainder else []
                buf_len = len(remainder)

        if buf:
            text = "".join(buf).strip()
            if text:
                chunks.append((text, {**meta, "chunk_id": len(chunks)}))

    return chunks


def chunk_manuals(manuals_dir: Path) -> list[tuple[str, dict]]:
    """Chunk all .md files under manuals_dir (flat, no recursion). Kept for backward compat."""
    all_chunks: list[tuple[str, dict]] = []
    md_files = sorted(f for f in manuals_dir.glob("*.md") if f.name.lower() != "index.md")
    for path in md_files:
        try:
            for text, meta in iter_file_chunks(path):
                all_chunks.append((text, meta))
        except Exception as e:
            print(f"Warning: skipped {path}: {e}", flush=True)
    return all_chunks


def chunk_sources(
    sources: list[tuple[Path, str]],
    exclude_patterns: list[str] | None = None,
) -> list[tuple[str, dict]]:
    """
    Chunk all .md files under multiple source roots (recursive **/*.md).
    sources: list of (absolute_path, display_name).
    exclude_patterns: e.g. ["**/node_modules/**", "**/.git/**", "**/index.md"].
    """
    exclude_patterns = exclude_patterns or []
    all_chunks: list[tuple[str, dict]] = []
    for root_path, source_name in sources:
        if not root_path.is_dir():
            print(f"Warning: source not a directory, skipped: {root_path}", flush=True)
            continue
        for path in sorted(root_path.rglob("*.md")):
            if path.name.lower() == "index.md" or _path_matches_exclude(path, exclude_patterns):
                continue
            try:
                for text, meta in iter_file_chunks(path, source_name=source_name):
                    all_chunks.append((text, meta))
            except Exception as e:
                print(f"Warning: skipped {path}: {e}", flush=True)
    return all_chunks


def chunk_id(text: str, meta: dict) -> str:
    """Stable id for dedup and ChromaDB."""
    key = (meta.get("path", "") or meta.get("source", "")) + str(meta.get("chunk_id", "")) + text[:200]
    h = hashlib.sha256(key.encode()).hexdigest()[:16]
    return f"{meta.get('source', '')}_{meta.get('chunk_id', 0)}_{h}"
