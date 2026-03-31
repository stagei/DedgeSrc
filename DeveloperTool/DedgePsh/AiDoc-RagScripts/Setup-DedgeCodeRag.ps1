<#
.SYNOPSIS
    Bootstrap the Dedge-code RAG folder structure, database metadata templates, and config.

.DESCRIPTION
    Creates library/Dedge-code/ with:
      - _databases/ folder containing placeholder markdown for each known DB2 database
      - .Dedge-rag-config.json with repos, extensions, excludes
    Run once. After this, run Import-DedgeCodeToRag.ps1 to populate code metadata.

.PARAMETER AiDocRoot
    Root of the AiDoc folder. Default: $env:OptPath\FkPythonApps\AiDoc

.EXAMPLE
    pwsh.exe -File Setup-DedgeCodeRag.ps1
#>
[CmdletBinding()]
param(
    [string]$AiDocRoot
)

$ErrorActionPreference = 'Stop'

if (-not $AiDocRoot) {
    if (-not $env:OptPath) { throw 'Environment variable OptPath is not set.' }
    $candidates = @(
        (Join-Path $env:OptPath 'FkPythonApps\AiDoc'),
        (Join-Path $env:OptPath 'src\AiDoc')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'mcp-ai-docs')) {
            $AiDocRoot = $c
            break
        }
    }
    if (-not $AiDocRoot) { $AiDocRoot = Join-Path $env:OptPath 'FkPythonApps\AiDoc' }
}

$ragName    = 'Dedge-code'
$libraryDir = Join-Path $AiDocRoot 'library'
$ragDir     = Join-Path $libraryDir $ragName
$dbDir      = Join-Path $ragDir '_databases'
$configFile = Join-Path $ragDir '.Dedge-rag-config.json'

Write-Host "[1/3] Creating folder structure..." -ForegroundColor Cyan

foreach ($dir in @($ragDir, $dbDir, (Join-Path $ragDir 'code'))) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "       Created: $dir" -ForegroundColor DarkGray
    }
}

Write-Host "[2/3] Writing database metadata templates..." -ForegroundColor Cyan

$databases = @(
    @{ Name = 'BASISPRO';  Desc = 'Dedge production database (FKMPRD on p-no1fkmprd-db). COBOL programs reference this via the alias FKAVDNT. BASISRAP is a daily restore of this database.' }
    @{ Name = 'BASISHST';  Desc = 'Dedge production history database (FKMHST on p-no1fkmprd-db). Stores historical transaction and product data.' }
    @{ Name = 'FKKONTO';   Desc = 'Innlan production database (INLPRD on p-no1inlprd-db). Account/financial database.' }
    @{ Name = 'COBDOK';    Desc = 'COBOL documentation database (DOCPRD on p-no1docprd-db). Stores generated program documentation.' }
)

foreach ($db in $databases) {
    $mdPath = Join-Path $dbDir "$($db.Name).md"
    if (-not (Test-Path -LiteralPath $mdPath)) {
        $content = @"
# $($db.Name)

$($db.Desc)

## Connection

- **Type:** DB2 LUW
- **Environment:** Production / Test

## Tables

<!-- Add table descriptions below. Example:

### TABLENAME

| Column | Type | Description |
|--------|------|-------------|
| COL1   | CHAR(10) | Primary key |
| COL2   | DECIMAL(11,2) | Amount |

-->

## Notes

<!-- Add any relevant notes about this database here -->
"@
        Set-Content -LiteralPath $mdPath -Value $content -Encoding utf8
        Write-Host "       Created: $($db.Name).md" -ForegroundColor DarkGray
    } else {
        Write-Host "       Exists:  $($db.Name).md" -ForegroundColor DarkGray
    }
}

$readmePath = Join-Path $dbDir 'README.md'
if (-not (Test-Path -LiteralPath $readmePath)) {
    @"
# Database Metadata

Static documentation for the DB2 databases used by Dedge programs.
These files are indexed by the RAG alongside the source code.

Edit the markdown files to add table/column descriptions, relationships,
and notes. The RAG will include this context when answering questions
about Dedge code.

Files are never overwritten by the import scripts.
"@ | Set-Content -LiteralPath $readmePath -Encoding utf8
}

Write-Host "[3/3] Writing config..." -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $configFile)) {
    $config = [ordered]@{
        ragName = $ragName
        repos = @(
            'Dedge'
            'DedgeAvdPrint'
            'DedgeDailyRoutine'
            'DedgeICC'
            'DedgeNodeJs'
            'DedgePOS'
            'DedgePosLogSearchMergeSort'
            'DedgePosNotification'
            'DedgePsh'
            'DedgePython'
            'DedgeTelemetry'
            'VcDedgeDb2Dev'
        )
        includeExtensions = @(
            '.cbl', '.cpy', '.cpb', '.cpx',
            '.rex',
            '.dcl', '.gs', '.imp', '.cre', '.sql', '.ins',
            '.ps1',
            '.cs',
            '.py',
            '.js', '.ts',
            '.html', '.cshtml',
            '.json', '.xml', '.config',
            '.bat', '.cmd'
        )
        ansiExtensions = @(
            '.cbl', '.cpy', '.cpb', '.cpx',
            '.rex',
            '.dcl', '.gs', '.imp', '.cre', '.ins',
            '.bat', '.cmd'
        )
        excludeDirs = @(
            '.git', 'node_modules', 'bin', 'obj', 'packages',
            '.vs', '__pycache__', '.venv', 'TestResults'
        )
        languageMap = [ordered]@{
            '.cbl'    = 'cobol'
            '.cpy'    = 'cobol'
            '.cpb'    = 'cobol'
            '.cpx'    = 'cobol'
            '.rex'    = 'rexx'
            '.dcl'    = 'sql'
            '.gs'     = 'sql'
            '.imp'    = 'sql'
            '.cre'    = 'sql'
            '.sql'    = 'sql'
            '.ins'    = 'sql'
            '.ps1'    = 'powershell'
            '.cs'     = 'csharp'
            '.py'     = 'python'
            '.js'     = 'javascript'
            '.ts'     = 'typescript'
            '.html'   = 'html'
            '.cshtml' = 'html'
            '.json'   = 'json'
            '.xml'    = 'xml'
            '.config' = 'xml'
            '.bat'    = 'batch'
            '.cmd'    = 'batch'
        }
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configFile -Encoding utf8
    Write-Host "       Created: .Dedge-rag-config.json" -ForegroundColor DarkGray
} else {
    Write-Host "       Exists:  .Dedge-rag-config.json" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Setup complete. Next steps:' -ForegroundColor Green
Write-Host '  1. Edit _databases/*.md to add table/column descriptions' -ForegroundColor White
Write-Host '  2. Run Import-DedgeCodeToRag.ps1 to convert code and build the index' -ForegroundColor White
Write-Host ''
