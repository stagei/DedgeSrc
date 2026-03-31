<#
.SYNOPSIS
    Regression test suite for GenericLogHandler.
.DESCRIPTION
    Orchestrates a full regression test across 7 phases:
      1. Database Reset (drop all tables)
      2. Schema Recreation (EF Core migrate via ImportService start)
      3. Import Test Data (file import + API ingest + stress test)
      4. Verify Imports (SQL assertions)
      5. Create Alert Filters (positive triggers, negative/below-threshold,
         time-window, cooldown, webhook-payload, failed-webhook)
      6. Run Alert Agent (two evaluation cycles for cooldown enforcement)
      7. Verify Alerts (positive triggers, negative tests, cooldown,
         failed webhook error recording, webhook payload content)

    Produces a REPORT.txt and optionally sends SMS on completion.
.PARAMETER SkipConfigSeed
    Skip exporting config from t-no1fkxtst-db (Phase 2b).
.PARAMETER NoBuild
    Skip the solution build step.
.PARAMETER NoSms
    Do not send SMS on completion.
.PARAMETER CaptureBaseline
    Run all tests, then save the observed numeric/boolean results to
    expected-results.json as the new predefined expectations baseline.
#>
param(
    [switch]$SkipConfigSeed,
    [switch]$NoBuild,
    [switch]$NoSms,
    [switch]$CaptureBaseline
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

# ============================================================================
# Configuration
# ============================================================================
$script:RepoRoot    = (Resolve-Path "$PSScriptRoot\..\..\").Path.TrimEnd('\')
$script:TestRoot    = $PSScriptRoot
$script:ConfigDir   = Join-Path $TestRoot 'config'
$script:TestDataDir = Join-Path $TestRoot 'testdata'
$script:SqlDir      = Join-Path $TestRoot 'sql'
$script:FilterDir   = Join-Path $TestRoot 'filters'
$script:ReportFile  = Join-Path $TestRoot 'REPORT.txt'

$script:WebApiProject     = Join-Path $RepoRoot 'src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj'
$script:ImportSvcProject  = Join-Path $RepoRoot 'src\GenericLogHandler.ImportService\GenericLogHandler.ImportService.csproj'
$script:AlertAgentProject = Join-Path $RepoRoot 'src\GenericLogHandler.AlertAgent\GenericLogHandler.AlertAgent.csproj'
$script:SolutionFile      = Join-Path $RepoRoot 'GenericLogHandler.sln'

$script:TestAppSettings   = Join-Path $ConfigDir 'appsettings.test.json'
$script:TestImportConfig  = Join-Path $ConfigDir 'import-config.test.json'

$script:DbHost     = 'localhost'
$script:DbPort     = 8432
$script:DbName     = 'GenericLogHandler'
$script:DbUser     = 'postgres'
$script:DbPassword = 'postgres'
$script:ConnStr    = "Host=$($script:DbHost);Port=$($script:DbPort);Database=$($script:DbName);Username=$($script:DbUser);Password=$($script:DbPassword)"

$script:ApiBaseUrl = 'http://localhost:8110'
$script:ApiPort    = 8110

$script:Results = [ordered]@{}
$script:StartTime = Get-Date

# ============================================================================
# Load Predefined Expectations
# ============================================================================
$script:ExpFile = Join-Path $TestRoot 'expected-results.json'
$script:Exp = @{}

if (Test-Path $script:ExpFile) {
    $script:Exp = (Get-Content $script:ExpFile -Raw | ConvertFrom-Json -AsHashtable)
    $script:Exp.Remove('_generated')
    Write-Host "Loaded $($script:Exp.Count) predefined expectations from expected-results.json"
}
else {
    Write-Host "WARNING: expected-results.json not found -- run with -CaptureBaseline to create it"
}

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Phase {
    param([string]$Name)
    $separator = '=' * 70
    Write-LogMessage $separator -Level INFO
    Write-LogMessage "  PHASE: $($Name)" -Level INFO
    Write-LogMessage $separator -Level INFO
}

function Add-Result {
    param([string]$Check, [string]$Expected, [string]$Actual, [bool]$Pass)
    $status = if ($Pass) { 'PASS' } else { 'FAIL' }
    $script:Results[$Check] = @{
        Expected = $Expected
        Actual   = $Actual
        Status   = $status
    }
    $icon = if ($Pass) { '[OK]' } else { '[FAIL]' }
    Write-LogMessage "  $($icon) $($Check): expected=$($Expected), actual=$($Actual)" -Level $(if ($Pass) { 'INFO' } else { 'ERROR' })
}

function Initialize-SqlModule {
    Import-Module SimplySql -Force -ErrorAction Stop
}

function Open-TestDbConnection {
    param([string]$DbName = $script:DbName)
    $cred = New-Object PSCredential($script:DbUser, (ConvertTo-SecureString $script:DbPassword -AsPlainText -Force))
    Open-PostGreConnection -Server $script:DbHost -Port $script:DbPort -Database $DbName -Credential $cred -ConnectionName 'test'
}

function Close-TestDbConnection {
    Close-SqlConnection -ConnectionName 'test' -ErrorAction SilentlyContinue
}

function Invoke-PgSql {
    param(
        [string]$Query,
        [switch]$NonQuery
    )

    if ($NonQuery) {
        return Invoke-SqlUpdate -Query $Query -ConnectionName 'test'
    }
    else {
        return Invoke-SqlQuery -Query $Query -ConnectionName 'test'
    }
}

function Invoke-PgScalar {
    param([string]$Query)
    return Invoke-SqlScalar -Query $Query -ConnectionName 'test'
}

function Stop-ProjectProcesses {
    Write-LogMessage "Stopping any running GenericLogHandler processes..." -Level INFO
    $processNames = @('GenericLogHandler.WebApi', 'GenericLogHandler.ImportService', 'GenericLogHandler.AlertAgent')
    foreach ($name in $processNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # Also stop by dotnet with matching command line
    Get-Process -Name 'dotnet' -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmdLine -match 'GenericLogHandler'
        } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Wait-ForApi {
    param([int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Uri "$($script:ApiBaseUrl)/health" -Method Get -TimeoutSec 3 -ErrorAction Stop
            Write-LogMessage "API is responding" -Level INFO
            return $true
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    Write-LogMessage "API did not respond within $($TimeoutSeconds) seconds" -Level ERROR
    return $false
}

function Start-DotnetProcess {
    param(
        [string]$ProjectPath,
        [string]$Name,
        [hashtable]$ExtraEnv = @{}
    )

    $logFile = Join-Path $script:TestRoot "$($Name).log"

    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $env:ConnectionStrings__Postgres = $script:ConnStr
    $env:ConnectionStrings__DefaultConnection = $script:ConnStr
    $env:ImportConfiguration__Database__Type = 'postgres'
    $env:DedgeAuth__Enabled = 'false'

    foreach ($key in $ExtraEnv.Keys) {
        [System.Environment]::SetEnvironmentVariable($key, $ExtraEnv[$key], 'Process')
    }

    $process = Start-Process -FilePath 'dotnet' `
        -ArgumentList "run --no-build --project `"$ProjectPath`"" `
        -WorkingDirectory $script:RepoRoot `
        -PassThru `
        -RedirectStandardOutput $logFile `
        -RedirectStandardError "$($logFile).err" `
        -NoNewWindow

    Write-LogMessage "Started $($Name) (PID: $($process.Id)), log: $($logFile)" -Level INFO
    return $process
}

# ============================================================================
# PHASE 0: Build + Initialize
# ============================================================================
Initialize-SqlModule

if (-not $NoBuild) {
    Write-Phase 'Phase 0: Build Solution'
    $buildResult = & dotnet build $script:SolutionFile --configuration Debug 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-LogMessage "Build FAILED:" -Level ERROR
        $buildResult | ForEach-Object { Write-LogMessage "  $_" -Level ERROR }
        exit 1
    }
    Write-LogMessage "Build succeeded" -Level INFO
}

# ============================================================================
# PHASE 1: Database Reset
# ============================================================================
Write-Phase 'Phase 1: Database Reset'
Stop-ProjectProcesses

# Ensure the database exists (create if needed)
try {
    $cred = New-Object PSCredential($script:DbUser, (ConvertTo-SecureString $script:DbPassword -AsPlainText -Force))
    Open-PostGreConnection -Server $script:DbHost -Port $script:DbPort -Database 'postgres' -Credential $cred -ConnectionName 'admin'
    $dbExists = Invoke-SqlScalar -Query "SELECT 1 FROM pg_database WHERE datname = '$($script:DbName)';" -ConnectionName 'admin'
    if (-not $dbExists) {
        Write-LogMessage "Database '$($script:DbName)' does not exist, creating..." -Level INFO
        Invoke-SqlUpdate -Query "CREATE DATABASE `"$($script:DbName)`";" -ConnectionName 'admin' | Out-Null
        Write-LogMessage "Database created" -Level INFO
    }
    else {
        Write-LogMessage "Database '$($script:DbName)' exists" -Level INFO
    }
    Close-SqlConnection -ConnectionName 'admin'
}
catch {
    Write-LogMessage "Database check/creation failed: $($_.Exception.Message)" -Level ERROR
    Close-SqlConnection -ConnectionName 'admin' -ErrorAction SilentlyContinue
    exit 1
}

# Open persistent connection to the test database
Open-TestDbConnection

try {
    $dropSql = Get-Content (Join-Path $script:SqlDir '00-drop-all.sql') -Raw
    Invoke-PgSql -Query $dropSql -NonQuery | Out-Null
    Write-LogMessage "All tables dropped successfully" -Level INFO
    Add-Result -Check 'db_reset' -Expected 'success' -Actual 'success' -Pass $true
}
catch {
    Write-LogMessage "Database reset failed: $($_.Exception.Message)" -Level ERROR
    Add-Result -Check 'db_reset' -Expected 'success' -Actual "FAILED: $($_.Exception.Message)" -Pass $false
    Close-TestDbConnection
    exit 1
}

# ============================================================================
# Config Swap: Replace repo-root configs with test versions BEFORE services start
# ============================================================================
$tempImportConfig = Join-Path $script:RepoRoot 'import-config.json.bak'
$origImportConfig = Join-Path $script:RepoRoot 'import-config.json'
$origAppSettings  = Join-Path $script:RepoRoot 'appsettings.json'
$tempAppSettings  = Join-Path $script:RepoRoot 'appsettings.json.bak'

if (Test-Path $origImportConfig) {
    Copy-Item $origImportConfig $tempImportConfig -Force
}
Copy-Item $script:TestImportConfig $origImportConfig -Force

if (Test-Path $origAppSettings) {
    Copy-Item $origAppSettings $tempAppSettings -Force
}
Copy-Item $script:TestAppSettings $origAppSettings -Force
Write-LogMessage "Config files swapped to test versions" -Level INFO

# ============================================================================
# PHASE 2: Schema Recreation + Config Seeding
# ============================================================================
Write-Phase 'Phase 2: Schema Recreation'

# Start ImportService briefly to trigger MigrateAsync
$importSvc = Start-DotnetProcess -ProjectPath $script:ImportSvcProject -Name 'ImportService-Migrate'
Start-Sleep -Seconds 15

# Verify tables were created
try {
    $tableCount = Invoke-PgScalar -Query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';"
    Write-LogMessage "Tables created: $($tableCount)" -Level INFO
    $expTables = $script:Exp['schema_tables']
    $tablesOk = [int]$tableCount -eq $expTables
    Add-Result -Check 'schema_tables' -Expected $expTables.ToString() -Actual $tableCount.ToString() -Pass $tablesOk
}
catch {
    Write-LogMessage "Schema check failed: $($_.Exception.Message)" -Level ERROR
    Add-Result -Check 'schema_tables' -Expected "$($script:Exp['schema_tables'])" -Actual 'FAILED' -Pass $false
}

# Kill ImportService after migration
if ($importSvc -and -not $importSvc.HasExited) {
    Stop-Process -Id $importSvc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-LogMessage "ImportService stopped after migration" -Level INFO
}

# Clear data seeded during migration (import cycle runs with RunOnce during migration too)
try {
    Invoke-PgSql -Query "DELETE FROM log_entries;" -NonQuery | Out-Null
    Invoke-PgSql -Query "DELETE FROM import_sources;" -NonQuery | Out-Null
    Invoke-PgSql -Query "DELETE FROM import_status;" -NonQuery | Out-Null
    Write-LogMessage "Cleared log_entries, import_sources, import_status (will re-seed from test config)" -Level INFO
}
catch {
    Write-LogMessage "Failed to clear tables: $($_.Exception.Message)" -Level WARN
}

# Phase 2b: Seed config from FKX (optional)
if (-not $SkipConfigSeed) {
    Write-LogMessage "Seeding configuration from t-no1fkxtst-db..." -Level INFO
    try {
        & pwsh.exe -NoProfile -File (Join-Path $script:SqlDir '01-seed-config-from-fkx.ps1')
    }
    catch {
        Write-LogMessage "Config seed failed (non-critical): $($_.Exception.Message)" -Level WARN
    }
}

# ============================================================================
# PHASE 3: Import Test Data
# ============================================================================
Write-Phase 'Phase 3: Import Test Data'

# 3a: Start WebApi and ingest API batch (queue entries for ImportService to drain)
Write-LogMessage "Phase 3a: API ingest via WebApi (queue entries)..." -Level INFO

$webApi = Start-DotnetProcess -ProjectPath $script:WebApiProject -Name 'WebApi-Ingest'
$apiReady = Wait-ForApi -TimeoutSeconds 30

if ($apiReady) {
    try {
        $ingestData = Get-Content (Join-Path $script:TestDataDir 'ingest-api-batch.json') -Raw
        $response = Invoke-RestMethod -Uri "$($script:ApiBaseUrl)/api/Logs/ingest/batch" `
            -Method Post `
            -Body $ingestData `
            -ContentType 'application/json' `
            -TimeoutSec 30

        Write-LogMessage "Ingest batch response: $($response | ConvertTo-Json -Compress)" -Level INFO

        $queueCount = Invoke-PgScalar -Query "SELECT COUNT(*) FROM ingest_queue;"
        Write-LogMessage "Items queued for import: $($queueCount)" -Level INFO
    }
    catch {
        Write-LogMessage "API ingest failed: $($_.Exception.Message)" -Level ERROR
        Add-Result -Check 'api_ingest_count' -Expected "$($script:Exp['api_ingest_count'])" -Actual "FAILED: $($_.Exception.Message)" -Pass $false
    }
}
else {
    Add-Result -Check 'api_ingest_count' -Expected "$($script:Exp['api_ingest_count'])" -Actual 'API not responding' -Pass $false
}

# 3b: Start ImportService - drains the ingest queue FIRST, then imports files
Write-LogMessage "Phase 3b: ImportService (drains queue + imports files)..." -Level INFO

try {
    $importSvc = Start-DotnetProcess -ProjectPath $script:ImportSvcProject -Name 'ImportService-Import'

    # Wait 20s for the import cycle to complete (queue drain + file import)
    Start-Sleep -Seconds 20

    # Time shift: compress all timestamps into the last 3 minutes so the job correlation
    # timer (sinceTime = now - 5min) and alert evaluation (TimeWindowMinutes) can see them
    Write-LogMessage "Shifting log_entries timestamps to recent values for correlation/alerts..." -Level INFO
    $timeShiftSql = @"
UPDATE log_entries
SET timestamp = NOW() - INTERVAL '3 minutes' + (
    EXTRACT(EPOCH FROM (timestamp - (SELECT MIN(timestamp) FROM log_entries)))
    / GREATEST(EXTRACT(EPOCH FROM ((SELECT MAX(timestamp) FROM log_entries) - (SELECT MIN(timestamp) FROM log_entries))), 1)
    * INTERVAL '2 minutes'
);
"@
    Invoke-PgSql -Query $timeShiftSql -NonQuery | Out-Null
    Write-LogMessage "Timestamps shifted to [NOW-3min, NOW-1min] range" -Level INFO

    # Kill ImportService (RunOnce host doesn't self-terminate)
    if ($importSvc -and -not $importSvc.HasExited) {
        Write-LogMessage "Stopping ImportService..." -Level INFO
        Stop-Process -Id $importSvc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    else {
        Write-LogMessage "ImportService exited with code $($importSvc.ExitCode)" -Level INFO
    }

    # Job correlation via SQL (the ImportService timer is unreliable in RunOnce/short-lived mode)
    Write-LogMessage "Running job correlation via SQL..." -Level INFO
    $jobCorrelationSql = @"
INSERT INTO job_executions (id, job_name, started_at, completed_at, status, computer_name, process_id,
    start_log_entry_id, end_log_entry_id, source_file, duration_seconds, error_message, created_at, updated_at)
SELECT
    gen_random_uuid(),
    s.job_name,
    s.timestamp AS started_at,
    c.timestamp AS completed_at,
    COALESCE(c.job_status, 'Started') AS status,
    s.computer_name,
    s.process_id,
    s.id AS start_log_entry_id,
    c.id AS end_log_entry_id,
    s.source_file,
    CASE WHEN c.timestamp IS NOT NULL THEN EXTRACT(EPOCH FROM (c.timestamp - s.timestamp)) END AS duration_seconds,
    CASE WHEN c.job_status = 'Failed' THEN c.message END AS error_message,
    NOW(),
    NOW()
FROM log_entries s
LEFT JOIN LATERAL (
    SELECT e.id, e.timestamp, e.job_status, e.message
    FROM log_entries e
    WHERE e.job_name = s.job_name
      AND e.computer_name = s.computer_name
      AND e.job_status IN ('Completed', 'Failed')
      AND e.timestamp > s.timestamp
    ORDER BY e.timestamp
    LIMIT 1
) c ON true
WHERE s.job_status = 'Started'
  AND s.job_name IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM job_executions je
      WHERE je.job_name = s.job_name
        AND je.computer_name = s.computer_name
        AND je.start_log_entry_id = s.id
  );
"@
    try {
        $jobInserted = Invoke-PgSql -Query $jobCorrelationSql -NonQuery
        Write-LogMessage "Job correlation: inserted $($jobInserted) job execution(s)" -Level INFO
    }
    catch {
        Write-LogMessage "Job correlation SQL failed: $($_.Exception.Message)" -Level WARN
    }

    # Log import service output for diagnostics
    $importLogFile = Join-Path $script:TestRoot 'ImportService-Import.log'
    if (Test-Path $importLogFile) {
        $importLog = Get-Content $importLogFile -Tail 30
        $importLog | ForEach-Object { Write-LogMessage "  [ImportSvc] $_" -Level DEBUG }
    }
    $importErrFile = "$($importLogFile).err"
    if (Test-Path $importErrFile) {
        $importErr = Get-Content $importErrFile -ErrorAction SilentlyContinue
        if ($importErr) {
            $importErr | ForEach-Object { Write-LogMessage "  [ImportSvc-ERR] $_" -Level WARN }
        }
    }

    $fileCount = Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE source_type IS NULL OR source_type != 'api-ingest';"
    Write-LogMessage "File-imported entries: $($fileCount)" -Level INFO
    $expFile = $script:Exp['file_import_count']
    Add-Result -Check 'file_import_count' -Expected $expFile.ToString() -Actual $fileCount.ToString() -Pass ([int]$fileCount -eq $expFile)

    $ingestCount = Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE source_type = 'api-ingest';"
    Write-LogMessage "API-ingested entries: $($ingestCount)" -Level INFO
    $expIngest = $script:Exp['api_ingest_count']
    Add-Result -Check 'api_ingest_count' -Expected $expIngest.ToString() -Actual $ingestCount.ToString() -Pass ([int]$ingestCount -eq $expIngest)
}
catch {
    Write-LogMessage "Import phase failed: $($_.Exception.Message)" -Level ERROR
    Add-Result -Check 'file_import_count' -Expected "$($script:Exp['file_import_count'])" -Actual "FAILED: $($_.Exception.Message)" -Pass $false
}

# ============================================================================
# PHASE 3c: API Stress Test
# ============================================================================
Write-LogMessage "Phase 3c: API stress test (single + batch ingest under concurrent load)..." -Level INFO

# WebApi is still running from Phase 3a
if (-not $webApi -or $webApi.HasExited) {
    $webApi = Start-DotnetProcess -ProjectPath $script:WebApiProject -Name 'WebApi-Stress'
    $null = Wait-ForApi -TimeoutSeconds 30
}

$stressEntryTemplate = @{
    Level        = 'INFO'
    ComputerName = 'STRESS-TEST-{0:D3}'
    UserName     = 'stress_runner'
    Source       = 'api-stress-test'
    Location     = 'C:\StressTest'
    FunctionName = 'StressWorker'
}

$stressSingleTarget   = 200   # individual POST /ingest calls
$stressBatchCount     = 10    # number of batch calls
$stressBatchSize      = 50    # entries per batch
$stressConcurrency    = 10    # parallel runspace slots
$stressTotalExpected  = $stressSingleTarget + ($stressBatchCount * $stressBatchSize)

Write-LogMessage "Stress config: $($stressSingleTarget) singles + $($stressBatchCount)x$($stressBatchSize) batches = $($stressTotalExpected) entries, concurrency=$($stressConcurrency)" -Level INFO

$stressErrors = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$stressOkCount = [System.Threading.Interlocked]

# Build all tasks: singles first, then batches
$stressTasks = [System.Collections.Generic.List[hashtable]]::new()

for ($i = 0; $i -lt $stressSingleTarget; $i++) {
    $body = @{
        Timestamp    = (Get-Date).AddSeconds(-($stressSingleTarget - $i)).ToString('o')
        Message      = "Stress single entry $($i): ordrenr: $((90100 + $i)) avdnr: $((800 + ($i % 50))) Performance test payload $(New-Guid)"
        Level        = @('INFO','WARN','ERROR','DEBUG')[$i % 4]
        ComputerName = "STRESS-TEST-$($i % 5 | ForEach-Object { '{0:D3}' -f $_ })"
        UserName     = 'stress_runner'
        Source       = 'api-stress-test'
        Location     = 'C:\StressTest'
        FunctionName = 'StressWorker'
    } | ConvertTo-Json -Compress
    $stressTasks.Add(@{ Type = 'single'; Body = $body; Index = $i })
}

for ($b = 0; $b -lt $stressBatchCount; $b++) {
    $batchItems = @()
    for ($j = 0; $j -lt $stressBatchSize; $j++) {
        $seq = ($b * $stressBatchSize) + $j
        $batchItems += @{
            Timestamp    = (Get-Date).AddSeconds(-($stressTotalExpected - $seq)).ToString('o')
            Message      = "Stress batch $($b) entry $($j): ordrenr: $((95000 + $seq)) avdnr: $((900 + ($seq % 30))) Batch load test $(New-Guid)"
            Level        = @('INFO','WARN','ERROR','DEBUG','FATAL')[$j % 5]
            ComputerName = "STRESS-BATCH-$($b % 3 | ForEach-Object { '{0:D3}' -f $_ })"
            UserName     = 'stress_batch'
            Source       = 'api-stress-test'
            Location     = 'C:\StressTest\Batch'
            FunctionName = 'BatchStressWorker'
        }
    }
    $body = $batchItems | ConvertTo-Json -Compress
    $stressTasks.Add(@{ Type = 'batch'; Body = $body; Index = $b; Count = $stressBatchSize })
}

$stressStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$successCount = 0
$failCount = 0

# Execute with throttled parallelism using runspace pool
$pool = [runspacefactory]::CreateRunspacePool(1, $stressConcurrency)
$pool.Open()
$runspaces = [System.Collections.Generic.List[object]]::new()

foreach ($task in $stressTasks) {
    $ps = [powershell]::Create().AddScript({
        param($baseUrl, $taskType, $body)
        try {
            $uri = if ($taskType -eq 'single') { "$($baseUrl)/api/Logs/ingest" } else { "$($baseUrl)/api/Logs/ingest/batch" }
            $null = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
            return @{ Success = $true }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }).AddArgument($script:ApiBaseUrl).AddArgument($task.Type).AddArgument($task.Body)
    $ps.RunspacePool = $pool
    $runspaces.Add(@{ PS = $ps; Handle = $ps.BeginInvoke(); Task = $task })
}

# Collect results
foreach ($rs in $runspaces) {
    $result = $rs.PS.EndInvoke($rs.Handle)
    if ($result -and $result[0].Success) {
        $successCount++
    }
    else {
        $failCount++
        $errMsg = if ($result) { $result[0].Error } else { 'null result' }
        $stressErrors.Add("$($rs.Task.Type)[$($rs.Task.Index)]: $($errMsg)")
    }
    $rs.PS.Dispose()
}
$pool.Close()
$pool.Dispose()

$stressStopwatch.Stop()
$stressElapsed = $stressStopwatch.Elapsed
$stressRps = [math]::Round($successCount / [math]::Max($stressElapsed.TotalSeconds, 0.001), 1)

Write-LogMessage "Stress test completed in $($stressElapsed.ToString('mm\:ss\.fff')): $($successCount) OK, $($failCount) failed, $($stressRps) req/s" -Level INFO

if ($stressErrors.Count -gt 0) {
    $sampleErrors = $stressErrors | Select-Object -First 5
    foreach ($err in $sampleErrors) {
        Write-LogMessage "  Stress error: $($err)" -Level WARN
    }
}

$stressSuccessRate = if (($successCount + $failCount) -gt 0) { [math]::Round(($successCount / ($successCount + $failCount)) * 100, 1) } else { 0 }
$stressTotalRequests = $stressSingleTarget + $stressBatchCount
Add-Result -Check 'stress_total_requests' -Expected $stressTotalRequests.ToString() -Actual "$($successCount + $failCount)" -Pass (($successCount + $failCount) -eq $stressTotalRequests)
$expRateMin = $script:Exp['stress_success_rate_min']
Add-Result -Check 'stress_success_rate' -Expected ">=$($expRateMin)%" -Actual "$($stressSuccessRate)%" -Pass ($stressSuccessRate -ge $expRateMin)
Add-Result -Check 'stress_no_500_errors' -Expected '0 server errors' -Actual "$($failCount) failures" -Pass ($failCount -eq 0)
$expRpsMin = $script:Exp['stress_rps_min']
Add-Result -Check 'stress_requests_per_sec' -Expected ">=$($expRpsMin)" -Actual "$($stressRps)" -Pass ($stressRps -ge $expRpsMin)

# Now drain the stress-test queue via ImportService
Write-LogMessage "Draining stress test ingest queue via ImportService..." -Level INFO
$stressQueueBefore = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM ingest_queue;")
Write-LogMessage "Ingest queue size before drain: $($stressQueueBefore)" -Level INFO

$importSvc2 = Start-DotnetProcess -ProjectPath $script:ImportSvcProject -Name 'ImportService-StressDrain'
Start-Sleep -Seconds 25

if ($importSvc2 -and -not $importSvc2.HasExited) {
    Stop-Process -Id $importSvc2.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$stressQueueAfter = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM ingest_queue;")
$stressDrained = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE source_type = 'api-ingest';")
Write-LogMessage "Ingest queue after drain: $($stressQueueAfter), total api-ingest entries: $($stressDrained)" -Level INFO

Add-Result -Check 'stress_queue_drained' -Expected '0' -Actual $stressQueueAfter.ToString() -Pass ($stressQueueAfter -eq 0)
$expPersisted = $script:Exp['stress_entries_persisted']
Add-Result -Check 'stress_entries_persisted' -Expected $expPersisted.ToString() -Actual $stressDrained.ToString() -Pass ($stressDrained -eq $expPersisted)

# Re-shift timestamps for the newly imported stress entries
Write-LogMessage "Re-shifting timestamps (including stress entries)..." -Level INFO
$timeShiftSql2 = @"
UPDATE log_entries
SET timestamp = NOW() - INTERVAL '3 minutes' + (
    EXTRACT(EPOCH FROM (timestamp - (SELECT MIN(timestamp) FROM log_entries)))
    / GREATEST(EXTRACT(EPOCH FROM ((SELECT MAX(timestamp) FROM log_entries) - (SELECT MIN(timestamp) FROM log_entries))), 1)
    * INTERVAL '2 minutes'
);
"@
Invoke-PgSql -Query $timeShiftSql2 -NonQuery | Out-Null

# Stop WebApi (will restart for Phase 5)
if ($webApi -and -not $webApi.HasExited) {
    Stop-Process -Id $webApi.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# ============================================================================
# PHASE 4: Verify Imports
# ============================================================================
Write-Phase 'Phase 4: Verify Imports'

$totalEntries = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries;")
$expTotal = $script:Exp['total_log_entries']
Add-Result -Check 'total_log_entries' -Expected $expTotal.ToString() -Actual $totalEntries.ToString() -Pass ($totalEntries -eq $expTotal)

$testServerCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE source_file LIKE '%TEST-SERVER%';")
$expTestSrv = $script:Exp['test_server_entries']
Add-Result -Check 'test_server_entries' -Expected $expTestSrv.ToString() -Actual $testServerCount.ToString() -Pass ($testServerCount -eq $expTestSrv)

$prodDb01Count = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE source_file LIKE '%PROD-DB01%';")
$expProdDb = $script:Exp['prod_db01_entries']
Add-Result -Check 'prod_db01_entries' -Expected $expProdDb.ToString() -Actual $prodDb01Count.ToString() -Pass ($prodDb01Count -eq $expProdDb)

$alertTestCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE source_file LIKE '%alert-trigger%';")
$expAlertTrig = $script:Exp['alert_trigger_entries']
Add-Result -Check 'alert_trigger_entries' -Expected $expAlertTrig.ToString() -Actual $alertTestCount.ToString() -Pass ($alertTestCount -eq $expAlertTrig)

# Level distribution check
$levelRows = Invoke-PgSql -Query "SELECT level::text AS level, COUNT(*) AS cnt FROM log_entries GROUP BY level ORDER BY level;"
$levelsFound = @()
if ($null -ne $levelRows) {
    $levelList = @($levelRows)
    foreach ($row in $levelList) {
        $levelsFound += $row.level.ToString()
        Write-LogMessage "  Level $($row.level): $($row.cnt)" -Level INFO
    }
}
$hasAllLevels = ('DEBUG' -in $levelsFound) -and ('INFO' -in $levelsFound) -and ('WARN' -in $levelsFound) -and ('ERROR' -in $levelsFound) -and ('FATAL' -in $levelsFound)
Add-Result -Check 'level_distribution' -Expected 'DEBUG,INFO,WARN,ERROR,FATAL' -Actual ($levelsFound -join ',') -Pass $hasAllLevels

# Extractor checks
$ordrenrCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE ordrenr IS NOT NULL AND ordrenr != '';")
$expOrd = $script:Exp['ordrenr_extracted']
Add-Result -Check 'ordrenr_extracted' -Expected $expOrd.ToString() -Actual $ordrenrCount.ToString() -Pass ($ordrenrCount -eq $expOrd)

$avdnrCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE avdnr IS NOT NULL AND avdnr != '';")
$expAvd = $script:Exp['avdnr_extracted']
Add-Result -Check 'avdnr_extracted' -Expected $expAvd.ToString() -Actual $avdnrCount.ToString() -Pass ($avdnrCount -eq $expAvd)

$alertIdCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM log_entries WHERE alert_id IS NOT NULL AND alert_id != '';")
$expAlertId = $script:Exp['alertid_extracted']
Add-Result -Check 'alertid_extracted' -Expected $expAlertId.ToString() -Actual $alertIdCount.ToString() -Pass ($alertIdCount -eq $expAlertId)

# Job correlation
$jobCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM job_executions;")
$expJobs = $script:Exp['job_executions']
Add-Result -Check 'job_executions' -Expected $expJobs.ToString() -Actual $jobCount.ToString() -Pass ($jobCount -eq $expJobs)

# Ingest queue drained
$queueRemaining = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM ingest_queue;")
Add-Result -Check 'ingest_queue_drained' -Expected '0' -Actual $queueRemaining.ToString() -Pass ($queueRemaining -eq 0)

# ============================================================================
# PHASE 5: Create Alert Filters via API
# ============================================================================
Write-Phase 'Phase 5: Create Alert Filters'

$webApi = Start-DotnetProcess -ProjectPath $script:WebApiProject -Name 'WebApi-Filters'
$apiReady = Wait-ForApi -TimeoutSeconds 30

$filterIds = @{}

if ($apiReady) {
    $filterFiles = Get-ChildItem $script:FilterDir -Filter '*.json'
    foreach ($filterFile in $filterFiles) {
        try {
            $filterJson = Get-Content $filterFile.FullName -Raw
            $response = Invoke-RestMethod -Uri "$($script:ApiBaseUrl)/api/filters" `
                -Method Post `
                -Body $filterJson `
                -ContentType 'application/json' `
                -TimeoutSec 15

            if ($response.data -and $response.data.id) {
                $filterId = $response.data.id
                $filterName = $response.data.name
                $filterIds[$filterName] = $filterId
                Write-LogMessage "Created filter: $($filterName) (ID: $($filterId))" -Level INFO
                Add-Result -Check "filter_create_$($filterFile.BaseName)" -Expected 'created' -Actual "ID: $($filterId)" -Pass $true
            }
            else {
                Write-LogMessage "Unexpected response for $($filterFile.Name): $($response | ConvertTo-Json -Compress)" -Level WARN
                Add-Result -Check "filter_create_$($filterFile.BaseName)" -Expected 'created' -Actual 'unexpected response' -Pass $false
            }
        }
        catch {
            Write-LogMessage "Failed to create filter $($filterFile.Name): $($_.Exception.Message)" -Level ERROR
            Add-Result -Check "filter_create_$($filterFile.BaseName)" -Expected 'created' -Actual "FAILED: $($_.Exception.Message)" -Pass $false
        }
    }

    $expectedFilterCount = $filterFiles.Count
    $dbFilterCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE is_alert_enabled = true AND category = 'regression-test';")
    Add-Result -Check 'alert_filters_in_db' -Expected $expectedFilterCount.ToString() -Actual $dbFilterCount.ToString() -Pass ($dbFilterCount -eq $expectedFilterCount)
}
else {
    Add-Result -Check 'filter_creation' -Expected 'success' -Actual 'API not responding' -Pass $false
}

# Keep WebApi running for alert agent webhook target
# (ORDER_SYNC_FAIL filter uses webhook to the local API)

# (Webhook payload verification uses alert_history columns, no external listener needed)

# ============================================================================
# PHASE 6: Run Alert Agent (Two Cycles for Cooldown Testing)
# ============================================================================
Write-Phase 'Phase 6: Run Alert Agent'

$alertAgent = Start-DotnetProcess -ProjectPath $script:AlertAgentProject -Name 'AlertAgent'

# Cycle 1: 10s startup delay + first evaluation. Wait 80s for first cycle to complete.
Write-LogMessage "Waiting 80 seconds for AlertAgent first evaluation cycle..." -Level INFO
Start-Sleep -Seconds 80

# Snapshot alert_history after cycle 1 (for cooldown comparison)
$alertCountAfterCycle1 = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history;")
$cooldownAlertsAfterCycle1 = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%COOLDOWN_TEST%';")
Write-LogMessage "After cycle 1: total alerts=$($alertCountAfterCycle1), cooldown_test alerts=$($cooldownAlertsAfterCycle1)" -Level INFO

# Cycle 2: Wait another 70s for second evaluation cycle (60s interval + buffer)
Write-LogMessage "Waiting 70 seconds for AlertAgent second evaluation cycle (cooldown test)..." -Level INFO
Start-Sleep -Seconds 70

$alertCountAfterCycle2 = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history;")
$cooldownAlertsAfterCycle2 = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%COOLDOWN_TEST%';")
Write-LogMessage "After cycle 2: total alerts=$($alertCountAfterCycle2), cooldown_test alerts=$($cooldownAlertsAfterCycle2)" -Level INFO

# Stop the alert agent
if ($alertAgent -and -not $alertAgent.HasExited) {
    Stop-Process -Id $alertAgent.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-LogMessage "AlertAgent stopped" -Level INFO
}

# Stop WebApi
if ($webApi -and -not $webApi.HasExited) {
    Stop-Process -Id $webApi.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}


# ============================================================================
# PHASE 7: Verify Alerts
# ============================================================================
Write-Phase 'Phase 7: Verify Alerts'

# --- 7a: Basic alert_history checks (existing) ---
Write-LogMessage "7a: Basic alert history checks..." -Level INFO

$alertHistoryCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history;")
$expHistory = $script:Exp['alert_history_records']
Add-Result -Check 'alert_history_records' -Expected $expHistory.ToString() -Actual $alertHistoryCount.ToString() -Pass ($alertHistoryCount -eq $expHistory)

$successfulAlerts = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE success = true;")
$expSuccess = $script:Exp['successful_alerts']
Add-Result -Check 'successful_alerts' -Expected $expSuccess.ToString() -Actual $successfulAlerts.ToString() -Pass ($successfulAlerts -eq $expSuccess)

# --- 7b: ORDER_SYNC_FAIL (positive, threshold=3, has 5+ entries) ---
Write-LogMessage "7b: ORDER_SYNC_FAIL positive trigger checks..." -Level INFO

$orderSyncAlerts = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%ORDER_SYNC_FAIL Alert%';")
$expOSAlerts = $script:Exp['order_sync_fail_alerts']
Add-Result -Check 'order_sync_fail_alert' -Expected $expOSAlerts.ToString() -Actual $orderSyncAlerts.ToString() -Pass ($orderSyncAlerts -eq $expOSAlerts)

if ($orderSyncAlerts -gt 0) {
    $orderSyncMatchCount = [int](Invoke-PgScalar -Query "SELECT MAX(match_count) FROM alert_history WHERE filter_name LIKE '%ORDER_SYNC_FAIL Alert%';")
    $expOSMatch = $script:Exp['order_sync_fail_match_count']
    Add-Result -Check 'order_sync_fail_match_count' -Expected $expOSMatch.ToString() -Actual $orderSyncMatchCount.ToString() -Pass ($orderSyncMatchCount -eq $expOSMatch)
}

# --- 7c: DB_CONN_LOST (positive, threshold=2, has 4 entries) ---
Write-LogMessage "7c: DB_CONN_LOST positive trigger checks..." -Level INFO

$dbConnAlerts = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST Alert%';")
$expDCAlerts = $script:Exp['db_conn_lost_alerts']
Add-Result -Check 'db_conn_lost_alert' -Expected $expDCAlerts.ToString() -Actual $dbConnAlerts.ToString() -Pass ($dbConnAlerts -eq $expDCAlerts)

if ($dbConnAlerts -gt 0) {
    $dbConnMatchCount = [int](Invoke-PgScalar -Query "SELECT MAX(match_count) FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST Alert%';")
    $expDCMatch = $script:Exp['db_conn_lost_match_count']
    Add-Result -Check 'db_conn_lost_match_count' -Expected $expDCMatch.ToString() -Actual $dbConnMatchCount.ToString() -Pass ($dbConnMatchCount -eq $expDCMatch)
}

# --- 7d: Filter state ---
Write-LogMessage "7d: Filter state checks..." -Level INFO

$evaluatedCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE is_alert_enabled = true AND last_evaluated_at IS NOT NULL;")
$expEval = $script:Exp['filters_evaluated']
Add-Result -Check 'filters_evaluated' -Expected $expEval.ToString() -Actual $evaluatedCount.ToString() -Pass ($evaluatedCount -eq $expEval)

$triggeredCount = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE is_alert_enabled = true AND last_triggered_at IS NOT NULL;")
$expTriggered = $script:Exp['filters_triggered']
Add-Result -Check 'filters_triggered' -Expected $expTriggered.ToString() -Actual $triggeredCount.ToString() -Pass ($triggeredCount -eq $expTriggered)

# --- 7e: BELOW-THRESHOLD negative test (threshold=100, should NOT trigger) ---
Write-LogMessage "7e: Below-threshold negative test..." -Level INFO

$belowThresholdAlerts = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%BELOW_THRESHOLD%';")
Add-Result -Check 'below_threshold_no_trigger' -Expected '0' -Actual $belowThresholdAlerts.ToString() -Pass ($belowThresholdAlerts -eq 0)

$belowThresholdEvaluated = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE name LIKE '%BELOW_THRESHOLD%' AND last_evaluated_at IS NOT NULL;")
Add-Result -Check 'below_threshold_was_evaluated' -Expected '1' -Actual $belowThresholdEvaluated.ToString() -Pass ($belowThresholdEvaluated -eq 1)

$belowThresholdNotTriggered = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE name LIKE '%BELOW_THRESHOLD%' AND last_triggered_at IS NULL;")
Add-Result -Check 'below_threshold_not_triggered' -Expected '1' -Actual $belowThresholdNotTriggered.ToString() -Pass ($belowThresholdNotTriggered -eq 1)

# --- 7f: TIME_WINDOW_EXPIRED negative test (TimeWindowMinutes=1, data older than 1 min) ---
Write-LogMessage "7f: Time window negative test..." -Level INFO

$timeWindowAlerts = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%TIME_WINDOW_EXPIRED%';")
Add-Result -Check 'time_window_no_trigger' -Expected '0' -Actual $timeWindowAlerts.ToString() -Pass ($timeWindowAlerts -eq 0)

$timeWindowEvaluated = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE name LIKE '%TIME_WINDOW_EXPIRED%' AND last_evaluated_at IS NOT NULL;")
Add-Result -Check 'time_window_was_evaluated' -Expected '1' -Actual $timeWindowEvaluated.ToString() -Pass ($timeWindowEvaluated -eq 1)

$timeWindowNotTriggered = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM saved_filters WHERE name LIKE '%TIME_WINDOW_EXPIRED%' AND last_triggered_at IS NULL;")
Add-Result -Check 'time_window_not_triggered' -Expected '1' -Actual $timeWindowNotTriggered.ToString() -Pass ($timeWindowNotTriggered -eq 1)

# --- 7g: COOLDOWN enforcement (CooldownMinutes=9999, should trigger once only) ---
Write-LogMessage "7g: Cooldown enforcement test..." -Level INFO

Add-Result -Check 'cooldown_triggered_cycle1' -Expected '1' -Actual $cooldownAlertsAfterCycle1.ToString() -Pass ($cooldownAlertsAfterCycle1 -eq 1)
Add-Result -Check 'cooldown_no_retrigger_cycle2' -Expected '1' -Actual $cooldownAlertsAfterCycle2.ToString() -Pass ($cooldownAlertsAfterCycle2 -eq 1)

# --- 7h: Failed webhook handling (DB_CONN_LOST posts to unreachable localhost:19999) ---
Write-LogMessage "7h: Failed webhook handling..." -Level INFO

$failedAlerts = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST Alert%' AND success = false;")
$expFailed = $script:Exp['failed_webhook_recorded']
Add-Result -Check 'failed_webhook_recorded' -Expected $expFailed.ToString() -Actual $failedAlerts.ToString() -Pass ($failedAlerts -eq $expFailed)

$failedWithError = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST Alert%' AND success = false AND error_message IS NOT NULL AND error_message != '';")
$expFailedErr = $script:Exp['failed_webhook_has_error_msg']
Add-Result -Check 'failed_webhook_has_error_msg' -Expected $expFailedErr.ToString() -Actual $failedWithError.ToString() -Pass ($failedWithError -eq $expFailedErr)

if ($failedAlerts -gt 0) {
    $sampleError = Invoke-PgScalar -Query "SELECT error_message FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST Alert%' AND success = false LIMIT 1;"
    Write-LogMessage "  Sample failed webhook error: $($sampleError)" -Level INFO
}

# --- 7i: Webhook payload content verification (via alert_history columns) ---
Write-LogMessage "7i: Webhook payload verification..." -Level INFO

$payloadAlerts = Invoke-PgSql -Query "SELECT success, match_count, action_type, action_taken, action_response, sample_entry_ids, error_message FROM alert_history WHERE filter_name LIKE '%WEBHOOK_PAYLOAD_VERIFY%' ORDER BY triggered_at LIMIT 1;"

if ($null -ne $payloadAlerts -and @($payloadAlerts).Count -gt 0) {
    $pa = @($payloadAlerts)[0]

    Add-Result -Check 'webhook_payload_succeeded' -Expected 'true' -Actual $pa.success.ToString() -Pass ($pa.success -eq $true)

    $expPayloadMatch = $script:Exp['webhook_payload_match_count']
    Add-Result -Check 'webhook_payload_match_count' -Expected $expPayloadMatch.ToString() -Actual "$($pa.match_count)" -Pass ([int]$pa.match_count -eq $expPayloadMatch)

    $hasActionType = $pa.action_type -eq 'webhook'
    Add-Result -Check 'webhook_payload_action_type' -Expected 'webhook' -Actual "$($pa.action_type)" -Pass $hasActionType

    $hasActionTaken = -not [string]::IsNullOrEmpty($pa.action_taken)
    Add-Result -Check 'webhook_payload_action_taken' -Expected 'non-empty' -Actual $(if ($hasActionTaken) { $pa.action_taken } else { '(empty)' }) -Pass $hasActionTaken

    $hasResponse = -not [string]::IsNullOrEmpty($pa.action_response)
    Add-Result -Check 'webhook_payload_has_response' -Expected 'non-empty' -Actual $(if ($hasResponse) { 'has response' } else { '(empty)' }) -Pass $hasResponse

    $hasSampleIds = -not [string]::IsNullOrEmpty($pa.sample_entry_ids)
    Add-Result -Check 'webhook_payload_has_sample_ids' -Expected 'non-empty' -Actual $(if ($hasSampleIds) { 'has IDs' } else { '(empty)' }) -Pass $hasSampleIds

    if ($hasSampleIds) {
        try {
            $sampleIds = $pa.sample_entry_ids | ConvertFrom-Json
            $idCount = @($sampleIds).Count
            $expIdCount = $script:Exp['webhook_payload_sample_id_count']
            Add-Result -Check 'webhook_payload_sample_id_count' -Expected $expIdCount.ToString() -Actual $idCount.ToString() -Pass ($idCount -eq $expIdCount)
        }
        catch {
            Add-Result -Check 'webhook_payload_sample_id_count' -Expected "$($script:Exp['webhook_payload_sample_id_count'])" -Actual "PARSE ERROR" -Pass $false
        }
    }
}
else {
    Write-LogMessage "No WEBHOOK_PAYLOAD_VERIFY alert found in alert_history" -Level WARN
    Add-Result -Check 'webhook_payload_succeeded' -Expected 'true' -Actual 'no record found' -Pass $false
}

# --- 7j: Cooldown filter webhook should succeed (posts to local API) ---
Write-LogMessage "7j: Cooldown filter webhook success check..." -Level INFO

$cooldownSuccess = [int](Invoke-PgScalar -Query "SELECT COUNT(*) FROM alert_history WHERE filter_name LIKE '%COOLDOWN_TEST%' AND success = true;")
Add-Result -Check 'cooldown_webhook_succeeded' -Expected '1' -Actual $cooldownSuccess.ToString() -Pass ($cooldownSuccess -eq 1)

# ============================================================================
# Cleanup: Close DB + Restore original config files
# ============================================================================
Write-Phase 'Cleanup'
Close-TestDbConnection
Stop-ProjectProcesses

if (Test-Path $tempImportConfig) {
    Move-Item $tempImportConfig $origImportConfig -Force
    Write-LogMessage "Restored original import-config.json" -Level INFO
}
if (Test-Path $tempAppSettings) {
    Move-Item $tempAppSettings $origAppSettings -Force
    Write-LogMessage "Restored original appsettings.json" -Level INFO
}

# ============================================================================
# Capture Baseline (if requested)
# ============================================================================
if ($CaptureBaseline) {
    Write-LogMessage "Capturing baseline expectations to expected-results.json..." -Level INFO

    $baselineChecks = @{
        'schema_tables'         = 'schema_tables'
        'file_import_count'     = 'file_import_count'
        'api_ingest_count'      = 'api_ingest_count'
        'stress_entries_persisted' = 'stress_entries_persisted'
        'total_log_entries'     = 'total_log_entries'
        'test_server_entries'   = 'test_server_entries'
        'prod_db01_entries'     = 'prod_db01_entries'
        'alert_trigger_entries' = 'alert_trigger_entries'
        'ordrenr_extracted'     = 'ordrenr_extracted'
        'avdnr_extracted'       = 'avdnr_extracted'
        'alertid_extracted'     = 'alertid_extracted'
        'job_executions'        = 'job_executions'
        'alert_history_records' = 'alert_history_records'
        'successful_alerts'     = 'successful_alerts'
        'order_sync_fail_alert' = 'order_sync_fail_alerts'
        'order_sync_fail_match_count' = 'order_sync_fail_match_count'
        'db_conn_lost_alert'    = 'db_conn_lost_alerts'
        'db_conn_lost_match_count' = 'db_conn_lost_match_count'
        'filters_evaluated'     = 'filters_evaluated'
        'filters_triggered'     = 'filters_triggered'
        'failed_webhook_recorded' = 'failed_webhook_recorded'
        'failed_webhook_has_error_msg' = 'failed_webhook_has_error_msg'
        'webhook_payload_match_count' = 'webhook_payload_match_count'
        'webhook_payload_sample_id_count' = 'webhook_payload_sample_id_count'
        'cooldown_webhook_succeeded' = 'cooldown_webhook_succeeded'
    }

    $baseline = [ordered]@{
        '_generated'               = "Baseline captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'). Update via: Run-RegressionTests.ps1 -CaptureBaseline"
        'stress_success_rate_min'  = 95
        'stress_rps_min'           = 10
        'stress_queue_drained'     = 0
        'stress_total_requests'    = $stressTotalRequests
        'ingest_queue_drained'     = 0
        'alert_filters_in_db'      = $expectedFilterCount
        'below_threshold_no_trigger'    = 0
        'below_threshold_was_evaluated' = 1
        'below_threshold_not_triggered' = 1
        'time_window_no_trigger'        = 0
        'time_window_was_evaluated'     = 1
        'time_window_not_triggered'     = 1
        'cooldown_triggered_cycle1'     = 1
        'cooldown_no_retrigger_cycle2'  = 1
    }

    foreach ($checkName in $baselineChecks.Keys) {
        $expKey = $baselineChecks[$checkName]
        if ($script:Results.ContainsKey($checkName)) {
            $val = $script:Results[$checkName].Actual
            try { $baseline[$expKey] = [int]$val } catch { $baseline[$expKey] = $val }
        }
    }

    $baseline | ConvertTo-Json -Depth 5 | Set-Content $script:ExpFile -Encoding utf8
    Write-LogMessage "Baseline saved with $($baseline.Count) expectations to $($script:ExpFile)" -Level INFO
}

# ============================================================================
# Report Generation
# ============================================================================
Write-Phase 'Report Generation'

$endTime = Get-Date
$duration = $endTime - $script:StartTime

$passCount = @($script:Results.Values | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = @($script:Results.Values | Where-Object { $_.Status -eq 'FAIL' }).Count
$totalChecks = $script:Results.Count
$overallStatus = if ($failCount -eq 0) { 'ALL PASS' } else { 'FAILED' }

$report = @"
=======================================================================
  GenericLogHandler Regression Test Report
=======================================================================
  Date:     $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))
  Duration: $($duration.ToString('hh\:mm\:ss'))
  Result:   $($overallStatus) ($($passCount)/$($totalChecks) passed, $($failCount) failed)
=======================================================================

Detailed Results:
-----------------------------------------------------------------------

"@

foreach ($check in $script:Results.Keys) {
    $r = $script:Results[$check]
    $statusIcon = if ($r.Status -eq 'PASS') { '[OK]  ' } else { '[FAIL]' }
    $report += "  $($statusIcon) $($check)`n"
    $report += "           Expected: $($r.Expected)`n"
    $report += "           Actual:   $($r.Actual)`n"
    $report += "`n"
}

$report += @"
-----------------------------------------------------------------------
  Summary: $($passCount) passed, $($failCount) failed out of $($totalChecks) checks
  Overall: $($overallStatus)
=======================================================================
"@

# Write report to file and console
$report | Out-File $script:ReportFile -Encoding utf8
Write-Host $report

# SMS notification
if (-not $NoSms -and $duration.TotalMinutes -ge 5) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $smsMsg = "GLH Regression: $($overallStatus). $($passCount)/$($totalChecks) pass. $($duration.ToString('mm\:ss'))."
    try {
        Send-Sms -Receiver $smsNumber -Message $smsMsg
        Write-LogMessage "SMS sent to $($smsNumber)" -Level INFO
    }
    catch {
        Write-LogMessage "SMS send failed: $($_.Exception.Message)" -Level WARN
    }
}

# Return exit code
if ($failCount -gt 0) {
    Write-LogMessage "REGRESSION TESTS FAILED: $($failCount) failures" -Level ERROR
    exit 1
}
else {
    Write-LogMessage "REGRESSION TESTS PASSED: All $($totalChecks) checks passed" -Level INFO
    exit 0
}
