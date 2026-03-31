# Server-AlertOnShutdown

**Kategori:** InfrastructureTools  
**Status:** ✅ Produksjon  
**Distribusjonsmål:** DB2-servere  
**Kompleksitet:** 🟢 Enkel  
**Sist oppdatert:** 2025-11-18  
**Kritikalitet:** 🟡 HØY  
**Forfatter:** Geir Helge Starholm, www.dEdge.no

---

## 🎯 Forretningsverdi

### Problemstilling
**Manglende synlighet ved uplanlagte server-nedstengninger og omstarter:**
- Produksjonsservere kan stenges ned/omstartes uten forvarsel
- Ingen umiddelbar varsling når kritiske servere går ned
- Vedlikeholdsvinduer kan bli oversett eller glemt
- Uplanlagte nedstengninger kan indikere maskinvareproblemer eller sikkerhetshendelser
- Teamet må vite umiddelbart når systemer omstartes

**Uten automatisering:**
- **Problem:** Server omstartes kl 03:00 (planlagt eller uplanlagt)
- **Resultat:** Teamet oppdager nedetid først når brukere melder problemer kl 07:00
- **Manuell deteksjon:** Sjekke hendelseslogger i ettertid
- **Impact:** Forsinket respons, usikker årsak, potensielt datatap

### Løsning
**Sanntids varslingssystem for nedstengning/omstart-hendelser:**
1. Utløses automatisk av Windows hendelseslogg (Event ID 1074)
2. Detekterer nedstengning/omstart umiddelbart
3. Sender SMS-varsler til utpekt personell
4. Sender FK Alert for logging og sporing
5. **Resultat:** Teamet informeres øyeblikkelig når servere går ned!

**ROI:** Raskere hendelseshåndtering, bedre vedlikeholdssporing, forbedret oppetidsovervåking  
**Frekvens:** ~12-20 hendelser/år (planlagt + uplanlagt)  
**Verdi:** Redusert MTTR (Mean Time To Recovery) med 2-3 timer per hendelse

---

## ⚙️ Funksjonalitet

### Hva Skjer Ved Nedstengning/Omstart

```
1. Bruker/Administrator initierer nedstengning eller omstart
   ↓
2. Windows genererer Event ID 1074 i System-loggen
   ↓  
3. Oppgaveplanlegger utløser: Server-AlertOnShutdown (umiddelbart)
   ↓
4. Skriptet kjører:
   - Detekterer servernavn ($env:COMPUTERNAME)
   - Henter SMS-mottakerliste
   - Bygger varslingsmelding
   ↓
5. Sender varsler:
   - FK Alert (Kode 7777): "ALERT: System shutdown/restart detected on SERVER"
   - SMS til alle konfigurerte mottakere
   ↓
6. Teamet mottar umiddelbar varsling!
   ↓
7. Systemet fortsetter med nedstengning/omstart
```

### Kode (Forenklet)

```powershell
# Hent SMS-mottakere
$smsNumbers = Get-SmsNumbers

# Bygg varslingsmelding
$message = "ALERT: System shutdown/restart detected on $($env:COMPUTERNAME)"

# Send FK Alert for sporing
Send-FkAlert -Program $(Get-InitScriptName) -Code "7777" -Message $message -Force

# Send SMS til alle mottakere
foreach ($smsNumber in $smsNumbers) {
    Send-Sms -Receiver $smsNumber -Message $message
}
```

---

## 🚀 Deployment

**Installasjon (_install.ps1):**
- Oppretter Windows Scheduled Task fra XML
- Trigger: Windows hendelseslogg - Event ID 1074 (System/User32)
- Kjør som: Gjeldende brukerkonto (med SID-erstatning)
- Kjør med høyeste privilegier
- Utførelsestidsgrense: 1 time

**XML Task Configuration:**
```xml
<Triggers>
  <EventTrigger>
    <Subscription>
      *[System[Provider[@Name='User32'] and EventID=1074]]
    </Subscription>
  </EventTrigger>
</Triggers>
```

**Event ID 1074:** Systemets nedstengning/omstart initiert av bruker eller applikasjon

---

## 📋 Konfigurasjon

**SMS-mottakere:**
- Konfigurert via `Get-SmsNumbers` funksjon fra GlobalFunctions
- Kan overstyres ved å sende `-SmsNumbers` parameter
- Typisk inkluderer: DBA-er, Infrastrukturteam, Vaktpersonell

**Varslingskode:**
- FK Alert-kode: 7777
- Logges til sentralt varslingssystem for sporing og rapportering

---

## 📈 Git-statistikk
- **Opprettet:** 2025-11-13
- **Commits:** 1
- **Linjer:** 47 (komplett løsning)

---

## 💰 ROI-beregning

| Scenario | Uten automatisering | Med automatisering | Besparelse |
|----------|-------------------|-----------------|---------|
| **Nedstengningshendelser** | 15/år | 15/år | - |
| **Deteksjonstid** | 4 timer i snitt | Umiddelbart | 60 timer/år |
| **Responstid** | 30 min forsinkelse | 5 min | 6,25 timer/år |
| **Kostnad (forsinket respons)** | 66,25 timer × 1500 NOK | 0 | 99,375 NOK |
| **Vedlikeholdssporing** | Manuell/manglende | Automatisk | Bedre compliance |
| **TOTAL** | ~100,000 NOK/år | Minimal | **~100,000 NOK/år** |

---

## ⚠️ Kritikalitet

**Uten dette systemet:**
- ❌ Ingen synlighet i server-nedstengningshendelser
- ❌ Forsinket hendelseshåndtering
- ❌ Tapte vedlikeholdsvinduer
- ❌ Potensielle uoppdagede sikkerhetsproblemer

**Med dette systemet:**
- ✅ Umiddelbar varsling ved nedstengning/omstart
- ✅ Bedre hendelsesporing
- ✅ SMS-varsler til teamet
- ✅ Sentralisert logging via FK Alert

---

## 🔍 Overvåking & Feilsøking

**Verifiser oppgavestatus:**
```powershell
Get-ScheduledTask -TaskName "Server-AlertOnShutdown" -TaskPath "\DevTools\"
```

**Test manuelt:**
```powershell
& "E:\opt\DedgePshApps\Server-AlertOnShutdown\Server-AlertOnShutdown.ps1"
```

**Sjekk logger:**
- Plassering: `C:\opt\data\AllPwshLog\<ComputerName>_<Date>.log`
- Søk etter: "shutdown alert"

---

**Status:** ✅ HØY prioritet overvåkingssystem  
**Anbefaling:** Hold aktivert på alle produksjons DB2-servere

