db2 uncatalog database FKDBQA
db2 uncatalog system odbc data source FKDBQA
db2 uncatalog node FKDBQA
db2 update cli cfg for section COMMON using CLNT_KRB_PLUGIN NULL

takeown /f "C:\Windows\Logs\krb5" /r /d y
takeown /f "C:\Windows\krb5.ini" /r /d y
takeown /f "C:\Windows\Logs\krb5kdc.log" /r /d y

takeown /f "C:\ProgramData\IBM\DB2\DB2COPY1\cfg\jaas.conf" /r /d y

del C:\ProgramData\IBM\DB2\DB2COPY1\cfg\jaas.conf /f /s /q
del C:\Windows\krb5.ini /f /s /q
del C:\Windows\Logs\krb5\kdc.log /f /s /q
del C:\Windows\Logs\krb5\kadmin.log /f /s /q
del C:\Windows\Logs\krb5\krb5lib.log /f /s /q
rd C:\Windows\Logs\krb5 /s /q

db2 list database directory
db2 list node directory
db2 get cli cfg for section COMMON | findstr "KRB"

