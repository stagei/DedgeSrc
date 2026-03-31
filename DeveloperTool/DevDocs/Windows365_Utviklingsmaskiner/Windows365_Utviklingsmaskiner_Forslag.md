# Windows 365 Cloud PC - Løsningsforslag for Utviklingsmaskiner


## Bakgrunn og formål

Utviklingsavdelingen ved Dedge har behov for effektive og sikre utviklingsmaskiner for å arbeide med ulike teknologier som Cobol, .NET C#, PowerShell, webløsninger og andre utviklingsverktøy. Dette dokumentet presenterer et løsningsforslag for migrering fra dagens VDI-løsning hostet hos Digiplex til en Windows 365 Cloud PC-løsning hostet i Azure.

Formålet er å balansere utviklernes behov for fleksibilitet og administrative rettigheter med organisasjonens sikkerhetskrav, samtidig som vi utnytter fordelene ved sky-baserte løsninger.

Utviklingsavdelingen har en rekke større prosjekter som skal frem mot 2030, og vi mener dette forslaget representerer et godt kompromiss mellom utviklernes behov og organisasjonens sikkerhetskrav, som vi håper alle parter kan stille seg bak.

## Nåværende situasjon

I dag benytter utviklere VDI-løsninger som er hostet hos Digiplex. Følgende utfordringer er identifisert med nåværende oppsett:

1. Utviklere har administrative rettigheter, noe vi forstår utgjør en potensiell sikkerhetsrisiko
2. Samme brukernavn og passord benyttes på både laptop og VDI, som øker risikoen ved kompromittering
3. Begrenset skalerbarhet i eksisterende infrastruktur
4. Økt ressursbehov for moderne utviklingsverktøy
5. Begrensninger av nettadresser hindrer tilgang til nødvendige utviklingsressurser

I tillegg så har Leveranseavdelingen en plan om å fjerne Digiplex som leverandør av VDI-løsninger i løpet av 2025, noe tvinger frem en ny og mer moderne løsning for utviklingsmaskinene.

## Foreslått løsning

Vi foreslår å implementere Windows 365 Cloud PC-løsninger i Azure for utviklerne. Denne løsningen vil være spesialtilpasset utviklingsarbeid og vil ha følgende nøkkelkomponenter:

### Brukerautentisering og tilgangskontroll

- Separate brukerkontoer uavhengig av eksisterende VDI-løsning og laptop-innlogging
- Unike passord som ikke deles med andre systemer
- Mulighet for multifaktor-autentisering via Microsoft Authenticator
- Lokale administrative rettigheter begrenses til utviklingsmaskinen
- **Ingen kontinuerlig sessjonsopptak** av utviklerens arbeidsflate, i motsetning til CyberArk-tilnærmingen på privilegerte servere

### Tekniske spesifikasjoner

- Windows 365 Enterprise-lisenser med dedikerte ressurser
- **Persistent tilstand**: Alle Cloud PC-er beholder nøyaktig tilstand mellom sesjoner
- **Multiscreen-støtte**: Fullstendig støtte for RDP med flere skjermer
- **Delt utklippstavle**: Sømløs kopiering og liming mellom laptop og Cloud PC
- **Skriverdeling**: Tilgang til lokale skrivere fra Cloud PC
- **Ubegrenset nettilgang**: Fulltilgang til utviklingsressurser inkludert YouTube, Reddit og andre kunnskapsplattformer
- **VPN-tilgang ved hjemmekontor**: Mulighet for å koble til Cloud PC via VPN fra hjemmekontor
- Optimalisert for RDP-ytelse med lav latens
- Tilrettelagt for installasjon av utviklingsverktøy og redigering av systeminnstillinger
- Tilgang til Excel (kun) fra Microsoft Office-pakken for Cobol-integrasjon

### Nettverkstilgang

