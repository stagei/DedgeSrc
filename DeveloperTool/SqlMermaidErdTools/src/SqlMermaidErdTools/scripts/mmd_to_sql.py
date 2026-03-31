#!/usr/bin/env python3
"""
Converts Mermaid ERD diagram to SQL DDL using a custom parser.
This is a temporary implementation until we find or build a proper Mermaid→SQL converter.
"""

import sys
import re

def parse_mermaid_to_sql(mermaid_content, target_dialect=''):
    """
    Parse Mermaid ERD and generate SQL CREATE TABLE statements.
    
    Args:
        mermaid_content: Mermaid ERD diagram as string
        target_dialect: Target SQL dialect (empty for ANSI SQL)
    
    Returns:
        SQL DDL statements as string
    """
    lines = mermaid_content.strip().split('\n')
    sql_statements = []
    current_table = None
    current_columns = []
    relationships = []
    
    # Regex patterns
    table_pattern = re.compile(r'^\s*(\w+)\s*\{')
    column_pattern = re.compile(r'^\s*(\w+)\s+(\w+)\s*(?:(PK|FK|UK))?\s*(?:"([^"]+)")?')
    relationship_pattern = re.compile(r'^\s*(\w+)\s+([\|\}\{o]-+[\|\}\{o])\s+(\w+)\s*:\s*(\w+)')
    
    for line in lines:
        line = line.strip()
        
        # Skip empty lines and erDiagram declaration
        if not line or line == 'erDiagram':
            continue
        
        # Check for table start
        table_match = table_pattern.match(line)
        if table_match:
            # Save previous table if exists
            if current_table and current_columns:
                sql_statements.append(generate_create_table(current_table, current_columns, target_dialect))
            
            current_table = table_match.group(1)
            current_columns = []
            continue
        
        # Check for table end
        if line == '}':
            if current_table and current_columns:
                sql_statements.append(generate_create_table(current_table, current_columns, target_dialect))
                current_table = None
                current_columns = []
            continue
        
        # Check for column definition
        column_match = column_pattern.match(line)
        if column_match and current_table:
            data_type = column_match.group(1)
            column_name = column_match.group(2)
            constraint = column_match.group(3) if column_match.group(3) else None
            attributes = column_match.group(4) if column_match.group(4) else ''
            
            current_columns.append({
                'name': column_name,
                'type': map_mermaid_type_to_sql(data_type, target_dialect),
                'constraint': constraint,
                'attributes': attributes
            })
            continue
        
        # Check for relationship
        relationship_match = relationship_pattern.match(line)
        if relationship_match:
            relationships.append({
                'from_table': relationship_match.group(1),
                'to_table': relationship_match.group(3),
                'fk_column': relationship_match.group(4)
            })
    
    # Save last table if exists
    if current_table and current_columns:
        sql_statements.append(generate_create_table(current_table, current_columns, target_dialect))
    
    # Add ALTER statements for foreign keys
    for rel in relationships:
        sql_statements.append(generate_foreign_key(rel, target_dialect))
    
    return '\n\n'.join(sql_statements)

def map_mermaid_type_to_sql(mermaid_type, dialect=''):
    """Map Mermaid data types to SQL types."""
    type_map = {
        'int': 'INTEGER',
        'bigint': 'BIGINT',
        'smallint': 'SMALLINT',
        'tinyint': 'TINYINT',
        'decimal': 'DECIMAL',
        'numeric': 'NUMERIC',
        'float': 'FLOAT',
        'real': 'REAL',
        'double': 'DOUBLE PRECISION',
        'varchar': 'VARCHAR(255)',
        'nvarchar': 'NVARCHAR(255)' if dialect.lower() in ['tsql', 'sqlserver'] else 'VARCHAR(255)',
        'char': 'CHAR(50)',
        'nchar': 'NCHAR(50)' if dialect.lower() in ['tsql', 'sqlserver'] else 'CHAR(50)',
        'text': 'TEXT',
        'ntext': 'TEXT',
        'date': 'DATE',
        'time': 'TIME',
        'datetime': 'TIMESTAMP',
        'timestamp': 'TIMESTAMP',
        'boolean': 'BOOLEAN' if dialect.lower() == 'postgres' else 'BIT',
        'bit': 'BIT' if dialect.lower() in ['tsql', 'sqlserver'] else 'BOOLEAN',
        'uuid': 'UUID' if dialect.lower() == 'postgres' else 'VARCHAR(36)',
        'uniqueidentifier': 'VARCHAR(36)',
        'binary': 'BINARY',
        'varbinary': 'VARBINARY'
    }
    return type_map.get(mermaid_type.lower(), mermaid_type.upper())

