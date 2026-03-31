/// <summary>
/// Defines SQL-related types and error codes used throughout the Dedge system.
/// Provides standardized error handling and status reporting for database operations.
/// </summary>
/// <remarks>
/// Features:
/// - Comprehensive SQL error code definitions
/// - Error mapping between different database providers
/// - Status information structure
/// - Error message formatting
/// - Operation result tracking
/// - Cross-database compatibility
/// </remarks>
/// <author>Geir Helge Starholm</author>
namespace DedgeCommon
{
    /// <summary>
    /// Common error codes shared between database providers
    /// </summary>
    public enum DbSqlError
    {
        Success = 0,
        NotFound = -1,
        UnknownError = -99,
    }

    /// <summary>
    /// Represents SQL execution status information
    /// </summary>
    public class SqlInfo
    {
        public DbSqlError SqlCode { get; set; }
        public string? ExeceptionMessage { get; set; }
        public string? InnerExeceptionMessage { get; set; }
        public string? SqlCodeShortDescription { get; set; }
        public string? SqlCodeDescription { get; set; }
        public int RowsAffected { get; set; }
        public int RowCount { get; set; }
        public string? SqlStatement { get; set; }
        public string? PrimaryTableName { get; set; } = "Unknown";

        public override string ToString()
        {
            return $"{Environment.NewLine}SqlCode: {SqlCode}{Environment.NewLine}" +
                   $"ExeceptionMessage: {ExeceptionMessage}{Environment.NewLine}" +
                   $"InnerExeceptionMessage: {InnerExeceptionMessage}{Environment.NewLine}" +
                   $"SqlCodeShortDescription: {SqlCodeShortDescription}{Environment.NewLine}" +
                   $"SqlCodeDescription: {SqlCodeDescription}{Environment.NewLine}" +
                   $"RowsAffected: {RowsAffected}{Environment.NewLine}" +
                   $"RowCount: {RowCount}{Environment.NewLine}" +
                   $"PrimaryTableName: {PrimaryTableName}{Environment.NewLine}" +
                   $"SqlStatement: {Environment.NewLine}{SqlStatement}{Environment.NewLine}";
        }
    }
}