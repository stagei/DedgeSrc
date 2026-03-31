<#
.SYNOPSIS
    Full pipeline: extract Rocket Visual COBOL (VS 2022 v11) help CABs to HTML, normalize,
    convert to Markdown via Doc2Markdown, and fix all cross-links.

.DESCRIPTION
    Combines the three former scripts into one end-to-end run:

      Step 1  Extract .cab files (and .mshc inside them) to output\html.
      Step 2  Normalize HTML: fix asset paths (styles/scripts/icons), rename each file
              to its <title>.html, translate ms-xhelp:// links to title-based .html hrefs.
      Step 3  Convert title-based HTML to Markdown with Doc2Markdown.
      Step 4  Rewrite all cross-links in .md files to local, editor-safe relative paths
              (./Filename%20With%20Spaces.md format).

.PARAMETER SourcePath
    Folder that contains helpcontentsetup.msha and the .cab files
    (e.g. C:\...\vcdocsvs2022_110).  Required for Step 1.
    If omitted, Steps 2-4 run against an already-populated OutputDirectory\html folder.

.PARAMETER OutputDirectory
    Root folder for output.  HTML goes to <OutputDirectory>\html,
    Markdown to <OutputDirectory>\md.
    Defaults to $env:OptPath\src\AiDoc\Rocket Visual Cobol For Visual Studio 2022 Version 11.

.PARAMETER SkipExtract
    Skip Step 1 (CAB extraction).  Use when HTML has already been extracted.

.PARAMETER SkipConvert
    Skip Step 3 (Doc2Markdown conversion).  Use when .md files already exist.

.EXAMPLE
    # Full run from scratch
    .\Build-VcHelpMarkdown.ps1 -SourcePath "C:\HelpSrc\vcdocsvs2022_110"

.EXAMPLE
    # HTML already extracted; just normalize + convert + fix links
    .\Build-VcHelpMarkdown.ps1 -SkipExtract

.EXAMPLE
    # Re-run only link-fixing on existing .md output
    .\Build-VcHelpMarkdown.ps1 -SkipExtract -SkipConvert
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$SourcePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [switch]$SkipExtract,

    [switch]$SkipConvert
)

#region --- Bootstrap logging ---
if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
    try {
        Import-Module GlobalFunctions -Force -ErrorAction Stop
    }
    catch {
        $fallbackPath = Join-Path $PSScriptRoot '..\..\DedgePsh\_Modules\GlobalFunctions\GlobalFunctions.psm1'
        if (Test-Path $fallbackPath -PathType Leaf) {
            Import-Module $fallbackPath -Force -ErrorAction Stop
        }
        else {
            throw 'Write-LogMessage is required. Import-Module GlobalFunctions -Force, or run from an environment where it is available.'
        }
    }
}
#endregion

$ErrorActionPreference = 'Stop'

#region --- Resolve paths ---
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $optPath = $env:OptPath
    if ([string]::IsNullOrWhiteSpace($optPath)) { $optPath = 'C:\opt' }
    $OutputDirectory = Join-Path $optPath 'src\AiDoc\Rocket Visual Cobol For Visual Studio 2022 Version 11'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$outHtml         = Join-Path $OutputDirectory 'html'
$outMd           = Join-Path $OutputDirectory 'md'

$doc2MarkdownScript = 'C:\opt\src\DedgeSrc\Doc2Markdown\Doc2Markdown.ps1'

Write-LogMessage "OutputDirectory : $($OutputDirectory)" -Level INFO
Write-LogMessage "HTML output     : $($outHtml)" -Level INFO
Write-LogMessage "Markdown output : $($outMd)" -Level INFO
#endregion

#region --- Shared helpers ---
$encoding      = [System.Text.Encoding]::UTF8
$titlePattern  = [regex]'<title>\s*([^<]*?)</title>'
# Regex explanation:
#   <title>          literal opening tag
#   \s*              optional leading whitespace
#   ([^<]*?)         capture group 1: any chars except '<', non-greedy (the page title)
#   \s*              optional trailing whitespace (handled by .Trim() after capture)
#   </title>         literal closing tag
$helpIdPattern = [regex]'<meta\s+name="Microsoft\.Help\.Id"\s+content="([^"]+)"'
# Regex explanation:
#   <meta            literal
#   \s+              one or more whitespace chars (between attributes)
#   name="           literal attribute start
#   Microsoft\.Help\.Id   literal value (dots escaped so they don't match any char)
#   "                closing quote
#   \s+              whitespace before next attribute
#   content="        literal
#   ([^"]+)          capture group 1: the Help Id value (any chars except quote)
#   "                closing quote

