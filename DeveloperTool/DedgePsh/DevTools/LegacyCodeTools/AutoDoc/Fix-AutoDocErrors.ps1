# Author: Geir Helge Starholm, Dedge AS
# Title: AutoDoc Error Fix Script
# Description: Extracts parsing errors from AutoDoc server logs, runs local single-file parsing,
#              uses AI to analyze and fix parsing issues, then retests until errors are resolved.

param(
    # Server path where error files are located
    [string]$ServerErrorPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc",
    
    # Server webs folder where HTML files are generated (same as ServerErrorPath)
    [string]$ServerWebsPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc",
    
    # Server log path for progress tracking
    [string]$ServerLogPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\AutoDoc",
    
    # Local output folder for testing
    [string]$LocalOutputFolder = "$env:OptPath\Webs\AutoDoc",
    
    # AutoDocBatchRunner script path
    [string]$AutoDocBatchRunnerPath = "$PSScriptRoot\AutoDocBatchRunner.ps1",
    
    # Skip user confirmation (for automated runs)
    [switch]$SkipConfirmation = $false,
    
    # Maximum number of errors to process (0 = unlimited)
    [int]$MaxErrors = 0,
    
    # Continue processing even if a fix fails
    [switch]$ContinueOnFailure = $false,
    
    # Resume from last saved progress state
    [switch]$ResumeFromProgress = $false
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name AutodocFunctions -Force

#region Error Extraction Functions

function Get-AutoDocErrors {
    <#
    .SYNOPSIS
        Extracts error filenames and details from .err files on the server.
    .DESCRIPTION
        Reads all .err files from the server output folder and parses their content
        to extract parser type, source file/table, and error details.
    .OUTPUTS
        Array of PSCustomObject with properties:
        - ErrorFileName: Name of the .err file
        - ParserType: CBL, REX, BAT, PS1, or SQL
        - SourceFile: Full path to source file (null for SQL)
        - TableName: SQL table name (null for file-based parsers)
        - ErrorMessage: Error message from the error file
        - StackTrace: Stack trace from the error file
        - ErrorFilePath: Full path to the error file
    #>
    param(
        [string]$ErrorPath = $ServerErrorPath
    )
    
    Write-LogMessage "Reading error files from: $ErrorPath" -Level INFO
    
    if (-not (Test-Path $ErrorPath -PathType Container)) {
        Write-LogMessage "Error path does not exist: $ErrorPath" -Level ERROR
        return @()
    }
    
    $errorFiles = Get-ChildItem -Path $ErrorPath -Filter "*.err" -ErrorAction SilentlyContinue
    
    if ($errorFiles.Count -eq 0) {
        Write-LogMessage "No error files found in $ErrorPath" -Level INFO
        return @()
    }
    
    Write-LogMessage "Found $($errorFiles.Count) error file(s)" -Level INFO
    
    $errors = @()
    
    foreach ($errFile in $errorFiles) {
        try {
            $content = Get-Content -Path $errFile.FullName -Raw -ErrorAction Stop
            
            # Parse error file content
            $parserType = $null
            $sourceFile = $null
            $tableName = $null
            $errorMessage = $null
            $errorStackTrace = $null
            
            # Extract ParserType
            if ($content -match 'ParserType:\s*(\w+)') {
                $parserType = $Matches[1]
            }
            
            # Extract File path
            if ($content -match 'File:\s*(.+?)(?:\r?\n|$)') {
                $fileMatch = $Matches[1].Trim()
                if ($fileMatch -ne "null" -and $fileMatch -ne "") {
                    $sourceFile = $fileMatch
                }
            }
            
            # Extract Table name
            if ($content -match 'Table:\s*(.+?)(?:\r?\n|$)') {
                $tableMatch = $Matches[1].Trim()
                if ($tableMatch -ne "null" -and $tableMatch -ne "") {
                    $tableName = $tableMatch
                }
            }
            
            # Extract Error message
            if ($content -match 'Error:\s*(.+?)(?:\r?\nStack:|$)') {
                $errorMessage = $Matches[1].Trim()
            }
            
            # Extract Stack trace
            if ($content -match 'Stack:\s*(.+)') {
                $errorStackTrace = $Matches[1].Trim()
            }
            
            # If parser type not found, try to infer from filename
            if (-not $parserType) {
                if ($errFile.Name -match '\.sql\.err$') {
                    $parserType = "SQL"
                }
                elseif ($errFile.Name -match '\.(cbl|rex|bat|ps1)\.err$') {
                    $parserType = $Matches[1].ToUpper()
                    if ($parserType -eq "CBL") { $parserType = "CBL" }
                    elseif ($parserType -eq "REX") { $parserType = "REX" }
                    elseif ($parserType -eq "BAT") { $parserType = "BAT" }
                    elseif ($parserType -eq "PS1") { $parserType = "PS1" }
                }
            }
            
            # If source file not found, try to infer from error filename
            if (-not $sourceFile -and $parserType -ne "SQL") {
                $baseName = $errFile.BaseName
                # Remove .sql suffix if present
                $baseName = $baseName -replace '\.sql$', ''
                
                # Try to find source file in common locations
                $extensions = @{
                    "CBL" = ".cbl"
                    "REX" = ".rex"
                    "BAT" = ".bat"
                    "PS1" = ".ps1"
                }
                
                if ($extensions.ContainsKey($parserType)) {
                    $ext = $extensions[$parserType]
                    $possiblePaths = @(
                        "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\cbl\$baseName$ext",
                        "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\rexx_prod\$baseName$ext",
                        "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\bat_prod\$baseName$ext",
                        "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\DedgePsh\$baseName$ext"
                    )
                    
                    foreach ($path in $possiblePaths) {
                        if (Test-Path $path) {
                            $sourceFile = $path
                            break
                        }
                    }
                }
            }
            
            # If table name not found for SQL, infer from filename
            if (-not $tableName -and $parserType -eq "SQL") {
                $baseName = $errFile.BaseName -replace '\.sql$', ''
                # Convert SCHEMA_TABLENAME to SCHEMA.TABLENAME
                $tableName = $baseName.Replace("_", ".")
            }
            
            $errorObj = [PSCustomObject]@{
                ErrorFileName = $errFile.Name
                ParserType    = $parserType
                SourceFile    = $sourceFile
                TableName     = $tableName
                ErrorMessage  = $errorMessage
                StackTrace    = $errorStackTrace
                ErrorFilePath = $errFile.FullName
            }
            
            $errors += $errorObj
        }
        catch {
            Write-LogMessage "Failed to parse error file $($errFile.Name): $($_.Exception.Message)" -Level WARN
        }
    }
    
    Write-LogMessage "Extracted $($errors.Count) error(s) from error files" -Level INFO
    return $errors
}

#endregion

#region Single File Parsing Functions

function Invoke-SingleFileParse {
    <#
    .SYNOPSIS
        Runs AutoDocBatchRunner in single file mode for a specific file or table.
    .DESCRIPTION
        Executes AutoDocBatchRunner.ps1 with -SingleFile parameter to parse
        a single file or SQL table locally.
    .PARAMETER ErrorInfo
        Error object containing parser type and source file/table information.
    .OUTPUTS
        PSCustomObject with properties:
        - Success: Boolean indicating if parsing succeeded
        - LogFile: Path to the log file
        - LogContent: Content of the log file
        - ErrorFile: Path to error file if parsing failed
        - OutputFile: Path to generated HTML file if successful
    #>
    param(
        [PSCustomObject]$ErrorInfo
    )
    
    Write-LogMessage "Parsing single file/table: $($ErrorInfo.ErrorFileName)" -Level INFO
    
    $singleFileParam = $null
    
    # Determine the single file parameter based on parser type
    if ($ErrorInfo.ParserType -eq "SQL") {
        if ($ErrorInfo.TableName) {
            $singleFileParam = $ErrorInfo.TableName
        }
        else {
            Write-LogMessage "No table name found for SQL error" -Level ERROR
            return $null
        }
    }
    else {
        if ($ErrorInfo.SourceFile -and (Test-Path $ErrorInfo.SourceFile)) {
            $singleFileParam = $ErrorInfo.SourceFile
        }
        elseif ($ErrorInfo.SourceFile) {
            # Try to find file by name in common locations
            $fileName = Split-Path -Leaf $ErrorInfo.SourceFile
            $possiblePaths = @(
                "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\cbl\$fileName",
                "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\rexx_prod\$fileName",
                "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\Dedge\bat_prod\$fileName",
                "$env:OptPath\data\AutoDoc\tmp\DedgeRepository\DedgePsh\$fileName"
            )
            
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $singleFileParam = $path
                    break
                }
            }
        }
        
        if (-not $singleFileParam) {
            Write-LogMessage "Could not find source file for $($ErrorInfo.ErrorFileName)" -Level ERROR
            return $null
        }
    }
    
    Write-LogMessage "Using single file parameter: $singleFileParam" -Level INFO
    
    # Get today's log file path
    $logDate = Get-Date -Format "yyyyMMdd"
    $logFile = Join-Path "$env:OptPath\data\AutoDoc" "FkLog_$logDate.log"
    
    # Clear any existing error file for this item
    $errorFileName = $ErrorInfo.ErrorFileName
    $localErrorFile = Join-Path $LocalOutputFolder $errorFileName
    if (Test-Path $localErrorFile) {
        Remove-Item $localErrorFile -Force -ErrorAction SilentlyContinue
    }
    
    # Run AutoDocBatchRunner in single file mode
    try {
        # Use direct script invocation with & operator to properly handle boolean parameters
        # Run in a job to capture output and exit code
        $job = Start-Job -ScriptBlock {
            param($ScriptPath, $SingleFile, $OutputFolder)
            & $ScriptPath -Regenerate Single -SingleFile $SingleFile -OutputFolder $OutputFolder -UseRamDisk:$false -QuickRun:$true 2>&1 | Out-Null
        } -ArgumentList $AutoDocBatchRunnerPath, $singleFileParam, $LocalOutputFolder
        
        # Wait for job to complete (with timeout)
        $job | Wait-Job -Timeout 300 | Out-Null
        
        # Get exit code
        $exitCode = if ($job.State -eq "Completed") { 0 } else { 1 }
        
        # Clean up job output
        $job | Receive-Job | Out-Null
        
        # Stop and remove job
        $job | Stop-Job -ErrorAction SilentlyContinue
        $job | Remove-Job -ErrorAction SilentlyContinue
        
        # Create a dummy process object for compatibility
        $process = [PSCustomObject]@{
            ExitCode = $exitCode
        }
        
        # Wait a moment for log file to be written
        Start-Sleep -Seconds 2
        
        # Read log file content
        $logContent = ""
        if (Test-Path $logFile) {
            $logContent = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        }
        
        # Check if error file was created
        $errorExists = Test-Path $localErrorFile
        
        # Check if HTML output was created
        $outputFile = $null
        if ($ErrorInfo.ParserType -eq "SQL") {
            $tableNameForFile = $ErrorInfo.TableName.Replace(".", "_")
            $outputFile = Join-Path $LocalOutputFolder "$tableNameForFile.sql.html"
        }
        else {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($singleFileParam)
            $ext = [System.IO.Path]::GetExtension($singleFileParam)
            $outputFile = Join-Path $LocalOutputFolder "$baseName$ext.html"
        }
        
        $outputExists = Test-Path $outputFile
        
        $result = [PSCustomObject]@{
            Success     = $outputExists -and -not $errorExists
            LogFile     = $logFile
            LogContent  = $logContent
            ErrorFile   = if ($errorExists) { $localErrorFile } else { $null }
            OutputFile  = if ($outputExists) { $outputFile } else { $null }
            ExitCode    = $process.ExitCode
        }
        
        return $result
    }
    catch {
        Write-LogMessage "Failed to run single file parse: $($_.Exception.Message)" -Level ERROR
        return [PSCustomObject]@{
            Success    = $false
            LogFile    = $logFile
            LogContent = ""
            ErrorFile  = $null
            OutputFile = $null
            ExitCode   = -1
        }
    }
}

