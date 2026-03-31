# RAG status

Fetch the RAG registry and display it as a markdown table. Use `GET http://dedge-server:8484/rags` (or 8485/8486) as primary source; fallback to `rag-registry.json` if API unreachable.

Display columns: **RAG** | **Server** | **Port** | **Last built** | **Description**. Format `builtAt` as date+time (e.g. 2026-03-06 09:48); use — when empty.
