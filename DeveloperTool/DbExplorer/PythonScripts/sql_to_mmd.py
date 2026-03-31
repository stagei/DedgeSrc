#!/usr/bin/env python3
"""
SQL to Mermaid ERD converter using SQLGlot.
This script parses SQL DDL and outputs Mermaid ERD diagram syntax.
"""

import sys
import json
from typing import List, Dict, Any

try:
    import sqlglot
    from sqlglot import parse, exp
except ImportError:
    print(json.dumps({"error": "SQLGlot not installed. Please install with: pip install sqlglot"}), file=sys.stderr)
    sys.exit(1)


def clean_tsql_brackets(sql: str) -> str:
    """Remove T-SQL/MS SQL Server bracket notation [identifier]."""
    import re
    # Replace [identifier] with identifier
    sql = re.sub(r'\[([^\]]+)\]', r'\1', sql)
    
    # Fix MS Access DEFAULT =Function() to DEFAULT Function()
    sql = re.sub(r'DEFAULT\s*=\s*', 'DEFAULT ', sql)
    
    return sql


def parse_sql_to_tables(sql: str):
    """Parse SQL DDL and extract table definitions and indexes."""
    tables = []
    alter_foreign_keys = []  # Store FK from ALTER TABLE statements
    indexes = []  # Store CREATE INDEX statements
    
    try:
        # Clean T-SQL brackets first
        sql = clean_tsql_brackets(sql)
        
        # Parse SQL statements
        statements = parse(sql)
        
        for statement in statements:
            if isinstance(statement, exp.Create) and statement.kind == "TABLE":
                table_info = extract_table_info(statement)
                if table_info:
                    tables.append(table_info)
            
            elif isinstance(statement, exp.Create) and statement.kind == "INDEX":
                # Extract index information
                index_info = extract_index_info(statement)
                if index_info:
                    indexes.append(index_info)
            
            elif isinstance(statement, exp.Alter):
                # Extract foreign keys from ALTER TABLE statements
                fk_info = extract_alter_table_foreign_key(statement)
                if fk_info:
                    alter_foreign_keys.append(fk_info)
    
    except Exception as e:
        raise Exception(f"SQL parsing failed: {str(e)}")
    
    # Merge ALTER TABLE foreign keys into corresponding tables
    for fk in alter_foreign_keys:
        for table in tables:
            if table["name"] == fk["from_table"]:
                table["foreign_keys"].append(fk)
                
                # Mark columns as FK
                for col_name in fk.get("from_columns", []):
                    for column in table["columns"]:
                        if column["name"] == col_name:
                            column["is_foreign_key"] = True
                break
    
    return tables, indexes


def extract_table_info(create_statement: exp.Create) -> Dict[str, Any]:
    """Extract table information from CREATE TABLE statement."""
    # SQLGlot CREATE TABLE has a Schema object in 'this'
    # The Schema has a Table object in its 'this' attribute
    schema_obj = create_statement.this
    table_name = None
    
    # For Schema objects, the table identifier is in schema_obj.this
    if hasattr(schema_obj, 'this') and schema_obj.this:
        # This should be a Table object
        table_identifier = schema_obj.this
        if hasattr(table_identifier, 'name'):
            table_name = str(table_identifier.name)
        else:
            # Sometimes it's directly the string
            table_name = str(table_identifier)
    
    # Fallback: try to extract name directly
    if not table_name or table_name.startswith('<'):
        if hasattr(schema_obj, 'name'):
            table_name = str(schema_obj.name)
    
    # Last resort: convert to string and take first word
    if not table_name or table_name.startswith('<'):
        schema_str = str(schema_obj)
        # Take first word before any parentheses or spaces
        if schema_str and not schema_str.startswith('<'):
            table_name = schema_str.split('(')[0].split()[0].strip()
    
    # Final fallback
    if not table_name or table_name.startswith('<'):
        table_name = "UnknownTable"
    
    columns = []
    primary_keys = []
    foreign_keys = []
    unique_constraints = []
    
    # Extract column definitions
    if create_statement.this.expressions:
        for expr in create_statement.this.expressions:
            if isinstance(expr, exp.ColumnDef):
                column_info = extract_column_info(expr)
                columns.append(column_info)
                
                # Track primary keys
                if column_info.get("is_primary_key"):
                    primary_keys.append(column_info["name"])
                
                # Track unique constraints
                if column_info.get("is_unique"):
                    unique_constraints.append(column_info["name"])
            
            elif isinstance(expr, exp.PrimaryKey):
                # Table-level primary key - properly extract column names
                pk_cols = [str(col.name) if hasattr(col, 'name') else str(col) for col in expr.expressions]
                primary_keys.extend(pk_cols)
            
            elif isinstance(expr, exp.ForeignKey):
                # Foreign key constraint
                fk_info = extract_foreign_key(expr, table_name)
                if fk_info:
                    foreign_keys.append(fk_info)
            
            elif isinstance(expr, exp.Unique):
                # Unique constraint - properly extract column names
                unique_cols = [str(col.name) if hasattr(col, 'name') else str(col) for col in expr.expressions]
                unique_constraints.extend(unique_cols)
    
    # Mark columns as FK if they're in foreign keys
    fk_column_names = set()
    for fk in foreign_keys:
        for col_name in fk.get("from_columns", []):
            fk_column_names.add(col_name)
    
    for column in columns:
        if column["name"] in fk_column_names:
            column["is_foreign_key"] = True
    
    return {
        "name": table_name,
        "columns": columns,
        "primary_keys": primary_keys,
        "foreign_keys": foreign_keys,
        "unique_constraints": unique_constraints
    }


