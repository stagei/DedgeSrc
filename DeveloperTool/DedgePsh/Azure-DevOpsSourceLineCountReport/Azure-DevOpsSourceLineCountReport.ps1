#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Counts lines of code across multiple git repositories and provides statistics per repo.

.DESCRIPTION
    This script analyzes git repositories to count lines of code, providing detailed statistics
    including total lines, lines per file type, and file counts. It processes multiple repositories
    and presents a summary comparison.

.PARAMETER RepoPaths
    Array of paths to git repositories to analyze.

.PARAMETER ExcludePatterns
    Array of file patterns to exclude from counting (e.g., '*.min.js', 'node_modules/*').

.PARAMETER IncludeFileTypes
    Array of file extensions to include. If not specified, all tracked files are counted.

.EXAMPLE
    .\Start-CountRepoLines.ps1 -RepoPaths @("C:\Projects\MyApp", "C:\Projects\MyLib")

.EXAMPLE
    .\Start-CountRepoLines.ps1 -RepoPaths @(".\repo1", ".\repo2") -IncludeFileTypes @("*.js", "*.ts", "*.cs")
#>

param(
    [Parameter(Mandatory = $false)]
    [string[]]$RepoPaths = @(
        "$env:OptPath\src\PathConsolidator",
        "$env:OptPath\src\ReplicateProdDataToTest",
        "$env:OptPath\src\SqlFormatter",
        "$env:OptPath\src\SystemMaintenance",
        "$env:OptPath\src\UTF8Ansi",
        "$env:OptPath\src\VC",
        "$env:OptPath\src\VcDedgePosTest",
        "$env:OptPath\src\AutoDoc",
        "$env:OptPath\src\BRREGRefresh",
        "$env:OptPath\src\CSVSplitter",
        "$env:OptPath\src\CursorMisc",
        "$env:OptPath\src\Databases",
        "$env:OptPath\src\DB2ExportCSV",
        "$env:OptPath\src\DevDocs",
        "$env:OptPath\src\DevTools",
        "$env:OptPath\src\DevToolsWeb",
        "$env:OptPath\src\EHFRefresh",
        "$env:OptPath\src\EntraMenuManager",
        "$env:OptPath\src\FixJob",
        "$env:OptPath\src\DedgeCommon",
        "$env:OptPath\src\Dedge",
        "$env:OptPath\src\DedgeAvdPrint",
        "$env:OptPath\src\DedgeDailyRoutine",
        "$env:OptPath\src\DedgeICC",
        "$env:OptPath\src\DedgeNodeJs",
        "$env:OptPath\src\DedgePOS",
        "$env:OptPath\src\DedgePosNotification",
        "$env:OptPath\src\DedgePsh",
        "$env:OptPath\src\DedgePython",
        "$env:OptPath\src\DedgeRemoteConnect",
        "$env:OptPath\src\FkSmsRestService",
        "$env:OptPath\src\FkStack",
        "$env:OptPath\src\GetPeppolDirectory",
        "$env:OptPath\src\Kerberos",
        "$env:OptPath\src\KerberosWorkshop",
        "$env:OptPath\src\KillDbSessions",
        "$env:OptPath\src\KimenExport",
        "$env:OptPath\src\Kvitteringskontroll"    )
    ,

    [string[]]$ExcludePatterns = @("*.min.js", "*.csv", "*.txt", "*.min.js", "*.min.css", "node_modules/*", "dist/*", "build/*", "*.lock", "package-lock.json"),

    [string[]]$IncludeFileTypes = @("*.cs", "*.ps1", "*.psm1", "*.ps1xml", "*.psd1", "*.bat", "*.cmd", "*.cbl", "*.gs", "*.rex", "*.py", "*.js")
)

function Test-GitRepository {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    Push-Location $Path
    try {
        $null = git rev-parse --git-dir 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }
}

function Get-FileExtension {
    param([string]$FileName)

    $ext = [System.IO.Path]::GetExtension($FileName).ToLower()
    if ([string]::IsNullOrEmpty($ext)) {
        return "no extension"
    }
    return $ext
}

