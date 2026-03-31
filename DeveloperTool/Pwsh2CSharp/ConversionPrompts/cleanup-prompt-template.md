# PowerShell → C# Conversion Cleanup (Pass {{PASS_NUMBER}} of {{TOTAL_PASSES}})

You are converting PowerShell 7 code to idiomatic C# (.NET 10). Below is the original PowerShell source and a mechanically converted C# version. The mechanical conversion is rough and needs significant cleanup.

## Your Task — Fix Compilation, Types, and API Calls

1. **Fix all compilation errors** — missing types, invalid syntax, unresolved references
2. **Replace dynamic/object** with concrete types where inferable from the PowerShell source
3. **Replace cmdlet stubs** with real .NET API calls:
   - `Write-LogMessage "X" -Level INFO` → `_logger.Info("X")` (NLog)
   - `Get-Content -LiteralPath $p -Raw` → `File.ReadAllTextAsync(path, Encoding.UTF8)`
   - `ConvertFrom-Json` → `JsonSerializer.Deserialize<T>(json, jsonOptions)`
   - `ConvertTo-Json -Depth N` → `JsonSerializer.Serialize(obj, jsonOptions)`
   - `Get-ChildItem -Recurse -File` → `Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)`
   - `Test-Path` → `File.Exists()` / `Directory.Exists()`
   - `Join-Path` → `Path.Combine()`
   - `Invoke-RestMethod` → `HttpClient` with `IHttpClientFactory`
   - `Invoke-WebRequest` → `HttpClient.SendAsync()`
4. **DB2 conversion** (critical):
   - Replace ALL `System.Data.Odbc` with `IBM.Data.Db2` (NuGet: Net.IBM.Data.Db2 9.0.0.400)
   - `OdbcConnection("DSN=X")` → `DB2Connection("Database=X;")`
   - `OdbcCommand` → `DB2Command`
   - `OdbcDataReader` → `DB2DataReader`
   - Catch `DB2Exception` with `SqlState` and `ErrorCode` logging
   - Use `async/await` with `CancellationToken` for all DB2 operations
5. **Apply C# naming conventions**:
   - PascalCase for methods, properties, classes
   - camelCase for local variables and parameters
   - `_camelCase` for private fields
   - `$script:variable` → private field `_variable`
6. **Add using statements** — at minimum: `System.Text`, `System.Text.Json`, `System.Text.RegularExpressions`, `NLog`, `IBM.Data.Db2` (if DB2)
7. **Add XML docs** on all public members
8. **Convert to async/await** where the PowerShell uses I/O, HTTP, or DB operations
9. **PowerShell hashtable** `[ordered]@{}` → typed record or `Dictionary<string, object>`
10. **PowerShell ArrayList** → `List<T>` with concrete type

## Output

Write the complete corrected C# file to: `{{OUTPUT_CS_PATH}}`

Do NOT omit any code. The output must be a complete, compilable C# file.

---

## Original PowerShell Source ({{BASE_NAME}}.ps1)

```powershell
{{PS1_SOURCE}}
```

## Mechanically Converted C# (needs cleanup)

```csharp
{{CS_SOURCE}}
```
