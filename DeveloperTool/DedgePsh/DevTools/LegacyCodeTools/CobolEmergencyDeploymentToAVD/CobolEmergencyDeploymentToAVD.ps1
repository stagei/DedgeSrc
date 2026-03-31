<#
.SYNOPSIS
    Emergency COBOL Production Deployment to AVD Workstations.

.DESCRIPTION
    This script distributes files from the central COBNT share (\\DEDGE.fk.no\erpprog\COBNT)
    to all online AVD workstations (p-no1avd-wrk001 through p-no1avd-wrk150) using parallel
    robocopy operations. Only newer files are copied from the root directory (non-recursive),
    and no files are deleted on either side. File extensions are hardcoded based on 
    \\p-no1avd-wrk003\COBNT.
    
    SAFETY GUARANTEES:
    - Robocopy NEVER modifies source files (read-only from source)
    - Uses /XO flag (only copies newer files, never deletes)
    - No /PURGE, /MIR, /S, or /E flags (no deletion, non-recursive - root directory only)
    - Use -TestOutputFolder for safe local testing

.PARAMETER StartNumber
    Starting machine number. Defaults to 1.

.PARAMETER EndNumber
    Ending machine number. Defaults to 150.

.PARAMETER SourcePath
    Source path for COBNT files. Defaults to \\DEDGE.fk.no\erpprog\COBNT.


.PARAMETER ThrottleLimit
    Number of parallel threads for robocopy operations. Defaults to 32.

.PARAMETER TestOutputFolder
    Local folder path for test mode. When specified, copies to this local folder instead of AVD workstations.
    Useful for testing and verification without deploying to production machines.
    Defaults to empty (production mode). Example: "C:\temp\COBNT_Test"

.EXAMPLE
    .\CobolObjects-ProductionsEmergencyDeploymentToAVD.ps1
    Distributes files to all machines 001-150

.EXAMPLE
    .\CobolObjects-ProductionsEmergencyDeploymentToAVD.ps1 -StartNumber 1 -EndNumber 50 -ThrottleLimit 50
    Distributes files to machines 001-050 with 50 parallel threads

.EXAMPLE
    .\CobolObjects-ProductionsEmergencyDeploymentToAVD.ps1 -TestOutputFolder "C:\temp\COBNT_Test"
    Test mode: Copies files to local folder for verification

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$StartNumber = 1,

    [Parameter(Mandatory = $false)]
    [int]$EndNumber = 150,

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "\\DEDGE.fk.no\erpprog\COBNT",

    [Parameter(Mandatory = $false)]
    [int]$ThrottleLimit = 32,

    [Parameter(Mandatory = $false)]
    [string]$TestOutputFolder = ""
)

Import-Module GlobalFunctions -Force

# Initialize comprehensive WorkObject for tracking
$script:WorkObject = [PSCustomObject]@{
    Name = "EmergencyCobolDeployProduction"
    Description = "Emergency COBOL Production Deployment to AVD Workstations"
    ScriptPath = $PSCommandPath
    ExecutionTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ExecutionUser = "$env:USERDOMAIN\$env:USERNAME"
    ComputerName = $env:COMPUTERNAME
    Success = $false
    Status = "Running"
    ErrorMessage = $null
    ExtensionsDiscovered = $false
    SharesFound = $false
    DistributionStarted = $false
    DistributionCompleted = $false
    TotalMachinesScanned = 0
    OnlineMachines = 0
    AvailableShares = 0
    TotalFilesCopied = 0
    TotalFilesSkipped = 0
    TotalFilesFailed = 0
    MachinesSucceeded = 0
    MachinesFailed = 0
    DiscoveredExtensions = @()
    TestMode = $false
    TestOutputFolder = $null
    StartTime = Get-Date
    EndTime = $null
    Duration = $null
    ScriptArray = @()
    MachineResults = @()
}

$shareName = "COBNT"
$startTime = Get-Date

# =========================================================================
# Hardcoded file extensions based on distinct extensions found in \\p-no1avd-wrk003\COBNT
# =========================================================================
$extensions = @(
    ".BND",   # Bind files
    ".GS",    # Object files (generated)
    ".INT",   # Intermediate object files
    ".REX",   # REXX scripts
    ".BAT"    # Batch files
)

