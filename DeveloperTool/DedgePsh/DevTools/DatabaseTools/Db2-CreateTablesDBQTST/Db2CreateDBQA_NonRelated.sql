-- =============================================
-- DBQA Views Management Script
-- Purpose: Creates and manages database views for quality assurance
-- =============================================
-- Dependencies:
-- System Tables/Views Used:
--   SYSCAT.SCHEMATA
--     └─ Used for schema filtering
--   SYSCAT.TABLES
--     └─ Used for table metadata
--   SYSCAT.COLUMNS
--     └─ Used for column definitions
--   SYSCAT.KEYCOLUSE
--     └─ Used for primary key information
--   SYSCAT.REFERENCES
--     └─ Used for foreign key relationships
--   SYSCAT.INDEXES, SYSCAT.INDEXCOLUSE
--     └─ Used for index definitions
--   SYSIBMADM.SNAPLOCK, SYSIBMADM.SNAPAPPL_INFO
--     └─ Used for lock monitoring
-- =============================================

-- Drop all non-DBQA related views first (ignore errors if objects don't exist)
CONNECT TO DBQTST;
-- BEGIN
--   DECLARE CONTINUE HANDLER FOR SQLSTATE '42704' BEGIN END;
  
--   -- Drop views in dependency order
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DROP_DB_CODE';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DB_SET_DATA_CAPTURE_ON';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_OBJECT_LOCK_TERMINATE_SCRIPT';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_ACTIVE_DB_SESSIONS';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_SOURCE';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_COLUMN_REMARK';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_TABLE_REMARK';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_INDEX';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_FOREIGN_KEY';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_COLUMN_INFO';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_DDL_SOURCE_CREATE_TABLE';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_OBJECT_LOCK_INFO';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_SCHEMA_NAME';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_TABLE_DEPENDENCY';
--   EXECUTE IMMEDIATE 'DROP VIEW TV.V_DBQA_PACKAGE_SQL_SOURCE';
-- END;
-- COMMIT;

-- =============================================
-- Schema Management Views
-- =============================================
-- Views for managing and tracking database schemas
CREATE VIEW TV.V_DBQA_SCHEMA_NAME AS
SELECT 
    SCHEMANAME AS SCHEMA_NAME,
    "DEFINER",
    CREATE_TIME
FROM SYSCAT.SCHEMATA 
WHERE SCHEMANAME IN ('FK','FKPROC','LOG','HST','CRM','TV','F0001','TCA','INL','DBM','Dedge');

COMMENT ON TABLE TV.V_DBQA_SCHEMA_NAME IS 'Lists and manages schemas that are part of the application. Provides centralized schema management and tracking.';
COMMENT ON COLUMN TV.V_DBQA_SCHEMA_NAME.SCHEMA_NAME IS 'Name of the database schema';
COMMENT ON COLUMN TV.V_DBQA_SCHEMA_NAME.DEFINER IS 'User who created the schema';
COMMENT ON COLUMN TV.V_DBQA_SCHEMA_NAME.CREATE_TIME IS 'When the schema was created';
COMMIT;

-- =============================================
-- Object Lock Information Views
-- =============================================
-- Views for monitoring database object locks
CREATE VIEW TV.V_DBQA_OBJECT_LOCK_INFO AS
SELECT DISTINCT
    appls.DB_NAME,
    CASE
        WHEN PKG.PKGNAME IS NOT NULL THEN 'PACKAGE'
        WHEN T.TABNAME IS NOT NULL AND T.TYPE = 'T' THEN 'TABLE'
        WHEN T.TABNAME IS NOT NULL AND T.TYPE = 'V' THEN 'VIEW'
        ELSE 'UNKNOWN'
    END AS OBJECT_TYPE,
    l.TABSCHEMA AS OBJECT_SCHEMA_NAME,
    l.TABNAME AS OBJECT_NAME,
    appls.PRIMARY_AUTH_ID AS USER_ID,
    appls.CLIENT_NNAME,
    appls.APPL_NAME,
    CASE
        WHEN UPPER(appls.APPL_NAME) = 'RUNW.EXE' AND UPPER(appls.PRIMARY_AUTH_ID) LIKE 'BUT%' THEN 'Cobol Windows Runtime Store'
        WHEN UPPER(appls.APPL_NAME) = 'RUNW.EXE' AND UPPER(appls.PRIMARY_AUTH_ID) NOT LIKE 'BUT%' THEN 'Cobol Windows Runtime Other'
        WHEN UPPER(appls.APPL_NAME) = 'RUN.EXE' AND (UPPER(appls.CLIENT_NNAME) LIKE 'SFK%' OR UPPER(appls.CLIENT_NNAME) LIKE 'SRV%' OR UPPER(appls.CLIENT_NNAME) LIKE 'P-%')
            AND UPPER(appls.PRIMARY_AUTH_ID) LIKE 'SRV%' THEN 'Cobol Batch Runtime Server'
        WHEN UPPER(appls.APPL_NAME) = 'RUN.EXE' AND (UPPER(appls.CLIENT_NNAME) LIKE 'SFK%' OR UPPER(appls.CLIENT_NNAME) LIKE 'SRV%' OR UPPER(appls.CLIENT_NNAME) LIKE 'P-%')
            AND UPPER(appls.PRIMARY_AUTH_ID) LIKE 'SRV%' THEN 'Cobol Batch Runtime Other'
        WHEN UPPER(appls.APPL_NAME) = 'MCLNETDB.EXE' THEN 'Cobol Wifi Barcode Reader'
        WHEN UPPER(appls.APPL_NAME) = 'CBLXECWS.EXE' THEN 'Cobol GUI Application Extender'
        WHEN UPPER(appls.APPL_NAME) = 'DIAWP-MSDRDACLIENT' THEN 'Azure Data Factory'
        ELSE appls.APPL_NAME
    END AS APPL_NAME_DESCRIPTION,
    L.LOCK_STATUS,
    CASE
        WHEN l.LOCK_STATUS = 'HELD' THEN 'Lock is currently held by the transaction.'
        WHEN l.LOCK_STATUS = 'WAITING' THEN 'Lock request is currently waiting and not yet granted.'
        WHEN l.LOCK_STATUS = 'CONVERTING' THEN 'Lock is being converted to a different lock mode.'
        WHEN l.LOCK_STATUS = 'GRNT' THEN 'Lock has been granted to the transaction.'
        ELSE 'Unknown Lock Status'
    END AS LOCK_STATUS_DESCRIPTION,
    L.LOCK_MODE,
    CASE
        WHEN LOCK_MODE = 'IS' THEN 'Intent Share Lock - Indicates intent to read data with shared access at a higher level.'
        WHEN LOCK_MODE = 'IX' THEN 'Intent Exclusive Lock - Indicates intent to modify data with exclusive access at a higher level.'
        WHEN LOCK_MODE = 'S' THEN 'Share Lock - Allows other transactions to read but not modify the data.'
        WHEN LOCK_MODE = 'U' THEN 'Update Lock - Similar to a shared lock but allows the possibility of being converted to an exclusive lock.'
        WHEN LOCK_MODE = 'X' THEN 'Exclusive Lock - Prevents other transactions from reading or writing the data.'
        WHEN LOCK_MODE = 'SIX' THEN 'Share with Intent Exclusive Lock - Allows shared access but indicates intent to modify specific rows.'
        WHEN LOCK_MODE = 'Z' THEN 'Super Exclusive Lock - Used primarily during certain types of database administration operations.'
        WHEN LOCK_MODE = 'K' THEN 'Next Key Lock - A lock on the next key to prevent phantom reads in serializable isolation levels.'
        WHEN LOCK_MODE = 'N' THEN 'No Lock - Indicates no locking behavior is being applied.'
        ELSE 'Unknown Lock Mode'
    END AS LOCK_MODE_DESCRIPTION,
    L.LOCK_OBJECT_TYPE,
    L.AGENT_ID,
    'CALL SYSPROC.ADMIN_CMD(''FORCE APPLICATION (' || L.AGENT_ID || ')'');' AS TERMINATE_SCRIPT
FROM SYSIBMADM.SNAPAPPL_INFO AS APPLS
JOIN SYSIBMADM.SNAPLOCK L ON APPLS.AGENT_ID = L.AGENT_ID
LEFT OUTER JOIN SYSCAT.PACKAGES PKG ON L.TABSCHEMA = PKG.PKGSCHEMA AND L.TABNAME = PKG.PKGNAME
LEFT OUTER JOIN SYSCAT.TABLES T ON L.TABSCHEMA = T.TABSCHEMA AND L.TABNAME = T.TABNAME
WHERE L.TABNAME <> '' AND L.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME);

