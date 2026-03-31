<#
.SYNOPSIS
    Exports Rocket Visual COBOL (VS 2022 v11) help content from .cab/.mshc to HTML and optionally Markdown.

.DESCRIPTION
    Extracts .cab packages (and any .mshc containers inside them), then copies HTML/assets to an output folder
    and optionally converts HTML to Markdown using pandoc when -ExportFormat includes Markdown.

.PARAMETER SourcePath
    Folder containing helpcontentsetup.msha and the .cab files (e.g. vcdocsvs2022_110), or a folder that
    contains .cab or .mshc files directly.

.PARAMETER OutputDirectory
    Root folder for exported content. HTML goes to <OutputDirectory>\html, Markdown to <OutputDirectory>\md.
    Defaults to <script folder>\output.

.PARAMETER ExportFormat
    What to produce: HTML only, Markdown only, or Both. Markdown requires pandoc on the path.

.EXAMPLE
    .\Export-VcHelpToHtmlOrMarkdown.ps1 -SourcePath "C:\...\vcdocsvs2022_110" -ExportFormat Both
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "output"),

    [Parameter(Mandatory = $false)]
    [ValidateSet("HTML", "Markdown", "Both")]
    [string]$ExportFormat = "Both"
)

# Ensure we have Write-LogMessage (GlobalFunctions from PsModulePath or fallback path)
if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
    try {
        Import-Module GlobalFunctions -Force -ErrorAction Stop
    }
    catch {
        $fallbackModulePath = Join-Path $PSScriptRoot "..\..\DedgePsh\_Modules\GlobalFunctions"
        if (Test-Path (Join-Path $fallbackModulePath "GlobalFunctions.psm1") -PathType Leaf) {
            Import-Module $fallbackModulePath -Force -ErrorAction Stop
        }
        else {
            throw "Write-LogMessage required. Load GlobalFunctions (e.g. Import-Module GlobalFunctions -Force) or run from an environment where it is available."
        }
    }
}

$ErrorActionPreference = "Stop"
if (-not [System.IO.Path]::IsPathRooted($SourcePath)) {
    $SourcePath = [System.IO.Path]::GetFullPath((Join-Path $PWD $SourcePath))
}
if (-not (Test-Path $SourcePath -PathType Container)) {
    Write-LogMessage "Source path does not exist or is not a directory: $($SourcePath)" -Level ERROR
    exit 1
}

if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $PWD $OutputDirectory))
}
$outHtml = Join-Path $OutputDirectory "html"
$outMd = Join-Path $OutputDirectory "md"

# Resolve .cab files from source folder (and optionally from .msha)
$cabFiles = @()
$mshaPath = Join-Path $SourcePath "helpcontentsetup.msha"
if (Test-Path $mshaPath -PathType Leaf) {
    Write-LogMessage "Reading manifest: $($mshaPath)" -Level INFO
    $mshaContent = Get-Content -Path $mshaPath -Raw -Encoding UTF8
    # Match href="Something.cab" in the manifest
    $cabNames = [regex]::Matches($mshaContent, 'href="([^"]+\.cab)"') | ForEach-Object { $_.Groups[1].Value }
    foreach ($name in $cabNames) {
        $cabPath = Join-Path $SourcePath $name
        if (Test-Path $cabPath -PathType Leaf) {
            $cabFiles += $cabPath
        }
        else {
            Write-LogMessage "CAB referenced in manifest not found: $($cabPath)" -Level WARN
        }
    }
}
# Also add any .cab directly in the folder
$cabFiles += Get-ChildItem -Path $SourcePath -Filter "*.cab" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
$cabFiles = $cabFiles | Sort-Object -Unique

if ($cabFiles.Count -eq 0) {
    Write-LogMessage "No .cab files found in or via source path. Place RocketVisualCOBOL.cab and MicroFocus_COBOL_RuntimeServices.cab in the source folder, or point -SourcePath to a folder that contains them." -Level ERROR
    exit 1
}

