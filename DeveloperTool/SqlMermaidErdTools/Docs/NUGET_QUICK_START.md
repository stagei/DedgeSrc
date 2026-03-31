# Quick Start: Publishing to NuGet.org

## 🚀 First Time Setup (5 minutes)

### 1. Get NuGet API Key
1. Go to https://www.nuget.org and sign in
2. Go to https://www.nuget.org/account/apikeys
3. Click **Create**
4. Fill in:
   - **Key Name**: `SqlMermaidErdTools`
   - **Glob Pattern**: `SqlMermaidErdTools*`
   - **Expiration**: 365 days (or never)
   - **Scopes**: ☑ Push new packages and package versions
5. Click **Create** and **COPY THE KEY** (shown only once!)

### 2. Optional: Create GitHub Repository
1. Go to https://github.com/new
2. Repository name: `SqlMermaidErdTools`
3. Make it **Public**
4. Add MIT License
5. Create repository

```bash
# In your project folder
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/SqlMermaidErdTools.git
git branch -M main
git push -u origin main
```

## 📦 Build & Test Package Locally

```powershell
# Build package only (no publishing)
.\publish-nuget.ps1 -BuildOnly

# Package will be in ./nupkg/ folder
# Test it locally before publishing!
```

## 🌐 Publish to NuGet.org

```powershell
# Publish to NuGet.org (for real!)
.\publish-nuget.ps1 -ApiKey "YOUR_API_KEY_HERE"
```

That's it! Wait 5-15 minutes for indexing.

## ✅ Verify Publication

Check: https://www.nuget.org/packages/SqlMermaidErdTools

## 📝 For Future Updates

1. **Update version** in `src/SqlMermaidErdTools/SqlMermaidErdTools.csproj`:
   ```xml
   <Version>0.2.0</Version>
   <PackageReleaseNotes>Added new features...</PackageReleaseNotes>
   ```

2. **Publish**:
   ```powershell
   .\publish-nuget.ps1 -ApiKey "YOUR_API_KEY"
   ```

## 🎯 Common Commands

```powershell
# Build only
.\publish-nuget.ps1 -BuildOnly

# Build and publish
.\publish-nuget.ps1 -ApiKey "oy2..."

# Skip tests (not recommended)
.\publish-nuget.ps1 -BuildOnly -SkipTests
```

## 📖 Full Documentation

See **NUGET_PUBLISHING_GUIDE.md** for complete details.

## 🆘 Troubleshooting

**"Version already exists"**
- Update `<Version>` in SqlMermaidErdTools.csproj
- You cannot republish the same version

**"Package too large"**
- Our package is ~50MB due to bundled Python runtime
- This is expected and acceptable for now

**"Tests failed"**
- Fix failing tests before publishing
- Or use `-SkipTests` (not recommended)

**"API key invalid"**
- Get new key from https://www.nuget.org/account/apikeys
- Make sure you copied it correctly (no extra spaces)
- Ensure glob pattern includes `SqlMermaidErdTools*`

## 💡 Tips

- ✅ Always test locally first (`-BuildOnly`)
- ✅ Run tests before publishing
- ✅ Update release notes in .csproj
- ✅ Tag releases in Git: `git tag v0.1.0`
- ✅ Keep API key secret (don't commit it!)
- ❌ Cannot delete packages (only unlist them)
- ❌ Cannot republish same version

