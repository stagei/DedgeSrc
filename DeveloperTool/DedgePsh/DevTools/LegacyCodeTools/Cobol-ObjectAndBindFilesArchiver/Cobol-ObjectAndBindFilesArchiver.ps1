<#
.SYNOPSIS
    Archives COBOL object files (.gs, .int) and bind files (.bnd) from network shares to timestamped zip files.

.DESCRIPTION
    This script iterates through multiple COBOL environment folders on the network share
    (\\DEDGE.fk.no\erpprog\COB*), syncs object files (.gs, .int) and bind files (.bnd)
    to a local folder using robocopy, then creates a timestamped zip archive.
    
    The local folders are kept between runs for efficient incremental syncing - robocopy
    only copies changed/new files and removes files deleted from source.
    
    The script is READ-ONLY on source directories - it never modifies or deletes files
    on the network shares.
    
    Environments processed:
    - COBNT, COBTST, COBFUT, COBKAT, COBVFT, COBVFK, COBMIG (production environments)
    - COBDEV (development environment - includes additional source file types)

    COBDEV special handling:
    - Source path: \\DEDGE.fk.no\erputv\Utvikling\fkavd\nt
    - Copies additional file types: *.cbl, *.md, *.cpy, *.cpb, *.dcl, *.cpx, *.gs, *.int,
      *.imp, *.rex, *.bat, *.cmd, *.cre, *.sql, *.ins, *.log
    - *.bnd files are copied to COBDEV\BND subfolder

.PARAMETER Environments
    Optional array of environment names to process. Defaults to all environments.

.PARAMETER RetentionDays
    Number of days to keep old archive zip files. Archives older than this will be deleted
    at the end of each run. Default is 7 days.

.EXAMPLE
    .\Cobol-ObjectAndBindFilesArchiver.ps1
    # Archives all COBOL environments, removes archives older than 7 days

.EXAMPLE
    .\Cobol-ObjectAndBindFilesArchiver.ps1 -Environments @("COBNT", "COBTST")
    # Archives only COBNT and COBTST environments

.EXAMPLE
    .\Cobol-ObjectAndBindFilesArchiver.ps1 -Environments @("COBDEV")
    # Archives only COBDEV (development environment with extended file types)

.EXAMPLE
    .\Cobol-ObjectAndBindFilesArchiver.ps1 -RetentionDays 30
    # Archives all environments, keeps archives for 30 days

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Source directories are READ-ONLY - this script never modifies network shares
    Uses robocopy for efficient incremental syncing
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("COBNT", "COBTST", "COBFUT", "COBKAT", "COBVFT", "COBVFK", "COBMIG", "COBDEV")]
    [string[]]$Environments = @("COBNT", "COBTST", "COBFUT", "COBKAT", "COBVFT", "COBVFK", "COBMIG", "COBDEV"),
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$RetentionDays = 7
)

Import-Module GlobalFunctions -Force

########################################################################################################
# Initialize WorkObject for tracking execution
########################################################################################################
$script:WorkObject = [PSCustomObject]@{
    # Job Information
    Name                    = "Cobol-ObjectAndBindFilesArchiver"
    Description             = "Archives COBOL object and bind files from network shares"
    ScriptPath              = $PSCommandPath
    ExecutionTimestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ExecutionUser           = "$env:USERDOMAIN\$env:USERNAME"
    ComputerName            = $env:COMPUTERNAME
    
    # Execution Status
    Success                 = $false
    Status                  = "Running"
    ErrorMessage            = $null
    
    # Configuration
    SourceBasePath          = "\\DEDGE.fk.no\erpprog"
    SourceDevPath           = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
    LocalFolder             = $null
    OutputFolder            = $null
    RetentionDays           = $RetentionDays
    EnvironmentsRequested   = $Environments
    
    # Statistics
    EnvironmentsProcessed   = 0
    SuccessfulArchives      = 0
    FailedArchives          = 0
    NoFilesEnvironments     = 0
    TotalFilesSynced        = 0
    TotalFilesDeleted       = 0
    TotalArchiveSize        = 0
    OldArchivesRemoved      = 0
    CleanupBytesFreed       = 0
    
    # Environment Details (populated during execution)
    EnvironmentResults      = @()
    
    # Available Archives Per Environment
    AvailableArchives       = @()
    
    # Timing
    StartTime               = Get-Date
    EndTime                 = $null
    Duration                = $null
    
    # Script and Output Tracking
    ScriptArray             = @()
}

########################################################################################################
# Functions
########################################################################################################

