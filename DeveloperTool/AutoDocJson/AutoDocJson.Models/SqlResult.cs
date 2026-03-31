namespace AutoDocNew.Models;

/// <summary>
/// SQL table parser result – all data needed to render a SQL doc page.
/// </summary>
public class SqlResult : DocFileResult
{
    public SqlMetadata Metadata { get; set; } = new();
    public List<SqlColumnDef> Columns { get; set; } = new();
    public string ErDiagramMmd { get; set; } = "";
    public List<SqlIndexDef> Indexes { get; set; } = new();
    public SqlPrimaryKeyDef? PrimaryKey { get; set; }
    public List<SqlUniqueKeyDef> UniqueKeys { get; set; } = new();
    public List<SqlForeignKeyDef> ForeignKeysOutgoing { get; set; } = new();
    public List<SqlForeignKeyDef> ForeignKeysIncoming { get; set; } = new();
    public List<SqlTriggerDef> Triggers { get; set; } = new();
    public string InteractionDiagramMmd { get; set; } = "";
    public List<SqlUsageDef> UsedBy { get; set; } = new();
    public SqlStatsDef? Stats { get; set; }
}

public class SqlUsageDef
{
    public string ProgramName { get; set; } = "";
    public string FileType { get; set; } = "";
    public string FilePath { get; set; } = "";
    public string Description { get; set; } = "";
    public string GeneratedAt { get; set; } = "";
}

public class SqlMetadata
{
    public string Schema { get; set; } = "";
    public string TableName { get; set; } = "";
    public string FullName { get; set; } = "";
    public string Comment { get; set; } = "";
    /// <summary>"Sql Table" or "Sql View"</summary>
    public string TableType { get; set; } = "";
    public string AlterTime { get; set; } = "";
}

public class SqlColumnDef
{
    public string Name { get; set; } = "";
    public int Number { get; set; }
    public string DataType { get; set; } = "";
    public string Length { get; set; } = "";
    public string Scale { get; set; } = "";
    public bool Nullable { get; set; }
    public bool IsPrimaryKey { get; set; }
    public bool IsForeignKey { get; set; }
    public string Remarks { get; set; } = "";
}

public class SqlIndexDef
{
    public string Name { get; set; } = "";
    public string IndexType { get; set; } = "";
    public bool IsUnique { get; set; }
    public string Columns { get; set; } = "";
    public string Levels { get; set; } = "";
}

public class SqlPrimaryKeyDef
{
    public string ConstraintName { get; set; } = "";
    public List<string> Columns { get; set; } = new();
}

public class SqlUniqueKeyDef
{
    public string ConstraintName { get; set; } = "";
    public List<string> Columns { get; set; } = new();
}

public class SqlForeignKeyDef
{
    public string ConstraintName { get; set; } = "";
    public string FkColumns { get; set; } = "";
    public string ReferencedTable { get; set; } = "";
    public string PkColumns { get; set; } = "";
    public string DeleteRule { get; set; } = "";
    public string Link { get; set; } = "";
}

public class SqlTriggerDef
{
    public string Name { get; set; } = "";
    public string Timing { get; set; } = "";
    public string Event { get; set; } = "";
    public string Granularity { get; set; } = "";
    public bool IsValid { get; set; }
}

public class SqlStatsDef
{
    public int RowCount { get; set; }
    public int DataPages { get; set; }
    public int ColumnCount { get; set; }
    public int IndexCount { get; set; }
    public int TriggerCount { get; set; }
    public int ParentTableCount { get; set; }
    public int ChildTableCount { get; set; }
}
