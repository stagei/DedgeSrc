# Plan: Apply Folder Permissions from Template Files

**Purpose:** Add functionality to IIS-DeployApp (and IIS-Handler) so that folder security can be driven by template files—either inline in deploy JSON or via a separate permissions JSON that can be reused (e.g. captured from `C:\inetpub\wwwroot`).

---

## 1. Current behaviour

- **Step 6** in `IIS-Handler.psm1` (Deploy-IISSite):
  - Grants **ReadAndExecute** to `IIS AppPool\<AppPoolName>` on `PhysicalPath`.
  - For AspNetCore, grants **Modify** to the same identity on the logs directory.
- **Root site** (DefaultWebSite): grants **IIS_IUSRS** **ReadAndExecute** on `PhysicalPath`.
- No template-driven permissions; everything is hardcoded.

---

## 2. Target behaviour

- **Optional** permissions in deploy flow:
  - If a deploy template (or a linked permissions template) defines a **Permissions** list, apply those rules in addition to (or instead of) the default app-pool rule, as specified below.
- **Extraction script** (run on server):
  - Reads ACL from a given path (e.g. `C:\inetpub\wwwroot`).
  - Writes a **JSON file** with one entry per principal (Identity + rights + Allow/Deny + inheritance).
  - JSON format is the same as the **permissions template** format so it can be dropped into templates or referenced by them.

---

## 3. Permissions template format (JSON)

Design so one structure can be used both for:
- **Extraction output** (current ACL → JSON), and  
- **Template input** (JSON → Apply to path).

### 3.1 Single-path template (e.g. wwwroot export)

```json
{
  "Description": "Optional comment, e.g. Captured from dedge-server wwwroot",
  "Path": "C:\\inetpub\\wwwroot",
  "Entries": [
    {
      "Identity": "BUILTIN\\Administrators",
      "FileSystemRights": "FullControl",
      "AccessControlType": "Allow",
      "InheritanceFlags": "ContainerInherit,ObjectInherit",
      "PropagationFlags": "None"
    },
    {
      "Identity": "IIS_IUSRS",
      "FileSystemRights": "ReadAndExecute",
      "AccessControlType": "Allow",
      "InheritanceFlags": "ContainerInherit,ObjectInherit",
      "PropagationFlags": "None"
    }
  ]
}
```

- **Path:** Target folder. In deploy context this can be overridden or defaulted to `PhysicalPath` (and/or logs path).
- **Entries:** Array of ACEs.  
  - **Identity:** Account (e.g. `DOMAIN\Group`, `BUILTIN\Administrators`, `IIS_IUSRS`).  
  - **FileSystemRights:** .NET enum name string: `FullControl`, `Modify`, `ReadAndExecute`, `Read`, `Write`, `ReadData`, `ListDirectory`, etc.  
  - **AccessControlType:** `Allow` or `Deny`.  
  - **InheritanceFlags:** `None`, `ContainerInherit`, `ObjectInherit`, or `ContainerInherit,ObjectInherit`.  
  - **PropagationFlags:** `None`, `NoPropagateInherit`, etc.

### 3.2 Inline in deploy template (optional)

Deploy JSON may include an optional **Permissions** block:

- **Option A – inline entries (same structure as Entries above):**  
  `"Permissions": { "Entries": [ ... ] }`  
  Applied to `PhysicalPath` (and optionally to logs path if defined).
- **Option B – reference external file:**  
  `"PermissionsTemplatePath": "templates\\wwwroot.permissions.json"`  
  That file uses the single-path format above; deploy resolves **Path** from template or uses `PhysicalPath` / logs path.

Recommendation: support both **inline** `Permissions.Entries` and **PermissionsTemplatePath** so that:
- A captured wwwroot JSON can be used as-is (reference by path), and  
- A deploy can add a few rules inline without a separate file.

---

## 4. Where to implement (IIS-Handler / IIS-DeployApp)

