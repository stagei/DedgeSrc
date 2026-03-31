echo ===========================================
echo 300 Creating instance ¤DB2TE_FED_INSTANCE_NAME¤
echo ===========================================
db2icrt ¤DB2TE_FED_INSTANCE_NAME¤ -s wse
SET DB2INSTANCE=¤DB2TE_FED_INSTANCE_NAME¤

echo ===========================================
echo 300 Setting DB2COMM to TCPIP
echo ===========================================
DB2SET DB2COMM=TCPIP

echo ===========================================
echo 300 Setting up DBM CFG for to allow federated databases
echo ===========================================
SET DB2INSTANCE=¤DB2TE_FED_INSTANCE_NAME¤
db2 update dbm cfg using FEDERATED YES

echo ===========================================
echo 300 Setting up DBM CFG
echo ===========================================
db2 update dbm cfg using SYSADM_GROUP "DB2ADMNS"
db2 update dbm cfg using SYSCTRL_GROUP "DB2ADMNS"
db2 update dbm cfg using SYSMAINT_GROUP "DB2ADMNS"
db2 update dbm cfg using SYSMON_GROUP "DB2ADMNS"

echo ===========================================
echo 300 Adding DB2 firewall rule
echo ===========================================

echo Remove existing firewall rule if it exists
netsh advfirewall firewall delete rule localport=¤DB2TE_FED_PORT¤ >nul 2>&1
netsh advfirewall firewall delete rule name="DB2 Remote Access ¤DB2TE_FED_DB_NAME¤" >nul 2>&1
echo Add new firewall rule
netsh advfirewall firewall add rule name="DB2 Remote Access ¤DB2TE_FED_DB_NAME¤" dir=in action=allow protocol=TCP localport=¤DB2TE_FED_PORT¤

echo ===========================================
echo 300 Adding service to services file
echo ===========================================

findstr /C:"¤DB2TE_FED_SVCENAME¤" %SystemRoot%\system32\drivers\etc\services > nul
if errorlevel 1 (
    echo ¤DB2TE_FED_SVCENAME¤        ¤DB2TE_FED_PORT¤/tcp                           #Db2 service name for ¤DB2TE_FED_DB_NAME¤ for NTLM access to ¤DB2TE_ALIAS1_NAME¤>> %SystemRoot%\system32\drivers\etc\services
    echo "Added service ¤DB2TE_FED_SVCENAME¤ to the services file"
)
echo findstr /I /C:"DB2C_" %SystemRoot%\system32\drivers\etc\services
findstr /I /C:"DB2C_" %SystemRoot%\system32\drivers\etc\services

echo.
echo If the services entries are incorrect, please:
echo 1. Open the services file manually: notepad.exe %SystemRoot%\system32\drivers\etc\services
echo 2. Remove any incorrect DB2 service entries
echo 3. Save the file and close notepad
echo 4. Re-run this script to add the correct entries
echo 5. Continue with the rest of the script
echo.

echo Review the services file entries above.  Will auto-continue after 10 seconds, or press Ctrl+C to exit.
timeout /t 10

echo ===========================================
echo 300 Setting SVCENAME
echo ===========================================
db2 update dbm cfg using SVCENAME ¤DB2TE_FED_SVCENAME¤

echo ===========================================
echo 300 Starting DB2 instance ¤DB2TE_FED_INSTANCE_NAME¤
echo ===========================================
db2start

echo ===========================================
echo 300 Creating database ¤DB2TE_FED_DB_NAME¤
echo ===========================================
db2 CREATE DATABASE ¤DB2TE_FED_DB_NAME¤ AUTOMATIC STORAGE YES ON '¤DB2TE_DISK¤' DBPATH ON '¤DB2TE_DISK¤\' USING CODESET IBM-1252 TERRITORY NO

echo ===========================================
echo 300 Catalog TCPIP node ¤DB2TE_FED_NODE¤ on ¤DB2TE_FED_PORT¤
echo ===========================================
db2 catalog tcpip node ¤DB2TE_FED_NODE¤ remote %COMPUTERNAME%.DEDGE.fk.no server ¤DB2TE_FED_PORT¤
db2stop force
db2start
db2 activate database ¤DB2TE_FED_DB_NAME¤

@REM @REM @REM @REM echo ===========================================
@REM echo Setting up DBM CFG for federated databases
@REM echo ===========================================

@REM db2 update dbm cfg using FEDERATED YES
@REM db2stop force
@REM db2start
@REM db2 activate database ¤DB2TE_FED_DB_NAME¤

echo ===========================================
echo 300 Granting DBADM on database to users
echo ===========================================
db2 connect to ¤DB2TE_FED_DB_NAME¤

db2 grant secadm on database to user FKGEISTA
db2 grant dbadm on database to user FKGEISTA
db2 grant dataaccess on database to user FKGEISTA
db2 grant accessctrl on database to user FKGEISTA

db2 grant secadm on database to user FKSVEERI
db2 grant dbadm on database to user FKSVEERI
db2 grant dataaccess on database to user FKSVEERI
db2 grant accessctrl on database to user FKSVEERI

