# 

Utviklet av Geir Helge Starholm (Dedge AS)  
Copyright © Dedge AS

## Oversikt

DedgeSign er et automatisert kodesigneringsverktøy som bruker Azure Trusted Signing med nettleserbasert autentisering. Verktøyet kan signere eller fjerne digitale signaturer fra kjørbare filer, både enkeltvis og i bulk.

## Forutsetninger

* Windows SDK (for SignTool)
  * Last ned fra: `https://go.microsoft.com/fwlink/p/?linkid=2196241`
  * Påkrevd sti: `C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe`
* Microsoft Trusted Signing Client Tools
  * Dlib installeres til: `%LOCALAPPDATA%\Microsoft\MicrosoftTrustedSigningClientTools\Azure.CodeSigning.Dlib.dll`
* PowerShell 7 eller nyere
  * Må kjøres som Administrator

## Installasjon

1. Installer forutsetningene nevnt ovenfor

2. Sett opp OptPath miljøvariabel:
   * Lag katalog "C:\opt\"
   * Opprett miljøvariabel "OptPath" og sett den til: "C:\opt"

3. Hent filene:
   * **For ferdig signerte filer:**
     * Kopier fra "\\DEDGE.fk.no\erputv"
     * Kopier alle filer fra "\\DEDGE.fk.no\erputv\Utvikling\fkavd\apps\DedgeSign\" til "%OptPath%\apps\DedgeSign\"
   
   * **For usignerte filer:**
     * Gå til "https://dev.azure.com/Dedge/Dedge/_git/DedgePsh?path=/DevTools/DedgeSign"
     * Velg "Download as Zip"
     * Pakk ut filene til "%OptPath%\apps\DedgeSign\"

4. Verifiser at alle nødvendige filer er på plass:
   * DedgeSign.ps1
   * DedgeSign-AddFileSign.ps1
   * DedgeSign-RemoveFileSign.ps1
   * AutoSign.cmd

## Bruk av Verktøyene

### Hovedverktøy (DedgeSign.ps1)

**Parametere:**

| Parameter | Type   | Påkrevd | Standard | Beskrivelse |
|-----------|--------|----------|---------|-------------|
| Path      | Tekst  | Nei      | "."     | Fil, mappe eller mønster som skal prosesseres |
| Recursive | Switch | Nei      | False   | Inkluder undermapper ved skanning |
| Action    | Tekst  | Nei      | "Add"   | Handling som skal utføres: 'Add' eller 'Remove' |
| NoConfirm | Switch | Nei      | False   | Hopp over bekreftelsesdialog |

**Eksempler på bruk:**
```powershell
# Signer en enkelt fil
.\DedgeSign.ps1 -Path sti\til\fil.exe -Action Add

# Signer alle filer i gjeldende mappe
.\DedgeSign.ps1 -Action Add

# Signer rekursivt i en mappe
.\DedgeSign.ps1 -Path sti\til\mappe -Recursive -Action Add

# Signer alle PowerShell-filer
.\DedgeSign.ps1 -Path *.ps1 -Action Add

# Fjern signaturer fra DLL-filer
.\DedgeSign.ps1 -Path C:\Prosjekt\bin\*.dll -Action Remove
```

### Enkeltfilsignering (DedgeSign-AddFileSign.ps1)

Verktøy for å signere enkeltstående filer.

**Parametere:**

| Parameter | Type  | Påkrevd | Beskrivelse |
|-----------|-------|---------|-------------|
| FilePath  | Tekst | Ja      | Stien til filen som skal signeres |

**Eksempel:**
```powershell
.\DedgeSign-AddFileSign.ps1 -FilePath "C:\MinApp\bin\Release\MinApp.exe"
```

### Fjerne Signaturer (DedgeSign-RemoveFileSign.ps1)

Verktøy for å fjerne signaturer fra filer.

**Støttede Filtyper:**

*Skriptfiler (Innholdsredigering):*
* PowerShell Scripts (.ps1)
* PowerShell Modules (.psm1)
* PowerShell Data Files (.psd1)
* VBScript (.vbs)
* Windows Script Files (.wsf)
* JavaScript (.js)

*Binærfiler (SignTool):*
* Kjørbare filer (.exe)
* Biblioteker (.dll)
* Installasjonsfiler (.msi)
* Systemfiler (.sys)
* Og mange andre binære formater

## Visual Studio Integrasjon

