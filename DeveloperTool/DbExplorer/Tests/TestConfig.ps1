# Shared test configuration - run tests independent of database provider
# Use -Profile / -Provider params or env: WDE_TEST_PROFILE, WDE_TEST_PROVIDER

param(
    [string]$Profile,
    [ValidateSet('', 'DB2', 'PostgreSQL', 'SQLite')]
    [string]$Provider
)

# Profile: from param, then env WDE_TEST_PROFILE, then default
if ($Profile) {
    $script:WDE_TestProfile = $Profile
} elseif ($env:WDE_TEST_PROFILE) {
    $script:WDE_TestProfile = $env:WDE_TEST_PROFILE
} else {
    $script:WDE_TestProfile = 'FKKTOTST'
}

# Provider: from param, then env WDE_TEST_PROVIDER (DB2, PostgreSQL), empty = run all (backward compat)
if ($Provider) {
    $script:WDE_TestProvider = $Provider
} elseif ($env:WDE_TEST_PROVIDER) {
    $script:WDE_TestProvider = $env:WDE_TEST_PROVIDER
} else {
    $script:WDE_TestProvider = ''
}

# CLI command names that are DB2-only (skip when provider is PostgreSQL)
$script:WDE_DB2OnlyCommands = @(
    'list-packages',
    'package-analysis',
    'package-details',
    'package-properties',
    'package-statements',
    'table-referencing-packages',
    'lock-monitor',
    'lock-monitor-full',
    'lock-chains',
    'active-sessions',
    'active-sessions-full',
    'session-details',
    'long-running-sessions',
    'database-load',
    'database-load-full',
    'table-activity',
    'top-active-tables',
    'cdc-info',
    'cdc-status-full',
    'cdc-configuration',
    'cdc-changes',
    'statistics-recommendations',
    'list-tablespaces'
)

function Get-WdeTestProfile {
    if ($script:WDE_TestProfile) { return $script:WDE_TestProfile }
    if ($env:WDE_TEST_PROFILE) { return $env:WDE_TEST_PROFILE }
    return 'FKKTOTST'
}

function Get-WdeTestProvider {
    if ($script:WDE_TestProvider) { return $script:WDE_TestProvider }
    if ($env:WDE_TEST_PROVIDER) { return $env:WDE_TEST_PROVIDER }
    return ''
}

# Returns $true if the CLI command should run for the given provider.
# When provider is empty or DB2: run all. When PostgreSQL: skip DB2-only commands.
function Test-WdeCommandSupportedForProvider {
    param(
        [string]$CommandName,
        [string]$Provider = $script:WDE_TestProvider
    )
    if ([string]::IsNullOrWhiteSpace($Provider) -or $Provider -eq 'DB2') {
        return $true
    }
    if ($Provider -eq 'PostgreSQL' -or $Provider -eq 'SQLite') {
        return $script:WDE_DB2OnlyCommands -notcontains $CommandName
    }
    return $true
}

# Log resolved config when TestLogger is loaded (e.g. by Run-TestSuite or Test-Connection)
if (Get-Command Write-TestLog -ErrorAction SilentlyContinue) {
    Write-TestLog "Profile: $($script:WDE_TestProfile), Provider: $($script:WDE_TestProvider)" -Level DEBUG
}

# Export for dot-sourcing: call with . .\Tests\TestConfig.ps1 -Profile "MyProfile" -Provider "PostgreSQL"
# Or set env: $env:WDE_TEST_PROFILE = "PostgreSQL_Local"; $env:WDE_TEST_PROVIDER = "PostgreSQL"
