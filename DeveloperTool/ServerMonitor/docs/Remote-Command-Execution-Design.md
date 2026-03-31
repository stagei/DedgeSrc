# Remote Script Execution Feature - Design Specification

## Overview

A new feature allowing administrators to execute predefined PowerShell scripts on multiple remote servers simultaneously. Accessed via a **web page in the Dashboard** (opened from Dashboard Tray menu), scripts are executed via the ServerMonitorTrayIcon API on each target server. Results are displayed in an **expandable grid** (similar to the Alerts panel) with status indicators.

**Key Features:**
- Web-based UI (not a Windows Form)
- Expandable grid rows showing script output (like Alerts panel)
- Status lights: 🟡 Pending → 🟢 Success / 🔴 Error
- Only predefined scripts via `run-psh` or `inst-psh`
- Hardcoded user authorization (FKSVEERI, FKGEISTA)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Dashboard Tray Application                            │
│  ┌─────────────┐                                                            │
│  │ Tray Icon   │──── "Command" menu item ────▶ Opens Browser to:            │
│  │             │                               http://localhost:8998/       │
│  └─────────────┘                               script-runner.html           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Dashboard Web App (Port 8998)                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  script-runner.html - Script Execution Page                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │ Server Selection | Script Input | Execute Button                │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │ Results Grid (expandable rows like Alerts panel)                │  │  │
│  │  │ ┌───────┬────────────────┬──────────┬─────────┬───────┬───────┐ │  │  │
│  │  │ │Status │ Server         │ Timestamp│ Script  │ Mode  │ Time  │ │  │  │
│  │  │ ├───────┼────────────────┼──────────┼─────────┼───────┼───────┤ │  │  │
│  │  │ │  🟢   │ p-no1fkmprd-app│ 12:34:56 │ MyScript│ run   │ 1.2s  │ │  │  │
│  │  │ │  ▼    │ (click to expand and see output)                    │ │  │  │
│  │  │ │  🟡   │ dedge-server│ 12:34:56 │ MyScript│ run   │ ...   │ │  │  │
│  │  │ │  🔴   │ p-no1inlprd-app│ 12:34:56 │ MyScript│ run   │ 0.5s  │ │  │  │
│  │  │ └───────┴────────────────┴──────────┴─────────┴───────┴───────┘ │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  API: POST /api/script/proxy-execute (proxies to Agent Tray)                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ HTTP POST /api/script/execute
                                      │ { "mode": "run", "scriptName": "...", "requestedBy": "..." }
                                      ▼
        ┌─────────────────────────────────────────────────────────────────────┐
        │                   Target Servers (via Agent Tray API)                │
        │                                                                      │
        │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
        │  │ p-no1fkmprd-app  │  │ dedge-server  │  │ p-no1inlprd-app  │  │
        │  │ Port 8997        │  │ Port 8997        │  │ Port 8997        │  │
        │  │ TrayApiServer    │  │ TrayApiServer    │  │ TrayApiServer    │  │
        │  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
        └─────────────────────────────────────────────────────────────────────┘
```

---

## Data Source

### ComputerInfo.json

Location: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json`

Structure:
```json
{
  "Name": "p-no1fkmprd-app",
  "Type": "Server",
  "Platform": "Azure",
  "Environments": ["PRD"],
  "IsActive": true
}
```

### Server Filtering Criteria

- **Platform**: Filter to `"Azure"` only (production infrastructure)
- **Type**: Filter to `"Server"` only (exclude Developer Machine, Private Machine)
- **IsActive**: Must be `true`

---

## Server Selection

### Auto-Generated Patterns

Analyze Azure server names to extract two pattern types:

#### 1. Server Type Patterns (suffix after last `-`)

