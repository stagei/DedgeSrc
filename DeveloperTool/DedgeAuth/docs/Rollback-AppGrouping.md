# Rollback Plan: App Grouping Feature

This document describes how to fully revert the App Grouping + ACL feature back to the working state as of **2026-03-09** if the implementation fails.

## Pre-Implementation State (Safe Points)

| Repository | Branch | Commit Hash (full) | Short Hash | Commit Message |
|---|---|---|---|---|
| **DedgeAuth** | `main` | `88f92832e16e899a53c450c11c660ece518f76a6` | `88f9283` | Fix scheduled task setup in _install.ps1 |
| **DedgePsh** | `main` | `7a1f9f939459702565b71debd85dd288303bbe1a` | `7a1f9f93` | feat(IIS-DeployApp): implement Windows Authentication configuration |

| Item | Value |
|---|---|
| DedgeAuth version | `1.0.148` |
| Latest EF migration | `20260317220125_AddWindowsSsoAndAuthMethod` |
| DedgeAuth remote | `https://Dedge@dev.azure.com/Dedge/Dedge/_git/DedgeAuth` |
| DedgePsh remote | `https://Dedge@dev.azure.com/Dedge/Dedge/_git/DedgePsh` |

---

## Step 1: Revert DedgeAuth Repository

Open a terminal in `C:\opt\src\DedgeAuth`.

### Option A: Hard reset (discards all local changes)

```powershell
cd C:\opt\src\DedgeAuth
git stash
git checkout main
git reset --hard 88f92832e16e899a53c450c11c660ece518f76a6
```

If you already pushed commits to the remote and need to force-revert:

```powershell
git push origin main --force
```

### Option B: Revert commits (keeps history, creates new revert commits)

If you prefer to keep the commit history and create explicit revert commits:

```powershell
cd C:\opt\src\DedgeAuth

# List commits since the safe point
git log --oneline 88f9283..HEAD

# Revert each commit in reverse order (newest first)
# Replace <hash1>, <hash2>, etc. with the actual commit hashes from the log above
git revert --no-edit <newest-hash>
git revert --no-edit <next-hash>
# ... repeat for each commit
git push origin main
```

---

## Step 2: Revert DedgePsh Repository

Open a terminal in `C:\opt\src\DedgePsh`.

### Option A: Hard reset

```powershell
cd C:\opt\src\DedgePsh
git stash
git checkout main
git reset --hard 7a1f9f939459702565b71debd85dd288303bbe1a
```

If already pushed:

```powershell
git push origin main --force
```

### Option B: Revert commits

```powershell
cd C:\opt\src\DedgePsh
git log --oneline 7a1f9f93..HEAD
git revert --no-edit <newest-hash>
# ... repeat for each commit
git push origin main
```

---

## Step 3: Revert the Database Migration

The app grouping feature adds new tables (`app_groups`, `app_group_items`) via an EF Core migration. The database must be rolled back to the last known-good migration.

### Last known-good migration

```
20260317220125_AddWindowsSsoAndAuthMethod
```

### Revert via EF Core CLI

From the DedgeAuth project root, target the migration before the app-grouping migration:

```powershell
cd C:\opt\src\DedgeAuth

dotnet ef database update 20260317220125_AddWindowsSsoAndAuthMethod `
    --project src\DedgeAuth.Data `
    --startup-project src\DedgeAuth.Api `
    --connection "Host=t-no1fkxtst-db;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres"
```

This rolls back any migrations applied after `AddWindowsSsoAndAuthMethod`, which drops the `app_groups` and `app_group_items` tables.

### Manual SQL fallback

If EF Core CLI is not available or fails, connect to PostgreSQL and run:

```sql
-- Drop the new tables (order matters due to foreign keys)
DROP TABLE IF EXISTS app_group_items CASCADE;
DROP TABLE IF EXISTS app_groups CASCADE;

-- Remove the migration record so EF doesn't think it was applied
DELETE FROM "__EFMigrationsHistory"
WHERE "MigrationId" LIKE '%AppGroup%';
```

Connection details:

```
Host: t-no1fkxtst-db
Port: 8432
Database: DedgeAuth
User: postgres
Password: postgres
```

---

## Step 4: Rebuild, Deploy Scripts, and Redeploy IIS

`Build-And-Publish.ps1` handles both building DedgeAuth and deploying DedgePsh scripts to the server (DatabaseSetup, AddAppSupport, IIS-DeployApp + modules). After reverting both repos, running it redeploys the reverted scripts automatically.

```powershell
# Build and publish DedgeAuth to staging + deploy reverted DedgePsh scripts
# (deploys: IIS-Handler.psm1, Register-DedgeAuthApp.ps1, all templates)
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish.ps1"

# Full IIS teardown + rebuild from reverted templates
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"
```

If consumer apps also need rebuilding (e.g., DedgeAuth.Client changed):

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1"
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"
```

