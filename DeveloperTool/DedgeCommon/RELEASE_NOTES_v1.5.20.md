# DedgeCommon v1.5.20 - Release Notes

**Release Date:** 2025-12-16  
**Status:** Production Ready

---

## 🎯 What's New

### WorkObject Pattern - Dynamic Reporting System
Create beautiful HTML and JSON reports from your C# applications, identical to PowerShell scripts.

**Key Features:**
- ✅ Dynamic property container (like PowerShell PSCustomObject)
- ✅ Script execution tracking with timestamps
- ✅ JSON export for programmatic access
- ✅ HTML export with tabbed interface and Monaco editor
- ✅ Shared HTML template with PowerShell
- ✅ Dark/light theme toggle
- ✅ Syntax highlighting (DB2, SQL, PowerShell)
- ✅ Web publishing support

### COBOL Execution Fixes
Fixed critical bugs in COBOL program execution.

**Key Fixes:**
- ✅ Corrected path resolution (was using wrong folder)
- ✅ Monitor files now go to network location
- ✅ Added validation: Requires 100+ .int files for local folders
- ✅ Removed automatic folder creation (security improvement)

---

## 🚀 Quick Start

### WorkObject Usage (C#):
```csharp
using DedgeCommon;

var workObject = new WorkObject();
workObject.SetProperty("DatabaseName", "BASISPRO");
workObject.SetProperty("Success", true);

workObject.AddScriptExecution(
    "Backup", 
    "BACKUP DATABASE TO E:\\backups",
    "Completed in 145 seconds");

var exporter = new WorkObjectExporter();
exporter.ExportToJson(workObject, "report.json");
exporter.ExportToHtml(workObject, "report.html", "My Report", autoOpen: true);
```

### WorkObject Usage (PowerShell):
```powershell
$workObject = [PSCustomObject]@{ 
    DatabaseName = "BASISPRO"
    Success = $true
    ScriptArray = @() 
}

$workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject `
    -Name "Backup" `
    -Script "BACKUP DATABASE TO E:\backups" `
    -Output "Completed in 145 seconds"

Export-WorkObjectToHtmlFile -WorkObject $workObject `
    -FileName "report.html" -Title "My Report" -AutoOpen $true
```

**Both produce identical HTML reports with tabs and Monaco editor!**

---

## 📦 Installation

```xml
<PackageReference Include="Dedge.DedgeCommon" Version="1.5.20" />
```

Or use command:
```powershell
dotnet add package Dedge.DedgeCommon --version 1.5.20
```

---

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.5.20 | 2025-12-16 | WorkObject pattern + COBOL fixes |
| 1.5.13 | Previous | Baseline version |

**Recommendation:** Update to v1.5.20 for bug fixes and new features.

---

## 📚 Documentation

- **README.md** - Complete API documentation
- **README_WORKOBJECT.md** - WorkObject quick start guide
- **COBOL_FOLDER_RESOLUTION_EXPLAINED.md** - COBOL path details

---

**For detailed API documentation, see README.md**  
**For WorkObject examples, see README_WORKOBJECT.md**
