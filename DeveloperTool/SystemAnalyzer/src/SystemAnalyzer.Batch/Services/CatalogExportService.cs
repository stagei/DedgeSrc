using System.Text.Json;
using System.Text.Json.Nodes;
using NLog;

namespace SystemAnalyzer.Batch.Services;

/// <summary>
/// C# equivalent of Export-DatabaseCatalogs.ps1.
/// Exports SYSCAT.TABLES and SYSCAT.PACKAGES from DB2 to AnalysisCommon/Databases/{DB}/.
/// </summary>
public sealed class CatalogExportService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly JsonSerializerOptions JsonWriteOptions = new() { WriteIndented = true };

    private static readonly Dictionary<string, string> DatabaseDescriptions = new(StringComparer.OrdinalIgnoreCase)
    {
        ["BASISRAP"] = "Dedge production report database",
        ["COBDOK"] = "CobDok document handling database",
        ["FKKONTO"] = "FkKonto/Innlan accounting database"
    };

    private const string TablesQuery = """
        SELECT
            TRIM(TABNAME)    AS TABNAME,
            TRIM(TABSCHEMA)  AS TABSCHEMA,
            TYPE,
            TRIM(REMARKS)    AS REMARKS,
            COLCOUNT,
            TRIM(TABSCHEMA) || '.' || TRIM(TABNAME) AS QUALIFIED_NAME
        FROM SYSCAT.TABLES
        WHERE TABSCHEMA NOT LIKE '%SYS%'
          AND TABSCHEMA NOT LIKE '%IBM%'
          AND TABSCHEMA <> 'ROA'
        ORDER BY TABSCHEMA, TABNAME
        """;

    private const string PackagesQuery = """
        SELECT
            TRIM(PKGSCHEMA)  AS PKGSCHEMA,
            TRIM(PKGNAME)    AS PKGNAME,
            TRIM(PKGNAME)    AS QUALIFIED_NAME,
            TRIM(PKGNAME) || '.CBL' AS SOURCE_FILENAME
        FROM SYSCAT.PACKAGES
        WHERE PKGSCHEMA IN ('FK','FKPROC','LOG','HST','CRM','TV','F0001','TCA','INL','DBM','Dedge')
        ORDER BY PKGSCHEMA, PKGNAME
        """;

    private readonly Db2Client _db2Client;
    private readonly HttpClient _httpClient;

    public CatalogExportService(Db2Client db2Client, HttpClient httpClient)
    {
        _db2Client = db2Client;
        _httpClient = httpClient;
    }

    /// <summary>
    /// Export catalogs for a given database to the specified directory.
    /// Returns true if export succeeded (or was skipped because files are recent).
    /// </summary>
    public async Task<bool> ExportCatalogAsync(string database, string outputDir, bool forceRefresh = false)
    {
        Directory.CreateDirectory(outputDir);

        var tablesPath = Path.Combine(outputDir, "syscat_tables.json");
        var packagesPath = Path.Combine(outputDir, "syscat_packages.json");

        if (!forceRefresh && File.Exists(tablesPath) && File.Exists(packagesPath))
        {
            var tablesAge = DateTime.Now - File.GetLastWriteTime(tablesPath);
            if (tablesAge.TotalHours < 24)
            {
                Logger.Info($"  Catalog files for {database} are recent ({tablesAge.TotalHours:F1}h old) — skipping export");
                return true;
            }
        }

        var description = DatabaseDescriptions.GetValueOrDefault(database, $"DB2 database {database}");
        Logger.Info($"  Exporting catalogs for {database} — {description}");

        // V1 pattern: try per-database ODBC (DSN={database}), then MCP fallback
        var tableRows = await _db2Client.ExecuteQueryForDatabaseAsync(TablesQuery, database, _httpClient);
        if (tableRows.Count == 0)
        {
            Logger.Warn($"  No table rows returned for {database} — catalog export failed (tried ODBC DSN={database} and MCP)");
            return false;
        }

        var packageRows = await _db2Client.ExecuteQueryForDatabaseAsync(PackagesQuery, database, _httpClient);

        // Build tables JSON
        var tableCount = tableRows.Count(r => r.GetValueOrDefault("TYPE")?.Trim() == "T");
        var viewCount = tableRows.Count(r => r.GetValueOrDefault("TYPE")?.Trim() == "V");
        var schemas = tableRows
            .Select(r => r.GetValueOrDefault("TABSCHEMA") ?? "")
            .Where(s => !string.IsNullOrEmpty(s))
            .Distinct()
            .OrderBy(s => s)
            .ToList();

        var tablesJson = new JsonObject
        {
            ["database"] = database,
            ["db2Alias"] = database,
            ["server"] = "",
            ["description"] = description,
            ["exportedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            ["exportedBy"] = Environment.UserName,
            ["query"] = TablesQuery.Trim(),
            ["summary"] = new JsonObject
            {
                ["totalObjects"] = tableRows.Count,
                ["tables"] = tableCount,
                ["views"] = viewCount,
                ["schemas"] = new JsonArray(schemas.Select(s => (JsonNode)JsonValue.Create(s)!).ToArray())
            },
            ["tables"] = new JsonArray(tableRows.Select(r => (JsonNode)new JsonObject
            {
                ["tabName"] = r.GetValueOrDefault("TABNAME"),
                ["tabSchema"] = r.GetValueOrDefault("TABSCHEMA"),
                ["type"] = r.GetValueOrDefault("TYPE")?.Trim(),
                ["remarks"] = r.GetValueOrDefault("REMARKS"),
                ["colCount"] = int.TryParse(r.GetValueOrDefault("COLCOUNT"), out var cc) ? cc : 0,
                ["qualifiedName"] = r.GetValueOrDefault("QUALIFIED_NAME")
            }).ToArray())
        };

        File.WriteAllText(tablesPath, tablesJson.ToJsonString(JsonWriteOptions));
        Logger.Info($"  [{database}] Tables: {tableRows.Count} ({tableCount} tables, {viewCount} views)");

        // Build packages JSON
        var pkgSchemas = packageRows
            .Select(r => r.GetValueOrDefault("PKGSCHEMA") ?? "")
            .Where(s => !string.IsNullOrEmpty(s))
            .Distinct()
            .OrderBy(s => s)
            .ToList();

        var perSchema = new JsonObject();
        foreach (var s in pkgSchemas)
            perSchema[s] = packageRows.Count(r => r.GetValueOrDefault("PKGSCHEMA") == s);

        var packagesJson = new JsonObject
        {
            ["database"] = database,
            ["db2Alias"] = database,
            ["server"] = "",
            ["description"] = description,
            ["exportedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            ["exportedBy"] = Environment.UserName,
            ["query"] = PackagesQuery.Trim(),
            ["summary"] = new JsonObject
            {
                ["totalPackages"] = packageRows.Count,
                ["schemas"] = new JsonArray(pkgSchemas.Select(s => (JsonNode)JsonValue.Create(s)!).ToArray()),
                ["perSchema"] = perSchema
            },
            ["packages"] = new JsonArray(packageRows.Select(r => (JsonNode)new JsonObject
            {
                ["pkgSchema"] = r.GetValueOrDefault("PKGSCHEMA"),
                ["pkgName"] = r.GetValueOrDefault("PKGNAME"),
                ["qualifiedName"] = r.GetValueOrDefault("QUALIFIED_NAME"),
                ["sourceFilename"] = r.GetValueOrDefault("SOURCE_FILENAME")
            }).ToArray())
        };

        File.WriteAllText(packagesPath, packagesJson.ToJsonString(JsonWriteOptions));
        Logger.Info($"  [{database}] Packages: {packageRows.Count} in schemas: {string.Join(", ", pkgSchemas)}");

        return true;
    }
}
