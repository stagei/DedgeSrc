using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using SystemAnalyzer2.Batch.AutoDoc;
using SystemAnalyzer2.Core.Models.AutoDoc;

namespace SystemAnalyzer2.Batch.Parsers;

/// <summary>
/// C# Parser - complete line-by-line translation from AutoDocFunctions.psm1
/// Functions translated:
///   Initialize-CSharpParseVariables    (lines 9104-9117)
///   Get-CSharpFiles                    (lines 9119-9141)
///   Get-SolutionProjects               (lines 9143-9187)
///   Get-ProjectReferences              (lines 9189-9266)
///   Read-CSharpFile                    (lines 9268-9492)
///   Write-CSharpMmdClass               (line 9498)
///   Write-CSharpMmdFlow                (line 9504)
///   Write-CSharpMmdInteraction         (line 9511)
///   Write-CSharpMmdExecFlow            (line 9517)
///   Get-CSharpProcessInvocations       (lines 9522-9633)
///   New-CSharpProcessDiagram           (lines 9635-9715)
///   Get-CSharpApiConfiguration         (lines 9717-9833)
///   Find-ExternalApiCallers            (lines 9835-9975)
///   Get-MethodBody                     (lines 9977-10008)
///   Get-MethodControlFlow              (lines 10010-10086)
///   Get-AllProjectsInFolder            (lines 10088-10133)
///   Get-ProjectCommunication           (lines 10297-10381)
///   New-EcosystemDiagram               (lines 10383-10522)
///   New-FullEcosystemDiagram           (lines 10135-10295)
///   New-ExecutionFlowDiagram           (lines 10524-10704)
///   New-ClassDiagram                   (lines 10706-10796)
///   New-ProjectInteractionDiagram      (lines 10798-10823)
///   New-NamespaceFlowDiagram           (lines 10825-10889)
///   New-ClassListHtml                  (lines 11888-11905)
///   New-ProjectListHtml                (lines 11907-11922)
///   New-NamespaceListHtml              (lines 11924-11948)
///   Start-CSharpParse                  (lines 10894-11376)
///   Start-CSharpEcosystemParse         (lines 11378-11765)
/// </summary>
public static class CSharpParser
{
    static CSharpParser()
    {
        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
    }

    #region Data Models

    private class SolutionProject
    {
        public string Name { get; set; } = "";
        public string Path { get; set; } = "";
        public string Guid { get; set; } = "";
        public string RelativePath { get; set; } = "";
    }

    private class ProjectReferences
    {
        public List<string> ProjectRefs { get; set; } = new();
        public List<PackageRef> PackageRefs { get; set; } = new();
        public string TargetFramework { get; set; } = "";
        public string RootNamespace { get; set; } = "";
        public string AssemblyName { get; set; } = "";
        public string Description { get; set; } = "";
        public string Product { get; set; } = "";
        public string Company { get; set; } = "";
    }

    private class PackageRef
    {
        public string Name { get; set; } = "";
        public string Version { get; set; } = "";
    }

    private class CSharpFileResult
    {
        public string Namespace { get; set; } = "";
        public List<ClassInfo> Classes { get; set; } = new();
        public List<InterfaceInfo> Interfaces { get; set; } = new();
        public List<string> Usings { get; set; } = new();
    }

    private class ClassInfo
    {
        public string Name { get; set; } = "";
        public string FullName { get; set; } = "";
        public string Namespace { get; set; } = "";
        public List<string> Attributes { get; set; } = new();
        public string BaseClass { get; set; } = "";
        public List<string> Interfaces { get; set; } = new();
        public List<MethodInfo> Methods { get; set; } = new();
        public List<string> Dependencies { get; set; } = new();
        public List<RestEndpoint> RestEndpoints { get; set; } = new();
        public string ControllerRoute { get; set; } = "";
        public string ProjectName { get; set; } = "";
        public string FilePath { get; set; } = "";
    }

    private class InterfaceInfo
    {
        public string Name { get; set; } = "";
        public string FullName { get; set; } = "";
        public List<string> Extends { get; set; } = new();
        public string ProjectName { get; set; } = "";
        public string FilePath { get; set; } = "";
    }

    private class MethodInfo
    {
        public string Name { get; set; } = "";
        public string Parameters { get; set; } = "";
        public string FullSignature { get; set; } = "";
        public List<SqlStatement> SqlStatements { get; set; } = new();
    }

    private class RestEndpoint
    {
        public string HttpVerb { get; set; } = "";
        public string Route { get; set; } = "";
        public string FullRoute { get; set; } = "";
        public string MethodName { get; set; } = "";
    }

    private class SqlStatement
    {
        public string Operation { get; set; } = "";
        public List<string> Tables { get; set; } = new();
        public List<string> Fields { get; set; } = new();
    }

    private class ProcessInvocation
    {
        public string Type { get; set; } = "";
        public string Name { get; set; } = "";
        public string Details { get; set; } = "";
        public string SourceFile { get; set; } = "";
    }

    private class ApiConfiguration
    {
        public List<string> BaseUrls { get; set; } = new();
        public List<string> Ports { get; set; } = new();
    }

    private class ExternalCaller
    {
        public string FileName { get; set; } = "";
        public string FilePath { get; set; } = "";
        public string FileType { get; set; } = "";
        public string MatchedPattern { get; set; } = "";
        public List<RestEndpoint> MatchedEndpoints { get; set; } = new();
        public string HtmlLink { get; set; } = "";
    }

    private class ControlFlowNode
    {
        public string Id { get; set; } = "";
        public string Label { get; set; } = "";
        public string Type { get; set; } = "";
        public string Condition { get; set; } = "";
        public string Target { get; set; } = "";
    }

    private class ProjectInfo
    {
        public string Name { get; set; } = "";
        public string Path { get; set; } = "";
        public string TargetFramework { get; set; } = "";
        public string RootNamespace { get; set; } = "";
        public List<PackageRef> PackageReferences { get; set; } = new();
        public string AssemblyName { get; set; } = "";
        public string ParentFolder { get; set; } = "";
    }

    private class CommunicationPattern
    {
        public string FromProject { get; set; } = "";
        public string Type { get; set; } = "";
        public string Endpoint { get; set; } = "";
        public string File { get; set; } = "";
        public string ServiceName { get; set; } = "";
        public string ControllerName { get; set; } = "";
        public string HubName { get; set; } = "";
    }

    #endregion

    #region Script-Level Variables (lines 9104-9117)

    // Script-level variables equivalent to $script: variables in PowerShell
    [ThreadStatic] private static int _sequenceNumber;
    [ThreadStatic] private static List<string>? _mmdClassContent;
    [ThreadStatic] private static List<string>? _mmdFlowContent;
    [ThreadStatic] private static List<string>? _mmdInteractionContent;
    [ThreadStatic] private static List<string>? _mmdExecutionFlowContent;
    [ThreadStatic] private static string? _mmdEcosystemContent;
    [ThreadStatic] private static List<string>? _sqlTableArray;

    /// <summary>
    /// Initializes thread-safe variables for C# parsing.
    /// Converted line-by-line from Initialize-CSharpParseVariables (lines 9104-9117)
    /// </summary>
    private static void InitializeCSharpParseVariables()
    {
        _sequenceNumber = 0;
        _mmdClassContent = new List<string>();
        _mmdFlowContent = new List<string>();
        _mmdInteractionContent = new List<string>();
        _mmdExecutionFlowContent = new List<string>();
        _mmdEcosystemContent = "";
        _sqlTableArray = new List<string>();
    }

    #endregion

    #region Write-CSharpMmd* Methods (lines 9498-9520)

    /// <summary>
    /// Adds a line to the class diagram content.
    /// Converted from Write-CSharpMmdClass (line 9498)
    /// </summary>
    private static void WriteCSharpMmdClass(string mmdString)
    {
        // No duplicate check - structural elements like } appear multiple times
        _mmdClassContent?.Add(mmdString);
    }

    /// <summary>
    /// Adds a line to the namespace flow diagram content.
    /// Converted from Write-CSharpMmdFlow (line 9504)
    /// </summary>
    private static void WriteCSharpMmdFlow(string mmdString)
    {
        // No duplicate check - structural elements like end appear multiple times
        _sequenceNumber++;
        _mmdFlowContent?.Add(mmdString);
    }

    /// <summary>
    /// Adds a line to the project interaction diagram content.
    /// Converted from Write-CSharpMmdInteraction (line 9511)
    /// </summary>
    private static void WriteCSharpMmdInteraction(string mmdString)
    {
        // No duplicate check - structural elements appear multiple times
        _mmdInteractionContent?.Add(mmdString);
    }

    /// <summary>
    /// Adds a line to the execution flow diagram content.
    /// Converted from Write-CSharpMmdExecFlow (line 9517)
    /// </summary>
    private static void WriteCSharpMmdExecFlow(string mmdString)
    {
        _mmdExecutionFlowContent?.Add(mmdString);
    }

    #endregion

    #region Get-CSharpFiles (lines 9119-9141)

    /// <summary>
    /// Gets all C# files in a folder, excluding common non-source folders.
    /// Converted line-by-line from Get-CSharpFiles (lines 9119-9141)
    /// </summary>
    private static List<string> GetCSharpFiles(string folderPath)
    {
        var excludeFolders = new[] { "bin", "obj", "node_modules", ".git", ".vs", "packages", "TestResults" };

        if (!Directory.Exists(folderPath))
            return new List<string>();

        return Directory.EnumerateFiles(folderPath, "*.cs", SearchOption.AllDirectories)
            .Where(f =>
            {
                string dirLower = Path.GetDirectoryName(f)?.ToLower() ?? "";
                foreach (string folder in excludeFolders)
                {
                    // Regex: \\folder(\\|$) - Match folder name in path followed by backslash or end
                    if (Regex.IsMatch(dirLower, @"\\" + Regex.Escape(folder) + @"(\\|$)"))
                        return false;
                }
                return true;
            })
            .ToList();
    }

    #endregion

    #region Get-SolutionProjects (lines 9143-9187)

    /// <summary>
    /// Parses a .sln file to extract project information.
    /// Converted line-by-line from Get-SolutionProjects (lines 9143-9187)
    /// </summary>
    private static List<SolutionProject> GetSolutionProjects(string solutionPath)
    {
        var projects = new List<SolutionProject>();

        if (!File.Exists(solutionPath))
        {
            AutoDocLogger.LogMessage($"Solution file not found: {solutionPath}", LogLevel.WARN);
            return projects;
        }

        string content = File.ReadAllText(solutionPath);

        // Regex: Project("{GUID}") = "ProjectName", "RelativePath\Project.csproj", "{ProjectGUID}"
        // Matches Project lines in .sln files to extract project name, path, and GUID
        string projectPattern = @"Project\(""\{[A-F0-9-]+\}""\)\s*=\s*""([^""]+)"",\s*""([^""]+)"",\s*""\{([A-F0-9-]+)\}""";
        var matches = Regex.Matches(content, projectPattern, RegexOptions.IgnoreCase);

        foreach (Match match in matches)
        {
            string projectName = match.Groups[1].Value;
            string relativePath = match.Groups[2].Value;
            string projectGuid = match.Groups[3].Value;

            // Skip solution folders
            if (!Regex.IsMatch(relativePath, @"\.csproj$"))
                continue;

            string solutionDir = Path.GetDirectoryName(solutionPath) ?? "";
            string projectPath = Path.Combine(solutionDir, relativePath);

            if (File.Exists(projectPath))
            {
                projects.Add(new SolutionProject
                {
                    Name = projectName,
                    Path = projectPath,
                    Guid = projectGuid,
                    RelativePath = relativePath
                });
            }
        }

        return projects;
    }

    #endregion

    #region Get-ProjectReferences (lines 9189-9266)

    /// <summary>
    /// Parses a .csproj file to extract project references and package references.
    /// Converted line-by-line from Get-ProjectReferences (lines 9189-9266)
    /// </summary>
    private static ProjectReferences GetProjectReferences(string projectPath)
    {
        var references = new ProjectReferences();

        if (!File.Exists(projectPath))
            return references;

        try
        {
            var csproj = XDocument.Load(projectPath);

            // Get target framework
            var tfNode = csproj.Descendants("TargetFramework").FirstOrDefault();
            if (tfNode != null) references.TargetFramework = tfNode.Value;

            // Get root namespace
            var nsNode = csproj.Descendants("RootNamespace").FirstOrDefault();
            if (nsNode != null) references.RootNamespace = nsNode.Value;

            // Get assembly name
            var anNode = csproj.Descendants("AssemblyName").FirstOrDefault();
            if (anNode != null) references.AssemblyName = anNode.Value;

            // Get description
            var descNode = csproj.Descendants("Description").FirstOrDefault();
            if (descNode != null) references.Description = descNode.Value;

            // Get product name
            var prodNode = csproj.Descendants("Product").FirstOrDefault();
            if (prodNode != null) references.Product = prodNode.Value;

            // Get company name
            var compNode = csproj.Descendants("Company").FirstOrDefault();
            if (compNode != null) references.Company = compNode.Value;

            // Get project references
            foreach (var projRef in csproj.Descendants("ProjectReference"))
            {
                string? include = projRef.Attribute("Include")?.Value;
                if (!string.IsNullOrEmpty(include))
                {
                    string projName = Path.GetFileNameWithoutExtension(include);
                    references.ProjectRefs.Add(projName);
                }
            }

            // Get package references
            foreach (var pkgRef in csproj.Descendants("PackageReference"))
            {
                string? include = pkgRef.Attribute("Include")?.Value;
                string? version = pkgRef.Attribute("Version")?.Value;
                if (!string.IsNullOrEmpty(include))
                {
                    references.PackageRefs.Add(new PackageRef
                    {
                        Name = include,
                        Version = version ?? ""
                    });
                }
            }
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Error parsing project file {projectPath}: {ex.Message}", LogLevel.WARN);
        }

        return references;
    }

    #endregion

    #region Read-CSharpFile (lines 9268-9492)

