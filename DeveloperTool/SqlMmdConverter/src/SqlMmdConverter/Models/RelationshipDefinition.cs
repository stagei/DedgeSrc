namespace SqlMmdConverter.Models;

/// <summary>
/// Represents a relationship between two tables in a database schema.
/// </summary>
/// <param name="FromTable">The source table name</param>
/// <param name="ToTable">The target/referenced table name</param>
/// <param name="FromColumn">The column in the source table</param>
/// <param name="ToColumn">The column in the target table</param>
/// <param name="Cardinality">The cardinality of the relationship</param>
/// <param name="Label">Optional label describing the relationship (e.g., "places", "contains")</param>
public record RelationshipDefinition(
    string FromTable,
    string ToTable,
    string FromColumn,
    string ToColumn,
    RelationshipCardinality Cardinality,
    string? Label = null
);

/// <summary>
/// Represents the cardinality of a relationship between tables.
/// </summary>
public enum RelationshipCardinality
{
    /// <summary>
    /// One-to-one relationship (||--||)
    /// </summary>
    OneToOne,

    /// <summary>
    /// One-to-many relationship (||--o{)
    /// </summary>
    OneToMany,

    /// <summary>
    /// Zero-or-one relationship (||--o|)
    /// </summary>
    ZeroOrOne,

    /// <summary>
    /// Zero-or-many relationship (||--o{)
    /// </summary>
    ZeroOrMany,

    /// <summary>
    /// Many-to-many relationship (}o--o{)
    /// </summary>
    ManyToMany
}

