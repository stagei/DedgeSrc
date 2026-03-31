# IIS-DeployApp

Deploys and configures IIS web applications using reusable JSON profiles.

## Scripts

| Script | Purpose |
|---|---|
| `IIS-DeployApp.ps1` | Deploy or update an IIS application from a profile |
| `IIS-UninstallApp.ps1` | Remove an IIS virtual application and its app pool |
| `Test-IISSite.ps1` | Run diagnostics and health checks on a deployed site |
| `_deploy.ps1` | Push scripts and templates to target servers |

## Deploy Profile Reference

Deploy profiles are JSON files stored in the `templates/` subfolder. When a profile is used for deployment, a timestamped copy is saved to the network profile directory for reuse.

### File Naming Convention

```
<SiteName>_<InstallSource>.deploy.json
```

Examples: `DocView_WinApp.deploy.json`, `DefaultWebSite_None.deploy.json`

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `SiteName` | string | Yes | Name of the IIS virtual application or site. Used as the application identity throughout deployment, app pool naming, firewall rules, and profile saving. Must be unique per parent site. |
| `PhysicalPath` | string | Yes | File system path where the application files reside. Supports environment variables (e.g. `$env:OptPath\DedgeWinApps\DocView`). Auto-determined from `InstallSource` if not provided: `WinApp` -> `DedgeWinApps\<name>`, `PshApp` -> `DedgePshApps\<name>`. |
| `AppType` | string | Yes | Determines how IIS is configured. `AspNetCore` creates an ASP.NET Core hosting configuration with `web.config` and a reverse-proxy handler. `Static` serves files directly with optional directory browsing. |
| `DotNetDll` | string | AspNetCore only | The entry-point DLL for the ASP.NET Core application (e.g. `DocView.dll`). Written into the `web.config` as the `aspNetCore` process path argument. If omitted for AspNetCore apps, the script searches `PhysicalPath` for a single `.dll` matching the site name. |
| `AppPoolName` | string | No | Name of the IIS application pool. Defaults to `SiteName` if not specified. **Each application must use its own app pool** (ASP.NET Core does not support multiple apps per pool; shared pools cause HTTP 500.35). All bundled templates set `AppPoolName` to a unique value per app. |
| `InstallSource` | string | Yes | Where the application binaries come from. Determines the physical path convention and deployment behavior: |
| | | | - `WinApp` -- Installed via Windows app packages into `DedgeWinApps\` |
| | | | - `PshApp` -- Deployed via PowerShell scripts into `DedgePshApps\` |
| | | | - `None` -- Files are managed manually; `PhysicalPath` must be explicit |
| `InstallAppName` | string | No | The application package name used when resolving binaries from the install source. Defaults to `SiteName`. Relevant for WinApp/PshApp sources where the package name may differ from the site name. |
| `VirtualPath` | string | Yes | The IIS virtual path where the application is mounted, relative to the parent site. Typically `/<SiteName>` (e.g. `/DocView`). Only the special `DefaultWebSite` profile may use `/` (root). |
| `ParentSite` | string | Yes | The IIS website that hosts this application as a virtual directory. Almost always `Default Web Site`. The parent site must already exist in IIS. |
| `HealthEndpoint` | string | No | A relative URL path appended to the application base URL for health checks during post-deployment verification (e.g. `/health`, `/api/status`). When set, `Test-IISSite` hits this endpoint first. If empty, the script falls back to root URL, Swagger, and common API paths. |
| `EnableDirectoryBrowsing` | bool | No | When `true`, enables IIS directory browsing for the application. Typically `true` for static file sites and `false` for AspNetCore apps. Defaults to `true` in the module if not specified. |
| `IsRootSiteProfile` | bool | No | When `true`, marks this profile as the root site bootstrap profile (only `DefaultWebSite` should use this). Root profiles deploy to `/` and configure the IIS site itself rather than creating a virtual application beneath it. All other profiles must set this to `false`. |
| `ApiPort` | int | AspNetCore only | The local TCP port the ASP.NET Core Kestrel server listens on (e.g. `8282`, `8100`). Used for: |
| | | | - Setting `ASPNETCORE_URLS=http://localhost:<port>` in `web.config` |
| | | | - Creating Windows Firewall inbound/outbound rules |
| | | | - Health check verification against the correct port |
| | | | Set to `0` for static sites or when no port binding is needed. |
| `LastDeployed` | string | No | Timestamp of the last successful deployment. Auto-populated by the deploy script in format `yyyy-MM-dd HH:mm:ss`. Leave empty in templates. |
| `DeployedBy` | string | No | The `DOMAIN\USERNAME` of the person who last deployed. Auto-populated by the deploy script. Leave empty in templates. |
| `ComputerName` | string | No | The hostname of the machine where the app was last deployed. Auto-populated by the deploy script. Leave empty in templates. |
| `AdditionalWinApps` | array of strings | No | WinApp names to install via `Install-OurWinApp` after the primary `InstallAppName` (e.g. agent, batch job). Each entry is installed with `-SkipShortcuts`. |
| `DedgeAuth` | object | No | When present, runs DedgeAuth app registration and/or appsettings patch. See [DedgeAuth block](#DedgeAuth-block) below. **Security:** Do not put DB password in templates; use `$env:DedgeAuth_DbPassword` or prompt. |

#### DedgeAuth block

When `DedgeAuth` is present and `RegisterInDatabase` or `UpdateAppSettings` is true, the deploy step will register the app in the DedgeAuth database and/or patch `appsettings.json` at the deployed path. All keys are optional; missing connection values will prompt (or use env vars in non-interactive).

| Key | Type | Description |
|-----|------|-------------|
| `RegisterInDatabase` | bool | If true, upsert app in DedgeAuth DB (apps table, tenant routing). Requires `Register-DedgeAuthApp.ps1` next to this repo (under `DedgeAuth\DedgeAuth-AddAppSupport\`). |
| `UpdateAppSettings` | bool | If true, patch deployed `appsettings.json` with `DedgeAuth:AuthServerUrl`, `DedgeAuth:AppId`, and optional connection string. |
| `DbHost`, `DbPort`, `DbName`, `DbUser` | string/number | DedgeAuth PostgreSQL connection. Password must **not** be in template; set `$env:DedgeAuth_DbPassword` or you will be prompted. |
| `AppId`, `DisplayName`, `Description`, `BaseUrl`, `Roles` | string/array | Used for DB registration; default to template `SiteName` and common values when omitted. |
| `AuthServerUrl` | string | Value written to `DedgeAuth:AuthServerUrl` when `UpdateAppSettings` is true (default `http://localhost/DedgeAuth`). |
| `TenantDomains` | array of strings | Tenant domains to add app routing for (default empty). |

### Example: AspNetCore Application

```json
{
  "SiteName": "DocView",
  "PhysicalPath": "$env:OptPath\\DedgeWinApps\\DocView",
  "AppType": "AspNetCore",
  "DotNetDll": "DocView.dll",
  "AppPoolName": "DocView",
  "InstallSource": "WinApp",
  "InstallAppName": "DocView",
  "VirtualPath": "/DocView",
  "ParentSite": "Default Web Site",
  "HealthEndpoint": "",
  "EnableDirectoryBrowsing": false,
  "IsRootSiteProfile": false,
  "ApiPort": 8282,
  "LastDeployed": "",
  "DeployedBy": "",
  "ComputerName": ""
}
```

### Example: Static Site (Root)

```json
{
  "SiteName": "DefaultWebSite",
  "PhysicalPath": "C:\\inetpub\\wwwroot",
  "AppType": "Static",
  "DotNetDll": "",
  "AppPoolName": "DefaultAppPool",
  "InstallSource": "None",
  "InstallAppName": "",
  "VirtualPath": "/",
  "ParentSite": "Default Web Site",
  "HealthEndpoint": "",
  "EnableDirectoryBrowsing": false,
  "IsRootSiteProfile": true,
  "ApiPort": 0
}
```

## Profile Lifecycle

1. **Templates** in `templates/` are bundled with the scripts and deployed to servers
2. **User picks** a template (or saved profile) when running `IIS-DeployApp.ps1`
3. **Profile values** fill in any parameters not explicitly provided on the command line
4. **After deployment**, a timestamped copy is saved to the network profile directory with `LastDeployed`, `DeployedBy`, and `ComputerName` populated
5. **Saved profiles** appear in the picker on subsequent runs, color-coded to distinguish from new templates

## Security

- **Never store database passwords in deploy templates.** Use environment variable `DedgeAuth_DbPassword` for DedgeAuth DB, or you will be prompted when the template has an `DedgeAuth` block.
