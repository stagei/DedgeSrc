Autonomous deploy → run → monitor → fix → redeploy → restart cycle for remote server jobs.

## Subcommands

| Usage | Description |
|-------|-------------|
| `/autocur help` | Show this help |
| `/autocur @path/to/project` | Full autonomous run on auto-detected server |
| `/autocur @path/to/project <server>` | Full autonomous run on a specific server |
| `/autocur kill <server>` | Kill the running job on a server |
| `/autocur status <server>` | Show slot status and live stdout |

Default (no subcommand): run the full deploy → trigger → monitor → fix cycle.

---

## Subcommand: `help`

```
/autocur — Autonomous Remote Execution

Deploys a project to remote servers, triggers execution via the
Cursor-ServerOrchestrator, monitors logs, fixes errors, redeploys,
and restarts — all without user intervention.

Subcommands:
  /autocur @project              Deploy + run on auto-detected server
  /autocur @project <server>     Deploy + run on specific server
  /autocur kill <server>         Kill running job
  /autocur status <server>       Check slot status + live stdout
  /autocur help                  Show this help

Supports: PowerShell, C#/.NET, Python projects.
Requires: Cursor-ServerOrchestrator scheduled task on target servers.
```

---

## 1. Identify Entry Point

Before starting, determine the project's canonical script or executable:

| Technology | Entry point pattern | Deploy folder |
|---|---|---|
| PowerShell | Main `.ps1` in project folder | `DedgePshApps/<AppName>/` |
| C# / .NET | Published DLL or `.exe` | `DedgeWinApps/<AppName>/` |
| Python | Main `.py` script | `FkPythonApps/<AppName>/` |

Clues: `_install.ps1` (scheduled task target), `README.md`, `_deploy.ps1`, `config.*.json`.

## 2. Server Discovery

Determine target server(s) from (priority order):

1. **User instruction** — `/autocur @project t-no1fkxtst-db`
2. **`config.*.json`** — contains `ServerFqdn` or similar
3. **`_deploy.ps1`** — `ComputerNameList` shows target servers

## 3. Deploy

The server runs **deployed code**, never local code. Always deploy before triggering.

### Deploy policy

Every sub-project has a `_deploy.ps1`. Running it is the **only** way to deploy. It handles:
- Scripts in the sub-project folder
- All dependent modules (auto-resolved by `Deploy-Handler`)
- Code signing of all `.ps1` and `.psm1` files
- Multi-server distribution via Robocopy
- Version tracking via `.version` marker files

**NEVER** `Copy-Item` individual files to UNC paths. **NEVER** run module `_deploy.ps1` separately — the project `_deploy.ps1` handles modules automatically. **NEVER** force-copy unsigned `.psm1` files.

### Deploy commands by technology

```powershell
# PowerShell
pwsh.exe -NoProfile -File "<project-folder>\_deploy.ps1"

# C# / .NET (build + publish to staging share)
pwsh.exe -NoProfile -File "<solution-root>\Build-And-Publish.ps1"
# Then optionally deploy to IIS:
pwsh.exe -NoProfile -File "<repo>\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName <AppName>

# Python
pwsh.exe -NoProfile -File "<project-folder>\_deploy.ps1"
```

### Deploy pipeline internals

```
Source files ──► Local Staging ──► Remote Staging Share + Target Servers
(modules + scripts)  (sign + hash)    (Robocopy distribution)
```

1. **Dependency resolution** — `Deploy-Files` scans `Import-Module` statements, deploys changed modules first
2. **Hash + signing** — SHA256 compare against `.unsigned` copy; if changed: copy to staging, code-sign via `Invoke-DedgeSign`, save `.unsigned` backup
3. **Distribution** — Robocopy from local staging to remote software share + each server in `ComputerNameList`

### "No new files to deploy"

Means the hash matches the staging area. Re-run the same `_deploy.ps1` — do NOT fall back to manual copy.

### Deploy failure

If `_deploy.ps1` hits a breakpoint or import error: check for `Set-PSBreakpoint`/`$DebugPreference`, run with `-NoProfile`, fix and retry. Never fall back to manual copy unless production is down and `_deploy.ps1` is genuinely broken.

## 4. Trigger via Orchestrator

Run commands on remote servers without SSH or PSRemoting. File-based protocol: write JSON command, read JSON result, all via UNC shares. Scheduled task polls every 60 seconds.

### Setup (once per session)

```powershell
. "<git-root>\DevTools\CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"
```

### Available functions

