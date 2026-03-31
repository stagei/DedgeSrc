# Production IIS + PostgreSQL deployment log (PRD)

**Date:** 2026-03-23  
**Scope:** `p-no1fkxprd-app` (IIS), `p-no1fkxprd-db` (PostgreSQL)  
**Source DB snapshots:** `t-no1fkxtst-db` → databases `DedgeAuth`, `GenericLogHandler`

---

## Policy: test users (`.cursor/rules/test-users.mdc`)

| Item | Action |
|------|--------|
| Form-login / documented test passwords | **Not used against PRD** — policy forbids test accounts and known passwords in production. |
| Verification from this PC | Anonymous / health URLs only (see §5). |

---

## 1. PostgreSQL 18 tooling (`Install-WindowsApps`)

| Server | Package | Exit | Notes |
|--------|---------|------|--------|
| `p-no1fkxprd-app` | `PostgreSQL.18.Client` | **0** | Client tools installed (`psql`, `pg_dump`, `pg_restore`). |
| `p-no1fkxprd-db` | `PostgreSQL.18` (server) | **0** | Server on port **8432**, data dir `E:\pg` (per `SoftwareUtils` switch). |

Script: `IIS-DeployApp\Install-Pg18-ForPrd.ps1` (orchestrator / autocur).

---

## 2. Database: TST → PRD

| Step | Result |
|------|--------|
| `pg_dump` from `t-no1fkxtst-db` (local dev) | **OK** — DedgeAuth + GenericLogHandler `.backup` files created. |
| Direct `pg_restore` from dev PC to `p-no1fkxprd-db` | **Failed** — firewall / connectivity (create DB step failed). |
| Copy backups to `\\p-no1fkxprd-db\opt\data\PostgresPrdRestore\` | **OK** |
| `DedgeAuth-Restore-Database.ps1` on **localhost** (`p-no1fkxprd-db`) | **OK** |
| `GenericLogHandler-Restore-Database.ps1` on **localhost** (`p-no1fkxprd-db`) | **OK** (~90s for large GLH backup) |

**Code fix:** `PostgreSql-Handler.psm1` — `Backup-PostgreSqlDatabase` used invalid `[string]::EndsWith(...)` static call; fixed to use instance `$outStr.EndsWith(...)` (deployed via `IIS-DeployApp\_deploy.ps1`).

Orchestration helper: `Invoke-TstToPrdPostgresBackupRestore.ps1` (run backups locally; restore on DB server via orchestrator with `localhost` + paths under `E:\opt\data\PostgresPrdRestore\`).

---

## 3. IIS: `IIS-RedeployAll.ps1` on `p-no1fkxprd-app`

| Phase | Status |
|-------|--------|
| Phase 1: Uninstall | Partial (some apps reported exit 1 — logged as non-fatal in script). |
| Phase 2: `iisreset` | **Completed** |
| Phase 3: Redeploy | **BLOCKED** on first app after `DefaultWebSite` (`AgriNxt.GrainDryingDeduction`) |

**Blocker:** App pool identity requires password for **`DEDGE\p1_srv_fkxprd_app`**.  
`Get-SecureStringUserPasswordAsPlainText` reported **no password stored** for `p1_srv_fkxprd_app` for the running user (`FKPRDADM`), then `Set-UserPasswordAsSecureString` started interactive prompting — **not suitable for unattended orchestrator**.

**Required action (manual on PRD app server, as the account that runs deploys):**

1. Run `Set-UserPasswordAsSecureString -Username p1_srv_fkxprd_app` (or equivalent) so the **Infrastructure** password vault contains the service account password for **`FKPRDADM`** (or whichever account runs `IIS-RedeployAll`).
2. Re-run:  
   `pwsh.exe -NoProfile -File "%OptPath%\DedgePshApps\IIS-DeployApp\IIS-RedeployAll.ps1"`  
   (or `-SkipUninstall` if you only need to continue app installs).

Until this is done, virtual apps **after** the root site may be missing.

---

## 4. HTTP checks (from developer PC, 2026-03-23)

| URL | Result |
|-----|--------|
| `http://p-no1fkxprd-app/` | **200** |
| `http://p-no1fkxprd-app/DedgeAuth/health` | **404** (not deployed / IIS incomplete) |
| `http://p-no1fkxprd-app/GenericLogHandler/health` | **404** |
| `http://p-no1fkxprd-app/DocView/` | **404** |
| `http://p-no1fkxprd-app/ServerMonitorDashboard/api/IsAlive` | **404** |

---

## 5. Files / deploy changes

| Repo path | Change |
|-----------|--------|
| `IIS-DeployApp\_deploy.ps1` | Added `p-no1fkxprd-db` to `ComputerNameList`. |
| `IIS-DeployApp\Install-Pg18-ForPrd.ps1` | **New** — DbServer vs AppServer install. |
| `IIS-DeployApp\Invoke-TstToPrdPostgresBackupRestore.ps1` | **New** — backup TST; restore must run on DB server if local restore fails. |
| `_Modules\PostgreSql-Handler\PostgreSql-Handler.psm1` | Fix `Backup-PostgreSqlDatabase` extension check. |

---

## RAG MCP access summary

| RAG MCP | Result |
|--------|--------|
| Not used for this run | N/A |
