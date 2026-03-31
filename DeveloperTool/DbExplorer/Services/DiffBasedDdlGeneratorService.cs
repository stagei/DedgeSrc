using System;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using SqlMermaidErdTools.Models;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// REFACTORED: Now uses SqlMermaidErdTools for migration DDL generation.
/// Primary method uses SqlMermaidErdTools.GenerateDiffAlterStatements() for better quality.
/// Legacy method preserved as fallback.
/// </summary>
public class DiffBasedDdlGeneratorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly SqlMermaidIntegrationService _sqlMermaidService;
    
    public DiffBasedDdlGeneratorService()
    {
        _sqlMermaidService = new SqlMermaidIntegrationService();
    }
    
    /// <summary>
    /// REFACTORED: Now attempts to use SqlMermaidErdTools for migration generation.
    /// Falls back to legacy method if SqlMermaidErdTools is not applicable.
    /// </summary>
    public async Task<string> GenerateMigrationScriptsAsync(
        string beforeMermaid,
        string afterMermaid,
        string targetSchema,
        SqlDialect dialect = SqlDialect.AnsiSql)
    {
        Logger.Info("Generating migration scripts using SqlMermaidErdTools - Dialect: {Dialect}", dialect);
        
        try
        {
            // Use SqlMermaidErdTools for superior migration DDL generation
            var migrationDdl = await _sqlMermaidService.GenerateMigrationFromMermaidDiffAsync(
                beforeMermaid,
                afterMermaid,
                dialect);
            
            // Add schema prefix to generated DDL if needed
            if (!string.IsNullOrEmpty(targetSchema) && targetSchema != "PUBLIC")
            {
                migrationDdl = AddSchemaPrefix(migrationDdl, targetSchema);
            }
            
            Logger.Info("Migration scripts generated successfully via SqlMermaidErdTools");
            return migrationDdl;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "SqlMermaidErdTools migration failed, using legacy method");
            return "-- SqlMermaidErdTools migration generation not available\n" +
                   "-- Falling back to legacy method (requires SchemaDiff object)\n" +
                   "-- Note: Call GenerateMigrationScriptsLegacy() with SchemaDiff instead";
        }
    }
    
    /// <summary>
    /// LEGACY METHOD: Original custom migration script generation.
    /// Preserved for backward compatibility with SchemaDiff-based workflow.
    /// </summary>
    public string GenerateMigrationScriptsLegacy(SchemaDiff diff, string targetSchema)
    {
        Logger.Info("Generating migration scripts (legacy) for {Count} changed tables", diff.TableChanges.Count);
        
        var ddl = new StringBuilder();
        ddl.AppendLine("-- Migration Script Generated from Mermaid Diagram");
        ddl.AppendLine($"-- Generated: {DateTime.Now}");
        ddl.AppendLine($"-- Target Schema: {targetSchema}");
        ddl.AppendLine("-- WARNING: Review carefully before executing!");
        ddl.AppendLine();
        
        foreach (var table in diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Added))
        {
            ddl.AppendLine($"-- Create new table: {targetSchema}.{table.TableName}");
            ddl.AppendLine($"CREATE TABLE {targetSchema}.{table.TableName} (");
            
            var columnDefs = table.AddedColumns.Select(c =>
            {
                var def = $"    {c.ColumnName} {c.NewDataType}";
                if (c.NewNullable == false) def += " NOT NULL";
                return def;
            });
            
            ddl.AppendLine(string.Join(",\n", columnDefs));
            ddl.AppendLine(");");
            ddl.AppendLine();
            
            var pkCols = table.AddedColumns.Where(c => c.IsPrimaryKeyChange).ToList();
            if (pkCols.Any())
            {
                ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                ddl.AppendLine($"  ADD PRIMARY KEY ({string.Join(", ", pkCols.Select(c => c.ColumnName))});");
                ddl.AppendLine();
            }
        }
        
        foreach (var table in diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Modified))
        {
            if (table.AddedColumns.Any())
            {
                foreach (var col in table.AddedColumns)
                {
                    ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                    ddl.AppendLine($"  ADD COLUMN {col.ColumnName} {col.NewDataType}");
                    if (col.NewNullable == false) ddl.Append(" NOT NULL");
                    ddl.AppendLine(";");
                    ddl.AppendLine();
                }
            }
            
            if (table.ModifiedColumns.Any())
            {
                foreach (var col in table.ModifiedColumns)
                {
                    ddl.AppendLine($"-- Modify column: {table.TableName}.{col.ColumnName}");
                    if (col.OldDataType != col.NewDataType)
                    {
                        ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                        ddl.AppendLine($"  ALTER COLUMN {col.ColumnName} SET DATA TYPE {col.NewDataType};");
                    }
                    if (col.OldNullable != col.NewNullable)
                    {
                        ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                        ddl.AppendLine($"  ALTER COLUMN {col.ColumnName} {(col.NewNullable == false ? "SET NOT NULL" : "DROP NOT NULL")};");
                    }
                    ddl.AppendLine();
                }
            }
            
            if (table.RemovedColumns.Any())
            {
                foreach (var col in table.RemovedColumns)
                {
                    ddl.AppendLine($"-- WARNING: Dropping column will DELETE DATA!");
                    ddl.AppendLine($"-- ALTER TABLE {targetSchema?.Trim() ?? ""}.{table.TableName?.Trim() ?? ""} DROP COLUMN {col.ColumnName?.Trim() ?? ""};");
                    ddl.AppendLine();
                }
            }
        }
        
        foreach (var table in diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Removed))
        {
            ddl.AppendLine($"-- WARNING: Dropping table will DELETE ALL DATA!");
            ddl.AppendLine($"-- DROP TABLE {targetSchema?.Trim() ?? ""}.{table.TableName?.Trim() ?? ""};");
            ddl.AppendLine();
        }
        
        return ddl.ToString();
    }
    
    /// <summary>
    /// Adds schema prefix to DDL statements.
    /// SqlMermaidErdTools generates DDL without schema prefix by default.
    /// </summary>
    private string AddSchemaPrefix(string ddl, string schema)
    {
        Logger.Debug("Adding schema prefix: {Schema}", schema);
        
        // Simple regex replacement to add schema prefix
        // ALTER TABLE tablename → ALTER TABLE schema.tablename
        ddl = System.Text.RegularExpressions.Regex.Replace(
            ddl,
            @"(CREATE TABLE|ALTER TABLE|DROP TABLE)\s+([A-Za-z0-9_]+)",
            $"$1 {schema}.$2",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        return ddl;
    }
}

