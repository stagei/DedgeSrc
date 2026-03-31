# ColumnNames — Cross-Analysis Column Translation Registry

## Purpose

Legacy DB2 column names are abbreviated Norwegian identifiers constrained by historical
character limits (e.g. `KUNDNR` = kundenummer, `BELOP` = beløp, `AVDNR` = avdelingsnummer).
The same column name often appears in dozens of tables across different business domains.

This folder is a **cross-analysis translation registry** — each file maps one unique DB2 column
name to its modern C# equivalent, with a unified English description built from all analysis
profiles that have encountered it. When CobDok and FkKonto both analyze a table containing
`AVDNR`, their perspectives are merged into a single, comprehensive understanding.

## How It Works

### Upsert Flow (during Phase 8f)

When an analysis profile names columns for a table:

1. **New column** (no registry entry): create `{COLUMN}.json` with a single context entry
2. **Existing, similar description**: add the analysis tag to `contexts[]`, keep `finalContext`
3. **Existing, different description**: invoke Ollama via `Naming-ColumnConflict.mdc` protocol
   to produce a unified `finalContext` that covers all valid perspectives

### Conflict Resolution

When two analyses produce different descriptions for the same column, Ollama evaluates:

- Whether both perspectives are valid (→ `keep-both`: merge into unified description)
- Whether the previous description was wrong (→ `replace-old`: mark old as superseded)
- Whether the new description is wrong (→ `keep-old`: add as analysis-specific note)

The `contexts[]` array preserves the original description from each analysis, even after
resolution. This provides full traceability of how understanding evolved across analyses.

## File Format

One JSON file per unique column name: `{COLUMNNAME}.json`

```json
{
  "originalName": "AVDNR",
  "futureName": "DepartmentNumber",
  "finalContext": "Numeric department/branch identifier. Foreign key to Z_AVDTAB. Used across ordering, inventory, and accounting to scope data to a physical location.",
  "contexts": [
    {
      "analysis": "CobDok",
      "description": "Department number for COBDOK documentation module ownership",
      "analyzedAt": "2026-03-26T11:00:00"
    },
    {
      "analysis": "FkKonto",
      "description": "Department number for accounting transactions and cost center allocation",
      "analyzedAt": "2026-03-26T14:30:00"
    }
  ],
  "usedInTables": ["A_BESTHODE", "A_ORDREHODE", "Z_AVDTAB", "TILGBRUKER"],
  "isTypicalForeignKey": true,
  "typicalTarget": "Z_AVDTAB.AVDNR",
  "model": "qwen2.5:7b",
  "lastResolvedAt": "2026-03-26T14:31:00"
}
```

| Field | Description |
|-------|-------------|
| `originalName` | Original DB2 column name (uppercase) |
| `futureName` | CamelCase C# property name |
| `finalContext` | Unified English description, resolved across all analyses |
| `contexts[]` | Per-analysis descriptions with timestamps and optional superseded flag |
| `usedInTables` | All tables known to contain this column |
| `isTypicalForeignKey` | Whether this column commonly acts as a FK |
| `typicalTarget` | Most common FK target (e.g. `Z_AVDTAB.AVDNR`) |
| `lastResolvedAt` | Timestamp of last conflict resolution |

## Relationship to TableNames

The table-specific column data (with FK inference per table) lives in `TableNames/{TABLE}.json`.
This registry provides the **generic, cross-table** view of each column name — a unified
translation dictionary independent of any specific table.

## Strategic Value

This registry enables:

- **Consistent naming across analysis profiles**: all analyses use the same C# name for `AVDNR`
- **Knowledge accumulation**: each analysis run enriches the understanding of shared columns
- **Foreign key discovery**: columns appearing in many tables are strong FK candidates
- **Future code generation**: a single source of truth for column-to-property mapping
- **Domain dictionary**: a comprehensive English glossary of legacy DB2 column semantics
