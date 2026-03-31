# InitMachine Build and Publish Configuration

This document explains how to configure the build and publish process for InitMachine, including the automatic signing of published artifacts.

## Project Structure

The project requires two main configuration files:

1. `InitMachine.csproj` - Main project file
2. `Properties/PublishProfiles/FolderProfile.pubxml` - Publish profile configuration

## Project File Configuration (InitMachine.csproj)

The project file needs the following configuration:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <!-- Basic project properties -->
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <!-- Signing target that runs after publish -->
  <Target Name="CustomActionsAfterPublish" AfterTargets="Publish">
    <Message Text="Sigining files using DedgeSign" Importance="high" />
    <Exec Command="pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command &quot;cd $(PublishDir); AutoSign.cmd $(PublishDir).&quot;" />
    <Message Text="Signing process completed" Importance="high" />
  </Target>
</Project>
```

### Important Points about Project Configuration:
- The signing target is named `CustomActionsAfterPublish`
- It runs after the `Publish` target using `AfterTargets="Publish"`
- High importance messages are included for build logging
- The signing command uses PowerShell to execute the signing script

## Publish Profile Configuration (FolderProfile.pubxml)

The publish profile should be located at `Properties/PublishProfiles/FolderProfile.pubxml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <PropertyGroup>
    <Configuration>Release</Configuration>
    <Platform>Any CPU</Platform>
    <PublishDir>A:\DevTools.NET\InitMachine</PublishDir>
    <PublishProtocol>FileSystem</PublishProtocol>
    <_TargetId>Folder</_TargetId>
  </PropertyGroup>
</Project>
```

### Important Points about Publish Configuration:
- Uses `FileSystem` publish protocol for local folder publishing
- Specifies the output directory where files will be published
- Configuration is set to `Release` by default
- Platform is set to `Any CPU`

## Publishing Process

To publish the project with signing:

```powershell
dotnet publish InitMachine.csproj -c Release
```

This will:
1. Build the project in Release configuration
2. Publish to the specified directory (A:\DevTools.NET\InitMachine)
3. Execute the signing process on the published files

## Signing Process

The signing process:
1. Changes to the publish directory
2. Executes `autoSign.cmd` with the current directory as parameter
3. Signs all executable files (*.exe, *.dll) in the directory
4. Provides feedback through build messages

## Requirements

- PowerShell 7+ installed
- DedgeSign tool available at the expected path
- Write access to the publish directory
- .NET SDK 8.0 or later

## Troubleshooting

If signing fails:
1. Check that PowerShell is available in PATH
2. Verify DedgeSign tool is installed and accessible
3. Ensure write permissions to the publish directory
4. Check build output with increased verbosity:
   ```powershell
   dotnet publish InitMachine.csproj -c Release -v detailed
   ```

## Notes

- The signing process is integrated into the publish workflow
- No manual intervention is required after configuration
- Build logs will show signing progress and results
- The process is designed to work with CI/CD pipelines 