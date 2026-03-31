# DB2 SSL Client Configuration Guide

This guide explains how to configure DB2 clients for SSL connections with Windows SSO using the automatically generated scripts.

## 📋 Overview

The `Db2-AddServerSslSupport.bat` script automatically generates client configuration scripts using the `Generate-ClientCertificateHandlingScripts.ps1` PowerShell script. These scripts handle SSL certificate installation and Kerberos configuration for different client types.

## 🛠️ Generated Scripts

When you run the main SSL configuration script, it creates install and uninstall scripts for three client types:

### 📁 Directory Structure
```
ClientSetup/
├── Jdbc/
│   ├── Install-Db2-SSL-Support-Java.bat
│   ├── Uninstall-Db2-SSL-Support-Java.bat
│   └── Manage-ClientCertificates.ps1
├── Dbeaver/
│   ├── Install-Db2-SSL-Support-Dbeaver.bat
│   ├── Uninstall-Db2-SSL-Support-Dbeaver.bat
│   └── Manage-ClientCertificates.ps1
└── OleDb/
    ├── Install-Db2-SSL-Support-OleDb.bat
    ├── Uninstall-Db2-SSL-Support-OleDb.bat
    └── Manage-ClientCertificates.ps1
```

## 🔧 Client Configuration Methods

### 1. Java/JDBC Applications

#### Installation
```cmd
# Navigate to client setup directory
cd ClientSetup\Java

# Run the install script
Install-Db2-SSL-Support-Java.bat
```

#### What it does:
- Imports SSL certificate into system Java truststore
- Copies `krb5.ini` to `C:\Windows\krb5.ini`
- Provides JDBC connection strings

#### Connection String Examples:
```java
// Recommended: Windows SSPI
jdbc:db2://hostname:50001/FKMVFT:securityMechanism=15;sslConnection=true;

// Alternative: Kerberos
jdbc:db2://hostname:50001/FKMVFT:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2srv/hostname@DEDGE.FK.NO;
```

#### Removal
```cmd
Uninstall-Db2-SSL-Support-Java.bat
```

---

### 2. DBeaver Configuration

#### Installation
```cmd
# Navigate to DBeaver setup directory
cd ClientSetup\Dbeaver

# Run the install script
Install-Db2-SSL-Support-Dbeaver.bat
```

#### What it does:
- Imports SSL certificate into DBeaver's JRE truststore
- Copies `krb5.ini` to `C:\Windows\krb5.ini`
- Provides DBeaver-specific configuration instructions

#### DBeaver Configuration Steps:
1. **Create New Connection**
   - Database: DB2 LUW
   - Server Host: `hostname.DEDGE.fk.no`
   - Port: `50001` (SSL) or `50000` (non-SSL)
   - Database: `FKMVFT`

2. **Authentication Tab**
   - **Leave Username and Password EMPTY**
   - Authentication will use your Windows domain login

3. **SSL Tab**
   - Use SSL: ✅ Yes
   - SSL Mode: Require

4. **Driver Properties**
   - Add custom property: `securityMechanism` = `15` (recommended)
   - Or: `securityMechanism` = `11` (alternative)

#### Complete JDBC URL:
```
jdbc:db2://hostname:50001/FKMVFT:securityMechanism=15;sslConnection=true;
```

#### Removal
```cmd
Uninstall-Db2-SSL-Support-Dbeaver.bat
```

---

### 3. OLE DB Applications

#### Installation
```cmd
# Navigate to OLE DB setup directory
cd ClientSetup\OleDb

# Run the install script
Install-Db2-SSL-Support-OleDb.bat
```

#### What it does:
- Imports SSL certificate into Windows certificate store
- Copies `krb5.ini` to `C:\Windows\krb5.ini`
- Provides OLE DB connection string examples

#### Connection String Examples:
```vb
' Recommended: Windows SSPI
Provider=IBMDADB2;Data Source=FKMVFT;Hostname=hostname;Port=50001;Protocol=TCPIP;Security=SSPI;SSL=True;

' Alternative: Kerberos
Provider=IBMDADB2;Data Source=FKMVFT;Hostname=hostname;Port=50001;Protocol=TCPIP;Authentication=Kerberos;SSL=True;
```

#### Removal
```cmd
Uninstall-Db2-SSL-Support-OleDb.bat
```

