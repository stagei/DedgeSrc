namespace SystemAnalyzer2.Core.Models.AutoDoc;

/// <summary>
/// COBOL parser result – all data needed to render a CBL doc page.
/// </summary>
public class CblResult : DocFileResult
{
    public CblMetadata Metadata { get; set; } = new();
    public DiagramData Diagrams { get; set; } = new();
    public List<SqlTableRef> SqlTables { get; set; } = new();
    public List<SubprogramRef> CalledSubprograms { get; set; } = new();
    public List<CopyElementRef> CopyElements { get; set; } = new();
    public List<ChangeLogEntry> ChangeLog { get; set; } = new();
    public List<ProductionLogEntry> ProductionLog { get; set; } = new();
}

public class CblMetadata
{
    /// <summary>Type code: B, H, S, V, A, F</summary>
    public string TypeCode { get; set; } = "";

    /// <summary>Full type label (e.g. "B - Batchprogram")</summary>
    public string TypeLabel { get; set; } = "";

    /// <summary>System name</summary>
    public string System { get; set; } = "";

    /// <summary>Uses SQL flag</summary>
    public bool UsesSql { get; set; }

    /// <summary>Uses Dialog System flag</summary>
    public bool UsesDialogSystem { get; set; }

    /// <summary>Screen layout link (if dialog system)</summary>
    public string ScreenLink { get; set; } = "";

    /// <summary>Screen layout text label</summary>
    public string ScreenLinkText { get; set; } = "";

    /// <summary>Created date/time</summary>
    public string Created { get; set; } = "";

    /// <summary>Last production date/time</summary>
    public string LastProduction { get; set; } = "";
}
