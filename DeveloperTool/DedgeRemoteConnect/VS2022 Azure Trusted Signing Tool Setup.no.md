# Automatisk signering av filer i Visual Studio 2022

Dette dokumentet forklarer hvordan man setter opp automatisk signering av både hovedapplikasjonen (.NET) og installasjonen (Setup Project) i Visual Studio 2022.

## Oppsett av applikasjonsprosjekt (.csproj)

1. Åpne prosjektets `.csproj`-fil
2. Legg til følgende egenskaper og post-build event for å signere output-filen:
   ```xml
   <PropertyGroup>
     <ShouldSign>false</ShouldSign>
     <ShouldSign Condition="'$(Configuration)' == 'Release'">true</ShouldSign>
   </PropertyGroup>

   <!-- Valgfritt: Debug-konfigurasjon for å verifisere signeringsstatus -->
   <Target Name="EchoConfiguration" BeforeTargets="PostBuild">
     <Message Importance="high" Text="Current Configuration: $(Configuration)" />
     <Message Importance="high" Text="Should Sign: $(ShouldSign)" />
   </Target>

   <Target Name="PostBuild" AfterTargets="PostBuildEvent" Condition="'$(ShouldSign)' == 'true'">
     <Message Importance="high" Text="Signing assembly..." />
     <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;\\path\to\signing\script.ps1&quot; -Path &quot;$(TargetPath)&quot; -Action Add -NoConfirm" />
   </Target>
   ```

Dette oppsettet sikrer at:
- Debug-bygg hopper over signering
- Release-bygg signeres automatisk
- Byggutdata viser signeringsstatus

## Oppsett av installasjonsprosjekt (.vdproj)

1. Åpne `.vdproj`-filen i en teksteditor
2. Finn "Product"-seksjonen
3. Legg til eller endre "PostBuildEvent"-egenskapen:
   ```
   "PostBuildEvent" = "8:pwsh.exe -ExecutionPolicy Bypass -File \"\\\\path\\to\\signing\\script.ps1\" $(TargetDir) -Action Add -NoConfirm"
   "RunPostBuildEvent" = "3:1"
   ```

## Viktige merknader

- Signeringsskriptet (DedgeSign.ps1) må være tilgjengelig fra byggemaskinen
- PowerShell execution policy må tillate kjøring av signeringsskriptet
- Riktige tilganger kreves for å aksessere sertifikatet og skriptet
- Signeringsprosessen kjører automatisk etter vellykkede Release-bygg
- Bruk anførselstegn rundt stier som kan inneholde mellomrom
- Parameteren -NoConfirm muliggjør automatisk signering uten brukerinteraksjon

## Feilsøking

### Ved signeringsfeil, sjekk:
- Tilgang til skriptstien
- PowerShell execution policy
- Tilgjengelighet og tilganger for sertifikatet
- Byggekontoens tilganger
- Verifiser at du bygger i Release-konfigurasjon

### Vanlige feilmeldinger:
- "Access denied": Sjekk fil- og nettverkstilganger
- "Certificate not found": Verifiser sertifikatsti og tilgjengelighet
- "PowerShell execution policy": Bruk -ExecutionPolicy Bypass

## Sikkerhetshensyn

- Lagre sertifikater sikkert
- Bruk miljøvariabler for sensitive stier
- Implementer riktig tilgangskontroll for signeringsskript
- Bruk timestamp-servere for langsiktig signaturgyldighet
- Regelmessig fornyelse av sertifikater

## Eksempelkonfigurasjon

### .csproj Eksempel
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <ShouldSign>false</ShouldSign>
    <ShouldSign Condition="'$(Configuration)' == 'Release'">true</ShouldSign>
  </PropertyGroup>

  <Target Name="PostBuild" AfterTargets="PostBuildEvent" Condition="'$(ShouldSign)' == 'true'">
    <Message Importance="high" Text="Signing assembly..." />
    <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;\\server\path\DedgeSign.ps1&quot; -Path &quot;$(TargetPath)&quot; -Action Add -NoConfirm" />
  </Target>
</Project>
```

### .vdproj Eksempel
```
"PostBuildEvent" = "8:pwsh.exe -ExecutionPolicy Bypass -File \"\\\\server\\path\\DedgeSign.ps1\" $(TargetDir) -Action Add -NoConfirm"
"RunPostBuildEvent" = "3:1"
``` 