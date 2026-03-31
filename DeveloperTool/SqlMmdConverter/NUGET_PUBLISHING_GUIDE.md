# Publishing SqlMmdConverter to NuGet.org

## Prerequisites

1. **NuGet.org Account**
   - Go to https://www.nuget.org
   - Sign in or create an account (can use Microsoft/GitHub account)

2. **API Key**
   - Once logged in, go to https://www.nuget.org/account/apikeys
   - Click "Create"
   - Give it a name like "Sql2MermaidErdConverter Publishing"
   - Select expiration (365 days recommended, or never expire)
   - **Glob Pattern**: `Sql2MermaidErdConverter*` (to restrict to your package)
   - **Scopes**: Select "Push new packages and package versions"
   - Click "Create"
   - **IMPORTANT**: Copy the API key immediately (shown only once)

3. **GitHub Repository** (Optional but recommended)
   - Create a public repository at https://github.com/new
   - Repository name: `SqlMmdConverter`
   - Description: "Bidirectional converter between SQL DDL and Mermaid ERD diagrams"
   - Set to Public
   - Initialize with README (you can overwrite it)
   - Choose MIT License

## Step-by-Step Publishing

### 1. Push to GitHub (if using)

```bash
# Initialize git if not done
git init

# Add all files
git add .

# Commit
git commit -m "Initial release v0.1.0"

# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/geirtul/SqlMmdConverter.git

# Push
git push -u origin main
```

### 2. Build the NuGet Package

```powershell
# Build the package
.\publish-nuget.ps1 -BuildOnly
```

Or manually:
```powershell
dotnet pack src/SqlMmdConverter/SqlMmdConverter.csproj `
  --configuration Release `
  --output ./nupkg `
  /p:IncludeSymbols=true `
  /p:SymbolPackageFormat=snupkg
```

This creates:
- `nupkg/SqlMmdConverter.0.1.0.nupkg` - Main package
- `nupkg/SqlMmdConverter.0.1.0.snupkg` - Symbol package (for debugging)

### 3. Test the Package Locally (Optional)

```powershell
# Create a test project
dotnet new console -n TestSqlMmdConverter
cd TestSqlMmdConverter

# Add local package source
dotnet nuget add source D:\opt\src\SqlMmdConverter\nupkg -n LocalTest

# Install your package
dotnet add package SqlMmdConverter --version 0.1.0

# Test it works
# (modify Program.cs to use SqlMmdConverter)
```

### 4. Publish to NuGet.org

**Option A: Use the helper script**
```powershell
.\publish-nuget.ps1 -ApiKey "YOUR_API_KEY_HERE"
```

**Option B: Manual publish**
```powershell
dotnet nuget push nupkg/SqlMmdConverter.0.1.0.nupkg `
  --api-key YOUR_API_KEY_HERE `
  --source https://api.nuget.org/v3/index.json
```

The symbol package (.snupkg) is automatically uploaded with the main package.

### 5. Verify Publication

1. Go to https://www.nuget.org/packages/Sql2MermaidErdConverter
2. It may take 5-15 minutes to appear and be indexed
3. Check the package details, readme, and dependencies

## Publishing Updates

When you release a new version:

1. **Update version in `.csproj`:**
   ```xml
   <Version>0.2.0</Version>
   <PackageReleaseNotes>Added Mermaid to SQL conversion...</PackageReleaseNotes>
   ```

2. **Commit and tag:**
   ```bash
   git commit -am "Release v0.2.0"
   git tag v0.2.0
   git push origin main --tags
   ```

3. **Build and publish:**
   ```powershell
   .\publish-nuget.ps1 -ApiKey "YOUR_API_KEY"
   ```

## Package Size Note

⚠️ **Warning**: This package bundles Python runtime (~50 MB for win-x64).

- Consider creating platform-specific packages:
  - `SqlMmdConverter.Runtime.Windows`
  - `SqlMmdConverter.Runtime.Linux`
  - `SqlMmdConverter.Runtime.MacOS`
- Main package can depend on the appropriate runtime package

For now, we're shipping a single win-x64 package for simplicity.

## Best Practices

1. **Semantic Versioning**: Use MAJOR.MINOR.PATCH (e.g., 1.0.0)
   - MAJOR: Breaking changes
   - MINOR: New features (backward compatible)
   - PATCH: Bug fixes

2. **Release Notes**: Always update `PackageReleaseNotes` in .csproj

3. **Git Tags**: Tag releases in git (`git tag v0.1.0`)

4. **Changelog**: Maintain CHANGELOG.md with all changes

5. **Security**: Never commit your API key to git

6. **Testing**: Always test the package locally before publishing

## Unlisting a Package

If you need to unlist a version (doesn't delete it, but hides from search):

1. Go to https://www.nuget.org/packages/Sql2MermaidErdConverter/
2. Click on the version
3. Click "Manage Package" (top right)
4. Click "Unlist"

**Note**: You cannot delete packages from NuGet.org, only unlist them.

## Support and Documentation

After publishing:

1. Update GitHub README with installation instructions
2. Add examples and usage documentation
3. Set up GitHub Issues for support
4. Consider adding GitHub Actions for automated publishing
5. Add badges to README:
   ```markdown
   [![NuGet](https://img.shields.io/nuget/v/Sql2MermaidErdConverter.svg)](https://www.nuget.org/packages/Sql2MermaidErdConverter/)
   [![NuGet Downloads](https://img.shields.io/nuget/dt/Sql2MermaidErdConverter.svg)](https://www.nuget.org/packages/Sql2MermaidErdConverter/)
   ```

## License

This package uses MIT License, which is:
- ✅ Free for commercial use
- ✅ Free for private use
- ✅ Free to modify and distribute
- ✅ No warranty provided

The LICENSE file in your repository contains the full license text.

