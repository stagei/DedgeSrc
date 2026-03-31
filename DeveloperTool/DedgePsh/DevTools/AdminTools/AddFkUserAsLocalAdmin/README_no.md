# AddFkUserAsLocalAdmin

**Kategori:** AdminTools  
**Kompleksitet:** 🟢 Lav  
**Tidsbesparelse:** ~30 min/kjøring

---

## 🎯 Forretningsverdi

**Funksjon:** Legger til nåværende bruker i lokal Administratorer-gruppe  
**Verdi:** Rask admin-tilgang for utviklere/administratorer

### Funksjonalitet
```powershell
# Finner lokal admin-gruppe (Engelsk/Norsk)
$adminGroupNames = @("Administrators", "Administratorer")

# Legger til nåværende bruker
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$adminGroup.Add("WinNT://$currentUser")
```

**Auto-detekterer:** Engelsk eller norsk Windows

### Tidsbesparelse
- **Tid spart:** 10 min per oppsett → øyeblikkelig
- **Selvbetjening:** Brukere kan legge til seg selv
- **Tidsbesparelse per kjøring:** ~30 minutter (manuelt arbeid eliminert)

---

**Status:** ✅ Aktiv  
**Bruksområde:** Utvikler-arbeidsstasjon oppsett

