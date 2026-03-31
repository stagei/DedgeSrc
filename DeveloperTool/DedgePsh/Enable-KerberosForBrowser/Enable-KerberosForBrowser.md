# Enable-KerberosForBrowser

Konfigurerer Chrome og Edge til å sende Kerberos-billetter automatisk til DedgeAuth-servere, slik at brukeren slipper Windows Security-dialogboksen ved innlogging.

## Hva skriptet gjør

1. **Setter `AuthServerAllowlist`** i registeret for både Chrome (`HKLM:\SOFTWARE\Policies\Google\Chrome`) og Edge (`HKLM:\SOFTWARE\Policies\Microsoft\Edge`) med de angitte servernavnene.
2. **Legger serveren i Local Intranet-sonen** (`HKCU:\...\ZoneMap\Domains\dedge-server`) for IE/Edge legacy-kompatibilitet.
3. **Verifiserer Kerberos TGT** via `klist` og gir veiledning hvis billett mangler.
4. **Sjekker DNS-oppslag** for den første serveren i listen.

Etter kjøring kan brukeren klikke «Sign in with Windows» på DedgeAuth-innloggingssiden uten å bli bedt om brukernavn og passord.

## Forutsetninger

- Må kjøres som **Administrator** (elevated PowerShell).
- Maskinen må være domenetilkoblet eller koblet til VPN slik at Kerberos TGT er tilgjengelig.

## Bruk

```powershell
# Standard — aktiverer for test-server og DEDGE-domenet
pwsh.exe -NoProfile -File .\Enable-KerberosForBrowser.ps1

# Egendefinerte servere
pwsh.exe -NoProfile -File .\Enable-KerberosForBrowser.ps1 -Servers "p-no1fkxprd-app,*.DEDGE.fk.no"

# Fjern all konfigurasjon (angre)
pwsh.exe -NoProfile -File .\Enable-KerberosForBrowser.ps1 -Remove
```

## Parametere

| Parameter | Type | Standard | Beskrivelse |
|-----------|------|----------|-------------|
| `-Servers` | string | `dedge-server,*.DEDGE.fk.no` | Kommaseparert liste med servernavn eller wildcard-mønstre |
| `-Remove` | switch | — | Fjerner registernøklene i stedet for å sette dem |

## Hva endres i registeret

| Sti | Verdi | Innhold |
|-----|-------|---------|
| `HKLM:\SOFTWARE\Policies\Google\Chrome\AuthServerAllowlist` | String | Serverlisten |
| `HKLM:\SOFTWARE\Policies\Microsoft\Edge\AuthServerAllowlist` | String | Serverlisten |
| `HKCU:\...\ZoneMap\Domains\dedge-server\http` | DWord = 1 | Local Intranet (sone 1) |

## Feilsøking

| Problem | Løsning |
|---------|---------|
| Fortsatt credential-prompt | Restart nettleseren etter kjøring |
| Ingen Kerberos TGT funnet | Koble til VPN, eller lås/lås opp PC-en for å fornye billetter |
| DNS-oppslag feiler | Sjekk at maskinen når DNS-serveren (VPN/nettverkstilgang) |
