# SQL30082N Reason Code 36 – UNEXPECTED CLIENT ERROR

## What the error means

From the **Db2 12.1 Message Reference** and **IBM Support** (Error SQL30082N Reason Code 15, 19, 24, or 36):

- **SQL30082N** – Security processing failed.
- **Reason code 36** – **"UNEXPECTED CLIENT ERROR"**  
  The failure occurs on the **client** during security/authentication handling, before or during the connection handshake.
- **SQLSTATE 08001** – Connection/communication exception.

So the problem is in the **client** environment (the machine where you run the app that connects to BASISKAT), not necessarily that the server rejected you.

---

## What to do (in order)

### 1. Check the **client** `db2diag.log`

From the **Database Security Guide**: for connection/security errors, you must look at the right side:

- If the **client** gets this error → inspect the diagnostic log **on the client**.
- If the **server** returns it to the client → inspect the log on the server.

Because reason 36 is “UNEXPECTED **CLIENT** ERROR”, start with the **client** log:

- **Windows**: e.g. `%DB2PATH%\db2dump\db2diag.log` (or the instance’s dump folder).
- Search for entries around the time of the failed connect, and for:
  - `SQL30082`
  - `security`
  - `plugin`
  - `36`
  - Any stack trace or “unexpected” / exception text.

The exact path depends on your DB2 instance and `DB2INSTPROF` / install path.

### 2. Confirm client security plugin and auth method

From the **Database Security Guide** (security plug-ins, client deployment):

- Client security plugins live under paths like:
  - **Windows**: `%DB2PATH%\security\plugin\<instance-name>\client`
- Ensure the **client** has the correct plugin for the server’s authentication (e.g. same auth type as server).
- Check **authentication** setting:
  - `db2 get dbm cfg` (on both client and server if possible) and compare **Authentication** (e.g. SERVER, SERVER_ENCRYPT, KERBEROS, etc.).
  - Client and server must be compatible (e.g. if server uses SERVER_ENCRYPT, client must support it and not be misconfigured).

Misconfigured or missing client plugin can surface as an “unexpected” client-side error (reason 36).

### 3. User ID and password

- **Security Guide** (e.g. SQL30082N reason 1 “PASSWORD EXPIRED”): many SQL30082N reason codes are auth-related.
- Even though 36 is “client error”, ensure:
  - User ID and password are correct for BASISKAT.
  - No special characters or encoding issues in the password (try a simple password once for testing).
  - User ID follows DB2 naming rules.

### 4. Windows-specific (your environment)

From IBM troubleshooting notes for SQL30082N-type errors on Windows:

- The Windows user (the one running the app) may need **“Access this computer from the network”**.
- Check: **Local Security Policy** (`secpol.msc`) → Local Policies → User Rights Assignment → “Access this computer from the network” – ensure the account (or group) is listed if required by your setup.

### 5. Other SQL30082N reason codes (for comparison)

Same IBM doc groups these; the same logs and config areas apply:

- **15** – Security processing at the server failed  
- **19** – USERID DISABLED or RESTRICTED  
- **24** – USERNAME AND/OR PASSWORD INVALID  
- **36** – UNEXPECTED CLIENT ERROR  

So if 36 persists, still re-check user status and password (19/24) and server-side logs (15) to rule out a wrong or disabled user that manifests as a client error.

### 6. Administration notification log (server side)

If you have server access:

- **Security Guide**: administration notification logs are useful for security/plugin issues.
- **Windows**: Event Viewer (e.g. Application or DB2 source).
- Look for events at the time of the failed connection; they may explain what the server saw and complement the client db2diag.log.

---

## Summary

| Item | Action |
|------|--------|
| **Error** | SQL30082N, reason 36 = “UNEXPECTED CLIENT ERROR” (client-side security processing). |
| **First step** | Open **client** `db2diag.log` and search for SQL30082, security, plugin, 36. |
| **Then** | Verify client security plugin path and authentication method vs server. |
| **Also** | Check user/password and, on Windows, “Access this computer from the network” if applicable. |

---

## References (Db2 LUW 12.1 manuals in this repo)

- **Db2 12.1.3 Message Reference, Vol. 2** – SQL30082N text (“Security processing failed with reason …”).
- **Db2 12.1.3 Database Security Guide** – Security processing, SQL30082N, security plug-ins (client deployment), db2diag and administration logs, authentication.
- **IBM Support**: “Error SQL30082N Reason Code 15, 19, 24, or 36” (troubleshooting steps; reason 36 explicitly: “UNEXPECTED CLIENT ERROR”).

Once you have a few lines from the **client** `db2diag.log` around the failed connect, you can use them to narrow down whether the cause is plugin load failure, auth method mismatch, or something else in the client stack.
