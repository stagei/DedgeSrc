# IntelliSense Improvement Specification

## Overview

This document specifies improvements to the SQL IntelliSense system to provide context-aware, schema-first completion suggestions that follow the database-agnostic architecture.

## Current State

**Location of IntelliSense Code:**
- `Services/IntelliSenseManager.cs` - Orchestrates providers
- `Services/SqlIntelliSenseProvider.cs` - Main completion logic
- `Services/IntelliSenseDataLoader.cs` - Loads metadata from JSON
- `Models/IntelliSenseModels.cs` - Data models
- `Controls/ConnectionTabControl.xaml.cs` - Editor integration

**Current Issues:**
1. IntelliSense shows `SCHEMA.TABLE` format directly instead of schema-first workflow
2. Ctrl+Space doesn't trigger context-aware suggestions
3. Suggestions not filtered based on SQL statement context
4. No multi-statement awareness

---

## Requirement 1: Schema-First IntelliSense

### Current Behavior
When typing `SELECT * FROM d`, IntelliSense shows:
```
DBM.KUNDER_VISMA_KRED
DBM.H_XE_ORDREH
ILOGTST.SOME_TABLE
...
```

### Expected Behavior

**Step 1: Show Schemas First**
When typing `SELECT * FROM d`, IntelliSense should show:
```
DBM                   (Schema)
DB2ADMIN              (Schema)
```

**Step 2: After Period, Show Tables/Views**
After user selects `DBM` and types `.`, IntelliSense should show:
```
KUNDER_VISMA_KRED     (Table: DBM.KUNDER_VISMA_KRED)
H_XE_ORDREH           (Table: DBM.H_XE_ORDREH)
P_PRISREG_FRI         (Table)
SOME_VIEW             (View)
```

### Implementation Changes

#### 1. Modify `DetermineSqlContext()` in `SqlIntelliSenseProvider.cs`

```csharp
private SqlContext DetermineSqlContext(string text, int caretPosition)
{
    var textBeforeCaret = text.Substring(0, Math.Min(caretPosition, text.Length));
    
    // Check for schema.period pattern first (highest priority)
    var schemaMatch = Regex.Match(textBeforeCaret, @"(\w+)\.$");
    if (schemaMatch.Success)
    {
        var possibleSchema = schemaMatch.Groups[1].Value;
        if (_schemaNames.Contains(possibleSchema, StringComparer.OrdinalIgnoreCase))
        {
            return SqlContext.SchemaObject; // Show tables/views in this schema
        }
    }
    
    // Check for table name context (after FROM/JOIN)
    var lastToken = GetPreviousToken(textBeforeCaret);
    if (lastToken is "FROM" or "JOIN" or "INTO" or "TABLE" or "UPDATE")
    {
        return SqlContext.Schema; // NEW: Show schemas first
    }
    
    // ... rest of context detection
}
```

#### 2. Add New `SqlContext.Schema` Enum Value

```csharp
public enum SqlContext
{
    Keyword,
    Schema,          // NEW: Show schemas only
    TableName,       // Show tables (deprecated - use SchemaObject)
    SchemaObject,    // Show tables/views within a specific schema
    ColumnName,
    Function,
    DataType,
    SystemCatalog,
    Snippet,
    General
}
```

#### 3. Add `GetSchemaCompletions()` Method

```csharp
private List<ICompletionData> GetSchemaCompletions()
{
    return _schemaNames
        .Select(s => new SqlSchemaCompletionData
        {
            Text = s,
            Description = $"Schema: {s}",
            Priority = 3.0,
            CompletionText = s  // Just the schema name, no period
        })
        .Cast<ICompletionData>()
        .ToList();
}
```

---

## Requirement 2: Ctrl+Space Context-Aware Trigger

### Current Behavior
Pressing Ctrl+Space shows all keywords without analyzing statement context.

### Expected Behavior
Ctrl+Space should:
1. Parse the current statement to determine cursor position context
2. Show only relevant suggestions based on SQL syntax position
3. Re-analyze and update suggestions based on what user has typed