    /// <summary>
    /// Parses a C# file to extract classes, interfaces, methods, and properties.
    /// Converted line-by-line from Read-CSharpFile (lines 9268-9492)
    /// </summary>
    private static CSharpFileResult ReadCSharpFile(string filePath, string projectName)
    {
        var result = new CSharpFileResult();

        if (!File.Exists(filePath))
            return result;

        try
        {
            string content = File.ReadAllText(filePath, Encoding.UTF8);

            // Extract using statements
            // Regex: ^\s*using\s+([^;]+); - Match using directives at the start of a line
            var usingMatches = Regex.Matches(content, @"^\s*using\s+([^;]+);", RegexOptions.Multiline);
            foreach (Match match in usingMatches)
            {
                result.Usings.Add(match.Groups[1].Value.Trim());
            }

            // Extract namespace (file-scoped or block-scoped)
            // Regex: (?:namespace\s+([^\s{;]+)\s*;)|(?:namespace\s+([^\s{]+)\s*\{) - Match both namespace styles
            var nsMatch = Regex.Match(content, @"(?:namespace\s+([^\s{;]+)\s*;)|(?:namespace\s+([^\s{]+)\s*\{)");
            if (nsMatch.Success)
            {
                result.Namespace = !string.IsNullOrEmpty(nsMatch.Groups[1].Value)
                    ? nsMatch.Groups[1].Value
                    : nsMatch.Groups[2].Value;
            }

            // Extract interfaces
            // Regex: (?:public|internal|private|protected)?\s*interface\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{ - Match interface declarations
            var ifaceMatches = Regex.Matches(content,
                @"(?:public|internal|private|protected)?\s*interface\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{",
                RegexOptions.Multiline);

            foreach (Match match in ifaceMatches)
            {
                var interfaceInfo = new InterfaceInfo
                {
                    Name = match.Groups[1].Value,
                    FullName = $"{result.Namespace}.{match.Groups[1].Value}",
                    ProjectName = projectName,
                    FilePath = filePath
                };

                if (match.Groups[2].Success)
                {
                    interfaceInfo.Extends = match.Groups[2].Value
                        .Split(',')
                        .Select(s => s.Trim())
                        .Where(s => s.Length > 0)
                        .ToList();
                }

                result.Interfaces.Add(interfaceInfo);
            }

            // Extract classes
            // Regex: (?:\[([^\]]+)\]\s*)*(?:public|internal|private|protected)?\s*(?:abstract|sealed|static|partial)?\s*class\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{
            // Matches class declarations with optional attributes, modifiers, generics, and base types
            var classMatches = Regex.Matches(content,
                @"(?:\[([^\]]+)\]\s*)*(?:public|internal|private|protected)?\s*(?:abstract|sealed|static|partial)?\s*class\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{",
                RegexOptions.Multiline);

            foreach (Match match in classMatches)
            {
                string className = match.Groups[2].Value;
                string fullName = !string.IsNullOrEmpty(result.Namespace)
                    ? $"{result.Namespace}.{className}"
                    : className;

                var classInfo = new ClassInfo
                {
                    Name = className,
                    FullName = fullName,
                    Namespace = result.Namespace,
                    ProjectName = projectName,
                    FilePath = filePath
                };

                if (match.Groups[1].Success)
                {
                    classInfo.Attributes.Add(match.Groups[1].Value);
                }

                if (match.Groups[3].Success)
                {
                    var bases = match.Groups[3].Value.Split(',').Select(b => b.Trim()).ToList();
                    foreach (string baseName in bases)
                    {
                        string cleanName = baseName.Split('<')[0].Trim();
                        // Regex: ^I[A-Z] - Check if name starts with I followed by uppercase (interface naming convention)
                        if (Regex.IsMatch(cleanName, @"^I[A-Z]"))
                        {
                            classInfo.Interfaces.Add(cleanName);
                        }
                        else if (string.IsNullOrEmpty(classInfo.BaseClass) && cleanName != "object")
                        {
                            classInfo.BaseClass = cleanName;
                        }
                    }
                }

                result.Classes.Add(classInfo);
            }

            // Extract methods
            // Regex: (?:public|protected|internal|private)\s+(?:virtual|override|abstract|static|async)?\s*(?:Task<?\w*>?|void|[\w<>,\s\[\]]+)\s+(\w+)\s*\(([^)]*)\)
            // Matches method declarations with access modifiers, return types, method name and parameters
            var methodMatches = Regex.Matches(content,
                @"(?:public|protected|internal|private)\s+(?:virtual|override|abstract|static|async)?\s*(?:Task<?\w*>?|void|[\w<>,\s\[\]]+)\s+(\w+)\s*\(([^)]*)\)",
                RegexOptions.Multiline);

            var methods = new List<MethodInfo>();
            foreach (Match match in methodMatches)
            {
                string methodName = match.Groups[1].Value;
                string parameters = match.Groups[2].Value.Trim();

                // Check if this is a constructor (same name as class)
                bool isConstructor = result.Classes.Any(c => c.Name == methodName);

                if (!isConstructor)
                {
                    methods.Add(new MethodInfo
                    {
                        Name = methodName,
                        Parameters = parameters,
                        FullSignature = $"{methodName}({parameters})"
                    });
                }
            }

            if (result.Classes.Count > 0)
            {
                result.Classes[result.Classes.Count - 1].Methods = methods;
            }

            // Detect REST API endpoints from controller classes
            // Regex: \[(Http(Get|Post|Put|Delete|Patch))(?:\("([^"]*)"\))?\]\s*(?:\[[^\]]+\]\s*)*(?:public|private|protected|internal)\s+(?:async\s+)?(?:Task<?\w*>?|IActionResult|ActionResult<?\w*>?|\w+)\s+(\w+)\s*\(
            // Matches HTTP verb attributes with optional route templates, followed by method signatures
            var restMatches = Regex.Matches(content,
                @"\[(Http(Get|Post|Put|Delete|Patch))(?:\(""([^""]*)""\))?\]\s*(?:\[[^\]]+\]\s*)*(?:public|private|protected|internal)\s+(?:async\s+)?(?:Task<?\w*>?|IActionResult|ActionResult<?\w*>?|\w+)\s+(\w+)\s*\(",
                RegexOptions.IgnoreCase);

            if (restMatches.Count > 0)
            {
                // Find controller route from class attribute
                // Regex: \[Route\("([^"]*)"\)\] - Match Route attribute on controller class
                var routeMatch = Regex.Match(content, @"\[Route\(""([^""]*)""\)\]");
                string baseRoute = routeMatch.Success ? routeMatch.Groups[1].Value : "";

                foreach (var classInfo in result.Classes)
                {
                    // Regex: Controller|ControllerBase - Check if class inherits from a Controller type
                    if (Regex.IsMatch(classInfo.BaseClass, @"Controller|ControllerBase") ||
                        classInfo.Attributes.Any(a => a.Contains("ApiController")))
                    {
                        classInfo.ControllerRoute = baseRoute;
                    }
                }

                foreach (Match restMatch in restMatches)
                {
                    string httpVerb = restMatch.Groups[2].Value.ToUpper();
                    string routeTemplate = restMatch.Groups[3].Success ? restMatch.Groups[3].Value : "";
                    string methodName = restMatch.Groups[4].Value;

                    foreach (var classInfo in result.Classes)
                    {
                        if (Regex.IsMatch(classInfo.BaseClass, @"Controller|ControllerBase") ||
                            classInfo.Attributes.Any(a => a.Contains("ApiController")))
                        {
                            string fullRoute;
                            if (!string.IsNullOrEmpty(classInfo.ControllerRoute) && !string.IsNullOrEmpty(routeTemplate))
                                fullRoute = $"{classInfo.ControllerRoute}/{routeTemplate}";
                            else if (!string.IsNullOrEmpty(classInfo.ControllerRoute))
                                fullRoute = classInfo.ControllerRoute;
                            else
                                fullRoute = routeTemplate;

                            classInfo.RestEndpoints.Add(new RestEndpoint
                            {
                                HttpVerb = httpVerb,
                                Route = routeTemplate,
                                FullRoute = fullRoute,
                                MethodName = methodName
                            });
                            break;
                        }
                    }
                }
            }

            // Extract constructor dependencies
            // Regex: public\s+(\w+)\s*\(([^)]+)\) - Match constructor declarations with parameters
            var ctorMatches = Regex.Matches(content, @"public\s+(\w+)\s*\(([^)]+)\)", RegexOptions.Multiline);
            foreach (Match match in ctorMatches)
            {
                string ctorName = match.Groups[1].Value;
                string parms = match.Groups[2].Value;

                foreach (var classInfo in result.Classes)
                {
                    if (classInfo.Name == ctorName)
                    {
                        var paramList = parms.Split(',');
                        foreach (string param in paramList)
                        {
                            string trimmedParam = param.Trim();
                            // Regex: ^([\w<>]+)\s+\w+$ - Match "TypeName paramName" pattern
                            var paramMatch = Regex.Match(trimmedParam, @"^([\w<>]+)\s+\w+$");
                            if (paramMatch.Success)
                            {
                                string typeName = paramMatch.Groups[1].Value;
                                // Regex: ^(string|int|bool|double|float|decimal|long|short|byte|char|object|CancellationToken)$
                                // Skip primitive and common types for dependency tracking
                                if (!Regex.IsMatch(typeName, @"^(string|int|bool|double|float|decimal|long|short|byte|char|object|CancellationToken)$"))
                                {
                                    classInfo.Dependencies.Add(typeName);
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Error parsing C# file {filePath}: {ex.Message}", LogLevel.WARN);
        }

        return result;
    }

    #endregion

    #region Get-CSharpProcessInvocations (lines 9522-9633)

    /// <summary>
    /// Detects external process invocations in C# source code.
    /// Converted line-by-line from Get-CSharpProcessInvocations (lines 9522-9633)
    /// </summary>
    private static List<ProcessInvocation> GetCSharpProcessInvocations(List<string> csFiles)
    {
        var invocations = new List<ProcessInvocation>();

        foreach (string filePath in csFiles)
        {
            if (!File.Exists(filePath)) continue;

            try
            {
                string content = File.ReadAllText(filePath, Encoding.UTF8);
                if (string.IsNullOrEmpty(content)) continue;

                string fileName = Path.GetFileName(filePath);

                // Detect Process.Start() calls
                // Regex: Process\.Start\s*\(\s*(?:"([^"]+)"|([^,\)]+)) - Match Process.Start with argument
                var processStartMatches = Regex.Matches(content, @"Process\.Start\s*\(\s*(?:""([^""]+)""|([^,\)]+))");
                foreach (Match match in processStartMatches)
                {
                    string processName = match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value.Trim();
                    invocations.Add(new ProcessInvocation { Type = "Process", Name = processName, Details = "Process.Start", SourceFile = fileName });
                }

                // Detect ProcessStartInfo with FileName
                // Regex: ProcessStartInfo[^{]*\{[^}]*FileName\s*=\s*"([^"]+)" - Match PSI with FileName property
                var psiMatches = Regex.Matches(content, @"ProcessStartInfo[^{]*\{[^}]*FileName\s*=\s*""([^""]+)""");
                foreach (Match match in psiMatches)
                {
                    invocations.Add(new ProcessInvocation { Type = "Process", Name = match.Groups[1].Value, Details = "ProcessStartInfo", SourceFile = fileName });
                }

                // Detect SqlConnection usage
                // Regex: new\s+SqlConnection\s*\( - Match SqlConnection instantiation
                var sqlConnMatches = Regex.Matches(content, @"new\s+SqlConnection\s*\(");
                foreach (Match _ in sqlConnMatches)
                {
                    invocations.Add(new ProcessInvocation { Type = "Database", Name = "SQL Server", Details = "SqlConnection", SourceFile = fileName });
                }

                // Detect DB2 connections
                // Regex: (DB2Connection|OdbcConnection|Db2Command) - Match DB2/ODBC connection types
                var db2Matches = Regex.Matches(content, @"(DB2Connection|OdbcConnection|Db2Command)", RegexOptions.IgnoreCase);
                foreach (Match match in db2Matches)
                {
                    invocations.Add(new ProcessInvocation { Type = "Database", Name = "DB2/ODBC", Details = match.Value, SourceFile = fileName });
                }

                // Detect PowerShell invocations
                // Regex: ("powershell\.exe"|"pwsh\.exe"|PowerShell\.Create|Runspace) - Match PS invocation patterns
                var psMatches = Regex.Matches(content, @"(""powershell\.exe""|""pwsh\.exe""|PowerShell\.Create|Runspace)", RegexOptions.IgnoreCase);
                foreach (Match match in psMatches)
                {
                    invocations.Add(new ProcessInvocation { Type = "PowerShell", Name = "PowerShell", Details = match.Value.Replace("\"", ""), SourceFile = fileName });
                }

                // Detect CMD/batch script invocations
                // Regex: ("cmd\.exe"|"\.bat"|"\.cmd") - Match CMD/batch invocations
                var cmdMatches = Regex.Matches(content, @"(""cmd\.exe""|""\.bat""|""\.cmd"")", RegexOptions.IgnoreCase);
                foreach (Match match in cmdMatches)
                {
                    invocations.Add(new ProcessInvocation { Type = "Script", Name = "CMD/Batch", Details = match.Value.Replace("\"", ""), SourceFile = fileName });
                }

                // Detect HTTP client usage (external API calls)
                // Regex: (HttpClient|WebClient|WebRequest|RestClient) - Match HTTP client types
                var httpMatches = Regex.Matches(content, @"(HttpClient|WebClient|WebRequest|RestClient)");
                foreach (Match match in httpMatches)
                {
                    invocations.Add(new ProcessInvocation { Type = "HTTP", Name = "External API", Details = match.Value, SourceFile = fileName });
                }
            }
            catch (Exception ex)
            {
                AutoDocLogger.LogMessage($"Error scanning file for process invocations: {filePath} - {ex.Message}", LogLevel.WARN);
            }
        }

        return invocations;
    }

    #endregion

    #region New-CSharpProcessDiagram (lines 9635-9715)

    /// <summary>
    /// Merges two diagram contents into a single diagram. Picks the first non-empty one,
    /// or combines them if both are present by appending the second as a comment-separated section.
    /// </summary>
    private static string MergeDiagrams(string label, string primary, string secondary)
    {
        bool hasPrimary = !string.IsNullOrWhiteSpace(primary) && !primary.Contains("No ") && !primary.Contains("not detected");
        bool hasSecondary = !string.IsNullOrWhiteSpace(secondary) && !secondary.Contains("No ") && !secondary.Contains("not detected");

        if (hasPrimary && hasSecondary)
            return primary + $"\n\n    %% --- {label}: additional context ---\n" + StripFlowchartDirective(secondary);
        if (hasPrimary) return primary;
        if (hasSecondary) return secondary;
        return $"flowchart LR\n    empty[\"No {label.ToLower()} information available\"]";
    }

    /// <summary>Removes duplicate flowchart directive from a diagram fragment for merging.</summary>
    private static string StripFlowchartDirective(string mmd)
    {
        if (string.IsNullOrWhiteSpace(mmd)) return mmd;
        var lines = mmd.Split('\n').ToList();
        if (lines.Count > 0 && Regex.IsMatch(lines[0].Trim(), @"^(flowchart|graph)\s+(TD|TB|LR|RL|BT)"))
            lines.RemoveAt(0);
        return string.Join("\n", lines);
    }

    /// <summary>
    /// Generates a Mermaid diagram showing external process invocations.
    /// Converted line-by-line from New-CSharpProcessDiagram (lines 9635-9715)
    /// </summary>
    private static string NewCSharpProcessDiagram(string solutionName, List<ProcessInvocation> processInvocations)
    {
        if (processInvocations == null || processInvocations.Count == 0)
            return "flowchart LR\n    noprocess[No external process invocations detected]";

        var mmdContent = new List<string>();
        mmdContent.Add("flowchart LR");

        // Regex: [^a-zA-Z0-9] - Replace non-alphanumeric for safe Mermaid node ID
        string solutionNode = Regex.Replace(solutionName, @"[^a-zA-Z0-9]", "_");
        mmdContent.Add($"    {solutionNode}[[\"{solutionName}\"]]");
        mmdContent.Add($"    style {solutionNode} stroke:#10b981,stroke-width:3px");

        var groupedProcesses = processInvocations.GroupBy(p => p.Type);

        int nodeCounter = 0;
        foreach (var group in groupedProcesses)
        {
            string typeShape = group.Key switch
            {
                "Process" => "{{",
                "Database" => "[(",
                "PowerShell" => "([",
                "Script" => "(",
                "HTTP" => "((",
                _ => "("
            };

            string typeShapeEnd = group.Key switch
            {
                "Process" => "}}",
                "Database" => ")]",
                "PowerShell" => "])",
                "Script" => ")",
                "HTTP" => "))",
                _ => ")"
            };

            string typeColor = group.Key switch
            {
                "Process" => "#f59e0b",
                "Database" => "#10b981",
                "PowerShell" => "#3b82f6",
                "Script" => "#8b5cf6",
                "HTTP" => "#ef4444",
                _ => "#6b7280"
            };

            var uniqueProcesses = group.Select(p => new { p.Name, p.Details, p.SourceFile }).Distinct();

            foreach (var proc in uniqueProcesses)
            {
                nodeCounter++;
                string nodeId = $"proc{nodeCounter}";
                // Regex: ["\n\r] - Remove quotes and newlines from display name
                string safeName = Regex.Replace(proc.Name, @"[""\n\r]", "");
                // Regex: \s+ - Collapse whitespace
                safeName = Regex.Replace(safeName, @"\s+", " ");
                if (safeName.Length > 40)
                    safeName = safeName.Substring(0, 37) + "...";

                mmdContent.Add($"    {solutionNode} --\"{group.Key}\"--> {nodeId}{typeShape}\"{safeName}\"{typeShapeEnd}");
                mmdContent.Add($"    style {nodeId} stroke:{typeColor},stroke-width:2px");
            }
        }

        return string.Join("\n", mmdContent);
    }

    #endregion

    #region Get-CSharpApiConfiguration (lines 9717-9833)

    /// <summary>
    /// Extracts REST API configuration (URLs, ports) from C# project config files.
    /// Converted line-by-line from Get-CSharpApiConfiguration (lines 9717-9833)
    /// </summary>
    private static ApiConfiguration GetCSharpApiConfiguration(string projectFolder)
    {
        var apiConfig = new ApiConfiguration();

        if (!Directory.Exists(projectFolder))
            return apiConfig;

        // Find and parse appsettings.json files
        var appsettingsFiles = Directory.EnumerateFiles(projectFolder, "appsettings*.json", SearchOption.AllDirectories)
            .Where(f => !Regex.IsMatch(Path.GetDirectoryName(f) ?? "", @"\\(bin|obj|node_modules)\\"));

        foreach (string file in appsettingsFiles)
        {
            try
            {
                string content = File.ReadAllText(file, Encoding.UTF8);
                if (string.IsNullOrEmpty(content)) continue;

                using var jsonDoc = JsonDocument.Parse(content);
                var root = jsonDoc.RootElement;

                // Extract Kestrel endpoints
                if (root.TryGetProperty("Kestrel", out var kestrel) &&
                    kestrel.TryGetProperty("Endpoints", out var endpoints))
                {
                    foreach (var endpoint in endpoints.EnumerateObject())
                    {
                        if (endpoint.Value.TryGetProperty("Url", out var urlProp))
                        {
                            string url = urlProp.GetString() ?? "";
                            apiConfig.BaseUrls.Add(url);

                            // Regex: :(\d+) - Extract port number from URL
                            var portMatch = Regex.Match(url, @":(\d+)");
                            if (portMatch.Success)
                            {
                                string port = portMatch.Groups[1].Value;
                                if (!apiConfig.Ports.Contains(port))
                                    apiConfig.Ports.Add(port);
                            }
                        }
                    }
                }

                // Extract RestApi.Port configuration
                if (root.TryGetProperty("RestApi", out var restApi) &&
                    restApi.TryGetProperty("Port", out var restPort))
                {
                    string port = restPort.ToString();
                    if (!apiConfig.Ports.Contains(port))
                        apiConfig.Ports.Add(port);
                }

                // Extract Dashboard.ServerMonitorPort
                if (root.TryGetProperty("Dashboard", out var dashboard) &&
                    dashboard.TryGetProperty("ServerMonitorPort", out var smPort))
                {
                    string port = smPort.ToString();
                    if (!apiConfig.Ports.Contains(port))
                        apiConfig.Ports.Add(port);
                }
            }
            catch (Exception ex)
            {
                AutoDocLogger.LogMessage($"Error parsing appsettings file: {file} - {ex.Message}", LogLevel.WARN);
            }
        }

        // Find and parse launchSettings.json files
        var launchSettingsFiles = Directory.EnumerateFiles(projectFolder, "launchSettings.json", SearchOption.AllDirectories)
            .Where(f => !Regex.IsMatch(Path.GetDirectoryName(f) ?? "", @"\\(bin|obj|node_modules)\\"));

        foreach (string file in launchSettingsFiles)
        {
            try
            {
                string content = File.ReadAllText(file, Encoding.UTF8);
                if (string.IsNullOrEmpty(content)) continue;

                using var jsonDoc = JsonDocument.Parse(content);
                var root = jsonDoc.RootElement;

                if (root.TryGetProperty("profiles", out var profiles))
                {
                    foreach (var profile in profiles.EnumerateObject())
                    {
                        if (profile.Value.TryGetProperty("applicationUrl", out var appUrl))
                        {
                            string[] urls = (appUrl.GetString() ?? "").Split(';');
                            foreach (string url in urls)
                            {
                                string trimmedUrl = url.Trim();
                                if (!string.IsNullOrEmpty(trimmedUrl) && !apiConfig.BaseUrls.Contains(trimmedUrl))
                                    apiConfig.BaseUrls.Add(trimmedUrl);

                                var portMatch = Regex.Match(trimmedUrl, @":(\d+)");
                                if (portMatch.Success)
                                {
                                    string port = portMatch.Groups[1].Value;
                                    if (!apiConfig.Ports.Contains(port))
                                        apiConfig.Ports.Add(port);
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                AutoDocLogger.LogMessage($"Error parsing launchSettings file: {file} - {ex.Message}", LogLevel.WARN);
            }
        }

        return apiConfig;
    }

    #endregion

    #region Find-ExternalApiCallers (lines 9835-9975)

    /// <summary>
    /// Finds external callers (PS1, BAT, CBL) that reference C# REST API endpoints.
    /// Converted line-by-line from Find-ExternalApiCallers (lines 9835-9975)
    /// </summary>
    private static List<ExternalCaller> FindExternalApiCallers(
        string srcRootFolder, List<string> apiPorts, List<RestEndpoint> restEndpoints, string outputFolder)
    {
        var callers = new List<ExternalCaller>();

        if (!Directory.Exists(srcRootFolder))
            return callers;

        string[] fileTypes = { "*.ps1", "*.bat", "*.cmd", "*.rex", "*.cbl" };

        // Build search patterns from ports
        var portPatterns = new List<string>();
        foreach (string port in apiPorts)
        {
            portPatterns.Add($":{port}");
            portPatterns.Add($"localhost:{port}");
            portPatterns.Add($"127.0.0.1:{port}");
        }

        // Build search patterns from REST endpoints
        var endpointPatterns = new List<string>();
        foreach (var endpoint in restEndpoints)
        {
            if (!string.IsNullOrEmpty(endpoint.Route))
            {
                // Regex: \{[^}]+\} - Remove route placeholders like {id}
                string routeParts = Regex.Replace(endpoint.Route, @"\{[^}]+\}", "");
                routeParts = routeParts.Trim('/');
                if (!string.IsNullOrEmpty(routeParts))
                {
                    endpointPatterns.Add($"api/{routeParts}");
                    endpointPatterns.Add($"/api/{routeParts}");
                }
            }
        }

        foreach (string fileType in fileTypes)
        {
            IEnumerable<string> files;
            try
            {
                files = Directory.EnumerateFiles(srcRootFolder, fileType, SearchOption.AllDirectories)
                    .Where(f => !Regex.IsMatch(Path.GetDirectoryName(f) ?? "", @"\\(bin|obj|node_modules|\.git|_old)\\"));
            }
            catch { continue; }

            foreach (string file in files)
            {
                try
                {
                    string content = File.ReadAllText(file, Encoding.UTF8);
                    if (string.IsNullOrEmpty(content)) continue;

                    string contentLower = content.ToLower();
                    bool isApiCaller = false;
                    string matchedPattern = "";
                    var matchedEndpoints = new List<RestEndpoint>();

                    // Check for port patterns
                    foreach (string pattern in portPatterns)
                    {
                        if (content.Contains(pattern))
                        {
                            isApiCaller = true;
                            matchedPattern = pattern;

                            foreach (var endpoint in restEndpoints)
                            {
                                string routeLower = endpoint.Route.ToLower();
                                if (contentLower.Contains(routeLower) ||
                                    contentLower.Contains($"api/{endpoint.MethodName.ToLower()}"))
                                {
                                    matchedEndpoints.Add(endpoint);
                                }
                            }
                            break;
                        }
                    }

                    // Check for endpoint patterns
                    if (!isApiCaller)
                    {
                        foreach (string pattern in endpointPatterns)
                        {
                            if (contentLower.Contains(pattern.ToLower()))
                            {
                                isApiCaller = true;
                                matchedPattern = pattern;

                                foreach (var endpoint in restEndpoints)
                                {
                                    string routeLower = endpoint.Route.ToLower();
                                    if (pattern.ToLower().Contains(routeLower))
                                    {
                                        matchedEndpoints.Add(endpoint);
                                    }
                                }
                                break;
                            }
                        }
                    }

                    if (isApiCaller)
                    {
                        string fileExt = Path.GetExtension(file).ToLower();
                        string callerType = fileExt switch
                        {
                            ".ps1" => "PowerShell",
                            ".bat" => "Batch",
                            ".cmd" => "Batch",
                            ".cbl" => "COBOL",
                            _ => "Script"
                        };

                        string htmlFileName = Path.GetFileName(file) + ".html";

                        callers.Add(new ExternalCaller
                        {
                            FileName = Path.GetFileName(file),
                            FilePath = file,
                            FileType = callerType,
                            MatchedPattern = matchedPattern,
                            MatchedEndpoints = matchedEndpoints,
                            HtmlLink = htmlFileName
                        });
                    }
                }
                catch
                {
                    // Silently skip files that can't be read
                }
            }
        }

        return callers;
    }

    #endregion

    #region Get-MethodBody (lines 9977-10008)

    /// <summary>
    /// Extracts the body of a method from C# source code using brace counting.
    /// Converted line-by-line from Get-MethodBody (lines 9977-10008)
    /// </summary>
    private static string GetMethodBody(string content, string methodName)
    {
        // Regex: (?:public|protected|private|internal)\s+(?:static\s+)?(?:async\s+)?(?:virtual\s+)?(?:override\s+)?[\w<>\[\],\s]+\s+{methodName}\s*\([^)]*\)\s*\{
        // Match method signature with access modifier, optional keywords, return type, and opening brace
        string pattern = $@"(?:public|protected|private|internal)\s+(?:static\s+)?(?:async\s+)?(?:virtual\s+)?(?:override\s+)?[\w<>\[\],\s]+\s+{Regex.Escape(methodName)}\s*\([^)]*\)\s*\{{";
        var match = Regex.Match(content, pattern, RegexOptions.Singleline);

        if (!match.Success) return "";

        int startIndex = match.Index + match.Length - 1;
        int braceCount = 1;
        int endIndex = startIndex + 1;

        while (braceCount > 0 && endIndex < content.Length)
        {
            char c = content[endIndex];
            if (c == '{') braceCount++;
            else if (c == '}') braceCount--;
            endIndex++;
        }

        if (braceCount == 0)
        {
            return content.Substring(startIndex + 1, endIndex - startIndex - 2);
        }
        return "";
    }

    #endregion

    #region Get-MethodControlFlow (lines 10010-10086)

    /// <summary>
    /// Parses method body for control flow statements.
    /// Converted line-by-line from Get-MethodControlFlow (lines 10010-10086)
    /// </summary>
    private static List<ControlFlowNode> GetMethodControlFlow(string methodBody, string methodName, string className)
    {
        var flowNodes = new List<ControlFlowNode>();
        int nodeId = 0;
        // Regex: [^a-zA-Z0-9] - Remove non-alphanumeric for safe identifiers
        string safeMethod = Regex.Replace(methodName, @"[^a-zA-Z0-9]", "_");
        string safeClass = Regex.Replace(className, @"[^a-zA-Z0-9]", "_");
        string prefix = $"{safeClass}_{safeMethod}";

        // Start node
        flowNodes.Add(new ControlFlowNode { Id = $"{prefix}_start", Label = $"Start: {methodName}", Type = "start" });

        // Control flow patterns
        var patterns = new Dictionary<string, string>
        {
            ["if"] = @"if\s*\(([^)]+)\)",
            ["else"] = @"else\s*\{",
            ["for"] = @"for\s*\(([^)]+)\)",
            ["foreach"] = @"foreach\s*\(([^)]+)\)",
            ["while"] = @"while\s*\(([^)]+)\)",
            ["switch"] = @"switch\s*\(([^)]+)\)",
            ["try"] = @"try\s*\{",
            ["catch"] = @"catch\s*(?:\([^)]*\))?\s*\{",
            ["return"] = @"return\s+([^;]+);",
            ["await"] = @"await\s+([^;]+);",
            ["throw"] = @"throw\s+([^;]+);"
        };

        // Extract method calls
        // Regex: (?:await\s+)?(\w+)\s*\.\s*(\w+)\s*\( - Match object.method() call patterns
        var callMatches = Regex.Matches(methodBody, @"(?:await\s+)?(\w+)\s*\.\s*(\w+)\s*\(");
        foreach (Match call in callMatches)
        {
            string obj = call.Groups[1].Value;
            string method = call.Groups[2].Value;

            // Skip common non-interesting calls
            if (new[] { "Console", "Debug", "Trace", "string", "int", "Math", "Convert" }.Contains(obj))
                continue;

            nodeId++;
            flowNodes.Add(new ControlFlowNode
            {
                Id = $"{prefix}_call_{nodeId}",
                Label = $"{obj}.{method}()",
                Type = "call",
                Target = method
            });
        }

        // Find control structures
        foreach (var kvp in patterns)
        {
            var matches = Regex.Matches(methodBody, kvp.Value);
            foreach (Match m in matches)
            {
                nodeId++;
                string condition = m.Groups.Count > 1 ? m.Groups[1].Value : "";
                string shortCondition = condition.Length > 30 ? condition.Substring(0, 30) + "..." : condition;

                flowNodes.Add(new ControlFlowNode
                {
                    Id = $"{prefix}_{kvp.Key}_{nodeId}",
                    Label = $"{kvp.Key} {shortCondition}",
                    Type = kvp.Key,
                    Condition = condition
                });
            }
        }

        // End node
        flowNodes.Add(new ControlFlowNode { Id = $"{prefix}_end", Label = "End", Type = "end" });

        return flowNodes;
    }

    #endregion

    #region Get-AllProjectsInFolder (lines 10088-10133)

    /// <summary>
    /// Discovers all .csproj files in a folder tree.
    /// Converted line-by-line from Get-AllProjectsInFolder (lines 10088-10133)
    /// </summary>
    private static (Dictionary<string, ProjectInfo> Projects, Dictionary<string, List<string>> ProjectReferences)
        GetAllProjectsInFolder(string rootFolder)
    {
        var projects = new Dictionary<string, ProjectInfo>(StringComparer.OrdinalIgnoreCase);
        var projectRefs = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

        if (!Directory.Exists(rootFolder))
            return (projects, projectRefs);

        // Find all .csproj files (excluding bin/obj/packages)
        var csprojFiles = Directory.EnumerateFiles(rootFolder, "*.csproj", SearchOption.AllDirectories)
            // Regex: \\(bin|obj|packages|node_modules|\.git)[\\/]? - Skip build output and dependency folders
            .Where(f => !Regex.IsMatch(Path.GetDirectoryName(f) ?? "", @"\\(bin|obj|packages|node_modules|\.git)[\\\/]?"))
            .ToList();

        AutoDocLogger.LogMessage($"Found {csprojFiles.Count} .csproj files in ecosystem", LogLevel.INFO);

        foreach (string csproj in csprojFiles)
        {
            string projName = Path.GetFileNameWithoutExtension(csproj);

            // Skip test projects
            // Regex: \.Tests$|\.Test$|Tests$ - Skip test project naming patterns
            if (Regex.IsMatch(projName, @"\.Tests$|\.Test$|Tests$"))
                continue;

            var refs = GetProjectReferences(csproj);

            projects[projName] = new ProjectInfo
            {
                Name = projName,
                Path = csproj,
                TargetFramework = refs.TargetFramework,
                RootNamespace = refs.RootNamespace,
                AssemblyName = refs.AssemblyName,
                PackageReferences = refs.PackageRefs,
                ParentFolder = Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(csproj)) ?? "")
            };

            projectRefs[projName] = refs.ProjectRefs;
        }

        return (projects, projectRefs);
    }

    #endregion

    #region Get-ProjectCommunication (lines 10297-10381)

    /// <summary>
    /// Analyzes C# source files for inter-project communication patterns.
    /// Converted line-by-line from Get-ProjectCommunication (lines 10297-10381)
    /// </summary>
    private static List<CommunicationPattern> GetProjectCommunication(
        Dictionary<string, ProjectInfo> projects, string sourceFolder)
    {
        var communications = new List<CommunicationPattern>();

        foreach (var kvp in projects)
        {
            string projName = kvp.Key;
            string projDir = Path.GetDirectoryName(kvp.Value.Path) ?? "";

            var csFiles = GetCSharpFiles(projDir);

            foreach (string csFile in csFiles)
            {
                string content;
                try { content = File.ReadAllText(csFile, Encoding.UTF8); }
                catch { continue; }
                if (string.IsNullOrEmpty(content)) continue;

                // Detect HTTP client usage with base URLs
                string[] httpPatterns =
                {
                    @"(?:BaseAddress|_baseUrl|baseUrl)\s*=\s*[""`]([^""`]+)[""`]",
                    @"new\s+HttpClient[^}]+BaseAddress\s*=\s*new\s+Uri\([""`]([^""`]+)[""`]\)",
                    @"GetAsync\([""`\$]([^""`]+)[""`]?\)",
                    @"PostAsync\([""`\$]([^""`]+)[""`]?",
                    @"/api/(\w+)(?:/\w+)*"
                };

                foreach (string pattern in httpPatterns)
                {
                    var matches = Regex.Matches(content, pattern, RegexOptions.IgnoreCase);
                    foreach (Match m in matches)
                    {
                        string endpoint = m.Groups[1].Value;
                        if (!string.IsNullOrEmpty(endpoint) && endpoint.Length > 2)
                        {
                            communications.Add(new CommunicationPattern
                            {
                                FromProject = projName,
                                Type = "HTTP",
                                Endpoint = endpoint,
                                File = Path.GetFileName(csFile)
                            });
                        }
                    }
                }

                // Detect service/interface dependencies
                // Regex: class\s+(\w+Service)\s*: - Match service class declarations
                var serviceMatch = Regex.Match(content, @"class\s+(\w+Service)\s*:");
                if (serviceMatch.Success)
                {
                    communications.Add(new CommunicationPattern
                    {
                        FromProject = projName,
                        Type = "Service",
                        ServiceName = serviceMatch.Groups[1].Value,
                        File = Path.GetFileName(csFile)
                    });
                }

                // Detect API controllers
                // Regex: \[ApiController\]|\[Route\([""]api/ - Match API controller attributes
                if (Regex.IsMatch(content, @"\[ApiController\]|\[Route\([""']api/"))
                {
                    var controllerMatch = Regex.Match(content, @"class\s+(\w+Controller)");
                    if (controllerMatch.Success)
                    {
                        communications.Add(new CommunicationPattern
                        {
                            FromProject = projName,
                            Type = "ApiController",
                            ControllerName = controllerMatch.Groups[1].Value,
                            File = Path.GetFileName(csFile)
                        });
                    }
                }

                // Detect SignalR hubs
                // Regex: class\s+(\w+)\s*:\s*Hub - Match SignalR hub class
                var hubMatch = Regex.Match(content, @"class\s+(\w+)\s*:\s*Hub");
                if (hubMatch.Success)
                {
                    communications.Add(new CommunicationPattern
                    {
                        FromProject = projName,
                        Type = "SignalRHub",
                        HubName = hubMatch.Groups[1].Value,
                        File = Path.GetFileName(csFile)
                    });
                }
            }
        }

        return communications;
    }

    #endregion

    #region Diagram Generation Functions

    /// <summary>
    /// Generates a classDiagram Mermaid with classes, methods, interfaces, inheritance.
    /// Converted line-by-line from New-ClassDiagram (lines 10706-10796)
    /// </summary>
    private static void NewClassDiagram(
        Dictionary<string, ClassInfo> classes, Dictionary<string, InterfaceInfo> interfaces,
        string projectName = "", int maxClasses = 8)
    {
        WriteCSharpMmdClass("classDiagram");

        var projectClasses = classes.Values
            .Where(c => string.IsNullOrEmpty(projectName) || c.ProjectName == projectName)
            .ToList();

        // Regex: Controller$ - Match controller class names
        var controllers = projectClasses.Where(c => Regex.IsMatch(c.Name, @"Controller$")).ToList();
        // Regex: Service$|Manager$ - Match service/manager class names (exclude controllers)
        var services = projectClasses.Where(c => Regex.IsMatch(c.Name, @"Service$|Manager$") && !Regex.IsMatch(c.Name, @"Controller$")).ToList();
        var others = projectClasses.Where(c => !Regex.IsMatch(c.Name, @"Controller$|Service$|Manager$")).ToList();

        var selectedClasses = new List<ClassInfo>();
        selectedClasses.AddRange(controllers.OrderByDescending(c => c.Methods.Count).Take(3));
        selectedClasses.AddRange(services.OrderByDescending(c => c.Methods.Count).Take(3));
        selectedClasses.AddRange(others.OrderByDescending(c => c.Methods.Count).Take(2));
        selectedClasses = selectedClasses.Take(maxClasses).ToList();

        int totalClasses = projectClasses.Count;

        // Only show interfaces that selected classes implement
        var usedInterfaces = new HashSet<string>();
        foreach (var cls in selectedClasses)
            foreach (string iface in cls.Interfaces)
                usedInterfaces.Add(iface);

        // Define interfaces
        foreach (var kvp in interfaces)
        {
            var iface = kvp.Value;
            if (!string.IsNullOrEmpty(projectName) && iface.ProjectName != projectName) continue;
            if (!usedInterfaces.Contains(iface.Name)) continue;
            string safeName = Regex.Replace(iface.Name, @"[^a-zA-Z0-9]", "_");
            WriteCSharpMmdClass($"    class {safeName}");
        }

        // Define classes with limited methods
        foreach (var cls in selectedClasses)
        {
            string safeName = Regex.Replace(cls.Name, @"[^a-zA-Z0-9]", "_");
            WriteCSharpMmdClass($"    class {safeName} {{");

            int methodCount = 0;
            int maxMethodsToShow = 5;
            foreach (var method in cls.Methods)
            {
                if (methodCount >= maxMethodsToShow)
                {
                    int remaining = cls.Methods.Count - maxMethodsToShow;
                    if (remaining > 0)
                        WriteCSharpMmdClass($"        +_more_{remaining}_methods()");
                    break;
                }
                string methodSig = method.Name.Replace("<", "").Replace(">", "");
                WriteCSharpMmdClass($"        +{methodSig}()");
                methodCount++;
            }
            WriteCSharpMmdClass("    }");
        }

        // Show inheritance and interface implementation
        foreach (var cls in selectedClasses)
        {
            string safeName = Regex.Replace(cls.Name, @"[^a-zA-Z0-9]", "_");

            if (!string.IsNullOrEmpty(cls.BaseClass) && cls.BaseClass != "object" && cls.BaseClass != "Object")
            {
                string safeBase = Regex.Replace(cls.BaseClass, @"[^a-zA-Z0-9]", "_");
                WriteCSharpMmdClass($"    {safeBase} <|-- {safeName} : extends");
            }

            foreach (string iface in cls.Interfaces)
            {
                string safeIface = Regex.Replace(iface, @"[^a-zA-Z0-9]", "_");
                WriteCSharpMmdClass($"    {safeIface} <|.. {safeName} : implements");
            }
        }

        if (totalClasses > maxClasses)
        {
            int remaining = totalClasses - selectedClasses.Count;
            WriteCSharpMmdClass($"    note \"{remaining} more classes not shown\"");
        }
    }

    /// <summary>
    /// Generates flowchart showing project references.
    /// Converted line-by-line from New-ProjectInteractionDiagram (lines 10798-10823)
    /// </summary>
    private static void NewProjectInteractionDiagram(
        Dictionary<string, ProjectInfo> projects, Dictionary<string, List<string>> projectReferences)
    {
        WriteCSharpMmdInteraction("flowchart TB");
        WriteCSharpMmdInteraction("    subgraph Solution");

        foreach (string projName in projects.Keys)
        {
            string safeName = Regex.Replace(projName, @"[^a-zA-Z0-9]", "_");
            WriteCSharpMmdInteraction($"        {safeName}[{projName}]");
        }

        WriteCSharpMmdInteraction("    end");

        foreach (var kvp in projectReferences)
        {
            string safeName = Regex.Replace(kvp.Key, @"[^a-zA-Z0-9]", "_");
            foreach (string refName in kvp.Value)
            {
                string safeRef = Regex.Replace(refName, @"[^a-zA-Z0-9]", "_");
                WriteCSharpMmdInteraction($"    {safeName} --> {safeRef}");
            }
        }
    }

    /// <summary>
    /// Groups classes by namespace into subgraphs.
    /// Converted line-by-line from New-NamespaceFlowDiagram (lines 10825-10889)
    /// </summary>
    private static void NewNamespaceFlowDiagram(Dictionary<string, ClassInfo> classes, string projectName = "")
    {
        WriteCSharpMmdFlow("flowchart TB");

        var namespaces = new Dictionary<string, (List<ClassInfo> Classes, int Controllers, int Services, int Other)>();

        foreach (var kvp in classes)
        {
            var cls = kvp.Value;
            if (!string.IsNullOrEmpty(projectName) && cls.ProjectName != projectName) continue;

            string ns = !string.IsNullOrEmpty(cls.Namespace) ? cls.Namespace : "(global)";

            if (!namespaces.ContainsKey(ns))
                namespaces[ns] = (new List<ClassInfo>(), 0, 0, 0);

            var entry = namespaces[ns];
            entry.Classes.Add(cls);

            if (Regex.IsMatch(cls.Name, @"Controller$"))
                entry.Controllers++;
            else if (Regex.IsMatch(cls.Name, @"Service$|Manager$"))
                entry.Services++;
            else
                entry.Other++;

            namespaces[ns] = entry;
        }

        var sortedNamespaces = namespaces.Keys
            .OrderByDescending(k => namespaces[k].Classes.Count)
            .Take(8)
            .ToList();

        foreach (string ns in sortedNamespaces)
        {
            string safeNs = Regex.Replace(ns, @"[^a-zA-Z0-9]", "_");
            var nsData = namespaces[ns];

            var details = new List<string>();
            if (nsData.Controllers > 0) details.Add($"{nsData.Controllers} Controllers");
            if (nsData.Services > 0) details.Add($"{nsData.Services} Services");
            if (nsData.Other > 0) details.Add($"{nsData.Other} Other");
            string detailStr = string.Join(", ", details);

            WriteCSharpMmdFlow($"    {safeNs}[\"📦 {ns}<br/>{detailStr}\"]");
        }

        if (namespaces.Count > 8)
        {
            int remaining = namespaces.Count - 8;
            WriteCSharpMmdFlow($"    more[\"... and {remaining} more namespaces\"]");
        }
    }

    /// <summary>
    /// Generates an application flow diagram showing the primary executable path.
    /// Detects app type (Web API, Console, Worker, Class Library) and renders
    /// an appropriate top-down flow: entry → configuration → middleware/pipeline →
    /// controllers/handlers → services → data access / external calls.
    /// For class libraries, shows the public API surface consumed by other projects.
    /// </summary>
    private static void NewExecutionFlowDiagram(
        Dictionary<string, ClassInfo> classes, Dictionary<string, string> methodBodies, int maxMethods = 20)
    {
        var sb = new List<string>();

        // Classify classes into layers
        var controllers = new List<ClassInfo>();
        var services = new List<ClassInfo>();
        var repositories = new List<ClassInfo>();
        var middlewareClasses = new List<ClassInfo>();
        var entryClasses = new List<ClassInfo>();
        var workerClasses = new List<ClassInfo>();
        var otherClasses = new List<ClassInfo>();

        foreach (var cls in classes.Values)
        {
            string name = cls.Name;
            string baseClass = cls.BaseClass ?? "";
            var attrs = cls.Attributes ?? new List<string>();
            var ifaces = cls.Interfaces ?? new List<string>();

            if (Regex.IsMatch(baseClass, @"Controller|ControllerBase") || attrs.Any(a => a.Contains("ApiController")))
                controllers.Add(cls);
            else if (Regex.IsMatch(name, @"^Program$|^Startup$") || cls.Methods.Any(m => m.Name is "Main" or "ConfigureServices" or "Configure"))
                entryClasses.Add(cls);
            else if (Regex.IsMatch(baseClass, @"BackgroundService|IHostedService") || ifaces.Any(i => i.Contains("IHostedService")))
                workerClasses.Add(cls);
            else if (name.EndsWith("Middleware") || ifaces.Any(i => i.Contains("IMiddleware")))
                middlewareClasses.Add(cls);
            else if (Regex.IsMatch(name, @"Repository|Repo$|DataAccess|DbContext") || ifaces.Any(i => Regex.IsMatch(i, @"IRepository|IDbContext")))
                repositories.Add(cls);
            else if (Regex.IsMatch(name, @"Service$|Manager$|Handler$|Processor$|Engine$|Runner$|Worker$|Helper$|Provider$"))
                services.Add(cls);
            else if (cls.Methods.Count > 0)
                otherClasses.Add(cls);
        }

        bool isWebApp = controllers.Count > 0 || middlewareClasses.Count > 0;
        bool isWorker = workerClasses.Count > 0 && !isWebApp;
        bool isLibrary = entryClasses.Count == 0 && controllers.Count == 0 && workerClasses.Count == 0;

        sb.Add("flowchart TD");
        sb.Add("");

        if (isLibrary)
        {
            // Class library: show public API surface
            sb.Add("    LibEntry([\"📦 Class Library\"])");
            var publicApis = services.Concat(otherClasses)
                .Where(c => c.Methods.Count > 0)
                .OrderByDescending(c => c.Methods.Count)
                .Take(8)
                .ToList();

            if (publicApis.Count > 0)
            {
                sb.Add("    subgraph PublicAPI[\"Public API Surface\"]");
                foreach (var cls in publicApis)
                {
                    string safeId = SafeNodeId(cls.Name);
                    string methodList = string.Join(", ", cls.Methods.Take(3).Select(m => m.Name));
                    if (cls.Methods.Count > 3) methodList += $" +{cls.Methods.Count - 3} more";
                    sb.Add($"        {safeId}[\"{cls.Name}\"]");
                }
                sb.Add("    end");
                sb.Add($"    LibEntry --> PublicAPI");
            }

            AddServiceDependencies(sb, publicApis.Concat(services).ToList(), repositories, "PublicAPI");
            AddDataAccessLayer(sb, repositories, classes, methodBodies);
        }
        else
        {
            // Executable app
            sb.Add("    AppStart([\"Application Start\"])");

            // DI / Configuration phase
            var diRegistrations = DetectDiRegistrations(methodBodies);
            if (diRegistrations.Count > 0)
            {
                sb.Add("    subgraph DI[\"Dependency Injection\"]");
                foreach (var reg in diRegistrations.Take(10))
                {
                    string safeId = SafeNodeId($"di_{reg}");
                    sb.Add($"        {safeId}[\"{reg}\"]");
                }
                sb.Add("    end");
                sb.Add("    AppStart --> DI");
            }

            if (isWebApp)
            {
                // Middleware pipeline
                if (middlewareClasses.Count > 0)
                {
                    sb.Add("    subgraph MW[\"Middleware Pipeline\"]");
                    string prevMw = "";
                    foreach (var mw in middlewareClasses.Take(6))
                    {
                        string mwId = SafeNodeId($"mw_{mw.Name}");
                        sb.Add($"        {mwId}[\"{mw.Name}\"]");
                        if (!string.IsNullOrEmpty(prevMw))
                            sb.Add($"        {prevMw} --> {mwId}");
                        prevMw = mwId;
                    }
                    sb.Add("    end");
                    sb.Add(diRegistrations.Count > 0 ? "    DI --> MW" : "    AppStart --> MW");
                }

                // Controllers
                if (controllers.Count > 0)
                {
                    sb.Add("    subgraph CTRL[\"Controllers / Endpoints\"]");
                    foreach (var ctrl in controllers.Take(8))
                    {
                        string ctrlId = SafeNodeId($"ctrl_{ctrl.Name}");
                        int endpointCount = ctrl.RestEndpoints.Count;
                        string label = endpointCount > 0
                            ? $"{ctrl.Name} ({endpointCount} endpoints)"
                            : ctrl.Name;
                        sb.Add($"        {ctrlId}[\"{label}\"]");

                        // Show top REST routes
                        foreach (var ep in ctrl.RestEndpoints.Take(3))
                        {
                            string epId = SafeNodeId($"ep_{ctrl.Name}_{ep.MethodName}");
                            sb.Add($"        {ctrlId} --> {epId}[\"{ep.HttpVerb} {ep.Route}\"]");
                        }
                    }
                    sb.Add("    end");
                    sb.Add(middlewareClasses.Count > 0 ? "    MW --> CTRL" :
                        diRegistrations.Count > 0 ? "    DI --> CTRL" : "    AppStart --> CTRL");
                }

                string previousLayer = controllers.Count > 0 ? "CTRL" :
                    middlewareClasses.Count > 0 ? "MW" :
                    diRegistrations.Count > 0 ? "DI" : "AppStart";

                AddServiceLayer(sb, services, methodBodies, previousLayer);
                AddServiceDependencies(sb, controllers.Concat(services).ToList(), repositories, "SVC");
                AddDataAccessLayer(sb, repositories, classes, methodBodies);
            }
            else if (isWorker)
            {
                // Worker / hosted service
                sb.Add("    subgraph Workers[\"Background Workers\"]");
                foreach (var w in workerClasses.Take(5))
                {
                    string wId = SafeNodeId($"wk_{w.Name}");
                    sb.Add($"        {wId}([\"{w.Name}\"])");
                    foreach (var method in w.Methods.Where(m => m.Name is "ExecuteAsync" or "StartAsync" or "StopAsync" or "DoWork").Take(3))
                    {
                        string mId = SafeNodeId($"wk_{w.Name}_{method.Name}");
                        sb.Add($"        {wId} --> {mId}[\"{method.Name}\"]");
                    }
                }
                sb.Add("    end");
                sb.Add(diRegistrations.Count > 0 ? "    DI --> Workers" : "    AppStart --> Workers");

                AddServiceLayer(sb, services, methodBodies, "Workers");
                AddDataAccessLayer(sb, repositories, classes, methodBodies);
            }
            else
            {
                // Console / other executable
                string previousLayer = diRegistrations.Count > 0 ? "DI" : "AppStart";
                if (entryClasses.Count > 0)
                {
                    var mainClass = entryClasses.First();
                    sb.Add($"    subgraph MainFlow[\"{mainClass.Name}\"]");
                    foreach (var method in mainClass.Methods.Take(6))
                    {
                        string mId = SafeNodeId($"main_{method.Name}");
                        sb.Add($"        {mId}[\"{method.Name}\"]");
                    }
                    sb.Add("    end");
                    sb.Add($"    {previousLayer} --> MainFlow");
                    previousLayer = "MainFlow";
                }
                AddServiceLayer(sb, services, methodBodies, previousLayer);
                AddDataAccessLayer(sb, repositories, classes, methodBodies);
            }
        }

        // Write all accumulated lines to the static flow content
        foreach (string line in sb)
            WriteCSharpMmdExecFlow(line);
    }

    private static string SafeNodeId(string raw) =>
        Regex.Replace(raw, @"[^a-zA-Z0-9_]", "_");

    private static void AddServiceLayer(List<string> sb, List<ClassInfo> services,
        Dictionary<string, string> methodBodies, string connectFrom)
    {
        if (services.Count == 0) return;

        sb.Add("    subgraph SVC[\"Services\"]");
        foreach (var svc in services.OrderByDescending(s => s.Methods.Count).Take(8))
        {
            string svcId = SafeNodeId($"svc_{svc.Name}");
            sb.Add($"        {svcId}[\"{svc.Name}\"]");

            foreach (var method in svc.Methods.Take(3))
            {
                string bodyKey = $"{svc.FullName}.{method.Name}";
                if (methodBodies.TryGetValue(bodyKey, out string? body) && body != null)
                {
                    // Show SQL operations inline
                    foreach (var sql in method.SqlStatements.Take(2))
                    {
                        if (sql.Tables.Count > 0)
                        {
                            string tableNode = SafeNodeId($"sql_{sql.Tables[0].Replace(".", "_")}");
                            sb.Add($"        {svcId} -->|\"{sql.Operation}\"| {tableNode}[(\"{sql.Tables[0].Trim()}\")]");
                        }
                    }
                }
            }
        }
        sb.Add("    end");
        sb.Add($"    {connectFrom} --> SVC");
    }

    private static void AddServiceDependencies(List<string> sb, List<ClassInfo> consumers,
        List<ClassInfo> repositories, string connectFrom)
    {
        // Extract DI dependencies from constructor parameters
        var usedServices = new HashSet<string>();
        foreach (var cls in consumers)
        {
            foreach (string dep in cls.Dependencies)
            {
                string cleanDep = dep.TrimStart('I');
                if (repositories.Any(r => r.Name == cleanDep || r.Name == dep))
                    usedServices.Add(dep);
            }
        }
    }

    private static void AddDataAccessLayer(List<string> sb, List<ClassInfo> repositories,
        Dictionary<string, ClassInfo> classes, Dictionary<string, string> methodBodies)
    {
        if (repositories.Count == 0) return;

        sb.Add("    subgraph DAL[\"Data Access\"]");
        var sqlTables = new HashSet<string>();
        foreach (var repo in repositories.Take(5))
        {
            string repoId = SafeNodeId($"dal_{repo.Name}");
            sb.Add($"        {repoId}[\"{repo.Name}\"]");
            foreach (var method in repo.Methods)
            {
                foreach (var sql in method.SqlStatements)
                {
                    foreach (string table in sql.Tables.Take(2))
                    {
                        sqlTables.Add(table.Trim());
                    }
                }
            }
        }
        sb.Add("    end");

        if (sqlTables.Count > 0)
        {
            sb.Add("    subgraph DB[\"Database\"]");
            foreach (string table in sqlTables.Take(10))
            {
                string tblId = SafeNodeId($"tbl_{table.Replace(".", "_")}");
                sb.Add($"        {tblId}[(\"{table}\")]");
            }
            sb.Add("    end");
            sb.Add("    DAL --> DB");
        }

        sb.Add("    SVC --> DAL");
    }

    /// <summary>Detect DI service registrations from Program.cs / Startup.cs method bodies.</summary>
    private static List<string> DetectDiRegistrations(Dictionary<string, string> methodBodies)
    {
        var registrations = new List<string>();
        var seen = new HashSet<string>();

        foreach (var kvp in methodBodies)
        {
            if (!Regex.IsMatch(kvp.Key, @"Program|Startup|ConfigureServices|Main")) continue;
            string body = kvp.Value;

            // Regex: services\.Add(Scoped|Transient|Singleton|Hosted)\s*<\s*(\w+) - Match DI registrations
            var diMatches = Regex.Matches(body, @"\.Add(?:Scoped|Transient|Singleton|Hosted\w*)\s*(?:<\s*(\w+))?");
            foreach (Match m in diMatches)
            {
                string svcName = m.Groups[1].Success ? m.Groups[1].Value : "Service";
                if (seen.Add(svcName))
                    registrations.Add(svcName);
            }

            // Regex: builder\.Services\.\w+\s*<\s*(\w+) - Match builder pattern registrations
            var builderMatches = Regex.Matches(body, @"builder\.Services\.\w+\s*<\s*(\w+)");
            foreach (Match m in builderMatches)
            {
                string svcName = m.Groups[1].Value;
                if (seen.Add(svcName))
                    registrations.Add(svcName);
            }
        }

        return registrations;
    }

    /// <summary>
    /// Generates ecosystem diagram showing project interactions.
    /// Converted line-by-line from New-EcosystemDiagram (lines 10383-10522)
    /// </summary>
    private static string NewEcosystemDiagram(
        Dictionary<string, ProjectInfo> projects, Dictionary<string, List<string>> projectReferences,
        List<CommunicationPattern> communications, string solutionName)
    {
        var diagram = new List<string>();
        diagram.Add("flowchart TB");
        diagram.Add("");
        diagram.Add($"    %% {solutionName} Ecosystem");
        diagram.Add("");

        var agents = new List<(string Name, string SafeName)>();
        var dashboards = new List<(string Name, string SafeName)>();
        var trayApps = new List<(string Name, string SafeName)>();
        var apis = new List<(string Name, string SafeName)>();
        var libraries = new List<(string Name, string SafeName)>();

        foreach (string projName in projects.Keys)
        {
            string safeName = Regex.Replace(projName, @"[^a-zA-Z0-9]", "_");

            if (Regex.IsMatch(projName, @"Agent")) agents.Add((projName, safeName));
            else if (Regex.IsMatch(projName, @"Dashboard|Web|UI")) dashboards.Add((projName, safeName));
            else if (Regex.IsMatch(projName, @"Tray|Icon|Desktop")) trayApps.Add((projName, safeName));
            else if (Regex.IsMatch(projName, @"Api|Service")) apis.Add((projName, safeName));
            else libraries.Add((projName, safeName));
        }

        if (agents.Count > 0)
        {
            diagram.Add("    subgraph Agents[\"🖥️ Server Agents\"]");
            foreach (var a in agents) diagram.Add($"        {a.SafeName}([\"{a.Name}\"])");
            diagram.Add("    end");
            diagram.Add("");
        }
        if (dashboards.Count > 0)
        {
            diagram.Add("    subgraph Dashboards[\"📊 Dashboards\"]");
            foreach (var d in dashboards) diagram.Add($"        {d.SafeName}([\"{d.Name}\"])");
            diagram.Add("    end");
            diagram.Add("");
        }
        if (trayApps.Count > 0)
        {
            diagram.Add("    subgraph TrayApps[\"🔔 Tray Applications\"]");
            foreach (var t in trayApps) diagram.Add($"        {t.SafeName}([\"{t.Name}\"])");
            diagram.Add("    end");
            diagram.Add("");
        }
        if (libraries.Count > 0)
        {
            diagram.Add("    subgraph Libraries[\"📦 Shared Libraries\"]");
            foreach (var l in libraries) diagram.Add($"        {l.SafeName}[\"{l.Name}\"]");
            diagram.Add("    end");
            diagram.Add("");
        }

        // Add project references as connections
        var addedConnections = new HashSet<string>();
        foreach (var kvp in projectReferences)
        {
            string safeName = Regex.Replace(kvp.Key, @"[^a-zA-Z0-9]", "_");
            foreach (string refName in kvp.Value)
            {
                string safeRef = Regex.Replace(refName, @"[^a-zA-Z0-9]", "_");
                string connKey = $"{safeName}->{safeRef}";
                if (!addedConnections.Contains(connKey) && projects.ContainsKey(refName))
                {
                    diagram.Add($"    {safeName} -->|references| {safeRef}");
                    addedConnections.Add(connKey);
                }
            }
        }
        diagram.Add("");

        // Add API communication patterns
        var apiEndpoints = communications.Where(c => c.Type == "HTTP" && c.Endpoint.Contains("/api/")).ToList();
        var groupedByProject = apiEndpoints.GroupBy(c => c.FromProject);

        foreach (var group in groupedByProject)
        {
            string fromProj = Regex.Replace(group.Key, @"[^a-zA-Z0-9]", "_");
            foreach (var comm in group.Take(5))
            {
                // Regex: snapshot|health|status - Check if endpoint is a monitoring endpoint
                if (Regex.IsMatch(comm.Endpoint, @"snapshot|health|status"))
                {
                    var target = agents.FirstOrDefault();
                    if (target.SafeName != null)
                    {
                        string connKey = $"{fromProj}->{target.SafeName}_api";
                        if (!addedConnections.Contains(connKey))
                        {
                            diagram.Add($"    {fromProj} -.->|\"API: {comm.Endpoint}\"| {target.SafeName}");
                            addedConnections.Add(connKey);
                        }
                    }
                }
                // Regex: agent|script|restart - Check if endpoint is a control endpoint
                else if (Regex.IsMatch(comm.Endpoint, @"agent|script|restart"))
                {
                    var target = agents.FirstOrDefault();
                    if (target.SafeName != null)
                    {
                        string connKey = $"{fromProj}->{target.SafeName}_ctrl";
                        if (!addedConnections.Contains(connKey))
                        {
                            diagram.Add($"    {fromProj} -.->|\"Control: {comm.Endpoint}\"| {target.SafeName}");
                            addedConnections.Add(connKey);
                        }
                    }
                }
            }
        }

        // Add styling
        diagram.Add("");
        diagram.Add("    %% Styling");
        diagram.Add("    classDef agent fill:#2d5016,stroke:#4a8522,color:#fff");
        diagram.Add("    classDef dashboard fill:#1e3a5f,stroke:#3a7bd5,color:#fff");
        diagram.Add("    classDef tray fill:#5c2d91,stroke:#8661c5,color:#fff");
        diagram.Add("    classDef library fill:#4a4a4a,stroke:#888,color:#fff");

        foreach (var a in agents) diagram.Add($"    class {a.SafeName} agent");
        foreach (var d in dashboards) diagram.Add($"    class {d.SafeName} dashboard");
        foreach (var t in trayApps) diagram.Add($"    class {t.SafeName} tray");
        foreach (var l in libraries) diagram.Add($"    class {l.SafeName} library");

        return string.Join("\n", diagram);
    }

    #endregion

    #region HTML List Generators (lines 11888-11948)

    /// <summary>
    /// Generates HTML class list.
    /// Converted line-by-line from New-ClassListHtml (lines 11888-11905)
    /// </summary>
    private static string NewClassListHtml(Dictionary<string, ClassInfo> classes)
    {
        var sb = new StringBuilder();
        foreach (string classKey in classes.Keys.OrderBy(k => k))
        {
            var cls = classes[classKey];
            int methodCount = cls.Methods?.Count ?? 0;
            sb.AppendLine($"<div class=\"class-item\">");
            sb.AppendLine($"    <div class=\"class-name\">{cls.Name}</div>");
            sb.AppendLine($"    <div class=\"class-namespace\">{cls.Namespace}</div>");
            sb.AppendLine($"    <div class=\"class-methods\">{methodCount} methods</div>");
            sb.AppendLine($"</div>");
        }
        return sb.ToString();
    }

    /// <summary>
    /// Generates HTML project list.
    /// Converted line-by-line from New-ProjectListHtml (lines 11907-11922)
    /// </summary>
    private static string NewProjectListHtml(Dictionary<string, ProjectInfo> projects)
    {
        var sb = new StringBuilder();
        foreach (string projName in projects.Keys.OrderBy(k => k))
        {
            var proj = projects[projName];
            string framework = !string.IsNullOrEmpty(proj.TargetFramework) ? proj.TargetFramework : "Unknown";
            sb.AppendLine($"<div class=\"class-item\">");
            sb.AppendLine($"    <div class=\"class-name\">📦 {projName}</div>");
            sb.AppendLine($"    <div class=\"class-namespace\">{framework}</div>");
            sb.AppendLine($"</div>");
        }
        return sb.ToString();
    }

    /// <summary>
    /// Generates HTML namespace list.
    /// Converted line-by-line from New-NamespaceListHtml (lines 11924-11948)
    /// </summary>
    private static string NewNamespaceListHtml(Dictionary<string, ClassInfo> classes)
    {
        var namespaces = new Dictionary<string, int>();
        foreach (var cls in classes.Values)
        {
            string ns = !string.IsNullOrEmpty(cls.Namespace) ? cls.Namespace : "(default)";
            if (!namespaces.ContainsKey(ns))
                namespaces[ns] = 0;
            namespaces[ns]++;
        }

        var sb = new StringBuilder();
        foreach (string ns in namespaces.Keys.OrderBy(k => k))
        {
            int count = namespaces[ns];
            sb.AppendLine($"<div class=\"class-item\">");
            sb.AppendLine($"    <div class=\"class-name\">📁 {ns}</div>");
            sb.AppendLine($"    <div class=\"class-methods\">{count} classes</div>");
            sb.AppendLine($"</div>");
        }
        return sb.ToString();
    }

    #endregion

    #region REST Diagram Generation

    /// <summary>
    /// Generates REST API diagram with external callers.
    /// Shared between StartCSharpParse and StartCSharpEcosystemParse.
    /// </summary>
    private static string GenerateRestDiagram(
        List<RestEndpoint> restEndpoints, List<ExternalCaller> externalCallers)
    {
        if (restEndpoints.Count == 0 && externalCallers.Count == 0)
            return "flowchart LR\n    NoAPI[\"No REST API endpoints detected\"]";

        var sb = new StringBuilder();
        sb.AppendLine("flowchart TB");

        if (externalCallers.Count > 0)
        {
            sb.AppendLine("    subgraph CALLERS[\"📞 External API Callers\"]");
            int callerCounter = 0;
            var uniqueCallers = externalCallers.GroupBy(c => c.FileName).Select(g => g.First()).ToList();
            foreach (var caller in uniqueCallers)
            {
                callerCounter++;
                string callerNodeId = $"caller{callerCounter}";
                string callerIcon = caller.FileType switch
                {
                    "PowerShell" => "🔵",
                    "Batch" => "🟤",
                    "COBOL" => "🟣",
                    _ => "⚪"
                };
                sb.AppendLine($"        {callerNodeId}[\"{callerIcon} {caller.FileName}\"]");
                sb.AppendLine($"        click {callerNodeId} \"{caller.HtmlLink}\" \"Open documentation\"");
            }
            sb.AppendLine("    end");
        }

        if (restEndpoints.Count > 0)
        {
            sb.AppendLine("    subgraph API[\"🌐 REST API Endpoints\"]");
            var controllerGroups = restEndpoints.GroupBy(e => e.MethodName.Contains("Controller") ? e.MethodName : "API");
            // Group by controller based on a simple naming heuristic
            var grouped = restEndpoints.GroupBy(e =>
            {
                // Find which controller this belongs to (based on the full route prefix)
                string route = e.FullRoute;
                if (route.Contains("/")) return route.Split('/')[0];
                return "API";
            });

            foreach (var group in restEndpoints.GroupBy(e => "API"))
            {
                foreach (var endpoint in group)
                {
                    string endpointId = $"ep_{Regex.Replace(endpoint.MethodName, @"[^a-zA-Z0-9]", "_")}";
                    string verbIcon = endpoint.HttpVerb switch
                    {
                        "GET" => "🟢",
                        "POST" => "🟡",
                        "PUT" => "🟠",
                        "DELETE" => "🔴",
                        _ => "⚪"
                    };
                    string route = !string.IsNullOrEmpty(endpoint.Route) ? endpoint.Route : $"/{endpoint.MethodName.ToLower()}";
                    sb.AppendLine($"        {endpointId}[\"{verbIcon} {endpoint.HttpVerb} {route}\"]");
                }
            }
            sb.AppendLine("    end");
        }

        // Add edges from callers to endpoints
        if (externalCallers.Count > 0 && restEndpoints.Count > 0)
        {
            int callerCounter = 0;
            var uniqueCallers = externalCallers.GroupBy(c => c.FileName).Select(g => g.First()).ToList();
            foreach (var caller in uniqueCallers)
            {
                callerCounter++;
                string callerNodeId = $"caller{callerCounter}";
                if (caller.MatchedEndpoints.Count > 0)
                {
                    foreach (var matched in caller.MatchedEndpoints)
                    {
                        string endpointId = $"ep_{Regex.Replace(matched.MethodName, @"[^a-zA-Z0-9]", "_")}";
                        sb.AppendLine($"    {callerNodeId} --\"{matched.HttpVerb}\"--> {endpointId}");
                    }
                }
                else
                {
                    var first = restEndpoints.FirstOrDefault();
                    if (first != null)
                    {
                        string endpointId = $"ep_{Regex.Replace(first.MethodName, @"[^a-zA-Z0-9]", "_")}";
                        sb.AppendLine($"    {callerNodeId} -.-> {endpointId}");
                    }
                }
            }
        }

        return sb.ToString();
    }

    /// <summary>
    /// Generates REST endpoint list HTML.
    /// </summary>
    private static string GenerateRestEndpointListHtml(
        List<RestEndpoint> restEndpoints, List<ExternalCaller> externalCallers)
    {
        if (restEndpoints.Count == 0)
            return "<p>No REST API endpoints detected</p>";

        var sb = new StringBuilder();
        sb.Append("<table class='detail-table'><tr><th>Verb</th><th>Route</th><th>Method</th><th>Callers</th></tr>");

        foreach (var endpoint in restEndpoints)
        {
            var matchingCallers = externalCallers.Where(c =>
                c.MatchedEndpoints.Any(me => me.MethodName == endpoint.MethodName)).ToList();

            string callerLinks;
            if (matchingCallers.Count > 0)
            {
                callerLinks = string.Join(", ", matchingCallers.Select(c =>
                    $"<a href='{c.HtmlLink}' title='{c.FilePath}'>{c.FileName}</a>"));
            }
            else
            {
                callerLinks = "<span class='text-muted'>-</span>";
            }

            sb.Append($"<tr><td><strong>{endpoint.HttpVerb}</strong></td><td><code>{endpoint.Route}</code></td><td>{endpoint.MethodName}</td><td>{callerLinks}</td></tr>");
        }

        sb.Append("</table>");
        return sb.ToString();
    }

    /// <summary>
    /// Generates port list HTML from API config.
    /// </summary>
    private static string GeneratePortListHtml(ApiConfiguration apiConfig)
    {
        if (apiConfig.Ports.Count == 0 && apiConfig.BaseUrls.Count == 0)
            return "<p>No ports configured in launchSettings.json or appsettings.json</p>";

        var sb = new StringBuilder();
        sb.Append("<table class='detail-table'><tr><th>Type</th><th>Value</th></tr>");
        foreach (string port in apiConfig.Ports)
            sb.Append($"<tr><td><strong>Port</strong></td><td><code>{port}</code></td></tr>");
        foreach (string url in apiConfig.BaseUrls)
            sb.Append($"<tr><td><strong>URL</strong></td><td><code>{url}</code></td></tr>");
        sb.Append("</table>");
        return sb.ToString();
    }

    #endregion

    #region Start-CSharpParse (lines 10894-11376)

    /// <summary>
    /// Main entry point for C# solution/project parsing.
    /// Converted line-by-line from Start-CSharpParse (lines 10894-11376)
    /// </summary>
    public static string? StartCSharpParse(
        string sourceFolder,
        string solutionFile = "",
        string outputFolder = "",
        string tmpRootFolder = "",
        string srcRootFolder = "",
        bool clientSideRender = true,
        bool cleanUp = true,
        bool generateHtml = false)
    {
        InitializeCSharpParseVariables();

        if (!Directory.Exists(sourceFolder))
        {
            AutoDocLogger.LogMessage($"Source folder not found: {sourceFolder}", LogLevel.ERROR);
            return null;
        }

        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder)) outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder)) tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");

        if (!Directory.Exists(outputFolder))
            Directory.CreateDirectory(outputFolder);

        AutoDocLogger.LogMessage($"Starting C# parser for: {sourceFolder}", LogLevel.INFO);
        DateTime startTime = DateTime.Now;

        // Find solution files
        var solutionFiles = new List<string>();
        if (!string.IsNullOrEmpty(solutionFile) && File.Exists(solutionFile))
        {
            solutionFiles.Add(solutionFile);
        }
        else
        {
            solutionFiles = Directory.EnumerateFiles(sourceFolder, "*.sln", SearchOption.AllDirectories)
                .Take(5).ToList();
        }

        string solutionName = solutionFiles.Count > 0
            ? Path.GetFileNameWithoutExtension(solutionFiles[0])
            : Path.GetFileName(sourceFolder);

        AutoDocLogger.LogMessage($"Found {solutionFiles.Count} solution file(s)", LogLevel.INFO);

        // Parse all projects
        var allProjects = new Dictionary<string, ProjectInfo>(StringComparer.OrdinalIgnoreCase);
        var allProjectRefs = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

        foreach (string slnFile in solutionFiles)
        {
            AutoDocLogger.LogMessage($"Parsing solution: {Path.GetFileName(slnFile)}", LogLevel.INFO);
            var projects = GetSolutionProjects(slnFile);

            foreach (var proj in projects)
            {
                var projRefs = GetProjectReferences(proj.Path);
                allProjects[proj.Name] = new ProjectInfo
                {
                    Name = proj.Name,
                    Path = proj.Path,
                    TargetFramework = projRefs.TargetFramework,
                    RootNamespace = projRefs.RootNamespace,
                    PackageReferences = projRefs.PackageRefs
                };
                allProjectRefs[proj.Name] = projRefs.ProjectRefs;
            }
        }

        // Fallback to .csproj files if no solution found
        if (allProjects.Count == 0)
        {
            var csprojFiles = Directory.EnumerateFiles(sourceFolder, "*.csproj", SearchOption.AllDirectories)
                .Where(f => !Regex.IsMatch(Path.GetDirectoryName(f) ?? "", @"\\(bin|obj|packages)[\\\/]"));

            foreach (string csproj in csprojFiles)
            {
                string projName = Path.GetFileNameWithoutExtension(csproj);
                var projRefs = GetProjectReferences(csproj);
                allProjects[projName] = new ProjectInfo
                {
                    Name = projName,
                    Path = csproj,
                    TargetFramework = projRefs.TargetFramework,
                    RootNamespace = projRefs.RootNamespace,
                    PackageReferences = projRefs.PackageRefs
                };
                allProjectRefs[projName] = projRefs.ProjectRefs;
            }
        }

        AutoDocLogger.LogMessage($"Total projects found: {allProjects.Count}", LogLevel.INFO);

        // Parse all C# files
        var allClasses = new Dictionary<string, ClassInfo>(StringComparer.Ordinal);
        var allInterfaces = new Dictionary<string, InterfaceInfo>(StringComparer.Ordinal);
        int totalMethods = 0;

        foreach (var kvp in allProjects)
        {
            string projDir = Path.GetDirectoryName(kvp.Value.Path) ?? "";
            var csFiles = GetCSharpFiles(projDir);

            foreach (string csFile in csFiles)
            {
                var parsed = ReadCSharpFile(csFile, kvp.Key);
                foreach (var cls in parsed.Classes)
                {
                    if (!allClasses.ContainsKey(cls.FullName))
                    {
                        allClasses[cls.FullName] = cls;
                        totalMethods += cls.Methods.Count;
                    }
                }
                foreach (var iface in parsed.Interfaces)
                {
                    if (!allInterfaces.ContainsKey(iface.FullName))
                        allInterfaces[iface.FullName] = iface;
                }
            }
        }

        AutoDocLogger.LogMessage($"Total classes: {allClasses.Count}, interfaces: {allInterfaces.Count}, methods: {totalMethods}", LogLevel.INFO);

        // Extract method bodies for flow analysis
        var methodBodies = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var kvp in allProjects)
        {
            string projDir = Path.GetDirectoryName(kvp.Value.Path) ?? "";
            var csFiles = GetCSharpFiles(projDir);

            foreach (string csFile in csFiles)
            {
                string content;
                try { content = File.ReadAllText(csFile, Encoding.UTF8); }
                catch { continue; }
                if (string.IsNullOrEmpty(content)) continue;

                foreach (var clsKvp in allClasses)
                {
                    var cls = clsKvp.Value;
                    if (cls.FilePath != csFile) continue;

                    foreach (var method in cls.Methods)
                    {
                        string body = GetMethodBody(content, method.Name);
                        if (!string.IsNullOrEmpty(body))
                        {
                            string key = $"{cls.FullName}.{method.Name}";
                            methodBodies[key] = body;

                            // Track SQL tables for "Uses SQL" checkbox
                            foreach (var sqlStmt in method.SqlStatements)
                            {
                                foreach (string table in sqlStmt.Tables)
                                {
                                    if (_sqlTableArray != null && !_sqlTableArray.Contains(table))
                                        _sqlTableArray.Add(table);
                                }
                            }
                        }
                    }
                }
            }
        }

        AutoDocLogger.LogMessage($"Extracted {methodBodies.Count} method bodies for flow analysis", LogLevel.INFO);

        // Generate diagrams
        NewClassDiagram(allClasses, allInterfaces);

        if (allProjects.Count > 1)
            NewProjectInteractionDiagram(allProjects, allProjectRefs);
        else
        {
            WriteCSharpMmdInteraction("flowchart LR");
            WriteCSharpMmdInteraction("    A[Single Project]");
        }

        NewNamespaceFlowDiagram(allClasses);
        NewExecutionFlowDiagram(allClasses, methodBodies);

        // Generate ecosystem diagram for multi-project solutions
        if (allProjects.Count > 1)
        {
            AutoDocLogger.LogMessage("Analyzing inter-project communication patterns...", LogLevel.INFO);
            var communications = GetProjectCommunication(allProjects, sourceFolder);
            AutoDocLogger.LogMessage($"Found {communications.Count} communication patterns", LogLevel.INFO);
            _mmdEcosystemContent = NewEcosystemDiagram(allProjects, allProjectRefs, communications, solutionName);
        }
        else
        {
            _mmdEcosystemContent = "flowchart LR\n    Single[📦 Single Project Solution]\n    Note[This solution contains only one project]\n    Single --- Note";
        }

        // Load template
        string templatesFolder = Path.Combine(outputFolder, "_templates");
        string templatePath = Path.Combine(templatesFolder, "csharpmmdtemplate.html");
        string template;

        if (File.Exists(templatePath))
        {
            template = File.ReadAllText(templatePath, Encoding.UTF8);
        }
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "csharpmmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                template = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else
            {
                AutoDocLogger.LogMessage($"Template file not found at {templatePath}", LogLevel.ERROR);
                return null;
            }
        }

        // Build diagram content strings
        string classDiagramContent = string.Join("\n", _mmdClassContent ?? new List<string>());
        string projectDiagramContent = string.Join("\n", _mmdInteractionContent ?? new List<string>());
        string namespaceDiagramContent = string.Join("\n", _mmdFlowContent ?? new List<string>());
        string flowDiagramContent = string.Join("\n", _mmdExecutionFlowContent ?? new List<string>());
        string ecosystemDiagramContent = _mmdEcosystemContent ?? "";

        string classListHtml = NewClassListHtml(allClasses);
        string projectListHtml = NewProjectListHtml(allProjects);
        string namespaceListHtml = NewNamespaceListHtml(allClasses);

        string targetFramework = allProjects.Values.FirstOrDefault()?.TargetFramework ?? "Unknown";

        // Apply shared CSS and common URL replacements
        string html = ParserBase.SetAutodocTemplate(template, outputFolder);

        // Generate SQL information
        string htmlUseSql = "";
        string sqlTablesHtml;
        string sqlTablesStyle = "display: none;";
        if (_sqlTableArray != null && _sqlTableArray.Count > 0)
        {
            htmlUseSql = "checked";
            sqlTablesStyle = "";
            var sqlSb = new StringBuilder("<ul style='list-style-type: none; padding-left: 0;'>");
            foreach (string table in _sqlTableArray.Distinct().OrderBy(t => t))
            {
                string tableLink = table.Replace(".", "_").ToLower() + ".sql.html";
                sqlSb.Append($"<li style='margin-bottom: 0.25rem;'><a href='./{tableLink}' target='_blank' style='text-decoration: none; color: var(--text-primary);'>{table}</a></li>");
            }
            sqlSb.Append("</ul>");
            sqlTablesHtml = sqlSb.ToString();
        }
        else
        {
            sqlTablesHtml = "<span style='color: var(--text-secondary); font-style: italic;'>No SQL tables detected</span>";
        }

        // Page-specific replacements
        html = html.Replace("[title]", solutionName);
        html = html.Replace("[solutionname]", solutionName);
        html = html.Replace("[targetframework]", targetFramework);
        html = html.Replace("[generationdate]", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        html = html.Replace("[projectcount]", allProjects.Count.ToString());
        html = html.Replace("[classcount]", allClasses.Count.ToString());
        html = html.Replace("[interfacecount]", allInterfaces.Count.ToString());
        html = html.Replace("[methodcount]", totalMethods.ToString());
        html = html.Replace("[usesql]", htmlUseSql);
        html = html.Replace("[sqltables]", sqlTablesHtml);
        html = html.Replace("[sqltablesstyle]", sqlTablesStyle);
        html = html.Replace("[flowdiagram]", flowDiagramContent);
        html = html.Replace("[classdiagram]", classDiagramContent);
        html = html.Replace("[projectdiagram]", projectDiagramContent);
        html = html.Replace("[namespacediagram]", namespaceDiagramContent);
        html = html.Replace("[ecosystemdiagram]", ecosystemDiagramContent);
        html = html.Replace("[classlist]", classListHtml);
        html = html.Replace("[projectlist]", projectListHtml);
        html = html.Replace("[namespacelist]", namespaceListHtml);

        // Collect REST endpoints from controller classes
        var restEndpoints = new List<RestEndpoint>();
        foreach (var cls in allClasses.Values)
        {
            if (Regex.IsMatch(cls.BaseClass, @"Controller|ControllerBase") ||
                cls.Attributes.Any(a => a.Contains("ApiController")))
            {
                restEndpoints.AddRange(cls.RestEndpoints);
            }
        }

        // Get API configuration
        var apiConfig = GetCSharpApiConfiguration(sourceFolder);
        AutoDocLogger.LogMessage($"Found API configuration: {apiConfig.Ports.Count} ports, {apiConfig.BaseUrls.Count} base URLs", LogLevel.INFO);

        // Find external callers
        var externalCallers = new List<ExternalCaller>();
        if (!string.IsNullOrEmpty(srcRootFolder) && Directory.Exists(srcRootFolder) && apiConfig.Ports.Count > 0)
        {
            externalCallers = FindExternalApiCallers(srcRootFolder, apiConfig.Ports, restEndpoints, outputFolder);
            AutoDocLogger.LogMessage($"Found {externalCallers.Count} external API callers", LogLevel.INFO);
        }

        // Generate REST diagram
        string restDiagramContent = GenerateRestDiagram(restEndpoints, externalCallers);
        string restEndpointListHtml = GenerateRestEndpointListHtml(restEndpoints, externalCallers);
        string portListHtml = GeneratePortListHtml(apiConfig);

        // Detect external process invocations
        var allCsFiles = GetCSharpFiles(sourceFolder);
        var processInvocations = GetCSharpProcessInvocations(allCsFiles);
        string processDiagramContent = NewCSharpProcessDiagram(solutionName, processInvocations);
        AutoDocLogger.LogMessage($"Detected {processInvocations.Count} external process invocations", LogLevel.INFO);

        bool hasProcessInvocations = processInvocations.Count > 0;
        string processTabStyle = hasProcessInvocations ? "" : "display: none;";
        string processContentStyle = hasProcessInvocations ? "" : "display: none;";

        // Detect execution paths (who calls this C# executable from scripts/scheduled tasks)
        string execPathDiagramContent = GetCSharpExecutionPathDiagram(solutionName, srcRootFolder);
        bool hasExecPath = !string.IsNullOrEmpty(execPathDiagramContent);
        string execPathTabStyle = hasExecPath ? "" : "display: none;";
        string execPathContentStyle = hasExecPath ? "" : "display: none;";
        AutoDocLogger.LogMessage($"Execution path analysis for {solutionName}: {(hasExecPath ? "callers found" : "no callers found")}", LogLevel.INFO);

        html = html.Replace("[processdiagram]", processDiagramContent);
        html = html.Replace("[processtabstyle]", processTabStyle);
        html = html.Replace("[processcontentstyle]", processContentStyle);
        html = html.Replace("[execpathdiagram]", execPathDiagramContent);
        html = html.Replace("[execpathtabstyle]", execPathTabStyle);
        html = html.Replace("[execpathcontentstyle]", execPathContentStyle);
        html = html.Replace("[restdiagram]", restDiagramContent);
        html = html.Replace("[restendpointcount]", restEndpoints.Count.ToString());
        html = html.Replace("[restendpointlist]", restEndpointListHtml);
        html = html.Replace("[portlist]", portListHtml);
        html = html.Replace("[githistory]", GitStatsService.RenderHtmlRows(GitStatsService.GetStats(!string.IsNullOrEmpty(solutionFile) ? solutionFile : sourceFolder, sourceFolder)));

        string outputFileName = $"{solutionName}.csharp.html";
        string outputPath = Path.Combine(outputFolder, outputFileName);
        if (generateHtml)
        {
            File.WriteAllText(outputPath, html, Encoding.UTF8);
        }

        TimeSpan duration = DateTime.Now - startTime;
        AutoDocLogger.LogMessage($"Generated: {outputPath}", LogLevel.INFO);
        AutoDocLogger.LogMessage($"C# parser completed: {solutionName} ({Math.Round(duration.TotalSeconds)} seconds)", LogLevel.INFO);

        // Write JSON result alongside HTML
        try
        {
            var csharpResult = new CSharpResult
            {
                Type = "CSharp",
                FileName = solutionName,
                Title = solutionName,
                Description = $"{allProjects.Count} projects, {allClasses.Count} classes, {allInterfaces.Count} interfaces",
                GeneratedAt = DateTime.Now.ToString("o"),
                SourceFile = solutionName.ToLower(),
                Metadata = new CSharpMetadata
                {
                    SolutionName = solutionName,
                    TargetFramework = targetFramework,
                    ProjectCount = allProjects.Count,
                    ClassCount = allClasses.Count,
                    InterfaceCount = allInterfaces.Count,
                    MethodCount = totalMethods,
                    UsesSql = _sqlTableArray != null && _sqlTableArray.Count > 0
                },
                Diagrams = new CSharpDiagrams
                {
                    FlowMmd = flowDiagramContent,
                    ArchitectureMmd = MergeDiagrams("Architecture", ecosystemDiagramContent, projectDiagramContent),
                    IntegrationMmd = MergeDiagrams("Integration", processDiagramContent, execPathDiagramContent),
                    RestMmd = restDiagramContent
                },
                SqlTables = (_sqlTableArray ?? new List<string>()).Distinct().OrderBy(t => t)
                    .Select(t => new SqlTableRef { Table = t, Link = "./" + t.Replace(".", "_").ToLower() + ".sql.html" }).ToList(),
                Classes = allClasses.Values.Select(c => new CSharpClassDef
                {
                    Name = c.Name,
                    FullName = c.FullName,
                    Namespace = c.Namespace,
                    BaseClass = c.BaseClass,
                    Interfaces = c.Interfaces,
                    MethodCount = c.Methods.Count,
                    ProjectName = c.ProjectName
                }).ToList(),
                Projects = allProjects.Select(p => new CSharpProjectDef
                {
                    Name = p.Key,
                    TargetFramework = p.Value.TargetFramework,
                    PackageReferences = p.Value.PackageReferences.Select(pr => $"{pr.Name} {pr.Version}").ToList()
                }).ToList(),
                Namespaces = allClasses.Values.GroupBy(c => c.Namespace)
                    .Select(g => new CSharpNamespaceDef
                    {
                        Name = g.Key,
                        ClassCount = g.Count(),
                        ControllerCount = g.Count(c => c.BaseClass.Contains("Controller")),
                        ServiceCount = g.Count(c => c.Name.Contains("Service"))
                    }).ToList(),
                RestEndpoints = restEndpoints.Select(e => new CSharpRestEndpointDef
                {
                    Verb = e.HttpVerb,
                    Route = e.Route,
                    Method = e.MethodName
                }).ToList(),
                Ports = apiConfig.Ports.Select(p => new CSharpPortDef { PortType = "Port", Value = p }).ToList(),
                ApiCallers = externalCallers.Select(c => new CSharpApiCallerDef
                {
                    ProgramName = c.FileName,
                    FileType = c.FileType,
                    FilePath = c.FilePath,
                    MatchedEndpoint = c.MatchedEndpoints.FirstOrDefault()?.Route ?? "",
                    HttpVerb = c.MatchedEndpoints.FirstOrDefault()?.HttpVerb ?? ""
                }).ToList()
            };
            string gitPath = !string.IsNullOrEmpty(solutionFile) && File.Exists(solutionFile) ? solutionFile : sourceFolder;
            csharpResult.GitHistory = GitStatsService.GetStats(gitPath, sourceFolder);
            JsonResultWriter.WriteResult(csharpResult, outputFolder, $"{solutionName}.csharp");
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Error writing JSON result for {solutionName}: {ex.Message}", LogLevel.WARN);
        }

        return outputPath;
    }

    #endregion

    #region GetCSharpExecutionPathDiagram

    /// <summary>
    /// Generates an execution path diagram showing which scripts and scheduled tasks
    /// launch this C# executable. Searches for the solution/project name (the compiled
    /// .exe name) in *.ps1, *.bat, *.rex files and scheduled task XML exports.
    /// </summary>
    private static string GetCSharpExecutionPathDiagram(string solutionName, string srcRootFolder)
    {
        if (string.IsNullOrEmpty(srcRootFolder) || !Directory.Exists(srcRootFolder))
            return "";

        bool programInUse = false;

        // Search for the solution name (= executable name) in scripts
        var (pInUse, returnMmdArray) = ExecutionPathHelper.FindAutoDocExecutionPaths(
            srcRootFolder,
            new[] { "*.ps1", "*.bat", "*.rex" },
            solutionName,
            programInUse,
            srcRootFolder);

        programInUse = pInUse;

        if (!programInUse || returnMmdArray.Count == 0)
        {
            AutoDocLogger.LogMessage($"C# executable is never called from any script or scheduled task: {solutionName}", LogLevel.INFO);
            return "";
        }

        AutoDocLogger.LogMessage($"Found {returnMmdArray.Count} execution path entries for C# executable: {solutionName}", LogLevel.INFO);

        // Build Mermaid flowchart
        var sb = new StringBuilder();
        sb.AppendLine("flowchart LR");
        sb.AppendLine($"    {solutionName.ToLower().Replace("-", "_").Replace(".", "_")}[\"{solutionName}.exe\"]");

        foreach (string item in returnMmdArray)
        {
            sb.AppendLine($"    {item}");
        }

        return sb.ToString();
    }

    #endregion

    #region Start-CSharpEcosystemParse (lines 11378-11765)

    /// <summary>
    /// Parses an entire folder containing multiple C# projects as a unified ecosystem.
    /// Converted line-by-line from Start-CSharpEcosystemParse (lines 11378-11765)
    /// </summary>
    public static string? StartCSharpEcosystemParse(
        string rootFolder,
        string outputFolder = "",
        string tmpRootFolder = "",
        string srcRootFolder = "",
        string ecosystemName = "",
        bool generateHtml = false)
    {
        InitializeCSharpParseVariables();

        if (!Directory.Exists(rootFolder))
        {
            AutoDocLogger.LogMessage($"Root folder not found: {rootFolder}", LogLevel.ERROR);
            return null;
        }

        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder)) outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder)) tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        if (string.IsNullOrEmpty(ecosystemName)) ecosystemName = Path.GetFileName(rootFolder);

        if (!Directory.Exists(outputFolder))
            Directory.CreateDirectory(outputFolder);

        AutoDocLogger.LogMessage($"Starting C# ecosystem parse for: {rootFolder}", LogLevel.INFO);
        DateTime startTime = DateTime.Now;

        // Discover ALL projects in the folder tree
        var (allProjects, allProjectRefs) = GetAllProjectsInFolder(rootFolder);

        if (allProjects.Count == 0)
        {
            AutoDocLogger.LogMessage($"No C# projects found in {rootFolder}", LogLevel.WARN);
            return null;
        }

        AutoDocLogger.LogMessage($"Discovered {allProjects.Count} projects in ecosystem", LogLevel.INFO);

        // Parse all C# files from all projects
        var allClasses = new Dictionary<string, ClassInfo>(StringComparer.Ordinal);
        var allInterfaces = new Dictionary<string, InterfaceInfo>(StringComparer.Ordinal);
        int totalMethods = 0;

        foreach (var kvp in allProjects)
        {
            string projDir = Path.GetDirectoryName(kvp.Value.Path) ?? "";
            var csFiles = GetCSharpFiles(projDir);

            foreach (string csFile in csFiles)
            {
                var parsed = ReadCSharpFile(csFile, kvp.Key);
                foreach (var cls in parsed.Classes)
                {
                    if (!allClasses.ContainsKey(cls.FullName))
                    {
                        allClasses[cls.FullName] = cls;
                        totalMethods += cls.Methods.Count;
                    }
                }
                foreach (var iface in parsed.Interfaces)
                {
                    if (!allInterfaces.ContainsKey(iface.FullName))
                        allInterfaces[iface.FullName] = iface;
                }
            }
        }

        AutoDocLogger.LogMessage($"Parsed {allClasses.Count} classes, {allInterfaces.Count} interfaces, {totalMethods} methods", LogLevel.INFO);

        // Extract method bodies for flow analysis
        var methodBodies = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var kvp in allProjects)
        {
            string projDir = Path.GetDirectoryName(kvp.Value.Path) ?? "";
            var csFiles = GetCSharpFiles(projDir);

            foreach (string csFile in csFiles)
            {
                string content;
                try { content = File.ReadAllText(csFile, Encoding.UTF8); }
                catch { continue; }
                if (string.IsNullOrEmpty(content)) continue;

                foreach (var clsKvp in allClasses)
                {
                    var cls = clsKvp.Value;
                    if (cls.FilePath != csFile) continue;

                    foreach (var method in cls.Methods)
                    {
                        string body = GetMethodBody(content, method.Name);
                        if (!string.IsNullOrEmpty(body))
                        {
                            string key = $"{cls.FullName}.{method.Name}";
                            methodBodies[key] = body;

                            foreach (var sqlStmt in method.SqlStatements)
                            {
                                foreach (string table in sqlStmt.Tables)
                                {
                                    if (_sqlTableArray != null && !_sqlTableArray.Contains(table))
                                        _sqlTableArray.Add(table);
                                }
                            }
                        }
                    }
                }
            }
        }

