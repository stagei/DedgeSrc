# Project: _template

**Replace this with your project name and description.**

## Purpose

Describe what this project does and why it exists.

## Scripts

| Script | Description |
|--------|-------------|
| `Run-Main.ps1` | Main entry point |

## Usage

From a developer machine, trigger execution via the orchestrator:

```powershell
. "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"

Invoke-ServerCommand -ServerName "dedge-server" `
    -Command '%OptPath%\DedgePshApps\Cursor-ServerOrchestrator\projects\<projectname>\Run-Main.ps1' `
    -Project "<projectname>"
```

This writes a `next_command_<username>_<projectname>.json` file on the target server.
The orchestrator picks it up within 60 seconds and starts the command in its own
concurrency slot.

## Configuration

Edit `config.json` to set project-specific parameters.

## Target Servers

List which servers this project targets:
- `dedge-server` (test)
- `p-no1fkxprd-app` (production)
