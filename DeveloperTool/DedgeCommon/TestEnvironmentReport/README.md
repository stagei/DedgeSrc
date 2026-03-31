# Environment Report Test Program

**Purpose:** Generate comprehensive environment settings report from any server or workstation.

---

## 📋 Overview

This program tests and reports on:
- ✅ FkEnvironmentSettings auto-detection
- ✅ Database configuration
- ✅ COBOL executable detection
- ✅ Network drive mapping status
- ✅ File system accessibility
- ✅ Database connectivity

---

## 🚀 Quick Start

### Build and Run Locally
```powershell
cd C:\opt\src\DedgeCommon\TestEnvironmentReport
dotnet run
```

### Publish for Deployment
```powershell
cd C:\opt\src\DedgeCommon\TestEnvironmentReport
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

Output: `bin\Release\net8.0\win-x64\publish\TestEnvironmentReport.exe`

---

## 📤 Deploy to Server

### Option 1: Copy Single File
```powershell
# After publishing, copy the single exe file
Copy-Item bin\Release\net8.0\win-x64\publish\TestEnvironmentReport.exe \\server-name\c$\Temp\
```

### Option 2: Use Provided Deployment Script
```powershell
.\Deploy-EnvironmentTest.ps1 -ComputerName "p-no1fkmtst-app"
```

---

## 💻 Usage

### Basic Usage (Auto-detect everything)
```powershell
TestEnvironmentReport.exe
```

**Output:**
- Console display of all settings
- `EnvironmentReport_<ComputerName>_<DateTime>.txt` - Text report
- `EnvironmentReport_<ComputerName>_<DateTime>.json` - JSON report

### Test ALL Databases (Comprehensive Verification)
```powershell
TestEnvironmentReport.exe --test-all-databases
```

**What it does:**
- Tests FkEnvironmentSettings with EVERY database name from DatabasesV2.json
- Verifies each database name and alias resolves correctly
- Checks COBOL object paths for each database
- Generates detailed report showing which databases work/fail
- Groups results by Application/Environment

**Output:**
- `AllDatabasesTest_<ComputerName>_<DateTime>.txt` - Detailed text report
- `AllDatabasesTest_<ComputerName>_<DateTime>.json` - JSON data
- Shows success rate (e.g., "45/46 databases passed")

**Use this to verify:** FkEnvironmentSettings works correctly with all your database configurations!

### Map Network Drives Automatically
```powershell
TestEnvironmentReport.exe --map-drives
```

Maps all standard Dedge drives (F, K, N, R, X) before running the report.

### With Override Database
```powershell
TestEnvironmentReport.exe BASISTST
```

### Skip Database Connectivity Test
```powershell
TestEnvironmentReport.exe --no-db-test
```

### Send Email Report
```powershell
TestEnvironmentReport.exe --email
```

**Note:** Email recipient can be set via environment variable:
```powershell
$env:REPORT_EMAIL = "your.email@Dedge.no"
TestEnvironmentReport.exe --email
```

### Combined Options
```powershell
# Map drives, override database, send email
TestEnvironmentReport.exe FKMPRD --map-drives --email

# Test all databases and email results
TestEnvironmentReport.exe --test-all-databases --email

# Auto-detect, skip DB test, map drives
TestEnvironmentReport.exe --no-db-test --map-drives
```

---

## 📄 Report Sections

### Section 1: Environment Settings
- Computer name and current user
- Server detection (Is Server: true/false)
- Application and Environment (auto-detected from server name)
- Database configuration
- COBOL version (MF/VC)
- All file paths (COBOL, DedgePshApps, EDI, D365)
- COBOL executable detection results

### Section 2: Database Connectivity Test
- Connection test using detected database
- Simple query execution
- Authentication verification (Kerberos/SSO status)

### Section 3: Network Drives
- Currently mapped drives
- Status of standard Dedge drives (F, K, N, R, X)
- Path verification

### Section 4: File System Access
- COBOL Object Path accessibility test
- DedgePshApps path test
- EDI path test
- File counting in accessible paths

### Section 5: Access Point Details
- Complete database access point information
- Connection details
- Authentication type
- Priority and status

### Section 6: Summary
- Overall status (✓ OK or ✗ FAILED)
- Component-by-component status
- List of any errors/warnings

---

## 📊 Example Report Output

```
═══════════════════════════════════════════════════════════
       DedgeCommon Environment Settings Report
