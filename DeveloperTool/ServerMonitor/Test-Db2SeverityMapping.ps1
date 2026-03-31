<#
.SYNOPSIS
    Proves the DB2 diagnostic severity mapping concept by analyzing test.txt
.DESCRIPTION
    Parses DB2 diagnostic entries and demonstrates:
    1. How to identify patterns using regex
    2. How to remap DB2 severity levels to appropriate ServerMonitor levels
    3. How to filter out noise messages
    4. Validates the patterns configured in appsettings.json
.EXAMPLE
    .\Test-Db2SeverityMapping.ps1 -InputFile "test.txt"
.EXAMPLE
    .\Test-Db2SeverityMapping.ps1 -UseConfigPatterns
#>
param(
    [string]$InputFile = "C:\opt\src\ServerMonitor\test.txt",
    [switch]$UseConfigPatterns
)

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Analyzing DB2 diagnostic entries for severity remapping`n" -ForegroundColor Cyan

#region Configuration - Severity Remapping Rules

# Patterns to IGNORE (filter out completely)
$ExclusionPatterns = @(
    @{
        Name = "STMM-AutoTuning"
        Description = "Self Tuning Memory Manager automatic configuration changes"
        # Regex breakdown:
        #   CHANGE\s*:      - Match "CHANGE :" with flexible whitespace
        #   \s*             - Optional whitespace after colon
        #   (APM|STMM)      - Match either APM or STMM component
        #   .*?             - Non-greedy match any characters
        #   (success|automatic) - Match success or automatic keyword
        Regex = 'CHANGE\s*:\s*(APM|STMM).*?(success|automatic)'
    },
    @{
        Name = "PackageCacheResize"
        Description = "Access Plan Manager package cache resize operations"
        # Regex breakdown:
        #   FUNCTION:\s*    - Match "FUNCTION:" with whitespace
        #   DB2 UDB,\s*     - Match component prefix
        #   access plan manager - Match APM subcomponent
        #   .*              - Any characters
        #   sqlra_resize_pckcache - Match the specific function name
        Regex = 'FUNCTION:\s*DB2 UDB,\s*access plan manager.*sqlra_resize_pckcache'
    },
    @{
        Name = "ConfigParamUpdate"
        Description = "Automatic configuration parameter adjustments"
        # Regex breakdown:
        #   FUNCTION:\s*    - Match "FUNCTION:" with whitespace
        #   DB2 UDB,\s*     - Match component prefix
        #   config/install  - Match config subcomponent
        #   .*              - Any characters
        #   sqlfLogUpdateCfgParam - Match the specific function name
        Regex = 'FUNCTION:\s*DB2 UDB,\s*config/install.*sqlfLogUpdateCfgParam'
    },
    @{
        Name = "NewDiagLogFile"
        Description = "New diagnostic log file started (rotation)"
        # Regex breakdown:
        #   START\s*:       - Match "START :" with flexible whitespace
        #   \s*             - Optional whitespace
        #   New Diagnostic Log file - Exact message text
        Regex = 'START\s*:\s*New Diagnostic Log file'
    }
)

# Patterns to REMAP severity
$SeverityRemapping = @(
    @{
        Name = "ForeignKeyViolation"
        Description = "SQL0530N - Foreign key constraint violation (expected in federated ops)"
        # Regex breakdown:
        #   SQL0530N        - Exact SQL error code for FK violations
        Regex = 'SQL0530N'
        Db2Level = "Error"
        RemappedLevel = "Informational"
    },
    @{
        Name = "DeadlockRollback"
        Description = "SQL0911N - Deadlock/timeout (transient, application retries)"
        # Regex breakdown:
        #   SQL0911N        - Exact SQL error code for deadlock/rollback
        Regex = 'SQL0911N'
        Db2Level = "Error"
        RemappedLevel = "Warning"
    },
    @{
        Name = "ClientTermination"
        Description = "Normal client disconnection detected"
        # Regex breakdown:
        #   MESSAGE\s*:     - Match "MESSAGE :" with flexible whitespace
        #   \s*             - Optional whitespace
        #   Detected client termination - Exact message text
        Regex = 'MESSAGE\s*:\s*Detected client termination'
        Db2Level = "Error"
        RemappedLevel = "Informational"
    },
    @{
        Name = "ConnectionTestFailure"
        Description = "TCP/connection test - client gone (benign)"
        # Regex breakdown:
        #   FUNCTION:\s*    - Match "FUNCTION:" with whitespace
        #   DB2 UDB,\s*     - Match component prefix
        #   common communication,\s* - Match communication subcomponent
        #   sqlcc           - Match SQL communication function prefix
        #   (tcptest|test)  - Match either tcptest or test variant
        Regex = 'FUNCTION:\s*DB2 UDB,\s*common communication,\s*sqlcc(tcptest|test)'
        Db2Level = "Error"
        RemappedLevel = "Informational"
    },
    @{
        Name = "AgentBreathingPoint"
        Description = "Agent detected client disconnection"
        # Regex breakdown:
        #   AgentBreathingPoint - Match the function name
        #   .*              - Any characters between
        #   ZRC=0x00000036  - Match the specific ZRC code (54 = client gone)
        Regex = 'AgentBreathingPoint.*ZRC=0x00000036'
        Db2Level = "Error"
        RemappedLevel = "Informational"
    },
    @{
        Name = "DRDAProbe20"
        Description = "DRDA wrapper errors (standard severity)"
        # Regex breakdown:
        #   drda wrapper,\s* - Match DRDA wrapper subcomponent
        #   report_error_message,\s* - Match error reporting function
        #   probe:20        - Match probe number 20 (standard severity)
        Regex = 'drda wrapper,\s*report_error_message,\s*probe:20'
        Db2Level = "Error"
        RemappedLevel = "Warning"
    }
)

#endregion

#region Analysis Functions

function Get-Db2Level {
    param([string]$Block)
    if ($Block -match 'LEVEL:\s*(\w+)') {
        return $Matches[1]
    }
    return "Unknown"
}

function Test-ExclusionPattern {
    param([string]$Block)
    foreach ($pattern in $ExclusionPatterns) {
        if ($Block -match $pattern.Regex) {
            return $pattern
        }
    }
    return $null
}

function Get-RemappedSeverity {
    param([string]$Block)
    foreach ($rule in $SeverityRemapping) {
        if ($Block -match $rule.Regex) {
            return $rule
        }
    }
    return $null
}

function Get-SqlCode {
    param([string]$Block)
    # Regex breakdown:
    #   SQL             - Literal "SQL" prefix
    #   (\d{4,5})       - Group 1: 4-5 digit error number
    #   ([A-Z]?)        - Group 2: Optional severity letter
    if ($Block -match 'SQL(\d{4,5})([A-Z]?)') {
        return "SQL$($Matches[1])$($Matches[2])"
    }
    return $null
}

#endregion

#region Main Analysis

Write-Host "Reading file: $InputFile" -ForegroundColor Gray
$content = Get-Content $InputFile -Raw
$blocks = $content -split '========================================'
$totalBlocks = ($blocks | Where-Object { $_.Trim() }).Count

Write-Host "Total entries: $totalBlocks`n" -ForegroundColor Green