COMMENT ON TABLE TV.V_DBQA_OBJECT_LOCK_INFO IS 'Monitors and manages database object locks. Provides detailed information about lock status, type, and resolution options.';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.DB_NAME IS 'Name of the database';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.OBJECT_TYPE IS 'Type of locked object (PACKAGE, TABLE, VIEW)';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.OBJECT_SCHEMA_NAME IS 'Schema of the locked object';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.OBJECT_NAME IS 'Name of the locked object';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.USER_ID IS 'User holding the lock';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.CLIENT_NNAME IS 'Network name of the client machine';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.APPL_NAME IS 'Name of the application holding the lock';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.APPL_NAME_DESCRIPTION IS 'Description of the application holding the lock';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.LOCK_STATUS IS 'Current status of the lock';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.LOCK_STATUS_DESCRIPTION IS 'Detailed description of the lock status';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.LOCK_MODE IS 'Type of lock being held';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.LOCK_MODE_DESCRIPTION IS 'Detailed description of the lock mode';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.LOCK_OBJECT_TYPE IS 'Type of object being locked';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.AGENT_ID IS 'Database agent identifier';
COMMENT ON COLUMN TV.V_DBQA_OBJECT_LOCK_INFO.TERMINATE_SCRIPT IS 'SQL to terminate the locking application';
COMMIT;

-- =============================================
-- Table Statistics Views
-- =============================================
-- Views for managing table statistics and maintenance
CREATE VIEW TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES AS
SELECT
    TABSCHEMA,
    TABNAME,
    Z.STATS_TIME,
    'CALL SYSPROC.ADMIN_CMD(' || x'27' || 'RUNSTATS ON TABLE ' || rtrim(tabschema) || '.' || rtrim(tabname) || 
    ' WITH DISTRIBUTION AND DETAILED INDEXES ALL' || x'27' || ');' AS TEXT
FROM syscat.tables z
WHERE TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
AND type = 'T';

COMMENT ON TABLE TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES IS 'Generates RUNSTATS commands for updating table statistics';
COMMENT ON COLUMN TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES.TABSCHEMA IS 'Schema of the table';
COMMENT ON COLUMN TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES.TABNAME IS 'Name of the table';
COMMENT ON COLUMN TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES.STATS_TIME IS 'When statistics were last updated';
COMMENT ON COLUMN TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES.TEXT IS 'Generated RUNSTATS command';

-- =============================================
-- DDL Generation Views - Table Creation
-- =============================================
-- Views for generating table creation DDL
CREATE VIEW TV.V_DBQA_DDL_SOURCE_CREATE_TABLE AS
SELECT
    X.TABSCHEMA,
    Y.TYPE AS TAB_TYPE,
    Y.REFRESH,
    X.TABNAME,
    1 AS SEQID,
    Y.ALTER_TIME AS LAST_CHANGED_DATETIME,
    Y.DEFINER AS LAST_CHANGE_BY,
    'CREATE_TABLE' AS TYPE,
    VARCHAR(
        'CREATE TABLE ' || trim(X.TABSCHEMA) || '.' || trim(X.TABNAME) || ' (' || CHR(10) || '#COLUMN_INFO#' || CHR(10) || 
        '   ) ' || CHR(10) || CASE WHEN Y.DATACAPTURE = 'Y' THEN '   DATA CAPTURE CHANGES ' ELSE '   ' END || 
        'IN ' || TRIM(Y.TBSPACE) || ';' || CHR(10)
    ) AS TEXT
FROM SYSCAT.COLUMNS X
JOIN SYSCAT.TABLES Y ON X.TABSCHEMA = Y.TABSCHEMA AND X.TABNAME = Y.TABNAME AND Y.TYPE IN ('T')
WHERE X.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
GROUP BY X.TABSCHEMA, Y.TYPE, Y.REFRESH, X.TABNAME, Y.DATACAPTURE, Y.TBSPACE, Y.ALTER_TIME, Y.DEFINER;

