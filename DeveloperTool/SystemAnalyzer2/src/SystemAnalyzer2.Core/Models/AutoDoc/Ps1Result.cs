namespace SystemAnalyzer2.Core.Models.AutoDoc;

/// <summary>
/// PowerShell parser result – all data needed to render a PS1/PSM1 doc page.
/// </summary>
public class Ps1Result : DocFileResult
{
    public Ps1Metadata Metadata { get; set; } = new();
    public DiagramData Diagrams { get; set; } = new();
    public List<ScriptRef> CalledScripts { get; set; } = new();
    public List<SubprogramRef> CalledPrograms { get; set; } = new();
    public List<ChangeLogEntry> ChangeLog { get; set; } = new();
    public List<string> Functions { get; set; } = new();
}

public class Ps1Metadata
{
    public bool UsesSql { get; set; }
    public bool UsesFtp { get; set; }
    public bool UsesWebservice { get; set; }
    public string Created { get; set; } = "";
}
