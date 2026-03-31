#!/usr/bin/env python3
"""
Mermaid ERD diff to SQL ALTER statements generator.
Compares two Mermaid ERD diagrams and generates SQL ALTER statements for the differences.
"""

import sys
import json
import re
from typing import List, Dict, Any, Tuple, Set

try:
    import sqlglot
    from sqlglot import exp
except ImportError:
    print(json.dumps({"error": "SQLGlot not installed. Please install with: pip install sqlglot"}), file=sys.stderr)
    sys.exit(1)


def parse_mermaid_erd(mermaid_content: str) -> Dict[str, Any]:
    """
    Parse Mermaid ERD content and extract entity definitions.
    Returns entities dictionary.
    """
    entities = {}
    
    lines = mermaid_content.split('\n')
    current_entity = None
    in_entity_block = False
    
    for line in lines:
        line = line.strip()
        
        # Skip empty lines and comments
        if not line or line.startswith('%%'):
            continue
        
        # Skip erDiagram declaration
        if line.lower().strip() == 'erdiagram':
            continue
        
        # Check for entity definition start: EntityName {
        entity_match = re.match(r'^(\w+)\s*\{', line)
        if entity_match:
            current_entity = entity_match.group(1)
            entities[current_entity] = {
                'name': current_entity,
                'columns': {}
            }
            in_entity_block = True
            continue
        
        # Check for entity block end
        if line == '}':
            in_entity_block = False
            current_entity = None
            continue
        
        # Parse column definition inside entity block
        if in_entity_block and current_entity:
            column_info = parse_column_definition(line)
            if column_info:
                entities[current_entity]['columns'][column_info['name']] = column_info
    
    return entities


def parse_column_definition(line: str) -> Dict[str, Any]:
    """
    Parse a Mermaid column definition line.
    Format: datatype column_name PK/FK/UK "constraints"
    """
    # Remove quotes and split
    parts = line.split('"')
    main_part = parts[0].strip()
    constraints_str = parts[1].strip() if len(parts) > 1 else ""
    
    # Parse main part: datatype column_name [PK] [FK] [UK]
    tokens = main_part.split()
    if len(tokens) < 2:
        return None
    
    data_type = tokens[0]
    column_name = tokens[1]
    
    # Parse markers
    markers = tokens[2:] if len(tokens) > 2 else []
    is_primary_key = 'PK' in markers
    is_foreign_key = 'FK' in markers
    is_unique = 'UK' in markers
    
    # Parse constraints
    is_not_null = False
    default_value = None
    
    if constraints_str:
        is_not_null = 'NOT NULL' in constraints_str
        default_match = re.search(r'DEFAULT\s+(\S+)', constraints_str)
        if default_match:
            default_value = default_match.group(1)
    
    # Primary keys are implicitly NOT NULL
    if is_primary_key:
        is_not_null = True
    
    return {
        'name': column_name,
        'data_type': data_type,
        'is_primary_key': is_primary_key,
        'is_foreign_key': is_foreign_key,
        'is_unique': is_unique,
        'is_not_null': is_not_null,
        'default_value': default_value
    }


def compare_entities(before: Dict[str, Any], after: Dict[str, Any]) -> Dict[str, Any]:
    """
    Compare two entity dictionaries and generate differences.
    Returns a dictionary with changes needed.
    """
    changes = {
        'tables_to_add': [],
        'tables_to_drop': [],
        'columns_to_add': {},
        'columns_to_drop': {},
        'columns_to_modify': {}
    }
    
    before_tables = set(before.keys())
    after_tables = set(after.keys())
    
    # New tables (sorted for consistent ordering)
    changes['tables_to_add'] = sorted(list(after_tables - before_tables))
    
    # Dropped tables (sorted for consistent ordering)
    changes['tables_to_drop'] = sorted(list(before_tables - after_tables))
    
    # Modified tables
    common_tables = before_tables & after_tables
    for table_name in common_tables:
        before_cols = before[table_name]['columns']
        after_cols = after[table_name]['columns']
        
        before_col_names = set(before_cols.keys())
        after_col_names = set(after_cols.keys())
        
        # New columns (sorted for consistent ordering)
        new_cols = after_col_names - before_col_names
        if new_cols:
            changes['columns_to_add'][table_name] = [after_cols[col] for col in sorted(new_cols)]
        
        # Dropped columns
        dropped_cols = before_col_names - after_col_names
        if dropped_cols:
            changes['columns_to_drop'][table_name] = sorted(list(dropped_cols))
        
        # Modified columns (same name but different properties)
        common_cols = before_col_names & after_col_names
        modified = []
        for col_name in sorted(common_cols):
            if before_cols[col_name] != after_cols[col_name]:
                modified.append({
                    'before': before_cols[col_name],
                    'after': after_cols[col_name]
                })
        if modified:
            changes['columns_to_modify'][table_name] = modified
    
    return changes


