using System.Text.Json.Serialization;

namespace AutoDocNew.Models;

/// <summary>
/// Base model for all per-file JSON output from parsers.
/// Each parser type extends this with type-specific data.
/// </summary>
public class DocFileResult
{
    /// <summary>File type: CBL, BAT, PS1, REX, SQL, CSharp</summary>
    public string Type { get; set; } = "";

    /// <summary>Base file name (e.g. BSAUTOS.CBL, Db2-DiagTracker.ps1)</summary>
    public string FileName { get; set; } = "";

    /// <summary>Page title</summary>
    public string Title { get; set; } = "";

    /// <summary>Description / synopsis</summary>
    public string Description { get; set; } = "";

    /// <summary>ISO timestamp when this JSON was generated</summary>
    public string GeneratedAt { get; set; } = "";

    /// <summary>Source file reference (lowercase) for links</summary>
    public string SourceFile { get; set; } = "";

    /// <summary>Git history statistics for the source file</summary>
    public GitHistory? GitHistory { get; set; }
}

/// <summary>Mermaid diagram pair (flow + sequence or others)</summary>
public class DiagramData
{
    public string FlowMmd { get; set; } = "";
    public string SequenceMmd { get; set; } = "";
    public string ProcessMmd { get; set; } = "";
}

/// <summary>Reference to an SQL table used by a program</summary>
public class SqlTableRef
{
    public string Table { get; set; } = "";
    public string Operation { get; set; } = "";
    public string Description { get; set; } = "";
    public string Link { get; set; } = "";
}

/// <summary>Reference to a called COBOL subprogram</summary>
public class SubprogramRef
{
    public string Module { get; set; } = "";
    public string Description { get; set; } = "";
    public string Type { get; set; } = "";
    public string System { get; set; } = "";
    public string Link { get; set; } = "";
}

/// <summary>Reference to a called script (BAT/PS1/REX)</summary>
public class ScriptRef
{
    public string Name { get; set; } = "";
    public string Link { get; set; } = "";
}

/// <summary>Reference to a COBOL COPY element</summary>
public class CopyElementRef
{
    public string Name { get; set; } = "";
    public string Link { get; set; } = "";
}

/// <summary>Changelog entry from source file comments or modkom.csv</summary>
public class ChangeLogEntry
{
    public string Date { get; set; } = "";
    public string User { get; set; } = "";
    public string Comment { get; set; } = "";
}

/// <summary>Production log entry from tiltp_log.csv</summary>
public class ProductionLogEntry
{
    public string Date { get; set; } = "";
    public string User { get; set; } = "";
}

/// <summary>Git history statistics with human-friendly property names</summary>
public class GitHistory
{
    /// <summary>Date of the most recent commit touching this file</summary>
    public string LastChanged { get; set; } = "";

    /// <summary>Author of the most recent commit</summary>
    public string ChangedBy { get; set; } = "";

    /// <summary>Total number of commits that touched this file</summary>
    public int TotalChanges { get; set; }

    /// <summary>Date of the earliest commit that introduced this file</summary>
    public string FirstAdded { get; set; } = "";

    /// <summary>Number of distinct authors</summary>
    public int Contributors { get; set; }

    /// <summary>List of contributors with their commit counts</summary>
    public List<GitContributor> ContributorList { get; set; } = new();
}

/// <summary>A single git contributor and their commit count</summary>
public class GitContributor
{
    public string Name { get; set; } = "";
    public int Changes { get; set; }
}
