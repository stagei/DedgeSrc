#!/usr/bin/env python3
import sys
sys.path.insert(0, "src/SqlMermaidErdTools/runtimes/win-x64/scripts")

from sql_to_mmd import parse_sql_to_tables, generate_mermaid_erd

sql = """
CREATE TABLE TestTable (
    id INT PRIMARY KEY,
    name VARCHAR(100)
);

CREATE INDEX idx_test ON TestTable (name);
"""

print("Parsing SQL...")
tables, indexes = parse_sql_to_tables(sql)

print(f"Found {len(tables)} tables")
print(f"Found {len(indexes)} indexes")

for idx in indexes:
    print(f"  Index: {idx}")

print("\nGenerating Mermaid...")
output = generate_mermaid_erd(tables, indexes)
print(output)