COMMENT ON TABLE TV.V_DBQA_DDL_SOURCE_CREATE_TABLE IS 'Generates CREATE TABLE statements for existing tables';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.TABSCHEMA IS 'Schema of the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.TAB_TYPE IS 'Type of table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.REFRESH IS 'Refresh mode for materialized query tables';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.TABNAME IS 'Name of the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.SEQID IS 'Sequence ID for ordering';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.LAST_CHANGED_DATETIME IS 'When the table was last modified';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.LAST_CHANGE_BY IS 'User who last modified the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.TYPE IS 'Type of DDL statement';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_CREATE_TABLE.TEXT IS 'Generated CREATE TABLE statement';
COMMIT;

-- =============================================
-- DDL Generation Views - Column Information
-- =============================================
-- Views for managing column definitions
CREATE VIEW TV.V_DBQA_DDL_SOURCE_COLUMN_INFO AS
SELECT
        X.TABSCHEMA,
        X.TABNAME,
        X.COLNO,
        2 AS SEQID,
        'TABLE_COLUMNS' AS TYPE,
        '"' || X.COLNAME || '"' || ' ' || X.TYPENAME || ' ' || 
        CASE
            WHEN X.TYPENAME = 'INTEGER' THEN ''
            WHEN X.TYPENAME = 'DECIMAL' THEN '(' || X.LENGTH || ',' || TRIM(CHAR(X.SCALE)) || ')'
            WHEN X.TYPENAME = 'TIMESTAMP' THEN '(' || TRIM(CHAR(X.SCALE)) || ')'
            WHEN X.TYPENAME = 'DATE' THEN ''
            ELSE '(' || X.LENGTH || ')'
        END || 
        CASE WHEN X.NULLS = 'N' THEN ' NOT NULL' ELSE '' END ||
        CASE
            WHEN X.DEFAULT IS NOT NULL  
                THEN ' WITH DEFAULT ' || TRIM(X.DEFAULT)
            ELSE ''
        END
        AS TEXT
    FROM SYSCAT.COLUMNS X
    JOIN SYSCAT.TABLES Y 
        ON X.TABSCHEMA = Y.TABSCHEMA 
        AND X.TABNAME = Y.TABNAME 
        AND Y.TYPE IN ('T')
    WHERE X.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME);

COMMENT ON TABLE TV.V_DBQA_DDL_SOURCE_COLUMN_INFO IS 'Provides column definitions for tables';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_COLUMN_INFO.TABSCHEMA IS 'Schema of the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_COLUMN_INFO.TABNAME IS 'Name of the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_COLUMN_INFO.SEQID IS 'Sequence ID for ordering';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_COLUMN_INFO.TYPE IS 'Type of DDL information';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_COLUMN_INFO.TEXT IS 'Generated column definition DDL';
COMMIT;

-- =============================================
-- DDL Generation Views - Primary Keys
-- =============================================
-- Views for managing primary key constraints
CREATE VIEW TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY AS
SELECT
    TABSCHEMA,
    TABNAME,
    2 AS SEQID,
    CONSTNAME,
    'PRIMARY_KEY' AS TYPE,
    VARCHAR(
        'ALTER TABLE ' || TRIM(TABSCHEMA) || '.' || TRIM(TABNAME) || ' ADD PRIMARY KEY (' || 
        LISTAGG(TRIM(COLNAME), ', ') WITHIN GROUP (ORDER BY COLSEQ) || ');'
    ) AS TEXT
FROM SYSCAT.KEYCOLUSE
WHERE TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
GROUP BY TABSCHEMA, TABNAME, CONSTNAME;

COMMENT ON TABLE TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY IS 'Generates DDL statements for primary key constraints. Facilitates schema replication and documentation.';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY.TABSCHEMA IS 'Schema of the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY.TABNAME IS 'Name of the table';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY.SEQID IS 'Sequence ID for ordering';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY.TYPE IS 'Type of DDL information';
COMMENT ON COLUMN TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY.TEXT IS 'Generated column definition DDL';
COMMIT;

-- =============================================
-- DDL Generation Views - Foreign Keys
-- =============================================
-- Views for managing foreign key relationships
CREATE VIEW TV.V_DBQA_DDL_SOURCE_FOREIGN_KEY AS
SELECT
    FK.TABSCHEMA,
    FK.TABNAME,
    3 AS SEQID,
    FK.CONSTNAME,
    'FOREIGN_KEY' AS TYPE,
 VARCHAR(
        'ALTER TABLE ' || TRIM(FK.TABSCHEMA) || '.' || TRIM(FK.TABNAME) || 
        ' ADD CONSTRAINT ' || TRIM(FK.CONSTNAME) || ' FOREIGN KEY (' || 
        RTRIM(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(
                                                    REPLACE(
                                                        REPLACE(
                                                            REPLACE(
                                                                REPLACE(
                                                                    REPLACE(
                                                                        REPLACE(
                                                                            REPLACE(
                                                                                REPLACE(
                                                                                    REPLACE(
                                                                                        REPLACE(
                                                                                            TRIM(FK.FK_COLNAMES),
                                                                                            '  ', ' '
                                                                                        ), '  ', ' '
                                                                                    ), '  ', ' '
                                                                                ), '  ', ' '
                                                                            ), '  ', ' '
                                                                        ), '  ', ' '
                                                                    ), '  ', ' '
                                                                ), '  ', ' '
                                                            ), '  ', ' '
                                                        ), '  ', ' '
                                                    ), '  ', ' '
                                                ), '  ', ' '
                                            ), '  ', ' '
                                        ), '  ', ' '
                                    ), '  ', ' '
                                ), '  ', ' '
                            ), '  ', ' '
                        ), '  ', ' '
                    ), '  ', ' '
                ), ' ', ','
            )
        )
        || ') REFERENCES ' || TRIM(FK.REFTABSCHEMA) || '.' || TRIM(FK.REFTABNAME) || 
        ' (' || 
        RTRIM(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(
                                                    REPLACE(
                                                        REPLACE(
                                                            REPLACE(
                                                                REPLACE(
                                                                    REPLACE(
                                                                        REPLACE(
                                                                            REPLACE(
                                                                                REPLACE(
                                                                                    REPLACE(
                                                                                        REPLACE(
                                                                                            TRIM(FK.PK_COLNAMES),
                                                                                            '  ', ' '
                                                                                        ), '  ', ' '
                                                                                    ), '  ', ' '
                                                                                ), '  ', ' '
                                                                            ), '  ', ' '
                                                                        ), '  ', ' '
                                                                    ), '  ', ' '
                                                                ), '  ', ' '
                                                            ), '  ', ' '
                                                        ), '  ', ' '
                                                    ), '  ', ' '
                                                ), '  ', ' '
                                            ), '  ', ' '
                                        ), '  ', ' '
                                    ), '  ', ' '
                                ), '  ', ' '
                            ), '  ', ' '
                        ), '  ', ' '
                    ), '  ', ' '
                ), ' ', ','
            )
        )
        || ') ' ||
        CASE FK.DELETERULE
            WHEN 'C' THEN ' ON DELETE CASCADE'
            WHEN 'R' THEN ' ON DELETE RESTRICT'
            WHEN 'N' THEN ' ON DELETE SET NULL'
            WHEN 'A' THEN ' ON DELETE NO ACTION'
            ELSE ''
        END ||
        CASE FK.UPDATERULE
            WHEN 'R' THEN ' ON UPDATE RESTRICT'
            WHEN 'C' THEN ' ON UPDATE CASCADE'
            WHEN 'N' THEN ' ON UPDATE SET NULL'
            WHEN 'A' THEN ' ON UPDATE NO ACTION'
            ELSE ''
        END
    ) AS TEXT
