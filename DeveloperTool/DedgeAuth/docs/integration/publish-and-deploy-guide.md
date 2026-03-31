# Publish Profiles and IIS Deployment Guide

This document describes the conventions for naming `.pubxml` publish profiles, publishing to the shared `DedgeCommon` network share, and deploying ASP.NET Core applications to IIS using the `IIS-DeployApp` tooling.

---

## 1. Publish Profiles (.pubxml)

### Naming Convention

Publish profiles live under each project's `Properties\PublishProfiles\` folder. The profile name reflects **what kind of app** it is and **how it is published**:

| Profile Name              | Used For                                      |
|---------------------------|-----------------------------------------------|
| `WebApp-FileSystem.pubxml` | ASP.NET Core web applications (hosted by IIS)  |
| `WinApp-FileSystem.pubxml` | Background services / console applications     |

All profiles use the `FileSystem` publish method to copy output to a UNC share on the deployment server.

### Folder Naming on the Network Share

Published output goes to:

```
\\<server>\DedgeCommon\Software\DedgeWinApps\<AppName>
```

#### Single-project solutions

When the solution contains only one deployable project, the folder name matches the solution name:

```
\\server\DedgeCommon\Software\DedgeWinApps\DedgeAuth
\\server\DedgeCommon\Software\DedgeWinApps\DocView
```

#### Multi-project solutions

When a solution contains multiple deployable projects (e.g. a web API plus background services), each project gets its own top-level folder using the pattern `<SolutionName>-<ComponentName>`:

```
\\server\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-WebApi
\\server\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-ImportService
\\server\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-AlertAgent
```

This keeps each app's binaries fully isolated -- no shared parent folder, no risk of DLL collisions between projects that share dependencies.

### Example: WebApp-FileSystem.pubxml (ASP.NET Core web app)

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <PropertyGroup>
    <DeleteExistingFiles>true</DeleteExistingFiles>
    <LastUsedBuildConfiguration>Release</LastUsedBuildConfiguration>
    <LastUsedPlatform>Any CPU</LastUsedPlatform>
    <PublishProvider>FileSystem</PublishProvider>
    <PublishUrl>\\server\DedgeCommon\Software\DedgeWinApps\MyApp-WebApi</PublishUrl>
    <PublishDir>\\server\DedgeCommon\Software\DedgeWinApps\MyApp-WebApi</PublishDir>
    <WebPublishMethod>FileSystem</WebPublishMethod>
    <_TargetId>Folder</_TargetId>
    <TargetFramework>net10.0</TargetFramework>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <SelfContained>false</SelfContained>
    <PublishSingleFile>false</PublishSingleFile>
  </PropertyGroup>
</Project>
```

> **Important:** Always set both `PublishUrl` and `PublishDir`. Visual Studio uses `PublishUrl`; the `dotnet publish` CLI uses `PublishDir`. If either is missing, the output may go to the wrong location.

### Example: WinApp-FileSystem.pubxml (background service)

Same structure, different destination:

```xml
<PublishUrl>\\server\DedgeCommon\Software\DedgeWinApps\MyApp-ImportService</PublishUrl>
<PublishDir>\\server\DedgeCommon\Software\DedgeWinApps\MyApp-ImportService</PublishDir>
```

Background services do not need `WebPublishMethod`, `_TargetId`, or `EnableUpdateAppSettings`.

---

## 2. Publishing from Build Scripts

When a `Build-And-Publish.ps1` script publishes projects, it should reference the profile by name:

```powershell
dotnet publish $projectPath /p:PublishProfile=WebApp-FileSystem -v minimal
dotnet publish $projectPath /p:PublishProfile=WinApp-FileSystem -v minimal
```

The profile file handles all settings (configuration, runtime, output path, self-contained mode), so the `dotnet publish` call only needs the project path and profile name.

---

## 3. IIS Deployment with IIS-DeployApp

### Overview

The `IIS-DeployApp.ps1` script deploys applications as **virtual applications** under an existing IIS site (typically `Default Web Site`). It handles the full lifecycle: teardown, file install, app pool creation, virtual app creation, `web.config` generation, permissions, start, and health check verification.

### Architecture Flow

```
Source Code
    |
    v
dotnet publish /p:PublishProfile=WebApp-FileSystem
    |
    v
Network Share: \\server\DedgeCommon\Software\DedgeWinApps\<AppName>
    |
    v
IIS-DeployApp.ps1 (reads deploy template)
    |
    +-- Install-OurWinApp: copies from DedgeCommon share to local $env:OptPath\DedgeWinApps\<AppName>
    +-- Creates/configures IIS app pool
    +-- Creates virtual application under Default Web Site
    +-- Generates web.config if missing
    +-- Sets folder permissions
    +-- Starts app pool and verifies health endpoint
    |
    v
