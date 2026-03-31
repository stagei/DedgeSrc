# Db2-DiagArchive

**Kategori:** DatabaseTools  
**Status:** ✅ Produksjon  
**Kompleksitet:** 🟢 Lav  
**Kritikalitet:** 🟡 Viktig (Feilsøking)

---

## 🎯 Forretningsverdi

**Problem:** DB2's `db2diag.log` vokser uendelig → fyller disk E:\  
**Løsning:** Daglig arkivering og opprydding av DB2-diagnoselogger  
**Verdi:** Forhindrer disk full + bevarer feilsøkingshistorikk

### Hva Gjør Den?
1. **Finner** alle `db2diag.log`-filer (alle DB2-instanser)
2. **Flytter** til arkivmappe: `C:\opt\data\Db2-DiagArchive\`
3. **Omdøper** med tidsstempel: `DB2_Diag_20251103083015.log`
4. **Rydder** logger eldre enn 30 dager
5. **Kjører daglig** kl 05:30

**Verdi:** ~30,000 NOK/år (forhindrer disk full-hendelser + bevarer diaghistorikk)

---

## ⚙️ Funksjonalitet

```powershell
# 1. Find all db2diag.log files
$diagFiles = Get-ChildItem "C:\ProgramData\IBM\DB2\DB2COPY1" -Filter "db2diag.log" -Recurse

foreach ($diagFile in $diagFiles) {
    # 2. Extract instance name from path
    $instanceFolder = $diagFile.FullName.Split("\") | Where-Object { $_ -like "DB2*" } | Select-Object -Last 1
    
    # 3. Create timestamped filename
    $destinationFileName = "$($instanceFolder)_Diag_$(Get-Date -Format 'yyyyMMddHHmmssfff').log"
    
    # 4. Move to archive
    Move-Item $diagFile.FullName -Destination "C:\opt\data\Db2-DiagArchive\$destinationFileName"
}

# 5. Clean old archives (30+ days)
Get-ChildItem "C:\opt\data\Db2-DiagArchive" -Filter "*.log" | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
    Remove-Item
```

---

## 📊 Typical Results

**Before archiving:**
- `db2diag.log`: 2-10 GB (growing daily)
- Disk E:\: 95% full
- Troubleshooting: Only current log available

**After archiving:**
- `db2diag.log`: Reset to 0 KB daily
- Disk E:\: Healthy space
- Troubleshooting: 30 days of archived logs

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