# Initialize counters
$stats = @{
    Total = 0
    ByDb2Level = @{}
    Excluded = @{}
    Remapped = @{}
    Kept = @{
        Error = 0
        Warning = 0
        Informational = 0
        Event = 0
    }
}

$results = @()

foreach ($block in $blocks) {
    if (-not $block.Trim()) { continue }
    $stats.Total++
    
    $db2Level = Get-Db2Level $block
    $sqlCode = Get-SqlCode $block
    
    # Count by DB2 level
    if (-not $stats.ByDb2Level.ContainsKey($db2Level)) {
        $stats.ByDb2Level[$db2Level] = 0
    }
    $stats.ByDb2Level[$db2Level]++
    
    # Check exclusion
    $exclusion = Test-ExclusionPattern $block
    if ($exclusion) {
        if (-not $stats.Excluded.ContainsKey($exclusion.Name)) {
            $stats.Excluded[$exclusion.Name] = 0
        }
        $stats.Excluded[$exclusion.Name]++
        continue
    }
    
    # Check remapping
    $remapping = Get-RemappedSeverity $block
    $finalLevel = $db2Level
    
    if ($remapping) {
        $finalLevel = $remapping.RemappedLevel
        if (-not $stats.Remapped.ContainsKey($remapping.Name)) {
            $stats.Remapped[$remapping.Name] = 0
        }
        $stats.Remapped[$remapping.Name]++
    }
    
    # Count final levels
    if ($stats.Kept.ContainsKey($finalLevel)) {
        $stats.Kept[$finalLevel]++
    } else {
        $stats.Kept[$finalLevel] = 1
    }
    
    # Store for detailed output
    $results += [PSCustomObject]@{
        Db2Level = $db2Level
        SqlCode = $sqlCode
        FinalLevel = $finalLevel
        Remapped = ($null -ne $remapping)
        Rule = if ($remapping) { $remapping.Name } else { $null }
    }
}

