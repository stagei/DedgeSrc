#!/usr/bin/env python3
import sqlglot
from sqlglot import parse, exp

sql = "CREATE INDEX idx_test ON TestTable (name);"

statements = parse(sql)

for stmt in statements:
    print(f"Statement type: {type(stmt).__name__}")
    print(f"Statement kind: {stmt.kind if hasattr(stmt, 'kind') else 'N/A'}")
    print(f"\nStatement attributes:")
    for attr in dir(stmt):
        if not attr.startswith('_'):
            val = getattr(stmt, attr)
            if not callable(val):
                print(f"  {attr}: {val}")
    
    if hasattr(stmt, 'this'):
        print(f"\nStatement.this: {stmt.this}")
        print(f"  type: {type(stmt.this).__name__}")
        if hasattr(stmt.this, 'this'):
            print(f"  this.this: {stmt.this.this}")
        if hasattr(stmt.this, 'expressions'):
            print(f"  this.expressions: {stmt.this.expressions}")
    
    print(f"\nFull SQL: {stmt.sql()}")