#endregion

#region Error Analysis Functions

function Get-ParseErrorDetails {
    <#
    .SYNOPSIS
        Analyzes log file content to extract detailed error information.
    .DESCRIPTION
        Parses the log file content to find error messages, stack traces,
        and identifies the parser function and line numbers where errors occurred.
    .PARAMETER LogContent
        Content of the log file to analyze.
    .PARAMETER ErrorInfo
        Original error information object.
    .OUTPUTS
        PSCustomObject with detailed error analysis including:
        - ErrorLines: Array of error log lines
        - FunctionName: Name of the function where error occurred
        - LineNumber: Line number where error occurred
        - ErrorPattern: Pattern of the error for searching in code
    #>
    param(
        [string]$LogContent,
        [PSCustomObject]$ErrorInfo
    )
    
    $errorLines = @()
    $functionName = $null
    $lineNumber = $null
    
    if ([string]::IsNullOrEmpty($LogContent)) {
        return [PSCustomObject]@{
            ErrorLines   = @()
            FunctionName = $null
            LineNumber   = $null
            ErrorPattern = $ErrorInfo.ErrorMessage
        }
    }
    
    # Extract ERROR level log lines
    $lines = $LogContent -split "`r?`n"
    foreach ($line in $lines) {
        if ($line -match '\|ERROR\|' -or $line -match '\|WARN\|') {
            $errorLines += $line
        }
    }
    
    # Try to extract function name and line number from stack trace
    if ($ErrorInfo.StackTrace) {
        # Look for function name pattern: at <function>, <file>:line <number>
        if ($ErrorInfo.StackTrace -match 'at\s+([^,]+),\s+([^:]+):line\s+(\d+)') {
            $functionName = $Matches[1].Trim()
            $lineNumber = [int]$Matches[3]
        }
        # Alternative pattern: at <function> in <file>:line <number>
        elseif ($ErrorInfo.StackTrace -match 'at\s+([^\s]+)\s+in\s+([^:]+):line\s+(\d+)') {
            $functionName = $Matches[1].Trim()
            $lineNumber = [int]$Matches[3]
        }
    }
    
    # Try to extract from log content if not found in stack trace
    if (-not $functionName) {
        foreach ($line in $errorLines) {
            if ($line -match 'at\s+([^,]+),\s+([^:]+):line\s+(\d+)') {
                $functionName = $Matches[1].Trim()
                $lineNumber = [int]$Matches[3]
                break
            }
        }
    }
    
    # Extract error pattern for code search
    $errorPattern = $ErrorInfo.ErrorMessage
    if ([string]::IsNullOrEmpty($errorPattern) -and $errorLines.Count -gt 0) {
        # Try to extract from last error line
        $lastError = $errorLines[-1]
        if ($lastError -match 'ERROR\|(.+)$') {
            $errorPattern = $Matches[1].Trim()
        }
    }
    
    return [PSCustomObject]@{
        ErrorLines   = $errorLines
        FunctionName = $functionName
        LineNumber   = $lineNumber
        ErrorPattern = $errorPattern
    }
}