#endregion

#region Output Results

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "                    DB2 SEVERITY MAPPING ANALYSIS" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan

Write-Host "`n📊 ORIGINAL DB2 LEVELS:" -ForegroundColor Yellow
foreach ($level in $stats.ByDb2Level.Keys | Sort-Object) {
    $count = $stats.ByDb2Level[$level]
    $pct = [math]::Round(($count / $stats.Total) * 100, 1)
    Write-Host "   $($level): $count ($($pct)%)"
}

Write-Host "`n🗑️  EXCLUDED (filtered out):" -ForegroundColor Yellow
$totalExcluded = 0
foreach ($name in $stats.Excluded.Keys | Sort-Object { $stats.Excluded[$_] } -Descending) {
    $count = $stats.Excluded[$name]
    $totalExcluded += $count
    $pattern = $ExclusionPatterns | Where-Object { $_.Name -eq $name }
    Write-Host "   [$count] $name" -ForegroundColor DarkGray
    Write-Host "         $($pattern.Description)" -ForegroundColor DarkGray
}
Write-Host "   ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "   TOTAL EXCLUDED: $totalExcluded entries" -ForegroundColor Red

Write-Host "`n🔄 REMAPPED (severity changed):" -ForegroundColor Yellow
$totalRemapped = 0
foreach ($name in $stats.Remapped.Keys | Sort-Object { $stats.Remapped[$_] } -Descending) {
    $count = $stats.Remapped[$name]
    $totalRemapped += $count
    $rule = $SeverityRemapping | Where-Object { $_.Name -eq $name }
    Write-Host "   [$count] $name" -ForegroundColor Cyan
    Write-Host "         $($rule.Db2Level) → $($rule.RemappedLevel)" -ForegroundColor Cyan
    Write-Host "         $($rule.Description)" -ForegroundColor Gray
}
Write-Host "   ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "   TOTAL REMAPPED: $totalRemapped entries" -ForegroundColor Cyan

Write-Host "`n✅ FINAL SERVERMONITOR LEVELS (after filtering & remapping):" -ForegroundColor Yellow
$remaining = $stats.Total - $totalExcluded
foreach ($level in @("Error", "Warning", "Informational", "Event")) {
    $count = $stats.Kept[$level]
    if ($count -gt 0) {
        $pct = [math]::Round(($count / $remaining) * 100, 1)
        $color = switch ($level) {
            "Error" { "Red" }
            "Warning" { "Yellow" }
            "Informational" { "Gray" }
            "Event" { "DarkGray" }
            default { "White" }
        }
        Write-Host "   $($level): $count ($($pct)%)" -ForegroundColor $color
    }
}

Write-Host "`n📈 SUMMARY:" -ForegroundColor Green
Write-Host "   Total entries analyzed:  $($stats.Total)"
Write-Host "   Entries EXCLUDED:        $totalExcluded ($(([math]::Round(($totalExcluded / $stats.Total) * 100, 1)))%)" -ForegroundColor Red
Write-Host "   Entries REMAPPED:        $totalRemapped ($(([math]::Round(($totalRemapped / $stats.Total) * 100, 1)))%)" -ForegroundColor Cyan
Write-Host "   Entries remaining:       $remaining ($(([math]::Round(($remaining / $stats.Total) * 100, 1)))%)" -ForegroundColor Green

# Calculate noise reduction
$originalErrors = $stats.ByDb2Level["Error"]
$finalErrors = $stats.Kept["Error"]
if ($originalErrors -gt 0) {
    $errorReduction = [math]::Round((1 - ($finalErrors / $originalErrors)) * 100, 1)
    Write-Host "`n🎯 ERROR NOISE REDUCTION:" -ForegroundColor Magenta
    Write-Host "   Original DB2 Errors: $originalErrors"
    Write-Host "   Final Errors:        $finalErrors"
    Write-Host "   Reduction:           $($errorReduction)%" -ForegroundColor Green
}

Write-Host "`n" + "=" * 70 -ForegroundColor Cyan

#endregion

Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round(((Get-Date) - $startTime).TotalSeconds, 1))s" -ForegroundColor Yellow