def extract_column_info(column_def: exp.ColumnDef) -> Dict[str, Any]:
    """Extract column information from column definition."""
    # Properly extract column name as string
    col_obj = column_def.this
    if hasattr(col_obj, 'name'):
        column_name = str(col_obj.name) if col_obj.name else "unknown"
    else:
        column_name = str(col_obj) if col_obj else "unknown"
    
    data_type = str(column_def.kind) if column_def.kind else "VARCHAR"
    
    # Parse constraints
    is_primary_key = False
    is_foreign_key = False
    is_unique = False
    is_not_null = False
    default_value = None
    
    if column_def.constraints:
        for constraint in column_def.constraints:
            # Constraints are wrapped in ColumnConstraint - access the 'kind'
            constraint_kind = constraint.kind if hasattr(constraint, 'kind') else constraint
            
            if isinstance(constraint_kind, exp.PrimaryKeyColumnConstraint):
                is_primary_key = True
                is_not_null = True  # PK implies NOT NULL
            elif isinstance(constraint_kind, exp.UniqueColumnConstraint):
                is_unique = True
            elif isinstance(constraint_kind, exp.NotNullColumnConstraint):
                is_not_null = True
            elif isinstance(constraint_kind, exp.DefaultColumnConstraint):
                # Extract the default value
                default_val = constraint_kind.this
                if default_val:
                    default_value = str(default_val.sql()) if hasattr(default_val, 'sql') else str(default_val)
    
    return {
        "name": column_name,
        "data_type": data_type,
        "is_primary_key": is_primary_key,
        "is_foreign_key": is_foreign_key,
        "is_unique": is_unique,
        "is_not_null": is_not_null,
        "default_value": default_value
    }


def extract_foreign_key(fk_expr: exp.ForeignKey, table_name: str) -> Dict[str, Any]:
    """Extract foreign key information."""
    # Properly extract column names as strings
    columns = []
    if fk_expr.expressions:
        for col in fk_expr.expressions:
            if hasattr(col, 'this'):
                columns.append(str(col.this))
            elif hasattr(col, 'name'):
                columns.append(str(col.name))
            else:
                columns.append(str(col))
    
    # Try different ways to get the reference
    reference = None
    if hasattr(fk_expr, 'reference'):
        reference = fk_expr.reference
    elif 'reference' in fk_expr.args:
        reference = fk_expr.args.get('reference')
    
    if reference:
        # Reference is a Reference object with:
        # - this: Schema object
        #   - this: Table object
        #     - this: Identifier object
        #       - this: string (table name)
        #   - expressions: list of column Identifiers
        ref_table = None
        ref_columns = []
        
        # Navigate: Reference -> Schema -> Table -> Identifier -> string
        if hasattr(reference, 'this'):  # reference.this is Schema
            schema = reference.this
            
            # Get table name from Schema.this (Table object)
            if hasattr(schema, 'this'):  # schema.this is Table
                table_obj = schema.this
                if hasattr(table_obj, 'this'):  # table.this is Identifier
                    identifier = table_obj.this
                    ref_table = str(identifier)  # identifier is either string or has __str__
            
            # Get column names from Schema.expressions
            if hasattr(schema, 'expressions') and schema.expressions:
                for col in schema.expressions:
                    if hasattr(col, 'this'):
                        ref_columns.append(str(col.this))
                    elif hasattr(col, 'name'):
                        ref_columns.append(str(col.name))
                    else:
                        ref_columns.append(str(col))
        
        if ref_table:
            return {
                "from_table": table_name,
                "from_columns": columns,
                "to_table": ref_table,
                "to_columns": ref_columns
            }
    
    return None


