# DB2 SSL Hands-On Implementation Guide

## 🖥️ DB2 Server SSL Configuration Details

### Server Environment Prerequisites
```batch
# Verify DB2 Installation
SET DB2_INSTALL_PATH=C:\DbInst
SET DB2_INSTANCE=DB2
SET DB2_HOME=%DB2_INSTALL_PATH%\%DB2_INSTANCE%

# Check GSKit Installation
SET GSKIT_PATH=C:\Program Files\ibm\gsk8\bin
dir "%GSKIT_PATH%\gsk8capicmd_64.exe"
```

### Exact DB2 Configuration Parameters
After running the SSL setup scripts, verify these exact DB2 configuration settings:

```batch
db2 get dbm cfg | findstr -i ssl
```

**Expected Output:**
```
SSL service name (SSL_SVCENAME) = 3701
SSL server keystore database (SSL_SVR_KEYDB) = C:\DB2\ssl\server.kdb
SSL server stash file (SSL_SVR_STASH) = C:\DB2\ssl\server.sth
SSL server certificate label (SSL_SVR_LABEL) = DB2_SERVER_CERT
SSL client keystore database (SSL_CLNT_KEYDB) = 
SSL client stash file (SSL_CLNT_STASH) = 
SSL certificate label (SSL_CLNT_LABEL) = 
SSL cipher suites (SSL_CIPHERSPECS) = 
SSL versions (SSL_VERSIONS) = 
```

### Server Network Configuration
```batch
# Verify services file entry (Windows)
type C:\Windows\System32\drivers\etc\services | findstr 3701

# Should show:
# db2c_DB2     3701/tcp  # DB2 connection service port

# Verify firewall rules
netsh advfirewall firewall show rule name="DB2 Remote Access t-no1fkmdev-db"
```

### Certificate Details Verification
```batch
# List certificates in keystore
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -list -db "C:\DB2\ssl\server.kdb" -pw "SslPwd123"

# Show certificate details
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -details -db "C:\DB2\ssl\server.kdb" -pw "SslPwd123" -label "DB2_SERVER_CERT"
```

---

## 🎯 DBeaver Community Edition Configuration

### Step 1: Certificate Import Options

#### Option A: Import to DBeaver's JRE (Recommended)
```batch
# Navigate to DBeaver JRE directory
cd "C:\Program Files\DBeaver\jre\bin"

# Import certificate
keytool.exe -import -alias t-no1fkmdev-db.DEDGE.fk.no -file "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\SSL\T-NO1FKMDEV-DB\db2-server-cert.cer" -keystore "..\lib\security\cacerts" -storepass changeit -noprompt
```

#### Option B: Create Custom Truststore
```batch
# Create directory
mkdir "C:\ProgramData\DBeaver\ssl"

# Create custom truststore
"C:\Program Files\DBeaver\jre\bin\keytool.exe" -import -alias t-no1fkmdev-db.DEDGE.fk.no -file "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\SSL\T-NO1FKMDEV-DB\db2-server-cert.cer" -keystore "C:\ProgramData\DBeaver\ssl\db2-truststore.jks" -storepass SslPwd123 -noprompt
```

### Step 2: DBeaver Connection Configuration

#### Connection Settings Tab:
```
Server Host: t-no1fkmdev-db.DEDGE.fk.no
Port: 3701
Database: FKAVDNT
Authentication: Kerberos
Username: [leave empty]
Password: [leave empty]
```

#### Driver Properties Tab:
**Essential Properties:**
```
securityMechanism = 11
sslConnection = true
kerberosServerPrincipal = db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO
gssCredential = SYSTEM_LOGIN
```

**Additional SSL Properties (if using custom truststore):**
```
sslTrustStoreLocation = C:\ProgramData\DBeaver\ssl\db2-truststore.jks
sslTrustStorePassword = SslPwd123
```

#### SSL Tab Configuration:
```
☑ Use SSL
SSL Mode: require
SSL Factory: [leave default]
SSL Certificate: [point to certificate file if not using truststore]
```

#### Advanced Tab (Optional):
```
☑ Show non-default database
☑ Show system schemas
Connection timeout: 30000
Keep-alive interval: 600
```

