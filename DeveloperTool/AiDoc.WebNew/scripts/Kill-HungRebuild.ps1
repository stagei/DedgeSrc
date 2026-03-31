param(
    [string]$RagName
)
$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force

Write-LogMessage "Kill-HungRebuild starting" -Level INFO

$killed = 0
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | ForEach-Object {
    $cmd = $_.CommandLine
    $pid2 = $_.ProcessId
    Write-LogMessage "  PID=$($pid2) CMD=$($cmd)" -Level INFO

    if ($cmd -match 'build_index\.py') {
        if (-not $RagName -or $cmd -match $RagName) {
            Write-LogMessage "  KILLING PID $($pid2) (build_index.py)" -Level WARN
            Stop-Process -Id $pid2 -Force -ErrorAction SilentlyContinue
            $killed++
        }
    }
}

$statusDir = Join-Path $env:OptPath 'data\Rebuild-RagIndex'
if ($RagName) {
    $runFile = Join-Path $statusDir "$($RagName).running"
    if (Test-Path $runFile) {
        Remove-Item $runFile -Force
        Write-LogMessage "Removed $($runFile)" -Level INFO
    }
} else {
    Get-ChildItem $statusDir -Filter '*.running' -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-LogMessage "Removed $($_.FullName)" -Level INFO
    }
}

Write-LogMessage "Kill-HungRebuild done. Killed $($killed) process(es)." -Level INFO
