@echo off
setlocal EnableDelayedExpansion

REM :strlen - Get string length
:strlen
set "str=!%1!"
set "len=0"
:strlen_loop
if defined str (
    set "str=!str:~1!"
    set /a len+=1
    goto :strlen_loop
)
echo.!len!> "%TEMP%\result.txt"
exit /b

REM :substr - Get substring
:substr
set "str=!%1!"
set "start=%2"
set "len=%3"
set "substr=!str:~%start%,%len%!"
echo.!substr!> "%TEMP%\result.txt"
exit /b

REM :replace - Replace text in string
:replace
set "str=!%1!"
set "find=%2"
set "repl=%3"
set "result=!str:%find%=%repl%!"
echo.!result!> "%TEMP%\result.txt"
exit /b

REM :trim - Remove leading/trailing spaces
:trim
set "str=!%1!"
for /f "tokens=*" %%A in ("!str!") do set "str=%%A"
set "rev=!str!"
:trim_loop
if not "!rev:~-1!"==" " goto :trim_done
set "rev=!rev:~0,-1!"
goto :trim_loop
:trim_done
echo.!rev!> "%TEMP%\result.txt"
exit /b

REM :upper - Convert to uppercase
:upper
set "str=!%1!"
for %%A in (!str!) do set "str=%%A"
set "str=!str:a=A!"
set "str=!str:b=B!"
set "str=!str:c=C!"
set "str=!str:d=D!"
set "str=!str:e=E!"
set "str=!str:f=F!"
set "str=!str:g=G!"
set "str=!str:h=H!"
set "str=!str:i=I!"
set "str=!str:j=J!"
set "str=!str:k=K!"
set "str=!str:l=L!"
set "str=!str:m=M!"
set "str=!str:n=N!"
set "str=!str:o=O!"
set "str=!str:p=P!"
set "str=!str:q=Q!"
set "str=!str:r=R!"
set "str=!str:s=S!"
set "str=!str:t=T!"
set "str=!str:u=U!"
set "str=!str:v=V!"
set "str=!str:w=W!"
set "str=!str:x=X!"
set "str=!str:y=Y!"
set "str=!str:z=Z!"
set "str=!str:æ=Æ!"
set "str=!str:ø=Ø!"
set "str=!str:å=Å!"
echo.!str!> "%TEMP%\result.txt"
exit /b

REM :lower - Convert to lowercase
:lower
set "str=!%1!"
for %%A in (!str!) do set "str=%%A"
set "str=!str:A=a!"
set "str=!str:B=b!"
set "str=!str:C=c!"
set "str=!str:D=d!"
set "str=!str:E=e!"
set "str=!str:F=f!"
set "str=!str:G=g!"
set "str=!str:H=h!"
set "str=!str:I=i!"
set "str=!str:J=j!"
set "str=!str:K=k!"
set "str=!str:L=l!"
set "str=!str:M=m!"
set "str=!str:N=n!"
set "str=!str:O=o!"
set "str=!str:P=p!"
set "str=!str:Q=q!"
set "str=!str:R=r!"
set "str=!str:S=s!"
set "str=!str:T=t!"
set "str=!str:U=u!"
set "str=!str:V=v!"
set "str=!str:W=w!"
set "str=!str:X=x!"
set "str=!str:Y=y!"
set "str=!str:Z=z!"
set "str=!str:Æ=æ!"
set "str=!str:Ø=ø!"
set "str=!str:Å=å!"
echo.!str!> "%TEMP%\result.txt"
exit /b

REM :lower - Convert to lowercase
:lower
set "str=!%1!"
for %%A in (!str!) do set "str=%%A"
set "str=!str:a=A!"
set "str=!str:b=B!"
set "str=!str:c=C!"
set "str=!str:d=D!"
set "str=!str:e=E!"
set "str=!str:f=F!"
set "str=!str:g=G!"
set "str=!str:h=H!"
set "str=!str:i=I!"
set "str=!str:j=J!"
set "str=!str:k=K!"
set "str=!str:l=L!"
set "str=!str:m=M!"
set "str=!str:n=N!"
set "str=!str:o=O!"
set "str=!str:p=P!"
set "str=!str:q=Q!"
set "str=!str:r=R!"
set "str=!str:s=S!"
set "str=!str:t=T!"
set "str=!str:u=U!"
set "str=!str:v=V!"
set "str=!str:w=W!"
set "str=!str:x=X!"
set "str=!str:y=Y!"
set "str=!str:z=Z!"
set "str=!str:æ=Æ!"
set "str=!str:ø=Ø!"
set "str=!str:å=Å!"
echo.!str!> "%TEMP%\result.txt"
exit /b

REM :reverse - Reverse string
:reverse
set "str=!%1!"
set "rev="
set "len=0"
:reverse_loop
if not "!str!"=="" (
    set "rev=!str:~0,1!!rev!"
    set "str=!str:~1!"
    goto :reverse_loop
)
echo.!rev!> "%TEMP%\result.txt"
exit /b

