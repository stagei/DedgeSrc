# TestEnvironmentReport - Quick Start Guide

**Purpose:** Verify FkEnvironmentSettings and server configuration

---

## 🚀 Quick Commands

### Test All Databases (Recommended First Run)
```powershell
cd C:\opt\src\DedgeCommon\TestEnvironmentReport
dotnet run -- --test-all-databases
```

**What it does:**
- Tests FkEnvironmentSettings with ALL 31 database names
- Verifies dual lookup (database name + alias)
- Checks COBOL paths
- Generates detailed report

**Expected Result:**
```
✅ Success: 31/31
✗ Failures: 0/31
Success Rate: 100.0%
```

**Output Files:**
- `AllDatabasesTest_<Computer>_<DateTime>.txt`
- `AllDatabasesTest_<Computer>_<DateTime>.json`

---

### Map Drives & Test Environment
```powershell
dotnet run -- --map-drives
```

**What it does:**
- Maps all standard Dedge drives (F, K, N, R, X)
- Tests current environment
- Verifies database connectivity
- Checks file access

**Expected Result:**
```
✓ All drives mapped
✅ REPORT COMPLETED SUCCESSFULLY
```

---

### Test Specific Database
```powershell
dotnet run -- BASISTST
```

Verifies environment configuration for specific database.

---

### Full Server Verification
```powershell
dotnet run -- --map-drives --email
```

Complete server check with email notification.

---

## 📤 Deploy to Servers

### Build Single-File Executable
```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

Output: `bin\Release\net8.0\win-x64\publish\TestEnvironmentReport.exe`

### Deploy Using Script
```powershell
.\Deploy-EnvironmentTest.ps1 -ComputerNameList @(
    "p-no1fkmprd-app",
    "t-no1fkmtst-app",
    "t-no1fkmdev-app"
) --email
```

**The script will:**
1. Build the application
2. Copy to each server's C:\Temp
3. Execute remotely
4. Collect reports to local `Reports/` folder
5. Show summary of success/failures

---

## 📊 Understanding Reports

### All Databases Test Report Shows:

**Section 1: Results by App/Env**
```
FKM/TST:
  BASISTST         BASISTST        | Path: ✓ \\DEDGE.fk.no\erpprog\cobtst\
  FKMTST           BASISTST        | Path: ✓ \\DEDGE.fk.no\erpprog\cobtst\
```

**Meaning:**
- Both FKMTST (database name) and BASISTST (alias) work
- Both resolve to the same alias: BASISTST
- COBOL path is accessible (✓)

**Section 2: Path Accessibility**
```
✓ \\DEDGE.fk.no\erpprog\cobtst\
   Used by: BASISTST, BASISTST, FKKTOTST, FKKTOTST
```

Shows which path is used by which databases.

---

## 🔍 Troubleshooting

### Test Shows Failures
Check the report for specific error messages:
- Database not found → Check DatabasesV2.json
- Path not accessible → Check network/permissions
- Runtime not found → Install Micro Focus COBOL

### Network Drives Won't Map
- Check network connectivity
- Verify UNC paths are accessible
- Check Windows credentials
- Review firewall rules

### Can't Connect to Database
- Verify Kerberos authentication configured
- Check database server is running
- Test network connectivity to server
- Review DatabasesV2.json configuration

---

## ✅ Success Criteria

### All Databases Test
- ✅ 31/31 databases should pass
- ✅ All paths should be accessible (or note which aren't)
- ✅ No error messages in report

### Environment Report
- ✅ Environment Settings: OK
- ✅ COBOL Runtime: Found
- ✅ COBOL Path Access: Accessible
- ✅ Database Connection: OK (if not skipped)
- ✅ Network Drives: All mapped (on servers)

---

## 💡 Pro Tips

### Tip 1: Test Before Server Deployment
```powershell
# Test locally first with all databases
dotnet run -- --test-all-databases

# If 100% pass locally, safe to deploy to servers
```

### Tip 2: Collect Server Inventory
```powershell
# Deploy to all servers
.\Deploy-EnvironmentTest.ps1 -ComputerNameList @("*-app", "*-db")

# Review Reports/ folder for complete inventory
```

### Tip 3: Verify After Changes
```powershell
# After updating DatabasesV2.json or DedgeCommon
dotnet run -- --test-all-databases

# Ensures no regressions
```

### Tip 4: Email for Remote Servers
```powershell
# Set recipient once
$env:REPORT_EMAIL = "your.email@Dedge.no"

# Then use --email flag
dotnet run -- --map-drives --email
```

---

## 🎯 What Each Test Validates

| Test Mode | Validates |
|-----------|-----------|
| `--test-all-databases` | All database names resolve correctly |
| `--map-drives` | Network drive mapping works |
| `<DatabaseName>` | Specific database configuration |
| `--no-db-test` | Everything except DB connectivity |
| `--email` | Email notification system |

---

## 📈 Current Test Results

From workstation 30237-FK:

**All Databases Test:**
- ✅ 31/31 passed (100%)
- ✅ All dual lookups working
- ✅ All paths correctly mapped
- ✅ 9 unique COBOL paths identified

**Drive Mapping:**
- ✅ 5/5 standard drives mapped
- ✅ All paths accessible
- ✅ No errors

**Environment Detection:**
- ✅ Correctly identified as workstation
- ✅ Default to FKM/PRD (BASISPRO)
- ✅ All COBOL executables found

---

## 🚀 Ready for Production

The test suite validates:
- ✅ FkEnvironmentSettings class is fully functional
- ✅ NetworkShareManager drive mapping works
- ✅ Database auto-detection is correct
- ✅ All database configurations are valid
- ✅ System ready for deployment

**Next:** Deploy to servers and verify auto-detection in real environments!

---

**Quick Start Guide Updated:** 2025-12-16 18:52  
**Test Status:** ✅ All systems verified locally  
**Recommendation:** Proceed with server deployment
