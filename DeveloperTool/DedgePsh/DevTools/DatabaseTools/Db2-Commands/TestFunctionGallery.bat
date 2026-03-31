@echo off
setlocal EnableDelayedExpansion
REM TestFunctionGallery.bat - Test all functions in FunctionGallery.bat

REM Test :strlen
set "str=Hello World"
call "%~dp0FunctionGallery.bat" :strlen str len
set /p len=<"%TEMP%\result.txt"
echo strlen: %len%

REM Test :substr
call "%~dp0FunctionGallery.bat" :substr str 6 5 substr
set /p substr=<"%TEMP%\result.txt"
echo substr: %substr%

REM Test :replace
call "%~dp0FunctionGallery.bat" :replace str "World" "Batch" replaced
set /p replaced=<"%TEMP%\result.txt"
echo replace: %replaced%

REM Test :trim
set "str2=   padded   "
call "%~dp0FunctionGallery.bat" :trim str2 trimmed
set /p trimmed=<"%TEMP%\result.txt"
echo trim: %trimmed%

REM Test :upper
call "%~dp0FunctionGallery.bat" :upper str uppered
set /p uppered=<"%TEMP%\result.txt"
echo upper: %uppered%

REM Test :lower
call "%~dp0FunctionGallery.bat" :lower str lowered
set /p lowered=<"%TEMP%\result.txt"
echo lower: %lowered%

REM Test :reverse
call "%~dp0FunctionGallery.bat" :reverse str reversed
set /p reversed=<"%TEMP%\result.txt"
echo reverse: %reversed%

REM Test :contains
call "%~dp0FunctionGallery.bat" :contains str "World" contains
set /p contains=<"%TEMP%\result.txt"
echo contains: %contains%

REM Test :startswith
call "%~dp0FunctionGallery.bat" :startswith str "Hello" startswith
set /p startswith=<"%TEMP%\result.txt"
echo startswith: %startswith%

REM Test :endswith
call "%~dp0FunctionGallery.bat" :endswith str "World" endswith
set /p endswith=<"%TEMP%\result.txt"
echo endswith: %endswith%

REM Test :split
set "csv=one,two,three"
call "%~dp0FunctionGallery.bat" :split csv , firsttoken
set /p firsttoken=<"%TEMP%\result.txt"
echo split: %firsttoken%

REM Test :join (stub)
call "%~dp0FunctionGallery.bat" :join joinresult
set /p joinresult=<"%TEMP%\result.txt"
echo join: %joinresult%

REM Test :pad
call "%~dp0FunctionGallery.bat" :pad str 20 padded
set /p padded=<"%TEMP%\result.txt"
echo pad: %padded%

REM Test :ltrim
call "%~dp0FunctionGallery.bat" :ltrim str2 ltrimmed
set /p ltrimmed=<"%TEMP%\result.txt"
echo ltrim: %ltrimmed%

REM Test :rtrim
call "%~dp0FunctionGallery.bat" :rtrim str2 rtrimmed
set /p rtrimmed=<"%TEMP%\result.txt"
echo rtrim: %rtrimmed%

REM Test :isempty
set "empty="
call "%~dp0FunctionGallery.bat" :isempty empty isempty
set /p isempty=<"%TEMP%\result.txt"
echo isempty: %isempty%

REM Test :isnumber
set "num=12345"
call "%~dp0FunctionGallery.bat" :isnumber num isnum
set /p isnum=<"%TEMP%\result.txt"
echo isnumber: %isnum%

REM Test :max
call "%~dp0FunctionGallery.bat" :max 5 10 maxval
set /p maxval=<"%TEMP%\result.txt"
echo max: %maxval%

REM Test :min
call "%~dp0FunctionGallery.bat" :min 5 10 minval
set /p minval=<"%TEMP%\result.txt"
echo min: %minval%

REM Test :abs
call "%~dp0FunctionGallery.bat" :abs -42 absval
set /p absval=<"%TEMP%\result.txt"
echo abs: %absval%

REM Test :random
call "%~dp0FunctionGallery.bat" :random rnd
set /p rnd=<"%TEMP%\result.txt"
echo random: %rnd%

REM Test :date
call "%~dp0FunctionGallery.bat" :date dt
set /p dt=<"%TEMP%\result.txt"
echo date: %dt%

REM Test :time
call "%~dp0FunctionGallery.bat" :time tm
set /p tm=<"%TEMP%\result.txt"
echo time: %tm%

