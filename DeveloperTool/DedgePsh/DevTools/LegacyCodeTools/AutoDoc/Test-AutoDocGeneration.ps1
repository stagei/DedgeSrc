# Author: Geir Helge Starholm, www.dEdge.no
# Purpose: Test wrapper for AutoDocBatchRunner.ps1 - generates and validates single files
# Usage: .\Test-AutoDocGeneration.ps1 [-StartFromIndex 0]
# Non-interactive: stops on first error, logs all results to file

param(
    [int]$StartFromIndex = 0
)

$ErrorActionPreference = 'Stop'

# Configuration
$autoDocFolder = $PSScriptRoot
$outputFolder = "$env:OptPath\Webs\AutoDoc"
$extractedFolder = "$env:OptPath\data\AutoDoc\extracted"
$logFile = Join-Path $autoDocFolder "Test-AutoDocGeneration.log"

# Ensure folders exist
if (-not (Test-Path $outputFolder)) { New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null }
if (-not (Test-Path $extractedFolder)) { New-Item -ItemType Directory -Path $extractedFolder -Force | Out-Null }

# Ensure work folders exist (required by AutoDocBatchRunner.ps1 QuickRun check)
$workFolder = "$env:OptPath\data\AutoDoc\tmp\DedgeRepository"
if (-not (Test-Path $workFolder)) { New-Item -ItemType Directory -Path $workFolder -Force | Out-Null }
if (-not (Test-Path "$workFolder\Dedge")) { New-Item -ItemType Directory -Path "$workFolder\Dedge" -Force | Out-Null }
if (-not (Test-Path "$workFolder\DedgePsh")) { New-Item -ItemType Directory -Path "$workFolder\DedgePsh" -Force | Out-Null }
if (-not (Test-Path "$workFolder\ServerMonitor")) { New-Item -ItemType Directory -Path "$workFolder\ServerMonitor" -Force | Out-Null }

# Test files to process - now includes files with SQL statements
$testFiles = @()

# Find files with SQL statements for testing new SQL parsing functionality
function Find-FilesWithSqlStatements {
    param(
        [string]$SearchPath,
        [string]$FileExtension,
        [int]$MaxFiles = 10
    )
    
    $files = @()
    if (-not (Test-Path $SearchPath)) {
        Write-Host "Search path not found: $SearchPath" -ForegroundColor Yellow
        return $files
    }
    
    # Search for files containing db2 commands with SQL keywords
    # Regex pattern breakdown:
    #   (db2|db2cmd|sqlexec)     - Match db2 command prefix (capture group 1)
    #   .*?                       - Match any characters (non-greedy)
    #   (select|insert|update|delete|declare\s+cursor) - Match SQL operation keywords (capture group 2)
    $sqlPattern = '(db2|db2cmd|sqlexec).*?(select|insert|update|delete|declare\s+cursor)'
    $foundFiles = Get-ChildItem -Path $SearchPath -Filter "*.$FileExtension" -Recurse -ErrorAction SilentlyContinue | 
        Select-String -Pattern $sqlPattern -CaseSensitive:$false -List | 
        Select-Object -First $MaxFiles -ExpandProperty Path -Unique
    
    foreach ($filePath in $foundFiles) {
        $fileName = Split-Path -Leaf $filePath
        $files += @{
            Type = $FileExtension.ToUpper()
            FileName = $fileName
            FullPath = $filePath
            IsTable = $false
        }
    }
    
    Write-Host "Found $($files.Count) $FileExtension file(s) with SQL statements in $SearchPath" -ForegroundColor Cyan
    return $files
}

# Add REXX files with SQL (up to 10)
$rexPath = "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\rexx_prod"
if (-not (Test-Path $rexPath)) {
    $rexPath = "$env:OptPath\Work\DedgeRepository\Dedge\rexx_prod"
}
$rexFiles = Find-FilesWithSqlStatements -SearchPath $rexPath -FileExtension "rex" -MaxFiles 10
$testFiles += $rexFiles

