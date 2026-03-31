#!/usr/bin/env python3
import sqlglot
from sqlglot import parse, exp

sql = """
CREATE TABLE TestTable (
    id INT PRIMARY KEY,
    name VARCHAR(100)
);

CREATE INDEX idx_test ON TestTable (name);
"""

statements = parse(sql)

print("Parsed statements:")
for i, stmt in enumerate(statements):
    print(f"{i}: {type(stmt).__name__}")
    print(f"   {stmt}")
    if hasattr(stmt, 'kind'):
        print(f"   kind: {stmt.kind}")
    print()

