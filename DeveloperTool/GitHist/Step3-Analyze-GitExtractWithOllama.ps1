<#
.SYNOPSIS
    Analyzes GitExtract folder projects using local Ollama models to generate
    business-oriented presentation summaries.

.DESCRIPTION
    Reads each project's GitHistory.md from the latest Projects_* folder,
    gathers README/markdown and executable context from the original source path,
    sends a structured prompt to Ollama, and writes PresentationSummary.md per project.
    Supports incremental re-analysis when GitHistory.md is newer than PresentationSummary.md.
    Finally aggregates all summaries into a tag-indexed PresentationDeck.md.

.PARAMETER GitHistRoot
    Root folder containing Projects_* subfolders. Defaults to script directory.

.PARAMETER ExtractFolder
    Specific Projects_* folder to process. Auto-detects latest if empty.

.PARAMETER Model
    Ollama model name. Auto-selects qwen3:8b or first available if empty.

.PARAMETER ApiUrl
    Ollama API URL. Defaults to http://localhost:11434.

.PARAMETER Temperature
    Model temperature (0.0-1.0). Lower = more deterministic. Default: 0.2.

.PARAMETER MaxTokens
    Maximum tokens for Ollama response. Default: 2048.

.PARAMETER Force
    Overwrite existing PresentationSummary.md files.
#>

param(
    [string]$GitHistRoot = $PSScriptRoot,
    [string]$ExtractFolder = '',
    [string]$Model = 'qwen3:8b',
    [string]$ApiUrl = 'http://localhost:11434',
    [double]$Temperature = 0.2,
    [int]$MaxTokens = 6144,
    [switch]$Force
)

Import-Module GlobalFunctions -Force
Import-Module OllamaHandler -Force

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# ── Helper: Read file content safely handling both UTF-8 and Windows-1252 ────
function Read-FileAutoEncoding {
    param(
        [string]$Path
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    $utf8 = [System.Text.Encoding]::UTF8
    $decoded = $utf8.GetString($bytes)
    if ($decoded.Contains([char]0xFFFD)) {
        return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
    }
    return $decoded
}

# ── Helper: Read file with size cap ──────────────────────────────────────────
function Read-CappedFile {
    param(
        [string]$Path,
        [int]$MaxBytes = 10240
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $content = Read-FileAutoEncoding -Path $Path
    }
    catch {
        return $null
    }
    if ($null -eq $content) { return $null }
    if ($content.Length -gt $MaxBytes) {
        return $content.Substring(0, $MaxBytes) + "`n... (truncated at $($MaxBytes) chars)"
    }
    return $content
}

# ── Helper: Extract header from any source file ──────────────────────────────
function Get-FileHeader {
    param(
        [string]$Path,
        [int]$MaxLines = 120
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $content = Read-FileAutoEncoding -Path $Path
    }
    catch {
        return $null
    }
    if ($null -eq $content) { return $null }
    $lines = $content -split "`n" | Select-Object -First $MaxLines
    return ($lines -join "`n")
}

# ── Helper: Build a compact file tree listing ─────────────────────────────────
function Get-ProjectFileTree {
    param(
        [string]$RootPath,
        [int]$MaxEntries = 120
    )
    $excludeDirs = @('.git', '.vs', 'bin', 'obj', 'node_modules', '.cursor', '__pycache__', 'packages', '.nuget')
    $entries = [System.Collections.Generic.List[string]]::new()

    $allItems = Get-ChildItem -LiteralPath $RootPath -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Substring($RootPath.Length).TrimStart('\', '/')
            $skip = $false
            foreach ($ex in $excludeDirs) {
                if ($rel -match "(^|[\\/])$([regex]::Escape($ex))([\\/]|$)") { $skip = $true; break }
            }
            -not $skip
        } |
        Select-Object -First ($MaxEntries * 2)

    foreach ($item in $allItems) {
        if ($entries.Count -ge $MaxEntries) { break }
        $rel = $item.FullName.Substring($RootPath.Length).TrimStart('\', '/').Replace('\', '/')
        if ($item.PSIsContainer) {
            $entries.Add("$($rel)/")
        } else {
            $entries.Add($rel)
        }
    }
    return ($entries -join "`n")
}

# ── Helper: Fetch RAG context for a project ──────────────────────────────────
function Get-RagContext {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string[]]$RagNames = @('Dedge-code', 'db2-docs'),
        [int]$Chunks = 4,
        [string]$RegistryHost = 'dedge-server',
        [int]$RegistryPort = 8484
    )
    $contextParts = [System.Collections.Generic.List[string]]::new()
    try {
        $registry = Invoke-RestMethod -Uri "http://$($RegistryHost):$($RegistryPort)/rags" -TimeoutSec 5 -ErrorAction Stop
        $ragHost = if ($registry.host) { $registry.host } else { $RegistryHost }
        foreach ($ragName in $RagNames) {
            $rag = $registry.rags | Where-Object { $_.name -eq $ragName }
            if (-not $rag) { continue }
            $ragUrl = "http://$($ragHost):$($rag.port)/query"
            $body = @{ query = $Query; n_results = $Chunks } | ConvertTo-Json
            try {
                $resp = Invoke-RestMethod -Uri $ragUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace($resp.result)) {
                    $contextParts.Add("### RAG: $($ragName)`n$($resp.result)")
                }
            } catch {
                Write-LogMessage "[$($scriptName)] RAG query to $($ragName) failed: $($_.Exception.Message)" -Level WARN
            }
        }
    } catch {
        Write-LogMessage "[$($scriptName)] RAG registry unreachable: $($_.Exception.Message)" -Level WARN
    }
    if ($contextParts.Count -eq 0) { return '' }
    return ($contextParts -join "`n`n")
}

