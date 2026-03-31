# Generate delete statements for AutoDoc output files that contain SQL statements
# Only files with SQL in source will be deleted (since those are affected by the code changes)

param(
    [string]$ServerWebsPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc",
    [string]$LocalRepoPath = "$env:OptPath\data\AutoDoc\tmp\DedgeRepository",
    [string]$OutputFile = "$PSScriptRoot\DeleteSqlFiles.ps1"
)

Import-Module GlobalFunctions -Force

Write-LogMessage "Scanning for files with SQL statements..." -Level INFO

# Fallback paths if tmp folder doesn't exist
if (-not (Test-Path $LocalRepoPath)) {
    $LocalRepoPath = "$env:OptPath\Work\DedgeRepository"
}

$batPath = Join-Path $LocalRepoPath "Dedge\bat_prod"
$ps1Path = Join-Path $LocalRepoPath "DedgePsh"
$rexPath = Join-Path $LocalRepoPath "Dedge\rexx_prod"

$deleteStatements = @()
$fileCount = 0

# SQL pattern to detect SQL statements in db2 commands
$sqlPattern = '(db2|db2cmd|sqlexec|''db2).*?(select|insert|update|delete|declare\s+cursor)'

function Find-FilesWithSql {
    param(
        [string]$SearchPath,
        [string]$FileExtension,
        [string]$TypeName
    )
    
    $files = @()
    if (-not (Test-Path $SearchPath)) {
        Write-LogMessage "Path not found: $SearchPath" -Level WARN
        return $files
    }
    
    $foundFiles = Get-ChildItem -Path $SearchPath -Filter "*.$FileExtension" -Recurse -ErrorAction SilentlyContinue | 
        Select-String -Pattern $sqlPattern -CaseSensitive:$false -List | 
        Select-Object -ExpandProperty Path -Unique
    
    foreach ($filePath in $foundFiles) {
        $fileName = Split-Path -Leaf $filePath
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        
        # Generate delete statements for HTML and MMD files
        $htmlFile = Join-Path $ServerWebsPath "$fileName.html"
        $mmdFile = Join-Path $ServerWebsPath "$fileName.mmd"
        
        $files += @{
            Type = $TypeName
            SourceFile = $fileName
            HtmlPath = $htmlFile
            MmdPath = $mmdFile
        }
    }
    
    return $files
}

# Find BAT files with SQL
Write-LogMessage "Scanning BAT files..." -Level INFO
$batFiles = Find-FilesWithSql -SearchPath $batPath -FileExtension "bat" -TypeName "BAT"
Write-LogMessage "Found $($batFiles.Count) BAT files with SQL statements" -Level INFO

# Find PS1 files with SQL
Write-LogMessage "Scanning PS1 files..." -Level INFO
$ps1Files = Find-FilesWithSql -SearchPath $ps1Path -FileExtension "ps1" -TypeName "PS1"
Write-LogMessage "Found $($ps1Files.Count) PS1 files with SQL statements" -Level INFO

# Find REXX files with SQL
Write-LogMessage "Scanning REXX files..." -Level INFO
$rexFiles = Find-FilesWithSql -SearchPath $rexPath -FileExtension "rex" -TypeName "REX"
Write-LogMessage "Found $($rexFiles.Count) REXX files with SQL statements" -Level INFO

# Generate delete statements
$deleteStatements += "# Auto-generated delete statements for files with SQL statements"
$deleteStatements += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$deleteStatements += "# Server path: $ServerWebsPath"
$deleteStatements += ""
$deleteStatements += "`$ServerWebsPath = '$ServerWebsPath'"
$deleteStatements += "`$deletedCount = 0"
$deleteStatements += "`$errorCount = 0"
$deleteStatements += ""

$allFiles = $batFiles + $ps1Files + $rexFiles
$fileCount = $allFiles.Count

foreach ($file in $allFiles) {
    $deleteStatements += "# $($file.Type): $($file.SourceFile)"
    
    # Delete HTML file
    $deleteStatements += "if (Test-Path '$($file.HtmlPath)') {"
    $deleteStatements += "    try {"
    $deleteStatements += "        Remove-Item '$($file.HtmlPath)' -Force -ErrorAction Stop"
    $deleteStatements += "        `$deletedCount++"
    $deleteStatements += "        Write-Host 'Deleted: $($file.SourceFile).html'"
    $deleteStatements += "    } catch {"
    $deleteStatements += "        Write-Host 'Error deleting $($file.SourceFile).html: ' + `$_.Exception.Message -ForegroundColor Red"
    $deleteStatements += "        `$errorCount++"
    $deleteStatements += "    }"
    $deleteStatements += "}"
    
    # Delete MMD file
    $deleteStatements += "if (Test-Path '$($file.MmdPath)') {"
    $deleteStatements += "    try {"
    $deleteStatements += "        Remove-Item '$($file.MmdPath)' -Force -ErrorAction Stop"
    $deleteStatements += "        `$deletedCount++"
    $deleteStatements += "        Write-Host 'Deleted: $($file.SourceFile).mmd'"
    $deleteStatements += "    } catch {"
    $deleteStatements += "        Write-Host 'Error deleting $($file.SourceFile).mmd: ' + `$_.Exception.Message -ForegroundColor Red"
    $deleteStatements += "        `$errorCount++"
    $deleteStatements += "    }"
    $deleteStatements += "}"
    
    $deleteStatements += ""
}

# Add summary
$deleteStatements += "Write-Host ''"
$deleteStatements += "Write-Host '============================================' -ForegroundColor Cyan"
$deleteStatements += 'Write-Host "Summary: Deleted $deletedCount files, $errorCount errors" -ForegroundColor Cyan'
$deleteStatements += "Write-Host '============================================' -ForegroundColor Cyan"

# Write to output file
$deleteStatements | Set-Content -Path $OutputFile -Encoding UTF8

Write-LogMessage "============================================" -Level INFO
Write-LogMessage "Generated delete statements for $fileCount files with SQL" -Level INFO
Write-LogMessage "Output file: $OutputFile" -Level INFO
Write-LogMessage "  - BAT files: $($batFiles.Count)" -Level INFO
Write-LogMessage "  - PS1 files: $($ps1Files.Count)" -Level INFO
Write-LogMessage "  - REXX files: $($rexFiles.Count)" -Level INFO
Write-LogMessage "============================================" -Level INFO