def extract_alter_table_foreign_key(alter_statement: exp.Alter) -> Dict[str, Any]:
    """Extract foreign key information from ALTER TABLE ADD CONSTRAINT statement."""
    # Get the table name from ALTER TABLE
    table_obj = alter_statement.this
    table_name = None
    
    if hasattr(table_obj, 'this'):
        if hasattr(table_obj.this, 'name'):
            table_name = str(table_obj.this.name)
        else:
            table_name = str(table_obj.this)
    elif hasattr(table_obj, 'name'):
        table_name = str(table_obj.name)
    else:
        table_name = str(table_obj)
    
    # Look for ADD CONSTRAINT with FOREIGN KEY
    if hasattr(alter_statement, 'actions') and alter_statement.actions:
        for action in alter_statement.actions:
            # AddConstraint has expressions, not this
            if isinstance(action, exp.AddConstraint):
                # Navigate: action.expressions[0] -> Constraint -> expressions[0] -> ForeignKey
                if hasattr(action, 'expressions') and action.expressions:
                    constraint = action.expressions[0]  # First is the Constraint object
                    
                    # The Constraint has expressions containing the ForeignKey
                    if hasattr(constraint, 'expressions') and constraint.expressions:
                        for expr in constraint.expressions:
                            if isinstance(expr, exp.ForeignKey):
                                fk_info = extract_foreign_key(expr, table_name)
                                if fk_info:
                                    return fk_info
    
    return None


def extract_index_info(create_statement: exp.Create) -> Dict[str, Any]:
    """Extract index information from CREATE INDEX statement."""
    index_name = None
    table_name = None
    columns = []
    
    # create_statement.this is an Index object
    if hasattr(create_statement, 'this') and create_statement.this:
        index_obj = create_statement.this
        
        # Index name: index_obj.this is an Identifier with the index name
        if hasattr(index_obj, 'this'):
            name_obj = index_obj.this
            if hasattr(name_obj, 'this'):
                index_name = str(name_obj.this)
            else:
                index_name = str(name_obj)
        
        # Table name: in args dict
        if hasattr(index_obj, 'args') and 'table' in index_obj.args:
            table_obj = index_obj.args['table']
            if table_obj and hasattr(table_obj, 'this'):
                table_ident = table_obj.this
                if hasattr(table_ident, 'this'):
                    table_name = str(table_ident.this)
                else:
                    table_name = str(table_ident)
        
        # Columns: in args dict under params
        if hasattr(index_obj, 'args') and 'params' in index_obj.args:
            params_obj = index_obj.args['params']
            if params_obj and hasattr(params_obj, 'args') and 'columns' in params_obj.args:
                cols_list = params_obj.args['columns']
                if cols_list:
                    for col_expr in cols_list:
                        # col_expr might be an Ordered containing a Column
                        col_obj = col_expr
                        if hasattr(col_expr, 'this'):
                            col_obj = col_expr.this
                        
                        # Now col_obj should be a Column
                        if hasattr(col_obj, 'this'):
                            col_ident = col_obj.this
                            if hasattr(col_ident, 'this'):
                                columns.append(str(col_ident.this))
                            else:
                                columns.append(str(col_ident))
    
    # Determine index type (unique, etc.)
    is_unique = False
    if hasattr(create_statement, 'args') and create_statement.args.get('unique'):
        is_unique = True
    
    # Only return if we have at least a name and table
    if index_name and table_name:
        return {
            "name": index_name,
            "table": table_name,
            "columns": columns if columns else ["unknown"],
            "is_unique": is_unique
        }
    
    return None


