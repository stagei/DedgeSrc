@echo off
REM Synopsis Start
REM This script monitors DB2 performance and identifies resource-consuming processes.
REM Synopsis End

echo ========================================
echo DB2 Performance Monitor
echo ========================================
echo.

REM Get current timestamp
for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set DATE=%%a%%b%%c
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TIME=%%a%%b
set TIMESTAMP=%DATE%_%TIME%

echo Timestamp: %TIMESTAMP%
echo.

REM Check if connected to a database
db2 connect to current >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Not connected to any database.
    echo Please connect to a database first using: db2 connect to DATABASE_NAME
    pause
    exit /b 1
)

echo ========================================
echo 1. Active Applications (Top 10 by CPU)
echo ========================================
db2 "SELECT
    APPLICATION_HANDLE,
    APPLICATION_NAME,
    CLIENT_USERID,
    CLIENT_WRKSTNNAME,
    TOTAL_CPU_TIME,
    TOTAL_ACT_TIME,
    TOTAL_WAIT_TIME,
    TOTAL_RQST_TIME
FROM TABLE(MON_GET_CONNECTION(NULL, -1)) AS T
ORDER BY TOTAL_CPU_TIME DESC
FETCH FIRST 10 ROWS ONLY"

echo.
echo ========================================
echo 2. Applications with Long Wait Times
echo ========================================
db2 "SELECT
    APPLICATION_HANDLE,
    APPLICATION_NAME,
    CLIENT_USERID,
    TOTAL_WAIT_TIME,
    LOCK_WAIT_TIME,
    TOTAL_ACT_TIME
FROM TABLE(MON_GET_CONNECTION(NULL, -1)) AS T
WHERE TOTAL_WAIT_TIME > 0
ORDER BY TOTAL_WAIT_TIME DESC
FETCH FIRST 10 ROWS ONLY"

echo.
echo ========================================
echo 3. Sort Operations (CPU Intensive)
echo ========================================
db2 "SELECT
    APPLICATION_HANDLE,
    APPLICATION_NAME,
    CLIENT_USERID,
    TOTAL_SORTS,
    TOTAL_SORT_TIME,
    TOTAL_SORT_OVERFLOWS
FROM TABLE(MON_GET_CONNECTION(NULL, -1)) AS T
WHERE TOTAL_SORTS > 0
ORDER BY TOTAL_SORT_TIME DESC
FETCH FIRST 10 ROWS ONLY"

echo.
echo ========================================
echo 4. Database Snapshot Summary
echo ========================================
db2 get snapshot for database on current | findstr /i "cpu\|memory\|buffer\|sort\|lock"

echo.
echo ========================================
echo 5. Current Lock Status
echo ========================================
db2 get snapshot for locks on current | findstr /i "lock\|wait\|hold"

echo.
echo ========================================
echo 6. Buffer Pool Usage
echo ========================================
db2 get snapshot for bufferpools on current | findstr /i "buffer\|hit\|read\|write"

echo.
echo ========================================
echo 7. Tablespace I/O Activity
echo ========================================
db2 get snapshot for tablespaces on current | findstr /i "read\|write\|async\|sync"

echo.
echo ========================================
echo Performance monitoring completed.
echo Check the output above for resource-intensive processes.
echo ========================================
pause

