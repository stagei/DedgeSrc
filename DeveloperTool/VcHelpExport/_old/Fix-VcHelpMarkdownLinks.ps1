<#
.SYNOPSIS
    Fixes ms-xhelp and .html links in existing VcHelp Markdown so they point to the correct .md documents.

.DESCRIPTION
    Builds Help Id -> base filename from title-based .html in output\html (using meta Microsoft.Help.Id and filename),
    then rewrites ](ms-xhelp:///?Id=XXX) and ](X.html) in all output\md\*.md to ](X.md).

.PARAMETER OutputHtmlRoot
    Folder containing title-based .html (default: script\output\html).
.PARAMETER OutputMdRoot
    Folder containing .md files (default: script\output\md).
#>
[CmdletBinding()]
param (
    [string]$OutputHtmlRoot = (Join-Path $PSScriptRoot "output\html"),
    [string]$OutputMdRoot   = (Join-Path $PSScriptRoot "output\md")
)

$ErrorActionPreference = "Stop"
$OutputHtmlRoot = [System.IO.Path]::GetFullPath($OutputHtmlRoot)
$OutputMdRoot   = [System.IO.Path]::GetFullPath($OutputMdRoot)
$encoding = [System.Text.Encoding]::UTF8
$helpIdPattern = [regex]'<meta\s+name="Microsoft\.Help\.Id"\s+content="([^"]+)"'

# Build Id -> base filename from root-level .html (they are named Title.html; base = filename without .html)
$idToBaseName = @{}
Get-ChildItem -Path $OutputHtmlRoot -Filter "*.html" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $content = [System.IO.File]::ReadAllText($_.FullName, $encoding)
    $idM = $helpIdPattern.Match($content)
    if ($idM.Success) {
        $id = $idM.Groups[1].Value.Trim()
        $idToBaseName[$id] = $base
    }
}
Write-Host "Built Id->filename map for $($idToBaseName.Count) Help Id(s) from $OutputHtmlRoot."

# Make .md link targets local-path safe: add ./ and encode spaces so editors (e.g. Cursor) open file, not "external website".
function Get-LocalMdLinkTarget {
    param ([string]$Target)
    if ([string]::IsNullOrEmpty($Target)) { return $Target }
    $t = $Target.Trim()
    if ($t -notmatch '^\./') { $t = './' + $t }
    return $t -replace ' ', '%20'
}

$mdFilesUpdated = 0
foreach ($mdFile in (Get-ChildItem -Path $OutputMdRoot -Filter "*.md" -File -ErrorAction SilentlyContinue)) {
    $mdContent = [System.IO.File]::ReadAllText($mdFile.FullName, $encoding)
    $orig = $mdContent
    foreach ($entry in $idToBaseName.GetEnumerator()) {
        $target = Get-LocalMdLinkTarget ($entry.Value + '.md')
        $mdContent = $mdContent.Replace("](ms-xhelp:///?Id=$($entry.Key))", "]($target)")
    }
    # ](something.html) -> ]./(something).md with encoded spaces
    $mdContent = [regex]::Replace($mdContent, '\]\(([^)]+)\.html\)', { param($m) $target = Get-LocalMdLinkTarget ($m.Groups[1].Value + '.md'); "]($target)" })
    # Normalize existing .md links (spaces -> %20, add ./) so editors treat them as local files
    $mdContent = [regex]::Replace($mdContent, '\]\(([^)]*\.md)\)', { param($m) $target = Get-LocalMdLinkTarget $m.Groups[1].Value; "]($target)" })
    if ($mdContent -ne $orig) { $mdFilesUpdated++ }
    [System.IO.File]::WriteAllText($mdFile.FullName, $mdContent, $encoding)
}
Write-Host "Updated cross-references in $mdFilesUpdated Markdown file(s)."