═══════════════════════════════════════════════════════════

Computer Name:    P-NO1FKMTST-APP
Current User:     DEDGE\FKMAPP
Report Time:      2025-12-16 18:00:00
OS Version:       Microsoft Windows NT 10.0.26100.0
.NET Version:     8.0.11

───────────────────────────────────────────────────────────
  SECTION 1: ENVIRONMENT SETTINGS
───────────────────────────────────────────────────────────
✓ Environment detected successfully

  Is Server:              True
  Application:            FKM
  Environment:            TST
  Database:               BASISTST
  Database Internal Name: FKMTST
  COBOL Version:          MF

  Database Server:        t-no1fkmtst-db
  Database Provider:      DB2
  Database App:           FKM
  Database Env:           TST

  COBOL Object Path:      \\DEDGE.fk.no\erpprog\cobtst\
  DedgePshApps Path:         C:\opt\DedgePshApps\
  EDI Standard Path:      \\DEDGE.fk.no\ERPdata\EDI

  COBOL Executables:
    ✓ Runtime (run.exe):   C:\Program Files\Micro Focus\Server 5.1\Bin\run.exe
    ✓ Windows Runtime:     C:\Program Files\Micro Focus\Server 5.1\Bin\runw.exe
    - Compiler:            Not found (OK for runtime-only servers)
    - DialogSystem:        Not found (OK for runtime-only servers)

───────────────────────────────────────────────────────────
  SECTION 2: DATABASE CONNECTIVITY TEST
───────────────────────────────────────────────────────────
Testing connection to database: BASISTST

✓ Database handler created successfully
✓ Database connection successful
✓ Test query executed successfully (1 row)

───────────────────────────────────────────────────────────
  SECTION 3: NETWORK DRIVES
───────────────────────────────────────────────────────────
Found 5 mapped network drives:
  ✓ F: → \\DEDGE.fk.no\Felles
  ✓ K: → \\DEDGE.fk.no\erputv\Utvikling
  ✓ N: → \\DEDGE.fk.no\erpprog
  ✓ R: → \\DEDGE.fk.no\erpdata
  ✓ X: → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon

Standard Dedge Drives Status:
  ✓ F: drive is mapped
  ✓ K: drive is mapped
  ✓ N: drive is mapped
  ✓ R: drive is mapped
  ✓ X: drive is mapped

───────────────────────────────────────────────────────────
  SECTION 6: SUMMARY
───────────────────────────────────────────────────────────
  Environment Settings:   ✓ OK
  COBOL Runtime:          ✓ Found
  COBOL Path Access:      ✓ Accessible
  Database Connection:    ✓ OK
  Network Drives:         5 mapped

✅ All checks passed successfully!

═══════════════════════════════════════════════════════════
```

---

## 🎯 Use Cases

### Use Case 1: Verify New Server Setup
Deploy to a newly configured server to verify:
- Database auto-detection is working
- Network drives are mapped correctly
- COBOL runtime is installed and detected
- File system permissions are correct

### Use Case 2: Troubleshoot Server Issues
When a server is having issues:
- Run the report to see what's missing
- Compare report with working server
- Identify configuration differences

### Use Case 3: Document Server Configuration
Generate reports from all servers for documentation:
- Inventory of all environments
- COBOL version tracking
- Network configuration audit

### Use Case 4: Verify After Updates
After updating DedgeCommon library:
- Verify auto-detection still works
- Confirm database connectivity
- Check for any regression issues

---

## 📧 Email Reporting

### Setup Email Recipient
```powershell
# Set environment variable for email recipient
[Environment]::SetEnvironmentVariable("REPORT_EMAIL", "your.email@Dedge.no", "User")

