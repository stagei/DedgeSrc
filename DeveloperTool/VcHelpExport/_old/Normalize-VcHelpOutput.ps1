<#
.SYNOPSIS
    Normalizes exported VcHelp HTML: fixes asset paths (styles, scripts, icons) and saves each page by its <title> as the filename.

.DESCRIPTION
    Reads all .htm/.html from output\html\html and output\html\MicroFocus_COBOL_RuntimeServices_extracted\html,
    rewrites relative paths to styles, scripts, and icons so they resolve from output\html,
    extracts the trimmed <title>, and saves each file as "Title.html" in output\html (with duplicate handling).

.PARAMETER OutputHtmlRoot
    Root folder containing html, styles, scripts, icons (default: script folder\output\html).
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$OutputHtmlRoot = (Join-Path $PSScriptRoot "output\html")
)

$ErrorActionPreference = "Stop"
$OutputHtmlRoot = [System.IO.Path]::GetFullPath($OutputHtmlRoot)
if (-not (Test-Path $OutputHtmlRoot -PathType Container)) {
    Write-Error "Output HTML root not found: $OutputHtmlRoot"
    exit 1
}

# Folders that contain topic .htm files (may be duplicated across both)
$topicFolders = @(
    (Join-Path $OutputHtmlRoot "html"),
    (Join-Path $OutputHtmlRoot "MicroFocus_COBOL_RuntimeServices_extracted\html")
)

# -Include only works when -Path has a wildcard; use -Filter or Where-Object to get .htm and .html
$allTopicFiles = @()
foreach ($dir in $topicFolders) {
    if (Test-Path $dir -PathType Container) {
        $allTopicFiles += Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(htm|html)$' }
    }
}

# Dedupe by same filename (same topic from two sources); keep one
$byBasename = @{}
foreach ($f in $allTopicFiles) {
    $key = $f.Name
    if (-not $byBasename.ContainsKey($key)) {
        $byBasename[$key] = $f
    }
}
$topicFiles = @($byBasename.Values)
$encoding = [System.Text.Encoding]::UTF8

Write-Host "Processing $($topicFiles.Count) unique topic file(s)."

# Regex: <title> optional whitespace, capture content, optional whitespace </title>
$titlePattern = [regex]'<title>\s*([^<]*?)</title>'
# Regex: Microsoft.Help.Id meta tag -> capture Id value
$helpIdPattern = [regex]'<meta\s+name="Microsoft\.Help\.Id"\s+content="([^"]+)"'

# Sanitize string for use as filename: remove/replace invalid and trim
function Get-SafeFileName {
    param ([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return "Untitled" }
    $t = $Title.Trim()
    # Replace Windows invalid filename chars with underscore
    $t = $t -replace '[\\/:*?"<>|]', '_'
    # Collapse multiple spaces/underscores to single underscore
    $t = $t -replace '\s+', ' '
    $t = $t -replace '_+', '_'
    $t = $t.Trim(' ', '_')
    if ([string]::IsNullOrEmpty($t)) { return "Untitled" }
    return $t
}

# Make .md link targets local-path safe so editors (e.g. Cursor) open file, not "external website".
function Get-LocalMdLinkTarget {
    param ([string]$Target)
    if ([string]::IsNullOrEmpty($Target)) { return $Target }
    $t = $Target.Trim()
    if ($t -notmatch '^\./') { $t = './' + $t }
    return $t -replace ' ', '%20'
}

# --- Pass 1: Build Help Id -> base filename map (from each topic's meta + title) ---
$idToBaseName = @{}
foreach ($file in $topicFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, $encoding)
    $titleM = $titlePattern.Match($content)
    $title = if ($titleM.Success) { $titleM.Groups[1].Value.Trim() } else { $file.BaseName }
    $baseFileName = Get-SafeFileName $title
    $idM = $helpIdPattern.Match($content)
    if ($idM.Success) {
        $helpId = $idM.Groups[1].Value.Trim()
        if (-not $idToBaseName.ContainsKey($helpId)) {
            $idToBaseName[$helpId] = $baseFileName
        }
    }
}
Write-Host "Built Id->filename map for $($idToBaseName.Count) Help Id(s)."

$usedNames = @{}
$savedCount = 0
$fixedPathCount = 0
$linkReplaceCount = 0