function Get-LanguageFromExtension {
    param([string]$Extension)

    $languageMap = @{
        ".js"          = "JavaScript"
        ".ts"          = "TypeScript"
        ".jsx"         = "React JSX"
        ".tsx"         = "React TSX"
        ".cs"          = "C#"
        ".py"          = "Python"
        ".java"        = "Java"
        ".cpp"         = "C++"
        ".c"           = "C"
        ".h"           = "C/C++ Header"
        ".hpp"         = "C++ Header"
        ".css"         = "CSS"
        ".scss"        = "SCSS"
        ".sass"        = "Sass"
        ".html"        = "HTML"
        ".xml"         = "XML"
        ".json"        = "JSON"
        ".yml"         = "YAML"
        ".yaml"        = "YAML"
        ".md"          = "Markdown"
        ".sh"          = "Shell Script"
        ".ps1"         = "PowerShell"
        ".sql"         = "SQL"
        ".php"         = "PHP"
        ".rb"          = "Ruby"
        ".go"          = "Go"
        ".rs"          = "Rust"
        ".kt"          = "Kotlin"
        ".swift"       = "Swift"
        "no extension" = "No Extension"
    }

    return $languageMap[$Extension] ?? "Other ($Extension)"
}

function Start-CountRepoLines {
    param(
        [string]$RepoPath,
        [string[]]$ExcludePatterns,
        [string[]]$IncludeFileTypes
    )

    Push-Location $RepoPath
    try {
        Write-Host "Analyzing repository: " -NoNewline
        Write-Host $RepoPath -ForegroundColor Cyan

        # Get all tracked files
        $trackedFiles = git ls-files | Where-Object { $_ -and $_.Trim() }

        if (-not $trackedFiles) {
            Write-Warning "No tracked files found in repository: $RepoPath"
            return $null
        }

        # Filter files based on include/exclude patterns
        $filteredFiles = $trackedFiles

        # Apply include filter if specified
        if ($IncludeFileTypes.Count -gt 0) {
            $filteredFiles = $filteredFiles | Where-Object {
                $file = $_
                $IncludeFileTypes | ForEach-Object {
                    if ($file -like $_) { return $true }
                }
                return $false
            }
        }

        # Apply exclude filter
        if ($ExcludePatterns.Count -gt 0) {
            $filteredFiles = $filteredFiles | Where-Object {
                $file = $_
                $exclude = $false
                foreach ($pattern in $ExcludePatterns) {
                    if ($file -like $pattern) {
                        $exclude = $true
                        break
                    }
                }
                return -not $exclude
            }
        }

        if (-not $filteredFiles) {
            Write-Warning "No files remain after filtering in repository: $RepoPath"
            return $null
        }

        # Count lines and analyze file types
        $stats = @{
            RepoPath   = $RepoPath
            RepoName   = Split-Path $RepoPath -Leaf
            TotalFiles = 0
            TotalLines = 0
            FileTypes  = @{}
            Languages  = @{}
        }

        $progressCounter = 0
        foreach ($file in $filteredFiles) {
            $progressCounter++
            if ($progressCounter % 50 -eq 0) {
                Write-Progress -Activity "Counting lines" -Status "Processing file $progressCounter of $($filteredFiles.Count)" -PercentComplete (($progressCounter / $filteredFiles.Count) * 100)
            }

            if (Test-Path $file) {
                try {
                    $content = Get-Content $file -ErrorAction SilentlyContinue
                    $lineCount = if ($content) { $content.Count } else { 0 }

                    $extension = Get-FileExtension $file
                    $language = Get-LanguageFromExtension $extension

                    $stats.TotalFiles++
                    $stats.TotalLines += $lineCount

                    # Track by file extension
                    if ($stats.FileTypes.ContainsKey($extension)) {
                        $stats.FileTypes[$extension].Files++
                        $stats.FileTypes[$extension].Lines += $lineCount
                    }
                    else {
                        $stats.FileTypes[$extension] = @{
                            Files = 1
                            Lines = $lineCount
                        }
                    }

                    # Track by language
                    if ($stats.Languages.ContainsKey($language)) {
                        $stats.Languages[$language].Files++
                        $stats.Languages[$language].Lines += $lineCount
                    }
                    else {
                        $stats.Languages[$language] = @{
                            Files = 1
                            Lines = $lineCount
                        }
                    }
                }
                catch {
                    Write-Warning "Could not read file: $file"
                }
            }
        }

        Write-Progress -Activity "Counting lines" -Completed
        return $stats
    }
    finally {
        Pop-Location
    }
}

