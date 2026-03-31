# Option : 1. SSL + Windows SSPI (RECOMMENDED): FKAVDNT 20250529 Manual with username, port and other info in dbeaver

## Attempts with [jcc][t4][2030][11211][4.31.10] Error
### Error message
[jcc][t4][2030][11211][4.31.10] A communication error occurred during operations on the connection's underlying socket, socket input stream, 
or socket output stream.  Error location: Reply.fill() - socketInputStream.read (-1).  Message: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target. ERRORCODE=-4499, SQLSTATE=08001
  PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
  PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    unable to find valid certification path to requested target
    unable to find valid certification path to requested target

### Connection keys attempted with different paths and quotes
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation=C:\Program Files\DBeaver\jre\lib\security\cacerts;traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation=C:\\Program Files\\DBeaver\\jre\\lib\\security\\cacerts;traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation=C:\Progra~1\DBeaver\jre\lib\security\cacerts;traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation=C:\\Progra~1\\DBeaver\\jre\\lib\\security\\cacerts;traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation="C:\Progra~1\DBeaver\jre\lib\security\cacerts";traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation="C:\\Progra~1\\DBeaver\\jre\\lib\\security\\cacerts";traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;




## Attempts with [jcc][t4][2043][11550][4.31.10] Error
### Error message
[jcc][t4][2043][11550][4.31.10] Exception java.io.FileNotFoundException: Error opening socket to server t-no1fkmdev-db.DEDGE.fk.no/10.33.103.139 on port 50,050 with message: "C:\Program Files\DBeaver\jre\lib\security\cacerts" (The filename, directory name, or volume label syntax is incorrect). ERRORCODE=-4499, SQLSTATE=08001
  "C:\Program Files\DBeaver\jre\lib\security\cacerts" (The filename, directory name, or volume label syntax is incorrect)
  "C:\Program Files\DBeaver\jre\lib\security\cacerts" (The filename, directory name, or volume label syntax is incorrect)


### Connection keys attempted with different paths and quotes

jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation="C:\Program Files\DBeaver\jre\lib\security\cacerts";traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation="C:\\Program Files\\DBeaver\\jre\\lib\\security\\cacerts";traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation='C:\Program Files\DBeaver\jre\lib\security\cacerts';traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;
jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50050/FKAVDNT:sslTrustStoreLocation='C:\\Program Files\\DBeaver\\jre\\lib\\security\\cacerts';traceDirectory=c:\temp;traceFile=trace;traceFileAppend=false;traceLevel=4087;


## Conclusion 
Does not work.

## Cursor.exe improvement comments

### DBeaver cacerts Location Detection Recommendations

**Problem**: Manual path specification for DBeaver JRE cacerts is error-prone and fails frequently due to:
- Path quoting issues in JDBC connection strings
- DBeaver version-specific JRE locations
- File path syntax errors
- Certificate not being properly imported

**Recommended Solutions for Better DBeaver Certificate Handling:**

1. **Auto-detect DBeaver JRE Location**
   ```batch
   # Script should automatically find DBeaver installation and JRE path
   - Check registry: HKLM\SOFTWARE\DBeaver Corp\DBeaver
   - Check common paths: %LOCALAPPDATA%\DBeaver, %PROGRAMFILES%\DBeaver
   - Detect JRE subdirectory version automatically
   ```

2. **Verify cacerts File Exists Before Import**
   ```batch
   # Always validate the target cacerts file exists
   if not exist "%DBEAVER_JRE_PATH%\lib\security\cacerts" (
       echo ERROR: DBeaver cacerts file not found at expected location
       echo Please verify DBeaver installation
   )
   ```

3. **Use System Java Instead of DBeaver-specific JRE**
   ```batch
   # Alternative: Import to system Java truststore which is more reliable
   keytool -import -trustcacerts -alias db2-ssl-cert ^
           -file "db2-server-cert.cer" ^
           -keystore "%JAVA_HOME%\lib\security\cacerts" ^
           -storepass changeit
   ```

4. **DBeaver Configuration Improvements**
   ```batch
   # Instead of sslTrustStoreLocation in JDBC URL, use:
   # 1. DBeaver.ini JVM parameter approach:
   # -Djavax.net.ssl.trustStore="path\to\cacerts"
   # 2. Copy certificate to Windows cert store for broader compatibility
   ```

5. **Connection String Simplification**
   ```jdbc
   # Recommended approach - avoid manual truststore paths:
   jdbc:db2://server:50050/database:securityMechanism=15;sslConnection=true;
   # Let DBeaver/Java use default truststore after proper certificate import
   ```

6. **Enhanced Script Features Needed**
   - DBeaver version detection and JRE path auto-discovery
   - Backup existing cacerts before modification
   - Verify certificate import success with keytool -list
   - Generate connection string without manual truststore path
   - Provide rollback capability if import fails

# Option : 1. SSL + Windows SSPI (RECOMMENDED): FKAVDNT

## Attempts with 
### Error message
