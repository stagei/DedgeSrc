using System;
using System.Collections.Generic;

namespace DbExplorer.Models
{
    /// <summary>
    /// Types of database objects that can be compared
    /// </summary>
    public enum SchemaObjectType
    {
        Table,
        View,
        Column,
        Index,
        PrimaryKey,
        UniqueConstraint,
        ForeignKey,
        CheckConstraint,
        Trigger,
        Sequence,
        Procedure,
        Function,
        Package,
        Alias
    }

    /// <summary>
    /// Type of difference between objects
    /// </summary>
    public enum DifferenceType
    {
        /// <summary>Object exists only in source schema</summary>
        OnlyInSource,
        /// <summary>Object exists only in target schema</summary>
        OnlyInTarget,
        /// <summary>Object exists in both but has differences</summary>
        Modified,
        /// <summary>Object is identical in both schemas</summary>
        Identical
    }

    /// <summary>
    /// Direction for applying changes
    /// </summary>
    public enum MergeDirection
    {
        /// <summary>No merge selected</summary>
        None,
        /// <summary>Apply source to target (create/update in target)</summary>
        SourceToTarget,
        /// <summary>Apply target to source (create/update in source)</summary>
        TargetToSource,
        /// <summary>Apply both directions (sync both)</summary>
        Both
    }

    /// <summary>
    /// Represents a database object for comparison
    /// </summary>
    public class SchemaObject
    {
        public string Schema { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public SchemaObjectType ObjectType { get; set; }
        
        /// <summary>Parent object (e.g., table for columns, indexes)</summary>
        public string? ParentName { get; set; }
        
        /// <summary>Full DDL definition of the object</summary>
        public string? Definition { get; set; }
        
        /// <summary>Source code for routines (procedures, functions)</summary>
        public string? SourceCode { get; set; }
        
        /// <summary>Object-specific properties for detailed comparison</summary>
        public Dictionary<string, object?> Properties { get; set; } = new();

        /// <summary>Unique identifier for the object</summary>
        public string FullName => ParentName != null 
            ? $"{Schema}.{ParentName}.{Name}" 
            : $"{Schema}.{Name}";

        public override string ToString() => FullName;
        
        public override int GetHashCode() => FullName.GetHashCode(StringComparison.OrdinalIgnoreCase);
        
        public override bool Equals(object? obj)
        {
            if (obj is SchemaObject other)
                return FullName.Equals(other.FullName, StringComparison.OrdinalIgnoreCase)
                       && ObjectType == other.ObjectType;
            return false;
        }
    }

    /// <summary>
    /// Represents a difference between source and target schemas
    /// </summary>
    public class SchemaDifference
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public SchemaObjectType ObjectType { get; set; }
        public DifferenceType DifferenceType { get; set; }
        
        /// <summary>Object from source schema (null if only in target)</summary>
        public SchemaObject? SourceObject { get; set; }
        
        /// <summary>Object from target schema (null if only in source)</summary>
        public SchemaObject? TargetObject { get; set; }
        
        /// <summary>Property-level differences for modified objects</summary>
        public List<PropertyDifference> PropertyDifferences { get; set; } = new();
        
        /// <summary>Line-by-line differences for source code</summary>
        public List<LineDifference> LineDifferences { get; set; } = new();
        
        /// <summary>User-selected merge direction</summary>
        public MergeDirection MergeDirection { get; set; } = MergeDirection.None;
        
        /// <summary>Is this difference selected for migration</summary>
        public bool IsSelected { get; set; }

        /// <summary>Display name for UI</summary>
        public string DisplayName => SourceObject?.Name ?? TargetObject?.Name ?? "Unknown";
        
        /// <summary>Full name including parent if applicable</summary>
        public string FullName => SourceObject?.FullName ?? TargetObject?.FullName ?? "Unknown";

        /// <summary>Get summary text for the difference</summary>
        public string GetSummary()
        {
            return DifferenceType switch
            {
                DifferenceType.OnlyInSource => $"Only in Source: {DisplayName}",
                DifferenceType.OnlyInTarget => $"Only in Target: {DisplayName}",
                DifferenceType.Modified => $"Modified: {DisplayName} ({PropertyDifferences.Count} differences)",
                DifferenceType.Identical => $"Identical: {DisplayName}",
                _ => DisplayName
            };
        }
    }

    /// <summary>
    /// Represents a difference in a specific property
    /// </summary>
    public class PropertyDifference
    {
        public string PropertyName { get; set; } = string.Empty;
        public string? SourceValue { get; set; }
        public string? TargetValue { get; set; }
        public bool IsSignificant { get; set; } = true;