### Implementation Changes

#### 1. Modify `SqlEditor_KeyDown` in `ConnectionTabControl.xaml.cs`

```csharp
private void SqlEditor_KeyDown(object sender, KeyEventArgs e)
{
    // Ctrl+Space = Force context-aware completion
    if (e.Key == Key.Space && Keyboard.Modifiers == ModifierKeys.Control)
    {
        e.Handled = true;
        ForceContextAwareCompletion();
        return;
    }
}

private void ForceContextAwareCompletion()
{
    var text = SqlEditor.Text;
    var caretPosition = SqlEditor.CaretOffset;
    
    // Parse current statement
    var currentStatement = ExtractCurrentStatement(text, caretPosition);
    var statementCaretOffset = CalculateStatementOffset(text, caretPosition, currentStatement);
    
    // Get context-aware completions
    var context = _intellisenseProvider.DetermineContext(
        currentStatement, 
        statementCaretOffset
    );
    
    ShowContextAwareCompletions(context);
}
```

#### 2. Add Statement Extraction Method

This reuses the same logic as Ctrl+Enter for statement detection:

```csharp
private string ExtractCurrentStatement(string text, int caretPosition)
{
    // Find statement boundaries (semicolons or EOF)
    var statements = SplitIntoStatements(text);
    var charCount = 0;
    
    foreach (var stmt in statements)
    {
        charCount += stmt.Length + 1; // +1 for semicolon
        if (charCount >= caretPosition)
        {
            return stmt.Trim();
        }
    }
    
    return statements.LastOrDefault() ?? text;
}
```

---

## Requirement 3: Context-Correct Suggestions

### Current Behavior
After `FROM`, IntelliSense shows mixed results including keywords that don't make sense.

### Expected Behavior

| Context | What Should Show |
|---------|------------------|
| `SELECT ` | Columns from tables in FROM clause, `*`, functions, `DISTINCT` |
| `FROM ` | Schemas first, then tables/views after schema selection |
| `WHERE ` | Columns from referenced tables, operators |
| `JOIN ` | Schemas/tables |
| `ON ` | Columns for join condition |
| `ORDER BY ` | Columns from SELECT clause |
| `GROUP BY ` | Columns from SELECT clause |
| `INSERT INTO ` | Schemas/tables |
| `VALUES (` | Literals, functions, subqueries |
| `SET ` | Columns of update target |

### Implementation Changes

#### 1. Enhanced Context Detection Algorithm

```csharp
public SqlContext DetermineContextAdvanced(string statement, int caretOffset)
{
    var tokens = TokenizeSql(statement);
    var tokenAtCaret = FindTokenAtPosition(tokens, caretOffset);
    var previousTokens = GetPreviousTokens(tokens, tokenAtCaret, count: 5);
    
    // Build context from token analysis
    return AnalyzeTokenContext(previousTokens, tokenAtCaret);
}

private SqlContext AnalyzeTokenContext(List<SqlToken> previous, SqlToken? current)
{
    var lastKeyword = previous.LastOrDefault(t => t.Type == TokenType.Keyword);
    
    return lastKeyword?.Value.ToUpperInvariant() switch
    {
        "SELECT" => SqlContext.ColumnName,
        "FROM" or "JOIN" or "INTO" => SqlContext.Schema,
        "WHERE" or "AND" or "OR" => SqlContext.ColumnName,
        "ON" => SqlContext.JoinCondition,
        "ORDER" when GetNextKeyword(current) == "BY" => SqlContext.OrderByColumn,
        "GROUP" when GetNextKeyword(current) == "BY" => SqlContext.GroupByColumn,
        "SET" => SqlContext.UpdateColumn,
        "VALUES" => SqlContext.InsertValue,
        "AS" => SqlContext.Alias,
        _ => SqlContext.Keyword
    };
}
```

#### 2. SQL Tokenizer (Simple)