| Pattern | Regex | Example Servers |
|---------|-------|-----------------|
| `-app` | `.*-app$` | p-no1fkmprd-app, t-no1inltst-app, p-no1fkxprd-app |
| `-db` | `.*-db$` | p-no1fkmprd-db, t-no1fkmtst-db, p-no1inlprd-db |
| `-soa` | `.*-soa$` | p-no1fkmprd-soa, t-no1fkmtst-soa |
| `-web` | `.*-web$` | p-no1fkmprd-web, t-no1fkmtst-web |
| `-pos` | `.*-pos$` | p-no1fkmprd-pos, t-no1fkmtst-pos |
| `-mcl` | `.*-mcl$` | p-no1fkmprd-mcl |

#### 2. Environment Patterns (3 chars before last `-`)

Extract the 3 characters immediately before the final `-` to identify environment:

| Pattern | Regex | Example Servers |
|---------|-------|-----------------|
| `prd` | `.*prd-[^-]+$` | p-no1fkmprd-app, p-no1inlprd-db, p-no1fkmprd-soa |
| `tst` | `.*tst-[^-]+$` | t-no1fkmtst-app, t-no1inltst-db, t-no1fkmtst-web |
| `dev` | `.*dev-[^-]+$` | t-no1fkmdev-db, t-no1inldev-db |
| `vft` | `.*vft-[^-]+$` | t-no1fkmvft-db |
| `vfk` | `.*vfk-[^-]+$` | t-no1fkmvfk-db |
| `sit` | `.*sit-[^-]+$` | t-no1fkmsit-db |
| `mig` | `.*mig-[^-]+$` | t-no1fkmmig-db |
| `per` | `.*per-[^-]+$` | t-no1fkmper-db |
| `fut` | `.*fut-[^-]+$` | t-no1fkmfut-db |
| `kat` | `.*kat-[^-]+$` | t-no1fkmkat-db |
| `fsp` | `.*fsp-[^-]+$` | t-no1fkmfsp-app |
| `rap` | `.*rap-[^-]+$` | p-no1fkmrap-db |

### Pattern Generation Algorithm

```csharp
var azureServers = allServers
    .Where(s => s.Platform == "Azure" && s.Type == "Server" && s.IsActive)
    .Select(s => s.Name)
    .ToList();

// Extract server type patterns (suffix after last dash)
var typePatterns = azureServers
    .Select(name => {
        var lastDash = name.LastIndexOf('-');
        return lastDash >= 0 ? name.Substring(lastDash) : null;
    })
    .Where(suffix => suffix != null)
    .Distinct()
    .OrderBy(s => s)
    .ToList();

// Extract environment patterns (3 chars before last dash)
var envPatterns = azureServers
    .Select(name => {
        var lastDash = name.LastIndexOf('-');
        // Get 3 chars before the last dash: e.g., "p-no1fkmprd-app" → "prd"
        if (lastDash >= 3) {
            return name.Substring(lastDash - 3, 3);
        }
        return null;
    })
    .Where(env => env != null)
    .Distinct()
    .OrderBy(s => s)
    .ToList();
```

### Selection UI

1. **Server Type Checkboxes** (row 1): Filter by server role
   - `[x] -app (4)`  `[ ] -db (8)`  `[x] -soa (2)`  `[ ] -web (2)`
   - `[ ] -pos (2)`  `[ ] -mcl (1)`
   - Checking a type selects all matching servers

2. **Environment Checkboxes** (row 2): Filter by environment code
   - `[x] prd (6)`  `[ ] tst (8)`  `[ ] dev (3)`  `[ ] vft (1)`
   - `[ ] sit (1)`  `[ ] mig (1)`  `[ ] per (1)`  `[ ] fut (1)`
   - Auto-generated from distinct 3-char codes before last `-`

3. **Combined Filtering**: Both filters work together (AND logic)
   - Selecting `-app` + `prd` shows only production app servers
   - Selecting `-db` + `tst` + `dev` shows test and dev database servers

4. **Matching Servers List**: Shows servers matching current filter
   - TreeView grouped by server type
   - Individual checkboxes for fine-grained selection
   - Uncheck specific servers to exclude from execution

