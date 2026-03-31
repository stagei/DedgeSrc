# PowerShell Origins for AutoDocJson C#

This document maps each C# component to its original PowerShell source files.

## Overview

The AutoDocJson C# solution is a port of the legacy PowerShell-based AutoDoc documentation system. All parsing logic, template handling, and batch orchestration were converted from PowerShell to C# for improved performance.

## Component Mapping

### Main Entry Point

| C# Component | PowerShell Origin |
|--------------|-------------------|
| `AutoDocJson/Program.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1` (lines 1-200) |
| `AutoDocJson.Core/CommandLineOptions.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1` (param block, lines 12-65) |
| `AutoDocJson/KillProcessHandler.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1` (Kill Other AutoDoc Processes region) |

### Core Library

| C# Component | PowerShell Origin |
|--------------|-------------------|
| `AutoDocJson.Core/BatchRunner.cs` | `AutoDocBatchRunner.ps1` main body (lines 2057-3203), handler functions |
| `AutoDocJson.Core/RegenerationDecider.cs` | `AutoDocBatchRunner.ps1` `RegenerateAutoDoc` (lines 1072-1200), `RegenerateAutoDocSql` (lines 1202-1263) |
| `AutoDocJson.Core/LastBatchRunState.cs` | `AutoDocBatchRunner.ps1` last execution date logic (lines 2448-2462). Replaces legacy `LastExecutionStore.cs` with JSON-based state and PID lock. |
| `AutoDocJson.Core/GitChangeDetector.cs` | New: Per-repo git change detection replacing per-file git log calls |
| `AutoDocJson.Core/WorklistManager.cs` | New: File-based worklist creation and lock-delete-read processing |
| `AutoDocJson.Core/WorkItem.cs` | `AutoDocBatchRunner.ps1` unified queue item structure (lines 2619-2723) |
| `AutoDocJson.Core/WorkQueueBuilder.cs` | `AutoDocBatchRunner.ps1` file collection with regen checks (lines 2606-2725) |
| `AutoDocJson.Core/JsonIndexService.cs` | `AutoDocBatchRunner.ps1` `CreateAllJsonIndexFiles` (lines 570-860) |
| `AutoDocJson.Core/CobdokExportService.cs` | `AutoDocBatchRunner.ps1` `HandleCobdokExport` (1848-1962), `ExportTableContentToFile` (923-1070), `ConvertFromAnsi1252ToUtf8` (901-922) |
| `AutoDocJson.Core/RepoSyncService.cs` | `AutoDocBatchRunner.ps1` repo sync (lines 2401-2439) + `AzureFunctions.psm1` |
| `AutoDocJson.Core/ContentZipHelper.cs` | `AutoDocBatchRunner.ps1` zip/unzip logic (lines 2386-2399, 3140-3151) |
| `AutoDocJson.Core/SqlInteractionsScanner.cs` | `AutoDocFunctions.psm1` `Search-HtmlFilesForSqlInteractions` (lines 8666-8808) |
| `AutoDocJson.Core/ISingleFileParser.cs` | `AutoDocBatchRunner.ps1` single-file dispatch (lines 2464-2573) |
| `AutoDocJson.Core/ICSharpProjectRunner.cs` | `AutoDocBatchRunner.ps1` `HandleCSharpProjects` (lines 1713-1846) |
| `AutoDocJson.Core/IGsFileRunner.cs` | `AutoDocBatchRunner.ps1` `HandleGsFiles` (lines 1328-1481) |
| `AutoDocJson.Core/Logger.cs` | `GlobalFunctions.psm1` (`Write-LogMessage` function) |
| `AutoDocJson.Core/ParserBase.cs` | `AutoDocFunctions.psm1` (shared utilities) |
| `AutoDocJson.Core/ConfigurationManager.cs` | `AutoDocBatchRunner.ps1` (configuration section) |
| `AutoDocJson.Core/PathHelper.cs` | `AutoDocFunctions.psm1` (`Get-AutodocSharedFolder`, path utilities) |
| `AutoDocJson.Core/SmsService.cs` | `GlobalFunctions.psm1` (`Send-Sms` function) |

### Parsers