```csharp
public class SqlToken
{
    public TokenType Type { get; set; }
    public string Value { get; set; }
    public int StartPosition { get; set; }
    public int EndPosition { get; set; }
}

public enum TokenType
{
    Keyword,
    Identifier,
    Operator,
    Literal,
    Comment,
    Whitespace,
    Symbol
}

private List<SqlToken> TokenizeSql(string sql)
{
    var tokens = new List<SqlToken>();
    // Implement regex-based tokenization
    // Match: keywords, identifiers, strings, numbers, operators, symbols
    return tokens;
}
```

---

## Requirement 4: Multi-Statement Awareness

### Current Behavior
IntelliSense analyzes entire editor content, not focused on current statement.

### Expected Behavior
IntelliSense should:
1. Detect current statement (same as Ctrl+Enter)
2. Only analyze tables/aliases within current statement
3. Provide completions relevant to current statement only

### Implementation Changes

#### 1. Statement Boundary Detection

```csharp
public class StatementInfo
{
    public string Text { get; set; }
    public int StartOffset { get; set; }
    public int EndOffset { get; set; }
    public List<string> TableReferences { get; set; } = new();
    public Dictionary<string, string> Aliases { get; set; } = new();
}

public StatementInfo ExtractCurrentStatementInfo(string fullText, int caretOffset)
{
    // Use same algorithm as Ctrl+Enter
    var statements = SplitByStatementDelimiters(fullText);
    var currentOffset = 0;
    
    foreach (var stmt in statements)
    {
        var end = currentOffset + stmt.Length;
        if (caretOffset >= currentOffset && caretOffset <= end)
        {
            return new StatementInfo
            {
                Text = stmt,
                StartOffset = currentOffset,
                EndOffset = end,
                TableReferences = ExtractTableReferences(stmt),
                Aliases = ExtractAliases(stmt)
            };
        }
        currentOffset = end + 1; // +1 for delimiter
    }
    
    return new StatementInfo { Text = fullText };
}
```

#### 2. Alias-Aware Column Completion

```csharp
private List<ICompletionData> GetColumnCompletionsWithAliases(StatementInfo statement)
{
    var completions = new List<ICompletionData>();
    
    foreach (var alias in statement.Aliases)
    {
        var tableName = alias.Value;
        var aliasName = alias.Key;
        
        if (_tableColumns.TryGetValue(tableName, out var columns))
        {
            completions.AddRange(columns.Select(c => new SqlColumnCompletionData
            {
                ColumnName = c.Name,
                TableAlias = aliasName,
                Text = $"{aliasName}.{c.Name}",
                Description = $"Column from {tableName} (alias: {aliasName})"
            }));
        }
    }
    
    return completions;
}
```

---

## Requirement 5: Database-Agnostic Architecture

### Mandatory Constraints

All IntelliSense improvements MUST:
1. Use `IConnectionManager` interface, never concrete types
2. Load provider-specific keywords from JSON files
3. Use `MetadataHandler.GetQuery()` for SQL queries
4. Register in `IntelliSenseManager` with provider name
5. No hardcoded DB2-specific code in shared classes

### File Structure

```
Services/
├── IntelliSenseManager.cs         # Orchestrator (agnostic)
├── SqlIntelliSenseProvider.cs     # Base provider (agnostic)
├── IntelliSenseDataLoader.cs      # JSON loader (agnostic)
└── Providers/
    ├── DB2/
    │   └── Db2IntelliSenseProvider.cs    # DB2-specific extensions
    ├── PostgreSQL/
    │   └── PostgreSqlIntelliSenseProvider.cs
    └── Oracle/
        └── OracleIntelliSenseProvider.cs
```

### Provider-Specific SQL in JSON

