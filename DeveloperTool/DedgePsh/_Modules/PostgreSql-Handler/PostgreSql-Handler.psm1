<#
.SYNOPSIS
    Common PostgreSQL detection, connection, configuration, and query execution for Windows.

.DESCRIPTION
    Provides: psql path detection (with optional install), connection testing, query execution,
    database creation, Npgsql-style connection strings, and local server configuration
    (postgresql.conf, pg_hba.conf, firewall, service restart). Used by DedgeAuth and GenericLogHandler
    database setup scripts and DedgeAuth-AddAppSupport.

.EXAMPLE
    $binPath = Get-PostgreSqlPsqlPath -InstallIfMissing
    Test-PostgreSqlConnection -Host localhost -Port 8432 -User postgres -Password postgres -PsqlExe (Join-Path $binPath psql.exe)

.EXAMPLE
    $out = Invoke-PostgreSqlQuery -Host $host -Port 8432 -User postgres -Password $pwd -Database DedgeAuth -Query "SELECT app_id FROM apps;"
#>

# Require GlobalFunctions for Write-LogMessage (user rule: all logging via Write-LogMessage)
if (-not (Get-Module -Name GlobalFunctions)) {
    Import-Module GlobalFunctions -Force
}

# ─── Constants ─────────────────────────────────────────────────────────────
$script:PostgreSqlPossibleBinPaths = @(
    'C:\Program Files\PostgreSQL\*\bin\psql.exe',
    'C:\pgsql\bin\psql.exe',
    'C:\PostgreSQL\bin\psql.exe'
)

$script:PostgreSqlLocalHostNames = @('localhost', '127.0.0.1')

$script:PostgreSqlDataPathCandidates = @(
    'E:\pg',
    'E:\pg\data',
    'C:\Program Files\PostgreSQL\*\data',
    'C:\pgsql\data',
    'C:\PostgreSQL\data'
)

function Get-PostgreSqlPsqlPath {
    <#
    .SYNOPSIS
        Finds the directory containing psql.exe, optionally installing PostgreSQL if missing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$InstallIfMissing,
        [Parameter(Mandatory = $false)]
        [string]$AppName = 'PostgreSQL.18'
    )

    $binDir = $null
    foreach ($path in $script:PostgreSqlPossibleBinPaths) {
        $found = Get-Item $path -ErrorAction SilentlyContinue |
            Sort-Object { try { [int]($_.Directory.Parent.Name) } catch { 0 } } -Descending |
            Select-Object -First 1
        if ($found) {
            $binDir = $found.DirectoryName
            break
        }
    }
    if (-not $binDir) {
        $cmd = Get-Command psql -ErrorAction SilentlyContinue
        if ($cmd) {
            $binDir = Split-Path $cmd.Source -Parent
        }
    }
    if ($binDir) {
        return $binDir
    }
    if (-not $InstallIfMissing) {
        return $null
    }
    Write-LogMessage "PostgreSQL not found - installing via Install-WindowsApps..." -Level INFO
    Import-Module SoftwareUtils -Force -ErrorAction SilentlyContinue
    if (Get-Command Install-WindowsApps -ErrorAction SilentlyContinue) {
        Install-WindowsApps -AppName $AppName
    }
    # Re-detect
    foreach ($path in $script:PostgreSqlPossibleBinPaths) {
        $found = Get-Item $path -ErrorAction SilentlyContinue |
            Sort-Object { try { [int]($_.Directory.Parent.Name) } catch { 0 } } -Descending |
            Select-Object -First 1
        if ($found) {
            $binDir = $found.DirectoryName
            break
        }
    }
    if (-not $binDir) {
        $cmd = Get-Command psql -ErrorAction SilentlyContinue
        if ($cmd) {
            $binDir = Split-Path $cmd.Source -Parent
        }
    }
    if (-not $binDir) {
        Write-LogMessage "PostgreSQL still not found after installation attempt." -Level ERROR
        return $null
    }
    Write-LogMessage "PostgreSQL found at: $($binDir)" -Level INFO
    return $binDir
}

function Test-PostgreSqlLocalHost {
    <#
    .SYNOPSIS
        Returns $true if the given host is considered the local machine.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host
    )
    $names = @('localhost', '127.0.0.1', $env:COMPUTERNAME, "$($env:COMPUTERNAME).DEDGE.fk.no") + $script:PostgreSqlLocalHostNames
    $names = $names | Select-Object -Unique
    return ($names | Where-Object { $_ -ieq $Host }).Count -gt 0
}

function Get-PostgreSqlConfigPath {
    <#
    .SYNOPSIS
        Locates postgresql.conf (data directory) from known paths or PostgreSQL service registry.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    foreach ($candidate in $script:PostgreSqlDataPathCandidates) {
        try {
            $confFiles = Get-Item (Join-Path $candidate 'postgresql.conf') -ErrorAction SilentlyContinue
            if ($confFiles) {
                $path = ($confFiles | Sort-Object FullName -Descending | Select-Object -First 1).FullName
                if ($path) { return $path }
            }
        }
        catch {
            # Drive may not exist
        }
    }
    $pgServices = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue
    foreach ($svc in $pgServices) {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
        $imagePath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).ImagePath
        # -D "path" or -D path
        if ($imagePath -and $imagePath -match '-D\s+"?([^"]+)"?') {
            $dataDir = $Matches[1].Trim()
            $confCandidate = Join-Path $dataDir 'postgresql.conf'
            if (Test-Path $confCandidate -PathType Leaf) {
                return $confCandidate
            }
        }
    }
    return $null
}

function Test-PostgreSqlConnection {
    <#
    .SYNOPSIS
        Tests connectivity by running SELECT 1. Returns $true if successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'psql and PGPASSWORD require plain string.')]
        [string]$Password,
        [Parameter(Mandatory = $false)]
        [string]$Database = 'postgres',
        [Parameter(Mandatory = $false)]
        [string]$PsqlExe
    )
    if (-not $PsqlExe) {
        $binDir = Get-PostgreSqlPsqlPath
        if (-not $binDir) { return $false }
        $PsqlExe = Join-Path $binDir 'psql.exe'
    }
    if (-not (Test-Path $PsqlExe -PathType Leaf)) {
        Write-LogMessage "psql not found at: $($PsqlExe)" -Level ERROR
        return $false
    }
    $prevPwd = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        $null = & $PsqlExe -h $Host -p $Port -U $User -d $Database -t -c 'SELECT 1' 2>&1
        return $LASTEXITCODE -eq 0
    }
    finally {
        $env:PGPASSWORD = $prevPwd
    }
}

