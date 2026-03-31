@echo off
REM ─────────────────────────────────────────────────────────────
REM  send-log.bat — Send a log entry to GenericLogHandler
REM  Uses curl.exe (included in Windows 10/11 and Server 2019+)
REM ─────────────────────────────────────────────────────────────
REM
REM  Usage:
REM    send-log.bat "My log message"
REM    send-log.bat "Job failed" ERROR MyBatchJob
REM    send-log.bat "Step 1 done" INFO NightlySync Started
REM
REM  Arguments:
REM    %1 = Message (required)
REM    %2 = Level   (optional, default: INFO)
REM    %3 = Source  (optional, default: batch-script)
REM    %4 = JobStatus (optional: Started, Completed, Failed)
REM ─────────────────────────────────────────────────────────────

set BASE_URL=http://dedge-server/GenericLogHandler
set ENDPOINT=%BASE_URL%/api/Logs/ingest

if "%~1"=="" (
    echo Usage: send-log.bat "message" [level] [source] [jobStatus]
    echo.
    echo   Levels:  DEBUG, INFO, WARN, ERROR, FATAL
    echo   Example: send-log.bat "Job finished" INFO NightlySync Completed
    exit /b 1
)

set MSG=%~1
set LVL=%~2
set SRC=%~3
set JSTAT=%~4

if "%LVL%"=="" set LVL=INFO
if "%SRC%"=="" set SRC=batch-script

REM Build JSON payload
if "%JSTAT%"=="" (
    set JSON={"message":"%MSG%","level":"%LVL%","source":"%SRC%","computerName":"%COMPUTERNAME%"}
) else (
    set JSON={"message":"%MSG%","level":"%LVL%","source":"%SRC%","computerName":"%COMPUTERNAME%","jobStatus":"%JSTAT%"}
)

REM Send via curl (fire and forget — ignore response)
curl.exe -s -o nul -w "HTTP %%{http_code}" -X POST "%ENDPOINT%" ^
    -H "Content-Type: application/json" ^
    -d "%JSON%"

echo.
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: Failed to send log entry
) else (
    echo Log entry queued
)


REM ─────────────────────────────────────────────────────────────
REM  BATCH EXAMPLE — send multiple entries
REM  Save the JSON to a temp file and POST it:
REM
REM  echo [{"message":"Step 1","level":"INFO","source":"MyJob"},{"message":"Step 2","level":"INFO","source":"MyJob"}] > %TEMP%\logbatch.json
REM  curl.exe -s -X POST "%BASE_URL%/api/Logs/ingest/batch" -H "Content-Type: application/json" -d @%TEMP%\logbatch.json
REM  del %TEMP%\logbatch.json
REM ─────────────────────────────────────────────────────────────
