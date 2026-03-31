# Author: Geir Helge Starholm, www.dEdge.no
# Title: C# Solution/Project Parser for AutoDoc
# Description: Parses C# solutions and projects to generate:
#              - Class diagrams showing inheritance and relationships
#              - Method flow diagrams
#              - Project interaction diagrams for multi-project solutions
#              Uses client-side Mermaid.js rendering for diagrams

param(
    [Parameter(Mandatory = $true)][string]$sourceFolder,      # Path to solution or project folder
    [string]$solutionFile = "",                               # Optional: specific .sln file
    [switch]$show,
    [string]$outputFolder = "",
    [bool]$cleanUp = $false,
    [string]$tmpRootFolder = "",
    [string]$srcRootFolder = "",
    [switch]$ClientSideRender
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name AutodocFunctions -Force

#region Script-Level Variables (Thread-Safe)

$script:sequenceNumber = 0
$script:mmdClassContent = [System.Collections.ArrayList]::new()
$script:mmdFlowContent = [System.Collections.ArrayList]::new()
$script:mmdInteractionContent = [System.Collections.ArrayList]::new()
$script:duplicateLineCheck = [System.Collections.Generic.HashSet[string]]::new()
$script:errorOccurred = $false
$script:useClientSideRender = $true  # Always use client-side for C#

# Parsed data structures
$script:projects = @{}           # ProjectName -> ProjectInfo
$script:classes = @{}            # FullClassName -> ClassInfo
$script:interfaces = @{}         # FullInterfaceName -> InterfaceInfo
$script:namespaces = @{}         # Namespace -> List of types
$script:projectReferences = @{}  # ProjectName -> List of referenced projects
$script:dependencies = @{}       # TypeName -> List of dependencies

#endregion

#region C# Parsing Functions

function Get-CSharpFiles {
    <#
    .SYNOPSIS
        Gets all C# files in a folder, excluding common non-source folders.
    #>
    param([string]$FolderPath)
    
    $excludeFolders = @('bin', 'obj', 'node_modules', '.git', '.vs', 'packages', 'TestResults')
    
    $csFiles = Get-ChildItem -Path $FolderPath -Filter "*.cs" -Recurse -File | Where-Object {
        $path = $_.DirectoryName.ToLower()
        $exclude = $false
        foreach ($folder in $excludeFolders) {
            if ($path -match "\\$folder(\\|$)") {
                $exclude = $true
                break
            }
        }
        -not $exclude
    }
    
    return $csFiles
}

function Get-SolutionProjects {
    <#
    .SYNOPSIS
        Parses a .sln file to extract project information.
    #>
    param([string]$SolutionPath)
    
    $projects = @()
    
    if (-not (Test-Path $SolutionPath)) {
        Write-LogMessage "Solution file not found: $SolutionPath" -Level WARN
        return $projects
    }
    
    $content = Get-Content $SolutionPath -Raw
    
    # Regex to match Project lines in .sln file
    # Project("{GUID}") = "ProjectName", "RelativePath\Project.csproj", "{ProjectGUID}"
    $projectPattern = 'Project\("\{[A-F0-9-]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"\{([A-F0-9-]+)\}"'
    
    $matches = [regex]::Matches($content, $projectPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    
    foreach ($match in $matches) {
        $projectName = $match.Groups[1].Value
        $relativePath = $match.Groups[2].Value
        $projectGuid = $match.Groups[3].Value
        
        # Skip solution folders
        if ($relativePath -notmatch '\.csproj$') { continue }
        
        $solutionDir = Split-Path $SolutionPath -Parent
        $projectPath = Join-Path $solutionDir $relativePath
        
        if (Test-Path $projectPath) {
            $projects += [PSCustomObject]@{
                Name = $projectName
                Path = $projectPath
                Guid = $projectGuid
                RelativePath = $relativePath
            }
        }
    }
    
    return $projects
}

function Get-ProjectRestPorts {
    <#
    .SYNOPSIS
        Extracts REST API ports from launchSettings.json or appsettings.json.
    #>
    param([string]$ProjectDirectory)
    
    $ports = @{
        Http = @()
        Https = @()
        ApplicationUrl = ""
    }
    
    # Check launchSettings.json (Properties folder)
    $launchSettingsPath = Join-Path $ProjectDirectory "Properties\launchSettings.json"
    if (Test-Path $launchSettingsPath) {
        try {
            $launchSettings = Get-Content $launchSettingsPath -Raw | ConvertFrom-Json
            
            # Check profiles for applicationUrl
            if ($launchSettings.profiles) {
                foreach ($profileName in $launchSettings.profiles.PSObject.Properties.Name) {
                    $profile = $launchSettings.profiles.$profileName
                    if ($profile.applicationUrl) {
                        $ports.ApplicationUrl = $profile.applicationUrl
                        
                        # Regex pattern explanation:
                        # https?://     - Match http:// or https://
                        # [^:]+         - Match hostname (any chars except colon)
                        # :(\d+)        - Capture port number
                        $urlMatches = [regex]::Matches($profile.applicationUrl, 'https?://[^:]+:(\d+)')
                        foreach ($urlMatch in $urlMatches) {
                            $port = $urlMatch.Groups[1].Value
                            if ($profile.applicationUrl -match "https.*:$port") {
                                $ports.Https += $port
                            } else {
                                $ports.Http += $port
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Error parsing launchSettings.json: $($_.Exception.Message)" -Level DEBUG
        }
    }
    
    # Check appsettings.json for Kestrel ports
    $appSettingsPath = Join-Path $ProjectDirectory "appsettings.json"
    if (Test-Path $appSettingsPath) {
        try {
            $appSettings = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
            
            # Check Kestrel endpoints
            if ($appSettings.Kestrel -and $appSettings.Kestrel.Endpoints) {
                foreach ($endpointName in $appSettings.Kestrel.Endpoints.PSObject.Properties.Name) {
                    $endpoint = $appSettings.Kestrel.Endpoints.$endpointName
                    if ($endpoint.Url) {
                        $urlMatch = [regex]::Match($endpoint.Url, ':(\d+)')
                        if ($urlMatch.Success) {
                            $port = $urlMatch.Groups[1].Value
                            if ($endpoint.Url -match "^https") {
                                $ports.Https += $port
                            } else {
                                $ports.Http += $port
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Error parsing appsettings.json: $($_.Exception.Message)" -Level DEBUG
        }
    }
    
    # Remove duplicates
    $ports.Http = $ports.Http | Select-Object -Unique
    $ports.Https = $ports.Https | Select-Object -Unique
    
    return $ports
}

function Get-ProjectReferences {
    <#
    .SYNOPSIS
        Parses a .csproj file to extract project references and package references.
    #>
    param([string]$ProjectPath)
    
    $references = @{
        ProjectReferences = @()
        PackageReferences = @()
        TargetFramework = ""
        RootNamespace = ""
        AssemblyName = ""
    }
    
    if (-not (Test-Path $ProjectPath)) {
        return $references
    }
    
    try {
        [xml]$csproj = Get-Content $ProjectPath
        
        # Get target framework
        $tfNode = $csproj.SelectSingleNode("//TargetFramework")
        if ($tfNode) { $references.TargetFramework = $tfNode.InnerText }
        
        # Get root namespace
        $nsNode = $csproj.SelectSingleNode("//RootNamespace")
        if ($nsNode) { $references.RootNamespace = $nsNode.InnerText }
        
        # Get assembly name
        $anNode = $csproj.SelectSingleNode("//AssemblyName")
        if ($anNode) { $references.AssemblyName = $anNode.InnerText }
        
        # Get project references
        $projRefs = $csproj.SelectNodes("//ProjectReference")
        foreach ($ref in $projRefs) {
            $include = $ref.GetAttribute("Include")
            if ($include) {
                $projName = [System.IO.Path]::GetFileNameWithoutExtension($include)
                $references.ProjectReferences += $projName
            }
        }
        
        # Get package references
        $pkgRefs = $csproj.SelectNodes("//PackageReference")
        foreach ($ref in $pkgRefs) {
            $include = $ref.GetAttribute("Include")
            $version = $ref.GetAttribute("Version")
            if ($include) {
                $references.PackageReferences += [PSCustomObject]@{
                    Name = $include
                    Version = $version
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error parsing project file $ProjectPath`: $($_.Exception.Message)" -Level WARN
    }
    
    return $references
}

function Parse-CSharpFile {
    <#
    .SYNOPSIS
        Parses a C# file to extract classes, interfaces, methods, and properties.
    #>
    param(
        [string]$FilePath,
        [string]$ProjectName
    )
    
    $result = @{
        Namespace = ""
        Classes = @()
        Interfaces = @()
        Enums = @()
        Usings = @()
    }
    
    if (-not (Test-Path $FilePath)) {
        return $result
    }
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        $lines = Get-Content $FilePath -Encoding UTF8
        
        # Extract using statements
        $usingPattern = '^\s*using\s+([^;]+);'
        $usingMatches = [regex]::Matches($content, $usingPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $usingMatches) {
            $result.Usings += $match.Groups[1].Value.Trim()
        }
        
        # Extract namespace (file-scoped or block-scoped)
        $namespacePattern = '(?:namespace\s+([^\s{;]+)\s*;)|(?:namespace\s+([^\s{]+)\s*\{)'
        $nsMatch = [regex]::Match($content, $namespacePattern)
        if ($nsMatch.Success) {
            $result.Namespace = if ($nsMatch.Groups[1].Value) { $nsMatch.Groups[1].Value } else { $nsMatch.Groups[2].Value }
        }
        
        # Extract interfaces
        $interfacePattern = '(?:public|internal|private|protected)?\s*interface\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{'
        $ifaceMatches = [regex]::Matches($content, $interfacePattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $ifaceMatches) {
            $interfaceInfo = @{
                Name = $match.Groups[1].Value
                FullName = "$($result.Namespace).$($match.Groups[1].Value)"
                Extends = @()
                Methods = @()
                Properties = @()
                ProjectName = $ProjectName
                FilePath = $FilePath
            }
            
            # Parse base interfaces
            if ($match.Groups[2].Success) {
                $bases = $match.Groups[2].Value -split ',' | ForEach-Object { $_.Trim() }
                $interfaceInfo.Extends = $bases
            }
            
            $result.Interfaces += $interfaceInfo
        }
        
        # Extract classes (including attributes)
        $classPattern = '(?:\[([^\]]+)\]\s*)*(?:public|internal|private|protected)?\s*(?:abstract|sealed|static|partial)?\s*class\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{'
        $classMatches = [regex]::Matches($content, $classPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        foreach ($match in $classMatches) {
            $className = $match.Groups[2].Value
            $fullName = if ($result.Namespace) { "$($result.Namespace).$className" } else { $className }
            
            $classInfo = @{
                Name = $className
                FullName = $fullName
                Namespace = $result.Namespace
                Attributes = @()
                BaseClass = ""
                Interfaces = @()
                Methods = @()
                Properties = @()
                Fields = @()
                Dependencies = @()
                ProjectName = $ProjectName
                FilePath = $FilePath
                IsController = $false  # REST API controller detection
                ControllerRoute = ""   # [Route] attribute value
                RestEndpoints = @()    # List of REST endpoints
            }
            
            # Parse attributes
            if ($match.Groups[1].Success) {
                $classInfo.Attributes += $match.Groups[1].Value
            }
            
            # Parse base class and interfaces
            if ($match.Groups[3].Success) {
                $bases = $match.Groups[3].Value -split ',' | ForEach-Object { $_.Trim() }
                foreach ($base in $bases) {
                    $baseName = ($base -split '<')[0].Trim()  # Remove generic parameters
                    if ($baseName -match '^I[A-Z]') {
                        # Likely an interface (starts with I followed by uppercase)
                        $classInfo.Interfaces += $baseName
                    }
                    elseif (-not $classInfo.BaseClass -and $baseName -ne 'object') {
                        $classInfo.BaseClass = $baseName
                    }
                    # Detect if class is a REST controller
                    if ($baseName -match '^(Controller|ControllerBase|ApiController)$') {
                        $classInfo.IsController = $true
                    }
                }
            }
            
            # Parse controller route attribute if present
            # Regex explanation:
            # \[Route\(    - Match opening [Route(
            # "([^"]*)"    - Capture group 1: route template inside quotes
            # \)\]         - Match closing )]
            if ($classInfo.Attributes -match 'Route\("([^"]*)"\)') {
                $classInfo.ControllerRoute = $matches[1]
            }
            elseif ($classInfo.Attributes -match "Route\('([^']*)'\)") {
                $classInfo.ControllerRoute = $matches[1]
            }
            
            $result.Classes += $classInfo
        }
        
        # Extract methods for each class (simplified - gets all public/protected methods)
        $methodPattern = '(?:public|protected|internal|private)\s+(?:virtual|override|abstract|static|async)?\s*(?:Task<?\w*>?|void|[\w<>,\s\[\]]+)\s+(\w+)\s*\(([^)]*)\)'
        $methodMatches = [regex]::Matches($content, $methodPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        $methods = @()
        foreach ($match in $methodMatches) {
            $methodName = $match.Groups[1].Value
            $parameters = $match.Groups[2].Value.Trim()
            
            # Skip constructors (name matches class name)
            $isConstructor = $false
            foreach ($class in $result.Classes) {
                if ($class.Name -eq $methodName) {
                    $isConstructor = $true
                    break
                }
            }
            
            if (-not $isConstructor) {
                $methods += @{
                    Name = $methodName
                    Parameters = $parameters
                    FullSignature = "$methodName($parameters)"
                }
            }
        }
        
        # Associate methods with classes (simplified - assumes single class per file or last class)
        if ($result.Classes.Count -gt 0) {
            $result.Classes[-1].Methods = $methods
        }
        
        # Extract REST API endpoints from controller classes
        # Regex pattern explanation:
        # \[(Http(Get|Post|Put|Delete|Patch))  - Match [HttpGet, [HttpPost, etc. - Group 1=full, Group 2=verb
        # (?:\("([^"]*)"\))?                    - Optional route template in quotes - Group 3
        # \]\s*                                 - Closing bracket and whitespace
        # (?:\[[^\]]+\]\s*)*                   - Skip other attributes (like [Authorize])
        # (?:public|private|protected|internal)\s+  - Access modifier
        # (?:async\s+)?                        - Optional async keyword
        # (?:Task<?\w*>?|IActionResult|ActionResult<?\w*>?|\w+)\s+  - Return type
        # (\w+)\s*\(                           - Method name - Group 4
        $restPattern = '\[(Http(Get|Post|Put|Delete|Patch))(?:\("([^"]*)"\))?\]\s*(?:\[[^\]]+\]\s*)*(?:public|private|protected|internal)\s+(?:async\s+)?(?:Task<?\w*>?|IActionResult|ActionResult<?\w*>?|\w+)\s+(\w+)\s*\('
        $restMatches = [regex]::Matches($content, $restPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        foreach ($restMatch in $restMatches) {
            $httpVerb = $restMatch.Groups[2].Value.ToUpper()
            $routeTemplate = if ($restMatch.Groups[3].Success) { $restMatch.Groups[3].Value } else { "" }
            $methodName = $restMatch.Groups[4].Value
            
            # Find the controller class this method belongs to
            foreach ($class in $result.Classes) {
                if ($class.IsController -or $class.BaseClass -match 'Controller') {
                    $class.RestEndpoints += @{
                        HttpVerb = $httpVerb
                        Route = $routeTemplate
                        MethodName = $methodName
                        FullRoute = if ($class.ControllerRoute -and $routeTemplate) { 
                            "$($class.ControllerRoute)/$routeTemplate" 
                        } elseif ($class.ControllerRoute) { 
                            $class.ControllerRoute 
                        } else { 
                            $routeTemplate 
                        }
                    }
                    break
                }
            }
        }
        
        # Extract constructor dependencies (dependency injection)
        $ctorPattern = 'public\s+(\w+)\s*\(([^)]+)\)'
        $ctorMatches = [regex]::Matches($content, $ctorPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        foreach ($match in $ctorMatches) {
            $ctorName = $match.Groups[1].Value
            $params = $match.Groups[2].Value
            
            # Find matching class
            foreach ($class in $result.Classes) {
                if ($class.Name -eq $ctorName) {
                    # Parse constructor parameters as dependencies
                    $paramList = $params -split ','
                    foreach ($param in $paramList) {
                        $param = $param.Trim()
                        if ($param -match '^([\w<>]+)\s+\w+$') {
                            $typeName = $matches[1]
                            if ($typeName -notmatch '^(string|int|bool|double|float|decimal|long|short|byte|char|object|CancellationToken)$') {
                                $class.Dependencies += $typeName
                            }
                        }
                    }
                    break
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error parsing C# file $FilePath`: $($_.Exception.Message)" -Level WARN
    }
    
    return $result
}

#endregion

#region Mermaid Generation Functions

function Write-MmdClass {
    param([string]$mmdString)
    
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {
        [void]$script:mmdClassContent.Add($mmdString)
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}

function Write-MmdFlow {
    param([string]$mmdString)
    
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {
        $script:sequenceNumber++
        [void]$script:mmdFlowContent.Add($mmdString)
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}

function Write-MmdInteraction {
    param([string]$mmdString)
    
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {
        [void]$script:mmdInteractionContent.Add($mmdString)
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}

function Generate-ClassDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid class diagram from parsed C# classes.
    #>
    param(
        [hashtable]$Classes,
        [hashtable]$Interfaces,
        [string]$ProjectName = ""
    )
    
    Write-MmdClass "classDiagram"
    
    # Generate interfaces
    foreach ($ifaceKey in $Interfaces.Keys) {
        $iface = $Interfaces[$ifaceKey]
        
        # Filter by project if specified
        if ($ProjectName -and $iface.ProjectName -ne $ProjectName) { continue }
        
        $safeName = $iface.Name -replace '[^a-zA-Z0-9]', '_'
        Write-MmdClass "    class $safeName {"
        Write-MmdClass "        <<interface>>"
        
        foreach ($method in $iface.Methods) {
            $methodSig = $method.Name -replace '[<>]', ''
            Write-MmdClass "        +$methodSig()"
        }
        
        Write-MmdClass "    }"
        
        # Inheritance
        foreach ($baseIface in $iface.Extends) {
            $safeBase = $baseIface -replace '[^a-zA-Z0-9]', '_'
            Write-MmdClass "    $safeBase <|-- $safeName"
        }
    }
    
    # Generate classes
    foreach ($classKey in $Classes.Keys) {
        $class = $Classes[$classKey]
        
        # Filter by project if specified
        if ($ProjectName -and $class.ProjectName -ne $ProjectName) { continue }
        
        $safeName = $class.Name -replace '[^a-zA-Z0-9]', '_'
        Write-MmdClass "    class $safeName {"
        
        # Add methods (limit to first 10 for readability)
        $methodCount = 0
        foreach ($method in $class.Methods) {
            if ($methodCount -ge 10) {
                Write-MmdClass "        +...(more methods)"
                break
            }
            $methodSig = $method.Name -replace '[<>]', ''
            Write-MmdClass "        +$methodSig()"
            $methodCount++
        }
        
        Write-MmdClass "    }"
        
        # Inheritance
        if ($class.BaseClass) {
            $safeBase = $class.BaseClass -replace '[^a-zA-Z0-9]', '_'
            Write-MmdClass "    $safeBase <|-- $safeName : extends"
        }
        
        # Interface implementations
        foreach ($iface in $class.Interfaces) {
            $safeIface = $iface -replace '[^a-zA-Z0-9]', '_'
            Write-MmdClass "    $safeIface <|.. $safeName : implements"
        }
        
        # Dependencies (DI)
        foreach ($dep in $class.Dependencies) {
            $safeDep = $dep -replace '[^a-zA-Z0-9]', '_'
            Write-MmdClass "    $safeName --> $safeDep : uses"
        }
    }
}

function Generate-ProjectInteractionDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid flowchart showing project interactions.
    #>
    param(
        [hashtable]$Projects,
        [hashtable]$ProjectReferences
    )
    
    Write-MmdInteraction "flowchart TB"
    Write-MmdInteraction "    subgraph Solution"
    
    foreach ($projName in $Projects.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        $proj = $Projects[$projName]
        
        # Determine project type for styling
        $projectType = "Project"
        if ($projName -match 'Core|Library') { $projectType = "Library" }
        elseif ($projName -match 'Test') { $projectType = "Test" }
        elseif ($projName -match 'Dashboard|Web|Api') { $projectType = "WebApp" }
        elseif ($projName -match 'Tray|Desktop|WinForms|WPF') { $projectType = "DesktopApp" }
        
        Write-MmdInteraction "        ${safeName}[$projName]"
    }
    
    Write-MmdInteraction "    end"
    
    # Project references
    foreach ($projName in $ProjectReferences.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        $refs = $ProjectReferences[$projName]
        
        foreach ($ref in $refs) {
            $safeRef = $ref -replace '[^a-zA-Z0-9]', '_'
            Write-MmdInteraction "    $safeName --> $safeRef"
        }
    }
}

function Generate-NamespaceFlowDiagram {
    <#
    .SYNOPSIS
        Generates a flowchart showing namespace organization and dependencies.
    #>
    param(
        [hashtable]$Classes,
        [string]$ProjectName = ""
    )
    
    Write-MmdFlow "flowchart LR"
    
    $namespaces = @{}
    
    # Group classes by namespace
    foreach ($classKey in $Classes.Keys) {
        $classItem = $Classes[$classKey]
        
        if ($ProjectName -and $classItem.ProjectName -ne $ProjectName) { continue }
        
        $ns = if ($classItem.Namespace) { $classItem.Namespace } else { "(global)" }
        
        if (-not $namespaces.ContainsKey($ns)) {
            $namespaces[$ns] = [System.Collections.ArrayList]::new()
        }
        [void]$namespaces[$ns].Add($classItem)
    }
    
    # Generate subgraphs for each namespace
    foreach ($ns in $namespaces.Keys) {
        $safeNs = $ns -replace '[^a-zA-Z0-9]', '_'
        $classesInNs = $namespaces[$ns]
        
        Write-MmdFlow "    subgraph $safeNs[`"$ns`"]"
        
        foreach ($classItem in $classesInNs) {
            $safeName = $classItem.Name -replace '[^a-zA-Z0-9]', '_'
            Write-MmdFlow "        ${safeNs}_${safeName}[`"$($classItem.Name)`"]"
        }
        
        Write-MmdFlow "    end"
    }
    
    # Add dependency links between classes
    foreach ($classKey in $Classes.Keys) {
        $classItem = $Classes[$classKey]
        
        if ($ProjectName -and $classItem.ProjectName -ne $ProjectName) { continue }
        
        $ns = if ($classItem.Namespace) { $classItem.Namespace } else { "(global)" }
        $safeNs = $ns -replace '[^a-zA-Z0-9]', '_'
        $safeName = $classItem.Name -replace '[^a-zA-Z0-9]', '_'
        
        foreach ($dep in $classItem.Dependencies) {
            # Find the dependency in our classes
            foreach ($depKey in $Classes.Keys) {
                $depClass = $Classes[$depKey]
                if ($depClass.Name -eq $dep -or $depClass.FullName -eq $dep) {
                    $depNs = if ($depClass.Namespace) { $depClass.Namespace } else { "(global)" }
                    $safeDepNs = $depNs -replace '[^a-zA-Z0-9]', '_'
                    $safeDepName = $depClass.Name -replace '[^a-zA-Z0-9]', '_'
                    
                    Write-MmdFlow "    ${safeNs}_${safeName} --> ${safeDepNs}_${safeDepName}"
                    break
                }
            }
        }
    }
}

#endregion

#region HTML Generation

function Get-CSharpHtmlTemplate {
    <#
    .SYNOPSIS
        Returns the HTML template for C# project documentation.
    #>
    
    return @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>[projectname] - C# Project Documentation</title>
    <link rel="icon" href="[iconurl]" type="image/x-icon">
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <style>
        :root {
            --bg-color: #1a1a2e;
            --card-bg: #16213e;
            --text-color: #e4e4e4;
            --accent-color: #0f3460;
            --highlight: #e94560;
            --border-color: #0f3460;
        }
        
        * { box-sizing: border-box; margin: 0; padding: 0; }
        
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            line-height: 1.6;
            padding: 20px;
        }
        
        .container { max-width: 1800px; margin: 0 auto; }
        
        header {
            background: linear-gradient(135deg, var(--accent-color), var(--card-bg));
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            border: 1px solid var(--border-color);
        }
        
        h1 {
            color: var(--highlight);
            font-size: 2rem;
            margin-bottom: 10px;
        }
        
        .meta-info {
            display: flex;
            gap: 30px;
            flex-wrap: wrap;
            font-size: 0.9rem;
            opacity: 0.9;
        }
        
        .meta-item { display: flex; gap: 8px; }
        .meta-label { color: var(--highlight); font-weight: 600; }
        
        .section {
            background: var(--card-bg);
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 25px;
            border: 1px solid var(--border-color);
        }
        
        .section h2 {
            color: var(--highlight);
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--border-color);
        }
        
        .diagram-container {
            background: #0d1117;
            border-radius: 8px;
            padding: 20px;
            overflow: auto;
            max-height: 800px;
        }
        
        .mermaid { 
            display: flex; 
            justify-content: center;
        }
        
        .controls {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
            flex-wrap: wrap;
        }
        
        button {
            background: var(--accent-color);
            color: var(--text-color);
            border: 1px solid var(--border-color);
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            transition: all 0.2s;
        }
        
        button:hover {
            background: var(--highlight);
            transform: translateY(-1px);
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
        }
        
        .stat-card {
            background: var(--accent-color);
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        
        .stat-value {
            font-size: 2rem;
            color: var(--highlight);
            font-weight: bold;
        }
        
        .stat-label {
            opacity: 0.8;
            font-size: 0.9rem;
        }
        
        .class-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 15px;
        }
        
        .class-card {
            background: var(--accent-color);
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid var(--highlight);
        }
        
        .class-name {
            font-weight: 600;
            color: var(--highlight);
        }
        
        .class-namespace {
            font-size: 0.8rem;
            opacity: 0.7;
        }
        
        .class-methods {
            margin-top: 10px;
            font-size: 0.85rem;
        }
        
        .tabs {
            display: flex;
            gap: 5px;
            margin-bottom: 20px;
        }
        
        .tab {
            padding: 10px 20px;
            background: var(--accent-color);
            border: none;
            border-radius: 8px 8px 0 0;
            cursor: pointer;
            color: var(--text-color);
        }
        
        .tab.active {
            background: var(--highlight);
        }
        
        .tab-content {
            display: none;
        }
        
        .tab-content.active {
            display: block;
        }
        
        a {
            color: var(--highlight);
            text-decoration: none;
        }
        
        a:hover {
            text-decoration: underline;
        }
        
        .back-link {
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="back-link">
            <a href="[autodochomepageurl]">← Back to AutoDoc Home</a>
        </div>
        
        <header>
            <h1>📦 [projectname]</h1>
            <div class="meta-info">
                <div class="meta-item">
                    <span class="meta-label">Solution:</span>
                    <span>[solutionname]</span>
                </div>
                <div class="meta-item">
                    <span class="meta-label">Framework:</span>
                    <span>[targetframework]</span>
                </div>
                <div class="meta-item">
                    <span class="meta-label">Generated:</span>
                    <span>[generationdate]</span>
                </div>
            </div>
        </header>
        
        <section class="section">
            <h2>📊 Statistics</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value">[projectcount]</div>
                    <div class="stat-label">Projects</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">[classcount]</div>
                    <div class="stat-label">Classes</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">[interfacecount]</div>
                    <div class="stat-label">Interfaces</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">[methodcount]</div>
                    <div class="stat-label">Methods</div>
                </div>
            </div>
        </section>
        
        <section class="section">
            <h2>📈 Diagrams</h2>
            
            <div class="tabs">
                <button class="tab active" onclick="showTab('class-diagram')">Class Diagram</button>
                <button class="tab" onclick="showTab('project-diagram')">Project Interactions</button>
                <button class="tab" onclick="showTab('namespace-diagram')">Namespace Flow</button>
            </div>
            
            <div id="class-diagram" class="tab-content active">
                <div class="controls">
                    <button onclick="zoomIn('classDiagram')">🔍+</button>
                    <button onclick="zoomOut('classDiagram')">🔍-</button>
                    <button onclick="resetZoom('classDiagram')">📐 Reset</button>
                    <button onclick="popOut('classDiagram', 'Class Diagram')">🗗 Pop Out</button>
                </div>
                <div class="diagram-container" id="classDiagram-container">
                    <div class="mermaid" id="classDiagram">
[classdiagram_content]
                    </div>
                </div>
            </div>
            
            <div id="project-diagram" class="tab-content">
                <div class="controls">
                    <button onclick="zoomIn('projectDiagram')">🔍+</button>
                    <button onclick="zoomOut('projectDiagram')">🔍-</button>
                    <button onclick="resetZoom('projectDiagram')">📐 Reset</button>
                    <button onclick="popOut('projectDiagram', 'Project Interactions')">🗗 Pop Out</button>
                </div>
                <div class="diagram-container" id="projectDiagram-container">
                    <div class="mermaid" id="projectDiagram">
[projectdiagram_content]
                    </div>
                </div>
            </div>
            
            <div id="namespace-diagram" class="tab-content">
                <div class="controls">
                    <button onclick="zoomIn('namespaceDiagram')">🔍+</button>
                    <button onclick="zoomOut('namespaceDiagram')">🔍-</button>
                    <button onclick="resetZoom('namespaceDiagram')">📐 Reset</button>
                    <button onclick="popOut('namespaceDiagram', 'Namespace Flow')">🗗 Pop Out</button>
                </div>
                <div class="diagram-container" id="namespaceDiagram-container">
                    <div class="mermaid" id="namespaceDiagram">
[namespacediagram_content]
                    </div>
                </div>
            </div>
        </section>
        
        <section class="section">
            <h2>📚 Classes & Interfaces</h2>
            <div class="class-list">
[classlist_content]
            </div>
        </section>
        
        <section class="section">
            <h2>🔗 Related Projects</h2>
            <div class="class-list">
[relatedprojects_content]
            </div>
        </section>
    </div>
    
    <script>
        // Initialize Mermaid
        mermaid.initialize({
            startOnLoad: true,
            theme: 'dark',
            securityLevel: 'loose',
            flowchart: { curve: 'basis', padding: 20 },
            maxEdges: 2000,
            maxTextSize: 100000
        });
        
        // Zoom functionality
        const zoomLevels = {};
        
        function zoomIn(id) {
            if (!zoomLevels[id]) zoomLevels[id] = 1;
            zoomLevels[id] *= 1.2;
            document.getElementById(id).style.transform = `scale(${zoomLevels[id]})`;
        }
        
        function zoomOut(id) {
            if (!zoomLevels[id]) zoomLevels[id] = 1;
            zoomLevels[id] *= 0.8;
            document.getElementById(id).style.transform = `scale(${zoomLevels[id]})`;
        }
        
        function resetZoom(id) {
            zoomLevels[id] = 1;
            document.getElementById(id).style.transform = 'scale(1)';
        }
        
        // Tab functionality
        function showTab(tabId) {
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            event.target.classList.add('active');
        }
        
        // Pop out functionality
        function popOut(id, title) {
            const content = document.getElementById(id).innerHTML;
            const popup = window.open('', title, 'width=1200,height=800');
            popup.document.write(`
                <!DOCTYPE html>
                <html>
                <head>
                    <title>${title}</title>
                    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"><\/script>
                    <style>
                        body { background: #0d1117; margin: 20px; }
                        .mermaid { display: flex; justify-content: center; }
                    </style>
                </head>
                <body>
                    <div class="mermaid">${content}</div>
                    <script>
                        mermaid.initialize({ startOnLoad: true, theme: 'dark', securityLevel: 'loose' });
                    <\/script>
                </body>
                </html>
            `);
        }
    </script>
</body>
</html>
'@
}

function Generate-ClassListHtml {
    param([hashtable]$Classes)
    
    $html = ""
    
    foreach ($classKey in $Classes.Keys | Sort-Object) {
        $class = $Classes[$classKey]
        
        $methodCount = $class.Methods.Count
        $interfaces = if ($class.Interfaces.Count -gt 0) { "Implements: " + ($class.Interfaces -join ", ") } else { "" }
        $baseClass = if ($class.BaseClass) { "Extends: $($class.BaseClass)" } else { "" }
        
        $html += @"
                <div class="class-card">
                    <div class="class-name">$($class.Name)</div>
                    <div class="class-namespace">$($class.Namespace)</div>
                    <div class="class-methods">
                        $methodCount methods
                        $(if ($baseClass) { "<br>$baseClass" })
                        $(if ($interfaces) { "<br>$interfaces" })
                    </div>
                </div>

"@
    }
    
    return $html
}

function Generate-RelatedProjectsHtml {
    param(
        [hashtable]$Projects,
        [string]$OutputFolder
    )
    
    $html = ""
    
    foreach ($projName in $Projects.Keys | Sort-Object) {
        $proj = $Projects[$projName]
        $fileName = "$projName.csharp.html"
        
        $html += @"
                <div class="class-card">
                    <a href="$fileName" class="class-name">$projName</a>
                    <div class="class-namespace">$($proj.TargetFramework)</div>
                </div>

"@
    }
    
    return $html
}

#endregion

#region Main Execution

# Validate input
if (-not (Test-Path $sourceFolder)) {
    Write-LogMessage "Source folder not found: $sourceFolder" -Level ERROR
    exit 1
}

# Set default folders
if (-not $outputFolder) { $outputFolder = "$env:OptPath\data\AutoDoc" }
if (-not $tmpRootFolder) { $tmpRootFolder = "$env:OptPath\data\AutoDoc\tmp" }

# Create output folder if needed
if (-not (Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
}

Write-LogMessage "Starting C# parser for: $sourceFolder" -Level INFO

$StartTime = Get-Date

# Find solution files
$solutionFiles = @()
if ($solutionFile -and (Test-Path $solutionFile)) {
    $solutionFiles += Get-Item $solutionFile
}
else {
    $solutionFiles = Get-ChildItem -Path $sourceFolder -Filter "*.sln" -Recurse | Select-Object -First 5
}

$solutionName = if ($solutionFiles.Count -gt 0) { 
    [System.IO.Path]::GetFileNameWithoutExtension($solutionFiles[0].Name) 
} else { 
    Split-Path $sourceFolder -Leaf 
}

Write-LogMessage "Found $($solutionFiles.Count) solution file(s)" -Level INFO

# Parse all projects
$allProjects = @{}
$allProjectRefs = @{}

foreach ($slnFile in $solutionFiles) {
    Write-LogMessage "Parsing solution: $($slnFile.Name)" -Level INFO
    $projects = Get-SolutionProjects -SolutionPath $slnFile.FullName
    
    foreach ($proj in $projects) {
        $projRefs = Get-ProjectReferences -ProjectPath $proj.Path
        
        $allProjects[$proj.Name] = @{
            Name = $proj.Name
            Path = $proj.Path
            TargetFramework = $projRefs.TargetFramework
            RootNamespace = $projRefs.RootNamespace
            PackageReferences = $projRefs.PackageReferences
        }
        
        $allProjectRefs[$proj.Name] = $projRefs.ProjectReferences
        
        Write-LogMessage "  Project: $($proj.Name) -> $($projRefs.ProjectReferences.Count) project refs" -Level INFO
    }
}

# If no solution found, scan for .csproj files directly
if ($allProjects.Count -eq 0) {
    Write-LogMessage "No solution files found, scanning for .csproj files directly" -Level INFO
    
    $csprojFiles = Get-ChildItem -Path $sourceFolder -Filter "*.csproj" -Recurse | Where-Object {
        $_.DirectoryName -notmatch '\\(bin|obj|packages)[\\/]'
    }
    
    foreach ($csproj in $csprojFiles) {
        $projName = [System.IO.Path]::GetFileNameWithoutExtension($csproj.Name)
        $projRefs = Get-ProjectReferences -ProjectPath $csproj.FullName
        
        $allProjects[$projName] = @{
            Name = $projName
            Path = $csproj.FullName
            TargetFramework = $projRefs.TargetFramework
            RootNamespace = $projRefs.RootNamespace
            PackageReferences = $projRefs.PackageReferences
        }
        
        $allProjectRefs[$projName] = $projRefs.ProjectReferences
    }
}

Write-LogMessage "Total projects found: $($allProjects.Count)" -Level INFO

# Parse all C# files
$allClasses = @{}
$allInterfaces = @{}
$totalMethods = 0

foreach ($projName in $allProjects.Keys) {
    $proj = $allProjects[$projName]
    $projDir = Split-Path $proj.Path -Parent
    
    Write-LogMessage "Parsing C# files in project: $projName" -Level INFO
    
    $csFiles = Get-CSharpFiles -FolderPath $projDir
    
    foreach ($csFile in $csFiles) {
        $parsed = Parse-CSharpFile -FilePath $csFile.FullName -ProjectName $projName
        
        foreach ($class in $parsed.Classes) {
            $key = $class.FullName
            if (-not $allClasses.ContainsKey($key)) {
                $allClasses[$key] = $class
                $totalMethods += $class.Methods.Count
            }
        }
        
        foreach ($iface in $parsed.Interfaces) {
            $key = $iface.FullName
            if (-not $allInterfaces.ContainsKey($key)) {
                $allInterfaces[$key] = $iface
            }
        }
    }
}

Write-LogMessage "Total classes: $($allClasses.Count), interfaces: $($allInterfaces.Count), methods: $totalMethods" -Level INFO

# Check if projects interact
$hasInteractions = $false
foreach ($refs in $allProjectRefs.Values) {
    if ($refs.Count -gt 0) {
        $hasInteractions = $true
        break
    }
}

Write-LogMessage "Projects have interactions: $hasInteractions" -Level INFO

# Generate diagrams
Write-LogMessage "Generating Mermaid diagrams..." -Level INFO

# Class diagram
Generate-ClassDiagram -Classes $allClasses -Interfaces $allInterfaces

# Project interaction diagram (if multiple projects)
if ($allProjects.Count -gt 1) {
    Generate-ProjectInteractionDiagram -Projects $allProjects -ProjectReferences $allProjectRefs
}
else {
    Write-MmdInteraction "flowchart LR"
    Write-MmdInteraction "    A[Single Project - No Interactions]"
}

# Namespace flow diagram
Generate-NamespaceFlowDiagram -Classes $allClasses

# Collect REST endpoints and ports
$script:restEndpoints = @()
$script:restPorts = @()
foreach ($classKey in $allClasses.Keys) {
    $class = $allClasses[$classKey]
    if ($class.IsController -or $class.RestEndpoints.Count -gt 0) {
        foreach ($endpoint in $class.RestEndpoints) {
            $script:restEndpoints += @{
                Controller = $class.Name
                HttpVerb = $endpoint.HttpVerb
                Route = $endpoint.FullRoute
                MethodName = $endpoint.MethodName
            }
        }
    }
}

# Get ports from each project
foreach ($projectKey in $allProjects.Keys) {
    $project = $allProjects[$projectKey]
    $projectDir = Split-Path $project.Path -Parent
    $ports = Get-ProjectRestPorts -ProjectDirectory $projectDir
    if ($ports.Http.Count -gt 0 -or $ports.Https.Count -gt 0) {
        $script:restPorts += @{
            ProjectName = $project.Name
            Http = $ports.Http
            Https = $ports.Https
            ApplicationUrl = $ports.ApplicationUrl
        }
    }
}

# Generate REST API diagram
$script:mmdRestContent = [System.Collections.ArrayList]::new()
function Write-MmdRest { param([string]$line); [void]$script:mmdRestContent.Add($line) }

if ($script:restEndpoints.Count -gt 0) {
    Write-MmdRest "flowchart LR"
    Write-MmdRest "    subgraph API[`"🌐 REST API Endpoints`"]"
    
    # Group by controller
    $controllerGroups = $script:restEndpoints | Group-Object -Property Controller
    foreach ($group in $controllerGroups) {
        $controllerName = $group.Name
        $safeName = $controllerName -replace '[^a-zA-Z0-9]', '_'
        Write-MmdRest "        subgraph $safeName[`"📦 $controllerName`"]"
        
        foreach ($endpoint in $group.Group) {
            $endpointId = "$($safeName)_$($endpoint.MethodName)"
            $verbIcon = switch ($endpoint.HttpVerb) {
                "GET" { "🟢" }
                "POST" { "🟡" }
                "PUT" { "🟠" }
                "DELETE" { "🔴" }
                "PATCH" { "🟣" }
                default { "⚪" }
            }
            $route = if ($endpoint.Route) { $endpoint.Route } else { "/$($endpoint.MethodName.ToLower())" }
            Write-MmdRest "            $endpointId[`"$verbIcon $($endpoint.HttpVerb) $route`"]"
        }
        Write-MmdRest "        end"
    }
    Write-MmdRest "    end"
}
else {
    Write-MmdRest "flowchart LR"
    Write-MmdRest "    NoAPI[`"No REST API endpoints detected`"]"
}

# Generate HTML output
Write-LogMessage "Generating HTML output..." -Level INFO

# Load external template (preferred) or fall back to embedded
$templatePath = Join-Path $PSScriptRoot "csharpmmdtemplate.html"
if (Test-Path $templatePath) {
    $template = Get-Content $templatePath -Raw -Encoding UTF8
}
else {
    $template = Get-CSharpHtmlTemplate
}

# Apply shared CSS and common URL replacements
$template = Set-AutodocTemplate -Template $template

# Build class diagram content
$classDiagramContent = $script:mmdClassContent -join "`n"

# Build project diagram content
$projectDiagramContent = $script:mmdInteractionContent -join "`n"

# Build namespace diagram content
$namespaceDiagramContent = $script:mmdFlowContent -join "`n"

# Generate class list HTML
$classListHtml = Generate-ClassListHtml -Classes $allClasses

# Generate related projects HTML
$relatedProjectsHtml = Generate-RelatedProjectsHtml -Projects $allProjects -OutputFolder $outputFolder

# Fill template
$html = $template
$html = $html.Replace("[projectname]", $solutionName)
$html = $html.Replace("[solutionname]", $solutionName)
$html = $html.Replace("[targetframework]", ($allProjects.Values | Select-Object -First 1).TargetFramework)
$html = $html.Replace("[generationdate]", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$html = $html.Replace("[projectcount]", $allProjects.Count.ToString())
$html = $html.Replace("[classcount]", $allClasses.Count.ToString())
$html = $html.Replace("[interfacecount]", $allInterfaces.Count.ToString())
$html = $html.Replace("[methodcount]", $totalMethods.ToString())
# Handle both old (embedded) and new (external) template placeholder names
$html = $html.Replace("[classdiagram_content]", $classDiagramContent)
$html = $html.Replace("[classdiagram]", $classDiagramContent)
$html = $html.Replace("[projectdiagram_content]", $projectDiagramContent)
$html = $html.Replace("[projectdiagram]", $projectDiagramContent)
$html = $html.Replace("[namespacediagram_content]", $namespaceDiagramContent)
$html = $html.Replace("[namespacediagram]", $namespaceDiagramContent)
$html = $html.Replace("[classlist_content]", $classListHtml)
$html = $html.Replace("[classlist]", $classListHtml)
$html = $html.Replace("[relatedprojects_content]", $relatedProjectsHtml)
$html = $html.Replace("[projectlist]", $relatedProjectsHtml)
# Additional placeholders for new template (provide empty or duplicate content)
$html = $html.Replace("[flowdiagram]", $namespaceDiagramContent)
$html = $html.Replace("[ecosystemdiagram]", $projectDiagramContent)
$html = $html.Replace("[namespacelist]", "")

# Generate REST API diagram content
$restDiagramContent = $script:mmdRestContent -join "`n"
$html = $html.Replace("[restdiagram]", $restDiagramContent)
$html = $html.Replace("[restendpointcount]", $script:restEndpoints.Count.ToString())

# Generate REST endpoint list HTML
$restEndpointListHtml = ""
if ($script:restEndpoints.Count -gt 0) {
    $restEndpointListHtml = "<table class='detail-table'><tr><th>Verb</th><th>Route</th><th>Controller</th><th>Method</th></tr>"
    foreach ($endpoint in $script:restEndpoints) {
        $verbClass = switch ($endpoint.HttpVerb) {
            "GET" { "text-success" }
            "POST" { "text-warning" }
            "PUT" { "text-info" }
            "DELETE" { "text-danger" }
            default { "" }
        }
        $restEndpointListHtml += "<tr><td class='$verbClass'><strong>$($endpoint.HttpVerb)</strong></td><td><code>$($endpoint.Route)</code></td><td>$($endpoint.Controller)</td><td>$($endpoint.MethodName)</td></tr>"
    }
    $restEndpointListHtml += "</table>"
}
else {
    $restEndpointListHtml = "<p>No REST API endpoints detected</p>"
}
$html = $html.Replace("[restendpointlist]", $restEndpointListHtml)

# Generate port list HTML
$portListHtml = ""
if ($script:restPorts.Count -gt 0) {
    $portListHtml = "<table class='detail-table'><tr><th>Project</th><th>HTTP</th><th>HTTPS</th></tr>"
    foreach ($portInfo in $script:restPorts) {
        $httpPorts = if ($portInfo.Http.Count -gt 0) { $portInfo.Http -join ", " } else { "-" }
        $httpsPorts = if ($portInfo.Https.Count -gt 0) { $portInfo.Https -join ", " } else { "-" }
        $portListHtml += "<tr><td>$($portInfo.ProjectName)</td><td>$httpPorts</td><td>$httpsPorts</td></tr>"
    }
    $portListHtml += "</table>"
}
else {
    $portListHtml = "<p>No ports configured in launchSettings.json or appsettings.json</p>"
}
$html = $html.Replace("[portlist]", $portListHtml)

# Save HTML file
$outputFileName = "$solutionName.csharp.html"
$outputPath = Join-Path $outputFolder $outputFileName
$html | Set-Content -Path $outputPath -Encoding UTF8

$EndTime = Get-Date
$Duration = [math]::Round(($EndTime - $StartTime).TotalSeconds)

Write-LogMessage "Generated: $outputPath" -Level INFO
Write-LogMessage "Time elapsed: $Duration seconds" -Level INFO
Write-LogMessage "C# parser completed successfully: $solutionName" -Level INFO

# Output the file path for verification
Write-Output $outputPath

#endregion
