using System.Collections.Generic;

namespace DbExplorer.Models;

public class MermaidTable
{
    public string Name { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public List<MermaidColumn> Columns { get; set; } = new();
    public List<MermaidRelationship> Relationships { get; set; } = new();
}

public class MermaidColumn
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public bool IsPrimaryKey { get; set; }
    public bool IsForeignKey { get; set; }
    public bool IsNullable { get; set; } = true;
    public string? Comment { get; set; }
}

public class MermaidRelationship
{
    public string FromTable { get; set; } = string.Empty;
    public string ToTable { get; set; } = string.Empty;
    public string Cardinality { get; set; } = "||--o{";
    public string? Label { get; set; }
}

public class SchemaDiff
{
    public List<TableDiff> TableChanges { get; set; } = new();
    public bool HasChanges => TableChanges.Any(t => t.HasChanges);
    public int TotalChanges => TableChanges.Sum(t => t.ChangeCount);
    public int TableCount => TableChanges.Count(t => t.HasChanges);
}

public class TableDiff
{
    public string TableName { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public TableChangeType ChangeType { get; set; }
    public List<ColumnChange> AddedColumns { get; set; } = new();
    public List<ColumnChange> RemovedColumns { get; set; } = new();
    public List<ColumnChange> ModifiedColumns { get; set; } = new();
    public List<FKChange> AddedForeignKeys { get; set; } = new();
    public List<FKChange> RemovedForeignKeys { get; set; } = new();
    
    public bool HasChanges => 
        AddedColumns.Any() || 
        RemovedColumns.Any() || 
        ModifiedColumns.Any() || 
        AddedForeignKeys.Any() || 
        RemovedForeignKeys.Any() ||
        ChangeType != TableChangeType.None;
    
    public int ChangeCount => 
        AddedColumns.Count + 
        RemovedColumns.Count + 
        ModifiedColumns.Count + 
        AddedForeignKeys.Count + 
        RemovedForeignKeys.Count;
}

public enum TableChangeType
{
    None,
    Added,
    Removed,
    Modified
}

public class ColumnChange
{
    public string ColumnName { get; set; } = string.Empty;
    public string? OldDataType { get; set; }
    public string? NewDataType { get; set; }
    public bool? OldNullable { get; set; }
    public bool? NewNullable { get; set; }
    public bool IsPrimaryKeyChange { get; set; }
    public ChangeType Type { get; set; }
}

public class FKChange
{
    public string ConstraintName { get; set; } = string.Empty;
    public string FromTable { get; set; } = string.Empty;
    public string ToTable { get; set; } = string.Empty;
    public List<string> Columns { get; set; } = new();
    public ChangeType Type { get; set; }
}

public enum ChangeType
{
    Added,
    Removed,
    Modified
}