FROM
    SYSCAT.REFERENCES FK
WHERE
    TABSCHEMA IN (
        SELECT SCHEMA_NAME
        FROM TV.V_DBQA_SCHEMA_NAME
    );

-- =============================================
-- DDL Generation Views - Indexes
-- =============================================
-- Views for managing database indexes
CREATE VIEW TV.V_DBQA_DDL_SOURCE_INDEX AS
SELECT
		I.TABSCHEMA,
		I.TABNAME,
		4 AS SEQID,
		I.INDNAME AS CONSTNAME,
		I.CREATE_TIME AS LAST_CHANGED_DATETIME,
		I.DEFINER AS LAST_CHANGE_BY,
	MAX(I.CREATE_TIME) AS LAST_ALTER_TIME,
CASE 
    WHEN I.UNIQUERULE = 'P' THEN 'PRIMARY_KEY_INDEX'
    WHEN I.UNIQUERULE = 'U' THEN 'UNIQUE_INDEX'
    WHEN I.INDEXTYPE = 'REF' THEN 'REF_INDEX'
    WHEN I.INDEXTYPE = 'DIM' THEN 'DIMENSION_INDEX'
    ELSE 'INDEX'
END AS TYPE,
VARCHAR(
    'CREATE ' || 
    CASE
        WHEN I.UNIQUERULE IN ('U', 'P') THEN 'UNIQUE '
        ELSE ''
    END || 
    CASE 
        WHEN I.INDEXTYPE = 'REF' THEN 'REF '
        WHEN I.INDEXTYPE = 'DIM' THEN 'DIMENSION '
        ELSE ''
    END ||
    'INDEX ' || TRIM(I.INDSCHEMA) || '.' || TRIM(I.INDNAME) || 
    ' ON ' || TRIM(I.TABSCHEMA) || '.' || TRIM(I.TABNAME) || 
    ' (' || LISTAGG(C.COLNAME || ' ' || CASE
        WHEN C.COLORDER = 'A' THEN 'ASC'
        ELSE 'DESC'
    END,
    ', ') 
    WITHIN GROUP (ORDER BY C.COLSEQ) || ')' ||
    CASE 
        WHEN I.COMPRESSION = 'Y' THEN ' COMPRESSION'
        ELSE ''
    END || 
    CASE 
        WHEN I.MINPCTUSED > 0 THEN ' MINPCTUSED ' || TRIM(CHAR(I.MINPCTUSED))
        ELSE ''
    END || ';'
) AS TEXT
	FROM SYSCAT.INDEXCOLUSE C
	JOIN SYSCAT.INDEXES I ON
		C.INDNAME = I.INDNAME
	WHERE
		I.TABSCHEMA IN (
		SELECT
			SCHEMA_NAME
		FROM
			TV.V_DBQA_SCHEMA_NAME)
	GROUP BY
		I.INDNAME,
		I.INDSCHEMA,
		I.TABSCHEMA,
		I.TABNAME,
		I.INDEXTYPE,
		I.COMPRESSION,
		I.MINPCTUSED,
		I.UNIQUERULE,
		I.CREATE_TIME,
		I.DEFINER;
