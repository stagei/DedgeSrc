# FkStack.ps1 - Analysis and Documentation

## Overview

**Purpose**: Automated deployment system for transferring COBOL programs, REXX scripts, batch files, and other code from development to production environment with ServiceNow integration.

**Location**: `DevTools/GitTools/FkStack/FkStack.ps1`

**Primary Function**: Manages the complete lifecycle of code deployment including:
- Validation of source files
- Backup of production files
- ServiceNow change request management
- File archiving and deployment
- COBOL dependency scanning

---

## Script Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `inputString` | string | "" | Multi-purpose input: comma-separated file list, .TXT file path, or single filename |
| `changeDescription` | string | "" | Description of the change for ServiceNow |
| `serviceNowId` | string | "" | Existing ServiceNow ticket ID (INC/SC/CHG) |
| `immediateDeploy` | string | "N" | Deploy immediately to production (J/N) |

---

## Global Variables and Paths

```powershell
$global:srcPath = 'C:\FKAVD\NT'              # Source development path
$global:cblCpyPath = 'C:\FKAVD\SYS\CPY'      # COBOL copy files path
$global:prodExecPath = 'C:\COBNT'            # Production execution path
$global:stackPath = 'C:\COBTP'               # Staging/test production path
$global:archivePath = 'C:\CBLARKIV'          # Archive path for ZIP files
$global:tempPath = 'C:\CBLARKIV\TMP\{USER}'  # Temporary work directory
```

---

## Core Functions

### ServiceNow Integration

#### `GetServiceNowInstance()`
- **Returns**: ServiceNow instance name ('fkatest')
- **Purpose**: Centralized instance configuration

#### `GetServiceNowCredentials()`
- **Returns**: PSCredential object
- **Security Issue**: ⚠️ **Hardcoded credentials** - username and password in plaintext
- **Recommendation**: Move to secure credential storage

#### `CreateServiceNowChangeRequest($changeDescription, $moduleList, $serviceNowId)`
- **Purpose**: Creates and immediately closes a ServiceNow change request
- **Workflow**: New → Scheduled → Implement → Review → Closed
- **Returns**: ServiceNow web URL for the change request
- **Bug**: ⚠️ Line 89 - Uses undefined `$uri` variable instead of `$servicenow_web_url`

#### `GetServiceNowOpenIssuesForUser($serviceNowId)`
- **Purpose**: Retrieves all open incidents, service requests, and change requests for current user
- **Returns**: Array of merged request objects with added properties (Type, stateText, Sequence)
- **Potential Bug**: ⚠️ Lines 325, 337 - Null checks may fail if API returns no results

#### `GetServiceNowData($url, $credential)`
- **Purpose**: Generic API wrapper for ServiceNow REST calls
- **Returns**: `$response.result` - **Can return array or null**
- **Potential Bug**: ⚠️ Returns array - callers must handle multiple elements

#### `Get-StateText($uri, $credential)`
- **Returns**: Single state label from first result

#### `Get-StateTexts($uri, $credential)`
- **Returns**: Array of all state code results
- **Note**: ✓ Correctly returns array (plural name indicates this)

#### `GetUserSysID($uri, $credential)`
- **Returns**: sys_id of first user result

---

### File and Module Management

#### `GetModuleInfo($moduleFileName)`
- **Purpose**: Gathers metadata about a module (timestamps, dependencies, validation status)
- **Returns**: PSCustomObject with module details
- **Side Effects**: Populates `$global:errorMessages` array with validation errors
- **Bug**: ⚠️ Line 633 - Uses `$module` variable but parameter is `$moduleFileName`
- **Validation Checks**:
  - INT file exists for compiled COBOL
  - INT file is newer than source
  - BND file exists if SQL is used

#### `ScanCobolProgram($source)`
- **Purpose**: Extracts COPY file dependencies from COBOL source
- **Returns**: Array of copy file paths
- **Logic**:
  1. Finds PROCEDURE DIVISION line number
  2. Scans for COPY statements before procedure division
  3. Excludes system copybooks (DS-CNTRL, DSSYSINF, etc.)
  4. Validates copy file existence
