@echo off
REM Call the main DB2 SSL configuration script with parameters - V3 (Windows SSO)
REM This version is optimized for Windows SSO without keytab dependencies
set DATABASE_NAME=FKAVDNT
set DATABASE_PORT=3710
set SSL_PASSWORD=SslPwd123
set SSL_PORT=3701

call ..\Db2-AddServerSslSupportV2.bat %DATABASE_NAME% %DATABASE_PORT% %SSL_PASSWORD% %SSL_PORT% 