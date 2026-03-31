#!/usr/bin/env pwsh
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Exports comprehensive security settings related to service logon rights for diagnostics.

.DESCRIPTION
    This script captures and exports all security settings relevant to running Windows services
    under user accounts. It should be run:
    1. BEFORE configuring service credentials (baseline)
    2. AFTER configuring service credentials (to see what changed)
    
    The script exports:
    - Complete security policy (all user rights)
    - Specific user rights (SeServiceLogonRight, SeBatchLogonRight)
    - User and SID information
    - Service configuration (if service exists)
    - Group Policy settings
    - Registry keys related to services
    
.PARAMETER ServiceName
    Name of the Windows Service to diagnose (default: ServerMonitor)

.PARAMETER Username
    Username to check rights for (default: current user)

.PARAMETER OutputPrefix
    Prefix for output files (default: "before" or "after")

.EXAMPLE
    .\Export-ServiceSecuritySettings.ps1 -OutputPrefix "before"
    # Run before configuring service

.EXAMPLE
    .\Export-ServiceSecuritySettings.ps1 -OutputPrefix "after"
    # Run after configuring service

.EXAMPLE
    .\Export-ServiceSecuritySettings.ps1 -Username "DEDGE\FKTSTADM" -OutputPrefix "custom"
    # Check specific user

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    This script requires administrative privileges to run.
    Output files are saved to: $PSScriptRoot\SecurityDiagnostics\
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ServiceName = "ServerMonitor",
    
    [Parameter(Mandatory = $false)]
    [string]$Username = "$env:USERDOMAIN\$env:USERNAME",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPrefix = ""  # Auto-detected if empty
)

Import-Module GlobalFunctions -Force

# Helper function to safely convert objects to JSON with depth handling
function ConvertTo-JsonSafe {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [Parameter(Mandatory = $false)]
        [int]$Depth = 10
    )
    
    try {
        # Try standard conversion first
        $json = $InputObject | ConvertTo-Json -Depth $Depth -Compress:$false -WarningAction SilentlyContinue
        return $json
    }
    catch {
        # If that fails, try to serialize as a simplified object
        try {
            $simplified = $InputObject | Select-Object * -ErrorAction SilentlyContinue
            $json = $simplified | ConvertTo-Json -Depth $Depth -Compress:$false -WarningAction SilentlyContinue
            return $json
        }
        catch {
            # Last resort: convert to string representation
            return @{
                Error = "JSON serialization failed"
                Type = $InputObject.GetType().FullName
                StringValue = $InputObject.ToString()
            } | ConvertTo-Json -Depth 2
        }
    }
}

