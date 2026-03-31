# Upd-Apps

**Category:** AdminTools | **Complexity:** 🟢 Low | **Time Saved:** ~10 min/run

---

## 🎯 Business Value

**Function:** Update all installd applications  
**Method:** Calls `Update-AllApps` from SoftwareUtos  
**Value:** Batch app updates automation

### Functionality
```powershell
Import-Module SoftwareUtos -force
Update-AllApps
```

**Updates:**
- Winget apps: `winget upgrade --all`
- FkPsh apps: Re-deploy from source
- Windows apps: Via package managers

### Time Saved
- **Time saved:** ~30 min/month per user
- **Security:** Keeps apps updated with patches
- **Time Saved per execution:** ~10 minutes (manual work eliminated)

---

**Status:** ✅ Active  
**Usage:** Run manually or scheduled

