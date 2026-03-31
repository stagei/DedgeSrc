param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = "$(Join-Path $PSScriptRoot "ArchiveTables.json")",
    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "",
    [Parameter(Mandatory = $false)]
    [string]$SingleTable = ""
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

function Get-SelectedDatabaseContext {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RequestedDatabaseName = ""
    )

    $selectedDatabaseName = $RequestedDatabaseName
    if ([string]::IsNullOrWhiteSpace($selectedDatabaseName)) {
        $selectedDatabaseName = Get-UserChoiceForDatabaseName -SkipAlias -SkipFederated -ThrowOnTimeout
    }

    $dbConfig = Get-DatabasesV2Json |
        Where-Object { $_.Provider -eq "DB2" -and $_.IsActive -eq $true -and $_.ServerName -eq $env:COMPUTERNAME } |
        Where-Object {
            $_.AccessPoints | Where-Object {
                $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" -and $_.CatalogName -eq $selectedDatabaseName
            }
        } |
        Select-Object -First 1

    if ($null -eq $dbConfig) {
        throw "Database $($selectedDatabaseName) not found as active PrimaryDb in DatabasesV2 for server $($env:COMPUTERNAME)."
    }

    $primaryAccessPoint = $dbConfig.AccessPoints |
        Where-Object { $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" -and $_.CatalogName -eq $selectedDatabaseName } |
        Select-Object -First 1

    if ($null -eq $primaryAccessPoint) {
        throw "Primary access point not found for database $($selectedDatabaseName)."
    }

    return [PSCustomObject]@{
        DatabaseName = $selectedDatabaseName
        InstanceName = $primaryAccessPoint.InstanceName
        Application  = $dbConfig.Application
    }
}

function Invoke-Db2MultiStatement {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string[]]$Db2Commands,
        [switch]$IgnoreErrors
    )

    $batLines = @()
    $batLines += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $batLines += Get-ConnectCommand -WorkObject $WorkObject
    foreach ($cmd in $Db2Commands) {
        $batLines += $cmd
    }
    $batLines += "db2 connect reset"
    $batLines += "db2 terminate"

    return Invoke-Db2ContentAsScript -Content $batLines -ExecutionType BAT -IgnoreErrors:$IgnoreErrors
}

function Get-OutputBetweenMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$StartMarker,
        [Parameter(Mandatory = $true)]
        [string]$EndMarker
    )

    [string[]]$result = @()
    $lines = $Output -split "`r?`n"
    $inside = $false
    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq $StartMarker) {
            $inside = $true
            continue
        }
        if ($trimmedLine -eq $EndMarker) {
            break
        }
        if ($inside -and -not [string]::IsNullOrWhiteSpace($trimmedLine)) {
            if ($trimmedLine -like "DB20000I*") { continue }
            if ($trimmedLine -match '^[A-Za-z]:\\.*>\s*') { continue }
            $result += $trimmedLine
        }
    }

    return ,$result
}

