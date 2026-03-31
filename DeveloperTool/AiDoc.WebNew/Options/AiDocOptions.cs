namespace AiDoc.WebNew.Options;

public class AiDocOptions
{
    /// <summary>
    /// Path to the RAG library, relative to $OptPath (e.g. "data\AiDoc.Library").
    /// Joined with $env:OptPath at runtime. Absolute paths are used as-is.
    /// </summary>
    public string LibraryRoot { get; set; } = "";

    /// <summary>
    /// Path to the Python RAG engine, relative to $OptPath (e.g. "FkPythonApps\AiDoc.Python").
    /// Joined with $env:OptPath at runtime. Absolute paths are used as-is.
    /// </summary>
    public string PythonRoot { get; set; } = "";

    /// <summary>
    /// Path to server-side PowerShell scripts, relative to $OptPath (e.g. "DedgePshApps\AiDoc.Pwsh.Server").
    /// Joined with $env:OptPath at runtime. Absolute paths are used as-is.
    /// </summary>
    public string ServerScriptsRoot { get; set; } = "";

    /// <summary>
    /// Path to client-side PowerShell scripts, relative to $OptPath (e.g. "DedgePshApps\AiDoc.Pwsh.Client").
    /// Joined with $env:OptPath at runtime. Absolute paths are used as-is.
    /// </summary>
    public string ClientScriptsRoot { get; set; } = "";

    /// <summary>
    /// Full path to the Python executable (venv or system).
    /// Auto-resolved from PythonRoot/.venv if empty.
    /// </summary>
    public string PythonExe { get; set; } = "";

    /// <summary>
    /// Hostname where RAG HTTP servers are running (for proxying queries).
    /// </summary>
    public string RagHost { get; set; } = "localhost";

    /// <summary>
    /// UNC share root for the library, e.g. \\server\opt\data\AiDoc.Library.
    /// Auto-computed from registry host if empty.
    /// </summary>
    public string UncShareRoot { get; set; } = "";

    /// <summary>
    /// Ollama API host (e.g. "localhost:11434").
    /// </summary>
    public string OllamaHost { get; set; } = "localhost:11434";

    /// <summary>
    /// Default Ollama model for RAG queries.
    /// </summary>
    public string OllamaDefaultModel { get; set; } = "llama3.2";

    /// <summary>
    /// Path to backup directory, relative to $OptPath (e.g. "data\AiDoc.Backup").
    /// </summary>
    public string BackupDir { get; set; } = "";

    /// <summary>
    /// Backup retention in days.
    /// </summary>
    public int BackupRetainDays { get; set; } = 30;

    /// <summary>
    /// Path to dev-side PowerShell scripts, relative to $OptPath.
    /// </summary>
    public string DevScriptsRoot { get; set; } = "";
}
