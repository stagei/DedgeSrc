# Missing Foreign Key Discovery Batch Job - Specification

## 1. Overview
This specification defines a new screen for selecting tables (similar to the
Mermaid designer table picker) and exporting a JSON input file that drives a
detached batch job. The batch job extracts data from selected tables into files
and analyzes relationships to detect likely foreign keys that are missing from
the schema. An additional JSON file lists fields to ignore during analysis.

The batch job must run independently of the WPF client thread (detached process)
and continue even if the UI is closed.

## 2. Goals
- Provide a UI to select a set of tables (Mermaid-like selection UX).
- Export table metadata and foreign key information to a JSON input file.
- Start a detached background job that performs data extraction and analysis.
- Support an ignore list JSON for columns/tables to skip.
- Produce a results JSON with candidate missing foreign keys and evidence.
- Handle tables with no primary keys without failure.

## 3. Non-Goals
- No automatic schema changes or DDL execution.
- No provider-specific logic outside existing DB2 provider files.
- No new database provider implementation.
- No UI for job monitoring beyond basic "started" feedback and log access.

## 4. UI Screen: "Missing FK Discovery"
### 4.1 Placement
- Main menu: View -> Missing FK Discovery...
- Access Level tag: AccessLevel:Middle (read-only data access).

### 4.2 Layout (Mermaid-like Table Picker)
Left panel:
- Schema dropdown.
- Table list with search/filter.
- Checkbox selection for tables.
- Buttons:
  - "Add Selected"
  - "Add All in Schema"
  - "Remove Selected"

Right panel:
- Selected tables list with schema.table.
- Buttons:
  - "Follow Foreign Keys ->" (add referenced tables)
  - "<- Follow Incoming FKs" (add referencing tables)
  - "Clear Selection"

Bottom panel:
- Output folder picker.
- Ignore JSON file picker.
- Options (thresholds, sampling, parallelism).
- Buttons:
  - "Generate Input JSON"
  - "Start Batch Job"
  - "Open Output Folder"
  - "Open Job Log"

### 4.3 Required UI Behaviors
- Validate that at least one table is selected before export.
- Validate output folder and ignore file path (if provided).
- Disable "Start Batch Job" until input JSON is generated.
- Show a job id after starting the batch job.
- Provide a status label with last action and file paths.

## 5. User Scenario Walkthrough (UI)
1. User opens Missing FK Discovery screen from View menu.
2. User selects schema and picks tables (search, add, remove).
3. User optionally follows outgoing/incoming FK links.
4. User selects output folder and optional ignore JSON file.
5. User clicks "Generate Input JSON".
   - If metadata query fails, show error and allow retry.
6. User clicks "Start Batch Job".
   - A detached process starts; UI shows job id and log path.
7. User can close the UI; job continues in background.

Edge cases:
- No tables selected -> show validation error.
- Output folder not writable -> show error with retry.
- DB connection lost -> log and show error.
- Ignore JSON invalid -> show error and keep current selection.
- Tables without PK -> allow; mark in output as "no key".

## 6. Data Flow
1. UI selection -> metadata collection -> input JSON file.
2. UI starts detached job with:
   - Input JSON path
   - Ignore JSON path (optional)
   - Output folder
   - Job id
3. Batch job:
   - Loads input JSON and ignore JSON.
   - Extracts table data into files.
   - Analyzes data and generates results JSON.
   - Writes a job log and progress updates.

## 7. JSON Schemas
### 7.1 Input JSON (missing_fk_input.json)
Purpose: Snapshot of selected tables and metadata.

Example:
```json
{
  "jobId": "2026-01-28T12-00-00Z_abc123",
  "generatedAtUtc": "2026-01-28T12:00:00Z",
  "connectionProfile": "FKKTOTST",
  "provider": "DB2",
  "providerVersion": "12.1",
  "options": {
    "minRowCount": 100,
    "minMatchRatio": 0.95,
    "strongMatchRatio": 0.99,
    "maxParallelTables": 4,
    "exportFormat": "csv",
    "includeNullsInMatch": false
  },
  "selectedTables": [
    { "schema": "INL", "name": "KUNDE" },
    { "schema": "INL", "name": "ORDER" }
  ],
  "tables": [
    {
      "schema": "INL",
      "name": "KUNDE",
      "rowCount": 1200,
      "columns": [
        { "name": "KUNDE_ID", "dataType": "INTEGER", "length": 4, "nullable": false }
      ],
      "primaryKey": [ "KUNDE_ID" ],
      "uniqueKeys": [ [ "KUNDE_ID" ] ],
      "foreignKeys": [
        {
          "name": "FK_ORDER_KUNDE",
          "columns": [ "KUNDE_ID" ],
          "refSchema": "INL",
          "refTable": "KUNDE",
          "refColumns": [ "KUNDE_ID" ]
        }
      ]
    }
  ]
}
```