# Add PS1 files with SQL (up to 10)
$ps1Path = "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\DedgePsh"
if (-not (Test-Path $ps1Path)) {
    $ps1Path = "$env:OptPath\Work\DedgeRepository\DedgePsh"
}
$ps1Files = Find-FilesWithSqlStatements -SearchPath $ps1Path -FileExtension "ps1" -MaxFiles 10
$testFiles += $ps1Files

# Add BAT files with SQL (up to 10)
$batPath = "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\bat_prod"
if (-not (Test-Path $batPath)) {
    $batPath = "$env:OptPath\Work\DedgeRepository\Dedge\bat_prod"
}
$batFiles = Find-FilesWithSqlStatements -SearchPath $batPath -FileExtension "bat" -MaxFiles 10
$testFiles += $batFiles

# Fallback: If no files found, use default test files
if ($testFiles.Count -eq 0) {
    Write-Host "No files with SQL statements found. Using default test files." -ForegroundColor Yellow
    $testFiles = @(
        @{ Type = "CBL"; FileName = "AABELMA.CBL"; FullPath = "$env:OptPath\Work\DedgeRepository\Dedge\cbl\AABELMA.CBL"; IsTable = $false }
        @{ Type = "REX"; FileName = "WKMONIT.REX"; FullPath = "$env:OptPath\Work\DedgeRepository\Dedge\rexx_prod\WKMONIT.REX"; IsTable = $false }
        @{ Type = "BAT"; FileName = "Catalog-All-Db2-Azure-Databases-Using-Kerberos-For-Db2Client.bat"; FullPath = "$env:OptPath\Work\DedgeRepository\Dedge\bat_prod\Catalog-All-Db2-Azure-Databases-Using-Kerberos-For-Db2Client.bat"; IsTable = $false }
        @{ Type = "PS1"; FileName = "Db2-CreateInitialDatabases.ps1"; FullPath = "$env:OptPath\Work\DedgeRepository\DedgePsh\DevTools\DatabaseTools\Db2-CreateInitialDatabases\Db2-CreateInitialDatabases.ps1"; IsTable = $false }
        @{ Type = "SQL"; FileName = "DBM.AH_ORDREHODE"; FullPath = $null; IsTable = $true }
        @{ Type = "SQL"; FileName = "DBM.AH_ORDRELINJER"; FullPath = $null; IsTable = $true }
        @{ Type = "CSHARP"; FileName = "ServerMonitor.sln"; FullPath = "$env:OptPath\Work\DedgeRepository\ServerMonitor\ServerMonitorAgent\ServerMonitor.sln"; IsTable = $false }
    )
}

# Initialize test results tracking
$testResults = @{
    StartTime       = Get-Date
    EndTime         = $null
    StartFromIndex  = $StartFromIndex
    LastIndex       = -1
    TotalFiles      = $testFiles.Count
    SuccessCount    = 0
    FailedCount     = 0
    Status          = "Running"
    Error           = $null
    FileResults     = @()
}

function Write-TestLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    
    $color = switch ($Level) {
        "OK" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Write-TestHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    Write-TestLog $Message
}

function Save-TestResults {
    $testResults.EndTime = Get-Date
    $duration = $testResults.EndTime - $testResults.StartTime
    
    $resultsJson = $testResults | ConvertTo-Json -Depth 5
    $resultsFile = Join-Path $autoDocFolder "Test-AutoDocGeneration.results.json"
    Set-Content -Path $resultsFile -Value $resultsJson -Encoding UTF8
    
    # Write summary to log
    Write-TestLog "============================================"
    Write-TestLog "TEST RESULTS SUMMARY"
    Write-TestLog "============================================"
    Write-TestLog "Status: $($testResults.Status)"
    Write-TestLog "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-TestLog "Last processed index: $($testResults.LastIndex)"
    Write-TestLog "Total files: $($testResults.TotalFiles)"
    Write-TestLog "Successful: $($testResults.SuccessCount)"
    Write-TestLog "Failed: $($testResults.FailedCount)"
    if ($testResults.Error) {
        Write-TestLog "Error: $($testResults.Error)" -Level "ERROR"
    }
    Write-TestLog "Results saved to: $resultsFile"
    Write-TestLog "============================================"
}

