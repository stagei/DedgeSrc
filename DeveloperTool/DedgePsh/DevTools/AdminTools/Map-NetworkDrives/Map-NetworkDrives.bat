doskey ll=dir /w
doskey la=dir /a
doskey lh=dir /ah
set MYOPTDRV=%OptPath:~0,2%

doskey cdtfk=cd "C:\TEMPFK"
doskey cdo=cd "%OptPath%" & %MYOPTDRV%
doskey cdpsh=cd "%OptPath%\DedgePshApps" & %MYOPTDRV%
doskey cdd=cd "%OptPath%\data" & %MYOPTDRV%

@REM net use f: /delete /y
@REM net use k: /delete /y
@REM net use n: /delete /y
@REM net use r: /delete /y
net use x: /delete /y

@REM if %COMPUTERNAME% == p-no1fkmprd-app (
@REM     net use m: /delete /y
@REM     net use y: /delete /y
@REM     net use z: /delete /y
@REM )

net use f: \\DEDGE.fk.no\Felles /persistent:YES >nul 2>&1
net use k: \\DEDGE.fk.no\erputv\Utvikling /persistent:YES >nul 2>&1
net use n: \\DEDGE.fk.no\erpprog /persistent:YES >nul 2>&1
net use r: \\DEDGE.fk.no\erpdata /persistent:YES >nul 2>&1
net use x: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon /persistent:YES >nul 2>&1
if %COMPUTERNAME% == p-no1fkmprd-app (
    net use m: \\sfknam01.DEDGE.fk.no\Felles_NKM\NKM_Utlast /user:Administrator Namdal10 /persistent:YES >nul 2>&1
    net use y: \\10.60.0.4\fabrikkdata /USER:SKAERP13 FiloDeig01! /persistent:YES >nul 2>&1
    net use z: \\10.60.0.4\produksjon /USER:SKAERP13 FiloDeig01! /persistent:YES >nul 2>&1
)

