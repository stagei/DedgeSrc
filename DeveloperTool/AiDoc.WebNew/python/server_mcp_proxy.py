"""
Thin local MCP stdio proxy that forwards RAG queries to a remote HTTP server.
Cursor talks MCP stdio to this script; this script talks HTTP to the network RAG service.

  python server_mcp_proxy.py --rag db2-docs --remote-url http://dedge-server:8484
"""
import argparse
import json
import sys
import urllib.request
import urllib.error


def _parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--rag", required=True, help="RAG name, e.g. db2-docs")
    p.add_argument("--remote-url", required=True, help="Base URL of remote RAG HTTP server, e.g. http://host:8484")
    return p.parse_args()


def _query_remote(base_url: str, query: str, n_results: int = 6) -> str:
    url = f"{base_url.rstrip('/')}/query"
    payload = json.dumps({"query": query, "n_results": n_results}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("result", json.dumps(data))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return f"Remote RAG error (HTTP {e.code}): {body}"
    except Exception as e:
        return f"Remote RAG unreachable: {e}"


def main():
    args = _parse_args()

    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP(args.rag, json_response=True)

    @mcp.tool()
    def query_docs(query: str, n_results: int = 6) -> str:
        """Search this RAG by meaning (semantic search). Use for documentation questions. Returns relevant excerpts; cite the source file in your answer. RAG: """ + args.rag
        return _query_remote(args.remote_url, query, n_results)

    mcp.run(transport="stdio")


if __name__ == "__main__":
    sys.exit(main())
