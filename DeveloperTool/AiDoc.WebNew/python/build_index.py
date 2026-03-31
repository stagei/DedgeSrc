"""
Build the ChromaDB vector index from configured markdown sources.
Reads rag_sources.json for source roots; falls back to Db2 manuals only if missing.
Run once (or when manuals change) so the MCP server can answer queries quickly.
All steps and errors are logged to RAG_LOG_DIR (or C:\\opt\\data\\AllPwshLog).

Writes .index_manifest.json next to content_root for outdated-index detection.

  python build_index.py           -- single index from rag_sources.json (legacy)
  python build_index.py --all     -- one index per AiDoc.Library/<name>/
"""
from pathlib import Path
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent

def _resolve_library_dir() -> Path:
    env = os.environ.get("AIDOC_LIBRARY_DIR", "").strip()
    if env and Path(env).is_dir():
        return Path(env)
    opt = os.environ.get("OptPath", "").strip()
    if opt:
        p = Path(opt) / "data" / "AiDoc.Library"
        if p.is_dir():
            return p
    return SCRIPT_DIR.parent / "AiDoc.Library"

LIBRARY_DIR = _resolve_library_dir()
INDEX_DIR = SCRIPT_DIR / ".db2-docs-index"
CONFIG_PATH = SCRIPT_DIR / "rag_sources.json"
COLLECTION_NAME = "db2_luw_manuals"
DEFAULT_EXCLUDE = ["**/node_modules/**", "**/.git/**", "**/index.md"]

# Logging: set up on first use
_logger = None

def _log():
    global _logger
    if _logger is None:
        from rag_logging import setup_rag_logging
        _logger = setup_rag_logging("build_index")
    return _logger


def load_sources(base_path: Path) -> tuple[list[tuple[Path, str]], list[str]]:
    """
    Load source list and exclude patterns from rag_sources.json.
    Returns (sources, exclude_patterns) where sources is [(absolute_path, name), ...].
    Paths in config can be absolute or relative to base_path (AiDoc root).
    """
    if not CONFIG_PATH.is_file():
        # Default: single Db2 manuals folder
        default_dir = base_path / "Db2-LUW-Version-121-English-Manuals"
        return ([(default_dir, "Db2 12.1 manuals")], ["**/node_modules/**", "**/.git/**", "**/index.md"])
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    sources = []
    for entry in data.get("sources", []):
        raw_path = entry.get("path", "")
        name = entry.get("name") or raw_path
        p = Path(raw_path)
        if not p.is_absolute():
            p = base_path / raw_path
        sources.append((p.resolve(), name))
    exclude = data.get("exclude_patterns", DEFAULT_EXCLUDE)
    return sources, exclude


def _collect_file_manifest(
    content_root: Path,
    sources: list[tuple[Path, str]],
    exclude_patterns: list[str],
) -> tuple[list[dict], str]:
    """Collect (path, mtime, size) for all indexed .md files. Paths relative to content_root."""
    from chunk import _path_matches_exclude

    entries: list[tuple[str, str, int]] = []
    for root_path, _ in sources:
        if not root_path.is_dir():
            continue
        for path in sorted(root_path.rglob("*.md")):
            if path.name.lower() == "index.md" or _path_matches_exclude(path, exclude_patterns):
                continue
            rel = str(path.relative_to(content_root)).replace("\\", "/")
            mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).isoformat()
            size = path.stat().st_size
            entries.append((rel, mtime, size))

    files = [{"path": p, "mtime": m, "size": s} for p, m, s in entries]
    hash_input = "|".join(f"{p}|{m}|{s}" for p, m, s in sorted(entries, key=lambda x: x[0]))
    source_hash = hashlib.sha256(hash_input.encode()).hexdigest()[:32]
    return files, source_hash


def _write_manifest(content_root: Path, files: list[dict], source_hash: str) -> None:
    """Write .index_manifest.json next to content_root for outdated-index detection."""
    manifest = {
        "builtAt": datetime.now(timezone.utc).isoformat(),
        "sourceHash": source_hash,
        "files": files,
    }
    manifest_path = content_root / ".index_manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    _log().info("Wrote manifest: %s", manifest_path)


