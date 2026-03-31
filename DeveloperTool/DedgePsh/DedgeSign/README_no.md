# DedgeSign

**Kategori:** AdminTools  
**Kompleksitet:** 🟡 Middels  
**Kritikalitet:** 🔴 KRITISK  
**Tidsbesparelse:** ~33 min/kjøring

---

## 🎯 Forretningsverdi

**Problem:** Usignerte scripts = Sikkerhetsadvarsler og kjøringsblokker  
**Løsning:** Azure Trusted Signing for kodesignering  
**Verdi:** Sikkerhets-compliance + produksjons-distribusjonsevne

### Funksjonalitet
Azure Trusted Signing Tool - legger til/fjerner digitale signaturer

**Funksjoner:**
- Signer PowerShell scripts, .exe, .dll filer
- Rekursiv katalogstøtte
- Legg til eller fjern signaturer
- Azure-basert trusted signing

**Bruk:**
```powershell
.\DedgeSign.ps1 -Path "script.ps1" -Action Add
.\DedgeSign.ps1 -Path "C:\Apps" -Recursive -Action Add
.\DedgeSign.ps1 -Path "file.exe" -Action Remove
```

### Tidsbesparelse
- **Sikkerhet:** Alle produksjonsscripts må signeres
- **Compliance:** Oppfyller sikkerhetskrav
- **Brukeropplevelse:** Ingen sikkerhetsadvarsler
- **Tidsbesparelse per kjøring:** ~33 minutter (manuelt arbeid eliminert)

---

**Status:** ✅ KRITISK for produksjon  
**Distribusjon:** Brukes i alle produksjons-distribusjoner

