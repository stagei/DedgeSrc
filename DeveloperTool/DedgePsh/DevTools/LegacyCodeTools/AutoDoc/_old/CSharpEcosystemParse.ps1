# Author: Geir Helge Starholm, www.dEdge.no
# Title: C# Ecosystem Parser for AutoDoc
# Description: Parses a folder containing multiple related C# solutions and projects
#              to generate an overview of the entire ecosystem with interaction diagrams.
#
# Usage:
#   .\CSharpEcosystemParse.ps1 -ecosystemFolder "C:\opt\src\ServerMonitor"

param(
    [Parameter(Mandatory = $true)]
    [string]$ecosystemFolder,
    
    [string]$ecosystemName = "",
    [string]$outputFolder = "",
    [switch]$generateIndividual
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name AutodocFunctions -Force

#region Script Variables

$script:solutions = @{}
$script:allProjects = @{}
$script:crossSolutionDeps = @{}
$script:sharedNamespaces = @{}
$script:mmdContent = [System.Collections.ArrayList]::new()
$script:duplicateCheck = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

#endregion

#region Helper Functions

function Write-EcoMmd {
    param([string]$line)
    if (-not $script:duplicateCheck.Contains($line)) {
        [void]$script:mmdContent.Add($line)
        [void]$script:duplicateCheck.Add($line)
    }
}

function Get-SolutionInfo {
    param([string]$slnPath)
    
    $solutionDir = Split-Path $slnPath -Parent
    $solutionName = [System.IO.Path]::GetFileNameWithoutExtension($slnPath)
    
    $projects = @()
    $content = Get-Content $slnPath -Raw
    
    # Parse project references from solution file
    $projectPattern = 'Project\("\{[A-F0-9-]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"\{([A-F0-9-]+)\}"'
    $matches = [regex]::Matches($content, $projectPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    
    foreach ($match in $matches) {
        $projectName = $match.Groups[1].Value
        $relativePath = $match.Groups[2].Value
        
        if ($relativePath -notmatch '\.csproj$') { continue }
        
        $projectPath = Join-Path $solutionDir $relativePath
        
        if (Test-Path $projectPath) {
            $projInfo = Get-ProjectInfo -ProjectPath $projectPath -SolutionName $solutionName
            $projects += $projInfo
        }
    }
    
    return @{
        Name = $solutionName
        Path = $slnPath
        Directory = $solutionDir
        Projects = $projects
    }
}

function Get-ProjectInfo {
    param(
        [string]$ProjectPath,
        [string]$SolutionName
    )
    
    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
    $projectDir = Split-Path $ProjectPath -Parent
    
    $info = @{
        Name = $projectName
        Path = $ProjectPath
        Directory = $projectDir
        SolutionName = $SolutionName
        TargetFramework = ""
        RootNamespace = ""
        ProjectReferences = @()
        PackageReferences = @()
        Namespaces = @()
        ClassCount = 0
        IsLibrary = $false
        IsWebApp = $false
        IsDesktopApp = $false
        IsTest = $false
    }
    
    try {
        [xml]$csproj = Get-Content $ProjectPath
        
        # Target framework
        $tfNode = $csproj.SelectSingleNode("//TargetFramework")
        if ($tfNode) { $info.TargetFramework = $tfNode.InnerText }
        
        # Root namespace
        $nsNode = $csproj.SelectSingleNode("//RootNamespace")
        if ($nsNode) { $info.RootNamespace = $nsNode.InnerText }
        else { $info.RootNamespace = $projectName }
        
        # Determine project type
        $sdk = $csproj.Project.Sdk
        if ($sdk -match 'Web') { $info.IsWebApp = $true }
        
        $outputType = $csproj.SelectSingleNode("//OutputType")
        if ($outputType) {
            if ($outputType.InnerText -eq 'Library') { $info.IsLibrary = $true }
            elseif ($outputType.InnerText -match 'Exe|WinExe') { $info.IsDesktopApp = $true }
        }
        
        if ($projectName -match 'Test') { $info.IsTest = $true }
        
        # Project references
        $projRefs = $csproj.SelectNodes("//ProjectReference")
        foreach ($ref in $projRefs) {
            $include = $ref.GetAttribute("Include")
            if ($include) {
                $refName = [System.IO.Path]::GetFileNameWithoutExtension($include)
                $info.ProjectReferences += $refName
            }
        }
        
        # Package references
        $pkgRefs = $csproj.SelectNodes("//PackageReference")
        foreach ($ref in $pkgRefs) {
            $include = $ref.GetAttribute("Include")
            if ($include) {
                $info.PackageReferences += $include
            }
        }
        
        # Scan for namespaces and count classes
        $csFiles = Get-ChildItem -Path $projectDir -Filter "*.cs" -Recurse -File | Where-Object {
            $_.DirectoryName -notmatch '\\(bin|obj)[\\/]'
        }
        
        $namespaces = @{}
        $classCount = 0
        
        foreach ($csFile in $csFiles) {
            $content = Get-Content $csFile.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            
            # Extract namespace
            if ($content -match 'namespace\s+([^\s{;]+)') {
                $ns = $matches[1]
                if (-not $namespaces.ContainsKey($ns)) {
                    $namespaces[$ns] = 0
                }
                $namespaces[$ns]++
            }
            
            # Count classes
            $classMatches = [regex]::Matches($content, '\bclass\s+\w+')
            $classCount += $classMatches.Count
        }
        
        $info.Namespaces = $namespaces.Keys | Sort-Object
        $info.ClassCount = $classCount
    }
    catch {
        Write-LogMessage "Error parsing project $ProjectPath`: $($_.Exception.Message)" -Level WARN
    }
    
    return $info
}

function Find-CrossSolutionDependencies {
    <#
    .SYNOPSIS
        Analyzes namespace usage to find cross-solution dependencies.
    #>
    param([hashtable]$Solutions)
    
    $dependencies = @{}
    $namespaceToSolution = @{}
    
    # Build namespace -> solution mapping
    foreach ($slnName in $Solutions.Keys) {
        $solution = $Solutions[$slnName]
        foreach ($proj in $solution.Projects) {
            foreach ($ns in $proj.Namespaces) {
                if (-not $namespaceToSolution.ContainsKey($ns)) {
                    $namespaceToSolution[$ns] = @()
                }
                $namespaceToSolution[$ns] += $slnName
            }
        }
    }
    
    # Find shared namespaces (potential integration points)
    $sharedNs = @{}
    foreach ($ns in $namespaceToSolution.Keys) {
        $solutionsForNs = @($namespaceToSolution[$ns]) | Select-Object -Unique
        if ($solutionsForNs.Count -gt 1) {
            $sharedNs[$ns] = $solutionsForNs
        }
    }
    
    return @{
        NamespaceMapping = $namespaceToSolution
        SharedNamespaces = $sharedNs
    }
}

function Generate-EcosystemDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid diagram showing the ecosystem overview.
    #>
    param(
        [hashtable]$Solutions,
        [hashtable]$CrossDeps
    )
    
    Write-EcoMmd "flowchart TB"
    
    # Create subgraphs for each solution
    foreach ($slnName in $Solutions.Keys | Sort-Object) {
        $solution = $Solutions[$slnName]
        $safeSln = $slnName -replace '[^a-zA-Z0-9]', '_'
        
        Write-EcoMmd "    subgraph ${safeSln}[`"📦 $slnName`"]"
        Write-EcoMmd "        direction LR"
        
        foreach ($proj in $solution.Projects) {
            $safeProj = $proj.Name -replace '[^a-zA-Z0-9]', '_'
            
            # Determine icon based on project type
            $icon = "📁"
            if ($proj.IsWebApp) { $icon = "🌐" }
            elseif ($proj.IsDesktopApp) { $icon = "🖥️" }
            elseif ($proj.IsLibrary) { $icon = "📚" }
            elseif ($proj.IsTest) { $icon = "🧪" }
            
            Write-EcoMmd "        ${safeSln}_${safeProj}[`"$icon $($proj.Name)<br/>$($proj.ClassCount) classes`"]"
            
            # Internal project references
            foreach ($ref in $proj.ProjectReferences) {
                $safeRef = $ref -replace '[^a-zA-Z0-9]', '_'
                Write-EcoMmd "        ${safeSln}_${safeProj} --> ${safeSln}_${safeRef}"
            }
        }
        
        Write-EcoMmd "    end"
    }
    
    # Add cross-solution links for shared namespaces
    if ($CrossDeps.SharedNamespaces.Count -gt 0) {
        Write-EcoMmd "    subgraph SharedNamespaces[`"🔗 Shared Namespaces`"]"
        
        $nsIndex = 0
        foreach ($ns in $CrossDeps.SharedNamespaces.Keys | Select-Object -First 10) {
            $safeNs = "SharedNs_$nsIndex"
            $shortNs = if ($ns.Length -gt 30) { $ns.Substring(0, 30) + "..." } else { $ns }
            Write-EcoMmd "        ${safeNs}[`"$shortNs`"]"
            $nsIndex++
        }
        
        Write-EcoMmd "    end"
    }
    
    # Add legend
    Write-EcoMmd "    subgraph Legend[`"📋 Legend`"]"
    Write-EcoMmd "        direction LR"
    Write-EcoMmd "        L1[🌐 Web App]"
    Write-EcoMmd "        L2[🖥️ Desktop]"
    Write-EcoMmd "        L3[📚 Library]"
    Write-EcoMmd "        L4[🧪 Test]"
    Write-EcoMmd "    end"
}

function Get-EcosystemHtmlTemplate {
    return @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>[ecosystemname] - C# Ecosystem Overview</title>
    <link rel="icon" href="[iconurl]" type="image/x-icon">
    <link rel="stylesheet" href="[cssoverrideurl]">
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <style>
[css]
        /* Ecosystem-specific overrides */
        .container { max-width: 1600px; }
        .ecosystem-header { background: linear-gradient(135deg, #1f6feb 0%, #238636 100%); padding: 40px; border-radius: 16px; margin-bottom: 32px; text-align: center; }
        .ecosystem-header h1 { color: white; font-size: 2.5rem; margin-bottom: 8px; text-shadow: 0 2px 4px rgba(0,0,0,0.3); }
        .subtitle { color: rgba(255,255,255,0.9); font-size: 1.1rem; }
        .stats-row { display: flex; justify-content: center; gap: 40px; margin-top: 24px; }
        .stat { text-align: center; }
        .stat-value { font-size: 2.5rem; font-weight: bold; color: white; }
        .stat-label { font-size: 0.9rem; color: rgba(255,255,255,0.8); }
        .solutions-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(350px, 1fr)); gap: 20px; }
        .solution-card { background: var(--bg-secondary); border: 1px solid var(--border-color); border-radius: 10px; padding: 20px; }
        .solution-header { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
        .solution-icon { font-size: 2rem; }
        .solution-name { font-size: 1.2rem; font-weight: 600; color: var(--accent-primary); }
        .solution-name a { color: inherit; text-decoration: none; }
        .solution-name a:hover { text-decoration: underline; }
        .solution-stats { display: flex; gap: 16px; margin-bottom: 12px; font-size: 0.85rem; color: var(--text-secondary); }
        .project-list { list-style: none; padding: 0; }
        .project-item { padding: 8px 12px; margin: 4px 0; background: var(--bg-card); border-radius: 6px; display: flex; justify-content: space-between; align-items: center; font-size: 0.9rem; }
        .project-type { padding: 2px 8px; border-radius: 12px; font-size: 0.75rem; background: var(--accent-success); color: white; }
        .project-type.web { background: #1f6feb; }
        .project-type.lib { background: #8957e5; }
        .project-type.test { background: #f85149; }
    </style>
</head>
<body>
    <div class="container">
        <div class="back-link">
            <a href="[autodochomepageurl]">← Back to AutoDoc Home</a>
        </div>
        
        <header class="ecosystem-header">
            <h1>🏗️ [ecosystemname]</h1>
            <div class="subtitle">C# Multi-Solution Ecosystem Overview</div>
            <div class="stats-row">
                <div class="stat">
                    <div class="stat-value">[solutioncount]</div>
                    <div class="stat-label">Solutions</div>
                </div>
                <div class="stat">
                    <div class="stat-value">[projectcount]</div>
                    <div class="stat-label">Projects</div>
                </div>
                <div class="stat">
                    <div class="stat-value">[classcount]</div>
                    <div class="stat-label">Classes</div>
                </div>
                <div class="stat">
                    <div class="stat-value">[namespacecount]</div>
                    <div class="stat-label">Namespaces</div>
                </div>
            </div>
        </header>
        
        <section class="section">
            <h2>🗺️ Ecosystem Architecture</h2>
            <div class="controls">
                <button onclick="zoom(1.2)">🔍+ Zoom In</button>
                <button onclick="zoom(0.8)">🔍- Zoom Out</button>
                <button onclick="zoom('reset')">📐 Reset</button>
            </div>
            <div class="diagram-container">
                <div class="mermaid" id="ecosystem-diagram">
[ecosystemdiagram]
                </div>
            </div>
        </section>
        
        <section class="section">
            <h2>📦 Solutions</h2>
            <div class="solutions-grid">
[solutionshtml]
            </div>
        </section>
    </div>
    
    <script>
        mermaid.initialize({
            startOnLoad: true,
            theme: 'dark',
            securityLevel: 'loose',
            flowchart: { curve: 'basis', padding: 20 },
            maxEdges: 3000
        });
        
        let currentZoom = 1;
        function zoom(factor) {
            const diagram = document.getElementById('ecosystem-diagram');
            if (factor === 'reset') { currentZoom = 1; }
            else { currentZoom *= factor; }
            diagram.style.transform = `scale(${currentZoom})`;
            diagram.style.transformOrigin = 'center top';
        }
    </script>
</body>
</html>
'@
}

function Generate-SolutionsHtml {
    param([hashtable]$Solutions)
    
    $html = ""
    
    foreach ($slnName in $Solutions.Keys | Sort-Object) {
        $solution = $Solutions[$slnName]
        $totalClasses = ($solution.Projects | Measure-Object -Property ClassCount -Sum).Sum
        
        $html += @"
                <div class="solution-card">
                    <div class="solution-header">
                        <span class="solution-icon">📦</span>
                        <span class="solution-name"><a href="$slnName.csharp.html">$slnName</a></span>
                    </div>
                    <div class="solution-stats">
                        <span>$($solution.Projects.Count) projects</span>
                        <span>$totalClasses classes</span>
                    </div>
                    <ul class="project-list">

"@
        
        foreach ($proj in $solution.Projects | Sort-Object Name) {
            $typeClass = ""
            $typeLabel = "App"
            if ($proj.IsWebApp) { $typeClass = "web"; $typeLabel = "Web" }
            elseif ($proj.IsLibrary) { $typeClass = "lib"; $typeLabel = "Library" }
            elseif ($proj.IsTest) { $typeClass = "test"; $typeLabel = "Test" }
            
            $html += @"
                        <li class="project-item">
                            <span>$($proj.Name)</span>
                            <span class="project-type $typeClass">$typeLabel</span>
                        </li>

"@
        }
        
        $html += @"
                    </ul>
                </div>

"@
    }
    
    return $html
}

#endregion

#region Main Execution

if (-not (Test-Path $ecosystemFolder)) {
    Write-LogMessage "Ecosystem folder not found: $ecosystemFolder" -Level ERROR
    exit 1
}

# Set default ecosystem name from folder
if (-not $ecosystemName) {
    $ecosystemName = Split-Path $ecosystemFolder -Leaf
}

# Set default output folder
if (-not $outputFolder) {
    $outputFolder = "$(Get-DevToolsWebPath)\AutoDoc"
}

if (-not (Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
}

Write-LogMessage "Starting C# Ecosystem parser for: $ecosystemFolder" -Level INFO

$StartTime = Get-Date

# Find all solution files
$solutionFiles = Get-ChildItem -Path $ecosystemFolder -Filter "*.sln" -Recurse | Where-Object {
    $_.DirectoryName -notmatch '\\(bin|obj|packages|\.git)[\\/]'
}

Write-LogMessage "Found $($solutionFiles.Count) solution files" -Level INFO

# Parse each solution
foreach ($slnFile in $solutionFiles) {
    Write-LogMessage "Parsing: $($slnFile.Name)" -Level INFO
    
    $solutionInfo = Get-SolutionInfo -slnPath $slnFile.FullName
    $script:solutions[$solutionInfo.Name] = $solutionInfo
    
    # Generate individual solution documentation if requested
    if ($generateIndividual) {
        Start-CSharpParse -SourceFolder $solutionInfo.Directory -OutputFolder $outputFolder
    }
}

# Analyze cross-solution dependencies
Write-LogMessage "Analyzing cross-solution dependencies..." -Level INFO
$crossDeps = Find-CrossSolutionDependencies -Solutions $script:solutions
$script:crossSolutionDeps = $crossDeps

# Calculate totals
$totalProjects = 0
$totalClasses = 0
$allNamespaces = @{}

foreach ($sln in $script:solutions.Values) {
    $totalProjects += $sln.Projects.Count
    foreach ($proj in $sln.Projects) {
        $totalClasses += $proj.ClassCount
        foreach ($ns in $proj.Namespaces) {
            $allNamespaces[$ns] = $true
        }
    }
}

Write-LogMessage "Total: $($script:solutions.Count) solutions, $totalProjects projects, $totalClasses classes" -Level INFO

# Generate ecosystem diagram
Write-LogMessage "Generating ecosystem diagram..." -Level INFO
Generate-EcosystemDiagram -Solutions $script:solutions -CrossDeps $crossDeps

# Generate HTML
$template = Get-EcosystemHtmlTemplate

# Apply shared CSS and common URL replacements
$html = Set-AutodocTemplate -Template $template

$ecosystemDiagram = $script:mmdContent -join "`n"
$solutionsHtml = Generate-SolutionsHtml -Solutions $script:solutions

# Page-specific replacements
$html = $html.Replace("[ecosystemname]", $ecosystemName)
$html = $html.Replace("[solutioncount]", $script:solutions.Count.ToString())
$html = $html.Replace("[projectcount]", $totalProjects.ToString())
$html = $html.Replace("[classcount]", $totalClasses.ToString())
$html = $html.Replace("[namespacecount]", $allNamespaces.Count.ToString())
$html = $html.Replace("[ecosystemdiagram]", $ecosystemDiagram)
$html = $html.Replace("[solutionshtml]", $solutionsHtml)

# Save HTML
$outputFileName = "$ecosystemName.ecosystem.html"
$outputPath = Join-Path $outputFolder $outputFileName
$html | Set-Content -Path $outputPath -Encoding UTF8

$EndTime = Get-Date
$Duration = [math]::Round(($EndTime - $StartTime).TotalSeconds)

Write-LogMessage "Generated ecosystem overview: $outputPath" -Level INFO
Write-LogMessage "Time elapsed: $Duration seconds" -Level INFO

# Output the file path
Write-Output $outputPath

#endregion
