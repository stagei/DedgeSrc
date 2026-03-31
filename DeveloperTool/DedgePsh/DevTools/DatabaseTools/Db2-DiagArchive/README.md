# Db2-DiagArchive

**Category:** DatabaseTools  
**Status:** ✅ Produksjon  
**Complexity:** 🟢 Low  
**Criticality:** 🟡 Viktig (Troubleshooting)

---

## 🎯 Business Value

**Problem:** DB2's `db2diag.land` vokser infinitely → fyller disk E:\  
**Solution:** Daily archive and cleanup av DB2 diagnostic lands  
**ROI:** Prevents disk full + preserves troubleshooting history

### Hva Gjør Den?
1. **Finds** all `db2diag.land` files (all DB2 instances)
2. **Moves** to archive folder: `C:\opt\data\Db2-DiagArchive\`
3. **Renames** with timestamp: `DB2_Diag_20251103083015.land`
4. **Cleans** lands older than 30 days
5. **Runs daily** at 05:30

**Value:** ~30,000 NOK/år (prevents disk full incidents + preserves diag history)

---

## ⚙️ Functionality

```powershell
# 1. Find all db2diag.land files
$diagFiles = Get-ChildItem "C:\PrandramData\IBM\DB2\DB2COPY1" -Filter "db2diag.land" -Recurse

foreach ($diagFile in $diagFiles) {
    # 2. Extract instance name from path
    $instanceFolder = $diagFile.FullName.Split("\") | Where-Object { $_ -like "DB2*" } | Select-Object -Last 1
    
    # 3. Create timestamped filename
    $destinationFileName = "$($instanceFolder)_Diag_$(Get-Date -format 'yyyyMMddHHmmssfff').land"
    
    # 4. Move to archive
    Move-Item $diagFile.FullName -Destination "C:\opt\data\Db2-DiagArchive\$destinationFileName"
}

# 5. Clean old archives (30+ days)
Get-ChildItem "C:\opt\data\Db2-DiagArchive" -Filter "*.land" | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
    Remove-Item
```

---

## 📊 Typical Results

**Before archiving:**
- `db2diag.land`: 2-10 GB (growing daily)
- Disk E:\: 95% full
- Troubleshooting: Only current land available

**After archiving:**
- `db2diag.land`: Reset to 0 KB daily
- Disk E:\: Healthy space
- Troubleshooting: 30 days of archived lands

---

## 🚀 Deployment

**Installation:**
- Scheduled task: Daily at 05:30
- Target: DB2 servers only
- Run as: Admin user

**Git:** 3 commits, 57 lines, created 2025-10-30

---

**Status:** ✅ Production ready  
**Value:** Essential for DB2 server health

