-- DbExplorer Sample SQL Queries
-- These are example queries for testing DB2 connectivity

-- ========================================
-- Basic SELECT Queries
-- ========================================

-- Simple SELECT
SELECT * FROM SYSCAT.TABLES
WHERE TABSCHEMA = 'SYSIBM'
FETCH FIRST 10 ROWS ONLY;

-- SELECT with WHERE clause
SELECT TABSCHEMA, TABNAME, TYPE, STATUS
FROM SYSCAT.TABLES
WHERE TYPE = 'T'
  AND STATUS = 'N'
FETCH FIRST 20 ROWS ONLY;

-- SELECT with JOIN
SELECT T.TABSCHEMA, T.TABNAME, C.COLNAME, C.TYPENAME, C.LENGTH
FROM SYSCAT.TABLES T
INNER JOIN SYSCAT.COLUMNS C
    ON T.TABSCHEMA = C.TABSCHEMA
    AND T.TABNAME = C.TABNAME
WHERE T.TABSCHEMA = 'SYSIBM'
FETCH FIRST 50 ROWS ONLY;

-- ========================================
-- Aggregate Functions
-- ========================================

-- COUNT with GROUP BY
SELECT TABSCHEMA, COUNT(*) AS TABLE_COUNT
FROM SYSCAT.TABLES
WHERE TYPE = 'T'
GROUP BY TABSCHEMA
ORDER BY TABLE_COUNT DESC
FETCH FIRST 10 ROWS ONLY;

-- Multiple aggregates
SELECT 
    TABSCHEMA,
    COUNT(*) AS TABLE_COUNT,
    COUNT(DISTINCT TYPE) AS TYPE_COUNT
FROM SYSCAT.TABLES
GROUP BY TABSCHEMA
FETCH FIRST 20 ROWS ONLY;

-- ========================================
-- Subqueries
-- ========================================

-- Subquery in WHERE clause
SELECT TABNAME, TABSCHEMA
FROM SYSCAT.TABLES
WHERE TABSCHEMA IN (
    SELECT DISTINCT TABSCHEMA
    FROM SYSCAT.TABLES
    WHERE TYPE = 'T'
)
FETCH FIRST 10 ROWS ONLY;

-- ========================================
-- System Catalog Queries
-- ========================================

-- List all schemas
SELECT SCHEMANAME, OWNER, DEFINER, CREATE_TIME
FROM SYSCAT.SCHEMATA
ORDER BY SCHEMANAME
FETCH FIRST 20 ROWS ONLY;

-- List all tables in a schema
SELECT TABNAME, TYPE, STATUS, CARD AS ROW_COUNT
FROM SYSCAT.TABLES
WHERE TABSCHEMA = 'SYSCAT'
ORDER BY TABNAME
FETCH FIRST 20 ROWS ONLY;

-- List columns for a specific table
SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, DEFAULT
FROM SYSCAT.COLUMNS
WHERE TABSCHEMA = 'SYSCAT'
  AND TABNAME = 'TABLES'
ORDER BY COLNO;

-- ========================================
-- Database Information
-- ========================================

-- Get database configuration
SELECT NAME, VALUE, DEFERRED_VALUE
FROM SYSIBMADM.DBCFG
FETCH FIRST 20 ROWS ONLY;

-- Get tablespace information
SELECT TBSPACE, TBSPACETYPE, DATATYPE, PAGESIZE
FROM SYSCAT.TABLESPACES
ORDER BY TBSPACE;

-- ========================================
-- Performance Monitoring
-- ========================================

-- Top tables by size
SELECT 
    TABSCHEMA,
    TABNAME,
    CARD AS ROW_COUNT,
    NPAGES AS NUM_PAGES,
    FPAGES AS FORMATTED_PAGES
FROM SYSCAT.TABLES
WHERE TYPE = 'T'
  AND CARD IS NOT NULL
ORDER BY NPAGES DESC
FETCH FIRST 20 ROWS ONLY;

-- ========================================
-- Date and Time Functions
-- ========================================

-- Current date and time
SELECT 
    CURRENT DATE AS CURRENT_DATE,
    CURRENT TIME AS CURRENT_TIME,
    CURRENT TIMESTAMP AS CURRENT_TIMESTAMP
FROM SYSIBM.SYSDUMMY1;

-- Date calculations
SELECT 
    CURRENT DATE AS TODAY,
    CURRENT DATE - 7 DAYS AS ONE_WEEK_AGO,
    CURRENT DATE + 30 DAYS AS THIRTY_DAYS_FROM_NOW
FROM SYSIBM.SYSDUMMY1;

-- ========================================
-- String Functions
-- ========================================