function Invoke-PostgreSqlQuery {
    <#
    .SYNOPSIS
        Executes a query via psql. Returns trimmed output string, or $null on error.
    .PARAMETER Unattended
        If set, errors are not written to host; only return value indicates success/failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'psql PGPASSWORD requires plain string.')]
        [string]$Password,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $false)]
        [string]$PsqlExe,
        [Parameter(Mandatory = $false)]
        [switch]$Unattended
    )
    if (-not $PsqlExe) {
        $binDir = Get-PostgreSqlPsqlPath
        if (-not $binDir) { return $null }
        $PsqlExe = Join-Path $binDir 'psql.exe'
    }
    if (-not (Test-Path $PsqlExe -PathType Leaf)) {
        if (-not $Unattended) {
            Write-LogMessage "psql not found at: $($PsqlExe)" -Level ERROR
        }
        return $null
    }
    $prevPwd = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        $result = & $PsqlExe -h $Host -p $Port -U $User -d $Database -t -A -c $Query 2>&1
        if ($LASTEXITCODE -ne 0) {
            if (-not $Unattended) {
                Write-LogMessage "SQL Error: $($result | Out-String)" -Level ERROR
            }
            return $null
        }
        return ($result | Out-String).Trim()
    }
    finally {
        $env:PGPASSWORD = $prevPwd
    }
}

function New-PostgreSqlDatabaseIfNotExists {
    <#
    .SYNOPSIS
        Creates the database if it does not exist. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'psql PGPASSWORD requires plain string.')]
        [string]$Password,
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$PsqlExe
    )
    if (-not $PsqlExe) {
        $binDir = Get-PostgreSqlPsqlPath
        if (-not $binDir) { throw 'PostgreSQL psql not found.' }
        $PsqlExe = Join-Path $binDir 'psql.exe'
    }
    $prevPwd = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        $checkQuery = "SELECT 1 FROM pg_database WHERE datname = '$($DatabaseName -replace "'", "''")'"
        $exists = & $PsqlExe -h $Host -p $Port -U $User -d postgres -t -c $checkQuery 2>$null
        if ($exists -match '1') {
            Write-LogMessage "Database '$($DatabaseName)' already exists." -Level INFO
            return
        }
        Write-LogMessage "Creating database '$($DatabaseName)'..." -Level INFO
        $safeName = $DatabaseName -replace '"', '""'
        $createSql = "CREATE DATABASE `"$safeName`""
        & $PsqlExe -h $Host -p $Port -U $User -d postgres -c $createSql 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Failed to create database '$($DatabaseName)'." -Level ERROR
            throw "Create database failed."
        }
        Write-LogMessage "Database '$($DatabaseName)' created successfully." -Level INFO
    }
    finally {
        $env:PGPASSWORD = $prevPwd
    }
}

function Get-PostgreSqlConnectionString {
    <#
    .SYNOPSIS
        Builds an Npgsql-style connection string (Host;Port;Database;Username;Password).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Connection string format requires plain string.')]
        [string]$Password
    )
    return "Host=$($Host);Port=$($Port);Database=$($Database);Username=$($User);Password=$($Password)"
}

function Set-PostgreSqlLocalConfig {
    <#
    .SYNOPSIS
        For a local PostgreSQL: ensures listen_addresses='*', port, pg_hba remote rule, firewall, and restarts service if needed.
    .PARAMETER PgHbaComment
        Comment to add in pg_hba.conf entry (e.g. "added by DedgeAuth-DatabaseSetup").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Used only for connection test.')]
        [string]$Password,
        [Parameter(Mandatory = $false)]
        [string]$PgHbaComment = 'PostgreSql-Handler'
    )
    $pgConfPath = Get-PostgreSqlConfigPath
    if (-not $pgConfPath) {
        Write-LogMessage "postgresql.conf not found - cannot verify port configuration." -Level WARN
        return
    }
    Write-LogMessage "Found postgresql.conf at: $($pgConfPath)" -Level INFO
    $confContent = Get-Content $pgConfPath -Raw
    $needsRestart = $false

    # listen_addresses
    $currentListen = $null
    if ($confContent -match "(?m)^\s*listen_addresses\s*=\s*'([^']*)'") { $currentListen = $Matches[1] }
    elseif ($confContent -match "(?m)^#\s*listen_addresses\s*=\s*'([^']*)'") { $currentListen = $Matches[1] }
    if ($null -eq $currentListen -or $currentListen -ne '*') {
        Write-LogMessage "listen_addresses is '$($currentListen ?? 'commented out')' — changing to '*' for remote access..." -Level INFO
        $confContent = $confContent -replace "(?m)^#?\s*listen_addresses\s*=\s*'[^']*'", "listen_addresses = '*'"
        $needsRestart = $true
    }
    else {
        Write-LogMessage "listen_addresses already set to '*'." -Level INFO
    }

    # port
    $currentPort = $null
    if ($confContent -match '(?m)^\s*port\s*=\s*(\d+)') { $currentPort = [int]$Matches[1] }
    elseif ($confContent -match '(?m)^#\s*port\s*=\s*(\d+)') { $currentPort = [int]$Matches[1] }
    if ($null -ne $currentPort -and $currentPort -ne $Port) {
        Write-LogMessage "Current port is $($currentPort), changing to $($Port)..." -Level INFO
        $confContent = $confContent -replace '(?m)^#?\s*port\s*=\s*\d+', "port = $($Port)"
        $needsRestart = $true
    }
    elseif ($null -ne $currentPort) {
        Write-LogMessage "PostgreSQL already configured on port $($currentPort)." -Level INFO
    }
    else {
        Write-LogMessage "Could not determine current port from postgresql.conf." -Level WARN
    }

    if ($needsRestart) {
        Set-Content -Path $pgConfPath -Value $confContent -Encoding UTF8 -Force
        Write-LogMessage "postgresql.conf updated." -Level INFO
    }

    # pg_hba.conf
    $pgDataDir = Split-Path $pgConfPath -Parent
    $pgHbaPath = Join-Path $pgDataDir 'pg_hba.conf'
    if (Test-Path $pgHbaPath) {
        $hbaContent = Get-Content $pgHbaPath -Raw
        if ($hbaContent -match '(?m)^(?!#)host\s+\S+\s+\S+\s+0\.0\.0\.0\/0') {
            Write-LogMessage "pg_hba.conf already allows remote IPv4 connections." -Level INFO
        }
        else {
            Write-LogMessage "Adding remote access rule to pg_hba.conf..." -Level INFO
            $hbaEntry = "`n# Allow remote connections ($($PgHbaComment))`nhost    all    all    0.0.0.0/0    scram-sha-256`n"
            Add-Content -Path $pgHbaPath -Value $hbaEntry -Encoding UTF8
            Write-LogMessage "pg_hba.conf updated — remote IPv4 connections allowed." -Level INFO
            $needsRestart = $true
        }
    }
    else {
        Write-LogMessage "pg_hba.conf not found at $($pgHbaPath)." -Level WARN
    }

    if ($needsRestart) {
        $pgService = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pgService) {
            Write-LogMessage "Restarting service '$($pgService.Name)' to apply configuration..." -Level INFO
            Restart-Service -Name $pgService.Name -Force
            $pgService.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
            Write-LogMessage "Service '$($pgService.Name)' restarted on port $($Port)." -Level INFO
        }
        else {
            Write-LogMessage "No PostgreSQL service found. Please restart PostgreSQL manually." -Level WARN
        }
    }

    # Firewall
    Write-LogMessage "Checking firewall rule for PostgreSQL port $($Port)..." -Level INFO
    try {
        $ruleName = "PostgreSQL Remote Access (port $($Port))"
        $portFilters = Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -eq $Port -and $_.Protocol -eq 'TCP' }
        $existingRule = $null
        if ($portFilters) {
            $existingRule = $portFilters | Get-NetFirewallRule -ErrorAction SilentlyContinue |
                Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' } |
                Select-Object -First 1
        }
        if ($existingRule) {
            Write-LogMessage "Firewall rule already exists: $($existingRule.DisplayName)" -Level INFO
        }
        else {
            $null = New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -ErrorAction Stop
            Write-LogMessage "Firewall rule created successfully." -Level INFO
        }
    }
    catch {
        Write-LogMessage "Could not configure firewall rule: $($_.Exception.Message)" -Level WARN
    }
}

