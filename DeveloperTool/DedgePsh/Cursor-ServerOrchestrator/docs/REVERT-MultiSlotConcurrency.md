# Revert Commands — Multi-Slot Concurrency (2026-03-22)

If the `_username_project` suffix changes fail and need to be rolled back, run these commands.

## Pre-Change Commit Hashes

| Repo | Path | Commit Hash |
|------|------|-------------|
| DedgePsh | `C:\opt\src\DedgePsh` | `4f2c9b664ab9f36e322c5f1818c58b755832c8c9` |
| DedgeAuth | `C:\opt\src\DedgeAuth` | `61a03a15af51eff63c022c1243fb6ef42053672e` |
| DocView | `C:\opt\src\DocView` | `c11a3cb41b97a089f9ba5246a5c03927e69d25b6` |
| GenericLogHandler | `C:\opt\src\GenericLogHandler` | `64f3a7d624953eed5095a9d7e9efe977db3a41e1` |
| ServerMonitor | `C:\opt\src\ServerMonitor` | `e830822eea7d4dcddebe413e0f38e8d9a7451c9b` |
| AutoDocJson | `C:\opt\src\AutoDocJson` | `dfd56905264e278773ea40d201f7b235b3c51091` |

## Revert All Repos (git reset --hard)

```powershell
# DedgePsh
git -C "C:\opt\src\DedgePsh" reset --hard 4f2c9b664ab9f36e322c5f1818c58b755832c8c9
git -C "C:\opt\src\DedgePsh" push --force

# DedgeAuth
git -C "C:\opt\src\DedgeAuth" reset --hard 61a03a15af51eff63c022c1243fb6ef42053672e
git -C "C:\opt\src\DedgeAuth" push --force

# DocView
git -C "C:\opt\src\DocView" reset --hard c11a3cb41b97a089f9ba5246a5c03927e69d25b6
git -C "C:\opt\src\DocView" push --force

# GenericLogHandler
git -C "C:\opt\src\GenericLogHandler" reset --hard 64f3a7d624953eed5095a9d7e9efe977db3a41e1
git -C "C:\opt\src\GenericLogHandler" push --force

# ServerMonitor
git -C "C:\opt\src\ServerMonitor" reset --hard e830822eea7d4dcddebe413e0f38e8d9a7451c9b
git -C "C:\opt\src\ServerMonitor" push --force

# AutoDocJson
git -C "C:\opt\src\AutoDocJson" reset --hard dfd56905264e278773ea40d201f7b235b3c51091
git -C "C:\opt\src\AutoDocJson" push --force
```

## Restore Orchestrator Scripts From Backup

If only the orchestrator scripts need restoring (without reverting git):

```powershell
$backup = "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator_backup_20260322"
$target = "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator"

# Restore the 4 changed script files
Copy-Item "$backup\Invoke-CursorOrchestrator.ps1" "$target\Invoke-CursorOrchestrator.ps1" -Force
Copy-Item "$backup\_helpers\_Shared.ps1" "$target\_helpers\_Shared.ps1" -Force
Copy-Item "$backup\_helpers\_CursorAgent.ps1" "$target\_helpers\_CursorAgent.ps1" -Force
Copy-Item "$backup\_localHelpers\Get-OrchestratorStatus.ps1" "$target\_localHelpers\Get-OrchestratorStatus.ps1" -Force
```

## Redeploy After Revert

After reverting, redeploy the old code to servers:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator\_deploy.ps1"
```

## Cleanup Backup Folder

Once verified stable (either after successful rollout or successful revert):

```powershell
Remove-Item "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator_backup_20260322" -Recurse -Force
```
