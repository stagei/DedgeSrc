# Nested SQL IntelliSense Specification

## Overview

This document specifies the architecture for scope-aware IntelliSense that properly handles nested subselects, derived tables, and multi-level SQL queries.

## Core Concept

Parse SQL by parenthesis nesting levels. Each level maintains its own scope of:
- **Aliases** (table aliases defined at this level)
- **Columns** (columns exposed by SELECT at this level)
- **SQL Parts** (SELECT, FROM, WHERE content)

### Visibility Rules

| Cursor at Level | Can See Aliases From | Can See Columns From |
|-----------------|---------------------|---------------------|
| Level 0 (main)  | Level 0 aliases     | Level 0 table columns + Level 1 subselect exposed columns |
| Level N         | Level N aliases     | Level N table columns + Level N+1 subselect exposed columns |

**Key Rule**: A subselect at level N+1 exposes ONLY its SELECT list columns to level N via its alias.

---

## Data Structure

### `SqlScope` Object

```csharp
public class SqlScope
{
    public int Level { get; set; }                    // Nesting level (0 = main query)
    public int StartPosition { get; set; }            // Position of opening '('
    public int EndPosition { get; set; }              // Position of closing ')'
    public string? Alias { get; set; }                // Alias if this is a derived table
    public List<TableReference> Tables { get; set; } // Tables/aliases in FROM clause
    public List<string> ExposedColumns { get; set; } // Columns from SELECT (exposed to parent)
    public string SelectPart { get; set; }            // The SELECT clause content
    public string FromPart { get; set; }              // The FROM clause content
    public string WherePart { get; set; }             // The WHERE clause content
}

public class TableReference
{
    public string Schema { get; set; }
    public string TableName { get; set; }
    public string FullName => $"{Schema}.{TableName}";
    public string? Alias { get; set; }
    public bool IsDerivedTable { get; set; }          // True if this is a subselect
    public int? DerivedTableScopeIndex { get; set; } // Index to child scope if derived
}
```

---

## Example 1: Simple Nested Query

### SQL
```sql
SELECT o.order_id, o.total, c.name
FROM DBM.ORDERS o
JOIN (SELECT customer_id, name FROM DBM.CUSTOMERS WHERE active = 'Y') c
  ON o.customer_id = c.customer_id
WHERE o.order_date > CURRENT DATE
```

### Parsed Scope Array

```json
[
  {
    "level": 0,
    "startPosition": 0,
    "endPosition": 195,
    "alias": null,
    "tables": [
      { "schema": "DBM", "tableName": "ORDERS", "alias": "o", "isDerivedTable": false },
      { "schema": null, "tableName": null, "alias": "c", "isDerivedTable": true, "derivedTableScopeIndex": 1 }
    ],
    "exposedColumns": ["order_id", "total", "name"],
    "selectPart": "o.order_id, o.total, c.name",
    "fromPart": "DBM.ORDERS o JOIN (...) c ON o.customer_id = c.customer_id",
    "wherePart": "o.order_date > CURRENT DATE"
  },
  {
    "level": 1,
    "startPosition": 52,
    "endPosition": 112,
    "alias": "c",
    "tables": [
      { "schema": "DBM", "tableName": "CUSTOMERS", "alias": null, "isDerivedTable": false }
    ],
    "exposedColumns": ["customer_id", "name"],
    "selectPart": "customer_id, name",
    "fromPart": "DBM.CUSTOMERS",
    "wherePart": "active = 'Y'"
  }
]
```

### IntelliSense Behavior

| Cursor Position | Available Aliases | Available Columns |
|-----------------|-------------------|-------------------|
| Main SELECT (level 0) | `o`, `c` | `o.*` (from ORDERS), `c.customer_id`, `c.name` (from subselect) |
| Main WHERE (level 0) | `o`, `c` | `o.*`, `c.customer_id`, `c.name` |
| Inside subselect (level 1) | none (no alias defined) | `customer_id`, `name`, `active` (from CUSTOMERS) |