-- =============================================
-- DDL Generation Views - Table Comments
-- =============================================
-- Views for managing table-level comments
CREATE VIEW TV.V_DBQA_DDL_SOURCE_TABLE_REMARK AS
SELECT
    T.TABSCHEMA,
    T.TABNAME,
    5 AS SEQID,
    '' AS CONSTNAME,
    'TABLE_REMARK' AS TYPE,
    VARCHAR('COMMENT ON TABLE ' || TRIM(T.TABSCHEMA) || '.' || TRIM(T.TABNAME) || ' IS ''' || T.REMARKS || ''';') AS TEXT
FROM SYSCAT.TABLES T
WHERE T.REMARKS IS NOT NULL AND TRIM(T.REMARKS) <> ''
AND T.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME);

-- =============================================
-- DDL Generation Views - Column Comments
-- =============================================
-- Views for managing column-level comments
CREATE VIEW TV.V_DBQA_DDL_SOURCE_COLUMN_REMARK AS
SELECT
    C.TABSCHEMA,
    C.TABNAME,
    6 AS SEQID,
    C.COLNAME AS CONSTNAME,
    'COLUMN_REMARK' AS TYPE,
    VARCHAR('COMMENT ON COLUMN ' || TRIM(C.TABSCHEMA) || '.' || TRIM(C.TABNAME) || '.' || 
           C.COLNAME || ' IS ''' || C.REMARKS || ''';') AS TEXT
FROM SYSCAT.COLUMNS C
WHERE C.REMARKS IS NOT NULL AND TRIM(C.REMARKS) <> ''
AND C.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME);
COMMIT;

-- =============================================
-- Source Code Management Views
-- =============================================
-- Views for managing database object source code
CREATE VIEW TV.V_DBQA_SOURCE AS
SELECT x.*,
    CASE
        WHEN TRIM(SCHEMA) = 'FK' THEN 1
        WHEN TRIM(SCHEMA) = 'FKPROC' THEN 2
        WHEN TRIM(SCHEMA) = 'TV' THEN 3
        ELSE 4
    END AS SCHEMA_PRI,
    CASE
        WHEN TRIM(TYPE) = 'FUNCTION' THEN 1
        WHEN TRIM(TYPE) = 'MQT' THEN 2
        WHEN TRIM(TYPE) = 'PROCEDURE' THEN 3
        WHEN TRIM(TYPE) = 'TRIGGER' THEN 4
        WHEN TRIM(TYPE) = 'VIEW' THEN 5
        ELSE 3
    END AS TYPE_PRI
FROM (
    SELECT
        CASE WHEN ROUTINETYPE = 'P' THEN 'PROCEDURE' ELSE 'FUNCTION' END AS TYPE,
        'SYSCAT.ROUTINES' AS SOURCE,
        ROUTINESCHEMA AS SCHEMA,
        ROUTINENAME AS NAME,        
        CASE
            WHEN ROUTINETYPE = 'P' THEN TRIM(X.ROUTINESCHEMA) || '.' || X.ROUTINENAME || CASE WHEN (SELECT COUNT(*) FROM SYSCAT.ROUTINES Y WHERE X.ROUTINESCHEMA = Y.ROUTINESCHEMA AND X.ROUTINENAME = Y.ROUTINENAME) > 1        THEN '_PARAM_COUNT_' || TRIM(CHAR(X.PARM_COUNT))        ELSE ''        END ||'.PRC.DDL.SQL'
            ELSE TRIM(X.ROUTINESCHEMA) || '.' || X.ROUTINENAME || '.FNC.DDL.SQL'
        END AS FILENAME,
        CASE
            WHEN ROUTINETYPE = 'P' THEN 'PRC'
            ELSE 'FNC'
        END AS SOURCE_TYPE,
        
        "DEFINER" AS LAST_CHANGE_BY,
        CASE
            WHEN X.CREATE_TIME < X.LAST_REGEN_TIME THEN LAST_REGEN_TIME
            ELSE X.CREATE_TIME
        END AS LAST_CHANGED_DATETIME,
        TEXT
    FROM SYSCAT.ROUTINES X
    WHERE X.ROUTINESCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
    AND X."LANGUAGE" = 'SQL' AND X.ROUTINETYPE IN ('P', 'F')
    UNION ALL
    
    SELECT
        'VIEW' AS TYPE,
        'SYSCAT.VIEWS' AS SOURCE,
        V.VIEWSCHEMA AS SCHEMA,
        V.VIEWNAME AS NAME,
        TRIM(V.VIEWSCHEMA) || '.' || V.VIEWNAME || '.VW.DDL.SQL' AS FILENAME,
        'VW' AS SOURCE_TYPE,
        V."DEFINER" AS LAST_CHANGE_BY,
        T.ALTER_TIME AS LAST_CHANGED_DATETIME,
        V.TEXT
    FROM SYSCAT.TABLES T 
    JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
    WHERE T.TYPE = 'V' AND T.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
    
    UNION ALL
    
    SELECT
        'MQT' AS TYPE,
        'SYSCAT.VIEWS' AS SOURCE,
        V.VIEWSCHEMA AS SCHEMA,
        V.VIEWNAME AS NAME,
        TRIM(V.VIEWSCHEMA) || '.' || V.VIEWNAME || '.MQT.DDL.SQL' AS FILENAME,
        'MQT' AS SOURCE_TYPE,
        V."DEFINER" AS LAST_CHANGE_BY,
        T.ALTER_TIME AS LAST_CHANGED_DATETIME,
        V.TEXT
    FROM SYSCAT.TABLES T 
    JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
    WHERE T.TYPE = 'S' AND T.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)    
    UNION ALL    
    SELECT
        'TRIGGER' AS TYPE,
        'SYSCAT.TRIGGERS' AS SOURCE,
        T.TRIGSCHEMA AS SCHEMA,
        T.TRIGNAME AS NAME,
        TRIM(TRIGSCHEMA) || '.' || TRIM(TABNAME) || '.' || TRIGNAME || '.TRG.DDL.SQL' AS FILENAME,
        TRIM(TRIGSCHEMA) || '.' || TRIM(TABNAME) || '.' || TRIGNAME || '.TRG.DDL.SQL' AS SOURCE_TYPE,
        "DEFINER" AS LAST_CHANGE_BY,
        CASE WHEN CREATE_TIME < LAST_REGEN_TIME THEN LAST_REGEN_TIME ELSE CREATE_TIME END AS LAST_CHANGED_DATETIME,
        TEXT
    FROM SYSCAT.TRIGGERS T
    WHERE TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
) x;

COMMENT ON TABLE TV.V_DBQA_SOURCE IS 'Manages database object source code';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.TYPE IS 'Type of database object';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.SOURCE IS 'Source catalog table';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.SCHEMA IS 'Schema of the object';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.NAME IS 'Name of the object';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.FILENAME IS 'Generated filename for source code';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.LAST_CHANGE_BY IS 'User who last modified the object';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.LAST_CHANGED_DATETIME IS 'When the object was last modified';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.TEXT IS 'Source code content';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.SCHEMA_PRI IS 'Schema priority for ordering';
COMMENT ON COLUMN TV.V_DBQA_SOURCE.TYPE_PRI IS 'Object type priority for ordering';

GRANT SELECT ON TABLE TV.V_DBQA_SOURCE TO PUBLIC;
COMMIT;

-- =============================================
-- Active Session Management Views
-- =============================================
-- Views for monitoring active database sessions
CREATE VIEW TV.V_DBQA_ACTIVE_DB_SESSIONS AS
SELECT
    APPLICATION_HANDLE,
    APPLICATION_NAME,
    CLIENT_HOSTNAME,
    CLIENT_PORT_NUMBER,
    SYSTEM_AUTH_ID,
    SESSION_AUTH_ID,
    CONNECTION_START_TIME
FROM TABLE (MON_GET_CONNECTION (cast(NULL as bigint), -2));

COMMENT ON TABLE TV.V_DBQA_ACTIVE_DB_SESSIONS IS 'Shows currently active database sessions';
COMMENT ON COLUMN TV.V_DBQA_ACTIVE_DB_SESSIONS.APPLICATION_HANDLE IS 'Unique identifier for the application';
COMMENT ON COLUMN TV.V_DBQA_ACTIVE_DB_SESSIONS.APPLICATION_NAME IS 'Name of the connected application';
COMMENT ON COLUMN TV.V_DBQA_ACTIVE_DB_SESSIONS.CLIENT_HOSTNAME IS 'Hostname of the client machine';
COMMENT ON COLUMN TV.V_DBQA_ACTIVE_DB_SESSIONS.SYSTEM_AUTH_ID IS 'System authorization ID';
COMMENT ON COLUMN TV.V_DBQA_ACTIVE_DB_SESSIONS.SESSION_AUTH_ID IS 'Session authorization ID';
COMMENT ON COLUMN TV.V_DBQA_ACTIVE_DB_SESSIONS.CONNECTION_START_TIME IS 'When the connection was established';

-- =============================================
-- Table Dependency Views
-- =============================================
-- Views for analyzing table dependencies
CREATE VIEW TV.V_DBQA_TABLE_DEPENDENCY AS 
SELECT DISTINCT 
    TABSCHEMA AS DEPENDENCY_SCHEMA_NAME, 
    TABNAME AS DEPENDENCY_TABLE_NAME, 
    DTYPE AS DEPENDENCY_TYPE, 
    OWNER, 
    OWNERTYPE, 
    BTYPE AS REFERENCE_TYPE, 
    BSCHEMA AS REFERENCE_SCHEMA_NAME, 
    BMODULENAME AS REFERENCE_MODULE_NAME, 
    BNAME AS REFERENCE_OBJECT_NAME, 
    BMODULEID AS REFERENCE_MODULE_ID, 
    TABAUTH, 
    VARAUTH, 
    "DEFINER"
FROM SYSCAT.TABDEP A  
WHERE BSCHEMA IN (SELECT schema_name FROM TV.V_DBQA_SCHEMA_NAME B)
OR TABSCHEMA IN (SELECT schema_name FROM TV.V_DBQA_SCHEMA_NAME B);

COMMENT ON TABLE TV.V_DBQA_TABLE_DEPENDENCY IS 'Shows dependencies between database objects';
COMMENT ON COLUMN TV.V_DBQA_TABLE_DEPENDENCY.DEPENDENCY_SCHEMA_NAME IS 'Schema of the dependent object';
COMMENT ON COLUMN TV.V_DBQA_TABLE_DEPENDENCY.DEPENDENCY_TABLE_NAME IS 'Name of the dependent object';
COMMENT ON COLUMN TV.V_DBQA_TABLE_DEPENDENCY.DEPENDENCY_TYPE IS 'Type of dependency';
COMMENT ON COLUMN TV.V_DBQA_TABLE_DEPENDENCY.REFERENCE_TYPE IS 'Type of referenced object';
COMMENT ON COLUMN TV.V_DBQA_TABLE_DEPENDENCY.REFERENCE_SCHEMA_NAME IS 'Schema of referenced object';
COMMENT ON COLUMN TV.V_DBQA_TABLE_DEPENDENCY.REFERENCE_OBJECT_NAME IS 'Name of referenced object';

-- Grant permissions
GRANT SELECT ON TV.V_DBQA_SCHEMA_NAME TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_OBJECT_LOCK_INFO TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_UPDATE_STATISTICS_ON_TABLES TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_CREATE_TABLE TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_COLUMN_INFO TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_ACTIVE_DB_SESSIONS TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_TABLE_DEPENDENCY TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_PRIMARY_KEY TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_FOREIGN_KEY TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_INDEX TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_TABLE_REMARK TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_DDL_SOURCE_COLUMN_REMARK TO PUBLIC;
GRANT SELECT ON TV.V_DBQA_SOURCE TO PUBLIC;

COMMIT; 

-- =============================================
-- Package SQL Analysis Views
-- =============================================
-- Views for analyzing package SQL statements
CREATE VIEW TV.V_DBQA_PACKAGE_SQL_SOURCE AS
SELECT
  z.PKGSCHEMA,
  z.PKGNAME,
  z.LASTUSED,
  x.TEXT
FROM
  SYSCAT.STATEMENTS x
  JOIN SYSCAT.PACKAGES z ON x.PKGSCHEMA = z.PKGSCHEMA
  JOIN TV.V_DBQA_SCHEMA_NAME v ON x.PKGSCHEMA = v.SCHEMA_NAME 
  AND x.PKGNAME = z.PKGNAME
WHERE
  z.LASTUSED > CURRENT DATE - 3 YEARS;
  
COMMENT ON TABLE TV.V_DBQA_PACKAGE_SQL_SOURCE IS 'Shows SQL statements from recently used packages';
COMMENT ON COLUMN TV.V_DBQA_PACKAGE_SQL_SOURCE.PKGSCHEMA IS 'Schema of the package';
COMMENT ON COLUMN TV.V_DBQA_PACKAGE_SQL_SOURCE.PKGNAME IS 'Name of the package';
COMMENT ON COLUMN TV.V_DBQA_PACKAGE_SQL_SOURCE.LASTUSED IS 'When the package was last used';
COMMENT ON COLUMN TV.V_DBQA_PACKAGE_SQL_SOURCE.TEXT IS 'SQL statement text';

GRANT SELECT ON TABLE TV.V_DBQA_PACKAGE_SQL_SOURCE TO PUBLIC;

COMMIT;

-- =============================================
-- Lock Termination Views - Group Level
-- =============================================
-- Views for managing group-level lock termination
CREATE VIEW TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT AS
SELECT
  L.DB_NAME,
  L.OBJECT_TYPE,
  L.OBJECT_SCHEMA_NAME,
  L.APPL_NAME_DESCRIPTION,
  'CALL SYSPROC.ADMIN_CMD(''FORCE APPLICATION (' || LISTAGG(DISTINCT L.AGENT_ID, ', ') || ''');' AS TERMINATE_SCRIPT