### Step 3: JDBC URL Examples

#### Complete JDBC URLs for DBeaver:

**With System Truststore:**
```
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:3701/FKAVDNT:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO;gssCredential=SYSTEM_LOGIN;
```

**With Custom Truststore:**
```
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:3701/FKAVDNT:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO;gssCredential=SYSTEM_LOGIN;sslTrustStoreLocation=C:\ProgramData\DBeaver\ssl\db2-truststore.jks;sslTrustStorePassword=SslPwd123;
```

---

## ☕ Java JDBC Client Configuration

### Required Dependencies
```xml
<!-- Maven dependencies -->
<dependency>
    <groupId>com.ibm.db2</groupId>
    <artifactId>jcc</artifactId>
    <version>11.5.8.0</version>
</dependency>
```

### Environment Variables
```batch
# Windows Environment Variables
SET JAVA_HOME=C:\Program Files\Java\jdk-17
SET DB2_SSL_TRUSTSTORE=C:\ssl\db2-truststore.jks
SET DB2_SSL_PASSWORD=SslPwd123
SET KRB5_CONFIG=C:\Windows\krb5.ini
```

### Java System Properties
```java
// Set these system properties in your Java application
System.setProperty("javax.net.ssl.trustStore", "C:\\ssl\\db2-truststore.jks");
System.setProperty("javax.net.ssl.trustStorePassword", "SslPwd123");
System.setProperty("javax.net.ssl.trustStoreType", "JKS");

// Kerberos properties
System.setProperty("java.security.krb5.conf", "C:\\Windows\\krb5.ini");
System.setProperty("java.security.auth.login.config", "C:\\config\\jaas.conf");
System.setProperty("javax.security.auth.useSubjectCredsOnly", "false");

// SSL debugging (for troubleshooting)
System.setProperty("javax.net.debug", "ssl,handshake");
```

### JAAS Configuration File (jaas.conf)
```
DB2ConnectionAuth {
    com.sun.security.auth.module.Krb5LoginModule required
    useTicketCache=true
    doNotPrompt=true
    debug=true;
};
```

### Java Connection Code Example
```java
import java.sql.*;
import java.util.Properties;

public class DB2SSLConnection {
    public static void main(String[] args) {
        String url = "jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:3701/FKAVDNT";
        
        Properties props = new Properties();
        props.setProperty("securityMechanism", "11"); // Kerberos
        props.setProperty("sslConnection", "true");
        props.setProperty("kerberosServerPrincipal", "db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO");
        props.setProperty("gssCredential", "SYSTEM_LOGIN");
        
        // SSL Trust Store Configuration
        props.setProperty("sslTrustStoreLocation", "C:\\ssl\\db2-truststore.jks");
        props.setProperty("sslTrustStorePassword", "SslPwd123");
        
        try {
            Class.forName("com.ibm.db2.jcc.DB2Driver");
            Connection conn = DriverManager.getConnection(url, props);
            System.out.println("Connected successfully!");
            conn.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

---

## 🐍 Python Client Configuration

### Required Libraries
```bash
pip install ibm_db
pip install pyOpenSSL
```

### Python Connection Example
```python
import ibm_db

# Connection parameters
conn_str = f"""
DATABASE=FKAVDNT;
HOSTNAME=t-no1fkmdev-db.DEDGE.fk.no;
PORT=3701;
PROTOCOL=TCPIP;
UID=;
PWD=;
SECURITY=SSL;
SSLServerCertificate=C:\\ssl\\db2-server-cert.cer;
Authentication=KERBEROS;
KerberosServerPrincipal=db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO;
"""

try:
    conn = ibm_db.connect(conn_str, "", "")
    print("Connected successfully!")
    ibm_db.close(conn)
except Exception as e:
    print(f"Connection failed: {e}")
```

---

## 🔧 .NET Client Configuration

### Connection String Example
```csharp
using IBM.Data.DB2.Core;

string connectionString = @"
    Server=t-no1fkmdev-db.DEDGE.fk.no:3701;
    Database=FKAVDNT;
    Authentication=Kerberos;
    Security=SSL;
    SSLServerCertificate=C:\ssl\db2-server-cert.cer;
    KerberosServerPrincipal=db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO;
