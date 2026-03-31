# SSL Certificate Management Scripts

This directory contains PowerShell and batch scripts for managing SSL certificates in Java and DBeaver truststores.

## Files

- `Generate-ClientCertificateHandlingScripts.ps1` - Main PowerShell script that generates certificate management batch files
- `example-usage.cmd` - Interactive batch file demonstrating how to use the PowerShell script
- `README.md` - This documentation file

## Quick Start

1. **Interactive Usage**: Run `example-usage.cmd` and follow the menu prompts
2. **Direct Usage**: Use the command line examples below

## Command Line Usage

### Basic Syntax
```cmd
powershell.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
    -outputFileName "output-script.bat" ^
    -clientConfigDirDbeaver "C:\config\dbeaver" ^
    -serverHostname "your-server.com" ^
    -certFile "C:\path\to\certificate.crt" ^
    -action "add|remove" ^
    -target "java|dbeaver"
```

### Examples

#### 1. Generate Java Certificate Import Script
```cmd
powershell.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
    -outputFileName "import-ssl-cert-to-java.bat" ^
    -clientConfigDirDbeaver "C:\config\dbeaver" ^
    -serverHostname "db2server.example.com" ^
    -certFile "C:\certs\db2server.crt" ^
    -action "add" ^
    -target "java"
```

#### 2. Generate Java Certificate Removal Script
```cmd
powershell.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
    -outputFileName "remove-ssl-cert-from-java.bat" ^
    -clientConfigDirDbeaver "C:\config\dbeaver" ^
    -serverHostname "db2server.example.com" ^
    -certFile "C:\certs\db2server.crt" ^
    -action "remove" ^
    -target "java"
```

#### 3. Generate DBeaver Certificate Import Script
```cmd
powershell.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
    -outputFileName "import-ssl-cert-to-dbeaver.bat" ^
    -clientConfigDirDbeaver "C:\config\dbeaver" ^
    -serverHostname "db2server.example.com" ^
    -certFile "C:\certs\db2server.crt" ^
    -action "add" ^
    -target "dbeaver"
```

#### 4. Generate DBeaver Certificate Removal Script
```cmd
powershell.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
    -outputFileName "remove-ssl-cert-from-dbeaver.bat" ^
    -clientConfigDirDbeaver "C:\config\dbeaver" ^
    -serverHostname "db2server.example.com" ^
    -certFile "C:\certs\db2server.crt" ^
    -action "remove" ^
    -target "dbeaver"
```

## Parameters

| Parameter | Required | Values | Description |
|-----------|----------|---------|-------------|
| `outputFileName` | Yes | Any valid filename | Name of the generated batch file |
| `clientConfigDirDbeaver` | Yes | Directory path | DBeaver configuration directory |
| `serverHostname` | Yes | Hostname/FQDN | Server hostname for certificate alias |
| `certFile` | Yes | File path | Path to the SSL certificate file (.crt, .cer, etc.) |
| `action` | Yes | `add` or `remove` | Whether to import or remove the certificate |
| `target` | Yes | `java` or `dbeaver` | Target JRE (system Java or DBeaver's JRE) |

## How It Works

1. The PowerShell script generates a batch file based on your parameters
2. The generated batch file:
   - Automatically detects the appropriate JRE location
   - Uses `keytool` to manage certificates in the truststore
   - Provides error handling and user feedback
   - Supports both adding and removing certificates

## Prerequisites

- Windows PowerShell
- Java JRE (for system Java operations) or DBeaver (for DBeaver operations)
- SSL certificate file in a supported format (.crt, .cer, .pem)
- Administrator privileges (recommended for modifying system truststores)

## Troubleshooting

- **PowerShell Execution Policy**: If you get execution policy errors, run PowerShell as Administrator and execute: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- **JRE Not Found**: The script will prompt you to manually enter the JRE path if it can't find it automatically
- **Permission Denied**: Run the generated batch file as Administrator when modifying system truststores 