---

## Example 2: Scalar Subselect

### SQL
```sql
SELECT o.order_id,
       o.customer_id,
       (SELECT SUM(amount) FROM DBM.ORDER_ITEMS oi WHERE oi.order_id = o.order_id) as total_amount
FROM DBM.ORDERS o
WHERE o.status = 'ACTIVE'
```

### Parsed Scope Array

```json
[
  {
    "level": 0,
    "alias": null,
    "tables": [
      { "schema": "DBM", "tableName": "ORDERS", "alias": "o", "isDerivedTable": false }
    ],
    "exposedColumns": ["order_id", "customer_id", "total_amount"],
    "selectPart": "o.order_id, o.customer_id, (...) as total_amount"
  },
  {
    "level": 1,
    "alias": null,
    "tables": [
      { "schema": "DBM", "tableName": "ORDER_ITEMS", "alias": "oi", "isDerivedTable": false }
    ],
    "exposedColumns": ["SUM(amount)"],
    "selectPart": "SUM(amount)",
    "parentAliasesVisible": ["o"]
  }
]
```

### IntelliSense Behavior

| Cursor Position | Available Aliases | Notes |
|-----------------|-------------------|-------|
| Main SELECT (level 0) | `o` | Scalar subselect doesn't expose alias |
| Inside scalar subselect (level 1) | `oi`, `o` | Parent alias `o` is visible for correlation |

**Special Rule**: Scalar subselects in SELECT clause can reference parent aliases (correlated subquery).

---

## Example 3: Multi-Level Nesting

### SQL
```sql
SELECT a.id, a.name, b.total_orders
FROM DBM.ACCOUNTS a
JOIN (
    SELECT customer_id, COUNT(*) as total_orders
    FROM (
        SELECT o.customer_id, o.order_id
        FROM DBM.ORDERS o
        WHERE o.status = 'COMPLETE'
    ) completed_orders
    GROUP BY customer_id
) b ON a.customer_id = b.customer_id
WHERE a.active = 'Y'
```

### Parsed Scope Array

```json
[
  {
    "level": 0,
    "alias": null,
    "tables": [
      { "schema": "DBM", "tableName": "ACCOUNTS", "alias": "a" },
      { "alias": "b", "isDerivedTable": true, "derivedTableScopeIndex": 1 }
    ],
    "exposedColumns": ["id", "name", "total_orders"]
  },
  {
    "level": 1,
    "alias": "b",
    "tables": [
      { "alias": "completed_orders", "isDerivedTable": true, "derivedTableScopeIndex": 2 }
    ],
    "exposedColumns": ["customer_id", "total_orders"]
  },
  {
    "level": 2,
    "alias": "completed_orders",
    "tables": [
      { "schema": "DBM", "tableName": "ORDERS", "alias": "o" }
    ],
    "exposedColumns": ["customer_id", "order_id"]
  }
]
```

### Column Visibility Chain

```
Level 0 (main):
  ├── a.* (all columns from DBM.ACCOUNTS)
  └── b.customer_id, b.total_orders (from level 1 exposed columns)
        └── NOT visible: completed_orders.*, o.*

Level 1 (subselect "b"):
  └── completed_orders.customer_id, completed_orders.order_id (from level 2)
        └── NOT visible: o.*

Level 2 (subselect "completed_orders"):
  └── o.* (all columns from DBM.ORDERS)
```

---

## Parsing Algorithm

### Step 1: Find All Scopes by Parentheses

