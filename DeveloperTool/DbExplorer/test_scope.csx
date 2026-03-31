using DbExplorer.Services;

// Test 1: Simple query
var sql1 = "SELECT o.order_id, o.total FROM DBM.ORDERS o WHERE o.status = 'A'";
var parser = new SqlScopeParser();
var scopes1 = parser.Parse(sql1);

Console.WriteLine("=== Test 1: Simple Query ===");
Console.WriteLine($"Scopes found: {scopes1.Count}");
foreach (var s in scopes1)
{
    Console.WriteLine($"  Level {s.Level}, Index {s.Index}: Tables={s.Tables.Count}, Exposed={s.ExposedColumns.Count}");
    foreach (var t in s.Tables) Console.WriteLine($"    Table: {t.FullName} AS {t.Alias}");
    foreach (var c in s.ExposedColumns) Console.WriteLine($"    Exposed: {c}");
}

// Test 2: Nested subselect
var sql2 = @"SELECT o.order_id, c.name 
FROM DBM.ORDERS o 
JOIN (SELECT customer_id, name FROM DBM.CUSTOMERS WHERE active = 'Y') c 
ON o.customer_id = c.customer_id";

var scopes2 = parser.Parse(sql2);
Console.WriteLine("\n=== Test 2: Nested Subselect ===");
Console.WriteLine($"Scopes found: {scopes2.Count}");
foreach (var s in scopes2)
{
    Console.WriteLine($"  Level {s.Level}, Index {s.Index}, Alias={s.Alias}: Tables={s.Tables.Count}");
    foreach (var t in s.Tables) 
    {
        Console.WriteLine($"    Table: {t.FullName} AS {t.Alias}, IsDerived={t.IsDerivedTable}, ChildIdx={t.DerivedTableScopeIndex}");
    }
    Console.WriteLine($"    Exposed columns: {string.Join(", ", s.ExposedColumns)}");
}

// Test visibility at main level
var mainScope = scopes2.First(s => s.Level == 0);
var visibility = parser.GetVisibleItems(scopes2, mainScope);
Console.WriteLine($"\nVisibility at main query:");
Console.WriteLine($"  Aliases: {string.Join(", ", visibility.Aliases.Select(a => a.Name))}");
Console.WriteLine($"  Derived table columns:");
foreach (var dt in visibility.DerivedTableColumns)
{
    Console.WriteLine($"    {dt.Alias}: {string.Join(", ", dt.ExposedColumns)}");
}