def build_index_for_content(
    content_root: Path,
    index_dir: Path,
    collection_name: str,
    exclude_patterns: list[str] | None = None,
) -> None:
    """Build one ChromaDB index from all **/*.md under content_root; write to index_dir."""
    from chunk import chunk_sources, chunk_id, _path_matches_exclude

    exclude_patterns = exclude_patterns or DEFAULT_EXCLUDE
    # Sources = immediate subdirs of content_root that contain .md, or content_root itself
    sources: list[tuple[Path, str]] = []
    for sub in sorted(content_root.iterdir()):
        if sub.is_dir() and next(sub.rglob("*.md"), None) is not None:
            sources.append((sub, sub.name))
    if not sources and next(content_root.rglob("*.md"), None) is not None:
        sources = [(content_root, content_root.name)]
    if not sources:
        _log().warning("No markdown sources under %s", content_root)
        return

    chunks = chunk_sources(sources, exclude_patterns)
    if not chunks:
        _log().warning("No chunks from %s", content_root)
        return

    import chromadb
    from rag_embedding import LocalONNXMiniLM_L6_V2

    index_dir.mkdir(parents=True, exist_ok=True)
    ef = LocalONNXMiniLM_L6_V2()
    client = chromadb.PersistentClient(path=str(index_dir))
    try:
        client.delete_collection(collection_name)
    except Exception:
        pass
    coll = client.create_collection(
        collection_name,
        embedding_function=ef,
        metadata={"description": f"RAG docs: {collection_name}"},
    )
    ids = []
    documents = []
    metadatas = []
    for text, meta in chunks:
        cid = chunk_id(text, meta)
        ids.append(cid)
        documents.append(text)
        metadatas.append({k: v for k, v in meta.items() if isinstance(v, (str, int, float, bool))})
    batch_size = 100
    for i in range(0, len(ids), batch_size):
        coll.add(
            ids=ids[i : i + batch_size],
            documents=documents[i : i + batch_size],
            metadatas=metadatas[i : i + batch_size],
        )
        n = min(i + batch_size, len(ids))
        _log().info("Indexed %s/%s", n, len(ids))
        print(f"  Indexed {n}/{len(ids)}", flush=True)
    files, source_hash = _collect_file_manifest(content_root, sources, exclude_patterns)
    _write_manifest(content_root, files, source_hash)

    _log().info("Done. Index in %s", index_dir)
    print(f"Done. Index in {index_dir}", flush=True)


def main() -> None:
    _log().info("build_index.py started; argv=%s", sys.argv)
    # Single RAG: python build_index.py --rag <name>
    if "--rag" in sys.argv:
        try:
            i = sys.argv.index("--rag")
            rag_name = sys.argv[i + 1]
        except (IndexError, ValueError):
            _log().error("Usage: python build_index.py --rag <name>")
            sys.exit(1)
        rag_dir = LIBRARY_DIR / rag_name
        if not rag_dir.is_dir():
            _log().error("Library RAG folder not found: %s", rag_dir)
            sys.exit(1)
        index_dir = rag_dir / ".index"
        coll_name = rag_name.replace("-", "_")
        _log().info("Building RAG: %s -> %s", rag_name, index_dir)
        print(f"Building RAG: {rag_name} ...", flush=True)
        build_index_for_content(rag_dir, index_dir, coll_name)
        return

    if "--all" in sys.argv:
        if not LIBRARY_DIR.is_dir():
            _log().error("No library folder. Run Initialize-LibraryFromRoot.ps1 first.")
            sys.exit(1)
        _log().info("Building all library RAGs under %s", LIBRARY_DIR)
        for rag_dir in sorted(LIBRARY_DIR.iterdir()):
            if not rag_dir.is_dir() or rag_dir.name.startswith("."):
                continue
            rag_name = rag_dir.name
            index_dir = rag_dir / ".index"
            coll_name = rag_name.replace("-", "_")
            _log().info("Building RAG: %s -> %s", rag_name, index_dir)
            print(f"Building RAG: {rag_name} ...", flush=True)
            build_index_for_content(rag_dir, index_dir, coll_name)
        return

    # Legacy: single index from rag_sources.json
    from chunk import chunk_sources, chunk_id

    _log().info("Legacy mode: loading sources from %s", CONFIG_PATH)
    sources, exclude_patterns = load_sources(ROOT)
    valid_sources = [(p, name) for p, name in sources if p.is_dir()]
    if not valid_sources:
        _log().error("No valid source directories found. Check rag_sources.json and paths.")
        sys.exit(1)

    _log().info("Chunking %s source(s)...", len(valid_sources))
    print("Chunking sources...", flush=True)
    chunks = chunk_sources(valid_sources, exclude_patterns)
    _log().info("Got %s chunks from %s source(s)", len(chunks), len(valid_sources))
    print(f"Got {len(chunks)} chunks from {len(valid_sources)} source(s)", flush=True)
    if not chunks:
        _log().error("No content to index.")
        sys.exit(1)

    import chromadb
    from rag_embedding import LocalONNXMiniLM_L6_V2

    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    ef = LocalONNXMiniLM_L6_V2()
    client = chromadb.PersistentClient(path=str(INDEX_DIR))
    try:
        client.delete_collection(COLLECTION_NAME)
    except Exception:
        pass
    coll = client.create_collection(
        COLLECTION_NAME,
        embedding_function=ef,
        metadata={"description": "RAG docs (multi-source)"},
    )

    ids = []
    documents = []
    metadatas = []
    for text, meta in chunks:
        cid = chunk_id(text, meta)
        ids.append(cid)
        documents.append(text)
        metadatas.append({k: v for k, v in meta.items() if isinstance(v, (str, int, float, bool))})

    batch_size = 100
    for i in range(0, len(ids), batch_size):
        coll.add(
            ids=ids[i : i + batch_size],
            documents=documents[i : i + batch_size],
            metadatas=metadatas[i : i + batch_size],
        )
        n = min(i + batch_size, len(ids))
        _log().info("Indexed %s/%s", n, len(ids))
        print(f"Indexed {n}/{len(ids)}", flush=True)

    _log().info("Done. Index in %s", INDEX_DIR)
    print(f"Done. Index in {INDEX_DIR}", flush=True)


if __name__ == "__main__":
    main()
