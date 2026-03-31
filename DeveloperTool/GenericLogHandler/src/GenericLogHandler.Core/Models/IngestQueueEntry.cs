using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Temporary queue row for the log ingest API. The WebApi INSERTs the raw JSON payload;
/// the ImportService drains the queue FIFO, converts to LogEntry, and deletes.
/// </summary>
[Table("ingest_queue")]
public class IngestQueueEntry
{
    [Key]
    [Column("id")]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public long Id { get; set; }

    [Required]
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [Required]
    [Column("payload", TypeName = "jsonb")]
    public string Payload { get; set; } = string.Empty;
}
