"""
Quick test of the RAG search (no Cursor needed).
Run from AiDoc.Python with the index built: py -3 test_rag_query.py
"""
import sys
sys.path.insert(0, ".")
from server import search_db2_docs

if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else "SQL30082N reason code 36 UNEXPECTED CLIENT ERROR"
    print("Query:", query)
    print("-" * 60)
    result = search_db2_docs(query, n_results=3)
    print(result[:3000] + ("..." if len(result) > 3000 else ""))