5. **Confirmation Before Execution**:
   - After clicking Execute, show confirmation dialog:
     ```
     ┌─────────────────────────────────────────────────────┐
     │ Confirm Command Execution                          │
     ├─────────────────────────────────────────────────────┤
     │ Command: Get-Service ServerMonitor                 │
     │                                                    │
     │ The following 6 servers will execute this command: │
     │   • p-no1fkmprd-app                                │
     │   • p-no1inlprd-app                                │
     │   • p-no1fkxprd-app                                │
     │   • t-no1fkmtst-app                                │
     │   • t-no1inltst-app                                │
     │   • dedge-server                                │
     │                                                    │
     │              [Execute]  [Cancel]                   │
     └─────────────────────────────────────────────────────┘
     ```
   - User must confirm before tabs are created and command is sent
   - This prevents accidental execution on wrong servers

---

## Command Execution

### Predefined Script Execution Only

This feature does **NOT** allow arbitrary PowerShell commands. It only executes **predefined scripts** that are already distributed on the target servers.

### Execution Modes (Radio Buttons)

Two hardcoded execution modes are available:

| Mode | Command Prefix | Description |
|------|----------------|-------------|
| **Run** | `run-psh` | Execute a script (for running existing scripts) |
| **Install** | `inst-psh` | Install/deploy a script (for installation scripts) |

### Script Input

- **Single-line TextBox** for script name only (e.g., `MyScript`, `Deploy-Agent`)
- **Radio buttons** to select execution mode: `( ) Run` or `( ) Install`
- Script name is passed to the server **without validation** (scripts must already exist on server)
- **No arbitrary commands allowed** - only script names

### Execution Flow

1. User selects execution mode (Run or Install)
2. User enters script name
3. User clicks Execute
4. Confirmation dialog shows server list
5. For each selected server (in parallel):
   - Display "Executing..." in the server's tab
   - POST to `http://{server}:8997/api/script/execute`
   - Include username of requester for authorization
   - Display output when received
   - Handle errors/timeouts gracefully

### Output Display

Each tab shows a read-only, scrollable text area styled like PowerShell:

```
PS C:\> run-psh MyScript

Script executed successfully.
Output from MyScript...

PS C:\> 
```

