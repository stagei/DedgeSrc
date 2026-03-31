# Website Response Codes Reference

HTTP status codes and IIS sub-status codes that can be returned from a website.  
Source: [HTTP status codes in IIS](https://learn.microsoft.com/en-us/troubleshoot/developer/webapps/iis/www-administration-management/http-status-code) (Microsoft Learn), plus ASP.NET Core ANCM codes.

---

## 1xx — Informational

| Code | Description |
|------|-------------|
| 100 | Continue — Initial part of request received; server will send final response after request is fully received. |
| 101 | Switching Protocols — Server agrees to switch application protocol. |

---

## 2xx — Successful

| Code | Description |
|------|-------------|
| 200 | OK — Request was successfully processed. |
| 201 | Created — Request fulfilled; one or more new resources created. |
| 202 | Accepted — Request accepted for processing; processing not yet complete. |
| 203 | Non-Authoritative Information — Request successful; content modified from origin. |
| 204 | No Content — Request fulfilled; no additional content to send. |
| 205 | Reset Content — Request fulfilled; client should reset document view. |
| 206 | Partial Content — Range request fulfilled; one or more parts transferred. |

---

## 3xx — Redirection

| Code | Description |
|------|-------------|
| 301 | Moved Permanently — Resource has a new permanent URI. |
| 302 | Found (Object Moved) — Resource temporarily under a different URI. |
| 304 | Not Modified — Conditional GET/HEAD; condition evaluated to false (use cached copy). |
| 307 | Temporary Redirect — Client should repeat request with same method to new URI. |

---

## 4xx — Client Error

### Standard 4xx

| Code | Description |
|------|-------------|
| 400 | Bad Request — Request malformed or invalid; client should not repeat without changes. |
| 401 | Access Denied — Lacks valid authentication credentials. |
| 403 | Forbidden — Server understood request but refuses to fulfill it. |
| 404 | Not Found — No current representation for target resource (or server won't disclose). |
| 405 | Method Not Allowed — Method known but not supported for target resource. |
| 406 | Not Acceptable — Client doesn't accept MIME type of requested resource. |
| 408 | Request Timed Out — Server did not receive complete request in time. |
| 412 | Precondition Failed — Request header precondition evaluated to false. |
| 413 | Request Entity Too Large — Request payload too large. |

### 400 sub-status (Bad Request)

| Code | Description |
|------|-------------|
| 400.1 | Invalid Destination Header |
| 400.2 | Invalid Depth Header |
| 400.3 | Invalid If Header |
| 400.4 | Invalid Overwrite Header |
| 400.5 | Invalid Translate Header |
| 400.6 | Invalid Request Body |
| 400.7 | Invalid Content Length |
| 400.8 | Invalid Timeout |
| 400.9 | Invalid Lock Token |
| 400.10 | Invalid X-Forwarded-For (XFF) header |
| 400.11 | Invalid WebSocket request |
| 400.601 | Bad client request (ARR) |
| 400.602 | Invalid time format (ARR) |
| 400.603 | Parse range error (ARR) |
| 400.604 | Client gone (ARR) |
| 400.605 | Maximum number of forwards (ARR) |
| 400.606 | Asynchronous competition error (ARR) |

### 401 sub-status (Access Denied)

| Code | Description |
|------|-------------|
| 401.1 | Logon failed — Invalid user name or password. |
| 401.2 | Logon failed due to server configuration |
| 401.3 | Unauthorized due to ACL on resource — NTFS/permission issue. |
| 401.4 | Authorization failed by filter (ISAPI) |
| 401.5 | Authorization failed by ISAPI/CGI application |
| 401.501 | Access denied: concurrent request rate limit reached (Dynamic IP Restriction) |
| 401.502 | Access denied: maximum request rate limit reached |
| 401.503 | Access denied: IP address denied |
| 401.504 | Access denied: host name denied |

### 403 sub-status (Forbidden)

| Code | Description |
|------|-------------|
| 403.1 | Execute access forbidden |
| 403.2 | Read access forbidden |
| 403.3 | Write access forbidden |
| 403.4 | SSL required |
| 403.5 | SSL 128 required |
| 403.6 | IP address rejected |
| 403.7 | Client certificate required |
| 403.8 | Site access denied (DNS name) |
| 403.9 | Too many clients (concurrent connections exceeded) |
| 403.10 | Execute access denied |
| 403.11 | Password changed |
| 403.12 | Mapper denied access (client cert user denied) |
| 403.13 | Client certificate revoked |
| 403.14 | Directory listing denied |
| 403.15 | Client access licenses exceeded |
| 403.16 | Client certificate untrusted or invalid |
| 403.17 | Client certificate expired or not yet valid |
| 403.18 | Cannot execute requested URL in current application pool |
| 403.19 | Cannot execute CGI in this application pool |
| 403.20 | Passport logon failed |
| 403.21 | Source access denied (WebDAV) |
| 403.22 | Infinite depth denied (WebDAV) |
| 403.501 | Forbidden: concurrent request rate limit reached |
| 403.502 | Forbidden: maximum request rate limit reached |
| 403.503 | Forbidden: IP address denied |
| 403.504 | Forbidden: host name denied |

### 404 sub-status (Not Found)

| Code | Description |
|------|-------------|
| 404.0 | Not found — File moved or does not exist. |
| 404.1 | Site Not Found |
| 404.2 | ISAPI or CGI restriction |
| 404.3 | MIME type restriction |
| 404.4 | No handler configured for file extension |
| 404.5 | Denied by request filtering configuration |
| 404.6 | Verb denied |
| 404.7 | File extension denied |
| 404.8 | Hidden namespace |
| 404.9 | File attribute hidden |
| 404.10 | Request header too long |
| 404.11 | Double escape sequence in request |
| 404.12 | High-bit characters not allowed |
| 404.13 | Content length too large |
| 404.14 | Request URL too long |
| 404.15 | Query string too long |
| 404.16 | WebDAV request sent to static file handler |
| 404.17 | Dynamic content mapped to static file handler |
| 404.18 | Query string sequence denied |
| 404.19 | Denied by filtering rule |
| 404.20 | Too many URL segments |
| 404.501 | Not found: concurrent request rate limit reached |
| 404.502 | Not found: maximum request rate limit reached |
| 404.503 | Not found: IP address denied |
| 404.504 | Not found: host name denied |

### Other 4xx sub-status

| Code | Description |
|------|-------------|
| 405.0 | Method not allowed |
| 406.0 | Not acceptable (invalid Accept MIME) |
| 408.0 | Request timed out |
| 412.0 | Precondition failed (invalid If-Match) |
| 413.0 | Request entity too large |

---

## 5xx — Server Error

### Standard 5xx

| Code | Description |
|------|-------------|
| 500 | Internal Server Error — Unexpected condition prevented fulfilling request. |
| 501 | Not Implemented — Server does not support required functionality. |
| 502 | Bad Gateway — Invalid response from upstream server (gateway/proxy). |
| 503 | Service Unavailable — Temporary overload or maintenance. |

### 500 sub-status (Internal Server Error)

| Code | Description |
|------|-------------|
| 500.0 | Module or ISAPI error occurred |
| 500.11 | Application is shutting down |
| 500.12 | Application is busy restarting |
| 500.13 | Web server is too busy |
| 500.15 | Direct requests for Global.asax not allowed |
| 500.19 | Configuration data invalid (ApplicationHost.config / Web.config) |
| 500.21 | Module not recognized |
| 500.22 | ASP.NET httpModules config does not apply in Managed Pipeline mode |
| 500.23 | ASP.NET httpHandlers config does not apply in Managed Pipeline mode |
| 500.24 | ASP.NET impersonation config does not apply in Managed Pipeline mode |
| 500.30 | **ANCM In-Process Start Failure** — ASP.NET Core app failed to start (runtime, hosting, startup exception) |
| 500.31 | **ANCM Failed to Find Native Dependencies** — Failed to load application (missing native deps) |
| 500.32 | **ANCM In-Process Start Failure (host policy)** |
| 500.33 | **ANCM In-Process Start Failure (dependent assembly)** |
| 500.34 | **ANCM Mixed Hosting Models Not Supported** — In-process and out-of-process cannot run in same app pool |
| 500.35 | **ANCM In-Process Start Failure (multiple startup assemblies)** |
| 500.50 | Rewrite error during RQ_BEGIN_REQUEST (inbound/config) |
| 500.51 | Rewrite error during GL_PRE_BEGIN_REQUEST (global rules) |
| 500.52 | Rewrite error during RQ_SEND_RESPONSE (outbound rule) |
| 500.53 | Rewrite error during RQ_RELEASE_REQUEST_STATE (outbound before cache) |
| 500.100 | Internal ASP error |

### 502 sub-status (Bad Gateway)

| Code | Description |
|------|-------------|
| 502.1 | CGI application timeout |
| 502.2 | Premature exit / Map request failure (ARR) |
| 502.3 | Forwarder connection error / WinHTTP async completion failure (ARR) |
| 502.4 | No server (ARR) |
| 502.5 | WebSocket failure (ARR) |
| 502.6 | Forwarded request failure (ARR) |
| 502.7 | Execute request failure (ARR) |

### 503 sub-status (Service Unavailable)

| Code | Description |
|------|-------------|
| 503.0 | Application pool unavailable (stopped or disabled) |
| 503.2 | Concurrent request limit exceeded |
| 503.3 | ASP.NET queue full |
| 503.4 | FastCGI queue full |

---

## Quick lookup (common codes)

| Code | Meaning |
|------|--------|
| 200 | OK |
| 301 | Moved permanently |
| 302 | Redirect |
| 304 | Not modified (use cache) |
| 400 | Bad request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not found |
| 405 | Method not allowed |
| 500 | Internal server error |
| 500.19 | Invalid Web.config / ApplicationHost.config |
| 500.30 | ASP.NET Core app failed to start (ANCM) |
| 500.34 | Mixed in-process/out-of-process in same app pool (ANCM) |
| 502 | Bad gateway |
| 503 | Service unavailable |

---

## Log file location

IIS records the HTTP status code (and sub-status when present) in the site log. Default folder: `inetpub\logs\LogFiles` (per-site subfolders; files named e.g. `exYYMMDD.log`).
