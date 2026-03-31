# DB2 KRB_SERVER_ENCRYPT Configuration Guide

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-02  
**Technology:** DB2 LUW 12.1  

---

## Overview

This document describes the configuration needed on both the **DB2 server** and **client** side to enable `KRB_SERVER_ENCRYPT` authentication. This mode allows the server to accept both Kerberos SSO connections (from Windows domain clients) and encrypted username/password connections (from JDBC, non-Windows clients, or tools like DBeaver).

**Example database used throughout:** `INLTST` on server `t-no1inltst-db`, with client-side catalog alias `FKKTOTST` on port `3718`.

---

## Server-Side Configuration

### DBM Configuration Parameters

Three parameters must be set on the DB2 instance. All require a `db2stop`/`db2start` cycle to take effect.

| Parameter | Value | Purpose |
|---|---|---|
| `AUTHENTICATION` | `KRB_SERVER_ENCRYPT` | Sets the instance-level authentication. Allows both Kerberos and encrypted password. |
| `SRVCON_AUTH` | `KRB_SERVER_ENCRYPT` | **Overrides `AUTHENTICATION` for incoming remote (TCP/IP) connections.** If this is set to `KERBEROS` while `AUTHENTICATION` is `KRB_SERVER_ENCRYPT`, remote JDBC clients will still be rejected. |
| `ALTERNATE_AUTH_ENC` | `AES_ONLY` | Encryption algorithm for the password exchange with JDBC JCC Type 4 drivers. Required for modern JCC drivers (11.5+). |

**Commands to apply:**

```bat
set DB2INSTANCE=DB2
db2 update dbm cfg using AUTHENTICATION KRB_SERVER_ENCRYPT
db2 update dbm cfg using SRVCON_AUTH KRB_SERVER_ENCRYPT
db2 update dbm cfg using ALTERNATE_AUTH_ENC AES_ONLY
db2stop force
db2start
```

**Verify:**

```bat
db2 get dbm cfg | findstr /i "AUTHENTICATION SRVCON_AUTH ALTERNATE_AUTH_ENC"
```

Expected output:

```
 Server connection authentication     (SRVCON_AUTH) = KRB_SERVER_ENCRYPT
 Database manager authentication      (AUTHENTICATION) = KRB_SERVER_ENCRYPT
 Alternate authentication             (ALTERNATE_AUTH_ENC) = AES_ONLY
```

### Important: SRVCON_AUTH vs AUTHENTICATION

`SRVCON_AUTH` takes precedence over `AUTHENTICATION` for all remote TCP/IP connections. If `SRVCON_AUTH` is set (not blank), the `AUTHENTICATION` value is ignored for incoming client connections. This is the most common misconfiguration — setting `AUTHENTICATION` to `KRB_SERVER_ENCRYPT` while `SRVCON_AUTH` remains at `KERBEROS`.

### Kerberos Plugin Configuration

These should already be set and typically don't need changes:

| Parameter | Value |
|---|---|
| `SRVCON_GSSPLUGIN_LIST` | `IBMkrb5` |
| `SRV_PLUGIN_MODE` | `UNFENCED` |
| `SRVCON_PW_PLUGIN` | *(empty = default)* |

### Server-Side Catalog Entries

On the server, catalog entries for the same database (e.g., `FKKTOTST` as alias for `INLTST`) also carry an `AUTHENTICATION` attribute:

```
Database alias     = FKKTOTST
Database name      = INLTST
Node name          = NODE2
Authentication     = KERBEROS         <-- This affects CLP loopback, not JDBC
```

This catalog-level `AUTHENTICATION` attribute only affects DB2 CLP connections that route through the catalog. JDBC connections bypass catalog entries entirely (see Client Types section below).

---

## Client-Side Configuration

### DB2 CLP Client (db2cmd)

The DB2 Command Line Processor uses the local catalog to resolve database aliases. Configuration is done via `db2 catalog` commands.

**Step 1: Catalog the node**

```bat
db2 catalog tcpip node FKKTOTST remote t-no1inltst-db.DEDGE.fk.no server 3718
```

**Step 2: Catalog the database with authentication type**

```bat
db2 catalog database INLTST as FKKTOTST at node FKKTOTST AUTHENTICATION KRB_SERVER_ENCRYPT TARGET PRINCIPAL db2/t-no1inltst-db.DEDGE.fk.no
```

**Step 3: Set CLI/ODBC Kerberos settings**

```bat
db2 update cli cfg for section COMMON using CLNT_KRB_PLUGIN IBMkrb5
db2 update cli cfg for section COMMON using AUTHENTICATION KERBEROS_SSPI
db2 terminate
```