function Export-IndexDdl {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    Write-LogMessage "Exporting index DDL for $($Schema).$($TableName)..." -Level INFO

    $query = @"
SELECT I.INDNAME, I.UNIQUERULE, I.INDEXTYPE, IC.COLNAME, IC.COLORDER, IC.COLSEQ
FROM SYSCAT.INDEXES I
JOIN SYSCAT.INDEXCOLUSE IC ON I.INDSCHEMA = IC.INDSCHEMA AND I.INDNAME = IC.INDNAME
WHERE I.TABSCHEMA = '$Schema' AND I.TABNAME = '$TableName'
ORDER BY I.INDNAME, IC.COLSEQ
FETCH FIRST 500 ROWS ONLY
"@

    $db2Commands = @()
    $db2Commands += "echo __IDX_START__"
    $db2Commands += "db2 -x `"$($query -replace "`r?`n", " ")`""
    $db2Commands += "echo __IDX_END__"

    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $lines = Get-OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__IDX_START__" -EndMarker "__IDX_END__"

    $indexes = @{}
    $indexRules = @{}
    foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 6) { continue }

        $indName = $parts[0].Trim()
        $uniqueRule = $parts[1].Trim()
        $colName = $parts[3].Trim()
        # A=ASC, D=DESC, I=INCLUDE
        $colOrder = $parts[4].Trim()
        $colSeq = [int]$parts[5].Trim()

        if (-not $indexes.ContainsKey($indName)) {
            $indexes[$indName] = @()
            $indexRules[$indName] = $uniqueRule
        }

        $direction = switch ($colOrder) {
            "A" { "ASC" }
            "D" { "DESC" }
            "I" { "ASC" }
            default { "ASC" }
        }

        $indexes[$indName] += [PSCustomObject]@{
            ColName  = $colName
            ColOrder = $direction
            ColSeq   = $colSeq
        }
    }

    $sqlStatements = @()
    $sqlStatements += "-- Index DDL for $($Schema).$($TableName)"
    $sqlStatements += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $sqlStatements += "-- Database: $($WorkObject.DatabaseName)"
    $sqlStatements += ""

    foreach ($indName in ($indexes.Keys | Sort-Object)) {
        $rule = $indexRules[$indName]
        $cols = $indexes[$indName] | Sort-Object ColSeq
        $colList = ($cols | ForEach-Object { "$($_.ColName) $($_.ColOrder)" }) -join ", "

        if ($rule -eq "P") {
            $sqlStatements += "ALTER TABLE $($Schema).$($TableName) ADD PRIMARY KEY ($($colList -replace ' ASC', '' -replace ' DESC', ''));"
        }
        elseif ($rule -eq "U") {
            $sqlStatements += "CREATE UNIQUE INDEX $($Schema).$($indName) ON $($Schema).$($TableName) ($($colList));"
        }
        else {
            $sqlStatements += "CREATE INDEX $($Schema).$($indName) ON $($Schema).$($TableName) ($($colList));"
        }
        $sqlStatements += ""
    }

    [System.IO.File]::WriteAllText($OutputFile, ($sqlStatements -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
    Write-LogMessage "  Wrote $($indexes.Count) index statement(s) to $OutputFile" -Level INFO
    return $indexes.Count
}

function Export-ViewDdl {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    Write-LogMessage "Exporting dependent view DDL for $($Schema).$($TableName)..." -Level INFO

    $depQuery = "SELECT TABSCHEMA, TABNAME FROM SYSCAT.TABDEP WHERE BSCHEMA = '$Schema' AND BNAME = '$TableName' AND BTYPE = 'T' AND DTYPE = 'V' ORDER BY TABNAME FETCH FIRST 50 ROWS ONLY"

    $db2Commands = @()
    $db2Commands += "echo __DEP_START__"
    $db2Commands += "db2 -x `"$depQuery`""
    $db2Commands += "echo __DEP_END__"

    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $depLines = Get-OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__DEP_START__" -EndMarker "__DEP_END__"

    $viewCount = 0
    $sqlStatements = @()
    $sqlStatements += "-- Dependent view DDL for $($Schema).$($TableName)"
    $sqlStatements += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $sqlStatements += "-- Database: $($WorkObject.DatabaseName)"
    $sqlStatements += ""

    foreach ($depLine in $depLines) {
        $parts = $depLine -split '\s+'
        if ($parts.Count -lt 2) { continue }

        $viewSchema = $parts[0].Trim()
        $viewName = $parts[1].Trim()

        $viewQuery = "SELECT TEXT FROM SYSCAT.VIEWS WHERE VIEWSCHEMA = '$viewSchema' AND VIEWNAME = '$viewName'"

        $viewCommands = @()
        $viewCommands += "echo __VIEW_START__"
        $viewCommands += "db2 -x `"$viewQuery`""
        $viewCommands += "echo __VIEW_END__"

        $viewOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $viewCommands -IgnoreErrors
        $viewLines = Get-OutputBetweenMarkers -Output ($viewOutput -join "`n") -StartMarker "__VIEW_START__" -EndMarker "__VIEW_END__"

        if ($viewLines.Count -gt 0) {
            $viewText = ($viewLines -join "`n").Trim()

            if ($viewText -notmatch '(?i)^CREATE\s') {
                $viewText = "CREATE OR REPLACE VIEW $($viewSchema).$($viewName) AS $viewText"
            }

            if (-not $viewText.EndsWith(";")) {
                $viewText += ";"
            }

            $sqlStatements += "-- View: $($viewSchema).$($viewName)"
            $sqlStatements += "DROP VIEW $($viewSchema).$($viewName);"
            $sqlStatements += ""
            $sqlStatements += $viewText
            $sqlStatements += ""
            $viewCount++
        }
    }

    if ($viewCount -eq 0) {
        $sqlStatements += "-- No dependent views found."
    }

    [System.IO.File]::WriteAllText($OutputFile, ($sqlStatements -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
    Write-LogMessage "  Wrote $viewCount view statement(s) to $OutputFile" -Level INFO
    return $viewCount
}

function Export-TriggerDdl {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    Write-LogMessage "Exporting trigger DDL for $($Schema).$($TableName)..." -Level INFO

    $trigQuery = "SELECT TRIGSCHEMA, TRIGNAME, TEXT FROM SYSCAT.TRIGGERS WHERE TABSCHEMA = '$Schema' AND TABNAME = '$TableName' ORDER BY TRIGNAME FETCH FIRST 50 ROWS ONLY"

    $db2Commands = @()
    $db2Commands += "echo __TRIG_START__"
    $db2Commands += "db2 -x `"$trigQuery`""
    $db2Commands += "echo __TRIG_END__"

    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $trigLines = Get-OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__TRIG_START__" -EndMarker "__TRIG_END__"

    $trigCount = 0
    $sqlStatements = @()
    $sqlStatements += "-- Trigger DDL for $($Schema).$($TableName)"
    $sqlStatements += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $sqlStatements += "-- Database: $($WorkObject.DatabaseName)"
    $sqlStatements += ""

    if ($trigLines.Count -gt 0) {
        foreach ($trigLine in $trigLines) {
            $trigText = $trigLine.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trigText)) {
                if (-not $trigText.EndsWith(";")) {
                    $trigText += ";"
                }
                $sqlStatements += $trigText
                $sqlStatements += ""
                $trigCount++
            }
        }
    }

    if ($trigCount -eq 0) {
        $sqlStatements += "-- No triggers found."
    }

    [System.IO.File]::WriteAllText($OutputFile, ($sqlStatements -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
    Write-LogMessage "  Wrote $trigCount trigger statement(s) to $OutputFile" -Level INFO
    return $trigCount
}

function Export-GrantDdl {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    Write-LogMessage "Exporting grants for $($Schema).$($TableName)..." -Level INFO

    $grantQuery = "SELECT GRANTEE, SELECTAUTH, INSERTAUTH, UPDATEAUTH, DELETEAUTH, CONTROLAUTH, REFAUTH FROM SYSCAT.TABAUTH WHERE TABSCHEMA = '$Schema' AND TABNAME = '$TableName' ORDER BY GRANTEE FETCH FIRST 100 ROWS ONLY"

    $db2Commands = @()
    $db2Commands += "echo __GRANT_START__"
    $db2Commands += "db2 -x `"$grantQuery`""
    $db2Commands += "echo __GRANT_END__"

    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $grantLines = Get-OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__GRANT_START__" -EndMarker "__GRANT_END__"

    $grantCount = 0
    $sqlStatements = @()
    $sqlStatements += "-- Grant statements for $($Schema).$($TableName)"
    $sqlStatements += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $sqlStatements += "-- Database: $($WorkObject.DatabaseName)"
    $sqlStatements += ""

    $processedGrantees = @{}

    foreach ($line in $grantLines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 7) { continue }

        $grantee = $parts[0].Trim()
        $selectAuth = $parts[1].Trim()
        $insertAuth = $parts[2].Trim()
        $updateAuth = $parts[3].Trim()
        $deleteAuth = $parts[4].Trim()
        $controlAuth = $parts[5].Trim()
        $refAuth = $parts[6].Trim()

        if ($processedGrantees.ContainsKey($grantee)) { continue }
        $processedGrantees[$grantee] = $true

        if ($grantee -eq "SYSIBM") { continue }

        $privs = @()
        if ($controlAuth -in @("Y", "G")) {
            $sqlStatements += "GRANT CONTROL ON $($Schema).$($TableName) TO $grantee;"
            $grantCount++
            continue
        }
        if ($selectAuth -in @("Y", "G")) { $privs += "SELECT" }
        if ($insertAuth -in @("Y", "G")) { $privs += "INSERT" }
        if ($updateAuth -in @("Y", "G")) { $privs += "UPDATE" }
        if ($deleteAuth -in @("Y", "G")) { $privs += "DELETE" }
        if ($refAuth -in @("Y", "G")) { $privs += "REFERENCES" }

        if ($privs.Count -gt 0) {
            $sqlStatements += "GRANT $($privs -join ', ') ON $($Schema).$($TableName) TO $grantee;"
            $grantCount++
        }
    }

    if ($grantCount -eq 0) {
        $sqlStatements += "-- No grants found."
    }

    [System.IO.File]::WriteAllText($OutputFile, ($sqlStatements -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
    Write-LogMessage "  Wrote $grantCount grant statement(s) to $OutputFile" -Level INFO
    return $grantCount
}

function Export-PackageRebindCommands {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    Write-LogMessage "Exporting package rebind commands for $($Schema).$($TableName)..." -Level INFO

    $pkgQuery = "SELECT DISTINCT PKGSCHEMA, PKGNAME FROM SYSCAT.PACKAGEDEP WHERE BSCHEMA = '$Schema' AND BNAME = '$TableName' AND BTYPE = 'T' ORDER BY PKGNAME FETCH FIRST 100 ROWS ONLY"

    $db2Commands = @()
    $db2Commands += "echo __PKG_START__"
    $db2Commands += "db2 -x `"$pkgQuery`""
    $db2Commands += "echo __PKG_END__"

    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $pkgLines = Get-OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__PKG_START__" -EndMarker "__PKG_END__"

    $pkgCount = 0
    $sqlStatements = @()
    $sqlStatements += "-- Package rebind commands for $($Schema).$($TableName)"
    $sqlStatements += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $sqlStatements += "-- Database: $($WorkObject.DatabaseName)"
    $sqlStatements += ""
    $sqlStatements += "-- Option 1: Rebind all packages in the database (simplest)"
    $sqlStatements += "-- db2rbind $($WorkObject.DatabaseName) -l rebind.log all"
    $sqlStatements += ""
    $sqlStatements += "-- Option 2: Rebind individual packages (targeted)"

    foreach ($line in $pkgLines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 2) { continue }

        $pkgSchema = $parts[0].Trim()
        $pkgName = $parts[1].Trim()

        $sqlStatements += "db2 `"REBIND PACKAGE $($pkgSchema).$($pkgName)`""
        $pkgCount++
    }

    $sqlStatements += ""

    if ($pkgCount -eq 0) {
        $sqlStatements += "-- No dependent packages found."
    }
    else {
        $sqlStatements += "-- Total: $pkgCount package(s) to rebind"
        $sqlStatements += "-- Note: With auto_reval=DEFERRED (Db2 default), packages are"
        $sqlStatements += "-- automatically revalidated on next access. Explicit rebind is optional."
    }

    [System.IO.File]::WriteAllText($OutputFile, ($sqlStatements -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
    Write-LogMessage "  Wrote $pkgCount rebind command(s) to $OutputFile" -Level INFO
    return $pkgCount
}

function Export-ForeignKeyDdl {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    Write-LogMessage "Exporting foreign key constraints for $($Schema).$($TableName)..." -Level INFO

    $fkQuery = "SELECT CONSTNAME, TABSCHEMA, TABNAME, REFTABSCHEMA, REFTABNAME, FK_COLNAMES, PK_COLNAMES FROM SYSCAT.REFERENCES WHERE (REFTABSCHEMA = '$Schema' AND REFTABNAME = '$TableName') OR (TABSCHEMA = '$Schema' AND TABNAME = '$TableName') ORDER BY CONSTNAME FETCH FIRST 50 ROWS ONLY"

    $db2Commands = @()
    $db2Commands += "echo __FK_START__"
    $db2Commands += "db2 -x `"$($fkQuery -replace "`r?`n", " ")`""
    $db2Commands += "echo __FK_END__"

    $rawOutput = Invoke-Db2MultiStatement -WorkObject $WorkObject -Db2Commands $db2Commands -IgnoreErrors
    $fkLines = Get-OutputBetweenMarkers -Output ($rawOutput -join "`n") -StartMarker "__FK_START__" -EndMarker "__FK_END__"

    $fkCount = 0
    $sqlStatements = @()
    $sqlStatements += "-- Foreign key constraints for $($Schema).$($TableName)"
    $sqlStatements += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $sqlStatements += "-- Database: $($WorkObject.DatabaseName)"
    $sqlStatements += ""

    foreach ($line in $fkLines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $sqlStatements += "-- Raw FK data: $line"
            $fkCount++
        }
    }

    if ($fkCount -eq 0) {
        $sqlStatements += "-- No foreign key constraints found."
    }

    [System.IO.File]::WriteAllText($OutputFile, ($sqlStatements -join "`n"), [System.Text.Encoding]::GetEncoding(1252))
    Write-LogMessage "  Wrote $fkCount FK constraint(s) to $OutputFile" -Level INFO
    return $fkCount
}

function Export-AllForTable {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$FullTableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $tableParts = $FullTableName -split '\.'
    if ($tableParts.Count -ne 2) {
        Write-LogMessage "Invalid table name format '$FullTableName'. Expected SCHEMA.TABLE." -Level ERROR
        return
    }
    $schema = $tableParts[0].Trim().ToUpper()
    $tableName = $tableParts[1].Trim().ToUpper()
    $tableDir = Join-Path $OutputDir "$($schema)_$($tableName)"

    New-Item -Path $tableDir -ItemType Directory -Force | Out-Null
    Write-LogMessage "=== Exporting dependencies for $($schema).$($tableName) ===" -Level INFO
    Write-LogMessage "  Output folder: $tableDir" -Level INFO

    $idxCount = Export-IndexDdl -WorkObject $WorkObject -Schema $schema -TableName $tableName -OutputFile (Join-Path $tableDir "$($tableName)_indexes.sql")
    $viewCount = Export-ViewDdl -WorkObject $WorkObject -Schema $schema -TableName $tableName -OutputFile (Join-Path $tableDir "$($tableName)_views.sql")
    $trigCount = Export-TriggerDdl -WorkObject $WorkObject -Schema $schema -TableName $tableName -OutputFile (Join-Path $tableDir "$($tableName)_triggers.sql")
    $grantCount = Export-GrantDdl -WorkObject $WorkObject -Schema $schema -TableName $tableName -OutputFile (Join-Path $tableDir "$($tableName)_grants.sql")
    $pkgCount = Export-PackageRebindCommands -WorkObject $WorkObject -Schema $schema -TableName $tableName -OutputFile (Join-Path $tableDir "$($tableName)_rebind_packages.sql")
    $fkCount = Export-ForeignKeyDdl -WorkObject $WorkObject -Schema $schema -TableName $tableName -OutputFile (Join-Path $tableDir "$($tableName)_fk_constraints.sql")

    $summary = @()
    $summary += "-- Dependency export summary for $($schema).$($tableName)"
    $summary += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $summary += "-- Database: $($WorkObject.DatabaseName)"
    $summary += "-- Server: $($env:COMPUTERNAME)"
    $summary += "--"
    $summary += "-- Indexes:      $idxCount"
    $summary += "-- Views:        $viewCount"
    $summary += "-- Triggers:     $trigCount"
    $summary += "-- Grants:       $grantCount"
    $summary += "-- Packages:     $pkgCount"
    $summary += "-- FK constr.:   $fkCount"
    $summary += "--"
    $summary += "-- Recreate order after CREATE TABLE ... LIKE:"
    $summary += "--   1. Run $($tableName)_indexes.sql      (primary key first, then non-unique)"
    $summary += "--   2. Run $($tableName)_fk_constraints.sql"
    $summary += "--   3. Run $($tableName)_triggers.sql"
    $summary += "--   4. Run $($tableName)_views.sql"
    $summary += "--   5. Run $($tableName)_grants.sql"
    $summary += "--   6. Run $($tableName)_rebind_packages.sql  (optional if auto_reval=DEFERRED)"

    [System.IO.File]::WriteAllText((Join-Path $tableDir "_SUMMARY.sql"), ($summary -join "`n"), [System.Text.Encoding]::GetEncoding(1252))

    Write-LogMessage "" -Level INFO
    Write-LogMessage "Summary for $($schema).$($tableName):" -Level INFO
    Write-LogMessage "  Indexes:      $idxCount" -Level INFO
    Write-LogMessage "  Views:        $viewCount" -Level INFO
    Write-LogMessage "  Triggers:     $trigCount" -Level INFO
    Write-LogMessage "  Grants:       $grantCount" -Level INFO
    Write-LogMessage "  Packages:     $pkgCount" -Level INFO
    Write-LogMessage "  FK constr.:   $fkCount" -Level INFO
    Write-LogMessage "  Output dir:   $tableDir" -Level INFO
}

# --- Main ---

$context = Get-SelectedDatabaseContext -RequestedDatabaseName $DatabaseName
Write-LogMessage "Database context: $($context.DatabaseName) (instance: $($context.InstanceName))" -Level INFO

if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $OutputFolder = Join-Path (Get-ApplicationDataPath) "ExportedDependencies"
}
New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
Write-LogMessage "Output folder: $OutputFolder" -Level INFO

$tablesToProcess = @()
if (-not [string]::IsNullOrWhiteSpace($SingleTable)) {
    $tablesToProcess += $SingleTable
}
else {
    if (-not (Test-Path $ConfigFilePath -PathType Leaf)) {
        throw "Config file not found: $ConfigFilePath"
    }
    $config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    foreach ($entry in $config) {
        $tablesToProcess += $entry.TableName
    }
}

Write-LogMessage "Tables to process: $($tablesToProcess -join ', ')" -Level INFO

foreach ($table in $tablesToProcess) {
    try {
        Export-AllForTable -WorkObject $context -FullTableName $table -OutputDir $OutputFolder
    }
    catch {
        Write-LogMessage "Error exporting dependencies for $($table): $($_.Exception.Message)" -Level ERROR
    }
}

Write-LogMessage "" -Level INFO
Write-LogMessage "Export complete. All dependency files are in: $OutputFolder" -Level INFO
