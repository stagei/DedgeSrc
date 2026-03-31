<#
.SYNOPSIS
    Tests JDBC connection to DB2 using the same JCC driver as DBeaver.
    Tries multiple JDBC security mechanisms to find one that works.

.PARAMETER DbHost
    DB2 server hostname (default: t-no1inltst-db)

.PARAMETER Port
    DB2 port (default: 3718)

.PARAMETER Database
    Actual database name on the server (default: INLTST).
    NOTE: Do NOT use catalog aliases like FKKTOTST for JDBC.

.PARAMETER User
    Username (default: DEDGE\fkgeista)

.PARAMETER Password
    Password. If omitted, will prompt interactively.
#>
param(
    [string]$DbHost = "t-no1inltst-db",
    [int]$Port = 3718,
    [string]$Database = "INLTST",
    [string]$User = "DEDGE\fkgeista",
    [string]$Password
)

$jdkPath = "C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot"
$javaExe = Join-Path $jdkPath "bin\java.exe"
$javacExe = Join-Path $jdkPath "bin\javac.exe"
$jccJar = "C:\Users\FKGEISTA\AppData\Roaming\DBeaverData\drivers\maven\maven-central\com.ibm.db2\jcc-12.1.0.0.jar"

if (-not (Test-Path $javaExe)) {
    Write-Error "Java not found at $($javaExe). Install: winget install EclipseAdoptium.Temurin.21.JDK"
    exit 1
}
if (-not (Test-Path $jccJar)) {
    $jccJar = "C:\Users\FKGEISTA\AppData\Roaming\DBeaverData\drivers\maven\maven-central\com.ibm.db2\jcc-11.5.9.0.jar"
    if (-not (Test-Path $jccJar)) {
        Write-Error "DB2 JCC driver not found in DBeaver's driver cache"
        exit 1
    }
}

$srcDir = $PSScriptRoot
$javaFile = Join-Path $srcDir "Db2JdbcTest.java"
$classFile = Join-Path $srcDir "Db2JdbcTest.class"

if (-not (Test-Path $classFile) -or (Get-Item $javaFile).LastWriteTime -gt (Get-Item $classFile).LastWriteTime) {
    Write-Host "Compiling..." -ForegroundColor Yellow
    & $javacExe -cp $jccJar $javaFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Compilation failed"
        exit 1
    }
}

if (-not $Password) {
    $secPw = Read-Host "Password for $($User)" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPw)
    )
}

& $javaExe -cp "$($srcDir);$($jccJar)" Db2JdbcTest $DbHost $Port $Database $User $Password
exit $LASTEXITCODE