function Invoke-PostgreSqlEnsureLocalReady {
    <#
    .SYNOPSIS
        When host is local: test connectivity (desired port then default 5432), then apply local config (port, listen_addresses, pg_hba, firewall, restart).
        Does nothing if host is not local.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Delegates to Test-PostgreSqlConnection and Set-PostgreSqlLocalConfig.')]
        [string]$Password,
        [Parameter(Mandatory = $false)]
        [string]$PsqlExe,
        [Parameter(Mandatory = $false)]
        [string]$PgHbaComment = 'PostgreSql-Handler'
    )
    if (-not (Test-PostgreSqlLocalHost -Host $Host)) {
        return
    }
    if (-not $PsqlExe) {
        $binDir = Get-PostgreSqlPsqlPath
        if (-not $binDir) { return }
        $PsqlExe = Join-Path $binDir 'psql.exe'
    }
    $testHost = 'localhost'
    $defaultPort = 5432
    Write-LogMessage "Testing local PostgreSQL connectivity..." -Level INFO
    $ok = Test-PostgreSqlConnection -Host $testHost -Port $Port -User $User -Password $Password -PsqlExe $PsqlExe
    if (-not $ok) {
        Write-LogMessage "Port $($Port) not responding. Trying default port $($defaultPort)..." -Level INFO
        $ok = Test-PostgreSqlConnection -Host $testHost -Port $defaultPort -User $User -Password $Password -PsqlExe $PsqlExe
        if (-not $ok) {
            Write-LogMessage "PostgreSQL not responding on port $($defaultPort) or $($Port)." -Level ERROR
            throw 'Local PostgreSQL not reachable.'
        }
        Write-LogMessage "PostgreSQL responding on default port $($defaultPort). Will reconfigure to $($Port)." -Level INFO
    }
    else {
        Write-LogMessage "PostgreSQL already responding on port $($Port)." -Level INFO
    }
    Set-PostgreSqlLocalConfig -Port $Port -User $User -Password $Password -PgHbaComment $PgHbaComment
}

