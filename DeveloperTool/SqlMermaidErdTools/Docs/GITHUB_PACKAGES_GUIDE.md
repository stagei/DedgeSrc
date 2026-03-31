# SqlMermaidErdTools - GitHub Packages Guide

This guide explains how to publish SqlMermaidErdTools as a private NuGet package on GitHub Packages, and how to consume it in your projects.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Publishing the Package](#publishing-the-package)
4. [Consuming the Package](#consuming-the-package)
5. [CI/CD Integration](#cicd-integration)
6. [Troubleshooting](#troubleshooting)

---

## Overview

**GitHub Packages** is a package hosting service that supports NuGet, npm, Docker, and more. It allows you to:

- ✅ Host **private** NuGet packages
- ✅ Control access via GitHub permissions
- ✅ Integrate with GitHub Actions for CI/CD
- ✅ Use standard `dotnet` CLI commands
- ✅ Version packages with semantic versioning

### Package Information

| Property | Value |
|----------|-------|
| **Package ID** | SqlMermaidErdTools |
| **Current Version** | 0.2.8 |
| **Target Framework** | .NET 10.0 |
| **Package Size** | ~22-50 MB |
| **License** | MIT |

---

## Prerequisites

### 1. Create a GitHub Personal Access Token (PAT)

1. Go to **GitHub** → **Settings** → **Developer settings**
2. Click **Personal access tokens** → **Tokens (classic)**
3. Click **"Generate new token (classic)"**
4. Configure the token:
   - **Note**: `SqlMermaidErdTools NuGet` (or any descriptive name)
   - **Expiration**: Choose appropriate duration
   - **Scopes**: Select these permissions:
     - ☑ `write:packages` (upload packages)
     - ☑ `read:packages` (download packages)
     - ☑ `delete:packages` (optional - delete package versions)
5. Click **"Generate token"**
6. **Copy the token immediately** (you won't see it again!)

> ⚠️ **Security Warning**: Never commit your PAT to source control!

### 2. Store Your Token Securely

**Option A: Environment Variable (Recommended)**

```powershell
# Windows PowerShell - Set permanently for current user
[System.Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "ghp_xxxxxxxxxxxx", [System.EnvironmentVariableTarget]::User)

# Or temporarily in current session
$env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxx"
```

```bash
# Linux/macOS - Add to ~/.bashrc or ~/.zshrc
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
```

**Option B: .NET User Secrets (for development)**

```bash
dotnet user-secrets set "GitHub:Token" "ghp_xxxxxxxxxxxx"
```

---

## Publishing the Package

### Package Types

There are two package configurations:

| Type | Size | Description |
|------|------|-------------|
| **Lightweight** | ~60 KB | Scripts only, requires system Python |
| **Full (Bundled)** | ~22-50 MB | Includes Python runtime with SQLGlot |

### Method 1: Using the Publish Script (Recommended)

We provide a PowerShell script that automates the entire process:

```powershell
# Navigate to repository root
cd C:\opt\src\SqlMermaidErdTools

# Publish with explicit credentials
.\Scripts\Publish-ToGitHubPackages.ps1 `
    -GitHubUsername "YOUR_GITHUB_USERNAME" `
    -GitHubToken "ghp_xxxxxxxxxxxx"

# Or use environment variable for token
$env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxx"
.\Scripts\Publish-ToGitHubPackages.ps1 -GitHubUsername "YOUR_GITHUB_USERNAME"

# Build only (no publish)
.\Scripts\Publish-ToGitHubPackages.ps1 -BuildOnly
```

### Building with Bundled Runtime (Full Package)

To create the full package with bundled Python runtime:

```powershell
# This downloads Python + SQLGlot and bundles them
.\Scripts\Build-NuGetPackage.ps1 -RuntimeId win-x64

# Then publish
.\Scripts\Publish-ToGitHubPackages.ps1 -GitHubUsername "YOUR_USERNAME" -GitHubToken "TOKEN"
```

### Method 2: Manual Publishing

```powershell
# Step 1: Build the package
dotnet pack src/SqlMermaidErdTools/SqlMermaidErdTools.csproj `
    --configuration Release `
    --output ./nupkg

# Step 2: Publish to GitHub Packages
dotnet nuget push "./nupkg/SqlMermaidErdTools.0.2.8.nupkg" `
    --source "https://nuget.pkg.github.com/YOUR_USERNAME/index.json" `
    --api-key "ghp_xxxxxxxxxxxx"
```

### Verification

After publishing, verify your package at:
```
https://github.com/stagei?tab=packages
```

Or directly at:
```
https://github.com/stagei/SqlMermaidErdTools/packages
```

---

## Consuming the Package

### Step 1: Add GitHub Packages Source

**One-time setup** - Add the GitHub Packages source to your NuGet configuration:

```powershell
# Add the source with credentials
dotnet nuget add source "https://nuget.pkg.github.com/stagei/index.json" `
    --name "github-sqlmermaid" `
    --username "YOUR_GITHUB_USERNAME" `
    --password "YOUR_PAT_TOKEN" `
    --store-password-in-clear-text
```

Or add to your project's `nuget.config`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="github-sqlmermaid" value="https://nuget.pkg.github.com/stagei/index.json" />
  </packageSources>
  <packageSourceCredentials>
    <github-sqlmermaid>
      <add key="Username" value="YOUR_GITHUB_USERNAME" />
      <add key="ClearTextPassword" value="YOUR_PAT_TOKEN" />
    </github-sqlmermaid>
  </packageSourceCredentials>
</configuration>
```

> 💡 **Tip**: For CI/CD, use environment variables instead of hardcoded tokens.

### Step 2: Install the Package

```powershell
# Install latest version
dotnet add package SqlMermaidErdTools

# Install specific version
dotnet add package SqlMermaidErdTools --version 0.2.8
```

### Step 3: Use in Your Code

```csharp
using SqlMermaidErdTools;
using SqlMermaidErdTools.Models;

// SQL → Mermaid ERD
var sqlDdl = @"
CREATE TABLE Customer (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE
);
";

var mermaid = SqlMermaidErdTools.ToMermaid(sqlDdl);
Console.WriteLine(mermaid);

// Mermaid → SQL
var sql = SqlMermaidErdTools.ToSql(mermaid, SqlDialect.PostgreSql);
Console.WriteLine(sql);
```

---

## CI/CD Integration

### GitHub Actions Workflow

Create `.github/workflows/publish-nuget.yml`:

```yaml
name: Publish NuGet Package

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to publish (leave empty to use project version)'
        required: false

jobs:
  publish:
    runs-on: windows-latest
    
    permissions:
      contents: read
      packages: write
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '10.0.x'
    
    - name: Setup Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.11'
    
    - name: Install SQLGlot
      run: pip install sqlglot
    
    - name: Restore dependencies
      run: dotnet restore
    
    - name: Build
      run: dotnet build --configuration Release --no-restore
    
    - name: Test
      run: dotnet test --configuration Release --no-build --verbosity normal
    
    - name: Pack
      run: dotnet pack src/SqlMermaidErdTools/SqlMermaidErdTools.csproj --configuration Release --output ./nupkg
    
    - name: Publish to GitHub Packages
      run: |
        dotnet nuget add source --username ${{ github.actor }} --password ${{ secrets.GITHUB_TOKEN }} --store-password-in-clear-text --name github "https://nuget.pkg.github.com/${{ github.repository_owner }}/index.json"
        dotnet nuget push "./nupkg/*.nupkg" --source "github" --api-key ${{ secrets.GITHUB_TOKEN }} --skip-duplicate
    
    - name: Upload Package Artifact
      uses: actions/upload-artifact@v4
      with:
        name: nuget-package
        path: ./nupkg/*.nupkg
```

### Consuming in CI/CD

For projects that consume this package in CI/CD:

```yaml
# In your consuming project's workflow
- name: Add GitHub Packages Source
  run: |
    dotnet nuget add source "https://nuget.pkg.github.com/OWNER_USERNAME/index.json" \
      --name github-sqlmermaid \
      --username ${{ github.actor }} \
      --password ${{ secrets.PACKAGES_PAT }} \
      --store-password-in-clear-text

- name: Restore dependencies
  run: dotnet restore
```

> 📝 **Note**: Use a secret named `PACKAGES_PAT` with `read:packages` scope for consuming packages.

---

## Troubleshooting

### Error: "401 Unauthorized"

**Cause**: Invalid or expired token.

**Solution**:
1. Verify your PAT hasn't expired
2. Check token has `write:packages` scope (for publishing)
3. Ensure username matches token owner

```powershell
# Test your token
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
```

### Error: "403 Forbidden"

**Cause**: Insufficient permissions.

**Solution**:
1. Token needs `write:packages` scope
2. For organization repos, check organization permissions
3. Verify repository visibility settings

### Error: "Package source not found"

**Cause**: Source not configured correctly.

**Solution**:
```powershell
# List configured sources
dotnet nuget list source

# Remove and re-add source
dotnet nuget remove source github-sqlmermaid
dotnet nuget add source "https://nuget.pkg.github.com/OWNER/index.json" --name github-sqlmermaid --username USER --password TOKEN --store-password-in-clear-text
```

### Error: "Unable to load the service index"

**Cause**: Network or authentication issue.

**Solution**:
1. Check internet connectivity
2. Verify the URL format: `https://nuget.pkg.github.com/OWNER/index.json`
3. Ensure credentials are correct

### Package Not Appearing in Search

**Note**: GitHub Packages can take a few minutes to index new packages.

**Workarounds**:
1. Wait 5-10 minutes and refresh
2. Install by exact version: `dotnet add package SqlMermaidErdTools --version 0.2.8`
3. Check the packages tab on your GitHub profile

---

## Package Visibility

### Making Package Public

To make your package publicly accessible (no authentication needed to consume):

1. The source repository must be **public**, OR
2. Go to **Package Settings** → **Change visibility** → **Public**

### Private Package Access

For private packages, consumers need:
1. A GitHub account
2. A PAT with `read:packages` scope
3. Access to the repository (for repo-linked packages)

---

## Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

To update the version, edit `src/SqlMermaidErdTools/SqlMermaidErdTools.csproj`:

```xml
<PropertyGroup>
  <Version>0.2.9</Version>  <!-- Update this -->
</PropertyGroup>
```

---

## Pricing & Limits

| GitHub Plan | Storage | Data Transfer |
|-------------|---------|---------------|
| **Free** | 500 MB | 1 GB/month |
| **Pro** | 2 GB | 10 GB/month |
| **Team** | 2 GB | 10 GB/month |
| **Enterprise** | 50 GB | 100 GB/month |

**Current package size**: ~22-50 MB per version

---

## Quick Reference

### Publish

```powershell
.\Scripts\Publish-ToGitHubPackages.ps1 -GitHubUsername "stagei" -GitHubToken "ghp_YOUR_TOKEN"
```

### Add Source (Consumer)

```powershell
dotnet nuget add source "https://nuget.pkg.github.com/stagei/index.json" --name github-sqlmermaid --username YOUR_USERNAME --password YOUR_PAT --store-password-in-clear-text
```

### Install Package

```powershell
dotnet add package SqlMermaidErdTools
```

### View Packages

```
https://github.com/stagei?tab=packages
```

---

## Support

- **Documentation**: See `README.md` and other docs in `/Docs`
- **Issues**: Create an issue on GitHub
- **Email**: SqlMermaidErdTools@dedge.no

---

## Related Documentation

- [README.md](../README.md) - Main project documentation
- [NUGET_PUBLISHING_GUIDE.md](NUGET_PUBLISHING_GUIDE.md) - Publishing to NuGet.org
- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical architecture
- [TESTING_STRATEGY.md](TESTING_STRATEGY.md) - Testing approach

---

*Last updated: December 2025*

