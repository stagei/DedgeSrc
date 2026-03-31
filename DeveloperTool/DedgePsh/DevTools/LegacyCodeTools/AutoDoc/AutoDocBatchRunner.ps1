# Author: Geir Helge Starholm, Dedge AS
# Title: Batch runner of AutoDoc.ps1
# Description: This script is used to generate flowcharts from cobol, Powershell, Object-Rexx,
#              Windows Batch and Sql code, to generate a json file that is used by the web page
#              to show the list of all generated flowcharts.
#              The script is run by a scheduled task on a daily basis.
#              The script is run by a user with administrator rights.
#              The script is run by a user with db2 rights.
#              The script is run by a user with git rights.
#              The script is run by a user with write access to the web folder.

param(
    # Regeneration mode:
    #   Incremental = Changed/missing files only (default) - no deletions
    #   All         = Regenerate everything (overwrite existing) - no deletions
    #   Errors      = Only files with previous errors (.err files) - no deletions
    #   JsonOnly    = Only regenerate JSON index files - no deletions
    #   Single      = One specific file (use with -SingleFile) - no deletions
    #   Clean       = FULL RESET: Delete generated files, clear tmp/git, then regenerate all
    #                 Preserves: _images/, _js/, _css/ folders, index.html, web.config
    [Parameter(Mandatory = $false)]
    [ValidateSet('Incremental', 'All', 'Errors', 'JsonOnly', 'Single', 'Clean')]
    [string]$Regenerate = "Incremental",
    
    # Single file mode: requires -Regenerate Single (e.g., "AABELMA.CBL" or full path)
    [string]$SingleFile = "",
    
    # Filter by file type(s) - process only specified types
    # Default: All types. Use array for multiple: @('Cbl', 'Sql')
    # Types: Cbl (COBOL), Rex (REXX), Bat (Batch), Ps1 (PowerShell), Sql (SQL tables), CSharp (C# projects)
    [Parameter(Mandatory = $false)]
    [ValidateSet('Cbl', 'Rex', 'Bat', 'Ps1', 'Sql', 'CSharp', 'Gs', 'All')]
    [string[]]$FileTypes = @('All'),
    
    # Limit processing to N files per type for testing (0 = unlimited)
    [int]$MaxFilesPerType = 0,
    
    # Use client-side Mermaid.js rendering (recommended)
    [bool]$ClientSideRender = $true,
    
    # Save Mermaid diagram source files (.mmd) alongside the HTML output
    [bool]$SaveMmdFiles = $true,
    
    # Enable parallel processing using multiple threads
    [bool]$Parallel = $true,
    
    # Percentage of CPU cores to use for parallel processing (ignored if ThreadCountMax is set)
    [int]$ThreadPercentage = 75,
    
    # Maximum number of threads to use (overrides ThreadPercentage if set, 0 = use ThreadPercentage)
    [int]$ThreadCountMax = 2,
   
    # Output folder for generated HTML files (default: $env:OptPath\Webs\AutoDoc)
    [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",

    # Skip git clone and update of source repositories
    [bool]$QuickRun = $false,

    # Use RAM disk (V:) for temporary files and repo clones for faster processing
    # Requires administrator privileges. Falls back to standard folders if creation fails.
    [bool]$UseRamDisk = $false,
    
    # Size of RAM disk in GB (only used when -UseRamDisk is specified)
    [int]$RamDiskSizeGB = 2

)

# All parser functions are consolidated in AutodocFunctions module
# The module contains: Start-CblParse, Start-RexParse, Start-Ps1Parse, Start-BatParse, Start-SqlParse, Start-CSharpParse, Start-CSharpEcosystemParse

Import-Module -Name GlobalFunctions -Force

#region Kill Other AutoDoc Processes
# Kill other PowerShell processes running AutoDocBatchRunner.ps1 to prevent conflicts
$currentProcessId = $PID

# Find all PowerShell processes that might be running AutoDoc
# Check both pwsh (PowerShell 7+) and powershell (Windows PowerShell 5.1)
$otherAutoDocProcesses = @()

# Get PowerShell 7+ processes
[array]$pwshProcesses = @(Get-Process -Name "pwsh" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentProcessId })
# Get Windows PowerShell 5.1 processes
[array]$psProcesses = @(Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentProcessId })

foreach ($proc in ($pwshProcesses + $psProcesses)) {
    try {
        # Try to get command line arguments using WMI/CIM
        $commandLine = $null
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell 7+ - use Get-CimInstance
            $cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
            $commandLine = $cimProcess.CommandLine
        }
        else {
            # Windows PowerShell 5.1 - use Get-WmiObject
            $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
            $commandLine = $wmiProcess.CommandLine
        }
        
        # Check if command line contains AutoDocBatchRunner
        if ($commandLine -and $commandLine -like "*AutoDocBatchRunner.ps1*") {
            $otherAutoDocProcesses += $proc
        }
    }
    catch {
        # If we can't check command line, skip this process
        continue
    }
}

if ($otherAutoDocProcesses.Count -gt 0) {
    Write-LogMessage "Found $($otherAutoDocProcesses.Count) other AutoDoc process(es) running. Terminating to prevent conflicts..." -Level WARN
    foreach ($proc in $otherAutoDocProcesses) {
        try {
            Write-LogMessage "Terminating process: PID $($proc.Id), Name: $($proc.ProcessName)" -Level INFO
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-LogMessage "Successfully terminated process PID $($proc.Id)" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to terminate process PID $($proc.Id): $($_.Exception.Message)" -Level WARN
        }
    }
    # Give processes a moment to terminate
    Start-Sleep -Seconds 2
}
else {
    Write-LogMessage "No other AutoDoc processes detected. Proceeding..." -Level INFO
}
#endregion Kill Other AutoDoc Processes

Import-Module -Name Agent-Handler -Force -ErrorAction SilentlyContinue  # Required for Get-DevToolsWebPath when running with pwsh -File
Import-Module -Name AutodocFunctions -Force
Import-Module -Name AzureFunctions -Force -ErrorAction SilentlyContinue
Import-Module -Name SoftwareUtils -Force -ErrorAction SilentlyContinue  # Required for Start-OurPshApp
Import-Module -Name Handle-RamDisk -Force -ErrorAction SilentlyContinue  # RAM disk management

#region FileTypes Expansion
# Expand 'All' to include all file types for simpler downstream checks
if ($FileTypes -contains 'All') {
    $FileTypes = @('Cbl', 'Rex', 'Bat', 'Ps1', 'Sql', 'CSharp', 'Gs')
}
Write-LogMessage "FileTypes filter: $($FileTypes -join ', ')" -Level INFO
#endregion FileTypes Expansion

#region RAM Disk Management

# Script-level variable to track RAM disk status
$script:RamDiskActive = $false
$script:RamDiskDriveLetter = "V:"

function Initialize-RamDisk {
    <#
    .SYNOPSIS
        Initializes a RAM disk for faster AutoDoc processing.
    .DESCRIPTION
        Creates a RAM disk using the Invoke-RamDisk function. If successful, sets 
        $script:RamDiskActive to $true and returns the drive letter.
        If creation fails, returns $null and falls back to standard folders.
    .PARAMETER SizeGB
        Size of the RAM disk in gigabytes.
    .OUTPUTS
        Drive letter (e.g., "V:") if successful, $null if failed.
    #>
    param(
        [int]$SizeGB = 2
    )
    
    Write-LogMessage "Attempting to create RAM disk ($SizeGB GB) for faster processing..." -Level INFO
    
    
    try {
        # Check if RAM disk already exists on V:
        $status = Invoke-RamDisk -Action Status -DriveLetter "V:"
        if ($status.Exists) {
            Write-LogMessage "Existing RAM disk found on V: ($($status.SizeGB) GB) - reusing it" -Level INFO
            $script:RamDiskActive = $true
            $script:RamDiskDriveLetter = "V:"
            return "V:"
        }
    }
    catch {
        # Status check failed, disk doesn't exist - continue to create
    }
    
    try {
        # Create new RAM disk with Force (removes if exists)
        Write-LogMessage "Creating RAM disk: SizeGB=$SizeGB, DriveLetter=V:" -Level INFO
        $result = Invoke-RamDisk -Action Create -DriveLetter "V:" -SizeGB $SizeGB -Force
        
        if ($result) {
            Write-LogMessage "RAM disk created successfully on V:" -Level INFO
            $script:RamDiskActive = $true
            $script:RamDiskDriveLetter = "V:"
            return "V:"
        }
        else {
            Write-LogMessage "RAM disk creation returned false" -Level WARN
            return $null
        }
    }
    catch {
        Write-LogMessage "Failed to create RAM disk: $($_.Exception.Message)" -Level WARN
        Write-LogMessage "Falling back to standard folder system" -Level INFO
        return $null
    }
}

function Get-WorkFolderRoot {
    <#
    .SYNOPSIS
        Returns the appropriate root folder for work files based on RAM disk status.
    .DESCRIPTION
        If RAM disk is active, returns V:\AutoDoc as root.
        Otherwise returns the standard $env:OptPath\data\AutoDoc folder.
    #>
    param(
        [string]$StandardRoot = "$env:OptPath\data\AutoDoc"
    )
    
    if ($script:RamDiskActive) {
        $ramRoot = "$($script:RamDiskDriveLetter)\AutoDoc"
        # Create the folder if it doesn't exist
        if (-not (Test-Path $ramRoot)) {
            New-Item -ItemType Directory -Path $ramRoot -Force | Out-Null
            Write-LogMessage "Created RAM disk work folder: $ramRoot" -Level INFO
        }
        return $ramRoot
    }
    else {
        return $StandardRoot
    }
}

function Remove-AutoDocRamDisk {
    <#
    .SYNOPSIS
        Removes the RAM disk created by AutoDoc.
    .DESCRIPTION
        Cleans up the RAM disk when the script finishes using the Handle-RamDisk module.
        Only removes if $script:RamDiskActive is $true (i.e., we created it).
        Handles gracefully if the RAM disk was already removed.
    #>
    
    if (-not $script:RamDiskActive) {
        Write-LogMessage "No RAM disk to clean up (not active)" -Level DEBUG
        return
    }
    
    $driveLetter = $script:RamDiskDriveLetter.TrimEnd(':')
    
    # First check if the drive even exists
    $driveExists = $false
    try {
        $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
        $driveExists = $null -ne $volume
    }
    catch {
        # Drive doesn't exist
    }
    
    if (-not $driveExists) {
        Write-LogMessage "RAM disk on $($script:RamDiskDriveLetter) already removed (drive not found)" -Level INFO
        $script:RamDiskActive = $false
        return
    }
    
    Write-LogMessage "Cleaning up RAM disk on $($script:RamDiskDriveLetter)..." -Level INFO
    
    # Try Invoke-RamDisk first
    $moduleRemoved = $false
    try {
        $result = Invoke-RamDisk -Action Remove -DriveLetter $script:RamDiskDriveLetter -Force
        if ($result) {
            Write-LogMessage "RAM disk removed successfully" -Level INFO
            $script:RamDiskActive = $false
            $moduleRemoved = $true
        }
    }
    catch {
        # Module failed - will try fallback
        Write-LogMessage "Invoke-RamDisk removal failed: $($_.Exception.Message)" -Level WARN
    }
    
    # Fallback: try direct imdisk if module didn't succeed
    if (-not $moduleRemoved) {
        try {
            $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
            if ($imdiskPath) {
                Write-LogMessage "Attempting direct imdisk removal..." -Level INFO
                $output = & imdisk -d -m $script:RamDiskDriveLetter 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "RAM disk removed successfully (direct imdisk)" -Level INFO
                    $script:RamDiskActive = $false
                }
                else {
                    Write-LogMessage "Direct imdisk removal failed (exit: $LASTEXITCODE): $output" -Level WARN
                }
            }
        }
        catch {
            Write-LogMessage "Fallback imdisk removal also failed: $($_.Exception.Message)" -Level WARN
        }
    }
}

#endregion RAM Disk Management

#region Parallel Processing Infrastructure

# Calculate optimal thread count based on CPU cores
function Get-OptimalThreadCount {
    param(
        [int]$Percentage = 75,
        [int]$MaxThreads = 0  # If > 0, overrides Percentage-based calculation
    )
    $totalCores = [Environment]::ProcessorCount
    
    if ($MaxThreads -gt 0) {
        # Use explicit max thread count (capped at total cores)
        $threads = [Math]::Min($MaxThreads, $totalCores)
        $threads = [Math]::Max(2, $threads)  # Minimum 2 threads
        return @{
            TotalCores = $totalCores
            Threads    = $threads
            MaxThreads = $MaxThreads
            Mode       = "MaxThreads"
        }
    }
    else {
        # Use percentage-based calculation
        $threads = [Math]::Max(2, [Math]::Floor($totalCores * ($Percentage / 100)))
        return @{
            TotalCores = $totalCores
            Threads    = $threads
            Percentage = $Percentage
            Mode       = "Percentage"
        }
    }
}

# Prepare thread-specific folders with copies of common files
# This ensures each parallel thread has its own isolated copy of cobdok data
function Initialize-ParallelThreadFolders {
    param(
        [string]$CobdokFolder,
        [string]$TmpFolder,
        [int]$ThreadCount
    )
    
    Write-LogMessage "Initializing $ThreadCount thread-specific folders with cobdok data..." -Level INFO
    
    $threadFolders = @()
    
    # Get list of all cobdok files to copy
    $cobdokFiles = Get-ChildItem -Path $CobdokFolder -Filter "*.csv" -ErrorAction SilentlyContinue
    
    for ($i = 0; $i -lt $ThreadCount; $i++) {
        $threadFolder = Join-Path $TmpFolder "thread_$i"
        $threadCobdokFolder = Join-Path $threadFolder "cobdok"
        
        # Create thread folder structure
        if (-not (Test-Path $threadFolder)) {
            New-Item -ItemType Directory -Path $threadFolder -Force | Out-Null
        }
        if (-not (Test-Path $threadCobdokFolder)) {
            New-Item -ItemType Directory -Path $threadCobdokFolder -Force | Out-Null
        }
        
        # Copy all cobdok CSV files to this thread's folder
        foreach ($file in $cobdokFiles) {
            $destPath = Join-Path $threadCobdokFolder $file.Name
            Copy-Item -Path $file.FullName -Destination $destPath -Force
        }
        
        $threadFolders += [PSCustomObject]@{
            ThreadId     = $i
            ThreadFolder = $threadFolder
            CobdokFolder = $threadCobdokFolder
        }
    }
    
    Write-LogMessage "Created $ThreadCount thread folders with cobdok copies" -Level INFO
    return $threadFolders
}