function Test-PostgreSqlSetup {
    <#
    .SYNOPSIS
        Runs a full diagnostic of PostgreSQL installation, service, config, firewall, and connectivity.
    .OUTPUTS
        PSCustomObject with .Issues (string[]) and .Passed (bool).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'psql PGPASSWORD requires plain string.')]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Port = 8432,
        [Parameter(Mandatory = $false)]
        [string]$Host = 'localhost',
        [Parameter(Mandatory = $false)]
        [string]$User = 'postgres',
        [Parameter(Mandatory = $false)]
        [string]$Password = 'postgres',
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName = $null
    )
    $issues = [System.Collections.ArrayList]@()
    $psqlExe = $null
    $binDir = Get-PostgreSqlPsqlPath
    if ($binDir) {
        $psqlExe = Join-Path $binDir 'psql.exe'
    }

    # 1. Installation
    Write-LogMessage "1. INSTALLATION" -Level INFO
    if ($psqlExe -and (Test-Path $psqlExe -PathType Leaf)) {
        Write-LogMessage "   psql.exe: $($psqlExe)" -Level INFO
        $version = & $psqlExe --version 2>&1
        Write-LogMessage "   Version: $($version)" -Level INFO
    }
    else {
        Write-LogMessage "   psql.exe: NOT FOUND" -Level ERROR
        $null = $issues.Add('PostgreSQL binaries not found')
    }
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $pgInstalled = $regPaths | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -match 'PostgreSQL' } |
        Select-Object DisplayName, DisplayVersion, InstallLocation
    if ($pgInstalled) {
        foreach ($pg in $pgInstalled) {
            Write-LogMessage "   Registry: $($pg.DisplayName) v$($pg.DisplayVersion)" -Level INFO
        }
    }
    else {
        Write-LogMessage "   Registry: No PostgreSQL in Add/Remove Programs" -Level WARN
    }

    # 2. Service
    Write-LogMessage "2. SERVICE" -Level INFO
    $pgServices = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue
    if ($pgServices) {
        foreach ($svc in $pgServices) {
            $level = if ($svc.Status -eq 'Running') { 'INFO' } else { 'ERROR' }
            Write-LogMessage "   Service: $($svc.Name) - $($svc.Status)" -Level $level
            if ($svc.Status -ne 'Running') {
                $null = $issues.Add("PostgreSQL service '$($svc.Name)' is not running (Status: $($svc.Status))")
            }
        }
    }
    else {
        Write-LogMessage "   Service: NO PostgreSQL service found" -Level ERROR
        $null = $issues.Add('No PostgreSQL service found')
    }

    # 3. Data directory & config
    Write-LogMessage "3. DATA DIRECTORY & CONFIGURATION" -Level INFO
    $pgConfPath = Get-PostgreSqlConfigPath
    if ($pgConfPath) {
        $dataDir = Split-Path $pgConfPath -Parent
        Write-LogMessage "   Data dir: $($dataDir)" -Level INFO
        Write-LogMessage "   Config file: $($pgConfPath)" -Level INFO
        $confContent = Get-Content $pgConfPath -Raw
        $configuredPort = $null
        if ($confContent -match '(?m)^\s*port\s*=\s*(\d+)') { $configuredPort = [int]$Matches[1] }
        elseif ($confContent -match '(?m)^#\s*port\s*=\s*(\d+)') { $configuredPort = [int]$Matches[1]; Write-LogMessage "   Port: $($configuredPort) (COMMENTED OUT)" -Level WARN }
        if ($null -ne $configuredPort) {
            if ($configuredPort -ne $Port) {
                Write-LogMessage "   Port: $($configuredPort) (EXPECTED: $($Port))" -Level ERROR
                $null = $issues.Add("PostgreSQL port is $configuredPort, expected $Port")
            }
            else {
                Write-LogMessage "   Port: $($configuredPort) (OK)" -Level INFO
            }
        }
        else {
            Write-LogMessage "   Port: Not found in config (default: 5432)" -Level WARN
            $null = $issues.Add('Port not explicitly set in postgresql.conf')
        }
        $listenAddr = $null
        if ($confContent -match "(?m)^\s*listen_addresses\s*=\s*'([^']*)'") { $listenAddr = $Matches[1] }
        elseif ($confContent -match "(?m)^#\s*listen_addresses\s*=\s*'([^']*)'") { $listenAddr = $Matches[1]; Write-LogMessage "   Listen: commented out (localhost only)" -Level ERROR; $null = $issues.Add('listen_addresses commented out - remote connections will fail') }
        if ($null -ne $listenAddr -and $listenAddr -ne '*' -and $listenAddr -notmatch '0\.0\.0\.0') {
            Write-LogMessage "   Listen: $($listenAddr)" -Level WARN
            $null = $issues.Add("listen_addresses is '$listenAddr' - remote connections may not work")
        }
        elseif ($null -ne $listenAddr) {
            Write-LogMessage "   Listen: $($listenAddr)" -Level INFO
        }
        $hbaPath = Join-Path $dataDir 'pg_hba.conf'
        if (Test-Path $hbaPath -PathType Leaf) {
            $hbaContent = Get-Content $hbaPath
            $remoteRules = $hbaContent | Where-Object { $_ -match '^\s*(host|hostssl)\s+' -and $_ -notmatch '^\s*#' }
            Write-LogMessage "   pg_hba.conf: $($remoteRules.Count) host rules found" -Level INFO
        }
    }
    else {
        Write-LogMessage "   Config file: NOT FOUND" -Level ERROR
        $null = $issues.Add("postgresql.conf not found")
    }

    # 4. Listening ports
    Write-LogMessage "4. LISTENING PORTS" -Level INFO
    $pgListening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in @(5432, 8432, $Port) } | Sort-Object LocalPort
    if ($pgListening) {
        foreach ($conn in $pgListening) {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            Write-LogMessage "   Port $($conn.LocalPort): Listening (PID $($conn.OwningProcess) - $($proc.ProcessName))" -Level INFO
        }
    }
    else {
        Write-LogMessage "   Port $($Port): NOT listening" -Level ERROR
        $null = $issues.Add("PostgreSQL is not listening on port $Port")
    }

    # 5. Firewall
    Write-LogMessage "5. FIREWALL RULES" -Level INFO
    $fwRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'PostgreSQL|postgres' -or $_.DisplayName -match "port\s*$Port" }
    if ($fwRules) {
        foreach ($rule in $fwRules) {
            Write-LogMessage "   Rule: $($rule.DisplayName) | Enabled: $($rule.Enabled)" -Level INFO
        }
    }
    else {
        Write-LogMessage "   No PostgreSQL firewall rules found" -Level ERROR
        $null = $issues.Add('No firewall rule for PostgreSQL')
    }

    # 6. Connectivity
    Write-LogMessage "6. CONNECTIVITY" -Level INFO
    if ($psqlExe) {
        $ok = Test-PostgreSqlConnection -Host $Host -Port $Port -User $User -Password $Password -PsqlExe $psqlExe
        if ($ok) {
            Write-LogMessage "   $($Host):$($Port) Connected OK" -Level INFO
        }
        else {
            Write-LogMessage "   $($Host):$($Port) FAILED" -Level ERROR
            $null = $issues.Add("Cannot connect to $($Host):$Port")
        }
        if ($Port -ne 5432) {
            $okDefault = Test-PostgreSqlConnection -Host $Host -Port 5432 -User $User -Password $Password -PsqlExe $psqlExe
            if ($okDefault) {
                Write-LogMessage "   $($Host):5432 Connected (still on default port!)" -Level WARN
                $null = $issues.Add('PostgreSQL still responding on default port 5432')
            }
        }
        $hostname = $env:COMPUTERNAME
        $okHost = Test-PostgreSqlConnection -Host $hostname -Port $Port -User $User -Password $Password -PsqlExe $psqlExe
        if ($okHost) {
            Write-LogMessage "   $($hostname):$($Port) Connected OK" -Level INFO
        }
        else {
            Write-LogMessage "   $($hostname):$($Port) FAILED" -Level ERROR
            $null = $issues.Add("Cannot connect via hostname $($hostname):$Port")
        }
        if (-not [string]::IsNullOrWhiteSpace($DatabaseName)) {
            $exists = Invoke-PostgreSqlQuery -Host $Host -Port $Port -User $User -Password $Password -Database postgres -Query "SELECT 1 FROM pg_database WHERE datname = '$($DatabaseName -replace "'", "''")'" -PsqlExe $psqlExe -Unattended
            if ($exists -match '1') {
                Write-LogMessage "   Database '$($DatabaseName)': EXISTS" -Level INFO
            }
            else {
                Write-LogMessage "   Database '$($DatabaseName)': NOT FOUND" -Level ERROR
                $null = $issues.Add("Database '$DatabaseName' does not exist")
            }
        }
    }
    else {
        Write-LogMessage "   Skipped - psql not found" -Level WARN
    }

    $passed = $issues.Count -eq 0
    Write-LogMessage "RESULT: $(if ($passed) { 'All checks passed' } else { "$($issues.Count) issue(s) found" })" -Level $(if ($passed) { 'INFO' } else { 'ERROR' })
    return [PSCustomObject]@{ Issues = [string[]]$issues; Passed = $passed }
}

