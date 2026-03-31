# Standardized logging for the test suite
# Call Start-TestLog once at the beginning of a test run; then use Write-TestLog for all output.

param(
    [string]$LogDir = "CLI_Test_Output",
    [string]$LogPrefix = "testsuite"
)

$script:WDE_TestLogPath = $null
$script:WDE_TestLogStarted = $null

function Get-WdeTestLogPath {
    # When Run-TestSuite sets WDE_TEST_LOG_PATH, all child scripts write to the same suite log
    if ($env:WDE_TEST_LOG_PATH) {
        return $env:WDE_TEST_LOG_PATH
    }
    if ($script:WDE_TestLogPath) { return $script:WDE_TestLogPath }
    $dir = $LogDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:WDE_TestLogPath = Join-Path $dir "${LogPrefix}_${timestamp}.log"
    return $script:WDE_TestLogPath
}

function Start-TestLog {
    param(
        [string]$Title = "Test run",
        [string]$LogDir = "CLI_Test_Output",
        [string]$LogPrefix = "testsuite"
    )
    $path = Get-WdeTestLogPath -LogDir $LogDir -LogPrefix $LogPrefix
    $script:WDE_TestLogStarted = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $header = @"
================================================================================
$Title
Started: $($script:WDE_TestLogStarted)
Log file: $path
Computer: $env:COMPUTERNAME
User: $env:USERNAME
================================================================================

"@
    # When running under Run-TestSuite (WDE_TEST_LOG_PATH), append section header instead of overwriting
    if ($path -eq $env:WDE_TEST_LOG_PATH) {
        Add-Content -Path $path -Value $header -Encoding utf8
    } else {
        $header | Out-File -FilePath $path -Encoding utf8
    }
    Write-Host $header -ForegroundColor Cyan
    return $path
}

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'PASS', 'FAIL')]
        [string]$Level = 'INFO',
        [switch]$NoConsole
    )
    $path = Get-WdeTestLogPath
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $path -Value $line -Encoding utf8
    if (-not $NoConsole) {
        $color = switch ($Level) {
            'PASS'  { 'Green' }
            'FAIL'  { 'Red' }
            'WARN'  { 'Yellow' }
            'ERROR' { 'Red' }
            'DEBUG' { 'DarkGray' }
            default { 'White' }
        }
        Write-Host $line -ForegroundColor $color
    }
}

function Get-TestLogPath { Get-WdeTestLogPath }