        AutoDocLogger.LogMessage($"Extracted {methodBodies.Count} method bodies", LogLevel.INFO);

        // Analyze communication patterns
        AutoDocLogger.LogMessage("Analyzing cross-project communication patterns...", LogLevel.INFO);
        var communications = GetProjectCommunication(allProjects, rootFolder);
        AutoDocLogger.LogMessage($"Found {communications.Count} communication patterns", LogLevel.INFO);

        // Generate all diagrams
        NewClassDiagram(allClasses, allInterfaces);
        NewProjectInteractionDiagram(allProjects, allProjectRefs);
        NewNamespaceFlowDiagram(allClasses);
        NewExecutionFlowDiagram(allClasses, methodBodies);

        // Generate the comprehensive ecosystem diagram
        _mmdEcosystemContent = NewEcosystemDiagram(allProjects, allProjectRefs, communications, ecosystemName);

        // Load template
        string templatesFolder = Path.Combine(outputFolder, "_templates");
        string templatePath = Path.Combine(templatesFolder, "csharpmmdtemplate.html");
        string template;

        if (File.Exists(templatePath))
        {
            template = File.ReadAllText(templatePath, Encoding.UTF8);
        }
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "csharpmmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                template = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else
            {
                AutoDocLogger.LogMessage($"Template file not found at {templatePath}", LogLevel.ERROR);
                return null;
            }
        }

        string classDiagramContent = string.Join("\n", _mmdClassContent ?? new List<string>());
        string projectDiagramContent = string.Join("\n", _mmdInteractionContent ?? new List<string>());
        string namespaceDiagramContent = string.Join("\n", _mmdFlowContent ?? new List<string>());
        string flowDiagramContent = string.Join("\n", _mmdExecutionFlowContent ?? new List<string>());
        string ecosystemDiagramContent = _mmdEcosystemContent ?? "";

        string classListHtml = NewClassListHtml(allClasses);
        string projectListHtml = NewProjectListHtml(allProjects);
        string namespaceListHtml = NewNamespaceListHtml(allClasses);

        // Get most common framework
        var frameworks = allProjects.Values
            .Where(p => !string.IsNullOrEmpty(p.TargetFramework))
            .GroupBy(p => p.TargetFramework)
            .OrderByDescending(g => g.Count())
            .ToList();
        string primaryFramework = frameworks.Count > 0 ? frameworks[0].Key : "Various";

        // Apply shared CSS and common URL replacements
        string html = ParserBase.SetAutodocTemplate(template, outputFolder);

        // Generate SQL information for ecosystem
        string htmlUseSql = "";
        string sqlTablesHtml;
        string sqlTablesStyle = "display: none;";
        if (_sqlTableArray != null && _sqlTableArray.Count > 0)
        {
            htmlUseSql = "checked";
            sqlTablesStyle = "";
            var sqlSb = new StringBuilder("<ul style='list-style-type: none; padding-left: 0;'>");
            foreach (string table in _sqlTableArray.Distinct().OrderBy(t => t))
            {
                string tableLink = table.Replace(".", "_").ToLower() + ".sql.html";
                sqlSb.Append($"<li style='margin-bottom: 0.25rem;'><a href='./{tableLink}' target='_blank' style='text-decoration: none; color: var(--text-primary);'>{table}</a></li>");
            }
            sqlSb.Append("</ul>");
            sqlTablesHtml = sqlSb.ToString();
        }
        else
        {
            sqlTablesHtml = "<span style='color: var(--text-secondary); font-style: italic;'>No SQL tables detected</span>";
        }

        // Page-specific replacements
        html = html.Replace("[title]", $"{ecosystemName} Ecosystem");
        html = html.Replace("[solutionname]", $"{ecosystemName} (Ecosystem)");
        html = html.Replace("[targetframework]", primaryFramework);
        html = html.Replace("[generationdate]", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        html = html.Replace("[projectcount]", allProjects.Count.ToString());
        html = html.Replace("[classcount]", allClasses.Count.ToString());
        html = html.Replace("[interfacecount]", allInterfaces.Count.ToString());
        html = html.Replace("[methodcount]", totalMethods.ToString());
        html = html.Replace("[usesql]", htmlUseSql);
        html = html.Replace("[sqltables]", sqlTablesHtml);
        html = html.Replace("[sqltablesstyle]", sqlTablesStyle);
        html = html.Replace("[flowdiagram]", flowDiagramContent);
        html = html.Replace("[classdiagram]", classDiagramContent);
        html = html.Replace("[projectdiagram]", projectDiagramContent);
        html = html.Replace("[namespacediagram]", namespaceDiagramContent);
        html = html.Replace("[ecosystemdiagram]", ecosystemDiagramContent);
        html = html.Replace("[classlist]", classListHtml);
        html = html.Replace("[projectlist]", projectListHtml);
        html = html.Replace("[namespacelist]", namespaceListHtml);

        // Collect REST endpoints from controller classes
        var restEndpoints = new List<RestEndpoint>();
        foreach (var cls in allClasses.Values)
        {
            if (Regex.IsMatch(cls.BaseClass, @"Controller|ControllerBase") ||
                cls.Attributes.Any(a => a.Contains("ApiController")))
            {
                restEndpoints.AddRange(cls.RestEndpoints);
            }
        }

        // Get API configuration
        var apiConfig = GetCSharpApiConfiguration(rootFolder);
        AutoDocLogger.LogMessage($"Ecosystem API config: {apiConfig.Ports.Count} ports, {apiConfig.BaseUrls.Count} base URLs", LogLevel.INFO);

        // Find external callers
        var externalCallers = new List<ExternalCaller>();
        if (!string.IsNullOrEmpty(srcRootFolder) && Directory.Exists(srcRootFolder) && apiConfig.Ports.Count > 0)
        {
            externalCallers = FindExternalApiCallers(srcRootFolder, apiConfig.Ports, restEndpoints, outputFolder);
            AutoDocLogger.LogMessage($"Found {externalCallers.Count} external API callers", LogLevel.INFO);
        }

        // Generate REST diagram
        string restDiagramContent = GenerateRestDiagram(restEndpoints, externalCallers);
        string restEndpointListHtml = GenerateRestEndpointListHtml(restEndpoints, externalCallers);
        string portListHtml = GeneratePortListHtml(apiConfig);

        // Detect external process invocations
        var allCsFiles = GetCSharpFiles(rootFolder);
        var processInvocations = GetCSharpProcessInvocations(allCsFiles);
        string processDiagramContent = NewCSharpProcessDiagram(ecosystemName, processInvocations);
        AutoDocLogger.LogMessage($"Detected {processInvocations.Count} external process invocations", LogLevel.INFO);

        bool hasProcessInvocations = processInvocations.Count > 0;
        string processTabStyle = hasProcessInvocations ? "" : "display: none;";
        string processContentStyle = hasProcessInvocations ? "" : "display: none;";

        // Detect execution paths (who calls this C# executable from scripts/scheduled tasks)
        string execPathDiagramContent = GetCSharpExecutionPathDiagram(ecosystemName, srcRootFolder);
        bool hasExecPath = !string.IsNullOrEmpty(execPathDiagramContent);
        string execPathTabStyle = hasExecPath ? "" : "display: none;";
        string execPathContentStyle = hasExecPath ? "" : "display: none;";
        AutoDocLogger.LogMessage($"Execution path analysis for {ecosystemName}: {(hasExecPath ? "callers found" : "no callers found")}", LogLevel.INFO);

        html = html.Replace("[processdiagram]", processDiagramContent);
        html = html.Replace("[processtabstyle]", processTabStyle);
        html = html.Replace("[processcontentstyle]", processContentStyle);
        html = html.Replace("[execpathdiagram]", execPathDiagramContent);
        html = html.Replace("[execpathtabstyle]", execPathTabStyle);
        html = html.Replace("[execpathcontentstyle]", execPathContentStyle);
        html = html.Replace("[restdiagram]", restDiagramContent);
        html = html.Replace("[restendpointcount]", restEndpoints.Count.ToString());
        html = html.Replace("[restendpointlist]", restEndpointListHtml);
        html = html.Replace("[portlist]", portListHtml);

        string outputFileName = $"{ecosystemName}.ecosystem.csharp.html";
        string outputPath = Path.Combine(outputFolder, outputFileName);
        if (generateHtml)
        {
            File.WriteAllText(outputPath, html, Encoding.UTF8);
        }

        TimeSpan duration = DateTime.Now - startTime;
        AutoDocLogger.LogMessage($"Generated ecosystem diagram: {outputPath}", LogLevel.INFO);
        AutoDocLogger.LogMessage($"C# ecosystem parse completed: {ecosystemName} ({Math.Round(duration.TotalSeconds)} seconds)", LogLevel.INFO);

        return outputPath;
    }

    #endregion
}
