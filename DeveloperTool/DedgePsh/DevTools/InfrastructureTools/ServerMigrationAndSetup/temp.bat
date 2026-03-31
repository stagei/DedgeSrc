set TEMPDB1=FKMPRD
set TEMPDB2=BASISREG
set TEMPDB2=BASISPRO
set TEMPDB4=XFKMPRD

set DB2INSTANCE=DB2
db2 list database Directory
db2 list node Directory
db2 connect to %TEMPDB1%
db2 select current timestamp from sysibm.sysdummy1
IF %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Successfully connected to %TEMPDB1%' -ForegroundColor Green"
    set "DB2_DB_ALIAS2_CONNECTION_SUCCESS=1"
) ELSE (
    powershell -Command "Write-Host 'Failed to connect to %TEMPDB1%' -ForegroundColor Red"
    set "ERROR_COUNT+=1"
)
db2 connect reset

db2 list database Directory
db2 list node Directory
db2 connect to %TEMPDB2%
db2 select current timestamp from sysibm.sysdummy1
IF %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Successfully connected to %TEMPDB2%' -ForegroundColor Green"
    set "DB2_DB_ALIAS2_CONNECTION_SUCCESS=1"
) ELSE (
    powershell -Command "Write-Host 'Failed to connect to %TEMPDB2%' -ForegroundColor Red"
    set "ERROR_COUNT+=1"
)
db2 connect reset

db2 list database Directory
db2 list node Directory
db2 connect to %TEMPDB3%
db2 select current timestamp from sysibm.sysdummy1
IF %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Successfully connected to %TEMPDB2%' -ForegroundColor Green"
    set "DB2_DB_ALIAS2_CONNECTION_SUCCESS=1"
) ELSE (
    powershell -Command "Write-Host 'Failed to connect to %TEMPDB2%' -ForegroundColor Red"
    set "ERROR_COUNT+=1"
)
db2 connect reset

set DB2INSTANCE=DB2FED
db2 list database Directory
db2 list node Directory
db2 connect to %TEMPDB4%
db2 select current timestamp from sysibm.sysdummy1
IF %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Successfully connected to %TEMPDB3%' -ForegroundColor Green"
    set "DB2_DB_ALIAS2_CONNECTION_SUCCESS=1"
) ELSE (
    powershell -Command "Write-Host 'Failed to connect to %TEMPDB3%' -ForegroundColor Red"
    set "ERROR_COUNT+=1"
)
db2 connect reset

set DB2INSTANCE=DB2

