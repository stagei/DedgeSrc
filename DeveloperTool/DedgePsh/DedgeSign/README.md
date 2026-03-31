# DedgeSign

**Category:** AdminTools  
**Complexity:** 🟡 withium  
**Criticality:** 🔴 CRITICAL  
**Time Saved:** ~33 min/run

---

## 🎯 Business Value

**Problem:** Unsigned scripts = Security warnings and execution blocks  
**Solution:** Azure Trusted Signing for code signing  
**Value:** Security compliance + production Deployment capability

### Functionality
Azure Trusted Signing Tool - adds/removes digital signatures

**Features:**
- Sign PowerShell scripts, .exe, .dll files
- Recursive directory support
- Add or Remove signatures
- Azure-based trusted signing

**Usage:**
```powershell
.\DedgeSign.ps1 -Path "script.ps1" -Action Add
.\DedgeSign.ps1 -Path "C:\Apps" -Recursive -Action Add
.\DedgeSign.ps1 -Path "file.exe" -Action Remove
```

### Time Saved
- **Security:** All production scripts must be signed
- **Compliance:** Meets security requirements
- **User experience:** No security warnings
- **Time Saved per execution:** ~33 minutes (manual work eliminated)

---

**Status:** ✅ CRITICAL for production  
**Deployment:** Used in all production Deployments