function Repair-PostgreSqlInstall {
    <#
    .SYNOPSIS
        Repairs a broken PostgreSQL installation: initdb, configure conf/hba, register and start service, firewall.
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'initdb/pg require plain string.')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DataDir = 'E:\pg',
        [Parameter(Mandatory = $false)]
        [int]$Port = 8432,
        [Parameter(Mandatory = $false)]
        [string]$SuperPassword = 'postgres',
        [Parameter(Mandatory = $false)]
        [string]$ServiceName = 'postgresql-x64-18'
    )
    $binDir = $null
    $found = Get-Item 'C:\Program Files\PostgreSQL\*\bin\initdb.exe' -ErrorAction SilentlyContinue |
        Sort-Object { try { [int]($_.Directory.Parent.Name) } catch { 0 } } -Descending |
        Select-Object -First 1
    if ($found) { $binDir = $found.DirectoryName }
    if (-not $binDir) {
        $binDir = Get-PostgreSqlPsqlPath
    }
    if (-not $binDir -or -not (Test-Path (Join-Path $binDir 'initdb.exe') -PathType Leaf)) {
        Write-LogMessage "PostgreSQL binaries (initdb) not found. Install PostgreSQL first." -Level ERROR
        throw 'PostgreSQL binaries not found.'
    }
    $initdbExe = Join-Path $binDir 'initdb.exe'
    $pgCtlExe = Join-Path $binDir 'pg_ctl.exe'
    $psqlExe = Join-Path $binDir 'psql.exe'
    Write-LogMessage "PostgreSQL bin: $($binDir)" -Level INFO

    $existingSvc = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue
    if ($existingSvc) {
        Write-LogMessage "Stopping and unregistering existing service: $($existingSvc.Name)..." -Level INFO
        Stop-Service -Name $existingSvc.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        & $pgCtlExe unregister -N $existingSvc.Name 2>&1 | Out-Null
    }

    if ($DataDir.StartsWith('E:\') -and -not (Test-Path 'E:\')) {
        $DataDir = 'C:\Program Files\PostgreSQL\18\data'
        Write-LogMessage "E:\ not found - using: $($DataDir)" -Level WARN
    }

    if (Test-Path (Join-Path $DataDir 'postgresql.conf') -PathType Leaf) {
        Write-LogMessage "Data directory already initialized at: $($DataDir)" -Level INFO
    }
    else {
        if (-not (Test-Path $DataDir)) {
            New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
            Write-LogMessage "Created data directory: $($DataDir)" -Level INFO
        }
        $dirContents = Get-ChildItem $DataDir -ErrorAction SilentlyContinue
        if ($dirContents.Count -gt 0) {
            Write-LogMessage "Data directory not empty. Clearing..." -Level WARN
            Remove-Item "$DataDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-LogMessage "Initializing database cluster..." -Level INFO
        $pwFile = Join-Path $env:TEMP 'pg_initpw.txt'
        Set-Content -Path $pwFile -Value $SuperPassword -Encoding ASCII -Force
        $initResult = & $initdbExe --pgdata="$DataDir" --username=postgres --pwfile="$pwFile" --encoding=UTF8 --locale=en_US.UTF-8 --auth=scram-sha-256 2>&1
        Remove-Item $pwFile -Force -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "initdb failed: $($initResult | Out-String)" -Level ERROR
            throw 'initdb failed.'
        }
        Write-LogMessage "Database cluster initialized." -Level INFO
    }

    $pgConfPath = Join-Path $DataDir 'postgresql.conf'
    $hbaConfPath = Join-Path $DataDir 'pg_hba.conf'
    if (Test-Path $pgConfPath) {
        $confContent = Get-Content $pgConfPath -Raw
        if ($confContent -match '(?m)^\s*port\s*=') { $confContent = $confContent -replace '(?m)^\s*port\s*=\s*\d+', "port = $Port" }
        elseif ($confContent -match '(?m)^#\s*port\s*=') { $confContent = $confContent -replace '(?m)^#\s*port\s*=\s*\d+', "port = $Port" }
        else { $confContent += "`nport = $Port`n" }
        if ($confContent -match "(?m)^\s*listen_addresses\s*=") { $confContent = $confContent -replace "(?m)^\s*listen_addresses\s*=\s*'[^']*'", "listen_addresses = '*'" }
        elseif ($confContent -match "(?m)^#\s*listen_addresses\s*=") { $confContent = $confContent -replace "(?m)^#\s*listen_addresses\s*=\s*'[^']*'", "listen_addresses = '*'" }
        else { $confContent += "`nlisten_addresses = '*'`n" }
        Set-Content -Path $pgConfPath -Value $confContent -Encoding UTF8 -Force
        Write-LogMessage "postgresql.conf: port=$($Port), listen_addresses='*'" -Level INFO
    }
    if (Test-Path $hbaConfPath) {
        $hbaContent = Get-Content $hbaConfPath -Raw
        if ($hbaContent -notmatch 'host\s+all\s+all\s+0\.0\.0\.0/0') {
            $hbaContent += "`n# Allow remote connections`nhost    all    all    0.0.0.0/0    scram-sha-256`nhost    all    all    ::/0    scram-sha-256`n"
            Set-Content -Path $hbaConfPath -Value $hbaContent -Encoding UTF8 -Force
            Write-LogMessage "pg_hba.conf: added remote access rules" -Level INFO
        }
    }

    Write-LogMessage "Registering Windows service '$($ServiceName)'..." -Level INFO
    & $pgCtlExe register -N $ServiceName -D "$DataDir" -S auto 2>&1 | Out-Null
    Write-LogMessage "Starting service..." -Level INFO
    Start-Service -Name $ServiceName -ErrorAction Stop
    $svc = Get-Service -Name $ServiceName
    $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-LogMessage "Service '$($ServiceName)' is running." -Level INFO

    try {
        $ruleName = "PostgreSQL Remote Access (port $($Port))"
        $existingRule = Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $Port -and $_.Protocol -eq 'TCP' } | Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' } | Select-Object -First 1
        if (-not $existingRule) {
            $null = New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -ErrorAction Stop
            Write-LogMessage "Firewall rule created: $($ruleName)" -Level INFO
        }
    }
    catch {
        Write-LogMessage "Firewall: $($_.Exception.Message)" -Level WARN
    }

    Start-Sleep -Seconds 2
    $env:PGPASSWORD = $SuperPassword
    $ok = Test-PostgreSqlConnection -Host localhost -Port $Port -User postgres -Password $SuperPassword -PsqlExe $psqlExe
    $env:PGPASSWORD = $null
    if ($ok) {
        Write-LogMessage "Verification: localhost:$($Port) OK" -Level INFO
    }
    else {
        Write-LogMessage "Verification: localhost:$($Port) failed" -Level ERROR
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Backup-PostgreSqlDatabase / Restore-PostgreSqlDatabase
# ═══════════════════════════════════════════════════════════════════════════════
# Reusable for any PostgreSQL database. Call from project-specific scripts that
# load connection details from a config (e.g. DatabaseConfig.ps1).
# ═══════════════════════════════════════════════════════════════════════════════

function Backup-PostgreSqlDatabase {
    <#
    .SYNOPSIS
        Creates a backup of a PostgreSQL database using pg_dump.
    .DESCRIPTION
        Writes a backup to OutputPath. Format Custom (-Fc) is default for use with
        pg_restore; use Plain for human-readable SQL.
    .PARAMETER Format
        Custom = binary archive for pg_restore (default). Plain = SQL text file.
    .OUTPUTS
        Full path to the created backup file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'pg_dump PGPASSWORD requires plain string.')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [string]$Password,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Custom', 'Plain')]
        [string]$Format = 'Custom',
        [Parameter(Mandatory = $false)]
        [string]$PsqlExe
    )
    $binDir = if ($PsqlExe) { Split-Path $PsqlExe -Parent } else { Get-PostgreSqlPsqlPath }
    if (-not $binDir) { throw 'PostgreSQL bin path not found. Specify -PsqlExe or install PostgreSQL.' }
    $pgDumpExe = Join-Path $binDir 'pg_dump.exe'
    if (-not (Test-Path $pgDumpExe -PathType Leaf)) {
        Write-LogMessage "pg_dump not found at: $($pgDumpExe)" -Level ERROR
        throw "pg_dump not found."
    }
    $outDir = Split-Path $OutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        Write-LogMessage "Created backup directory: $($outDir)" -Level INFO
    }
    $formatArg = if ($Format -eq 'Plain') { '-Fp' } else { '-Fc' }
    $ext = if ($Format -eq 'Plain') { '.sql' } else { '.backup' }
    $outStr = [string]$OutputPath
    if (-not $outStr.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
        $OutputPath = $outStr.TrimEnd('.') + $ext
    }
    Write-LogMessage "Backing up database '$($Database)' to $($OutputPath) (Format: $($Format))..." -Level INFO
    $prevPwd = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        & $pgDumpExe -h $Host -p $Port -U $User -d $Database $formatArg -f $OutputPath 2>&1 | ForEach-Object { Write-LogMessage "pg_dump: $_" -Level DEBUG }
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "pg_dump failed (exit code $($LASTEXITCODE))." -Level ERROR
            throw "Backup failed."
        }
        Write-LogMessage "Backup completed: $($OutputPath)" -Level INFO
        return $OutputPath
    }
    finally {
        $env:PGPASSWORD = $prevPwd
    }
}