REM :contains - Check if string contains substring
:contains
set "str=!%1!"
set "sub=!%2!"
echo !str! | findstr /C:"!sub!" >nul && (echo.1> "%TEMP%\result.txt") || (echo.0> "%TEMP%\result.txt")
exit /b

REM :startswith - Check if string starts with substring
:startswith
set "str=!%1!"
set "sub=!%2!"
if "!str:~0,%=len:~2=%!"=="!sub!" (echo.1> "%TEMP%\result.txt") else (echo.0> "%TEMP%\result.txt")
exit /b

REM :endswith - Check if string ends with substring
:endswith
set "str=!%1!"
set "sub=!%2!"
set "lenStr=!str!"
set "lenSub=!sub!"
set /a lstr=0, lsub=0
:endswith_lenstr
if defined lenStr set "lenStr=!lenStr:~1!"& set /a lstr+=1& goto :endswith_lenstr
:endswith_lensub
if defined lenSub set "lenSub=!lenSub:~1!"& set /a lsub+=1& goto :endswith_lensub
set /a diff=lstr-lsub
if "!str:~%diff%!"=="!sub!" (echo.1> "%TEMP%\result.txt") else (echo.0> "%TEMP%\result.txt")
exit /b

REM :split - Split string by delimiter (returns first token only for simplicity)
:split
set "str=!%1!"
set "delim=%2"
set "token="
for /f "delims=%delim% tokens=1" %%A in ("!str!") do set "token=%%A"
echo.!token!> "%TEMP%\result.txt"
exit /b

REM :join - Join array elements with delimiter (not practical in batch, stub)
:join
echo.NOT_IMPLEMENTED> "%TEMP%\result.txt"
exit /b

REM :pad - Pad string to specified length (right pad with spaces)
:pad
set "str=!%1!"
set "len=%2"
set "padstr=!str!"
:pad_loop
if not "!padstr!"=="" if not "!padstr:~%len%!"=="" goto :pad_done
set "padstr=!padstr! "
goto :pad_loop
:pad_done
set "padstr=!padstr:~0,%len%!"
echo.!padstr!> "%TEMP%\result.txt"
exit /b

REM :ltrim - Remove leading spaces only
:ltrim
set "str=!%1!"
set "ltrim="
for /f "tokens=*" %%A in ("!str!") do set "ltrim=%%A"
echo.!ltrim!> "%TEMP%\result.txt"
exit /b

REM :rtrim - Remove trailing spaces only
:rtrim
set "str=!%1!"
set "rtrim=!str!"
:rtrim_loop
if not "!rtrim:~-1!"==" " goto :rtrim_done
set "rtrim=!rtrim:~0,-1!"
goto :rtrim_loop
:rtrim_done
echo.!rtrim!> "%TEMP%\result.txt"
exit /b

REM :isempty - Check if string is empty
:isempty
set "str=!%1!"
if "!str!"=="" (echo.1> "%TEMP%\result.txt") else (echo.0> "%TEMP%\result.txt")
exit /b

REM :isnumber - Check if string is numeric
:isnumber
set "str=!%1!"
echo !str! | findstr /R "^[0-9][0-9]*$" >nul && (echo.1> "%TEMP%\result.txt") || (echo.0> "%TEMP%\result.txt")
exit /b

REM :max - Get maximum of two numbers
:max
set /a a=%1, b=%2
if !a! gtr !b! (echo.!a!> "%TEMP%\result.txt") else (echo.!b!> "%TEMP%\result.txt")
exit /b

REM :min - Get minimum of two numbers
:min
set /a a=%1, b=%2
if !a! lss !b! (echo.!a!> "%TEMP%\result.txt") else (echo.!b!> "%TEMP%\result.txt")
exit /b

REM :abs - Get absolute value
:abs
set /a n=%1
if !n! lss 0 (set /a n*=-1)
echo.!n!> "%TEMP%\result.txt"
exit /b

REM :random - Generate random number
:random
set /a rnd=%random%
echo.!rnd!> "%TEMP%\result.txt"
exit /b

REM :date - Get current date
:date
set "dt=%date%"
echo.!dt!> "%TEMP%\result.txt"
exit /b

REM :time - Get current time
:time
set "tm=%time%"
echo.!tm!> "%TEMP%\result.txt"
exit /b

REM :fileexists - Check if file exists
:fileexists
if exist "%1" (echo.1> "%TEMP%\result.txt") else (echo.0> "%TEMP%\result.txt")
exit /b

REM :direxists - Check if directory exists
:direxists
if exist "%1\" (echo.1> "%TEMP%\result.txt") else (echo.0> "%TEMP%\result.txt")
exit /b

REM :getfilesize - Get file size (in bytes)
:getfilesize
for %%A in ("%1") do echo.%%~zA> "%TEMP%\result.txt"
exit /b

REM :getfiletime - Get file modification time
:getfiletime
for %%A in ("%1") do echo.%%~tA> "%TEMP%\result.txt"
exit /b

