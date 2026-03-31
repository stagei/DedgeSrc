# DBeaver Kerberos Authentication Setup Progress

## Environment Details
- **DB2 Version:** 12.1
- **Database Server:** t-no1fkmtst-db:3701
- **Database Name:** BASISTST
- **OS:** Windows 10.0.26100
- **Authentication:** Kerberos SSO (already working with ODBC and cataloged databases)

## Current Status: ⚠️ Progress Made - New Error

## Attempt Log

### Attempt 1: Security Mechanism 11 (Kerberos) ❌
- **Timestamp:** [Previous attempt]
- **User Confirmed:** ✅ Tested
- **Connection String:** `jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=11;`
- **Error:** "No LoginModules configured for JaasClient"
- **Issue:** Missing or incorrectly configured JAAS configuration file

### Attempt 2: Security Mechanism 15 (Windows SSPI) ❌  
- **Timestamp:** [Previous attempt]
- **User Confirmed:** ✅ Tested
- **Connection String:** `jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=15;`
- **Error:** "non-SSL connection are not supported for security mechanism 15"
- **Issue:** This mechanism requires SSL/TLS encryption

### Attempt 3: JAAS Configuration Without krb5.ini ⚠️ Partial Success
- **Timestamp:** 2024-12-19 [Previous]
- **User Confirmed:** ✅ JAAS file created, JVM args configured
- **Strategy:** Use minimal JAAS config without krb5.ini, leverage Windows domain auto-discovery
- **New Error:** "Unable to obtain Principal Name for authentication"
- **Progress:** ✅ JAAS configuration now working (no more "No LoginModules" error)
- **Issue:** Java cannot auto-discover the Service Principal Name (SPN) for DB2 server

### Attempt 4: Add SPN to JDBC Connection String ⚠️ SPN Mismatch Found
- **Timestamp:** 2024-12-19 [Current Time]
- **User Confirmed:** ✅ Tested current SPN
- **Strategy:** Explicitly specify the Kerberos Service Principal Name in connection string
- **Current Connection String:** `jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=11;kerberosServerPrincipal=db2/t-no1fkmtst-db`
- **Issue:** SPN mismatch - using `db2srv/t-no1fkmtst-db` but registered SPNs are different

### Discovered SPNs (via setspn -Q db2/t-no1fkmtst-db):
```
CN=T1_srv_ t-no1fkmtst-db,OU=Servicekontoer,OU=Brukere,OU=T1,OU=FKA,DC=DEDGE,DC=fk,DC=no
        db2/t-no1fkmtst-db.DEDGE.fk.no
        db2/t-no1fkmtst-db
```

### Attempt 5: Use Correct SPN Format ❌ Still Failing
- **Timestamp:** 2024-12-19 [Previous]
- **User Confirmed:** ✅ Tested with correct SPN
- **Strategy:** Use the actual registered SPN from domain
- **Connection String Tested:** `jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=11;kerberosServerPrincipal=db2/t-no1fkmtst-db;`
- **Error:** Still "Unable to obtain Principal Name for authentication"
- **Issue:** Even with correct SPN, authentication still failing

### Attempt 6: Add Kerberos Realm to SPN ⏳ BREAKTHROUGH FOUND
- **Timestamp:** 2024-12-19 [Current Time]
- **User Confirmed:** ⏳ Pending test
- **Strategy:** Add explicit Kerberos realm to the SPN or try FQDN format
- **Discovery:** ✅ Found valid Kerberos ticket in cache: `db2/t-no1fkmtst-db.DEDGE.fk.no @ DEDGE.FK.NO`

### klist Analysis Results ✅
```
#4>     Client: FKGEISTA @ DEDGE.FK.NO
        Server: db2/t-no1fkmtst-db.DEDGE.fk.no @ DEDGE.FK.NO
        KerbTicket Encryption Type: RSADSI RC4-HMAC(NT)
        Ticket Flags 0x40a10000 -> forwardable renewable pre_authent name_canonicalize
        Start Time: 5/23/2025 9:39:13 (local)
        End Time:   5/23/2025 18:16:50 (local)
        Renew Time: 5/30/2025 8:16:50 (local)
```

**Recommended Connection String (should match existing ticket):**
```
jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=11;kerberosServerPrincipal=db2/t-no1fkmtst-db.DEDGE.fk.no@DEDGE.FK.NO;
```

## Why We're Trying Without krb5.ini First