**Step 4: Test**

```bat
db2 connect to FKKTOTST
db2 "SELECT COUNT(*) FROM inl.KONTOTYPE"
db2 connect reset
```

### JDBC / DBeaver / Type 4 Driver

JDBC Type 4 drivers (IBM JCC) connect **directly via DRDA protocol** over TCP/IP. They do **not** use the DB2 catalog system.

**Connection parameters:**

| Parameter | Value | Notes |
|---|---|---|
| URL | `jdbc:db2://t-no1inltst-db:3718/INLTST` | Must use the **actual database name**, not a catalog alias |
| User | `DEDGE\fkgeista` | Domain-qualified username |
| Password | *(your password)* | |
| securityMechanism | *(default)* | Driver auto-negotiates; no override needed |

**Critical: Use the real database name, not the catalog alias.**

| Database name | JDBC result |
|---|---|
| `INLTST` | Connects successfully |
| `FKKTOTST` | `DSS length not 0` protocol error — the server tries to resolve this catalog alias internally and creates a DRDA redirect loop |
| Non-existent name | `SQLCODE=-1001` (database not found) |

**DBeaver setup:**

1. Connection type: **Db2 for LUW**
2. Connect by: **Host**
3. Host: `t-no1inltst-db`
4. Port: `3718`
5. Database: **`INLTST`** (not `FKKTOTST`)
6. Authentication: Database Native
7. Username: `DEDGE\fkgeista`
8. Password: your password

### ODBC Client

ODBC connections use the same catalog as DB2 CLP. After cataloging (Step 1-3 above), register as ODBC data source:

```bat
db2 catalog system odbc data source FKKTOTST
db2 catalog user odbc data source FKKTOTST
```

---

## Client Types Comparison

| Client Type | Uses DB2 Catalog? | Database Name | Auth Negotiation |
|---|---|---|---|
| DB2 CLP (`db2cmd`) | Yes | Alias (`FKKTOTST`) | Via catalog entry's `AUTHENTICATION` attribute |
| ODBC | Yes | Alias (`FKKTOTST`) | Via catalog + CLI config |
| **JDBC (JCC Type 4)** | **No** | **Real name (`INLTST`)** | **Direct DRDA negotiation with server's `SRVCON_AUTH`** |
| .NET (IBM.Data.DB2) | Depends | Either (if cataloged) | Via catalog or connection string |

---

## DatabasesV2.json Configuration

The centralized database configuration (`DatabasesV2.json`) defines access points for each database. Example for `INLTST`:

```json
{
  "Database": "INLTST",
  "Provider": "DB2",
  "Application": "INL",
  "Environment": "TST",
  "PrimaryCatalogName": "FKKTOTST",
  "ServerName": "t-no1inltst-db",
  "AccessPoints": [
    {
      "InstanceName": "DB2",
      "CatalogName": "INLTST",
      "AccessPointType": "PrimaryDb",
      "Port": "50000",
      "NodeName": "NODE1",
      "AuthenticationType": "Kerberos"
    },
    {
      "InstanceName": "DB2",
      "CatalogName": "FKKTOTST",
      "AccessPointType": "Alias",
      "Port": "3718",
      "NodeName": "NODE2",
      "AuthenticationType": "Kerberos"
    },
    {
      "InstanceName": "DB2FED",
      "CatalogName": "XINLTST",
      "AccessPointType": "FederatedDb",
      "Port": "50010",
      "NodeName": "NODEFED",
      "AuthenticationType": "Ntlm"
    }
  ]
}
```

To enable `KRB_SERVER_ENCRYPT` for JDBC, change the `AuthenticationType` from `"Kerberos"` to `"KerberosServerEncrypt"` on the relevant access point. The `Set-Db2KerberosClientConfig` function in `Db2-Handler.psm1` uses this value to determine the catalog command's `AUTHENTICATION` parameter:

```powershell
$authenticationType = if ($CommonParamObject.AuthenticationType -eq "KerberosServerEncrypt") {
    "KRB_SERVER_ENCRYPT"
} else {
    "KERBEROS"
}
```

---

## How KRB_SERVER_ENCRYPT Works

`KRB_SERVER_ENCRYPT` is a hybrid authentication mode:

```
Client connects via DRDA
  │
  ├─ Windows domain client with Kerberos ticket?
  │    └─ Uses KERBEROS (GSS-API / IBMkrb5 plugin) ── SSO, no password needed
  │
  └─ Non-Kerberos client (JDBC, Linux, etc.)?
       └─ Falls back to SERVER_ENCRYPT ── username + AES-encrypted password
```