#endregion

#region AI Fix Functions

function Invoke-AIFix {
    <#
    .SYNOPSIS
        Uses AI to analyze error and fix parsing code.
    .DESCRIPTION
        Searches codebase for relevant parser code, analyzes the error context,
        and applies fixes to resolve parsing issues.
    .PARAMETER ErrorInfo
        Error information object.
    .PARAMETER ErrorDetails
        Detailed error analysis from Get-ParseErrorDetails.
    .PARAMETER ParseResult
        Result from Invoke-SingleFileParse.
    .OUTPUTS
        Boolean indicating if fix was applied successfully.
    #>
    param(
        [PSCustomObject]$ErrorInfo,
        [PSCustomObject]$ErrorDetails,
        [PSCustomObject]$ParseResult
    )
    
    Write-LogMessage "=== AI FIX REQUEST ===" -Level INFO
    
    # Get parser module path
    $parserModulePath = (Get-Module -Name AutodocFunctions -ListAvailable | Select-Object -First 1).Path
    
    if (-not $parserModulePath -or -not (Test-Path $parserModulePath)) {
        Write-LogMessage "Could not find AutodocFunctions module" -Level ERROR
        return $false
    }
    
    # Determine parser function name
    $parserFunctionName = switch ($ErrorInfo.ParserType) {
        "CBL" { "Start-CblParse" }
        "REX" { "Start-RexParse" }
        "BAT" { "Start-BatParse" }
        "PS1" { "Start-Ps1Parse" }
        "SQL" { "Start-SqlParse" }
        default { $null }
    }
    
    if (-not $parserFunctionName) {
        Write-LogMessage "Unknown parser type: $($ErrorInfo.ParserType)" -Level ERROR
        return $false
    }
    
    # Create error summary file for AI analysis
    $errorSummaryFile = Join-Path $env:TEMP "AutoDocError_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $errorSummary = @{
        ErrorFileName    = $ErrorInfo.ErrorFileName
        ParserType       = $ErrorInfo.ParserType
        ParserFunction   = $parserFunctionName
        SourceFile       = $ErrorInfo.SourceFile
        TableName        = $ErrorInfo.TableName
        ErrorMessage     = $ErrorInfo.ErrorMessage
        StackTrace       = $ErrorInfo.StackTrace
        FunctionName     = $ErrorDetails.FunctionName
        LineNumber       = $ErrorDetails.LineNumber
        ErrorPattern     = $ErrorDetails.ErrorPattern
        ErrorLines       = $ErrorDetails.ErrorLines
        ParserModulePath = $parserModulePath
        LogFile          = $ParseResult.LogFile
        LogContent       = $ParseResult.LogContent
        LocalErrorFile   = $ParseResult.ErrorFile
    }
    
    $errorSummary | ConvertTo-Json -Depth 10 | Set-Content -Path $errorSummaryFile -Encoding UTF8
    Write-LogMessage "Error summary saved to: $errorSummaryFile" -Level INFO
    
    # Display comprehensive error information
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR ANALYSIS FOR AI FIX" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error File: $($ErrorInfo.ErrorFileName)" -ForegroundColor Yellow
    Write-Host "Parser Type: $($ErrorInfo.ParserType)" -ForegroundColor Cyan
    Write-Host "Parser Function: $parserFunctionName" -ForegroundColor Cyan
    Write-Host "Parser Module: $parserModulePath" -ForegroundColor Cyan
    
    if ($ErrorInfo.SourceFile) {
        Write-Host "Source File: $($ErrorInfo.SourceFile)" -ForegroundColor Cyan
    }
    if ($ErrorInfo.TableName) {
        Write-Host "SQL Table: $($ErrorInfo.TableName)" -ForegroundColor Cyan
    }
    
    Write-Host "`nError Message:" -ForegroundColor Yellow
    Write-Host $ErrorInfo.ErrorMessage -ForegroundColor Red
    
    if ($ErrorDetails.FunctionName) {
        Write-Host "`nFunction: $($ErrorDetails.FunctionName)" -ForegroundColor Cyan
    }
    if ($ErrorDetails.LineNumber) {
        Write-Host "Line Number: $($ErrorDetails.LineNumber)" -ForegroundColor Cyan
    }
    
    Write-Host "`nError Pattern: $($ErrorDetails.ErrorPattern)" -ForegroundColor Yellow
    
    if ($ErrorDetails.ErrorLines.Count -gt 0) {
        Write-Host "`nError Log Lines:" -ForegroundColor Yellow
        $ErrorDetails.ErrorLines | ForEach-Object {
            Write-Host $_ -ForegroundColor Red
        }
    }
    
    if ($ErrorInfo.StackTrace) {
        Write-Host "`nStack Trace:" -ForegroundColor Yellow
        Write-Host $ErrorInfo.StackTrace -ForegroundColor Gray
    }
    
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "AI ASSISTANT INSTRUCTIONS:" -ForegroundColor Green
    Write-Host "1. Search codebase for: $parserFunctionName" -ForegroundColor White
    Write-Host "2. Analyze error: $($ErrorDetails.ErrorPattern)" -ForegroundColor White
    if ($ErrorDetails.FunctionName) {
        Write-Host "3. Check function: $($ErrorDetails.FunctionName) at line $($ErrorDetails.LineNumber)" -ForegroundColor White
    }
    Write-Host "4. Apply fix to resolve parsing error" -ForegroundColor White
    Write-Host "5. Error summary file: $errorSummaryFile" -ForegroundColor White
    Write-Host "========================================`n" -ForegroundColor Red
    
    # Prompt user/AI for fix
    if (-not $SkipConfirmation) {
        Write-Host "Waiting for AI assistant to analyze and fix the error..." -ForegroundColor Yellow
        Write-Host "Press Enter after the fix has been applied to continue with retest." -ForegroundColor Yellow
        Write-Host "Or type 'skip' to skip this error." -ForegroundColor Yellow
        $response = Read-Host "`nFix applied? (Enter=Yes, skip=Skip)"
        
        if ($response -eq "skip" -or $response -eq "Skip") {
            Write-LogMessage "User skipped fix for $($ErrorInfo.ErrorFileName)" -Level INFO
            return $false
        }
    }
    else {
        Write-LogMessage "SkipConfirmation is enabled. Assuming fix will be applied." -Level INFO
        Write-Host "Waiting 5 seconds for fix to be applied..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    
    Write-LogMessage "Proceeding to retest after fix..." -Level INFO
    return $true  # Return true to indicate we should retest
}

