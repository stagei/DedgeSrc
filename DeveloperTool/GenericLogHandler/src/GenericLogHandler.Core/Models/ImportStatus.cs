using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Tracks the status of import operations
/// </summary>
[Table("import_status")]
public class ImportStatus
{
    /// <summary>
    /// Unique identifier for the import status record
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Name of the import source
    /// </summary>
    [Required]
    [Column("source_name")]
    [MaxLength(200)]
    public string SourceName { get; set; } = string.Empty;

    /// <summary>
    /// Type of source (file, database, eventlog, etc.)
    /// </summary>
    [Required]
    [Column("source_type")]
    [MaxLength(50)]
    public string SourceType { get; set; } = string.Empty;

    /// <summary>
    /// File path being processed (if applicable)
    /// </summary>
    [Column("file_path")]
    [MaxLength(1000)]
    public string FilePath { get; set; } = string.Empty;

    /// <summary>
    /// Last timestamp of data that was successfully processed
    /// </summary>
    [Column("last_processed_timestamp")]
    public DateTime? LastProcessedTimestamp { get; set; }

    /// <summary>
    /// Timestamp when the last import operation was performed
    /// </summary>
    [Column("last_import_timestamp")]
    public DateTime LastImportTimestamp { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Number of records successfully processed in the last run
    /// </summary>
    [Column("records_processed")]
    public long RecordsProcessed { get; set; }

    /// <summary>
    /// Number of records that failed processing in the last run
    /// </summary>
    [Column("records_failed")]
    public long RecordsFailed { get; set; }

    /// <summary>
    /// Current status of the import operation
    /// </summary>
    [Column("status")]
    public ImportStatusType Status { get; set; } = ImportStatusType.Pending;

    /// <summary>
    /// Error message if the import failed
    /// </summary>
    [Column("error_message")]
    public string ErrorMessage { get; set; } = string.Empty;

    /// <summary>
    /// Duration of the last processing operation in milliseconds
    /// </summary>
    [Column("processing_duration_ms")]
    public long ProcessingDurationMs { get; set; }

    /// <summary>
    /// Additional metadata about the import operation
    /// </summary>
    [Column("metadata")]
    public string Metadata { get; set; } = string.Empty;

    /// <summary>
    /// Last processed byte offset in the file for incremental reads
    /// </summary>
    [Column("last_processed_byte_offset")]
    public long LastProcessedByteOffset { get; set; }

    /// <summary>
    /// Hash of the file to detect file rotation (first 1KB + file size)
    /// </summary>
    [Column("file_hash")]
    [MaxLength(64)]
    public string? FileHash { get; set; }

    /// <summary>
    /// File size at last processing
    /// </summary>
    [Column("last_file_size")]
    public long LastFileSize { get; set; }

    /// <summary>
    /// File creation date (UTC) - used to detect file rotation for append-only files
    /// </summary>
    [Column("file_creation_date")]
    public DateTime? FileCreationDate { get; set; }

    /// <summary>
    /// Last processed line number for append-only files (1-based)
    /// </summary>
    [Column("last_processed_line")]
    public long LastProcessedLine { get; set; }

    /// <summary>
    /// Calculates the processing rate (records per second)
    /// </summary>
    public double GetProcessingRate()
    {
        if (ProcessingDurationMs <= 0) return 0;
        return (double)RecordsProcessed / (ProcessingDurationMs / 1000.0);
    }

    /// <summary>
    /// Calculates the error rate as a percentage
    /// </summary>
    public double GetErrorRate()
    {
        var totalRecords = RecordsProcessed + RecordsFailed;
        if (totalRecords <= 0) return 0;
        return (double)RecordsFailed / totalRecords * 100;
    }
}

/// <summary>
/// Import operation status types
/// </summary>
public enum ImportStatusType
{
    Pending = 1,
    Processing = 2,
    Completed = 3,
    Failed = 4,
    Paused = 5
}
