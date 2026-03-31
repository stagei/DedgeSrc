#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test round-trip conversion: SQL → MMD → SQL and compare results
.DESCRIPTION
    This script tests the new bidirectional conversion features:
    1. Converts SQL to Mermaid
    2. Converts Mermaid back to SQL
    3. Compares original and round-trip SQL
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SqlFile = "test.sql"
)

# Colors for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Step { param([string]$Message) Write-Host "`n━━━ $Message ━━━" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║        SqlMermaidErdTools Round-Trip Test                   ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Magenta

# Check if SQL file exists
if (-not (Test-Path $SqlFile)) {
    Write-Error "SQL file not found: $SqlFile"
    exit 1
}

Write-Info "Input file: $SqlFile"
Write-Info "File size: $((Get-Item $SqlFile).Length) bytes"

# Build the project
Write-Step "Building solution"
$buildResult = dotnet build SqlMermaidErdTools.sln --configuration Release --verbosity quiet
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}
Write-Success "Build successful"

# Create test program
Write-Step "Creating test program"
$testProgram = @'
using SqlMermaidErdTools;
using SqlMermaidErdTools.Models;

if (args.Length < 1)
{
    Console.WriteLine("Usage: test-converter <sql-file>");
    return 1;
}

var sqlFile = args[0];
Console.WriteLine($"Reading SQL from: {sqlFile}");
var sql = await File.ReadAllTextAsync(sqlFile);

Console.WriteLine($"\n━━━ Step 1: SQL → Mermaid ━━━");
var mermaid = await SqlMermaidErdTools.ToMermaidAsync(sql);
var mmdFile = sqlFile + ".roundtrip.mmd";
await File.WriteAllTextAsync(mmdFile, mermaid);
Console.WriteLine($"✓ Generated Mermaid ERD ({mermaid.Length} chars)");
Console.WriteLine($"✓ Saved to: {mmdFile}");

Console.WriteLine($"\n━━━ Step 2: Mermaid → SQL (ANSI) ━━━");
var sqlFromMmd = await SqlMermaidErdTools.ToSqlAsync(mermaid, SqlDialect.AnsiSql);
var sqlRoundtripFile = sqlFile + ".roundtrip.sql";
await File.WriteAllTextAsync(sqlRoundtripFile, sqlFromMmd);
Console.WriteLine($"✓ Generated SQL DDL ({sqlFromMmd.Length} chars)");
Console.WriteLine($"✓ Saved to: {sqlRoundtripFile}");

Console.WriteLine($"\n━━━ Step 3: SQL → SQL (Translate to PostgreSQL) ━━━");
var postgresSql = await SqlMermaidErdTools.TranslateDialectAsync(sql, SqlDialect.AnsiSql, SqlDialect.PostgreSql);
var postgresFile = sqlFile + ".postgres.sql";
await File.WriteAllTextAsync(postgresFile, postgresSql);
Console.WriteLine($"✓ Translated to PostgreSQL ({postgresSql.Length} chars)");
Console.WriteLine($"✓ Saved to: {postgresFile}");

Console.WriteLine($"\n━━━ Summary ━━━");
Console.WriteLine($"Original SQL:     {sql.Length,10} chars");
Console.WriteLine($"Mermaid ERD:      {mermaid.Length,10} chars");
Console.WriteLine($"Roundtrip SQL:    {sqlFromMmd.Length,10} chars");
Console.WriteLine($"PostgreSQL SQL:   {postgresSql.Length,10} chars");

Console.WriteLine($"\n✓ All conversions completed successfully!");
Console.WriteLine($"\nGenerated files:");
Console.WriteLine($"  - {mmdFile}");
Console.WriteLine($"  - {sqlRoundtripFile}");
Console.WriteLine($"  - {postgresFile}");

return 0;
'@

$testProgramFile = "test-converter-program.cs"
Set-Content -Path $testProgramFile -Value $testProgram
Write-Success "Created test program: $testProgramFile"

# Run the test
Write-Step "Executing round-trip conversion test"
dotnet run --project src\SqlMermaidErdTools\SqlMermaidErdTools.csproj --configuration Release -- $testProgramFile $SqlFile

if ($LASTEXITCODE -eq 0) {
    Write-Success "`nRound-trip test completed successfully!"
    
    # Show file sizes
    Write-Step "Generated files comparison"
    $files = @(
        "$SqlFile.roundtrip.mmd",
        "$SqlFile.roundtrip.sql",
        "$SqlFile.postgres.sql"
    )
    
    foreach ($file in $files) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            Write-Info ("{0,-30} {1,10:N0} bytes" -f $file, $size)
        }
    }
} else {
    Write-Error "Round-trip test failed"
    exit 1
}

# Clean up test program
Remove-Item $testProgramFile -ErrorAction SilentlyContinue

