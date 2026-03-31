# Log Ingest API

The Generic Log Handler exposes an anonymous HTTP API that any program can use to submit log entries without prior registration. Entries are queued in the database and processed by the ImportService on its next cycle (typically within seconds).

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/Logs/ingest` | Anonymous | Submit a single log entry |
| `POST` | `/api/Logs/ingest/batch` | Anonymous | Submit multiple log entries |

Both endpoints return `202 Accepted` immediately — the caller does not wait for processing.

## Base URL

| Environment | Base URL |
|-------------|----------|
| IIS (test server) | `http://dedge-server/GenericLogHandler` |
| Local dev | `http://localhost:52421` |

Full endpoint example: `http://dedge-server/GenericLogHandler/api/Logs/ingest`

## Request Format

Content-Type: `application/json`

### Single entry (`/api/Logs/ingest`)

```json
{
  "message": "Order 12345 processed successfully",
  "level": "INFO",
  "source": "OrderService",
  "timestamp": "2026-02-18T14:30:00Z",
  "computerName": "PROD-APP-01",
  "userName": "SVC_ORDER",
  "jobName": "ProcessOrders",
  "jobStatus": "Completed",
  "functionName": "ProcessBatch",
  "location": "OrderService.dll"
}
```

### Batch (`/api/Logs/ingest/batch`)

```json
[
  { "message": "Job started", "level": "INFO", "source": "MyApp", "jobName": "Nightly", "jobStatus": "Started" },
  { "message": "Processing 500 records", "level": "INFO", "source": "MyApp", "jobName": "Nightly" },
  { "message": "Job completed", "level": "INFO", "source": "MyApp", "jobName": "Nightly", "jobStatus": "Completed" }
]
```

## Field Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `message` | string | **Yes** | — | The log message text |
| `level` | string | No | `INFO` | Log level: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL` |
| `source` | string | No | `ingest-api` | Identifying name for the calling system |
| `timestamp` | ISO 8601 | No | Current UTC time | When the event occurred |
| `computerName` | string | No | Server hostname | Machine where the event originated |
| `userName` | string | No | *(empty)* | User or service account name |
| `jobName` | string | No | *(null)* | Name of the job or batch process |
| `jobStatus` | string | No | *(null)* | `Started`, `Completed`, `Failed`, `Running` |
| `errorId` | string | No | *(null)* | Unique error identifier |
| `exceptionType` | string | No | *(null)* | Exception class name |
| `stackTrace` | string | No | *(null)* | Full stack trace for errors |
| `functionName` | string | No | *(empty)* | Function or method name |
| `location` | string | No | *(empty)* | Script path, DLL, or module location |

## Response Format

### Success (202 Accepted)

```json
{
  "success": true,
  "data": { "queued": 1 },
  "error": null
}
```

For batch, `queued` reflects the number of entries accepted.

### Error (400 / 500)

```json
{
  "success": false,
  "data": null,
  "error": "Error description"
}
```

## Processing Flow

```
Caller  ─POST─►  WebApi  ─INSERT─►  ingest_queue (PostgreSQL)
                   │                       │
                   ▼                       │
              202 Accepted            ImportService
              (immediate)          (next cycle, FIFO)
                                       │
                                       ▼
                                  log_entries table
                                  (queue row deleted)
```

1. The WebApi serializes the request to JSON and inserts a row into `ingest_queue`.
2. The caller receives `202 Accepted` immediately.
3. The ImportService drains the queue at the start of each import cycle (every few seconds).
4. Each queue entry is deserialized, mapped to a `LogEntry`, saved to `log_entries`, and deleted from the queue.
5. Malformed entries are logged and discarded to avoid blocking.

## Minimal Example

The only required field is `message`. This is the simplest possible call:

```json
{ "message": "Something happened" }
```

Defaults applied: level=INFO, source=ingest-api, timestamp=now, computerName=server hostname.

## Sample Code

Ready-to-use samples for each language are in the `Samples/` subfolder:

| Language | File | Description |
|----------|------|-------------|
| PowerShell | [`Send-LogEntry.ps1`](Samples/Send-LogEntry.ps1) | Full-featured with retry, batch support, and error handling |
| Batch/CMD | [`send-log.bat`](Samples/send-log.bat) | Uses `curl` for environments without PowerShell |
| C# | [`LogIngestClient.cs`](Samples/LogIngestClient.cs) | Async helper class with `HttpClient` |
| COBOL | [`LOGINGEST.CBL`](Samples/LOGINGEST.CBL) | HTTP POST via system CALL to curl |
| REXX | [`LOGINGEST.REX`](Samples/LOGINGEST.REX) | HTTP POST using `RxSock` or `curl` fallback |

## Best Practices

1. **Use batch for high-volume logging** — buffer entries and send in groups of 50–200 to reduce HTTP overhead.
2. **Always include `source`** — makes it easy to find your entries in the dashboard and log search.
3. **Set `level` correctly** — ERROR and FATAL entries trigger the alert system.
4. **Use ISO 8601 timestamps with timezone** — e.g. `2026-02-18T14:30:00Z` or `2026-02-18T15:30:00+01:00`.
5. **Fire and forget** — the endpoint returns 202 immediately; don't wait or retry unless the HTTP call itself fails.
6. **Include `jobName` and `jobStatus`** for batch processes — the Job Status dashboard tracks these automatically.
