using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Services.Providers.DB2;

/// <summary>
/// Service for collecting and caching DB2 metadata
/// </summary>
public class DB2MetadataService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    private readonly string _metadataFolder;
    
    public DB2MetadataService()
    {
        _metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        
        _metadataFolder = UserDataFolderHelper.EnsureSubFolder("metadata");
        if (!Directory.Exists(_metadataFolder))
        {
            Directory.CreateDirectory(_metadataFolder);
            Logger.Debug("Created metadata folder: {Folder}", _metadataFolder);
        }
        Logger.Debug("Metadata folder: {Folder}", _metadataFolder);
    }
    
    /// <summary>
    /// Collect database metadata and save to JSON (version-specific, not database-specific)
    /// </summary>
    public async Task CollectMetadataAsync(IConnectionManager connectionManager, string profileName)
    {
        Logger.Info("Starting metadata collection for profile: {Profile}", profileName);
        
        try
        {
            // Step 1: Get DB2 version
            var version = await GetDB2VersionAsync(connectionManager);
            Logger.Info("DB2 Version detected: {Version}", version);
            
            // Step 2: Check if version-specific metadata file already exists
            var fileName = $"db2_{version}_system_tables.json";
            var filePath = Path.Combine(_metadataFolder, fileName);
            
            if (File.Exists(filePath))
            {
                var fileInfo = new FileInfo(filePath);
                if (fileInfo.Length > 0)
                {
                    Logger.Info("Metadata file for version {Version} already exists, skipping collection: {File}", version, fileName);
                    return;
                }
            }
            
            // Step 3: Get all SYSCAT tables
            var syscatTables = await GetSyscatTablesAsync(connectionManager);
            Logger.Info("Found {Count} SYSCAT tables", syscatTables.Rows.Count);
            
            // Step 4: Build relationship documentation
            var relationships = BuildSyscatRelationships();
            
            // Step 5: Build query patterns
            var queryPatterns = BuildQueryPatterns();
            
            // Step 6: Save to JSON file
            await SaveMetadataWithRelationshipsAsync(fileName, syscatTables, version, relationships, queryPatterns);
            
            Logger.Info("Metadata collection completed successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to collect metadata");
            throw;
        }
    }
    
    /// <summary>
    /// Get DB2 version information
    /// </summary>
    private async Task<string> GetDB2VersionAsync(IConnectionManager connectionManager)
    {
        Logger.Debug("Querying DB2 version");
        
        try
        {
            const string versionSql = @"
                SELECT PROD_RELEASE 
                FROM SYSIBMADM.ENV_PROD_INFO 
                WHERE LICENSE_INSTALLED = 'Y'
                FETCH FIRST 1 ROW ONLY
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(versionSql);
            
            if (result.Rows.Count > 0)
            {
                var version = result.Rows[0]["PROD_RELEASE"].ToString()?.Trim();
                Logger.Debug("Raw version string: {Version}", version);
                
                // Clean up version string (e.g., "DB2 v11.5.0.0" -> "11.5")
                version = CleanVersionString(version ?? "unknown");
                return version;
            }
            
            Logger.Warn("No version information found, using 'unknown'");
            return "unknown";
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to get DB2 version, using 'unknown'");
            return "unknown";
        }
    }
    
    /// <summary>
    /// Clean version string to extract major.minor version
    /// </summary>
    private string CleanVersionString(string version)
    {
        // Extract major.minor version (e.g., "11.5" from "DB2 v11.5.0.0")
        var match = System.Text.RegularExpressions.Regex.Match(version, @"(\d+\.\d+)");
        if (match.Success)
        {
            return match.Groups[1].Value;
        }
        
        // Fallback: remove special characters
        return version.Replace(" ", "_").Replace(".", "_").Replace("/", "_");
    }
    
    /// <summary>
    /// Get all SYSCAT tables
    /// </summary>
    private async Task<DataTable> GetSyscatTablesAsync(IConnectionManager connectionManager)
    {
        Logger.Debug("Querying SYSCAT.TABLES");
        
        const string tablesSql = @"
            SELECT * 
            FROM SYSCAT.TABLES 
            WHERE TABSCHEMA = 'SYSCAT'
            ORDER BY TABNAME
        ";
        
        return await connectionManager.ExecuteQueryAsync(tablesSql);
    }
    
    /// <summary>
    /// Save metadata to JSON file
    /// </summary>
    private async Task SaveMetadataAsync(string fileName, DataTable dataTable, string version)
    {
        var filePath = Path.Combine(_metadataFolder, fileName);
        Logger.Debug("Saving metadata to: {File}", filePath);
        
        // Check if file already exists and has data
        if (File.Exists(filePath))
        {
            var fileInfo = new FileInfo(filePath);
            if (fileInfo.Length > 0)
            {
                Logger.Info("Metadata file already exists and contains data, skipping: {File}", fileName);
                return;
            }
        }
        
        // Convert DataTable to JSON
        var rows = new List<Dictionary<string, object?>>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            var dict = new Dictionary<string, object?>();
            foreach (DataColumn column in dataTable.Columns)
            {
                var value = row[column];
                dict[column.ColumnName] = value == DBNull.Value ? null : value;
            }
            rows.Add(dict);
        }
        
        var metadata = new
        {
            CollectedAt = DateTime.UtcNow,
            DB2Version = version,
            RowCount = dataTable.Rows.Count,
            Columns = dataTable.Columns.Cast<DataColumn>().Select(c => new
            {
                c.ColumnName,
                DataType = c.DataType.Name
            }).ToList(),
            Data = rows
        };
        
        var options = new JsonSerializerOptions 
        { 
            WriteIndented = true 
        };
        var json = JsonSerializer.Serialize(metadata, options);
        
        await File.WriteAllTextAsync(filePath, json);
        Logger.Info("Metadata saved: {File} ({Size} bytes)", fileName, json.Length);
    }
    
    /// <summary>
    /// Collect table-specific metadata
    /// </summary>
    public async Task CollectTableMetadataAsync(
        IConnectionManager connectionManager, 
        string tableName, 
        string schemaName,
        string version,
        string profileName)
    {
        Logger.Info("Collecting metadata for table: {Schema}.{Table}", schemaName, tableName);
        
        try
        {
            // Get column information
            var columnsSqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetTableColumns_All");
            var columnsSql = columnsSqlTemplate.Replace("?", $"'{tableName}'").Replace("?", $"'{schemaName}'");
            
            Logger.Debug("Using query: SERVICE_GetTableColumnsAll");
            var columns = await connectionManager.ExecuteQueryAsync(columnsSql);
            
            // Get index information
            var indexesSqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetTableIndexes_All");
            var indexesSql = indexesSqlTemplate.Replace("?", $"'{tableName}'").Replace("?", $"'{schemaName}'");
            
            Logger.Debug("Using query: SERVICE_GetTableIndexesAll");
            var indexes = await connectionManager.ExecuteQueryAsync(indexesSql);
            
            // Save combined metadata
            var fileName = $"db2_table_{schemaName}_{tableName}_{version}_{SanitizeFileName(profileName)}.json";
            var filePath = Path.Combine(_metadataFolder, fileName);
            
            var metadata = new
            {
                Table = new { Schema = schemaName, Name = tableName },
                CollectedAt = DateTime.UtcNow,
                DB2Version = version,
                Columns = ConvertToList(columns),
                Indexes = ConvertToList(indexes)
            };
            
            var options = new JsonSerializerOptions { WriteIndented = true };
            var json = JsonSerializer.Serialize(metadata, options);
            await File.WriteAllTextAsync(filePath, json);
            
            Logger.Info("Table metadata saved: {File}", fileName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to collect table metadata for {Schema}.{Table}", schemaName, tableName);
            throw;
        }
    }
    
    /// <summary>
    /// Convert DataTable to list of dictionaries
    /// </summary>
    private List<Dictionary<string, object?>> ConvertToList(DataTable dataTable)
    {
        var list = new List<Dictionary<string, object?>>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            var dict = new Dictionary<string, object?>();
            foreach (DataColumn column in dataTable.Columns)
            {
                var value = row[column];
                dict[column.ColumnName] = value == DBNull.Value ? null : value;
            }
            list.Add(dict);
        }
        
        return list;
    }
    
    /// <summary>
    /// Sanitize filename to remove invalid characters
    /// </summary>
    private string SanitizeFileName(string fileName)
    {
        var invalidChars = Path.GetInvalidFileNameChars();
        return string.Join("_", fileName.Split(invalidChars, StringSplitOptions.RemoveEmptyEntries));
    }
    
    /// <summary>
    /// Build SYSCAT relationship documentation
    /// </summary>
    private Dictionary<string, object> BuildSyscatRelationships()
    {
        Logger.Debug("Building SYSCAT relationship documentation");
        
        return new Dictionary<string, object>
        {
            ["description"] = "DB2 SYSCAT System Catalog Table Relationships",
            ["version"] = "1.0",
            ["relationships"] = new Dictionary<string, object>
            {
                ["SYSCAT.TABLES"] = new Dictionary<string, object>
                {
                    ["primary_keys"] = new[] { "TABSCHEMA", "TABNAME" },
                    ["related_tables"] = new Dictionary<string, object>
                    {
                        ["SYSCAT.COLUMNS"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.COLUMNS.TABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.COLUMNS.TABNAME",
                            description = "Get all columns for a table",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.INDEXES"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.INDEXES.TABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.INDEXES.TABNAME",
                            description = "Get all indexes for a table",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.REFERENCES"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.REFERENCES.TABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.REFERENCES.TABNAME",
                            description = "Get foreign keys FROM this table (referencing other tables)",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.REFERENCES_PK"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.REFERENCES.REFTABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.REFERENCES.REFTABNAME",
                            description = "Get foreign keys TO this table (referenced by other tables)",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.TABCONST"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.TABCONST.TABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.TABCONST.TABNAME",
                            description = "Get all constraints (PK, FK, CHECK, UNIQUE) for a table",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.TRIGGERS"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.TRIGGERS.TABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.TRIGGERS.TABNAME",
                            description = "Get all triggers on a table",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.TABDEP"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.TABDEP.TABSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.TABDEP.TABNAME",
                            description = "Get dependencies (views, routines, packages) that reference this table",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.PACKAGEDEP"] = new
                        {
                            join_condition = "SYSCAT.TABLES.TABSCHEMA = SYSCAT.PACKAGEDEP.BSCHEMA AND SYSCAT.TABLES.TABNAME = SYSCAT.PACKAGEDEP.BNAME",
                            description = "Get packages that use this table",
                            cardinality = "1:N"
                        }
                    }
                },
                ["SYSCAT.COLUMNS"] = new Dictionary<string, object>
                {
                    ["primary_keys"] = new[] { "TABSCHEMA", "TABNAME", "COLNAME" },
                    ["related_tables"] = new Dictionary<string, object>
                    {
                        ["SYSCAT.TABLES"] = new
                        {
                            join_condition = "SYSCAT.COLUMNS.TABSCHEMA = SYSCAT.TABLES.TABSCHEMA AND SYSCAT.COLUMNS.TABNAME = SYSCAT.TABLES.TABNAME",
                            description = "Get table information for a column",
                            cardinality = "N:1"
                        },
                        ["SYSCAT.KEYCOLUSE"] = new
                        {
                            join_condition = "SYSCAT.COLUMNS.TABSCHEMA = SYSCAT.KEYCOLUSE.TABSCHEMA AND SYSCAT.COLUMNS.TABNAME = SYSCAT.KEYCOLUSE.TABNAME AND SYSCAT.COLUMNS.COLNAME = SYSCAT.KEYCOLUSE.COLNAME",
                            description = "Check if column is part of a primary key or unique constraint",
                            cardinality = "1:N"
                        }
                    }
                },
                ["SYSCAT.REFERENCES"] = new Dictionary<string, object>
                {
                    ["description"] = "Foreign key relationships between tables",
                    ["related_tables"] = new Dictionary<string, object>
                    {
                        ["SYSCAT.INDEXES"] = new
                        {
                            join_condition = "SYSCAT.REFERENCES.TABSCHEMA = SYSCAT.INDEXES.TABSCHEMA AND SYSCAT.REFERENCES.TABNAME = SYSCAT.INDEXES.TABNAME AND EXISTS (SELECT 1 FROM SYSCAT.KEYCOLUSE WHERE SYSCAT.KEYCOLUSE.CONSTNAME = SYSCAT.REFERENCES.CONSTNAME AND SYSCAT.INDEXES.COLNAMES LIKE '%' || SYSCAT.KEYCOLUSE.COLNAME || '%')",
                            description = "Check if foreign key columns are indexed (for performance)",
                            cardinality = "1:N"
                        }
                    }
                },
                ["SYSCAT.INDEXES"] = new Dictionary<string, object>
                {
                    ["primary_keys"] = new[] { "INDSCHEMA", "INDNAME" },
                    ["related_tables"] = new Dictionary<string, object>
                    {
                        ["SYSCAT.TABLES"] = new
                        {
                            join_condition = "SYSCAT.INDEXES.TABSCHEMA = SYSCAT.TABLES.TABSCHEMA AND SYSCAT.INDEXES.TABNAME = SYSCAT.TABLES.TABNAME",
                            description = "Get table that this index belongs to",
                            cardinality = "N:1"
                        },
                        ["SYSCAT.INDEXCOLUSE"] = new
                        {
                            join_condition = "SYSCAT.INDEXES.INDSCHEMA = SYSCAT.INDEXCOLUSE.INDSCHEMA AND SYSCAT.INDEXES.INDNAME = SYSCAT.INDEXCOLUSE.INDNAME",
                            description = "Get individual columns in the index with ordering",
                            cardinality = "1:N"
                        }
                    }
                },
                ["SYSCAT.PACKAGES"] = new Dictionary<string, object>
                {
                    ["primary_keys"] = new[] { "PKGSCHEMA", "PKGNAME" },
                    ["related_tables"] = new Dictionary<string, object>
                    {
                        ["SYSCAT.PACKAGEDEP"] = new
                        {
                            join_condition = "SYSCAT.PACKAGES.PKGSCHEMA = SYSCAT.PACKAGEDEP.PKGSCHEMA AND SYSCAT.PACKAGES.PKGNAME = SYSCAT.PACKAGEDEP.PKGNAME",
                            description = "Get all table/view/routine dependencies for this package",
                            cardinality = "1:N"
                        },
                        ["SYSCAT.STATEMENTS"] = new
                        {
                            join_condition = "SYSCAT.PACKAGES.PKGSCHEMA = SYSCAT.STATEMENTS.PKGSCHEMA AND SYSCAT.PACKAGES.PKGNAME = SYSCAT.STATEMENTS.PKGNAME",
                            description = "Get all SQL statements in this package",
                            cardinality = "1:N"
                        }
                    }
                }
            }
        };
    }
    
    /// <summary>
    /// Build common query patterns for SYSCAT tables (based on proven patterns from Db2CreateDBQA_NonRelated.sql)
    /// </summary>
    private Dictionary<string, object> BuildQueryPatterns()
    {
        Logger.Debug("Building SYSCAT query patterns from proven templates");
        
        return new Dictionary<string, object>
        {
            ["description"] = "Proven query patterns for DB2 SYSCAT system catalog (from Db2CreateDBQA_NonRelated.sql)",
            ["version"] = "1.0",
            ["source"] = "Db2CreateDBQA_NonRelated.sql - Production tested patterns",
            ["patterns"] = new Dictionary<string, object>
            {
                ["get_views_for_schema"] = new
                {
                    description = "Get all views in a schema (PROVEN PATTERN: Line 544-558)",
                    query = @"SELECT
    'VIEW' AS TYPE,
    V.VIEWSCHEMA AS SCHEMA,
    V.VIEWNAME AS NAME,
    TRIM(V.DEFINER) AS LAST_CHANGE_BY,
    T.ALTER_TIME AS LAST_CHANGED_DATETIME,
    TRIM(T.REMARKS) AS REMARKS,
    V.TEXT
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
WHERE T.TYPE = 'V' AND T.TABSCHEMA = ?
ORDER BY V.VIEWNAME",
                    parameters = new[] { "TABSCHEMA" },
                    notes = new[]
                    {
                        "CRITICAL: Start from SYSCAT.TABLES (not SYSCAT.VIEWS) and join to VIEWS",
                        "Filter by T.TYPE = 'V' to get views",
                        "REMARKS comes from SYSCAT.TABLES, not SYSCAT.VIEWS",
                        "Use DEFINER (not OWNER) from TABLES for consistency",
                        "ALTER_TIME comes from TABLES"
                    }
                },
                ["get_mqts_for_schema"] = new
                {
                    description = "Get Materialized Query Tables (MQTs) in a schema (PROVEN PATTERN: Line 562-574)",
                    query = @"SELECT
    'MQT' AS TYPE,
    V.VIEWSCHEMA AS SCHEMA,
    V.VIEWNAME AS NAME,
    TRIM(V.DEFINER) AS LAST_CHANGE_BY,
    T.ALTER_TIME AS LAST_CHANGED_DATETIME,
    T.REFRESH,
    V.TEXT
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
WHERE T.TYPE = 'S' AND T.TABSCHEMA = ?
ORDER BY V.VIEWNAME",
                    parameters = new[] { "TABSCHEMA" },
                    notes = new[]
                    {
                        "MQTs have T.TYPE = 'S' (Staging/Summary table)",
                        "Still need join between TABLES and VIEWS for MQTs"
                    }
                },
                ["get_create_table_ddl"] = new
                {
                    description = "Generate CREATE TABLE DDL (PROVEN PATTERN: Line 170-188)",
                    query = @"SELECT
    X.TABSCHEMA,
    Y.TYPE AS TAB_TYPE,
    Y.REFRESH,
    X.TABNAME,
    Y.ALTER_TIME AS LAST_CHANGED_DATETIME,
    Y.DEFINER AS LAST_CHANGE_BY,
    VARCHAR(
        'CREATE TABLE ' || TRIM(X.TABSCHEMA) || '.' || TRIM(X.TABNAME) || ' (' || CHR(10) || 
        '#COLUMN_INFO#' || CHR(10) || 
        '   ) ' || CHR(10) || 
        CASE WHEN Y.DATACAPTURE = 'Y' THEN '   DATA CAPTURE CHANGES ' ELSE '   ' END || 
        'IN ' || TRIM(Y.TBSPACE) || ';' || CHR(10)
    ) AS TEXT
FROM SYSCAT.COLUMNS X
JOIN SYSCAT.TABLES Y ON X.TABSCHEMA = Y.TABSCHEMA AND X.TABNAME = Y.TABNAME 
    AND Y.TYPE IN ('T')
WHERE X.TABSCHEMA = ?
GROUP BY X.TABSCHEMA, Y.TYPE, Y.REFRESH, X.TABNAME, Y.DATACAPTURE, Y.TBSPACE, Y.ALTER_TIME, Y.DEFINER",
                    parameters = new[] { "TABSCHEMA" },
                    notes = new[]
                    {
                        "Join COLUMNS to TABLES to get table list",
                        "GROUP BY to get unique table rows",
                        "Include DATACAPTURE, TBSPACE, ALTER_TIME, DEFINER",
                        "#COLUMN_INFO# placeholder for column definitions"
                    }
                },
                ["get_column_definitions"] = new
                {
                    description = "Generate column definitions with proper data types (PROVEN PATTERN: Line 206-241)",
                    query = @"SELECT
    X.TABSCHEMA,
    X.TABNAME,
    X.COLNO,
    '""' || X.COLNAME || '"" ' || X.TYPENAME || ' ' || 
    CASE
        WHEN X.TYPENAME = 'INTEGER' THEN ''
        WHEN X.TYPENAME = 'DECIMAL' THEN '(' || X.LENGTH || ',' || TRIM(CHAR(X.SCALE)) || ')'
        WHEN X.TYPENAME = 'TIMESTAMP' THEN '(' || TRIM(CHAR(X.SCALE)) || ')'
        WHEN X.TYPENAME = 'DATE' THEN ''
        ELSE '(' || X.LENGTH || ')'
    END || 
    CASE WHEN X.NULLS = 'N' THEN ' NOT NULL' ELSE '' END ||
    CASE WHEN X.DEFAULT IS NOT NULL THEN ' WITH DEFAULT ' || TRIM(X.DEFAULT) ELSE '' END
    AS TEXT
FROM SYSCAT.COLUMNS X
JOIN SYSCAT.TABLES Y ON X.TABSCHEMA = Y.TABSCHEMA AND X.TABNAME = Y.TABNAME 
    AND Y.TYPE IN ('T')
WHERE X.TABSCHEMA = ? AND X.TABNAME = ?
ORDER BY X.COLNO",
                    parameters = new[] { "TABSCHEMA", "TABNAME" },
                    notes = new[]
                    {
                        "Quote column names with double quotes",
                        "Handle type-specific length/scale logic",
                        "Include NULLS and DEFAULT clauses",
                        "Order by COLNO for proper column sequence"
                    }
                },
                ["get_primary_key_ddl"] = new
                {
                    description = "Generate PRIMARY KEY DDL (PROVEN PATTERN: Line 247-268)",
                    query = @"SELECT
    TABSCHEMA,
    TABNAME,
    CONSTNAME,
    VARCHAR(
        'ALTER TABLE ' || TRIM(TABSCHEMA) || '.' || TRIM(TABNAME) || 
        ' ADD PRIMARY KEY (' || 
        LISTAGG(TRIM(COLNAME), ', ') WITHIN GROUP (ORDER BY COLSEQ) || 
        ');'
    ) AS TEXT
FROM SYSCAT.KEYCOLUSE
WHERE TABSCHEMA = ? AND TABNAME = ?
GROUP BY TABSCHEMA, TABNAME, CONSTNAME",
                    parameters = new[] { "TABSCHEMA", "TABNAME" },
                    notes = new[]
                    {
                        "Use SYSCAT.KEYCOLUSE directly",
                        "Use LISTAGG to combine columns in proper order",
                        "ORDER BY COLSEQ for correct column order"
                    }
                },
                ["get_foreign_key_ddl"] = new
                {
                    description = "Generate FOREIGN KEY DDL with DELETE/UPDATE rules (PROVEN PATTERN: Line 274-396)",
                    query = @"SELECT
    FK.TABSCHEMA,
    FK.TABNAME,
    FK.CONSTNAME,
    VARCHAR(
        'ALTER TABLE ' || TRIM(FK.TABSCHEMA) || '.' || TRIM(FK.TABNAME) || 
        ' ADD CONSTRAINT ' || TRIM(FK.CONSTNAME) || ' FOREIGN KEY (' || 
        RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            TRIM(FK.FK_COLNAMES), '  ', ' '), '  ', ' '), '  ', ' '), '  ', ' '), ' ', ',')) ||
        ') REFERENCES ' || TRIM(FK.REFTABSCHEMA) || '.' || TRIM(FK.REFTABNAME) || 
        ' (' || 
        RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            TRIM(FK.PK_COLNAMES), '  ', ' '), '  ', ' '), '  ', ' '), '  ', ' '), ' ', ',')) ||
        ') ' ||
        CASE FK.DELETERULE
            WHEN 'C' THEN ' ON DELETE CASCADE'
            WHEN 'R' THEN ' ON DELETE RESTRICT'
            WHEN 'N' THEN ' ON DELETE SET NULL'
            WHEN 'A' THEN ' ON DELETE NO ACTION'
            ELSE ''
        END ||
        CASE FK.UPDATERULE
            WHEN 'R' THEN ' ON UPDATE RESTRICT'
            WHEN 'C' THEN ' ON UPDATE CASCADE'
            WHEN 'N' THEN ' ON UPDATE SET NULL'
            WHEN 'A' THEN ' ON UPDATE NO ACTION'
            ELSE ''
        END || ';'
    ) AS TEXT
