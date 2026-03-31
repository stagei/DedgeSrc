# PowerShell → C# Refactoring Pass (Pass {{PASS_NUMBER}} of {{TOTAL_PASSES}})

You are refactoring a C# file that was converted from PowerShell 7. The previous pass fixed basic compilation issues. Now improve structure and quality.

## Your Task — Refactor for Production Quality

1. **Class structure** — break monolithic code into well-named classes with single responsibility:
   - Extract a `Settings`/`Options` class for configuration (bindable from `IOptions<T>`)
   - Extract service classes for distinct concerns (DB2 queries, HTTP calls, file I/O)
   - Use constructor injection for dependencies
2. **Dependency injection**:
   - Define interfaces for services (`IDb2QueryService`, `IAnalysisService`, etc.)
   - Use `IHttpClientFactory` for HTTP clients
   - Use `ILogger<T>` (NLog backend) for logging
3. **DB2 validation** (critical):
   - Verify ALL DB2 access uses `IBM.Data.Db2` (`DB2Connection`, `DB2Command`, `DB2DataReader`)
   - Verify NO `System.Data.Odbc` references remain
   - Verify `DB2Exception` is caught specifically with `SqlState`/`ErrorCode`
   - Verify the dual-path pattern exists if the PowerShell had `Invoke-Db2QueryAny` (ADO.NET + MCP HTTP fallback)
4. **Error handling** — specific exceptions before generic:
   - `DB2Exception` for DB2 operations
   - `HttpRequestException` for HTTP operations
   - `JsonException` for JSON parsing
   - `IOException` for file operations
5. **Functional equivalence** — compare every function in the original PowerShell against the C# to verify:
   - Every PS function has a C# method equivalent
   - Return types match the intent (PS arrays → `List<T>`, hashtables → dictionaries or typed objects)
   - Error handling follows the same recovery pattern
6. **Logging parity** — every `Write-LogMessage` / `Write-Warning` / `Write-Host` in the PS has a corresponding NLog call
7. **JSON handling** — use `System.Text.Json` with proper options:
   - `WriteIndented = true` for output files
   - `PropertyNamingPolicy = JsonNamingPolicy.CamelCase`
   - `DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull`
   - `JavaScriptEncoder.UnsafeRelaxedJsonEscaping` for non-ASCII characters
8. **Encoding** — register `CodePagesEncodingProvider` if Windows-1252 is used
9. **Ensure compilability** — no missing types, no unresolved references, all used packages referenced

## Output

Write the complete refactored C# file to: `{{OUTPUT_CS_PATH}}`

Do NOT omit any code. The output must be a complete, compilable C# file.

---

## Original PowerShell Source (for reference)

```powershell
{{PS1_SOURCE}}
```

## Current C# Code (needs refactoring)

```csharp
{{CS_SOURCE}}
```
