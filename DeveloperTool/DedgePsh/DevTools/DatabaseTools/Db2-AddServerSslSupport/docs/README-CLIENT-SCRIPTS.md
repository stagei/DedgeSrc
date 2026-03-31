# DB2 SSL Client Script Generation System

This directory contains scripts for automatically generating DB2 SSL client configuration scripts for different client types.

## 📋 Quick Overview

### Main Components
- `Generate-ClientCertificateHandlingScripts.ps1` - PowerShell script generator
- `Manage-ClientCertificates.ps1` - PowerShell certificate management utility
- `Db2-AddServerSslSupport.bat` - Main SSL server configuration (auto-generates client scripts)
- `Example-GenerateClientScripts.bat` - Manual script generation example

### Client Types Supported
- **Java/JDBC** - System Java truststore
- **DBeaver** - DBeaver JRE truststore  
- **OLE DB** - Windows certificate store

## 🚀 Quick Start

### Automatic Generation (Recommended)
Run the main SSL configuration script which automatically generates all client scripts:
```cmd
Db2-AddServerSslSupport.bat FKMVFT 50000 YourSSLPassword 50001
```

### Manual Generation
Use the example script to generate client scripts manually:
```cmd
Example-GenerateClientScripts.bat
```

## 📁 Generated Output Structure

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

## 🔧 How to Configure Your Client

### For DBeaver Users
1. Run: `ClientSetup\Dbeaver\Install-Db2-SSL-Support-Dbeaver.bat`
2. In DBeaver:
   - Server: `hostname.DEDGE.fk.no`
   - Port: `50001` (SSL)
   - Database: `FKMVFT`
   - Driver Property: `securityMechanism=15`
   - **Leave username/password EMPTY**

### For Java/JDBC Applications
1. Run: `ClientSetup\Java\Install-Db2-SSL-Support-Java.bat`
2. Use connection string:
   ```java
   jdbc:db2://hostname:50001/FKMVFT:securityMechanism=15;sslConnection=true;
   ```

### For OLE DB Applications
1. Run: `ClientSetup\OleDb\Install-Db2-SSL-Support-OleDb.bat`
2. Use connection string:
   ```vb
   Provider=IBMDADB2;Data Source=FKMVFT;Hostname=hostname;Port=50001;Protocol=TCPIP;Security=SSPI;SSL=True;
   ```

## 🛠️ Script Parameters

### Generate-ClientCertificateHandlingScripts.ps1 Parameters
```powershell
-OutputFileName      # Path to generated .bat file
-ServerHostname      # DB2 server hostname
-CertFile           # Path to SSL certificate file
-Action             # "add" or "remove"
-Target             # "java", "dbeaver", or "oledb"
-Krb5IniPath        # Path to krb5.ini (optional)
-SslPort            # SSL port (default: 50001)
-DatabaseName       # Database name (default: FKMVFT)
-DatabasePort       # Standard port (default: 50000)
```

### Example Call
```cmd
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "C:\temp\install-dbeaver-cert.bat" ^
  -ServerHostname "p-no1db-vm02.DEDGE.fk.no" ^
  -CertFile "C:\DB2\ssl\db2-server-cert.cer" ^
  -Action "add" ^
  -Target "dbeaver" ^
  -Krb5IniPath "C:\DB2\kerberos\krb5.ini" ^
  -SslPort "50001" ^
  -DatabaseName "FKMVFT" ^
  -DatabasePort "50000"
```

## 🔐 Security Features

### Windows SSO Support
- Uses your Windows domain credentials automatically
- No username/password required in connection strings
- Supports both Windows SSPI and Kerberos authentication

### SSL Certificate Management
- Automatically imports certificates to appropriate truststore
- Separate scripts for install/remove operations
- PowerShell-based certificate handling with error checking

### Kerberos Configuration
- Automatic krb5.ini installation when available
- Minimal configuration for Windows SSO environments
- Optional - not required for Windows SSPI (securityMechanism=15)

## 📚 Documentation Files

- `CLIENT-CONFIGURATION-GUIDE.md` - Comprehensive configuration guide
- `README-CLIENT-SCRIPTS.md` - This overview file
- Individual script help - Run any .bat file to see usage instructions

## ⚠️ Important Notes

1. **Always leave username/password empty** in client applications
2. **Restart applications** after certificate import
3. **Use securityMechanism=15** for simplest setup (Windows SSPI)
4. **SSL certificate import is required** for SSL connections
5. **Run as administrator** if certificate import fails

## 🧪 Testing

### Connection Test
```cmd
# Test SSL connectivity
powershell -Command "Test-NetConnection -ComputerName hostname -Port 50001"

# Check Kerberos tickets
klist

# Use generated test script
ClientSetup\Test-Ssl-Connection-From-Client.bat
```

### Troubleshooting
- Check certificate import: Use Windows Certificate Manager (`certmgr.msc`)
- Verify Java truststore: Use `keytool -list` command
- Test non-SSL fallback: Use port 50000 instead of 50001
- Check logs in the `Logs\` directory

## 🔄 Updates

When server configuration changes:
1. Run removal scripts first
2. Re-run main SSL configuration script
3. Run new install scripts
4. Test connections

## 📞 Support

For configuration issues, refer to:
- Script-generated error messages
- `CLIENT-CONFIGURATION-GUIDE.md` for detailed instructions
- PowerShell script source code for technical details 