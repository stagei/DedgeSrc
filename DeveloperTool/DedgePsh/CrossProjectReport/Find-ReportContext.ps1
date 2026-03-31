<#
.SYNOPSIS
    Discover project ownership, related code, and context for a cross-project issue report.

.DESCRIPTION
    Given a file path, URL, or search terms, this script:
    1. Finds the owning git repo under C:\opt\src
    2. Identifies the technology stack (.NET, PowerShell, Node.js, Python)
    3. Locates related source files (entry points, config, middleware pipeline)
    4. Extracts function/class signatures around the problem area
    5. Checks for existing _inbox reports on the same topic
    6. Returns structured context for the AI agent to build a high-quality report

.PARAMETER FilePath
    A file path that belongs to the target project (e.g. Program.cs, a log file, a URL path).

.PARAMETER SearchTerms
    Keywords to search for in the target project (e.g. "MCP", "DedgeAuth", "middleware").

.PARAMETER Url
    A URL that maps to an IIS virtual app — the script resolves it to the owning project.

.PARAMETER SourceProject
    Name of the project where the issue was discovered (for the report header).

.PARAMETER MaxResults
    Max search results per term. Default: 10.

.EXAMPLE
    pwsh.exe -NoProfile -File Find-ReportContext.ps1 -FilePath "C:\opt\src\AutoDocJson\AutoDocJson.Web\Program.cs"

.EXAMPLE
    pwsh.exe -NoProfile -File Find-ReportContext.ps1 -Url "http://dedge-server/AutoDocJson/mcp" -SearchTerms "MapMcp","UseDedgeAuth"

.EXAMPLE
    pwsh.exe -NoProfile -File Find-ReportContext.ps1 -SearchTerms "MCP","authentication" -FilePath "C:\opt\src\AutoDocJson"
#>
[CmdletBinding()]
param(
    [string]$FilePath,
    [string[]]$SearchTerms,
    [string]$Url,
    [string]$SourceProject = (Split-Path (git -C $PSScriptRoot rev-parse --show-toplevel 2>$null) -Leaf),
    [int]$MaxResults = 10
)

$ErrorActionPreference = 'Stop'

# ════════════════════════════════════════════════════════════════════════════════
# Resolve target project
# ════════════════════════════════════════════════════════════════════════════════

