<#
.SYNOPSIS
    Generates or imports an SSL/TLS certificate and binds it to an IIS site for HTTPS.

.DESCRIPTION
    Metadata-driven SSL certificate management for IIS, following the DedgeSign pattern.
    Certificate configuration is stored in a JSON config file (ssl-certificate.json)
    so settings are reusable and environment-specific.

    Supports three modes:
    - SelfSigned : Generate a self-signed certificate (test/dev environments)
    - Import     : Import an existing .pfx certificate (production / CA-signed)
    - Detect     : Find and bind an existing certificate from the local store by hostname

    On first run, creates ssl-certificate.json with defaults derived from the local
    machine (hostname, FQDN, organization). Edit this file to customize for your
    environment -- subsequent runs use these settings automatically.

    The certificate is created with:
    - Subject with Organization fields (O, OU, L, S, C) from config
    - Subject Alternative Names (DNS) for hostname, FQDN, and any extras
    - Server Authentication EKU (1.3.6.1.5.5.7.3.1)
    - RSA 4096-bit key with SHA-256 signature
    - Exportable private key
    - Configurable validity period

    After creation/import, the script can:
    - Bind to an IIS site on port 443 (replacing existing binding if -Force)
    - Trust locally (copy to Trusted Root CA store)
    - Export to .pfx for distribution to other servers
    - Clean up expired/old certificates for the same hostname

.PARAMETER Mode
    Certificate source mode:
    - SelfSigned : Generate a new self-signed certificate (default)
    - Import     : Import from a .pfx file
    - Detect     : Find an existing valid cert in LocalMachine\My by hostname match

.PARAMETER ConfigPath
    Path to ssl-certificate.json. Default: $PSScriptRoot\ssl-certificate.json

.PARAMETER ImportPfxPath
    Path to .pfx file to import. Required when Mode is Import.

.PARAMETER ImportPassword
    Password for the .pfx file. If not provided, you will be prompted.

.PARAMETER ExportPath
    Export the certificate to a .pfx file at this path after creation.

.PARAMETER ExportPassword
    Password for the exported .pfx file. If not provided, you will be prompted.

.PARAMETER TrustLocally
    Copy certificate to Trusted Root Certification Authorities (LocalMachine\Root).

.PARAMETER SkipIISBinding
    Generate/import the certificate without binding it to IIS.

.PARAMETER CleanupOld
    Remove expired or superseded certificates for the same hostname from LocalMachine\My.

.PARAMETER Force
    Replace an existing HTTPS binding on the same port without prompting.

.PARAMETER ShowConfig
    Display the current ssl-certificate.json configuration and exit.

.EXAMPLE
    .\New-IISSslCertificate.ps1
    First run creates ssl-certificate.json, then generates a self-signed cert and binds to IIS.

.EXAMPLE
    .\New-IISSslCertificate.ps1 -TrustLocally -CleanupOld
    Generate cert, trust it locally, and remove old certs for the same hostname.

.EXAMPLE
    .\New-IISSslCertificate.ps1 -Mode Import -ImportPfxPath "C:\certs\server.pfx" -Force
    Import a CA-signed certificate and bind it to IIS, replacing any existing binding.

.EXAMPLE
    .\New-IISSslCertificate.ps1 -Mode Detect -Force
    Find an existing valid cert in the store matching the configured hostname and bind it.

.EXAMPLE
    .\New-IISSslCertificate.ps1 -ShowConfig
    Display the current configuration file contents.

.EXAMPLE
    .\New-IISSslCertificate.ps1 -ExportPath "\\other-server\share\cert.pfx" -SkipIISBinding
    Generate cert and export it for use on another server.
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("SelfSigned", "Import", "Detect")]
    [string]$Mode = "SelfSigned",

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "",

    [Parameter(Mandatory = $false)]
    [string]$ImportPfxPath = "",

    [Parameter(Mandatory = $false)]
    [SecureString]$ImportPassword = $null,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = "",

    [Parameter(Mandatory = $false)]
    [SecureString]$ExportPassword = $null,

    [Parameter(Mandatory = $false)]
    [switch]$TrustLocally,

    [Parameter(Mandatory = $false)]
    [switch]$SkipIISBinding,

    [Parameter(Mandatory = $false)]
    [switch]$CleanupOld,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$ShowConfig
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

