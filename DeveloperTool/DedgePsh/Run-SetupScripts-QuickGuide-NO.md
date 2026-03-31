# Kjør oppsettsskript (Coding Tools)

Vennligst kjør følgende kommandoer:

```powershell
Import-Module SoftwareUtils -Force
Install-OurPshApp -AppName "Setup-CursorDb2Mcp"
Install-OurPshApp -AppName "Setup-OllamaRag"
Install-OurPshApp -AppName "Setup-CursorRag"
Install-OurPshApp -AppName "Setup-CursorUserSettings"
Install-OurPshApp -AppName "Setup-OllamaDb2"
```

## Hva hvert skript gjør

- `Setup-CursorDb2Mcp`
  - Registrerer `db2-query` MCP-serveren i Cursor `mcp.json`.
  - Resultat: Cursor kan bruke remote DB2 query MCP-endepunkt.

- `Setup-OllamaRag`
  - Legger til `Ask-Rag`-hjelpefunksjon i PowerShell-profilen og konfigurerer den mot remote RAG-servere.
  - Resultat: Du kan stille dokumentspørsmål fra terminal med Ollama + RAG.

- `Setup-CursorRag`
  - Konfigurerer Cursor til å bruke remote RAG-dokumentasjonsservere (via proxy + MCP-oppføringer).
  - Resultat: Cursor chat kan spørre de delte RAG-indeksene etter omstart.

- `Setup-CursorUserSettings`
  - Legger inn team-standard Cursor-brukerinnstillinger og installerer anbefalte Cursor-utvidelser.
  - Resultat: Standardisert Cursor-oppsett (innstillinger + utvidelser) for gjeldende bruker.

- `Setup-OllamaDb2`
  - Setter opp lokal Ollama DB2-bridge mot remote `CursorDb2McpServer`.
  - Resultat: Du får lokale hjelpekommandoer for DB2-spørringer med Ollama (`Start-Db2Bridge`, `Ask-Db2`).

## Forventet samlet resultat

Etter at alle fem installasjoner er kjørt, er maskinen klar for:

- Cursor + DB2 MCP-spørringer
- Cursor + RAG-dokumentasjonsspørsmål
- Ollama i terminal for både RAG- og DB2-flyter
- Team-standard Cursor-konfigurasjon