def generate_alter_statements(changes: Dict[str, Any], after: Dict[str, Any], dialect: str) -> str:
    """
    Generate SQL ALTER statements from the changes dictionary.
    """
    statements = []
    
    # DROP TABLE statements (do these last in practice, but list them)
    for table_name in changes['tables_to_drop']:
        statements.append(f"-- Dropping table: {table_name}")
        statements.append(f"DROP TABLE {table_name};")
        statements.append("")
    
    # CREATE TABLE statements for new tables
    for table_name in changes['tables_to_add']:
        entity = after[table_name]
        statements.append(f"-- Creating new table: {table_name}")
        
        column_defs = []
        # Sort columns by name for consistent ordering
        for col_name in sorted(entity['columns'].keys()):
            col = entity['columns'][col_name]
            col_def = f"{col['name']} {map_data_type(col['data_type'], dialect)}"
            
            if col['is_primary_key']:
                col_def += " PRIMARY KEY"
            elif col['is_not_null']:
                col_def += " NOT NULL"
            
            if col['is_unique'] and not col['is_primary_key']:
                col_def += " UNIQUE"
            
            if col['default_value']:
                col_def += f" DEFAULT {col['default_value']}"
            
            column_defs.append(col_def)
        
        definitions_str = ',\n    '.join(column_defs)
        create_table = f"CREATE TABLE {table_name} (\n    {definitions_str}\n);"
        statements.append(create_table)
        statements.append("")
    
    # ALTER TABLE ADD COLUMN statements (sorted by table name for consistent ordering)
    for table_name in sorted(changes['columns_to_add'].keys()):
        columns = changes['columns_to_add'][table_name]
        for col in columns:
            statements.append(f"-- Adding column to {table_name}: {col['name']}")
            col_def = f"{col['name']} {map_data_type(col['data_type'], dialect)}"
            
            if col['is_not_null']:
                col_def += " NOT NULL"
            
            if col['is_unique']:
                col_def += " UNIQUE"
            
            if col['default_value']:
                col_def += f" DEFAULT {col['default_value']}"
            
            statements.append(f"ALTER TABLE {table_name} ADD COLUMN {col_def};")
            statements.append("")
    
    # ALTER TABLE DROP COLUMN statements (sorted by table name for consistent ordering)
    for table_name in sorted(changes['columns_to_drop'].keys()):
        columns = changes['columns_to_drop'][table_name]
        for col_name in columns:
            statements.append(f"-- Dropping column from {table_name}: {col_name}")
            statements.append(f"ALTER TABLE {table_name} DROP COLUMN {col_name};")
            statements.append("")
    
    # ALTER TABLE MODIFY COLUMN statements (sorted by table name for consistent ordering)
    for table_name in sorted(changes['columns_to_modify'].keys()):
        modifications = changes['columns_to_modify'][table_name]
        for mod in modifications:
            before_col = mod['before']
            after_col = mod['after']
            col_name = after_col['name']
            
            statements.append(f"-- Modifying column {table_name}.{col_name}")
            
            # Generate MODIFY/ALTER COLUMN based on dialect
            col_def = f"{col_name} {map_data_type(after_col['data_type'], dialect)}"
            
            if after_col['is_not_null']:
                col_def += " NOT NULL"
            else:
                col_def += " NULL"
            
            if after_col['default_value']:
                col_def += f" DEFAULT {after_col['default_value']}"
            
            # Dialect-specific ALTER syntax
            if dialect in ['mysql']:
                statements.append(f"ALTER TABLE {table_name} MODIFY COLUMN {col_def};")
            elif dialect in ['postgres']:
                # PostgreSQL requires separate commands for type, null, default
                statements.append(f"ALTER TABLE {table_name} ALTER COLUMN {col_name} TYPE {map_data_type(after_col['data_type'], dialect)};")
                if after_col['is_not_null'] != before_col['is_not_null']:
                    if after_col['is_not_null']:
                        statements.append(f"ALTER TABLE {table_name} ALTER COLUMN {col_name} SET NOT NULL;")
                    else:
                        statements.append(f"ALTER TABLE {table_name} ALTER COLUMN {col_name} DROP NOT NULL;")
            elif dialect in ['tsql']:
                statements.append(f"ALTER TABLE {table_name} ALTER COLUMN {col_def};")
            else:
                # ANSI SQL and others
                statements.append(f"ALTER TABLE {table_name} ALTER COLUMN {col_def};")
            
            statements.append("")
    
    return '\n'.join(statements) if statements else "-- No changes detected"