db2 grant secadm on database to user DB2NT
db2 grant dbadm on database to user DB2NT
db2 grant dataaccess on database to user DB2NT
db2 grant accessctrl on database to user DB2NT

db2 grant secadm on database to group DB2ADMNS
db2 grant dbadm on database to group DB2ADMNS
db2 grant dataaccess on database to group DB2ADMNS
db2 grant accessctrl on database to group DB2ADMNS

db2 update dbm cfg using FEDERATED YES

echo ===========================================
echo 300 Resetting connection
echo ===========================================
db2 connect reset
db2stop force
db2start
db2 activate database ¤DB2TE_FED_DB_NAME¤

echo ===========================================
echo 300 Creating DRDA wrapper for using federated connections
echo DRDA = Distributed Relational Database Architecture - IBM protocol for database communication
echo ===========================================
SET DB2INSTANCE=¤DB2TE_FED_INSTANCE_NAME¤
db2 connect to ¤DB2TE_FED_DB_NAME¤
db2 CREATE WRAPPER DRDA

echo ===========================================
echo 300 Creating federation "server"
echo ===========================================
db2 connect to ¤DB2TE_FED_DB_NAME¤
db2 "CREATE SERVER ¤DB2TE_FED_LINK_DB_NAME¤ TYPE DB2/LUW VERSION '12.1' WRAPPER DRDA AUTHORIZATION \"¤DB2TE_FED_LINK_USERNAME¤\" PASSWORD \"¤DB2TE_FED_LINK_PASSWORD¤\" OPTIONS (DBNAME '¤DB2TE_FED_LINK_DB_NAME¤', HOST '%COMPUTERNAME%.DEDGE.fk.no', PORT '¤DB2TE_FED_LINK_PORT¤')"

echo ===========================================
echo 300 Creating user mapping - will be used for all tables
echo ===========================================
db2 connect to ¤DB2TE_FED_DB_NAME¤
db2 "CREATE USER MAPPING FOR ¤DB2TE_FED_LINK_USERNAME¤ SERVER ¤DB2TE_FED_LINK_DB_NAME¤ OPTIONS (REMOTE_AUTHID '¤DB2TE_FED_LINK_USERNAME¤', REMOTE_PASSWORD '¤DB2TE_FED_LINK_PASSWORD¤')"

echo ===========================================
echo 300 Starting offline backup script for database ¤DB2TE_FED_DB_NAME¤
echo ===========================================
set IN_CURR_DB_INSTANCE_NAME=¤DB2TE_FED_INSTANCE_NAME¤
set IN_CURR_DB_NAME=¤DB2TE_FED_DB_NAME¤
set IN_RESTORE_PATH=¤DB2TE_RESTORE_PATH¤
call ¤DB2TE_GEN_FOLDER¤\900_db2_backup_offline.bat %IN_CURR_DB_INSTANCE_NAME% %IN_CURR_DB_NAME% %IN_RESTORE_PATH%

echo ===========================================
echo 300 Dropping existing nicknames for all sql objects in current database ¤DB2TE_DB_NAME¤
echo ===========================================
set IN_CURR_DB_INSTANCE_NAME=¤DB2TE_FED_INSTANCE_NAME¤
set IN_CURR_DB_NAME=¤DB2TE_FED_DB_NAME¤
set IN_WORK_FOLDER=¤DB2TE_GEN_FOLDER¤
call ¤DB2TE_GEN_FOLDER¤\910_db2_drop_existing_nicknames.bat %IN_CURR_DB_INSTANCE_NAME% %IN_CURR_DB_NAME% %IN_WORK_FOLDER%

echo
echo ===========================================
echo 300 Generating nickname for all sql objects in remote database ¤DB2TE_ALIAS1_NAME¤
echo ===========================================
set IN_CURR_DB_INSTANCE_NAME=¤DB2TE_FED_INSTANCE_NAME¤
set IN_CURR_DB_NAME=¤DB2TE_FED_DB_NAME¤
set IN_RMT_DB_INSTANCE_NAME=¤DB2TE_FED_LINK_INSTANCE_NAME¤
set IN_RMT_DB_NAME=¤DB2TE_FED_LINK_DB_NAME¤
set IN_WORK_FOLDER=¤DB2TE_GEN_FOLDER¤
set IN_SQLFILE=310_db2_create_nickname_for_remote_database.sql
set IN_CONNECT_USER=¤DB2TE_FED_LINK_USERNAME¤
set IN_CONNECT_PASSWORD=¤DB2TE_FED_LINK_PASSWORD¤
call ¤DB2TE_GEN_FOLDER¤\920_db2_create_nickname_for_remote_database.bat %IN_CURR_DB_INSTANCE_NAME% %IN_CURR_DB_NAME% %IN_RMT_DB_INSTANCE_NAME% %IN_RMT_DB_NAME% %IN_WORK_FOLDER% %IN_SQLFILE% %IN_CONNECT_USER% %IN_CONNECT_PASSWORD%

echo ===========================================
echo 300 Resetting connection
echo ===========================================
SET DB2INSTANCE=¤DB2TE_INSTANCE_NAME¤
db2 connect reset
db2stop force
db2start
db2 activate database ¤DB2TE_DB_NAME¤

