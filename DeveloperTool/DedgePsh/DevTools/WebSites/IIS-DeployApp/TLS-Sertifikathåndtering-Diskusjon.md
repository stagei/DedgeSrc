# TLS-sertifikathåndtering for IIS-applikasjoner

**Forfatter:** Geir Helge Starholm, www.dEdge.no  
**Opprettet:** 2026-02-27  
**Status:** Venter på endelig godkjenning fra Frank Arild Medhus-Dale

---

## Hva vi prøver å sikre

### DedgeAuth — Intern autentiseringsplattform

DedgeAuth er en egenutviklet autentiseringsserver (ASP.NET Core / .NET 10) som håndterer brukerinnlogging for alle interne webapplikasjoner. Systemet har **eget brukerregister med egne passord** (ikke Windows-autentisering).

**Hvorfor ikke Windows-autentisering?**
Vi har gjentatte ganger forsøkt å bruke Windows-autentisering (Kerberos/NTLM) for disse applikasjonene, men har ikke fått det til å fungere uten at brukerne må taste inn brukernavn og passord ved hver gang de åpner en av appene. Dette gir en dårligere brukeropplevelse enn den egenutviklede løsningen, som tilbyr SSO på tvers av alle 5 applikasjoner etter én enkelt innlogging. Sannsynlig årsak er at utviklernes laptop-PCer (Windows 11) ikke er innrullert i AD, og dermed ikke kan autentisere sømløst via Kerberos mot interne IIS-tjenester. Det er mulig at Windows-autentisering løses på et senere tidspunkt, men per i dag er det kun DedgeAuths egen autentiseringsløsning som er aktuell — og den sender passord som klartekst over HTTP.

**Slik fungerer pålogging i dag (uten TLS):**

1. Brukeren skriver inn e-post og passord i et login-skjema (`login.html`)
2. Nettleseren sender en HTTP POST til `/api/auth/login` med passord i klartekst JSON:
   ```
   POST /DedgeAuth/api/auth/login
   Content-Type: application/json
   { "email": "bruker@Dedge.no", "password": "mittPassord123" }
   ```
3. Passordet sendes **i klartekst over nettverket** — lesbart for alle med tilgang til nettverkstrafikken
4. Først etter at passordet ankommer serveren hashes det med BCrypt

**Sensitiv data som flyter uten kryptering:**

| Data | Tidspunkt | Risiko uten TLS |
|---|---|---|
| Passord (klartekst) | Ved innlogging (POST body) | Avlytting gir direkte tilgang til brukerkonto |
| JWT access token | Alle API-kall (`Authorization: Bearer`) | Token-tyveri gir full sesjonstilgang i 30 min |
| Refresh token | Cookie ved token-fornyelse | Gir 7 dagers persistent tilgang |
| Auth code (SSO) | Ved app-til-app autentisering | Kan brukes til å kapre SSO-sesjoner |
| Brukerinfo | I localStorage og API-responser | E-post, navn, tilgangsnivå, approller, tenant |

**Applikasjoner som avhenger av DedgeAuth:**

Alle disse appene bruker DedgeAuth for autentisering via `DedgeAuth.Client`-biblioteket og arver derfor samme sikkerhetsrisiko:

| App | Funksjon | Port |
|---|---|---|
| DedgeAuth | Autentiseringsserver, login, brukeradmin | 8100 |
| DocView | Dokumentvisning | 8282 |
| GenericLogHandler | Loggbehandling | 8110 |
| ServerMonitorDashboard | Serverovervåking | 8998 |
| AutoDocJson | API-dokumentasjon | 5280 |

### Målservere for TLS-sertifikater

| Server | Miljø | Formål |
|---|---|---|
| `dedge-server` | Test | Testmiljø for alle applikasjoner |
| `p-no1fkxprd-app` | Produksjon | Produksjonsmiljø for alle applikasjoner |

Begge servere trenger vertsnavn-spesifikke SAN-sertifikater utstedt av AD CS.

### Hva vi ønsker å bruke TLS/SSL til

Vi har utviklet en intern autentiseringsplattform (**DedgeAuth**) som håndterer brukerinnlogging for 5 interne webapplikasjoner (DedgeAuth, DocView, GenericLogHandler, ServerMonitorDashboard og AutoDocJson). Alle kjører som IIS-applikasjoner på `dedge-server` (test) og `p-no1fkxprd-app` (produksjon).