def generate_mermaid_erd(tables: List[Dict[str, Any]], indexes: List[Dict[str, Any]]) -> str:
    """Generate Mermaid ERD diagram from table definitions."""
    lines = ["erDiagram"]
    
    # Generate entity definitions FIRST (relationships come after)
    for table in tables:
        lines.append(f"    {table['name']} {{")
        
        primary_keys = set(table.get("primary_keys", []))
        unique_constraints = set(table.get("unique_constraints", []))
        
        # Generate column definitions
        for column in table.get("columns", []):
            col_name = column["name"]
            data_type = simplify_data_type(column["data_type"])
            
            # Determine constraint markers
            markers = []
            if col_name in primary_keys or column.get("is_primary_key"):
                markers.append("PK")
            elif column.get("is_foreign_key"):
                markers.append("FK")
            if col_name in unique_constraints or column.get("is_unique"):
                if "PK" not in markers:  # Don't mark UK if already PK
                    markers.append("UK")
            
            # Build constraint description
            constraints = []
            if column.get("is_not_null") and "PK" not in markers:
                constraints.append("NOT NULL")
            if column.get("default_value"):
                constraints.append(f"DEFAULT {column['default_value']}")
            
            # Format the line
            marker_str = " " + " ".join(markers) if markers else ""
            constraint_str = f' "{", ".join(constraints)}"' if constraints else ""
            
            lines.append(f"        {data_type} {col_name}{marker_str}{constraint_str}")
        
        lines.append("    }")
        lines.append("")
    
    # Build index lookup for relationship annotations
    index_lookup = {}
    for idx in indexes:
        table_name = idx["table"]
        for col in idx["columns"]:
            key = f"{table_name}.{col}"
            if key not in index_lookup:
                index_lookup[key] = []
            index_lookup[key].append(idx)
    
    # Generate relationships AFTER table definitions
    relationships_added = set()
    for table in tables:
        for fk in table.get("foreign_keys", []):
            from_table = fk["from_table"]
            to_table = fk["to_table"]
            
            # Avoid duplicate relationships
            rel_key = f"{from_table}-{to_table}"
            if rel_key not in relationships_added:
                # Default to one-to-many relationship (||--o{)
                rel_name = fk["from_columns"][0] if fk["from_columns"] else "references"
                
                # Check if there's an index on the FK column(s)
                fk_has_index = False
                index_info = []
                for col in fk.get("from_columns", []):
                    key = f"{from_table}.{col}"
                    if key in index_lookup:
                        fk_has_index = True
                        for idx in index_lookup[key]:
                            idx_type = "UNIQUE" if idx["is_unique"] else "INDEX"
                            index_info.append(f"{idx_type}:{idx['name']}")
                
                # Add index annotation to relationship if index exists
                if index_info:
                    rel_name_with_index = f"{rel_name} (indexed: {', '.join(index_info[:2])})"  # Limit to 2 indexes
                    lines.append(f"    {to_table} ||--o{{ {from_table} : \"{rel_name_with_index}\"")
                else:
                    lines.append(f"    {to_table} ||--o{{ {from_table} : {rel_name}")
                
                relationships_added.add(rel_key)
    
    # Add empty line after relationships
    if relationships_added:
        lines.append("")
    
    # Add index information as comments at the bottom
    if indexes:
        lines.append("")
        lines.append("%% ===========================================================")
        lines.append("%% DATABASE INDEXES")
        lines.append("%% ===========================================================")
        lines.append("%%")
        lines.append(f"%% Total Indexes: {len(indexes)}")
        lines.append("%%")
        
        # Group indexes by table
        indexes_by_table = {}
        for idx in indexes:
            table_name = idx["table"]
            if table_name not in indexes_by_table:
                indexes_by_table[table_name] = []
            indexes_by_table[table_name].append(idx)
        
        # Generate human-readable index descriptions
        for table_name in sorted(indexes_by_table.keys()):
            table_indexes = indexes_by_table[table_name]
            lines.append(f"%%")
            lines.append(f"%% {table_name} ({len(table_indexes)} index{'es' if len(table_indexes) != 1 else ''}):")
            
            for idx in table_indexes:
                index_type = "UNIQUE index" if idx["is_unique"] else "Index"
                columns_str = ", ".join(idx["columns"]) if idx["columns"] else "unknown columns"
                lines.append(f"%%   - {idx['name']}: {index_type} on ({columns_str})")
                
                # Add explanation for common index patterns
                idx_name_lower = idx['name'].lower()
                if 'fk_' in idx_name_lower:
                    lines.append(f"%%       - Speeds up foreign key lookups and joins")
                elif 'pk_' in idx_name_lower or 'primary' in idx_name_lower:
                    lines.append(f"%%       - Primary key constraint enforcement")
                elif 'idx_' in idx_name_lower or 'ix_' in idx_name_lower:
                    if len(idx["columns"]) == 1:
                        lines.append(f"%%       - Optimizes queries filtering or sorting by {idx['columns'][0]}")
                    else:
                        lines.append(f"%%       - Composite index for multi-column queries")
                elif 'uk_' in idx_name_lower or 'unique' in idx_name_lower:
                    lines.append(f"%%       - Enforces uniqueness constraint")
        
        lines.append("%%")
        lines.append("%% Note: Indexes improve query performance but are not shown in the")
        lines.append("%% visual diagram above. They are maintained automatically by the database.")
    
    return "\n".join(lines)