function Get-SafeFileName {
    <# Sanitize a page title for use as a Windows filename. #>
    param ([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return 'Untitled' }
    $t = $Title.Trim()
    $t = $t -replace '[\\/:*?"<>|]', '_'
    $t = $t -replace '\s+', ' '
    $t = $t -replace '_+', '_'
    $t = $t.Trim(' ', '_')
    if ([string]::IsNullOrEmpty($t)) { return 'Untitled' }
    return $t
}

function Get-LocalMdLinkTarget {
    <#
    Make a .md link target safe for local editors (e.g. Cursor):
    - Adds './' prefix so the link is unambiguously a relative file path.
    - Encodes spaces as %20 so the URL parser does not split the filename.
    #>
    param ([string]$Target)
    if ([string]::IsNullOrEmpty($Target)) { return $Target }
    $t = $Target.Trim()
    if ($t -notmatch '^\./') { $t = './' + $t }
    return $t -replace ' ', '%20'
}
#endregion

# ============================================================
# STEP 1 — Extract CAB / MSHC -> HTML
# ============================================================
if ($SkipExtract) {
    Write-LogMessage 'Step 1 skipped (SkipExtract).' -Level INFO
}
else {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        Write-LogMessage '-SourcePath is required when -SkipExtract is not set.' -Level ERROR
        exit 1
    }
    $SourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path $SourcePath -PathType Container)) {
        Write-LogMessage "SourcePath not found: $($SourcePath)" -Level ERROR
        exit 1
    }

    # Collect .cab files via manifest and direct scan
    $cabFiles  = @()
    $mshaPath  = Join-Path $SourcePath 'helpcontentsetup.msha'
    if (Test-Path $mshaPath -PathType Leaf) {
        Write-LogMessage "Reading manifest: $($mshaPath)" -Level INFO
        $mshaContent = Get-Content -Path $mshaPath -Raw -Encoding UTF8
        # Regex explanation:
        #   href="      literal attribute start
        #   ([^"]+\.cab)  capture group 1: any chars except quote, ending in .cab
        #   "           closing quote
        [regex]::Matches($mshaContent, 'href="([^"]+\.cab)"') |
            ForEach-Object { $_.Groups[1].Value } |
            ForEach-Object {
                $cabPath = Join-Path $SourcePath $_
                if (Test-Path $cabPath -PathType Leaf) { $cabFiles += $cabPath }
                else { Write-LogMessage "CAB from manifest not found: $($cabPath)" -Level WARN }
            }
    }
    $cabFiles += Get-ChildItem -Path $SourcePath -Filter '*.cab' -File -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
    $cabFiles = $cabFiles | Sort-Object -Unique

    if ($cabFiles.Count -eq 0) {
        Write-LogMessage 'No .cab files found in SourcePath.' -Level ERROR
        exit 1
    }

    foreach ($dir in @($OutputDirectory, $outHtml, $outMd)) {
        if (-not (Test-Path $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-LogMessage "Created: $($dir)" -Level INFO
        }
    }

    $expandExe = Join-Path $env:SystemRoot 'System32\expand.exe'
    if (-not (Test-Path $expandExe -PathType Leaf)) {
        Write-LogMessage "expand.exe not found: $($expandExe)" -Level ERROR
        exit 1
    }

    $tempRoot = Join-Path $env:TEMP "VcHelpExport_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-LogMessage "Temp dir: $($tempRoot)" -Level DEBUG

    try {
        $allExtractedDirs = @()

        foreach ($cab in $cabFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cab)
            $destDir  = Join-Path $tempRoot $baseName
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Write-LogMessage "Extracting: $($cab)" -Level INFO
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = $expandExe
            $psi.Arguments              = "`"$cab`" -F:* `"$destDir`""
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $null = $p.StandardOutput.ReadToEnd()
            $err  = $p.StandardError.ReadToEnd()
            $p.WaitForExit(120000)
            if ($p.ExitCode -ne 0) {
                Write-LogMessage "expand.exe error (code $($p.ExitCode)): $($err)" -Level ERROR
                continue
            }
            $allExtractedDirs += $destDir
        }

        # Expand any .mshc (ZIP) files found under temp
        Get-ChildItem -Path $tempRoot -Filter '*.mshc' -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $mshc       = $_
                $zipPath    = $mshc.FullName -replace '\.mshc$', '.zip'
                $extractDir = $mshc.FullName -replace '\.mshc$', '_extracted'
                try {
                    Copy-Item -Path $mshc.FullName -Destination $zipPath -Force
                    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
                    Write-LogMessage "Expanded MSHC: $($mshc.Name)" -Level INFO
                    $allExtractedDirs += $extractDir
                }
                catch {
                    Write-LogMessage "Failed to expand $($mshc.Name): $($_.Exception.Message)" -Level WARN
                }
                finally {
                    if (Test-Path $zipPath -PathType Leaf) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
                }
            }

        # Copy HTML topics and web assets to outHtml
        $htmlCount = 0
        $assetExts = @('*.css','*.js','*.png','*.jpg','*.jpeg','*.gif','*.svg','*.woff','*.woff2')
        foreach ($dir in $allExtractedDirs) {
            if (-not (Test-Path $dir -PathType Container)) { continue }
            Get-ChildItem -Path $dir -Include '*.html','*.xhtml','*.htm' -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $rel        = $_.FullName.Substring($dir.Length).TrimStart('\','/')
                    $destFile   = Join-Path $outHtml $rel
                    $destParent = Split-Path $destFile -Parent
                    if (-not (Test-Path $destParent -PathType Container)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
                    Copy-Item -Path $_.FullName -Destination $destFile -Force
                    $htmlCount++
                }
            foreach ($ext in $assetExts) {
                Get-ChildItem -Path $dir -Filter $ext -Recurse -File -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $rel        = $_.FullName.Substring($dir.Length).TrimStart('\','/')
                        $destFile   = Join-Path $outHtml $rel
                        $destParent = Split-Path $destFile -Parent
                        if (-not (Test-Path $destParent -PathType Container)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
                        Copy-Item -Path $_.FullName -Destination $destFile -Force
                    }
            }
        }
        Write-LogMessage "Step 1 complete: $($htmlCount) HTML topic(s) copied to $($outHtml)" -Level INFO
    }
    finally {
        if (Test-Path $tempRoot -PathType Container) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Removed temp dir: $($tempRoot)" -Level DEBUG
        }
    }
}