**Styling:**
- Dark background (#012456 - PowerShell blue-black)
- White/light gray text
- Consolas/JetBrains Mono font
- Errors in red, success in green

---

## Agent Tray API Extension

### New Endpoint: POST /api/script/execute

**Request:**
```json
{
  "mode": "run",
  "scriptName": "MyScript",
  "requestedBy": "FKGEISTA",
  "timeoutSeconds": 30
}
```

| Field | Type | Description |
|-------|------|-------------|
| `mode` | string | Either `"run"` or `"install"` (maps to `run-psh` or `inst-psh`) |
| `scriptName` | string | Name of the script to execute (no validation, must exist on server) |
| `requestedBy` | string | Username of the person requesting execution (for authorization) |
| `timeoutSeconds` | int | Optional timeout (default 30 seconds) |

**Response (Success):**
```json
{
  "success": true,
  "exitCode": 0,
  "command": "run-psh MyScript",
  "output": "Script executed successfully.\nOutput from MyScript...",
  "error": null,
  "executionTimeMs": 1245
}
```

**Response (Unauthorized):**
```json
{
  "success": false,
  "exitCode": -1,
  "command": null,
  "output": null,
  "error": "Unauthorized: User 'SOMEUSER' is not allowed to execute scripts",
  "executionTimeMs": 0
}
```

**Response (Invalid Mode):**
```json
{
  "success": false,
  "exitCode": -1,
  "command": null,
  "output": null,
  "error": "Invalid mode: 'foo'. Only 'run' or 'install' are allowed",
  "executionTimeMs": 0
}
```

**Response (Script Error):**
```json
{
  "success": false,
  "exitCode": 1,
  "command": "run-psh MyScript",
  "output": "",
  "error": "Script 'MyScript' not found or failed to execute",
  "executionTimeMs": 123
}
```

### Security Considerations

1. **User Access Control (Dashboard Tray - Client Side)**:
   - The "Command" menu item is **only visible** to authorized users
   - **Hardcoded** authorized usernames (not configurable):
     - `FKSVEERI`
     - `FKGEISTA`
   - Check performed via `Environment.UserName` at menu creation time
   - Menu item is simply not added if user is not authorized (no error message)

2. **User Access Control (Agent Tray - Server Side)**:
   - The API endpoint **validates the `requestedBy` field** before execution
   - **Hardcoded** authorized usernames (same list, not configurable):
     - `FKSVEERI`
     - `FKGEISTA`
   - Requests from any other username are **rejected with 403 Forbidden**
   - Implementation:
     ```csharp
     // In TrayApiServer.cs - hardcoded, not configurable
     private static readonly HashSet<string> AuthorizedScriptUsers = new(StringComparer.OrdinalIgnoreCase)
     {
         "FKSVEERI",
         "FKGEISTA"
     };
     
     private bool IsUserAuthorized(string requestedBy)
     {
         return AuthorizedScriptUsers.Contains(requestedBy);
     }
     ```
   - All unauthorized requests are logged but silently ignored (no execution)

3. **Command Prefix Validation (Agent Tray - Server Side)**:
   - Only two command prefixes are allowed: `run-psh` and `inst-psh`
   - These are **hardcoded** and cannot be changed via configuration
   - Implementation:
     ```csharp
     // Hardcoded valid modes - only these two are allowed
     private static readonly Dictionary<string, string> ValidModes = new(StringComparer.OrdinalIgnoreCase)
     {
         { "run", "run-psh" },
         { "install", "inst-psh" }
     };
     
     private string? GetCommandPrefix(string mode)
     {
         return ValidModes.TryGetValue(mode, out var prefix) ? prefix : null;
     }
     ```
   - Any other mode value is rejected with an error response

4. **No API Documentation (Hidden Feature)**:
   - The `/api/script/execute` endpoint is **NOT documented anywhere**
   - **Agent Tray**: Endpoint excluded from any API documentation
   - **Dashboard Tray**: No Swagger/OpenAPI exposure for this feature
   - **Dashboard Web App**: No references to script execution in Swagger docs
   - The feature is only known to authorized users via the hidden menu item

5. **No Arbitrary Commands**:
   - Only predefined scripts (already on server) can be executed
   - Only two execution modes: `run-psh` and `inst-psh`
   - Script names are passed as-is (no validation needed - scripts must exist)
   - This is NOT a remote shell - just a script runner

6. **Audit Logging**:
   - All script execution requests are logged with:
     - Timestamp
     - Requesting username
     - Script name
     - Execution mode
     - Success/failure result
   - Unauthorized attempts are also logged

---

## UI Components

### Script Runner Web Page (`script-runner.html`)

A pop-out web page (like alert-settings.html) styled to match the Dashboard theme.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 🛠️ Script Runner                                              [Theme Toggle]│
├─────────────────────────────────────────────────────────────────────────────┤
│ ┌─ Server Selection ─────────────────────────────────────────────────────┐  │
│ │ Server Type:                                                            │  │
│ │ [x] -app (4)  [ ] -db (8)  [ ] -soa (2)  [ ] -web (2)  [ ] -pos (2)    │  │
│ │                                                                         │  │
│ │ Environment:                                                            │  │
│ │ [x] prd (6)  [ ] tst (8)  [ ] dev (3)  [ ] other...                    │  │
│ │                                                                         │  │
│ │ Matching: 4 servers  [Select All] [Clear]                              │  │
│ └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│ ┌─ Script Execution ─────────────────────────────────────────────────────┐  │
│ │ Mode:  (•) Run (run-psh)   ( ) Install (inst-psh)                      │  │
│ │                                                                         │  │
│ │ Script Name: [____________________]  [Execute]  [Clear Results]        │  │
│ └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│ ┌─ Execution Results ────────────────────────────────────────────────────┐  │
│ │                                                                         │  │
│ │ ┌────────┬──────────────────┬──────────┬──────────┬──────┬───────────┐ │  │
│ │ │ Status │ Server           │ Started  │ Script   │ Mode │ Duration  │ │  │
│ │ ├────────┼──────────────────┼──────────┼──────────┼──────┼───────────┤ │  │
│ │ │   🟢   │ p-no1fkmprd-app  │ 12:34:56 │ MyScript │ run  │ 1.2s      │ │  │
│ │ │   ▼ ───┴──────────────────┴──────────┴──────────┴──────┴───────────┤ │  │
│ │ │   │ Output:                                                        │ │  │
│ │ │   │ Script executed successfully.                                  │ │  │
│ │ │   │ Installed 3 components.                                        │ │  │
│ │ │   └────────────────────────────────────────────────────────────────┤ │  │
│ │ │   🟡   │ dedge-server  │ 12:34:56 │ MyScript │ run  │ ...       │ │  │
│ │ │   🔴   │ p-no1inlprd-app  │ 12:34:56 │ MyScript │ run  │ 0.5s      │ │  │
│ │ │   ▼ ───┴──────────────────┴──────────┴──────────┴──────┴───────────┤ │  │
│ │ │   │ Error:                                                         │ │  │
│ │ │   │ Script 'MyScript' not found in C:\opt\scripts                  │ │  │
│ │ │   └────────────────────────────────────────────────────────────────┤ │  │
│ │ │   🟢   │ p-no1fkxprd-app  │ 12:34:56 │ MyScript │ run  │ 2.1s      │ │  │
│ │ └────────┴──────────────────┴──────────┴──────────┴──────┴───────────┘ │  │
│ │                                                                         │  │
│ └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│ Summary: 3 success, 1 error, 0 pending                                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Status Indicators

| Status | Icon | Description |
|--------|------|-------------|
| Pending | 🟡 | Script execution started, waiting for response |
| Success | 🟢 | Script executed successfully (exit code 0) |
| Error | 🔴 | Script failed (non-zero exit code, timeout, or connection error) |

### Expandable Row Details

Each row in the results grid is **expandable** (click to toggle):
- **Collapsed**: Shows status, server, timestamp, script, mode, duration
- **Expanded**: Shows full script output in a preformatted block

### Grid Behavior

1. **On Execute Click**:
   - Confirmation dialog shows server list
   - On confirm, immediately add all selected servers to the grid
   - Each row starts with 🟡 (yellow/pending) status
   - Timestamp is the moment execution was initiated

2. **As Results Return**:
   - Each server's row updates independently
   - Status changes from 🟡 to 🟢 (success) or 🔴 (error)
   - Duration updates with actual execution time
   - Output becomes available for expansion

3. **Sorting**: Newest executions at top (or group by batch)

### Color Scheme (Dashboard Theme)

Uses existing Dashboard CSS variables for light/dark mode consistency:

| Element | Light Mode | Dark Mode |
|---------|------------|-----------|
| Success Row | Light green bg | Dark green bg |
| Error Row | Light red bg | Dark red bg |
| Pending Row | Light yellow bg | Dark yellow bg |
| Output Block | Light gray bg | Dark gray bg |

---

## Implementation TODO

### Phase 1: Agent Tray API Extension

- [ ] **1.1** Add new endpoint `POST /api/script/execute` in `TrayApiServer.cs`
- [ ] **1.2** Add hardcoded authorized users list (FKSVEERI, FKGEISTA)
- [ ] **1.3** Validate `requestedBy` field against authorized users (reject others)
- [ ] **1.4** Add hardcoded valid modes map: `run` → `run-psh`, `install` → `inst-psh`
- [ ] **1.5** Validate mode and reject invalid values
- [ ] **1.6** Execute script using `run-psh` or `inst-psh` with script name
- [ ] **1.7** Implement timeout handling (default 30s)
- [ ] **1.8** Add audit logging for all requests (authorized and unauthorized)
- [ ] **1.9** **Exclude endpoint from any API documentation** (hidden API)
- [ ] **1.10** Test endpoint locally with curl/Postman

### Phase 2: Dashboard Web App - Script Runner Page

- [ ] **2.1** Create `script-runner.html` page (pop-out like alert-settings.html)
- [ ] **2.2** Create `script-runner.css` with Dashboard theme support
- [ ] **2.3** Create `script-runner.js` for page logic
- [ ] **2.4** Load server list from ComputerInfo.json via Dashboard API
- [ ] **2.5** Implement server type pattern extraction (suffix after last `-`)
- [ ] **2.6** Implement environment pattern extraction (3 chars before last `-`)
- [ ] **2.7** Add server type checkbox row with counts
- [ ] **2.8** Add environment checkbox row with counts
- [ ] **2.9** Implement combined AND filtering
- [ ] **2.10** Add Select All / Clear buttons

### Phase 3: Dashboard Web App - Script Input & Execution

- [ ] **3.1** Add radio buttons for mode: Run (run-psh) / Install (inst-psh)
- [ ] **3.2** Add script name input field
- [ ] **3.3** Add Execute and Clear Results buttons
- [ ] **3.4** Add confirmation modal showing server list before execution
- [ ] **3.5** On confirm, add all servers to results grid with 🟡 pending status
- [ ] **3.6** Store username for `requestedBy` field

### Phase 4: Dashboard Web App - Results Grid

- [ ] **4.1** Create expandable results grid (like Alerts panel)
- [ ] **4.2** Grid columns: Status, Server, Timestamp, Script, Mode, Duration
- [ ] **4.3** Implement row expansion to show script output
- [ ] **4.4** Status indicator: 🟡 pending → 🟢 success / 🔴 error
- [ ] **4.5** Style success/error/pending rows with appropriate colors
- [ ] **4.6** Add summary bar: "3 success, 1 error, 0 pending"

### Phase 5: Dashboard API - Proxy Endpoint

- [ ] **5.1** Create `POST /api/script/proxy-execute` endpoint in Dashboard
- [ ] **5.2** Accept: servers[], mode, scriptName, requestedBy
- [ ] **5.3** Validate requestedBy against hardcoded users (FKSVEERI, FKGEISTA)
- [ ] **5.4** For each server, call Agent Tray API in parallel
- [ ] **5.5** Return results as they complete (or batch response)
- [ ] **5.6** Handle timeouts and connection errors per server

### Phase 6: Dashboard Tray - Menu Integration

- [ ] **6.1** Add "Command" menu item to tray context menu
- [ ] **6.2** Check `Environment.UserName` against hardcoded users
- [ ] **6.3** Only show menu item for FKSVEERI, FKGEISTA
- [ ] **6.4** On click, open browser to `http://localhost:8998/script-runner.html`
- [ ] **6.5** Pass username as query param: `?user=FKGEISTA`

### Phase 7: Testing & Polish

- [ ] **7.1** Test pattern extraction with real ComputerInfo.json
- [ ] **7.2** Test API authorization (verify unauthorized users rejected)
- [ ] **7.3** Test script execution on test servers
- [ ] **7.4** Verify grid updates as results return
- [ ] **7.5** Test dark/light mode theme switching
- [ ] **7.6** Add copy-to-clipboard for output
- [ ] **7.7** Add keyboard shortcuts (Enter = Execute)
- [ ] **7.8** Persist last selected filters in localStorage

---

## Configuration

### Dashboard Tray appsettings.json

```json
{
  "RemoteScript": {
    "DefaultTimeoutSeconds": 30,
    "MaxParallelExecutions": 10,
    "ScriptHistorySize": 50,
    "AgentTrayPort": 8997
  }
}
```

**Note:** Authorized users are **hardcoded** (FKSVEERI, FKGEISTA) - not configurable.

### Agent Tray appsettings.json

```json
{
  "ScriptExecution": {
    "Enabled": true,
    "MaxTimeoutSeconds": 120,
    "LogScriptExecutions": true
  }
}
```

**Note:** The following are **hardcoded** and not configurable:
- Authorized users: `FKSVEERI`, `FKGEISTA`
- Valid modes: `run` → `run-psh`, `install` → `inst-psh`

---

## Error Handling

| Scenario | User Feedback |
|----------|---------------|
| Server offline | Tab shows "Connection refused - server may be offline" |
| Script timeout | Tab shows "Script timed out after 30 seconds" |
| Script not found | Tab shows error output from run-psh/inst-psh |
| Unauthorized user | Tab shows "Unauthorized: User 'X' is not allowed to execute scripts" |
| Invalid mode | Tab shows "Invalid mode: Only 'run' or 'install' are allowed" |
| API error | Tab shows "API error: {message}" |
| No servers selected | Execute button disabled, tooltip: "Select at least one server" |
| Empty script name | Execute button disabled, tooltip: "Enter a script name" |

---

## Future Enhancements

1. **Script Library**: Pre-defined scripts with descriptions
2. **Command Templates**: Parameterized commands (e.g., "Restart service: [name]")
3. **Scheduled Execution**: Run commands at specified times
4. **Output Comparison**: Side-by-side diff of output from multiple servers
5. **Authentication**: Windows authentication or API keys
6. **Role-Based Access**: Different users can run different command sets
7. **Command Approval**: Require approval for destructive commands

---

## Files to Create/Modify

### New Files

| File | Project | Description |
|------|---------|-------------|
| `script-runner.html` | ServerMonitorDashboard | Script runner web page |
| `css/script-runner.css` | ServerMonitorDashboard | Styles for script runner |
| `js/script-runner.js` | ServerMonitorDashboard | Script runner logic |
| `Controllers/ScriptController.cs` | ServerMonitorDashboard | Proxy API for script execution |
| `Services/ScriptProxyService.cs` | ServerMonitorDashboard | HTTP client to Agent Tray APIs |

### Modified Files

| File | Project | Changes |
|------|---------|---------|
| `TrayApiServer.cs` | ServerMonitorTrayIcon | Add /api/script/execute endpoint |
| `DashboardTrayContext.cs` | ServerMonitorDashboard.Tray | Add "Command" menu item → opens browser |
| `index.html` | ServerMonitorDashboard | Add link to script runner in Tools panel |
| `Program.cs` | ServerMonitorDashboard | Register ScriptController |

### User Authorization (Hardcoded - Both Client and Server)

The following users are authorized to use the Command feature. This list is **hardcoded** in **both** applications and is **not configurable** via settings:

**Dashboard Tray (Client - menu visibility):**
```csharp
// In DashboardTrayContext.cs
private static readonly HashSet<string> AuthorizedScriptUsers = new(StringComparer.OrdinalIgnoreCase)
{
    "FKSVEERI",
    "FKGEISTA"
};
```

**Agent Tray (Server - API validation):**
```csharp
// In TrayApiServer.cs
private static readonly HashSet<string> AuthorizedScriptUsers = new(StringComparer.OrdinalIgnoreCase)
{
    "FKSVEERI",
    "FKGEISTA"
};
```

**Important:** Authorization is checked in **both places**:
1. **Client-side**: Menu item not shown to unauthorized users
2. **Server-side**: API rejects requests from unauthorized users

To add or remove users, **both** files must be modified and redeployed.

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Agent Tray API Extension | 4-6 hours |
| Phase 2: Script Runner Page (HTML/CSS) | 3-4 hours |
| Phase 3: Script Input & Execution (JS) | 3-4 hours |
| Phase 4: Results Grid | 4-6 hours |
| Phase 5: Dashboard Proxy API | 3-4 hours |
| Phase 6: Tray Menu Integration | 1-2 hours |
| Phase 7: Testing & Polish | 2-4 hours |
| **Total** | **20-30 hours** |

---

## Approval Checklist

- [ ] Architecture approved
- [ ] Security considerations reviewed
- [ ] UI mockups approved
- [ ] API contract finalized
- [ ] Configuration structure approved
