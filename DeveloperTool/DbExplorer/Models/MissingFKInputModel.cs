using System;
using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Input JSON model for Missing FK Discovery batch job.
/// Contains snapshot of selected tables and their metadata.
/// </summary>
public class MissingFKInputModel
{
    public string JobId { get; set; } = string.Empty;
    public DateTime GeneratedAtUtc { get; set; }
    public string ConnectionProfile { get; set; } = string.Empty;
    public string Provider { get; set; } = string.Empty;
    public string ProviderVersion { get; set; } = string.Empty;
    public MissingFKOptions Options { get; set; } = new();
    public List<TableReference> SelectedTables { get; set; } = new();
    public List<MissingFKTableMetadata> Tables { get; set; } = new();
}
