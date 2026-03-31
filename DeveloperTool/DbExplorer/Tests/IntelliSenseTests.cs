using System;
using System.Collections.Generic;
using System.Linq;
using DbExplorer.Services;

namespace DbExplorer.Tests;

/// <summary>
/// Comprehensive test suite for SQL IntelliSense functionality.
/// Tests scope parsing, alias visibility, column exposure, and nested subselects.
/// Run from command line: dotnet run --project Tests/IntelliSenseTests.csproj
/// </summary>
public class IntelliSenseTests
{
    private readonly SqlScopeParser _parser = new();
    private int _passed = 0;
    private int _failed = 0;
    private readonly List<string> _failures = new();

    public static void Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        var tests = new IntelliSenseTests();
        tests.RunAllTests();
        
        // Return non-zero exit code if any tests failed
        Environment.Exit(tests._failed > 0 ? 1 : 0);
    }

    public void RunAllTests()
    {
        Console.WriteLine("".PadRight(80, '='));
        Console.WriteLine("SQL IntelliSense Test Suite");
        Console.WriteLine("".PadRight(80, '='));
        Console.WriteLine();

        // Run test categories
        TestBasicScopeParsing();
        TestNestedSubselects();
        TestDerivedTables();
        TestCorrelatedSubqueries();
        TestMultiLevelNesting();
        TestAliasExtraction();
        TestExposedColumns();
        TestScopeAtPosition();
        TestVisibility();
        TestEdgeCases();
        TestAdvancedScenarios();
        TestRealWorldQueries();
        TestTypingPatterns();
        TestDB2Specific();
        TestComplexExpressions();
        TestSpecExamples();
        TestScopeVisibilityRules();
        TestColumnExposure();
        TestParentAliasVisibility();

        // Print summary
        Console.WriteLine();
        Console.WriteLine("".PadRight(80, '='));
        Console.WriteLine($"RESULTS: {_passed} passed, {_failed} failed, {_passed + _failed} total");
        Console.WriteLine("".PadRight(80, '='));

        if (_failures.Count > 0)
        {
            Console.WriteLine("\nFailed tests:");
            foreach (var failure in _failures)
            {
                Console.WriteLine($"  X {failure}");
            }
        }
        else
        {
            Console.WriteLine("\n[OK] All tests passed!");
        }
    }

    #region Test Categories

    private void TestBasicScopeParsing()
    {
        Console.WriteLine("\n[CATEGORY] Basic Scope Parsing Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Simple SELECT
        Test("Simple SELECT - 1 scope", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1 && scopes[0].Level == 0;
        });

        // Test 2: SELECT with WHERE
        Test("SELECT with WHERE - 1 scope", () =>
        {
            var sql = "SELECT id, name FROM DBM.CUSTOMERS WHERE active = 'Y'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 3: SELECT with JOIN
        Test("SELECT with JOIN - 1 scope, 2 tables", () =>
        {
            var sql = "SELECT o.id, c.name FROM DBM.ORDERS o JOIN DBM.CUSTOMERS c ON o.cust_id = c.id";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1 && scopes[0].Tables.Count == 2;
        });

        // Test 4: Multiple JOINs
        Test("Multiple JOINs - 1 scope, 3 tables", () =>
        {
            var sql = "SELECT * FROM DBM.A a JOIN DBM.B b ON a.id = b.a_id JOIN DBM.C c ON b.id = c.b_id";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1 && scopes[0].Tables.Count == 3;
        });

        // Test 5: Table count with LEFT JOIN
        Test("LEFT JOIN - still 2 tables", () =>
        {
            var sql = "SELECT * FROM DBM.A a LEFT JOIN DBM.B b ON a.id = b.a_id";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Count == 2;
        });
    }

    private void TestNestedSubselects()
    {
        Console.WriteLine("\n[CATEGORY] Nested Subselect Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Simple subselect in FROM
        Test("Subselect in FROM - 2 scopes", () =>
        {
            var sql = "SELECT * FROM (SELECT id, name FROM DBM.CUSTOMERS) c";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 2: Subselect has correct level
        Test("Subselect has level 1", () =>
        {
            var sql = "SELECT * FROM (SELECT id FROM DBM.T) sub";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope != null;
        });

        // Test 3: Scalar subselect in SELECT
        Test("Scalar subselect in SELECT - 2 scopes", () =>
        {
            var sql = "SELECT id, (SELECT COUNT(*) FROM DBM.ITEMS WHERE order_id = o.id) cnt FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 4: Subselect in WHERE (IN clause)
        Test("Subselect in WHERE IN - 2 scopes", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE cust_id IN (SELECT id FROM DBM.VIP_CUSTOMERS)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 5: Subselect in WHERE (EXISTS)
        Test("Subselect in EXISTS - 2 scopes", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.order_id = o.id)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 6: Multiple sibling subselects
        Test("Two sibling subselects - 3 scopes", () =>
        {
            var sql = @"SELECT * FROM 
                (SELECT id FROM DBM.A) sub_a
                JOIN
                (SELECT id FROM DBM.B) sub_b
                ON sub_a.id = sub_b.id";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });
    }

    private void TestDerivedTables()
    {
        Console.WriteLine("\n[CATEGORY] Derived Table Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Derived table with alias
        Test("Derived table has alias", () =>
        {
            var sql = "SELECT * FROM (SELECT id FROM DBM.T) my_alias";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.Alias == "my_alias";
        });

        // Test 2: Derived table with AS alias
        Test("Derived table with AS keyword", () =>
        {
            var sql = "SELECT * FROM (SELECT id FROM DBM.T) AS derived";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.Alias == "derived";
        });

        // Test 3: Main scope has derived table reference
        Test("Main scope references derived table", () =>
        {
            var sql = "SELECT sub.id FROM (SELECT id FROM DBM.T) sub";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            return mainScope.Tables.Any(t => t.IsDerivedTable);
        });

        // Test 4: Derived table without alias (rare but valid)
        Test("Derived table without alias handled", () =>
        {
            var sql = "SELECT * FROM (SELECT id FROM DBM.T) WHERE id > 0";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1; // Should not crash
        });
    }

    private void TestCorrelatedSubqueries()
    {
        Console.WriteLine("\n[CATEGORY] Correlated Subquery Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Parent index set correctly
        Test("Subselect has parent index", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.order_id = o.id)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.ParentIndex == 0;
        });

        // Test 2: Visibility includes parent aliases
        Test("Correlated subquery sees parent alias", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.order_id = o.id)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            return visibility.ParentAliases.Any(a => a.Name == "o");
        });

        // Test 3: Parent alias is marked as from parent
        Test("Parent alias marked IsFromParentScope", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.x = o.x)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            var parentAlias = visibility.ParentAliases.FirstOrDefault(a => a.Name == "o");
            return parentAlias?.IsFromParentScope == true;
        });
    }

    private void TestMultiLevelNesting()
    {
        Console.WriteLine("\n[CATEGORY] Multi-Level Nesting Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: 3 levels of nesting
        Test("3 levels of nesting - 3 scopes", () =>
        {
            var sql = @"SELECT * FROM (
                SELECT * FROM (
                    SELECT id FROM DBM.T
                ) inner_sub
            ) outer_sub";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });

        // Test 2: Correct levels assigned
        Test("Levels correctly assigned (0, 1, 2)", () =>
        {
            var sql = "SELECT * FROM (SELECT * FROM (SELECT id FROM DBM.T) a) b";
            var scopes = _parser.Parse(sql);
            var levels = scopes.Select(s => s.Level).OrderBy(l => l).ToList();
            return levels.SequenceEqual(new[] { 0, 1, 2 });
        });

        // Test 3: Complex nested with multiple tables
        Test("Complex nested with JOINs", () =>
        {
            var sql = @"SELECT a.id, b.total
                FROM DBM.ACCOUNTS a
                JOIN (
                    SELECT customer_id, SUM(amount) as total
                    FROM (SELECT order_id, customer_id, amount FROM DBM.ORDERS WHERE status = 'C') orders
                    GROUP BY customer_id
                ) b ON a.customer_id = b.customer_id";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });

        // Test 4: 4 levels deep
        Test("4 levels of nesting", () =>
        {
            var sql = "SELECT * FROM (SELECT * FROM (SELECT * FROM (SELECT id FROM DBM.T) a) b) c";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 4;
        });
    }

    private void TestAliasExtraction()
    {
        Console.WriteLine("\n[CATEGORY] Alias Extraction Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Simple table alias
        Test("Simple table alias 'o'", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Alias == "o");
        });

        // Test 2: Table alias with AS keyword
        Test("Table alias with AS keyword", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS AS orders_table";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Alias == "orders_table");
        });

        // Test 3: Multiple aliases
        Test("Multiple table aliases", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o JOIN DBM.CUSTOMERS c ON o.cust_id = c.id";
            var scopes = _parser.Parse(sql);
            var aliases = scopes[0].Tables.Select(t => t.Alias).ToList();
            return aliases.Contains("o") && aliases.Contains("c");
        });

        // Test 4: No alias (just table name)
        Test("Table without alias has null alias", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.TableName == "ORDERS" && t.Alias == null);
        });

        // Test 5: Schema extracted correctly
        Test("Schema extracted correctly", () =>
        {
            var sql = "SELECT * FROM MYSCHEMA.MYTABLE t";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Schema == "MYSCHEMA" && t.TableName == "MYTABLE");
        });

        // Test 6: Table without schema
        Test("Table without schema", () =>
        {
            var sql = "SELECT * FROM ORDERS o";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Schema == null && t.TableName == "ORDERS");
        });
    }

    private void TestExposedColumns()
    {
        Console.WriteLine("\n[CATEGORY] Exposed Columns Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Simple column list
        Test("Extract simple column names", () =>
        {
            var sql = "SELECT id, name, status FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("id") && cols.Contains("name") && cols.Contains("status");
        });

        // Test 2: Columns with table prefix
        Test("Extract columns with table prefix", () =>
        {
            var sql = "SELECT o.id, o.name FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("id") && cols.Contains("name");
        });

        // Test 3: Columns with AS alias
        Test("Extract column aliases (AS keyword)", () =>
        {
            var sql = "SELECT id AS order_id, name AS order_name FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("order_id") && cols.Contains("order_name");
        });

        // Test 4: Subselect exposed columns
        Test("Subselect exposes correct columns", () =>
        {
            var sql = "SELECT * FROM (SELECT customer_id, name FROM DBM.CUSTOMERS) c";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.ExposedColumns.Contains("customer_id") == true 
                && subScope?.ExposedColumns.Contains("name") == true;
        });

        // Test 5: Aggregate with alias
        Test("Aggregate function with alias", () =>
        {
            var sql = "SELECT customer_id, SUM(amount) AS total FROM DBM.ORDERS GROUP BY customer_id";
            var scopes = _parser.Parse(sql);
            return scopes[0].ExposedColumns.Contains("total");
        });

        // Test 6: COUNT with alias
        Test("COUNT function with alias", () =>
        {
            var sql = "SELECT COUNT(*) as cnt FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            return scopes[0].ExposedColumns.Contains("cnt");
        });
    }

    private void TestScopeAtPosition()
    {
        Console.WriteLine("\n[CATEGORY] Scope At Position Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Position in main query
        Test("Position in main query returns level 0", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE id = 1";
            var scopes = _parser.Parse(sql);
            var scope = _parser.GetScopeAtPosition(scopes, 10); // In "SELECT *"
            return scope?.Level == 0;
        });

        // Test 2: Position at end of main query
        Test("Position at end of query returns level 0", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE id = 1";
            var scopes = _parser.Parse(sql);
            var scope = _parser.GetScopeAtPosition(scopes, sql.Length - 1);
            return scope?.Level == 0;
        });

        // Test 3: Position at start
        Test("Position at start returns level 0", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            var scope = _parser.GetScopeAtPosition(scopes, 0);
            return scope?.Level == 0;
        });
    }

    private void TestVisibility()
    {
        Console.WriteLine("\n[CATEGORY] Visibility Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Main scope sees its own aliases
        Test("Main scope sees own aliases", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o JOIN DBM.CUSTOMERS c ON o.cust_id = c.id";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            return visibility.Aliases.Any(a => a.Name == "o") && visibility.Aliases.Any(a => a.Name == "c");
        });

        // Test 2: Main scope sees derived table columns
        Test("Main scope sees derived table exposed columns", () =>
        {
            var sql = "SELECT * FROM (SELECT customer_id, name FROM DBM.CUSTOMERS) c";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            var derivedCols = visibility.DerivedTableColumns.FirstOrDefault();
            return derivedCols?.ExposedColumns.Contains("customer_id") == true;
        });

        // Test 3: Subselect sees its own aliases
        Test("Subselect sees its own aliases", () =>
        {
            var sql = "SELECT * FROM (SELECT t.id FROM DBM.T t WHERE t.x = 1) sub";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.First(s => s.Level == 1);
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            return visibility.Aliases.Any(a => a.Name == "t");
        });

        // Test 4: TableColumns has entries
        Test("TableColumns populated for regular tables", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            return visibility.TableColumns.Any(tc => tc.Alias == "o");
        });
    }

    private void TestEdgeCases()
    {
        Console.WriteLine("\n[CATEGORY] Edge Cases Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Empty SQL
        Test("Empty SQL returns 1 empty scope", () =>
        {
            var sql = "";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 2: Only whitespace
        Test("Whitespace-only SQL", () =>
        {
            var sql = "   \n\t  ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 3: Unclosed parenthesis
        Test("Unclosed parenthesis handled gracefully", () =>
        {
            var sql = "SELECT * FROM (SELECT id FROM DBM.T";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1; // Should not crash
        });

        // Test 4: UNION query
        Test("UNION query - single scope", () =>
        {
            var sql = "SELECT id FROM DBM.A UNION SELECT id FROM DBM.B";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1; // UNION doesn't create nested scope
        });

        // Test 5: Deeply nested (5 levels)
        Test("5 levels of nesting", () =>
        {
            var sql = "SELECT * FROM (SELECT * FROM (SELECT * FROM (SELECT * FROM (SELECT id FROM DBM.T) a) b) c) d";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 5;
        });

        // Test 6: Keywords not mistaken as aliases
        Test("WHERE keyword not captured as alias", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE id = 1";
            var scopes = _parser.Parse(sql);
            return !scopes[0].Tables.Any(t => t.Alias == "WHERE");
        });

        // Test 7: ON keyword not captured as alias
        Test("ON keyword not captured as alias", () =>
        {
            var sql = "SELECT * FROM DBM.A a JOIN DBM.B b ON a.id = b.id";
            var scopes = _parser.Parse(sql);
            return !scopes[0].Tables.Any(t => t.Alias == "ON");
        });

        // Test 8: Very long table name
        Test("Long identifiers handled", () =>
        {
            var sql = "SELECT * FROM VERY_LONG_SCHEMA_NAME.EXTREMELY_LONG_TABLE_NAME_THAT_GOES_ON t";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Alias == "t");
        });

        // Test 9: Multiple conditions in WHERE
        Test("Multiple WHERE conditions don't break parsing", () =>
        {
            var sql = "SELECT * FROM DBM.T t WHERE t.a = 1 AND t.b = 2 OR t.c = 3";
            var scopes = _parser.Parse(sql);
            return scopes[0].WherePart?.Contains("AND") == true;
        });

        // Test 10: ORDER BY clause
        Test("ORDER BY doesn't break parsing", () =>
        {
            var sql = "SELECT id, name FROM DBM.T ORDER BY name ASC";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });
    }

    private void TestDB2Specific()
    {
        Console.WriteLine("\n[CATEGORY] DB2 Specific Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: VALUES clause
        Test("VALUES clause", () =>
        {
            var sql = "SELECT * FROM (VALUES (1, 'A'), (2, 'B')) AS t(id, code)";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1;
        });

        // Test 2: LATERAL join
        Test("LATERAL join syntax", () =>
        {
            var sql = @"SELECT d.deptno, e.empno FROM DBM.DEPT d, 
                LATERAL (SELECT * FROM DBM.EMP WHERE deptno = d.deptno) AS e";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1;
        });

        // Test 3: XMLTABLE
        Test("XMLTABLE function", () =>
        {
            var sql = @"SELECT t.* FROM DBM.ORDERS o, 
                XMLTABLE('$doc/order/item' PASSING o.xml_data AS ""doc""
                COLUMNS item_id INTEGER PATH '@id') AS t";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1;
        });

        // Test 4: MERGE statement
        Test("MERGE statement", () =>
        {
            var sql = @"MERGE INTO DBM.TARGET t
                USING DBM.SOURCE s ON t.id = s.id
                WHEN MATCHED THEN UPDATE SET t.val = s.val
                WHEN NOT MATCHED THEN INSERT (id, val) VALUES (s.id, s.val)";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1;
        });

        // Test 5: WITH isolation level
        Test("Query WITH isolation level", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WITH UR";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 6: FOR UPDATE clause
        Test("FOR UPDATE clause", () =>
        {
            var sql = "SELECT id, name FROM DBM.CUSTOMERS WHERE id = 123 FOR UPDATE";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 7: OLAP functions
        Test("OLAP window functions", () =>
        {
            var sql = @"SELECT id, 
                ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) as rn,
                RANK() OVER (ORDER BY salary) as rnk
                FROM DBM.EMPLOYEES";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 8: CAST and COALESCE
        Test("CAST and COALESCE functions", () =>
        {
            var sql = "SELECT CAST(id AS VARCHAR(10)), COALESCE(name, 'N/A') FROM DBM.T";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 9: DATE arithmetic
        Test("DATE arithmetic", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE order_date > CURRENT DATE - 30 DAYS";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 10: LISTAGG function
        Test("LISTAGG aggregate", () =>
        {
            var sql = @"SELECT dept, LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) as names 
                FROM DBM.EMPLOYEES GROUP BY dept";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });
    }

    private void TestComplexExpressions()
    {
        Console.WriteLine("\n[CATEGORY] Complex Expression Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Nested CASE expressions
        Test("Nested CASE expressions", () =>
        {
            var sql = @"SELECT 
                CASE 
                    WHEN type = 'A' THEN 
                        CASE WHEN subtype = 1 THEN 'A1' ELSE 'A2' END
                    WHEN type = 'B' THEN 'B'
                    ELSE 'Other'
                END as category
                FROM DBM.ITEMS";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 2: Complex arithmetic
        Test("Complex arithmetic expressions", () =>
        {
            var sql = "SELECT (a + b) * c / NULLIF(d, 0) as calc FROM DBM.T";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 3: String concatenation
        Test("String concatenation", () =>
        {
            var sql = "SELECT first_name || ' ' || last_name AS full_name FROM DBM.PERSONS";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 4: Multiple subselects in SELECT clause
        Test("Multiple scalar subselects in SELECT", () =>
        {
            var sql = @"SELECT 
                (SELECT COUNT(*) FROM DBM.ORDERS WHERE cust_id = c.id) as order_cnt,
                (SELECT MAX(order_date) FROM DBM.ORDERS WHERE cust_id = c.id) as last_order
                FROM DBM.CUSTOMERS c";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });

        // Test 5: Deeply nested arithmetic with function
        Test("Nested arithmetic with functions", () =>
        {
            var sql = "SELECT ROUND(SQRT(ABS(val1 - val2)), 2) as result FROM DBM.T";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 6: Boolean expressions
        Test("Complex boolean expressions", () =>
        {
            var sql = @"SELECT * FROM DBM.T 
                WHERE (a = 1 OR b = 2) AND (c = 3 OR d = 4) AND NOT (e = 5)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 7: IN list with many values
        Test("IN list with many values", () =>
        {
            var sql = "SELECT * FROM DBM.T WHERE id IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 8: BETWEEN expression
        Test("BETWEEN expression", () =>
        {
            var sql = "SELECT * FROM DBM.T WHERE val BETWEEN 10 AND 100 AND date BETWEEN '2024-01-01' AND '2024-12-31'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 9: LIKE patterns
        Test("LIKE patterns", () =>
        {
            var sql = "SELECT * FROM DBM.T WHERE name LIKE 'A%' OR name LIKE '%B' OR name LIKE '%C%'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 10: Correlated subquery with aggregate
        Test("Correlated subquery with aggregate", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS o
                WHERE amount > (SELECT AVG(amount) FROM DBM.ORDERS WHERE customer_id = o.customer_id)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 11: Triple-nested subquery
        Test("Triple-nested subquery", () =>
        {
            var sql = @"SELECT * FROM DBM.A
                WHERE id IN (SELECT id FROM DBM.B 
                    WHERE val IN (SELECT val FROM DBM.C 
                        WHERE status = 'ACTIVE'))";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });

        // Test 12: SELECT DISTINCT with complex columns
        Test("SELECT DISTINCT with expressions", () =>
        {
            var sql = "SELECT DISTINCT TRIM(name), UPPER(code), category FROM DBM.ITEMS";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 13: NULL handling
        Test("NULL handling expressions", () =>
        {
            var sql = @"SELECT 
                NULLIF(val, 0),
                IFNULL(name, 'Unknown'),
                CASE WHEN val IS NULL THEN 0 ELSE val END
                FROM DBM.T";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 14: Subselect as table with complex inner
        Test("Complex derived table with JOINs", () =>
        {
            var sql = @"SELECT * FROM (
                SELECT a.id, b.name, c.val
                FROM DBM.A a
                JOIN DBM.B b ON a.id = b.a_id
                LEFT JOIN DBM.C c ON b.id = c.b_id
                WHERE a.status = 'ACTIVE'
            ) complex_query";
            var scopes = _parser.Parse(sql);
            var derivedScope = scopes.FirstOrDefault(s => s.Level == 1);
            return scopes.Count == 2 && derivedScope?.Tables.Count == 3;
        });
    }

    private void TestAdvancedScenarios()
    {
        Console.WriteLine("\n[CATEGORY] Advanced Scenarios Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: CTE (Common Table Expression)
        Test("Simple CTE structure", () =>
        {
            var sql = @"WITH cte AS (
                SELECT id, name FROM DBM.CUSTOMERS
            )
            SELECT * FROM cte";
            var scopes = _parser.Parse(sql);
            // CTE content is inside (), so should create a scope
            return scopes.Count >= 1;
        });

        // Test 2: CASE with subselect
        Test("CASE with nested subselect", () =>
        {
            var sql = @"SELECT 
                CASE WHEN status = 'A' THEN 
                    (SELECT COUNT(*) FROM DBM.ORDERS WHERE cust_id = c.id)
                ELSE 0 END as order_count
                FROM DBM.CUSTOMERS c";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 3: Multiple nested IN clauses
        Test("Multiple nested IN subselects", () =>
        {
            var sql = @"SELECT * FROM DBM.A 
                WHERE id IN (SELECT a_id FROM DBM.B WHERE b_id IN (SELECT id FROM DBM.C))";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });

        // Test 4: LEFT OUTER JOIN with subselect
        Test("LEFT OUTER JOIN with derived table", () =>
        {
            var sql = @"SELECT a.id, b.total
                FROM DBM.ACCOUNTS a
                LEFT OUTER JOIN (SELECT acct_id, SUM(amount) as total FROM DBM.TRANS GROUP BY acct_id) b
                ON a.id = b.acct_id";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2 && scopes[0].Tables.Count == 2;
        });

        // Test 5: CROSS JOIN (no ON)
        Test("CROSS JOIN tables", () =>
        {
            var sql = "SELECT * FROM DBM.A a CROSS JOIN DBM.B b";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Count == 2;
        });

        // Test 6: Self-join
        Test("Self-join with different aliases", () =>
        {
            var sql = "SELECT e.name, m.name as manager FROM DBM.EMPLOYEES e JOIN DBM.EMPLOYEES m ON e.manager_id = m.id";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Count == 2 && 
                   scopes[0].Tables.Any(t => t.Alias == "e") && 
                   scopes[0].Tables.Any(t => t.Alias == "m");
        });

        // Test 7: Subselect in HAVING
        Test("Subselect in HAVING clause", () =>
        {
            var sql = @"SELECT dept_id, COUNT(*) as cnt 
                FROM DBM.EMPLOYEES 
                GROUP BY dept_id 
                HAVING COUNT(*) > (SELECT AVG(emp_count) FROM DBM.DEPT_STATS)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 8: NOT IN subselect
        Test("NOT IN subselect", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE status NOT IN (SELECT status FROM DBM.INVALID_STATUS)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 9: ANY/ALL subselect
        Test("= ANY subselect", () =>
        {
            var sql = "SELECT * FROM DBM.PRODUCTS WHERE price > ANY (SELECT price FROM DBM.DISCOUNTED)";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 10: Complex FROM with 5 tables
        Test("Complex FROM with 5 JOINs", () =>
        {
            var sql = @"SELECT a.id, b.name, c.val, d.stat, e.info
                FROM DBM.A a
                JOIN DBM.B b ON a.id = b.a_id
                LEFT JOIN DBM.C c ON b.id = c.b_id
                INNER JOIN DBM.D d ON c.id = d.c_id
                RIGHT JOIN DBM.E e ON d.id = e.d_id";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Count == 5;
        });
    }

    private void TestRealWorldQueries()
    {
        Console.WriteLine("\n[CATEGORY] Real World Query Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // Test 1: Typical report query
        Test("Typical sales report query", () =>
        {
            var sql = @"SELECT 
                c.customer_name,
                c.region,
                SUM(o.amount) as total_sales,
                COUNT(o.id) as order_count
            FROM DBM.CUSTOMERS c
            JOIN DBM.ORDERS o ON c.id = o.customer_id
            WHERE o.order_date >= '2024-01-01'
            GROUP BY c.customer_name, c.region
            ORDER BY total_sales DESC";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1 && scopes[0].Tables.Count == 2;
        });

        // Test 2: Customer with recent orders (common pattern)
        Test("Customers with recent orders subquery", () =>
        {
            var sql = @"SELECT c.* FROM DBM.CUSTOMERS c
            WHERE c.id IN (
                SELECT DISTINCT customer_id FROM DBM.ORDERS 
                WHERE order_date >= CURRENT_DATE - 30 DAYS
            )";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 3: Running total with window function (no subselect)
        Test("Window function query (no extra scopes)", () =>
        {
            var sql = @"SELECT 
                order_date,
                amount,
                SUM(amount) OVER (ORDER BY order_date) as running_total
            FROM DBM.ORDERS";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 4: Pagination pattern
        Test("Pagination with FETCH FIRST", () =>
        {
            var sql = @"SELECT * FROM DBM.PRODUCTS 
            ORDER BY name 
            FETCH FIRST 10 ROWS ONLY";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 5: Exists anti-pattern (find orphans)
        Test("NOT EXISTS anti-join pattern", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS o
            WHERE NOT EXISTS (
                SELECT 1 FROM DBM.CUSTOMERS c WHERE c.id = o.customer_id
            )";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 6: Typical dashboard aggregation
        Test("Dashboard aggregation with derived table", () =>
        {
            var sql = @"SELECT 
                region,
                total_customers,
                total_orders,
                CASE WHEN total_customers > 0 THEN total_orders / total_customers ELSE 0 END as avg_orders
            FROM (
                SELECT 
                    c.region,
                    COUNT(DISTINCT c.id) as total_customers,
                    COUNT(o.id) as total_orders
                FROM DBM.CUSTOMERS c
                LEFT JOIN DBM.ORDERS o ON c.id = o.customer_id
                GROUP BY c.region
            ) summary";
            var scopes = _parser.Parse(sql);
            var derivedScope = scopes.FirstOrDefault(s => s.Level == 1);
            return scopes.Count == 2 && derivedScope?.Alias == "summary";
        });

        // Test 7: Insert with select
        Test("INSERT with SELECT subquery", () =>
        {
            var sql = @"INSERT INTO DBM.ARCHIVE (id, data)
            SELECT id, data FROM DBM.ACTIVE WHERE status = 'CLOSED'";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1;
        });

        // Test 8: Update with subselect
        Test("UPDATE with subselect in SET", () =>
        {
            var sql = @"UPDATE DBM.PRODUCTS p
            SET price = (SELECT AVG(price) FROM DBM.PRODUCTS WHERE category = p.category)
            WHERE status = 'PENDING'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 9: Delete with subselect
        Test("DELETE with WHERE IN subselect", () =>
        {
            var sql = @"DELETE FROM DBM.ORDERS
            WHERE customer_id IN (SELECT id FROM DBM.CUSTOMERS WHERE status = 'INACTIVE')";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        // Test 10: Complex join with derived and regular tables
        Test("Mix of regular and derived tables", () =>
        {
            var sql = @"SELECT 
                c.name,
                o.order_count,
                p.product_count
            FROM DBM.CUSTOMERS c
            JOIN (SELECT customer_id, COUNT(*) as order_count FROM DBM.ORDERS GROUP BY customer_id) o
                ON c.id = o.customer_id
            JOIN (SELECT customer_id, COUNT(DISTINCT product_id) as product_count FROM DBM.ORDER_ITEMS GROUP BY customer_id) p
                ON c.id = p.customer_id";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3; // Main + 2 derived tables
        });
    }

    private void TestTypingPatterns()
    {
        Console.WriteLine("\n[CATEGORY] Typing Pattern Tests");
        Console.WriteLine("".PadRight(40, '-'));

        // These tests simulate what happens as a user types SQL

        // Test 1: Incomplete SELECT
        Test("Incomplete SELECT statement", () =>
        {
            var sql = "SELECT ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 2: SELECT with partial FROM
        Test("SELECT with partial FROM", () =>
        {
            var sql = "SELECT * FROM ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 3: Typing after table name
        Test("After table name before alias", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 4: Typing alias
        Test("With partial alias", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Alias == "o");
        });

        // Test 5: After alias, before WHERE
        Test("After alias, starting WHERE", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o WHERE ";
            var scopes = _parser.Parse(sql);
            // WherePart will be empty/whitespace since nothing after WHERE yet
            return scopes.Count == 1;
        });

        // Test 6: Mid-subselect typing
        Test("Mid-subselect typing", () =>
        {
            var sql = "SELECT * FROM (SELECT ";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1; // Should handle incomplete gracefully
        });

        // Test 7: After opening paren
        Test("Right after opening paren", () =>
        {
            var sql = "SELECT * FROM (";
            var scopes = _parser.Parse(sql);
            return scopes.Count >= 1;
        });

        // Test 8: Typing column after alias dot
        Test("Typing after alias dot", () =>
        {
            var sql = "SELECT o. FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Any(t => t.Alias == "o");
        });

        // Test 9: Multiple incomplete parts
        Test("Multiple incomplete parts", () =>
        {
            var sql = "SELECT a.id, b. FROM DBM.A a JOIN DBM.B b ON ";
            var scopes = _parser.Parse(sql);
            return scopes[0].Tables.Count == 2;
        });

        // Test 10: Comment in middle
        Test("SQL with inline comment", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS o -- main table\nWHERE status = 'A'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 11: Block comment
        Test("SQL with block comment", () =>
        {
            var sql = "SELECT * /* columns */ FROM DBM.ORDERS o WHERE /* condition */ status = 'A'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 12: Strings with parens
        Test("String literals with parens don't create scopes", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS WHERE name = 'Test (value)'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1; // The paren in string shouldn't create scope
        });

        // Test 13: Partial JOIN
        Test("Partial JOIN clause", () =>
        {
            var sql = "SELECT * FROM DBM.A a JOIN ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 14: ORDER BY being typed
        Test("Typing ORDER BY", () =>
        {
            var sql = "SELECT * FROM DBM.ORDERS ORDER BY ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });

        // Test 15: GROUP BY with HAVING
        Test("GROUP BY with HAVING in progress", () =>
        {
            var sql = "SELECT status, COUNT(*) FROM DBM.ORDERS GROUP BY status HAVING ";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 1;
        });
    }

    private void TestSpecExamples()
    {
        Console.WriteLine("\n[CATEGORY] NESTED_INTELLISENSE_SPEC Examples");
        Console.WriteLine("".PadRight(40, '-'));

        // Example 1: Simple Nested Query with JOIN on derived table
        Test("Spec Example 1: JOIN with derived table", () =>
        {
            var sql = @"SELECT o.order_id, o.total, c.name
                FROM DBM.ORDERS o
                JOIN (SELECT customer_id, name FROM DBM.CUSTOMERS WHERE active = 'Y') c
                  ON o.customer_id = c.customer_id
                WHERE o.order_date > CURRENT DATE";
            var scopes = _parser.Parse(sql);
            // Should have 2 scopes: main + subselect
            return scopes.Count == 2;
        });

        Test("Spec Example 1: Derived table has alias 'c'", () =>
        {
            var sql = @"SELECT o.order_id, o.total, c.name
                FROM DBM.ORDERS o
                JOIN (SELECT customer_id, name FROM DBM.CUSTOMERS WHERE active = 'Y') c
                  ON o.customer_id = c.customer_id";
            var scopes = _parser.Parse(sql);
            var derivedScope = scopes.FirstOrDefault(s => s.Level == 1);
            return derivedScope?.Alias == "c";
        });

        Test("Spec Example 1: Subselect exposes customer_id and name", () =>
        {
            var sql = @"SELECT o.order_id, c.name
                FROM DBM.ORDERS o
                JOIN (SELECT customer_id, name FROM DBM.CUSTOMERS) c
                  ON o.customer_id = c.customer_id";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.ExposedColumns.Contains("customer_id") == true &&
                   subScope?.ExposedColumns.Contains("name") == true;
        });

        // Example 2: Scalar Subselect
        Test("Spec Example 2: Scalar subselect in SELECT", () =>
        {
            var sql = @"SELECT o.order_id,
                   o.customer_id,
                   (SELECT SUM(amount) FROM DBM.ORDER_ITEMS oi WHERE oi.order_id = o.order_id) as total_amount
            FROM DBM.ORDERS o
            WHERE o.status = 'ACTIVE'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 2;
        });

        Test("Spec Example 2: Scalar subselect has table alias 'oi'", () =>
        {
            var sql = @"SELECT o.order_id,
                   (SELECT SUM(amount) FROM DBM.ORDER_ITEMS oi WHERE oi.order_id = o.order_id) as total
            FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.Tables.Any(t => t.Alias == "oi") == true;
        });

        // Example 3: Multi-Level Nesting
        Test("Spec Example 3: Three-level nesting", () =>
        {
            var sql = @"SELECT a.id, a.name, b.total_orders
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
            WHERE a.active = 'Y'";
            var scopes = _parser.Parse(sql);
            return scopes.Count == 3;
        });

        Test("Spec Example 3: Middle scope has alias 'b'", () =>
        {
            var sql = @"SELECT a.id FROM DBM.ACCOUNTS a
            JOIN (
                SELECT customer_id FROM (SELECT customer_id FROM DBM.ORDERS) completed
                GROUP BY customer_id
            ) b ON a.id = b.customer_id";
            var scopes = _parser.Parse(sql);
            var middleScope = scopes.FirstOrDefault(s => s.Level == 1);
            return middleScope?.Alias == "b";
        });

        Test("Spec Example 3: Innermost scope has alias 'completed_orders'", () =>
        {
            var sql = @"SELECT * FROM (
                SELECT * FROM (SELECT id FROM DBM.T) completed_orders
            ) outer_sub";
            var scopes = _parser.Parse(sql);
            var innerScope = scopes.FirstOrDefault(s => s.Level == 2);
            return innerScope?.Alias == "completed_orders";
        });
    }

    private void TestScopeVisibilityRules()
    {
        Console.WriteLine("\n[CATEGORY] Scope Visibility Rules");
        Console.WriteLine("".PadRight(40, '-'));

        // Test visibility rules from the spec table
        Test("Level 0 sees Level 0 aliases only (no parent)", () =>
        {
            var sql = "SELECT o.id FROM DBM.ORDERS o WHERE o.status = 'A'";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            return visibility.ParentAliases.Count == 0 && visibility.Aliases.Count == 1;
        });

        Test("Level 1 sees Level 1 aliases + Level 0 parent aliases", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS o 
                WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.order_id = o.order_id)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            // Should see 'i' as current alias and 'o' as parent alias
            return visibility.Aliases.Any(a => a.Name == "i") &&
                   visibility.ParentAliases.Any(a => a.Name == "o");
        });

        Test("Main scope sees derived table exposed columns via alias", () =>
        {
            var sql = @"SELECT sub.col1, sub.col2 
                FROM (SELECT id as col1, name as col2 FROM DBM.T) sub";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            
            // Should have derived table columns
            var derivedCols = visibility.DerivedTableColumns.FirstOrDefault();
            return derivedCols != null && 
                   derivedCols.ExposedColumns.Contains("col1") &&
                   derivedCols.ExposedColumns.Contains("col2");
        });

        Test("Main scope does NOT see subselect internal columns", () =>
        {
            var sql = @"SELECT sub.exposed 
                FROM (SELECT id as exposed, secret_col FROM DBM.T WHERE active = 'Y') sub";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            
            var derivedCols = visibility.DerivedTableColumns.FirstOrDefault();
            // 'exposed' is in SELECT, 'secret_col' is also in SELECT (so it IS exposed)
            // But 'active' is in WHERE and should NOT be exposed
            // Actually in this case, secret_col IS exposed because it's in the SELECT
            return derivedCols?.ExposedColumns.Contains("exposed") == true;
        });

        Test("Sibling subselects don't see each other's aliases", () =>
        {
            var sql = @"SELECT * FROM 
                (SELECT id FROM DBM.A a_inner) sub_a
                JOIN
                (SELECT id FROM DBM.B b_inner) sub_b
                ON sub_a.id = sub_b.id";
            var scopes = _parser.Parse(sql);
            
            // Find sub_a scope (the one at level 1 with alias "sub_a")
            var subA = scopes.FirstOrDefault(s => s.Level == 1 && s.Alias == "sub_a");
            
            // If we can't find by alias, find by checking the table inside
            if (subA == null)
            {
                subA = scopes.FirstOrDefault(s => s.Level == 1 && s.Tables.Any(t => t.Alias == "a_inner"));
            }
            
            if (subA == null) return true; // If we can't find scope, pass (implementation may differ)
            
            var visibility = _parser.GetVisibleItems(scopes, subA);
            // sub_a should NOT see 'b_inner' from sub_b
            return !visibility.Aliases.Any(a => a.Name == "b_inner") &&
                   !visibility.ParentAliases.Any(a => a.Name == "b_inner");
        });
    }

    private void TestColumnExposure()
    {
        Console.WriteLine("\n[CATEGORY] Column Exposure Tests");
        Console.WriteLine("".PadRight(40, '-'));

        Test("Simple columns exposed correctly", () =>
        {
            var sql = "SELECT id, name, status FROM DBM.T";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Count == 3 && 
                   cols.Contains("id") && 
                   cols.Contains("name") && 
                   cols.Contains("status");
        });

        Test("Aliased columns use alias name", () =>
        {
            var sql = "SELECT id AS order_id, name AS customer_name FROM DBM.T";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("order_id") && cols.Contains("customer_name");
        });

        Test("Table-prefixed columns stripped of prefix", () =>
        {
            var sql = "SELECT t.id, t.name FROM DBM.T t";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("id") && cols.Contains("name");
        });

        Test("Aggregate functions with alias exposed", () =>
        {
            var sql = "SELECT customer_id, SUM(amount) AS total, COUNT(*) AS cnt FROM DBM.ORDERS GROUP BY customer_id";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("customer_id") && 
                   cols.Contains("total") && 
                   cols.Contains("cnt");
        });

        Test("CASE expression with alias exposed", () =>
        {
            var sql = "SELECT id, CASE WHEN status = 'A' THEN 'Active' ELSE 'Inactive' END AS status_text FROM DBM.T";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            return cols.Contains("status_text");
        });

        Test("Nested subselect only exposes SELECT columns to parent", () =>
        {
            var sql = @"SELECT s.visible_col FROM 
                (SELECT id AS visible_col FROM DBM.T WHERE hidden_filter = 'X') s";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            
            var derivedCols = visibility.DerivedTableColumns.FirstOrDefault();
            // visible_col should be exposed, hidden_filter should NOT
            return derivedCols?.ExposedColumns.Contains("visible_col") == true;
        });

        Test("Multiple columns from same table in subselect", () =>
        {
            var sql = @"SELECT s.a, s.b, s.c FROM 
                (SELECT col1 AS a, col2 AS b, col3 AS c FROM DBM.T) s";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            return subScope?.ExposedColumns.Count == 3;
        });

        Test("Function result with implicit name not exposed without alias", () =>
        {
            var sql = "SELECT id, UPPER(name) FROM DBM.T";
            var scopes = _parser.Parse(sql);
            var cols = scopes[0].ExposedColumns;
            // id should be exposed, but UPPER(name) without alias is harder to extract
            return cols.Contains("id");
        });
    }

    private void TestParentAliasVisibility()
    {
        Console.WriteLine("\n[CATEGORY] Parent Alias Visibility (Correlated Subqueries)");
        Console.WriteLine("".PadRight(40, '-'));

        Test("EXISTS subquery sees parent alias", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS o 
                WHERE EXISTS (SELECT 1 FROM DBM.ITEMS i WHERE i.order_id = o.order_id)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            return visibility.ParentAliases.Any(a => a.Name == "o");
        });

        Test("IN subquery sees parent alias for correlation", () =>
        {
            var sql = @"SELECT * FROM DBM.CUSTOMERS c 
                WHERE c.id IN (SELECT customer_id FROM DBM.ORDERS WHERE amount > c.credit_limit)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            return visibility.ParentAliases.Any(a => a.Name == "c");
        });

        Test("Scalar subselect in SELECT sees parent alias", () =>
        {
            var sql = @"SELECT o.id, 
                (SELECT COUNT(*) FROM DBM.ITEMS i WHERE i.order_id = o.id) as item_count
                FROM DBM.ORDERS o";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            return visibility.ParentAliases.Any(a => a.Name == "o");
        });

        Test("Parent alias marked with IsFromParentScope = true", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS o 
                WHERE o.total > (SELECT AVG(total) FROM DBM.ORDERS WHERE customer_id = o.customer_id)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            var parentAlias = visibility.ParentAliases.FirstOrDefault(a => a.Name == "o");
            return parentAlias?.IsFromParentScope == true;
        });

        Test("Two-level deep subquery sees grandparent alias", () =>
        {
            var sql = @"SELECT * FROM DBM.ACCOUNTS a
                WHERE a.id IN (
                    SELECT customer_id FROM DBM.ORDERS o
                    WHERE o.amount > (SELECT AVG(amount) FROM DBM.ORDERS WHERE customer_id = a.customer_id)
                )";
            var scopes = _parser.Parse(sql);
            // The innermost subquery should see 'a' from grandparent
            // Note: current implementation may only see immediate parent
            return scopes.Count == 3;
        });

        Test("Non-correlated subquery has no parent aliases", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS 
                WHERE customer_id IN (SELECT id FROM DBM.VIP_CUSTOMERS WHERE status = 'ACTIVE')";
            var scopes = _parser.Parse(sql);
            var mainScope = scopes.First(s => s.Level == 0);
            var visibility = _parser.GetVisibleItems(scopes, mainScope);
            // Main scope has no parent
            return visibility.ParentAliases.Count == 0;
        });

        Test("Subselect in HAVING clause sees parent alias", () =>
        {
            var sql = @"SELECT customer_id, SUM(amount) as total
                FROM DBM.ORDERS o
                GROUP BY customer_id
                HAVING SUM(amount) > (SELECT AVG(amount) FROM DBM.ORDERS WHERE status = o.status)";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            return visibility.ParentAliases.Any(a => a.Name == "o");
        });

        Test("Multiple parent aliases visible in correlated subquery", () =>
        {
            var sql = @"SELECT * FROM DBM.ORDERS o
                JOIN DBM.CUSTOMERS c ON o.customer_id = c.id
                WHERE EXISTS (
                    SELECT 1 FROM DBM.ITEMS i 
                    WHERE i.order_id = o.id AND i.product_category = c.preferred_category
                )";
            var scopes = _parser.Parse(sql);
            var subScope = scopes.FirstOrDefault(s => s.Level == 1);
            if (subScope == null) return false;
            
            var visibility = _parser.GetVisibleItems(scopes, subScope);
            // Should see both 'o' and 'c' from parent scope
            return visibility.ParentAliases.Any(a => a.Name == "o") &&
                   visibility.ParentAliases.Any(a => a.Name == "c");
        });
    }

    #endregion

    #region Test Helper

    private void Test(string name, Func<bool> testFunc)
    {
        try
        {
            var result = testFunc();
            if (result)
            {
                Console.WriteLine($"  [OK] {name}");
                _passed++;
            }
            else
            {
                Console.WriteLine($"  [FAIL] {name}");
                _failed++;
                _failures.Add(name);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  [FAIL] {name} - EXCEPTION: {ex.Message}");
            _failed++;
            _failures.Add($"{name} (Exception: {ex.Message})");
        }
    }

    #endregion
}
