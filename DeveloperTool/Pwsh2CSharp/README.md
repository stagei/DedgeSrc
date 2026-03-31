# Pwsh2CSharp — PowerShell to C# Converter

Converts PowerShell 7 scripts to C# using a custom AST-based converter and optional AI-powered cleanup via Cursor Agent CLI.

## Pipeline

```
*.ps1 → [PS7 AST Parser] → [Recursive Emitter] → raw/*.cs → [Agent CLI cleanup] → cleaned/*.cs
```

1. **Mechanical AST conversion** — Parses `.ps1` files using `[System.Management.Automation.Language.Parser]::ParseFile()`, walks the AST recursively, emits C# code using a configurable cmdlet mapping table.
2. **AI-powered cleanup** (optional) — Cursor Agent CLI refines types, async patterns, DB2 access, DI, and domain-specific logic.
3. **Build verification** (optional) — Runs `dotnet build` on the target project to check compilation.

## Prerequisites

- PowerShell 7+ (`pwsh.exe`)
- .NET 10 SDK (for build verification)
- `GlobalFunctions` module (in PSModulePath)
- Cursor Agent CLI at `C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-AgentCLI\` (for cleanup passes)

## Usage

```powershell
# Convert a single file
pwsh.exe -NoProfile -File Convert-PwshToCSharp.ps1 `
    -InputPath .\MyScript.ps1 `
    -OutputPath .\Output

# Convert a folder of scripts with a target namespace
pwsh.exe -NoProfile -File Convert-PwshToCSharp.ps1 `
    -InputPath C:\opt\src\Project\Scripts `
    -OutputPath C:\temp\converted `
    -Namespace MyApp.Batch

# Mechanical only (skip AI cleanup)
pwsh.exe -NoProfile -File Convert-PwshToCSharp.ps1 `
    -InputPath .\MyScript.ps1 `
    -OutputPath .\Output `
    -SkipCleanup

# With build verification against target project
pwsh.exe -NoProfile -File Convert-PwshToCSharp.ps1 `
    -InputPath .\MyScript.ps1 `
    -OutputPath .\Output `
    -TargetProjectPath C:\opt\src\MyProject\src\MyProject.csproj
```

## Using the converter module directly

```powershell
Import-Module .\Converter\PwshToCSharpConverter.psm1 -Force

# From file
$csharp = ConvertTo-CSharpSource -InputFile .\MyScript.ps1 -Namespace 'MyApp'

# From code string
$csharp = ConvertTo-CSharpSource -InputCode 'param([string]$Name) Write-Host $Name' -ClassName 'Greeter'
```

## Output Structure

```
OutputPath/
  raw/           # Mechanical AST conversion output
  cleaned/       # After Agent CLI cleanup passes
  conversion-report.json
```

## Converter Architecture

The converter module lives in `Converter/` and uses PowerShell 7's built-in AST parser:

| File | Role |
|------|------|
| `PwshToCSharpConverter.psm1` | Module root, dot-sources all functions |
| `CmdletMappings.json` | Configurable cmdlet-to-C# mapping table |
| `Public/ConvertTo-CSharpSource.ps1` | Main exported function |
| `Private/Convert-AstNode.ps1` | Central dispatcher (switches on AST type name) |
| `Private/Convert-ScriptBlock.ps1` | ScriptBlockAst -> C# class skeleton |
| `Private/Convert-FunctionDef.ps1` | FunctionDefinitionAst -> C# method |
| `Private/Convert-ParamBlock.ps1` | ParamBlockAst -> C# typed parameters |
| `Private/Convert-Statement.ps1` | if/for/foreach/while/switch/try/return |
| `Private/Convert-Pipeline.ps1` | PipelineAst -> LINQ chains |
| `Private/Convert-Command.ps1` | CommandAst -> C# via mapping table |
| `Private/Convert-Expression.ps1` | Expressions, operators, strings, hashtables |
| `Private/Resolve-TypeName.ps1` | PS type constraints -> C# type names |
| `Private/Get-CmdletMapping.ps1` | Loads and caches CmdletMappings.json |

## What the converter handles

| PowerShell | C# |
|---|---|
| `param()` blocks with types and defaults | Constructor/method parameters |
| `function Verb-Noun { }` | PascalCase methods |
| `[switch]$Force` | `bool force = false` |
| `if/elseif/else` | `if/else if/else` |
| `foreach/for/while/do-while` | Direct C# equivalents |
| `try/catch/finally` | Typed exception handling |
| `switch` | C# switch with case/break |
| `$x = value` | `var x = value;` with first-use detection |
| `"Hello $Name"` | `$"Hello {name}"` |
| `@{ Key = Value }` | `Dictionary<string, object?>` |
| `-eq/-ne/-gt/-lt` | `==`, `!=`, `>`, `<` |
| `-match/-notmatch` | `Regex.IsMatch()` |
| `| Where-Object { }` | `.Where(item => ...)` |
| `| ForEach-Object { }` | `.Select(item => ...)` |
| `| Sort-Object Property` | `.OrderBy(item => item.Property)` |
| `Write-LogMessage -Level INFO` | `Logger.Info()` (NLog) |
| `Get-Content -Raw` | `File.ReadAllText()` |
| `Set-Content` | `File.WriteAllText()` |
| `Test-Path -PathType Leaf` | `File.Exists()` |
| `ConvertFrom-Json` | `JsonSerializer.Deserialize<JsonElement>()` |
| `Invoke-RestMethod` | `HttpClient.GetAsync()/PostAsync()` |
| `Start-Sleep -Seconds` | `Task.Delay(TimeSpan.FromSeconds())` |

Unmapped cmdlets emit `/* TODO: Convert cmdlet 'X' */` with original source.

## Customizing Cmdlet Mappings

Edit `Converter/CmdletMappings.json` to add or change mappings. Each entry has:

- `emit`: `"simple"` (pattern replacement), `"delegate"` (custom logic in Convert-Command.ps1), `"comment"`, `"discard"`, or `"pipeline"`
- `pattern`: C# template with `{0}` placeholder for arguments (simple mode)
- `using`: Array of required C# using statements

## Running Tests

```powershell
Import-Module Pester -MinimumVersion 5.0 -Force
$config = New-PesterConfiguration
$config.Run.Path = '.\Converter\Tests\ConvertTo-CSharpSource.Tests.ps1'
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

## Cursor Rules

The `.cursor/rules/` folder contains rules for the Agent CLI cleanup passes:

| Rule | Purpose |
|------|---------|
| `pwsh2csharp-conversion.mdc` | General PS-to-C# mapping reference |
| `pwsh2csharp-db2-conversion.mdc` | ODBC -> IBM.Data.Db2 async conversion |
| `code-style.mdc` | C# naming and style conventions |
| `logging-nlog.mdc` | NLog standards |
| `factory-pattern.mdc` | DB-agnostic factory pattern |
| `db2-patterns.mdc` | DB2 connection/query standards |

## Phase 1 — SystemAnalyzer

Target scripts:
- `Regenerate-All-Analyses.ps1` -> `RegenerateAllAnalyses.cs`
- `Run-Analysis.ps1` -> `RunAnalysis.cs`
- `Invoke-FullAnalysis.ps1` -> `InvokeFullAnalysis.cs`

C# project: `c:\opt\src\SystemAnalyzer\src\SystemAnalyzer.Batch.CSharp\`
