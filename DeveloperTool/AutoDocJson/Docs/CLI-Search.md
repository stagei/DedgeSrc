# AutoDocJson CLI Search

Search the generated documentation index directly from the command line without starting the batch runner or web server.

## Syntax

```
AutoDocJson.exe --search <terms> [--searchfield <field>] [--searchtypes <types>] [--searchlogic AND|OR]
```

When `--search` is present the application runs the search, prints results, and exits immediately.

## Parameters

| Parameter | Description |
|---|---|
| `--search <terms>` | Text to search for. Use comma-separated values for multiple terms within the same field (AND). Can be repeated to add filters on different fields. |
| `--searchfield <field>` | Restrict the preceding `--search` to a specific JSON field. Must follow directly after its `--search` value. |
| `--searchtypes <types>` | Comma-separated list of file types to include: `CBL`, `SQL`, `PS1`, `REX`, `BAT`, `CSharp`. Omit to search all types. |
| `--searchlogic AND\|OR` | How multiple `--search` filters are combined. Default is `AND` (all must match). Use `OR` to match any. |

## Available Fields

Fields vary by file type. Common fields across all types:

| Field | Description | Types |
|---|---|---|
| `fileName` | Source file name | All |
| `description` | File description / header comment | All |
| `columns` | Table column names | SQL |
| `metadata.schema` | Database schema (e.g. DBM, CRM) | SQL |
| `metadata.tableName` | Table name without schema | SQL |
| `metadata.fullName` | Schema.TableName | SQL |
| `metadata.tableType` | `Sql Table` or `Sql View` | SQL |
| `metadata.comment` | Table comment from DB2 catalog | SQL |
| `metadata.system` | System code and name | CBL |
| `metadata.typeCode` | Program type code | CBL |
| `metadata.typeLabel` | Program type label | CBL |
| `metadata.created` | Creation date | CBL, PS1 |
| `metadata.lastProduction` | Last production date | CBL |
| `sqlTables` | Referenced SQL tables | CBL |
| `calledSubprograms` | Called COBOL subprograms | CBL |
| `calledPrograms` | Called programs | CBL |
| `copyElements` | COPY members used | CBL |
| `changeLog` | Change history text | CBL, PS1 |
| `calledScripts` | Referenced PowerShell modules/scripts | PS1 |
| `functions` | Defined functions | PS1, CSharp |
| `classes` | Defined classes | CSharp |
| `namespaces` | Namespaces | CSharp |
| `restEndpoints` | REST API endpoints | CSharp |
| `diagrams` | Mermaid diagram content (node labels, relationships) | All |

## Examples

### 1. Simple text search

Search across all fields and all file types:

```
AutoDocJson.exe --search ORDREHODE
```

Result: 611 matches across SQL tables (file name), CBL programs (sqlTables field), and more.

### 2. Filter by file type

Search only SQL table definitions:

```
AutoDocJson.exe --search ORDREHODE --searchtypes SQL
```

Result: 48 SQL tables with "ORDREHODE" in the name or metadata.

### 3. Search within a specific field

Find SQL tables that have `AVDNR` in their column list:

```
AutoDocJson.exe --search AVDNR --searchfield columns --searchtypes SQL
```

Result: 1232 SQL tables containing the AVDNR column.

### 4. Multiple terms in the same field (AND)

Find SQL tables that have **both** `AVDNR` and `ORDRENR` columns:

```
AutoDocJson.exe --search "AVDNR,ORDRENR" --searchfield columns --searchtypes SQL
```

Result: 534 tables (subset of the 1232 from example 3 -- only those with both columns).

### 5. AND across multiple fields

Find COBOL programs that reference the `PLUKKLISTE` table **and** call the `GMADATO` subprogram **and** have "Plukklister" in the description:

```
AutoDocJson.exe --search PLUKKLISTE --searchfield sqlTables ^
                --search GMADATO --searchfield calledSubprograms ^
                --search Plukklister --searchfield description ^
                --searchtypes CBL
```

