# RAG MCP Answers: SQL30082N, DB2 Security, and COBCH0779

**Generated:** 2025-02-28  
**Purpose:** Answer three questions using the custom RAG MCP servers (**user-db2-docs**, **user-visual-cobol-docs**) and workspace docs.

---

## RAG MCP access: Yes

Both custom RAG MCP servers were **reachable** and returned results:

- **user-db2-docs** — `query_docs` over Db2 12.1 LUW manuals (e.g. `db2_sec_guide_1213.md`, `db2_msgs_vol2_1213.md`).
- **user-visual-cobol-docs** — `query_docs` over Visual COBOL Messages Reference 11 (e.g. `COBCH0761 - COBCH0780.md`).

Answers below cite RAG source files where used; workspace docs are cited for reason code 36 wording and troubleshooting details that the RAG did not return verbatim.

---

## 1. What does SQL30082N reason code 36 mean?

**SQL30082N** is the DB2 message for **“Security processing failed.”**

From the **Db2 Database Security Guide** (via **user-db2-docs**, source: `db2_sec_guide_1213.md`):

- **SQLCODE -30082** is returned for **all connection-related plug-in errors** (security plug-in problem determination).
- Security plug-in issues are reported via SQL errors and the administration notification log; for connection-related plug-in errors you get SQL30082N.

From **workspace docs** (`SQL30082N-Reason36-Troubleshooting.md`, `FAQ-SQL30082N-Security-COBCH0779.md`), which align with the Db2 Message Reference and IBM Support:

- **Reason code 36** means **“UNEXPECTED CLIENT ERROR”** — a client-side security/plugin failure during connection.
- **Where it happens:** On the **client** (the machine where the application connecting to DB2 runs), during security/authentication handling.
- **SQLSTATE:** Typically **08001** (connection/communication exception).

So the failure is in the **client** environment (plugin, config, or OS/network rights), not necessarily a server rejection.

### What to check first (reason 36)

1. **Client `db2diag.log`**  
   On the client: e.g. `%DB2PATH%\db2dump\db2diag.log`. Search for `SQL30082`, `security`, `plugin`, `36`, and any stack/exception text around the time of the failed connect.

2. **Client security plugin and auth method**  
   Client plugins: e.g. `%DB2PATH%\security\plugin\<instance>\client` (Windows). Align auth settings: `db2 get dbm cfg` on client and server (e.g. SERVER, SERVER_ENCRYPT, KERBEROS).

3. **User ID and password**  
   Ensure correct user/password, DB2 naming rules, and no encoding/special-character issues.

4. **Windows**  
   User may need **“Access this computer from the network”** (Local Security Policy → User Rights Assignment).

5. **DB2 instance service account (server-side)**  
   If using Kerberos or auth failures in general, verify DB2 instance services are **not** running as `LocalSystem` (see `.cursor/rules/db2-sql30082n-troubleshooting.mdc`).

---

## 2. How do I fix “DB2 security processing failed”?

“Security processing failed” is the generic **SQL30082N** message. The **reason code** (e.g. 15, 19, 24, 36) tells you where to focus.

| Reason | Meaning | Focus |
|--------|--------|--------|
| **15** | Security processing at the **server** failed | Server config, plugins, server `db2diag.log` |
| **19** | USERID DISABLED or RESTRICTED | User/account status (OS or DB2) |
| **24** | USERNAME AND/OR PASSWORD INVALID | Credentials, LDAP/password policy |
| **36** | UNEXPECTED **CLIENT** ERROR | Client plugin, client config, client `db2diag.log` |

From the **Db2 Security Guide** (RAG: `db2_sec_guide_1213.md`): SQL30082 is returned for connection-related plug-in errors; use administration notification logs (UNIX: `sqllib/db2dump/*instance*.*N*.nfy`; Windows: Event Viewer) for debugging.

### General fix approach

1. **Identify the reason code** in the full SQL30082N text (e.g. “reason 36”).
2. **User ID and naming:** Ensure the user ID follows DB2 naming rules and is not disabled/restricted (reason 19/24).
3. **Authentication method:** Align client and server (e.g. SERVER, SERVER_ENCRYPT, KERBEROS). Misconfigured or missing client plugin often shows as reason 36.
4. **Logs:** Reason 36 → **client** `db2diag.log` first; Reason 15 → **server** `db2diag.log` and admin/notification logs.
5. **LDAP:** If using LDAP, verify LDAP configuration and that the user/password are valid in LDAP.
6. **Windows:** Ensure the account has **“Access this computer from the network”** if required; ensure DB2 instance services run under the correct domain account, not `LocalSystem`.

---

## 3. Explain COBCH0779 (Visual COBOL)

**COBCH0779** is a **Micro Focus / Rocket Visual COBOL** compiler message.

From the **Visual COBOL Messages Reference 11** (via **user-visual-cobol-docs**):

- RAG returned **`COBCH0761 - COBCH0780.md`** — “Lists the Syntax Checking error messages from COBCH0761 through COBCH0780.”
- So **COBCH0779** is in the **syntax checking** range (COBCH0761–COBCH0780), i.e. a **compile-time** message.

Interpretation:

- **COBCH** = COBOL Compiler message prefix.
- **0779** = Message number in the 700–799 range (syntax checking / compile-time in Micro Focus documentation).

The **exact** text for COBCH0779 is version-specific. To get the precise wording and action:

1. **Product documentation** — Error Messages or Compiler messages manual for your exact product and version (Visual COBOL for Visual Studio / for Eclipse, or COBOL Server), **07xx** or **0779** entry.
2. **Version-specific docs** — Use the doc set that matches your installed build.
3. **Support** — If unclear, use your support channel with full message text and a minimal repro (source line, directives, product version).

In practice: treat COBCH0779 as a **compile-time (syntax/configuration) message** and resolve it by correcting the reported source line or compiler/configuration setup as indicated in your version’s error message reference.

---

## RAG MCP access summary

| Item | Status |
|------|--------|
| **user-db2-docs** | ✅ Reachable. `query_docs` used for SQL30082N, security plug-ins, connection-related errors. |
| **user-visual-cobol-docs** | ✅ Reachable. `query_docs` used for COBCH0779; confirmed in COBCH0761–COBCH0780 (syntax checking). |
| **RAG sources cited** | `db2_sec_guide_1213.md`, `db2_msgs_vol2_1213.md` (Db2-LUW-Version-121-English-Manuals); `COBCH0761 - COBCH0780.md` (Visual COBOL Messages Reference 11). |
| **Workspace docs used** | `FAQ-SQL30082N-Security-COBCH0779.md`, `SQL30082N-Reason36-Troubleshooting.md`, `.cursor/rules/db2-sql30082n-troubleshooting.mdc` (reason code 36 wording and checklist). |

**Conclusion:** The custom RAG MCPs are accessible and were used to answer the three questions; workspace docs supplemented where the RAG did not return the exact reason-code-36 text or full troubleshooting steps.