-- String operations
SELECT 
    'Hello' || ' ' || 'DB2' AS CONCATENATION,
    UPPER('lowercase') AS UPPERCASE,
    LOWER('UPPERCASE') AS LOWERCASE,
    SUBSTR('Database', 1, 4) AS SUBSTRING,
    LENGTH('DB2') AS STRING_LENGTH
FROM SYSIBM.SYSDUMMY1;

-- ========================================
-- Sample INSERT/UPDATE/DELETE
-- (Comment out if you don't have permissions)
-- ========================================

-- Create sample table
-- CREATE TABLE SAMPLE_DATA (
--     ID INTEGER NOT NULL PRIMARY KEY,
--     NAME VARCHAR(100),
--     DESCRIPTION VARCHAR(500),
--     CREATED_DATE DATE,
--     CREATED_TIME TIMESTAMP
-- );

-- Insert sample data
-- INSERT INTO SAMPLE_DATA (ID, NAME, DESCRIPTION, CREATED_DATE, CREATED_TIME)
-- VALUES (1, 'Test Record', 'This is a test record', CURRENT DATE, CURRENT TIMESTAMP);

-- Update sample data
-- UPDATE SAMPLE_DATA
-- SET DESCRIPTION = 'Updated description'
-- WHERE ID = 1;

-- Delete sample data
-- DELETE FROM SAMPLE_DATA
-- WHERE ID = 1;

-- Drop sample table
-- DROP TABLE SAMPLE_DATA;

-- ========================================
-- Transaction Examples
-- (Uncomment to use)
-- ========================================

-- BEGIN TRANSACTION;
-- 
-- INSERT INTO SAMPLE_DATA VALUES (1, 'Record 1', 'Description 1', CURRENT DATE, CURRENT TIMESTAMP);
-- INSERT INTO SAMPLE_DATA VALUES (2, 'Record 2', 'Description 2', CURRENT DATE, CURRENT TIMESTAMP);
-- 
-- COMMIT;

-- or

-- ROLLBACK;

-- ========================================
-- Common Table Expressions (CTE)
-- ========================================

WITH TABLE_STATS AS (
    SELECT 
        TABSCHEMA,
        COUNT(*) AS TABLE_COUNT,
        SUM(CARD) AS TOTAL_ROWS
    FROM SYSCAT.TABLES
    WHERE TYPE = 'T'
      AND CARD IS NOT NULL
    GROUP BY TABSCHEMA
)
SELECT *
FROM TABLE_STATS
WHERE TABLE_COUNT > 0
ORDER BY TOTAL_ROWS DESC
FETCH FIRST 10 ROWS ONLY;

-- ========================================
-- Window Functions
-- ========================================

SELECT 
    TABSCHEMA,
    TABNAME,
    CARD AS ROW_COUNT,
    RANK() OVER (PARTITION BY TABSCHEMA ORDER BY CARD DESC) AS RANK_IN_SCHEMA
FROM SYSCAT.TABLES
WHERE TYPE = 'T'
  AND CARD IS NOT NULL
FETCH FIRST 20 ROWS ONLY;

-- ========================================
-- CASE Statement
-- ========================================

SELECT 
    TABNAME,
    TYPE,
    CASE TYPE
        WHEN 'T' THEN 'Table'
        WHEN 'V' THEN 'View'
        WHEN 'A' THEN 'Alias'
        WHEN 'N' THEN 'Nickname'
        ELSE 'Other'
    END AS TYPE_DESCRIPTION,
    STATUS
FROM SYSCAT.TABLES
WHERE TABSCHEMA = 'SYSCAT'
FETCH FIRST 10 ROWS ONLY;

-- ========================================
-- Null Handling
-- ========================================

SELECT 
    TABNAME,
    COALESCE(REMARKS, 'No remarks') AS REMARKS,
    CARD,
    COALESCE(CARD, 0) AS CARD_WITH_DEFAULT
FROM SYSCAT.TABLES
WHERE TABSCHEMA = 'SYSCAT'
FETCH FIRST 10 ROWS ONLY;

-- ========================================
-- Database Version
-- ========================================

SELECT 
    SERVICE_LEVEL,
    FIXPACK_NUM
FROM TABLE(SYSPROC.ENV_GET_INST_INFO())
AS INSTANCEINFO;

-- ========================================
-- Active Connections
-- ========================================

SELECT 
    APPLICATION_HANDLE,
    CLIENT_APPLNAME,
    CLIENT_WRKSTNNAME,
    STATUS
FROM SYSIBMADM.APPLICATIONS
FETCH FIRST 20 ROWS ONLY;

