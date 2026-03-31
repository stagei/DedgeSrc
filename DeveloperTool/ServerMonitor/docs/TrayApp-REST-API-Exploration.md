# ServerMonitor Tray App REST API - Feasibility Analysis

## Current Architecture: Trigger Files

The current communication between the Dashboard and Tray App uses **file-based triggers**:

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│   Dashboard (API)   │ ──────▶ │  Network Share (UNC Path)        │
│   Port 8998         │  Write  │  \\server\Config\ServerMonitor\  │
└─────────────────────┘         └──────────────────────────────────┘
                                              │
                                              │ FileSystemWatcher / Polling
                                              ▼
                                ┌──────────────────────────────────┐
                                │   Tray App (per server)          │
                                │   Reads trigger files            │
                                │   Executes actions               │
                                └──────────────────────────────────┘
```

### Current Trigger Files
| File | Purpose |
|------|---------|
| `ReinstallServerMonitor.txt` | Global reinstall trigger |
| `ReinstallServerMonitor_{SERVER}.txt` | Server-specific reinstall |
| `StartServerMonitor.txt` | Global start trigger |
| `StartServerMonitor_{SERVER}.txt` | Server-specific start |
| `StopServerMonitor.txt` | Global stop trigger |
| `StopServerMonitorTray.txt` | Stop tray app itself |

---

## Proposed Architecture: REST API on Tray App

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│   Dashboard (API)   │ ──────▶ │   Tray App REST API              │
│   Port 8998         │  HTTP   │   Port 8997 (each server)        │
└─────────────────────┘         └──────────────────────────────────┘
                                              │
                                              │ Direct control
                                              ▼
                                ┌──────────────────────────────────┐
                                │   ServerMonitor Agent Service    │
                                │   Port 8999                      │
                                └──────────────────────────────────┘
```

### Proposed Tray App API Endpoints

```
GET  /api/status           - Get tray app status
GET  /api/agent/status     - Get agent service status
GET  /api/agent/version    - Get installed agent version

POST /api/agent/start      - Start the agent service
POST /api/agent/stop       - Stop the agent service  
POST /api/agent/restart    - Restart the agent service
POST /api/agent/reinstall  - Reinstall from source

POST /api/tray/exit        - Close the tray application
```

---

## Comparison: Trigger Files vs REST API

| Aspect | Trigger Files | REST API |
|--------|---------------|----------|
| **Latency** | 1-3 seconds (polling/watcher) | Immediate (~50ms) |
| **Reliability** | Depends on network share availability | Requires tray app to be running |
| **Firewall** | No additional ports needed | Requires port 8997 open |
| **Complexity** | Simple file I/O | HTTP server in tray app |
| **Feedback** | No direct response | Immediate success/failure |
| **Offline servers** | Files wait until server reads | Immediate "unreachable" error |
| **Broadcast** | Easy (global files) | Requires loop over servers |
| **State tracking** | File existence = pending | Real-time status |
| **Debugging** | Check file existence | HTTP response codes/logs |

---

## Implementation Details

### 1. Add Minimal HTTP Server to Tray App

Using `HttpListener` (built into .NET, no dependencies):

```csharp
public class TrayApiServer : IDisposable
{
    private readonly HttpListener _listener;
    private readonly CancellationTokenSource _cts;
    private readonly ServiceManager _serviceManager;
    private const int Port = 8997;

    public TrayApiServer(ServiceManager serviceManager)
    {
        _serviceManager = serviceManager;
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://+:{Port}/");
        _cts = new CancellationTokenSource();
    }

    public void Start()
    {
        _listener.Start();
        Task.Run(() => ListenLoop(_cts.Token));
    }

    private async Task ListenLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var context = await _listener.GetContextAsync();
                _ = HandleRequestAsync(context);
            }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                Debug.WriteLine($"API error: {ex.Message}");
            }
        }
    }

    private async Task HandleRequestAsync(HttpListenerContext context)
    {
        var path = context.Request.Url?.AbsolutePath ?? "";
        var method = context.Request.HttpMethod;
        
        object? response = (method, path) switch
        {
            ("GET", "/api/status") => new { status = "running", version = GetVersion() },
            ("GET", "/api/agent/status") => new { running = _serviceManager.IsRunning() },
            ("POST", "/api/agent/start") => await StartAgent(),
            ("POST", "/api/agent/stop") => await StopAgent(),
            ("POST", "/api/agent/reinstall") => await TriggerReinstall(),
            _ => null
        };

        await WriteJsonResponse(context.Response, response);
    }
}
```

### 2. Required Firewall Configuration

```powershell
# Add to ServerMonitorAgent
New-NetFirewallRule -DisplayName "ServerMonitor Tray API" `
    -Direction Inbound -LocalPort 8997 -Protocol TCP -Action Allow