**ODBC vs JDBC Difference:**
- **ODBC/DB2 Client:** Uses Windows native Kerberos libraries and domain configuration automatically
- **Java/JDBC:** Typically requires explicit Kerberos configuration file

**Our Hypothesis:**
Since Windows domain is properly configured and Kerberos SSO works with ODBC, Java might be able to auto-discover the Kerberos settings from Windows without needing explicit krb5.ini configuration.

## Completed Steps ✅

### Step 1: Create JAAS Configuration File ✅
- **Location:** `C:\ProgramData\IBM\DB2\DB2COPY1\cfg\jaas.conf`
- **User Confirmed:** ✅ Created successfully
- **Content:**
```
JaasClient {
   com.sun.security.auth.module.Krb5LoginModule required
   useTicketCache=true
   doNotPrompt=true;
};
```

### Step 2: Configure DBeaver JVM Arguments ✅
- **User Confirmed:** ✅ Added to dbeaver.ini
- **Arguments:**
```
-Djava.security.auth.login.config=C:\ProgramData\IBM\DB2\DB2COPY1\cfg\jaas.conf
-Djavax.security.auth.useSubjectCredsOnly=false
```

## Current Attempt: Adding SPN to Connection String

### Step 3: Add Service Principal Name ⚠️ SPN Mismatch Found
- **User Confirmed:** ✅ Tested with incorrect SPN
- **Issue Found:** Using `db2srv/t-no1fkmtst-db` but actual registered SPNs are:
  - `db2/t-no1fkmtst-db.DEDGE.fk.no`
  - `db2/t-no1fkmtst-db`

### Step 4: Test with Correct SPN ⏳
- **User Confirmed:** ⏳ Pending test
- **Recommended Connection Strings:**

**Option A: Short form SPN (try first)**
```
jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=11;kerberosServerPrincipal=db2/t-no1fkmtst-db;
```

**Option B: FQDN form SPN (if Option A fails)**
```
jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=11;kerberosServerPrincipal=db2/t-no1fkmtst-db.DEDGE.fk.no;
```

## Fallback Options

### Fallback 1: Add krb5.ini Configuration
- **Status:** ⏳ Ready if needed
- **Additional JVM Argument:** `-Djava.security.krb5.conf=C:\Windows\krb5.ini`

### Fallback 2: SSL with Mechanism 15
- **Status:** ⏳ Ready if needed
- **Connection String:** `jdbc:db2://t-no1fkmtst-db:3701/BASISTST:securityMechanism=15;sslConnection=true;`

## Notes
- Kerberos SSO is already working with ODBC and DB2 client
- No keytab file needed (using existing ticket cache)
- Username in DBeaver: DEDGEVKGEISTA
- JAAS configuration is now working correctly

## DB2 JDBC Security Mechanisms Reference

Here's the complete list of available `securityMechanism` values for DB2 JDBC connections:

| Security Mechanism | Value | Constant Name | Description |
|-------------------|-------|---------------|-------------|
| **User ID and password** | `3` | `CLEAR_TEXT_PASSWORD_SECURITY` | Basic username/password authentication |
| **User ID only** | `4` | `USER_ONLY_SECURITY` | Username only (client authentication) |
| **User ID and encrypted password** | `7` | `ENCRYPTED_PASSWORD_SECURITY` | Username with encrypted password |
| **Encrypted user ID and encrypted password** | `9` | `ENCRYPTED_USER_AND_PASSWORD_SECURITY` | Both username and password encrypted (default in newer versions) |
| **Kerberos** | `11` | `KERBEROS_SECURITY` | Kerberos authentication ✅ **Currently using** |
| **Encrypted user ID and encrypted data** | `12` | `ENCRYPTED_USER_AND_DATA_SECURITY` | Encrypted username and data transmission |
| **Encrypted user ID, password, and data** | `13` | `ENCRYPTED_USER_PASSWORD_AND_DATA_SECURITY` | Full encryption of credentials and data |
| **Plugin** | `15` | `PLUGIN_SECURITY` | GSS plugin authentication (Windows SSPI) |
| **Encrypted user ID only** | `16` | `ENCRYPTED_USER_ONLY_SECURITY` | Encrypted username only |
| **TLS client certificate** | `18` | `TLS_CLIENT_CERTIFICATE_SECURITY` | Certificate-based authentication |
| **Token authentication** | `19` | `TOKEN_SECURITY` | Token-based authentication |

### Notes on Security Mechanisms:
- **Value 11 (Kerberos)** - What we're currently using successfully
- **Value 15 (Plugin/SSPI)** - Requires SSL connection for DB2
- **Value 9** - Default for newer DB2 JDBC drivers (4.33+)
- **Value 3** - Default for older DB2 JDBC drivers

