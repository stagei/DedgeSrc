using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Linq;

public static class SqlTableExtractorOld1
{
    public class TableColumnInfo
    {
        public string TableName { get; set; } = string.Empty;
        public List<string> Columns { get; set; } = new List<string>();
        public bool VerificationIsNeeded { get; set; } = false;
        public string? TableAlias { get; set; }
    }

    public static List<TableColumnInfo> ExtractTableAndColumnNames(string sqlString, bool debug = false)
    {
        var result = ExtractTableAndColumnNamesRecursive(sqlString, debug);

        if (debug)
        {
            Console.WriteLine("\nTable and Alias Information:");
            foreach (var table in result)
            {
                Console.WriteLine($"Table: {table.TableName}, Alias: {table.TableAlias ?? "(no alias)"}");
                Console.WriteLine($"Columns: {string.Join(", ", table.Columns)}");
                Console.WriteLine($"Verification Needed: {table.VerificationIsNeeded}");
                Console.WriteLine("---");
            }
        }

        return result;
    }

    private static List<TableColumnInfo> ExtractTableAndColumnNamesRecursive(string sqlString, bool debug)
    {
        var tableColumnInfos = new Dictionary<string, TableColumnInfo>(StringComparer.OrdinalIgnoreCase);
        var currentSqlTables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Keywords that should not be treated as tables
        var sqlKeywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "INSERT", "UPDATE", "DELETE", "SELECT", "FROM", "WHERE", "JOIN", "AS", "ON", "SET", "INTO",
            "BEGIN", "END", "DECLARE", "EXEC", "EXECUTE", "RETURN", "CREATE", "ALTER", "DROP"
        };

        var tablePatterns = new List<string>
        {
            @"\bFROM\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"\bJOIN\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"\bINTO\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"\bUPDATE\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"\bMERGE\s+INTO\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"\bON\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"(?:FROM|JOIN)\s+(?:INSERTED|DELETED)(?:\s+(?:AS\s+)?([^\s,;()]+))?",
            @"\bWITH\s+([^\s,;()]+)(?:\s+(?:AS\s+)?([^\s,;()]+))?\s+AS"
        };

        // First pass: collect all tables in current SQL statement
        foreach (var pattern in tablePatterns)
        {
            var tableMatches = Regex.Matches(sqlString, pattern, RegexOptions.IgnoreCase);
            foreach (Match match in tableMatches)
            {
                if (match.Groups.Count > 1)
                {
                    var tableName = match.Groups[1].Value;
                    var tableAlias = match.Groups.Count > 2 ? match.Groups[2].Value : null;

                    // Skip if it's a SQL keyword
                    if (sqlKeywords.Contains(tableName)) continue;
                    
                    // Skip if it looks like a column reference (contains '.')
                    if (tableName.Contains(".")) continue;

                    currentSqlTables.Add(tableName);
                    
                    // Create or update table info
                    var key = $"{tableName}_{tableAlias}";
                    if (!tableColumnInfos.ContainsKey(key))
                    {
                        tableColumnInfos[key] = new TableColumnInfo 
                        { 
                            TableName = tableName,
                            TableAlias = tableAlias
                        };
                    }
                }
            }
        }

        bool hasMultipleTables = currentSqlTables.Count > 1;

        // Extract columns for each table
        var columnPatterns = new List<(string Pattern, string Type)>
        {
            (@"\bSELECT\s+(.*?)(?:\s+FROM|\s*$)", "SELECT"),
            (@"\bINSERT\s+INTO\s+[^\s]+\s*\((.*?)\)", "INSERT"),
            (@"\bUPDATE\s+.*?\s+SET\s+(.*?)(?:\s+WHERE|\s*$)", "UPDATE"),
            (@"\bRETURNS\s+TABLE\s*\((.*?)\)", "RETURNS"),
            (@"(?<=INSERTED|DELETED)\.(.*?)(?:\s|,|;|\))", "SPECIAL")
        };