FROM
  (
    SELECT
      DB_NAME,
      OBJECT_TYPE,
      OBJECT_SCHEMA_NAME,
      APPL_NAME_DESCRIPTION,
      AGENT_ID
    FROM
      TV.V_DBQA_OBJECT_LOCK_INFO
    WHERE
      LOCK_MODE IN ('S', 'U', 'X', 'IX', 'SIX')
    GROUP BY
      DB_NAME,
      OBJECT_TYPE,
      OBJECT_SCHEMA_NAME,
      APPL_NAME_DESCRIPTION,
      AGENT_ID
      UNION 
    SELECT
      DB_NAME,
      OBJECT_TYPE,
      OBJECT_SCHEMA_NAME,
      '*** ALL USERS ***' AS APPL_NAME_DESCRIPTION,
      AGENT_ID
    FROM
      TV.V_DBQA_OBJECT_LOCK_INFO
    GROUP BY
      DB_NAME,
      OBJECT_TYPE,
      OBJECT_SCHEMA_NAME,
      APPL_NAME_DESCRIPTION,
      AGENT_ID
  ) L
GROUP BY
  L.DB_NAME,
  L.OBJECT_TYPE,
  L.OBJECT_SCHEMA_NAME,
  L.APPL_NAME_DESCRIPTION;

