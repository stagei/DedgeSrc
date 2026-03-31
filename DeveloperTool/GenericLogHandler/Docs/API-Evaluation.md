# Generic Log Handler – REST API Evaluation

## Test Results

All listed endpoints were tested (Development, HTTP, anonymous allowed). **13/13 passed.**

| Endpoint | Method | Purpose | Test |
|----------|--------|---------|------|
| `/health` | GET | Infrastructure health (DB connectivity) | 200 |
| `/openapi/v1.json` | GET | OpenAPI spec | 200 |
| `/api/logs/search` | GET | Search logs (query params: dates, levels, computer, user, message, etc.) | 200 |
| `/api/logs/{id}` | GET | Get single log by ID | 404 for missing ID (correct) |
| `/api/logs/statistics` | GET | Stats for date range (totals, errors, warnings, unique computers/users) | 200 |
| `/api/logs/level-counts` | GET | Count per level in date range | 200 |
| `/api/logs/top-computers` | GET | Top N computers by log count | 200 |
| `/api/logs/recent-errors` | GET | Recent ERROR/FATAL entries | 200 |
| `/api/logs/export/csv` | POST | Export search results as CSV (body: `LogSearchRequest`) | 200 |
| `/api/logs/export/excel` | POST | Export search results as XLSX (body: `LogSearchRequest`) | 200 |
| `/api/dashboard/summary` | GET | Dashboard: today stats, hourly trends, top computers, top errors | 200 |
| `/api/dashboard/health` | GET | App-level health (recent activity, errors) | 200 |
| `/api/dashboard/trends` | GET | Log volume trends by hour | 200 |

Run tests: `.\scripts\Test-WebApi.ps1` (start WebApi first; use HTTP in Development).

---

## Do We Have All the APIs We Need?

### Covered well

- **Search** – Full criteria (dates, levels, computer, user, message, exception, regex, source, sort, pagination). Sufficient for log-search UI and ad‑hoc queries.
- **Single log** – Get by ID for detail view.
- **Aggregations** – Statistics, level counts, top computers, recent errors. Enough for dashboard and summaries.
- **Export** – CSV and Excel from the same search model. Good for offline analysis.
- **Dashboard** – Summary, health, trends. Good for a single overview page.
- **Health** – `/health` with DB check for load balancers and monitoring.

### Optional / future improvements

| Need | Suggestion | Priority |
|------|------------|----------|
| **Filter dropdowns** | `GET /api/logs/source-types` and/or `GET /api/logs/computers` returning distinct values (e.g. last 7 days) so UIs can build filter lists without scanning all data. | Low – can derive from search + stats today. |
| **Import / job status** | `GET /api/import/status` (and optionally `GET /api/import/sources`) from `import_status` (and config) so operators can see last run, record counts, errors per source. | Medium – useful for ops. |
| **Retention / cleanup** | `GET /api/admin/retention` (config or summary) and optionally `POST /api/admin/retention/run-now` to trigger cleanup. | Low – retention is in Import Service today. |
| **Bulk delete (admin)** | `DELETE /api/logs?from=...&to=...` or by criteria for manual purge. | Low – overlap with retention. |
| **Full-text / regex** | Search already supports `MessageText`, `RegexPattern`, and `ConcatenatedSearchString`. If you add Postgres full-text (e.g. GIN), you could expose a dedicated `GET /api/logs/fulltext?q=...` later. | Optional. |

### Conclusion

- **For the current UI (dashboard + log search + export) and for monitoring (health, trends, recent errors), the existing APIs are sufficient.**
- The only clearly missing piece for a “complete” ops story is **import/job status** (read-only status of sources and last run). The rest are nice-to-haves.

---

## Implementation notes

- **Auth**: Production uses Windows (Negotiate); Development allows anonymous over HTTP for `Test-WebApi.ps1`.
- **Health**: `/health` uses `AddDbContextCheck<LoggingDbContext>` so it reflects real DB connectivity.
- **Response shape**: All JSON APIs use `ApiResponse<T>` with `Success`, `Data`, `Error`, `Timestamp`; PascalCase is preserved.
