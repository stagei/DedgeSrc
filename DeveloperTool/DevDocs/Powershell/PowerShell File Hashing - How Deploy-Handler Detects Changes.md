# PowerShell File Hashing — How Deploy-Handler Detects Changes

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-17  
**Technology:** PowerShell

---

## Overview

A **hash** is a fixed-length string of characters computed from a file's entire content using a mathematical algorithm. It acts as a **digital fingerprint** — if even a single character in the file changes, the hash becomes completely different.

---

## Key Properties

| Property | Meaning |
|---|---|
| **Deterministic** | Same file content always produces the same hash |
| **Fixed length** | Output is always the same length regardless of file size |
| **Avalanche effect** | Changing 1 byte changes the entire hash |
| **One-way** | You cannot reconstruct the file from the hash |

## Real Example: `IIS-DeployApp\_deploy.ps1`

The file contains just 5 lines (169 bytes):

```powershell
param (
    [bool]$DeployModules = $true
)
Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("dedge-server", "p-no1fkxprd-app") -DeployModules $DeployModules
```

Its hash values:

| Algorithm | Hash |
|---|---|
| **SHA256** | `79DC7E936B98A3C60B4EC50293420F701CBAB40ECD426962D830FF4A20DF446C` |
| **MD5** | `32FBAC4DC63E7B14532374AEEDE1CB0C` |

If you changed even one letter — say `$true` to `$True` — both hashes would become entirely different strings.

## How Deploy-Handler Uses Hashes

When `Deploy-Files` runs, it computes the hash of each source file and compares it to a stored `.version` marker on the target server. If the hashes match, the file is skipped ("No new files to deploy"). If they differ, the file is copied, signed, and deployed. This is why hash comparison is much more reliable than checking timestamps — it detects actual content changes, not just when the file was last saved.

## PowerShell Commands

```powershell
# Compute SHA256 hash (default)
Get-FileHash "path\to\file" -Algorithm SHA256

# Compute MD5 hash
Get-FileHash "path\to\file" -Algorithm MD5

# Compare two files by hash
$hash1 = (Get-FileHash "file1.ps1").Hash
$hash2 = (Get-FileHash "file2.ps1").Hash
if ($hash1 -eq $hash2) { "Files are identical" } else { "Files differ" }
```