try {
    $ErrorActionPreference = "Stop"
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "     Service Security Settings Diagnostic Export Tool" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Verify running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "❌ ERROR: This script must be run as Administrator!" -ForegroundColor Red
        throw "This script must be run as Administrator!"
    }
    
    # Auto-detect output prefix based on service state if not specified
    if ([string]::IsNullOrWhiteSpace($OutputPrefix)) {
        Write-Host "🔍 Auto-detecting service state..." -ForegroundColor Cyan
        
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        
        if (-not $service) {
            $OutputPrefix = "BeforeServiceAdded"
            Write-Host "   ⚪ Service '$ServiceName' not installed" -ForegroundColor Yellow
            Write-Host "   📁 Output folder: $OutputPrefix" -ForegroundColor Gray
        }
        elseif ($service.Status -eq 'Running') {
            $OutputPrefix = "AfterServiceOk"
            Write-Host "   ✅ Service '$ServiceName' is installed and running" -ForegroundColor Green
            Write-Host "   📁 Output folder: $OutputPrefix" -ForegroundColor Gray
        }
        else {
            $OutputPrefix = "AfterServiceFail"
            Write-Host "   ❌ Service '$ServiceName' is installed but not running (Status: $($service.Status))" -ForegroundColor Red
            Write-Host "   📁 Output folder: $OutputPrefix" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    # Create output directory structure
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseDir = "$PSScriptRoot\SecurityDiagnostics"
    $outputDir = "$baseDir\$OutputPrefix"
    
    if (-not (Test-Path $baseDir)) {
        New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    
    $outputBase = "$outputDir\$timestamp"
    
    Write-Host "📋 Configuration:" -ForegroundColor Yellow
    Write-Host "   Service Name: $ServiceName" -ForegroundColor Gray
    Write-Host "   Username: $Username" -ForegroundColor Gray
    Write-Host "   Output Directory: $outputDir" -ForegroundColor Gray
    Write-Host "   Timestamp: $timestamp" -ForegroundColor Gray
    Write-Host ""
    
    # Resolve username to SID
    Write-Host "🔍 Resolving user information..." -ForegroundColor Cyan
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount($Username)
        $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        $userSidString = $userSid.Value
        
        Write-Host "   ✅ Username: $Username" -ForegroundColor Green
        Write-Host "   ✅ SID: $userSidString" -ForegroundColor Green
        
        # Save user info
        $userInfo = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Username = $Username
            SID = $userSidString
            ComputerName = $env:COMPUTERNAME
            Domain = $env:USERDOMAIN
            CurrentUser = "$env:USERDOMAIN\$env:USERNAME"
        }
        ConvertTo-JsonSafe -InputObject $userInfo -Depth 5 | Out-File "$outputBase`_UserInfo.json" -Encoding UTF8
        Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_UserInfo.json" -ForegroundColor Gray
    }
    catch {
        Write-Host "   ❌ Failed to resolve username: $($_.Exception.Message)" -ForegroundColor Red
        $userSidString = "UNKNOWN"
    }
    Write-Host ""
    
    # Export complete security policy
    Write-Host "📄 Exporting complete security policy..." -ForegroundColor Cyan
    try {
        $secpolFile = "$outputBase`_SecurityPolicy.inf"
        $seceditArgs = @("/export", "/cfg", $secpolFile, "/quiet")
        $null = & secedit.exe $seceditArgs
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $secpolFile)) {
            $fileSize = (Get-Item $secpolFile).Length
            Write-Host "   ✅ Security policy exported ($fileSize bytes)" -ForegroundColor Green
            Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_SecurityPolicy.inf" -ForegroundColor Gray
        }
        else {
            Write-Host "   ❌ Failed to export security policy (exit code: $LASTEXITCODE)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   ❌ Error exporting security policy: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # Parse and extract user rights from security policy
    Write-Host "🔐 Extracting user rights assignments..." -ForegroundColor Cyan
    try {
        if (Test-Path $secpolFile) {
            $secpolContent = Get-Content -Path $secpolFile -Raw
            $userRights = @{}
            
            # Extract all privilege rights
            $privilegeSection = $secpolContent -split '\[Privilege Rights\]' | Select-Object -Last 1
            $privilegeSection = $privilegeSection -split '\[' | Select-Object -First 1
            
            $privilegeLines = $privilegeSection -split "`r`n" | Where-Object { $_ -match '=' }
            foreach ($line in $privilegeLines) {
                if ($line -match '^(.+?)\s*=\s*(.+)$') {
                    $rightName = $matches[1].Trim()
                    $rightValue = $matches[2].Trim()
                    $userRights[$rightName] = $rightValue
                }
            }
            
            # Save all user rights
            ConvertTo-JsonSafe -InputObject $userRights -Depth 5 | Out-File "$outputBase`_UserRights.json" -Encoding UTF8
            Write-Host "   ✅ Extracted $($userRights.Count) user rights assignments" -ForegroundColor Green
            Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_UserRights.json" -ForegroundColor Gray
            
            # Check specific rights for the target user
            Write-Host ""
            Write-Host "   📊 Rights for $($Username) (SID: $userSidString):" -ForegroundColor Yellow
            
            $targetRights = @{
                'SeServiceLogonRight' = 'Log on as a service'
                'SeBatchLogonRight' = 'Log on as a batch job'
                'SeInteractiveLogonRight' = 'Log on locally'
                'SeNetworkLogonRight' = 'Access this computer from the network'
                'SeDenyServiceLogonRight' = 'Deny log on as a service'
                'SeDenyBatchLogonRight' = 'Deny log on as a batch job'
            }
            
            $rightsReport = @()
            foreach ($right in $targetRights.GetEnumerator()) {
                $rightName = $right.Key
                $rightDescription = $right.Value
                
                if ($userRights.ContainsKey($rightName)) {
                    $hasRight = $userRights[$rightName] -match [regex]::Escape($userSidString)
                    $status = if ($hasRight) { "✅ GRANTED" } else { "❌ NOT GRANTED" }
                    $color = if ($hasRight) { "Green" } else { "Red" }
                    
                    Write-Host "      $status - $rightDescription ($rightName)" -ForegroundColor $color
                    
                    $rightsReport += [PSCustomObject]@{
                        Right = $rightName
                        Description = $rightDescription
                        HasRight = $hasRight
                        AllSIDs = $userRights[$rightName]
                    }
                }
                else {
                    Write-Host "      ⚠️  NOT DEFINED - $rightDescription ($rightName)" -ForegroundColor Yellow
                    $rightsReport += [PSCustomObject]@{
                        Right = $rightName
                        Description = $rightDescription
                        HasRight = $false
                        AllSIDs = "NOT DEFINED"
                    }
                }
            }
            
            ConvertTo-JsonSafe -InputObject $rightsReport -Depth 5 | Out-File "$outputBase`_TargetUserRights.json" -Encoding UTF8
            Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_TargetUserRights.json" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "   ❌ Error extracting user rights: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # Export service configuration
    Write-Host "⚙️  Exporting service configuration..." -ForegroundColor Cyan
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $serviceCim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'"
            
            $serviceInfo = @{
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Name = $service.Name
                DisplayName = $service.DisplayName
                Status = $service.Status
                StartType = $service.StartType
                ServiceAccount = $serviceCim.StartName
                PathName = $serviceCim.PathName
                Description = $serviceCim.Description
                ProcessId = $serviceCim.ProcessId
                State = $serviceCim.State
                ExitCode = $serviceCim.ExitCode
            }
            
            ConvertTo-JsonSafe -InputObject $serviceInfo -Depth 5 | Out-File "$outputBase`_ServiceInfo.json" -Encoding UTF8
            
            Write-Host "   ✅ Service: $($service.DisplayName)" -ForegroundColor Green
            Write-Host "      Status: $($service.Status)" -ForegroundColor Gray
            Write-Host "      Start Type: $($service.StartType)" -ForegroundColor Gray
            Write-Host "      Account: $($serviceCim.StartName)" -ForegroundColor Gray
            Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_ServiceInfo.json" -ForegroundColor Gray
        }
        else {
            Write-Host "   ⚠️  Service '$ServiceName' not found" -ForegroundColor Yellow
            ConvertTo-JsonSafe -InputObject @{ Error = "Service not found"; ServiceName = $ServiceName } -Depth 2 | Out-File "$outputBase`_ServiceInfo.json" -Encoding UTF8
        }
    }
    catch {
        Write-Host "   ❌ Error exporting service info: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # Check Group Policy settings
    Write-Host "🔧 Checking Group Policy settings..." -ForegroundColor Cyan
    try {
        $gpresultFile = "$outputBase`_GroupPolicy.html"
        $null = & gpresult.exe /H $gpresultFile /F 2>&1
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $gpresultFile)) {
            $fileSize = (Get-Item $gpresultFile).Length
            Write-Host "   ✅ Group Policy report exported ($fileSize bytes)" -ForegroundColor Green
            Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_GroupPolicy.html" -ForegroundColor Gray
            Write-Host "      (Open in browser to view)" -ForegroundColor Gray
        }
        else {
            Write-Host "   ⚠️  Group Policy export failed or incomplete" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "   ❌ Error exporting Group Policy: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # Export relevant registry keys
    Write-Host "📝 Exporting registry keys..." -ForegroundColor Cyan
    try {
        $regKeys = @(
            "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
            "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSidString"
        )
        
        $regExport = @{}
        foreach ($regPath in $regKeys) {
            if (Test-Path $regPath) {
                $regValues = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                
                # Flatten registry values to simple key-value pairs
                $flattenedReg = @{}
                foreach ($prop in ($regValues.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" })) {
                    try {
                        # Convert complex types to strings
                        if ($prop.Value -is [array]) {
                            $flattenedReg[$prop.Name] = $prop.Value -join ", "
                        }
                        elseif ($null -eq $prop.Value) {
                            $flattenedReg[$prop.Name] = "(null)"
                        }
                        else {
                            $flattenedReg[$prop.Name] = $prop.Value.ToString()
                        }
                    }
                    catch {
                        $flattenedReg[$prop.Name] = "(error converting value)"
                    }
                }
                
                $regExport[$regPath] = $flattenedReg
                Write-Host "   ✅ Exported: $regPath" -ForegroundColor Green
            }
            else {
                Write-Host "   ⚠️  Not found: $regPath" -ForegroundColor Yellow
                $regExport[$regPath] = "KEY_NOT_FOUND"
            }
        }
        
        ConvertTo-JsonSafe -InputObject $regExport -Depth 5 | Out-File "$outputBase`_Registry.json" -Encoding UTF8
        Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_Registry.json" -ForegroundColor Gray
    }
    catch {
        Write-Host "   ❌ Error exporting registry: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # Get recent Event Log entries related to services and logon
    Write-Host "📊 Capturing recent Event Log entries..." -ForegroundColor Cyan
    try {
        $eventLogs = @()
        
        # System log - service errors
        $systemEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 1,2,3  # Critical, Error, Warning
            StartTime = (Get-Date).AddHours(-24)
        } -MaxEvents 100 -ErrorAction SilentlyContinue | Where-Object {
            $_.Message -match $ServiceName -or 
            $_.Message -match "service" -or 
            $_.ProviderName -eq "Service Control Manager"
        }
        
        if ($systemEvents) {
            # Flatten event objects to avoid deep nesting issues
            $flattenedSystemEvents = $systemEvents | ForEach-Object {
                [PSCustomObject]@{
                    TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Level = $_.Level
                    LevelDisplayName = $_.LevelDisplayName
                    ProviderName = $_.ProviderName
                    Id = $_.Id
                    Message = $_.Message
                    MachineName = $_.MachineName
                    UserId = if ($_.UserId) { $_.UserId.ToString() } else { $null }
                    ProcessId = $_.ProcessId
                }
            }
            $eventLogs += $flattenedSystemEvents
            Write-Host "   ✅ Captured $($systemEvents.Count) System log entries" -ForegroundColor Green
        }
        
        # Security log - logon events
        $securityEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            StartTime = (Get-Date).AddHours(-24)
        } -MaxEvents 100 -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -in @(4624, 4625, 4634, 4672, 4673, 4648) -and  # Logon/logoff events
            $_.Message -match [regex]::Escape($Username)
        }
        
        if ($securityEvents) {
            # Flatten event objects to avoid deep nesting issues
            $flattenedSecurityEvents = $securityEvents | ForEach-Object {
                [PSCustomObject]@{
                    TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Level = $_.Level
                    LevelDisplayName = $_.LevelDisplayName
                    ProviderName = $_.ProviderName
                    Id = $_.Id
                    Message = $_.Message
                    MachineName = $_.MachineName
                    UserId = if ($_.UserId) { $_.UserId.ToString() } else { $null }
                    ProcessId = $_.ProcessId
                }
            }
            $eventLogs += $flattenedSecurityEvents
            Write-Host "   ✅ Captured $($securityEvents.Count) Security log entries" -ForegroundColor Green
        }
        
        if ($eventLogs.Count -gt 0) {
            ConvertTo-JsonSafe -InputObject $eventLogs -Depth 5 | Out-File "$outputBase`_EventLogs.json" -Encoding UTF8
            Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_EventLogs.json" -ForegroundColor Gray
        }
        else {
            Write-Host "   ⚠️  No relevant events found in last 24 hours" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "   ❌ Error capturing event logs: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""



    
    # Create summary report
    Write-Host "📋 Creating summary report..." -ForegroundColor Cyan
    $summaryFile = "$outputBase`_SUMMARY.txt"
    
    $summary = @"
═══════════════════════════════════════════════════════════════
Service Security Settings Diagnostic Report
═══════════════════════════════════════════════════════════════

Capture Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Capture Prefix: $OutputPrefix
Computer: $env:COMPUTERNAME
Domain: $env:USERDOMAIN

Target Configuration:
  Service Name: $ServiceName
  Username: $Username
  User SID: $userSidString
  Capture Category: $OutputPrefix

Files Generated (in SecurityDiagnostics\$OutputPrefix\):
  - $($timestamp)_UserInfo.json
  - $($timestamp)_SecurityPolicy.inf
  - $($timestamp)_UserRights.json
  - $($timestamp)_TargetUserRights.json
  - $($timestamp)_ServiceInfo.json
  - $($timestamp)_GroupPolicy.html
  - $($timestamp)_Registry.json
  - $($timestamp)_EventLogs.json
  - $($timestamp)_SUMMARY.txt

═══════════════════════════════════════════════════════════════

Service Status at Capture Time:
  $OutputPrefix

Folder Structure:
  - BeforeServiceAdded: Captures before service is created
  - AfterServiceFail: Captures when service exists but not running
  - AfterServiceOk: Captures when service is running successfully

Quick Diagnosis Steps:

1. Compare captures across folders:
   - BeforeServiceAdded vs AfterServiceFail: See what changed during installation
   - AfterServiceFail vs AfterServiceOk: See what fixed the issue
   - Check UserRights.json for SeServiceLogonRight changes
   - Check TargetUserRights.json to see if rights were granted

2. Review Group Policy report:
   - Open GroupPolicy.html in browser
   - Look for "User Rights Assignment" policies
   - Check if domain GPO is overriding local settings

3. Check Event Logs:
   - Review EventLogs.json for service start failures
   - Look for Event ID 7041 (service logon failure)
   - Look for Event ID 4625 (failed logon attempt)

4. Verify Security Policy:
   - Open SecurityPolicy.inf
   - Find [Privilege Rights] section
   - Confirm SeServiceLogonRight includes user SID: $userSidString

═══════════════════════════════════════════════════════════════
"@
    
    $summary | Out-File $summaryFile -Encoding UTF8
    Write-Host "   ✅ Summary report created" -ForegroundColor Green
    Write-Host "   💾 Saved: $OutputPrefix\$($timestamp)_SUMMARY.txt" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "✅ Security settings diagnostic export complete!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📂 All files saved to: $outputDir" -ForegroundColor Yellow
    Write-Host "📄 Review the SUMMARY file for next steps" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "💡 Automatic folder organization:" -ForegroundColor Cyan
    Write-Host "   BeforeServiceAdded - Service not installed yet" -ForegroundColor Gray
    Write-Host "   AfterServiceFail   - Service installed but not running" -ForegroundColor Gray
    Write-Host "   AfterServiceOk     - Service installed and running" -ForegroundColor Gray
    Write-Host ""
    Write-Host "💡 Workflow:" -ForegroundColor Cyan
    Write-Host "   1. Run this script (auto-detects service state)" -ForegroundColor Gray
    Write-Host "   2. Make changes (install service, grant rights, etc.)" -ForegroundColor Gray
    Write-Host "   3. Run this script again (captures new state)" -ForegroundColor Gray
    Write-Host "   4. Use Compare-SecurityCaptures.ps1 to see differences" -ForegroundColor Gray
    Write-Host ""
    
    # Open output directory
    Start-Process explorer.exe -ArgumentList $outputDir
}
catch {
    Write-Host ""
    Write-Host "❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   at line $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