- Sikker tilgang til eksisterende servere for Dedge og FkKonto
- Konfigurert for tilgang til nye Azure-baserte tjenester under abonnementene P-Dedge og T-Dedge
- Tilgang til lokale disker på utviklernes laptoper, men ikke nettverksdisker
- Åpen tilgang til tekniske informasjonskilder og videobaserte opplæringsressurser på nett
- **VPN-løsning** for sikker tilkobling fra hjemmekontor eller eksterne lokasjoner

### Overvåking og personvern

- Selektiv logging av sikkerhetsrelevante hendelser, fremfor kontinuerlig skjermopptak som gjøres i CyberArk på privilegerte servere i dag
- Balansert tilnærming til sikkerhet som respekterer utviklernes arbeidsmiljø, effektivitet og personvern
- Differensiert sikkerhetstilnærming mellom produksjonsservere og utviklingsmiljøer

### Sikkerhetsaspekter


Selv om løsningen gir utviklere administrative rettigheter, så er det vårt mål å sikre at utviklingsmiljøene er sikre og effektive.

1. **Segmentering**: Separate brukerkontoer uten kobling til hovedbrukerkontoen
2. **Multifaktor-autentisering**: Ekstra sikkerhetslag ved innlogging
3. **Nettverksisolasjon**: Begrenset og kontrollert nettverkstilgang til produksjonsmiljøer, men ubegrenset tilgang til utviklingsressurser
4. **Målrettet overvåking**: Logging og monitorering av sikkerhetsrelevante hendelser på Windows 365-maskinene, uten kontinuerlig sessjonsopptak
5. **Sikker fjerntilgang**: VPN-løsning for hjemmekontor som sikrer at kun autoriserte brukere får tilgang
6. **Geografisk tilgangskontroll**: Nettverkstilgang begrenses til norske IP-adresser og godkjente lokasjoner for å sikre etterlevelse av personvernlovgivning (GDPR) og andre regulatoriske krav. Dette inkluderer:
   - Blokkering av tilgang fra høyrisiko-lokasjoner
   - Logging av geografisk tilgangsdata
   - Varsling ved forsøk på tilgang fra ikke-godkjente lokasjoner


### Fra utviklingsavdelingens perspektiv ser vi for oss følgende komponenter i løsningen:

1. **Windows 365 Enterprise**: 
   - Gir mulighet for tilpasning av maskinvare og programvare
   - Sikrer fullstendig **persistent tilstand** mellom alle sesjoner - maskinen forblir nøyaktig slik utvikleren forlot den
   - Støtter **flere skjermer i RDP** med opptil 4 skjermer

2. **Fjernarbeid og hjemmekontorløsning**:
   - Sikker VPN-løsning for tilgang til Cloud PC fra laptopen eller annen hjemmekontorløsning
   - Samme brukeropplevelse uavhengig av arbeidslokasjon
   - Optimalisert nettverkskonfigurasjon for stabil ytelse også over VPN

3. **Sikker nettverksforbindelse**: 
   - VNet-integrasjon mellom Windows 365 og Azure-tjenester
   - Ingen blokkering av legitime utviklingsressurser på nett (YouTube, Reddit, Stack Overflow, etc.)
   - Sikre nettfiltre som beskytter mot skadelig kode uten å hindre tilgang til teknisk innhold

4. **Optimalisert RDP-opplevelse**:
   - Konfigurert for UDP-transport for bedre ytelse
   - Støtte for høy bildekvalitet og lyd
   - **Delt utklippstavle** for sømløs kopiering og liming av tekst, kode, bilder og filer
   - **Tilgang til lokale skrivere** fra Cloud PC-miljøet
   - Overføring av lokale ressurser som tastaturevent, mus, og kopier/lim inn

5. **Personvernhensyn**:
   - Målrettet logging av sikkerhetsrelevante hendelser
   - Ingen kontinuerlig skjermopptak som med CyberArk
   - Balansert tilnærming mellom sikkerhet og personvern

### Fordeler med løsningen