function Restore-PostgreSqlDatabase {
    <#
    .SYNOPSIS
        Restores a PostgreSQL database from a backup created by pg_dump.
    .DESCRIPTION
        InputPath can be a .backup (custom format) or .sql (plain) file.
        If CreateDatabaseIfNotExists is set, the database is created before restore.
        For custom format, --clean --if-exists drops existing objects before restore.
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'pg_restore/psql PGPASSWORD requires plain string.')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [string]$Password,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $false)]
        [switch]$CreateDatabaseIfNotExists,
        [Parameter(Mandatory = $false)]
        [switch]$Clean,
        [Parameter(Mandatory = $false)]
        [string]$PsqlExe
    )
    if (-not (Test-Path $InputPath -PathType Leaf)) {
        Write-LogMessage "Backup file not found: $($InputPath)" -Level ERROR
        throw "Backup file not found."
    }
    $binDir = if ($PsqlExe) { Split-Path $PsqlExe -Parent } else { Get-PostgreSqlPsqlPath }
    if (-not $binDir) { throw 'PostgreSQL bin path not found. Specify -PsqlExe or install PostgreSQL.' }
    $psqlExe = Join-Path $binDir 'psql.exe'
    $pgRestoreExe = Join-Path $binDir 'pg_restore.exe'
    if (-not (Test-Path $psqlExe -PathType Leaf)) { throw "psql not found in $($binDir)." }

    if ($CreateDatabaseIfNotExists) {
        Write-LogMessage "Ensuring database '$($Database)' exists..." -Level INFO
        New-PostgreSqlDatabaseIfNotExists -Host $Host -Port $Port -User $User -Password $Password -DatabaseName $Database -PsqlExe $psqlExe
    }

    $prevPwd = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        $isPlain = [string]::Equals([System.IO.Path]::GetExtension($InputPath), '.sql', [StringComparison]::OrdinalIgnoreCase)
        if ($isPlain) {
            Write-LogMessage "Restoring from plain SQL: $($InputPath) into '$($Database)'..." -Level INFO
            $result = & $psqlExe -h $Host -p $Port -U $User -d $Database -f $InputPath 2>&1
            $exitCode = $LASTEXITCODE
            foreach ($line in $result) { Write-LogMessage "psql: $($line)" -Level DEBUG }
            if ($exitCode -ne 0) {
                Write-LogMessage "psql restore failed (exit code $($exitCode))." -Level ERROR
                throw "Restore failed."
            }
        }
        else {
            if (-not (Test-Path $pgRestoreExe -PathType Leaf)) {
                Write-LogMessage "pg_restore not found at: $($pgRestoreExe)" -Level ERROR
                throw "pg_restore not found for custom-format backup."
            }
            $cleanArgs = if ($Clean) { @('--clean', '--if-exists') } else { @() }
            Write-LogMessage "Restoring from custom backup: $($InputPath) into '$($Database)'..." -Level INFO
            & $pgRestoreExe -h $Host -p $Port -U $User -d $Database @cleanArgs $InputPath 2>&1 | ForEach-Object { Write-LogMessage "pg_restore: $_" -Level DEBUG }
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "pg_restore reported exit code $($LASTEXITCODE) (some warnings are expected if objects already exist)." -Level WARN
            }
            Write-LogMessage "Restore completed." -Level INFO
        }
    }
    finally {
        $env:PGPASSWORD = $prevPwd
    }
}

