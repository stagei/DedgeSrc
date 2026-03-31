echo DIRECTIVES"%VCPATH%\cfg\VcCompilerDirectivesStd.dir" > K:\fkavd\Dedge2\cfg\VcCompilerDirectivesStdProxy.dir

echo visualstudio"4"                 > .\VcCompilerDirectivesStd.dir
echo anim                           >> .\VcCompilerDirectivesStd.dir
echo cobidy"%VCPATH%\int\"          >> .\VcCompilerDirectivesStd.dir
echo sourcetabstop"4"               >> .\VcCompilerDirectivesStd.dir
echo sourceformat"Variable"         >> .\VcCompilerDirectivesStd.dir
echo noquery                        >> .\VcCompilerDirectivesStd.dir
echo warnings"1"                    >> .\VcCompilerDirectivesStd.dir
echo max-error"100"                 >> .\VcCompilerDirectivesStd.dir

echo DB2(DB)                         > .\VcCompilerDirectivesSql.dir
echo DB2(DB=DB2DEV)                 >> .\VcCompilerDirectivesSql.dir
echo DB2(BINDDIR=%VCPATH%\bnd)      >> .\VcCompilerDirectivesSql.dir
echo DB2(COPY)                      >> .\VcCompilerDirectivesSql.dir
echo DB2(NOINIT)                    >> .\VcCompilerDirectivesSql.dir
echo DB2(COLLECTION=DBM)            >> .\VcCompilerDirectivesSql.dir
echo DB2(UDB-VERSION=V9)            >> .\VcCompilerDirectivesSql.dir
echo DB2(BIND)                      >> .\VcCompilerDirectivesSql.dir

@REM mkdir "%VCPATH%\_old"
mkdir "%VCPATH%\bnd"
mkdir "%VCPATH%\cfg"
mkdir "%VCPATH%\dir"
@REM mkdir "%VCPATH%\inc"
mkdir "%VCPATH%\int"
mkdir "%VCPATH%\lst"
mkdir "%VCPATH%\net"
@REM mkdir "%VCPATH%\obj"
@REM mkdir "%VCPATH%\prj"
mkdir "%VCPATH%\src"
mkdir "%VCPATH%\src\bat"
mkdir "%VCPATH%\src\rex"
mkdir "%VCPATH%\src\psh"
mkdir "%VCPATH%\src\cbl\imp"
mkdir "%VCPATH%\src\cbl\cpy"
mkdir "%VCPATH%\src\cbl\cpy\sys\cpy"
mkdir "%VCPATH%\tmp"