<#
    Function: Invoke-RobocopySync
    Uses robocopy to sync files from source to destination with specific file filters.
    Removes local files that were deleted from source, and overwrites changed files.
    
    Parameters:
        - SourcePath: Network source path to sync from (READ-ONLY)
        - DestinationPath: Local destination path to sync to
        - FileFilters: Array of file filters (e.g., "*.gs", "*.int")
    
    Returns: PSCustomObject with sync statistics
    
    Robocopy parameters used:
        /PURGE  - Delete destination files/dirs that no longer exist in source
        /R:3    - Number of retries on failed copies (3)
        /W:1    - Wait time between retries in seconds (1)
        /NJH    - No Job Header
        /NJS    - No Job Summary
        /NDL    - No Directory List
        /NC     - No Class (don't log file class)
        /NS     - No Size (don't log file sizes in output)
#>
function Invoke-RobocopySync {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        
        [Parameter(Mandatory)]
        [string[]]$FileFilters
    )
    
    $stats = [PSCustomObject]@{
        FilesCopied   = 0
        FilesSkipped  = 0
        FilesDeleted  = 0
        FilesFailed   = 0
        BytesCopied   = 0
        ExitCode      = 0
        Success       = $false
        ErrorMessage  = $null
    }
    
    # Validate source exists
    if (-not (Test-Path $SourcePath)) {
        $stats.ErrorMessage = "Source path does not exist: $($SourcePath)"
        return $stats
    }
    
    # Create destination if it doesn't exist
    if (-not (Test-Path $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created destination folder: $($DestinationPath)" -Level INFO
    }
    
    # Build file filter string for robocopy
    $filterString = $FileFilters -join " "
    
    try {
        # Robocopy parameters used:
        # /PURGE removes files in destination that don't exist in source
        # We don't use /MIR because we don't want recursive copying
        # We don't use /S or /E so it's non-recursive
        # /R:3 = 3 retries on failed copies
        # /W:1 = 1 second wait between retries
        
        $robocopyPath = "C:\Windows\System32\robocopy.exe"
        if (-not (Test-Path $robocopyPath)) {
            $robocopyPath = (Get-Command "robocopy" -ErrorAction SilentlyContinue).Path
        }
        
        Write-LogMessage "Robocopy: $($SourcePath) -> $($DestinationPath) [$($filterString)]" -Level DEBUG
        
        # Execute robocopy and capture output
        $robocopyOutput = & $robocopyPath $SourcePath $DestinationPath $FileFilters /PURGE /R:3 /W:1 2>&1
        $stats.ExitCode = $LASTEXITCODE
        
        # Parse robocopy output for statistics
        foreach ($line in $robocopyOutput) {
            $lineStr = $line.ToString()
            
            # Match statistics lines like "Files :         5         3         2         0         0         0"
            #                              Total   Copied  Skipped  Mismatch  Failed   Extras
            if ($lineStr -match '^\s*Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
                $stats.FilesCopied = [int]$Matches[2]
                $stats.FilesSkipped = [int]$Matches[3]
                $stats.FilesFailed = [int]$Matches[5]
                $stats.FilesDeleted = [int]$Matches[6]  # "Extras" are files deleted from destination
            }
            
            # Match bytes line like "Bytes :   1.234 m    500 k         0         0         0         0"
            if ($lineStr -match '^\s*Bytes\s*:\s*[\d\.\s\w]+\s+([\d\.]+\s*[kmgt]?)') {
                # Just note that bytes were copied - detailed parsing is complex
            }
        }
        
        # Robocopy exit codes:
        # 0 = No files copied, no errors
        # 1 = Files copied successfully
        # 2 = Extra files or directories detected (deleted from destination)
        # 3 = 1+2
        # 4 = Mismatched files or directories detected
        # 8+ = Errors occurred
        if ($stats.ExitCode -lt 8) {
            $stats.Success = $true
        }
        else {
            $stats.Success = $false
            $stats.ErrorMessage = "Robocopy failed with exit code $($stats.ExitCode)"
            Write-LogMessage $stats.ErrorMessage -Level ERROR
        }
    }
    catch {
        $stats.ErrorMessage = "Robocopy execution failed: $($_.Exception.Message)"
        Write-LogMessage $stats.ErrorMessage -Level ERROR -Exception $_
    }
    
    return $stats
}

<#
    Function: Sync-EnvironmentFilesToLocal
    Generic sync function that uses the environment configuration object to sync files
    from network share to local folder using robocopy.
    
    Uses the EnvironmentConfig PSCustomObject which contains:
        - Name: Environment name (e.g., COBNT, COBDEV)
        - SourcePath: Path to source files (e.g., \\DEDGE.fk.no\erpprog\COBNT)
        - BndSourcePath: Path to BND files (may be same as SourcePath or subfolder)
        - FileSuffixes: Array of file patterns to sync (e.g., @("*.gs", "*.int"))
        - BndSuffixes: Array of BND file patterns (e.g., @("*.bnd"))
    
    Parameters:
        - EnvConfig: PSCustomObject with environment configuration
        - LocalFolder: Local folder to sync files to
    
    Returns: PSCustomObject with sync statistics
#>
function Sync-EnvironmentFilesToLocal {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$EnvConfig,
        
        [Parameter(Mandatory)]
        [string]$LocalFolder
    )
    
    $stats = [PSCustomObject]@{
        EnvironmentName   = $EnvConfig.Name
        SourcePath        = $EnvConfig.SourcePath
        BndSourcePath     = $EnvConfig.BndSourcePath
        SourceFilesSynced = 0
        ObjectFilesSynced = 0
        BindFilesSynced   = 0
        FilesDeleted      = 0
        TotalFiles        = 0
        Errors            = @()
        FileTypeCounts    = @{}
    }
    
    # Local paths (we create and manage these)
    $localEnvPath = Join-Path $LocalFolder $EnvConfig.Name
    $localBndPath = Join-Path $localEnvPath "BND"
    
    # Validate source path exists
    if (-not (Test-Path $EnvConfig.SourcePath)) {
        $errorMsg = "Source environment path does not exist: $($EnvConfig.SourcePath)"
        Write-LogMessage $errorMsg -Level WARN
        $stats.Errors += $errorMsg
        return $stats
    }
    
    # Sync source files using file suffixes from configuration - NON-RECURSIVE
    Write-LogMessage "Syncing files ($($EnvConfig.FileSuffixes -join ', ')) from: $($EnvConfig.SourcePath)" -Level INFO
    
    $sourceSyncResult = Invoke-RobocopySync -SourcePath $EnvConfig.SourcePath -DestinationPath $localEnvPath -FileFilters $EnvConfig.FileSuffixes
    
    if ($sourceSyncResult.Success) {
        $stats.SourceFilesSynced = $sourceSyncResult.FilesCopied
        $stats.ObjectFilesSynced = $sourceSyncResult.FilesCopied  # For backward compatibility
        $stats.FilesDeleted += $sourceSyncResult.FilesDeleted
        Write-LogMessage "Source files: $($sourceSyncResult.FilesCopied) copied, $($sourceSyncResult.FilesSkipped) unchanged, $($sourceSyncResult.FilesDeleted) deleted" -Level INFO
    }
    else {
        $stats.Errors += $sourceSyncResult.ErrorMessage
    }
    
    # Sync bind files using BND suffixes from configuration - NON-RECURSIVE
    if (Test-Path $EnvConfig.BndSourcePath) {
        Write-LogMessage "Syncing BND files ($($EnvConfig.BndSuffixes -join ', ')) from: $($EnvConfig.BndSourcePath)" -Level INFO
        
        $bndSyncResult = Invoke-RobocopySync -SourcePath $EnvConfig.BndSourcePath -DestinationPath $localBndPath -FileFilters $EnvConfig.BndSuffixes
        
        if ($bndSyncResult.Success) {
            $stats.BindFilesSynced = $bndSyncResult.FilesCopied
            $stats.FilesDeleted += $bndSyncResult.FilesDeleted
            Write-LogMessage "BND files: $($bndSyncResult.FilesCopied) copied, $($bndSyncResult.FilesSkipped) unchanged, $($bndSyncResult.FilesDeleted) deleted" -Level INFO
        }
        else {
            $stats.Errors += $bndSyncResult.ErrorMessage
        }
    }
    else {
        Write-LogMessage "BND folder does not exist in source: $($EnvConfig.BndSourcePath)" -Level WARN
    }
    
    # Count total files in local folder by suffix
    if (Test-Path $localEnvPath) {
        foreach ($suffix in $EnvConfig.FileSuffixes) {
            $files = @(Get-ChildItem -Path $localEnvPath -File -Filter $suffix -ErrorAction SilentlyContinue)
            $suffixKey = $suffix.Replace("*", "").Replace(".", "").ToUpper()
            $stats.FileTypeCounts[$suffixKey] = $files.Count
            $stats.TotalFiles += $files.Count
        }
        
        # Log file type counts if there are multiple types
        if ($EnvConfig.FileSuffixes.Count -gt 2) {
            Write-LogMessage "$($EnvConfig.Name) file type counts:" -Level INFO
            foreach ($suffixKey in $stats.FileTypeCounts.Keys) {
                if ($stats.FileTypeCounts[$suffixKey] -gt 0) {
                    Write-LogMessage "  $($suffixKey): $($stats.FileTypeCounts[$suffixKey])" -Level INFO
                }
            }
        }
    }
    
    if (Test-Path $localBndPath) {
        foreach ($suffix in $EnvConfig.BndSuffixes) {
            $bndFiles = @(Get-ChildItem -Path $localBndPath -File -Filter $suffix -ErrorAction SilentlyContinue)
            $stats.FileTypeCounts["BND"] = $bndFiles.Count
            $stats.TotalFiles += $bndFiles.Count
        }
        Write-LogMessage "  BND: $($stats.FileTypeCounts["BND"])" -Level INFO
    }
    
    return $stats
}

<#
    Function: New-CobolArchive
    Creates a timestamped zip archive of the local folder.
    
    Parameters:
        - EnvironmentName: Name of the COBOL environment (e.g., COBNT)
        - LocalFolder: Base local folder path
        - OutputFolder: Folder to create the zip file in
    
    Returns: Path to the created zip file, or $null on failure
#>
function New-CobolArchive {
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentName,
        
        [Parameter(Mandatory)]
        [string]$LocalFolder,
        
        [Parameter(Mandatory)]
        [string]$OutputFolder
    )
    
    $localEnvPath = Join-Path $LocalFolder $EnvironmentName
    
    if (-not (Test-Path $localEnvPath)) {
        Write-LogMessage "Local folder does not exist: $($localEnvPath)" -Level ERROR
        return $null
    }
    
    # Generate timestamped filename: COB*<YYYYMMDD-HHMMSS>.zip
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $zipFileName = "$($EnvironmentName)-$($timestamp).zip"
    $zipFilePath = Join-Path $OutputFolder $zipFileName
    
    Write-LogMessage "Creating archive: $($zipFilePath)" -Level INFO
    
    try {
        # Ensure output folder exists
        if (-not (Test-Path $OutputFolder)) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
        }
        
        # Remove existing zip if it exists (shouldn't happen with timestamp, but just in case)
        if (Test-Path $zipFilePath) {
            Remove-Item -Path $zipFilePath -Force
        }
        
        # Create zip archive
        Compress-Archive -Path $localEnvPath -DestinationPath $zipFilePath -CompressionLevel Optimal -Force
        
        $zipFile = Get-Item $zipFilePath
        $zipSizeMB = [math]::Round($zipFile.Length / 1MB, 2)
        Write-LogMessage "✅ Archive created: $($zipFileName) ($($zipSizeMB) MB)" -Level INFO
        
        return $zipFilePath
    }
    catch {
        Write-LogMessage "Failed to create archive: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $null
    }
}

