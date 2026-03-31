"""
MCP proxy server that forwards query_docs calls to a remote RAG HTTP server.
Cursor starts this via stdio MCP; no local ChromaDB/ONNX needed.

  python server_proxy.py --rag db2-docs --remote-host dedge-server --remote-port 8484
  python server_proxy.py --rag visual-cobol-docs --remote-host dedge-server --remote-port 8485
"""
import argparse
import json
import sys
import urllib.request
import urllib.error


def _parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--rag", required=True, help="RAG display name (e.g. db2-docs)")
    p.add_argument("--remote-host", required=True, help="Remote RAG HTTP server hostname")
    p.add_argument("--remote-port", type=int, required=True, help="Remote RAG HTTP server port")
    return p.parse_args()


def _query_remote(host: str, port: int, query: str, n_results: int = 6) -> str:
    url = f"http://{host}:{port}/query"
    payload = json.dumps({"query": query, "n_results": n_results}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("result", "No result returned from remote RAG.")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return f"Remote RAG error (HTTP {e.code}): {body}"
    except urllib.error.URLError as e:
        return f"Cannot reach remote RAG at {url}: {e.reason}"
    except Exception as e:
        return f"Remote RAG query failed: {e}"


def main():
    args = _parse_args()
    rag_name = args.rag
    host = args.remote_host
    port = args.remote_port

    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP(rag_name, json_response=True)

    @mcp.tool()
    def query_docs(query: str, n_results: int = 6) -> str:
        f"""Search this RAG by meaning (semantic search). Use for documentation questions. Returns relevant excerpts; cite the source file in your answer. RAG: {rag_name}"""
        return _query_remote(host, port, query, n_results)

    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
