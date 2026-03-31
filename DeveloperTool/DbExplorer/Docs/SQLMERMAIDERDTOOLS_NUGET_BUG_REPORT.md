# SqlMermaidErdTools NuGet Package - Bug Report

**Status**: ✅ **RESOLVED IN v0.3.1**  
**Package**: SqlMermaidErdTools  
**Version with Issue**: 0.2.8  
**Version with Fix**: 0.3.1  
**Reported**: December 14, 2025  
**Resolved**: December 14, 2025 (same day!)  
**Original Severity**: CRITICAL  
**Resolution**: Package maintainer added proper MSBuild targets and bundled runtimes  

---

## ✅ RESOLUTION (v0.3.1)

**The package maintainer has FIXED all reported issues in version 0.3.1!**

### What Was Fixed
1. ✅ **Added `build/SqlMermaidErdTools.targets`** - MSBuild target file now properly deploys Python scripts
2. ✅ **Added `buildTransitive/` folder** - Ensures transitive dependencies get scripts too
3. ✅ **Bundled Python runtime** - Embedded Python 3.11.7 in `/runtimes/win-x64/python/`
4. ✅ **Bundled Node.js runtime** - Embedded Node.js in `/runtimes/win-x64/node/`
5. ✅ **Auto-deployment working** - Scripts automatically appear in `bin/Debug/net10.0-windows/scripts/`

### Verification (December 14, 2025)
```bash
dotnet add package SqlMermaidErdTools  # Gets v0.3.1
dotnet build
# ✅ Python scripts auto-deployed to bin/Debug/net10.0-windows/scripts/
# ✅ Python runtime at bin/Debug/net10.0-windows/runtimes/win-x64/python/python.exe
# ✅ All 4 core functions work out-of-the-box
```

### Impact
- **Before (v0.2.8)**: Package was broken, required manual workarounds
- **After (v0.3.1)**: Package is professional-grade, works perfectly out-of-the-box
- **Upgrade command**: `dotnet add package SqlMermaidErdTools` (automatically gets latest)

---

## Original Issue Report (v0.2.8)

### Issue Summary

The SqlMermaidErdTools NuGet package contains Python scripts in its `/scripts/` folder, but these scripts are **not automatically deployed** to consuming projects' output directories. This causes all core functionality to fail with "Python script not found" errors.

---

## Expected Behavior

When a project references SqlMermaidErdTools v0.2.8:
1. User adds package: `dotnet add package SqlMermaidErdTools`
2. User builds project: `dotnet build`
3. Python scripts should automatically appear in: `bin/Debug/net10.0/scripts/*.py`
4. All functions work without additional configuration

---

## Actual Behavior

When a project references SqlMermaidErdTools v0.2.8:
1. User adds package: `dotnet add package SqlMermaidErdTools` ✅
2. User builds project: `dotnet build` ✅
3. Python scripts are **NOT copied** to output directory ❌
4. All functions fail with errors ❌

---

## Error Messages

### ConvertSqlToMermaidAsync
```
[ERROR] Python script not found: sql_to_mmd.py
Checked:
- bin\Debug\net10.0\runtimes\win-x64\scripts\sql_to_mmd.py
- bin\Debug\net10.0\scripts\sql_to_mmd.py
```

### ConvertMermaidToSqlAsync
```
[ERROR] Python script not found: mmd_to_sql.py
```

### TranslateSqlDialectAsync
```
[ERROR] Python script not found: sql_dialect_translate.py
```

### GenerateMigrationFromMermaidDiffAsync
```
[ERROR] Python script not found: mmd_diff_to_sql.py
```

---

## Root Cause Analysis

### Package Structure (Current)

```
sqlmermaiderdtools/0.2.8/
├── lib/
│   └── net10.0/
│       └── SqlMermaidErdTools.dll
├── scripts/                           ✅ Scripts exist here
│   ├── mmd_diff_to_alter.py          ✅ 7,433 bytes
│   ├── mmd_diff_to_sql.py            ✅ 13,525 bytes
│   ├── mmd_to_sql.py                 ✅ 9,648 bytes
│   ├── sql_dialect_translate.py      ✅ 4,557 bytes
│   └── sql_to_mmd.py                 ✅ 25,380 bytes
├── icon.png
├── README.md
└── sqlmermaiderdtools.nuspec
```