foreach ($file in $topicFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, $encoding)

    # Extract title
    $m = $titlePattern.Match($content)
    $title = if ($m.Success) { $m.Groups[1].Value.Trim() } else { $file.BaseName }
    $baseFileName = Get-SafeFileName $title
    $fileName = $baseFileName + ".html"

    # Ensure unique filename
    if ($usedNames.ContainsKey($fileName)) {
        $usedNames[$fileName] += 1
        $n = $usedNames[$fileName]
        $fileName = "${baseFileName} ($n).html"
    }
    else {
        $usedNames[$fileName] = 1
    }

    # Fix relative paths so they resolve from output\html (styles, scripts, icons at same level)
    $originalContent = $content
    $content = $content -replace 'href="\.\./styles/', 'href="styles/'
    $content = $content -replace 'href="\.\./scripts/', 'href="scripts/'
    $content = $content -replace 'href="\.\./icons/', 'href="icons/'
    $content = $content -replace 'src="\.\./styles/', 'src="styles/'
    $content = $content -replace 'src="\.\./scripts/', 'src="scripts/'
    $content = $content -replace 'src="\.\./icons/', 'src="icons/'
    if ($content -ne $originalContent) { $fixedPathCount++ }

    # Translate ms-xhelp links to title-based .html (same folder)
    foreach ($entry in $idToBaseName.GetEnumerator()) {
        $id = $entry.Key
        $base = $entry.Value
        $oldLink = "ms-xhelp:///?Id=$id"
        $newLink = "$base.html"
        if ($content -like "*$oldLink*") {
            $content = $content.Replace($oldLink, $newLink)
            $linkReplaceCount++
        }
    }

    $destPath = Join-Path $OutputHtmlRoot $fileName
    [System.IO.File]::WriteAllText($destPath, $content, $encoding)
    $savedCount++
}

Write-Host "Saved $savedCount topic(s) to $OutputHtmlRoot with title-based filenames. Updated paths in $fixedPathCount file(s). Replaced $linkReplaceCount ms-xhelp link(s) with title-based .html."

# Generate Markdown from the title-based HTML using Doc2Markdown (same base name -> .md in output\md)
$outputMdRoot = Join-Path (Split-Path $OutputHtmlRoot -Parent) "md"
if (-not (Test-Path $outputMdRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $outputMdRoot -Force | Out-Null
}
$doc2MarkdownScript = Join-Path $PSScriptRoot "..\Doc2Markdown\Doc2Markdown.ps1"
if (Test-Path $doc2MarkdownScript -PathType Leaf) {
    Write-Host "Running Doc2Markdown to produce Markdown in $outputMdRoot ..."
    & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $doc2MarkdownScript -InputPath $OutputHtmlRoot -OutputPath $outputMdRoot -Recursive:$false -EmbedImages:$true
    if ($LASTEXITCODE -eq 0) {
        $mdCount = (Get-ChildItem -Path $outputMdRoot -Filter "*.md" -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "Markdown output: $mdCount file(s) in $outputMdRoot"
        # Rewrite ms-xhelp and .html links in .md to point to .md files (Get-LocalMdLinkTarget defined at script level)
        $mdFilesUpdated = 0
        foreach ($mdFile in (Get-ChildItem -Path $outputMdRoot -Filter "*.md" -File -ErrorAction SilentlyContinue)) {
            $mdContent = [System.IO.File]::ReadAllText($mdFile.FullName, $encoding)
            $orig = $mdContent
            foreach ($entry in $idToBaseName.GetEnumerator()) {
                $id = $entry.Key
                $target = Get-LocalMdLinkTarget ($entry.Value + '.md')
                $mdContent = $mdContent.Replace("](ms-xhelp:///?Id=$id)", "]($target)")
            }
            # .html -> .md
            $mdContent = [regex]::Replace($mdContent, '\]\(([^)]+)\.html\)', ']($1.md)')
            # Normalize all .md links (add ./, encode spaces) so editors open file, not "external website"
            $rawTargets = [regex]::Matches($mdContent, '\]\(([^)]*\.md)\)') |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
            foreach ($rawTarget in $rawTargets) {
                $encoded = Get-LocalMdLinkTarget $rawTarget
                if ($rawTarget -ne $encoded) {
                    $mdContent = $mdContent.Replace("]($rawTarget)", "]($encoded)")
                }
            }
            if ($mdContent -ne $orig) { $mdFilesUpdated++ }
            [System.IO.File]::WriteAllText($mdFile.FullName, $mdContent, $encoding)
        }
        if ($mdFilesUpdated -gt 0) { Write-Host "Rewrote cross-references in $mdFilesUpdated Markdown file(s) to .md targets." }
    }
    else {
        Write-Warning "Doc2Markdown exited with code $LASTEXITCODE."
    }
}
else {
    Write-Warning "Doc2Markdown.ps1 not found at $doc2MarkdownScript; skipping Markdown generation."
}