function Get-ExpectedHtmlPath {
    param($TestFile)
    
    $fileName = $TestFile.FileName
    $type = $TestFile.Type
    
    switch ($type) {
        "CBL" { return Join-Path $outputFolder "$fileName.html" }
        "REX" { return Join-Path $outputFolder "$fileName.html" }
        "BAT" { return Join-Path $outputFolder "$fileName.html" }
        "PS1" { return Join-Path $outputFolder "$fileName.html" }
        "SQL" { 
            $safeName = $fileName.Replace(".", "_").ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower()
            return Join-Path $outputFolder "$safeName.sql.html"
        }
        "CSHARP" { 
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            return Join-Path $outputFolder "$baseName.csharp.html"
        }
    }
}

function Invoke-AutoDocGeneration {
    param($TestFile)
    
    Write-TestLog "Running AutoDocBatchRunner.ps1 for $($TestFile.FileName)..."
    
    $params = @{
        Regenerate   = "Single"
        SaveMmdFiles = $true
        Parallel     = $false
    }
    
    # Only set QuickRun for subsequent files (skip git clone after first file)
    if ($script:currentIndex -gt 0) {
        $params.QuickRun = $true
    }
    
    if ($TestFile.IsTable) {
        $params.SingleFile = $TestFile.FileName
    }
    else {
        $params.SingleFile = $TestFile.FullPath
    }
    
    Push-Location $autoDocFolder
    & ".\AutoDocBatchRunner.ps1" @params
    $exitCode = $LASTEXITCODE
    Pop-Location
    
    if ($exitCode -ne 0 -and $null -ne $exitCode) {
        throw "AutoDocBatchRunner.ps1 exited with code $exitCode"
    }
    
    return $true
}

function Test-HtmlValidation {
    param([string]$HtmlPath)
    
    $results = @{
        CssIncluded   = $false
        IconIncluded  = $false
        ImageIncluded = $false
        AllPassed     = $false
    }
    
    if (-not (Test-Path $HtmlPath)) {
        Write-TestLog "HTML file not found: $HtmlPath" -Level "FAIL"
        return $results
    }
    
    $htmlContent = Get-Content $HtmlPath -Raw
    
    # Check for CSS
    if ($htmlContent -match 'autodoc-shared\.css' -or $htmlContent -match ':root\s*\{' -or $htmlContent -match '--bg-primary') {
        $results.CssIncluded = $true
        Write-TestLog "CSS styles included" -Level "OK"
    }
    else {
        Write-TestLog "CSS styles NOT found" -Level "FAIL"
    }
    
    # Check for favicon/icon
    if ($htmlContent -match 'rel="icon"' -or $htmlContent -match 'favicon' -or $htmlContent -match 'fk\.ico') {
        $results.IconIncluded = $true
        Write-TestLog "Favicon/icon reference included" -Level "OK"
    }
    else {
        Write-TestLog "Favicon/icon reference NOT found" -Level "WARN"
    }
    
    # Check for logo image
    if ($htmlContent -match 'fk\.svg' -or $htmlContent -match 'logo' -or $htmlContent -match '<img.*src=') {
        $results.ImageIncluded = $true
        Write-TestLog "Logo/image reference included" -Level "OK"
    }
    else {
        Write-TestLog "Logo/image reference NOT found" -Level "WARN"
    }
    
    # Check for Mermaid content
    if ($htmlContent -match 'class="mermaid"' -or $htmlContent -match '<div class="mermaid">') {
        Write-TestLog "Mermaid diagram content found" -Level "OK"
    }
    else {
        Write-TestLog "No Mermaid diagram content" -Level "WARN"
    }
    
    $results.AllPassed = $results.CssIncluded -and $results.IconIncluded -and $results.ImageIncluded
    return $results
}