FROM SYSCAT.REFERENCES FK
WHERE FK.TABSCHEMA = ? AND FK.TABNAME = ?",
                    parameters = new[] { "TABSCHEMA", "TABNAME" },
                    notes = new[]
                    {
                        "Use FK_COLNAMES and PK_COLNAMES directly from SYSCAT.REFERENCES",
                        "Multiple REPLACE calls to handle space padding in CHAR columns",
                        "Include DELETERULE and UPDATERULE with proper CASE statements",
                        "DELETE rules: C=CASCADE, R=RESTRICT, N=SET NULL, A=NO ACTION",
                        "UPDATE rules: Same as DELETE rules"
                    }
                },
                ["get_index_ddl"] = new
                {
                    description = "Generate INDEX DDL with all options (PROVEN PATTERN: Line 402-465)",
                    query = @"SELECT
    I.TABSCHEMA,
    I.TABNAME,
    I.INDNAME AS CONSTNAME,
    I.CREATE_TIME AS LAST_CHANGED_DATETIME,
    I.DEFINER AS LAST_CHANGE_BY,
    CASE 
        WHEN I.UNIQUERULE = 'P' THEN 'PRIMARY_KEY_INDEX'
        WHEN I.UNIQUERULE = 'U' THEN 'UNIQUE_INDEX'
        WHEN I.INDEXTYPE = 'REF' THEN 'REF_INDEX'
        WHEN I.INDEXTYPE = 'DIM' THEN 'DIMENSION_INDEX'
        ELSE 'INDEX'
    END AS TYPE,
    VARCHAR(
        'CREATE ' || 
        CASE WHEN I.UNIQUERULE IN ('U', 'P') THEN 'UNIQUE ' ELSE '' END || 
        CASE 
            WHEN I.INDEXTYPE = 'REF' THEN 'REF '
            WHEN I.INDEXTYPE = 'DIM' THEN 'DIMENSION '
            ELSE ''
        END ||
        'INDEX ' || TRIM(I.INDSCHEMA) || '.' || TRIM(I.INDNAME) || 
        ' ON ' || TRIM(I.TABSCHEMA) || '.' || TRIM(I.TABNAME) || 
        ' (' || LISTAGG(C.COLNAME || ' ' || 
            CASE WHEN C.COLORDER = 'A' THEN 'ASC' ELSE 'DESC' END, ', ') 
            WITHIN GROUP (ORDER BY C.COLSEQ) || ')' ||
        CASE WHEN I.COMPRESSION = 'Y' THEN ' COMPRESSION' ELSE '' END || 
        CASE WHEN I.MINPCTUSED > 0 THEN ' MINPCTUSED ' || TRIM(CHAR(I.MINPCTUSED)) ELSE '' END || ';'
    ) AS TEXT
FROM SYSCAT.INDEXCOLUSE C
JOIN SYSCAT.INDEXES I ON C.INDNAME = I.INDNAME
WHERE I.TABSCHEMA = ? AND I.TABNAME = ?
GROUP BY I.INDNAME, I.INDSCHEMA, I.TABSCHEMA, I.TABNAME, I.INDEXTYPE, 
         I.COMPRESSION, I.MINPCTUSED, I.UNIQUERULE, I.CREATE_TIME, I.DEFINER",
                    parameters = new[] { "TABSCHEMA", "TABNAME" },
                    notes = new[]
                    {
                        "Join SYSCAT.INDEXCOLUSE to SYSCAT.INDEXES",
                        "Use LISTAGG with COLORDER (A=ASC, D=DESC)",
                        "GROUP BY all index properties",
                        "Include COMPRESSION and MINPCTUSED options",
                        "Handle UNIQUERULE: P=Primary, U=Unique",
                        "Handle INDEXTYPE: REF, DIM, or regular"
                    }
                },
                ["get_package_sql_statements"] = new
                {
                    description = "Get SQL statements from packages (PROVEN PATTERN: Line 680-692)",
                    query = @"SELECT
    Z.PKGSCHEMA,
    Z.PKGNAME,
    Z.LASTUSED,
    X.TEXT
FROM SYSCAT.STATEMENTS X
JOIN SYSCAT.PACKAGES Z ON X.PKGSCHEMA = Z.PKGSCHEMA AND X.PKGNAME = Z.PKGNAME
WHERE Z.PKGSCHEMA = ? AND Z.PKGNAME = ?
ORDER BY X.STMTNO, X.SECTNO, X.SEQNO",
                    parameters = new[] { "PKGSCHEMA", "PKGNAME" },
                    notes = new[]
                    {
                        "CRITICAL: Join SYSCAT.STATEMENTS to SYSCAT.PACKAGES",
                        "Match on both PKGSCHEMA and PKGNAME",
                        "Order by STMTNO, SECTNO, SEQNO for proper statement sequence"
                    }
                },
                ["get_drop_view_ddl"] = new
                {
                    description = "Generate DROP VIEW DDL (PROVEN PATTERN: Line 846-856)",
                    query = @"SELECT
    VIEWSCHEMA AS SCHEMA_NAME,
    VIEWNAME AS OBJECT_NAME,
    'VIEW' AS OBJECT_TYPE,
    'DROP VIEW ' || TRIM(VIEWSCHEMA) || '.' || TRIM(VIEWNAME) || ';' AS DROP_STATEMENT
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME 
WHERE T.TYPE = 'V' AND T.TABSCHEMA = ?",
                    parameters = new[] { "TABSCHEMA" },
                    notes = new[]
                    {
                        "Always join TABLES and VIEWS (consistent pattern)",
                        "Filter by T.TYPE = 'V'"
                    }
                },
                ["get_table_remarks_ddl"] = new
                {
                    description = "Generate COMMENT ON TABLE DDL (PROVEN PATTERN: Line 470-480)",
                    query = @"SELECT
    T.TABSCHEMA,
    T.TABNAME,
    VARCHAR('COMMENT ON TABLE ' || TRIM(T.TABSCHEMA) || '.' || TRIM(T.TABNAME) || 
            ' IS ''' || T.REMARKS || ''';') AS TEXT
FROM SYSCAT.TABLES T
WHERE T.REMARKS IS NOT NULL AND TRIM(T.REMARKS) <> ''
AND T.TABSCHEMA = ? AND T.TABNAME = ?",
                    parameters = new[] { "TABSCHEMA", "TABNAME" }
                },
                ["get_column_remarks_ddl"] = new
                {
                    description = "Generate COMMENT ON COLUMN DDL (PROVEN PATTERN: Line 486-497)",
                    query = @"SELECT
    C.TABSCHEMA,
    C.TABNAME,
    C.COLNAME,
    VARCHAR('COMMENT ON COLUMN ' || TRIM(C.TABSCHEMA) || '.' || TRIM(C.TABNAME) || '.' || 
            C.COLNAME || ' IS ''' || C.REMARKS || ''';') AS TEXT
FROM SYSCAT.COLUMNS C
WHERE C.REMARKS IS NOT NULL AND TRIM(C.REMARKS) <> ''
AND C.TABSCHEMA = ? AND C.TABNAME = ?
ORDER BY C.COLNO",
                    parameters = new[] { "TABSCHEMA", "TABNAME" }
                },
                ["get_update_statistics_ddl"] = new
                {
                    description = "Generate RUNSTATS commands (PROVEN PATTERN: Line 149-164)",
                    query = @"SELECT
    TABSCHEMA,
    TABNAME,
    STATS_TIME,
    'CALL SYSPROC.ADMIN_CMD(' || x'27' || 
    'RUNSTATS ON TABLE ' || RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) || 
    ' WITH DISTRIBUTION AND DETAILED INDEXES ALL' || x'27' || ');' AS TEXT
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ? AND TYPE = 'T'",
                    parameters = new[] { "TABSCHEMA" }
                },
                ["get_data_capture_ddl"] = new
                {
                    description = "Generate ALTER TABLE DATA CAPTURE DDL (PROVEN PATTERN: Line 890-923)",
                    query = @"SELECT
    Y.TABSCHEMA,
    Y.TABNAME,
    Y.DATACAPTURE,
    CASE Y.DATACAPTURE
        WHEN 'N' THEN 'No data capture'
        WHEN 'Y' THEN 'Data capture enabled for changes'
        WHEN 'L' THEN 'Data capture for load'
        ELSE 'Unknown value'
    END AS DATACAPTURE_DESCRIPTION,
    VARCHAR(CASE Y.DATACAPTURE
        WHEN 'Y' THEN ''
        ELSE 'ALTER TABLE ' || TRIM(Y.TABSCHEMA) || '.' || TRIM(Y.TABNAME) || 
             '  DATA CAPTURE CHANGES;'
    END) AS SQL_SCRIPT
FROM SYSCAT.TABLES Y
WHERE Y.TYPE = 'T' AND Y.TABSCHEMA = ?
ORDER BY Y.DATACAPTURE",
                    parameters = new[] { "TABSCHEMA" }
                }
            }
        };
    }
    
    /// <summary>
    /// Save metadata with relationships and query patterns
    /// </summary>
    private async Task SaveMetadataWithRelationshipsAsync(
        string fileName, 
        DataTable syscatTables, 
        string version,
        Dictionary<string, object> relationships,
        Dictionary<string, object> queryPatterns)
    {
        var filePath = Path.Combine(_metadataFolder, fileName);
        Logger.Debug("Saving metadata with relationships to: {File}", filePath);
        
        // Convert DataTable to JSON
        var rows = ConvertToList(syscatTables);
        
        var metadata = new
        {
            CollectedAt = DateTime.UtcNow,
            DB2Version = version,
            Description = "DB2 System Catalog (SYSCAT) metadata including table relationships and query patterns",
            SystemTables = new
            {
                Count = syscatTables.Rows.Count,
                Columns = syscatTables.Columns.Cast<DataColumn>().Select(c => new
                {
                    c.ColumnName,
                    DataType = c.DataType.Name
                }).ToList(),
                Data = rows
            },
            Relationships = relationships,
            QueryPatterns = queryPatterns
        };
        
        var options = new JsonSerializerOptions 
        { 
            WriteIndented = true 
        };
        var json = JsonSerializer.Serialize(metadata, options);
        
        await File.WriteAllTextAsync(filePath, json);
        Logger.Info("Metadata saved with relationships: {File} ({Size} bytes)", fileName, json.Length);
    }
}


