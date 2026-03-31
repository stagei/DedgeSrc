@echo off
REM Call the main DB2 SSL configuration script with parameters
set DATABASE_NAME=FKAVDNT
set DATABASE_PORT=3710
set SSL_PASSWORD=SslPwd123
set SSL_PORT=3701

call ..\Db2-AddServerSslSupport.bat %DATABASE_NAME% %DATABASE_PORT% %SSL_PASSWORD% %SSL_PORT%