### What's Missing

❌ **No `build/` folder**  
❌ **No `build/SqlMermaidErdTools.targets` file**  
❌ **No `buildTransitive/` folder**  
❌ **No `contentFiles/` folder**  

**Result**: MSBuild has no instructions to copy scripts to output directory.

---

## Impact

| Function | Status | Reason |
|----------|--------|--------|
| `SqlMermaidErdTools.ToMermaidAsync(sqlDdl)` | ❌ BROKEN | `sql_to_mmd.py` not deployed |
| `SqlMermaidErdTools.ToSqlAsync(mermaid, dialect)` | ❌ BROKEN | `mmd_to_sql.py` not deployed |
| `SqlMermaidErdTools.TranslateAsync(sql, from, to)` | ❌ BROKEN | `sql_dialect_translate.py` not deployed |
| `SqlMermaidErdTools.GenerateMigrationAsync(before, after, dialect)` | ❌ BROKEN | `mmd_diff_to_sql.py` not deployed |

**All core functionality is broken.**

---

## The Fix

### Required File: `build/SqlMermaidErdTools.targets`

Create this file in the package source:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  
  <!-- Copy Python scripts to output directory -->
  <ItemGroup>
    <Content Include="$(MSBuildThisFileDirectory)..\scripts\*.py">
      <Link>scripts\%(Filename)%(Extension)</Link>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
      <Visible>false</Visible>
    </Content>
  </ItemGroup>
  
  <!-- Build target to ensure deployment -->
  <Target Name="CopySqlMermaidPythonScripts" AfterTargets="Build">
    <Message Text="SqlMermaidErdTools: Deploying Python scripts to output" Importance="high" />
    <Copy 
      SourceFiles="$(MSBuildThisFileDirectory)..\scripts\mmd_diff_to_alter.py;
                   $(MSBuildThisFileDirectory)..\scripts\mmd_diff_to_sql.py;
                   $(MSBuildThisFileDirectory)..\scripts\mmd_to_sql.py;
                   $(MSBuildThisFileDirectory)..\scripts\sql_dialect_translate.py;
                   $(MSBuildThisFileDirectory)..\scripts\sql_to_mmd.py"
      DestinationFolder="$(OutputPath)scripts" 
      SkipUnchangedFiles="true" />
  </Target>
  
</Project>
```

### Update Package Build Configuration

**In the SqlMermaidErdTools.csproj:**

```xml
<ItemGroup>
  <!-- Include build targets in package -->
  <None Include="build\SqlMermaidErdTools.targets" Pack="true" PackagePath="build" />
  <None Include="build\SqlMermaidErdTools.targets" Pack="true" PackagePath="buildTransitive" />
  
  <!-- Include Python scripts in package -->
  <None Include="scripts\*.py" Pack="true" PackagePath="scripts" />
</ItemGroup>
```

**Or in the .nuspec file:**

```xml
<files>
  <!-- Build targets for MSBuild integration -->
  <file src="build\SqlMermaidErdTools.targets" target="build\SqlMermaidErdTools.targets" />
  <file src="build\SqlMermaidErdTools.targets" target="buildTransitive\SqlMermaidErdTools.targets" />
  
  <!-- Python scripts -->
  <file src="scripts\*.py" target="scripts" />
</files>
```

---

## Alternative Solution: contentFiles

If you prefer using `contentFiles` instead of build targets:

### Structure
```
contentFiles/
└── any/
    └── any/
        └── scripts/
            ├── mmd_diff_to_alter.py
            ├── mmd_diff_to_sql.py
            ├── mmd_to_sql.py
            ├── sql_dialect_translate.py
            └── sql_to_mmd.py
```

### In .nuspec
```xml
<contentFiles>
  <files include="any/any/scripts/*.py" buildAction="Content" copyToOutput="true" flatten="false" />
</contentFiles>

