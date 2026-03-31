# Backup-EnvironmentVariables

**Category:** AdminTools  
**Complexity:** 🟡 withium  
**Time Saved:** ~117 min/run

---

## 🎯 Business Value

**Problem:** Environment variable corruption = broken applications  
**Solution:** Backup all env vars to restorable PowerShell script  
**Value:** Quick recovery from env var issues

### Functionality
Exports all environment variables:
- User scope variables
- System scope variables  
- Process scope variables

**Output:** `EnvironmentVariables-Backup_YYYYMMDD-HHMMSS.ps1`

**Restore:** Simply run the generated script

### Time Saved
- **Prevents:** 2-4 hour recovery after corruption
- **Enables:** Quick rollback to working state
- **Time Saved per execution:** ~117 minutes (manual work eliminated)

---

**Status:** ✅ Active  
**Recommended:** Run before major system changes