def map_data_type(mermaid_type: str, dialect: str) -> str:
    """Map Mermaid data types to SQL dialect-specific types."""
    mermaid_type_lower = mermaid_type.lower()
    
    if mermaid_type_lower in ['int', 'integer']:
        return 'INTEGER' if dialect == 'sqlite' else 'INT'
    elif mermaid_type_lower == 'bigint':
        return 'BIGINT'
    elif mermaid_type_lower == 'smallint':
        return 'SMALLINT'
    elif mermaid_type_lower in ['varchar', 'string']:
        return 'VARCHAR(255)'
    elif mermaid_type_lower == 'text':
        return 'TEXT'
    elif mermaid_type_lower == 'char':
        return 'CHAR(1)'
    elif mermaid_type_lower in ['decimal', 'numeric']:
        return 'DECIMAL(10,2)'
    elif mermaid_type_lower == 'float':
        return 'FLOAT'
    elif mermaid_type_lower == 'double':
        return 'DOUBLE' if dialect in ['mysql', 'postgres'] else 'FLOAT'
    elif mermaid_type_lower == 'boolean':
        return 'BOOLEAN' if dialect in ['postgres', 'sqlite'] else 'BIT'
    elif mermaid_type_lower == 'date':
        return 'DATE'
    elif mermaid_type_lower == 'time':
        return 'TIME'
    elif mermaid_type_lower == 'datetime':
        return 'DATETIME' if dialect in ['mysql', 'tsql'] else 'TIMESTAMP'
    elif mermaid_type_lower == 'timestamp':
        return 'TIMESTAMP'
    elif mermaid_type_lower == 'uuid':
        return 'UUID' if dialect == 'postgres' else 'UNIQUEIDENTIFIER' if dialect == 'tsql' else 'VARCHAR(36)'
    else:
        return mermaid_type.upper()


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: mmd_diff_to_sql.py <before_mermaid_file> <after_mermaid_file> [dialect]"}), file=sys.stderr)
        sys.exit(1)
    
    before_file = sys.argv[1]
    after_file = sys.argv[2]
    dialect = sys.argv[3] if len(sys.argv) > 3 else 'ansi'
    
    try:
        # Read Mermaid files
        with open(before_file, 'r', encoding='utf-8') as f:
            before_content = f.read()
        
        with open(after_file, 'r', encoding='utf-8') as f:
            after_content = f.read()
        
        # Parse both diagrams
        before_entities = parse_mermaid_erd(before_content)
        after_entities = parse_mermaid_erd(after_content)
        
        # Compare and find differences
        changes = compare_entities(before_entities, after_entities)
        
        # Generate ALTER statements
        alter_statements = generate_alter_statements(changes, after_entities, dialect)
        
        # Output result
        print(alter_statements)
        
    except FileNotFoundError as e:
        print(json.dumps({"error": f"File not found: {e.filename}"}), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