#endregion

#region HTML File Management Functions

function Get-ServerHtmlFilePath {
    <#
    .SYNOPSIS
        Determines the server HTML file path for a given error.
    .DESCRIPTION
        Constructs the expected HTML filename based on parser type and error information.
    .OUTPUTS
        Full path to the HTML file on the server, or $null if cannot be determined.
    #>
    param(
        [PSCustomObject]$ErrorInfo
    )
    
    $htmlFileName = $null
    
    switch ($ErrorInfo.ParserType) {
        "SQL" {
            if ($ErrorInfo.TableName) {
                # SQL: tablename.sql.html (dots replaced with underscores, lowercase)
                $tableNameForFile = $ErrorInfo.TableName.Replace(".", "_").ToLower()
                $htmlFileName = "$tableNameForFile.sql.html"
            }
        }
        "CBL" {
            if ($ErrorInfo.SourceFile) {
                $baseName = [System.IO.Path]::GetFileName($ErrorInfo.SourceFile)
                $htmlFileName = "$baseName.html"
            }
            elseif ($ErrorInfo.ErrorFileName) {
                $baseName = $ErrorInfo.ErrorFileName -replace '\.err$', ''
                $htmlFileName = "$baseName.html"
            }
        }
        "REX" {
            if ($ErrorInfo.SourceFile) {
                $baseName = [System.IO.Path]::GetFileName($ErrorInfo.SourceFile)
                $htmlFileName = "$baseName.html"
            }
            elseif ($ErrorInfo.ErrorFileName) {
                $baseName = $ErrorInfo.ErrorFileName -replace '\.err$', ''
                $htmlFileName = "$baseName.html"
            }
        }
        "BAT" {
            if ($ErrorInfo.SourceFile) {
                $baseName = [System.IO.Path]::GetFileName($ErrorInfo.SourceFile)
                $htmlFileName = "$baseName.html"
            }
            elseif ($ErrorInfo.ErrorFileName) {
                $baseName = $ErrorInfo.ErrorFileName -replace '\.err$', ''
                $htmlFileName = "$baseName.html"
            }
        }
        "PS1" {
            if ($ErrorInfo.SourceFile) {
                $baseName = [System.IO.Path]::GetFileName($ErrorInfo.SourceFile)
                $htmlFileName = "$baseName.html"
            }
            elseif ($ErrorInfo.ErrorFileName) {
                $baseName = $ErrorInfo.ErrorFileName -replace '\.err$', ''
                $htmlFileName = "$baseName.html"
            }
        }
    }
    
    if ($htmlFileName) {
        $htmlFilePath = Join-Path $ServerWebsPath $htmlFileName
        return $htmlFilePath
    }
    
    return $null
}