Notes:
- Connection profile name is stored, not credentials.
- All SQL used for metadata comes from JSON statements via MetadataHandler.
- Tables with no PK must set "primaryKey": [].

### 7.2 Ignore JSON (missing_fk_ignore.json)
Purpose: List of tables and columns to exclude.

Example:
```json
{
  "ignoreTables": [
    { "schema": "SYSIBM", "name": "*" },
    { "schema": "INL", "name": "LOG_*" }
  ],
  "ignoreColumns": [
    { "schema": "INL", "table": "*", "name": "LAST_UPDATED_TS" },
    { "schema": "*", "table": "*", "name": "CREATED_BY" }
  ],
  "ignoreColumnPatterns": [
    "^TMP_",
    "_HASH$"
  ],
  "ignoreDataTypes": [
    "BLOB",
    "CLOB",
    "XML"
  ]
}
```

Notes:
- Patterns are regex; they must be documented with a comment block when used in
  code (see regex rule).
- Wildcards in table/column entries are supported ("*").

### 7.3 Results JSON (missing_fk_results.json)
Purpose: Output of the batch analysis.

Example:
```json
{
  "jobId": "2026-01-28T12-00-00Z_abc123",
  "completedAtUtc": "2026-01-28T12:45:00Z",
  "summary": {
    "tablesScanned": 42,
    "candidatesFound": 8,
    "strongCandidates": 3,
    "tablesWithoutKeys": 5
  },
  "candidates": [
    {
      "childTable": { "schema": "INL", "name": "ORDER" },
      "childColumns": [ "KUNDE_ID" ],
      "parentTable": { "schema": "INL", "name": "KUNDE" },
      "parentColumns": [ "KUNDE_ID" ],
      "matchRatio": 0.992,
      "nullRatio": 0.01,
      "evidence": {
        "childDistinct": 1180,
        "parentDistinct": 1200,
        "missingInParent": 9
      },
      "confidence": "STRONG",
      "recommendation": "ADD_FK"
    }
  ],
  "tablesWithoutKeys": [
    { "schema": "INL", "name": "EVENT_LOG" }
  ]
}
```

## 8. Batch Job Execution
### 8.1 Launch Mode
Use a detached process based on the existing CLI infrastructure:
- Start a new process of DbExplorer.exe in CLI mode.
- Suggested command:
  - `DbExplorer.exe -profile FKKTOTST -command missing-fk-scan -input <path> -ignore <path> -out <folder>`

### 8.2 CLI/WPF Parity
The UI must use the same CLI command that can also be invoked manually.

Required CLI commands:
- `missing-fk-generate-input` (optional if UI handles input JSON)
- `missing-fk-scan` (runs the batch job)
- `missing-fk-status` (optional, reads status file)

## 9. Data Extraction
- Export format: CSV (UTF-8), one file per table.
- File naming: `<schema>.<table>.csv` with sanitized names.
- Extraction must be streaming and chunked to avoid memory spikes.
- Export queries must be parameterized and use MetadataHandler statements.

## 10. Missing FK Detection Algorithm (High Level)
1. Determine candidate parent keys:
   - Use primary keys first.
   - Use unique constraints / unique indexes.
   - If none, compute uniqueness ratio (distinct / row count) to discover
     potential keys.
2. Determine candidate child columns:
   - Match data type, length, scale.
   - Exclude ignored columns and data types.
   - Prefer columns with name patterns like *_ID.
3. Compute match ratio:
   - Join or hash compare values for each candidate pair.
   - Match ratio = child values present in parent / total child values.
4. Score confidence:
   - STRONG if matchRatio >= strongMatchRatio.
   - POSSIBLE if matchRatio >= minMatchRatio.
5. Emit results JSON with evidence counts.

## 11. Handling Tables Without Primary Keys
- Input JSON must allow "primaryKey": [].
- If no PK and no unique keys, table can still be:
  - A child table (columns may reference other tables).
  - A parent table only if a high-uniqueness column is found.
- Results must list all tables without keys.

## 12. Logging and Error Handling
- Use NLog with DEBUG logging for:
  - Metadata collection
  - Export start/end per table
  - Candidate scoring steps
  - File paths and counts (no sensitive data)
- All exceptions must be logged with context.
- Mask connection passwords in logs.

## 13. Performance and Safety
- Limit parallel table exports (default 4).
- Use cancellation tokens for graceful stop (future enhancement).
- Provide sampling mode for large tables (future enhancement).
- Ensure job does not block UI thread (detached process only).

## 14. Security and Access Control
- Requires AccessLevel:Middle (read-only operations).
- No data modifications or DDL execution.
- Do not write credentials to JSON files.

## 15. Dependencies and Constraints
- No new NuGet packages unless required.
- All SQL must be stored in ConfigFiles/*.json and retrieved via MetadataHandler.
- Provider-specific code remains in provider files only.

## 16. Open Questions
- Default output folder location (AppData vs user selected).
- Retention policy for exported data files.
- Should results include a generated DDL script (optional).