## 🚀 Quick Start for Each Client Type

### Java/JDBC Quick Start
1. Run: `ClientSetup\Java\Install-Db2-SSL-Support-Java.bat`
2. Use connection string with `securityMechanism=15`
3. No username/password required

### DBeaver Quick Start
1. Run: `ClientSetup\Dbeaver\Install-Db2-SSL-Support-Dbeaver.bat`
2. Create DB2 connection with SSL enabled
3. Set Driver Property: `securityMechanism=15`
4. Leave username/password empty
5. Test connection

### OLE DB Quick Start
1. Run: `ClientSetup\OleDb\Install-Db2-SSL-Support-OleDb.bat`
2. Use connection string with `Security=SSPI;SSL=True`
3. No username/password required

## 🔐 Security Mechanisms Explained

| Mechanism | Description | Best For | Requirements |
|-----------|-------------|----------|-------------|
| `securityMechanism=15` | Windows SSPI | Most scenarios | No additional files |
| `securityMechanism=11` | Kerberos | Complex environments | May need krb5.ini |
| `Security=SSPI` (OLE DB) | Windows SSPI | OLE DB apps | No additional files |
| `Authentication=Kerberos` (OLE DB) | Kerberos | OLE DB with explicit auth | May need krb5.ini |

## 🧪 Testing Your Configuration

### Test SSL Connectivity
```cmd
# Test port connectivity
powershell -Command "Test-NetConnection -ComputerName hostname -Port 50001"
```

### Test Kerberos Tickets
```cmd
# View current Kerberos tickets
klist

# Should show tickets for your domain
```

### Test Connection
```cmd
# Use the generated test script
ClientSetup\Test-Ssl-Connection-From-Client.bat
```

## 🛠️ Behind the Scenes

### How Scripts are Generated
The main batch file calls:
```cmd
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "path\to\output.bat" ^
  -ServerHostname "hostname.DEDGE.fk.no" ^
  -CertFile "path\to\cert.cer" ^
  -Action "add" ^
  -Target "java|dbeaver|oledb" ^
  -Krb5IniPath "path\to\krb5.ini" ^
  -SslPort "50001" ^
  -DatabaseName "FKMVFT" ^
  -DatabasePort "50000"
```

### PowerShell Script Functions
- **Generate-JavaInstallScript**: Creates Java truststore import script
- **Generate-DbeaverInstallScript**: Creates DBeaver-specific import script
- **Generate-OleDbInstallScript**: Creates Windows certificate store import script
- **Generate-*RemoveScript**: Creates corresponding removal scripts

## ⚠️ Important Notes

### General
- **Always leave username/password empty** in client applications
- Your Windows domain credentials are used automatically
- SSL certificate import is required for SSL connections
- Restart applications after certificate import

### DBeaver Specific
- Certificate goes into DBeaver's JRE, not system Java
- Use Driver Properties for security mechanism
- No DBeaver.ini modifications needed

### Java/JDBC Specific
- Certificate goes into system Java truststore
- Affects all Java applications on the system
- Requires IBM DB2 JDBC driver in classpath

### OLE DB Specific
- Certificate goes into Windows certificate store
- Requires IBM DB2 OLE DB Provider installed
- Works with any OLE DB-compatible application

## 🆘 Troubleshooting

### Certificate Issues
```cmd
# Check certificate in Java truststore
keytool -list -keystore "%JAVA_HOME%\lib\security\cacerts" -storepass changeit | findstr hostname

# Check certificate in Windows store
certlm.msc
```

### Connection Issues
1. Verify certificate is imported
2. Check firewall (port 50001 should be open)
3. Verify Kerberos tickets: `klist`
4. Try non-SSL fallback (port 50000)
5. Check application logs

### Script Issues
- Ensure PowerShell execution policy allows scripts
- Run as administrator if needed
- Check file paths in generated scripts

## 🔄 Updating Configuration

If server configuration changes:
1. Run removal scripts first
2. Re-run the main SSL configuration script
3. Run new install scripts
4. Test connections

## 📞 Support

For issues with:
- **Generated scripts**: Check the `Generate-ClientCertificateHandlingScripts.ps1` source
- **SSL configuration**: Review main batch script logs
- **Client connections**: Check client-specific troubleshooting sections above 