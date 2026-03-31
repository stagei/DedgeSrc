namespace AutoDocNew.Models;

/// <summary>
/// C# solution parser result – all data needed to render a CSharp doc page.
/// </summary>
public class CSharpResult : DocFileResult
{
    public CSharpMetadata Metadata { get; set; } = new();
    public CSharpDiagrams Diagrams { get; set; } = new();
    public List<SqlTableRef> SqlTables { get; set; } = new();
    public List<CSharpClassDef> Classes { get; set; } = new();
    public List<CSharpProjectDef> Projects { get; set; } = new();
    public List<CSharpNamespaceDef> Namespaces { get; set; } = new();
    public List<CSharpRestEndpointDef> RestEndpoints { get; set; } = new();
    public List<CSharpPortDef> Ports { get; set; } = new();
    public List<CSharpApiCallerDef> ApiCallers { get; set; } = new();
}

public class CSharpMetadata
{
    public string SolutionName { get; set; } = "";
    public string TargetFramework { get; set; } = "";
    public int ProjectCount { get; set; }
    public int ClassCount { get; set; }
    public int InterfaceCount { get; set; }
    public int MethodCount { get; set; }
    public bool UsesSql { get; set; }
}

/// <summary>
/// Focused diagram types for a C# solution (4 diagrams, all rendered via GoJS).
/// Flow: primary execution path from entry point through services.
/// Architecture: project structure, references, and communication patterns.
/// Integration: external interactions (DB, HTTP, file I/O, process invocations, who triggers this app).
/// Rest: REST endpoint interaction diagram (which programs call this app's API).
/// </summary>
public class CSharpDiagrams
{
    public string FlowMmd { get; set; } = "";
    public string ArchitectureMmd { get; set; } = "";
    public string IntegrationMmd { get; set; } = "";
    public string RestMmd { get; set; } = "";
}

public class CSharpClassDef
{
    public string Name { get; set; } = "";
    public string FullName { get; set; } = "";
    public string Namespace { get; set; } = "";
    public string BaseClass { get; set; } = "";
    public List<string> Interfaces { get; set; } = new();
    public int MethodCount { get; set; }
    public string ProjectName { get; set; } = "";
}

public class CSharpProjectDef
{
    public string Name { get; set; } = "";
    public string TargetFramework { get; set; } = "";
    public int ClassCount { get; set; }
    public List<string> ProjectReferences { get; set; } = new();
    public List<string> PackageReferences { get; set; } = new();
}

public class CSharpNamespaceDef
{
    public string Name { get; set; } = "";
    public int ClassCount { get; set; }
    public int ControllerCount { get; set; }
    public int ServiceCount { get; set; }
}

public class CSharpRestEndpointDef
{
    public string Verb { get; set; } = "";
    public string Route { get; set; } = "";
    public string Method { get; set; } = "";
    public string Controller { get; set; } = "";
}

public class CSharpPortDef
{
    public string PortType { get; set; } = "";
    public string Value { get; set; } = "";
}

/// <summary>External program that calls a REST endpoint exposed by this C# app</summary>
public class CSharpApiCallerDef
{
    public string ProgramName { get; set; } = "";
    public string FileType { get; set; } = "";
    public string FilePath { get; set; } = "";
    public string MatchedEndpoint { get; set; } = "";
    public string HttpVerb { get; set; } = "";
}