| C# Component | PowerShell Origin (Current) | PowerShell Origin (Legacy) |
|--------------|-----------------------------|-----------------------------|
| `AutoDocJson.Parsers/CblParser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-CblParse`) | `C:\opt\src\DedgePsh\_Modules\_old\CblParseFunctions.psm1` |
| `AutoDocJson.Parsers/RexParser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-RexParse`) | `C:\opt\src\DedgePsh\_Modules\_old\RexParseFunctions.psm1` |
| `AutoDocJson.Parsers/BatParser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-BatParse`) | `C:\opt\src\DedgePsh\_Modules\_old\BatParseFunctions.psm1` |
| `AutoDocJson.Parsers/Ps1Parser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-Ps1Parse`) | `C:\opt\src\DedgePsh\_Modules\_old\Ps1ParseFunctions.psm1` |
| `AutoDocJson.Parsers/SqlParser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-SqlParse`) | `C:\opt\src\DedgePsh\_Modules\_old\SqlParseFunctions.psm1` |
| `AutoDocJson.Parsers/CSharpParser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-CSharpParse`, `Start-CSharpEcosystemParse`) | `C:\opt\src\DedgePsh\_Modules\_old\CSharpParseFunctions.psm1` |
| `AutoDocJson.Parsers/GsParser.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (`Start-GsParse`, lines 11964-12193) | N/A |
| `AutoDocJson.Parsers/ParserBase.cs` | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` (shared functions) | N/A |

### Additional Parsers (Legacy Scripts)

These scripts in `_old` folder were the original standalone parsers before consolidation:

