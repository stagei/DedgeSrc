namespace AutoDocNew.Models;

/// <summary>
/// BAT parser result – all data needed to render a BAT doc page.
/// </summary>
public class BatResult : DocFileResult
{
    public BatMetadata Metadata { get; set; } = new();
    public DiagramData Diagrams { get; set; } = new();
    public List<ScriptRef> CalledScripts { get; set; } = new();
    public List<SubprogramRef> CalledPrograms { get; set; } = new();
    public List<ChangeLogEntry> ChangeLog { get; set; } = new();
}

public class BatMetadata
{
    public bool UsesSql { get; set; }
    public bool UsesRexx { get; set; }
    public string Created { get; set; } = "";
}