COMMENT ON TABLE TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT IS 'Generates scripts to terminate grouped locks';
COMMENT ON COLUMN TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT.DB_NAME IS 'Name of the database';
COMMENT ON COLUMN TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT.OBJECT_TYPE IS 'Type of locked object';
COMMENT ON COLUMN TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT.OBJECT_SCHEMA_NAME IS 'Schema of locked object';
COMMENT ON COLUMN TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT.APPL_NAME_DESCRIPTION IS 'Description of locking application';
COMMENT ON COLUMN TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT.TERMINATE_SCRIPT IS 'Generated script to terminate locks';

GRANT SELECT ON TABLE TV.V_DBQA_GROUP_LOCK_TERMINATE_SCRIPT TO PUBLIC;

COMMIT;

-- =============================================
-- Lock Termination Views - Object Level
-- =============================================
-- Views for managing object-level lock termination
CREATE VIEW TV.V_DBQA_OBJECT_LOCK_TERMINATE_SCRIPT AS
SELECT
  L.DB_NAME,
  L.OBJECT_TYPE,
  L.OBJECT_SCHEMA_NAME,
  L.OBJECT_NAME,
  'CALL SYSPROC.ADMIN_CMD(''FORCE APPLICATION (' || LISTAGG(DISTINCT L.AGENT_ID, ', ') || ')'');' AS TERMINATE_SCRIPT
FROM
  (
    SELECT
      DB_NAME,
      OBJECT_TYPE,
      OBJECT_SCHEMA_NAME,
      OBJECT_NAME,
      AGENT_ID
    FROM
      TV.V_DBQA_OBJECT_LOCK_INFO
    WHERE
      LOCK_MODE IN ('S', 'U', 'X', 'IX', 'SIX')
    GROUP BY
      DB_NAME,
      OBJECT_TYPE,
      OBJECT_SCHEMA_NAME,
      OBJECT_NAME,
      AGENT_ID
  ) L
GROUP BY
  L.DB_NAME,
  L.OBJECT_TYPE,
  L.OBJECT_SCHEMA_NAME,
  L.OBJECT_NAME;

GRANT
SELECT
  ON TABLE TV.V_DBQA_OBJECT_LOCK_TERMINATE_SCRIPT TO PUBLIC;

COMMIT;

-- =============================================
-- Database Object Management Views
-- =============================================
-- Views for managing database object lifecycle
CREATE VIEW TV.V_DBQA_DROP_DB_CODE AS
SELECT
  ROUTINESCHEMA AS schema_name,
  ROUTINENAME AS object_name,
  SPECIFICNAME,
  'FUNCTION' AS object_type,
  'DROP SPECIFIC FUNCTION ' || trim(ROUTINESCHEMA) || '.' || SPECIFICNAME || ';' AS DROP_STATEMENT
FROM
  SYSCAT.ROUTINES
WHERE
  trim(ROUTINESCHEMA) IN (
    SELECT
      SCHEMA_NAME
    FROM
      tv.V_DBQA_SCHEMA_NAME
  )
UNION ALL
SELECT
  TRIGSCHEMA AS schema_name,
  TRIGNAME AS object_name,
  '' AS SPECIFICNAME,
  'TRIGGER' AS object_type,
  'DROP TRIGGER ' || trim(TRIGSCHEMA) || '.' || trim(TRIGNAME) || ';' AS drop_statement
FROM
  SYSCAT.TRIGGERS
WHERE
  trim(TRIGSCHEMA) IN (
    SELECT
      SCHEMA_NAME
    FROM
      tv.V_DBQA_SCHEMA_NAME
  )
UNION ALL
SELECT
  VIEWSCHEMA AS schema_name,
  VIEWNAME AS object_name,
  '' AS SPECIFICNAME,  
  'VIEW' AS object_type,
  'DROP VIEW ' || trim(VIEWSCHEMA) || '.' || trim(VIEWNAME) || ';' AS drop_statement
FROM
SYSCAT.TABLES T JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME 
WHERE
  T.TYPE = 'V' AND 
  T.TABSCHEMA IN (SELECT SCHEMA_NAME FROM TV.V_DBQA_SCHEMA_NAME)
  AND T.TABNAME = 'DREG20V_SUM1'
UNION ALL
SELECT
  TABSCHEMA AS schema_name,
  TABNAME AS object_name,
  '' AS SPECIFICNAME, 
  'MQT' AS object_type,
  'DROP TABLE ' || trim(TABSCHEMA) || '.' || trim(TABNAME) || ';' AS drop_statement
FROM
  SYSCAT.TABLES
WHERE
  TYPE = 'S' 
  AND trim(TABSCHEMA) IN (
    SELECT
      SCHEMA_NAME
    FROM
      tv.V_DBQA_SCHEMA_NAME
  );

