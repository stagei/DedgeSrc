# Mistake: Emergency Cleanup Feature Mix-up (Rolled Back)

## What happened

An **emergency database cleanup** feature was implemented in DbExplorer based on instructions that were **mixed between Cursor instances** (or between different projects/contexts). The request referred to an "import job," a "log table," and a 30 GB threshold—context that did not belong to this project. The feature was fully implemented (service, CLI command, config, UI, automation, and documentation) and has since been **fully rolled back**.

## Lesson for agents

1. **Verify instructions and scope**  
   Before implementing a feature, confirm that the request applies to **this** project and that terms (e.g. "import job," "log table") refer to something that exists or is planned here.

2. **Check project context**  
   If the user mentions something that does not appear in the codebase (e.g. no import job or log table), clarify or treat the request as out of scope for this repo.

3. **Avoid cross-context implementation**  
   Do not implement features that clearly belong to another codebase or another Cursor conversation without explicit confirmation that they are intended for DbExplorer.

## What was rolled back

- **Deleted**: `EmergencyDatabaseCleanupService.cs`, `EmergencyCleanupConfigService.cs`, `EmergencyCleanupConfig.cs`, `EmergencyCleanupDialog.xaml` / `.xaml.cs`, `EMERGENCY_DATABASE_CLEANUP.md`
- **Reverted**: CLI `emergency-cleanup` command and related parser options in `CliCommandHandlerService` and `CliArgumentParser`
- **Reverted**: Tools → Emergency cleanup menu item, MainWindow timer, and all automation in `MainWindow.xaml` / `MainWindow.xaml.cs`
- **Reverted**: Emergency database cleanup section in `APPLICATION_ARCHITECTURE.md`

No emergency cleanup functionality remains in the project. This document is kept as a record of the mistake and to guide future agents.