Result: 1 match -- `OSAPLUK.CBL` (the only file satisfying all three conditions).

### 6. AND across multiple fields (broader)

Find COBOL programs that reference the `ORDREHODE` table **and** call the `GMACOCO` subprogram:

```
AutoDocJson.exe --search ORDREHODE --searchfield sqlTables ^
                --search GMACOCO --searchfield calledSubprograms ^
                --searchtypes CBL
```

Result: 317 COBOL programs that use both.

### 7. OR logic between fields

Find COBOL programs that reference `PLUKKLISTE` in sqlTables **or** call `OKAUTVE` as a subprogram:

```
AutoDocJson.exe --search PLUKKLISTE --searchfield sqlTables ^
                --search OKAUTVE --searchfield calledSubprograms ^
                --searchtypes CBL ^
                --searchlogic OR
```

Result: 9 matches (union -- includes `OSAPLUK.CBL` via PLUKKLISTE and `OSAUTLE.CBL` via OKAUTVE).

### 8. Multi-term in one field across types

Find PowerShell scripts that import **both** `Infrastructure` and `GlobalFunctions` modules:

```
AutoDocJson.exe --search "Infrastructure,GlobalFunctions" --searchfield calledScripts --searchtypes PS1
```

Result: 26 PS1 files that depend on both modules.

### 9. OR across the same field

Find PowerShell scripts that import **either** `Deploy-Handler` or `SoftwareUtils`:

```
AutoDocJson.exe --search Deploy-Handler --searchfield calledScripts ^
                --search SoftwareUtils --searchfield calledScripts ^
                --searchtypes PS1 ^
                --searchlogic OR
```

Result: 32 PS1 files (broader than AND would give).

### 10. Combine field filter with schema filter

Find DBM tables that have **both** `AVDNR` and `KUNDENR` columns **and** belong to the `DBM` schema:

```
AutoDocJson.exe --search "AVDNR,KUNDENR" --searchfield columns ^
                --search DBM --searchfield metadata.schema ^
                --searchtypes SQL
```

Result: 218 DBM tables with both columns.

### 11. Pinpoint a single file with 4 conditions

Narrow down to exactly one file using four different field conditions:

```
AutoDocJson.exe --search PLUKKLISTE --searchfield sqlTables ^
                --search GMADATO --searchfield calledSubprograms ^
                --search Plukklister --searchfield description ^
                --search Optima --searchfield metadata.system ^
                --searchtypes CBL
```

Result: Exactly 1 match -- `OSAPLUK.CBL`.

### 12. No results

```
AutoDocJson.exe --search XYZNONEXISTENT12345
```

Result: 0 results (no match found -- clean exit).

## Output Format

Results are displayed as a formatted table:

```
Search: "PLUKKLISTE" in sqlTables + "GMADATO" in calledSubprograms + "Plukklister" in description (CBL only)
Found 1 results:

  Type  File         Description              Matched In
  ----  -----------  -----------------------  ----------
  CBL   OSAPLUK.CBL  Utskrift av Plukklister  sqlTables, calledSubprograms, description
```

The **Matched In** column shows which fields contained the search terms.

When using OR logic, the header uses `|` as separator and appends `[OR logic]`:

```
Search: "PLUKKLISTE" in sqlTables | "OKAUTVE" in calledSubprograms (CBL only) [OR logic]
Found 9 results:
```

## Notes

- All searches are **case-insensitive**.
- The search index is loaded from `%OptPath%\Webs\AutoDocJson\_json\search-index.json`.
- Use `--outputfolder` to point to a different output folder if needed.
- When a single `--search` is used without `--searchfield`, it searches across all fields (simple mode).
- When multiple `--search` entries are used, the engine switches to advanced mode where each filter targets its specified field.
- Within a single `--search` value, comma-separated terms are matched with AND logic (all must be present in the field).
- Between multiple `--search` filters, `--searchlogic` controls AND (default) or OR combination.