| Function | Purpose |
|----------|---------|
| `Invoke-ServerCommand` | Run a file on the server, wait for result (`-Project`, `-Timeout`) |
| `Invoke-ServerScript` | Run inline PowerShell on the server (`-Script`, `-Project`) |
| `Get-ServerLog` | Read log files (AllPwshLog, IISDeployApp, DedgeAuth) |
| `Get-ServerStdout` | Peek at live stdout (`-TailLines`, `-Project`) |
| `Test-OrchestratorReady` | Check if a slot is idle or busy (`-Project`) |
| `Write-KillFile` | Abort a running command (`-Project`) |
| `Read-ResultFile` | Read last result without waiting (`-Project`) |
| `Stop-ServerProcess` | Read running PID, write kill file (`-Project`) |
| `Stop-RunningCommand` | Low-level kill (in `_Shared.ps1`) |
| `Get-RunningProcess` | Show PID, command, elapsed time |
| `Get-AllRunningSlots` | List all active user+project slots on a server |

### Trigger by technology

```powershell
# PowerShell
Invoke-ServerCommand -ServerName '<server>' `
    -Command '%OptPath%\DedgePshApps\<AppName>\<Script>.ps1' `
    -Arguments '<args>' -Project '<slug>' -Timeout <seconds>

# C# / .NET (exe)
Invoke-ServerCommand -ServerName '<server>' `
    -Command '%OptPath%\DedgeWinApps\<AppName>\<App>.exe' `
    -Arguments '<args>' -Project '<slug>' -Timeout <seconds>

# C# / .NET (dll)
Invoke-ServerCommand -ServerName '<server>' `
    -Command 'dotnet %OptPath%\DedgeWinApps\<AppName>\<App>.dll' `
    -Arguments '<args>' -Project '<slug>' -Timeout <seconds>

# Python
Invoke-ServerCommand -ServerName '<server>' `
    -Command 'py -3 %OptPath%\FkPythonApps\<AppName>\<script>.py' `
    -Arguments '<args>' -Project '<slug>' -Timeout <seconds>

# Inline PowerShell (quick commands)
Invoke-ServerScript -Script 'hostname' -ServerName '<server>'
```

**CRITICAL:** Use `%OptPath%` (Windows env var syntax), NOT `$env:OptPath`.

### Command path rules

| Format | Works? | Why |
|--------|--------|-----|
| `%OptPath%\DedgePshApps\Script.ps1` | YES | `ExpandEnvironmentVariables()` expands `%VAR%` |
| `C:\full\path\Script.ps1` | YES | Absolute paths work |
| `$env:OptPath\Script.ps1` | NO | PowerShell syntax, not expanded by .NET |

### Supported executors

| Extension | Executor |
|-----------|----------|
| `.ps1` | `pwsh.exe -NoProfile -ExecutionPolicy Bypass -File` |
| `.py` | `py -3` |
| `.bat`/`.cmd` | `cmd.exe /c` |
| `.exe` | Direct execution |
| `.rex` | `regina` |

## 5. Monitor Logs

### Log locations

| Technology | Primary log | Secondary |
|---|---|---|
| PowerShell (with override) | `\\<server>\opt\data\<AppName>\FkLog_YYYYMMDD.log` | `AllPwshLog` |
| PowerShell (without override) | `\\<server>\opt\data\AllPwshLog\FkLog_YYYYMMDD.log` | — |
| C# / .NET (Serilog) | `\\<server>\opt\data\<AppName>\Logs\*.log` | stdout |
| Python | `\\<server>\opt\data\<AppName>\*.log` | stdout |
| Orchestrator stdout | `\\<server>\opt\data\Cursor-ServerOrchestrator\stdout_capture_<user>_<project>.txt` | — |

**Always copy locally first** — never read directly from UNC:

```powershell
$localCopy = Join-Path $env:TEMP "RemoteLog_$(Split-Path $remotePath -Leaf)"
Copy-Item -Path $remotePath -Destination $localCopy -Force
```

### Live stdout

```powershell
Get-ServerStdout -ServerName '<server>' -TailLines 30 -Project '<slug>'
```

### Monitoring cadence

| Task type | Poll interval |
|---|---|
| Short (< 5 min) | Every 30-60 seconds |
| Medium (5-30 min) | Every 2-3 minutes |
| Long (30 min - 2 hours) | Every 5-10 minutes |
| Very long (2+ hours) | Every 10-30 minutes |

### Date rollover

If the job runs past midnight, check the next day's log file.

### Common patterns