# ─── Config file path ───────────────────────────────────────────────────────────
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "ssl-certificate.json"
}

# ─── Initialize-Metadata ────────────────────────────────────────────────────────
# Creates ssl-certificate.json with sensible defaults if it doesn't exist.
# Pattern borrowed from DedgeSign's Initialize-Metadata / metadata-fka.json approach.
function Initialize-SslMetadata {
    param([string]$Path)

    if (Test-Path $Path -PathType Leaf) {
        Write-LogMessage "Using existing config: $($Path)" -Level INFO
        return
    }

    $hostname = $env:COMPUTERNAME.ToLower()
    $fqdn = try { [System.Net.Dns]::GetHostEntry($hostname).HostName.ToLower() } catch { $hostname }

    $config = [ordered]@{
        _comment       = "SSL certificate configuration. Edit these values for your environment."
        Hostname       = $hostname
        DnsNames       = @($hostname, $fqdn, "localhost")
        Organization   = "Dedge SA"
        OrgUnit        = "IT"
        Locality       = "Oslo"
        State          = "Oslo"
        Country        = "NO"
        ValidityYears  = 2
        KeyLength      = 4096
        HashAlgorithm  = "SHA256"
        FriendlyName   = "IIS SSL - $($hostname)"
        IISSiteName    = "Default Web Site"
        Port           = 443
    }

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    Write-LogMessage "Created SSL config at: $($Path)" -Level INFO
    Write-LogMessage "Review and edit the config, then run the script again." -Level INFO
    Write-LogMessage "Default values derived from this machine ($($hostname))." -Level INFO
}

# ─── Initialize-Prerequisites ────────────────────────────────────────────────────
# Checks that required PowerShell modules are available before proceeding.
# Pattern borrowed from DedgeSign's Initialize-Prerequisites.
function Initialize-SslPrerequisites {
    $missing = @()

    if (-not (Get-Module -ListAvailable -Name "WebAdministration") -and -not $SkipIISBinding) {
        $missing += "WebAdministration (IIS management module)"
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        $missing += "Administrator privileges (run as admin)"
    }

    if ($missing.Count -gt 0) {
        Write-LogMessage "Missing prerequisites:" -Level ERROR
        foreach ($item in $missing) {
            Write-LogMessage "  - $($item)" -Level ERROR
        }
        return $false
    }

    Write-LogMessage "Prerequisites OK (Admin: yes, IIS module: $(if ($SkipIISBinding) { 'skipped' } else { 'available' }))" -Level INFO
    return $true
}

# ─── Test-ExistingCertificate ────────────────────────────────────────────────────
# Like DedgeSign's Test-FileSignature: checks if a valid cert already exists
# for this hostname so we don't create unnecessary duplicates.
function Test-ExistingCertificate {
    param([string]$Hostname)

    $certs = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {
        $_.NotAfter -gt (Get-Date) -and
        ($_.Subject -match "CN=$([regex]::Escape($Hostname))" -or
         $_.DnsNameList.Unicode -contains $Hostname)
    } | Sort-Object NotAfter -Descending

    if ($certs.Count -gt 0) {
        $best = $certs[0]
        $daysLeft = ($best.NotAfter - (Get-Date)).Days
        Write-LogMessage "Found existing valid certificate for '$($Hostname)':" -Level INFO
        Write-LogMessage "  Thumbprint: $($best.Thumbprint)" -Level INFO
        Write-LogMessage "  Subject:    $($best.Subject)" -Level INFO
        Write-LogMessage "  Expires:    $($best.NotAfter.ToString('yyyy-MM-dd')) ($($daysLeft) days remaining)" -Level INFO
        return $best
    }
    return $null
}

# ─── Remove-ExpiredCertificates ──────────────────────────────────────────────────
# Cleans up expired or old certs for the same hostname.
function Remove-ExpiredCertificates {
    param(
        [string]$Hostname,
        [string]$CurrentThumbprint
    )

    $expired = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {
        $_.Thumbprint -ne $CurrentThumbprint -and
        ($_.Subject -match "CN=$([regex]::Escape($Hostname))") -and
        ($_.NotAfter -lt (Get-Date))
    }

    if ($expired.Count -eq 0) {
        Write-LogMessage "No expired certificates to clean up." -Level INFO
        return
    }

    foreach ($old in $expired) {
        Write-LogMessage "Removing expired cert: $($old.Thumbprint) (expired $($old.NotAfter.ToString('yyyy-MM-dd')))" -Level WARN
        Remove-Item "Cert:\LocalMachine\My\$($old.Thumbprint)" -Force
    }
    Write-LogMessage "Removed $($expired.Count) expired certificate(s)." -Level INFO
}