function Format-Number {
    param([int]$Number)
    return $Number.ToString("N0")
}

function Show-RepoStatistics {
    param($Stats, $AllStats)

    Write-Host "`n" + "="*80 -ForegroundColor Yellow
    Write-Host "Repository: " -NoNewline
    Write-Host $Stats.RepoName -ForegroundColor Green
    Write-Host "Path: " -NoNewline
    Write-Host $Stats.RepoPath -ForegroundColor Gray
    Write-Host "="*80 -ForegroundColor Yellow

    Write-Host "`nOverall Statistics:" -ForegroundColor Cyan
    Write-Host "  Total Files: " -NoNewline
    Write-Host (Format-Number $Stats.TotalFiles) -ForegroundColor White
    Write-Host "  Total Lines: " -NoNewline
    Write-Host (Format-Number $Stats.TotalLines) -ForegroundColor White

    if ($Stats.TotalFiles -gt 0) {
        $avgLines = [math]::Round($Stats.TotalLines / $Stats.TotalFiles, 1)
        Write-Host "  Average Lines per File: " -NoNewline
        Write-Host $avgLines -ForegroundColor White
    }

    # Show top languages
    Write-Host "`nTop Languages:" -ForegroundColor Cyan
    $topLanguages = $Stats.Languages.GetEnumerator() |
    Sort-Object { $_.Value.Lines } -Descending |
    Select-Object -First 10

    foreach ($lang in $topLanguages) {
        $percentage = [math]::Round(($lang.Value.Lines / $Stats.TotalLines) * 100, 1)
        Write-Host ("  {0,-20} {1,8} files  {2,10} lines  ({3,5}%)" -f
            $lang.Name,
            (Format-Number $lang.Value.Files),
            (Format-Number $lang.Value.Lines),
            $percentage) -ForegroundColor White
    }

    # Show file extensions if different from languages
    if ($Stats.FileTypes.Count -ne $Stats.Languages.Count) {
        Write-Host "`nFile Extensions:" -ForegroundColor Cyan
        $topExtensions = $Stats.FileTypes.GetEnumerator() |
        Sort-Object { $_.Value.Lines } -Descending |
        Select-Object -First 10

        foreach ($ext in $topExtensions) {
            $percentage = [math]::Round(($ext.Value.Lines / $Stats.TotalLines) * 100, 1)
            Write-Host ("  {0,-15} {1,8} files  {2,10} lines  ({3,5}%)" -f
                $ext.Name,
                (Format-Number $ext.Value.Files),
                (Format-Number $ext.Value.Lines),
                $percentage) -ForegroundColor White
        }
    }
}