### Compatibility:
- **DB2 on Linux/Unix/Windows**: Supports values 3, 4, 7, 9, 11, 12, 13, 15, 16, 19
- **DB2 for z/OS**: Supports values 3, 4, 7, 9, 11, 12, 13, 18
- **DB2 for IBM i**: Supports values 3, 4, 7, 9, 11

Source: [IBM DB2 Security Documentation](https://www.ibm.com/docs/en/db2/11.5.x?topic=java-security-under-data-server-driver-jdbc-sqlj)

## SSL Configuration Options

If you want to enable SSL on your DB2 server (e.g., to use securityMechanism=15 or add encryption), you need to configure the `ssl_svcename` parameter:

### Server-Side SSL Configuration

#### 1. Configure SSL Service Name
```sql
-- Set the SSL service name/port (run as DB2 instance owner)
db2 update dbm cfg using ssl_svcename <port_number>
-- Example:
db2 update dbm cfg using ssl_svcename 50001
```

#### 2. Configure SSL Certificate and Keystore
```sql
-- Set the SSL keystore location
db2 update dbm cfg using ssl_svr_keydb <path_to_keystore>
-- Example:
db2 update dbm cfg using ssl_svr_keydb C:\DB2\ssl\server.kdb

-- Set the SSL keystore password stash file
db2 update dbm cfg using ssl_svr_stash <path_to_stash_file>
-- Example:
db2 update dbm cfg using ssl_svr_stash C:\DB2\ssl\server.sth
```

#### 3. Configure SSL Security Label (Optional)
```sql
-- Set SSL certificate label (if using specific certificate)
db2 update dbm cfg using ssl_svr_label <certificate_label>
```

#### 4. Restart DB2 Instance
```cmd
-- Stop DB2
db2stop

-- Start DB2
db2start
```

### Client-Side Changes for SSL

If you enable SSL on the server, your JDBC connection string would change to:

#### Option 1: SSL with Kerberos (Current mechanism + SSL)
```
jdbc:db2://t-no1fkmtst-db:50001/BASISTST:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/t-no1fkmtst-db.DEDGE.fk.no@DEDGE.FK.NO;
```

#### Option 2: SSL with Windows SSPI (Alternative)
```
jdbc:db2://t-no1fkmtst-db:50001/BASISTST:securityMechanism=15;sslConnection=true;
```

### Verification Commands

#### Check Current SSL Configuration:
```sql
-- View current SSL settings
db2 get dbm cfg | findstr -i ssl
```

#### Test SSL Connection:
```cmd
-- Test SSL connectivity
db2 connect to <database> user <username> using <password>
```

### SSL Certificate Requirements

You'll need either:
1. **Self-signed certificate** (for testing)
2. **CA-signed certificate** (for production)
3. **Windows Certificate Store integration**

### Creating SSL Certificate Files

The SSL keystore files need to be **created** using DB2's GSKit tools. Here's how:

#### Method 1: Create Self-Signed Certificate (For Testing)

```cmd
# Navigate to DB2 GSKit directory (adjust path for your DB2 version)
cd "C:\Program Files\IBM\SQLLIB\gskit\bin"

# Create directory for SSL files
mkdir C:\DB2\ssl

# Create a new keystore database
gsk8capicmd_64 -keydb -create -db "C:\DB2\ssl\server.kdb" -pw "your_password" -stash

# Create a self-signed certificate
gsk8capicmd_64 -cert -create -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT" -dn "CN=t-no1fkmtst-db.DEDGE.fk.no,O=YourOrg,C=NO" -size 2048 -sigalg SHA256WithRSA

# Set the certificate as default
gsk8capicmd_64 -cert -setdefault -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT"
```

#### Method 2: Import Existing Certificate

If you have an existing certificate from your CA:

```cmd
# Import CA certificate
gsk8capicmd_64 -cert -add -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "CA_CERT" -file "ca_cert.cer"

# Import server certificate
gsk8capicmd_64 -cert -add -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT" -file "server_cert.cer"

# Import private key (if separate)
gsk8capicmd_64 -cert -import -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT" -file "server_cert_with_key.p12" -pw_p12 "p12_password"
```

#### Method 3: Use Windows Certificate Store

```cmd
# Export certificate from Windows Certificate Store to .p12 format first
# Then import into DB2 keystore
gsk8capicmd_64 -cert -import -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT" -file "exported_cert.p12" -pw_p12 "export_password"
```

### GSKit Commands Reference

#### List certificates in keystore:
```cmd
gsk8capicmd_64 -cert -list -db "C:\DB2\ssl\server.kdb" -pw "your_password"
```

#### View certificate details:
```cmd
gsk8capicmd_64 -cert -details -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT"
```

#### Extract certificate to file:
```cmd
gsk8capicmd_64 -cert -extract -db "C:\DB2\ssl\server.kdb" -pw "your_password" -label "DB2_SERVER_CERT" -target "server_cert.cer"
```

### File Locations and Names

- **server.kdb** - The keystore database file (you choose the location)
- **server.sth** - The stash file (automatically created with `-stash` option)
- **server.rdb** - The request database (automatically created)

### Important Notes:

1. **GSKit Location**: Usually in `C:\Program Files\IBM\SQLLIB\gskit\bin\`
2. **Password**: Use a strong password and remember it
3. **Certificate DN**: Must match your server hostname
4. **Permissions**: DB2 instance owner must have read access to these files
5. **Backup**: Keep backups of your certificate files

### Alternative: Quick Test Certificate

For quick testing, you can also use:

```cmd
# Create a simple test keystore
keytool -genkeypair -alias db2server -keyalg RSA -keysize 2048 -validity 365 -keystore "C:\DB2\ssl\server.jks" -storepass "password123" -keypass "password123" -dname "CN=t-no1fkmtst-db.DEDGE.fk.no,O=Test,C=NO"

# Then convert to GSKit format if needed
```

**Recommendation**: Start with Method 1 (self-signed) for testing, then move to Method 2 (CA-signed) for production.

## Script Idempotency Issues and Solutions

### Current Issues with configure-db2-ssl.bat

The current script has some issues if run multiple times:

#### ❌ **Problems:**
1. **Step 2** - Creating keystore will fail if `server.kdb` already exists
2. **Step 3** - Creating certificate will fail if certificate label already exists
3. No cleanup of partial failures

#### ✅ **Solutions:**

**Option 1: Use teardown-db2-ssl.bat first**
```cmd
# If script fails, run teardown first, then retry
teardown-db2-ssl.bat
configure-db2-ssl.bat
```

**Option 2: Make script idempotent (recommended)**
The script should be modified to:
- Check if keystore exists before creating
- Remove existing certificates before creating new ones
- Handle partial failures gracefully

### Improved Script Sections

#### Better Step 2 (Keystore Creation):
```cmd
echo Step 2: Creating SSL keystore database...
if exist "%SSL_DIR%\server.kdb" (
    echo - Keystore already exists, removing old one...
    del /f "%SSL_DIR%\server.kdb" 2>nul
    del /f "%SSL_DIR%\server.sth" 2>nul
    del /f "%SSL_DIR%\server.rdb" 2>nul
)
"%GSKIT_PATH%\gsk8capicmd_64.exe" -keydb -create -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -stash
```

#### Better Step 3 (Certificate Creation):
```cmd
echo Step 3: Creating self-signed certificate...
REM Remove existing certificate if it exists
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -delete -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" 2>nul
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -create -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" -dn "CN=%SERVER_HOSTNAME%,O=FK,C=NO" -size 2048 -sigalg SHA256WithRSA
```

### Current Workarounds

**If the script fails partway through:**

1. **Run teardown script:**
   ```cmd
   teardown-db2-ssl.bat
   ```

2. **Then run configure script again:**
   ```cmd
   configure-db2-ssl.bat
   ```

3. **Or manually clean up and retry:**
   ```cmd
   # Stop DB2
   db2stop
   
   # Remove SSL files
   rmdir /s /q C:\DB2\ssl
   
   # Reset DB2 config
   db2 reset dbm cfg using ssl_svcename
   db2 reset dbm cfg using ssl_svr_keydb
   db2 reset dbm cfg using ssl_svr_stash
   db2 reset dbm cfg using ssl_svr_label
   
   # Restart DB2
   db2start
   
   # Run configure script again
   configure-db2-ssl.bat
   ```

### Safe Re-run Strategy

**Current script is safe to re-run ONLY for:**
- ✅ DB2 configuration updates (Steps 6-8)
- ✅ Directory creation (Step 1)

**NOT safe to re-run for:**
- ❌ Keystore creation (Step 2)
- ❌ Certificate creation (Step 3)

**Best Practice:** Always run teardown before re-running configure if there was any failure. 