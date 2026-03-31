#!/usr/bin/env python3
"""
SQL dialect translator using SQLGlot.
This script converts SQL from one dialect to another.
"""

import sys
import json

try:
    import sqlglot
    from sqlglot import parse, transpile
except ImportError:
    print(json.dumps({"error": "SQLGlot not installed. Please install with: pip install sqlglot"}), file=sys.stderr)
    sys.exit(1)


def translate_sql(sql_content: str, source_dialect: str, target_dialect: str) -> str:
    """
    Translate SQL from source dialect to target dialect using SQLGlot.
    """
    try:
        # Use SQLGlot's transpile function for dialect translation
        # transpile returns a list of SQL strings
        translated = transpile(
            sql_content,
            read=source_dialect,
            write=target_dialect,
            pretty=True
        )
        
        # Join all translated statements
        return '\n\n'.join(translated)
    except Exception as e:
        raise Exception(f"SQL dialect translation failed: {str(e)}")


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 4:
        print(json.dumps({"error": "Usage: sql_dialect_translate.py <sql_file> <source_dialect> <target_dialect> [ast_output_file]"}), file=sys.stderr)
        sys.exit(1)
    
    sql_file = sys.argv[1]
    source_dialect = sys.argv[2] if sys.argv[2] else None  # Empty string becomes None for SQLGlot
    target_dialect = sys.argv[3] if sys.argv[3] else None  # Empty string becomes None for SQLGlot
    ast_output_file = sys.argv[4] if len(sys.argv) > 4 else None
    
    try:
        # Read SQL file
        with open(sql_file, 'r', encoding='utf-8') as f:
            sql_content = f.read()
        
        # Export AST if requested
        if ast_output_file:
            try:
                # Parse SQL to get AST
                statements = parse(sql_content, read=source_dialect)
                
                # Build AST representation
                ast_lines = ["SQLGlot Abstract Syntax Tree (AST)", "=" * 60, ""]
                ast_lines.append(f"Source Dialect: {source_dialect or 'default'}")
                ast_lines.append(f"Target Dialect: {target_dialect or 'default'}")
                ast_lines.append("=" * 60)
                ast_lines.append("")
                
                for i, stmt in enumerate(statements, 1):
                    ast_lines.append(f"Statement {i} - AST Structure:")
                    ast_lines.append("-" * 60)
                    # Get string representation of AST
                    ast_lines.append(str(stmt))
                    ast_lines.append("")
                    # Also add SQL representation in source dialect
                    ast_lines.append(f"Statement {i} - Source SQL:")
                    ast_lines.append("-" * 60)
                    try:
                        ast_lines.append(stmt.sql(dialect=source_dialect, pretty=True))
                    except:
                        ast_lines.append("(SQL generation not available)")
                    ast_lines.append("")
                    # Add SQL representation in target dialect
                    ast_lines.append(f"Statement {i} - Target SQL:")
                    ast_lines.append("-" * 60)
                    try:
                        ast_lines.append(stmt.sql(dialect=target_dialect, pretty=True))
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
        
        # Translate SQL
        translated_sql = translate_sql(sql_content, source_dialect, target_dialect)
        
        # Output result
        print(translated_sql)
        
    except FileNotFoundError:
        print(json.dumps({"error": f"File not found: {sql_file}"}), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

