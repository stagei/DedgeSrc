# ServerMonitor Agent API - Improvement Recommendations

Based on the Dashboard implementation, here are recommended improvements to the Agent API to enhance monitoring capabilities.

---

## 1. Add `/api/CachedSnapshot` Endpoint

**Status**: 🔴 **MISSING**

The Dashboard expects a `/api/CachedSnapshot` endpoint that returns the last saved snapshot without generating new data. This is useful for:
- Reducing load on monitored servers
- Faster responses when real-time data isn't critical
- Fallback when live data collection is slow

**Recommended Implementation**:

```csharp
// SnapshotController.cs
[HttpGet("CachedSnapshot")]
[ProducesResponseType(typeof(SystemSnapshot), 200)]
[ProducesResponseType(404)]
public IActionResult GetCachedSnapshot()
{
    var cached = _globalSnapshot.GetCachedSnapshot();
    if (cached == null)
    {
        return NotFound(new { message = "No cached snapshot available" });
    }
    return Ok(cached);
}
```

---

## 2. Add `/api/snapshot/alerts/recent` Endpoint

**Status**: ✅ **IMPLEMENTED** (referenced in tray app)

Already available for the tray app. Ensure it's documented and supports pagination:

```http
GET /api/snapshot/alerts/recent?count=10
```

---

## 3. Add Server Info Endpoint

**Status**: 🟡 **ENHANCEMENT**

Add a lightweight endpoint for basic server info without full snapshot:

```http
GET /api/info
```

**Response**:
```json
{
  "serverName": "P-NO1FKMPRD-DB",
  "agentVersion": "1.0.3",
  "startTime": "2026-01-13T08:00:00Z",
  "uptime": "5:23:45",
  "lastSnapshotTime": "2026-01-13T12:00:00Z",
  "monitoringEnabled": true
}
```

**Benefits**:
- Dashboard can show agent version per server
- Verify which version is actually running (vs deployed)
- Check agent health without full snapshot overhead

---

## 4. Add Metrics Summary Endpoint

**Status**: 🟡 **ENHANCEMENT**

Lightweight endpoint for key metrics only (no processes, alerts, DB2):

```http
GET /api/metrics
```

**Response**:
```json
{
  "cpu": {
    "currentPercent": 45.2,
    "averagePercent": 42.1,
    "isSustainedHigh": false
  },
  "memory": {
    "usedPercent": 67.5,
    "usedGb": 10.8,
    "totalGb": 16.0,
    "isThresholdExceeded": false
  },
  "disk": {
    "drives": [
      { "letter": "C:", "usedPercent": 45.0, "freeGb": 275.0 },
      { "letter": "D:", "usedPercent": 12.0, "freeGb": 880.0 }
    ]
  },
  "uptime": {
    "days": 45.2,
    "formatted": "45d 5h 12m"
  },
  "timestamp": "2026-01-13T12:00:00Z"
}
```

**Benefits**:
- Much faster than full snapshot
- Ideal for dashboard polling
- Reduces network traffic

---

## 5. Add Bulk Status Endpoint

**Status**: 🟡 **ENHANCEMENT**

Instead of calling `/api/IsAlive` for each server, Dashboard could call one agent to check others:

```http
POST /api/status/check
Content-Type: application/json

{
  "servers": ["P-NO1FKMPRD-APP", "P-NO1FKMPRD-WEB", "T-NO1FKXTST-DB"],
  "port": 8999
}
```

**Response**:
```json
{
  "results": [
    { "server": "P-NO1FKMPRD-APP", "isAlive": true, "responseMs": 45 },
    { "server": "P-NO1FKMPRD-WEB", "isAlive": true, "responseMs": 32 },
    { "server": "T-NO1FKXTST-DB", "isAlive": false, "error": "Connection refused" }
  ],
  "checkedAt": "2026-01-13T12:00:00Z"
}
```

**Benefits**:
- Single call from Dashboard instead of 44 parallel calls
- Agent has network proximity to other servers
- Reduces Dashboard complexity

---

## 6. Add Alert Acknowledgment

**Status**: 🟡 **ENHANCEMENT**

Allow acknowledging alerts from the Dashboard:

```http
POST /api/alerts/{id}/acknowledge
Content-Type: application/json

{
  "acknowledgedBy": "admin",
  "notes": "Known issue, scheduled for maintenance"
}
```

**Benefits**:
- Suppress repeated notifications
- Track who responded to alerts
- Clear dashboard clutter

---

## 7. Standardize Response Format

**Status**: 🟡 **ENHANCEMENT**

Ensure all endpoints return consistent wrapper:

```json
{
  "success": true,
  "data": { ... },
  "metadata": {
    "serverName": "P-NO1FKMPRD-DB",
    "timestamp": "2026-01-13T12:00:00Z",
    "agentVersion": "1.0.3"
  },
  "error": null
}
```

**Benefits**:
- Easier error handling in Dashboard
- Consistent parsing logic
- Version tracking per response

---

## Implementation Priority

| Priority | Enhancement | Effort | Impact |
|----------|-------------|--------|--------|
| 🔴 High | `/api/CachedSnapshot` | Low | Dashboard cached mode |
| 🟡 Medium | `/api/info` | Low | Agent version display |
| 🟡 Medium | `/api/metrics` | Medium | Faster polling |
| 🟢 Low | Bulk status check | Medium | Network optimization |
| 🟢 Low | Alert acknowledgment | Medium | UX improvement |
| 🟢 Low | Response wrapper | High | Breaking change |

---

## Breaking Changes Warning

If implementing response wrapper (#7), consider:
1. Version the API (`/api/v2/snapshot`)
2. Accept header for format selection
3. Gradual migration with compatibility layer

---

## Conclusion

The most impactful immediate improvements are:
1. **`/api/CachedSnapshot`** - Enables Dashboard cached mode
2. **`/api/info`** - Shows running agent version in Dashboard

These are low-effort, high-value additions that enhance the Dashboard without breaking existing functionality.
