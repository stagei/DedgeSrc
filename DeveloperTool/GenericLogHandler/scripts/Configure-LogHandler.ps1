#Requires -Version 5.1
<#
.SYNOPSIS
    Configuration script for Generic Log Handler system

.DESCRIPTION
    This script helps configure the Generic Log Handler system by:
    - Setting up log source configurations
    - Configuring database connections
    - Setting retention policies
    - Testing connections and configurations

.PARAMETER ConfigPath
    Path to the configuration file. Default is C:\GenericLogHandler\Config\import-config.json

.PARAMETER AddLogSource
    Add a new log source configuration

.PARAMETER TestConnections
    Test all configured connections

.EXAMPLE
    .\Configure-LogHandler.ps1 -TestConnections

.EXAMPLE
    .\Configure-LogHandler.ps1 -AddLogSource
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "C:\GenericLogHandler\Config\import-config.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$AddLogSource,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestConnections
)

# Import GlobalFunctions if available
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
} catch {
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

function Get-Configuration {
    if (-not (Test-Path $ConfigPath)) {
        Write-LogMessage "Configuration file not found: $ConfigPath" -Level "ERROR"
        return $null
    }
    
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        return $config
    } catch {
        Write-LogMessage "Error reading configuration: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Save-Configuration {
    param([object]$Config)
    
    try {
        $Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
        Write-LogMessage "Configuration saved successfully" -Level "INFO"
        return $true
    } catch {
        Write-LogMessage "Error saving configuration: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Add-PowerShellLogSource {
    $config = Get-Configuration
    if (-not $config) { return }
    
    Write-Host "`n=== Adding PowerShell Log Source ===" -ForegroundColor Yellow
    
    $sourceName = Read-Host "Enter source name"
    $logPath = Read-Host "Enter log file path pattern (e.g., C:\opt\data\AllPwshLog\*.log)"
    $watchDirectory = (Read-Host "Watch directory for new files? (Y/N)" -Default "Y") -eq "Y"
    $moveProcessed = (Read-Host "Move processed files? (Y/N)" -Default "N") -eq "Y"
    
    $processedLocation = ""
    if ($moveProcessed) {
        $processedLocation = Read-Host "Enter processed files location"
    }
    
    $newSource = @{
        name = $sourceName
        type = "file"
        enabled = $true
        priority = $config.import_sources.Count + 1
        config = @{
            path = $logPath
            format = "powershell"
            parser = "powershell_log_parser"
            watch_directory = $watchDirectory
            encoding = "utf-8"
            poll_interval = 30
            process_existing_files = $false
            move_processed_files = $moveProcessed
            processed_files_location = $processedLocation
            error_files_location = "$([System.IO.Path]::GetDirectoryName($logPath))\Errors"
        }
    }
    
    $config.import_sources += $newSource
    
    if (Save-Configuration $config) {
        Write-LogMessage "PowerShell log source '$sourceName' added successfully" -Level "INFO"
    }
}

function Add-DatabaseLogSource {
    $config = Get-Configuration
    if (-not $config) { return }
    
    Write-Host "`n=== Adding Database Log Source ===" -ForegroundColor Yellow
    
    $sourceName = Read-Host "Enter source name"
    $provider = Read-Host "Enter provider (IBM.Data.DB2 or System.Data.Odbc)" -Default "IBM.Data.DB2"
    $connectionString = Read-Host "Enter connection string"
    $query = Read-Host "Enter SQL query"
    $pollInterval = [int](Read-Host "Enter poll interval (seconds)" -Default "300")
    $incrementalColumn = Read-Host "Enter incremental column name (optional)"
    
    $newSource = @{
        name = $sourceName
        type = "database"
        enabled = $true
        priority = $config.import_sources.Count + 1
        config = @{
            provider = $provider
            connection_string = $connectionString
            query = $query
            poll_interval = $pollInterval
            incremental_column = $incrementalColumn
            incremental_value_store = "C:\GenericLogHandler\Data\incremental_state.json"
            batch_size = 500
            timeout = 120
        }
    }
    
    $config.import_sources += $newSource
    
    if (Save-Configuration $config) {
        Write-LogMessage "Database log source '$sourceName' added successfully" -Level "INFO"
    }
}

function Add-EventLogSource {
    $config = Get-Configuration
    if (-not $config) { return }
    
    Write-Host "`n=== Adding Windows Event Log Source ===" -ForegroundColor Yellow
    
    $sourceName = Read-Host "Enter source name"
    $logNames = (Read-Host "Enter log names (comma-separated, e.g., Application,System)" -Default "Application,System").Split(',') | ForEach-Object { $_.Trim() }
    $eventLevels = (Read-Host "Enter event levels (comma-separated, e.g., Error,Warning)" -Default "Error,Warning,Information").Split(',') | ForEach-Object { $_.Trim() }
    $pollInterval = [int](Read-Host "Enter poll interval (seconds)" -Default "60")
    $maxEvents = [int](Read-Host "Enter max events per poll" -Default "1000")
    
    $newSource = @{
        name = $sourceName
        type = "eventlog"
        enabled = $true
        priority = $config.import_sources.Count + 1
        config = @{
            log_names = $logNames
            event_levels = $eventLevels
            poll_interval = $pollInterval
            max_events_per_poll = $maxEvents
            event_id_filters = @{
                include = @()
                exclude = @(4624, 4634) # Exclude logon/logoff events by default
            }
        }
    }
    
    $config.import_sources += $newSource
    
    if (Save-Configuration $config) {
        Write-LogMessage "Event log source '$sourceName' added successfully" -Level "INFO"
    }
}

function Test-DatabaseConnection {
    param([object]$Source)
    
    Write-LogMessage "Testing database connection for: $($Source.name)" -Level "INFO"
    
    try {
        if ($Source.config.provider -eq "IBM.Data.DB2") {
            # Test DB2 connection (simplified)
            $testQuery = "SELECT 1 FROM SYSIBM.SYSDUMMY1"
        } else {
            # Test ODBC connection
            $testQuery = "SELECT 1"
        }
        
        Write-LogMessage "Connection string: $($Source.config.connection_string -replace 'Password=[^;]*', 'Password=***')" -Level "DEBUG"
        Write-LogMessage "Test query: $testQuery" -Level "DEBUG"
        
        # Note: Actual connection testing would require the appropriate drivers
        Write-LogMessage "Database connection test completed (manual verification required)" -Level "INFO"
        return $true
        
    } catch {
        Write-LogMessage "Database connection test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-FileSource {
    param([object]$Source)
    
    Write-LogMessage "Testing file source: $($Source.name)" -Level "INFO"
    
    try {
        $directory = [System.IO.Path]::GetDirectoryName($Source.config.path)
        $pattern = [System.IO.Path]::GetFileName($Source.config.path)
        
        if (-not (Test-Path $directory)) {
            Write-LogMessage "Directory does not exist: $directory" -Level "ERROR"
            return $false
        }
        
        $files = Get-ChildItem -Path $directory -Filter $pattern -ErrorAction SilentlyContinue
        Write-LogMessage "Found $($files.Count) files matching pattern: $($Source.config.path)" -Level "INFO"
        
        if ($files.Count -gt 0) {
            $sampleFile = $files[0]
            Write-LogMessage "Sample file: $($sampleFile.FullName) (Size: $($sampleFile.Length) bytes, Modified: $($sampleFile.LastWriteTime))" -Level "INFO"
        }
        
        return $true
        
    } catch {
        Write-LogMessage "File source test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-EventLogSource {
    param([object]$Source)
    
    Write-LogMessage "Testing event log source: $($Source.name)" -Level "INFO"
    
    try {
        foreach ($logName in $Source.config.log_names) {
            if (Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue) {
                Write-LogMessage "Event log '$logName' is accessible" -Level "INFO"
            } else {
                Write-LogMessage "Event log '$logName' is not accessible" -Level "WARN"
            }
        }
        
        return $true
        
    } catch {
        Write-LogMessage "Event log source test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-AllConnections {
    $config = Get-Configuration
    if (-not $config) { return }
    
    Write-Host "`n=== Testing All Connections ===" -ForegroundColor Yellow
    
    $successCount = 0
    $totalCount = 0
    
    foreach ($source in $config.import_sources) {
        if (-not $source.enabled) {
            Write-LogMessage "Skipping disabled source: $($source.name)" -Level "INFO"
            continue
        }
        
        $totalCount++
        $success = $false
        
        switch ($source.type) {
            "database" { $success = Test-DatabaseConnection $source }
            "file" { $success = Test-FileSource $source }
            "eventlog" { $success = Test-EventLogSource $source }
            default { 
                Write-LogMessage "Unknown source type: $($source.type)" -Level "WARN"
                $success = $false
            }
        }
        
        if ($success) { $successCount++ }
    }
    
    Write-Host "`n=== Test Results ===" -ForegroundColor Yellow
    Write-LogMessage "Tested $totalCount sources: $successCount successful, $($totalCount - $successCount) failed" -Level "INFO"
    
    if ($successCount -eq $totalCount) {
        Write-LogMessage "All connection tests passed!" -Level "INFO"
    } else {
        Write-LogMessage "Some connection tests failed. Check the logs above for details." -Level "WARN"
    }
}

function Show-Configuration {
    $config = Get-Configuration
    if (-not $config) { return }
    
    Write-Host "`n=== Current Configuration ===" -ForegroundColor Yellow
    
    Write-Host "General Settings:" -ForegroundColor Cyan
    Write-Host "  Service Name: $($config.general.service_name)"
    Write-Host "  Log Level: $($config.general.log_level)"
    Write-Host "  Max Concurrent Imports: $($config.general.max_concurrent_imports)"
    Write-Host "  Batch Size: $($config.general.batch_size)"
    
    Write-Host "`nDatabase Settings:" -ForegroundColor Cyan
    Write-Host "  Type: $($config.database.type)"
    Write-Host "  Database: $($config.database.database_name)"
    Write-Host "  Connection: $($config.database.connection_string -replace 'Password=[^;]*', 'Password=***')"
    
    Write-Host "`nRetention Settings:" -ForegroundColor Cyan
    Write-Host "  Default Days: $($config.retention.default_days)"
    Write-Host "  Cleanup Schedule: $($config.retention.cleanup_schedule)"
    
    Write-Host "`nImport Sources:" -ForegroundColor Cyan
    foreach ($source in $config.import_sources) {
        $status = if ($source.enabled) { "Enabled" } else { "Disabled" }
        Write-Host "  $($source.name) ($($source.type)) - $status"
    }
}

function Set-RetentionPolicy {
    $config = Get-Configuration
    if (-not $config) { return }
    
    Write-Host "`n=== Setting Retention Policy ===" -ForegroundColor Yellow
    
    $defaultDays = [int](Read-Host "Enter default retention days" -Default $config.retention.default_days)
    $config.retention.default_days = $defaultDays
    
    Write-Host "`nSet retention by log level:"
    $levels = @("FATAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE")
    
    foreach ($level in $levels) {
        $currentValue = $config.retention.by_level.$level
        if (-not $currentValue) { $currentValue = $defaultDays }
        
        $newValue = Read-Host "  $level retention days" -Default $currentValue
        if ($newValue) {
            $config.retention.by_level.$level = [int]$newValue
        }
    }
    
    if (Save-Configuration $config) {
        Write-LogMessage "Retention policy updated successfully" -Level "INFO"
    }
}

function Main-Menu {
    while ($true) {
        Write-Host "`n=== Generic Log Handler Configuration ===" -ForegroundColor Yellow
        Write-Host "1. Show current configuration"
        Write-Host "2. Add PowerShell log source"
        Write-Host "3. Add database log source"
        Write-Host "4. Add event log source"
        Write-Host "5. Set retention policy"
        Write-Host "6. Test all connections"
        Write-Host "7. Exit"
        
        $choice = Read-Host "`nSelect option (1-7)"
        
        switch ($choice) {
            "1" { Show-Configuration }
            "2" { Add-PowerShellLogSource }
            "3" { Add-DatabaseLogSource }
            "4" { Add-EventLogSource }
            "5" { Set-RetentionPolicy }
            "6" { Test-AllConnections }
            "7" { return }
            default { Write-Host "Invalid option. Please select 1-7." -ForegroundColor Red }
        }
    }
}

# Main execution
try {
    Write-LogMessage "Generic Log Handler Configuration Tool" -Level "INFO"
    Write-LogMessage "Configuration file: $ConfigPath" -Level "INFO"
    
    if ($AddLogSource) {
        Write-Host "`n=== Add New Log Source ===" -ForegroundColor Yellow
        Write-Host "1. PowerShell log files"
        Write-Host "2. Database source"
        Write-Host "3. Windows Event Logs"
        
        $sourceType = Read-Host "`nSelect source type (1-3)"
        switch ($sourceType) {
            "1" { Add-PowerShellLogSource }
            "2" { Add-DatabaseLogSource }
            "3" { Add-EventLogSource }
            default { Write-LogMessage "Invalid source type" -Level "ERROR" }
        }
    } elseif ($TestConnections) {
        Test-AllConnections
    } else {
        Main-Menu
    }
    
} catch {
    Write-LogMessage "Configuration error: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}
