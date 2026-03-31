# Backup-EnvironmentVariables

**Kategori:** AdminTools  
**Kompleksitet:** 🟡 Middels  
**Tidsbesparelse:** ~117 min/kjøring

---

## 🎯 Forretningsverdi

**Problem:** Miljøvariabel-korrupsjon = ødelagte applikasjoner  
**Løsning:** Sikkerhetskopier alle miljøvariabler til gjenopprettbart PowerShell-script  
**Verdi:** Rask gjenoppretting fra miljøvariabel-problemer

### Funksjonalitet
Eksporterer alle miljøvariabler:
- Bruker-scope variabler
- System-scope variabler  
- Prosess-scope variabler

**Output:** `EnvironmentVariables-Backup_YYYYMMDD-HHMMSS.ps1`

**Gjenopprett:** Bare kjør det genererte scriptet

### Tidsbesparelse
- **Forhindrer:** 2-4 timer gjenoppretting etter korrupsjon
- **Muliggjør:** Rask tilbakerulling til fungerende tilstand
- **Tidsbesparelse per kjøring:** ~117 minutter (manuelt arbeid eliminert)

---

**Status:** ✅ Aktiv  
**Anbefalt:** Kjør før større systemendringer

