namespace AiDoc.WebNew.Models;

public class RagServiceInfo
{
    public string Name { get; set; } = "";
    public int Port { get; set; }
    public string Status { get; set; } = "unknown";
    public int? Pid { get; set; }
    public DateTime? StartedAt { get; set; }
    public TimeSpan? Uptime { get; set; }
    public string? HealthEndpoint { get; set; }
}

public enum ServiceAction { Start, Stop, Restart }

public class EnvironmentStatus
{
    public string? PythonVersion { get; set; }
    public string? PythonPath { get; set; }
    public bool VenvExists { get; set; }
    public bool LibraryExists { get; set; }
    public int IndexCount { get; set; }
    public int ServicesRunning { get; set; }
    public List<string> Issues { get; set; } = new();
}

public class BackupInfo
{
    public string FileName { get; set; } = "";
    public DateTime Date { get; set; }
    public long SizeBytes { get; set; }
    public int RagCount { get; set; }
    public string FilePath { get; set; } = "";
}

public class OllamaQueryRequest
{
    public string Query { get; set; } = "";
    public string Rag { get; set; } = "db2-docs";
    public string Model { get; set; } = "llama3.2";
    public int Chunks { get; set; } = 6;
}

public class OllamaQueryResult
{
    public string Answer { get; set; } = "";
    public string RagName { get; set; } = "";
    public string Model { get; set; } = "";
    public int ChunksUsed { get; set; }
    public List<string> Sources { get; set; } = new();
}

public class CursorMcpConfig
{
    public Dictionary<string, CursorMcpServerEntry> McpServers { get; set; } = new();
}

public class CursorMcpServerEntry
{
    public string Command { get; set; } = "";
    public List<string> Args { get; set; } = new();
    public string Cwd { get; set; } = "";
}

public class OllamaRagConfig
{
    public string ProfileBlock { get; set; } = "";
    public Dictionary<string, string> RagUrls { get; set; } = new();
    public string DefaultModel { get; set; } = "";
    public List<string> AvailableRags { get; set; } = new();
}

public class OllamaDb2Config
{
    public string ProfileBlock { get; set; } = "";
    public int BridgePort { get; set; }
    public string RemoteHost { get; set; } = "";
    public string Model { get; set; } = "";
}

public class ProxyScriptResponse
{
    public string Content { get; set; } = "";
    public string FileName { get; set; } = "server_mcp_proxy.py";
}