# ─── Build-SubjectString ────────────────────────────────────────────────────────
# Builds a proper X.500 subject string from config fields.
function Build-SubjectString {
    param([hashtable]$Config)

    $parts = @("CN=$($Config.Hostname)")
    if ($Config.OrgUnit)      { $parts += "OU=$($Config.OrgUnit)" }
    if ($Config.Organization) { $parts += "O=$($Config.Organization)" }
    if ($Config.Locality)     { $parts += "L=$($Config.Locality)" }
    if ($Config.State)        { $parts += "S=$($Config.State)" }
    if ($Config.Country)      { $parts += "C=$($Config.Country)" }

    return ($parts -join ", ")
}

# ─── Bind-ToIIS ──────────────────────────────────────────────────────────────────
# Binds a certificate to an IIS site on the configured HTTPS port.
function Bind-ToIIS {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$SiteName,
        [int]$Port
    )

    Import-Module WebAdministration -Force -ErrorAction Stop

    $bindingPath = "IIS:\SslBindings\0.0.0.0!$($Port)"
    $existingBinding = $null
    try { $existingBinding = Get-Item $bindingPath -ErrorAction SilentlyContinue } catch {}

    if ($existingBinding) {
        if ($existingBinding.Thumbprint -eq $Certificate.Thumbprint) {
            Write-LogMessage "Certificate is already bound to port $($Port). No changes needed." -Level INFO
            return
        }
        if ($Force) {
            Write-LogMessage "Replacing existing HTTPS binding on port $($Port) (old thumbprint: $($existingBinding.Thumbprint))..." -Level WARN
            Remove-Item $bindingPath -Force
        }
        else {
            Write-LogMessage "HTTPS binding already exists on port $($Port) (thumbprint: $($existingBinding.Thumbprint)). Use -Force to replace." -Level WARN
            return
        }
    }

    $site = Get-Website -Name $SiteName -ErrorAction Stop
    $httpsBinding = $site.Bindings.Collection | Where-Object {
        $_.protocol -eq "https" -and $_.bindingInformation -match ":$($Port):"
    }

    if (-not $httpsBinding) {
        New-WebBinding -Name $SiteName -Protocol "https" -Port $Port -IPAddress "*" -ErrorAction Stop
        Write-LogMessage "Added HTTPS binding on port $($Port) to '$($SiteName)'." -Level INFO
    }

    New-Item $bindingPath -Value $Certificate -Force | Out-Null
    Write-LogMessage "Certificate bound to 0.0.0.0:$($Port)." -Level INFO

    $verify = Get-Item $bindingPath -ErrorAction SilentlyContinue
    if ($verify -and $verify.Thumbprint -eq $Certificate.Thumbprint) {
        Write-LogMessage "IIS HTTPS binding verified." -Level INFO
    }
    else {
        Write-LogMessage "IIS HTTPS binding could not be verified. Check IIS Manager." -Level WARN
    }

    # Firewall rule for non-standard HTTPS ports
    if ($Port -ne 443) {
        $fwName = "IIS HTTPS Port $($Port)"
        $existing = Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
            Write-LogMessage "Firewall rule added: $($fwName)" -Level INFO
        }
    }
}

# ─── Trust-Locally ───────────────────────────────────────────────────────────────
function Add-ToTrustedRoot {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::Root,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

    $existing = $rootStore.Certificates | Where-Object { $_.Thumbprint -eq $Certificate.Thumbprint }
    if ($existing) {
        Write-LogMessage "Certificate already in Trusted Root store." -Level INFO
    }
    else {
        $rootStore.Add($Certificate)
        Write-LogMessage "Certificate added to Trusted Root Certification Authorities." -Level INFO
    }

    $rootStore.Close()
}

# ─── Export-Certificate ──────────────────────────────────────────────────────────
function Export-SslCertificate {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$Path,
        [SecureString]$Password
    )

    if (-not $Password) {
        $Password = Read-Host -Prompt "Enter export password for .pfx" -AsSecureString
    }

    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Export-PfxCertificate -Cert $Certificate -FilePath $Path -Password $Password | Out-Null
    Write-LogMessage "Certificate exported to: $($Path)" -Level INFO
}

