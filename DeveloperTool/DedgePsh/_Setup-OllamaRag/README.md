# Setup-OllamaRag

One-command setup for using local Ollama models with remote AiDoc RAG context.

This tool configures a PowerShell helper function `Ask-Rag` so developers can query RAG indexes from terminal and get answers from Ollama.

## What It Does

- Discovers available RAGs from `http://dedge-server:8484/rags`
- Verifies `ollama` is installed
- Ensures at least one model is available (pulls selected model if needed)
- Validates RAG server reachability (`/health`)
- Adds/updates `Ask-Rag` function in PowerShell profile (`$PROFILE.CurrentUserAllHosts`)
- Supports clean removal of the function (`-Remove`)

## Prerequisites

- Windows 11 / Windows Server 2025
- PowerShell 7+ (`pwsh.exe`)
- Ollama installed ([https://ollama.com](https://ollama.com))
- Network access to `dedge-server`

## Usage

Initial setup:

```powershell
pwsh.exe -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Setup-OllamaRag\Setup-OllamaRag.ps1"
```

Use a specific model:

```powershell
pwsh.exe -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Setup-OllamaRag\Setup-OllamaRag.ps1" -Model mistral
```

Remove function from profile:

```powershell
pwsh.exe -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Setup-OllamaRag\Setup-OllamaRag.ps1" -Remove
```

## After Setup

Restart PowerShell, then run:

```powershell
Ask-Rag "What does SQL30082N reason code 36 mean?"
Ask-Rag "COBCH0779 compiler error" -Rag visual-cobol-docs
Ask-Rag "Where is Deploy-Files used?" -Rag Dedge-code -Model llama3.2 -Chunks 8
```

## Ask-Rag Parameters

- `-Question` (required): user question
- `-Rag`: RAG name (`db2-docs`, `visual-cobol-docs`, `Dedge-code`, or any discovered index)
- `-Model`: Ollama model name
- `-Chunks`: number of retrieved context chunks (default `6`)

## Notes

- RAG names and URLs are auto-generated from server registry.
- If HTTP registry lookup fails, script tries UNC fallback:
  `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\FkPythonApps\AiDoc\rag-registry.json`
