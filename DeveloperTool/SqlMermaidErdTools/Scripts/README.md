# Scripts

PowerShell scripts for building, testing, and publishing SqlMermaidErdTools.

## Build & Publish Scripts

### Build-NuGetPackage.ps1
**Purpose:** Builds the SqlMermaidErdTools NuGet package with bundled Python and Node.js runtimes

**Usage:**
```powershell
.\Scripts\Build-NuGetPackage.ps1 -RuntimeId win-x64
.\Scripts\Build-NuGetPackage.ps1 -RuntimeId win-x64 -SkipDownload
.\Scripts\Build-NuGetPackage.ps1 -RuntimeId linux-x64 -Configuration Debug
```

**Parameters:**
- `RuntimeId` - Target runtime (win-x64, linux-x64, osx-x64)
- `SkipDownload` - Skip downloading runtimes if they already exist
- `Configuration` - Build configuration (Debug or Release)

**What it does:**
- Downloads portable Python and Node.js runtimes
- Installs SQLGlot and little-mermaid-2-the-sql dependencies
- Builds and packages everything into a platform-specific NuGet package

---

### Publish-ToNuGet.ps1
**Purpose:** Builds and publishes SqlMermaidErdTools to NuGet.org

**Usage:**
```powershell
.\Scripts\Publish-ToNuGet.ps1 -ApiKey YOUR_API_KEY
.\Scripts\Publish-ToNuGet.ps1 -BuildOnly
```

**Parameters:**
- `ApiKey` - NuGet API key for publishing (get from https://www.nuget.org/account/apikeys)
- `BuildOnly` - Only build the package without publishing

**What it does:**
- Checks package version
- Builds the NuGet package
- Runs tests
- Publishes to NuGet.org (if ApiKey provided)

---

### Publish-ToGitHubPackages.ps1
**Purpose:** Builds and publishes SqlMermaidErdTools to GitHub Packages (private NuGet registry)

**Usage:**
```powershell
# Publish with explicit credentials
.\Scripts\Publish-ToGitHubPackages.ps1 -GitHubUsername "YOUR_USERNAME" -GitHubToken "ghp_xxxx"

# Use environment variable for token
$env:GITHUB_TOKEN = "ghp_xxxx"
.\Scripts\Publish-ToGitHubPackages.ps1 -GitHubUsername "YOUR_USERNAME"

# Build only (no publish)
.\Scripts\Publish-ToGitHubPackages.ps1 -BuildOnly
```

**Parameters:**
- `GitHubUsername` - Your GitHub username or organization name
- `GitHubToken` - GitHub Personal Access Token with `write:packages` scope
- `BuildOnly` - Only build the package without publishing
- `SkipTests` - Skip running tests before building
- `OutputPath` - Output directory for .nupkg files (default: ./nupkg)

**What it does:**
- Builds the NuGet package
- Runs tests (optional)
- Publishes to GitHub Packages (your private NuGet registry)
- Displays installation instructions after publish

**Prerequisites:**
1. Create a GitHub PAT with `write:packages` scope
2. See [GITHUB_PACKAGES_GUIDE.md](../Docs/GITHUB_PACKAGES_GUIDE.md) for detailed setup

---

## Testing Scripts

### Convert-SqlToMermaid.ps1
**Purpose:** Converts SQL DDL files to Mermaid ERD diagrams

**Usage:**
```powershell
.\Scripts\Convert-SqlToMermaid.ps1 test.sql
.\Scripts\Convert-SqlToMermaid.ps1 D:\opt\src\SqlMermaidErdTools\test.sql -ExportMarkdown
```

**Parameters:**
- `InputFile` - Path to the SQL file to convert (required)
- `ExportMarkdown` - Export as Markdown with embedded Mermaid diagram (.md file)

**What it does:**
- Auto-detects SqlMermaidErdTools.exe or Python runtime
- Converts SQL file to Mermaid ERD format
- Outputs .mmd or .md file (based on ExportMarkdown flag)

---

### Test-SqlConversion.ps1
**Purpose:** Simple test script for SQL to Mermaid conversion

**Usage:**
```powershell
.\Scripts\Test-SqlConversion.ps1
```

**What it does:**
- Converts `test.sql` to `test.mmd` using bundled Python runtime
- Shows conversion output and errors

**Note:** Requires `test.sql` file in project root and bundled Python runtime

---

## Debug Scripts (Python)

### Debug-SqlGlotParsing.py
**Purpose:** Debug script to test SQLGlot parsing of SQL statements

**Usage:**
```bash
python Scripts/Debug-SqlGlotParsing.py
```

**What it does:**
- Parses sample SQL with CREATE TABLE and CREATE INDEX statements
- Shows parsed statement types and structure
- Useful for debugging SQLGlot parsing issues

---

### Debug-IndexStructure.py
**Purpose:** Debug script to inspect SQLGlot's internal structure for CREATE INDEX statements

**Usage:**
```bash
python Scripts/Debug-IndexStructure.py
```

**What it does:**
- Parses a CREATE INDEX statement
- Displays all attributes and internal structure
- Shows how SQLGlot represents indexes
- Useful for understanding SQLGlot's AST structure

---

## Notes

- All scripts should be run from the **project root directory**
- Scripts use relative paths to `src\SqlMermaidErdTools\`
- Build scripts require:
  - .NET 10 SDK
  - Internet connection (for first-time runtime downloads)
- Publishing requires a NuGet API key from https://www.nuget.org

## Directory Structure

```
SqlMermaidErdTools/
├── Scripts/                        ← You are here
│   ├── Build-NuGetPackage.ps1
│   ├── Publish-ToNuGet.ps1
│   ├── Publish-ToGitHubPackages.ps1
│   ├── Convert-SqlToMermaid.ps1
│   ├── Test-SqlConversion.ps1
│   └── README.md
├── nuget.config                    ← NuGet source configuration
├── src/
│   └── SqlMermaidErdTools/
│       ├── scripts/                ← Python conversion scripts
│       └── runtimes/               ← Bundled Python/Node.js runtimes
├── Docs/
│   ├── GITHUB_PACKAGES_GUIDE.md    ← Complete GitHub Packages guide
│   └── ...
└── ...
```