# Clean up thread-specific folders after parallel processing
function Remove-ParallelThreadFolders {
    param(
        [string]$TmpFolder,
        [int]$ThreadCount
    )
    
    for ($i = 0; $i -lt $ThreadCount; $i++) {
        $threadFolder = Join-Path $TmpFolder "thread_$i"
        if (Test-Path $threadFolder) {
            Remove-Item -Path $threadFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-LogMessage "Cleaned up $ThreadCount thread folders" -Level INFO
}

# Export common parse data for parallel workers to avoid repeated CSV loading
function Export-CommonParseData {
    param(
        [string]$CobdokFolder,
        [string]$ExportPath
    )
    
    $commonData = @{
        ModulCsv   = @()
        TablesCsv  = @()
        ColumnsCsv = @()
        CallCsv    = @()
        CopyCsv    = @()
    }
    
    # Load CSVs if they exist
    $modulCsvPath = Join-Path $CobdokFolder "modul.csv"
    if (Test-Path $modulCsvPath) {
        $commonData.ModulCsv = @(Import-Csv $modulCsvPath -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';')
    }
    
    $tablesCsvPath = Join-Path $CobdokFolder "tables.csv"
    if (Test-Path $tablesCsvPath) {
        $commonData.TablesCsv = @(Import-Csv $tablesCsvPath -Header schemaName, tableName, comment, type, alter_time -Delimiter ';')
    }
    
    $columnsCsvPath = Join-Path $CobdokFolder "columns.csv"
    if (Test-Path $columnsCsvPath) {
        $commonData.ColumnsCsv = @(Import-Csv $columnsCsvPath -Header tabschema, tabname, colname, colno, typeschema, typename, length, scale, remarks -Delimiter ';' -ErrorAction SilentlyContinue)
    }
    
    $callCsvPath = Join-Path $CobdokFolder "call.csv"
    if (Test-Path $callCsvPath) {
        $commonData.CallCsv = @(Import-Csv $callCsvPath -ErrorAction SilentlyContinue)
    }
    
    $copyCsvPath = Join-Path $CobdokFolder "copy.csv"
    if (Test-Path $copyCsvPath) {
        $commonData.CopyCsv = @(Import-Csv $copyCsvPath -ErrorAction SilentlyContinue)
    }
    
    # Serialize to file for parallel workers
    $commonData | Export-Clixml -Path $ExportPath -Force
    
    return $commonData
}

# Thread-safe logging using concurrent queue
$script:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()

function Write-ParallelLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $script:LogQueue.Enqueue([PSCustomObject]@{
            Timestamp = Get-Date
            Level     = $Level
            Message   = $Message
        })
}

function Clear-ParallelLogs {
    $logEntry = $null
    while ($script:LogQueue.TryDequeue([ref]$logEntry)) {
        Write-LogMessage $logEntry.Message -Level $logEntry.Level
    }
}

# Process files in parallel
function Invoke-ParallelFileParsing {
    param(
        [array]$FilesToProcess,
        [string]$ParserType,  # CBL, REX, BAT, PS1, SQL
        [string]$OutputFolder,
        [string]$TmpRootFolder,
        [string]$SrcRootFolder,
        [bool]$ClientSideRender,
        [int]$ThrottleLimit,
        [string]$CommonDataPath
    )
    
    if ($FilesToProcess.Count -eq 0) {
        Write-LogMessage "No $ParserType files to process" -Level INFO
        return
    }
    
    Write-LogMessage "Processing $($FilesToProcess.Count) $ParserType files in parallel (ThrottleLimit: $ThrottleLimit)" -Level INFO
    
    $processedCount = [ref]0
    $errorCount = [ref]0
    
    # Create a parallel temp folder base for isolating file-specific temp files
    # But keep the main tmpRootFolder for accessing cobdok data
    $parallelTmpBase = Join-Path $TmpRootFolder "parallel"
    if (-not (Test-Path $parallelTmpBase)) {
        New-Item -ItemType Directory -Path $parallelTmpBase -Force | Out-Null
    }
    
    $FilesToProcess | ForEach-Object -Parallel {
        # Import modules and ensure globals are initialized for parallel runspace
        Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
        Initialize-GlobalFunctionsForParallel
        Import-Module -Name AutodocFunctions -Force -ErrorAction Stop
        
        $file = $_
        $parserType = $using:ParserType
        $outputFolder = $using:OutputFolder
        $tmpRootFolder = $using:TmpRootFolder  # Keep original for cobdok access
        $srcRootFolder = $using:SrcRootFolder
        $ClientSideRender = $using:ClientSideRender
        $parallelTmpBase = $using:parallelTmpBase
        
        try {
            $params = @{
                OutputFolder  = $outputFolder
                CleanUp       = $true
                TmpRootFolder = $tmpRootFolder  # Use original - contains cobdok subfolder
                SrcRootFolder = $srcRootFolder
            }
            
            if ($ClientSideRender) {
                $params.Add("ClientSideRender", $true)
            }
            
            switch ($parserType) {
                "CBL" {
                    $params.Add("SourceFile", $file.FullName)
                    Start-CblParse @params
                }
                "REX" {
                    $params.Add("SourceFile", $file.FullName)
                    Start-RexParse @params
                }
                "BAT" {
                    $params.Add("SourceFile", $file.FullName)
                    Start-BatParse @params
                }
                "PS1" {
                    $params.Add("SourceFile", $file.FullName)
                    Start-Ps1Parse @params
                }
                "SQL" {
                    # SQL uses table name instead of file
                    $params.Add("SqlTable", $file.TableName)
                    Start-SqlParse @params
                }
            }
            
            # Increment success counter
            [System.Threading.Interlocked]::Increment($using:processedCount) | Out-Null
        }
        catch {
            [System.Threading.Interlocked]::Increment($using:errorCount) | Out-Null
            
            # Create error file
            $errFileName = if ($parserType -eq "SQL") { $file.TableName.Replace(".", "_") + ".sql.err" } else { $file.Name + ".err" }
            $errFilePath = Join-Path $outputFolder $errFileName
            "Error: $($_.Exception.Message)`n$($_.ScriptStackTrace)" | Set-Content -Path $errFilePath -Force
        }
    } -ThrottleLimit $ThrottleLimit
    
    Write-LogMessage ("Completed $($ParserType): $($processedCount.Value) processed, $($errorCount.Value) errors") -Level INFO
}

#endregion Parallel Processing Infrastructure

function CreateAllJsonIndexFiles {
    <#
    .SYNOPSIS
        Generates all JSON index files for index.html based purely on files present in the output folder.
    .DESCRIPTION
        Scans the output folder for generated HTML files of each type (CBL, BAT, PS1, PSM1, REX, SQL, C#)
        and creates the corresponding JSON files in the _json subfolder.
        For CBL and SQL files, enriches with cobdok metadata (modul.csv, tables.csv) if available.
        This function replaces all individual CreateJsonFile* functions and is called once at the end of the job.
    .PARAMETER OutputFolder
        The folder containing generated HTML files.
    .PARAMETER CobdokFolder
        The folder containing cobdok CSV exports (modul.csv, tables.csv, etc.).
    .PARAMETER ServerMonitorFolder
        The folder containing C# ServerMonitor source for description enrichment.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder,
        [Parameter(Mandatory = $true)]
        [string]$CobdokFolder,
        [Parameter(Mandatory = $false)]
        [string]$ServerMonitorFolder = ""
    )

    $jsonOutputFolder = Join-Path $OutputFolder "_json"
    if (-not (Test-Path $jsonOutputFolder)) {
        New-Item -ItemType Directory -Path $jsonOutputFolder -Force | Out-Null
    }

    Write-LogMessage ("-" * 75) -Level INFO
    Write-LogMessage "Generating JSON index files from output folder" -Level INFO
    Write-LogMessage "Output folder: $($OutputFolder)" -Level INFO
    Write-LogMessage ("-" * 75) -Level INFO

    ################################################################################
    # 1. CBL - COBOL programs
    ################################################################################
    $jsonFile = Join-Path $jsonOutputFolder "CblParseResult.json"
    $objArray = @()

    # Load cobdok modul.csv for enrichment (optional)
    $csvModulArray = @()
    $modulCsvPath = Join-Path $CobdokFolder "modul.csv"
    if (Test-Path $modulCsvPath -PathType Leaf) {
        try {
            $csvModulArray = Import-Csv $modulCsvPath -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';'
            Write-LogMessage "Loaded modul.csv with $($csvModulArray.Count) entries for CBL enrichment" -Level INFO
        }
        catch {
            Write-LogMessage "Warning: Could not load modul.csv - CBL entries will have no description/system/type" -Level WARN
        }
    }
    else {
        Write-LogMessage "modul.csv not found at $($modulCsvPath) - CBL entries will have no description/system/type" -Level WARN
    }

    $cblFiles = Get-ChildItem -Path $OutputFolder -Filter "*.cbl.html" -Name -ErrorAction SilentlyContinue
    foreach ($fileName in $cblFiles) {
        try {
            $fileNameLower = $fileName.ToLower()
            $errorFilename = Join-Path $OutputFolder $fileNameLower.Replace(".cbl.html", ".cbl.err")

            if (Test-Path $errorFilename -PathType Leaf) {
                continue
            }

            $baseFileName = $fileNameLower.Replace(".cbl.html", "").ToUpper()
            $link = "<a href=`"./$($fileNameLower.Trim())`" target=`"_blank`">$($baseFileName).cbl</a><br>"

            # Enrich from cobdok modul.csv if available
            $htmlSystem = ""
            $htmlDesc = ""
            $htmlType = ""
            if ($csvModulArray.Count -gt 0) {
                $descMatch = $csvModulArray | Where-Object { $_.modul.Contains($baseFileName) }
                if ($descMatch.Count -gt 0) {
                    $item = $descMatch[0]
                    $htmlSystem = $item.delsystem.Trim()
                    $htmlDesc = $item.tekst.Trim()
                    $htmlType = $item.modultype.Trim()
                }
            }

            $objArray += [PSCustomObject]@{
                programName     = "$($baseFileName.ToLower()).cbl"
                programNameLink = $link
                description     = $htmlDesc
                system          = $htmlSystem
                type            = $htmlType
            }
        }
        catch {
            Write-LogMessage "Error processing CBL file $($fileName): $($_.Exception.Message)" -Level ERROR -Exception $_
        }
    }

    if ($objArray.Count -gt 0) {
        $objArray | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFile -Encoding UTF8
    }
    else {
        "[]" | Set-Content -Path $jsonFile -Encoding UTF8
    }
    Write-LogMessage "CblParseResult.json: $($objArray.Count) entries" -Level INFO

    ################################################################################
    # 2. Script types - BAT, PS1, PSM1, REX (all use same structure)
    ################################################################################
    $scriptTypes = @(
        @{ Extension = "bat";  TypeName = "Windows Batch Script"; JsonName = "BatParseResult.json" },
        @{ Extension = "ps1";  TypeName = "Powershell Script";    JsonName = "Ps1ParseResult.json" },
        @{ Extension = "psm1"; TypeName = "Powershell Module";    JsonName = "Psm1ParseResult.json" },
        @{ Extension = "rex";  TypeName = "Object Rexx Script";   JsonName = "RexParseResult.json" }
    )

    foreach ($scriptType in $scriptTypes) {
        $jsonFile = Join-Path $jsonOutputFolder $scriptType.JsonName
        $objArray = @()
        $pattern = "*.$($scriptType.Extension).html"
        $htmlFiles = Get-ChildItem -Path $OutputFolder -Filter $pattern -Name -ErrorAction SilentlyContinue

        foreach ($fileName in $htmlFiles) {
            $errorFilename = Join-Path $OutputFolder $fileName.Replace(".html", ".err")
            if (Test-Path $errorFilename -PathType Leaf) {
                continue
            }

            $baseFileName = $fileName.Replace(".html", "").ToUpper()
            $link = "<a href=`"./$($fileName.ToLower().Trim())`" target=`"_blank`">$($baseFileName)</a><br>"

            $objArray += [PSCustomObject]@{
                scriptNameLink = $link
                type           = $scriptType.TypeName
            }
        }

        if ($objArray.Count -gt 0) {
            $objArray | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFile -Encoding UTF8
        }
        else {
            "[]" | Set-Content -Path $jsonFile -Encoding UTF8
        }
        Write-LogMessage "$($scriptType.JsonName): $($objArray.Count) entries" -Level INFO
    }

    ################################################################################
    # 3. SQL - Tables and views (scan *.sql.html files, enrich from tables.csv)
    ################################################################################
    $jsonFile = Join-Path $jsonOutputFolder "SqlParseResult.json"
    $objArray = @()

    # Load cobdok tables.csv for enrichment (optional)
    $csvTableLookup = @{}
    $tablesCsvPath = Join-Path $CobdokFolder "tables.csv"
    if (Test-Path $tablesCsvPath -PathType Leaf) {
        try {
            $csvTableArray = Import-Csv $tablesCsvPath -Header schemaName, tableName, comment, type -Delimiter ';'
            foreach ($row in $csvTableArray) {
                $key = "$($row.schemaName.ToString().ToUpper().Trim()).$($row.tableName.ToString().ToUpper().Trim())"
                $csvTableLookup[$key] = $row
            }
            Write-LogMessage "Loaded tables.csv with $($csvTableLookup.Count) entries for SQL enrichment" -Level INFO
        }
        catch {
            Write-LogMessage "Warning: Could not load tables.csv - SQL entries will have no description/type" -Level WARN
        }
    }
    else {
        Write-LogMessage "tables.csv not found at $($tablesCsvPath) - SQL entries will have no description/type" -Level WARN
    }

    $sqlFiles = Get-ChildItem -Path $OutputFolder -Filter "*.sql.html" -Name -ErrorAction SilentlyContinue
    foreach ($fileName in $sqlFiles) {
        try {
            # Extract table name from filename: SCHEMA_TABLENAME.sql.html -> SCHEMA.TABLENAME
            $baseName = $fileName.Replace(".sql.html", "").ToUpper()
            # The filename uses _ as separator between schema and table, but schema.table uses .
            # Find matching cobdok entry by trying to match the filename pattern
            $tableName = ""
            $htmlDesc = ""
            $htmlType = "Sql table"

            # Try to find a matching cobdok entry
            $matchFound = $false
            foreach ($key in $csvTableLookup.Keys) {
                $expectedFilename = $key.Replace(".", "_").Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA")
                if ($expectedFilename -eq $baseName) {
                    $tableName = $key
                    $row = $csvTableLookup[$key]
                    $htmlDesc = $row.comment.ToString().ToUpper().Trim()
                    if ($row.type.Contains("V")) {
                        $htmlType = "Sql view"
                    }
                    $matchFound = $true
                    break
                }
            }

            if (-not $matchFound) {
                # Fallback: use filename as table name (replace first _ with .)
                $underscorePos = $baseName.IndexOf("_")
                if ($underscorePos -gt 0) {
                    $tableName = $baseName.Substring(0, $underscorePos) + "." + $baseName.Substring($underscorePos + 1)
                }
                else {
                    $tableName = $baseName
                }
            }

            $filelink = "./$($fileName.ToLower().Trim())"
            $tablenamelink = "<a href=`"$($filelink)`" target=`"_blank`">$($tableName)</a>"

            $objArray += [PSCustomObject]@{
                tableNameLink = $tablenamelink
                description   = $htmlDesc
                type          = $htmlType
            }
        }
        catch {
            Write-LogMessage "Error processing SQL file $($fileName): $($_.Exception.Message)" -Level ERROR -Exception $_
        }
    }

    if ($objArray.Count -gt 0) {
        $objArray | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFile -Encoding UTF8
    }
    else {
        "[]" | Set-Content -Path $jsonFile -Encoding UTF8
    }
    Write-LogMessage "SqlParseResult.json: $($objArray.Count) entries" -Level INFO

    ################################################################################
    # 4. C# - Projects and ecosystems
    ################################################################################
    $jsonFile = Join-Path $jsonOutputFolder "CSharpParseResult.json"
    $objArray = @()

    $csharpFiles = Get-ChildItem -Path $OutputFolder -Filter "*.csharp.html" -Name -ErrorAction SilentlyContinue
    foreach ($fileName in $csharpFiles) {
        $baseFileName = $fileName.Replace(".csharp.html", "")
        $link = "<a href=`"./$($fileName.ToLower().Trim())`" target=`"_blank`">$($baseFileName)</a><br>"

        $projectType = "C# Solution"
        $description = ""

        if ($baseFileName.ToLower().EndsWith(".ecosystem")) {
            $projectType = "C# Ecosystem"
            $description = "Multi-project ecosystem diagram"
        }
        elseif ($ServerMonitorFolder -and (Test-Path $ServerMonitorFolder -ErrorAction SilentlyContinue)) {
            $slnFile = Get-ChildItem -Path $ServerMonitorFolder -Filter "$($baseFileName).sln" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($slnFile) {
                $csprojFiles = Get-ChildItem -Path $slnFile.DirectoryName -Filter "*.csproj" -Recurse -ErrorAction SilentlyContinue
                foreach ($csproj in $csprojFiles) {
                    try {
                        [xml]$xmlContent = Get-Content $csproj.FullName
                        $descNode = $xmlContent.SelectSingleNode("//Description")
                        if ($descNode -and $descNode.InnerText) {
                            $description = $descNode.InnerText
                            break
                        }
                    }
                    catch { }
                }
            }
        }

        $objArray += [PSCustomObject]@{
            projectName     = $baseFileName
            projectNameLink = $link
            description     = $description
            type            = $projectType
        }
    }

    if ($objArray.Count -gt 0) {
        $objArray | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFile -Encoding UTF8
    }
    else {
        "[]" | Set-Content -Path $jsonFile -Encoding UTF8
    }
    Write-LogMessage "CSharpParseResult.json: $($objArray.Count) entries" -Level INFO

    ################################################################################
    # Summary
    ################################################################################
    $totalFiles = (Get-ChildItem -Path $jsonOutputFolder -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
    Write-LogMessage ("-" * 75) -Level INFO
    Write-LogMessage "JSON index generation complete - $($totalFiles) JSON files in $($jsonOutputFolder)" -Level INFO
    Write-LogMessage ("-" * 75) -Level INFO
}

function CreateJsonFileSqlOld {
    param (
        $outputFolder, $cobdokFolder, $jsonScriptFile
    )
    $objArray = @()
    $workArray = Get-ChildItem -Path $outputFolder -Include "*.sql.html" -Name

    foreach ($currenItemName in $workArray) {
        $filename = $currenItemName.ToString()

        $baseFileName = $filename.Replace(".sql.html", "").ToUpper()
        $linkname = $baseFileName.ToLower().Replace("dbm_", "dbm.").Replace("hst_", "hst.").Replace("log_", "log.").Replace("crm_", "crm.").Replace("tv_", "tv.").ToUpper()
        if ($baseFileName.Contains("OE") -and -not $baseFileName.Contains("DATOER")) {
            $linkname = $linkname.Replace("OE", "Ø")
        }
        if ($baseFileName.Contains("AE")) {
            $linkname = $linkname.Replace("AE", "Æ")
        }
        if ($baseFileName.Contains("AA")) {
            $linkname = $linkname.Replace("AA", "Å")
        }

        $link = "<a href=" + '"./' + $filename.ToLower().Trim() + '"' + "target=" + '"' + "_blank" + '"' + ">" + $baseFileName.Replace("dbm_", "dbm.").Replace("hst_", "hst.").Replace("crm_", "crm.").Replace("log_", "log.").Replace("tv_", "tv.") + "</a><br>"

        # Create a new object
        $obj = New-Object PSObject

        # Add properties to the object
        $obj | Add-Member -Type NoteProperty -Name "tableNameLink" -Value $link
        $objArray += $obj
    }
    # Convert the object to JSON
    $json = $objArray | ConvertTo-Json

    # Write the JSON to a file
    $jsonfile = $jsonScriptFile
    $json | Set-Content -Path $jsonfile
    Write-LogMessage ("Updated " + $jsonScriptFile) -Level INFO
}
function ConvertFromAnsi1252ToUtf8 {
    param (
        $exportTableName, $folderPath
    )
    # Specify the paths for the source ANSI file and the destination UTF-8 file

    $convertFilePath = $folderPath + "\" + $exportTableName + ".csv"
    # check if the file exists
    if (-not (Test-Path -Path $convertFilePath -PathType Leaf)) {
        Write-LogMessage ("File " + $convertFilePath + " does not exist") -Level WARN
        return
    }

    $stream = New-Object System.IO.FileStream($convertFilePath, [System.IO.FileMode]::Open)
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::GetEncoding("Windows-1252"))
    $content = $reader.ReadToEnd()
    $reader.Close()
    $stream.Close()

    # Convert the content to UTF-8 encoding and write it to the destination file
    Set-Content -Path $convertFilePath -Value $content -Encoding UTF8
}
function ExportTableContentToFile {
    <#
    .SYNOPSIS
        Generates DB2 export commands for system catalog metadata.
    .DESCRIPTION
        Creates DB2 export commands for extracting comprehensive table metadata
        from SYSCAT views including tables, columns, indexes, constraints, 
        foreign keys, triggers, and packages.
    .PARAMETER exportTableName
        The type of metadata to export (tables, columns, indexes, constraints, 
        references, triggers, keycoluse, routines, packages, packagedep).
    .PARAMETER folderPath
        Destination folder for the CSV export files.
    .OUTPUTS
        DB2 export command string.
    .NOTES
        Based on DB2 12.1 System Catalog Metadata reference.
        All CHAR columns use TRIM() for proper handling.
    #>
    param (
        $exportTableName, $folderPath
    )
    
    $schemaFilter = "('DBM','HST','CRM','LOG','TV')"
    
    switch ($exportTableName) {
        # Tables - enhanced with more metadata
        "tables" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(tabschema), TRIM(tabname), TRIM(COALESCE(remarks,'')), TRIM(type), " +
                "alter_time, create_time, COALESCE(card,-1), COALESCE(npages,-1), colcount, " +
                "TRIM(COALESCE(tbspace,'')), parents, children, keycolumns " +
                "FROM syscat.tables WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname"
        }
        
        # Columns - enhanced with nullable, default, identity info
        "columns" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(tabschema), TRIM(tabname), TRIM(colname), colno, TRIM(typeschema), " +
                "TRIM(typename), length, scale, TRIM(COALESCE(remarks,'')), TRIM(nulls), " +
                "TRIM(COALESCE(CAST(default AS VARCHAR(254)),'')), TRIM(identity), TRIM(generated) " +
                "FROM syscat.columns WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname, colno"
        }
        
        # Indexes - comprehensive index metadata
        "indexes" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(indschema), TRIM(indname), TRIM(tabschema), TRIM(tabname), " +
                "TRIM(colnames), TRIM(uniquerule), colcount, TRIM(indextype), " +
                "COALESCE(nleaf,-1), nlevels, COALESCE(fullkeycard,-1), create_time, " +
                "TRIM(COALESCE(remarks,'')) " +
                "FROM syscat.indexes WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname, indname"
        }
        
        # Index columns - detailed column info for each index
        "indexcoluse" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(i.indschema), TRIM(i.indname), TRIM(i.tabschema), TRIM(i.tabname), " +
                "TRIM(c.colname), c.colseq, TRIM(c.colorder) " +
                "FROM syscat.indexes i JOIN syscat.indexcoluse c " +
                "ON TRIM(i.indschema) = TRIM(c.indschema) AND TRIM(i.indname) = TRIM(c.indname) " +
                "WHERE i.tabschema IN $schemaFilter ORDER BY i.tabschema, i.tabname, c.indname, c.colseq"
        }
        
        # Table constraints - PK, UK, FK, Check
        "tabconst" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), TRIM(type), " +
                "TRIM(enforced), TRIM(COALESCE(remarks,'')) " +
                "FROM syscat.tabconst WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname, constname"
        }
        
        # Key column usage - columns in PK/UK/FK constraints
        "keycoluse" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), TRIM(colname), colseq " +
                "FROM syscat.keycoluse WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname, constname, colseq"
        }
        
        # Foreign key references - detailed FK relationships
        "references" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), " +
                "TRIM(reftabschema), TRIM(reftabname), TRIM(refkeyname), " +
                "TRIM(fk_colnames), TRIM(pk_colnames), TRIM(deleterule), TRIM(updaterule), " +
                "colcount, create_time " +
                "FROM syscat.references WHERE tabschema IN $schemaFilter " +
                "OR reftabschema IN $schemaFilter ORDER BY tabschema, tabname, constname"
        }
        
        # Triggers on tables
        "triggers" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(trigschema), TRIM(trigname), TRIM(tabschema), TRIM(tabname), " +
                "TRIM(trigtime), TRIM(trigevent), TRIM(granularity), TRIM(valid), create_time, " +
                "TRIM(COALESCE(remarks,'')) " +
                "FROM syscat.triggers WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname, trigname"
        }
        
        # Check constraints
        "checks" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), create_time, " +
                "TRIM(COALESCE(CAST(text AS VARCHAR(1000)),'')) " +
                "FROM syscat.checks WHERE tabschema IN $schemaFilter ORDER BY tabschema, tabname, constname"
        }
        
        # Routines (stored procedures and functions)
        "routines" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(routineschema), TRIM(routinename), TRIM(specificname), " +
                "TRIM(routinetype), TRIM(origin), TRIM(language), parm_count, " +
                "TRIM(sql_data_access), create_time, TRIM(COALESCE(remarks,'')) " +
                "FROM syscat.routines WHERE routineschema IN $schemaFilter ORDER BY routineschema, routinename"
        }
        
        # Package dependencies - which packages use which tables
        "packagedep" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(pkgschema), TRIM(pkgname), TRIM(btype), TRIM(bschema), TRIM(bname) " +
                "FROM syscat.packagedep WHERE bschema IN $schemaFilter AND btype = 'T' " +
                "ORDER BY bschema, bname, pkgschema, pkgname"
        }
        
        # Routine dependencies - which routines use which tables
        "routinedep" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(routineschema), TRIM(routinename), TRIM(btype), TRIM(bschema), TRIM(bname) " +
                "FROM syscat.routinedep WHERE bschema IN $schemaFilter AND btype = 'T' " +
                "ORDER BY bschema, bname, routineschema, routinename"
        }
        
        # Table statistics (cardinality, page counts)
        "tablestats" {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "SELECT TRIM(tabschema), TRIM(tabname), card, npages, fpages, overflow, " +
                "stats_time, TRIM(tableorg), TRIM(compression) " +
                "FROM syscat.tables WHERE tabschema IN $schemaFilter AND type IN ('T','S') ORDER BY tabschema, tabname"
        }
        
        # Legacy exports (modul, call, copy, etc. from cobdok database)
        default {
            $command = "db2 export to $folderPath\$exportTableName.csv of del modified by coldel; " +
                "select * from dbm.$exportTableName"
        }
    }
    return $command
}