$scriptExtensions = @('.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.py', '.js', '.ts', '.sh')
$csharpKeyPatterns = @('Program.cs', 'Startup.cs', '*Controller.cs', '*Service.cs', '*Handler.cs', '*Worker.cs')
$projectFileExts   = @('.csproj', '.sln', '.fsproj', '.vbproj')
$configFiles       = @('package.json', 'requirements.txt', 'pyproject.toml', 'Cargo.toml', 'go.mod')

# ── Step 1: Find extract folder ──────────────────────────────────────────────
Write-LogMessage "[$($scriptName)] Starting Ollama analysis" -Level INFO

if ([string]::IsNullOrWhiteSpace($ExtractFolder)) {
    $extractDirs = Get-ChildItem -Path $GitHistRoot -Directory -Filter 'Projects_*' |
        Sort-Object Name -Descending
    if ($extractDirs.Count -eq 0) {
        Write-LogMessage "[$($scriptName)] No Projects_* folders found in $($GitHistRoot)" -Level ERROR
        exit 1
    }
    $ExtractFolder = $extractDirs[0].FullName
}

if (-not (Test-Path -LiteralPath $ExtractFolder -PathType Container)) {
    Write-LogMessage "[$($scriptName)] Extract folder not found: $($ExtractFolder)" -Level ERROR
    exit 1
}

Write-LogMessage "[$($scriptName)] Extract folder: $($ExtractFolder)" -Level INFO

# ── Step 2: Validate Ollama service and model ────────────────────────────────
if (-not (Test-OllamaService -ApiUrl $ApiUrl)) {
    Write-LogMessage "[$($scriptName)] Ollama not running, attempting start..." -Level WARN
    if (-not (Start-OllamaService -ApiUrl $ApiUrl)) {
        Write-LogMessage "[$($scriptName)] Cannot connect to Ollama at $($ApiUrl)" -Level ERROR
        exit 1
    }
}

$availableModels = Get-OllamaModels -ApiUrl $ApiUrl
if ($availableModels.Count -eq 0) {
    Write-LogMessage "[$($scriptName)] No Ollama models available" -Level ERROR
    exit 1
}

if ($Model -notin $availableModels) {
    $fallback = if ('llama3.1:8b' -in $availableModels) { 'llama3.1:8b' } else { $availableModels[0] }
    Write-LogMessage "[$($scriptName)] Model '$($Model)' not available, using '$($fallback)'" -Level WARN
    $Model = $fallback
}

Write-LogMessage "[$($scriptName)] Model: $($Model)" -Level INFO
Write-LogMessage "[$($scriptName)] Temperature: $($Temperature), MaxTokens: $($MaxTokens)" -Level INFO

# ── Step 3: Find all GitHistory.md files ─────────────────────────────────────
$historyFiles = Get-ChildItem -Path $ExtractFolder -Recurse -Filter 'GitHistory.md' -File |
    Sort-Object FullName

$total = $historyFiles.Count
Write-LogMessage "[$($scriptName)] Found $($total) GitHistory.md files to analyze" -Level INFO

