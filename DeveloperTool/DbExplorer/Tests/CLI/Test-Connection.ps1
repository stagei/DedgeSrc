param(
    [string]$Profile,
    [ValidateSet('', 'DB2', 'PostgreSQL', 'SQLite')]
    [string]$Provider
)

$testsRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path $testsRoot -Parent

# Use suite log path when set (Run-TestSuite); otherwise create a dedicated log for this script
$logDir = Join-Path $projectRoot "CLI_Test_Output"
. (Join-Path $testsRoot "TestLogger.ps1") -LogDir $logDir -LogPrefix "connection_test"
Start-TestLog -Title "Connection test" -LogDir $logDir -LogPrefix "connection_test" | Out-Null

. (Join-Path $testsRoot "TestConfig.ps1") -Profile $Profile -Provider $Provider
$Profile = Get-WdeTestProfile
$providerLabel = if (Get-WdeTestProvider) { " [$(Get-WdeTestProvider)]" } else { "" }

Write-TestLog "Testing connection (profile: $($Profile))$($providerLabel)..." -Level INFO

$OutputDir = Join-Path $projectRoot "CLI_Test_Output"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Test using CLI - works with any provider (DB2, PostgreSQL, etc.)
# Use ProcessStartInfo so exit code is reliable (.NET exe does not set $LASTEXITCODE in PowerShell)
$exePath = Join-Path $projectRoot "bin\Debug\net10.0-windows\DbExplorer.exe"
$outFile = Join-Path $OutputDir "test_schemas.json"
$psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{
    FileName = $exePath
    Arguments = "--profile $Profile --command list-schemas --outfile `"$outFile`""
    UseShellExecute = $false
    RedirectStandardOutput = $true
    RedirectStandardError = $true
    CreateNoWindow = $true
}
$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
$exitCode = $proc.ExitCode
$result = $stdout, $stderr | Where-Object { $_ }

if ($exitCode -eq 0) {
    Write-TestLog "Connection successful (profile: $Profile)." -Level PASS
    if (Test-Path $outFile) {
        $schemas = Get-Content $outFile -Raw | ConvertFrom-Json
        $count = if ($schemas -is [Array]) { $schemas.Count } else { @($schemas).Count }
        Write-TestLog "Schemas returned: $count" -Level INFO
        $schemas | Format-Table -AutoSize | Out-String | ForEach-Object { Write-TestLog $_ -Level DEBUG -NoConsole }
    }
    exit 0
} else {
    Write-TestLog "Connection failed (profile: $Profile). ExitCode: $exitCode" -Level FAIL
    Write-TestLog ($result | Out-String) -Level ERROR
    exit 1
}