function Get-MermaidContent {
    param([string]$HtmlPath, [string]$OutputFolder)
    
    $htmlContent = Get-Content $HtmlPath -Raw
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($HtmlPath)
    
    $mermaidPattern = '(?s)<div[^>]*class="mermaid"[^>]*>(.*?)</div>'
    $mermaidMatches = [regex]::Matches($htmlContent, $mermaidPattern)
    
    $extractedFiles = @()
    $index = 0
    
    foreach ($match in $mermaidMatches) {
        $mmdContent = $match.Groups[1].Value.Trim()
        
        if ([string]::IsNullOrWhiteSpace($mmdContent) -or $mmdContent -match '^\[.*\]$') {
            continue
        }
        
        # Clean up HTML entities
        $mmdContent = $mmdContent -replace '&lt;', '<'
        $mmdContent = $mmdContent -replace '&gt;', '>'
        $mmdContent = $mmdContent -replace '&amp;', '&'
        $mmdContent = $mmdContent -replace '&quot;', '"'
        $mmdContent = $mmdContent -replace '&#39;', "'"
        
        $mmdFileName = "${baseName}_diagram${index}.extracted.mmd"
        $mmdPath = Join-Path $OutputFolder $mmdFileName
        
        Set-Content -Path $mmdPath -Value $mmdContent -Encoding UTF8
        $extractedFiles += $mmdPath
        $index++
        
        Write-TestLog "Extracted: $mmdFileName" -Level "OK"
    }
    
    if ($extractedFiles.Count -eq 0) {
        Write-TestLog "No Mermaid diagrams extracted (may be client-side rendered)" -Level "WARN"
    }
    
    return $extractedFiles
}

function Test-MermaidConversion {
    param([string]$MmdPath)
    
    $svgPath = $MmdPath -replace '\.mmd$', '.svg'
    
    Write-TestLog "Converting to SVG: $([System.IO.Path]::GetFileName($MmdPath))..."
    
    $mmdcPath = Get-Command "mmdc" -ErrorAction SilentlyContinue
    if (-not $mmdcPath) {
        $mmdcPath = Get-Command "mmdc.cmd" -ErrorAction SilentlyContinue
    }
    
    if (-not $mmdcPath) {
        Write-TestLog "mmdc not found in PATH - skipping SVG conversion" -Level "WARN"
        return $null
    }
    
    & mmdc -i $MmdPath -o $svgPath 2>&1 | Out-Null
    
    if (Test-Path $svgPath) {
        Write-TestLog "SVG created: $([System.IO.Path]::GetFileName($svgPath))" -Level "OK"
        return $svgPath
    }
    else {
        throw "SVG conversion failed - no output file created"
    }
}