# Or set for current session only
$env:REPORT_EMAIL = "your.email@Dedge.no"
```

### Send Report
```powershell
TestEnvironmentReport.exe --email
```

The email will contain:
- Subject: `[Environment Report] ✓ All OK on <ComputerName>` (or ⚠️ Issues Found)
- Body: Full text report
- Sent via DedgeCommon Notification system

---

## 🔧 Deployment Script

### Deploy-EnvironmentTest.ps1

Create this script to easily deploy and run on multiple servers:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ComputerNameList,
    
    [Parameter(Mandatory = $false)]
    [string]$OverrideDatabase,
    
    [Parameter(Mandatory = $false)]
    [switch]$SendEmail
)

# Build and publish
Write-Host "Building TestEnvironmentReport..." -ForegroundColor Yellow
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true

$exePath = "bin\Release\net8.0\win-x64\publish\TestEnvironmentReport.exe"

foreach ($computerName in $ComputerNameList) {
    Write-Host "`nDeploying to $computerName..." -ForegroundColor Cyan
    
    # Copy to server
    $destPath = "\\$computerName\c$\Temp\TestEnvironmentReport.exe"
    Copy-Item $exePath $destPath -Force
    
    # Execute remotely
    $args = ""
    if ($OverrideDatabase) { $args += " $OverrideDatabase" }
    if ($SendEmail) { $args += " --email" }
    
    Write-Host "Executing on $computerName..." -ForegroundColor Yellow
    Invoke-Command -ComputerName $computerName -ScriptBlock {
        param($args)
        Set-Location C:\Temp
        .\TestEnvironmentReport.exe $args
    } -ArgumentList $args
    
    # Retrieve reports
    $reportFiles = Get-ChildItem "\\$computerName\c$\Temp\EnvironmentReport_*.txt" -ErrorAction SilentlyContinue
    if ($reportFiles) {
        foreach ($file in $reportFiles) {
            $localPath = "Reports\$($file.Name)"
            Copy-Item $file.FullName $localPath -Force
            Write-Host "  Report saved to: $localPath" -ForegroundColor Green
        }
    }
}

Write-Host "`nDeployment complete!" -ForegroundColor Green
```

---

## 🎨 Output Files

### Text Report
**File:** `EnvironmentReport_<ComputerName>_<DateTime>.txt`
- Human-readable format
- Section-based organization
- Status indicators (✓, ✗, ⚠️)
- Easy to read and share

### JSON Report
**File:** `EnvironmentReport_<ComputerName>_<DateTime>.json`
- Machine-readable format
- Complete settings object
- Can be imported for comparison
- Useful for automation

---

## 🔍 Troubleshooting

### "COBOL Runtime NOT FOUND"
- Install Micro Focus COBOL on the server
- Or set BIN_FOLDER environment variable to runtime path

### "Database connectivity test FAILED"
- Check network connectivity to database server
- Verify Kerberos authentication is configured
- Check that DatabasesV2.json is accessible

### "COBOL Object Path NOT accessible"
- Check network drive mappings
- Verify permissions to UNC path
- Ensure path exists on network

### "Network drives NOT mapped"
- Run `NetworkShareManager.MapAllDrives()` first
- Or manually map drives
- Check network connectivity

---

## ✅ Success Criteria

A successful report shows:
- ✓ Environment Settings: OK
- ✓ COBOL Runtime: Found
- ✓ COBOL Path Access: Accessible
- ✓ Database Connection: OK
- ✓ Network Drives: All 5 standard drives mapped

---

## 🚀 Next Steps After Report

### If All OK
1. Server is properly configured
2. DedgeCommon applications will work correctly
3. COBOL programs can execute
4. Database connections will succeed

### If Errors Found
1. Review specific errors in Section 6
2. Fix configuration issues
3. Re-run report to verify fixes
4. Compare with working server report

---

**Created:** 2025-12-16  
**Purpose:** Server environment verification and documentation  
**Status:** Ready for deployment
