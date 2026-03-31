# AutoDoc Error Fix Script - AI Instructions

## Overview

The `Fix-AutoDocErrors.ps1` script automates the process of identifying, analyzing, and fixing AutoDoc parsing errors using AI assistance. This document explains how an AI assistant should interact with this script to fix errors systematically.

## Workflow

### 1. Initial Setup

The script extracts parsing errors from `.err` files on the server (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc`). Each error file contains:
- **ParserType**: CBL, REX, BAT, PS1, or SQL
- **SourceFile**: Path to source file (for file-based parsers)
- **TableName**: SQL table name (for SQL parser)
- **ErrorMessage**: The error message
- **StackTrace**: Stack trace showing where the error occurred

### 2. Error Processing Loop

For each error, the script:

1. **Extracts Error Information**: Reads the `.err` file and parses its content
2. **Runs Local Parsing**: Executes `AutoDocBatchRunner.ps1` in single-file mode locally
3. **Checks Result**: 
   - If parsing succeeds → Error is already fixed, mark as fixed
   - If parsing fails → Proceed to AI fix workflow

### 3. AI Fix Workflow (When Parsing Fails)

When a parsing error is detected:

1. **Error Analysis**: The script calls `Invoke-AIFix` which:
   - Creates a JSON summary file in `%TEMP%\AutoDocError_yyyyMMdd_HHmmss.json`
   - Displays comprehensive error information to the console
   - Shows the parser function, source file/table, error message, and stack trace
   - **Pauses and waits for AI input**

2. **AI Assistant Actions**:
   - **Read the error summary JSON file** from `%TEMP%\AutoDocError_*.json`
   - **Search the codebase** for the parser function (e.g., `Start-SqlParse`, `Start-CblParse`)
   - **Analyze the error**:
     - Read the relevant function code
     - Understand what the error means (e.g., "Cannot bind argument to parameter 'ColumnsArray' because it is null")
     - Identify the root cause (e.g., CSV file missing, filter returns null, etc.)
   - **Apply the fix**:
     - Modify the parser function code
     - Add null checks, error handling, or fix logic errors
     - Ensure the fix handles edge cases
   - **Verify the fix**:
     - Check for linter errors
     - Ensure code follows project standards
   - **Signal completion**: Press Enter in the console (or type 'skip' to skip)

3. **Retest After Fix**:
   - Script reloads the `AutodocFunctions` module to ensure latest code is used
   - Re-runs single-file parsing
   - If successful → 
     - Removes error file from server (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc\*.err`)
     - **Removes HTML file from server** (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc\*.html`) to force regeneration
     - Marks as fixed
   - If failed → Shows new error details, marks as failed

**IMPORTANT**: When an error is successfully fixed, the script automatically removes both:
- The `.err` error file from the server
- The corresponding `.html` file from the server webs folder

This ensures that when `AutoDocBatchRunner.ps1` runs next time (in Incremental or All mode), it will detect the missing HTML file and regenerate it with the fixed parser code. The HTML filename format is:
- **CBL/REX/BAT/PS1**: `filename.html` (e.g., `BSAUTOS.CBL.html`, `script.bat.html`)
- **SQL**: `tablename.sql.html` (e.g., `CRM_MARKEDSREGISTER.sql.html` - dots replaced with underscores, lowercase)

### 4. Progress Tracking

The script tracks progress using:
- **Server Log File**: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\AutoDoc\FkLog_yyyyMMdd.log`
- **Created Date**: Uses the log file's creation date to identify the session
- **Line Numbers**: Tracks which log entries have been processed
- **State File**: Stores progress in `%TEMP%\Fix-AutoDocErrors-Progress.json`

When resuming:
- Script reads the progress state file
- Compares server log file created date with stored date
- If dates match → Resumes from last processed line number
- If dates differ → Starts fresh (new session)

## AI Assistant Best Practices

### When Fixing Errors

1. **Read the Error Summary JSON**:
   ```powershell
   $errorFile = Get-ChildItem "$env:TEMP\AutoDocError_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
   $errorInfo = Get-Content $errorFile.FullName | ConvertFrom-Json
   ```

2. **Search for the Parser Function**:
   ```powershell
   codebase_search -query "Where is Start-SqlParse function defined? What causes ColumnsArray to be null?"
   ```

3. **Read the Function Code**:
   ```powershell
   read_file -target_file "_Modules/AutoDocFunctions/AutoDocFunctions.psm1" -offset 7498 -limit 100
   ```

4. **Apply the Fix**:
   - Add null checks before using variables
   - Initialize arrays as empty arrays (`@()`) instead of allowing null
   - Add error handling for file operations
   - Follow PowerShell best practices

5. **Check for Linter Errors**:
   ```powershell
   read_lints -paths ["_Modules/AutoDocFunctions/AutoDocFunctions.psm1"]
   ```

6. **Test Locally** (optional):
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1" -Regenerate Single -SingleFile "CRM.MARKEDSREGISTER" -UseRamDisk:$false -QuickRun:$true
   ```

7. **Signal Completion**: Press Enter in the console where the script is waiting

### Common Error Patterns

#### SQL Parser Errors
- **Null ColumnsArray**: CSV file missing or filter returns null
  - **Fix**: Initialize as `@()`, add file existence check, handle import errors
- **Missing CSV files**: `columns.csv` or `tables.csv` not found
  - **Fix**: Add `Test-Path` checks, provide helpful error messages

#### File-Based Parser Errors
- **File not found**: Source file path incorrect
  - **Fix**: Check path resolution logic, add fallback paths
- **Parsing exceptions**: Code structure not recognized
  - **Fix**: Improve regex patterns, add error handling

### Error Fix Examples

#### Example 1: Null Parameter Binding
**Error**: `Cannot bind argument to parameter 'ColumnsArray' because it is null.`

**Root Cause**: CSV import fails or filter returns null

**Fix**:
```powershell
# Initialize as empty array
$columnsArray = @()

# Check file exists before importing
$columnsCsvPath = Join-Path $inputDbFileFolder "columns.csv"
if (Test-Path $columnsCsvPath) {
    try {
        $csvTableArray1 = Import-Csv $columnsCsvPath -Header ... -ErrorAction Stop
        if ($null -ne $csvTableArray1) {
            $columnsArray = $csvTableArray1 | Where-Object { ... }
        }
    }
    catch {
        Write-LogMessage "Failed to load columns.csv: $($_.Exception.Message)" -Level WARN
        $columnsArray = @()
    }
}
else {
    Write-LogMessage "Columns CSV file not found: $columnsCsvPath" -Level WARN
}

# Ensure not null before passing to function
if ($null -eq $columnsArray) {
    $columnsArray = @()
}
```

## Script Parameters

- `-ServerErrorPath`: Path to server error files (default: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc`)
- `-ServerWebsPath`: Path to server webs folder where HTML files are generated (default: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc`)
- `-ServerLogPath`: Path to server log files for progress tracking (default: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\AutoDoc`)
- `-LocalOutputFolder`: Local output folder for testing (default: `$env:OptPath\Webs\AutoDoc`)
- `-MaxErrors`: Maximum number of errors to process (0 = unlimited)
- `-ContinueOnFailure`: Continue processing even if a fix fails
- `-SkipConfirmation`: Skip user confirmation (for automated runs)
- `-ResumeFromProgress`: Resume from last saved progress state

