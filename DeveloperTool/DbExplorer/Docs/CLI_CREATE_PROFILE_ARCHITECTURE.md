# CLI create-profile: Architecture and Implementation Branches

This document records architectural decisions and implementation branches encountered when adding the CLI `create-profile` command for DB2 and PostgreSQL 18.

## Implemented Behavior

- **Command:** `create-profile` (no connection required; meta command like `connection-profiles`).
- **Basics:** `-name`, `-provider` (DB2 | PostgreSQL), `-host` (or `-server`), `-port`, `-database`, `-username`, `-password`.
- **Optional:** `-version` (default: 12.1 for DB2, 18 for PostgreSQL), `-outfile` (optional for create-profile; result JSON to file or console).
- **Storage:** Profile is saved via `ConnectionStorageService` to `Documents\DbExplorer\connections.json` with DPAPI-encrypted password.
- **Version handling:** `DatabaseConnection` has optional `Version`; when saving, `ConnectionStorageService` uses it if set, else defaults by provider (12.1 DB2, 18 PostgreSQL).

## Architectural Branches / Notes

### 1. Two connection storage mechanisms

- **ConnectionStorageService** uses **connections.json** (path from `UserDataFolderHelper.GetFilePath("connections.json")` → `Documents\DbExplorer\connections.json`). This is what the main app and CLI use for `GetConnection(profileName)` and for saving from the connection dialog.
- **ConnectionProfileService** uses **connection_profiles.json** (same user data folder, different file). The CLI command `connection-profiles` (list) uses `ConnectionProfileService.LoadAllProfiles()`, so it lists profiles from **connection_profiles.json**, not from **connections.json**.

**Branch:** `create-profile` was implemented to write only to **connections.json** via `ConnectionStorageService`, so new profiles are available for `--profile` and in the GUI. Listing via `connection-profiles` may still show a different set (connection_profiles.json). Unifying list and create on a single storage (e.g. always use connections.json for both) would require changing `connection-profiles` to use `ConnectionStorageService.LoadConnections()` or migrating/merging the two files.

### 2. Version on DatabaseConnection

- **SavedConnection** (JSON model) has `Version` (e.g. "12.1", "18").
- **DatabaseConnection** (in-memory model used by GUI and CLI) did not have `Version`; `ConnectionStorageService.SaveConnection` previously hardcoded `Version = "12.1"`.
- **Decision:** Added optional `DatabaseConnection.Version`. When saving, `ConnectionStorageService` uses `connection.Version` if set; otherwise it defaults by provider (PostgreSQL → "18", else "12.1"). CLI `create-profile` sets `Version` from `-version` or provider default.

### 3. OutFile optional for create-profile

- Most CLI commands require `-outfile`; the handler returns non-zero if `args.OutFile` is empty.
- **Decision:** For `create-profile` only, `OutFile` is optional. If provided, the result JSON is written to the file; otherwise it is printed to the console. This allows one-line profile creation without a result file.

### 4. Connection limit (10) in ConnectionStorageService

- `SaveConnection` keeps at most 10 connections (removes oldest by `LastUsed` when inserting an 11th).
- **Decision:** Left as-is. If more than 10 named profiles are needed, this limit is an architectural constraint to revisit (e.g. configurable limit or separate “pinned” vs “recent” list).

### 5. Ensure-Pg18Profile.ps1 vs create-profile

- **Ensure-Pg18Profile.ps1** (tests/automation) creates/updates the `PostgreSQL_Local` profile by writing directly to `connections.json` with DPAPI (PowerShell) so the format matches the app.
- **create-profile** uses the app’s `ConnectionStorageService` (C# DPAPI) and the same file. Both end up writing to `Documents\DbExplorer\connections.json`; Ensure-Pg18Profile remains useful for test/CI when the app is not run.

## Files Touched

- `Utils/CliArgumentParser.cs` – `CreateName`, `CreateProvider`, `CreateHost`, `CreatePort`, `CreateDatabase`, `CreateUsername`, `CreatePassword`, `CreateVersion`; parser for `-name`, `-provider`, `-host`/`-server`, `-port`, `-database`, `-username`, `-password`, `-version`.
- `Models/DatabaseConnection.cs` – optional `Version`.
- `Services/ConnectionStorageService.cs` – Version from connection or default by provider when saving.
- `Services/CliCommandHandlerService.cs` – `create-profile` → `CreateConnectionProfileAsync`; OutFile optional for create-profile; help-all entry.
- `Services/CliExecutorService.cs` – create-profile treated as meta command (no profile load); PrintHelp updated with create-profile and notes.

## Usage Examples

```text
# PostgreSQL 18 (default port 5432, version 18)
DbExplorer.exe -Command create-profile -name PostgreSQL_Local -provider PostgreSQL -host localhost -port 5432 -database postgres -username postgres -password postgres

# DB2 (default port 50000, version 12.1)
DbExplorer.exe -Command create-profile -name MyDB2 -provider DB2 -host dbhost -port 50000 -database MYDB -username user -password secret

# With result file
DbExplorer.exe -Command create-profile -name PG_Dev -provider PostgreSQL -host 192.168.1.1 -database app -username app -password xxx -outfile create_result.json
```
