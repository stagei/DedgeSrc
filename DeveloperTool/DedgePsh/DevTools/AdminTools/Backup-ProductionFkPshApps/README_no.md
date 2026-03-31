# Backup-ProductionDedgePshApps

**Kategori:** AdminTools | **Kompleksitet:** 🟢 Lav | **Kritikalitet:** 🔴 HØY  
**Tidsbesparelse:** ~93 min/kjøring

---

## 🎯 Forretningsverdi

**Problem:** Risiko for tap av produksjonskode  
**Løsning:** Daglig backup av C:\opt\DedgePshApps til arkiv  
**Verdi:** Kode-tilbakerulling evne + katastrofegjenoppretting

### Funksjonalitet
- Zipper hele `C:\opt\DedgePshApps` mappen
- Lagrer til: `C:\opt\data\Backup-ProductionDedgePshApps\COMPUTERNAME_YYYYMMDD-HHMMSS.zip`
- Beholder 10 dagers backups
- Kjører daglig via planlagt oppgave

**Kode:**
```powershell
$localDedgePshAppsFolder = "$env:OptPath\DedgePshApps"
$zipFileName = "$env:COMPUTERNAME_$(Get-Date -Format "yyyyMMdd-HHmmss").zip"
Compress-Archive -Path $localDedgePshAppsFolder -DestinationPath $zipFilePath
```

### Tidsbesparelse
- **Forhindrer:** Kodetap fra utilsiktede slettinger/korrupsjon
- **Muliggjør:** Rask tilbakerulling til tidligere versjoner
- **Tidsbesparelse per kjøring:** ~93 minutter (manuelt arbeid eliminert)

---

**Status:** ✅ Produksjon  
**Distribusjon:** Planlagt daglig