```csharp
public List<SqlScope> ParseScopes(string sql)
{
    var scopes = new List<SqlScope>();
    var stack = new Stack<int>();  // Track opening parenthesis positions
    int level = 0;
    
    // Level 0 is the main query (no parentheses)
    scopes.Add(new SqlScope { Level = 0, StartPosition = 0, EndPosition = sql.Length });
    
    for (int i = 0; i < sql.Length; i++)
    {
        if (sql[i] == '(')
        {
            level++;
            stack.Push(i);
        }
        else if (sql[i] == ')' && stack.Count > 0)
        {
            int start = stack.Pop();
            string content = sql.Substring(start + 1, i - start - 1);
            
            // Check if this is a subselect (starts with SELECT)
            if (content.TrimStart().StartsWith("SELECT", StringComparison.OrdinalIgnoreCase))
            {
                scopes.Add(new SqlScope 
                { 
                    Level = level,
                    StartPosition = start,
                    EndPosition = i,
                    // Parse content further...
                });
            }
            level--;
        }
    }
    
    return scopes;
}
```

### Step 2: Extract Alias for Each Scope

Look for alias immediately after closing parenthesis:
```
) c ON ...       -> alias = "c"
) AS customer    -> alias = "customer"
) as total_amt   -> alias = "total_amt" (scalar subselect)
```

### Step 3: Parse SELECT, FROM, WHERE for Each Scope

For each scope, extract:
1. **SELECT columns** → These become `ExposedColumns`
2. **FROM tables/aliases** → These become `Tables`
3. **WHERE clause** → For reference

### Step 4: Determine Current Scope at Caret Position

```csharp
public SqlScope GetScopeAtPosition(List<SqlScope> scopes, int caretPosition)
{
    // Find the innermost scope containing the caret
    return scopes
        .Where(s => caretPosition >= s.StartPosition && caretPosition <= s.EndPosition)
        .OrderByDescending(s => s.Level)
        .FirstOrDefault();
}
```

---

## Handler Architecture

### NestedSelectHandler

Handles column completions when cursor is in a SELECT clause at any level.

```csharp
public class NestedSelectHandler
{
    public List<ICompletionData> GetCompletions(List<SqlScope> scopes, int currentLevel)
    {
        var completions = new List<ICompletionData>();
        var currentScope = scopes.First(s => s.Level == currentLevel);
        
        // Add columns from tables at current level
        foreach (var table in currentScope.Tables.Where(t => !t.IsDerivedTable))
        {
            completions.AddRange(GetColumnsForTable(table));
        }
        
        // Add exposed columns from derived tables (subselects at level + 1)
        foreach (var derivedTable in currentScope.Tables.Where(t => t.IsDerivedTable))
        {
            var childScope = scopes[derivedTable.DerivedTableScopeIndex.Value];
            foreach (var col in childScope.ExposedColumns)
            {
                completions.Add(new SqlColumnCompletionData
                {
                    ColumnName = col,
                    TableName = derivedTable.Alias,
                    Description = $"From subselect: {derivedTable.Alias}"
                });
            }
        }
        
        return completions;
    }
}
```

### NestedFromHandler

Handles table/schema completions when cursor is in a FROM clause.

```csharp
public class NestedFromHandler
{
    public List<ICompletionData> GetCompletions(int currentLevel)
    {
        // FROM clause always shows available schemas/tables
        // Level doesn't affect what schemas/tables are available
        return GetSchemaCompletions();
    }
}
```

### NestedWhereHandler

Handles column completions when cursor is in a WHERE clause.

