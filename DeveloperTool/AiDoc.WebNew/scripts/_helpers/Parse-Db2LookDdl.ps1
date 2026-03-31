<#
.SYNOPSIS
    Parses db2look output into per-object DDL blocks.

.DESCRIPTION
    Reads the single large db2look SQL file (using @ as statement terminator),
    splits it into individual DDL statements, and groups them by the
    SCHEMA.OBJECTNAME they belong to. Returns a hashtable where each key is
    SCHEMA.OBJECTNAME and the value is an array of DDL statement strings.
#>

function Parse-Db2LookDdl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DdlFilePath
    )

    if (-not (Test-Path $DdlFilePath)) {
        Write-LogMessage "DDL file not found: $($DdlFilePath)" -Level WARN
        return @{}
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($DdlFilePath)
    $rawContent = [System.Text.Encoding]::GetEncoding(1252).GetString($rawBytes)

    $statements = $rawContent -split '(?m)^@\s*$|(?<=\S)\s*@\s*$'

    $ddlMap = @{}

    foreach ($stmt in $statements) {
        $trimmed = $stmt.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match '^--') {
            $nonComment = ($trimmed -split "`n" | Where-Object { $_ -notmatch '^\s*--' -and -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
            if ([string]::IsNullOrWhiteSpace($nonComment)) { continue }
            $trimmed = $nonComment.Trim()
        }

        $objectKey = Get-DdlObjectKey -Statement $trimmed
        if ($objectKey) {
            if (-not $ddlMap.ContainsKey($objectKey)) {
                $ddlMap[$objectKey] = @()
            }
            $ddlMap[$objectKey] += $stmt.Trim()
        }
    }

    return $ddlMap
}

function Get-DdlObjectKey {
    param([string]$Statement)

    $s = $Statement

    # CREATE TABLE "SCHEMA"."TABLENAME"  or  CREATE TABLE SCHEMA.TABLENAME
    # Regex breakdown:
    #   CREATE\s+TABLE\s+  -- literal CREATE TABLE
    #   "?(\w+)"?\."?(\w+)"?  -- optional-quoted SCHEMA.NAME, captured in groups 1 and 2
    if ($s -match 'CREATE\s+TABLE\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # ALTER TABLE "SCHEMA"."TABLE" ADD CONSTRAINT ...
    if ($s -match 'ALTER\s+TABLE\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # CREATE (UNIQUE)? INDEX "SCHEMA"."IDXNAME" ON "SCHEMA"."TABLE"
    # We key by the target table, not the index name
    if ($s -match 'CREATE\s+(?:UNIQUE\s+)?INDEX\s+"?\w+"?\."?\w+"?\s+ON\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # CREATE OR REPLACE VIEW / CREATE VIEW
    if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # CREATE OR REPLACE PROCEDURE / CREATE PROCEDURE
    if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?PROCEDURE\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # CREATE OR REPLACE FUNCTION / CREATE FUNCTION
    if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # CREATE TRIGGER
    if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    # COMMENT ON TABLE / COMMENT ON COLUMN
    if ($s -match 'COMMENT\s+ON\s+TABLE\s+"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }
    if ($s -match 'COMMENT\s+ON\s+COLUMN\s+"?(\w+)"?\."?(\w+)"?\.') {
        return "$($matches[1]).$($matches[2])"
    }

    # GRANT ... ON TABLE/VIEW
    if ($s -match 'GRANT\s+.*\s+ON\s+(?:TABLE\s+)?"?(\w+)"?\."?(\w+)"?') {
        return "$($matches[1]).$($matches[2])"
    }

    return $null
}