DedgeAuth har et **eget brukerregister med egne passord**. Vi har gjentatte ganger forsøkt å bruke Windows-autentisering (Kerberos/NTLM), men dette fungerer ikke sømløst fordi utviklernes laptop-PCer (Windows 11) ikke er innrullert i AD. Brukerne ble bedt om å taste inn brukernavn og passord for hver app, noe som ga dårligere brukeropplevelse enn vår egen løsning som tilbyr SSO på tvers av alle 5 applikasjoner etter én enkelt innlogging. Windows-autentisering kan eventuelt løses på sikt, men per i dag brukes kun DedgeAuths egen pålogging.

**Uten TLS sendes følgende i klartekst over nettverket:**
- **Passord** i HTTP POST body ved hver innlogging
- **JWT access tokens** i Authorization-header på alle API-kall (gir full tilgang i 30 minutter)
- **Refresh token cookies** (gir 7 dagers persistent tilgang)
- **Auth codes** ved SSO mellom applikasjonene

Vi ønsker TLS-sertifikater på **2 servere** (`dedge-server` og `p-no1fkxprd-app`) for å kryptere all trafikk mellom nettleser og server, slik at passord og tokens ikke kan avlyttes på nettverket.

### Konkret trussel

Uten TLS kan enhver med tilgang til nettverkstrafikken mellom klient og server (kompromittert maskin, nettverksmonitorering, rogue device) fange opp:
- Brukerpassord i klartekst ved hver innlogging
- JWT-tokens som gir full tilgang til alle tilkoblede applikasjoner
- Refresh-tokens som gir 7 dagers persistent tilgang uten nytt passord

Dette er ikke en teoretisk risiko — det er en direkte konsekvens av at DedgeAuth bruker eget passordregister og sender credentials som klartekst HTTP POST.

---

## Oppsummering

Designforslag for å innføre TLS på interne IIS-applikasjoner, med bruk av Azure Key Vault for sertifikatlagring og distribusjon. Sikkerhetsteamet og Cloud/Infrastruktur har gitt tilbakemeldinger som krever justeringer i designet, men støtter TLS-initiativet.

### Konklusjon

- **AD CS** skal være eneste utsteder av produksjonssertifikater
- **Azure Key Vault** beholdes som sikkert hvelv og distribusjonsmekanisme
- **Wildcard-sertifikater** er forbudt — bruk vertsnavn-spesifikke SAN-sertifikater
- **Self-signed sertifikater** er forbudt i produksjon
- Endelig godkjenning må gjennom **Frank Arild Medhus-Dale**

### Rollemapping mot kryptografiprosedyre

| Prosedyrerolle | Azure-rolle |
|---|---|
| Kryptoforvalter | Key Vault Certificate Officer |
| Sjef IT-sikkerhet | Key Vault Administrator |
| Systemeier | Lesetilgang til relevante secrets/certs via RBAC |

### Åpne punkter

1. Antall servere: **2 stk** — `dedge-server` (test) og `p-no1fkxprd-app` (produksjon)
2. CA-bruker for RBAC-rollene må avklares
3. Endelig godkjenning fra Frank Arild Medhus-Dale

---

## Diskusjonstråd (kronologisk)

### Martin Lystad — Kommentarer til designforslaget

> Hei Geir,
> Jeg har noen spørsmål og kommentarer.
>
> 1. Key vault er greit. Den kan vi kombinere med den du etterspurte i den andre requesten. Ønsker du allikevel å ha adskilte vaults er det også OK.
>
> 2. Da må sertifikatet inneholde EKU: Server Authentication
>
> 3. Wildcard for DEDGE.fk.no deler vi ikke ut. Vi ønsker ikke at ett sertifikat kan stå for ett hvilket som helst navn i vårt interne domene. Hvor mange servere er det snakk om her?
>
> 4. Jeg ser ikke ett problem med dette. Vi pleier å aksessere KV ressurser via Cloud admin, men jeg ser at dere ikke har CA brukere. Kjører uansett en sjekk med IT sikkerhet på denne.
>
> 5. Denne er ikke OK. New-SelfSignedCertificate genererer ett sertifikat som er fint til testing, men det skal ikke genereres å distribueres en egen sertifikat struktur/chain for DEDGE.fk.no. Vi kan godta New-SelfSignedCertificate for enkel testing så lenge det ikke "impersonator" DEDGE.fk.no. I produksjon er det ikke aktuelt. Da skal sertifikater være signert av vår CA tjeneste med webserver sertifikat template. Dette vil nok gjøre jobben deres litt lettere også siden Dedges interne rot sertifikat alt skal ligge i trusted root certificates på våre servere. Da trenger du bare å binde webserver sertifikatet til IIS tjenesten og off you go.
>
> Alt i alt liker vi tanken på å transisjoner til TLS. Dette er et veldig bra sikkerhets tiltak.
> Med noen justeringer rundt sertifikat signering blir dette bra.
>
> Jeg setter saken til IT sikkerhet da de også burde lese igjennom og forstå målbildet og utfordringene.