COMMENT ON TABLE TV.V_DBQA_DROP_DB_CODE IS 'Generates drop statements for database objects';
COMMENT ON COLUMN TV.V_DBQA_DROP_DB_CODE.SCHEMA_NAME IS 'Schema of the object';
COMMENT ON COLUMN TV.V_DBQA_DROP_DB_CODE.OBJECT_NAME IS 'Name of the object';
COMMENT ON COLUMN TV.V_DBQA_DROP_DB_CODE.SPECIFICNAME IS 'Specific name for functions';
COMMENT ON COLUMN TV.V_DBQA_DROP_DB_CODE.OBJECT_TYPE IS 'Type of database object';
COMMENT ON COLUMN TV.V_DBQA_DROP_DB_CODE.DROP_STATEMENT IS 'Generated drop statement';

GRANT SELECT ON TABLE TV.V_DBQA_DROP_DB_CODE TO PUBLIC;

COMMIT;

-- =============================================
-- Data Capture Configuration Views
-- =============================================
-- Views for managing data capture settings
CREATE VIEW TV.V_DBQA_DB_SET_DATA_CAPTURE_ON AS
SELECT
  *
FROM
  (
    SELECT
      Y.TABSCHEMA,
      Y.TABNAME,
      Y.DATACAPTURE,
      CASE Y.DATACAPTURE
        WHEN 'N' THEN 'No data capture'
        WHEN 'Y' THEN 'Data capture enabled for changes'
        WHEN 'L' THEN 'Data capture for load'
        ELSE 'Unknown value'
      END AS DATACAPTURE_DESCRIPTION,
      VARCHAR(CASE Y.DATACAPTURE
        WHEN 'Y' THEN ''
        ELSE 
        'ALTER TABLE ' || trim(Y.TABSCHEMA) || '.' || trim(Y.TABNAME) || '  DATA CAPTURE CHANGES;'
      END )     
       AS SQL_SCRIPT
    FROM
      SYSCAT.TABLES Y
    WHERE
      Y.TYPE = 'T'
      AND Y.TABSCHEMA IN (SELECT TRIM(SCHEMA_NAME) FROM TV.V_DBQA_SCHEMA_NAME)
    ORDER BY
      DATACAPTURE
  ) x;
  
  
GRANT SELECT ON TABLE TV.V_DBQA_DB_SET_DATA_CAPTURE_ON TO PUBLIC;

COMMIT;


-- =============================================
-- Create Nickname for federated database view
-- =============================================
-- View for creating nickname template for federated databases
CREATE VIEW TV.V_DBQA_CREATE_NICKNAME_TEMPLATE AS
 SELECT
	x.*,
	'db2 "CREATE NICKNAME ' || trim(X.SCHEMA) || '.' || trim(X.NAME) || ' FOR ¤DB2DATABASE_NAME¤.' || trim(X.SCHEMA) || '.' || trim(X.NAME) || '"' AS FEDERATED_NICKNAME_DATABASE_NAME,
	'db2 "CREATE NICKNAME ' || trim(X.SCHEMA) || '.' || trim(X.NAME) || ' FOR ¤DB2DATABASE_ALIAS1_NAME¤.' || trim(X.SCHEMA) || '.' || trim(X.NAME) || '"' AS FEDERATED_NICKNAME_ALIAS_NAME_1,	
	'db2 "CREATE NICKNAME ' || trim(X.SCHEMA) || '.' || trim(X.NAME) || ' FOR ¤DB2DATABASE_ALIAS2_NAME¤.' || trim(X.SCHEMA) || '.' || trim(X.NAME) || '"' AS FEDERATED_NICKNAME_ALIAS_NAME_2
FROM
	(
	SELECT
		CASE
			WHEN ROUTINETYPE = 'P' THEN 'PROCEDURE'
			ELSE 'FUNCTION'
		END AS TYPE,
		'SYSCAT.ROUTINES' AS SOURCE,
		ROUTINESCHEMA AS SCHEMA,
		ROUTINENAME AS NAME,
		CASE
			WHEN ROUTINETYPE = 'P' THEN 'PRC'
			ELSE 'FNC'
		END AS SOURCE_TYPE,
		"DEFINER" AS LAST_CHANGE_BY,
		CASE
			WHEN X.CREATE_TIME < X.LAST_REGEN_TIME THEN LAST_REGEN_TIME
			ELSE X.CREATE_TIME
		END AS LAST_CHANGED_DATETIME
	FROM
		SYSCAT.ROUTINES X
	WHERE
		X.ROUTINESCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC')
		AND X."LANGUAGE" = 'SQL'
		AND X.ROUTINETYPE IN ('P', 'F')
UNION ALL
SELECT
	X.TYPE AS TYPE,
	'SYSCAT.TABLES' AS SOURCE,
	X.TABSCHEMA AS SCHEMA,
	X.TABNAME AS NAME,
		    CASE X."TYPE"
        WHEN 'A' THEN 'Alias'
        WHEN 'G' THEN 'Created temporary table'
        WHEN 'H' THEN 'Hierarchy table'
        WHEN 'L' THEN 'Detached table'
        WHEN 'N' THEN 'Nickname'
        WHEN 'S' THEN 'Materialized query table'
        WHEN 'T' THEN 'Table (untyped)'
        WHEN 'U' THEN 'Typed table'
        WHEN 'V' THEN 'View (untyped)'
        WHEN 'W' THEN 'Typed view'
        ELSE 'Unknown type'
    END AS SOURCE_TYPE,
	X."DEFINER" AS LAST_CHANGE_BY,
	X.ALTER_TIME AS LAST_CHANGED_DATETIME
FROM
    SYSCAT.TABLES X
WHERE
    X.TYPE NOT IN ('V','T')
    AND X.TABSCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC')
UNION ALL
	SELECT
		'TRIGGER' AS TYPE,
		'SYSCAT.TRIGGERS' AS SOURCE,
		T.TRIGSCHEMA AS SCHEMA,
		T.TRIGNAME AS NAME,
		'TRG' AS SOURCE_TYPE,
		"DEFINER" AS LAST_CHANGE_BY,
		CASE
			WHEN CREATE_TIME < LAST_REGEN_TIME THEN LAST_REGEN_TIME
			ELSE CREATE_TIME
		END AS LAST_CHANGED_DATETIME
	FROM
		SYSCAT.TRIGGERS T
	WHERE
		TABSCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC')
) X;

GRANT SELECT ON TABLE TV.V_DBQA_CREATE_NICKNAME_TEMPLATE TO PUBLIC;

COMMIT;