| C# Component | Legacy Standalone Script |
|--------------|--------------------------|
| `CblParser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\CblParse.ps1` |
| `RexParser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\RexParse.ps1` |
| `BatParser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\BatParse.ps1` |
| `Ps1Parser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\Ps1Parse.ps1` |
| `SqlParser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\SqlParse.ps1` |
| `CSharpParser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\CSharpParse.ps1` |
| `CSharpEcosystemParser.cs` | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_old\CSharpEcosystemParse.ps1` |

### Testing & Automation

| C# Component | PowerShell Origin |
|--------------|-------------------|
| `AutoDocJson.Tests/ComparativeTester.cs` | `C:\opt\src\DedgePsh\AutoDocJson\AutoDocJson.Tests\VerifyAndCompareHtml.ps1` |
| `AutoDocJson.Tests/OvernightRunner.ps1` | New (automation wrapper for C# batch runner) |
| `AutoDocJson.Tests/OvernightMonitor.ps1` | New (SMS monitoring for overnight runs) |
| `AutoDocJson.Tests/RunPowerShellBatchRunner.ps1` | Wrapper to invoke: `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1` |

### Utilities & Support Scripts

| C# Component/Feature | PowerShell Origin |
|-----------------------|-------------------|
| Error file handling | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Fix-AutoDocErrors.ps1` |
| Error HTML cleanup | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Remove-FixedErrorHtmlFiles.ps1` |
| Regenerated file cleanup | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Remove-RegeneratedFiles.ps1` |
| Path fixing | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Fix-AutoDocPaths.ps1` |
| Process termination | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Stop-AutoDocProcesses.ps1` |
| Deployment | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_deploy.ps1` |
| Local IIS deployment | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_deployLocalIIS.ps1` |
| Installation | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_install.ps1` |
| Dialog system parser test | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Test-DialogSystemParser.ps1` |
| AutoDoc generation test | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\Test-AutoDocGeneration.ps1` |

## Shared Resources

The following resources are used by both PowerShell and C# versions:

| Resource | Location |
|----------|----------|
| HTML Templates | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_templates\` |
| CSS Stylesheets | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_css\` |
| JavaScript | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_js\` |
| Images/Icons | `C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\_images\` |

## Module Dependencies

### PowerShell Modules Used by AutoDoc

| Module | Path | Purpose |
|--------|------|---------|
| GlobalFunctions | `C:\opt\src\DedgePsh\_Modules\GlobalFunctions\GlobalFunctions.psm1` | Logging, SMS, utilities |
| AutoDocFunctions | `C:\opt\src\DedgePsh\_Modules\AutoDocFunctions\AutoDocFunctions.psm1` | All parser functions |
| Db2-Handler | `C:\opt\src\DedgePsh\_Modules\Db2-Handler\Db2-Handler.psm1` | DB2 cobdok exports |
| Handle-RamDisk | `C:\opt\src\DedgePsh\_Modules\Handle-RamDisk\Handle-RamDisk.psm1` | RAM disk for temp files |

## Function Mapping

### Key Functions Ported from AutoDocBatchRunner.ps1

| PowerShell Function | C# Method/Class |
|--------------------|---------------------|
| `HandleCblFiles` (line 1265) | `WorkQueueBuilder.Build()` + `BatchRunner.DispatchParse()` |
| `HandleScriptFiles` (line 1483) | `WorkQueueBuilder.Build()` + `BatchRunner.DispatchParse()` |
| `HandleSqlTables` (line 1650) | `WorkQueueBuilder.Build()` + `BatchRunner.DispatchParse()` |
| `HandleCSharpProjects` (line 1713) | `BatchRunner.HandleCSharpProjects()` |
| `HandleGsFiles` (line 1328) | `BatchRunner.HandleGsFiles()` + `GsParser.StartGsParse()` |
| `HandleCobdokExport` (line 1848) | `CobdokExportService.Export()` |
| `ExportTableContentToFile` (line 923) | `CobdokExportService.BuildExportCommand()` |
| `ConvertFromAnsi1252ToUtf8` (line 901) | `CobdokExportService.ConvertFromAnsi1252ToUtf8()` |
| `RegenerateAutoDoc` (line 1072) | `RegenerationDecider.ShouldRegenerateFile()` |
| `RegenerateAutoDocSql` (line 1202) | `RegenerationDecider.ShouldRegenerateSqlTable()` |
| `CreateAllJsonIndexFiles` (line 570) | `JsonIndexService.UpdateAll()` |
| `Get-OptimalThreadCount` (line 312) | `BatchRunner.Run()` (inline thread count logic) |
| `Invoke-ParallelFileParsing` (line 473) | `Parallel.ForEach` in `BatchRunner.Run()` |
| `Copy-StaticAssetsToOutput` (line 2046) | `BatchRunner.CopyStaticAssetsToOutput()` |
| `CreateFolderIfNeeded` (line 1982) | `BatchRunner.CreateFolderIfNeeded()` |
| `SetFullFolderPath` (line 1967) | Not needed (C# uses `Path.GetFullPath`) |
| Main body (lines 2057-3203) | `BatchRunner.Run()` |

### Key Functions Ported from AutoDocFunctions.psm1

| PowerShell Function | C# Method Location |
|--------------------|---------------------|
| `Start-CblParse` | `CblParser.cs` → `StartCblParse()` |
| `Start-RexParse` | `RexParser.cs` → `StartRexParse()` |
| `Start-BatParse` | `BatParser.cs` → `StartBatParse()` |
| `Start-Ps1Parse` | `Ps1Parser.cs` → `StartPs1Parse()` |
| `Start-SqlParse` | `SqlParser.cs` → `StartSqlParse()` |
| `Start-CSharpParse` | `CSharpParser.cs` → `StartCSharpParse()` |
| `Start-CSharpEcosystemParse` | `CSharpParser.cs` → `StartCSharpEcosystemParse()` |
| `Start-GsParse` | `GsParser.cs` → `StartGsParse()` |
| `Search-HtmlFilesForSqlInteractions` | `SqlInteractionsScanner.cs` → `Scan()` |
| `Get-AutodocSharedFolder` | `PathHelper.cs` → `GetAutodocSharedFolder()` |
| `Find-AutodocUsages` | `ParserBase.cs` → `FindAutodocUsages()` |
| `Write-LogMessage` | `Logger.cs` → `LogMessage()` |

### Shared Parser Utilities

| PowerShell Origin | C# Utility |
|--------------------|---------------------|
| Script-level `$mmdContent`/`$sequenceContent` variables | `MermaidWriter.cs` (thread-safe Mermaid content builder) |
| SQL detection in `Start-BatParse`/`Start-RexParse`/`Start-Ps1Parse`/`Start-CblParse` | `SqlParseHelper.cs` (shared SQL statement detection and extraction) |
| `Get-*ExecutionPathDiagram` in BAT/REX/PS1/CBL parsers | `ExecutionPathHelper.cs` (shared execution path discovery, diagram gen, SVG) |

### CSharpParser.cs - All 30+ Functions Translated

| PowerShell Function (line) | C# Method |
|--------------------|---------------------|
| `Initialize-CSharpParseVariables` (9104) | `InitializeCSharpParseVariables()` |
| `Get-CSharpFiles` (9119) | `GetCSharpFiles()` |
| `Get-SolutionProjects` (9143) | `GetSolutionProjects()` |
| `Get-ProjectReferences` (9189) | `GetProjectReferences()` |
| `Read-CSharpFile` (9268) | `ReadCSharpFile()` |
| `Write-CSharpMmdClass/Flow/Interaction/ExecFlow` | `WriteCSharpMmd*()` |
| `Get-CSharpProcessInvocations` (9522) | `GetCSharpProcessInvocations()` |
| `New-CSharpProcessDiagram` (9635) | `NewCSharpProcessDiagram()` |
| `Get-CSharpApiConfiguration` (9717) | `GetCSharpApiConfiguration()` |
| `Find-ExternalApiCallers` (9835) | `FindExternalApiCallers()` |
| `Get-MethodBody` (9977) | `GetMethodBody()` |
| `Get-MethodControlFlow` (10010) | `GetMethodControlFlow()` |
| `Get-AllProjectsInFolder` (10088) | `GetAllProjectsInFolder()` |
| `Get-ProjectCommunication` (10297) | `GetProjectCommunication()` |
| `New-EcosystemDiagram` (10383) | `NewEcosystemDiagram()` |
| `New-ExecutionFlowDiagram` (10524) | `NewExecutionFlowDiagram()` |
| `New-ClassDiagram` (10706) | `NewClassDiagram()` |
| `New-ProjectInteractionDiagram` (10798) | `NewProjectInteractionDiagram()` |
| `New-NamespaceFlowDiagram` (10825) | `NewNamespaceFlowDiagram()` |
| `Start-CSharpParse` (10894) | `StartCSharpParse()` |
| `Start-CSharpEcosystemParse` (11378) | `StartCSharpEcosystemParse()` |
| `New-ClassListHtml` (11888) | `NewClassListHtml()` |
| `New-ProjectListHtml` (11907) | `NewProjectListHtml()` |
| `New-NamespaceListHtml` (11924) | `NewNamespaceListHtml()` |
| `ScanCSharpMethodForSql` (7305) | Integrated into `ReadCSharpFile()` SQL detection |

### Key Functions Ported from GlobalFunctions.psm1

| PowerShell Function | C# Method Location |
|--------------------|---------------------|
| `Write-LogMessage` | `AutoDocJson.Core/Logger.cs` → `LogMessage()` |
| `Send-Sms` | `AutoDocJson.Core/SmsService.cs` → `SendSms()` |

## Version History

| Date | Description |
|------|-------------|
| 2024-12 | Initial C# port started |
| 2025-01 | Parser consolidation in AutoDocFunctions.psm1 |
| 2026-01 | AutoDocFunctions migrated to `_Modules/AutoDocFunctions/` |
| 2026-02 | NLog integration in C# Logger |
| 2026-02 | Overnight automation scripts added |
| 2026-02 | Full BatchRunner translation: cobdok export, regen decider, work queue, parallel processing, JSON indexes, CSharp/GS handlers, SQL interactions, zip, SMS |
| 2026-02 | Shared parser utilities: MermaidWriter, SqlParseHelper, ExecutionPathHelper |
| 2026-02 | Full line-by-line parser translations: BatParser, RexParser, Ps1Parser, CblParser, SqlParser, CSharpParser (all 30+ functions) |

## Notes

1. **Parser Consolidation**: Originally, each parser had its own module (`CblParseFunctions.psm1`, etc.). These were consolidated into a single `AutoDocFunctions.psm1` module in January 2025. The old modules are preserved in `_Modules\_old\` for reference.

2. **Standalone Scripts**: The `_old` folder in `DevTools/LegacyCodeTools/AutoDoc/` contains the original standalone parser scripts that were later refactored into module functions.

3. **Log Format Compatibility**: The C# `Logger.cs` maintains the same log format as PowerShell's `Write-LogMessage` to enable unified log analysis across both systems.

4. **Output Folders**: PowerShell outputs to `C:\opt\Webs\AutoDoc\`, while C# outputs to `C:\opt\Webs\AutoDocJson\` to allow side-by-side comparison.

5. **RAM Disk**: The PowerShell `Initialize-RamDisk`, `Get-WorkFolderRoot`, and `Remove-AutoDocRamDisk` functions are NOT ported. The C# `CommandLineOptions` accepts `-UseRamDisk` but ignores it. All temp work uses standard disk paths.

6. **Full Coverage**: As of Feb 2026, every function in `AutoDocBatchRunner.ps1` has a C# equivalent except RAM disk (intentionally excluded). The C# `BatchRunner.Run()` replicates the exact flow from the PS main body (lines 2057-3203).
