# Remove AutoDoc output files that need regeneration due to code changes
# This script removes BAT, PS1, and REXX HTML/MMD files and their JSON index files

param(
    [string]$ServerWebsPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc"
)

Import-Module GlobalFunctions -Force

Write-LogMessage "Removing regenerated files from: $ServerWebsPath" -Level INFO

if (-not (Test-Path $ServerWebsPath)) {
    Write-LogMessage "Server path not accessible: $ServerWebsPath" -Level ERROR
    exit 1
}

$deletedCount = 0
$errorCount = 0

# Remove BAT files
Write-LogMessage "Removing BAT HTML files..." -Level INFO
$batHtmlFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.bat.html" -ErrorAction SilentlyContinue
foreach ($file in $batHtmlFiles) {
    try {
        Remove-Item $file.FullName -Force -ErrorAction Stop
        $deletedCount++
    }
    catch {
        Write-LogMessage "Error deleting $($file.Name): $($_.Exception.Message)" -Level WARN
        $errorCount++
    }
}
Write-LogMessage "Removed $($batHtmlFiles.Count) BAT HTML files" -Level INFO

Write-LogMessage "Removing BAT MMD files..." -Level INFO
$batMmdFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.bat.mmd" -ErrorAction SilentlyContinue
foreach ($file in $batMmdFiles) {
    try {
        Remove-Item $file.FullName -Force -ErrorAction Stop
        $deletedCount++
    }
    catch {
        Write-LogMessage "Error deleting $($file.Name): $($_.Exception.Message)" -Level WARN
        $errorCount++
    }
}
Write-LogMessage "Removed $($batMmdFiles.Count) BAT MMD files" -Level INFO

# Remove PS1 files
Write-LogMessage "Removing PS1 HTML files..." -Level INFO
$ps1HtmlFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.ps1.html" -ErrorAction SilentlyContinue
foreach ($file in $ps1HtmlFiles) {
    try {
        Remove-Item $file.FullName -Force -ErrorAction Stop
        $deletedCount++
    }
    catch {
        Write-LogMessage "Error deleting $($file.Name): $($_.Exception.Message)" -Level WARN
        $errorCount++
    }
}
Write-LogMessage "Removed $($ps1HtmlFiles.Count) PS1 HTML files" -Level INFO

Write-LogMessage "Removing PS1 MMD files..." -Level INFO
$ps1MmdFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.ps1.mmd" -ErrorAction SilentlyContinue
foreach ($file in $ps1MmdFiles) {
    try {
        Remove-Item $file.FullName -Force -ErrorAction Stop
        $deletedCount++
    }
    catch {
        Write-LogMessage "Error deleting $($file.Name): $($_.Exception.Message)" -Level WARN
        $errorCount++
    }
}
Write-LogMessage "Removed $($ps1MmdFiles.Count) PS1 MMD files" -Level INFO

# Remove REXX files
Write-LogMessage "Removing REXX HTML files..." -Level INFO
$rexHtmlFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.rex.html" -ErrorAction SilentlyContinue
foreach ($file in $rexHtmlFiles) {
    try {
        Remove-Item $file.FullName -Force -ErrorAction Stop
        $deletedCount++
    }
    catch {
        Write-LogMessage "Error deleting $($file.Name): $($_.Exception.Message)" -Level WARN
        $errorCount++
    }
}
Write-LogMessage "Removed $($rexHtmlFiles.Count) REXX HTML files" -Level INFO

Write-LogMessage "Removing REXX MMD files..." -Level INFO
$rexMmdFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.rex.mmd" -ErrorAction SilentlyContinue
foreach ($file in $rexMmdFiles) {
    try {
        Remove-Item $file.FullName -Force -ErrorAction Stop
        $deletedCount++
    }
    catch {
        Write-LogMessage "Error deleting $($file.Name): $($_.Exception.Message)" -Level WARN
        $errorCount++
    }
}
Write-LogMessage "Removed $($rexMmdFiles.Count) REXX MMD files" -Level INFO

# Remove JSON index files
$jsonOutputFolder = Join-Path $ServerWebsPath "_json"
if (Test-Path $jsonOutputFolder) {
    Write-LogMessage "Removing JSON index files..." -Level INFO
    
    $jsonFiles = @(
        "BatParseResult.json",
        "Ps1ParseResult.json",
        "RexParseResult.json"
    )
    
    foreach ($jsonFile in $jsonFiles) {
        $jsonPath = Join-Path $jsonOutputFolder $jsonFile
        if (Test-Path $jsonPath) {
            try {
                Remove-Item $jsonPath -Force -ErrorAction Stop
                Write-LogMessage "Removed JSON file: $jsonFile" -Level INFO
                $deletedCount++
            }
            catch {
                Write-LogMessage "Error deleting $($jsonFile): $($_.Exception.Message)" -Level WARN
                $errorCount++
            }
        }
    }
}

Write-LogMessage "============================================" -Level INFO
Write-LogMessage "Summary: Deleted $deletedCount files, $errorCount errors" -Level INFO
Write-LogMessage "============================================" -Level INFO