def generate_create_table(table_name, columns, dialect=''):
    """Generate CREATE TABLE statement from parsed data."""
    sql = f"CREATE TABLE {table_name} (\n"
    
    column_defs = []
    pk_columns = []
    uk_columns = []
    
    for col in columns:
        col_def = f"    {col['name']} {col['type']}"
        
        # Parse attributes
        attrs = col['attributes'].upper()
        if 'NOT NULL' in attrs:
            col_def += ' NOT NULL'
        
        # Extract DEFAULT value
        default_match = re.search(r'DEFAULT\s+([A-Z0-9]+)', attrs)
        if default_match:
            default_val = default_match.group(1)
            if default_val in ['FALSE', 'TRUE']:
                col_def += f' DEFAULT {default_val}'
            elif default_val == 'NOW()':
                if dialect.lower() == 'postgres':
                    col_def += ' DEFAULT CURRENT_TIMESTAMP'
                else:
                    col_def += ' DEFAULT CURRENT_TIMESTAMP'
            else:
                col_def += f' DEFAULT {default_val}'
        
        column_defs.append(col_def)
        
        # Track constraints
        if col['constraint'] == 'PK':
            pk_columns.append(col['name'])
        elif col['constraint'] == 'UK':
            uk_columns.append(col['name'])
    
    # Add column definitions
    sql += ',\n'.join(column_defs)
    
    # Add primary key constraint
    if pk_columns:
        sql += f',\n    PRIMARY KEY ({", ".join(pk_columns)})'
    
    # Add unique constraints
    for uk_col in uk_columns:
        sql += f',\n    UNIQUE ({uk_col})'
    
    sql += '\n);'
    return sql

def generate_foreign_key(relationship, dialect=''):
    """Generate ALTER TABLE statement for foreign key."""
    fk_name = f"FK_{relationship['from_table']}_{relationship['to_table']}"
    
    # For simplicity, assume FK column follows naming convention
    # In real implementation, this should be derived from the relationship
    fk_column = relationship['fk_column']
    
    # Try to infer the PK column name (usually 'id' or table name + 'ID')
    to_table = relationship['to_table']
    # Common patterns: id, ID, TableNameID, table_name_id
    pk_column = 'id'  # Default assumption
    
    sql = f"ALTER TABLE {relationship['from_table']}\n"
    sql += f"    ADD CONSTRAINT {fk_name}\n"
    sql += f"    FOREIGN KEY ({fk_column})\n"
    sql += f"    REFERENCES {to_table}({pk_column});"
    
    return sql

def main():
    if len(sys.argv) < 2:
        print("ERROR: Mermaid content file required", file=sys.stderr)
        sys.exit(1)
    
    mermaid_file = sys.argv[1]
    dialect = sys.argv[2] if len(sys.argv) > 2 else ''
    ast_output_file = sys.argv[3] if len(sys.argv) > 3 else None
    
    try:
        with open(mermaid_file, 'r', encoding='utf-8') as f:
            mermaid_content = f.read()
        
        sql_output = parse_mermaid_to_sql(mermaid_content, dialect)
        
        # Export AST if requested
        if ast_output_file:
            try:
                # Parse the generated SQL to show its AST
                statements = sqlglot.parse(sql_output, read=dialect if dialect else None)
                
                # Build AST representation
                ast_lines = ["SQLGlot Abstract Syntax Tree (AST)", "=" * 60, ""]
                ast_lines.append(f"Generated SQL Dialect: {dialect or 'default'}")
                ast_lines.append("=" * 60)
                ast_lines.append("")
                
                for i, stmt in enumerate(statements, 1):
                    ast_lines.append(f"Statement {i} - AST Structure:")
                    ast_lines.append("-" * 60)
                    # Get string representation of AST
                    ast_lines.append(str(stmt))
                    ast_lines.append("")
                    # Also add pretty-printed SQL
                    ast_lines.append(f"Statement {i} - SQL:")
                    ast_lines.append("-" * 60)
                    try:
                        ast_lines.append(stmt.sql(dialect=dialect if dialect else None, pretty=True))
                    except:
                        ast_lines.append("(SQL generation not available)")
                    ast_lines.append("")
                    ast_lines.append("=" * 60)
                    ast_lines.append("")
                
                # Write AST to file
                with open(ast_output_file, 'w', encoding='utf-8') as f:
                    f.write('\n'.join(ast_lines))
            except Exception as e:
                # Don't fail if AST export fails
                with open(ast_output_file, 'w', encoding='utf-8') as f:
                    f.write(f"AST Export Error: {str(e)}\n")
        
        print(sql_output)
        
    except Exception as e:
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
