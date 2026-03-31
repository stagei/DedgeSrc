@echo off
REM echo %PROFILE_LOADED%
if not defined PROFILE_LOADED (
    set PROFILE_LOADED=NOT_LOADED
)

@REM if  exist n:\ (
@REM     set PROFILE_LOADED=OK
@REM )

@REM if not exist n:\ (
@REM     set PROFILE_LOADED=NOT_LOADED
@REM )
@REM echo "%CMDCMDLINE%"
if %PROFILE_LOADED% == NOT_LOADED (
    set PROFILE_LOADED=OK
    doskey ll=dir /w 2>&1
    doskey la=dir /a 2>&1
    doskey lh=dir /ah 2>&1
    doskey cdtfk=cd /d "C:\TEMPFK" 2>&1
    doskey cdo=cd /d "%OptPath%" 2>&1
    doskey cdpsh=cd /d "%OptPath%\DedgePshApps" 2>&1
    doskey cdd=cd /d "%OptPath%\data" 2>&1


    @echo off
    net use f: /delete /y >nul 2>&1
    net use f: \\DEDGE.fk.no\Felles  >nul 2>&1

    net use k: /delete /y >nul 2>&1
    net use k: \\DEDGE.fk.no\erputv\Utvikling  >nul 2>&1

    net use n: /delete /y >nul 2>&1
    net use n: \\DEDGE.fk.no\erpprog  >nul 2>&1

    net use r: /delete /y >nul 2>&1
    net use r: \\DEDGE.fk.no\erpdata  >nul 2>&1

    net use x: /delete /y >nul 2>&1
    net use x: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon  >nul 2>&1


    if %COMPUTERNAME% == p-no1fkmprd-app (
        net use m: /delete /y >nul 2>&1
        net use m: \\sfknam01.DEDGE.fk.no\Felles_NKM\NKM_Utlast /user:Administrator Namdal10  >nul 2>&1

        net use y: /delete /y >nul 2>&1
        net use y: \\10.60.0.4\fabrikkdata /USER:SKAERP13 FiloDeig01! >nul 2>&1
    
        net use z: /delete /y >nul 
        net use z: \\10.60.0.4\produksjon FiloDeig01! /USER:SKAERP13 >nul 2>&1
    )
    echo Nettverksdisker satt opp!
)