1. **Økt sikkerhet**: Segmentering av utviklingsmiljøer fra produksjons- og kontormiljøer
2. **Forbedret fleksibilitet**: Utviklere kan selvstendig installere nødvendige verktøy
3. **Skalerbarhet**: Enkel oppskalering av ressurser etter behov
4. **Moderne infrastruktur**: Utnyttelse av sky-fordeler som høy tilgjengelighet
5. **Kostnadskontroll**: Forutsigbar abonnementsmodell i stedet for store investeringer
6. **Geografisk fleksibilitet**: Mulighet for tilgang fra ulike lokasjoner, inkludert hjemmekontor via VPN
7. **Persistent tilstand**: Utviklere kan fortsette nøyaktig der de slapp, med alle programmer, filer og vinduer i samme tilstand
8. **Optimal arbeidsflyt**: Støtte for flere skjermer sikrer at utviklere kan arbeide effektivt med komplekse oppgaver
9. **Sømløs integrasjon**: Delt utklippstavle og skrivere eliminerer barrierer mellom lokal og cloud-basert arbeidsflate
10. **Ubegrenset kunnskapstilgang**: Utviklere får tilgang til alle relevante kunnskapsressurser uten unødige begrensninger
11. **Forbedret arbeidsmiljø**: Eliminering av kontinuerlig sessjonsopptak som i CyberArk-løsninger, til fordel for en mer målrettet og ikke-påtrengende sikkerhetsovervåking
12. **Fleksibel arbeidslokasjon**: Sikker tilgang til utviklingsmiljøet via VPN fra hjemmekontor eller andre lokasjoner

### Utviklingsavdelingens konklusjon

Windows 365 Cloud PC representerer en balansert løsning som ivaretar både utviklernes behov for fleksibilitet og administrative rettigheter, samtidig som organisasjonens sikkerhetskrav kan adresseres gjennom flere lag med sikkerhetstiltak. 

Løsningen sikrer viktige utviklerkrav:
- **Persistent tilstand**: Alle programmer, filer og vinduer forblir nøyaktig i samme tilstand mellom sesjoner, noe som øker produktiviteten betraktelig
- **Multiskjerm-støtte**: Full støtte for flere skjermer i RDP, så utviklere kan utnytte hele skjermområdet sitt effektivt
- **Delt utklippstavle og skrivere**: Sømløs deling av utklippstavle og skrivere mellom laptop og Cloud PC sikrer en integrert arbeidsopplevelse
- **Administrative rettigheter**: Utviklere har nødvendig frihet til å tilpasse miljøet etter behov
- **Sikker separasjon**: Løsningen sikrer god isolasjon fra andre systemer og brukerkontoer
- **Ubegrenset tilgang til utviklingsressurser**: Ingen blokkering av legitime kunnskapskilder som Reddit, YouTube, Stack Overflow og andre ressurser utviklere trenger for å løse tekniske utfordringer
- **API-tilgang for utviklingsverktøy**: Åpen tilgang til nødvendige API-endepunkter for GitHub Copilot, Cursor AI og lignende AI-assisterte utviklingsverktøy, uten nettverksbegrensninger som hindrer kommunikasjon med disse tjenestene
- **Personvern og arbeidsmiljø**: Eliminering av kontinuerlig sessjonsopptak som i CyberArk-løsninger, til fordel for en mer målrettet og ikke-påtrengende sikkerhetsovervåking
- **Fleksibel arbeidslokasjon**: Sikker tilgang til utviklingsmiljøet via VPN fra hjemmekontor eller andre lokasjoner

Vi ber sikkerhets- og leveranseavdelingen vurdere dette forslaget, og vi ser fram til å diskutere hvordan en slik løsning kan implementeres på en måte som både ivaretar sikkerhetshensyn og utviklernes produktivitetsbehov. På grunn av utfasingen av Digiplex så er det viktig at vi får en løsning som er i tråd med Dedges digitale strategi, i god tid før vi må gå over til en ny løsning.