<files>
  <file src="scripts\mmd_diff_to_alter.py" target="contentFiles\any\any\scripts" />
  <file src="scripts\mmd_diff_to_sql.py" target="contentFiles\any\any\scripts" />
  <file src="scripts\mmd_to_sql.py" target="contentFiles\any\any\scripts" />
  <file src="scripts\sql_dialect_translate.py" target="contentFiles\any\any\scripts" />
  <file src="scripts\sql_to_mmd.py" target="contentFiles\any\any\scripts" />
</files>
```

---

## Testing the Fix

### Step 1: Build the Fixed Package
```bash
cd SqlMermaidErdTools
dotnet pack -c Release -o nupkg
```

### Step 2: Test in Clean Project
```bash
mkdir TestProject
cd TestProject
dotnet new console
dotnet add package SqlMermaidErdTools --version 0.2.9 --source ../SqlMermaidErdTools/nupkg
dotnet build
```

### Step 3: Verify Scripts are Deployed
```bash
ls bin/Debug/net*/scripts/*.py
```

**Expected output:**
```
bin/Debug/net10.0/scripts/mmd_diff_to_alter.py
bin/Debug/net10.0/scripts/mmd_diff_to_sql.py
bin/Debug/net10.0/scripts/mmd_to_sql.py
bin/Debug/net10.0/scripts/sql_dialect_translate.py
bin/Debug/net10.0/scripts/sql_to_mmd.py
```

### Step 4: Test Functionality
```csharp
using SqlMermaidErdTools;

var sql = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));";
var mermaid = await SqlMermaidErdTools.ToMermaidAsync(sql);
Console.WriteLine(mermaid); // Should work without errors
```

---

## Package Description Inconsistency

**Package Description Says:**
> "Zero-configuration - includes embedded Python runtime."

**Reality:**
- ✅ Python runtime IS embedded (works correctly)
- ❌ NOT zero-configuration (scripts don't auto-deploy)
- ⚠️ Requires manual workaround in every consuming project

**Recommendation**: After fixing, this will truly be "zero-configuration" ✅

---

## References: How Other Packages Handle This

### Selenium.WebDriver
- Uses `build/*.targets` to deploy browser drivers
- Drivers auto-copy to `bin/Debug/net*/drivers/`

### Microsoft.Web.WebView2
- Uses `runtimes/win-x64/native/` for native DLLs
- Auto-deploys WebView2Loader.dll via MSBuild

### Playwright
- Uses custom MSBuild targets
- Auto-installs browser binaries on first build

**All successful NuGet packages with runtime assets use build targets.**

---

## Recommended Version Number

Current: `0.2.8`  
Fixed: `0.2.9` (patch - fixes deployment bug)  

**Change Log for 0.2.9:**
```
- Fixed: Python scripts now auto-deploy to consuming projects
- Added: build/SqlMermaidErdTools.targets for MSBuild integration
- Fixed: Package now truly "zero-configuration" as advertised
```

---

## Severity Justification

**Why CRITICAL:**
- ❌ 100% of core functionality broken without workaround
- ❌ Package appears completely broken to new users
- ❌ No error in package installation (fails at runtime)
- ❌ No documentation of workaround
- ❌ Violates "zero-configuration" promise

**User Experience:**
1. Install package ✅
2. Write code ✅
3. Build succeeds ✅
4. Run application ❌ **Cryptic error**
5. Spend hours debugging ❌
6. Give up or find workaround manually ❌

---

## Summary

| Aspect | Status |
|--------|--------|
| Code Quality | ✅ Excellent |
| Python Runtime | ✅ Works perfectly |
| Scripts Content | ✅ All present in package |
| **Deployment Config** | ❌ **Missing** |
| User Experience | ❌ **Broken** |

**The Fix**: Add one file (`build/SqlMermaidErdTools.targets`) to package.  
**Effort**: ~15 minutes  
**Impact**: Makes package usable for all users  

---

## Package Metadata

- **Repository**: https://github.com/geirtul/SqlMermaidErdTools
- **Author**: Geir Helge Starholm
- **Company**: Dedge AS
- **License**: MIT
- **Last Updated**: 2025-12-01

---

**Recommendation**: Fix in v0.2.9 and publish immediately. This is a packaging issue, not a code issue, and has a simple solution with massive user experience improvement.

