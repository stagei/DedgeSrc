# CLI Implementation Guide

## ✅ What Has Been Built

A **professional, production-ready .NET Global Tool** with built-in license validation hooks.

---

## 📁 Project Structure

```
srcCLI/
├── SqlMermaidErdTools.CLI.csproj   # CLI tool project file
├── Program.cs                       # Main entry point
├── Commands/                        # Command implementations
│   ├── SqlToMmdCommand.cs          # SQL → Mermaid conversion
│   ├── MmdToSqlCommand.cs          # Mermaid → SQL conversion
│   ├── DiffCommand.cs              # Schema diff/migration
│   ├── LicenseCommand.cs           # License management
│   └── VersionCommand.cs           # Version info
├── Services/
│   └── LicenseService.cs           # License validation & management
└── README.md                        # User documentation
```

---

## 🔧 How It Works

### Architecture

```
User runs: sqlmermaid sql-to-mmd input.sql
         ↓
    Program.cs (Main)
         ↓
    SqlToMmdCommand
         ↓
    LicenseService.ValidateOperation()
         ↓
    SqlToMmdConverter (from SqlMermaidErdTools.dll)
         ↓
    Python scripts (bundled in SqlMermaidErdTools)
         ↓
    Returns Mermaid ERD
```

### License Validation Flow

```
User runs command
         ↓
Read ~/.sqlmermaid-license file
         ↓
Parse license JSON
         ↓
Check:
  - License tier (Free/Pro/Team/Enterprise)
  - Expiry date (if applicable)
  - Table count limit
         ↓
If Free tier + >10 tables:
  → Show upgrade message
  → Exit with code 2
         ↓
Otherwise:
  → Proceed with conversion
```

---

## 🚀 Installation & Testing

### Build the CLI Tool

```powershell
# Build the project
cd D:\opt\src\SqlMermaidErdTools
dotnet build srcCLI/SqlMermaidErdTools.CLI.csproj

# Pack as tool
dotnet pack srcCLI/SqlMermaidErdTools.CLI.csproj -c Release

# Install globally (from local)
dotnet tool install -g SqlMermaidErdTools.CLI --add-source ./srcCLI/bin/Release
```

### Test It

```powershell
# Check version
sqlmermaid version

# Check license (should show Free tier)
sqlmermaid license show

# Convert SQL to Mermaid
sqlmermaid sql-to-mmd TestFiles/test.sql

# Convert with output file
sqlmermaid sql-to-mmd TestFiles/test.sql -o test.mmd

# Convert Mermaid to SQL
sqlmermaid mmd-to-sql test.mmd --dialect PostgreSql -o test_pg.sql
```

---

## 🔐 License System

### License File Location

```
Windows: C:\Users\{username}\.sqlmermaid-license
Linux:   /home/{username}/.sqlmermaid-license
macOS:   /Users/{username}/.sqlmermaid-license
```

### License File Format (JSON)

```json
{
  "Tier": "Pro",
  "Email": "user@example.com",
  "LicenseKey": "SQLMMD-PRO-XXXX-XXXX-XXXX",
  "ExpiryDate": "2025-12-31T00:00:00Z",
  "MaxTables": null
}
```

### License Tiers

| Tier | Max Tables | Features |
|------|------------|----------|
| **Free** | 10 | All dialects, community support |
| **Pro** | Unlimited | Commercial use, email support |
| **Team** | Unlimited | Team features, priority support |
| **Enterprise** | Unlimited | SLA, custom features |

### Activate a License

```powershell
# Activate Pro license
sqlmermaid license activate --key SQLMMD-PRO-1234-5678-9ABC --email you@example.com

# Show current license
sqlmermaid license show

# Deactivate (revert to Free)
sqlmermaid license deactivate
```

---

## 📋 Commands Reference

### sql-to-mmd

Convert SQL DDL to Mermaid ERD.

```powershell
sqlmermaid sql-to-mmd <input.sql> [options]

Options:
  -o, --output <file>         Output file path (stdout if not specified)
  --export-dir <directory>    Export intermediate files for debugging
```

**Examples:**
```powershell
# To stdout
sqlmermaid sql-to-mmd schema.sql

# To file
sqlmermaid sql-to-mmd schema.sql --output schema.mmd

# With debug export
sqlmermaid sql-to-mmd schema.sql -o schema.mmd --export-dir ./debug
```

---

### mmd-to-sql

Convert Mermaid ERD to SQL DDL.

```powershell
sqlmermaid mmd-to-sql <input.mmd> [options]

Options:
  -o, --output <file>         Output file path (stdout if not specified)
  -d, --dialect <dialect>     SQL dialect (AnsiSql|SqlServer|PostgreSql|MySql)
  --export-dir <directory>    Export intermediate files for debugging
```

**Examples:**
```powershell
# Default dialect (AnsiSql)
sqlmermaid mmd-to-sql schema.mmd

# PostgreSQL
sqlmermaid mmd-to-sql schema.mmd --dialect PostgreSql -o schema.sql

# All dialects
sqlmermaid mmd-to-sql schema.mmd -d AnsiSql -o ansi.sql
sqlmermaid mmd-to-sql schema.mmd -d SqlServer -o sqlserver.sql
sqlmermaid mmd-to-sql schema.mmd -d PostgreSql -o postgres.sql
sqlmermaid mmd-to-sql schema.mmd -d MySql -o mysql.sql
```

---

### diff

Generate SQL migration from Mermaid diagram changes.

```powershell
sqlmermaid diff <before.mmd> <after.mmd> [options]

Options:
  -o, --output <file>         Output migration file (stdout if not specified)
  -d, --dialect <dialect>     SQL dialect (AnsiSql|SqlServer|PostgreSql|MySql)
  --export-dir <directory>    Export intermediate files for debugging
```