if ($total -eq 0) {
    Write-LogMessage "[$($scriptName)] Nothing to analyze" -Level WARN
    exit 0
}

# ── System prompt ────────────────────────────────────────────────────────────
$systemPrompt = @"
You are a technical writer preparing annual review presentation content for management.
You describe projects in SPECIFIC business terms — what value they deliver, what problems they solve,
who benefits, how data flows through the system, what integrations are involved.
Be PRECISE and DETAILED — never write vague or generic descriptions. Reference actual file formats,
table names, endpoints, and processing steps visible in the code.
For Input/Output: ONLY include paths and resources you can actually see in the provided source code.
DO NOT invent, guess, or fabricate file paths, table names, or resources.
Always respond in the exact markdown structure requested. No preamble, no trailing remarks,
no explanations outside the requested sections.
"@

$requiredSections = @('Business Purpose', 'Tags', 'Key Source Files', 'Technical Details', 'Period Summary')

function Repair-OllamaResponse {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $text = [regex]::Replace($Raw, '<think>[\s\S]*?</think>', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $text = $text -replace '</think>', ''
    $text = $text -replace '<think>', ''
    if ($text -match '(?s)(## Business Purpose.*)') {
        $text = $Matches[1]
    } elseif ($text -match '(?s)(## [A-Z].*)') {
        $text = $Matches[1]
    }
    $cleanLines = $text -split "`n"
    $kept = [System.Collections.Generic.List[string]]::new()
    $foundPeriod = $false
    foreach ($cl in $cleanLines) {
        if ($cl -match '^## Period Summary') {
            if ($foundPeriod) { break }
            $foundPeriod = $true
            $kept.Add($cl)
            continue
        }
        if ($foundPeriod -and $cl -match '^## ') { break }
        $kept.Add($cl)
    }
    return (($kept -join "`n").Trim() -replace '(?m)^\s*$\n', "`n")
}

function Get-MissingSections {
    param([string]$Text)
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($sec in $requiredSections) {
        $found = $Text -match "## $([regex]::Escape($sec))"
        if (-not $found -and $sec -eq 'Key Source Files') {
            $found = $Text -match '## Executables'
        }
        if (-not $found) { $missing.Add($sec) }
    }
    return $missing
}

# ── Step 4: Process each project ─────────────────────────────────────────────
$allSummaries = [System.Collections.Generic.List[PSCustomObject]]::new()
$i = 0

foreach ($histFile in $historyFiles) {
    $i++
    $projectFolder = $histFile.DirectoryName
    $summaryPath = Join-Path $projectFolder 'PresentationSummary.md'

    if ((Test-Path -LiteralPath $summaryPath) -and -not $Force) {
        $histLastWrite = $histFile.LastWriteTime
        $summaryLastWrite = (Get-Item -LiteralPath $summaryPath).LastWriteTime
        if ($histLastWrite -le $summaryLastWrite) {
            Write-LogMessage "[$($scriptName)] Skip (up to date): $($summaryPath)" -Level DEBUG
            $existingContent = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction SilentlyContinue
            if ($existingContent) {
                $allSummaries.Add([PSCustomObject]@{
                    ProjectFolder = $projectFolder
                    Content = $existingContent
                })
            }
            continue
        }
        Write-LogMessage "[$($scriptName)] Re-analyzing (GitHistory.md updated): $(Split-Path $projectFolder -Leaf)" -Level INFO
    }

    $gitHistContent = Get-Content -LiteralPath $histFile.FullName -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($gitHistContent)) {
        Write-LogMessage "[$($scriptName)] Skip empty GitHistory.md: $($histFile.FullName)" -Level WARN
        continue
    }

    # Parse source path from GitHistory.md
    $sourcePath = $null
    if ($gitHistContent -match 'Source path:\s*`([^`]+)`') {
        $sourcePath = $Matches[1]
    }

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        Write-LogMessage "[$($scriptName)] Skip (no source path found): $($histFile.FullName)" -Level WARN
        continue
    }

    $projectName = Split-Path $sourcePath -Leaf
    Write-LogMessage "[$($scriptName)] Analyzing: $($projectName) ($($i)/$($total))" -Level INFO

    # ── Gather context from source ──
    $mdContext = ''
    $fileTreeContext = ''
    $sourceCodeContext = ''
    $projectFileContext = ''
    $sourceExists = Test-Path -LiteralPath $sourcePath -PathType Container

    if ($sourceExists) {
        # ── File tree overview ──
        $fileTreeContext = Get-ProjectFileTree -RootPath $sourcePath -MaxEntries 120
        if ([string]::IsNullOrWhiteSpace($fileTreeContext)) {
            $fileTreeContext = '(empty project)'
        }

        # ── Markdown / documentation files (recursive, prioritize README) ──
        $readmePath = Join-Path $sourcePath 'README.md'
        if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
            $readmePath = Join-Path $sourcePath 'readme.md'
        }

        $mdFiles = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
            $mdFiles.Add($readmePath)
        }

        $otherMd = Get-ChildItem -LiteralPath $sourcePath -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ne 'README.md' -and $_.Name -ne 'readme.md' -and
                $_.FullName -notmatch '[\\/](bin|obj|node_modules|\.git|\.vs)[\\/]'
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 3

        foreach ($mf in $otherMd) { $mdFiles.Add($mf.FullName) }

        foreach ($mdFile in $mdFiles) {
            $mdName = $mdFile.Substring($sourcePath.Length).TrimStart('\', '/').Replace('\', '/')
            $mdContent = Read-CappedFile -Path $mdFile -MaxBytes 10240
            if ($mdContent) {
                $mdContext += "### $($mdName)`n$($mdContent)`n`n"
            }
        }

        # ── Project / solution files (.sln, .csproj, package.json etc.) ──
        $projFiles = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Extension -in $projectFileExts -or $_.Name -in $configFiles) -and
                $_.FullName -notmatch '[\\/](bin|obj|node_modules|\.git|\.vs)[\\/]'
            } |
            Select-Object -First 20

        foreach ($pf in $projFiles) {
            $pfRel = $pf.FullName.Substring($sourcePath.Length).TrimStart('\', '/').Replace('\', '/')
            $pfContent = Read-CappedFile -Path $pf.FullName -MaxBytes 8192
            if ($pfContent) {
                $projectFileContext += "### $($pfRel)`n$($pfContent)`n`n"
            }
        }

        # ── Script and source files (recursive) ──
        $allSourceFiles = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in $scriptExtensions -and
                $_.FullName -notmatch '[\\/](bin|obj|node_modules|\.git|\.vs|__pycache__|packages)[\\/]'
            } |
            Sort-Object Length |
            Select-Object -First 20

        foreach ($sf in $allSourceFiles) {
            $sfRel = $sf.FullName.Substring($sourcePath.Length).TrimStart('\', '/').Replace('\', '/')
            $header = Get-FileHeader -Path $sf.FullName -MaxLines 80
            if ($header) {
                $sourceCodeContext += "### $($sfRel)`n$($header)`n`n"
            }
        }

        # ── Key C# source files (recursive, selective) ──
        foreach ($pattern in $csharpKeyPatterns) {
            $csFiles = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '[\\/](bin|obj|\.git|\.vs|Migrations)[\\/]' } |
                Select-Object -First 3
            foreach ($cf in $csFiles) {
                $cfRel = $cf.FullName.Substring($sourcePath.Length).TrimStart('\', '/').Replace('\', '/')
                $header = Get-FileHeader -Path $cf.FullName -MaxLines 60
                if ($header) {
                    $sourceCodeContext += "### $($cfRel)`n$($header)`n`n"
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($mdContext)) { $mdContext = '(no documentation files found)' }
    if ([string]::IsNullOrWhiteSpace($sourceCodeContext)) { $sourceCodeContext = '(no source files found)' }
    if ([string]::IsNullOrWhiteSpace($projectFileContext)) { $projectFileContext = '(no project files found)' }

    # ── Fetch RAG context for richer descriptions ──
    $ragQuery = "$projectName purpose usage integration"
    $ragContext = Get-RagContext -Query $ragQuery
    $ragSection = if (-not [string]::IsNullOrWhiteSpace($ragContext)) { "`n## Related Documentation (RAG):`n$($ragContext)" } else { '' }

    # ── Build prompt ──
    $userPrompt = @"
## Project: $projectName
## Source: $sourcePath

## Git Activity Summary:
$gitHistContent

## Project File Tree:
$fileTreeContext

## Project / Solution Files (csproj, sln, package.json, etc.):
$projectFileContext

## Documentation:
$mdContext
$ragSection

## Script and Source Files (headers):
$sourceCodeContext

---
Produce ONLY the following markdown output with these exact section headers:

## Business Purpose
(4-8 sentences. First explain what BUSINESS problem this solves and WHO uses it. Then describe HOW it works: what data flows in, what processing happens, what output is produced. Include specifics: mention actual file formats, protocols, database tables, scheduling, or integration points visible in the code. Do NOT be vague or generic - be precise about what this specific project does based on the source code you see.)

## Tags
tag1, tag2, tag3, ...
(choose from themes: db2, infrastructure, automation, deployment, reporting, monitoring, authentication, backup, cobol, azure, logging, configuration, utilities, web, scheduling, dotnet, python, node - add custom tags as needed)
(if this project is part of a .sln solution with multiple sub-projects, add a tag: solution:<SolutionName>)

## Key Source Files
| File | Functionality |
|---|---|
| path/to/file.ps1 | what this file adds to the project |
(list only the KEY script and source files from the Source Files section above - max 15 entries)
(for C# projects: describe what functionality each .cs file contributes to the compiled application - controllers, services, models, etc.)
(NEVER list files from obj/, bin/, packages/, .git/, or .vs/ directories)
(NEVER fabricate or invent filenames - only use files actually shown above in the provided context)

## Technical Details

### Parameters
| Parameter | Type | Description |
|---|---|---|
| -ServerName | string | Target server hostname |
(list key parameters/arguments from the source files above, especially from param() blocks, CLI args, or config - max 12 entries)
(if no parameters found, write: No parameters detected.)

### Input / Output
| Direction | Path or Resource | Description |
|---|---|---|
| Input | C:\data\prices.csv | Daily price feed file |
| Output | STDOUT / logfile | Execution results |
(ONLY list paths, resources, URLs, or APIs that are ACTUALLY visible in the source code shown above)
(look for literal file paths, UNC paths, URLs, connection strings, folder variables in the code)
(DO NOT invent or guess paths - if you cannot find a specific path in the code, do NOT include it)
(max 10 entries; if none found, write: No specific I/O paths detected.)

### Database
- **Technology**: (e.g. DB2, SQL Server, SQLite, PostgreSQL, or "None detected")
- **Connection**: (connection string pattern or server reference if visible, otherwise "N/A")
- **Tables/Views**: (comma-separated list of table or view names referenced in SQL, ORM, or COBOL code, or "None detected")

## Period Summary
(2-4 sentences on what evolved in this project during the analysis period. Mention specific commits or changes if notable.)
"@

    # ── Call Ollama with requery for missing sections (max 2 retries) ──
    $maxAttempts = 3
    $bestResponse = ''
    $bestMissingCount = $requiredSections.Count + 1
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $currentPrompt = $userPrompt
        if ($attempt -eq 2 -and -not [string]::IsNullOrWhiteSpace($bestResponse)) {
            $missingSections = Get-MissingSections -Text $bestResponse
            $missingList = ($missingSections | ForEach-Object { "- ## $_" }) -join "`n"
            $currentPrompt = @"
Your previous response was INCOMPLETE. The following required sections were MISSING:
$missingList

Here is what you returned so far (keep what is correct, add the missing parts):
$bestResponse

---
You MUST now produce a COMPLETE response with ALL of these sections:
## Business Purpose
## Tags
## Key Source Files
## Technical Details (with subsections: ### Parameters, ### Input / Output, ### Database)
## Period Summary

Original project context for reference:
## Project: $projectName
## Source: $sourcePath

## Git Activity Summary (abbreviated):
$(($gitHistContent -split "`n" | Select-Object -First 40) -join "`n")

## Script and Source Files (headers):
$sourceCodeContext
"@
            Write-LogMessage "[$($scriptName)] Requery attempt $($attempt)/$($maxAttempts) for $($projectName) - missing: $($missingSections -join ', ')" -Level WARN
        }
        elseif ($attempt -eq 3) {
            Write-LogMessage "[$($scriptName)] Fresh retry attempt $($attempt)/$($maxAttempts) for $($projectName)" -Level WARN
        }

        $rawResponse = Invoke-OllamaGenerate -Prompt $currentPrompt -Model $Model -ApiUrl $ApiUrl -SystemPrompt $systemPrompt -Temperature $Temperature -MaxTokens $MaxTokens
        $cleaned = Repair-OllamaResponse -Raw $rawResponse
        if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
            $currentMissing = Get-MissingSections -Text $cleaned
            if ($currentMissing.Count -lt $bestMissingCount) {
                $bestResponse = $cleaned
                $bestMissingCount = $currentMissing.Count
            }
        }

        if ($bestMissingCount -eq 0) {
            if ($attempt -gt 1) {
                Write-LogMessage "[$($scriptName)] All sections present after attempt $($attempt) for $($projectName)" -Level INFO
            }
            break
        }
    }

    $response = $bestResponse
    $missingSections = Get-MissingSections -Text $response
    if ($missingSections.Count -gt 0) {
        Write-LogMessage "[$($scriptName)] Still missing sections after $($maxAttempts) attempts for $($projectName): $($missingSections -join ', ')" -Level WARN
    }

    # ── Write PresentationSummary.md ──
    $summaryLines = [System.Collections.Generic.List[string]]::new()
    $summaryLines.Add("# $($projectName)")
    $summaryLines.Add('')
    $summaryLines.Add("- Source: ``$($sourcePath)``")
    $summaryLines.Add("- Model: ``$($Model)``")
    $summaryLines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $summaryLines.Add('')

    if ([string]::IsNullOrWhiteSpace($response)) {
        Write-LogMessage "[$($scriptName)] FAILED analysis for: $($projectName)" -Level ERROR
        $summaryLines.Add('> ANALYSIS FAILED - Ollama returned no response. Re-run with -Force to retry.')
    }
    else {
        $summaryLines.Add($response)
    }

    $summaryText = $summaryLines -join "`n"
    $summaryText | Out-File -LiteralPath $summaryPath -Encoding utf8
    Write-LogMessage "[$($scriptName)] Written: $($summaryPath)" -Level INFO

    $allSummaries.Add([PSCustomObject]@{
        ProjectFolder = $projectFolder
        Content = $summaryText
    })
}

Write-LogMessage "[$($scriptName)] All projects processed. Building PresentationDeck..." -Level INFO

# ── Step 5: Build PresentationDeck.md with tag index ─────────────────────────
$deckPath = Join-Path $ExtractFolder 'PresentationDeck.md'
$deck = [System.Collections.Generic.List[string]]::new()

$deck.Add('# Presentation Deck - Git Activity Analysis')
$deck.Add('')
$deck.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$deck.Add("- Model: ``$($Model)``")
$deck.Add("- Projects analyzed: $($allSummaries.Count)")
$deck.Add("- Extract folder: ``$($ExtractFolder)``")
$deck.Add('')

# Parse tags from all summaries
$tagMap = @{}
foreach ($s in $allSummaries) {
    $folderName = Split-Path $s.ProjectFolder -Leaf
    $relPath = $s.ProjectFolder.Substring($ExtractFolder.Length).TrimStart('\', '/').Replace('\', '/')

    if ($s.Content -match '(?m)^## Tags\s*\r?\n(.+)') {
        $tagLine = $Matches[1].Trim()
        $tags = $tagLine -split '\s*,\s*' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' }
        foreach ($tag in $tags) {
            if (-not $tagMap.ContainsKey($tag)) {
                $tagMap[$tag] = [System.Collections.Generic.List[string]]::new()
            }
            $tagMap[$tag].Add("[$($folderName)](./$($relPath)/PresentationSummary.md)")
        }
    }
}

$deck.Add('---')
$deck.Add('')
$deck.Add('## Tag Index')
$deck.Add('')

$sortedTags = $tagMap.Keys | Sort-Object
foreach ($tag in $sortedTags) {
    $deck.Add("### $($tag)")
    foreach ($link in $tagMap[$tag]) {
        $deck.Add("- $($link)")
    }
    $deck.Add('')
}

$deck.Add('---')
$deck.Add('')
$deck.Add('## Project Summaries')
$deck.Add('')

$sortedSummaries = $allSummaries | Sort-Object { Split-Path $_.ProjectFolder -Leaf }
foreach ($s in $sortedSummaries) {
    $deck.Add($s.Content)
    $deck.Add('')
    $deck.Add('---')
    $deck.Add('')
}

$deck -join "`n" | Out-File -LiteralPath $deckPath -Encoding utf8

Write-LogMessage "[$($scriptName)] PresentationDeck written: $($deckPath)" -Level INFO
Write-LogMessage "[$($scriptName)] Done. $($allSummaries.Count) projects, $($sortedTags.Count) unique tags" -Level INFO
