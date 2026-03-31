# TableNames — Self-Contained Table Definitions

## Purpose

Legacy DB2 table names in the Dedge system follow abbreviated Norwegian naming conventions
established decades ago (e.g. `A_ORDREHODE`, `Z_AVDTAB`, `TILGJVAREREG`). These names are
cryptic, inconsistent, and carry no semantic meaning for developers unfamiliar with the domain.

This folder stores **self-contained table definition files** — each file includes:

- **AI-generated CamelCase C# class name** and namespace for the table
- **All column-level naming**: CamelCase property names, English descriptions, inferred FK relationships

Having everything in one file per table enables automated generation of strongly-typed
Entity Framework / Dapper mapping classes that bridge the old DB2 schema to a modern .NET domain model.

## How Names Are Generated

Each table is analyzed by Ollama in two steps during Phase 8f:

1. **Table naming** — using table metadata, column structure, program usage, and COBOL source context:
   - DB2 catalog metadata: table type, schemas, Norwegian REMARKS/comments
   - Column structure: all column names, types, and comments from SYSCAT.COLUMNS
   - COBOL usage context: RAG snippets showing how the table is used in JOIN/WHERE patterns
   - Program usage: which COBOL programs reference this table and with what SQL operations

2. **Column naming** — using the same context plus cross-table column relationships:
   - Cross-table column index: which other tables share the same column name (FK signal)
   - DB2 SYSCAT.REFERENCES: explicit foreign key constraints
   - Column name patterns: Norwegian abbreviation conventions (NR=number, DATO=date, etc.)

## File Format

One JSON file per table: `{TABLENAME}.json`

```json
{
  "tableName": "A_ORDREHODE",
  "futureName": "OrderHeader",
  "namespace": "Orders",
  "columns": [
    {
      "name": "ORDRNR",
      "futureName": "OrderNumber",
      "description": "Unique order identifier",
      "foreignKey": null
    },
    {
      "name": "KUNDNR",
      "futureName": "CustomerNumber",
      "description": "Reference to customer who placed the order",
      "foreignKey": {
        "targetTable": "KUNDE",
        "targetColumn": "KUNDNR",
        "confidence": "high",
        "evidence": "Explicit DB2 FK + column name match + JOIN in BDHETIK.CBL"
      }
    }
  ],
  "model": "qwen2.5:7b",
  "protocol": "Naming-TableNames",
  "analyzedAt": "2026-03-25T15:00:00"
}
```

## Relationship to ColumnNames

Each column in a table's `columns[]` array is also upserted into the cross-analysis
column registry at `ColumnNames/{COLUMN}.json`. The column registry provides a unified
view across all analysis profiles, while this file provides the table-specific view.

## Cache Behavior

- A table file is considered complete when it has both `futureName` and a non-empty `columns[]` array
- If a file exists without columns, the next analysis run will add column naming
- Files are never overwritten by subsequent runs — the first analysis to name a table "wins"

## Downstream Use

These mappings will be consumed by a future C# code generation project to produce:

- Entity classes with `[Table("A_ORDREHODE")]` attributes and `[Column("KUNDNR")]` properties
- Navigation properties for inferred FK relationships
- XML documentation comments with English descriptions
- DbContext configurations mapping modern names to legacy schema
- Repository interfaces using the modern domain names