# Check if test mode is enabled
$isTestMode = -not [string]::IsNullOrWhiteSpace($TestOutputFolder)
if ($isTestMode) {
    $script:WorkObject.TestMode = $true
    $script:WorkObject.TestOutputFolder = $TestOutputFolder
    # Ensure test folder exists
    if (-not (Test-Path -Path $TestOutputFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $TestOutputFolder -Force | Out-Null
        Write-LogMessage "Created test output folder: $TestOutputFolder" -Level INFO
    }
}

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED
Write-LogMessage "=============================================" -Level INFO
if ($isTestMode) {
    Write-LogMessage "  Emergency COBOL Production Deployment - TEST MODE" -Level INFO
}
else {
    Write-LogMessage "  Emergency COBOL Production Deployment to AVD" -Level INFO
}
Write-LogMessage "=============================================" -Level INFO
Write-LogMessage "Source: $SourcePath" -Level INFO
if ($isTestMode) {
    Write-LogMessage "Test mode: ENABLED" -Level INFO
    Write-LogMessage "Test output folder: $TestOutputFolder" -Level INFO
}
else {
    Write-LogMessage "Machine range: p-no1avd-wrk$($StartNumber.ToString('000')) - p-no1avd-wrk$($EndNumber.ToString('000'))" -Level INFO
}
Write-LogMessage "Parallel threads: $ThrottleLimit" -Level INFO

# Generate machine names
$machines = $StartNumber..$EndNumber | ForEach-Object {
    "p-no1avd-wrk$($_.ToString('000'))"
}
$script:WorkObject.TotalMachinesScanned = $machines.Count

# =========================================================================
# STEP 1: Use hardcoded file extensions
# =========================================================================
Write-LogMessage "Using hardcoded file extensions based on \\p-no1avd-wrk003\COBNT" -Level DEBUG
$script:WorkObject.ExtensionsDiscovered = $true
$script:WorkObject.DiscoveredExtensions = $extensions

$extensionOutput = @(
    "Hardcoded extensions (based on \\p-no1avd-wrk003\COBNT):",
    "Extensions: $($extensions -join ', ')"
)

$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
    -Name "Extension-Configuration" `
    -Script "Hardcoded extensions: $($extensions -join ', ')" `
    -Output ($extensionOutput -join "`n")

if ($extensions.Count -eq 0) {
    Write-LogMessage "No file extensions configured" -Level ERROR
    $script:WorkObject.ErrorMessage = "No file extensions configured"
    $script:WorkObject.Status = "Failed"
    throw "No file extensions configured"
}

# =========================================================================
# STEP 2: Discover available COBNT shares (or setup test mode)
# =========================================================================
if ($isTestMode) {
    Write-LogMessage "Test mode: Using local test folder instead of share discovery" -Level INFO
    $availableSharesList = @([PSCustomObject]@{
        MachineName = "TEST-LOCAL"
        SharePath   = $TestOutputFolder
        Available   = $true
        CheckedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    })
    $script:WorkObject.SharesFound = $true
    $script:WorkObject.OnlineMachines = 1
    $script:WorkObject.AvailableShares = 1
    
    $shareDiscoveryOutput = @(
        "Test mode: ENABLED",
        "Test output folder: $TestOutputFolder",
        "Skipping network share discovery"
    )
    
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
        -Name "Share-Discovery" `
        -Script "Test mode - using local folder" `
        -Output ($shareDiscoveryOutput -join "`n")
}
else {
    Write-LogMessage "Discovering available COBNT shares..." -Level DEBUG
    $availableShares = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    $machines | ForEach-Object -Parallel {
        $machine = $_
        $shareName = $using:shareName
        $bag = $using:availableShares
        
        Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
        Initialize-GlobalFunctionsForParallel -ErrorAction SilentlyContinue
        
        try {
            $ping = Test-Connection -ComputerName $machine -Count 1 -Quiet -TimeoutSeconds 1 -ErrorAction SilentlyContinue
            
            if ($ping) {
                $uncPath = "\\$machine\$shareName"
                if (Test-Path -Path $uncPath -ErrorAction SilentlyContinue) {
                    $shareInfo = [PSCustomObject]@{
                        MachineName = $machine
                        SharePath   = $uncPath
                        Available   = $true
                        CheckedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $bag.Add($shareInfo)
                }
            }
        }
        catch {
            # Silently skip errors
        }
    } -ThrottleLimit $ThrottleLimit

    $availableSharesList = $availableShares.ToArray() | Sort-Object MachineName
    $script:WorkObject.SharesFound = $true
    $script:WorkObject.OnlineMachines = ($availableSharesList | Where-Object { $_.Available }).Count
    $script:WorkObject.AvailableShares = $availableSharesList.Count

    $shareDiscoveryOutput = @(
        "Total machines scanned: $($machines.Count)",
        "Online machines with COBNT share: $($availableSharesList.Count)",
        "Available shares:"
    ) + ($availableSharesList | ForEach-Object { "  - $($_.MachineName): $($_.SharePath)" })

    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
        -Name "Share-Discovery" `
        -Script "Parallel share discovery on $($machines.Count) machines" `
        -Output ($shareDiscoveryOutput -join "`n")

    if ($availableSharesList.Count -eq 0) {
        Write-LogMessage "No available shares found - cannot proceed with distribution" -Level ERROR
        $script:WorkObject.ErrorMessage = "No available COBNT shares found"
        $script:WorkObject.Status = "Failed"
        throw "No available COBNT shares found"
    }
}

# =========================================================================
# STEP 3: Parallel robocopy distribution
# =========================================================================
Write-LogMessage "Starting parallel file distribution..." -Level DEBUG
$script:WorkObject.DistributionStarted = $true

# Build include filters for robocopy
# Robocopy expects unquoted wildcard patterns as separate arguments
$includeFilters = $extensions | ForEach-Object { "*$_" }

# Thread-safe collections for results
$machineResults = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
$totalFilesCopied = [ref]0
$totalFilesSkipped = [ref]0
$totalFilesFailed = [ref]0
$machinesSucceeded = [ref]0
$machinesFailed = [ref]0

$availableSharesList | ForEach-Object -Parallel {
    $share = $_
    $sourcePath = $using:SourcePath
    $includeFilters = $using:includeFilters
    $resultsBag = $using:machineResults
    $copiedRef = $using:totalFilesCopied
    $skippedRef = $using:totalFilesSkipped
    $failedRef = $using:totalFilesFailed
    $succeededRef = $using:machinesSucceeded
    $failedCountRef = $using:machinesFailed
    $isTestMode = $using:isTestMode
    
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
    Initialize-GlobalFunctionsForParallel -ErrorAction SilentlyContinue
    
    $machineResult = [PSCustomObject]@{
        MachineName = $share.MachineName
        SharePath = $share.SharePath
        Success = $false
        FilesCopied = 0
        FilesSkipped = 0
        FilesFailed = 0
        ExitCode = -1
        ErrorMessage = $null
        StartTime = Get-Date
        EndTime = $null
        Duration = $null
    }
    
    try {
        # Build robocopy arguments
        # SOURCE is ALWAYS \\DEDGE.fk.no\erpprog\COBNT (never changes)
        # DESTINATION is $share.SharePath (test folder in test mode, or \\p-no1avd-wrk***\COBNT in production)
        $robocopyArgs = @(
            $sourcePath      # SOURCE: Always \\DEDGE.fk.no\erpprog\COBNT
            $share.SharePath # DESTINATION: Test folder or AVD workstation share
        ) + $includeFilters + @(
            "/XO"    # Only newer files
            "/R:3"   # 3 retries
            "/W:1"   # Wait time
            "/NFL"   # No file list
            "/NDL"   # No directory list
            "/NJH"   # No job header
            "/NJS"   # No job summary
        )
        
        # Log the exact robocopy command for verification (only in test mode)
        if ($isTestMode) {
            $cmdLine = "robocopy `"$sourcePath`" `"$($share.SharePath)`" $($includeFilters -join ' ') /XO /R:3 /W:1 /NFL /NDL /NJH /NJS"
            Write-LogMessage "[$($share.MachineName)] SOURCE: $sourcePath -> DESTINATION: $($share.SharePath)" -Level INFO
            Write-LogMessage "[$($share.MachineName)] Robocopy command: $cmdLine" -Level INFO
        }
        
        # Execute robocopy
        $robocopyOutput = & robocopy @robocopyArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        $machineResult.ExitCode = $exitCode
        $machineResult.EndTime = Get-Date
        $machineResult.Duration = $machineResult.EndTime - $machineResult.StartTime
        
        # Parse robocopy output for statistics
        foreach ($line in $robocopyOutput) {
            $lineStr = $line.ToString()
            if ($lineStr -match '^\s*Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
                # Format: Total Copied Skipped Mismatch Failed Extras
                $machineResult.FilesCopied = [int]$Matches[2]
                $machineResult.FilesSkipped = [int]$Matches[3]
                $machineResult.FilesFailed = [int]$Matches[5]
            }
        }
        
        # Robocopy exit codes: 0-7 are success, 8+ are errors
        if ($exitCode -le 7) {
            $machineResult.Success = $true
            [System.Threading.Interlocked]::Add($copiedRef, $machineResult.FilesCopied) | Out-Null
            [System.Threading.Interlocked]::Add($skippedRef, $machineResult.FilesSkipped) | Out-Null
            [System.Threading.Interlocked]::Add($failedRef, $machineResult.FilesFailed) | Out-Null
            [System.Threading.Interlocked]::Increment($succeededRef) | Out-Null
        }
        else {
            $machineResult.Success = $false
            $machineResult.ErrorMessage = "Robocopy exit code: $exitCode"
            [System.Threading.Interlocked]::Increment($failedCountRef) | Out-Null
        }
    }
    catch {
        $machineResult.Success = $false
        $machineResult.ErrorMessage = $_.Exception.Message
        $machineResult.EndTime = Get-Date
        $machineResult.Duration = $machineResult.EndTime - $machineResult.StartTime
        [System.Threading.Interlocked]::Increment($failedCountRef) | Out-Null
    }
    
    $resultsBag.Add($machineResult)
} -ThrottleLimit $ThrottleLimit

# Collect results
$script:WorkObject.MachineResults = $machineResults.ToArray() | Sort-Object MachineName
$script:WorkObject.TotalFilesCopied = $totalFilesCopied.Value
$script:WorkObject.TotalFilesSkipped = $totalFilesSkipped.Value
$script:WorkObject.TotalFilesFailed = $totalFilesFailed.Value
$script:WorkObject.MachinesSucceeded = $machinesSucceeded.Value
$script:WorkObject.MachinesFailed = $machinesFailed.Value
$script:WorkObject.DistributionCompleted = $true

$endTime = Get-Date
$script:WorkObject.EndTime = $endTime
$script:WorkObject.Duration = $endTime - $startTime

Write-LogMessage "Distribution completed" -Level INFO
Write-LogMessage "Summary:" -Level INFO
Write-LogMessage "  Machines succeeded: $($script:WorkObject.MachinesSucceeded)" -Level INFO
Write-LogMessage "  Machines failed: $($script:WorkObject.MachinesFailed)" -Level INFO
Write-LogMessage "  Total files copied: $($script:WorkObject.TotalFilesCopied)" -Level INFO
Write-LogMessage "  Total files skipped: $($script:WorkObject.TotalFilesSkipped)" -Level INFO
if ($script:WorkObject.TotalFilesFailed -gt 0) {
    Write-LogMessage "  Total files failed: $($script:WorkObject.TotalFilesFailed)" -Level WARN
}
Write-LogMessage "  Duration: $($script:WorkObject.Duration.ToString('hh\:mm\:ss'))" -Level INFO

# Build distribution output for WorkObject
$modeDescription = if ($isTestMode) { 
    "Mode: TEST (local folder)" 
} else { 
    "Mode: PRODUCTION (AVD workstations)" 
}

$distributionOutput = @(
    "Source: $SourcePath",
    "Extensions filtered: $($extensions -join ', ')",
    $modeDescription,
    "Machines processed: $($script:WorkObject.MachineResults.Count)",
    "Machines succeeded: $($script:WorkObject.MachinesSucceeded)",
    "Machines failed: $($script:WorkObject.MachinesFailed)",
    "Total files copied: $($script:WorkObject.TotalFilesCopied)",
    "Total files skipped: $($script:WorkObject.TotalFilesSkipped)",
    "Total files failed: $($script:WorkObject.TotalFilesFailed)",
    "",
    "Per-machine results:"
) + ($script:WorkObject.MachineResults | ForEach-Object {
    "  $($_.MachineName): Success=$($_.Success) Copied=$($_.FilesCopied) Skipped=$($_.FilesSkipped) Failed=$($_.FilesFailed) ExitCode=$($_.ExitCode)"
})

$robocopyScript = "robocopy `"$SourcePath`" `"<destination>`" $($includeFilters -join ' ') /XO /R:3 /W:1 /NFL /NDL /NJH /NJS"
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
    -Name "File-Distribution" `
    -Script $robocopyScript `
    -Output ($distributionOutput -join "`n")

# =========================================================================
# STEP 3.5: Verify copied files (especially useful in test mode)
# =========================================================================
if ($isTestMode -and (Test-Path -Path $TestOutputFolder -PathType Container)) {
    Write-LogMessage "Verifying copied files in test folder..." -Level INFO
    try {
        $copiedFiles = Get-ChildItem -Path $TestOutputFolder -File -ErrorAction SilentlyContinue
        $filesByExtension = $copiedFiles | Group-Object Extension | Sort-Object Name
        
        $verificationOutput = @(
            "Test folder: $TestOutputFolder",
            "Total files copied: $($copiedFiles.Count)",
            "",
            "Files by extension:"
        ) + ($filesByExtension | ForEach-Object {
            "  $($_.Name): $($_.Count) file(s)"
        })
        
        if ($copiedFiles.Count -gt 0) {
            $verificationOutput += @(
                "",
                "Sample files (first 20):"
            ) + ($copiedFiles | Select-Object -First 20 | ForEach-Object {
                "  $($_.Name) ($([math]::Round($_.Length / 1KB, 2)) KB)"
            })
        }
        
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
            -Name "File-Verification" `
            -Script "Get-ChildItem -Path `"$TestOutputFolder`" -File" `
            -Output ($verificationOutput -join "`n")
        
        Write-LogMessage "Verification complete: $($copiedFiles.Count) files found in test folder" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to verify copied files: $($_.Exception.Message)" -Level WARN -Exception $_
    }
}

# =========================================================================
# STEP 4: Export HTML report
# =========================================================================
try {
    $script:WorkObject.Success = ($script:WorkObject.MachinesFailed -eq 0)
    $script:WorkObject.Status = if ($script:WorkObject.Success) { "Completed" } else { "Completed with errors" }
    
    # Add timestamp to filename: EmergencyCobolDeployProduction-<yyyymmdd-hhmmss>.html
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $baseFileName = if ($script:WorkObject.Success) {
        "EmergencyCobolDeployProduction"
    }
    else {
        "EmergencyCobolDeployProduction_FAILED"
    }
    $reportFileName = "$baseFileName-$timestamp.html"
    
    $reportPath = Join-Path (Get-ApplicationDataPath) $reportFileName
    $reportTitle = if ($script:WorkObject.Success) {
        "Emergency COBOL Production Deployment to AVD"
    }
    else {
        "Emergency COBOL Production Deployment to AVD - FAILED"
    }
    
    Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject `
        -FileName $reportPath `
        -Title $reportTitle `
        -AddToDevToolsWebPath $true `
        -DevToolsWebDirectory "JobReports" `
        -AutoOpen $true
    
    Write-LogMessage "HTML report exported to: $reportPath" -Level INFO
    Write-LogMessage "Opening HTML report..." -Level INFO
}
catch {
    Write-LogMessage "Failed to export HTML report: $($_.Exception.Message)" -Level WARN -Exception $_
}

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level $(if ($script:WorkObject.Success) { "JOB_COMPLETED" } else { "JOB_FAILED" })

# Return WorkObject for pipeline use
return $script:WorkObject
