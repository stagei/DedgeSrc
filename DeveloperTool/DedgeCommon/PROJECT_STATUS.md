# DedgeCommon - Project Status

**Version:** 1.5.26  
**Date:** 2025-12-16  
**Status:** ✅ Production Ready - Bug Fixed

---

## 📦 Current Version Features

### WorkObject Pattern (v1.5.19-1.5.20)
- Dynamic property container for execution tracking
- JSON and HTML export with tabs and Monaco editor
- **3-level Monaco fallback:** Local → CDN → Plain text
- Works offline (automatic fallback to plain text)
- Shared template system (PowerShell & C#)
- See: `README_WORKOBJECT.md` for quick start

### COBOL Fixes (v1.5.14-1.5.18)
- Fixed path resolution bugs
- Added 100+ .int file validation
- Removed automatic folder creation
- Monitor files go to network location

---

## 📚 Documentation

### Essential Docs (Keep Updated):
- **README.md** - Main API documentation
- **README_WORKOBJECT.md** - WorkObject quick start
- **RELEASE_NOTES_v1.5.20.md** - Current release notes
- **.cursorrules** - Project and documentation rules

### Architecture Docs (Reference):
- **ARCHITECTURE_FKENVIRONMENTSETTINGS_INTEGRATION.md** - Design decisions
- **COBOL_FOLDER_RESOLUTION_EXPLAINED.md** - COBOL path logic
- **POSTGRESQL_SUPPORT.md** - PostgreSQL integration
- **ENV_VAR_EXAMPLES.md** - Environment variable reference

### Archived:
- **_old/** - Previous implementation summaries
- **_old_reports/** - Session summaries and temporary docs

---

## 🧪 Testing

**C# Test:** `TestWorkObject` - 15/15 passed ✅  
**PowerShell Test:** `Test-WorkObjectExport.ps1` - 15/15 passed ✅  
**Total:** 30/30 tests passed ✅

---

## 📦 Deployment

**Package:** Dedge.DedgeCommon v1.5.26  
**Feed:** Azure DevOps Dedge  
**Install:**
```xml
<PackageReference Include="Dedge.DedgeCommon" Version="1.5.26" />
```

**Latest Fix (v1.5.26):**
- Fixed `.GetString()` bug in GlobalFunctions.cs
- Changed to proper `(string)` casts for Newtonsoft.Json
- GlobalSettings.json now loads correctly
- Web publishing works when GlobalSettings accessible

---

## 🎯 Next Actions (For Operations Team)

### For GetPeppolDirectory (Pending):
1. Update package reference to v1.5.20
2. Test on development server
3. Verify COBOL execution works (AABELMA program)
4. Check file locations (.rc, .mfout in correct path)
5. Verify monitor files go to network share (cobnt/monitor or cobtst/monitor)
6. Deploy to production after successful testing

### For Other Applications:
- Consider using WorkObject pattern for execution reports
- Update to v1.5.20 for COBOL bug fixes (if using RunCblProgram)

---

## 📋 Quick Reference

### Deploy New Version:
The Azure-NugetVersionPush script is searched in this order:
1. `C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1`
2. `$env:OptPath\DedgePshApps\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1`
3. If not found: Run `Inst-Psh Azure-NugetVersionPush` then search again

### Test WorkObject:
```powershell
# C# test
cd c:\opt\src\DedgeCommon\TestWorkObject
dotnet run

# PowerShell test
pwsh -File "C:\opt\src\DedgePsh\_Modules\GlobalFunctions\Test-WorkObjectExport.ps1"
```

---

**Last Updated:** 2025-12-16  
**Maintained By:** Geir Helge Starholm
