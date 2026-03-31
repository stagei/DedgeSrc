db2icrt DB2_2 -s wse
rem prep server for using federated databases
db2 update dbm cfg using FEDERATED YES
db2stop force
db2start
db2 activate db FKMDUM

rem create DRDA wrapper for using federated connections
db2 CREATE WRAPPER DRDA

rem create federation "server"
db2 "CREATE SERVER BASISTST TYPE DB2/LUW VERSION '12.1' WRAPPER DRDA AUTHORIZATION \"db2nt\" PASSWORD \"ntdb2\" OPTIONS (DBNAME 'BASISTST', HOST 't-no1fkmtst-db.DEDGE.fk.no', PORT '3701')"

rem create user mapping - will be used for all tables
CREATE USER MAPPING FOR db2nt SERVER BASISTST OPTIONS (REMOTE_AUTHID 'db2nt', REMOTE_PASSWORD 'ntdb2');

rem create nickname for tables in remote tables
db2 "CREATE NICKNAME DBM.Z_AVDTAB FOR BASISTST.DBM.Z_AVDTAB"