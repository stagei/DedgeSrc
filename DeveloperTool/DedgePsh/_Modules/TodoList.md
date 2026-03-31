# PowerShell Module Documentation Update Todolist

This todolist outlines the tasks needed to update documentation for each .psm1 module in the _Modules folder.

## General Tasks for Each Module
1. Update the README.md file to document only the exported functions
2. Update the internal .SYNOPSIS comments to align with actual implementation

## Module-Specific Tasks

### 1. AlertWKMon
- [x] Review and update exported functions in AlertWKMon.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 2. CblRun
- [x] Review and update exported functions in CblRun.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 3. CheckLog
- [x] Review and update exported functions in CheckLog.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 4. ConvertAnsi1252ToUtf8
- [x] Review and update exported functions in ConvertAnsi1252ToUtf8.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 5. ConvertFileFromAnsi1252ToUtf8
- [x] Review and update exported functions in ConvertFileFromAnsi1252ToUtf8.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 6. ConvertStringFromAnsi1252ToUtf8
- [x] Review and update exported functions in ConvertStringFromAnsi1252ToUtf8.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 7. ConvertUtf8ToAnsi1252
- [x] Review and update exported functions in ConvertUtf8ToAnsi1252.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 8. Deploy-Handler
- [x] Review and update exported functions in Deploy-Handler.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 9. Export-Array
- [x] Review and update exported functions in Export-Array.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 10. FKASendEmail
- [x] Review and update exported functions in FKASendEmail.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 11. FKASendSMSDirect
- [x] Review and update exported functions in FKASendSMSDirect.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 12. DedgeCommon
- [x] Review and update exported functions in DedgeCommon.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 13. Get-FunctionsFromPsm1
- [x] Review and update exported functions in Get-FunctionsFromPsm1.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 14. GlobalFunctions
- [x] Review and update exported functions in GlobalFunctions.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 15. Infrastructure
- [x] Review and update exported functions in Infrastructure.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 16. Logger
- [x] Review and update exported functions in Logger.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 17. MarkdownToHtml
- [x] Review and update exported functions in MarkdownToHtml.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 18. OdbcHandler
- [x] Review and update exported functions in OdbcHandler.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 19. ScheduledTask-Handler
- [x] Review and update exported functions in ScheduledTask-Handler.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 20. SoftwareUtils
- [x] Review and update exported functions in SoftwareUtils.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

### 21. WKMon
- [x] Review and update exported functions in WKMon.psm1
- [x] Update .SYNOPSIS comments to match implementation
- [x] Update module documentation in README.md

## Process for Each Module

1. **Identify Exported Functions**
   - Open the .psm1 file
   - Look for `Export-ModuleMember` statements to identify exported functions
   - Alternatively, use the Get-FunctionsFromPsm1 module to extract exported functions

2. **Review .SYNOPSIS Comments**
   - For each exported function, review the .SYNOPSIS comment block
   - Ensure it accurately describes the current implementation
   - Update if necessary to match actual functionality

3. **Update README.md**
   - Document only the exported functions in the README.md file
   - Include function name, brief description, and usage examples
   - Ensure consistency with the .SYNOPSIS comments
