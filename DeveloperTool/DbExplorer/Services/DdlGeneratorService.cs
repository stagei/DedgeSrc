using System;
using System.Data;
using System.Text;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for generating DDL (CREATE and DROP) statements for database objects.
/// Uses IConnectionManager factory methods for database-agnostic operation.
/// </summary>
public class DdlGeneratorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;

    public DdlGeneratorService(IConnectionManager connectionManager, MetadataHandler? metadataHandler = null)
    {
        _connectionManager = connectionManager;
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
    }

    /// <summary>
    /// Generate DDL for a database object
    /// </summary>
    public async Task<(string createDdl, string dropDdl)> GenerateDdlAsync(DatabaseObject obj)
    {
        Logger.Info("Generating DDL for {Type}: {Name}", obj.Type, obj.FullName);
        
        return obj.Type switch
        {
            ObjectType.Tables => await GenerateTableDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Views => await GenerateViewDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Indexes => await GenerateIndexDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Sequences => await GenerateSequenceDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Synonyms => await GenerateSynonymDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Triggers => await GenerateTriggerDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Procedures => await GenerateProcedureDdlAsync(obj.SchemaName, obj.Name),
            ObjectType.Functions => await GenerateFunctionDdlAsync(obj.SchemaName, obj.Name),
            _ => throw new NotSupportedException($"DDL generation not supported for {obj.Type}")
        };
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a table
    /// </summary>
    private async Task<(string, string)> GenerateTableDdlAsync(string schema, string tableName)
    {
        Logger.Debug("Generating table DDL for {Schema}.{Table}", schema, tableName);
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE TABLE DDL for {schema}.{tableName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine($"CREATE TABLE {schema}.{tableName}");
        createDdl.AppendLine("(");
        
        // Get columns
        var columnsSql = _metadataHandler?.GetStatement("DDL_GetTableColumns") 
            ?? @"SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, DEFAULT, IDENTITY
            FROM SYSCAT.COLUMNS
            WHERE TABSCHEMA = ? AND TABNAME = ?
            ORDER BY COLNO";
        
        using var colCommand = _connectionManager.CreateCommand(columnsSql);
        colCommand.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        colCommand.Parameters.Add(_connectionManager.CreateParameter("@table", tableName));
        
        using var colReader = await colCommand.ExecuteReaderAsync();
        var first = true;
        
        while (await colReader.ReadAsync())
        {
            if (!first) createDdl.AppendLine(",");
            first = false;
            
            var colName = colReader.GetString(0);
            var typeName = colReader.GetString(1);
            var length = colReader.IsDBNull(2) ? 0 : colReader.GetInt32(2);
            var scale = colReader.IsDBNull(3) ? 0 : colReader.GetInt16(3);
            var nulls = colReader.GetString(4);
            var defaultVal = colReader.IsDBNull(5) ? null : colReader.GetString(5);
            var identity = colReader.GetString(6);
            
            createDdl.Append($"    {colName} {typeName}");
            
            if (typeName.Contains("CHAR") || typeName == "VARCHAR" || typeName == "VARGRAPHIC")
                createDdl.Append($"({length})");
            else if (typeName == "DECIMAL" || typeName == "NUMERIC")
                createDdl.Append($"({length},{scale})");
            
            if (identity == "Y")
                createDdl.Append(" GENERATED ALWAYS AS IDENTITY");
            
            if (nulls == "N")
                createDdl.Append(" NOT NULL");
            
            if (!string.IsNullOrEmpty(defaultVal))
                createDdl.Append($" DEFAULT {defaultVal}");
        }
        
        createDdl.AppendLine();
        createDdl.AppendLine(");");
        
        // Get primary key
        var pkSql = _metadataHandler?.GetStatement("DDL_GetTablePrimaryKey") 
            ?? @"SELECT CONSTNAME, COLNAMES
            FROM SYSCAT.TABCONST
            WHERE TABSCHEMA = ? AND TABNAME = ? AND TYPE = 'P'";
        
        using var pkCommand = _connectionManager.CreateCommand(pkSql);
        pkCommand.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        pkCommand.Parameters.Add(_connectionManager.CreateParameter("@table", tableName));
        
        var pkName = await pkCommand.ExecuteScalarAsync();
        if (pkName != null)
        {
            createDdl.AppendLine();
            createDdl.AppendLine($"-- Primary Key");
            createDdl.AppendLine($"ALTER TABLE {schema}.{tableName}");
            createDdl.AppendLine($"    ADD CONSTRAINT {pkName}");
            
            using var pkReader = await pkCommand.ExecuteReaderAsync();
            if (await pkReader.ReadAsync())
            {
                var colNames = pkReader.GetString(1);
                createDdl.AppendLine($"    PRIMARY KEY ({colNames.Replace("+", ", ")});");
            }
        }
        
        // Generate DROP
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP TABLE DDL for {schema}.{tableName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP TABLE {schema}.{tableName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a view
    /// </summary>
    private async Task<(string, string)> GenerateViewDdlAsync(string schema, string viewName)
    {
        Logger.Debug("Generating view DDL for {Schema}.{View}", schema, viewName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetViewText") 
            ?? @"SELECT TEXT
            FROM SYSCAT.VIEWS
            WHERE VIEWSCHEMA = ? AND VIEWNAME = ?";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@view", viewName));
        
        var text = await command.ExecuteScalarAsync();
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE VIEW DDL for {schema}.{viewName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine($"CREATE VIEW {schema}.{viewName} AS");
        createDdl.AppendLine(text?.ToString() ?? "");
        createDdl.AppendLine(";");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP VIEW DDL for {schema}.{viewName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP VIEW {schema}.{viewName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for an index
    /// </summary>
    private async Task<(string, string)> GenerateIndexDdlAsync(string schema, string indexName)
    {
        Logger.Debug("Generating index DDL for {Schema}.{Index}", schema, indexName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetIndexDetails") 
            ?? @"SELECT TABSCHEMA, TABNAME, UNIQUERULE, COLNAMES, INDEXTYPE
            FROM SYSCAT.INDEXES
            WHERE INDSCHEMA = ? AND INDNAME = ?";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@index", indexName));
        
        using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            throw new Exception($"Index {schema}.{indexName} not found");
        
        var tabSchema = reader.GetString(0);
        var tabName = reader.GetString(1);
        var uniqueRule = reader.GetString(2);
        var colNames = reader.GetString(3);
        var indexType = reader.GetString(4);
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE INDEX DDL for {schema}.{indexName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        
        if (uniqueRule == "U")
            createDdl.Append("CREATE UNIQUE INDEX ");
        else
            createDdl.Append("CREATE INDEX ");
        
        createDdl.AppendLine($"{schema}.{indexName}");
        createDdl.AppendLine($"    ON {tabSchema}.{tabName}");
        createDdl.AppendLine($"    ({colNames.Replace("+", ", ")});");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP INDEX DDL for {schema}.{indexName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP INDEX {schema}.{indexName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a sequence
    /// </summary>
    private async Task<(string, string)> GenerateSequenceDdlAsync(string schema, string seqName)
    {
        Logger.Debug("Generating sequence DDL for {Schema}.{Sequence}", schema, seqName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetSequenceDetails") 
            ?? @"SELECT START, INCREMENT, MINVALUE, MAXVALUE, CYCLE, CACHE, ORDER
            FROM SYSCAT.SEQUENCES
            WHERE SEQSCHEMA = ? AND SEQNAME = ?";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@seq", seqName));
        
        using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            throw new Exception($"Sequence {schema}.{seqName} not found");
        
        var start = reader.IsDBNull(0) ? 1 : reader.GetInt64(0);
        var increment = reader.IsDBNull(1) ? 1 : reader.GetInt64(1);
        var minValue = reader.IsDBNull(2) ? 1 : reader.GetInt64(2);
        var maxValue = reader.IsDBNull(3) ? long.MaxValue : reader.GetInt64(3);
        var cycle = reader.IsDBNull(4) ? "N" : reader.GetString(4);
        var cache = reader.IsDBNull(5) ? 20 : reader.GetInt64(5);
        var order = reader.IsDBNull(6) ? "N" : reader.GetString(6);
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE SEQUENCE DDL for {schema}.{seqName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine($"CREATE SEQUENCE {schema}.{seqName}");
        createDdl.AppendLine($"    START WITH {start}");
        createDdl.AppendLine($"    INCREMENT BY {increment}");
        createDdl.AppendLine($"    MINVALUE {minValue}");
        createDdl.AppendLine($"    MAXVALUE {maxValue}");
        createDdl.AppendLine($"    {(cycle == "Y" ? "CYCLE" : "NO CYCLE")}");
        createDdl.AppendLine($"    CACHE {cache}");
        createDdl.AppendLine($"    {(order == "Y" ? "ORDER" : "NO ORDER")};");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP SEQUENCE DDL for {schema}.{seqName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP SEQUENCE {schema}.{seqName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a synonym
    /// </summary>
    private async Task<(string, string)> GenerateSynonymDdlAsync(string schema, string synonymName)
    {
        Logger.Debug("Generating synonym DDL for {Schema}.{Synonym}", schema, synonymName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetSynonymDetails") 
            ?? @"SELECT BASE_TABSCHEMA, BASE_TABNAME
            FROM SYSCAT.TABLES
            WHERE TABSCHEMA = ? AND TABNAME = ? AND TYPE = 'A'";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@synonym", synonymName));
        
        using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            throw new Exception($"Synonym {schema}.{synonymName} not found");
        
        var baseSchema = reader.GetString(0);
        var baseName = reader.GetString(1);
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE ALIAS DDL for {schema}.{synonymName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine($"CREATE ALIAS {schema}.{synonymName}");
        createDdl.AppendLine($"    FOR {baseSchema}.{baseName};");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP ALIAS DDL for {schema}.{synonymName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP ALIAS {schema}.{synonymName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a trigger
    /// </summary>
    private async Task<(string, string)> GenerateTriggerDdlAsync(string schema, string triggerName)
    {
        Logger.Debug("Generating trigger DDL for {Schema}.{Trigger}", schema, triggerName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetTriggerText") 
            ?? @"SELECT TEXT
            FROM SYSCAT.TRIGGERS
            WHERE TRIGSCHEMA = ? AND TRIGNAME = ?";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@trigger", triggerName));
        
        var text = await command.ExecuteScalarAsync();
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE TRIGGER DDL for {schema}.{triggerName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine(text?.ToString() ?? $"-- Trigger text not available");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP TRIGGER DDL for {schema}.{triggerName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP TRIGGER {schema}.{triggerName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a procedure
    /// </summary>
    private async Task<(string, string)> GenerateProcedureDdlAsync(string schema, string procName)
    {
        Logger.Debug("Generating procedure DDL for {Schema}.{Procedure}", schema, procName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetProcedureText") 
            ?? @"SELECT TEXT
            FROM SYSCAT.ROUTINES
            WHERE ROUTINESCHEMA = ? AND ROUTINENAME = ? AND ROUTINETYPE = 'P'";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@proc", procName));
        
        var text = await command.ExecuteScalarAsync();
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE PROCEDURE DDL for {schema}.{procName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine(text?.ToString() ?? $"-- Procedure text not available");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP PROCEDURE DDL for {schema}.{procName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP PROCEDURE {schema}.{procName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }

    /// <summary>
    /// Generate CREATE and DROP DDL for a function
    /// </summary>
    private async Task<(string, string)> GenerateFunctionDdlAsync(string schema, string funcName)
    {
        Logger.Debug("Generating function DDL for {Schema}.{Function}", schema, funcName);
        
        var sql = _metadataHandler?.GetStatement("DDL_GetFunctionText") 
            ?? @"SELECT TEXT
            FROM SYSCAT.ROUTINES
            WHERE ROUTINESCHEMA = ? AND ROUTINENAME = ? AND ROUTINETYPE = 'F'";
        
        using var command = _connectionManager.CreateCommand(sql);
        command.Parameters.Add(_connectionManager.CreateParameter("@schema", schema));
        command.Parameters.Add(_connectionManager.CreateParameter("@func", funcName));
        
        var text = await command.ExecuteScalarAsync();
        
        var createDdl = new StringBuilder();
        createDdl.AppendLine($"-- CREATE FUNCTION DDL for {schema}.{funcName}");
        createDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        createDdl.AppendLine();
        createDdl.AppendLine(text?.ToString() ?? $"-- Function text not available");
        
        var dropDdl = new StringBuilder();
        dropDdl.AppendLine($"-- DROP FUNCTION DDL for {schema}.{funcName}");
        dropDdl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        dropDdl.AppendLine();
        dropDdl.AppendLine($"DROP FUNCTION {schema}.{funcName};");
        
        return (createDdl.ToString(), dropDdl.ToString());
    }
}
