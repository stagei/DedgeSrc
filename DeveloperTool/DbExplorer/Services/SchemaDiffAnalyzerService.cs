using System;
using System.Collections.Generic;
using System.Linq;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

public class SchemaDiffAnalyzerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MermaidDiagramGeneratorService _mermaidService;
    
    public SchemaDiffAnalyzerService()
    {
        _mermaidService = new MermaidDiagramGeneratorService();
    }
    
    public SchemaDiff AnalyzeDifferences(string originalMermaid, string editedMermaid)
    {
        Logger.Info("Analyzing schema differences");
        
        var originalTables = _mermaidService.ParseMermaidDiagram(originalMermaid);
        var editedTables = _mermaidService.ParseMermaidDiagram(editedMermaid);
        
        var diff = new SchemaDiff();
        
        var addedTables = editedTables.Keys.Except(originalTables.Keys);
        foreach (var tableName in addedTables)
        {
            var table = editedTables[tableName];
            diff.TableChanges.Add(new TableDiff
            {
                TableName = tableName,
                Schema = table.Schema,
                ChangeType = TableChangeType.Added,
                AddedColumns = table.Columns.Select(c => new ColumnChange
                {
                    ColumnName = c.Name,
                    NewDataType = c.DataType,
                    NewNullable = c.IsNullable,
                    IsPrimaryKeyChange = c.IsPrimaryKey,
                    Type = ChangeType.Added
                }).ToList()
            });
        }
        
        var removedTables = originalTables.Keys.Except(editedTables.Keys);
        foreach (var tableName in removedTables)
        {
            diff.TableChanges.Add(new TableDiff
            {
                TableName = tableName,
                ChangeType = TableChangeType.Removed
            });
        }
        
        var commonTables = originalTables.Keys.Intersect(editedTables.Keys);
        foreach (var tableName in commonTables)
        {
            var tableDiff = CompareTableStructures(
                originalTables[tableName],
                editedTables[tableName]);
            
            if (tableDiff.HasChanges)
            {
                diff.TableChanges.Add(tableDiff);
            }
        }
        
        Logger.Info("Diff complete: {Added} added, {Removed} removed, {Modified} modified",
            diff.TableChanges.Count(t => t.ChangeType == TableChangeType.Added),
            diff.TableChanges.Count(t => t.ChangeType == TableChangeType.Removed),
            diff.TableChanges.Count(t => t.ChangeType == TableChangeType.Modified));
        
        return diff;
    }
    
    private TableDiff CompareTableStructures(MermaidTable original, MermaidTable edited)
    {
        var diff = new TableDiff
        {
            TableName = original.Name,
            Schema = original.Schema,
            ChangeType = TableChangeType.Modified
        };
        
        var originalCols = original.Columns.ToDictionary(c => c.Name);
        var editedCols = edited.Columns.ToDictionary(c => c.Name);
        
        foreach (var colName in editedCols.Keys.Except(originalCols.Keys))
        {
            var col = editedCols[colName];
            diff.AddedColumns.Add(new ColumnChange
            {
                ColumnName = colName,
                NewDataType = col.DataType,
                NewNullable = col.IsNullable,
                IsPrimaryKeyChange = col.IsPrimaryKey,
                Type = ChangeType.Added
            });
        }
        
        foreach (var colName in originalCols.Keys.Except(editedCols.Keys))
        {
            diff.RemovedColumns.Add(new ColumnChange
            {
                ColumnName = colName,
                Type = ChangeType.Removed
            });
        }
        
        foreach (var colName in originalCols.Keys.Intersect(editedCols.Keys))
        {
            var origCol = originalCols[colName];
            var editCol = editedCols[colName];
            
            if (origCol.DataType != editCol.DataType || 
                origCol.IsNullable != editCol.IsNullable ||
                origCol.IsPrimaryKey != editCol.IsPrimaryKey)
            {
                diff.ModifiedColumns.Add(new ColumnChange
                {
                    ColumnName = colName,
                    OldDataType = origCol.DataType,
                    NewDataType = editCol.DataType,
                    OldNullable = origCol.IsNullable,
                    NewNullable = editCol.IsNullable,
                    Type = ChangeType.Modified
                });
            }
        }
        
        return diff;
    }
}

