#!/usr/bin/env python3
"""
Generates SQL ALTER statements from differences between two Mermaid ERD diagrams.
"""

import sys
import re

def parse_mermaid_schema(mermaid_content):
    """Parse Mermaid ERD and return a dictionary of tables and columns."""
    lines = mermaid_content.strip().split('\n')
    tables = {}
    current_table = None
    
    table_pattern = re.compile(r'^\s*(\w+)\s*\{')
    column_pattern = re.compile(r'^\s*(\w+)\s+(\w+)\s*(?:(PK|FK|UK))?\s*(?:"([^"]+)")?')
    
    for line in lines:
        line = line.strip()
        
        if not line or line == 'erDiagram':
            continue
        
        table_match = table_pattern.match(line)
        if table_match:
            current_table = table_match.group(1)
            tables[current_table] = {'columns': {}, 'order': []}
            continue
        
        if line == '}':
            current_table = None
            continue
        
        column_match = column_pattern.match(line)
        if column_match and current_table:
            data_type = column_match.group(1)
            column_name = column_match.group(2)
            constraint = column_match.group(3) if column_match.group(3) else None
            attributes = column_match.group(4) if column_match.group(4) else ''
            
            tables[current_table]['columns'][column_name] = {
                'type': data_type,
                'constraint': constraint,
                'attributes': attributes
            }
            tables[current_table]['order'].append(column_name)
    
    return tables

def generate_alter_statements(before_tables, after_tables, dialect=''):
    """Generate ALTER TABLE statements for the differences."""
    statements = []
    
    # Find added tables
    for table_name in after_tables:
        if table_name not in before_tables:
            statements.append(f"-- New table: {table_name}")
            statements.append(generate_create_table_from_dict(table_name, after_tables[table_name], dialect))
    
    # Find dropped tables
    for table_name in before_tables:
        if table_name not in after_tables:
            statements.append(f"-- Dropped table: {table_name}")
            statements.append(f"DROP TABLE {table_name};")
    
    # Find modified tables
    for table_name in after_tables:
        if table_name in before_tables:
            before_cols = before_tables[table_name]['columns']
            after_cols = after_tables[table_name]['columns']
            
            # Find added columns
            for col_name in after_cols:
                if col_name not in before_cols:
                    col_def = after_cols[col_name]
                    sql_type = map_type_to_sql(col_def['type'], dialect)
                    attrs = col_def['attributes'].upper() if col_def['attributes'] else ''
                    
                    alter_stmt = f"ALTER TABLE {table_name}\n    ADD COLUMN {col_name} {sql_type}"
                    
                    if 'NOT NULL' in attrs:
                        alter_stmt += ' NOT NULL'
                    
                    # Extract DEFAULT value
                    default_match = re.search(r'DEFAULT\s+([A-Z0-9()]+)', attrs)
                    if default_match:
                        alter_stmt += f' DEFAULT {default_match.group(1)}'
                    
                    alter_stmt += ';'
                    statements.append(f"-- Added column: {table_name}.{col_name}")
                    statements.append(alter_stmt)
            
            # Find dropped columns
            for col_name in before_cols:
                if col_name not in after_cols:
                    statements.append(f"-- Dropped column: {table_name}.{col_name}")
                    statements.append(f"ALTER TABLE {table_name}\n    DROP COLUMN {col_name};")
            
            # Find modified columns (simplified - only check if type changed)
            for col_name in after_cols:
                if col_name in before_cols:
                    before_col = before_cols[col_name]
                    after_col = after_cols[col_name]
                    
                    if before_col['type'] != after_col['type']:
                        sql_type = map_type_to_sql(after_col['type'], dialect)
                        statements.append(f"-- Modified column: {table_name}.{col_name}")
                        
                        if dialect.lower() == 'postgres':
                            statements.append(f"ALTER TABLE {table_name}\n    ALTER COLUMN {col_name} TYPE {sql_type};")
                        else:
                            statements.append(f"ALTER TABLE {table_name}\n    MODIFY COLUMN {col_name} {sql_type};")
    
    return '\n\n'.join(statements) if statements else '-- No schema changes detected'

def map_type_to_sql(mermaid_type, dialect=''):
    """Map Mermaid data types to SQL types."""
    type_map = {
        'int': 'INTEGER',
        'varchar': 'VARCHAR(255)',
        'nvarchar': 'VARCHAR(255)',
        'datetime': 'TIMESTAMP',
        'timestamp': 'TIMESTAMP',
        'date': 'DATE',
        'time': 'TIME',
        'boolean': 'BOOLEAN' if dialect.lower() == 'postgres' else 'BIT',
        'bit': 'BIT' if dialect.lower() in ['tsql', 'sqlserver'] else 'BOOLEAN',
        'text': 'TEXT',
        'decimal': 'DECIMAL',
        'float': 'FLOAT',
        'uuid': 'UUID' if dialect.lower() == 'postgres' else 'VARCHAR(36)'
    }
    return type_map.get(mermaid_type.lower(), mermaid_type.upper())

def generate_create_table_from_dict(table_name, table_info, dialect=''):
    """Generate CREATE TABLE statement from table dictionary."""
    sql = f"CREATE TABLE {table_name} (\n"
    
    column_defs = []
    pk_columns = []
    
    for col_name in table_info['order']:
        col = table_info['columns'][col_name]
        col_def = f"    {col_name} {map_type_to_sql(col['type'], dialect)}"
        
        attrs = col['attributes'].upper() if col['attributes'] else ''
        if 'NOT NULL' in attrs:
            col_def += ' NOT NULL'
        
        column_defs.append(col_def)
        
        if col['constraint'] == 'PK':
            pk_columns.append(col_name)
    
    sql += ',\n'.join(column_defs)
    
    if pk_columns:
        sql += f',\n    PRIMARY KEY ({", ".join(pk_columns)})'
    
    sql += '\n);'
    return sql

def main():
    if len(sys.argv) < 3:
        print("ERROR: Both before and after Mermaid files required", file=sys.stderr)
        sys.exit(1)
    
    before_file = sys.argv[1]
    after_file = sys.argv[2]
    dialect = sys.argv[3] if len(sys.argv) > 3 else ''
    
    try:
        with open(before_file, 'r', encoding='utf-8') as f:
            before_content = f.read()
        
        with open(after_file, 'r', encoding='utf-8') as f:
            after_content = f.read()
        
        before_tables = parse_mermaid_schema(before_content)
        after_tables = parse_mermaid_schema(after_content)
        
        alter_statements = generate_alter_statements(before_tables, after_tables, dialect)
        print(alter_statements)
        
    except Exception as e:
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()

