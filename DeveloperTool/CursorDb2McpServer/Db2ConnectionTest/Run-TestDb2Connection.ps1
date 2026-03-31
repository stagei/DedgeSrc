<#
.SYNOPSIS
    Test DB2 connection to FKMTST using DedgeCommon DedgeDbHandler.
    Verifies connection only - no MCP pipeline.
#>
param()

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

try {
    Write-LogMessage "Db2ConnectionTest" -Level JOB_STARTED

    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    $exePath = Join-Path $PSScriptRoot 'Db2ConnectionTest.exe'
    if (-not (Test-Path -LiteralPath $exePath)) {
        Write-LogMessage "Db2ConnectionTest.exe not found at $exePath. Run dotnet publish first." -Level ERROR
        Write-LogMessage "Db2ConnectionTest" -Level JOB_FAILED
        exit 1
    }

    Write-LogMessage "Running DB2 connection test (FKMTST)..." -Level INFO
    $output = & $exePath 2>&1
    $exitCode = $LASTEXITCODE

    Write-LogMessage "Output: $output" -Level INFO
    Write-LogMessage "Exit code: $exitCode" -Level INFO

    if ($exitCode -eq 0) {
        Write-LogMessage "DB2 connection test succeeded" -Level INFO
        Write-LogMessage "Db2ConnectionTest" -Level JOB_COMPLETED
        exit 0
    }
    else {
        Write-LogMessage "DB2 connection test failed with exit code $exitCode" -Level ERROR
        Write-LogMessage "Db2ConnectionTest" -Level JOB_FAILED
        exit 1
    }
}
catch {
    Write-LogMessage "Db2ConnectionTest failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "Db2ConnectionTest" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