Live at: http://server/<VirtualPath>/
```

### Deployment Templates

Templates are JSON files in the `templates\` folder:

```
IIS-DeployApp\
├── IIS-DeployApp.ps1        ← Main deployment script
├── IIS-UninstallApp.ps1     ← Uninstall/teardown script
├── Test-IISSite.ps1         ← Post-deploy diagnostics
├── _deploy.ps1              ← Syncs this folder to target servers
└── templates\
    ├── DedgeAuth_WinApp.deploy.json
    ├── DocView_WinApp.deploy.json
    ├── GenericLogHandler_WinApp.deploy.json
    └── ...
```

### Template Naming Convention

```
<SiteName>_<InstallSource>.deploy.json
```

| Component       | Description                                          |
|-----------------|------------------------------------------------------|
| `SiteName`      | The IIS virtual application name                     |
| `InstallSource` | `WinApp`, `PshApp`, or `None`                        |

Examples:
- `DedgeAuth_WinApp.deploy.json` -- single-project ASP.NET Core app
- `GenericLogHandler_WinApp.deploy.json` -- web API component of a multi-project solution
- `AutoDoc_None.deploy.json` -- static site, files already in place

### Template Fields

```json
{
  "SiteName": "GenericLogHandler",
  "PhysicalPath": "$env:OptPath\\DedgeWinApps\\GenericLogHandler-WebApi",
  "AppType": "AspNetCore",
  "DotNetDll": "GenericLogHandler.WebApi.dll",
  "AppPoolName": "GenericLogHandler",
  "InstallSource": "WinApp",
  "InstallAppName": "GenericLogHandler-WebApi",
  "VirtualPath": "/GenericLogHandler",
  "ParentSite": "Default Web Site",
  "HealthEndpoint": "/health",
  "ApiPort": 8110
}
```

Key relationships:

| Field            | Maps To                                                       |
|------------------|---------------------------------------------------------------|
| `InstallAppName` | Folder name under `DedgeCommon\Software\DedgeWinApps\` on the share |
| `PhysicalPath`   | Local path on the server after `Install-OurWinApp` copies it  |
| `SiteName`       | IIS virtual application name and app pool name                |
| `VirtualPath`    | URL path (e.g. `/GenericLogHandler` -> `http://server/GenericLogHandler/`) |

For multi-project solutions, `InstallAppName` includes the component suffix (e.g. `GenericLogHandler-WebApi`) while `SiteName` and `VirtualPath` use the solution name only (e.g. `GenericLogHandler`). Only the web API component needs an IIS deployment template -- background services are installed as Windows services separately.

### Running a Deployment

```powershell
# On the target server, or remotely:
.\IIS-DeployApp.ps1
# Interactive: shows a profile picker and deploys the selected template

# Or specify directly:
.\IIS-DeployApp.ps1 -SiteName "GenericLogHandler"
```

### Automatic web.config Patching

The `IIS-Handler` module automatically patches `web.config` during deployment for all AspNetCore apps. **No manual web.config edits are needed.** The following is handled automatically:

- **`maxQueryString`** is set to `8192` (IIS default of 2048 is too small for JWT tokens passed via `?token=<jwt>` after DedgeAuth login)
- **`AuthServerUrl`** is normalized to `http://localhost/DedgeAuth` — even if a server-specific hostname was present, it is replaced with the server-agnostic localhost URL

This means you do not need to configure `web.config` manually after deployment. The IIS-DeployApp system handles it.

---

## 4. Deploying Changes to IIS-DeployApp Itself

After making **any changes** to files in the `IIS-DeployApp` folder (scripts, templates, etc.), always run the deploy script to sync them to the target servers:

```powershell
.\IIS-DeployApp\_deploy.ps1
```

This uses `Deploy-Handler` to copy the updated scripts and templates to all configured application servers. Without this step, remote servers will still have the old versions.

---

## 5. Summary: End-to-End for a New Project

1. **Create `.pubxml` profiles** in each project's `Properties\PublishProfiles\`:
   - `WebApp-FileSystem.pubxml` for web apps
   - `WinApp-FileSystem.pubxml` for services
   - Target: `\\server\DedgeCommon\Software\DedgeWinApps\<SolutionName>` (single project) or `<SolutionName>-<Component>` (multi-project)

2. **Publish** via `dotnet publish /p:PublishProfile=<ProfileName>` or a `Build-And-Publish.ps1` script

3. **Create an IIS deployment template** at `IIS-DeployApp\templates\<SiteName>_WinApp.deploy.json` with `InstallAppName` matching the folder name on the share. Add a `DedgeAuth` block (AppId, DisplayName, Description, Roles, TenantDomains, BaseUrl) so IIS-DeployApp registers the app in the DedgeAuth database when deploying.

4. **Run `_deploy.ps1`** to sync the new template to target servers

5. **Run `IIS-DeployApp.ps1`** on the target server to deploy — it will create the IIS virtual app and register the app in DedgeAuth from the template's DedgeAuth block