**Examples:**
```powershell
# Generate migration
sqlmermaid diff schema_v1.mmd schema_v2.mmd -d PostgreSql -o migration.sql

# Review migration
cat migration.sql

# Apply to database
psql mydb < migration.sql
```

---

### license

Manage your SqlMermaid license.

```powershell
sqlmermaid license <subcommand>

Subcommands:
  show         Show current license information
  activate     Activate a license key
  deactivate   Deactivate the current license
```

**Examples:**
```powershell
# Check license
sqlmermaid license show

# Activate
sqlmermaid license activate --key SQLMMD-PRO-1234 --email you@example.com

# Deactivate
sqlmermaid license deactivate
```

---

### version

Show version information.

```powershell
sqlmermaid version
```

---

## 🔌 Integration with VS Code Extensions

The VS Code extensions (`srcVSC` and `srcVSCADV`) detect and use this CLI tool:

### Auto-Detection

```typescript
// In conversionService.ts
try {
    const result = child_process.execSync('dotnet tool list -g', { encoding: 'utf-8' });
    if (result.includes('sqlmermaiderdtools.cli')) {
        this.cliPath = 'sqlmermaid'; // ✅ Found!
    }
} catch (error) {
    console.log('CLI not found - will use API if configured');
}
```

### Calling the CLI

```typescript
// SQL → Mermaid
const command = `sqlmermaid sql-to-mmd "${tempSqlFile}" --output "${tempMmdFile}"`;
child_process.execSync(command);

// Mermaid → SQL
const command = `sqlmermaid mmd-to-sql "${tempMmdFile}" --dialect ${dialect} --output "${tempSqlFile}"`;
child_process.execSync(command);
```

---

## 💡 License Validation Implementation

### Table Counting

Each command counts tables in the input/output:

```csharp
private static int CountTables(string mermaid)
{
    var lines = mermaid.Split('\n');
    return lines.Count(line => 
        line.Trim().EndsWith("{") && 
        !line.TrimStart().StartsWith("%%")
    );
}
```

### Validation Check

```csharp
var license = licenseService.GetLicense();
var validation = licenseService.ValidateOperation(tableCount);

if (!validation.IsValid)
{
    Console.Error.WriteLine($"❌ {validation.Message}");
    
    if (validation.Tier == LicenseTier.Free)
    {
        Console.Error.WriteLine(licenseService.GetUpgradeMessage());
    }
    
    Environment.Exit(2); // Exit with code 2 (license error)
    return;
}
```

### Upgrade Message

Free tier users see:

```
╔══════════════════════════════════════════════════════════════════════╗
║                    UPGRADE TO PRO                                    ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  🚀 Unlimited Tables                                                 ║
║  🎯 All SQL Dialects                                                 ║
║  ⚡ Priority Support                                                 ║
║  🔄 Commercial Use License                                           ║
║                                                                      ║
║  Individual: $99/year or $249 perpetual                             ║
║  Team (5):   $399/year                                              ║
║  Enterprise: $1,999/year                                            ║
║                                                                      ║
║  Visit: https://sqlmermaid.tools/pricing                            ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## 🚀 Publishing to NuGet.org

### 1. Build Release Package

```powershell
dotnet pack srcCLI/SqlMermaidErdTools.CLI.csproj -c Release
```

### 2. Publish to NuGet

```powershell
dotnet nuget push srcCLI/bin/Release/SqlMermaidErdTools.CLI.0.2.0.nupkg `
    --api-key $env:NUGET_API_KEY_SQL2MMD `
    --source https://api.nuget.org/v3/index.json
```

### 3. Users Install

```powershell
dotnet tool install -g SqlMermaidErdTools.CLI
```

---

## 📊 Exit Codes

| Code | Meaning | Example |
|------|---------|---------|
| `0` | Success | Conversion completed successfully |
| `1` | Conversion error | Invalid SQL syntax, file not found |
| `2` | License validation failed | Table limit exceeded, expired license |

---

## 🔮 Future Enhancements

### Phase 1: Online License Validation (Planned)

```csharp
public async Task<ActivationResult> ActivateLicenseAsync(string licenseKey, string email)
{
    // Call license server API
    var response = await httpClient.PostAsync(
        "https://api.sqlmermaid.tools/v1/licenses/activate",
        new { licenseKey, email }
    );
    
    if (response.IsSuccessStatusCode)
    {
        var license = await response.Content.ReadFromJsonAsync<LicenseInfo>();
        // Save to local file
        await SaveLicenseAsync(license);
        return new ActivationResult { Success = true, License = license };
    }
    
    return new ActivationResult { Success = false, Message = "Invalid license key" };
}
```

### Phase 2: Offline License Validation

Use JWT tokens or license file signatures for offline validation.

### Phase 3: Usage Analytics

Track anonymous usage statistics for product improvement.

---

## ✅ Testing Checklist

- [ ] Build succeeds without errors
- [ ] Install as global tool works
- [ ] `sqlmermaid version` shows correct version
- [ ] `sqlmermaid license show` shows Free tier by default
- [ ] SQL → Mermaid conversion works
- [ ] Mermaid → SQL conversion works for all 4 dialects
- [ ] Diff command generates valid ALTER statements
- [ ] Table limit enforced for Free tier (>10 tables fails)
- [ ] License activate/deactivate works
- [ ] Exit codes correct (0, 1, 2)
- [ ] Help text displays for all commands
- [ ] VS Code extensions can find and use the CLI

---

## 📚 Related Documentation

- **User Guide**: `srcCLI/README.md`
- **License Guide**: `Docs/LICENSING_MONETIZATION_GUIDE.md`
- **Main README**: `README.md`

---

Made with ❤️ for the SqlMermaidErdTools project

