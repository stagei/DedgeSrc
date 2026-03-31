# Grant-LogonRightsToCurrentUser

**Kategori:** AdminTools | **Tidsbesparelse:** ~10 min/kjøring

---

## 🎯 Forretningsverdi

**Funksjon:** Gi "Logg på som batch-jobb" og "Logg på som tjeneste" rettigheter til nåværende bruker  
**Formål:** Nødvendig for Oppgaveplanlegger-jobber og Windows-tjenester  
**Verdi:** Muliggjør planlagte oppgaver og tjenester som kjører som spesifikk bruker

### Funksjonalitet
Legger til både `SeBatchLogonRight` og `SeServiceLogonRight` til nåværende bruker

**Windows Sikkerhetspolicy:**
- Brukerrettigheter tildeling → Logg på som batch-jobb
- Brukerrettigheter tildeling → Logg på som tjeneste

**Påkrevd for:**
- Planlagte oppgaver som kjører som bruker
- Windows-tjenester som kjører som bruker
- Tjenestekontoer
- SQL Server-tjenestekontoer
- IIS Application Pool-identiteter
- Batch-jobber

### Tidsbesparelse
- **Automatisering:** Muliggjør bruker-kontekst planlagte oppgaver og tjenester
- **Tid spart:** Manuell policy-konfigurasjon → automatisert
- **Tidsbesparelse per kjøring:** ~10 minutter (manuelt arbeid eliminert)

---

## 📋 Bruk

```powershell
# Kjør som Administrator
.\Grant-LogonRightsToCurrentUser.ps1
```

Eller via deployment:
```powershell
.\_install.ps1
```

---

**Status:** ✅ Aktiv  
**Kritisk for:** Oppsett av planlagte oppgaver og Windows-tjenester  
**Forfatter:** Geir Helge Starholm, www.dEdge.no
