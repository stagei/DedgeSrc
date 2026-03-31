Telemetri service kjører i dag på 
p-no1fkmprd-app på port 8989 
Fra localhost på prod-maskinen:
http://localhost:8989/swagger/index.html



sql server databasene ligger på hhv

t-Dedge-work-dbserver.database.windows.net på port 1433
 
Test: t-Dedge-work-dbserver.database.windows.net, databasenavn t-Dedge-work-db
 
Prod: p-Dedge-work-dbserver.database.windows.net, databasenavn p-Dedge-pos-telemetry
 
Begge steder må brannmuren åpnes i databaseserver-konfigen for de to hostene i Azure...


Jeg foreslår du lager 3 kataloger:
C:\Program Files (x86)\COBNT
C:\Program Files (x86)\DB2CAT
C:\Program Files (x86)\COBVC (For fremtidig Visual Cobol bruk)

Gi full kontroll på filene til dise to gruppene:
DEDGE\ACL_ERPUTV_Utvikling_Full
DEDGE\ACL_Dedge_Servere_Utviklere
