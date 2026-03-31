# FileLockDetectionHandler

PowerShell-verktøy for å finne og håndtere låste filer i Windows.

## Forutsetninger

- Windows
- PowerShell 5.1 eller nyere
- Administratorrettigheter
- Internettilkobling (første gang)

## Brukseksempler

### Sjekk én fil

```powershell
# Sjekk Excel-fil
.\FileLockDetectionHandler.ps1 -Path "C:\sti\til\din\fil.xlsx"

# Sjekk Word-dokument
.\FileLockDetectionHandler.ps1 -Path "C:\dokumenter\rapport.docx"
```

### Sjekk hele mapper

```powershell
# Sjekk alle filer i en mappe
.\FileLockDetectionHandler.ps1 -Path "C:\dokumenter" -Recurse

# Sjekk med detaljert utskrift
.\FileLockDetectionHandler.ps1 -Path "C:\dokumenter" -Verbose
```

### Kjør som administrator

```powershell
# Metode 1 - PowerShell 7
Start-Process pwsh -Verb RunAs -ArgumentList "-Command .\FileLockDetectionHandler.ps1 -Path 'C:\sti\til\fil.xlsx'"

# Metode 2 - Windows PowerShell
Start-Process powershell -Verb RunAs -ArgumentList "-Command .\FileLockDetectionHandler.ps1 -Path 'C:\sti\til\fil.xlsx'"
```

## Menyvalg

Når programmet kjører:
1. Skriv inn nummeret til filen du vil låse opp
2. Skriv 'Q' for å avslutte

## Tips

- Første gang lastes Handle-verktøyet ned automatisk
- Vær forsiktig med å låse opp filer som er i bruk
- Bruk `-Verbose` for å se mer detaljert informasjon

## Eksempel på utdata

```
Locked Files Report:
Index  FileName    ProcessName  ProcessId  LockType  Owner
-----  --------    -----------  ---------  --------  -----
1      rapport.xlsx  EXCEL.EXE    1234       File      DOMENE\bruker
``` 