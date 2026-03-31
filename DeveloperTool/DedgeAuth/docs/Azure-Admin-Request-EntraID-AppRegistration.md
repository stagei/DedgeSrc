# Forespørsel: Registrer DedgeAuth som Entra ID-applikasjon

**Fra:** Geir Helge Starholm  
**Dato:** 2026-03-23  
**Formål:** Vi ønsker å legge til "Logg inn med Microsoft"-knapp i DedgeAuth (vårt interne autentiseringssystem). Dette krever en App Registration i Entra ID.

---

## Hva er DedgeAuth?

DedgeAuth er vår interne autentiseringsplattform for FK sine utviklings- og driftsverktøy (DocView, GenericLogHandler, ServerMonitorDashboard, AutoDocJson m.fl.). DedgeAuth er også planlagt som autentiseringsplattform for den nye versjonen av Korn og Såvare, som er under utvikling/planlegging. Den kjører som IIS-applikasjon på:

| Miljø | Server | URL |
|---|---|---|
| **Test** | `dedge-server` | `http://dedge-server/DedgeAuth/` |
| **Produksjon** | `p-no1fkxprd-app` | `http://p-no1fkxprd-app/DedgeAuth/` |

---

## Hva vi trenger: App Registration i Azure Portal

### Steg 1: Opprett ny App Registration

Gå til **Entra ID** (portal.azure.com) → **App registrations** → **New registration**

| Felt | Verdi |
|---|---|
| **Name** | `DedgeAuth` |
| **Supported account types** | "Accounts in this organizational directory only" (Dedge — Single tenant) |
| **Redirect URI (Web)** | `http://dedge-server/DedgeAuth/signin-oidc` |

### Steg 2: Legg til Redirect URI-er for alle miljøer

Under **Authentication** → **Platform configurations** → **Web** → **Redirect URIs**, legg til alle disse:

```
http://dedge-server/DedgeAuth/signin-oidc
http://p-no1fkxprd-app/DedgeAuth/signin-oidc
http://localhost/DedgeAuth/signin-oidc
```

Sett også:

| Felt | Verdi |
|---|---|
| **Front-channel logout URL** | `http://dedge-server/DedgeAuth/signout-oidc` |
| **ID tokens** | Huk av (under "Implicit grant and hybrid flows") |

### Steg 3: Opprett Client Secret

Under **Certificates & secrets** → **Client secrets** → **New client secret**:

| Felt | Verdi |
|---|---|
| **Description** | `DedgeAuth OIDC` |
| **Expires** | 24 måneder (eller i henhold til organisasjonens policy) |

**Viktig:** Kopier secret-verdien med en gang — den vises kun én gang.

### Steg 4: Bekreft API-tillatelser

Under **API permissions** skal disse allerede være på plass (legges til automatisk):

| Tillatelse | Type | Beskrivelse |
|---|---|---|
| `Microsoft Graph` → `User.Read` | Delegated | Leser innlogget brukers profil |

Ingen ekstra tillatelser er nødvendig. DedgeAuth trenger kun å vite hvem brukeren er (e-post og visningsnavn).

### Steg 5: Send oss disse 3 verdiene

| Verdi | Hvor den finnes |
|---|---|
| **Tenant ID** | App registration → Overview → "Directory (tenant) ID" |
| **Client ID** | App registration → Overview → "Application (client) ID" |
| **Client Secret** | Verdien kopiert fra Steg 3 |

Send verdiene til **geir.helge.starholm@Dedge.no** (gjerne kryptert eller via Teams).

Eksempel på format:

```
TenantId:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ClientId:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ClientSecret: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Hva dette brukes til

Når registreringen er på plass, legger vi til en "Logg inn med Microsoft"-knapp i DedgeAuth. For brukere med Entra ID-tilknyttede PC-er (Azure AD Join) betyr dette:

- Ingen brukernavn/passord-dialog
- Microsoft sitt innloggingsvindu håndterer autentisering automatisk via PRT (Primary Refresh Token)
- Brukeren blir automatisk logget inn med sin FK-konto

**Sikkerhetsdetaljer:**
- Single tenant — kun `Dedge.no`-kontoer kan logge inn
- Client Secret lagres i `appsettings.json` på serveren (ikke i kildekode/git)
- Kun `User.Read`-tilgang — appen kan ikke lese andres data eller gjøre endringer i Entra ID
- All kommunikasjon mellom DedgeAuth og Microsoft skjer server-til-server (authorization code flow)

---

## Kontaktperson

Ved spørsmål, ta kontakt med:

**Geir Helge Starholm**  
E-post: geir.helge.starholm@Dedge.no  
Telefon: 971 88 358