Write-LogMessage "Found $($cabFiles.Count) CAB file(s). Creating output directories." -Level INFO
foreach ($dir in @($OutputDirectory, $outHtml, $outMd)) {
    if (-not (Test-Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-LogMessage "Created directory: $($dir)" -Level INFO
    }
}

$expandExe = Join-Path $env:SystemRoot "System32\expand.exe"
if (-not (Test-Path $expandExe -PathType Leaf)) {
    Write-LogMessage "Windows expand.exe not found: $($expandExe)" -Level ERROR
    exit 1
}

$tempRoot = Join-Path $env:TEMP "VcHelpExport_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
Write-LogMessage "Using temp directory: $($tempRoot)" -Level DEBUG

try {
    $allExtractedDirs = @()
    foreach ($cab in $cabFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cab)
        $destDir = Join-Path $tempRoot $baseName
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Write-LogMessage "Extracting CAB: $($cab) -> $($destDir)" -Level INFO
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $expandExe
        $psi.Arguments = "`"$cab`" -F:* `"$destDir`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $null = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit(120000)
        if ($p.ExitCode -ne 0) {
            Write-LogMessage "expand.exe exited with code $($p.ExitCode). StdErr: $($err)" -Level ERROR
            continue
        }
        $allExtractedDirs += $destDir
    }

    # Find and expand all .mshc (ZIP) under temp
    $mshcFiles = Get-ChildItem -Path $tempRoot -Filter "*.mshc" -Recurse -File -ErrorAction SilentlyContinue
    foreach ($mshc in $mshcFiles) {
        $zipPath = $mshc.FullName -replace '\.mshc$', '.zip'
        $extractDir = $mshc.FullName -replace '\.mshc$', '_extracted'
        try {
            Copy-Item -Path $mshc.FullName -Destination $zipPath -Force
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
            Write-LogMessage "Expanded MSHC: $($mshc.Name) -> $($extractDir)" -Level INFO
            $allExtractedDirs += $extractDir
        }
        catch {
            Write-LogMessage "Failed to expand .mshc $($mshc.FullName): $($_.Exception.Message)" -Level WARN -Exception $_
        }
        finally {
            if (Test-Path $zipPath -PathType Leaf) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
        }
    }

    # Gather all .html/.xhtml and assets from extracted dirs and copy to output\html
    $htmlCount = 0
    foreach ($dir in $allExtractedDirs) {
        if (-not (Test-Path $dir -PathType Container)) { continue }
        $htmlFiles = Get-ChildItem -Path $dir -Include "*.html", "*.xhtml", "*.htm" -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $htmlFiles) {
            $rel = $f.FullName.Substring($dir.Length).TrimStart('\', '/')
            $destFile = Join-Path $outHtml $rel
            $destParent = [System.IO.Path]::GetDirectoryName($destFile)
            if (-not (Test-Path $destParent -PathType Container)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Copy-Item -Path $f.FullName -Destination $destFile -Force
            $htmlCount++
        }
        # Copy common asset extensions so links and images work
        $assetExtensions = @("*.css", "*.js", "*.png", "*.jpg", "*.jpeg", "*.gif", "*.svg", "*.woff", "*.woff2")
        foreach ($ext in $assetExtensions) {
            Get-ChildItem -Path $dir -Filter $ext -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring($dir.Length).TrimStart('\', '/')
                $destFile = Join-Path $outHtml $rel
                $destParent = [System.IO.Path]::GetDirectoryName($destFile)
                if (-not (Test-Path $destParent -PathType Container)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $destFile -Force
            }
        }
    }
    Write-LogMessage "Copied $($htmlCount) HTML topic(s) and assets to $($outHtml)" -Level INFO

    # Optional: convert HTML -> Markdown with pandoc
    if ($ExportFormat -in @("Markdown", "Both")) {
        $pandocExe = Get-Command pandoc -ErrorAction SilentlyContinue
        if (-not $pandocExe) {
            Write-LogMessage "pandoc not found on PATH. Skipping Markdown export. Install pandoc or set ExportFormat to HTML." -Level WARN
        }
        else {
            $htmlTopics = Get-ChildItem -Path $outHtml -Include "*.html", "*.xhtml", "*.htm" -Recurse -File -ErrorAction SilentlyContinue
            $mdCount = 0
            foreach ($f in $htmlTopics) {
                $rel = $f.FullName.Substring($outHtml.Length).TrimStart('\', '/')
                $mdRel = [System.IO.Path]::ChangeExtension($rel, "md")
                $destMd = Join-Path $outMd $mdRel
                $destParent = [System.IO.Path]::GetDirectoryName($destMd)
                if (-not (Test-Path $destParent -PathType Container)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }
                try {
                    & pandoc -s $f.FullName -o $destMd 2>&1 | Out-Null
                    $mdCount++
                }
                catch {
                    Write-LogMessage "pandoc failed for $($f.Name): $($_.Exception.Message)" -Level WARN -Exception $_
                }
            }
            Write-LogMessage "Converted $($mdCount) topic(s) to Markdown in $($outMd)" -Level INFO
        }
    }
}
finally {
    if (Test-Path $tempRoot -PathType Container) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Removed temp directory: $($tempRoot)" -Level DEBUG
    }
}

Write-LogMessage "Export complete. HTML: $($outHtml). Markdown: $($outMd)." -Level INFO
