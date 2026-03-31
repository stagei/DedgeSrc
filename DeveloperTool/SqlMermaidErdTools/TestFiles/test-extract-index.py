#!/usr/bin/env python3
import sqlglot
from sqlglot import parse, exp

sql = "CREATE INDEX idx_test ON TestTable (name);"
statements = parse(sql)
stmt = statements[0]

print(f"Statement type: {type(stmt).__name__}")
print(f"Statement kind: {stmt.kind}")
print(f"has 'this': {hasattr(stmt, 'this')}")
print(f"stmt.this: {stmt.this}")
print(f"stmt.this type: {type(stmt.this).__name__}")

index_obj = stmt.this
print(f"\nindex_obj.this: {index_obj.this if hasattr(index_obj, 'this') else 'NO ATTR'}")
print(f"index_obj.table: {index_obj.table if hasattr(index_obj, 'table') else 'NO ATTR'}")
print(f"index_obj.params: {index_obj.params if hasattr(index_obj, 'params') else 'NO ATTR'}")

if hasattr(index_obj, 'this'):
    name_obj = index_obj.this
    print(f"\nname_obj: {name_obj}")
    print(f"name_obj type: {type(name_obj).__name__}")
    print(f"name_obj.this: {name_obj.this if hasattr(name_obj, 'this') else str(name_obj)}")

if hasattr(index_obj, 'table'):
    table_obj = index_obj.table
    print(f"\ntable_obj: {table_obj}")
    print(f"table_obj type: {type(table_obj).__name__}")
    if hasattr(table_obj, 'this'):
        table_ident = table_obj.this
        print(f"table_ident: {table_ident}")
        print(f"table_ident type: {type(table_ident).__name__}")
        print(f"table_ident.this: {table_ident.this if hasattr(table_ident, 'this') else str(table_ident)}")