function Remove-ServerHtmlFile {
    <#
    .SYNOPSIS
        Removes the HTML file from the server webs folder.
    .DESCRIPTION
        Deletes the generated HTML file from the server to force regeneration on next AutoDocBatchRunner run.
    #>
    param(
        [PSCustomObject]$ErrorInfo
    )
    
    $htmlFilePath = Get-ServerHtmlFilePath -ErrorInfo $ErrorInfo
    
    if (-not $htmlFilePath) {
        Write-LogMessage "Could not determine HTML file path for $($ErrorInfo.ErrorFileName)" -Level WARN
        return $false
    }
    
    try {
        if (Test-Path $htmlFilePath -PathType Leaf) {
            Remove-Item $htmlFilePath -Force -ErrorAction Stop
            Write-LogMessage "Removed HTML file from server: $htmlFilePath" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "HTML file not found on server (may have been removed already): $htmlFilePath" -Level DEBUG
            return $false
        }
    }
    catch {
        Write-LogMessage "Could not remove server HTML file: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region Progress Tracking Functions

function Get-ProgressState {
    <#
    .SYNOPSIS
        Reads progress state from state file.
    .DESCRIPTION
        Loads progress state from %TEMP%\Fix-AutoDocErrors-Progress.json if it exists.
    .OUTPUTS
        PSCustomObject with progress state, or $null if no state file exists.
    #>
    
    $progressFile = Join-Path $env:TEMP "Fix-AutoDocErrors-Progress.json"
    
    if (-not (Test-Path $progressFile)) {
        return $null
    }
    
    try {
        $content = Get-Content $progressFile -Raw -ErrorAction Stop
        $state = $content | ConvertFrom-Json
        Write-LogMessage "Loaded progress state from: $progressFile" -Level INFO
        Write-LogMessage "Session Date: $($state.SessionDate), Last Processed: $($state.LastProcessedErrorFileName), Line: $($state.LastProcessedLineNumber)" -Level INFO
        return $state
    }
    catch {
        Write-LogMessage "Failed to load progress state: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Save-ProgressState {
    <#
    .SYNOPSIS
        Saves current progress state to state file.
    .DESCRIPTION
        Writes progress state to %TEMP%\Fix-AutoDocErrors-Progress.json.
    #>
    param(
        [string]$SessionDate,
        [datetime]$LogFileCreatedDate,
        [int]$LastProcessedLineNumber,
        [string]$LastProcessedErrorFileName,
        [string[]]$ProcessedErrors,
        [int]$FixedCount,
        [int]$FailedCount,
        [int]$SkippedCount
    )
    
    $progressFile = Join-Path $env:TEMP "Fix-AutoDocErrors-Progress.json"
    
    $state = [PSCustomObject]@{
        SessionDate = $SessionDate
        LogFileCreatedDate = $LogFileCreatedDate.ToString("yyyy-MM-ddTHH:mm:ss")
        LastProcessedLineNumber = $LastProcessedLineNumber
        LastProcessedErrorFileName = $LastProcessedErrorFileName
        ProcessedErrors = $ProcessedErrors
        FixedCount = $FixedCount
        FailedCount = $FailedCount
        SkippedCount = $SkippedCount
        LastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }
    
    try {
        $state | ConvertTo-Json -Depth 10 | Set-Content $progressFile -Encoding UTF8 -ErrorAction Stop
        Write-LogMessage "Saved progress state to: $progressFile" -Level DEBUG
    }
    catch {
        Write-LogMessage "Failed to save progress state: $($_.Exception.Message)" -Level WARN
    }
}

function Get-ServerLogFileInfo {
    <#
    .SYNOPSIS
        Gets the current server log file and its creation date.
    .DESCRIPTION
        Finds the log file for today on the server and returns its info.
    .OUTPUTS
        PSCustomObject with LogFilePath and CreatedDate, or $null if not found.
    #>
    
    $logDate = Get-Date -Format "yyyyMMdd"
    $logFileName = "FkLog_$logDate.log"
    $logFilePath = Join-Path $ServerLogPath $logFileName
    
    if (-not (Test-Path $logFilePath)) {
        Write-LogMessage "Server log file not found: $logFilePath" -Level WARN
        return $null
    }
    
    try {
        $logFile = Get-Item $logFilePath -ErrorAction Stop
        $result = [PSCustomObject]@{
            LogFilePath = $logFilePath
            CreatedDate = $logFile.CreationTime
            LastWriteTime = $logFile.LastWriteTime
            LineCount = (Get-Content $logFilePath | Measure-Object -Line).Lines
        }
        Write-LogMessage "Found server log file: $logFilePath (Created: $($result.CreatedDate), Lines: $($result.LineCount))" -Level INFO
        return $result
    }
    catch {
        Write-LogMessage "Failed to read server log file info: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Get-ProcessedErrorsFromLog {
    <#
    .SYNOPSIS
        Extracts processed error filenames from log file up to a specific line number.
    .DESCRIPTION
        Reads log file and finds all error filenames that have been processed.
    #>
    param(
        [string]$LogFilePath,
        [int]$UpToLineNumber
    )
    
    if (-not (Test-Path $LogFilePath)) {
        return @()
    }
    
    try {
        $logLines = Get-Content $LogFilePath -TotalCount $UpToLineNumber -ErrorAction Stop
        $processedErrors = @()
        
        # Look for log entries indicating error processing
        # Pattern: "Processing Error: FILENAME.err" or "Parsing succeeded for FILENAME.err"
        foreach ($line in $logLines) {
            if ($line -match 'Processing Error:\s*([^\s]+\.err)') {
                $errorFileName = $Matches[1]
                if ($processedErrors -notcontains $errorFileName) {
                    $processedErrors += $errorFileName
                }
            }
            elseif ($line -match 'Parsing succeeded for\s+([^\s]+\.err)') {
                $errorFileName = $Matches[1]
                if ($processedErrors -notcontains $errorFileName) {
                    $processedErrors += $errorFileName
                }
            }
            elseif ($line -match 'Fix successful.*for\s+([^\s]+\.err)') {
                $errorFileName = $Matches[1]
                if ($processedErrors -notcontains $errorFileName) {
                    $processedErrors += $errorFileName
                }
            }
        }
        
        Write-LogMessage "Extracted $($processedErrors.Count) processed error(s) from log file (up to line $UpToLineNumber)" -Level INFO
        return $processedErrors
    }
    catch {
        Write-LogMessage "Failed to read log file for processed errors: $($_.Exception.Message)" -Level WARN
        return @()
    }
}

function Test-ProgressStateValid {
    <#
    .SYNOPSIS
        Checks if progress state is valid for current session.
    .DESCRIPTION
        Compares progress state with current server log file to determine if resume is possible.
    #>
    param(
        [PSCustomObject]$ProgressState,
        [PSCustomObject]$LogFileInfo
    )
    
    if ($null -eq $ProgressState -or $null -eq $LogFileInfo) {
        return $false
    }
    
    # Check if log file created date matches (within 1 hour tolerance for timezone differences)
    $stateDate = [datetime]::Parse($ProgressState.LogFileCreatedDate)
    $logDate = $LogFileInfo.CreatedDate
    $timeDiff = [Math]::Abs(($stateDate - $logDate).TotalHours)
    
    if ($timeDiff -gt 1) {
        Write-LogMessage "Progress state log date ($stateDate) does not match current log date ($logDate). Starting fresh." -Level INFO
        return $false
    }
    
    # Check if log file has more lines than last processed (should have)
    if ($LogFileInfo.LineCount -lt $ProgressState.LastProcessedLineNumber) {
        Write-LogMessage "Log file has fewer lines ($($LogFileInfo.LineCount)) than last processed ($($ProgressState.LastProcessedLineNumber)). Starting fresh." -Level INFO
        return $false
    }
    
    Write-LogMessage "Progress state is valid. Resuming from line $($ProgressState.LastProcessedLineNumber)" -Level INFO
    return $true
}

#endregion

#region Main Processing Loop

function Start-ErrorFixProcess {
    <#
    .SYNOPSIS
        Main processing loop that fixes all AutoDoc parsing errors.
    .DESCRIPTION
        Gets list of errors, processes each one, applies fixes, and retests.
        Supports progress tracking and resuming from previous session.
    #>
    
    Write-LogMessage "=== AutoDoc Error Fix Process Started ===" -Level INFO
    
    # Initialize progress tracking
    $sessionDate = Get-Date -Format "yyyyMMdd"
    $logFileInfo = Get-ServerLogFileInfo
    $progressState = $null
    $resumeFromLine = 0
    $initialProcessedErrors = @()
    
    # Load progress state if resuming
    if ($ResumeFromProgress) {
        $progressState = Get-ProgressState
        if ($null -ne $progressState -and $null -ne $logFileInfo) {
            if (Test-ProgressStateValid -ProgressState $progressState -LogFileInfo $logFileInfo) {
                $resumeFromLine = $progressState.LastProcessedLineNumber
                $initialProcessedErrors = $progressState.ProcessedErrors
                Write-LogMessage "Resuming from previous session. Last processed: $($progressState.LastProcessedErrorFileName) at line $resumeFromLine" -Level INFO
                Write-LogMessage "Already processed $($initialProcessedErrors.Count) error(s)" -Level INFO
            }
            else {
                Write-LogMessage "Progress state is not valid for current session. Starting fresh." -Level INFO
                $progressState = $null
            }
        }
        else {
            Write-LogMessage "No valid progress state found. Starting fresh." -Level INFO
        }
    }
    
    # Get list of errors from server
    $errors = Get-AutoDocErrors -ErrorPath $ServerErrorPath
    
    if ($errors.Count -eq 0) {
        Write-LogMessage "No errors found. Exiting." -Level INFO
        return
    }
    
    Write-LogMessage "Found $($errors.Count) error(s) to process" -Level INFO
    
    # Filter out already processed errors if resuming
    if ($initialProcessedErrors.Count -gt 0) {
        $errors = $errors | Where-Object { $initialProcessedErrors -notcontains $_.ErrorFileName }
        Write-LogMessage "After filtering processed errors: $($errors.Count) error(s) remaining" -Level INFO
    }
    
    # Limit errors if MaxErrors is set
    if ($MaxErrors -gt 0 -and $errors.Count -gt $MaxErrors) {
        Write-LogMessage "Limiting to first $MaxErrors error(s)" -Level INFO
        $errors = $errors[0..($MaxErrors - 1)]
    }
    
    # Initialize counters from progress state if resuming
    if ($null -ne $progressState) {
        $fixedCount = $progressState.FixedCount
        $skippedCount = $progressState.SkippedCount
        $failedCount = $progressState.FailedCount
        Write-LogMessage "Resuming with counts - Fixed: $fixedCount, Skipped: $skippedCount, Failed: $failedCount" -Level INFO
    }
    else {
        $fixedCount = 0
        $skippedCount = 0
        $failedCount = 0
    }
    
    $processedErrors = $initialProcessedErrors.Clone()
    
    foreach ($errorItem in $errors) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Processing Error: $($errorItem.ErrorFileName)" -ForegroundColor Cyan
        Write-Host "Parser Type: $($errorItem.ParserType)" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        
        # Check if already processed
        if ($processedErrors -contains $errorItem.ErrorFileName) {
            Write-LogMessage "Skipping already processed error: $($errorItem.ErrorFileName)" -Level INFO
            $skippedCount++
            continue
        }
        
        # Run local parsing
        Write-LogMessage "Running local parsing for $($errorItem.ErrorFileName)..." -Level INFO
        $parseResult = Invoke-SingleFileParse -ErrorInfo $errorItem
        
        if ($null -eq $parseResult) {
            Write-LogMessage "Failed to run parsing for $($errorItem.ErrorFileName)" -Level ERROR
            $failedCount++
            if (-not $ContinueOnFailure) {
                break
            }
            continue
        }
        
        # Check if parsing succeeded
        if ($parseResult.Success) {
            Write-LogMessage "Parsing succeeded for $($errorItem.ErrorFileName) - may have been fixed already" -Level INFO
            $fixedCount++
            
            # Remove error file from server if accessible
            try {
                if (Test-Path $errorItem.ErrorFilePath) {
                    Remove-Item $errorItem.ErrorFilePath -Force -ErrorAction SilentlyContinue
                    Write-LogMessage "Removed error file from server: $($errorItem.ErrorFilePath)" -Level INFO
                }
            }
            catch {
                Write-LogMessage "Could not remove server error file: $($_.Exception.Message)" -Level WARN
            }
            
            # Remove HTML file from server to force regeneration on next AutoDocBatchRunner run
            $htmlRemoved = Remove-ServerHtmlFile -ErrorInfo $errorItem
            if ($htmlRemoved) {
                Write-LogMessage "Removed HTML file from server to force regeneration" -Level INFO
            }
            
            $processedErrors += $errorItem.ErrorFileName
            continue
        }
        
        # Parsing failed - analyze error
        Write-LogMessage "Parsing failed. Analyzing error details..." -Level WARN
        $errorDetails = Get-ParseErrorDetails -LogContent $parseResult.LogContent -ErrorInfo $errorItem
        
        # Attempt AI fix
        Write-LogMessage "Attempting to fix error..." -Level INFO
        $shouldRetest = Invoke-AIFix -ErrorInfo $errorItem -ErrorDetails $errorDetails -ParseResult $parseResult
        
        if ($shouldRetest) {
            # Retest after fix
            Write-LogMessage "Retesting after fix..." -Level INFO
            Start-Sleep -Seconds 2  # Brief pause for file system and module reload
            
            # Clear module cache to ensure latest code is loaded
            Remove-Module -Name AutodocFunctions -Force -ErrorAction SilentlyContinue
            Import-Module -Name AutodocFunctions -Force
            
            $retestResult = Invoke-SingleFileParse -ErrorInfo $errorItem
            
            if ($retestResult.Success) {
                Write-Host "`n✓ Fix successful! Error resolved for $($errorItem.ErrorFileName)" -ForegroundColor Green
                Write-LogMessage "Fix successful! Error resolved for $($errorItem.ErrorFileName)" -Level INFO
                $fixedCount++
                
                # Remove error file from server if accessible
                try {
                    if (Test-Path $errorItem.ErrorFilePath) {
                        Remove-Item $errorItem.ErrorFilePath -Force -ErrorAction SilentlyContinue
                        Write-LogMessage "Removed error file from server: $($errorItem.ErrorFilePath)" -Level INFO
                    }
                }
                catch {
                    Write-LogMessage "Could not remove server error file: $($_.Exception.Message)" -Level WARN
                }
                
                # Remove HTML file from server to force regeneration on next AutoDocBatchRunner run
                $htmlRemoved = Remove-ServerHtmlFile -ErrorInfo $errorItem
                if ($htmlRemoved) {
                    Write-LogMessage "Removed HTML file from server to force regeneration" -Level INFO
                }
            }
            else {
                Write-Host "`n✗ Fix did not resolve error for $($errorItem.ErrorFileName)" -ForegroundColor Red
                Write-LogMessage "Fix did not resolve error for $($errorItem.ErrorFileName)" -Level WARN
                
                # Show new error details if available
                if ($retestResult.LogContent) {
                    $newErrorDetails = Get-ParseErrorDetails -LogContent $retestResult.LogContent -ErrorInfo $errorItem
                    if ($newErrorDetails.ErrorLines.Count -gt 0) {
                        Write-Host "New error details:" -ForegroundColor Yellow
                        $newErrorDetails.ErrorLines | ForEach-Object {
                            Write-Host $_ -ForegroundColor Red
                        }
                    }
                }
                
                $failedCount++
                
                if (-not $ContinueOnFailure) {
                    Write-Host "`nStopping due to fix failure. Use -ContinueOnFailure to continue processing other errors." -ForegroundColor Yellow
                    break
                }
            }
        }
        else {
            Write-LogMessage "Fix not applied for $($errorItem.ErrorFileName)" -Level WARN
            $failedCount++
        }
        
        $processedErrors += $errorItem.ErrorFileName
        
        # Update progress state after each error
        if ($null -ne $logFileInfo) {
            $currentLineCount = if (Test-Path $logFileInfo.LogFilePath) {
                (Get-Content $logFileInfo.LogFilePath | Measure-Object -Line).Lines
            } else {
                $resumeFromLine
            }
            
            Save-ProgressState -SessionDate $sessionDate `
                -LogFileCreatedDate $logFileInfo.CreatedDate `
                -LastProcessedLineNumber $currentLineCount `
                -LastProcessedErrorFileName $errorItem.ErrorFileName `
                -ProcessedErrors $processedErrors `
                -FixedCount $fixedCount `
                -FailedCount $failedCount `
                -SkippedCount $skippedCount
        }
        
        # Brief pause between errors
        Start-Sleep -Seconds 1
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "=== Processing Complete ===" -ForegroundColor Green
    Write-Host "Fixed: $fixedCount" -ForegroundColor Green
    Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow
    Write-Host "Failed: $failedCount" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-LogMessage "Error fix process completed. Fixed: $fixedCount, Skipped: $skippedCount, Failed: $failedCount" -Level INFO
    
    # Clear progress state file on successful completion
    $progressFile = Join-Path $env:TEMP "Fix-AutoDocErrors-Progress.json"
    if (Test-Path $progressFile) {
        try {
            Remove-Item $progressFile -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Cleared progress state file" -Level INFO
        }
        catch {
            Write-LogMessage "Could not clear progress state file: $($_.Exception.Message)" -Level WARN
        }
    }
}

#endregion

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    Start-ErrorFixProcess
}