# ═══════════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════════
try {
    # --- Step 1: Initialize metadata config ---
    Initialize-SslMetadata -Path $ConfigPath

    # --- Load config ---
    $configRaw = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $config = @{}
    $configRaw.PSObject.Properties | ForEach-Object { $config[$_.Name] = $_.Value }

    if ($ShowConfig) {
        Write-LogMessage "=== SSL Certificate Configuration ===" -Level INFO
        Write-LogMessage "  Config file: $($ConfigPath)" -Level INFO
        foreach ($key in ($config.Keys | Where-Object { $_ -ne '_comment' } | Sort-Object)) {
            $val = $config[$key]
            if ($val -is [array]) { $val = $val -join ", " }
            Write-LogMessage "  $($key): $($val)" -Level INFO
        }
        Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
        return
    }

    # --- Step 2: Check prerequisites ---
    $prereqOk = Initialize-SslPrerequisites
    if (-not $prereqOk) {
        throw "Prerequisites not met. See errors above."
    }

    # --- Step 3: Resolve settings from config ---
    $hostname      = ($config.Hostname ?? $env:COMPUTERNAME).ToLower()
    $dnsNames      = [System.Collections.Generic.List[string]]::new()
    $validityYears = [int]($config.ValidityYears ?? 2)
    $keyLength     = [int]($config.KeyLength ?? 4096)
    $hashAlg       = $config.HashAlgorithm ?? "SHA256"
    $friendlyName  = $config.FriendlyName ?? "IIS SSL - $($hostname)"
    $iisSiteName   = $config.IISSiteName ?? "Default Web Site"
    $port          = [int]($config.Port ?? 443)

    # Build SAN list from config + auto-detect
    foreach ($name in $config.DnsNames) {
        $lower = $name.Trim().ToLower()
        if ($lower -and -not $dnsNames.Contains($lower)) {
            $dnsNames.Add($lower)
        }
    }
    if (-not $dnsNames.Contains($hostname)) { $dnsNames.Insert(0, $hostname) }
    $fqdn = try { [System.Net.Dns]::GetHostEntry($hostname).HostName.ToLower() } catch { $null }
    if ($fqdn -and -not $dnsNames.Contains($fqdn)) { $dnsNames.Add($fqdn) }
    if (-not $dnsNames.Contains("localhost")) { $dnsNames.Add("localhost") }

    $cert = $null

    # --- Step 4: Acquire certificate based on mode ---
    switch ($Mode) {

        "SelfSigned" {
            $existingCert = Test-ExistingCertificate -Hostname $hostname
            if ($existingCert -and -not $Force) {
                $daysLeft = ($existingCert.NotAfter - (Get-Date)).Days
                Write-LogMessage "A valid certificate already exists ($($daysLeft) days remaining). Use -Force to create a new one." -Level WARN
                $cert = $existingCert
            }
            else {
                $subject = Build-SubjectString -Config $config
                $notAfter = (Get-Date).AddYears($validityYears)

                Write-LogMessage "Generating self-signed certificate:" -Level INFO
                Write-LogMessage "  Subject:     $($subject)" -Level INFO
                Write-LogMessage "  DNS names:   $($dnsNames -join ', ')" -Level INFO
                Write-LogMessage "  Key:         RSA $($keyLength)-bit, $($hashAlg)" -Level INFO
                Write-LogMessage "  Valid until: $($notAfter.ToString('yyyy-MM-dd'))" -Level INFO

                # EKU OID 1.3.6.1.5.5.7.3.1 = Server Authentication (SSL/TLS)
                $certParams = @{
                    Subject           = $subject
                    DnsName           = $dnsNames.ToArray()
                    CertStoreLocation = "Cert:\LocalMachine\My"
                    FriendlyName      = $friendlyName
                    NotAfter          = $notAfter
                    KeyAlgorithm      = "RSA"
                    KeyLength         = $keyLength
                    HashAlgorithm     = $hashAlg
                    KeyExportPolicy   = "Exportable"
                    KeyUsage          = @("DigitalSignature", "KeyEncipherment")
                    TextExtension     = @(
                        # OID 2.5.29.37 = Extended Key Usage
                        # 1.3.6.1.5.5.7.3.1 = Server Authentication (TLS/SSL)
                        "2.5.29.37={text}1.3.6.1.5.5.7.3.1"
                    )
                }

                $cert = New-SelfSignedCertificate @certParams
                Write-LogMessage "Certificate created. Thumbprint: $($cert.Thumbprint)" -Level INFO
            }
        }

        "Import" {
            if (-not $ImportPfxPath -or -not (Test-Path $ImportPfxPath -PathType Leaf)) {
                throw "Import mode requires -ImportPfxPath pointing to an existing .pfx file. Got: '$($ImportPfxPath)'"
            }

            if (-not $ImportPassword) {
                $ImportPassword = Read-Host -Prompt "Enter password for $($ImportPfxPath)" -AsSecureString
            }

            Write-LogMessage "Importing certificate from: $($ImportPfxPath)" -Level INFO
            $imported = Import-PfxCertificate -FilePath $ImportPfxPath -Password $ImportPassword `
                -CertStoreLocation "Cert:\LocalMachine\My" -Exportable
            $cert = Get-ChildItem "Cert:\LocalMachine\My\$($imported.Thumbprint)"
            Write-LogMessage "Imported certificate. Thumbprint: $($cert.Thumbprint), Subject: $($cert.Subject)" -Level INFO
        }

        "Detect" {
            $cert = Test-ExistingCertificate -Hostname $hostname
            if (-not $cert) {
                throw "No valid certificate found in LocalMachine\My for hostname '$($hostname)'. Use -Mode SelfSigned to create one."
            }
        }
    }

    if (-not $cert) {
        throw "No certificate was acquired. Check mode and parameters."
    }

    # --- Step 5: Trust locally ---
    if ($TrustLocally) {
        Add-ToTrustedRoot -Certificate $cert
    }

    # --- Step 6: Export ---
    if ($ExportPath) {
        Export-SslCertificate -Certificate $cert -Path $ExportPath -Password $ExportPassword
    }

    # --- Step 7: Bind to IIS ---
    if (-not $SkipIISBinding -and $iisSiteName) {
        Write-LogMessage "Binding certificate to IIS site '$($iisSiteName)' on port $($port)..." -Level INFO
        Bind-ToIIS -Certificate $cert -SiteName $iisSiteName -Port $port
    }
    elseif ($SkipIISBinding) {
        Write-LogMessage "Skipping IIS binding (-SkipIISBinding)." -Level INFO
    }

    # --- Step 8: Cleanup old certs ---
    if ($CleanupOld) {
        Remove-ExpiredCertificates -Hostname $hostname -CurrentThumbprint $cert.Thumbprint
    }

    # --- Summary ---
    Write-LogMessage "" -Level INFO
    Write-LogMessage "=== Certificate Summary ===" -Level INFO
    Write-LogMessage "  Mode:        $($Mode)" -Level INFO
    Write-LogMessage "  Thumbprint:  $($cert.Thumbprint)" -Level INFO
    Write-LogMessage "  Subject:     $($cert.Subject)" -Level INFO
    Write-LogMessage "  DNS names:   $(($cert.DnsNameList.Unicode | Select-Object -Unique) -join ', ')" -Level INFO
    Write-LogMessage "  Valid:       $($cert.NotBefore.ToString('yyyy-MM-dd')) to $($cert.NotAfter.ToString('yyyy-MM-dd'))" -Level INFO
    Write-LogMessage "  Key size:    $($cert.PublicKey.Key.KeySize)-bit" -Level INFO
    Write-LogMessage "  Store:       Cert:\LocalMachine\My" -Level INFO
    if ($TrustLocally)    { Write-LogMessage "  Trusted:     Yes (LocalMachine\Root)" -Level INFO }
    if ($ExportPath)      { Write-LogMessage "  Exported:    $($ExportPath)" -Level INFO }
    if (-not $SkipIISBinding -and $iisSiteName) {
        Write-LogMessage "  IIS site:    $($iisSiteName)" -Level INFO
        Write-LogMessage "  HTTPS URL:   https://$($hostname)/" -Level INFO
        if ($port -ne 443) {
            Write-LogMessage "  HTTPS port:  $($port)" -Level INFO
        }
    }
    Write-LogMessage "" -Level INFO

    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
