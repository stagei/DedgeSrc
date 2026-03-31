# ProgramNames — Modern C# Project Name Mapping

## Purpose

Legacy COBOL program names follow a 6-8 character naming convention established in the 1980s
(e.g. `RUHBEHK`, `BDHETIK`, `AABKCSV`). The naming encodes subsystem and function type through
positional character rules, but these conventions are undocumented and known only to senior
developers.

This folder stores **AI-suggested descriptive C# project/class names** for each legacy program,
enabling a modernization roadmap where each COBOL program can be mapped to a meaningful .NET
project with a clear purpose.

## How Names Are Generated

Program naming uses comprehensive context from the analysis pipeline:

- **Classification**: program role (main-ui, batch-processing, webservice, common-utility)
- **COBDOK metadata**: system, sub-system, Norwegian description, deprecated status
- **Table usage**: which DB2 tables the program reads/writes, with future table names if available
- **Call graph**: which programs it calls and is called by
- **Dedge Code RAG**: COBOL source snippets showing the program's main logic flow

This context lets the AI understand that `RUHBEHK` is not just a random string but a grain
maintenance handler that manages stock levels and pricing calculations.

## File Format

One JSON file per program: `{PROGRAMNAME}.json`

```json
{
  "program": "RUHBEHK",
  "futureProjectName": "GrainStockMaintenance",
  "futureNamespace": "Agriculture.Grain",
  "description": "Manages grain stock levels, pricing calculations, and inventory adjustments",
  "model": "qwen2.5:7b",
  "protocol": "Naming-ProgramNames",
  "analyzedAt": "2026-03-25T15:00:00"
}
```

## Downstream Use

These mappings will guide the modernization roadmap:

- Project scaffolding with descriptive solution/project names
- Architecture documentation mapping old-to-new
- Dependency graphs using meaningful names instead of cryptic codes
- Sprint planning with human-readable feature descriptions