function Find-OwningRepo {
    param([string]$Path)
    $resolved = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { $Path }
    $srcRoot = 'C:\opt\src'
    if ($resolved -like "$($srcRoot)\*") {
        $relative = $resolved.Substring($srcRoot.Length + 1)
        $projectName = $relative.Split('\')[0]
        $projectPath = Join-Path $srcRoot $projectName
        if (Test-Path (Join-Path $projectPath '.git')) {
            return @{ Name = $projectName; Path = $projectPath }
        }
    }
    return $null
}

function Resolve-UrlToProject {
    param([string]$Url)

    # Match pattern: http://server/VirtualApp/...
    # Regex: protocol + host + optional port, then /AppName
    #   ^https?://     — protocol
    #   [^/]+          — hostname (any non-slash)
    #   /([^/?]+)      — capture first path segment (virtual app name)
    if ($Url -match '^https?://[^/]+/([^/?]+)') {
        $appName = $matches[1]
        $templateDir = 'C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\templates'
        if (Test-Path $templateDir) {
            $templates = @(Get-ChildItem $templateDir -Filter '*.deploy.json' -File)
            foreach ($t in $templates) {
                $cfg = Get-Content $t.FullName -Raw | ConvertFrom-Json
                if ($cfg.SiteName -eq $appName) {
                    $srcProjects = @(Get-ChildItem 'C:\opt\src' -Directory | Where-Object {
                        $_.Name -eq $appName -or $_.Name -like "$($appName)*"
                    })
                    if ($srcProjects.Count -gt 0) {
                        $best = $srcProjects | Where-Object { Test-Path (Join-Path $_.FullName '.git') } | Select-Object -First 1
                        if ($best) { return @{ Name = $best.Name; Path = $best.FullName; SiteName = $appName } }
                    }
                }
            }
        }
        $directMatch = Join-Path 'C:\opt\src' $appName
        if (Test-Path (Join-Path $directMatch '.git')) {
            return @{ Name = $appName; Path = $directMatch; SiteName = $appName }
        }
    }
    return $null
}

$targetProject = $null

if ($FilePath) {
    $targetProject = Find-OwningRepo -Path $FilePath
}
if (-not $targetProject -and $Url) {
    $targetProject = Resolve-UrlToProject -Url $Url
}
if (-not $targetProject) {
    Write-Host "ERROR: Could not determine target project from provided inputs." -ForegroundColor Red
    Write-Host "Provide -FilePath (path inside a C:\opt\src project) or -Url (IIS virtual app URL)."
    exit 1
}

# ════════════════════════════════════════════════════════════════════════════════
# Detect technology stack
# ════════════════════════════════════════════════════════════════════════════════

function Get-TechStack {
    param([string]$ProjectPath)
    $stack = [System.Collections.ArrayList]::new()
    $indicators = @{
        'DotNet'     = @('*.csproj', '*.sln', '*.cs')
        'PowerShell' = @('*.ps1', '*.psm1')
        'NodeJs'     = @('package.json')
        'Python'     = @('requirements.txt', 'setup.py', 'pyproject.toml', '*.py')
        'Cobol'      = @('*.cbl', '*.cob', '*.cpy')
    }
    foreach ($tech in $indicators.Keys) {
        foreach ($pattern in $indicators[$tech]) {
            $found = @(Get-ChildItem $ProjectPath -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\(bin|obj|node_modules|\.venv|dist)\\' } |
                Select-Object -First 1)
            if ($found.Count -gt 0) {
                $null = $stack.Add($tech)
                break
            }
        }
    }
    return $stack
}

$techStack = Get-TechStack -ProjectPath $targetProject.Path

# ════════════════════════════════════════════════════════════════════════════════
# Find entry points and key files
# ════════════════════════════════════════════════════════════════════════════════

function Find-EntryPoints {
    param([string]$ProjectPath, [System.Collections.ArrayList]$Stack)
    $entries = [System.Collections.ArrayList]::new()

    if ($Stack -contains 'DotNet') {
        $programFiles = @(Get-ChildItem $ProjectPath -Filter 'Program.cs' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(bin|obj|test)\\' })
        foreach ($f in $programFiles) { $null = $entries.Add(@{ Type = 'DotNet Entry'; Path = $f.FullName }) }

        $startupFiles = @(Get-ChildItem $ProjectPath -Filter 'Startup.cs' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(bin|obj|test)\\' })
        foreach ($f in $startupFiles) { $null = $entries.Add(@{ Type = 'DotNet Startup'; Path = $f.FullName }) }

        $csprojFiles = @(Get-ChildItem $ProjectPath -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
        foreach ($f in $csprojFiles) { $null = $entries.Add(@{ Type = 'Project File'; Path = $f.FullName }) }

        $appSettings = @(Get-ChildItem $ProjectPath -Filter 'appsettings*.json' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
        foreach ($f in $appSettings) { $null = $entries.Add(@{ Type = 'Config'; Path = $f.FullName }) }
    }

    if ($Stack -contains 'PowerShell') {
        $mainScripts = @(Get-ChildItem $ProjectPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_*' })
        foreach ($f in $mainScripts) { $null = $entries.Add(@{ Type = 'PS Script'; Path = $f.FullName }) }

        $modules = @(Get-ChildItem $ProjectPath -Filter '*.psm1' -Recurse -File -ErrorAction SilentlyContinue)
        foreach ($f in $modules) { $null = $entries.Add(@{ Type = 'PS Module'; Path = $f.FullName }) }
    }

    if ($Stack -contains 'NodeJs') {
        $pkgJson = @(Get-ChildItem $ProjectPath -Filter 'package.json' -File -ErrorAction SilentlyContinue)
        foreach ($f in $pkgJson) { $null = $entries.Add(@{ Type = 'Node Package'; Path = $f.FullName }) }

        $indexFiles = @(Get-ChildItem $ProjectPath -Filter 'index.*' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\node_modules\\' } | Select-Object -First 3)
        foreach ($f in $indexFiles) { $null = $entries.Add(@{ Type = 'Node Entry'; Path = $f.FullName }) }
    }

    if ($Stack -contains 'Python') {
        $mainPy = @(Get-ChildItem $ProjectPath -Filter 'main.py' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(\.venv|__pycache__)\\' } | Select-Object -First 1)
        foreach ($f in $mainPy) { $null = $entries.Add(@{ Type = 'Python Entry'; Path = $f.FullName }) }

        $appPy = @(Get-ChildItem $ProjectPath -Filter 'app.py' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(\.venv|__pycache__)\\' } | Select-Object -First 1)
        foreach ($f in $appPy) { $null = $entries.Add(@{ Type = 'Python Entry'; Path = $f.FullName }) }
    }

    return $entries
}

$entryPoints = Find-EntryPoints -ProjectPath $targetProject.Path -Stack $techStack

# ════════════════════════════════════════════════════════════════════════════════
# Search for related code using search terms
# ════════════════════════════════════════════════════════════════════════════════

function Search-ProjectCode {
    param([string]$ProjectPath, [string[]]$Terms, [int]$Max)
    $allHits = [System.Collections.ArrayList]::new()

    # Regex: exclude build/vendor/output directories from search
    #   \\(bin|obj|node_modules|\.venv|dist|__pycache__)\\
    $excludePattern = '\\(bin|obj|node_modules|\.venv|dist|__pycache__|\.git)\\'

    $sourceFiles = @(Get-ChildItem $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch $excludePattern -and
            $_.Extension -in @('.cs', '.ps1', '.psm1', '.py', '.js', '.mjs', '.ts', '.json', '.xml', '.csproj', '.md', '.yaml', '.yml', '.config', '.cbl', '.cob')
        })

    foreach ($term in $Terms) {
        $count = 0
        foreach ($file in $sourceFiles) {
            if ($count -ge $Max) { break }
            try {
                $hits = Select-String -Path $file.FullName -Pattern $term -SimpleMatch -ErrorAction SilentlyContinue
                foreach ($hit in $hits) {
                    if ($count -ge $Max) { break }
                    $null = $allHits.Add(@{
                        Term    = $term
                        File    = $hit.Path
                        Line    = $hit.LineNumber
                        Content = $hit.Line.Trim()
                    })
                    $count++
                }
            }
            catch {}
        }
    }
    return $allHits
}

$searchHits = @()
if ($SearchTerms -and $SearchTerms.Count -gt 0) {
    $normalizedTerms = @($SearchTerms | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $searchHits = Search-ProjectCode -ProjectPath $targetProject.Path -Terms $normalizedTerms -Max $MaxResults
}

# ════════════════════════════════════════════════════════════════════════════════
# Extract .NET middleware pipeline (if applicable)
# ════════════════════════════════════════════════════════════════════════════════

function Get-MiddlewarePipeline {
    param([string]$ProjectPath)
    $programFiles = @(Get-ChildItem $ProjectPath -Filter 'Program.cs' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(bin|obj|test)\\' })

    $pipeline = [System.Collections.ArrayList]::new()
    foreach ($pf in $programFiles) {
        $lines = Get-Content $pf.FullName -Encoding utf8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            # Regex: match middleware and endpoint mapping calls
            #   app\.             — object prefix
            #   (Use|Map|Add)     — common middleware/endpoint prefixes
            #   \w+               — method name continuation
            #   \(                — opening paren
            if ($line -match 'app\.(Use|Map|Add)\w+\(') {
                $null = $pipeline.Add(@{
                    File  = $pf.FullName
                    Line  = $i + 1
                    Order = $pipeline.Count + 1
                    Call  = $line
                })
            }
            # Regex: match builder.Services registrations
            #   builder\.Services\. — services registration prefix
            #   (Add|With)\w+       — registration method
            if ($line -match 'builder\.Services\.(Add|With)\w+') {
                $null = $pipeline.Add(@{
                    File  = $pf.FullName
                    Line  = $i + 1
                    Order = $pipeline.Count + 1
                    Call  = $line
                })
            }
        }
    }
    return $pipeline
}

$middlewarePipeline = @()
if ($techStack -contains 'DotNet') {
    $middlewarePipeline = Get-MiddlewarePipeline -ProjectPath $targetProject.Path
}

# ════════════════════════════════════════════════════════════════════════════════
# Check for existing _inbox reports
# ════════════════════════════════════════════════════════════════════════════════

$existingReports = @()
$inboxPath = Join-Path $targetProject.Path '_inbox'
if (Test-Path $inboxPath) {
    $existingReports = @(Get-ChildItem $inboxPath -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Select-Object Name, FullName, LastWriteTime)
}

# ════════════════════════════════════════════════════════════════════════════════
# Git recent activity
# ════════════════════════════════════════════════════════════════════════════════

$recentCommits = @()
try {
    $gitLog = git -C $targetProject.Path log --oneline -10 --format='%h|%s|%an|%ar' 2>$null
    if ($gitLog) {
        foreach ($entry in $gitLog) {
            $parts = $entry -split '\|', 4
            if ($parts.Count -ge 4) {
                $recentCommits += @{
                    Hash    = $parts[0]
                    Subject = $parts[1]
                    Author  = $parts[2]
                    When    = $parts[3]
                }
            }
        }
    }
}
catch {}

# ════════════════════════════════════════════════════════════════════════════════
# IIS deploy template (if applicable)
# ════════════════════════════════════════════════════════════════════════════════

$deployTemplate = $null
$templateDir = 'C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\templates'
if (Test-Path $templateDir) {
    $matching = @(Get-ChildItem $templateDir -Filter '*.deploy.json' -File |
        Where-Object { $_.Name -like "$($targetProject.Name)*" })
    if ($matching.Count -gt 0) {
        $deployTemplate = Get-Content $matching[0].FullName -Raw | ConvertFrom-Json
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# Build output
# ════════════════════════════════════════════════════════════════════════════════

$context = [ordered]@{
    TargetProject = [ordered]@{
        Name = $targetProject.Name
        Path = $targetProject.Path
        TechStack = @($techStack)
    }
    SourceProject = $SourceProject
    EntryPoints   = @($entryPoints | ForEach-Object {
        [ordered]@{ Type = $_.Type; Path = $_.Path; Relative = $_.Path.Replace($targetProject.Path + '\', '') }
    })
    SearchResults = @($searchHits | ForEach-Object {
        [ordered]@{
            Term     = $_.Term
            File     = $_.File.Replace($targetProject.Path + '\', '')
            Line     = $_.Line
            Content  = if ($_.Content.Length -gt 120) { $_.Content.Substring(0, 120) + '...' } else { $_.Content }
        }
    })
    MiddlewarePipeline = @($middlewarePipeline | ForEach-Object {
        [ordered]@{
            Order = $_.Order
            Line  = $_.Line
            File  = $_.File.Replace($targetProject.Path + '\', '')
            Call  = $_.Call
        }
    })
    ExistingInboxReports = @($existingReports | ForEach-Object {
        [ordered]@{ Name = $_.Name; Modified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    })
    RecentCommits = @($recentCommits)
    DeployTemplate = if ($deployTemplate) {
        [ordered]@{
            SiteName       = $deployTemplate.SiteName
            AppType        = $deployTemplate.AppType
            ApiPort        = $deployTemplate.ApiPort
            HealthEndpoint = $deployTemplate.HealthEndpoint
            PhysicalPath   = $deployTemplate.PhysicalPath
        }
    } else { $null }
}

$json = $context | ConvertTo-Json -Depth 10
Write-Output $json
