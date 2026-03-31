# FAQ: SQL30082N, DB2 Security Processing Failed, and COBCH0779

**Purpose:** Quick reference for three common questions: SQL30082N reason code 36, fixing “DB2 security processing failed,” and the Visual COBOL message COBCH0779.

---

## 1. What does SQL30082N reason code 36 mean?

**SQL30082N** is the DB2 message for **“Security processing failed.”**  
**Reason code 36** means **“UNEXPECTED CLIENT ERROR”** (sometimes also referred to as a client security plugin error).

- **Where it happens:** The failure occurs on the **client** (the machine where the application connecting to DB2 runs), during security/authentication handling, before or during the connection handshake.
- **SQLSTATE:** Usually **08001** (connection/communication exception).

So the problem is in the **client** environment (plugin, config, or OS/network rights), not necessarily that the server rejected the user.

### What to check first (reason 36)

1. **Client `db2diag.log`**  
   On the client: e.g. `%DB2PATH%\db2dump\db2diag.log`. Search for `SQL30082`, `security`, `plugin`, `36`, and any stack/exception text around the time of the failed connect.

2. **Client security plugin and auth method**  
   - Client plugins: e.g. `%DB2PATH%\security\plugin\<instance>\client` (Windows).  
   - Compare auth settings: `db2 get dbm cfg` on client and server (e.g. SERVER, SERVER_ENCRYPT, KERBEROS). Client and server must be compatible.

3. **User ID and password**  
   Even for a “client” error, ensure user/password are correct, user ID follows DB2 naming rules, and there are no encoding/special-character issues.

4. **Windows**  
   User may need **“Access this computer from the network”** (Local Security Policy → User Rights Assignment).

5. **DB2 instance service account (Kerberos / server-side)**  
   If you use Kerberos or see auth failures in general, verify the DB2 instance services are **not** running as `LocalSystem`. They should run under the domain account that owns the SPN (e.g. `DOMAIN\serviceaccount`). Check with:
   ```powershell
   Get-CimInstance Win32_Service | Where-Object { $_.Name -match '^DB2' } |
       Select-Object Name, DisplayName, StartName, State | Format-Table -AutoSize
   ```

---

## 2. How do I fix “DB2 security processing failed”?

“Security processing failed” is the generic **SQL30082N** message. The **reason code** (e.g. 15, 19, 24, 36) tells you where to focus.

| Reason | Meaning | Focus |
|--------|--------|--------|
| **15** | Security processing at the **server** failed | Server config, plugins, server `db2diag.log` |
| **19** | USERID DISABLED or RESTRICTED | User/account status (OS or DB2) |
| **24** | USERNAME AND/OR PASSWORD INVALID | Credentials, LDAP/password policy |
| **36** | UNEXPECTED **CLIENT** ERROR | Client plugin, client config, client `db2diag.log` |

### General fix approach

1. **Identify the reason code** in the full SQL30082N text (e.g. “reason 36”).
2. **User ID and naming:** Ensure the user ID follows DB2 naming rules and is not disabled/restricted (reason 19/24).
3. **Authentication method:** Align client and server (e.g. SERVER, SERVER_ENCRYPT, KERBEROS). Misconfigured or missing client plugin often shows as reason 36.
4. **Logs:**  
   - Reason 36 → **client** `db2diag.log` first.  
   - Reason 15 → **server** `db2diag.log` and admin/notification logs.
5. **LDAP:** If using LDAP, verify LDAP configuration and that the user/password are valid in LDAP.
6. **File permissions (Unix/Linux):** Check permissions in `~/sqllib/security/` (e.g. `db2ckpw`, `db2chpw`) if you see related errors (e.g. SQL1639N).
7. **Password encryption (older DB2):** On releases before 9.5 FP4 with local auth, confirm password encryption algorithm compatibility (e.g. Crypt, MD5, SHA1, SHA256, SHA512).
8. **Windows:** Ensure the account has **“Access this computer from the network”** if required.
9. **Kerberos/Windows service:** Ensure DB2 instance services run under the correct domain account, not `LocalSystem` (see section 1).

IBM recommends using the appropriate **authentication testing utility** (per platform) to isolate whether the issue is outside DB2 (e.g. OS/network policy).

---

## 3. Explain COBCH0779 (Visual COBOL)

**COBCH0779** is a **Micro Focus / Rocket Visual COBOL** compiler message.

- **COBCH** = COBOL Compiler message prefix (compiler-host or compiler run).
- **0779** = Message number in the 700–799 range, which in Micro Focus documentation is typically associated with **syntax checking / compile-time** messages (as opposed to runtime or I/O messages).

Public Micro Focus documentation often documents error ranges such as COBCH1741–COBCH1760; the **exact text for COBCH0779** is not in the searchable public docs used for this FAQ. To get the precise wording and recommended action:

1. **Product documentation**  
   Check the **Error Messages** or **Compiler messages** manual for your exact product and version (e.g. Visual COBOL for Visual Studio / for Eclipse, or COBOL Server), looking for the **07xx** or **0779** entry.

2. **Version-specific docs**  
   Micro Focus / Rocket docs are version-specific; use the doc set that matches your installed build.

3. **Support**  
   If the message text or cause is unclear, use your support channel (e.g. Rocket Software support, or Micro Focus support if still under contract) with the full message text and a minimal repro (source line, directives, and product version).

In practice: treat COBCH0779 as a **compile-time (syntax/configuration) message** and resolve it by correcting the reported source line or compiler/configuration setup as indicated in your version’s error message reference.

---

## References

- **SQL30082N (reason 36):** Db2 Message Reference (e.g. 12.1), Database Security Guide; IBM Support: “Error SQL30082N Reason Code 15, 19, 24, or 36.”
- **Workspace:** `DevTools/DatabaseTools/SQL30082N-Reason36-Troubleshooting.md`, `.cursor/rules/db2-sql30082n-troubleshooting.mdc`.
- **COBCH:** Micro Focus / Rocket Visual COBOL documentation (Error Messages, version-specific); `DevTools/LegacyCodeTools/VisualCobol/AnalysisResult-VisualCobolToolset.md`.
