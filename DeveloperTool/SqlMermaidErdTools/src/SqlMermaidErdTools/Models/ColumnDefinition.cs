namespace SqlMermaidErdTools.Models;

/// <summary>
/// Represents a column definition in a database table.
/// </summary>
/// <param name="Name">The name of the column</param>
/// <param name="DataType">The data type of the column (e.g., INT, VARCHAR, etc.)</param>
/// <param name="Length">Optional length/size for data types that support it (e.g., VARCHAR(255))</param>
/// <param name="Precision">Optional precision for numeric types (e.g., DECIMAL(10,2))</param>
/// <param name="Scale">Optional scale for numeric types (e.g., DECIMAL(10,2))</param>
/// <param name="IsNullable">Indicates whether the column allows NULL values</param>
/// <param name="IsPrimaryKey">Indicates whether the column is part of the primary key</param>
/// <param name="IsForeignKey">Indicates whether the column is a foreign key</param>
/// <param name="IsUnique">Indicates whether the column has a unique constraint</param>
/// <param name="DefaultValue">Optional default value for the column</param>
/// <param name="Comment">Optional comment or description for the column</param>
/// <param name="ReferencedTable">If foreign key, the table it references</param>
/// <param name="ReferencedColumn">If foreign key, the column it references</param>
public record ColumnDefinition(
    string Name,
    string DataType,
    int? Length = null,
    int? Precision = null,
    int? Scale = null,
    bool IsNullable = true,
    bool IsPrimaryKey = false,
    bool IsForeignKey = false,
    bool IsUnique = false,
    string? DefaultValue = null,
    string? Comment = null,
    string? ReferencedTable = null,
    string? ReferencedColumn = null
)
{
    /// <summary>
    /// Gets the full data type specification including length/precision.
    /// </summary>
    public string FullDataType => Length.HasValue
        ? $"{DataType}({Length})"
        : Precision.HasValue && Scale.HasValue
            ? $"{DataType}({Precision},{Scale})"
            : Precision.HasValue
                ? $"{DataType}({Precision})"
                : DataType;

    /// <summary>
    /// Gets the constraint markers for the column (PK, FK, UK, NOT NULL).
    /// </summary>
    public string ConstraintMarkers
    {
        get
        {
            var markers = new List<string>();
            if (IsPrimaryKey) markers.Add("PK");
            if (IsForeignKey) markers.Add("FK");
            if (IsUnique && !IsPrimaryKey) markers.Add("UK");
            if (!IsNullable) markers.Add("NOT NULL");
            if (DefaultValue != null) markers.Add($"DEFAULT {DefaultValue}");
            return string.Join(", ", markers);
        }
    }
}

