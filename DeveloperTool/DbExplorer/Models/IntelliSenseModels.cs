namespace DbExplorer.Models;

/// <summary>
/// Column information for IntelliSense.
/// </summary>
public class ColumnInfo
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public bool IsNullable { get; set; }
    public bool IsPrimaryKey { get; set; }
    public string? DefaultValue { get; set; }
    public int? Length { get; set; }
}

/// <summary>
/// Table information for IntelliSense.
/// </summary>
public class TableInfo
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string FullName => $"{Schema}.{Name}";
    public long RowCount { get; set; }
    public List<ColumnInfo> Columns { get; set; } = new();
}

/// <summary>
/// View information for IntelliSense.
/// </summary>
public class ViewInfo
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string FullName => $"{Schema}.{Name}";
}

/// <summary>
/// Procedure information for IntelliSense.
/// </summary>
public class ProcedureInfo
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string FullName => $"{Schema}.{Name}";
    public List<ParameterInfo> Parameters { get; set; } = new();
}

/// <summary>
/// Function information for IntelliSense.
/// </summary>
public class FunctionInfo
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string FullName => $"{Schema}.{Name}";
    public string ReturnType { get; set; } = string.Empty;
    public List<ParameterInfo> Parameters { get; set; } = new();
}

/// <summary>
/// Parameter information for procedures/functions.
/// </summary>
public class ParameterInfo
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public string Mode { get; set; } = string.Empty; // IN, OUT, INOUT
    public int Position { get; set; }
}

