@echo off
REM Simple DB2 Menu for Current db2cmd.exe Session
REM Dedge - Database Management Tool

setlocal enabledelayedexpansion

:main_menu
cls
echo ╔═══════════════════════════════════════════════════════════════╗
echo ║              Simple DB2 Menu - Dedge             ║
echo ║                Current db2cmd.exe Session                    ║
echo ╚═══════════════════════════════════════════════════════════════╝
echo.
echo Current DB2INSTANCE: %DB2INSTANCE%
echo.
echo ┌─ Instance Management ─────────────────────────────────────────┐
echo │  1. Set DB2INSTANCE to DB2                                    │
echo │  2. Set DB2INSTANCE to DB2FED                                 │
echo │  3. Set DB2INSTANCE to DB2A                                   │
echo │  4. Set DB2INSTANCE to DB2T                                   │
echo └───────────────────────────────────────────────────────────────┘
echo.
echo ┌─ Database Operations ─────────────────────────────────────────┐
echo │  5. Get Current Instance Info                                 │
echo │  6. List All Databases                                        │
echo │  7. DB2 Stop/Start/Activate All                              │
echo │  8. Show DB2 Process Status                                   │
echo └───────────────────────────────────────────────────────────────┘
echo.
echo ┌─ Quick Commands ──────────────────────────────────────────────┐
echo │  9. Connect to Database (specify name)                       │
echo │  A. Activate Database (specify name)                         │
echo │  B. Show Database Applications                                │
echo └───────────────────────────────────────────────────────────────┘
echo.
echo ┌─ Menu Options ────────────────────────────────────────────────┐
echo │  0. Exit to Command Prompt                                    │
echo └───────────────────────────────────────────────────────────────┘
echo.
set /p choice="Please select an option (0-B): "

if /i "%choice%"=="1" goto set_db2
if /i "%choice%"=="2" goto set_db2fed
if /i "%choice%"=="3" goto set_db2a
if /i "%choice%"=="4" goto set_db2t
if /i "%choice%"=="5" goto get_instance
if /i "%choice%"=="6" goto list_databases
if /i "%choice%"=="7" goto restart_db2
if /i "%choice%"=="8" goto show_status
if /i "%choice%"=="9" goto connect_db
if /i "%choice%"=="a" goto activate_db
if /i "%choice%"=="A" goto activate_db
if /i "%choice%"=="b" goto show_apps
if /i "%choice%"=="B" goto show_apps
if /i "%choice%"=="0" goto exit_menu

echo Invalid option. Please try again.
timeout /t 2 >nul
goto main_menu

:set_db2
echo.
echo Setting DB2INSTANCE to DB2...
set DB2INSTANCE=DB2
echo ✓ DB2INSTANCE set to: %DB2INSTANCE%
db2 get instance
echo.
pause
goto main_menu

:set_db2fed
echo.
echo Setting DB2INSTANCE to DB2FED...
set DB2INSTANCE=DB2FED
echo ✓ DB2INSTANCE set to: %DB2INSTANCE%
db2 get instance
echo.
pause
goto main_menu

:set_db2a
echo.
echo Setting DB2INSTANCE to DB2A...
set DB2INSTANCE=DB2A
echo ✓ DB2INSTANCE set to: %DB2INSTANCE%
db2 get instance
echo.
pause
goto main_menu

:set_db2t
echo.
echo Setting DB2INSTANCE to DB2T...
set DB2INSTANCE=DB2T
echo ✓ DB2INSTANCE set to: %DB2INSTANCE%
db2 get instance
echo.
pause
goto main_menu

:get_instance
echo.
echo === Current Instance Information ===
db2 get instance
echo.
pause
goto main_menu

:list_databases
echo.
echo === Available Databases ===
db2 list database directory
echo.
pause
goto main_menu

:restart_db2
echo.
echo === Full DB2 Restart and Database Activation ===
echo.
echo Step 1: Stopping DB2...
db2stop force
timeout /t 3 >nul

echo Step 2: Starting DB2...
db2start
timeout /t 5 >nul

echo Step 3: Activating databases...
echo NOTE: You may need to manually activate specific databases
db2 list database directory
echo.
echo To activate a database, use: db2 activate database [DBNAME]
echo.
pause
goto main_menu

:show_status
echo.
echo === DB2 Status Information ===
echo Current DB2INSTANCE: %DB2INSTANCE%
echo.
echo Process Information:
db2pd -
echo.
pause
goto main_menu

:connect_db
echo.
set /p dbname="Enter database name to connect to: "
if "%dbname%"=="" (
    echo No database name provided.
    pause
    goto main_menu
)

echo Connecting to database: %dbname%
db2 connect to %dbname%
echo.
echo To disconnect, use: db2 connect reset
echo.
pause
goto main_menu

:activate_db
echo.
set /p dbname="Enter database name to activate: "
if "%dbname%"=="" (
    echo No database name provided.
    pause
    goto main_menu
)

echo Activating database: %dbname%
db2 activate database %dbname%
echo.
pause
goto main_menu

:show_apps
echo.
echo === Current Database Applications ===
db2 list application show detail
echo.
pause
goto main_menu

:exit_menu
echo.
echo Exiting DB2 Menu...
echo Current environment preserved in this session.
echo DB2INSTANCE is still set to: %DB2INSTANCE%
echo.