For å automatisk signere bygde filer i Visual Studio:

1. Høyreklikk på prosjektet i Solution Explorer
2. Velg "Properties"
3. Naviger til "Build Events"
4. I "Post-build event command line", legg til:
```cmd
"%OptPath%\apps\DedgeSign\AutoSign.cmd" "$(TargetPath)"
```

For å signere alle filer i output-mappen, legg til "Y" som parameter:
```cmd
"%OptPath%\apps\DedgeSign\AutoSign.cmd" "$(TargetPath)" Y
```

## Feilsøking

1. Sjekk at %OptPath% miljøvariabelen er korrekt satt
2. Verifiser at DedgeSign er riktig installert i %OptPath%\apps\DedgeSign\
3. Kontroller build-output for signeringsrelaterte feil
4. Sjekk at SignTool.exe er tilgjengelig i riktig sti
5. Verifiser at du har nødvendige rettigheter i Azure for kodesignering

## Støttede Filtyper

* Kjørbare filer (.exe)
* Biblioteker (.dll)
* PowerShell (.ps1, .psm1, .psd1)
* Skript (.vbs, .wsf, .js)
* Installasjonsfiler (.msi, .msix, .appx)
* Systemfiler (.sys, .drv)
* Og mange andre formater

## Notater

* Verktøyet sjekker automatisk om filer allerede er signert
* Støtter både signering og fjerning av signaturer
* Kan behandle flere filer samtidig
* Gir detaljert fremgangsinformasjon
* Bruker Azure Trusted Signing med nettleserbasert autentisering

## Azure Oppsett for Kodesignering

### Forutsetninger

* Azure-abonnement med administrative tilganger
* Azure CLI installert (valgfritt)
* Tilgang til Azure Portal

### Opprette Signeringsrolle i Azure

**Metode 1: Via Azure Portal**

1. Logg inn på [Azure Portal](https://portal.azure.com)
2. Naviger til **Azure Active Directory**
3. Velg **Roles and administrators**
4. Klikk **+ New custom role**
5. Konfigurer rollen med følgende innstillinger:
   * Navn: "Trusted Signing Certificate Profile Signer"
   * Beskrivelse: "Can sign and manage trusted certificate profiles"
   * Baseline permissions: Start from scratch
   * Tillatelser:
     * Microsoft.Authorization/*/read
     * Microsoft.Certificates/trustedSigningCertificates/*

**Metode 2: Via Azure PowerShell**

```powershell
# Koble til Azure
Connect-AzAccount

# Opprett rolledefinisjon
$role = @{
    Name = "Trusted Signing Certificate Profile Signer"
    Description = "Can sign and manage trusted certificate profiles"
    Actions = @(
        "Microsoft.Authorization/*/read",
        "Microsoft.Certificates/trustedSigningCertificates/*"
    )
    AssignableScopes = @("/subscriptions/<ditt-subscription-id>")
}

New-AzRoleDefinition -Role $role
```

### Tildele Rollen til en Bruker

**Via Azure Portal:**

1. Gå til **Azure Active Directory**
2. Velg **Roles and administrators**
3. Finn og klikk på "Trusted Signing Certificate Profile Signer"
4. Klikk **+ Add assignments**
5. Søk etter og velg brukeren
6. Klikk **Add**

**Via PowerShell:**

```powershell
# Variabler
$userPrincipalName = "bruker@domene.com"
$subscriptionId = "<ditt-subscription-id>"
$roleName = "Trusted Signing Certificate Profile Signer"

# Hent bruker-ID
$user = Get-AzADUser -UserPrincipalName $userPrincipalName

# Tildel rolle
New-AzRoleAssignment -ObjectId $user.Id `
                     -RoleDefinitionName $roleName `
                     -Scope "/subscriptions/$subscriptionId"
```

### Verifisering av Rolletilgang

For å verifisere rolletildelingen:

1. La brukeren logge inn på Azure Portal
2. Naviger til Azure Active Directory
3. Klikk på **My permissions**
4. Bekreft at "Trusted Signing Certificate Profile Signer" er listet

### Feilsøking av Azure-roller

1. Verifiser at brukeren eksisterer i Azure AD
2. Sjekk at du har tilstrekkelige rettigheter til å tildele roller
3. Kontroller at subscription ID er korrekt
4. Vent noen minutter på rollepropagering
5. Sjekk Azure Activity Logs for eventuelle feilmeldinger 