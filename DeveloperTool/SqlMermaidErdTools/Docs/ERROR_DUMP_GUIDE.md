# Error Dump System - SqlMermaidErdTools

## Overview

When SQLGlot processing fails (cannot parse SQL or generate output), SqlMermaidErdTools automatically creates a comprehensive error dump for troubleshooting and support purposes.

## What Triggers an Error Dump?

Error dumps are created when:

1. **SQLGlot produces no output** - The Python script executes but returns empty/null results
2. **Python script execution fails** - The SQLGlot Python script throws an exception or exits with error code
3. **Parsing failures** - SQLGlot cannot parse the input SQL or Mermaid ERD syntax

## Error Dump Contents

Each error dump is a ZIP file containing:

```
ErrorDump_<FunctionName>_<Timestamp>.zip
├── ERROR_DETAILS.txt              - Complete error information
├── SqlMermaidErdTools.log         - Application log file
└── ExportedFiles/                 - All intermediate conversion files
    ├── <Function>-In_Original.*   - Original input
    ├── <Function>-In_Cleaned.*    - Preprocessed input
    ├── <Function>-In.*            - Final input sent to conversion
    └── <Function>-InToSqlGlot*.*  - Exact input sent to SQLGlot
```

### ERROR_DETAILS.txt

Contains:
- Timestamp of the error
- Function name that failed
- Detailed error message
- Full exception stack trace
- Inner exception details (if any)
- Environment information:
  - Operating System
  - Machine name
  - Username
  - .NET version
  - Working directory
  - Runtime directory

### SqlMermaidErdTools.log

The complete application log showing:
- All operations leading up to the error
- Previous successful conversions in the same session
- Diagnostic information

### ExportedFiles

All input and intermediate files that were processed before the error occurred, allowing exact reproduction of the issue.

## Error Dump Location

Error dumps are stored in:

```
<ApplicationRuntimeDirectory>/ErrorDump/
```

For example:
```
D:\MyApp\bin\Release\net10.0\ErrorDump\
```

Each error creates TWO files:
1. **ErrorDump_<FunctionName>_<Timestamp>.zip** - The actual error dump
2. **ErrorDump_<FunctionName>_<Timestamp>.txt** - Support instructions

## Support Instructions File

Alongside each error dump ZIP, a `.txt` file is created with:
- Contact information for support (SqlMermaidErdTools@dedge.no)
- Instructions on what to include when requesting support
- Privacy notice about dump contents
- Alternative support channels (GitHub issues)

## Automatic Processing

When an error occurs:

1. ✅ **Log FATAL error** to console and log file
2. ✅ **Create ErrorDump folder** in runtime directory
3. ✅ **Create Tmp\<timestamp> folder** for staging
4. ✅ **Copy log file** to tmp folder
5. ✅ **Copy all export files** to tmp folder
6. ✅ **Create ERROR_DETAILS.txt** in tmp folder
7. ✅ **ZIP the tmp folder** 
8. ✅ **Move ZIP to ErrorDump folder**
9. ✅ **Clean up tmp folder**
10. ✅ **Create support instructions .txt file**
11. ✅ **Log completion** of error dump creation

All of this happens automatically - no user intervention required!

## Example Error Log

```
[2025-12-01 10:45:24.358] [ERROR] FATAL ERROR in SqlToMmd: Python script 'sql_to_mmd.py' execution failed
[2025-12-01 10:45:24.378] [INFO] Copied log file to dump: SqlMermaidErdTools.log
[2025-12-01 10:45:24.381] [INFO] Copied export files from: D:\MyData\Export
[2025-12-01 10:45:24.400] [INFO] Created error dump zip: ErrorDump_SqlToMmd_20251201_104524_358.zip
[2025-12-01 10:45:24.401] [INFO] Cleaned up temporary folder: Tmp_20251201_104524_358
[2025-12-01 10:45:24.401] [INFO] Created support instructions: ErrorDump_SqlToMmd_20251201_104524_358.txt
[2025-12-01 10:45:24.401] [ERROR] ERROR DUMP CREATED: ErrorDump_SqlToMmd_20251201_104524_358.zip
[2025-12-01 10:45:24.401] [ERROR] Please refer to ErrorDump_SqlToMmd_20251201_104524_358.txt for instructions
```

## Using Error Dumps for Support

### If You Have a Support Agreement:

1. Locate the error dump ZIP file in the `ErrorDump` folder
2. Read the accompanying `.txt` file for instructions
3. Email the ZIP file to: **SqlMermaidErdTools@dedge.no**
4. Include:
   - Brief description of what you were trying to do
   - Input file type (SQL/Mermaid)
   - Target output type
   - Any custom settings used

### If You Don't Have a Support Agreement:

1. Review the `ERROR_DETAILS.txt` inside the ZIP for error information
2. Check the input files to identify any syntax issues
3. Visit: https://github.com/dedge-space/SqlMermaidErdTools
4. File a GitHub issue with:
   - Error description
   - Relevant portions of ERROR_DETAILS.txt
   - Sanitized sample input (if not sensitive)

## Privacy Considerations

⚠️ **Error dumps contain**:
- Your input SQL/Mermaid files
- System environment information (OS, username, machine name)
- Application logs

**Before sharing an error dump:**
- Review contents for sensitive data (database names, credentials, etc.)
- Sanitize input files if needed
- Remove any proprietary SQL logic if required

## Disabling Error Dumps

Error dumps are created automatically when `ExportFolderPath` is set on converters. If you don't want error dumps:

```csharp
// DON'T set ExportFolderPath
var converter = new SqlToMmdConverter(); 

// Errors will still be logged to console, but no dump files created
var result = await converter.ConvertAsync(sql);
```

## Troubleshooting

### Error Dump Not Created

**Possible reasons:**
- `ExportFolderPath` not set on the converter
- Insufficient disk space
- No write permissions to runtime directory
- Export folder doesn't exist (check earlier in logs)

### Large Error Dump Files

Error dumps typically range from **2KB - 5MB** depending on:
- Size of input files
- Number of intermediate files
- Log file size

If dumps are consistently large (>10MB), consider:
- Reducing input file sizes for testing
- Clearing the log file periodically
- Archiving old error dumps

---

## Technical Implementation

Error dumps are created by the `ErrorDumpManager` class, which is automatically invoked by `BaseConverter` when SQLGlot processing fails.

Key classes:
- `ErrorHandling.ErrorDumpManager` - Creates and manages error dumps
- `Converters.BaseConverter` - Catches errors and triggers dump creation
- `Runtime.RuntimeManager` - Executes Python scripts and reports errors

The system is designed to never fail silently - if error dump creation itself fails, it logs a CRITICAL error and continues to throw the original exception.

---

**Last Updated:** 2025-12-01  
**Version:** 0.1.0