def simplify_data_type(data_type: str) -> str:
    """Simplify data type names for Mermaid."""
    data_type = data_type.upper()
    
    # Map SQL types to simpler Mermaid-friendly names
    type_mapping = {
        "INTEGER": "int",
        "BIGINT": "bigint",
        "SMALLINT": "smallint",
        "DECIMAL": "decimal",
        "NUMERIC": "decimal",
        "FLOAT": "float",
        "REAL": "float",
        "DOUBLE": "double",
        "VARCHAR": "varchar",
        "NVARCHAR": "varchar",
        "CHAR": "char",
        "NCHAR": "char",
        "TEXT": "text",
        "DATE": "date",
        "TIME": "time",
        "DATETIME": "datetime",
        "TIMESTAMP": "timestamp",
        "BOOLEAN": "boolean",
        "BOOL": "boolean",
        "BINARY": "binary",
        "VARBINARY": "varbinary",
        "UUID": "uuid"
    }
    
    # Check for exact match
    if data_type in type_mapping:
        return type_mapping[data_type]
    
    # Check for types with length (e.g., VARCHAR(255))
    for sql_type, mermaid_type in type_mapping.items():
        if data_type.startswith(sql_type):
            return mermaid_type
    
    # Default to lowercase version
    return data_type.split("(")[0].lower()


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: sql_to_mmd.py <sql_file> [ast_output_file]"}), file=sys.stderr)
        sys.exit(1)
    
    sql_file = sys.argv[1]
    ast_output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        # Read SQL file
        with open(sql_file, 'r', encoding='utf-8') as f:
            sql_content = f.read()
        
        # Export AST if requested
        if ast_output_file:
            try:
                # Clean and parse SQL to get AST
                cleaned_sql = clean_tsql_brackets(sql_content)
                statements = parse(cleaned_sql)
                
                # Build AST representation
                ast_lines = ["SQLGlot Abstract Syntax Tree (AST)", "=" * 60, ""]
                for i, stmt in enumerate(statements, 1):
                    ast_lines.append(f"Statement {i}:")
                    ast_lines.append("-" * 60)
                    # Get string representation of AST
                    ast_lines.append(str(stmt))
                    ast_lines.append("")
                    # Also add pretty-printed version
                    ast_lines.append(f"Statement {i} (Pretty):")
                    ast_lines.append("-" * 60)
                    try:
                        ast_lines.append(stmt.sql(pretty=True))
                    except:
                        ast_lines.append("(pretty print not available)")
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
        
        # Parse SQL
        tables, indexes = parse_sql_to_tables(sql_content)
        
        # Generate Mermaid ERD
        mermaid_output = generate_mermaid_erd(tables, indexes)
        
        # Output result
        print(mermaid_output)
        
    except FileNotFoundError:
        print(json.dumps({"error": f"File not found: {sql_file}"}), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

