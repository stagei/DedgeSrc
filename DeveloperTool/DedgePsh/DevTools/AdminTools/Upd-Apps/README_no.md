# Upd-Apps

**Kategori:** AdminTools | **Kompleksitet:** 🟢 Lav | **Tidsbesparelse:** ~10 min/kjøring

---

## 🎯 Forretningsverdi

**Funksjon:** Oppdater alle installerte applikasjoner  
**Metode:** Kaller `Update-AllApps` fra SoftwareUtils  
**Verdi:** Batch app-oppdatering automatisering

### Funksjonalitet
```powershell
Import-Module SoftwareUtils -Force
Update-AllApps
```

**Oppdaterer:**
- Winget apps: `winget upgrade --all`
- FkPsh apps: Re-deploy fra kilde
- Windows apps: Via pakkebehandlere

### Tidsbesparelse
- **Tid spart:** ~30 min/måned per bruker
- **Sikkerhet:** Holder apps oppdatert med patcher
- **Tidsbesparelse per kjøring:** ~10 minutter (manuelt arbeid eliminert)

---

**Status:** ✅ Aktiv  
**Bruk:** Kjør manuelt eller planlagt