### Martin Lystad — Work note

> Hei Sikkerhet, sett dere litt inn i denne og kom med eventuelle innspill på mine innsigelser.

### Tom Erik Brurok — Work note

> @Jarle Pedersen Har du noen innspill på dette fra et Sikkerhets Arkitekt standpunkt? Vet at wildcard domene sertifikater er ikke lov. Og nå er vel også test sertifikater fra våre CA tilbydere såpass billige at det burde kunne benyttes der? Har opplevd tidligere at sertifikater fra test miljø har blitt brukt i prod... Evt. annet?
> Info til @Frank Arild Medhus-Dale i tilfelle det må diskuteres på mandagsmøte...

### Jarle Pedersen — Sikkerhetsarkitekt, innspill og kryptografiprosedyre

> Vi holder på å utarbeide en prosedyre for kryptografi som etablerer tydelige krav til nøkkelhåndtering, sertifikatutstedelse og bruk av kryptografi i FKA, og påvirker dermed designforslaget på noen områder. Prosedyren slår fast at selvsignerte sertifikater ikke skal brukes i produksjon, at wildcard-sertifikater er forbudt, og at alle interne sertifikater skal utstedes gjennom en godkjent FKA-intern CA.
>
> Dette innebærer at designet må justeres slik at:
>
> - AD CS blir eneste utsteder av produksjonssertifikater for IIS-applikasjonene.
> - Azure Key Vault brukes utelukkende som sikkert nøkkelhvelv og distribusjonsmekanisme, ikke som CA. Prosedyren krever nemlig at nøkler lagres i godkjent hvelv og aldri i klartekst, noe Key Vault understøtter fullt ut.
> - Sertifikater må være vertsnavn-spesifikke SAN-sertifikater, ikke wildcard.
> - Rotasjon, logging og sporbarhet ivaretas gjennom AD CS-logging kombinert med Key Vault audit-logs, som tilfredsstiller krav til sertifikatlivssyklus og hendelseshåndtering.
>
> I sum styrker prosedyren designforslaget ved å tydeliggjøre at kombinasjonen AD CS (som utsteder) + Azure Key Vault (som distribuert hvelv) er riktig sikkerhetsarkitektur for FKA. Designet må derfor justeres marginalt, men i positiv retning for å være fullt compliant med styringskravene. Øvrige prinsipper i prosedyren, som krav om kryptering i transitt, godkjente algoritmer og sentralisert nøkkelhåndtering, oppfylles allerede av den foreslåtte arkitekturen.
>
> Som nevnt, så vil det kreves en CA bruker for å kunne bruke RBAC rollene og trolig bør dette mappes opp mot definerte roller i prosedyren:
>
> - Kryptoforvalter → Key Vault Certificate Officer
> - Sjef IT-sikkerhet → Key Vault Administrator
> - Systemeier → Lesetilgang til relevante secrets/certs via RBAC
>
> Kan kanskje være aktuelt med test sertifikat fra våre CA tilbydere, men risiko for miljøglidning (test i prod), uforutsigbar kjede/OCSP-avhengighet i isolerte testnett, og manglende kontroll.
>
> Må uansett en runde innom @Frank Arild Medhus-Dale for endelig godkjenning ref: "ansvarlig for å kravstille, kontrollere og rapportere på etterlevelsen av kravene fremstilt i prosedyren."

### Jarle Pedersen — Oppfølging

> @Markus Lundby Riseng Vi har hatt en diskusjon internt i sikkerthetsgruppa angående denne, og Frank spør om den eksisterende PKI løsningen ikke dekker behovet det spør om her?
