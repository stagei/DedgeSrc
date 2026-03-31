# Rename Summary: ServerMonitor → ServerMonitor

## ✅ Completed - Files and Folders Renamed

### Solution File
- ✅ `ServerMonitor.sln` → `ServerMonitor.sln`

### Installation Scripts
- ✅ `Install-ServerSurveillanceService.ps1` → `ServerMonitorAgent`

### Project Folders
- ✅ `src/ServerMonitor/` → `src/ServerMonitor/`
- ✅ `src/ServerMonitor.Core/` → `src/ServerMonitor.Core/`
- ✅ `tests/ServerMonitor.Tests/` → `tests/ServerMonitor.Tests/`

### Project Files
- ✅ `src/ServerMonitor/ServerMonitor.csproj` → `src/ServerMonitor/ServerMonitor.csproj`
- ✅ `src/ServerMonitor.Core/ServerMonitor.Core.csproj` → `src/ServerMonitor.Core/ServerMonitor.Core.csproj`
- ✅ `tests/ServerMonitor.Tests/ServerMonitor.Tests.csproj` → `tests/ServerMonitor.Tests/ServerMonitor.Tests.csproj`

---

## 🔧 User Action Required - String Replacements in Code

### Files That Need String Updates

#### 1. **All .cs Files**
Replace in:
- Namespace declarations
- Using statements
- Comments/documentation

**Find:** `ServerMonitor`  
**Replace:** `ServerMonitor`

Affected files:
- All files in `src/ServerMonitor/*.cs`
- All files in `src/ServerMonitor.Core/**/*.cs`
- All files in `tests/ServerMonitor.Tests/*.cs`

#### 2. **Project Files (.csproj)**

**Files to update:**
- `src/ServerMonitor/ServerMonitor.csproj`
- `src/ServerMonitor.Core/ServerMonitor.Core.csproj`
- `tests/ServerMonitor.Tests/ServerMonitor.Tests.csproj`

**Updates needed:**
```xml
<!-- Update RootNamespace -->
<RootNamespace>ServerMonitor</RootNamespace>  <!-- was ServerMonitor -->

<!-- Update AssemblyName -->
<AssemblyName>ServerMonitor</AssemblyName>  <!-- was ServerMonitor -->

<!-- Update ProjectReference paths -->
<ProjectReference Include="..\ServerMonitor.Core\ServerMonitor.Core.csproj" />
<!-- was ..\ServerMonitor.Core\ServerMonitor.Core.csproj -->
```

#### 3. **Solution File (ServerMonitor.sln)**

Update project paths:
```
Project("{...}") = "ServerMonitor", "src\ServerMonitor\ServerMonitorAgent\ServerMonitor.csproj", "{...}"
Project("{...}") = "ServerMonitor.Core", "src\ServerMonitor.Core\ServerMonitor.Core.csproj", "{...}"
Project("{...}") = "ServerMonitor.Tests", "tests\ServerMonitor.Tests\ServerMonitor.Tests.csproj", "{...}"
```

#### 4. **ServerMonitorAgent**

Update:
```powershell
# Service name
$ServiceName = "ServerMonitor"  # was ServerMonitor

# Display name
$DisplayName = "Server Monitor"  # was Server Surveillance Tool

# Description
$Description = "Monitors server health..."  # update description

# ExePath default
$ExePath = "$PSScriptRoot\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
# was ...ServerMonitor\...\ServerMonitor.exe

# Firewall rule name
# Update any references to service name
```

#### 5. **NLog.config**

Check for any references:
```xml
<!-- Update EventLog source if present -->
<target xsi:type="EventLog" source="ServerMonitor" ... />
<!-- was source="ServerMonitor" -->
```

#### 6. **appsettings.json**

Already updated by user:
```json
{
  "Logging": {
    "LogDirectory": "C:\\opt\\data\\ServerMonitor",  ✅ Already done
    "AppName": "ServerMonitor"                       ✅ Already done
  }
}
```

#### 7. **Documentation Files**

Update references in:
- `README.md`
- `SERVICE-INSTALLATION-GUIDE.md`
- `GLOBAL-SNAPSHOT-IMPLEMENTATION.md`
- `SEQUENTIAL-ALERT-ARCHITECTURE.md`
- `REST-API-IMPLEMENTATION.md`
- Any other `.md` files with references

---

## 🔍 Recommended Find & Replace Approach

### In Visual Studio / VS Code

1. **Open Solution**
   - Open `ServerMonitor.sln`

2. **Find & Replace Across Solution**
   - Press `Ctrl+Shift+H` (VS) or `Ctrl+Shift+F` (VS Code)
   - Find: `ServerMonitor`
   - Replace: `ServerMonitor`
   - Scope: **Entire Solution**
   - Match case: **Yes**
   - Click **Replace All**

3. **Verify Changes**
   - Review changed files
   - Look for any issues (e.g., comments that shouldn't be changed)

4. **Rebuild Solution**
   ```powershell
   dotnet clean
   dotnet build
   ```

5. **Run Tests**
   ```powershell
   dotnet test
   ```

### Using PowerShell (Alternative)

```powershell
# Navigate to project root
cd C:\opt\src\ServerMonitor

# Replace in all .cs files
Get-ChildItem -Recurse -Filter "*.cs" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'ServerMonitor', 'ServerMonitor' | 
    Set-Content $_.FullName
}

# Replace in all .csproj files
Get-ChildItem -Recurse -Filter "*.csproj" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'ServerMonitor', 'ServerMonitor' | 
    Set-Content $_.FullName
}

# Replace in solution file
(Get-Content "ServerMonitor.sln") -replace 'ServerMonitor', 'ServerMonitor' | 
Set-Content "ServerMonitor.sln"

# Replace in install script
(Get-Content "ServerMonitorAgent") -replace 'ServerMonitor', 'ServerMonitor' | 
Set-Content "ServerMonitorAgent"

# Replace in markdown docs
Get-ChildItem -Recurse -Filter "*.md" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'ServerMonitor', 'ServerMonitor' | 
    Set-Content $_.FullName
}
```

---

## ✅ Verification Checklist

After making string replacements:

- [ ] Solution builds without errors: `dotnet build`
- [ ] All tests pass: `dotnet test`
- [ ] Project references are correct in all `.csproj` files
- [ ] Solution file references correct project paths
- [ ] Install script has correct service name and paths
- [ ] NLog EventLog source updated
- [ ] Documentation updated
- [ ] No remaining references to "ServerMonitor" (use Find in Files)

---

## 📊 Summary

| Category | Items Renamed | Status |
|----------|---------------|--------|
| Solution File | 1 | ✅ Complete |
| Script Files | 1 | ✅ Complete |
| Project Folders | 3 | ✅ Complete |
| Project Files | 3 | ✅ Complete |
| **Total** | **8** | **✅ Complete** |
| Code Strings | ~500+ | 🔧 **User Action Required** |

---

**All file and folder renames are complete!**  
**Ready for code string replacements.** 🚀