```

### 3. Dashboard API Changes

```csharp
// Instead of creating trigger files:
public async Task<ActionResult> StartAgent(string serverName)
{
    var client = _httpClientFactory.CreateClient();
    try
    {
        var response = await client.PostAsync(
            $"http://{serverName}:8997/api/agent/start", 
            null);
        
        return Ok(new { 
            success = response.IsSuccessStatusCode,
            message = response.IsSuccessStatusCode 
                ? "Agent started successfully" 
                : "Failed to start agent"
        });
    }
    catch (HttpRequestException)
    {
        return Ok(new { 
            success = false, 
            message = "Tray app not reachable" 
        });
    }
}
```

---

## Advantages of REST API

### ✅ Immediate Feedback
```
Dashboard → POST /api/agent/start → 200 OK { "success": true }
```
No more waiting and polling for file deletion.

### ✅ Real-Time Status
```
Dashboard → GET /api/status → { "agentRunning": true, "version": "1.0.72" }
```
Know instantly if a server's tray app is running.

### ✅ Better Error Handling
- Connection refused → Tray app not running
- 500 error → Action failed with details
- Timeout → Network issue

### ✅ Simpler Dashboard Code
No more:
- Creating trigger files
- Polling for file deletion
- Handling file system errors

### ✅ Audit Trail
HTTP logs provide automatic audit of who triggered what action.

---

## Disadvantages / Challenges

### ❌ Additional Firewall Port
- Port 8997 must be opened on all servers
- More attack surface

### ❌ Tray App Must Be Running
- If tray crashes, no way to remotely start it
- Trigger files can "queue" actions for when tray restarts

### ❌ No "Fire and Forget" for Offline Servers
- Trigger files wait on disk until server comes online
- REST API would need retry logic in Dashboard

### ❌ Admin Rights for HttpListener
- `HttpListener` on `http://+:port/` requires admin or URL ACL
- Can use `http://localhost:port/` but then not accessible remotely

### ❌ Broadcast Actions More Complex
- "Stop All" requires looping through all servers
- Trigger file approach: one file affects all

---

## Hybrid Approach (Recommended)

Keep **trigger files for broadcast/offline scenarios** and add **REST API for real-time control**:

```
┌─────────────────────┐
│   Dashboard         │
├─────────────────────┤
│ Single Server:      │ ──▶ REST API (immediate feedback)
│   Start/Stop/Status │
├─────────────────────┤
│ All Servers:        │ ──▶ Trigger Files (broadcast)
│   Stop All          │
│   Update All        │
├─────────────────────┤
│ Offline Servers:    │ ──▶ Trigger Files (queued)
│   Start when ready  │
└─────────────────────┘
```

### Benefits of Hybrid:
1. **Best of both worlds** - Real-time for online servers, queued for offline
2. **Backward compatible** - Existing trigger file logic still works
3. **Graceful degradation** - If REST fails, fall back to trigger files
4. **Progressive rollout** - Add REST API without breaking existing functionality

---

## Security Considerations

### Authentication Options

1. **API Key in Header**
   ```http
   POST /api/agent/start
   X-API-Key: shared-secret-key
   ```

2. **Windows Authentication (NTLM/Kerberos)**
   ```csharp
   _listener.AuthenticationSchemes = AuthenticationSchemes.IntegratedWindowsAuthentication;
   ```

3. **IP Whitelist**
   ```csharp
   if (!IsAllowedIp(context.Request.RemoteEndPoint.Address))
       return Unauthorized();
   ```

4. **Mutual TLS (mTLS)**
   - Requires certificate on Dashboard and each Tray App
   - Most secure but complex setup

### Recommended: Windows Authentication + IP Whitelist
- Only allow requests from known Dashboard servers
- Leverage existing Windows domain authentication

---

## Estimated Implementation Effort

| Component | Effort | Notes |
|-----------|--------|-------|
| Tray API Server class | 4-6 hours | HttpListener setup, routing |
| API endpoints (5-7) | 2-3 hours | Start/Stop/Status/Reinstall |
| Firewall configuration | 1 hour | PowerShell script update |
| Dashboard API changes | 3-4 hours | New service to call Tray APIs |
| Dashboard UI updates | 2-3 hours | Show real-time status |
| Authentication | 2-4 hours | Depending on approach |
| Testing | 4-6 hours | Multi-server testing |
| **Total** | **18-27 hours** | ~3-4 days |

---

## Recommendation

### Short Term: Keep Trigger Files
The current trigger file system works and is simple. The main pain points (latency, no feedback) are manageable.

### Medium Term: Add REST API for Status
Add a minimal REST API to the Tray App for **status queries only**:
- `GET /api/status` - Is tray running?
- `GET /api/agent/status` - Is agent running?

This provides immediate feedback in Dashboard without changing action triggers.

### Long Term: Full REST API with Fallback
Once the minimal API is stable, expand to include actions:
- `POST /api/agent/start|stop|restart|reinstall`
- Keep trigger files as fallback for offline servers

---

## Conclusion

Implementing a REST API on the Tray App is **feasible and would improve user experience** with:
- Immediate feedback
- Real-time status
- Better error handling

However, it adds complexity:
- Additional firewall port
- Admin rights or URL ACL configuration
- Authentication requirements

**The hybrid approach is recommended**: Use REST API for real-time control of online servers while keeping trigger files for broadcast actions and offline server queuing.