---

## Step 6: Verify

```powershell
# Run GrabScreenShot to capture all apps and send verification email + SMS
pwsh.exe -NoProfile -File "C:\opt\src\GrabScreenShot\Invoke-GrabScreenShot.ps1"
```

Manual verification checklist:

- [ ] `http://localhost/DedgeAuth/login.html` -- login form renders, Windows auth works
- [ ] `http://localhost/DedgeAuth/admin.html` -- admin panel loads, no "Groups" tab
- [ ] `http://localhost/DocView/` -- auth redirect, styled page
- [ ] `http://localhost/GenericLogHandler/` -- auth redirect, styled page
- [ ] `http://localhost/ServerMonitorDashboard/` -- auth redirect, styled page
- [ ] `http://localhost/AutoDocJson/` -- auth redirect, styled page
- [ ] User menu app switcher shows flat app list (no folders/groups)

---

## Files Changed by the App Grouping Feature

### DedgeAuth repository (`C:\opt\src\DedgeAuth`)

| File | Change Type |
|---|---|
| `src/DedgeAuth.Core/Models/AppGroup.cs` | NEW |
| `src/DedgeAuth.Core/Models/AppGroupItem.cs` | NEW |
| `src/DedgeAuth.Data/AuthDbContext.cs` | MODIFIED (DbSet + config) |
| `src/DedgeAuth.Data/Migrations/*AppGroup*` | NEW (migration files) |
| `src/DedgeAuth.Services/AppGroupAccessService.cs` | NEW |
| `src/DedgeAuth.Api/Controllers/AppGroupsController.cs` | NEW |
| `src/DedgeAuth.Api/Controllers/AuthController.cs` | MODIFIED (broadened Windows auth) |
| `src/DedgeAuth.Api/wwwroot/admin.html` | MODIFIED (Groups tab) |
| `src/DedgeAuth.Api/wwwroot/login.html` | MODIFIED (tree rendering) |
| `src/DedgeAuth.Api/wwwroot/js/DedgeAuth-user.js` | MODIFIED (grouped app switcher) |
| `src/DedgeAuth.Services/DatabaseSeeder.cs` | MODIFIED (default groups) |
| `Build-And-Publish.ps1` | MODIFIED (added DedgeAuth-AddAppSupport deploy) |

### DedgePsh repository (`C:\opt\src\DedgePsh`)

| File | Change Type |
|---|---|
| `_Modules/IIS-Handler/IIS-Handler.psm1` | MODIFIED (`Register-AppInDedgeAuthDb` function) |
| `DevTools/WebSites/DedgeAuth/DedgeAuth-AddAppSupport/Register-DedgeAuthApp.ps1` | MODIFIED (new `-GroupsJson` param + Step 5) |
| `DevTools/WebSites/IIS-DeployApp/templates/GenericLogHandler_WinApp.deploy.json` | MODIFIED (`Groups` field) |
| `DevTools/WebSites/IIS-DeployApp/templates/ServerMonitorDashboard_WinApp.deploy.json` | MODIFIED (`Groups` field) |
| `DevTools/WebSites/IIS-DeployApp/templates/DocView_WinApp.deploy.json` | MODIFIED (`Groups` field) |
| `DevTools/WebSites/IIS-DeployApp/templates/AutoDocJson_WinApp.deploy.json` | MODIFIED (`Groups` field) |
| `DevTools/WebSites/IIS-DeployApp/templates/AgriNxt.GrainDryingDeduction_WinApp.deploy.json` | MODIFIED (`Groups` field) |

---

## Summary: Quick Rollback Commands

Copy-paste this block for a full rollback:

```powershell
# 1. Revert DedgeAuth
cd C:\opt\src\DedgeAuth
git stash
git checkout main
git reset --hard 88f92832e16e899a53c450c11c660ece518f76a6

# 2. Revert DedgePsh
cd C:\opt\src\DedgePsh
git stash
git checkout main
git reset --hard 7a1f9f939459702565b71debd85dd288303bbe1a

# 3. Revert database
cd C:\opt\src\DedgeAuth
dotnet ef database update 20260317220125_AddWindowsSsoAndAuthMethod `
    --project src\DedgeAuth.Data `
    --startup-project src\DedgeAuth.Api `
    --connection "Host=t-no1fkxtst-db;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres"

# 4. Build, publish, and deploy reverted scripts to server
#    (Build-And-Publish.ps1 deploys DedgePsh scripts: IIS-Handler, Register-DedgeAuthApp, templates)
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish.ps1"

# 5. Full IIS teardown + rebuild from reverted templates
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"

# 6. Verify
pwsh.exe -NoProfile -File "C:\opt\src\GrabScreenShot\Invoke-GrabScreenShot.ps1"
```
