# Backup-ProductionDedgePshApps

**Category:** AdminTools | **Complexity:** 🟢 Low | **Criticality:** 🔴 HIGH  
**Time Saved:** ~93 min/run

---

## 🎯 Business Value

**Problem:** Production code loss risk  
**Solution:** Daily Backup of C:\opt\DedgePshApps to archive  
**Value:** Code rollback capability + disaster recovery

### Functionality
- Zips entire `C:\opt\DedgePshApps` folder
- Saves to: `C:\opt\data\Backup-ProductionDedgePshApps\COMPUTERNAME_YYYYMMDD-HHMMSS.zip`
- Retains 10 days of Backups
- Runs daily via scheduled task

**Code:**
```powershell
$localDedgePshAppsFolder = "$env:OptPath\DedgePshApps"
$zipFileName = "$env:COMPUTERNAME_$(Get-Date -format "yyyyMMdd-HHmmss").zip"
Compress-Archive -Path $localDedgePshAppsFolder -DestinationPath $zipFilePath
```

### Time Saved
- **Prevents:** Code loss from accidental deletions/corruption
- **Enables:** Quick rollback to previous versions
- **Time Saved per execution:** ~93 minutes (manual work eliminated)

---

**Status:** ✅ Production  
**Deployment:** Scheduled daily