function RegenerateAutoDoc ($fileName, $lastGenerationDate, $Regenerate, $outputFolder) {

    $returnValue = $true

    if ($fileName.DirectoryName.ToLower().Contains("_old")) {
        Write-LogMessage ("Skipping file: " + $fileName.Name + " - Sourcefile is located in old folder: " + $fileName.DirectoryName) -Level INFO -QuietMode
        $returnValue = $false
        return $returnValue
    }

    if ($Regenerate -eq "Errors") {
        $errorFilename = $outputFolder + "\" + $fileName.Name + ".err"
        if (Test-Path $errorFilename -PathType Leaf) {
            $returnValue = $true
            Write-LogMessage ("Regenerate " + $fileName.Name + " - Error file exists: " + $errorFilename) -Level WARN -QuietMode
            return $returnValue
        }
        else {
            $returnValue = $false
            return $returnValue
        }
    }

    # Check AutodocFunctions module for changes (consolidated module for all parsers)
    # Note: GlobalFunctions.psm1 is NOT checked - it's a utility module (logging, etc.)
    # that doesn't affect the generated HTML output
    $autodocModulePath = (Get-Module -Name AutodocFunctions -ListAvailable | Select-Object -First 1).Path
    if ($autodocModulePath -and (Test-Path $autodocModulePath)) {
        $autodocModuleDate = [int](Get-Item $autodocModulePath).LastWriteTime.ToString("yyyyMMdd")
        if ($autodocModuleDate -gt $lastGenerationDate) {
            $returnValue = $true
            Write-LogMessage ("Regenerate " + $fileName.Name + " - AutodocFunctions module changed: " + $autodocModuleDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
            return $returnValue
        }
    }

    # Check type-specific template files for changes
    # Templates are in _templates subfolder relative to script root
    $templateDir = Join-Path $PSScriptRoot "_templates"

    if ($fileName.Name.ToLower().Contains(".cbl")) {
        $templateFile = Join-Path $templateDir "cblmmdtemplate.html"
        if (Test-Path $templateFile -PathType Leaf) {
            $contentFileDate = [int](Get-Item $templateFile).LastWriteTime.ToString("yyyyMMdd")
            if ($contentFileDate -gt $lastGenerationDate) {
                $returnValue = $true
                Write-LogMessage ("Regenerate " + $fileName.Name + " - cblmmdtemplate.html changed: " + $contentFileDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
                return $returnValue
            }
        }
    }

    if ($fileName.Name.ToLower().Contains(".ps1")) {
        $templateFile = Join-Path $templateDir "ps1mmdtemplate.html"
        if (Test-Path $templateFile -PathType Leaf) {
            $contentFileDate = [int](Get-Item $templateFile).LastWriteTime.ToString("yyyyMMdd")
            if ($contentFileDate -gt $lastGenerationDate) {
                $returnValue = $true
                Write-LogMessage ("Regenerate " + $fileName.Name + " - ps1mmdtemplate.html changed: " + $contentFileDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
                return $returnValue
            }
        }
    }

    if ($fileName.Name.ToLower().Contains(".rex")) {
        $templateFile = Join-Path $templateDir "rexmmdtemplate.html"
        if (Test-Path $templateFile -PathType Leaf) {
            $contentFileDate = [int](Get-Item $templateFile).LastWriteTime.ToString("yyyyMMdd")
            if ($contentFileDate -gt $lastGenerationDate) {
                $returnValue = $true
                Write-LogMessage ("Regenerate " + $fileName.Name + " - rexmmdtemplate.html changed: " + $contentFileDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
                return $returnValue
            }
        }
    }

    if ($fileName.Name.ToLower().Contains(".bat")) {
        $templateFile = Join-Path $templateDir "batmmdtemplate.html"
        if (Test-Path $templateFile -PathType Leaf) {
            $contentFileDate = [int](Get-Item $templateFile).LastWriteTime.ToString("yyyyMMdd")
            if ($contentFileDate -gt $lastGenerationDate) {
                $returnValue = $true
                Write-LogMessage ("Regenerate " + $fileName.Name + " - batmmdtemplate.html changed: " + $contentFileDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
                return $returnValue
            }
        }
    }

    $contentFilename = $outputFolder + "\" + $fileName.Name + ".html"
    if (-Not (Test-Path $contentFilename -PathType Leaf)) {
        $returnValue = $true
        Write-LogMessage ("Regenerate " + $fileName.Name + " -  Not previously generated: " + $contentFilename) -Level INFO -QuietMode
        return $returnValue
    }

    try {
        # Check Git commit date only if not in "All" or "Clean" mode
        # Note: Use -notin for cleaner multi-value check
        if ($Regenerate -notin @("All", "Clean")) {
            Push-Location
            Set-Location -Path $fileName.DirectoryName.ToString()
            $lastCommitDate = [int](git.exe log -n 1 --pretty=format:%cd --date=format:%Y%m%d $fileName.Name)
            Pop-Location
            if ($lastCommitDate -lt $lastGenerationDate) {
                $returnValue = $false
            }
            if ($returnValue -eq $true) {
                Write-LogMessage ("Regenerate " + $fileName.Name + " -  Last Commit Date: " + $lastCommitDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
            }
        }
        else {
            $returnValue = $true
        }
    }
    catch {
        $returnValue = $true
    }

    if ($returnValue -eq $false) {
        $errorFilename = $outputFolder + "\" + $fileName.Name + ".err"
        if (Test-Path $errorFilename -PathType Leaf) {
            $returnValue = $true
            Write-LogMessage ("Regenerate " + $fileName.Name + " - Error file exists: " + $errorFilename) -Level WARN -QuietMode
            return $returnValue
        }
    }

    return $returnValue
}

function RegenerateAutoDocSql ($tableInfo, $lastGenerationDate, $Regenerate, $outputFolder) {
    $returnValue = $true
    $tableName = $tableInfo.schemaName.Trim().ToUpper() + "." + $tableInfo.tableName.Trim().ToUpper()
    $tableNameFile = $tableInfo.schemaName.Trim().ToUpper() + "_" + $tableInfo.tableName.Trim().ToUpper()
    $contentFilename = ($outputFolder + "/" + $tableNameFile.Trim() + ".sql.html").Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower()

    # Check AutodocFunctions module for changes (consolidated module for all parsers)
    # Note: GlobalFunctions.psm1 is NOT checked - it's a utility module (logging, etc.)
    # that doesn't affect the generated HTML output
    $autodocModulePath = (Get-Module -Name AutodocFunctions -ListAvailable | Select-Object -First 1).Path
    if ($autodocModulePath -and (Test-Path $autodocModulePath)) {
        $autodocModuleDate = [int](Get-Item $autodocModulePath).LastWriteTime.ToString("yyyyMMdd")
        if ($autodocModuleDate -gt $lastGenerationDate) {
            $returnValue = $true
            Write-LogMessage ("Regenerate " + $tableName + " - AutodocFunctions module changed: " + $autodocModuleDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
            return $returnValue
        }
    }

    $templateFile = Join-Path $PSScriptRoot "_templates" | Join-Path -ChildPath "sqlmmdtemplate.html"
    if (Test-Path $templateFile -PathType Leaf) {
        $contentFileDate = [int](Get-Item $templateFile).LastWriteTime.ToString("yyyyMMdd")
        if ($contentFileDate -gt $lastGenerationDate) {
            $returnValue = $true
            Write-LogMessage ("Regenerate " + $tableName + " - sqlmmdtemplate.html changed: " + $contentFileDate.ToString() + " - Last Generation Date: " + $lastGenerationDate.ToString()) -Level INFO -QuietMode
            return $returnValue
        }
    }

    if (-Not (Test-Path $contentFilename -PathType Leaf)) {
        $returnValue = $true
        Write-LogMessage ("Regenerate " + $tableName + " -  Not previously generated: " + $contentFilename) -Level INFO -QuietMode
        return $returnValue
    }

    # If regenerate="All" or "Clean", always regenerate
    if ($Regenerate -in @("All", "Clean")) {
        return $true
    }

    # Compare DB2 ALTER_TIME (last DDL date) with the generated HTML file date
    # Only regenerate if the table structure has changed since last HTML generation
    try {
        # Parse ALTER_TIME from DB2 syscat.tables (format: YYYY-MM-DD-HH.MM.SS.nnnnnn)
        $alterTimeInt = [int]($tableInfo.alter_time.Substring(0, 10).Replace("-", ""))
        $contentFileDate = [int](Get-Item $contentFilename).LastWriteTime.ToString("yyyyMMdd")
        
        if ($contentFileDate -lt $alterTimeInt) {
            Write-LogMessage ("Regenerate " + $tableName + " - Table DDL changed. ALTER_TIME: " + $alterTimeInt + " > HTML date: " + $contentFileDate) -Level INFO
            return $true
        }
        else {
            # Table hasn't changed since HTML was generated - skip
            return $false
        }
    }
    catch {
        # If parsing fails, regenerate to be safe
        Write-LogMessage ("Regenerate " + $tableName + " - Could not parse ALTER_TIME, regenerating to be safe") -Level WARN
        return $true
    }
}

function HandleCblFiles($DedgeCblFolder, $outputFolder, $tmpFolder, $autoDocRootFolder, $lastGenerationDate, $lastExecutionInfoFileName, $Regenerate, $exitCounter = 10000, [switch]$ClientSideRender, [bool]$SaveMmdFiles = $true, [switch]$Parallel, [int]$ThrottleLimit = 6) {

    $workArrayAll = @()
    $descArray = Get-ChildItem -Path $DedgeCblFolder -Filter "*.cbl"
    foreach ($currentItem in $descArray) {
        if (!$currentItem.Name.Contains("-")) {
            $workArrayAll += $currentItem
        }
    }

    Write-LogMessage ("All cbl files: " + $workArrayAll.Count) -Level INFO

    Set-Location -Path $PSScriptRoot

    # Use the work folder containing cloned repositories for execution path analysis
    $srcRootFolder = $workFolder

    # Filter files that need regeneration
    $filesToProcess = @()
    $counter = 0
    foreach ($fileName in $workArrayAll) {
        if (RegenerateAutoDoc -fileName $fileName -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
            $filesToProcess += $fileName
            $counter++
            if ($counter -ge $exitCounter) {
                break
            }
        }
    }
    
    Write-LogMessage ("CBL files to process: " + $filesToProcess.Count) -Level INFO

    if ($Parallel -and $filesToProcess.Count -gt 1) {
        # Parallel processing
        Invoke-ParallelFileParsing -FilesToProcess $filesToProcess -ParserType "CBL" `
            -OutputFolder $outputFolder -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder `
            -ClientSideRender $ClientSideRender -ThrottleLimit $ThrottleLimit -CommonDataPath ""
    }
    else {
        # Sequential processing (original behavior)
        foreach ($fileName in $filesToProcess) {
            $codeFile = $fileName.FullName.ToString()
            $parseParams = @{
                sourceFile    = $codeFile
                show          = $false
                outputFolder  = $outputFolder
                cleanUp       = $true
                tmpRootFolder = $tmpFolder
                srcRootFolder = $srcRootFolder
            }
            if ($ClientSideRender) {
                $parseParams.Add("ClientSideRender", $true)
            }
            if ($SaveMmdFiles) {
                $parseParams.Add("SaveMmdFiles", $true)
            }
            Start-CblParse @parseParams
        }
    }
    
    Set-Content -Path $lastExecutionInfoFileName -Value $lastGenerationDate.ToString()
}

function HandleGsFiles {
    <#
    .SYNOPSIS
        Processes Dialog System screenset files (.gs) to generate HTML documentation.
    .DESCRIPTION
        1. Exports .gs files to .imp format using dswin.exe (with 30s timeout)
        2. Parses the .imp files to generate HTML with tabbed window views
    #>
    param(
        [string]$DedgeGsFolder,
        [string]$DedgeImpFolder,
        [string]$outputFolder,
        [string]$tmpFolder,
        [int]$lastGenerationDate,
        [string]$Regenerate,
        [int]$exitCounter = 10000
    )
    
    $dswinPath = "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\dswin.exe"
    $timeoutSeconds = 30
    
    # Check if dswin.exe exists
    if (-not (Test-Path $dswinPath)) {
        Write-LogMessage "dswin.exe not found at: $dswinPath - skipping GS file processing" -Level WARN
        return
    }
    
    # Ensure imp folder exists
    if (-not (Test-Path $DedgeImpFolder)) {
        New-Item -ItemType Directory -Path $DedgeImpFolder -Force | Out-Null
    }
    
    # Get all .gs files (exclude files with special characters)
    $gsFiles = Get-ChildItem -Path $DedgeGsFolder -Filter "*.gs" -ErrorAction SilentlyContinue | 
        Where-Object { -not ($_.Name.Contains("-") -or $_.Name.Contains("_") -or $_.Name.Contains(" ")) }
    
    if (-not $gsFiles -or $gsFiles.Count -eq 0) {
        Write-LogMessage "No GS files found in: $DedgeGsFolder" -Level WARN
        return
    }
    
    Write-LogMessage "All GS files: $($gsFiles.Count)" -Level INFO
    
    # Filter files that need regeneration
    $filesToProcess = @()
    $counter = 0
    foreach ($gsFile in $gsFiles) {
        # Create a pseudo FileInfo for the expected output file
        $expectedOutput = Join-Path $outputFolder "$($gsFile.BaseName).screen.html"
        
        $needsRegen = switch ($Regenerate) {
            "All" { $true }
            "Clean" { $true }
            "Incremental" {
                if (-not (Test-Path $expectedOutput)) { $true }
                elseif ($gsFile.LastWriteTime.ToString("yyyyMMdd") -gt $lastGenerationDate) { $true }
                else { $false }
            }
            "Errors" {
                $errFile = Join-Path $outputFolder "$($gsFile.BaseName).screen.err"
                Test-Path $errFile
            }
            default { $false }
        }
        
        if ($needsRegen) {
            $filesToProcess += $gsFile
            $counter++
            if ($counter -ge $exitCounter) { break }
        }
    }
    
    Write-LogMessage "GS files to process: $($filesToProcess.Count)" -Level INFO
    
    $exportedCount = 0
    $failedCount = 0
    
    foreach ($gsFile in $filesToProcess) {
        $baseName = $gsFile.BaseName.ToUpper()
        $impFile = Join-Path $DedgeImpFolder "$baseName.IMP"
        $htmlFile = Join-Path $outputFolder "$baseName.screen.html"
        $errFile = Join-Path $outputFolder "$baseName.screen.err"
        
        # Remove previous error file if exists
        if (Test-Path $errFile) {
            Remove-Item $errFile -Force -ErrorAction SilentlyContinue
        }
        
        try {
            # Step 1: Export .gs to .imp using dswin.exe with timeout
            Write-LogMessage "Exporting GS: $($gsFile.Name) -> $baseName.IMP" -Level DEBUG
            
            $process = Start-Process -FilePath $dswinPath `
                -ArgumentList "/e `"$($gsFile.FullName)`" `"$impFile`"" `
                -PassThru -NoNewWindow -ErrorAction Stop
            
            $completed = $false
            try {
                $completed = $process.WaitForExit($timeoutSeconds * 1000)
            }
            catch {
                $completed = $false
            }
            
            if (-not $completed) {
                # Process exceeded timeout - kill it
                Write-LogMessage "dswin.exe timeout for $($gsFile.Name) - killing process" -Level WARN
                
                if (-not $process.HasExited) {
                    $process | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                
                # Kill any lingering dswin.exe
                Get-Process -Name "dswin" -ErrorAction SilentlyContinue | ForEach-Object {
                    $_ | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                
                "Timeout: dswin.exe exceeded $timeoutSeconds seconds" | Set-Content -Path $errFile
                $failedCount++
                continue
            }
            
            # Verify .imp file was created
            if (-not (Test-Path $impFile)) {
                Write-LogMessage "Failed to export $($gsFile.Name) - no IMP file created" -Level WARN
                "Export failed: No IMP file created by dswin.exe" | Set-Content -Path $errFile
                $failedCount++
                continue
            }
            
            # Step 2: Parse .imp file and generate HTML
            Write-LogMessage "Parsing IMP: $baseName.IMP" -Level DEBUG
            
            Start-GsParse -ImpFile $impFile -OutputFolder $outputFolder
            
            if (Test-Path $htmlFile) {
                $exportedCount++
                Write-LogMessage "Generated: $baseName.screen.html" -Level INFO
            }
            else {
                Write-LogMessage "Failed to generate HTML for $baseName" -Level WARN
                "Parse failed: HTML file not generated" | Set-Content -Path $errFile
                $failedCount++
            }
        }
        catch {
            Write-LogMessage "Error processing $($gsFile.Name): $($_.Exception.Message)" -Level ERROR
            $_.Exception.Message | Set-Content -Path $errFile
            $failedCount++
        }
    }
    
    Write-LogMessage "GS processing complete: $exportedCount generated, $failedCount failed" -Level INFO
}

function HandleScriptFiles ($cobdokFolder, $DedgeRexFolder, $DedgeBatFolder, $DedgePshFolder, $outputFolder, $tmpFolder, $autoDocRootFolder, $lastGenerationDate, $Regenerate, $exitCounter = 10000, [switch]$ClientSideRender, [bool]$SaveMmdFiles = $true, [switch]$Parallel, [int]$ThrottleLimit = 6) {
    # Use the work folder containing cloned repositories for execution path analysis
    $srcRootFolder = $workFolder

    # ===== REX FILES =====
    $descArray = @()
    $descArray = Get-ChildItem -Path $DedgeRexFolder -Filter "*.rex"
    Write-LogMessage ("All Rexx files: " + $descArray.Count) -Level INFO

    # Filter files that need regeneration
    $rexFilesToProcess = @()
    $counter = 0
    foreach ($codeFile in $descArray) {
        if (RegenerateAutoDoc -fileName $codeFile -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
            $rexFilesToProcess += $codeFile
            $counter++
            if ($counter -ge $exitCounter) { break }
        }
    }
    Write-LogMessage ("REX files to process: " + $rexFilesToProcess.Count) -Level INFO

    if ($Parallel -and $rexFilesToProcess.Count -gt 1) {
        Invoke-ParallelFileParsing -FilesToProcess $rexFilesToProcess -ParserType "REX" `
            -OutputFolder $outputFolder -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder `
            -ClientSideRender $ClientSideRender -ThrottleLimit $ThrottleLimit -CommonDataPath ""
    }
    else {
        foreach ($codeFile in $rexFilesToProcess) {
            $parseParams = @{
                sourceFile    = $codeFile.FullName
                show          = $false
                outputFolder  = $outputFolder
                cleanUp       = $true
                tmpRootFolder = $tmpFolder
                srcRootFolder = $srcRootFolder
            }
            if ($ClientSideRender) { $parseParams.Add("ClientSideRender", $true) }
            if ($SaveMmdFiles) { $parseParams.Add("SaveMmdFiles", $true) }
            Start-RexParse @parseParams
        }
    }

    # ===== BAT FILES =====
    $descArray = @()
    # Skip files where basename starts with _ or - (internal/helper scripts)
    $descArray = Get-ChildItem -Path $DedgeBatFolder -Filter "*.bat" | Where-Object { $_.BaseName -notmatch '^[_-]' }
    Write-LogMessage ("All Batch files: " + $descArray.Count) -Level INFO

    # Filter files that need regeneration
    $batFilesToProcess = @()
    $counter = 0
    foreach ($codeFile in $descArray) {
        if (RegenerateAutoDoc -fileName $codeFile -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
            $batFilesToProcess += $codeFile
            $counter++
            if ($counter -ge $exitCounter) { break }
        }
    }
    Write-LogMessage ("BAT files to process: " + $batFilesToProcess.Count) -Level INFO

    if ($Parallel -and $batFilesToProcess.Count -gt 1) {
        Invoke-ParallelFileParsing -FilesToProcess $batFilesToProcess -ParserType "BAT" `
            -OutputFolder $outputFolder -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder `
            -ClientSideRender $ClientSideRender -ThrottleLimit $ThrottleLimit -CommonDataPath ""
    }
    else {
        foreach ($codeFile in $batFilesToProcess) {
            $parseParams = @{
                sourceFile    = $codeFile
                show          = $false
                outputFolder  = $outputFolder
                cleanUp       = $true
                tmpRootFolder = $tmpFolder
                srcRootFolder = $srcRootFolder
            }
            if ($ClientSideRender) { $parseParams.Add("ClientSideRender", $true) }
            if ($SaveMmdFiles) { $parseParams.Add("SaveMmdFiles", $true) }
            Start-BatParse @parseParams
        }
    }

    # Build module index for linking Import-Module statements
    Write-LogMessage "Building module index..." -Level INFO
    $moduleIndex = Build-ModuleIndex -ModulesFolder (Join-Path $DedgePshFolder "_Modules")
    Write-LogMessage "Module index built: $($moduleIndex.Count) modules" -Level INFO

    # ===== PS1 FILES =====
    $descArray = @()
    # Skip files where basename starts with _ or - (internal/helper scripts)
    $descArray = Get-ChildItem -Path $DedgePshFolder -Recurse -Filter "*.ps1" | Where-Object { $_.BaseName -notmatch '^[_-]' }
    Write-LogMessage ("All Powershell files: " + $descArray.Count) -Level INFO

    # Filter files that need regeneration
    $ps1FilesToProcess = @()
    $counter = 0
    foreach ($codeFile in $descArray) {
        if (RegenerateAutoDoc -fileName $codeFile -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
            $ps1FilesToProcess += $codeFile
            $counter++
            if ($counter -ge $exitCounter) { break }
        }
    }
    Write-LogMessage ("PS1 files to process: " + $ps1FilesToProcess.Count) -Level INFO

    if ($Parallel -and $ps1FilesToProcess.Count -gt 1) {
        Invoke-ParallelFileParsing -FilesToProcess $ps1FilesToProcess -ParserType "PS1" `
            -OutputFolder $outputFolder -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder `
            -ClientSideRender $ClientSideRender -ThrottleLimit $ThrottleLimit -CommonDataPath ""
    }
    else {
        foreach ($codeFile in $ps1FilesToProcess) {
            $parseParams = @{
                sourceFile    = $codeFile
                show          = $false
                outputFolder  = $outputFolder
                cleanUp       = $true
                tmpRootFolder = $tmpFolder
                srcRootFolder = $srcRootFolder
                ModuleIndex   = $moduleIndex
            }
            if ($ClientSideRender) { $parseParams.Add("ClientSideRender", $true) }
            if ($SaveMmdFiles) { $parseParams.Add("SaveMmdFiles", $true) }
            Start-Ps1Parse @parseParams
        }
    }

    # ===== PSM1 FILES =====
    $descArray = @()
    # Skip files where basename starts with _ or - (internal/helper scripts)
    $descArray = Get-ChildItem -Path $DedgePshFolder -Recurse -Filter "*.psm1" | Where-Object { $_.BaseName -notmatch '^[_-]' }
    Write-LogMessage ("All PowerShell module files: " + $descArray.Count) -Level INFO

    # Filter files that need regeneration
    $psm1FilesToProcess = @()
    $counter = 0
    foreach ($codeFile in $descArray) {
        if (RegenerateAutoDoc -fileName $codeFile -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
            $psm1FilesToProcess += $codeFile
            $counter++
            if ($counter -ge $exitCounter) { break }
        }
    }
    Write-LogMessage ("PSM1 files to process: " + $psm1FilesToProcess.Count) -Level INFO

    if ($Parallel -and $psm1FilesToProcess.Count -gt 1) {
        Invoke-ParallelFileParsing -FilesToProcess $psm1FilesToProcess -ParserType "PS1" `
            -OutputFolder $outputFolder -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder `
            -ClientSideRender $ClientSideRender -ThrottleLimit $ThrottleLimit -CommonDataPath ""
    }
    else {
        foreach ($codeFile in $psm1FilesToProcess) {
            $parseParams = @{
                sourceFile    = $codeFile
                show          = $false
                outputFolder  = $outputFolder
                cleanUp       = $true
                tmpRootFolder = $tmpFolder
                srcRootFolder = $srcRootFolder
                ModuleIndex   = $moduleIndex
            }
            if ($ClientSideRender) { $parseParams.Add("ClientSideRender", $true) }
            if ($SaveMmdFiles) { $parseParams.Add("SaveMmdFiles", $true) }
            Start-Ps1Parse @parseParams
        }
    }
}

function HandleSqlTables ($cobdokFolder, $DedgeRexFolder, $DedgeBatFolder, $DedgePshFolder, $outputFolder, $tmpFolder, $autoDocRootFolder, $lastGenerationDate, $Regenerate, $exitCounter = 10000, [switch]$Parallel, [int]$ThrottleLimit = 6) {
    $tableArray = Import-Csv ($cobdokFolder + "\tables.csv") -Header schemaName, tableName, comment, type, alter_time -Delimiter ';'
    Write-LogMessage ("All Sql tables: " + $tableArray.Count) -Level INFO
    # Use the work folder containing cloned repositories for execution path analysis
    $srcRootFolder = $workFolder

    # Filter tables that need regeneration
    $tablesToProcess = @()
    $counter = 0
    foreach ($tableInfo in $tableArray) {
        if (RegenerateAutoDocSql -tableInfo $tableInfo -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
            # Create object with TableName property for parallel processing
            $tablesToProcess += [PSCustomObject]@{
                TableName     = $tableInfo.schemaName.Trim() + "." + $tableInfo.tableName.Trim()
                SchemaName    = $tableInfo.schemaName.Trim()
                TableNameOnly = $tableInfo.tableName.Trim()
            }
            $counter++
            if ($counter -ge $exitCounter) { break }
        }
    }
    Write-LogMessage ("SQL tables to process: " + $tablesToProcess.Count) -Level INFO

    if ($Parallel -and $tablesToProcess.Count -gt 1) {
        # Parallel processing for SQL tables
        $processedCount = [ref]0
        $errorCount = [ref]0
        
        $tablesToProcess | ForEach-Object -Parallel {
            # Import modules and ensure globals are initialized for parallel runspace
            Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
            Initialize-GlobalFunctionsForParallel
            Import-Module -Name AutodocFunctions -Force -ErrorAction Stop
            
            $table = $_
            $outputFolder = $using:outputFolder
            $tmpRootFolder = $using:tmpFolder
            $srcRootFolder = $using:srcRootFolder
            
            try {
                Start-SqlParse -SqlTable $table.TableName -Show $false -OutputFolder $outputFolder `
                    -CleanUp $true -TmpRootFolder $tmpRootFolder -SrcRootFolder $srcRootFolder
                
                [System.Threading.Interlocked]::Increment($using:processedCount) | Out-Null
            }
            catch {
                [System.Threading.Interlocked]::Increment($using:errorCount) | Out-Null
                $errFilePath = Join-Path $outputFolder ($table.TableName.Replace(".", "_") + ".sql.err")
                "Error: $($_.Exception.Message)" | Set-Content -Path $errFilePath -Force
            }
        } -ThrottleLimit $ThrottleLimit
        
        Write-LogMessage ("Completed SQL: $($processedCount.Value) processed, $($errorCount.Value) errors") -Level INFO
    }
    else {
        # Sequential processing (original behavior)
        foreach ($table in $tablesToProcess) {
            Start-SqlParse -SqlTable $table.TableName -Show $false -OutputFolder $outputFolder `
                -CleanUp $true -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder
        }
    }
}

function HandleCSharpProjects ($serverMonitorFolder, $outputFolder, $tmpFolder, $srcRootFolder, $lastGenerationDate, $regenerate) {
    <#
    .SYNOPSIS
        Handles C# project parsing for AutoDoc.
    .DESCRIPTION
        Parses C# solutions and projects from all repositories in the work folder
        to generate class diagrams, project interaction diagrams, and ecosystem diagrams.
        Also searches for external callers (PS1, REX, CBL) that use the REST API or ports.
    #>
    
    # Search all repositories in the work folder, not just ServerMonitor
    $workFolderRoot = Split-Path $serverMonitorFolder -Parent
    if (-not (Test-Path $workFolderRoot)) {
        Write-LogMessage "Work folder not found: $workFolderRoot - Skipping C# parsing" -Level WARN
        return
    }
    
    Write-LogMessage "Starting C# project parsing for all repositories in $workFolderRoot..." -Level INFO
    
    # Find all solution files across all repositories
    $allSolutionFiles = Get-ChildItem -Path $workFolderRoot -Filter "*.sln" -Recurse -ErrorAction SilentlyContinue | 
        Where-Object { $_.FullName -notmatch '\\(bin|obj|\.vs|\.git)[\\/]' }
    
    if ($allSolutionFiles.Count -eq 0) {
        Write-LogMessage "No .sln files found in $workFolderRoot" -Level WARN
        return
    }
    
    Write-LogMessage "Found $($allSolutionFiles.Count) C# solution(s) across all repositories" -Level INFO
    
    # =========================================================================
    # STEP 1: Generate ECOSYSTEM diagram for each repository folder
    # This shows how all projects in each repository relate to each other
    # =========================================================================
    $repositories = $allSolutionFiles | ForEach-Object { Split-Path (Split-Path $_.FullName -Parent) -Leaf } | Sort-Object -Unique
    
    foreach ($repoName in $repositories) {
        $repoFolder = Join-Path $workFolderRoot $repoName
        if (-not (Test-Path $repoFolder)) { continue }
        
        $ecosystemName = $repoName
        $ecosystemHtmlPath = Join-Path $outputFolder "$ecosystemName.ecosystem.csharp.html"
        
        $shouldGenerateEcosystem = $true
        if ($regenerate -notin @("All", "Clean") -and (Test-Path $ecosystemHtmlPath)) {
            $ecosystemDate = [int](Get-Item $ecosystemHtmlPath).LastWriteTime.ToString("yyyyMMdd")
            
            # Check if any .csproj or .cs file is newer
            $newestFile = Get-ChildItem -Path $repoFolder -Include "*.csproj", "*.cs" -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|\.vs|\.git)[\\/]' } |
            Sort-Object LastWriteTime -Descending | 
            Select-Object -First 1
            
            if ($newestFile) {
                $newestDate = [int]$newestFile.LastWriteTime.ToString("yyyyMMdd")
                if ($newestDate -le $ecosystemDate) {
                    $shouldGenerateEcosystem = $false
                    Write-LogMessage "Skipping $ecosystemName ecosystem - No changes since last generation" -Level INFO
                }
            }
        }
        
        if ($shouldGenerateEcosystem) {
            try {
                Write-LogMessage "Generating ecosystem diagram for $ecosystemName (all projects combined)..." -Level INFO
                Start-CSharpEcosystemParse -RootFolder $repoFolder `
                    -OutputFolder $outputFolder `
                    -TmpRootFolder $tmpFolder `
                    -EcosystemName $ecosystemName
            }
            catch {
                Write-LogMessage "Error generating ecosystem diagram for ${ecosystemName}: $($_.Exception.Message)" -Level ERROR -Exception $_
            }
        }
    }
    
    # =========================================================================
    # STEP 2: Generate individual solution diagrams
    # =========================================================================
    $solutionFiles = $allSolutionFiles
    
    Write-LogMessage "Processing $($solutionFiles.Count) C# solution(s) individually..." -Level INFO
    
    foreach ($solution in $solutionFiles) {
        try {
            $solutionFolder = $solution.DirectoryName
            $solutionName = $solution.BaseName
            
            # Check if we should regenerate based on solution file date
            $htmlFileName = ($solutionName + ".csharp.html").ToLower()
            $htmlFilePath = Join-Path $outputFolder $htmlFileName
            
            $shouldRegenerate = $true
            if ($regenerate -notin @("All", "Clean") -and (Test-Path $htmlFilePath)) {
                $htmlDate = [int](Get-Item $htmlFilePath).LastWriteTime.ToString("yyyyMMdd")
                $slnDate = [int]$solution.LastWriteTime.ToString("yyyyMMdd")
                
                if ($slnDate -le $htmlDate -and $slnDate -le $lastGenerationDate) {
                    # Also check if any .cs files are newer
                    $newestCsFile = Get-ChildItem -Path $solutionFolder -Filter "*.cs" -Recurse -ErrorAction SilentlyContinue | 
                    Sort-Object LastWriteTime -Descending | 
                    Select-Object -First 1
                    
                    if ($newestCsFile) {
                        $csDate = [int]$newestCsFile.LastWriteTime.ToString("yyyyMMdd")
                        if ($csDate -le $htmlDate) {
                            $shouldRegenerate = $false
                            Write-LogMessage "Skipping $solutionName - No changes since last generation" -Level INFO
                        }
                    }
                    else {
                        $shouldRegenerate = $false
                    }
                }
            }
            
            if ($shouldRegenerate) {
                Write-LogMessage "Parsing C# solution: $($solution.Name)" -Level INFO
                Start-CSharpParse -SourceFolder $solutionFolder `
                    -SolutionFile $solution.FullName `
                    -OutputFolder $outputFolder `
                    -TmpRootFolder $tmpFolder `
                    -SrcRootFolder $srcRootFolder `
                    -ClientSideRender `
                    -CleanUp
            }
        }
        catch {
            Write-LogMessage "Error parsing C# solution $($solution.Name): $($_.Exception.Message)" -Level ERROR -Exception $_
        }
    }
    
    Write-LogMessage "C# project parsing completed" -Level INFO
}

function HandleCobdokExport ($cobdokFolder) {
    <#
    .SYNOPSIS
        Exports comprehensive DB2 system catalog metadata to CSV files.
    .DESCRIPTION
        Connects to cobdok and fkavdnt databases and exports table metadata,
        column definitions, indexes, constraints, foreign keys, triggers,
        and dependency information for documentation generation.
    #>
    Write-LogMessage ("Exporting tables from cobdok and fkavdnt databases") -Level INFO

    $array = @()

    $result = "del " + $cobdokFolder + "\" + "*.csv /F /Q"
    $array += $result

    # ========================================
    # COBDOK Database - Legacy COBOL metadata
    # ========================================
    $result = "db2 connect to cobdok"
    $array += $result

    $result = ExportTableContentToFile -exportTableName "call" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "cobdok_meny" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "copy" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "copyset" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "delsystem" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "modul" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "modkom" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "sqlxtab" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "tiltp_log" -folderPath $cobdokFolder
    $array += $result

    # ========================================
    # FKAVDNT Database - SQL table metadata
    # Enhanced exports for comprehensive documentation
    # ========================================
    $result = "db2 connect to fkavdnt"
    $array += $result

    # Core metadata
    $result = ExportTableContentToFile -exportTableName "tables" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "columns" -folderPath $cobdokFolder
    $array += $result

    # Index metadata
    $result = ExportTableContentToFile -exportTableName "indexes" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "indexcoluse" -folderPath $cobdokFolder
    $array += $result

    # Constraint metadata
    $result = ExportTableContentToFile -exportTableName "tabconst" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "keycoluse" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "references" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "checks" -folderPath $cobdokFolder
    $array += $result

    # Trigger metadata
    $result = ExportTableContentToFile -exportTableName "triggers" -folderPath $cobdokFolder
    $array += $result

    # Dependency metadata (which programs/packages use which tables)
    $result = ExportTableContentToFile -exportTableName "packagedep" -folderPath $cobdokFolder
    $array += $result

    $result = ExportTableContentToFile -exportTableName "routinedep" -folderPath $cobdokFolder
    $array += $result

    $result = "exit"
    $array += $result

    $outPutFile = $cobdokFolder + "\ExportTableContentToFile.cmd"
    Set-Content -Path $outPutFile -Value $array
    db2cmd.exe -w $outPutFile
    Write-Output "Export completed"

    # Convert all exported files from ANSI 1252 to UTF-8
    $filesToConvert = @(
        "call", "cobdok_meny", "copy", "copyset", "delsystem", "modul", "modkom", "sqlxtab", "tiltp_log",
        "tables", "columns", "indexes", "indexcoluse", "tabconst", "keycoluse", "references", "checks",
        "triggers", "packagedep", "routinedep"
    )
    
    foreach ($fileName in $filesToConvert) {
        ConvertFromAnsi1252ToUtf8 -exportTableName $fileName -folderPath $cobdokFolder
    }
    
    Write-LogMessage ("Exported $($filesToConvert.Count) metadata files to $cobdokFolder") -Level INFO
}

# NOTE: Repository cloning/updating is now handled by CloneDedgeToCommonWorkFolder.ps1
# which is called at the start of the MAIN section with proper PAT authentication.

function SetFullFolderPath ($folderPath) {
    $returnPath = $folderPath
    try {

        # Set folders to correct full path
        Push-Location
        Set-Location -Path $folderPath
        $returnPath = (Get-Location).Path
        Pop-Location
    }
    catch {
        <#Do this if a terminating exception happens#>
    }
    return $returnPath
}
function CreateFolderIfNeeded ($folderPath) {
    # Check if the folder exists and create it if it doesn't
    if (-not (Test-Path -Path $folderPath -PathType Container)) {
        New-Item -Path $folderPath -ItemType Directory
    }
}

function Copy-StaticAssetsToOutput {
    <#
    .SYNOPSIS
        Copies static asset folders (_js, _css, _images, _json, _templates) from source to output folder
    .DESCRIPTION
        Ensures the output folder has all required static assets for the AutoDoc web application.
        This includes JavaScript, CSS, images, JSON data files, and HTML templates.
    .PARAMETER SourceRoot
        The source folder containing the static asset subfolders (defaults to $PSScriptRoot)
    .PARAMETER OutputRoot
        The target output folder where assets will be copied
    #>
    param(
        [string]$SourceRoot = $PSScriptRoot,
        [string]$OutputRoot
    )
    
    Write-LogMessage "Copying static assets to output folder: $OutputRoot" -Level INFO
    
    # Define folders to copy
    $assetFolders = @("_js", "_css", "_images", "_templates")
    
    foreach ($folder in $assetFolders) {
        $sourceFolder = Join-Path $SourceRoot $folder
        $targetFolder = Join-Path $OutputRoot $folder
        
        if (Test-Path $sourceFolder) {
            # Create target folder if needed
            if (-not (Test-Path $targetFolder)) {
                New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
            }
            
            # Copy all files from source to target
            Copy-Item -Path "$sourceFolder\*" -Destination $targetFolder -Force -Recurse -ErrorAction SilentlyContinue
            $fileCount = (Get-ChildItem -Path $sourceFolder -File -ErrorAction SilentlyContinue).Count
            Write-LogMessage "  Copied $folder/ ($fileCount files)" -Level INFO
        }
        else {
            Write-LogMessage "  Source folder not found: $sourceFolder" -Level WARN
        }
    }
    
    # Copy index.html from _templates/ to root of output
    $templatesFolder = Join-Path $SourceRoot "_templates"
    $indexFile = Join-Path $templatesFolder "index.html"
    if (Test-Path $indexFile) {
        Copy-Item -Path $indexFile -Destination $OutputRoot -Force -ErrorAction SilentlyContinue
        Write-LogMessage "  Copied index.html to output root" -Level INFO
    }
    
    # Copy web.config from _templates/ to root of output (IIS configuration)
    $webConfigFile = Join-Path $templatesFolder "web.config"
    $destWebConfig = Join-Path $OutputRoot "web.config"
    if ((Test-Path $webConfigFile) -and (-not (Test-Path $destWebConfig))) {
        Copy-Item -Path $webConfigFile -Destination $OutputRoot -Force -ErrorAction SilentlyContinue
        Write-LogMessage "  Copied web.config to output root" -Level INFO
    }
    
    # Ensure .json folder exists (will be populated by CreateJsonFile* functions)
    $jsonFolder = Join-Path $OutputRoot "_json"
    if (-not (Test-Path $jsonFolder)) {
        New-Item -ItemType Directory -Path $jsonFolder -Force | Out-Null
        Write-LogMessage "  Created _json/ folder" -Level INFO
    }
    
    Write-LogMessage "Static assets copied successfully" -Level INFO
}

############################################################################################################
# MAIN
############################################################################################################

# Parameter handling

# Copy scheduled task XML files to the search directory
# These files are the origin of most automated tasks and help trace execution paths
# $scheduledTasksSource = "\\p-no1fkmprd-app\opt\data\ScheduledTasksExport"
# $scheduledTasksTarget = "$env:OptPath\work\DedgeRepository\ScheduledTasksExport"

# if (Test-Path $scheduledTasksSource -PathType Container) {
#     try {
#         if (-not (Test-Path $scheduledTasksTarget -PathType Container)) {
#             New-Item -Path $scheduledTasksTarget -ItemType Directory -Force | Out-Null
#         }
#         Write-Host "Copying scheduled task files from $scheduledTasksSource to $scheduledTasksTarget"
#         robocopy $scheduledTasksSource $scheduledTasksTarget *.xml /MIR /R:1 /W:1 /NJH /NJS /NFL /NDL /NC /NS 2>&1 | Out-Null
#         Write-Host "Scheduled task files copied successfully"
#     }
#     catch {
#         Write-Host "Warning: Could not copy scheduled task files: $($_.Exception.Message)"
#     }
# }
# else {
#     Write-Host "Warning: Scheduled tasks source folder not accessible: $scheduledTasksSource"
# }

# NOTE: Repository update using Sync-MultipleAzureDevOpsRepositories is called after variable definitions below

# NOTE: npm/puppeteer/mermaid-cli package checks removed - using client-side rendering only

if ($Regenerate.Length -eq 0) {
    Write-Error "Missing parameter regenerate"
    exit
}

Write-Host "==> AutoDocBatchRunner started. regenerate = " $Regenerate

# Get the folder containing the script
Set-Location -Path $PSScriptRoot

# ============================================================
# RAM DISK INITIALIZATION (if requested)
# If -UseRamDisk is specified, attempt to create a RAM disk on V:
# All temporary work files and repo clones will use V:\AutoDoc
# Falls back to standard folders if creation fails
# ============================================================
if ($UseRamDisk) {
    $ramDiskResult = Initialize-RamDisk -SizeGB $RamDiskSizeGB
    if ($ramDiskResult) {
        Write-LogMessage "RAM disk mode ENABLED - Using $ramDiskResult for work files" -Level INFO
    }
    else {
        Write-LogMessage "RAM disk creation failed - Using standard folder system" -Level WARN
    }
}

# Define folder paths - use $env:OptPath\data\AutoDoc for local data
# If RAM disk is active, work files (repos, temp) go to V:\AutoDoc
# Output and config files always stay in $env:OptPath\data\AutoDoc
$autoDocDataFolder = "$env:OptPath\data\AutoDoc"
$autoDocRootFolder = $autoDocDataFolder

# Get work folder root (V:\AutoDoc if RAM disk active, otherwise standard path)
$workFolderRoot = Get-WorkFolderRoot -StandardRoot $autoDocDataFolder

# Store last execution info in data folder, not script folder (always on local disk)
$lastExecutionInfoFileName = "$autoDocDataFolder\AutoDocBatchRunner.dat"

# Work folder uses RAM disk if active, otherwise standard path
# This includes git clones, temp files, and cobdok exports
$workFolder = "$workFolderRoot\tmp\DedgeRepository"
$DedgeFolder = $workFolder + "\Dedge"
$DedgePshFolder = $workFolder + "\DedgePsh"
$ServerMonitorFolder = $workFolder + "\ServerMonitor"

$DedgeCblFolder = $DedgeFolder + "\cbl"
$DedgeGsFolder = $DedgeFolder + "\gs"
$DedgeImpFolder = $DedgeFolder + "\imp"
$DedgeRexFolder = $DedgeFolder + "\rexx_prod"
$DedgeBatFolder = $DedgeFolder + "\bat_prod"
$appsFolderTmp = "$env:OptPath\data\AutoDoc\Sync"

# Log the folder configuration
if ($script:RamDiskActive) {
    Write-LogMessage "Work folders configured on RAM disk:" -Level INFO
    Write-LogMessage "  Work folder: $workFolder" -Level INFO
    Write-LogMessage "  Output folder: $OutputFolder (local disk)" -Level INFO
}

# OutputFolder: Always use the parameter value (defaults to $env:OptPath\Webs\AutoDoc)
# The -OutputFolder parameter should be respected - don't override it based on server name
# webFolderRoot is always the same as OutputFolder (both generated content and web serving)
$webFolderRoot = $OutputFolder
Write-LogMessage "Output folder: $OutputFolder" -Level INFO

# Clean mode: Full reset - clears data folders, git checkouts, and generated files
# This is the ONLY mode that deletes files from OutputFolder
# PRESERVE: _images, _js, and _css subfolders in output folder (static assets)
if ($Regenerate -eq "Clean") {
    Write-LogMessage "Clean mode: Resetting AutoDoc data folders for fresh regeneration..." -Level WARN
    
    # 1. Remove tmp folder (includes cobdok, thread folders, .dat file) - forces full regeneration
    # Check both standard path and RAM disk path
    $tmpFolderPath = "$autoDocDataFolder\tmp"
    if (Test-Path $tmpFolderPath) {
        Write-LogMessage "Removing tmp folder: $tmpFolderPath" -Level INFO
        Remove-Item -Path $tmpFolderPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Also clean RAM disk tmp folder if RAM disk is active
    if ($script:RamDiskActive) {
        $ramTmpPath = "$($script:RamDiskDriveLetter)\AutoDoc\tmp"
        if (Test-Path $ramTmpPath) {
            Write-LogMessage "Removing RAM disk tmp folder: $ramTmpPath" -Level INFO
            Remove-Item -Path $ramTmpPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # 2. Remove last execution info file to force regeneration
    $lastExecFile = "$autoDocDataFolder\AutoDocLastExecution.dat"
    if (Test-Path $lastExecFile) {
        Write-LogMessage "Removing last execution file: $lastExecFile" -Level INFO
        Remove-Item -Path $lastExecFile -Force -ErrorAction SilentlyContinue
    }
    
    # 3. Remove git checkout folders to get fresh copies
    if (Test-Path $workFolder) {
        Write-LogMessage "Removing git checkouts: $workFolder" -Level INFO
        Remove-Item -Path $workFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # 4. Remove all generated files (html, mmd, err, json) except protected files
    #    PRESERVE: _images, _js, _css subfolders (static assets - logos, icons, JS/CSS libraries)
    #    PRESERVE: index.html, web.config (IIS configuration)
    #    CLEAR: _json subfolder (parser results need to be regenerated)
    #    If FileTypes is specified, only clean files matching those types
    $protectedFiles = @("index.html", "web.config")
    
    # Map FileTypes to file patterns
    $fileTypePatterns = @{
        'Cbl'    = @('*.cbl.html')
        'Rex'    = @('*.rex.html')
        'Bat'    = @('*.bat.html')
        'Ps1'    = @('*.ps1.html', '*.psm1.html')
        'Sql'    = @('*.sql.html')
        'CSharp' = @('*.csharp.html')
        'Gs'     = @('*.screen.html', '*.gs.html')
    }
    
    # Determine which file patterns to clean based on FileTypes
    $patternsToClean = @()
    if ($FileTypes -contains 'All') {
        # Clean all file types
        $patternsToClean = $fileTypePatterns.Values | ForEach-Object { $_ }
    }
    else {
        # Clean only specified file types
        foreach ($fileType in $FileTypes) {
            if ($fileTypePatterns.ContainsKey($fileType)) {
                $patternsToClean += $fileTypePatterns[$fileType]
            }
        }
    }
    
    if (Test-Path $OutputFolder) {
        if ($patternsToClean.Count -gt 0) {
            Write-LogMessage "Clean mode: Removing generated files from output folder (FileTypes: $($FileTypes -join ', '))..." -Level INFO
        }
        else {
            Write-LogMessage "Clean mode: Removing all generated files from output folder..." -Level INFO
        }
        Write-LogMessage "Protected files: $($protectedFiles -join ', ')" -Level INFO
        
        # Remove .html files matching specified patterns (or all if no FileTypes filter)
        if ($patternsToClean.Count -gt 0) {
            # Clean only files matching specified FileTypes
            $htmlFilesToRemove = @()
            foreach ($pattern in $patternsToClean) {
                $matchingFiles = Get-ChildItem -Path $OutputFolder -Filter $pattern -File -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -notin $protectedFiles }
                $htmlFilesToRemove += $matchingFiles
            }
            if ($htmlFilesToRemove.Count -gt 0) {
                $htmlFilesToRemove | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $($htmlFilesToRemove.Count) HTML files matching FileTypes: $($FileTypes -join ', ')" -Level INFO
            }
            
            # Remove matching .mmd files
            $mmdFilesToRemove = @()
            foreach ($pattern in $patternsToClean) {
                $mmdPattern = $pattern -replace '\.html$', '.mmd'
                $matchingMmd = Get-ChildItem -Path $OutputFolder -Filter $mmdPattern -File -ErrorAction SilentlyContinue
                $mmdFilesToRemove += $matchingMmd
            }
            if ($mmdFilesToRemove.Count -gt 0) {
                $mmdFilesToRemove | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $($mmdFilesToRemove.Count) MMD files matching FileTypes: $($FileTypes -join ', ')" -Level INFO
            }
            
            # Remove matching .err files
            $errFilesToRemove = @()
            foreach ($pattern in $patternsToClean) {
                $errPattern = $pattern -replace '\.html$', '.err'
                $matchingErr = Get-ChildItem -Path $OutputFolder -Filter $errPattern -File -ErrorAction SilentlyContinue
                $errFilesToRemove += $matchingErr
            }
            if ($errFilesToRemove.Count -gt 0) {
                $errFilesToRemove | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $($errFilesToRemove.Count) ERR files matching FileTypes: $($FileTypes -join ', ')" -Level INFO
            }
        }
        else {
            # Clean all files (original behavior when FileTypes not specified or empty)
            $htmlFiles = Get-ChildItem -Path $OutputFolder -Filter "*.html" -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -notin $protectedFiles }
            if ($htmlFiles) {
                $htmlFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $($htmlFiles.Count) HTML files (kept: $($protectedFiles -join ', '))" -Level INFO
            }
            
            # Remove all .mmd files
            $mmdFiles = Get-ChildItem -Path $OutputFolder -Filter "*.mmd" -File -ErrorAction SilentlyContinue
            if ($mmdFiles) {
                $mmdFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $($mmdFiles.Count) MMD files" -Level INFO
            }
            
            # Remove all .err files
            $errFiles = Get-ChildItem -Path $OutputFolder -Filter "*.err" -File -ErrorAction SilentlyContinue
            if ($errFiles) {
                $errFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $($errFiles.Count) ERR files" -Level INFO
            }
        }
        
        # Clear _json folder content (parser results need to be regenerated)
        # Only clean JSON files matching FileTypes if specified
        $jsonFolder = Join-Path $OutputFolder "_json"
        if (Test-Path $jsonFolder) {
            if ($patternsToClean.Count -gt 0) {
                # Clean only JSON files matching FileTypes
                $jsonFilesToRemove = @()
                foreach ($fileType in $FileTypes) {
                    $jsonPattern = "*$fileType*.json"
                    $matchingJson = Get-ChildItem -Path $jsonFolder -Filter $jsonPattern -File -ErrorAction SilentlyContinue
                    $jsonFilesToRemove += $matchingJson
                }
                if ($jsonFilesToRemove.Count -gt 0) {
                    $jsonFilesToRemove | Remove-Item -Force -ErrorAction SilentlyContinue
                    Write-LogMessage "Cleared _json folder ($($jsonFilesToRemove.Count) JSON files removed matching FileTypes: $($FileTypes -join ', '))" -Level INFO
                }
            }
            else {
                # Clean all JSON files
                $jsonFiles = Get-ChildItem -Path $jsonFolder -Filter "*.json" -File -ErrorAction SilentlyContinue
                if ($jsonFiles) {
                    $jsonFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                    Write-LogMessage "Cleared _json folder ($($jsonFiles.Count) JSON files removed)" -Level INFO
                }
            }
        }
    }
    
    Write-LogMessage "Clean mode: Data reset complete. Preserved: _images/, _js/, _css/ folders, index.html, web.config" -Level INFO
}

# Regenerate = "All": Regenerate all files without deleting anything (just overwrite when processing)
# Note: No file deletions here - files are simply overwritten when regenerated
if ($Regenerate -eq "All") {
    Write-LogMessage "All mode: Will regenerate all files (overwrite existing, no deletions)" -Level INFO
}

# Temp and cobdok folders use RAM disk if active for faster I/O
$tmpFolder = "$workFolderRoot\tmp"
$cobdokFolder = "$workFolderRoot\tmp\cobdok"

# Create folders if needed
CreateFolderIfNeeded -folderPath $autoDocRootFolder
# CreateFolderIfNeeded -folderPath $DedgeFolder
# CreateFolderIfNeeded -folderPath $DedgePshFolder
# CreateFolderIfNeeded -folderPath $DedgeRexFolder
# CreateFolderIfNeeded -folderPath $DedgeCblFolder
# CreateFolderIfNeeded -folderPath $DedgeBatFolder
CreateFolderIfNeeded -folderPath $tmpFolder
CreateFolderIfNeeded -folderPath $cobdokFolder
CreateFolderIfNeeded -folderPath $outputFolder

# Set folders to correct full path
$autoDocRootFolder = SetFullFolderPath -folderPath $autoDocRootFolder
# $DedgeFolder = SetFullFolderPath -folderPath $DedgeFolder
# $DedgePshFolder = SetFullFolderPath -folderPath $DedgePshFolder
# $DedgeRexFolder = SetFullFolderPath -folderPath $DedgeRexFolder
# $DedgeCblFolder = SetFullFolderPath -folderPath $DedgeCblFolder
# $DedgeBatFolder = SetFullFolderPath -folderPath $DedgeBatFolder
$tmpFolder = SetFullFolderPath -folderPath $tmpFolder
$cobdokFolder = SetFullFolderPath -folderPath $cobdokFolder
$outputFolder = SetFullFolderPath -folderPath $outputFolder
$machineName = $env:COMPUTERNAME.ToLower()

Write-LogMessage ("AutoDocBatchRunner started on: $machineName. Parameter regenerate = " + $Regenerate) -Level INFO
Write-LogMessage ("Started " + $MyInvocation.MyCommand.Name + " using Powershell version: " + $PSVersionTable.PSVersion.Major.ToString() + "." + $PSVersionTable.PSVersion.Minor.ToString()) -Level INFO

# Copy static assets to output folder at startup
# This ensures _js/, _css/, _images/, _templates/ and index.html are available before processing
Copy-StaticAssetsToOutput -SourceRoot $PSScriptRoot -OutputRoot $outputFolder

# JSON files go to .json subfolder
$jsonOutputFolder = Join-Path $outputFolder "_json"
if (-not (Test-Path $jsonOutputFolder)) {
    New-Item -ItemType Directory -Path $jsonOutputFolder -Force | Out-Null
}
# JSON index files are generated at end of job by CreateAllJsonIndexFiles


# Single file mode - process only one specific file for testing
if (-not [string]::IsNullOrEmpty($SingleFile)) {
    Write-LogMessage ("Single file mode: Processing $SingleFile") -Level INFO
    $Parallel = $false
    $ThreadPercentage = 100
    $MaxFilesPerType = 1
    $ClientSideRender = $true
    $SaveMmdFiles = $true
    $QuickRun = $true
    $Regenerate = "Single"
}
    

#Check if the machine name is dedge-server and zip file exists, and unzip it to $outputFolder
if ($Regenerate -ne "JsonOnly") {
    <# Action to perform if the condition is true #>
    $machineName = $env:COMPUTERNAME.ToLower()
    Write-LogMessage ("Running on " + $machineName) -Level INFO
    if ($machineName -eq "dedge-server") {
        $zipFileName = $tmpFolder + "\content.zip"
        if (Test-Path $zipFileName -PathType Leaf) {
            Write-LogMessage ("Unzipping " + $zipFileName + " to " + $autoDocRootFolder) -Level INFO
            Expand-Archive -Path $zipFileName -DestinationPath $autoDocRootFolder -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $zipFileName -Force -ErrorAction SilentlyContinue
            Write-LogMessage ("Unzip completed") -Level INFO
        }
    }

    # Update source repositories from Azure DevOps using AzureFunctions module
    if ($QuickRun -and $(Get-ChildItem -Path $DedgeFolder -Recurse -File).Count -gt 0) {
        Write-Host "Skipping git clone/update (QuickRun = true)"
    }
    else {
        Write-Host "Discovering and updating source repositories from Azure DevOps..."
        
        # Discover all repositories in Project Dedge
        $discoveredRepos = Get-AzureDevOpsRepositories -Organization "Dedge" -Project "Dedge"
        
        if ($discoveredRepos -and $discoveredRepos.Count -gt 0) {
            Write-LogMessage "Discovered $($discoveredRepos.Count) repositories in Project Dedge" -Level INFO
            $repositories = @()
            foreach ($repo in $discoveredRepos) {
                $repoFolder = Join-Path $workFolder $repo.Name
                $repositories += @{ Name = $repo.Name; Folder = $repoFolder }
                Write-LogMessage "  - $($repo.Name) -> $repoFolder" -Level DEBUG
            }
        }
        else {
            # Fallback to hardcoded list if discovery fails
            Write-LogMessage "Repository discovery failed or returned no results, using hardcoded list" -Level WARN
            $repositories = @(
                @{ Name = "Dedge"; Folder = $DedgeFolder },
                @{ Name = "DedgePsh"; Folder = $DedgePshFolder },
                @{ Name = "ServerMonitor"; Folder = $ServerMonitorFolder }
            )
        }
        
        Write-LogMessage "Syncing $($repositories.Count) repositories..." -Level INFO
        $repoUpdateResult = Sync-MultipleAzureDevOpsRepositories -Repositories $repositories
        
        if ($repoUpdateResult.Success) {
            Write-Host "Source repositories updated: $($repoUpdateResult.SuccessCount) synced, $($repoUpdateResult.FailedCount) failed"
        }
        else {
            Write-Host "Warning: Could not update source repositories. Continuing with existing files..."
        }
    }

    if ($QuickRun -and $(Get-ChildItem -Path $cobdokFolder -Recurse -File).Count -gt 0) {
        Write-Host "Skipping cobdok export (QuickRun = true)"
    }
    else {
        HandleCobdokExport -cobdokFolder $cobdokFolder
    }

    $lastGenerationDate = 0
    if (Test-Path $lastExecutionInfoFileName -PathType Leaf) {
        $lastGenerationDate = Get-Content -Path $lastExecutionInfoFileName
        $lastGenerationDate = [int]$lastGenerationDate
    }

    if ($lastGenerationDate.Length -eq 0 -or $lastGenerationDate -eq 0) {
        $lastGenerationDate = [int](Get-Date).AddDays(-10).ToString("yyyyMMdd")
    }

    if ($Regenerate -ne "Errors") {
        $nextGenerationDate = [int](Get-Date).AddDays(-1).ToString("yyyyMMdd")
        Set-Content -Path $lastExecutionInfoFileName -Value $nextGenerationDate.ToString()
        Write-LogMessage ("Last generation date: " + $lastGenerationDate.ToString()) -Level INFO
    }

    # Single file mode - process only one specific file for testing
    if (-not [string]::IsNullOrEmpty($SingleFile)) {
        Write-LogMessage ("Single file mode: Processing $SingleFile") -Level INFO
        # Use the work folder containing cloned repositories for execution path analysis
        $srcRootFolder = $workFolder
        
        Set-Location -Path $PSScriptRoot
        
        # Check if this is a SQL table name (format: SCHEMA.TABLE or no file extension)
        $isSqlTable = $false
        if ($SingleFile -match '^[A-Z]+\.[A-Z0-9_]+$' -or ($SingleFile -notlike "*.*" -and $SingleFile -match '^[A-Z]')) {
            # Looks like a SQL table name (e.g., DBM.FAKTHIST99B)
            $isSqlTable = $true
            Write-LogMessage ("Detected SQL table: $SingleFile") -Level INFO
        }
        
        if ($isSqlTable) {
            # Process SQL table directly
            $parseParams = @{
                SqlTable      = $SingleFile
                Show          = $false
                OutputFolder  = $outputFolder
                CleanUp       = $true
                TmpRootFolder = $tmpFolder
                SrcRootFolder = $srcRootFolder
            }
            
            Start-SqlParse @parseParams
            Write-LogMessage ("Single SQL table processing complete: $SingleFile") -Level INFO
            exit 0  # Exit successfully - skip JSON generation, SMS, and other batch processing
        }
        
        # Find the source file
        $sourceFilePath = $null
        if (Test-Path $SingleFile -PathType Leaf) {
            $sourceFilePath = $SingleFile
        }
        elseif (Test-Path (Join-Path $DedgeCblFolder $SingleFile) -PathType Leaf) {
            $sourceFilePath = Join-Path $DedgeCblFolder $SingleFile
        }
        elseif (Test-Path (Join-Path $DedgePshFolder $SingleFile) -PathType Leaf) {
            $sourceFilePath = Join-Path $DedgePshFolder $SingleFile
        }
        
        if ($null -eq $sourceFilePath) {
            Write-LogMessage ("Could not find source file: $SingleFile") -Level ERROR
            Write-Error "Could not find source file: $SingleFile"
            return
        }
        
        Write-LogMessage ("Found source file: $sourceFilePath") -Level INFO
        $fileExt = [System.IO.Path]::GetExtension($sourceFilePath).ToLower()
        
        # Build common parameters
        $parseParams = @{
            sourceFile    = $sourceFilePath
            show          = $false
            outputFolder  = $outputFolder
            cleanUp       = $true
            tmpRootFolder = $tmpFolder
            srcRootFolder = $srcRootFolder
        }
        
        # Add ClientSideRender if specified (now supported for all parser types)
        if ($ClientSideRender) {
            $parseParams.Add("ClientSideRender", $true)
            Write-LogMessage ("Using client-side Mermaid.js rendering") -Level INFO
        }
        
        # Add SaveMmdFiles if specified
        if ($SaveMmdFiles) {
            $parseParams.Add("SaveMmdFiles", $true)
            Write-LogMessage ("Saving Mermaid diagram source files (.mmd)") -Level INFO
        }
        
        switch ($fileExt) {
            ".cbl" {
                Start-CblParse @parseParams
            }
            ".ps1" {
                Start-Ps1Parse @parseParams
            }
            ".rex" {
                Start-RexParse @parseParams
            }
            ".bat" {
                Start-BatParse @parseParams
            }
            ".sln" {
                # C# Solution file - use Start-CSharpParse
                $solutionFolder = [System.IO.Path]::GetDirectoryName($sourceFilePath)
                Write-LogMessage ("Processing C# solution from folder: $solutionFolder") -Level INFO
                
                Start-CSharpParse -SourceFolder $solutionFolder `
                    -SolutionFile $sourceFilePath `
                    -OutputFolder $outputFolder `
                    -TmpRootFolder $tmpFolder `
                    -SrcRootFolder $srcRootFolder `
                    -ClientSideRender `
                    -CleanUp
            }
            default {
                Write-LogMessage ("Unsupported file type: $fileExt") -Level ERROR
                Write-Error "Unsupported file type: $fileExt"
                return
            }
        }
        
        Write-LogMessage ("Single file processing complete: $SingleFile") -Level INFO
        exit 0  # Exit successfully - skip JSON generation, SMS, and other batch processing
    }

    # Use maxFilesPerType if specified, otherwise use a high default value
    $exitCounter = if ($MaxFilesPerType -gt 0) { $MaxFilesPerType } else { 100000 }
    if ($MaxFilesPerType -gt 0) {
        Write-LogMessage ("Simulation mode: Processing max $MaxFilesPerType files per type") -Level INFO
    }
    
    # Calculate parallel processing settings
    # ThreadCountMax overrides ThreadPercentage if set (> 0)
    $threadInfo = Get-OptimalThreadCount -Percentage $ThreadPercentage -MaxThreads $ThreadCountMax
    $throttleLimit = $threadInfo.Threads
    Write-LogMessage "Thread configuration: $($threadInfo.Threads) threads (Mode: $($threadInfo.Mode), Cores: $($threadInfo.TotalCores))" -Level INFO
    # Use the work folder containing cloned repositories for execution path analysis
    $srcRootFolder = $workFolder
    
    if ($Parallel) {
        # ============================================================
        # UNIFIED QUEUE PARALLEL PROCESSING
        # All threads start immediately on a single work queue.
        # Non-CBL items (REX, BAT, PS1, SQL) placed first for faster completion.
        # CBL items follow - all threads work on whatever is next in queue.
        # ============================================================
        
        Write-LogMessage ("Parallel processing ENABLED: $throttleLimit threads on unified queue") -Level INFO
        
        # Export common data for parallel workers
        $commonDataPath = Join-Path $tmpFolder "CommonParseData.xml"
        Export-CommonParseData -CobdokFolder $cobdokFolder -ExportPath $commonDataPath | Out-Null
        Write-LogMessage ("Common parse data exported to: $commonDataPath") -Level INFO
        
        # ============================================================
        # COLLECT FILES INTO SEPARATE QUEUES BY CATEGORY
        # ============================================================
        
        $nonCblQueue = @()  # REX, BAT, PS1, SQL
        $cblQueue = @()     # CBL files
        
        # Collect CBL files (only if Cbl is in FileTypes)
        if ('Cbl' -in $FileTypes) {
            Write-LogMessage "Collecting CBL files..." -Level INFO
            $cblFiles = Get-ChildItem -Path $DedgeCblFolder -Filter "*.cbl" | Where-Object { !$_.Name.Contains("-") }
            $cblCounter = 0
            foreach ($file in $cblFiles) {
                if (RegenerateAutoDoc -fileName $file -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
                    $cblQueue += [PSCustomObject]@{
                        ParserType = "CBL"
                        FilePath   = $file.FullName
                        FileName   = $file.Name
                        TableName  = $null
                    }
                    $cblCounter++
                    if ($cblCounter -ge $exitCounter) { break }
                }
            }
        }
        
        # Collect REX files (only if Rex is in FileTypes)
        if ('Rex' -in $FileTypes) {
            Write-LogMessage "Collecting REX files..." -Level INFO
            $rexFiles = Get-ChildItem -Path $DedgeRexFolder -Filter "*.rex"
            $rexCounter = 0
            foreach ($file in $rexFiles) {
                if (RegenerateAutoDoc -fileName $file -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
                    $nonCblQueue += [PSCustomObject]@{
                        ParserType = "REX"
                        FilePath   = $file.FullName
                        FileName   = $file.Name
                        TableName  = $null
                    }
                    $rexCounter++
                    if ($rexCounter -ge $exitCounter) { break }
                }
            }
        }
        
        # Collect BAT files (only if Bat is in FileTypes, skip files where basename starts with _ or -)
        if ('Bat' -in $FileTypes) {
            Write-LogMessage "Collecting BAT files..." -Level INFO
            $batFiles = Get-ChildItem -Path $DedgeBatFolder -Filter "*.bat" | Where-Object { $_.BaseName -notmatch '^[_-]' }
            $batCounter = 0
            foreach ($file in $batFiles) {
                if (RegenerateAutoDoc -fileName $file -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
                    $nonCblQueue += [PSCustomObject]@{
                        ParserType = "BAT"
                        FilePath   = $file.FullName
                        FileName   = $file.Name
                        TableName  = $null
                    }
                    $batCounter++
                    if ($batCounter -ge $exitCounter) { break }
                }
            }
        }
        
        # Collect PS1 files (only if Ps1 is in FileTypes, skip files where basename starts with _ or -)
        if ('Ps1' -in $FileTypes) {
            Write-LogMessage "Collecting PS1 files..." -Level INFO
            $ps1Files = Get-ChildItem -Path $DedgePshFolder -Recurse -Filter "*.ps1" | Where-Object { $_.BaseName -notmatch '^[_-]' }
            $ps1Counter = 0
            foreach ($file in $ps1Files) {
                if (RegenerateAutoDoc -fileName $file -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
                    $nonCblQueue += [PSCustomObject]@{
                        ParserType = "PS1"
                        FilePath   = $file.FullName
                        FileName   = $file.Name
                        TableName  = $null
                    }
                    $ps1Counter++
                    if ($ps1Counter -ge $exitCounter) { break }
                }
            }
        }
        
        # Collect PSM1 files (only if Ps1 is in FileTypes, skip files where basename starts with _ or -)
        if ('Ps1' -in $FileTypes) {
            Write-LogMessage "Collecting PSM1 files..." -Level INFO
            $psm1Files = Get-ChildItem -Path $DedgePshFolder -Recurse -Filter "*.psm1" | Where-Object { $_.BaseName -notmatch '^[_-]' }
            $psm1Counter = 0
            foreach ($file in $psm1Files) {
                if (RegenerateAutoDoc -fileName $file -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
                    $nonCblQueue += [PSCustomObject]@{
                        ParserType = "PSM1"
                        FilePath   = $file.FullName
                        FileName   = $file.Name
                        TableName  = $null
                    }
                    $psm1Counter++
                    if ($psm1Counter -ge $exitCounter) { break }
                }
            }
        }
        
        # Collect SQL tables (only if Sql is in FileTypes and not Errors mode)
        if ('Sql' -in $FileTypes -and $Regenerate -ne "Errors") {
            Write-LogMessage "Collecting SQL tables..." -Level INFO
            $tableArray = Import-Csv ($cobdokFolder + "\tables.csv") -Header schemaName, tableName, comment, type, alter_time -Delimiter ';'
            $sqlCounter = 0
            foreach ($tableInfo in $tableArray) {
                if (RegenerateAutoDocSql -tableInfo $tableInfo -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -outputFolder $outputFolder) {
                    $tableName = $tableInfo.schemaName.Trim() + "." + $tableInfo.tableName.Trim()
                    $nonCblQueue += [PSCustomObject]@{
                        ParserType = "SQL"
                        FilePath   = $null
                        FileName   = $null
                        TableName  = $tableName
                    }
                    $sqlCounter++
                    if ($sqlCounter -ge $exitCounter) { break }
                }
            }
        }
        
        # Calculate queue statistics
        $cblCount = $cblQueue.Count
        $rexCount = ($nonCblQueue | Where-Object { $_.ParserType -eq "REX" }).Count
        $batCount = ($nonCblQueue | Where-Object { $_.ParserType -eq "BAT" }).Count
        $ps1Count = ($nonCblQueue | Where-Object { $_.ParserType -eq "PS1" }).Count
        $sqlCount = ($nonCblQueue | Where-Object { $_.ParserType -eq "SQL" }).Count
        $totalNonCbl = $nonCblQueue.Count
        $totalCount = $cblCount + $totalNonCbl
        
        Write-LogMessage "Work queues: CBL=$cblCount | Non-CBL=$totalNonCbl (REX=$rexCount BAT=$batCount PS1=$ps1Count SQL=$sqlCount) | Total=$totalCount" -Level INFO
        
        # ============================================================
        # INITIALIZE THREAD-SPECIFIC FOLDERS WITH COBDOK COPIES
        # Each thread gets its own copy of common files to avoid contention
        # ============================================================
        $threadFolders = Initialize-ParallelThreadFolders -CobdokFolder $cobdokFolder -TmpFolder $tmpFolder -ThreadCount $throttleLimit
        
        # Combine queues for thread assignment (non-CBL first, then CBL)
        $workQueue = $nonCblQueue + $cblQueue
        
        # Add thread assignment to each work item (round-robin distribution)
        $workIndex = 0
        foreach ($item in $workQueue) {
            $threadId = $workIndex % $throttleLimit
            $item | Add-Member -NotePropertyName "ThreadId" -NotePropertyValue $threadId -Force
            $item | Add-Member -NotePropertyName "ThreadFolder" -NotePropertyValue ($threadFolders[$threadId].ThreadFolder) -Force
            $item | Add-Member -NotePropertyName "ThreadCobdokFolder" -NotePropertyValue ($threadFolders[$threadId].CobdokFolder) -Force
            $workIndex++
        }
        
        Write-LogMessage "Processing $totalCount items using unified queue with $throttleLimit parallel threads..." -Level INFO
        
        $totalItems = $workQueue.Count
        $progressStartTime = Get-Date
        
        # ============================================================
        # BUILD FILENAME-TO-THREAD MAPPING FOR PROGRESS MONITORING
        # Maps expected output filename (lowercase) → ThreadId
        # ============================================================
        $fileToThreadMap = @{}
        foreach ($item in $workQueue) {
            $expectedFile = switch ($item.ParserType) {
                "CBL" { ($item.FileName + ".html").ToLower() }
                "REX" { ($item.FileName + ".html").ToLower() }
                "BAT" { ($item.FileName + ".html").ToLower() }
                "PS1" { ($item.FileName + ".html").ToLower() }
                "SQL" { ($item.TableName.Replace(".", "_") + ".sql.html").ToLower().Replace("æ", "ae").Replace("ø", "oe").Replace("å", "aa") }
            }
            if ($expectedFile) {
                $fileToThreadMap[$expectedFile] = $item.ThreadId
            }
        }
        
        # Count items assigned per thread for reference
        $itemsPerThread = @{}
        for ($t = 0; $t -lt $throttleLimit; $t++) { $itemsPerThread[$t] = 0 }
        foreach ($item in $workQueue) { $itemsPerThread[$item.ThreadId]++ }
        
        Write-LogMessage "Thread distribution: $(($itemsPerThread.GetEnumerator() | Sort-Object Name | ForEach-Object { "T$($_.Key)=$($_.Value)" }) -join ' ')" -Level INFO
        
        # ============================================================
        # START BACKGROUND MONITORING JOB (logs every 120 seconds)
        # Uses file-based progress logging for thread-safe output
        # ============================================================
        $monitoringInterval = 120  # seconds
        $monitorStopFile = Join-Path $tmpFolder "stop_monitor.flag"
        $monitorLogFile = Join-Path $tmpFolder "monitor_progress.log"
        Remove-Item -Path $monitorStopFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $monitorLogFile -Force -ErrorAction SilentlyContinue
        
        # Export data for monitoring job
        $monitorDataFile = Join-Path $tmpFolder "monitor_data.xml"
        @{
            FileToThreadMap = $fileToThreadMap
            ItemsPerThread  = $itemsPerThread
            OutputFolder    = $outputFolder
            StartTime       = $progressStartTime
            TotalItems      = $totalItems
            ThreadCount     = $throttleLimit
            StopFile        = $monitorStopFile
            LogFile         = $monitorLogFile
            Interval        = $monitoringInterval
        } | Export-Clixml -Path $monitorDataFile -Force
        
        $monitorJob = Start-Job -ScriptBlock {
            param($dataFile)
            
            $data = Import-Clixml -Path $dataFile
            $fileToThreadMap = $data.FileToThreadMap
            $itemsPerThread = $data.ItemsPerThread
            $outputFolder = $data.OutputFolder
            $startTime = $data.StartTime
            $totalItems = $data.TotalItems
            $threadCount = $data.ThreadCount
            $stopFile = $data.StopFile
            $logFile = $data.LogFile
            $interval = $data.Interval
            
            while (-not (Test-Path $stopFile)) {
                Start-Sleep -Seconds $interval
                
                # Check if we should stop
                if (Test-Path $stopFile) { break }
                
                # Count files generated since start time, grouped by thread
                $threadCompleted = @{}
                for ($t = 0; $t -lt $threadCount; $t++) { $threadCompleted[$t] = 0 }
                
                $typeCompleted = @{ CBL = 0; REX = 0; BAT = 0; PS1 = 0; SQL = 0 }
                $totalCompleted = 0
                $errorCount = 0
                
                # Scan output folder for files modified since start
                $generatedFiles = Get-ChildItem -Path $outputFolder -Filter "*.html" -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -ge $startTime }
                
                foreach ($file in $generatedFiles) {
                    $fileName = $file.Name.ToLower()
                    $totalCompleted++
                    
                    # Determine type
                    if ($fileName -like "*.cbl.html") { $typeCompleted.CBL++ }
                    elseif ($fileName -like "*.rex.html") { $typeCompleted.REX++ }
                    elseif ($fileName -like "*.bat.html") { $typeCompleted.BAT++ }
                    elseif ($fileName -like "*.ps1.html") { $typeCompleted.PS1++ }
                    elseif ($fileName -like "*.sql.html") { $typeCompleted.SQL++ }
                    
                    # Map to thread
                    if ($fileToThreadMap.ContainsKey($fileName)) {
                        $tid = $fileToThreadMap[$fileName]
                        $threadCompleted[$tid]++
                    }
                }
                
                # Count errors
                $errorCount = (Get-ChildItem -Path $outputFolder -Filter "*.err" -ErrorAction SilentlyContinue | 
                    Where-Object { $_.LastWriteTime -ge $startTime }).Count
                
                # Calculate stats
                $elapsed = (Get-Date) - $startTime
                $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
                $pct = if ($totalItems -gt 0) { [math]::Round($totalCompleted / $totalItems * 100, 1) } else { 0 }
                $rate = if ($elapsed.TotalMinutes -gt 0) { [math]::Round($totalCompleted / $elapsed.TotalMinutes, 1) } else { 0 }
                $remaining = $totalItems - $totalCompleted
                $eta = if ($rate -gt 0) { [math]::Round($remaining / $rate, 0) } else { "?" }
                
                # Build per-thread progress string (show threads with activity)
                $activeThreads = ($threadCompleted.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object Name | 
                    ForEach-Object { "T$($_.Key):$($_.Value)/$($itemsPerThread[$_.Key])" }) -join ' '
                
                if (-not $activeThreads) { $activeThreads = "(waiting for first completions)" }
                
                # Write progress to log file (will be read by main thread)
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $monitorLine = "[$timestamp] MONITOR: $totalCompleted/$totalItems ($pct%) | CBL=$($typeCompleted.CBL) REX=$($typeCompleted.REX) BAT=$($typeCompleted.BAT) PS1=$($typeCompleted.PS1) SQL=$($typeCompleted.SQL) | Err=$errorCount | Rate=$rate/min | Elapsed=$elapsedStr | ETA=${eta}min"
                $threadsLine = "[$timestamp] THREADS: $activeThreads"
                
                # Append to log file
                Add-Content -Path $logFile -Value $monitorLine -Force
                Add-Content -Path $logFile -Value $threadsLine -Force
                
                # Also output to job stream (for Receive-Job)
                Write-Output $monitorLine
                Write-Output $threadsLine
            }
        } -ArgumentList $monitorDataFile
        
        Write-LogMessage "Background monitoring started (interval: ${monitoringInterval}s, job ID: $($monitorJob.Id))" -Level INFO
        
        # ============================================================
        # UNIFIED QUEUE PARALLEL PROCESSING
        # All threads start immediately on a single combined queue.
        # Non-CBL items are placed first in queue (faster processing).
        # All $throttleLimit threads work simultaneously on whatever is next.
        # ============================================================
        $useClientSideRender = $ClientSideRender
        $useSaveMmdFiles = $SaveMmdFiles
        
        # Build unified work queue: non-CBL first (faster), then CBL
        $unifiedQueue = @()
        $unifiedQueue += $nonCblQueue
        $unifiedQueue += $cblQueue
        
        Write-LogMessage "Starting unified parallel processing with $throttleLimit threads..." -Level INFO
        Write-LogMessage "  Queue order: $totalNonCbl non-CBL items (REX/BAT/PS1/SQL) first, then $cblCount CBL items" -Level INFO
        Write-LogMessage "  Total: $($unifiedQueue.Count) items" -Level INFO
        
        if ($unifiedQueue.Count -gt 0) {
            $unifiedQueue | ForEach-Object -Parallel {
                # Import modules and ensure globals are initialized for parallel runspace
                Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
                Initialize-GlobalFunctionsForParallel
                Import-Module -Name AutodocFunctions -Force -ErrorAction Stop
                
                $item = $_
                $outFolder = $using:outputFolder
                $srcFolder = $using:srcRootFolder
                $useClientRender = $using:useClientSideRender
                $saveMmd = $using:useSaveMmdFiles
                $threadTmpFolder = $item.ThreadFolder
                
                try {
                    $params = @{
                        OutputFolder  = $outFolder
                        CleanUp       = $true
                        TmpRootFolder = $threadTmpFolder
                        SrcRootFolder = $srcFolder
                    }
                    
                    switch ($item.ParserType) {
                        "CBL" {
                            if ($useClientRender) { $params.Add("ClientSideRender", $true) }
                            if ($saveMmd) { $params.Add("SaveMmdFiles", $true) }
                            $params.Add("SourceFile", $item.FilePath)
                            Start-CblParse @params
                        }
                        "REX" {
                            if ($useClientRender) { $params.Add("ClientSideRender", $true) }
                            if ($saveMmd) { $params.Add("SaveMmdFiles", $true) }
                            $params.Add("SourceFile", $item.FilePath)
                            Start-RexParse @params
                        }
                        "BAT" {
                            if ($useClientRender) { $params.Add("ClientSideRender", $true) }
                            if ($saveMmd) { $params.Add("SaveMmdFiles", $true) }
                            $params.Add("SourceFile", $item.FilePath)
                            Start-BatParse @params
                        }
                        "PS1" {
                            if ($useClientRender) { $params.Add("ClientSideRender", $true) }
                            if ($saveMmd) { $params.Add("SaveMmdFiles", $true) }
                            $params.Add("SourceFile", $item.FilePath)
                            Start-Ps1Parse @params
                        }
                        "SQL" {
                            $params.Add("SqlTable", $item.TableName)
                            Start-SqlParse @params
                        }
                    }
                }
                catch {
                    $errFileName = switch ($item.ParserType) {
                        "SQL" { $item.TableName.Replace(".", "_") + ".sql.err" }
                        default { $item.FileName + ".err" }
                    }
                    $errFilePath = Join-Path $outFolder $errFileName
                    "ParserType: $($item.ParserType)`nFile: $($item.FilePath)`nTable: $($item.TableName)`nError: $($_.Exception.Message)`n`nStack:`n$($_.ScriptStackTrace)" | Set-Content -Path $errFilePath -Force
                }
            } -ThrottleLimit $throttleLimit
            
            Write-LogMessage "Unified parallel processing complete" -Level INFO
        }
        
        # ============================================================
        # STOP MONITORING AND COLLECT FINAL STATS
        # ============================================================
        "stop" | Set-Content -Path $monitorStopFile -Force
        Start-Sleep -Seconds 2  # Give monitor time to exit gracefully
        
        # Read and log monitoring output
        if (Test-Path $monitorLogFile) {
            Write-LogMessage "=== MONITORING LOG ===" -Level INFO
            Get-Content $monitorLogFile | ForEach-Object {
                # Extract the message part and log it
                if ($_ -match '^\[.*?\] (.+)$') {
                    Write-LogMessage $Matches[1] -Level INFO
                }
                else {
                    Write-LogMessage $_ -Level INFO
                }
            }
            Remove-Item -Path $monitorLogFile -Force -ErrorAction SilentlyContinue
        }
        
        Stop-Job -Job $monitorJob -ErrorAction SilentlyContinue
        Remove-Job -Job $monitorJob -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $monitorStopFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $monitorDataFile -Force -ErrorAction SilentlyContinue
        
        # Count final results and store at script scope for SMS
        $script:totalElapsed = (Get-Date) - $progressStartTime
        $script:totalElapsedStr = "{0:hh\:mm\:ss}" -f $script:totalElapsed
        
        $script:cblDone = (Get-ChildItem "$outputFolder\*.cbl.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:rexDone = (Get-ChildItem "$outputFolder\*.rex.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:batDone = (Get-ChildItem "$outputFolder\*.bat.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:ps1Done = (Get-ChildItem "$outputFolder\*.ps1.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:psm1Done = (Get-ChildItem "$outputFolder\*.psm1.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:sqlDone = (Get-ChildItem "$outputFolder\*.sql.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:csharpDone = (Get-ChildItem "$outputFolder\*.csharp.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:gsDone = (Get-ChildItem "$outputFolder\*.screen.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:errDone = (Get-ChildItem "$outputFolder\*.err" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:totalDone = $script:cblDone + $script:rexDone + $script:batDone + $script:ps1Done + $script:psm1Done + $script:sqlDone + $script:csharpDone + $script:gsDone
        $script:finalRate = if ($script:totalElapsed.TotalMinutes -gt 0) { [math]::Round($script:totalDone / $script:totalElapsed.TotalMinutes, 1) } else { 0 }
        
        Write-LogMessage "=== FINAL STATISTICS ===" -Level INFO
        Write-LogMessage "Total generated: $($script:totalDone) | Errors: $($script:errDone)" -Level INFO
        Write-LogMessage "By type: CBL=$($script:cblDone) REX=$($script:rexDone) BAT=$($script:batDone) PS1=$($script:ps1Done) PSM1=$($script:psm1Done) SQL=$($script:sqlDone) C#=$($script:csharpDone) GS=$($script:gsDone)" -Level INFO
        Write-LogMessage "Duration: $($script:totalElapsedStr) | Average rate: $($script:finalRate) files/min" -Level INFO
        
        # Clean up thread-specific folders
        Remove-ParallelThreadFolders -TmpFolder $tmpFolder -ThreadCount $throttleLimit
        
        Write-LogMessage "Parallel processing complete" -Level INFO
        
        # Handle C# projects (ServerMonitor) - runs after parallel processing since it's a separate task
        HandleCSharpProjects -serverMonitorFolder $ServerMonitorFolder -outputFolder $outputFolder -tmpFolder $tmpFolder -srcRootFolder $srcRootFolder -lastGenerationDate $lastGenerationDate -regenerate $regenerate
        
        # Recount C# and GS after HandleCSharpProjects completes
        $script:csharpDone = (Get-ChildItem "$outputFolder\*.csharp.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:gsDone = (Get-ChildItem "$outputFolder\*.screen.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $progressStartTime }).Count
        $script:totalDone = $script:cblDone + $script:rexDone + $script:batDone + $script:ps1Done + $script:sqlDone + $script:csharpDone + $script:gsDone
        
        # Update last execution info
        Set-Content -Path $lastExecutionInfoFileName -Value $lastGenerationDate.ToString()
    }
    else {
        # Sequential processing mode - use original handler functions
        Write-LogMessage ("Sequential processing mode (use -Parallel to enable parallel processing)") -Level INFO
        
        $seqStartTime = Get-Date
        
        # Handle COBOL files (if Cbl is in FileTypes)
        if ('Cbl' -in $FileTypes) {
            HandleCblFiles -DedgeCblFolder $DedgeCblFolder -outputFolder $outputFolder -tmpFolder $tmpFolder -autoDocRootFolder $autoDocRootFolder -lastGenerationDate $lastGenerationDate -lastExecutionInfoFileName $lastExecutionInfoFileName -regenerate $Regenerate -exitCounter $exitCounter -clientSideRender:$ClientSideRender -SaveMmdFiles $SaveMmdFiles -Parallel:$Parallel -ThrottleLimit $throttleLimit
        }
        
        # Handle script files (Rex, Bat, Ps1) - only if any of these types are in FileTypes
        $scriptTypesToProcess = $FileTypes | Where-Object { $_ -in @('Rex', 'Bat', 'Ps1') }
        if ($scriptTypesToProcess.Count -gt 0) {
            HandleScriptFiles -cobdokFolder $cobdokFolder -DedgeRexFolder $DedgeRexFolder -DedgeBatFolder $DedgeBatFolder -DedgePshFolder $DedgePshFolder -outputFolder $outputFolder -tmpFolder $tmpFolder -autoDocRootFolder $autoDocRootFolder -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -exitCounter $exitCounter -clientSideRender:$ClientSideRender -SaveMmdFiles $SaveMmdFiles -Parallel:$Parallel -ThrottleLimit $throttleLimit -FileTypes $scriptTypesToProcess
        }
        
        # Handle SQL tables (if Sql is in FileTypes and not in Errors mode)
        if ('Sql' -in $FileTypes -and $Regenerate -ne "Errors") {
            HandleSqlTables -cobdokFolder $cobdokFolder -DedgeRexFolder $DedgeRexFolder -DedgeBatFolder $DedgeBatFolder -DedgePshFolder $DedgePshFolder -outputFolder $outputFolder -tmpFolder $tmpFolder -autoDocRootFolder $autoDocRootFolder -lastGenerationDate $lastGenerationDate -regenerate $Regenerate -exitCounter $exitCounter -Parallel:$Parallel -ThrottleLimit $throttleLimit
        }
        
        # Handle C# projects (if CSharp is in FileTypes)
        if ('CSharp' -in $FileTypes) {
            HandleCSharpProjects -serverMonitorFolder $ServerMonitorFolder -outputFolder $outputFolder -tmpFolder $tmpFolder -srcRootFolder $srcRootFolder -lastGenerationDate $lastGenerationDate -regenerate $Regenerate
        }
        
        # After all file types are generated, scan HTML files for SQL table interactions
        # This builds the interaction JSON cache and updates SQL files with interaction diagrams
        if ('Sql' -in $FileTypes -and $Regenerate -ne "Errors") {
            Write-LogMessage "Scanning HTML files for SQL table interactions..." -Level INFO
            try {
                $jsonCachePath = Join-Path $outputFolder "_sql_interactions.json"
                $interactions = Search-HtmlFilesForSqlInteractions -OutputFolder $outputFolder -JsonOutputPath $jsonCachePath
                Write-LogMessage "Found interactions for $($interactions.Keys.Count) tables" -Level INFO
                
                # Update SQL files with interaction diagrams
                if ($interactions.Keys.Count -gt 0) {
                    Write-LogMessage "Updating SQL files with interaction diagrams..." -Level INFO
                    $tableArray = Import-Csv ($cobdokFolder + "\tables.csv") -Header schemaName, tableName, comment, type, alter_time -Delimiter ';' -ErrorAction SilentlyContinue
                    if ($tableArray) {
                        foreach ($tableInfo in $tableArray) {
                            $tableFullName = $tableInfo.schemaName.Trim().ToUpper() + "." + $tableInfo.tableName.Trim().ToUpper()
                            $tableNameLower = $tableFullName.ToLower()
                            
                            if ($interactions.ContainsKey($tableNameLower)) {
                                try {
                                    # Regenerate with interaction diagram
                                    Start-SqlParse -SqlTable $tableFullName -Show $false -OutputFolder $outputFolder `
                                        -CleanUp $true -TmpRootFolder $tmpFolder -SrcRootFolder $srcRootFolder
                                }
                                catch {
                                    Write-LogMessage "Error updating SQL file with interactions for $tableFullName : $($_.Exception.Message)" -Level WARN
                                }
                            }
                        }
                    }
                }
            }
            catch {
                Write-LogMessage "Error scanning for SQL interactions: $($_.Exception.Message)" -Level WARN
            }
        }
        
        # Handle Dialog System screensets (if Gs is in FileTypes)
        if ('Gs' -in $FileTypes) {
            HandleGsFiles -DedgeGsFolder $DedgeGsFolder -DedgeImpFolder $DedgeImpFolder -outputFolder $outputFolder -tmpFolder $tmpFolder -lastGenerationDate $lastGenerationDate -Regenerate $Regenerate -exitCounter $exitCounter
        }
        
        # Calculate statistics for sequential mode
        $script:totalElapsed = (Get-Date) - $seqStartTime
        $script:totalElapsedStr = "{0:hh\:mm\:ss}" -f $script:totalElapsed
        $script:cblDone = (Get-ChildItem "$outputFolder\*.cbl.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:rexDone = (Get-ChildItem "$outputFolder\*.rex.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:batDone = (Get-ChildItem "$outputFolder\*.bat.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:ps1Done = (Get-ChildItem "$outputFolder\*.ps1.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:psm1Done = (Get-ChildItem "$outputFolder\*.psm1.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:sqlDone = (Get-ChildItem "$outputFolder\*.sql.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:csharpDone = (Get-ChildItem "$outputFolder\*.csharp.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:gsDone = (Get-ChildItem "$outputFolder\*.screen.html" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:errDone = (Get-ChildItem "$outputFolder\*.err" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $seqStartTime }).Count
        $script:totalDone = $script:cblDone + $script:rexDone + $script:batDone + $script:ps1Done + $script:psm1Done + $script:sqlDone + $script:csharpDone + $script:gsDone
        $script:finalRate = if ($script:totalElapsed.TotalMinutes -gt 0) { [math]::Round($script:totalDone / $script:totalElapsed.TotalMinutes, 1) } else { 0 }
        
        Write-LogMessage "=== FINAL STATISTICS (Sequential) ===" -Level INFO
        Write-LogMessage "Total generated: $($script:totalDone) | Errors: $($script:errDone)" -Level INFO
        Write-LogMessage "By type: CBL=$($script:cblDone) REX=$($script:rexDone) BAT=$($script:batDone) PS1=$($script:ps1Done) PSM1=$($script:psm1Done) SQL=$($script:sqlDone) C#=$($script:csharpDone) GS=$($script:gsDone)" -Level INFO
        Write-LogMessage "Duration: $($script:totalElapsedStr) | Average rate: $($script:finalRate) files/min" -Level INFO
    }
}

Write-LogMessage ("Create json index files from output folder") -Level INFO
CreateAllJsonIndexFiles -OutputFolder $outputFolder -CobdokFolder $cobdokFolder -ServerMonitorFolder $ServerMonitorFolder

# Output is now written directly to web folder, no copy needed
Write-LogMessage ("Output folder is web content folder: " + $outputFolder) -Level INFO

if ($env:COMPUTERNAME.ToLower().Trim() -ne "dedge-server") {
    Write-LogMessage ("Not running on dedge-server.") -Level INFO
    # zip all files in the content folder
    $zipFileName = $tmpFolder + "\content.zip"
    if (Test-Path $zipFileName -PathType Leaf) {
        Remove-Item -Path $zipFileName -Force -ErrorAction SilentlyContinue
    }
    Write-LogMessage ("Zip all files in the content folder to " + $zipFileName) -Level INFO
    Compress-Archive -Path $outputFolder -DestinationPath $zipFileName -Force -ErrorAction SilentlyContinue
    Write-LogMessage ("Copy zip file to " + $appsFolderTmp) -Level INFO
    Copy-Item -Path $zipFileName -Destination $appsFolderTmp -Force -ErrorAction SilentlyContinue
}

# Final copy of static assets to ensure web folder has latest versions
# (especially important if outputFolder != webFolderRoot on some configurations)
if ($webFolderRoot -ne $outputFolder) {
    Copy-StaticAssetsToOutput -SourceRoot $PSScriptRoot -OutputRoot $webFolderRoot
}
else {
    Write-LogMessage "Static assets already copied to output folder at startup" -Level INFO
}


# Log list over all *.err files
$errArray = Get-ChildItem -Path $outputFolder -Filter "*.err" -Name
if ($errArray.Count -gt 0) {
    Write-LogMessage ("List over all *.err files - start") -Level WARN
    foreach ($errFile in $errArray) {
        Write-LogMessage ("Error file: " + $errFile) -Level WARN
    }
    Write-LogMessage ("List over all *.err files - end") -Level WARN
}

Write-LogMessage ("AutoDocBatchRunner completed") -Level INFO

# Build SMS message with statistics
if ($script:totalDone -gt 0) {
    # Format: "AutoDoc: 100 files (CBL:20 REX:20 BAT:20 PS1:20 SQL:20 C#:4) Err:0 Time:00:22:33"
    $smsStats = "AutoDoc: $($script:totalDone) files"
    $smsTypes = @()
    if ($script:cblDone -gt 0) { $smsTypes += "CBL:$($script:cblDone)" }
    if ($script:rexDone -gt 0) { $smsTypes += "REX:$($script:rexDone)" }
    if ($script:batDone -gt 0) { $smsTypes += "BAT:$($script:batDone)" }
    if ($script:ps1Done -gt 0) { $smsTypes += "PS1:$($script:ps1Done)" }
    if ($script:sqlDone -gt 0) { $smsTypes += "SQL:$($script:sqlDone)" }
    if ($script:csharpDone -gt 0) { $smsTypes += "C#:$($script:csharpDone)" }
    if ($script:gsDone -gt 0) { $smsTypes += "GS:$($script:gsDone)" }
    if ($smsTypes.Count -gt 0) { $smsStats += " ($($smsTypes -join '`n '))" }
    if ($script:errDone -gt 0) { $smsStats += "`nErr:$($script:errDone)" }
    $smsStats += "`nTime:$($script:totalElapsedStr)"
    $smsMessage = $smsStats
}
else {
    $smsMessage = "AutoDoc completed (no files processed)"
}

Send-Sms -Receiver "+4797188358" -Message $smsMessage

# ============================================================
# CLEANUP: Remove RAM disk if we created one
# ============================================================
if ($script:RamDiskActive) {
    Remove-AutoDocRamDisk
}