<#
.SYNOPSIS
    Creates and configures standard PostgreSQL folder structure with SMB shares.

.DESCRIPTION
    Creates or finds existing PostgreSQL folders for a given instance/purpose:
    - DataFolder: PostgreSQL data directory (pg_data)
    - BackupFolder: Database backup files (shared)
    - WalArchiveFolder: WAL archive files
    - RestoreFolder: For database restore staging (shared)

    Creates SMB shares for folders requiring network access.
    Uses Find-ValidDrives / Find-ExistingFolder from GlobalFunctions (same pattern as Get-Db2Folders).

.PARAMETER FolderName
    Specific folder to create ("All", "DataFolder", "BackupFolder", "WalArchiveFolder", "RestoreFolder").
    Default is "All".

.PARAMETER InstanceName
    Logical name for the PostgreSQL instance. Used as prefix for folder and share names.
    Default: "PostgreSql"

.PARAMETER Quiet
    Suppresses informational log messages.

.PARAMETER SkipRecreateFolders
    Skips SMB share creation if folders already exist.

.EXAMPLE
    $folders = Find-PgFolders
    # Creates all standard PostgreSQL folders and shares with default instance name "PostgreSql"

.EXAMPLE
    $folders = Find-PgFolders -InstanceName "PgDedgeAuth" -FolderName "BackupFolder"
    # Creates only the backup folder for the PgDedgeAuth instance

.OUTPUTS
    PSCustomObject with properties: InstanceName, ValidDrives, DataFolder, BackupFolder, WalArchiveFolder, RestoreFolder
#>
function Find-PgFolders {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FolderName = "All",
        [Parameter(Mandatory = $false)]
        [string]$InstanceName = "PostgreSql",
        [Parameter(Mandatory = $false)]
        [switch]$Quiet,
        [Parameter(Mandatory = $false)]
        [switch]$SkipRecreateFolders
    )
    try {
        Write-LogMessage "Finding PostgreSQL folders for instance '$($InstanceName)'" -Level INFO -Quiet:$Quiet

        $validDrives = Find-ValidDrives
        $result = [PSCustomObject]@{
            InstanceName = $InstanceName
            ValidDrives  = $validDrives
        }

        $folderArray = @()

        if ($FolderName -eq "All" -or $FolderName -eq "DataFolder") {
            $folderArray += [PSCustomObject]@{
                Name = "DataFolder"
                Path = $(Find-ExistingFolder -Name "$($InstanceName)" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateFolders)
            }
        }

        if ($FolderName -eq "All" -or $FolderName -eq "BackupFolder") {
            $folderArray += [PSCustomObject]@{
                Name        = "BackupFolder"
                ShareName   = "$($InstanceName)Backup"
                Description = "$($InstanceName)Backup is a shared folder for PostgreSQL backup files"
                Path        = $(Find-ExistingFolder -Name "$($InstanceName)Backup" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateFolders)
            }
        }

        if ($FolderName -eq "All" -or $FolderName -eq "WalArchiveFolder") {
            $folderArray += [PSCustomObject]@{
                Name = "WalArchiveFolder"
                Path = $(Find-ExistingFolder -Name "$($InstanceName)WalArchive" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateFolders)
            }
        }

        if ($FolderName -eq "All" -or $FolderName -eq "RestoreFolder") {
            $folderArray += [PSCustomObject]@{
                Name        = "RestoreFolder"
                ShareName   = "$($InstanceName)Restore"
                Description = "$($InstanceName)Restore is a shared folder for PostgreSQL restore staging"
                Path        = $(Find-ExistingFolder -Name "$($InstanceName)Restore" -Quiet:$Quiet -SkipRecreateFolders:$SkipRecreateFolders)
            }
        }

        foreach ($folder in $folderArray) {
            Add-Member -InputObject $result -NotePropertyName $folder.Name -NotePropertyValue $folder.Path -Force
            if ($folder.ShareName -and -not $SkipRecreateFolders) {
                Write-LogMessage "Adding SMB shared folder $($folder.ShareName) with path $($folder.Path)" -Level INFO
                Import-Module Infrastructure -Force
                $null = Add-SmbSharedFolder -Path $folder.Path -ShareName $folder.ShareName -Description $folder.Description
            }
        }

        return $result
    }
    catch {
        Write-LogMessage "Error creating PostgreSQL folders" -Level ERROR -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Returns PostgreSQL database entries from the central DatabasesV2.json config.

.DESCRIPTION
    Loads database definitions from DatabasesV2.json (via Get-DatabasesV2Json from
    GlobalFunctions) filtered by Provider = "PostgreSQL". Supports additional filtering
    by ServerName, Environment, Application, and Database name.

.PARAMETER ServerName
    Filter by server name (e.g. "t-no1fkxtst-db"). Default: current computer name.

.PARAMETER Environment
    Filter by environment (e.g. "TST", "PRD"). Default: all.

.PARAMETER Application
    Filter by application name (e.g. "DedgeAuth"). Default: all.

.PARAMETER Database
    Filter by database name. Default: all.

.PARAMETER ActiveOnly
    Only return entries where IsActive is true. Default: true.

.OUTPUTS
    Array of PSCustomObjects from DatabasesV2.json where Provider is PostgreSQL.

.EXAMPLE
    Get-PostgreSqlDatabases
    Returns all active PostgreSQL databases configured for the current server.

.EXAMPLE
    Get-PostgreSqlDatabases -Application "DedgeAuth" -Environment "TST"
    Returns the DedgeAuth TST PostgreSQL database entry.
#>
function Get-PostgreSqlDatabases {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServerName = $env:COMPUTERNAME,
        [Parameter(Mandatory = $false)]
        [string]$Environment = $null,
        [Parameter(Mandatory = $false)]
        [string]$Application = $null,
        [Parameter(Mandatory = $false)]
        [string]$Database = $null,
        [Parameter(Mandatory = $false)]
        [bool]$ActiveOnly = $true
    )

    $filtered = @(Get-DatabasesV2Json | Where-Object { $_.Provider -eq "PostgreSQL" })

    if ($ActiveOnly) {
        $filtered = @($filtered | Where-Object { $_.IsActive -eq $true })
    }
    if ($ServerName) {
        $filtered = @($filtered | Where-Object { $_.ServerName -ieq $ServerName })
    }
    if ($Environment) {
        $filtered = @($filtered | Where-Object { $_.Environment -ieq $Environment })
    }
    if ($Application) {
        $filtered = @($filtered | Where-Object { $_.Application -ieq $Application })
    }
    if ($Database) {
        $filtered = @($filtered | Where-Object { $_.Database -ieq $Database })
    }

    return $filtered
}

