<#
.SYNOPSIS
    Fixes incorrect paths and Mermaid ER diagram syntax in AutoDoc HTML files.
.DESCRIPTION
    This script scans all HTML files in the AutoDoc output folder and fixes:
    1. Old folder paths: .images -> _images, .json -> _json, .js -> _js, .css -> _css, .templates -> _templates
    2. Mermaid ER diagram issues: 
       - Multi-word types (LONG VARCHAR -> LONGVARCHAR)
       - Type length specifiers (CHARACTER(1) -> CHARACTER)
.PARAMETER Path
    The path to the AutoDoc folder. Defaults to $env:OptPath\Webs\AutoDoc
.PARAMETER WhatIf
    Shows what would be changed without making changes.
.EXAMPLE
    .\Fix-AutoDocPaths.ps1
    Fixes all files in the default AutoDoc folder.
.EXAMPLE
    .\Fix-AutoDocPaths.ps1 -Path "E:\opt\Webs\AutoDoc" -WhatIf
    Shows what would be fixed without making changes.
#>
param(
    [string]$Path = "$env:OptPath\Webs\AutoDoc",
    [switch]$WhatIf
)

# Import logging if available
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
    $hasLogging = $true
} catch {
    $hasLogging = $false
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if ($hasLogging) {
        Write-LogMessage $Message -Level $Level
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

Write-Log "Starting AutoDoc path fix script" -Level INFO
Write-Log "Target folder: $Path" -Level INFO

if (-not (Test-Path $Path)) {
    Write-Log "Path does not exist: $Path" -Level ERROR
    exit 1
}

# Get all HTML files
$htmlFiles = Get-ChildItem -Path $Path -Filter "*.html" -File
$totalFiles = $htmlFiles.Count
Write-Log "Found $totalFiles HTML files to process" -Level INFO

$stats = @{
    FilesProcessed = 0
    FilesModified = 0
    PathFixes = 0
    MermaidFixes = 0
    Errors = 0
}

foreach ($file in $htmlFiles) {
    $stats.FilesProcessed++
    
    try {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $originalContent = $content
        $modified = $false
        
        # === FIX 1: Old folder paths ===
        # .images -> _images
        if ($content -match '\./.images/') {
            $content = $content -replace '\./.images/', './_images/'
            $stats.PathFixes++
            $modified = $true
        }
        
        # .json -> _json
        if ($content -match '\./.json/') {
            $content = $content -replace '\./.json/', './_json/'
            $stats.PathFixes++
            $modified = $true
        }
        
        # .js -> _js
        if ($content -match '\./.js/') {
            $content = $content -replace '\./.js/', './_js/'
            $stats.PathFixes++
            $modified = $true
        }
        
        # .css -> _css
        if ($content -match '\./.css/') {
            $content = $content -replace '\./.css/', './_css/'
            $stats.PathFixes++
            $modified = $true
        }
        
        # .templates -> _templates
        if ($content -match '\./.templates/') {
            $content = $content -replace '\./.templates/', './_templates/'
            $stats.PathFixes++
            $modified = $true
        }
        
        # === FIX 2: Mermaid ER diagram multi-word types ===
        # Only apply to files that have mermaid ER diagrams
        if ($content -match '<pre class="mermaid"[^>]*>[\s\S]*?erDiagram') {
            
            # Fix LONG VARCHAR -> LONGVARCHAR (and similar multi-word types)
            if ($content -match 'LONG VARCHAR') {
                $content = $content -replace 'LONG VARCHAR', 'LONGVARCHAR'
                $stats.MermaidFixes++
                $modified = $true
            }
            
            if ($content -match 'LONG VARGRAPHIC') {
                $content = $content -replace 'LONG VARGRAPHIC', 'LONGVARGRAPHIC'
                $stats.MermaidFixes++
                $modified = $true
            }
            
            # Fix type length specifiers: TYPE(N) -> TYPE or TYPE(N,M) -> TYPE
            # Common DB2 types with length specifiers
            $typesWithLength = @(
                'DECIMAL', 'VARCHAR', 'CHARACTER', 'CHAR', 'NUMERIC', 
                'INTEGER', 'SMALLINT', 'BIGINT', 'FLOAT', 'DOUBLE', 'REAL',
                'LONGVARCHAR', 'VARGRAPHIC', 'GRAPHIC', 'BLOB', 'CLOB',
                'DBCLOB', 'BINARY', 'VARBINARY'
            )
            
            foreach ($typeName in $typesWithLength) {
                # Match TYPE(N) or TYPE(N,M) pattern
                $pattern = "$typeName\(\d+(?:,\d+)?\)"
                if ($content -match $pattern) {
                    $content = $content -replace $pattern, $typeName
                    $stats.MermaidFixes++
                    $modified = $true
                }
            }
        }
        
        # Save if modified
        if ($modified) {
            if ($WhatIf) {
                Write-Log "Would fix: $($file.Name)" -Level INFO
            } else {
                $content | Set-Content -Path $file.FullName -Encoding UTF8 -NoNewline
            }
            $stats.FilesModified++
        }
        
    } catch {
        Write-Log "Error processing $($file.Name): $($_.Exception.Message)" -Level ERROR
        $stats.Errors++
    }
    
    # Progress indicator every 500 files
    if ($stats.FilesProcessed % 500 -eq 0) {
        Write-Log "Progress: $($stats.FilesProcessed)/$totalFiles files processed..." -Level INFO
    }
}

# Summary
Write-Log "========================================" -Level INFO
Write-Log "AutoDoc Path Fix Complete" -Level INFO
Write-Log "========================================" -Level INFO
Write-Log "Files processed: $($stats.FilesProcessed)" -Level INFO
Write-Log "Files modified:  $($stats.FilesModified)" -Level INFO
Write-Log "Path fixes:      $($stats.PathFixes)" -Level INFO
Write-Log "Mermaid fixes:   $($stats.MermaidFixes)" -Level INFO
Write-Log "Errors:          $($stats.Errors)" -Level INFO

if ($WhatIf) {
    Write-Log "(WhatIf mode - no changes were made)" -Level WARN
}

# Return stats for programmatic use
return $stats
