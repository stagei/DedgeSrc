<#
.SYNOPSIS
    Configures Chrome and Edge to allow automatic Kerberos/Negotiate authentication
    to DedgeAuth servers, eliminating the Windows Security credential prompt.

.DESCRIPTION
    Sets the AuthServerAllowlist registry policy for both Chrome and Edge so the
    browser sends Kerberos tickets automatically to trusted servers. Also adds
    the server to the Local Intranet zone for IE/Edge legacy compatibility.

    Requires elevation (Run as Administrator).

.PARAMETER Servers
    Comma-separated list of server hostnames or wildcard patterns to trust.
    Default: "dedge-server,*.DEDGE.fk.no"

.PARAMETER Remove
    Removes the registry keys instead of setting them (undo).

.EXAMPLE
    .\Enable-KerberosForBrowser.ps1
    # Enables Kerberos for default servers

.EXAMPLE
    .\Enable-KerberosForBrowser.ps1 -Servers "p-no1fkxprd-app,*.DEDGE.fk.no"
    # Enables Kerberos for production server

.EXAMPLE
    .\Enable-KerberosForBrowser.ps1 -Remove
    # Removes all Kerberos browser configuration
#>
param(
    [string]$Servers = "dedge-server,*.DEDGE.fk.no",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

# Require elevation
$currentPrincipal = [Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as administrator', then try again."
    exit 1
}

$registryPaths = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Google\Chrome";    Name = "Chrome" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge";   Name = "Edge" }
)

$intranetZonePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\dedge-server"

if ($Remove) {
    Write-Host "`n=== Removing Kerberos Browser Configuration ===" -ForegroundColor Yellow

    foreach ($entry in $registryPaths) {
        if (Test-Path $entry.Path) {
            $existing = Get-ItemProperty -Path $entry.Path -Name "AuthServerAllowlist" -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-ItemProperty -Path $entry.Path -Name "AuthServerAllowlist" -Force
                Write-Host "[Removed] $($entry.Name): AuthServerAllowlist" -ForegroundColor Green
            } else {
                Write-Host "[Skip]    $($entry.Name): AuthServerAllowlist not set" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[Skip]    $($entry.Name): Registry path does not exist" -ForegroundColor DarkGray
        }
    }

    if (Test-Path $intranetZonePath) {
        Remove-Item -Path $intranetZonePath -Recurse -Force
        Write-Host "[Removed] Intranet zone entry for dedge-server" -ForegroundColor Green
    } else {
        Write-Host "[Skip]    Intranet zone entry not present" -ForegroundColor DarkGray
    }

    Write-Host "`nDone. Restart your browser for changes to take effect." -ForegroundColor Cyan
    exit 0
}

Write-Host "`n=== Enabling Kerberos/Negotiate for Browser ===" -ForegroundColor Cyan
Write-Host "Servers: $Servers`n"

# Set AuthServerAllowlist for Chrome and Edge
foreach ($entry in $registryPaths) {
    if (-not (Test-Path $entry.Path)) {
        New-Item -Path $entry.Path -Force | Out-Null
    }
    Set-ItemProperty -Path $entry.Path -Name "AuthServerAllowlist" -Value $Servers -Type String
    Write-Host "[OK] $($entry.Name): AuthServerAllowlist = $Servers" -ForegroundColor Green
}

# Add to Local Intranet zone (zone 1) for IE/Edge legacy
if (-not (Test-Path $intranetZonePath)) {
    New-Item -Path $intranetZonePath -Force | Out-Null
}
Set-ItemProperty -Path $intranetZonePath -Name "http" -Value 1 -Type DWord
Write-Host "[OK] Intranet zone: http://dedge-server added to Local Intranet (zone 1)" -ForegroundColor Green

# Verify Kerberos TGT
Write-Host "`n=== Kerberos Ticket Status ===" -ForegroundColor Cyan
try {
    $klistOutput = & klist 2>&1
    $tgt = $klistOutput | Where-Object { $_ -match "krbtgt" }
    if ($tgt) {
        Write-Host "[OK] Kerberos TGT found:" -ForegroundColor Green
        $tgt | ForEach-Object { Write-Host "     $_" }
    } else {
        Write-Host "[WARN] No Kerberos TGT found. You may need to:" -ForegroundColor Yellow
        Write-Host "       1. Connect to VPN (if off-network)"
        Write-Host "       2. Lock and unlock your PC (refreshes tickets)"
        Write-Host "       3. Run: runas /netonly /user:DEDGE\$($env:USERNAME) cmd"
    }
} catch {
    Write-Host "[WARN] Could not run klist: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test SPN resolution
Write-Host "`n=== SPN Verification ===" -ForegroundColor Cyan
$firstServer = ($Servers -split ",")[0]
if ($firstServer -notmatch "\*") {
    try {
        $resolved = [System.Net.Dns]::GetHostEntry($firstServer)
        Write-Host "[OK] DNS: $firstServer -> $($resolved.AddressList[0])" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Cannot resolve $($firstServer) - check DNS/VPN" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "1. Chrome and Edge are now configured to send Kerberos tickets to: $Servers"
Write-Host "2. dedge-server is in the Local Intranet zone"
Write-Host "3. Restart your browser for changes to take effect"
Write-Host "4. Click 'Sign in with Windows' on the DedgeAuth login page -- no prompt expected`n"
Write-Host "To undo: .\Enable-KerberosForBrowser.ps1 -Remove`n" -ForegroundColor DarkGray