# ============================================================
# STEP 2 — Normalize HTML: title-based filenames + fix paths
# ============================================================
Write-LogMessage 'Step 2: Normalizing HTML (title-based filenames, asset paths, ms-xhelp links).' -Level INFO

if (-not (Test-Path $outHtml -PathType Container)) {
    Write-LogMessage "HTML output folder not found: $($outHtml). Run without -SkipExtract first." -Level ERROR
    exit 1
}

# Topic HTML lives in two subfolders after extraction
$topicFolders = @(
    (Join-Path $outHtml 'html'),
    (Join-Path $outHtml 'MicroFocus_COBOL_RuntimeServices_extracted\html')
)
$allTopicFiles = @()
foreach ($dir in $topicFolders) {
    if (Test-Path $dir -PathType Container) {
        $allTopicFiles += Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(htm|html)$' }
    }
}

# Deduplicate by filename (same topic may appear in both folders)
$byBasename = @{}
foreach ($f in $allTopicFiles) {
    if (-not $byBasename.ContainsKey($f.Name)) { $byBasename[$f.Name] = $f }
}
$topicFiles = @($byBasename.Values)
Write-LogMessage "Found $($topicFiles.Count) unique topic file(s) to normalize." -Level INFO

# Pass 1: build Help Id -> safe base filename map
$idToBaseName = @{}
foreach ($file in $topicFiles) {
    $content    = [System.IO.File]::ReadAllText($file.FullName, $encoding)
    $titleM     = $titlePattern.Match($content)
    $title      = if ($titleM.Success) { $titleM.Groups[1].Value.Trim() } else { $file.BaseName }
    $baseName   = Get-SafeFileName $title
    $idM        = $helpIdPattern.Match($content)
    if ($idM.Success) {
        $helpId = $idM.Groups[1].Value.Trim()
        if (-not $idToBaseName.ContainsKey($helpId)) { $idToBaseName[$helpId] = $baseName }
    }
}
Write-LogMessage "Help Id map: $($idToBaseName.Count) entries." -Level INFO

# Pass 2: write title-based HTML with fixed paths and translated ms-xhelp links
$usedNames       = @{}
$savedCount      = 0
$fixedPathCount  = 0
$linkReplaceCount = 0