        public override string ToString() => 
            $"{PropertyName}: '{SourceValue ?? "(null)"}' → '{TargetValue ?? "(null)"}'";
    }

    /// <summary>
    /// Represents a line difference for source code comparison
    /// </summary>
    public class LineDifference
    {
        public int LineNumber { get; set; }
        public LineDifferenceType Type { get; set; }
        public string? SourceLine { get; set; }
        public string? TargetLine { get; set; }
    }

    public enum LineDifferenceType
    {
        Unchanged,
        Added,
        Removed,
        Modified
    }

    /// <summary>
    /// Complete comparison result between two schemas
    /// </summary>
    public class SchemaComparisonResult
    {
        public string SourceSchema { get; set; } = string.Empty;
        public string TargetSchema { get; set; } = string.Empty;
        public string SourceConnectionName { get; set; } = string.Empty;
        public string TargetConnectionName { get; set; } = string.Empty;
        public DateTime ComparisonTime { get; set; } = DateTime.Now;
        
        /// <summary>All differences organized by object type</summary>
        public Dictionary<SchemaObjectType, List<SchemaDifference>> DifferencesByType { get; set; } = new();
        
        /// <summary>Summary statistics</summary>
        public ComparisonSummary Summary { get; set; } = new();

        /// <summary>Get all differences as a flat list</summary>
        public IEnumerable<SchemaDifference> GetAllDifferences()
        {
            foreach (var kvp in DifferencesByType)
            {
                foreach (var diff in kvp.Value)
                {
                    yield return diff;
                }
            }
        }

        /// <summary>Get differences by type filter</summary>
        public IEnumerable<SchemaDifference> GetDifferences(DifferenceType type)
        {
            return GetAllDifferences().Where(d => d.DifferenceType == type);
        }

        /// <summary>Get selected differences for migration</summary>
        public IEnumerable<SchemaDifference> GetSelectedDifferences()
        {
            return GetAllDifferences().Where(d => d.IsSelected && d.MergeDirection != MergeDirection.None);
        }
    }

    /// <summary>
    /// Summary statistics for comparison
    /// </summary>
    public class ComparisonSummary
    {
        public int TotalObjectsInSource { get; set; }
        public int TotalObjectsInTarget { get; set; }
        public int OnlyInSourceCount { get; set; }
        public int OnlyInTargetCount { get; set; }
        public int ModifiedCount { get; set; }
        public int IdenticalCount { get; set; }

        /// <summary>Counts by object type</summary>
        public Dictionary<SchemaObjectType, ObjectTypeSummary> ByObjectType { get; set; } = new();

        public int TotalDifferences => OnlyInSourceCount + OnlyInTargetCount + ModifiedCount;

        public string GetSummaryText()
        {
            return $"Comparison Summary:\n" +
                   $"  Source objects: {TotalObjectsInSource}\n" +
                   $"  Target objects: {TotalObjectsInTarget}\n" +
                   $"  Only in Source: {OnlyInSourceCount}\n" +
                   $"  Only in Target: {OnlyInTargetCount}\n" +
                   $"  Modified: {ModifiedCount}\n" +
                   $"  Identical: {IdenticalCount}";
        }
    }

    /// <summary>
    /// Summary for a specific object type
    /// </summary>
    public class ObjectTypeSummary
    {
        public SchemaObjectType ObjectType { get; set; }
        public int SourceCount { get; set; }
        public int TargetCount { get; set; }
        public int OnlyInSource { get; set; }
        public int OnlyInTarget { get; set; }
        public int Modified { get; set; }
        public int Identical { get; set; }
    }

    /// <summary>
    /// DDL script generated from selected differences
    /// </summary>
    public class MigrationScript
    {
        public string ConnectionName { get; set; } = string.Empty;
        public string TargetSchema { get; set; } = string.Empty;
        public MergeDirection Direction { get; set; }
        public List<string> DdlStatements { get; set; } = new();
        public List<SchemaDifference> SourceDifferences { get; set; } = new();

        /// <summary>Get the complete script</summary>
        public string GetFullScript()
        {
            var header = $"-- Migration Script\n" +
                        $"-- Target: {ConnectionName}.{TargetSchema}\n" +
                        $"-- Direction: {Direction}\n" +
                        $"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}\n" +
                        $"-- Objects: {SourceDifferences.Count}\n" +
                        $"-- ============================================\n\n";

            return header + string.Join("\n\n", DdlStatements);
        }
    }
}
