# Deployment Guide for DedgeCommon

This document outlines the process for deploying the DedgeCommon library as a NuGet package to Azure DevOps artifacts.

## Prerequisites

1. Azure DevOps account with appropriate permissions
2. .NET SDK installed
3. Access to the Dedge feed in Azure DevOps

## Configuration Steps

### 1. Configure NuGet Source

First, ensure your NuGet configuration is properly set up:

```powershell
# Remove any existing sources to avoid conflicts
dotnet nuget remove source "DedgeFeed"
dotnet nuget remove source "Dedge"

# Add the Azure DevOps feed
dotnet nuget add source "https://pkgs.dev.azure.com/Dedge/Dedge/_packaging/Dedge/nuget/v3/index.json" `
    --name "Dedge" `
    --username "geir.helge.starholm@Dedge.no" `
    --password "3yiMpjXRWsJlIrVaVeE9GIU1lE5EkmAjFrTon3ixnPZhgGbLYcooJQQJ99BLACAAAAAMSOigAAASAZDO2p9d" `
    --store-password-in-clear-text

```

	


### 2. Build the Package

```powershell
# Build in Release mode
dotnet build --configuration Release

# Create the NuGet package
dotnet pack --configuration Release
```

### 3. Push to Azure DevOps

```powershell
# Push the package to Azure DevOps
dotnet nuget push --source "Dedge" `
    --api-key "az" `
    "bin/Release/Dedge.DedgeCommon.*.nupkg" `
    --skip-duplicate
```

## Version Management

- Update the version number in the project file before building
- Follow semantic versioning (MAJOR.MINOR.PATCH)
- Use the `--skip-duplicate` flag to avoid version conflicts

## Troubleshooting

1. If authentication fails:
   - Verify your PAT token has package read/write permissions
   - Ensure your Azure DevOps account has appropriate access

2. If push fails:
   - Check if the version already exists
   - Verify the package was built correctly
   - Ensure you have write permissions to the feed

## Security Notes

- Never commit PAT tokens to source control
- Rotate PAT tokens periodically
- Use environment variables or Azure KeyVault for sensitive credentials

## CI/CD Pipeline

For automated deployments, configure your Azure Pipeline with these steps:

```yaml
steps:
- task: DotNetCoreCLI@2
  inputs:
    command: 'build'
    projects: '**/DedgeCommon.csproj'
    arguments: '--configuration Release'

- task: DotNetCoreCLI@2
  inputs:
    command: 'pack'
    packagesToPack: '**/DedgeCommon.csproj'
    configuration: 'Release'
    versioningScheme: 'off'

- task: NuGetCommand@2
  inputs:
    command: 'push'
    feedsToUse: 'select'
    publishVstsFeed: 'Dedge'
    allowPackageConflicts: true
```

## Post-Deployment Verification

1. Check the package is visible in Azure DevOps artifacts
2. Verify the package can be installed in a test project
3. Run integration tests against the deployed package

For any deployment issues, contact the development team or refer to the Azure DevOps documentation. 