REM Test :fileexists
call "%~dp0FunctionGallery.bat" :fileexists "%~f0" filex
set /p filex=<"%TEMP%\result.txt"
echo fileexists: %filex%

REM Test :direxists
call "%~dp0FunctionGallery.bat" :direxists "%~dp0" direx
set /p direx=<"%TEMP%\result.txt"
echo direxists: %direx%

REM Test :getfilesize
call "%~dp0FunctionGallery.bat" :getfilesize "%~f0" fsize
set /p fsize=<"%TEMP%\result.txt"
echo getfilesize: %fsize%

REM Test :getfiletime
call "%~dp0FunctionGallery.bat" :getfiletime "%~f0" ftime
set /p ftime=<"%TEMP%\result.txt"
echo getfiletime: %ftime%

REM Fictive test for empty string to all functions
set "empty="
call "%~dp0FunctionGallery.bat" :strlen empty len_empty
set /p len_empty=<"%TEMP%\result.txt"
echo strlen (empty): %len_empty%

call "%~dp0FunctionGallery.bat" :substr empty 0 5 substr_empty
set /p substr_empty=<"%TEMP%\result.txt"
echo substr (empty): %substr_empty%

call "%~dp0FunctionGallery.bat" :replace empty "a" "b" replace_empty
set /p replace_empty=<"%TEMP%\result.txt"
echo replace (empty): %replace_empty%

call "%~dp0FunctionGallery.bat" :trim empty trim_empty
set /p trim_empty=<"%TEMP%\result.txt"
echo trim (empty): %trim_empty%

call "%~dp0FunctionGallery.bat" :upper empty upper_empty
set /p upper_empty=<"%TEMP%\result.txt"
echo upper (empty): %upper_empty%

call "%~dp0FunctionGallery.bat" :lower empty lower_empty
set /p lower_empty=<"%TEMP%\result.txt"
echo lower (empty): %lower_empty%

call "%~dp0FunctionGallery.bat" :reverse empty reverse_empty
set /p reverse_empty=<"%TEMP%\result.txt"
echo reverse (empty): %reverse_empty%

call "%~dp0FunctionGallery.bat" :contains empty "a" contains_empty
set /p contains_empty=<"%TEMP%\result.txt"
echo contains (empty): %contains_empty%

call "%~dp0FunctionGallery.bat" :startswith empty "a" startswith_empty
set /p startswith_empty=<"%TEMP%\result.txt"
echo startswith (empty): %startswith_empty%

call "%~dp0FunctionGallery.bat" :endswith empty "a" endswith_empty
set /p endswith_empty=<"%TEMP%\result.txt"
echo endswith (empty): %endswith_empty%

call "%~dp0FunctionGallery.bat" :split empty , split_empty
set /p split_empty=<"%TEMP%\result.txt"
echo split (empty): %split_empty%

call "%~dp0FunctionGallery.bat" :pad empty 5 pad_empty
set /p pad_empty=<"%TEMP%\result.txt"
echo pad (empty): %pad_empty%

call "%~dp0FunctionGallery.bat" :ltrim empty ltrim_empty
set /p ltrim_empty=<"%TEMP%\result.txt"
echo ltrim (empty): %ltrim_empty%

call "%~dp0FunctionGallery.bat" :rtrim empty rtrim_empty
set /p rtrim_empty=<"%TEMP%\result.txt"
echo rtrim (empty): %rtrim_empty%

call "%~dp0FunctionGallery.bat" :isempty empty isempty_empty
set /p isempty_empty=<"%TEMP%\result.txt"
echo isempty (empty): %isempty_empty%

call "%~dp0FunctionGallery.bat" :isnumber empty isnumber_empty
set /p isnumber_empty=<"%TEMP%\result.txt"
echo isnumber (empty): %isnumber_empty%

call "%~dp0FunctionGallery.bat" :max 0 0 max_empty
set /p max_empty=<"%TEMP%\result.txt"
echo max (0,0): %max_empty%

call "%~dp0FunctionGallery.bat" :min 0 0 min_empty
set /p min_empty=<"%TEMP%\result.txt"
echo min (0,0): %min_empty%

call "%~dp0FunctionGallery.bat" :abs 0 abs_empty
set /p abs_empty=<"%TEMP%\result.txt"
echo abs (0): %abs_empty%

REM No need to test :random, :date, :time, :fileexists, :direxists, :getfilesize, :getfiletime with empty

endlocal

