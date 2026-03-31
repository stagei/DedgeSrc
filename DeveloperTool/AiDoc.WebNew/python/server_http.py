"""
HTTP server exposing RAG search for network access. Run on a server machine so clients can query over the network.
All requests and errors are logged to RAG_LOG_DIR (or C:\\opt\\data\\AllPwshLog).

  python server_http.py --rag db2-docs [--host 0.0.0.0] [--port 8765]

  POST /query  Body: {"query": "your question", "n_results": 6}  -> {"result": "chunk text..."}
  GET  /query?q=your+question&n=6  -> {"result": "..."}
  GET  /health  -> 200 OK (for load balancers / readiness)
  GET  /rags   -> JSON registry of all available RAGs and their ports
"""
import argparse
import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# Logging
from rag_logging import setup_rag_logging
_logger = setup_rag_logging("server_http")

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
REGISTRY_FILE = LIBRARY_DIR / "rag-registry.json"


def _parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--rag", required=True, help="RAG name (library subfolder), e.g. db2-docs")
    p.add_argument("--host", default="0.0.0.0", help="Bind address. Use 0.0.0.0 for all interfaces.")
    p.add_argument("--port", type=int, default=8765, help="Port to listen on")
    return p.parse_args()


def _init_server_module(rag_name: str) -> None:
    """Set sys.argv so server.py parses --rag, then import so INDEX_DIR/COLLECTION_NAME are set."""
    sys.argv = [str(SCRIPT_DIR / "server.py"), "--rag", rag_name]
    sys.path.insert(0, str(SCRIPT_DIR))


def _check_dependencies() -> None:
    """
    Eagerly verify that critical Python packages are importable.
    Raises ImportError with a clear message if the venv is incomplete.
    Called once at startup so NSSM sees the process exit immediately
    instead of serving a misleading /health OK while queries fail.
    """
    missing = []
    for pkg in ("chromadb", "onnxruntime"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        raise ImportError(
            f"Required package(s) not installed in venv: {', '.join(missing)}. "
            "Run Fix-VenvAndRestart.ps1 to rebuild the Python virtual environment."
        )


def main() -> int:
    args = _parse_args()
    _logger.info("server_http.py started; rag=%s host=%s port=%s", args.rag, args.host, args.port)

    # Fail fast if venv is broken — prevents /health returning OK while queries fail
    try:
        _check_dependencies()
    except ImportError as e:
        _logger.error("Startup dependency check failed: %s", e)
        return 1

    _init_server_module(args.rag)
    from server import search_db2_docs

    class RAGHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.startswith("/health"):
                # Shallow liveness check — process is alive
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"OK")
                return
            if self.path.startswith("/ready"):
                # Deep readiness check — verify chromadb collection is actually openable
                try:
                    from server import _get_collection
                    _get_collection()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"ready": True, "rag": args.rag}).encode())
                except Exception as e:
                    _logger.error("/ready check failed: %s", e)
                    self.send_response(503)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"ready": False, "error": str(e)}).encode())
                return
            if self.path.startswith("/rags"):
                try:
                    data = json.loads(REGISTRY_FILE.read_text(encoding="utf-8"))
                    # Enrich each RAG with builtAt from .index_manifest.json
                    for rag in data.get("rags", []):
                        manifest_path = LIBRARY_DIR / rag["name"] / ".index_manifest.json"
                        if manifest_path.is_file():
                            try:
                                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                                rag["builtAt"] = manifest.get("builtAt", "")
                            except Exception:
                                rag["builtAt"] = ""
                        else:
                            rag["builtAt"] = ""
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps(data).encode())
                except FileNotFoundError:
                    self.send_response(404)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "rag-registry.json not found"}).encode())
                except Exception as e:
                    _logger.exception("GET /rags error")
                    self.send_response(500)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": str(e)}).encode())
                return
            if self.path.startswith("/query"):
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                query = (qs.get("q") or [""])[0]
                n = int((qs.get("n") or ["6"])[0])
                if not query:
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "Missing query parameter 'q'"}).encode())
                    return
                try:
                    result = search_db2_docs(query, n_results=n)
                    _logger.info("GET /query q=%s n=%s -> 200 len=%s", query[:80], n, len(result))
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"result": result}).encode())
                except FileNotFoundError as e:
                    _logger.error("GET /query FileNotFoundError: %s", e)
                    self.send_response(503)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": str(e)}).encode())
                except Exception as e:
                    _logger.exception("GET /query error")
                    self.send_response(500)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": str(e)}).encode())
                return
            self.send_response(404)
            self.end_headers()

        def do_POST(self):
            if self.path != "/query" and not self.path.startswith("/query?"):
                self.send_response(404)
                self.end_headers()
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8") if content_length else "{}"
            try:
                data = json.loads(body) if body.strip() else {}
            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
                return
            query = data.get("query", "")
            n = int(data.get("n_results", data.get("n", 6)))
            if not query:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Missing 'query' in body"}).encode())
                return
            try:
                result = search_db2_docs(query, n_results=n)
                _logger.info("POST /query query=%s n=%s -> 200 len=%s", query[:80], n, len(result))
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"result": result}).encode())
            except FileNotFoundError as e:
                _logger.error("POST /query FileNotFoundError: %s", e)
                self.send_response(503)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
            except Exception as e:
                _logger.exception("POST /query error")
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())

        def log_message(self, format, *args):
            msg = args[0] if args else format
            _logger.info("%s", msg)
            print(msg)

    server = HTTPServer((args.host, args.port), RAGHandler)
    print(f"RAG HTTP server (rag={args.rag}) listening on http://{args.host}:{args.port}")
    print("  POST /query  JSON body: {\"query\": \"...\", \"n_results\": 6}")
    print("  GET  /query?q=...&n=6")
    print("  GET  /health            Shallow liveness  (process alive)")
    print("  GET  /ready             Deep readiness    (chromadb collection openable)")
    print("  GET  /rags              RAG registry (all available RAGs and ports)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
