@echo off
setlocal enabledelayedexpansion

echo [DEBUG] Script started

set "program=Server-AlertOnShutdown"
set "kode=9999"
set "computername=%COMPUTERNAME%"
set "melding=System shutdown/restart detected on %computername%"

:: Show variables after assignment
echo [DEBUG] program=%program%
echo [DEBUG] kode=%kode%
echo [DEBUG] computername=%computername%
echo [DEBUG] melding=%melding%

:: Get timestamp in yyyyMMddHHmmss format
for /f "tokens=1-4 delims=/- " %%a in ('wmic os get localdatetime ^| find "."') do (
    set datetime=%%a
)
set "timestamp=!datetime:~0,14!"
echo [DEBUG] timestamp=!timestamp!

set "wkmon=!timestamp! !program! !kode! !computername!: !melding!"
echo [DEBUG] wkmon=!wkmon!

:: Default path
set "wkmonpath=.\"
set "compup=!computername!"
echo [DEBUG] Initial wkmonpath=!wkmonpath!
echo [DEBUG] compup=!compup!

:: Convert to upper and check if starts with P-NO1
for %%C in (!compup!) do (
    set "uppercomp=%%C"
)
set "prefix=!uppercomp:~0,5!"
echo [DEBUG] uppercomp=!uppercomp!
echo [DEBUG] prefix=!prefix!

if /I "!prefix!"=="P-NO1" (
    set "wkmonpath=\\DEDGE.fk.no\erpprog\cobnt\monitor\"
    echo [DEBUG] wkmonpath changed to !wkmonpath! since hostname starts with P-NO1
) else (
    echo [DEBUG] wkmonpath remains !wkmonpath!
)

set "wkmonfilename=!wkmonpath!!computername!!timestamp!.MON"
echo [DEBUG] wkmonfilename=!wkmonfilename!

:: Write to file (ASCII by default)
echo [DEBUG] Writing to !wkmonfilename!
echo !wkmon! > "!wkmonfilename!"

:: Optional logging section (no Logger util in BAT, so just echo for demonstration)
echo [DEBUG] Finished. wkmon content:
echo !wkmon!

endlocal