| Pattern | Meaning |
|---|---|
| `JOB_STARTED` | Script began execution |
| `JOB_COMPLETED` | Finished successfully |
| `JOB_FAILED` | Failed |
| `\|ERROR\|` | Error-level entry |
| `\|WARN\|` | Warning-level entry |
| `finished with exit code: 0` | Orchestrator confirms success |
| `finished with exit code: 1` | Orchestrator detected failure |

## 6. On Error: Fix → Deploy → Kill → Restart

1. **Analyze** — Read the error from the log, identify root cause
2. **Fix** — Edit local source code
3. **Deploy** — Run the project's `_deploy.ps1` (or `Build-And-Publish.ps1`)
4. **Kill** — `Stop-ServerProcess -ServerName '<server>' -Reason 'Fix and redeploy' -Project '<slug>'`
5. **Restart** — Re-trigger via `Invoke-ServerCommand`, using skip flags if supported

Check `param()` block or README for partial restart switches (e.g., `-SkipStep1`, `-Resume`).

## 7. Post-Completion

1. **Verify exit code** — `Read-ResultFile` → `exitCode: 0`
2. **Verify log** — No `ERROR` entries after final step
3. **Run validation** — Health checks, row counts, API tests if defined
4. **Send SMS** — Notify current user:

```powershell
Import-Module GlobalFunctions -Force
Send-Sms -Receiver (Get-UserSmsNumber) -Message "<AppName> on <server>: completed. Duration: <elapsed>."
```

## 8. Execution Logs

Every `/autocur` run MUST produce a markdown log:

```
<project-folder>/ExecLogs/<servername>_<yyyyMMdd-HHmmss>.md
```

Content: start time, server, each monitoring check with timestamp, errors + root cause, fixes applied, redeploy/restart actions, final status + duration.

## 9. Concurrency and Timing

- Scheduled task polls every **60 seconds** — max wait before pickup
- **One command per user+project slot** — identified by `<user>_<project>` in filenames
- **Multiple slots run concurrently** on the same server
- **Multiple servers can run in parallel**
- **Server-side: No timeout** — job runs until exit or kill
- **Client-side: Default 1800s (30 min)** — override with `-Timeout`
- If client wait times out, job **keeps running** on server

## 10. Orchestrator Internals

```
CLIENT SIDE (dev machine)                    SERVER SIDE (remote)
─────────────────────────                    ───────────────────
_CursorAgent.ps1                             Invoke-CursorOrchestrator.ps1
  │ dot-sources ↓                              │ scheduled task (every 60s)
_Shared.ps1                                    │ scans next_command_*.json
  │ Write-CommandFile() ──UNC──►               │ starts pending commands
  │ Wait-ForResult() ◄──UNC──                  │ polls kill file every 10s
  │ Get-ServerStdout() → stdout_capture        │ writes last_result + history/
```

### Server data paths

| Item | Path |
|------|------|
| Command | `\\<server>\opt\data\Cursor-ServerOrchestrator\next_command_<user>_<project>.json` |
| Result | `\\<server>\opt\data\Cursor-ServerOrchestrator\last_result_<user>_<project>.json` |
| Running | `\\<server>\opt\data\Cursor-ServerOrchestrator\running_command_<user>_<project>.json` |
| Kill | `\\<server>\opt\data\Cursor-ServerOrchestrator\kill_command_<user>_<project>.txt` |
| Stdout | `\\<server>\opt\data\Cursor-ServerOrchestrator\stdout_capture_<user>_<project>.txt` |
| Stderr | `\\<server>\opt\data\Cursor-ServerOrchestrator\stderr_capture_<user>_<project>.txt` |
| History | `\\<server>\opt\data\Cursor-ServerOrchestrator\history\` |

### Result statuses

| Status | Trigger |
|--------|---------|
| `COMPLETED` | Exit code 0 |
| `FAILED` | Non-zero exit code |
| `KILLED` | Kill file detected |
| `REJECTED` | Security validation failed |
| `PARSE_ERROR` | Invalid JSON in command file |

## 11. Mandatory Behaviors

1. **NEVER stop and ask the user to check the log** — the agent checks it
2. **NEVER tell the user to run something manually** — use the orchestrator
3. **NEVER use arbitrary retry limits** — continue until success or deadline
4. **NEVER lose track of progress** — maintain a todo list
5. **NEVER read logs directly from UNC** — copy locally first
6. **Always deploy before triggering**
7. **Always check for date rollover** past midnight
8. **Always send SMS on completion or critical failure**
9. **Be proactive** — detect errors, diagnose, fix, deploy, kill, restart

## 12. Project-Specific Overrides

Projects may provide a local `.cursor/rules/` file that overrides sections of this command with custom entry points, log paths, step sequences, skip switches, known error patterns, and validation commands.