function Show-Summary {
    param($AllStats)

    Write-Host "`n" + "="*80 -ForegroundColor Magenta
    Write-Host "SUMMARY - All Repositories" -ForegroundColor Magenta
    Write-Host "="*80 -ForegroundColor Magenta

    $totalFiles = ($AllStats | Measure-Object -Property TotalFiles -Sum).Sum
    $totalLines = ($AllStats | Measure-Object -Property TotalLines -Sum).Sum

    Write-Host "`nGrand Totals:" -ForegroundColor Cyan
    Write-Host "  Repositories Analyzed: " -NoNewline
    Write-Host $AllStats.Count -ForegroundColor White
    Write-Host "  Total Files: " -NoNewline
    Write-Host (Format-Number $totalFiles) -ForegroundColor White
    Write-Host "  Total Lines: " -NoNewline
    Write-Host (Format-Number $totalLines) -ForegroundColor White

    Write-Host "`nRepository Comparison:" -ForegroundColor Cyan
    $sortedRepos = $AllStats | Sort-Object TotalLines -Descending

    foreach ($repo in $sortedRepos) {
        $percentage = if ($totalLines -gt 0) { [math]::Round(($repo.TotalLines / $totalLines) * 100, 1) } else { 0 }
        Write-Host ("  {0,-30} {1,8} files  {2,10} lines  ({3,5}%)" -f
            $repo.RepoName,
            (Format-Number $repo.TotalFiles),
            (Format-Number $repo.TotalLines),
            $percentage) -ForegroundColor White
    }

    # Combined language statistics
    Write-Host "`nCombined Language Statistics:" -ForegroundColor Cyan
    $combinedLanguages = @{}

    foreach ($stats in $AllStats) {
        foreach ($lang in $stats.Languages.GetEnumerator()) {
            if ($combinedLanguages.ContainsKey($lang.Name)) {
                $combinedLanguages[$lang.Name].Files += $lang.Value.Files
                $combinedLanguages[$lang.Name].Lines += $lang.Value.Lines
            }
            else {
                $combinedLanguages[$lang.Name] = @{
                    Files = $lang.Value.Files
                    Lines = $lang.Value.Lines
                }
            }
        }
    }

    $topCombinedLanguages = $combinedLanguages.GetEnumerator() |
    Sort-Object { $_.Value.Lines } -Descending |
    Select-Object -First 15

    foreach ($lang in $topCombinedLanguages) {
        $percentage = [math]::Round(($lang.Value.Lines / $totalLines) * 100, 1)
        Write-Host ("  {0,-20} {1,8} files  {2,10} lines  ({3,5}%)" -f
            $lang.Name,
            (Format-Number $lang.Value.Files),
            (Format-Number $lang.Value.Lines),
            $percentage) -ForegroundColor White
    }
}

# Main execution
Write-Host "Git Repository Line Counter" -ForegroundColor Green
Write-Host "Analyzing $($RepoPaths.Count) repositories..." -ForegroundColor Yellow

$allStats = @()
$validRepos = 0

foreach ($repoPath in $RepoPaths) {
    $absolutePath = Resolve-Path $repoPath -ErrorAction SilentlyContinue
    if (-not $absolutePath) {
        Write-Warning "Path does not exist: $repoPath"
        continue
    }

    if (-not (Test-GitRepository $absolutePath)) {
        Write-Warning "Not a git repository: $absolutePath"
        continue
    }

    $validRepos++
    $stats = Start-CountRepoLines -RepoPath $absolutePath -ExcludePatterns $ExcludePatterns -IncludeFileTypes $IncludeFileTypes

    if ($stats) {
        $allStats += $stats
        Show-RepoStatistics -Stats $stats -AllStats $allStats
    }
}

if ($allStats.Count -gt 1) {
    Show-Summary -AllStats $allStats
}

if ($validRepos -eq 0) {
    Write-Error "No valid git repositories found to analyze."
    exit 1
}

Write-Host "`nAnalysis complete!" -ForegroundColor Green

# Other (.cbl)            3 607 files   3 336 992 lines  (   70`%)
# JavaScript              2 248 files     484 536 lines  ( 10,2`%)
# Other (.gs)             1 220 files     467 052 lines  (  9,8`%)
# Other (.rex)              852 files     243 936 lines  (  5,1`%)
# Other (.bat)            1 088 files      68 544 lines  (  1,4`%)
# PowerShell                527 files      68 484 lines  (  1,4`%)
# C#                        317 files      62 177 lines  (  1,3`%)
# Other (.psm1)              31 files      25 791 lines  (  0,5`%)
# Other (.cmd)              260 files       7 744 lines  (  0,2`%)
# Python                      4 files         240 lines  (    0`%)

# # Total across all repositories: 10,154 files, 4,763,544 lines