        foreach (var (pattern, type) in columnPatterns)
        {
            var columnMatches = Regex.Matches(sqlString, pattern, RegexOptions.IgnoreCase | RegexOptions.Singleline);
            foreach (Match columnMatch in columnMatches)
            {
                if (columnMatch.Groups.Count > 1)
                {
                    var columns = columnMatch.Groups[1].Value.Split(',');
                    foreach (var column in columns)
                    {
                        var columnName = column.Trim();
                        
                        // Skip empty columns
                        if (string.IsNullOrWhiteSpace(columnName)) continue;

                        // If column has table prefix, add to specific table
                        string? targetTable = null;
                        if (columnName.Contains("."))
                        {
                            var parts = columnName.Split('.');
                            var prefix = parts[0].Trim();
                            columnName = parts[1].Trim();

                            // Find table by alias or name
                            targetTable = tableColumnInfos.Values
                                .FirstOrDefault(t => t.TableAlias == prefix || t.TableName == prefix)
                                ?.TableName;
                        }

                        // Handle AS alias in column name
                        if (columnName.Contains(" AS ", StringComparison.OrdinalIgnoreCase))
                        {
                            columnName = columnName.Split(new[] { " AS " }, StringSplitOptions.None)[1].Trim();
                        }

                        // Add column to appropriate table(s)
                        foreach (var tableInfo in tableColumnInfos.Values)
                        {
                            if (targetTable == null || tableInfo.TableName == targetTable)
                            {
                                if (!tableInfo.Columns.Contains(columnName))
                                {
                                    tableInfo.Columns.Add(columnName);
                                }

                                if (hasMultipleTables && targetTable == null)
                                {
                                    tableInfo.VerificationIsNeeded = true;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Handle subselects
        var subselectPattern = @"\(([^()]+)\)";
        var subselectMatches = Regex.Matches(sqlString, subselectPattern, RegexOptions.IgnoreCase);
        foreach (Match match in subselectMatches)
        {
            if (match.Groups.Count > 1)
            {
                var subqueryResults = ExtractTableAndColumnNamesRecursive(match.Groups[1].Value, debug);
                foreach (var result in subqueryResults)
                {
                    var key = $"{result.TableName}_{result.TableAlias}";
                    if (!tableColumnInfos.ContainsKey(key))
                    {
                        tableColumnInfos[key] = result;
                    }
                }
            }
        }

        return tableColumnInfos.Values.ToList();
    }

    public static string ExtractTableNames(string sqlString)
    {
        var tableNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        ExtractTableNamesRecursive(sqlString, tableNames);
        return string.Join(", ", tableNames);
    }

    private static void ExtractTableNamesRecursive(string sqlString, HashSet<string> tableNames)
    {
        var patterns = new List<string>
        {
            @"\bFROM\s+([^\s,;]+)",
            @"\bJOIN\s+([^\s,;]+)",
            @"\bINTO\s+([^\s,;]+)",
            @"\bUPDATE\s+([^\s,;]+)",
            @"\bMERGE\s+INTO\s+([^\s,;]+)",
            @"\bWITH\s+([^\s,;]+)\s+AS"
        };

        foreach (var pattern in patterns)
        {
            var matches = Regex.Matches(sqlString, pattern, RegexOptions.IgnoreCase);
            foreach (Match match in matches)
            {
                if (match.Groups.Count > 1)
                {
                    tableNames.Add(match.Groups[1].Value);
                }
            }
        }

        // Handle subselects
        var subselectPattern = @"\(([^()]+)\)";
        var subselectMatches = Regex.Matches(sqlString, subselectPattern, RegexOptions.IgnoreCase);
        foreach (Match match in subselectMatches)
        {
            if (match.Groups.Count > 1)
            {
                ExtractTableNamesRecursive(match.Groups[1].Value, tableNames);
            }
        }
    }

    public static void RunTests()
    {
        Console.WriteLine("\n=== Starting SQL Table Extractor Tests ===\n");

        void PrintTestResult(string testName, List<TableColumnInfo> result)
        {
            Console.WriteLine($"\n--- Test: {testName} ---");
            Console.WriteLine("Tables found:");
            foreach (var table in result)
            {
                Console.WriteLine($"\nTable: {table.TableName}");
                Console.WriteLine($"Alias: {table.TableAlias ?? "(no alias)"}");
                Console.WriteLine($"Verification needed: {table.VerificationIsNeeded}");
                Console.WriteLine("Columns:");
                foreach (var column in table.Columns)
                {
                    Console.WriteLine($"  - {column}");
                }
                Console.WriteLine("---");
            }
            Console.WriteLine($"Total tables found: {result.Count}\n");
        }

        try
        {
            // Test 9: Trigger with INSERTED/DELETED and multiple statements
            var test9 = @"
                CREATE TRIGGER trg_OrderDetails_Update
                ON OrderDetails
                AFTER UPDATE
                AS
                BEGIN
                    -- First statement uses INSERTED
                    INSERT INTO AuditLog (TableName, Action, OldValue, NewValue)
                    SELECT 
                        'OrderDetails',
                        'UPDATE',
                        d.Quantity,
                        i.Quantity
                    FROM DELETED d
                    JOIN INSERTED i ON d.OrderDetailId = i.OrderDetailId
                    WHERE d.Quantity != i.Quantity;

                    -- Second statement updates related table
                    UPDATE Orders
                    SET TotalAmount = TotalAmount + (i.Quantity - d.Quantity) * i.UnitPrice
                    FROM Orders o
                    JOIN DELETED d ON o.OrderId = d.OrderId
                    JOIN INSERTED i ON d.OrderDetailId = i.OrderDetailId;

                    -- Third statement with unmapped column
                    INSERT INTO Notifications (Message, Status)
                    VALUES ('Order updated', 'Pending');
                END";
            var result9 = ExtractTableAndColumnNames(test9);
            PrintTestResult("Trigger with INSERTED/DELETED", result9);
            Debug.Assert(result9.Count >= 4, "Test 9: Should have at least 4 tables (OrderDetails, AuditLog, Orders, Notifications)");
            Debug.Assert(result9.Any(t => t.TableName == "OrderDetails"), "Test 9: Should contain OrderDetails table");
            Debug.Assert(result9.Any(t => t.TableName == "AuditLog"), "Test 9: Should contain AuditLog table");
            Debug.Assert(result9.Any(t => t.TableName == "Orders"), "Test 9: Should contain Orders table");
            Debug.Assert(result9.Any(t => t.TableName == "Notifications"), "Test 9: Should contain Notifications table");
            Debug.Assert(result9.Any(t => t.VerificationIsNeeded), "Test 9: Should need verification for unmapped columns");

            // Test 10: Complex stored procedure with output parameters
            var test10 = @"
                CREATE PROCEDURE usp_ProcessOrder
                    @OrderId INT,
                    @CustomerId INT,
                    @TotalAmount DECIMAL(18,2) OUTPUT,
                    @Status VARCHAR(50) OUTPUT
                AS
                BEGIN
                    -- First statement with CTE and subquery
                    WITH OrderSummary AS (
                        SELECT 
                            o.OrderId,
                            o.CustomerId,
                            (SELECT COUNT(*) FROM OrderDetails od WHERE od.OrderId = o.OrderId) as ItemCount,
                            unmapped_column
                        FROM Orders o
                        WHERE o.OrderId = @OrderId
                    )
                    UPDATE Customers
                    SET LastOrderDate = GETDATE(),
                        OrderCount = OrderCount + 1
                    FROM Customers c
                    JOIN OrderSummary os ON c.CustomerId = os.CustomerId;

                    -- Second statement with multiple joins
                    SELECT @TotalAmount = SUM(od.Quantity * p.UnitPrice)
                    FROM OrderDetails od
                    JOIN Products p ON od.ProductId = p.ProductId
                    LEFT JOIN Discounts d ON p.ProductId = d.ProductId
                    WHERE od.OrderId = @OrderId;

                    -- Third statement with dynamic SQL
                    DECLARE @sql NVARCHAR(MAX)
                    SET @sql = 'SELECT @Status = Status FROM OrderStatus WHERE OrderId = @OrderId'
                    EXEC sp_executesql @sql, N'@OrderId INT, @Status VARCHAR(50) OUTPUT', 
                        @OrderId, @Status OUTPUT;
                END";
            var result10 = ExtractTableAndColumnNames(test10);
            PrintTestResult("Complex Stored Procedure", result10);
            Debug.Assert(result10.Count >= 6, "Test 10: Should have at least 6 tables");
            Debug.Assert(result10.Any(t => t.TableName == "Orders"), "Test 10: Should contain Orders table");
            Debug.Assert(result10.Any(t => t.TableName == "OrderDetails"), "Test 10: Should contain OrderDetails table");
            Debug.Assert(result10.Any(t => t.TableName == "Customers"), "Test 10: Should contain Customers table");
            Debug.Assert(result10.Any(t => t.TableName == "Products"), "Test 10: Should contain Products table");
            Debug.Assert(result10.Any(t => t.TableName == "Discounts"), "Test 10: Should contain Discounts table");
            Debug.Assert(result10.Any(t => t.TableName == "OrderStatus"), "Test 10: Should contain OrderStatus table");
            Debug.Assert(result10.Any(t => t.VerificationIsNeeded), "Test 10: Should need verification for unmapped columns");

            // Test 11: Table-valued function with CTEs
            var test11 = @"
                CREATE FUNCTION fn_GetCustomerOrders
                (
                    @CustomerId INT,
                    @StartDate DATE,
                    @EndDate DATE
                )
                RETURNS TABLE
                AS
                RETURN
                (
                    WITH CustomerStats AS (
                        SELECT 
                            c.CustomerId,
                            c.CustomerName,
                            unmapped_stat_column,
                            (SELECT MAX(OrderDate) FROM Orders o2 WHERE o2.CustomerId = c.CustomerId) as LastOrderDate
                        FROM Customers c
                        WHERE c.CustomerId = @CustomerId
                    ),
                    OrderStats AS (
                        SELECT 
                            o.OrderId,
                            o.OrderDate,
                            (SELECT COUNT(*) FROM OrderDetails od WHERE od.OrderId = o.OrderId) as ItemCount
                        FROM Orders o
                        WHERE o.CustomerId = @CustomerId
                        AND o.OrderDate BETWEEN @StartDate AND @EndDate
                    )
                    SELECT 
                        cs.CustomerName,
                        os.OrderId,
                        os.OrderDate,
                        os.ItemCount,
                        p.ProductName,
                        od.Quantity,
                        od.UnitPrice,
                        d.DiscountAmount
                    FROM CustomerStats cs
                    CROSS APPLY OrderStats os
                    JOIN OrderDetails od ON os.OrderId = od.OrderId
                    JOIN Products p ON od.ProductId = p.ProductId
                    LEFT JOIN Discounts d ON p.ProductId = d.ProductId
                    WHERE EXISTS (
                        SELECT 1 
                        FROM CustomerPreferences cp 
                        WHERE cp.CustomerId = cs.CustomerId 
                        AND cp.ProductId = p.ProductId
                    )
                )";
            var result11 = ExtractTableAndColumnNames(test11);
            PrintTestResult("Table-Valued Function", result11);
            Debug.Assert(result11.Count >= 7, "Test 11: Should have at least 7 tables");
            Debug.Assert(result11.Any(t => t.TableName == "Customers"), "Test 11: Should contain Customers table");
            Debug.Assert(result11.Any(t => t.TableName == "Orders"), "Test 11: Should contain Orders table");
            Debug.Assert(result11.Any(t => t.TableName == "OrderDetails"), "Test 11: Should contain OrderDetails table");
            Debug.Assert(result11.Any(t => t.TableName == "Products"), "Test 11: Should contain Products table");
            Debug.Assert(result11.Any(t => t.TableName == "Discounts"), "Test 11: Should contain Discounts table");
            Debug.Assert(result11.Any(t => t.TableName == "CustomerPreferences"), "Test 11: Should contain CustomerPreferences table");
            Debug.Assert(result11.Any(t => t.VerificationIsNeeded), "Test 11: Should need verification for unmapped columns");

            Console.WriteLine("\n=== All tests completed successfully! ===\n");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\n!!! Test failed !!!");
            Console.WriteLine($"Error: {ex.Message}");
            Console.WriteLine($"Stack trace: {ex.StackTrace}");
            throw;
        }
    }
} 