foreach ($file in $topicFiles) {
    $content  = [System.IO.File]::ReadAllText($file.FullName, $encoding)
    $titleM   = $titlePattern.Match($content)
    $title    = if ($titleM.Success) { $titleM.Groups[1].Value.Trim() } else { $file.BaseName }
    $baseName = Get-SafeFileName $title
    $fileName = $baseName + '.html'

    if ($usedNames.ContainsKey($fileName)) {
        $usedNames[$fileName] += 1
        $n        = $usedNames[$fileName]
        $fileName = "$baseName ($n).html"
    }
    else {
        $usedNames[$fileName] = 1
    }

    $orig    = $content
    $content = $content -replace 'href="\.\./styles/',  'href="styles/'
    $content = $content -replace 'href="\.\./scripts/', 'href="scripts/'
    $content = $content -replace 'href="\.\./icons/',   'href="icons/'
    $content = $content -replace 'src="\.\./styles/',   'src="styles/'
    $content = $content -replace 'src="\.\./scripts/',  'src="scripts/'
    $content = $content -replace 'src="\.\./icons/',    'src="icons/'
    if ($content -ne $orig) { $fixedPathCount++ }

    foreach ($entry in $idToBaseName.GetEnumerator()) {
        $oldLink = "ms-xhelp:///?Id=$($entry.Key)"
        $newLink = "$($entry.Value).html"
        if ($content.Contains($oldLink)) {
                    $content = $content.Replace($oldLink, $newLink)
                    $linkReplaceCount++
                }
    }

    $destPath = Join-Path $outHtml $fileName
    [System.IO.File]::WriteAllText($destPath, $content, $encoding)
    $savedCount++
}
Write-LogMessage "Step 2 complete: $($savedCount) file(s) saved, $($fixedPathCount) asset paths fixed, $($linkReplaceCount) ms-xhelp link(s) replaced." -Level INFO

# ============================================================
# STEP 3 — Convert HTML -> Markdown via Doc2Markdown
# ============================================================
if ($SkipConvert) {
    Write-LogMessage 'Step 3 skipped (SkipConvert).' -Level INFO
}
else {
    if (-not (Test-Path $doc2MarkdownScript -PathType Leaf)) {
        Write-LogMessage "Doc2Markdown not found at $($doc2MarkdownScript) — skipping conversion. Run Step 4 manually if .md files already exist." -Level WARN
    }
    else {
        if (-not (Test-Path $outMd -PathType Container)) {
            New-Item -ItemType Directory -Path $outMd -Force | Out-Null
        }
        Write-LogMessage "Step 3: Running Doc2Markdown -> $($outMd)" -Level INFO
        & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $doc2MarkdownScript `
            -InputPath $outHtml -OutputPath $outMd -Recursive:$false -EmbedImages:$true
        if ($LASTEXITCODE -eq 0) {
            $mdCount = (Get-ChildItem -Path $outMd -Filter '*.md' -File -ErrorAction SilentlyContinue | Measure-Object).Count
            Write-LogMessage "Step 3 complete: $($mdCount) Markdown file(s) in $($outMd)" -Level INFO
        }
        else {
            Write-LogMessage "Doc2Markdown exited with code $($LASTEXITCODE)." -Level WARN
        }
    }
}

# ============================================================
# STEP 4 — Fix / normalize all cross-links in .md files
# ============================================================
Write-LogMessage 'Step 4: Fixing cross-links in Markdown files.' -Level INFO

if (-not (Test-Path $outMd -PathType Container)) {
    Write-LogMessage "Markdown folder not found, nothing to fix: $($outMd)" -Level WARN
}
else {
    # Build a fresh Id -> base filename map from the now-written title-based HTML
    $idMapForMd = @{}
    Get-ChildItem -Path $outHtml -Filter '*.html' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $base    = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $content = [System.IO.File]::ReadAllText($_.FullName, $encoding)
            $idM     = $helpIdPattern.Match($content)
            if ($idM.Success) {
                $id = $idM.Groups[1].Value.Trim()
                if (-not $idMapForMd.ContainsKey($id)) { $idMapForMd[$id] = $base }
            }
        }
    Write-LogMessage "Link map: $($idMapForMd.Count) Help Id(s) from HTML." -Level INFO

    $mdFilesUpdated = 0
    Get-ChildItem -Path $outMd -Filter '*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $mdFile    = $_
            $mdContent = [System.IO.File]::ReadAllText($mdFile.FullName, $encoding)
            $orig      = $mdContent

            # Replace ms-xhelp:// links with local .md paths
            foreach ($entry in $idMapForMd.GetEnumerator()) {
                $target    = Get-LocalMdLinkTarget ($entry.Value + '.md')
                $mdContent = $mdContent.Replace("](ms-xhelp:///?Id=$($entry.Key))", "]($target)")
            }

            # Rewrite .html -> .md
            $mdContent = [regex]::Replace($mdContent, '\]\(([^)]+)\.html\)', ']($1.md)')

            # Normalize all remaining .md link targets (add ./, encode spaces)
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
    Write-LogMessage "Step 4 complete: $($mdFilesUpdated) Markdown file(s) had links updated." -Level INFO
}

Write-LogMessage "All done. Markdown: $($outMd)" -Level INFO
