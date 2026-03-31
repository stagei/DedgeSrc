# PowerShell Syntax Checker

Validates PowerShell script syntax using the official PowerShell parser.

## Why Use This?

IDE linters (VSCode, Cursor) can produce **false positives** on large or complex PowerShell files. The `[System.Management.Automation.Language.Parser]::ParseFile` method is the authoritative source for syntax validation.

**If this script reports "No syntax errors", the code is valid** - even if the IDE shows errors.

## Usage

```powershell
# Check a single file
.\PowerShell-SyntaxChecker.ps1 -Path "C:\scripts\MyScript.ps1"

# Check all PowerShell files in a directory
.\PowerShell-SyntaxChecker.ps1 -Path "C:\scripts" -Recurse

# Check files from pipeline
Get-ChildItem *.ps1 | .\PowerShell-SyntaxChecker.ps1
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Path` | string[] | Path to file(s) or directory to check |
| `-Recurse` | switch | Recursively check subdirectories |

## Output

```
PowerShell Syntax Checker
=========================
Checking 5 file(s)...

OK: Script1.ps1
OK: Script2.ps1
ERRORS: Script3.ps1
  Line 42: Missing closing '}' in statement block
OK: Script4.ps1
OK: Script5.ps1

-------------------------
Summary:
  Files checked:    5
  Files with errors: 1
  Total errors:     1
```

## When to Use

- When IDE linters show many syntax errors on large files
- Before committing changes to verify syntax
- In CI/CD pipelines for validation
- When troubleshooting "false positive" linter errors