This means:
- **Windows CLP clients** on the domain continue to use transparent Kerberos SSO
- **JDBC/DBeaver** clients can authenticate with username + encrypted password
- **Non-Windows clients** (Linux, macOS) can connect using username + password (encrypted with AES)

---

## Troubleshooting

### Error: "Security mechanism not supported" (ERRORCODE=-4214)

**Cause:** `SRVCON_AUTH` is set to `KERBEROS` (not `KRB_SERVER_ENCRYPT`). The server rejects the encrypted password mechanism.

**Fix:** `db2 update dbm cfg using SRVCON_AUTH KRB_SERVER_ENCRYPT` + restart instance.

### Error: "DSS length not 0" (ERRORCODE=-4499)

**Cause:** JDBC URL uses a catalog alias (e.g., `FKKTOTST`) instead of the actual database name (`INLTST`). The server tries to resolve the alias through its catalog, creating a DRDA redirect that corrupts the protocol exchange.

**Fix:** Change the JDBC URL to use the real database name: `jdbc:db2://host:port/INLTST`

### Error: "User ID or Password invalid" (ERRORCODE=-4214, SQLSTATE=28000)

**Cause:** Correct protocol negotiation, but wrong credentials. This error actually confirms the auth setup is working correctly.

**Fix:** Verify username and password.

### DB2 CLP works but JDBC doesn't

**Cause:** DB2 CLP uses the local catalog (which resolves aliases and handles Kerberos via the `IBMkrb5` plugin). JDBC bypasses the catalog and connects directly via DRDA. Different server-side parameters control each path:

| Connection type | Controlled by |
|---|---|
| Local connections | `AUTHENTICATION` |
| Remote CLP (via catalog) | Catalog entry's `AUTHENTICATION` attribute |
| Remote JDBC/DRDA | `SRVCON_AUTH` |

### ALTERNATE_AUTH_ENC value rejected

DB2 12.1 LUW accepts `AES_ONLY` (not `AES_256_CBC` which is for newer versions). If `db2 update dbm cfg using ALTERNATE_AUTH_ENC AES_256_CBC` fails with `SQL0104N`, use `AES_ONLY` instead.

---

## Automation in Db2-Handler.psm1

The `Add-DatabaseConfigurations` function in `_Modules/Db2-Handler/Db2-Handler.psm1` applies these settings automatically when `$WorkObject.UseNewConfigurations` is `$true`:

```powershell
if ($WorkObject.UseNewConfigurations) {
    $db2Commands += "db2 update dbm cfg using AUTHENTICATION KRB_SERVER_ENCRYPT"
    $db2Commands += "db2 update dbm cfg using SRVCON_AUTH KRB_SERVER_ENCRYPT"
    $db2Commands += "db2 update dbm cfg using ALTERNATE_AUTH_ENC AES_ONLY"
} else {
    $db2Commands += "db2 update dbm cfg using AUTHENTICATION KERBEROS"
    $db2Commands += "db2 update dbm cfg using SRVCON_AUTH KERBEROS"
}
```

The client-side catalog script generation in `Set-Db2KerberosClientConfig` also respects this, using `KRB_SERVER_ENCRYPT` in the `db2 catalog database` command when `CommonParamObject.AuthenticationType` is `"KerberosServerEncrypt"`.

To enable: set `"AuthenticationType": "KerberosServerEncrypt"` on the relevant access point in `DatabasesV2.json`, and run the pipeline with `-UseNewConfigurations`.

---

## Quick Reference: Complete Setup Checklist

### Server

- [ ] `AUTHENTICATION = KRB_SERVER_ENCRYPT`
- [ ] `SRVCON_AUTH = KRB_SERVER_ENCRYPT`
- [ ] `ALTERNATE_AUTH_ENC = AES_ONLY`
- [ ] `SRVCON_GSSPLUGIN_LIST = IBMkrb5`
- [ ] Instance restarted (`db2stop force` + `db2start`)

### Client (DB2 CLP / ODBC)

- [ ] Node cataloged with correct hostname and port
- [ ] Database cataloged with `AUTHENTICATION KRB_SERVER_ENCRYPT` and `TARGET PRINCIPAL`
- [ ] `CLNT_KRB_PLUGIN = IBMkrb5` in CLI config
- [ ] ODBC data sources registered (if needed)

### Client (JDBC / DBeaver)

- [ ] Use real database name (`INLTST`), not catalog alias (`FKKTOTST`)
- [ ] Connect to the DRDA listener port (e.g., `3718`)
- [ ] Domain-qualified username (`DEDGE\fkgeista`)
- [ ] No special `securityMechanism` needed (driver auto-negotiates)
