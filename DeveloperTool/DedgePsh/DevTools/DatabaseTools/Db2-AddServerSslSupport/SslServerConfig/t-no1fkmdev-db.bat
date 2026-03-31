@echo off
REM Call the main DB2 SSL configuration script with parameters - V3 (Windows SSO)
REM This version is optimized for Windows SSO without keytab dependencies
set DATABASE_NAME=FKAVDNT
set DATABASE_PORT=3710
set SSL_PASSWORD=SslPwd123
set SSL_PORT=50050
set SSL_SVCENAME=DB2C_SSL
set FUNCTION=ALL

call ..\Db2-AddServerSslSupport.bat %FUNCTION% %DATABASE_NAME% %DATABASE_PORT% %SSL_PASSWORD% %SSL_PORT% %SSL_SVCENAME%