# ═══════════════════════════════════════════════════════════════════════════════
# MCP Server helpers
# ═══════════════════════════════════════════════════════════════════════════════

function Get-PostgreSqlMcpServerPath {
    <#
    .SYNOPSIS
        Returns the path to the PostgreSQL MCP server directory.
    .DESCRIPTION
        Resolves the MCP server path by checking deployed and dev locations.
    .OUTPUTS
        String path to the MCP server directory, or $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $candidates = @(
        (Join-Path $env:OptPath "DedgePshApps\Setup-CursorPostgreSqlMcp"),
        (Join-Path $PSScriptRoot "..\..\DevTools\CodingTools\Setup-CursorPostgreSqlMcp")
    )
    foreach ($c in $candidates) {
        $full = [System.IO.Path]::GetFullPath($c)
        $script = Join-Path $full 'postgresql-mcp-server.mjs'
        if (Test-Path $script -PathType Leaf) {
            return $full
        }
    }
    return $null
}

function Test-PostgreSqlMcpServer {
    <#
    .SYNOPSIS
        Tests whether the PostgreSQL MCP server can start and respond to an initialize request.
    .OUTPUTS
        PSCustomObject with .Passed (bool) and .Message (string).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'MCP server env var requires plain string.')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$PostgresUser = 'postgres',
        [Parameter(Mandatory = $false)]
        [string]$PostgresPassword = 'postgres',
        [Parameter(Mandatory = $false)]
        [int]$PostgresPort = 8432
    )

    $serverDir = Get-PostgreSqlMcpServerPath
    if (-not $serverDir) {
        return [PSCustomObject]@{ Passed = $false; Message = 'MCP server directory not found.' }
    }

    $serverScript = Join-Path $serverDir 'postgresql-mcp-server.mjs'
    $nodeModules  = Join-Path $serverDir 'node_modules'

    $nodeExe = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeExe) {
        return [PSCustomObject]@{ Passed = $false; Message = 'Node.js not found.' }
    }

    if (-not (Test-Path $nodeModules)) {
        return [PSCustomObject]@{ Passed = $false; Message = 'node_modules missing. Run Setup-CursorPostgreSqlMcp.ps1 first.' }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $nodeExe.Source
    $psi.Arguments = "`"$serverScript`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Environment['PG_USER']     = $PostgresUser
    $psi.Environment['PG_PASSWORD'] = $PostgresPassword
    $psi.Environment['PG_PORT']     = [string]$PostgresPort

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 1500

        if ($proc.HasExited) {
            $stderr = $proc.StandardError.ReadToEnd()
            return [PSCustomObject]@{ Passed = $false; Message = "Server exited: $($stderr)" }
        }

        $initRequest = @{
            jsonrpc = '2.0'; id = 1; method = 'initialize'
            params = @{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'test'; version = '1.0' } }
        } | ConvertTo-Json -Depth 6 -Compress

        $proc.StandardInput.WriteLine($initRequest)
        $proc.StandardInput.Flush()
        Start-Sleep -Milliseconds 500

        $response = $proc.StandardOutput.ReadLine()
        if ($response) {
            $parsed = $response | ConvertFrom-Json
            if ($parsed.result.serverInfo) {
                return [PSCustomObject]@{
                    Passed  = $true
                    Message = "Server OK: $($parsed.result.serverInfo.name) v$($parsed.result.serverInfo.version)"
                }
            }
        }
        return [PSCustomObject]@{ Passed = $false; Message = 'No valid response from server.' }
    }
    catch {
        return [PSCustomObject]@{ Passed = $false; Message = "Error: $($_.Exception.Message)" }
    }
    finally {
        if ($proc -and -not $proc.HasExited) {
            $proc.Kill()
            $proc.WaitForExit(5000)
        }
        if ($proc) { $proc.Dispose() }
    }
}

function Get-PostgreSqlMcpConnectionInfo {
    <#
    .SYNOPSIS
        Returns connection info for a database suitable for MCP server configuration.
    .DESCRIPTION
        Looks up the database in DatabasesV2.json (Provider=PostgreSQL) and returns
        server, port, database name, and environment.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$Environment = 'TST'
    )

    $splat = @{ Database = $DatabaseName; ServerName = $null }
    if ($Environment) { $splat['Environment'] = $Environment }

    $entries = Get-PostgreSqlDatabases @splat
    if ($entries.Count -eq 0) {
        Write-LogMessage "Database '$($DatabaseName)' not found in DatabasesV2.json (Provider=PostgreSQL)" -Level WARN
        return $null
    }

    $entry = $entries[0]
    return [PSCustomObject]@{
        Database    = $entry.Database
        Server      = $entry.ServerName
        Port        = $entry.Port
        Environment = $entry.Environment
        Application = $entry.Application
    }
}

Export-ModuleMember -Function @(
    'Get-PostgreSqlPsqlPath',
    'Test-PostgreSqlLocalHost',
    'Get-PostgreSqlConfigPath',
    'Test-PostgreSqlConnection',
    'Invoke-PostgreSqlQuery',
    'New-PostgreSqlDatabaseIfNotExists',
    'Get-PostgreSqlConnectionString',
    'Set-PostgreSqlLocalConfig',
    'Invoke-PostgreSqlEnsureLocalReady',
    'Test-PostgreSqlSetup',
    'Repair-PostgreSqlInstall',
    'Backup-PostgreSqlDatabase',
    'Restore-PostgreSqlDatabase',
    'Find-PgFolders',
    'Get-PostgreSqlDatabases',
    'Get-PostgreSqlMcpServerPath',
    'Test-PostgreSqlMcpServer',
    'Get-PostgreSqlMcpConnectionInfo'
)
