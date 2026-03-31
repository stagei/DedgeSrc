"""
MCP server exposing a RAG search tool over configured markdown sources.
Cursor can call the tool to get relevant chunks as context.

  python server.py              -- single RAG (legacy: .db2-docs-index, db2_luw_manuals)
  python server.py --rag NAME   -- library RAG: uses AiDoc.Library/NAME/.index, collection NAME (e.g. db2-docs, visual-cobol-docs)
"""
import argparse
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

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


def _parse_rag_name() -> tuple[Path, str]:
    """Return (index_dir, collection_name). If --rag NAME, use AiDoc.Library/NAME/.index; else legacy."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--rag", type=str, default=None, help="RAG name (library subfolder), e.g. db2-docs")
    args, _ = parser.parse_known_args()
    if args.rag:
        index_dir = LIBRARY_DIR / args.rag / ".index"
        coll = args.rag.replace("-", "_")
        return index_dir, coll
    index_dir = Path(
        os.environ.get("RAG_INDEX_PATH", "").strip() or str(SCRIPT_DIR / ".db2-docs-index")
    )
    return index_dir, "db2_luw_manuals"


INDEX_DIR, COLLECTION_NAME = _parse_rag_name()
# For library RAGs, index is AiDoc.Library/<name>/.index so parent of index dir is the RAG name
RAG_DISPLAY_NAME = INDEX_DIR.parent.name if INDEX_DIR.parent.name != "AiDoc.Python" else "db2-docs"

# Lazy load to avoid importing heavy libs until first use
_client = None
_coll = None


def _get_collection():
    global _client, _coll
    if _coll is not None:
        return _coll
    if not INDEX_DIR.is_dir():
        raise FileNotFoundError(
            f"RAG index not found at {INDEX_DIR}. Run: python build_index.py --all (or build_index.py for legacy)."
        )
    import chromadb
    from rag_embedding import LocalONNXMiniLM_L6_V2

    ef = LocalONNXMiniLM_L6_V2()
    _client = chromadb.PersistentClient(path=str(INDEX_DIR))
    _coll = _client.get_collection(
        COLLECTION_NAME,
        embedding_function=ef,
    )
    return _coll


def search_db2_docs(query: str, n_results: int = 6) -> str:
    """
    Search the Db2 12.1 LUW English manuals by meaning (vector search).
    Use this when the user asks about DB2 errors, SQL codes, security, configuration, or commands.
    Returns the most relevant text chunks; include them in your answer and cite the source file.
    """
    coll = _get_collection()
    res = coll.query(
        query_texts=[query],
        n_results=n_results,
        include=["documents", "metadatas", "distances"],
    )
    if not res or not res["documents"] or not res["documents"][0]:
        return "No matching sections found. Try rephrasing or check that the index was built (run build_index.py)."
    out = []
    for i, (doc, meta, dist) in enumerate(
        zip(
            res["documents"][0],
            res["metadatas"][0],
            res["distances"][0],
        ),
        1,
    ):
        source = meta.get("source", "?")
        source_name = meta.get("source_name", "")
        label = f"source: {source}" + (f", from: {source_name}" if source_name else "")
        out.append(f"[{i}] ({label}, distance={dist:.3f})\n{doc}")
    return "\n\n---\n\n".join(out)


def main():
    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP(
        RAG_DISPLAY_NAME,
        json_response=True,
    )

    @mcp.tool()
    def query_docs(query: str, n_results: int = 6) -> str:
        """Search this RAG by meaning (semantic search). Use for documentation questions. Returns relevant excerpts; cite the source file in your answer. RAG: """ + RAG_DISPLAY_NAME
        try:
            return search_db2_docs(query, n_results=n_results)
        except FileNotFoundError as e:
            return str(e)
        except Exception as e:
            return f"Search failed: {e}"

    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