";

using (var connection = new DB2Connection(connectionString))
{
    connection.Open();
    Console.WriteLine("Connected successfully!");
}
```

---

## 🐧 Linux Client Configuration

### Certificate Import (Linux)
```bash
# Convert certificate format if needed
openssl x509 -in db2-server-cert.cer -inform DER -out db2-server-cert.pem -outform PEM

# Create Java truststore
keytool -import -alias db2-server -file db2-server-cert.pem -keystore /opt/db2-truststore.jks -storepass SslPwd123 -noprompt

# System-wide certificate (optional)
sudo cp db2-server-cert.pem /usr/local/share/ca-certificates/db2-server.crt
sudo update-ca-certificates
```

### Linux Environment Variables
```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export DB2_SSL_TRUSTSTORE=/opt/db2-truststore.jks
export DB2_SSL_PASSWORD=SslPwd123
export KRB5_CONFIG=/etc/krb5.conf
```

---

## 🔍 Troubleshooting Guide

### Common SSL Handshake Issues

#### Enable SSL Debug Logging
```java
// Java applications
System.setProperty("javax.net.debug", "ssl,handshake,trustmanager");
System.setProperty("com.ibm.jsse2.overrideDefaultTLS", "true");
```

#### Test SSL Connection
```batch
# Windows PowerShell SSL test
powershell -Command "
$socket = New-Object System.Net.Sockets.TcpClient
$socket.Connect('t-no1fkmdev-db.DEDGE.fk.no', 3701)
$ssl = New-Object System.Net.Security.SslStream($socket.GetStream())
$ssl.AuthenticateAsClient('t-no1fkmdev-db.DEDGE.fk.no')
Write-Host 'SSL Handshake successful'
Write-Host 'Certificate: ' $ssl.RemoteCertificate.Subject
$ssl.Close()
$socket.Close()
"
```

### Certificate Validation Errors
```
# Common errors and solutions:

Error: "PKIX path building failed"
Solution: Certificate not in truststore - reimport certificate

Error: "Hostname verification failed"
Solution: Ensure certificate CN matches server hostname

Error: "Certificate expired"
Solution: Regenerate server certificate

Error: "SSLHandshakeException"
Solution: Check SSL cipher compatibility
```

### Kerberos Authentication Issues
```batch
# Test Kerberos ticket
klist

# Renew Kerberos ticket
kinit username@DEDGE.FK.NO

# Clear Kerberos cache
kdestroy
```

---

## 📋 Verification Checklist

### Server Verification
- [ ] DB2 SSL parameters configured correctly
- [ ] Certificate created and set as default
- [ ] Firewall rule allowing SSL port
- [ ] DB2 instance restarted successfully
- [ ] SSL handshake test passes

### Client Verification
- [ ] Certificate imported to appropriate truststore
- [ ] JDBC driver version compatible
- [ ] Kerberos configuration correct
- [ ] Network connectivity to SSL port
- [ ] Authentication successful

### Security Verification
- [ ] Self-signed certificate replaced with CA-signed (production)
- [ ] Strong passwords implemented
- [ ] Network access properly restricted
- [ ] Audit logging enabled
- [ ] Certificate expiration monitoring configured

---

## 🚀 Performance Optimization

### Connection Pooling Configuration
```java
// HikariCP example
HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:3701/FKAVDNT");
config.addDataSourceProperty("securityMechanism", "11");
config.addDataSourceProperty("sslConnection", "true");
config.addDataSourceProperty("kerberosServerPrincipal", "db2/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO");
config.setMaximumPoolSize(20);
config.setConnectionTimeout(30000);
```

### SSL Performance Tuning
```
# DB2 SSL cipher optimization
db2 update dbm cfg using SSL_CIPHERSPECS "TLS_RSA_WITH_AES_128_CBC_SHA"

# Connection keep-alive
db2 update dbm cfg using KEEPALIVE 1
```

This guide provides the exact technical details needed to implement DB2 SSL connections with proper client configurations for various platforms and tools. 