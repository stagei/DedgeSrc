namespace SqlMermaidErdTools.Models;

/// <summary>
/// Represents a database table definition including its columns and relationships.
/// </summary>
/// <param name="Name">The name of the table</param>
/// <param name="Schema">Optional schema name (e.g., "dbo", "public")</param>
/// <param name="Columns">The columns in the table</param>
/// <param name="Comment">Optional comment or description for the table</param>
public record TableDefinition(
    string Name,
    string? Schema = null,
    IReadOnlyList<ColumnDefinition>? Columns = null,
    string? Comment = null
)
{
    /// <summary>
    /// Gets the columns in the table.
    /// </summary>
    public IReadOnlyList<ColumnDefinition> Columns { get; init; } = Columns ?? Array.Empty<ColumnDefinition>();

    /// <summary>
    /// Gets the full table name including schema if present.
    /// </summary>
    public string FullName => string.IsNullOrEmpty(Schema) ? Name : $"{Schema}.{Name}";

    /// <summary>
    /// Gets the primary key columns for this table.
    /// </summary>
    public IEnumerable<ColumnDefinition> PrimaryKeyColumns =>
        Columns.Where(c => c.IsPrimaryKey);

    /// <summary>
    /// Gets the foreign key columns for this table.
    /// </summary>
    public IEnumerable<ColumnDefinition> ForeignKeyColumns =>
        Columns.Where(c => c.IsForeignKey);

    /// <summary>
    /// Gets the unique columns (excluding primary keys) for this table.
    /// </summary>
    public IEnumerable<ColumnDefinition> UniqueColumns =>
        Columns.Where(c => c.IsUnique && !c.IsPrimaryKey);

    /// <summary>
    /// Checks if the table has a specific column by name.
    /// </summary>
    /// <param name="columnName">The name of the column to find</param>
    /// <returns>True if the column exists, false otherwise</returns>
    public bool HasColumn(string columnName) =>
        Columns.Any(c => c.Name.Equals(columnName, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Gets a column by name.
    /// </summary>
    /// <param name="columnName">The name of the column to get</param>
    /// <returns>The column definition or null if not found</returns>
    public ColumnDefinition? GetColumn(string columnName) =>
        Columns.FirstOrDefault(c => c.Name.Equals(columnName, StringComparison.OrdinalIgnoreCase));
}