**File: `ConfigFiles/db2_12.1_intellisense_queries.json`**
```json
{
  "GetSchemasQuery": "SELECT DISTINCT TRIM(SCHEMANAME) FROM SYSCAT.SCHEMATA WHERE SCHEMANAME NOT LIKE 'SYS%' ORDER BY SCHEMANAME",
  "GetTablesInSchemaQuery": "SELECT TRIM(TABNAME), TYPE FROM SYSCAT.TABLES WHERE TRIM(TABSCHEMA) = ? ORDER BY TABNAME",
  "GetColumnsQuery": "SELECT TRIM(COLNAME), TYPENAME, LENGTH, NULLS FROM SYSCAT.COLUMNS WHERE TRIM(TABSCHEMA) = ? AND TRIM(TABNAME) = ? ORDER BY COLNO"
}
```

**File: `ConfigFiles/postgresql_16.0_intellisense_queries.json`**
```json
{
  "GetSchemasQuery": "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema') ORDER BY schema_name",
  "GetTablesInSchemaQuery": "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name",
  "GetColumnsQuery": "SELECT column_name, data_type, character_maximum_length, is_nullable FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position"
}
```

---

## Implementation Plan

### Phase 1: Schema-First IntelliSense
1. Add `SqlContext.Schema` enum value
2. Modify `DetermineSqlContext()` for FROM/JOIN detection
3. Create `GetSchemaCompletions()` method
4. Update completion window to show schemas first
5. Test with multiple schemas

### Phase 2: Ctrl+Space Enhancement
1. Add Ctrl+Space handler with context analysis
2. Implement `ExtractCurrentStatement()` 
3. Add statement-caret offset calculation
4. Test with various cursor positions

### Phase 3: Context-Correct Suggestions
1. Implement SQL tokenizer
2. Create `AnalyzeTokenContext()` method
3. Build context-to-completion mapping
4. Test all SQL contexts (SELECT, FROM, WHERE, etc.)

### Phase 4: Multi-Statement Support
1. Implement `StatementInfo` extraction
2. Add alias detection and tracking
3. Scope column completions to current statement
4. Test with multiple statements in editor

### Phase 5: Provider Abstraction
1. Move DB2-specific queries to JSON
2. Create provider-specific query files
3. Update `MetadataHandler` for IntelliSense queries
4. Test with DB2 (PostgreSQL placeholder for future)

---

## Testing Scenarios

### Scenario 1: Schema Selection
```sql
SELECT * FROM |    -- Shows: DBM, ILOGTST, DB2ADMIN, etc.
SELECT * FROM DBM| -- Shows: DBM (matched)
SELECT * FROM DBM.|-- Shows: Tables/Views in DBM schema
```

### Scenario 2: Column Completion
```sql
SELECT | FROM DBM.CUSTOMERS  -- Shows: columns of CUSTOMERS
SELECT C.| FROM DBM.CUSTOMERS C  -- Shows: columns with alias C
```

### Scenario 3: Multi-Statement
```sql
SELECT * FROM DBM.ORDERS;   -- Statement 1
SELECT | FROM DBM.CUSTOMERS -- Statement 2: only CUSTOMERS columns
```

### Scenario 4: Ctrl+Space
```sql
SELECT * FROM DBM.ORDERS WHERE |  -- Ctrl+Space shows columns of ORDERS
```

---

## Success Criteria

1. ✅ After `FROM`, schemas appear first in completion list
2. ✅ After `SCHEMA.`, tables/views of that schema appear
3. ✅ Ctrl+Space triggers context-aware suggestions
4. ✅ Suggestions match SQL context (SELECT=columns, FROM=schemas)
5. ✅ Multi-statement editor shows only current statement's context
6. ✅ Works with all supported database providers
7. ✅ No hardcoded DB2 code in shared services

---

## References

- `.cursorrules` - Database agnostic architecture rules
- `Services/SqlIntelliSenseProvider.cs` - Current implementation
- `ConfigFiles/db2_12.1_keywords.json` - Current keywords file
- `Controls/ConnectionTabControl.xaml.cs` - Editor integration

---

*Document created: 2025-12-18*
*Author: AI Assistant*
*Status: SPECIFICATION - Ready for Implementation*