- **Side Effects**: Adds to `$global:errorMessages` if copy files not found

#### `CblUseSql($module)`
- **Purpose**: Determines if COBOL module uses DB2 SQL
- **Returns**: Boolean - checks for `$SET DB2` directive
- **Logic**: Scans for `^\s*\$SET\s+DB2` pattern

#### `GetFileLastWrittenTime($filePath)`
- **Purpose**: Safe wrapper for getting LastWriteTime
- **Returns**: DateTime or null if file doesn't exist

---

### Deployment Operations

#### `CopyModuleFiles($moduleInfo, $folderName)`
- **Purpose**: Orchestrates copying module files to multiple destinations
- **Destinations**:
  1. Temporary working directory
  2. Stack/staging path
  3. Production (if immediate deploy)

#### `CopyModuleFilesToPath($moduleInfo, $deployPath)`
- **Purpose**: Copies module source and related files to specified path
- **COBOL Files Copied**:
  - .CBL source → /SRC/CBL/
  - .INT (intermediate)
  - .IDY (index)
  - .BND (bind file) → /BND/
  - .GS (if exists)
  - All copy files → /SRC/CPY/
- **Other Files**:
  - REX, BAT, CMD, SQL → /SRC/{suffix}/

#### `HandleProductionFileBackup($fileObjList)`
- **Purpose**: Creates backup of production files before deployment
- **Backup Location**: `C:\COBNT\_backup\{YYYYMMDD}\{USERNAME}\`
- **Files Backed Up**:
  - Source files (.CBL, .REX, .BAT, .CMD)
  - Compiled files (.INT, .IDY, .BND, .GS)

#### `ZipAndArchiveFiles($fileObjList, $tempPath, $archivePath)`
- **Purpose**: Creates ZIP archives of deployed modules
- **Archive Format**: `{ModuleName}_{DDMMYY}_{HHMMSS}_TIL_PROD.ZIP`
- **Archive Structure**: `C:\CBLARKIV\{ModuleName}\`

#### `BackupProdModule($moduleInfo, $backupFolder)`
- **Purpose**: Backs up individual module files from production
- **Handles**: Both COBOL modules and other file types

---

## Main Script Flow

### 1. Initialization (Lines 766-806)
- Sets up global paths
- Creates required directories
- Initializes error message array

### 2. Input Processing (Lines 811-1020)

#### Input String Handling:
- **Empty**: Interactive menu mode
- **Contains '?'**: Display help and exit
- **Ends with '.TXT'**: Parse deployment file
- **Single filename**: Deploy that file
- **Comma-separated**: Deploy multiple files

#### TXT File Format:
```
COMMENT:Kommentar til overføringen
PROGRAM:Programnavn1
PROGRAM:Programnavn2
SERVICE_NOW_ID:ServiceNow ID
IMMEDIATE_DEPLOY:J/N
```

#### Interactive Prompts:
1. Change description (if not provided)
2. Module/program names (if not provided)
3. ServiceNow ticket selection/creation
4. Immediate deployment confirmation

### 3. File Collection and Validation (Lines 1088-1134)
- Builds `$fileObjList` with module metadata
- For COBOL programs:
  - Scans for validation modules (XXH*/XXF* → XXV*)
  - Collects copy file dependencies
  - Validates compilation status
- Exits if any validation errors found

### 4. Deployment Execution (Lines 1137-1141)
1. Backup production files
2. Copy files to temporary/staging/production paths
3. Create ZIP archives
4. Clean up temporary files

---

## Critical Bugs and Issues

### 🔴 **Critical Issues**

#### 1. **Hardcoded Test Data (Lines 935-937)**
```powershell
$moduleList += 'BKFINFA.CBL'
$moduleList += 'WKSTYR.REX'
$changeDescription = 'Deploy av endringer i programmet som følge av innmeldt problem'
```
**Impact**: Script ALWAYS deploys these two files regardless of user input  
**Risk**: Accidental production deployments  
**Fix Required**: Remove or comment out these lines immediately

#### 2. **Hardcoded Credentials (Lines 16-18)**
```powershell
$username = 'Dedge.integration'
$password = 'XTj0+SP.1A'
```
**Impact**: Security vulnerability - credentials exposed in source code  
**Risk**: Unauthorized access to ServiceNow  
**Fix Required**: Use secure credential storage (Windows Credential Manager, Azure Key Vault)

#### 3. **Wrong Variable Reference (Line 89)**
```powershell
Write-Host "Change Request Link Web: $uri"
```
**Impact**: Displays wrong URL to user  
**Fix**: Should be `$servicenow_web_url`

### ⚠️ **High Priority Issues**

#### 4. **Variable Scope Bug (Line 633)**
```powershell
function GetModuleInfo ($moduleFileName) {
    $pos = $module.LastIndexOf('.')  # Uses $module instead of $moduleFileName
```
**Impact**: Function will fail if `$module` is not in parent scope  
**Risk**: Deployment failures  
**Fix**: Replace all instances of `$module` with `$moduleFileName` in function

#### 5. **Array Return Type Issues**

**Function**: `GetServiceNowData` (Line 302)
```powershell
return $response.result
```
**Issue**: Returns array but callers may not handle it  
**Affected Lines**:
- Line 319: `$incidents = GetServiceNowData ...`
- Line 323: `$incidents += GetServiceNowData ...`
- Line 331: `$srrequests = GetServiceNowData ...`
- Line 335: `$srrequests += GetServiceNowData ...`
- Line 343: `$crrequests = GetServiceNowData ...`
- Line 346: `$srrequests += GetServiceNowData ...` (Note: Wrong variable name!)

**Impact**: 
- Line 346 assigns to `$srrequests` instead of `$crrequests` - **logic error**
- Null additions may cause unexpected behavior

#### 6. **Null Addition Issues (Line 354)**
```powershell
$requests = $incidents + $srrequests + $crrequests
```
**Issue**: If any variable is null, result may be unexpected  
**Recommended**: Initialize arrays explicitly or use null-coalescing

#### 7. **Copy Variable Name Bugs**

**Line 335**: Wrong variable in assignment
```powershell
$srrequests += GetServiceNowData -url $incidentUrl -credential $credential
```
Should be `$srrequestUrl`, not `$incidentUrl`

**Line 346**: Wrong target variable
```powershell
$srrequests += GetServiceNowData -url $incidentUrl -credential $credential
```
Should be `$crrequests +=` and use correct URL variable

**Line 453**: Typo in variable name
```powershell
New-Item -ItemType Directory -Path $folderCpy -ErrorAction SilentlyContinue | Out-Null
```
Should be `$deployPathCpy`, not `$folderCpy`

### ℹ️ **Medium Priority Issues**

#### 8. **Incomplete Logic (Line 844)**
```powershell
if (readChar -eq '?') {
```
Missing `$` before `readChar` - should be `$readChar`

#### 9. **Inefficient String Building**
Lines 950-961 use string concatenation in loop - should use StringBuilder or array join

#### 10. **Error Handling**
- Many functions lack try-catch blocks
- Silent failures with `-ErrorAction SilentlyContinue`
- No logging of deployment operations

#### 11. **Comparison Logic (Line 985)**
```powershell
if ($periodPos -gt 0) {
```
Should check `$pos` not `$periodPos` (wrong variable)

---

## Supported File Types

| Type | Extension | Current Support | Future Support |
|------|-----------|----------------|----------------|
| COBOL | .CBL | ✓ Full | - |
| REXX | .REX | ✓ Basic | - |
| Batch | .BAT | ✓ Basic | - |
| Command | .CMD | ✓ Basic | - |
| SQL | .SQL | ❌ Disabled | Planned |
| PowerShell Script | .PS1 | ❌ Disabled | Planned |
| PowerShell Module | .PSM1 | ❌ Disabled | Planned |
| Executable | .EXE | ❌ Disabled | Planned |

---

## COBOL-Specific Logic

### Validation Modules
- Programs with 3rd character 'H' or 'F' (e.g., XXHYYY.CBL)
- Automatically checks for validation module (XXVYYY.CBL)
- Deploys both if validation module exists

### Copy File Dependencies
**Excluded System Copybooks**:
- DS-CNTRL
- DSSYSINF
- DSRUNNER
- DS-CALL
- SQLENV
- GMAUTILS
- DEFCLL
- REQFELL
- DSUSRVAL

### SQL Detection
Scans for `$SET DB2` directive to determine if BND file is required

---

## Security Concerns

1. **Hardcoded Credentials**: ServiceNow credentials in plaintext
2. **No Authentication**: No verification beyond username prompt
3. **No Audit Trail**: Limited logging of who deployed what
4. **No Rollback Mechanism**: Backups exist but no automated rollback
5. **Immediate Deploy Risk**: One prompt guards production changes

---

## Recommendations

### Immediate Actions Required

1. **Remove test data** (lines 935-937)
2. **Fix variable scope bugs** in `GetModuleInfo`
3. **Fix copy-paste errors** in `GetServiceNowOpenIssuesForUser`
4. **Fix URI display bug** in `CreateServiceNowChangeRequest`

### Short-Term Improvements

1. **Secure credentials** - Use Windows Credential Manager or secure vault
2. **Add comprehensive logging** - Use `Write-LogMessage` from GlobalFunctions
3. **Add error handling** - Wrap critical operations in try-catch
4. **Add unit tests** - Test each function independently
5. **Validate return types** - Ensure array vs single object consistency

### Long-Term Enhancements

1. **Implement rollback functionality**
2. **Add deployment validation/smoke tests**
3. **Create audit log in database**
4. **Add support for SQL, PS1, PSM1 deployments**
5. **Implement staged rollout** (partial server deployment)
6. **Add approval workflow** for production deployments
7. **Integrate with CI/CD pipeline**

---

## Testing Recommendations

### Unit Tests Needed

1. `GetModuleInfo` - Test with valid/invalid modules
2. `ScanCobolProgram` - Test copy file detection
3. `CblUseSql` - Test SQL detection
4. `GetServiceNowData` - Mock API responses
5. File backup operations - Verify file integrity

### Integration Tests Needed

1. Full deployment workflow (dev → staging)
2. ServiceNow integration (test instance only)
3. Backup and restore procedures
4. Multi-module deployment
5. Validation module detection

### Edge Cases to Test

1. Missing source files
2. Uncompiled COBOL programs
3. Missing copy files
4. Missing BND files for SQL programs
5. Duplicate module names
6. Network failures during deployment
7. Insufficient disk space
8. File locking issues

---

## Performance Considerations

1. **Sequential file operations** - Could benefit from parallel processing
2. **Repeated directory existence checks** - Could cache results
3. **Multiple API calls to ServiceNow** - Could batch requests
4. **Large copy file scanning** - Could optimize regex patterns

---

## Documentation Gaps

1. No inline comments for complex logic
2. No function parameter descriptions
3. No examples of usage
4. No troubleshooting guide
5. No deployment architecture diagram

---

## Compliance and Standards

### Met Standards
- Uses conventional PowerShell function naming
- Implements backup before deployment
- Validates files before deployment

### Violations
- ❌ No logging via Write-LogMessage
- ❌ Hardcoded paths (should use configuration)
- ❌ No module imports (should import GlobalFunctions)
- ❌ No parameter validation attributes
- ❌ Inconsistent error handling

---

## Conclusion

FkStack.ps1 is a functional but risky deployment tool with several critical bugs that must be addressed before production use. The most urgent issues are:

1. Hardcoded test data causing automatic deployments
2. Security vulnerabilities with exposed credentials
3. Variable scope and copy-paste bugs in ServiceNow integration
4. Lack of error handling and logging

The script demonstrates good structure with separated concerns (ServiceNow, file operations, COBOL-specific logic) but needs significant refactoring to meet production standards for safety, security, and maintainability.

**Recommendation**: Do not use this script in its current state without fixing the critical bugs listed above.