## Running the Script

### First Time (Process All Errors)
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Fix-AutoDocErrors.ps1"
```

### Resume from Progress
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Fix-AutoDocErrors.ps1" -ResumeFromProgress
```

### Process Limited Errors
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Fix-AutoDocErrors.ps1" -MaxErrors 5 -ContinueOnFailure
```

## Progress State File Format

The progress state file (`%TEMP%\Fix-AutoDocErrors-Progress.json`) contains:

```json
{
  "SessionDate": "20260204",
  "LogFileCreatedDate": "2026-02-04T12:20:00",
  "LastProcessedLineNumber": 150,
  "LastProcessedErrorFileName": "CRM_MARKEDSREGISTER.sql.err",
  "ProcessedErrors": [
    "BSAUTOS.CBL.err",
    "Client-Config-For-All-Db2-Azure-Databases-Using-Kerberos-SSL-For-Dbeaver.bat.err"
  ],
  "FixedCount": 2,
  "FailedCount": 0,
  "SkippedCount": 0
}
```

## Troubleshooting

### Script Stops Waiting for Input
- The script pauses at `Invoke-AIFix` waiting for Enter key
- AI assistant should apply the fix, then press Enter
- Or type 'skip' to skip the current error

### Progress Not Resuming
- Check that the server log file exists and is accessible
- Verify the progress state file exists in `%TEMP%`
- Check that log file created date matches stored date

### Module Not Reloading
- Script uses `Remove-Module` and `Import-Module` to reload
- If issues persist, restart PowerShell session

## Notes

- The script processes errors in the order they appear in the error file list
- Fixed errors are automatically removed from the server (both `.err` and `.html` files)
- **HTML file removal**: When an error is fixed, the corresponding HTML file is removed from `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc` to ensure `AutoDocBatchRunner.ps1` regenerates it on the next run
- The script logs all actions using `Write-LogMessage`
- Progress is saved after each error is processed
- The script can be safely interrupted and resumed
