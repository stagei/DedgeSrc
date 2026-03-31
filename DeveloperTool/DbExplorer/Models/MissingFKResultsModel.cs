using System;
using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Results JSON model for Missing FK Discovery batch job.
/// Contains analysis results with candidate foreign keys and evidence.
/// </summary>
public class MissingFKResultsModel
{
    public string JobId { get; set; } = string.Empty;
    public DateTime CompletedAtUtc { get; set; }
    public MissingFKSummary Summary { get; set; } = new();
    public List<MissingFKCandidate> Candidates { get; set; } = new();
    public List<TableReference> TablesWithoutKeys { get; set; } = new();
}
