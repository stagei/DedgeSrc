<#
.SYNOPSIS
    Exports configuration tables from t-no1fkxtst-db and inserts into local PostgreSQL.
.DESCRIPTION
    Connects to the FKX test database, exports saved_filters, import_sources, and
    import_level_filters rows (excluding log_entries), then inserts them into the
    local database on localhost:8432.
#>
param(
    [string]$SourceHost     = 't-no1fkxtst-db',
    [int]$SourcePort        = 8432,
    [string]$SourceDatabase = 'GenericLogHandler',
    [string]$SourceUser     = 'postgres',
    [string]$SourcePassword = 'postgres',

    [string]$TargetHost     = 'localhost',
    [int]$TargetPort        = 8432,
    [string]$TargetDatabase = 'GenericLogHandler',
    [string]$TargetUser     = 'postgres',
    [string]$TargetPassword = 'postgres'
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module SimplySql -Force

function Open-SourceDb {
    $cred = New-Object PSCredential($SourceUser, (ConvertTo-SecureString $SourcePassword -AsPlainText -Force))
    Open-PostGreConnection -Server $SourceHost -Port $SourcePort -Database $SourceDatabase -Credential $cred -ConnectionName 'source'
}

function Open-TargetDb {
    $cred = New-Object PSCredential($TargetUser, (ConvertTo-SecureString $TargetPassword -AsPlainText -Force))
    Open-PostGreConnection -Server $TargetHost -Port $TargetPort -Database $TargetDatabase -Credential $cred -ConnectionName 'target'
}

function Export-And-Insert {
    param(
        [string]$TableName,
        [string]$SelectQuery
    )

    Write-LogMessage "Exporting $($TableName) from source..." -Level INFO

    $rows = @(Invoke-SqlQuery -Query $SelectQuery -ConnectionName 'source')
    if ($null -eq $rows -or $rows.Count -eq 0) {
        Write-LogMessage "  No rows found in $($TableName) on source, skipping" -Level WARN
        return 0
    }

    Write-LogMessage "  Found $($rows.Count) rows in $($TableName)" -Level INFO

    # Clear target table first
    Invoke-SqlUpdate -Query "DELETE FROM $($TableName);" -ConnectionName 'target' | Out-Null

    $insertCount = 0
    foreach ($row in $rows) {
        $columns = @()
        $values  = @()
        $props = $row.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }
        foreach ($prop in $props) {
            $columns += $prop.Name
            $val = $prop.Value
            if ($null -eq $val) {
                $values += 'NULL'
            }
            elseif ($val -is [bool]) {
                $values += if ($val) { 'true' } else { 'false' }
            }
            elseif ($val -is [DateTime]) {
                $values += "'" + $val.ToString('yyyy-MM-dd HH:mm:ss.ffffffzzz') + "'"
            }
            elseif ($val -is [int] -or $val -is [long] -or $val -is [double] -or $val -is [decimal]) {
                $values += $val.ToString()
            }
            elseif ($val -is [Guid]) {
                $values += "'" + $val.ToString() + "'"
            }
            else {
                $escaped = $val.ToString().Replace("'", "''")
                $values += "'" + $escaped + "'"
            }
        }

        $insertSql = "INSERT INTO $($TableName) ($($columns -join ', ')) VALUES ($($values -join ', ')) ON CONFLICT DO NOTHING;"
        try {
            Invoke-SqlUpdate -Query $insertSql -ConnectionName 'target' | Out-Null
            $insertCount++
        }
        catch {
            Write-LogMessage "  Failed to insert row into $($TableName): $($_.Exception.Message)" -Level ERROR
        }
    }

    Write-LogMessage "  Inserted $($insertCount) rows into $($TableName)" -Level INFO
    return $insertCount
}

# ============================================================================
# Main
# ============================================================================

Write-LogMessage "=== Config Seed: Exporting from $($SourceHost) to $($TargetHost) ===" -Level INFO

# Test source connectivity
try {
    Open-SourceDb
    $testResult = Invoke-SqlScalar -Query "SELECT 1;" -ConnectionName 'source'
    Write-LogMessage "Source database connection OK" -Level INFO
}
catch {
    Write-LogMessage "Cannot connect to source database $($SourceHost):$($SourcePort) - $($_.Exception.Message)" -Level ERROR
    Write-LogMessage "Skipping config seed from remote. Local DB will start with empty config." -Level WARN
    Close-SqlConnection -ConnectionName 'source' -ErrorAction SilentlyContinue
    exit 0
}

# Test target connectivity
try {
    Open-TargetDb
    $testResult = Invoke-SqlScalar -Query "SELECT 1;" -ConnectionName 'target'
    Write-LogMessage "Target database connection OK" -Level INFO
}
catch {
    Write-LogMessage "Cannot connect to target database $($TargetHost):$($TargetPort) - $($_.Exception.Message)" -Level ERROR
    Close-SqlConnection -ConnectionName 'source' -ErrorAction SilentlyContinue
    Close-SqlConnection -ConnectionName 'target' -ErrorAction SilentlyContinue
    exit 1
}

$totalInserted = 0

# Export import_sources
$totalInserted += Export-And-Insert -TableName 'import_sources' `
    -SelectQuery 'SELECT * FROM import_sources ORDER BY priority;'

# Export import_level_filters
$totalInserted += Export-And-Insert -TableName 'import_level_filters' `
    -SelectQuery 'SELECT * FROM import_level_filters ORDER BY source_name, level;'

# Export saved_filters (not log_entries, not alert_history)
$totalInserted += Export-And-Insert -TableName 'saved_filters' `
    -SelectQuery 'SELECT * FROM saved_filters ORDER BY created_at;'

# Export users
$totalInserted += Export-And-Insert -TableName 'users' `
    -SelectQuery 'SELECT * FROM users ORDER BY username;'

Close-SqlConnection -ConnectionName 'source' -ErrorAction SilentlyContinue
Close-SqlConnection -ConnectionName 'target' -ErrorAction SilentlyContinue

Write-LogMessage "=== Config Seed Complete: $($totalInserted) total rows inserted ===" -Level INFO