function Open-InBrowser {
    param([string]$FilePath)
    
    if (Test-Path $FilePath) {
        Start-Process "msedge" -ArgumentList $FilePath
        Write-TestLog "Opened in Edge: $([System.IO.Path]::GetFileName($FilePath))" -Level "OK"
    }
    else {
        Write-TestLog "File not found for browser: $FilePath" -Level "WARN"
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Start fresh log
$logHeader = @"
================================================================================
 AutoDoc Generation Test Suite
 Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
 StartFromIndex: $StartFromIndex
================================================================================
"@
Set-Content -Path $logFile -Value $logHeader -Encoding UTF8

Write-TestHeader "AutoDoc Generation Test Suite"
Write-TestLog "Output folder: $outputFolder"
Write-TestLog "Extracted folder: $extractedFolder"
Write-TestLog "Files to test: $($testFiles.Count)"
Write-TestLog "Starting from index: $StartFromIndex"

try {
    for ($i = $StartFromIndex; $i -lt $testFiles.Count; $i++) {
        $testFile = $testFiles[$i]
        $testResults.LastIndex = $i
        $script:currentIndex = $i  # Track for SkipGitClone logic
        
        $fileResult = @{
            Index      = $i
            Type       = $testFile.Type
            FileName   = $testFile.FileName
            Status     = "Running"
            HtmlPath   = $null
            MmdCount   = 0
            SvgCount   = 0
            Error      = $null
        }
        
        Write-TestHeader "[$($i + 1)/$($testFiles.Count)] Testing: $($testFile.Type) - $($testFile.FileName)"
        
        # Step 1: Generate
        Write-TestLog "STEP 1: Generation"
        $generated = Invoke-AutoDocGeneration -TestFile $testFile
        
        if (-not $generated) {
            throw "Generation failed for $($testFile.FileName)"
        }
        
        # Step 2: Find and validate HTML
        Write-TestLog "STEP 2: HTML Validation"
        $htmlPath = Get-ExpectedHtmlPath -TestFile $testFile
        $fileResult.HtmlPath = $htmlPath
        
        if (-not (Test-Path $htmlPath)) {
            Write-TestLog "Expected HTML not found: $htmlPath" -Level "WARN"
            
            # Try to find any matching HTML
            $possibleFiles = Get-ChildItem -Path $outputFolder -Filter "*$($testFile.FileName)*.html" -ErrorAction SilentlyContinue
            if ($possibleFiles) {
                Write-TestLog "Found possible match: $($possibleFiles[0].Name)"
                $htmlPath = $possibleFiles[0].FullName
                $fileResult.HtmlPath = $htmlPath
            }
            else {
                throw "HTML file not found for $($testFile.FileName)"
            }
        }
        
        $validation = Test-HtmlValidation -HtmlPath $htmlPath
        
        if (-not $validation.CssIncluded) {
            throw "CSS validation failed for $($testFile.FileName)"
        }
        
        # Step 3: Open in browser
        Write-TestLog "STEP 3: Browser Preview"
        Open-InBrowser -FilePath $htmlPath
        
        # Step 4: Extract and convert Mermaid (skip for SQL)
        if ($testFile.Type -eq "SQL") {
            Write-TestLog "STEP 4: Mermaid Extraction (SKIPPED for SQL)"
        }
        else {
            Write-TestLog "STEP 4: Mermaid Extraction & Conversion"
            $mmdFiles = Get-MermaidContent -HtmlPath $htmlPath -OutputFolder $extractedFolder
            $fileResult.MmdCount = $mmdFiles.Count
            
            foreach ($mmdFile in $mmdFiles) {
                $svgPath = Test-MermaidConversion -MmdPath $mmdFile
                if ($svgPath) {
                    $fileResult.SvgCount++
                    Open-InBrowser -FilePath $svgPath
                }
            }
        }
        
        # Mark file as successful
        $fileResult.Status = "Success"
        $testResults.SuccessCount++
        $testResults.FileResults += $fileResult
        
        # Auto-continue in non-interactive mode
        Write-TestLog "Auto-continuing to next file (non-interactive mode)" -Level "INFO"
        Write-TestLog "COMPLETED: $($testFile.FileName)" -Level "OK"
    }
    
    # All tests passed
    $testResults.Status = "Success"
    Write-TestLog "ALL TESTS PASSED!" -Level "OK"
    Save-TestResults
    exit 0
}
catch {
    # Error occurred - stop immediately
    $testResults.Status = "Failed"
    $testResults.FailedCount++
    $testResults.Error = $_.Exception.Message
    
    if ($fileResult) {
        $fileResult.Status = "Failed"
        $fileResult.Error = $_.Exception.Message
        $testResults.FileResults += $fileResult
    }
    
    Write-TestLog "FATAL ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-TestLog "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-TestLog "To resume, run: .\Test-AutoDocGeneration.ps1 -StartFromIndex $($testResults.LastIndex)" -Level "INFO"
    
    Save-TestResults
    exit 1
}
