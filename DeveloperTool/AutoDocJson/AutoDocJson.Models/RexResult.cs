namespace AutoDocNew.Models;

/// <summary>
/// Object-Rexx parser result – all data needed to render a REX doc page.
/// </summary>
public class RexResult : DocFileResult
{
    public RexMetadata Metadata { get; set; } = new();
    public DiagramData Diagrams { get; set; } = new();
    public List<ScriptRef> CalledScripts { get; set; } = new();
    public List<SubprogramRef> CalledPrograms { get; set; } = new();
    public List<ChangeLogEntry> ChangeLog { get; set; } = new();
}

public class RexMetadata
{
    public bool UsesSql { get; set; }
    public bool UsesFtp { get; set; }
    public string Created { get; set; } = "";
}