```csharp
public class NestedWhereHandler
{
    public List<ICompletionData> GetCompletions(List<SqlScope> scopes, int currentLevel)
    {
        var completions = new List<ICompletionData>();
        var currentScope = scopes.First(s => s.Level == currentLevel);
        
        // Same as SELECT - add columns from current level tables
        foreach (var table in currentScope.Tables.Where(t => !t.IsDerivedTable))
        {
            completions.AddRange(GetColumnsForTable(table));
        }
        
        // Add exposed columns from derived tables
        foreach (var derivedTable in currentScope.Tables.Where(t => t.IsDerivedTable))
        {
            var childScope = scopes[derivedTable.DerivedTableScopeIndex.Value];
            completions.AddRange(childScope.ExposedColumns.Select(col => 
                new SqlColumnCompletionData { ColumnName = col, TableName = derivedTable.Alias }
            ));
        }
        
        // For correlated subqueries: add parent aliases
        if (currentLevel > 0 && IsCorrelatedSubquery(currentScope))
        {
            var parentScope = scopes.First(s => s.Level == currentLevel - 1);
            foreach (var table in parentScope.Tables)
            {
                completions.Add(new SqlAliasCompletionData 
                { 
                    AliasName = table.Alias ?? table.TableName,
                    Description = "Parent scope alias"
                });
            }
        }
        
        return completions;
    }
}
```

---

## Implementation Phases

### Phase 1: Basic Scope Parsing ✅
- [x] Parse parentheses to identify scope boundaries
- [x] Determine if each scope is a subselect
- [x] Find alias for each subselect

### Phase 2: SQL Part Extraction ✅
- [x] Extract SELECT clause columns for each scope
- [x] Extract FROM clause tables/aliases for each scope
- [x] Build the scope tree with parent-child relationships

### Phase 3: Scope-Aware Completions ✅
- [x] Implement `NestedSelectHandler` (integrated into GetColumnNameCompletions)
- [x] Implement `NestedFromHandler` (integrated into GetSchemaCompletions)
- [x] Implement `NestedWhereHandler` (same as SELECT handler)
- [x] Determine current scope from caret position

### Phase 4: Correlated Subquery Support ✅
- [x] Detect correlated subqueries (reference to parent alias)
- [x] Allow parent aliases in WHERE/ON clauses of subqueries

---

## Edge Cases

### 1. Function Calls with Parentheses
```sql
SELECT COALESCE(a.name, 'N/A'), TRIM(a.code) FROM ...
```
**Solution**: Only treat `()` as scope if content starts with SELECT.

### 2. IN Clause with Subselect
```sql
SELECT * FROM DBM.ORDERS WHERE customer_id IN (SELECT id FROM DBM.CUSTOMERS)
```
**Solution**: The subselect is at level 1, but doesn't have an alias (not a derived table).

### 3. EXISTS Clause
```sql
SELECT * FROM DBM.ORDERS o WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.order_id = o.order_id)
```
**Solution**: Correlated subquery - parent alias `o` should be visible inside.

### 4. UNION/INTERSECT
```sql
SELECT a.id FROM DBM.A a
UNION
SELECT b.id FROM DBM.B b
```
**Solution**: Each SELECT is at level 0 but different "branches". Need branch tracking.

---

## Summary

| Component | Responsibility |
|-----------|---------------|
| `SqlScopeParser` | Parse SQL into scope tree |
| `NestedSelectHandler` | Column completions in SELECT |
| `NestedFromHandler` | Schema/table completions in FROM |
| `NestedWhereHandler` | Column completions in WHERE |
| `ScopeResolver` | Find current scope from caret position |

This architecture ensures that:
1. ✅ Aliases are only visible within their scope
2. ✅ Subselect exposes only its SELECT columns to parent
3. ✅ Correlated subqueries can reference parent aliases
4. ✅ Multi-level nesting is properly handled

---

## Test Coverage

**110 automated tests** covering:
- Basic scope parsing (5 tests)
- Nested subselects (6 tests)
- Derived tables (4 tests)
- Correlated subqueries (3 tests)
- Multi-level nesting (4 tests)
- Alias extraction (6 tests)
- Exposed columns (6 tests)
- Scope at position (3 tests)
- Visibility (4 tests)
- Edge cases (10 tests)
- Advanced scenarios (10 tests)
- Real world queries (10 tests)
- Typing patterns (15 tests)
- DB2 specific (10 tests)
- Complex expressions (14 tests)

Run tests: `.\run_intellisense_tests.ps1`

---

*Last Updated: 2026-01-27*
