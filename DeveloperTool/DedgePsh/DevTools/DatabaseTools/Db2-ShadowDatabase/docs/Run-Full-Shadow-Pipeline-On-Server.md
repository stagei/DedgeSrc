# Run Full Shadow Pipeline On Server

## What to run directly on the server

If you want **one command** that runs the full end-to-end flow (restore from PRD + steps 1,2,3,4,5), run:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$env:OptPath\DedgePshApps\Db2-ShadowDatabase\Run-FullShadowPipeline.ps1"
```

This script executes:
- Step 1 (PRD restore + create shadow DB/instance)
- Step 2 (copy DDL + data to shadow)
- Step 3 (schema/object verification)
- Step 5 (row count verification in shadow)
- Step 4 (move shadow back to original instance)
- Final verification after move

## Scripts you can run directly in `pwsh.exe` on the DB server

- `Run-FullShadowPipeline.ps1` (**recommended** for full pipeline)
- `Step-1-CreateShadowDatabase.ps1`
- `Step-2-CopyDatabaseContent.ps1`
- `Step-3-CleanupShadowDatabase.ps1`
- `Step-4-MoveToOriginalInstance.ps1`
- `Step-5-VerifyRowCounts.ps1`
- `Verify-LocalDb2Connection.ps1` (local DB2 client validation from the server)

## Full command for your requested flow (restore from PROD + 1,2,3,4,5)

Use this exact command on the DB server:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$env:OptPath\DedgePshApps\Db2-ShadowDatabase\Run-FullShadowPipeline.ps1"
```

## Optional: local verification command after pipeline

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$env:OptPath\DedgePshApps\Db2-ShadowDatabase\Verify-LocalDb2Connection.ps1" -ConfigName fkmvft -SendSms -SkipJdbc
```

## Notes

- `Invoke-ShadowDatabaseOrchestrator.ps1` with `RUN_ALL` does **not** include Step 4 by default.
- For full 1,2,3,4,5 in one run, use `Run-FullShadowPipeline.ps1`.
- Config is auto-resolved from `config.*.json` by server name.

## Sources

- `DevTools/DatabaseTools/Db2-ShadowDatabase/Run-FullShadowPipeline.ps1`
- `DevTools/DatabaseTools/Db2-ShadowDatabase/Invoke-ShadowDatabaseOrchestrator.ps1`
- `DevTools/DatabaseTools/Db2-ShadowDatabase/Verify-LocalDb2Connection.ps1`