| Location | Change |
|----------|--------|
| **IIS-Handler.psm1** | New helper: `Set-FolderPermissionsFromTemplate` (or similar). Input: path, permissions array; logic: `Get-Acl`, for each entry create `FileSystemAccessRule`, `AddAccessRule`, `Set-Acl`. Parse `FileSystemRights` / `InheritanceFlags` / `PropagationFlags` from strings (e.g. split `ContainerInherit,ObjectInherit`). |
| **IIS-Handler.psm1** | **Step 6:** After ensuring app pool identity has at least ReadAndExecute (existing behaviour), if deploy params contain `Permissions` or `PermissionsTemplatePath`: load template (merge inline + external if both present), resolve target path(s) (PhysicalPath, optional logs path), call `Set-FolderPermissionsFromTemplate` for each path. |
| **IIS-DeployApp.ps1** | No change required if templates and template path are passed through existing splat to `Deploy-IISSite`; ensure `IIS-Handler` reads `Permissions` / `PermissionsTemplatePath` from the merged profile (same as other template fields). |
| **Templates** | New optional keys in `*.deploy.json`: `Permissions` (object with `Entries`), `PermissionsTemplatePath` (string). Optional separate files under `templates\` e.g. `wwwroot.permissions.json`. |

---

## 5. Apply logic (detailed)

1. **Load permissions list**  
   - If `PermissionsTemplatePath` is set and file exists: read JSON, take `Entries` (and optional `Path` override).  
   - If `Permissions.Entries` is present: merge with any entries from template file (template file can define base set, deploy adds overrides).  
   - If neither is set: keep current behaviour only (app pool + logs).

2. **Target path(s)**  
   - For normal app: apply to `PhysicalPath`; if template has `Path`, it can be used when applying a **standalone** permissions file (e.g. for wwwroot), but in deploy context we usually apply to `PhysicalPath` (and logs path if applicable).  
   - For root site: apply to `PhysicalPath` (same as today).

3. **Apply**  
   - For each path: `Get-Acl`, for each entry in `Entries`: build `FileSystemAccessRule(Identity, FileSystemRights, InheritanceFlags, PropagationFlags, AccessControlType)`, then `AddAccessRule`; finally `Set-Acl`.  
   - Preserve existing default step: ensure app pool (or IIS_IUSRS for root) has at least the same access as today unless template explicitly replaces it.

4. **Idempotency**  
   - Adding rules with `AddAccessRule` is additive; duplicate identity+rights may need to be avoided (e.g. check existing ACL or use a “replace” mode later). For v1, additive is acceptable.

---

## 6. Extraction script (standalone, run on server)

- **Script:** e.g. `Export-WwwrootPermissions.ps1` (or generic `Export-FolderPermissions.ps1`) in `DevTools\WebSites\IIS-DeployApp\`.
- **Parameters:**  
  - `-Path` (default `C:\inetpub\wwwroot`),  
  - `-OutputPath` (default: next to script or current directory, e.g. `wwwroot.permissions.json`).
- **Behaviour:**  
  - `Get-Acl -Path $Path`  
  - For each `FileSystemAccessRule` in `$acl.Access`: capture `IdentityReference.Value`, `FileSystemRights`, `AccessControlType`, `InheritanceFlags`, `PropagationFlags`.  
  - Map to the same JSON shape as above (Identity, FileSystemRights as enum name, AccessControlType, InheritanceFlags/PropagationFlags as comma-separated or single value).  
  - Write JSON with `Path` and `Entries` so the file is a valid permissions template.
- **Usage:** Copy script to server (or run via deploy); run with pwsh; use generated JSON as `PermissionsTemplatePath` or paste `Entries` into a deploy template.

---

## 7. File placement

| Item | Path |
|------|------|
| Plan (this file) | `DevTools\WebSites\IIS-DeployApp\docs\Plan-Permissions-From-Template.md` |
| Extraction script | `DevTools\WebSites\IIS-DeployApp\Export-FolderPermissions.ps1` |
| Example template (optional) | `templates\wwwroot.permissions.json` (after first export from a server) |

---

## 8. Order of implementation

1. Implement **Export-FolderPermissions.ps1** (extract ACL → JSON).  
2. Run it on a server for `C:\inetpub\wwwroot`, save as `wwwroot.permissions.json`.  
3. Implement **Set-FolderPermissionsFromTemplate** (and string-to-enum parsing) in IIS-Handler.  
4. In **Deploy-IISSite** Step 6: keep current app-pool (and root) logic; add optional load and apply of `Permissions` / `PermissionsTemplatePath`.  
5. Add **Permissions** / **PermissionsTemplatePath** to profile merge in IIS-Handler (same as other template fields).  
6. Test with a deploy template that references `wwwroot.permissions.json` (or inline Entries) for a path such as wwwroot or an app’s PhysicalPath.

---

## 9. Security note

- Templates may contain paths and account names. Store template files in a controlled location (e.g. same repo as deploy templates) and restrict who can change them.
- Applying Deny rules or reducing rights can lock out admins; prefer Allow-only templates and test on non-production first.