<#
    Function: Get-AvailableArchivesPerEnvironment
    Gets a list of available archive zip files grouped by environment.
    
    Parameters:
        - OutputFolder: Folder containing the archive zip files
    
    Returns: Array of PSCustomObjects with environment and archive details
#>
function Get-AvailableArchivesPerEnvironment {
    param(
        [Parameter(Mandatory)]
        [string]$OutputFolder
    )
    
    $archivesByEnvironment = @()
    
    if (-not (Test-Path $OutputFolder)) {
        return $archivesByEnvironment
    }
    
    # Get all COB*.zip files
    $allArchives = Get-ChildItem -Path $OutputFolder -Filter "COB*.zip" -File -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending
    
    if ($null -eq $allArchives -or @($allArchives).Count -eq 0) {
        return $archivesByEnvironment
    }
    
    # Group by environment (extract environment name from filename)
    # Filename format: COBNT20260116-143052.zip -> Environment: COBNT
    $environments = @("COBNT", "COBTST", "COBFUT", "COBKAT", "COBVFT", "COBVFK", "COBMIG", "COBDEV")
    
    foreach ($env in $environments) {
        $envArchives = $allArchives | Where-Object { $_.Name -like "$env*.zip" }
        
        if ($envArchives -and @($envArchives).Count -gt 0) {
            $archiveDetails = @()
            foreach ($archive in $envArchives) {
                $archiveDetails += [PSCustomObject]@{
                    FileName     = $archive.Name
                    FullPath     = $archive.FullName
                    SizeMB       = [math]::Round($archive.Length / 1MB, 2)
                    Created      = $archive.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                    AgeDays      = [math]::Round(((Get-Date) - $archive.LastWriteTime).TotalDays, 1)
                }
            }
            
            $archivesByEnvironment += [PSCustomObject]@{
                EnvironmentName = $env
                ArchiveCount    = @($envArchives).Count
                TotalSizeMB     = [math]::Round(($envArchives | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                LatestArchive   = $archiveDetails[0].FileName
                LatestCreated   = $archiveDetails[0].Created
                Archives        = $archiveDetails
            }
        }
    }
    
    return $archivesByEnvironment
}

<#
    Function: Remove-OldArchives
    Removes archive zip files older than the specified retention period.
    
    Parameters:
        - OutputFolder: Folder containing the archive zip files
        - RetentionDays: Number of days to keep archives
    
    Returns: PSCustomObject with cleanup statistics
#>
function Remove-OldArchives {
    param(
        [Parameter(Mandatory)]
        [string]$OutputFolder,
        
        [Parameter(Mandatory)]
        [int]$RetentionDays
    )
    
    $stats = [PSCustomObject]@{
        FilesRemoved    = 0
        BytesFreed      = 0
        Errors          = @()
    }
    
    if (-not (Test-Path $OutputFolder)) {
        Write-LogMessage "Output folder does not exist, no archives to clean up" -Level DEBUG
        return $stats
    }
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    Write-LogMessage "Removing archives older than $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss')) ($($RetentionDays) days)" -Level INFO
    
    try {
        # Find all COB*.zip files older than retention period
        $oldArchives = Get-ChildItem -Path $OutputFolder -Filter "COB*.zip" -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        if ($null -eq $oldArchives -or @($oldArchives).Count -eq 0) {
            Write-LogMessage "No old archives found to remove" -Level INFO
            return $stats
        }
        
        foreach ($archive in $oldArchives) {
            try {
                $fileSize = $archive.Length
                Remove-Item -Path $archive.FullName -Force
                $stats.FilesRemoved++
                $stats.BytesFreed += $fileSize
                Write-LogMessage "Removed old archive: $($archive.Name) (age: $([math]::Round(((Get-Date) - $archive.LastWriteTime).TotalDays, 1)) days)" -Level INFO
            }
            catch {
                $errorMsg = "Failed to remove $($archive.Name): $($_.Exception.Message)"
                Write-LogMessage $errorMsg -Level WARN
                $stats.Errors += $errorMsg
            }
        }
        
        $freedMB = [math]::Round($stats.BytesFreed / 1MB, 2)
        Write-LogMessage "Cleanup complete: Removed $($stats.FilesRemoved) old archive(s), freed $($freedMB) MB" -Level INFO
    }
    catch {
        $errorMsg = "Error during archive cleanup: $($_.Exception.Message)"
        Write-LogMessage $errorMsg -Level ERROR -Exception $_
        $stats.Errors += $errorMsg
    }
    
    return $stats
}

########################################################################################################
# Main
########################################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    
    ########################################################################################################
    # Environment Configuration Array
    # Defines source paths and file suffixes for each environment
    ########################################################################################################
    $EnvironmentConfig = @(
        # COBNT - Production environment (direct under erpprog)
        [PSCustomObject]@{
            Name           = "COBNT"
            Description    = "Production environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBNT"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBNT\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBTST - Test environment (direct under erpprog)
        [PSCustomObject]@{
            Name           = "COBTST"
            Description    = "Test environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBTST"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBTST\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBFUT - Future/Feature test environment (under COBTST)
        [PSCustomObject]@{
            Name           = "COBFUT"
            Description    = "Future/Feature test environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBTST\COBFUT"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBTST\COBFUT\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBKAT - Category test environment (under COBTST)
        [PSCustomObject]@{
            Name           = "COBKAT"
            Description    = "Category test environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBTST\COBKAT"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBTST\COBKAT\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBVFT - VF test environment (under COBTST)
        [PSCustomObject]@{
            Name           = "COBVFT"
            Description    = "VF test environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBTST\COBVFT"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBTST\COBVFT\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBVFK - VFK environment (under COBTST)
        [PSCustomObject]@{
            Name           = "COBVFK"
            Description    = "VFK environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBTST\COBVFK"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBTST\COBVFK\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBMIG - Migration environment (under COBTST)
        [PSCustomObject]@{
            Name           = "COBMIG"
            Description    = "Migration environment"
            SourcePath     = "\\DEDGE.fk.no\erpprog\COBTST\COBMIG"
            BndSourcePath  = "\\DEDGE.fk.no\erpprog\COBTST\COBMIG\BND"
            FileSuffixes   = @("*.gs", "*.int")
            BndSuffixes    = @("*.bnd")
        },
        
        # COBDEV - Development environment (different base path, extended file types)
        [PSCustomObject]@{
            Name           = "COBDEV"
            Description    = "Development environment (extended file types)"
            SourcePath     = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
            BndSourcePath  = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"  # Same path, BND goes to subfolder
            FileSuffixes   = @(
                "*.cbl",   # COBOL source
                "*.cpy",   # Copy files
                "*.cpb",   # Copy files
                "*.dcl",   # Declaration files
                "*.cpx",   # Copy files
                "*.gs",    # Object files
                "*.int",   # Intermediate object files
                "*.imp",   # Import files
                "*.rex",   # REXX scripts
                "*.bat",   # Batch files
                "*.cmd",   # Command files
                "*.cre",   # SQL create files
                "*.sql",   # SQL files
                "*.ins",   # SQL insert files
                "*.log",   # Log files
                "*.md"     # Documentation
            )
            BndSuffixes    = @("*.bnd")
        }
    )
    
    # Get application data path for local storage and output
    $appDataPath = Get-ApplicationDataPath
    $localFolder = Join-Path $appDataPath "CobolFiles"
    $outputFolder = Join-Path $appDataPath "CobolArchives"
    
    # Update WorkObject with paths
    $script:WorkObject.LocalFolder = $localFolder
    $script:WorkObject.OutputFolder = $outputFolder
    
    # Log configuration
    Write-LogMessage "Local folder: $($localFolder)" -Level INFO
    Write-LogMessage "Output folder: $($outputFolder)" -Level INFO
    Write-LogMessage "Environments to process: $($Environments -join ', ')" -Level INFO
    Write-LogMessage "Archive retention: $($RetentionDays) days" -Level INFO
    Write-LogMessage "Sync mode: Robocopy (incremental with delete)" -Level INFO
    
    # Log environment configuration details
    Write-LogMessage "Environment Configuration:" -Level INFO
    foreach ($envConfig in $EnvironmentConfig) {
        if ($Environments -contains $envConfig.Name) {
            Write-LogMessage "  $($envConfig.Name): $($envConfig.SourcePath)" -Level INFO
            Write-LogMessage "    BND: $($envConfig.BndSourcePath)" -Level DEBUG
            Write-LogMessage "    Suffixes: $($envConfig.FileSuffixes -join ', ')" -Level DEBUG
        }
    }
    
    # Build configuration summary for WorkObject
    $configSummary = @()
    foreach ($envConfig in $EnvironmentConfig) {
        if ($Environments -contains $envConfig.Name) {
            $configSummary += "═══════════════════════════════════════════════════════════"
            $configSummary += "$($envConfig.Name) - $($envConfig.Description)"
            $configSummary += "  Source: $($envConfig.SourcePath)"
            $configSummary += "  BND Source: $($envConfig.BndSourcePath)"
            $configSummary += "  File Suffixes: $($envConfig.FileSuffixes -join ', ')"
            $configSummary += "  BND Suffixes: $($envConfig.BndSuffixes -join ', ')"
        }
    }
    
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Configuration" -Script "Job Configuration" -Output @"
Local Folder: $localFolder
Output Folder: $outputFolder
Environments: $($Environments -join ', ')
Retention Days: $RetentionDays
Sync Mode: Robocopy (incremental with delete)

Environment Source Paths:
$($configSummary -join "`n")
"@
    
    # Ensure folders exist
    if (-not (Test-Path $localFolder)) {
        New-Item -Path $localFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created local folder: $($localFolder)" -Level INFO
    }
    if (-not (Test-Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created output folder: $($outputFolder)" -Level INFO
    }
    
    # Track results
    $results = @()
    
    foreach ($envName in $Environments) {
        Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
        Write-LogMessage "Processing environment: $($envName)" -Level INFO
        Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
        
        # Get environment configuration from array
        $envConfig = $EnvironmentConfig | Where-Object { $_.Name -eq $envName }
        
        if ($null -eq $envConfig) {
            Write-LogMessage "No configuration found for environment: $($envName)" -Level ERROR
            continue
        }
        
        Write-LogMessage "Source path: $($envConfig.SourcePath)" -Level INFO
        Write-LogMessage "BND source path: $($envConfig.BndSourcePath)" -Level INFO
        Write-LogMessage "File suffixes: $($envConfig.FileSuffixes -join ', ')" -Level DEBUG
        
        $envResult = [PSCustomObject]@{
            EnvironmentName    = $envName
            SourcePath         = $envConfig.SourcePath
            BndSourcePath      = $envConfig.BndSourcePath
            SourceFilesSynced  = 0
            ObjectFilesSynced  = 0
            BindFilesSynced    = 0
            FilesDeleted       = 0
            TotalFiles         = 0
            FileTypeCounts     = @{}
            ArchivePath        = $null
            ArchiveFileName    = $null
            ArchiveSizeBytes   = 0
            ArchiveSizeMB      = 0
            Status             = "Pending"
            Errors             = @()
        }
        
        try {
            # Step 1: Sync files using robocopy with configuration from array
            Write-LogMessage "Step 1: Syncing files from network..." -Level INFO
            
            # Use generic sync function with configuration
            $syncStats = Sync-EnvironmentFilesToLocal -EnvConfig $envConfig -LocalFolder $localFolder
            
            $envResult.SourceFilesSynced = $syncStats.SourceFilesSynced
            $envResult.ObjectFilesSynced = $syncStats.ObjectFilesSynced
            $envResult.BindFilesSynced = $syncStats.BindFilesSynced
            $envResult.FilesDeleted = $syncStats.FilesDeleted
            $envResult.TotalFiles = $syncStats.TotalFiles
            $envResult.FileTypeCounts = $syncStats.FileTypeCounts
            $envResult.Errors += $syncStats.Errors
            
            # Update totals
            $filesSync = $syncStats.SourceFilesSynced + $syncStats.ObjectFilesSynced
            $script:WorkObject.TotalFilesSynced += ($filesSync + $syncStats.BindFilesSynced)
            $script:WorkObject.TotalFilesDeleted += $syncStats.FilesDeleted
            
            # Check if any files exist in local folder
            if ($syncStats.TotalFiles -eq 0) {
                Write-LogMessage "No files found to archive for $($envName)" -Level WARN
                $envResult.Status = "NoFiles"
                $script:WorkObject.NoFilesEnvironments++
                $results += $envResult
                continue
            }
            
            Write-LogMessage "Total files in local folder: $($syncStats.TotalFiles)" -Level INFO
            
            # Step 2: Create zip archive
            Write-LogMessage "Step 2: Creating zip archive..." -Level INFO
            $archivePath = New-CobolArchive -EnvironmentName $envName -LocalFolder $localFolder -OutputFolder $outputFolder
            
            if ($null -ne $archivePath -and (Test-Path $archivePath)) {
                $archiveFile = Get-Item $archivePath
                $envResult.ArchivePath = $archivePath
                $envResult.ArchiveFileName = $archiveFile.Name
                $envResult.ArchiveSizeBytes = $archiveFile.Length
                $envResult.ArchiveSizeMB = [math]::Round($archiveFile.Length / 1MB, 2)
                $envResult.Status = "Success"
                
                $script:WorkObject.SuccessfulArchives++
                $script:WorkObject.TotalArchiveSize += $archiveFile.Length
                
                # Note: Local folder is kept for efficient incremental sync on next run
                Write-LogMessage "Local folder kept for incremental sync: $(Join-Path $localFolder $envName)" -Level DEBUG
            }
            else {
                $envResult.Status = "ArchiveFailed"
                $envResult.Errors += "Failed to create archive"
                $script:WorkObject.FailedArchives++
            }
        }
        catch {
            Write-LogMessage "Error processing $($envName): $($_.Exception.Message)" -Level ERROR -Exception $_
            $envResult.Status = "Failed"
            $envResult.Errors += $_.Exception.Message
            $script:WorkObject.FailedArchives++
        }
        
        $results += $envResult
        
        # Build file type counts output for environments with multiple file types
        $fileTypeOutput = ""
        if ($null -ne $envResult.FileTypeCounts -and $envResult.FileTypeCounts.Count -gt 0) {
            foreach ($typeName in $envResult.FileTypeCounts.Keys | Sort-Object) {
                if ($envResult.FileTypeCounts[$typeName] -gt 0) {
                    $fileTypeOutput += "  $($typeName): $($envResult.FileTypeCounts[$typeName])`n"
                }
            }
        }
        
        # Add environment result to WorkObject with source path info from configuration
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Environment_$envName" -Script "Processing $envName" -Output @"
Status: $($envResult.Status)
Source Path: $($envConfig.SourcePath)
BND Source Path: $($envConfig.BndSourcePath)
File Suffixes: $($envConfig.FileSuffixes -join ', ')
Source Files Synced: $($envResult.SourceFilesSynced)
Bind Files Synced: $($envResult.BindFilesSynced)
Files Deleted: $($envResult.FilesDeleted)
Total Files: $($envResult.TotalFiles)
File Type Counts:
$fileTypeOutput
Archive: $($envResult.ArchiveFileName)
Archive Size: $($envResult.ArchiveSizeMB) MB
"@
    }
    
    $script:WorkObject.EnvironmentsProcessed = $results.Count
    $script:WorkObject.EnvironmentResults = $results
    
    # Clean up old archives
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "Cleaning up old archives..." -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    $cleanupStats = Remove-OldArchives -OutputFolder $outputFolder -RetentionDays $RetentionDays
    
    $script:WorkObject.OldArchivesRemoved = $cleanupStats.FilesRemoved
    $script:WorkObject.CleanupBytesFreed = $cleanupStats.BytesFreed
    
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Cleanup" -Script "Archive Cleanup" -Output @"
Retention Days: $RetentionDays
Archives Removed: $($cleanupStats.FilesRemoved)
Space Freed: $([math]::Round($cleanupStats.BytesFreed / 1MB, 2)) MB
"@
    
    # Get available archives per environment
    Write-LogMessage "Getting available archives per environment..." -Level INFO
    $script:WorkObject.AvailableArchives = Get-AvailableArchivesPerEnvironment -OutputFolder $outputFolder
    
    # Build available archives summary for WorkObject
    $archiveSummary = @()
    foreach ($envArchive in $script:WorkObject.AvailableArchives) {
        $archiveSummary += "═══════════════════════════════════════════════════════════"
        $archiveSummary += "Environment: $($envArchive.EnvironmentName)"
        $archiveSummary += "  Archive Count: $($envArchive.ArchiveCount)"
        $archiveSummary += "  Total Size: $($envArchive.TotalSizeMB) MB"
        $archiveSummary += "  Latest: $($envArchive.LatestArchive) ($($envArchive.LatestCreated))"
        $archiveSummary += ""
        foreach ($archive in $envArchive.Archives) {
            $archiveSummary += "    - $($archive.FileName) | $($archive.SizeMB) MB | $($archive.Created) | $($archive.AgeDays) days old"
        }
    }
    
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "AvailableArchives" -Script "Available Archives Per Environment" -Output ($archiveSummary -join "`n")
    
    # Summary
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "  Processing Complete - Summary" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    
    $successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $failedCount = ($results | Where-Object { $_.Status -in @("Failed", "ArchiveFailed") }).Count
    $noFilesCount = ($results | Where-Object { $_.Status -eq "NoFiles" }).Count
    
    Write-LogMessage "Environments processed: $($results.Count)" -Level INFO
    Write-LogMessage "Successful archives: $($successCount)" -Level INFO
    if ($noFilesCount -gt 0) {
        Write-LogMessage "Environments with no files: $($noFilesCount)" -Level WARN
    }
    if ($failedCount -gt 0) {
        Write-LogMessage "Failed: $($failedCount)" -Level WARN
    }
    if ($cleanupStats.FilesRemoved -gt 0) {
        $freedMB = [math]::Round($cleanupStats.BytesFreed / 1MB, 2)
        Write-LogMessage "Old archives removed: $($cleanupStats.FilesRemoved) (freed $($freedMB) MB)" -Level INFO
    }
    
    Write-LogMessage "" -Level INFO
    Write-LogMessage "Archives created:" -Level INFO
    foreach ($result in ($results | Where-Object { $_.Status -eq "Success" })) {
        Write-LogMessage "  $($result.ArchivePath) ($($result.ArchiveSizeMB) MB)" -Level INFO
        $syncedCount = $result.SourceFilesSynced + $result.BindFilesSynced
        Write-LogMessage "    Source: $($result.SourcePath)" -Level INFO
        Write-LogMessage "    Total files: $($result.TotalFiles), Synced: $($syncedCount), Deleted: $($result.FilesDeleted)" -Level INFO
    }
    
    # Update WorkObject with success status
    $script:WorkObject.Success = $true
    $script:WorkObject.Status = "Completed"
    $script:WorkObject.EndTime = Get-Date
    $script:WorkObject.Duration = $script:WorkObject.EndTime - $script:WorkObject.StartTime
    
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Summary" -Script "Execution Summary" -Output @"
Environments Processed: $($results.Count)
Successful Archives: $successCount
Failed Archives: $failedCount
No Files Environments: $noFilesCount
Total Files Synced: $($script:WorkObject.TotalFilesSynced)
Total Files Deleted: $($script:WorkObject.TotalFilesDeleted)
Total Archive Size: $([math]::Round($script:WorkObject.TotalArchiveSize / 1MB, 2)) MB
Old Archives Removed: $($cleanupStats.FilesRemoved)
Space Freed: $([math]::Round($cleanupStats.BytesFreed / 1MB, 2)) MB
Duration: $($script:WorkObject.Duration.ToString('hh\:mm\:ss'))
"@
    
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    
    # Export WorkObject to HTML and deploy to web folder "Jobs"
    try {
        $reportFileName = Join-Path $appDataPath "CobolObjectAndBindFilesArchiver_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject `
            -FileName $reportFileName `
            -Title "COBOL Object and Bind Files Archiver" `
            -AddToDevToolsWebPath $true `
            -DevToolsWebDirectory "Jobs" `
            -AutoOpen $false
        
        Write-LogMessage "Execution report exported to: $($reportFileName)" -Level INFO
        Write-LogMessage "Report also available at: $(Get-DevToolsWebPathUrl)/Jobs/COBOL Object and Bind Files Archiver.html" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to export HTML report: $($_.Exception.Message)" -Level WARN
    }
    
    # Return results
    return [PSCustomObject]@{
        SourceBasePath       = $sourceBasePath
        LocalFolder          = $localFolder
        OutputFolder         = $outputFolder
        EnvironmentsTotal    = $results.Count
        SuccessfulArchives   = $successCount
        FailedArchives       = $failedCount
        NoFilesEnvironments  = $noFilesCount
        TotalFilesSynced     = $script:WorkObject.TotalFilesSynced
        TotalFilesDeleted    = $script:WorkObject.TotalFilesDeleted
        OldArchivesRemoved   = $cleanupStats.FilesRemoved
        CleanupBytesFreed    = $cleanupStats.BytesFreed
        RetentionDays        = $RetentionDays
        AvailableArchives    = $script:WorkObject.AvailableArchives
        Details              = $results
    }
}
catch {
    # Update WorkObject with failure
    $script:WorkObject.Success = $false
    $script:WorkObject.Status = "Failed"
    $script:WorkObject.ErrorMessage = $_.Exception.Message
    $script:WorkObject.EndTime = Get-Date
    $script:WorkObject.Duration = $script:WorkObject.EndTime - $script:WorkObject.StartTime
    
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Error" -Script "Execution Error" -Output @"
Error occurred at line: $($_.InvocationInfo.ScriptLineNumber)
Error message: $($_.Exception.Message)
Stack trace: $($_.ScriptStackTrace)
"@
    
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    
    # Export failure report
    try {
        $appDataPath = Get-ApplicationDataPath
        $reportFileName = Join-Path $appDataPath "CobolObjectAndBindFilesArchiver_FAILED_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject `
            -FileName $reportFileName `
            -Title "COBOL Object and Bind Files Archiver - FAILED" `
            -AddToDevToolsWebPath $true `
            -DevToolsWebDirectory "Jobs" `
            -AutoOpen $false
        
        Write-LogMessage "Failure report exported to: $($reportFileName)" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to export failure report: $($_.Exception.Message)" -Level WARN
    }
    
    throw
}
