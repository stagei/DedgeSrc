# DedgeSign - Signing MSI Files from C# Projects

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-02-26  
**Technology:** PowerShell / C# / WiX

---

## Overview

MSI signing uses the exact same `DedgeSign.ps1` calling convention as EXE/DLL signing.
No special parameters, no different syntax -- just point `-Path` at the `.msi` file.

---

## Calling Convention (unchanged)

```xml
<Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1&quot; -Path &quot;$(PathToFile)&quot; -Action Add -NoConfirm -Parallel" />
```

| Parameter | Value | Notes |
|---|---|---|
| `-Path` | Path to `.msi`, `.exe`, `.dll`, etc. | Same parameter for all file types |
| `-Action` | `Add` or `Remove` | Same as before |
| `-NoConfirm` | (switch) | Skips interactive prompt |
| `-Parallel` | (switch) | Optional, enables parallel signing |

---

## Example: Signing EXE (existing pattern)

From `IIS-AutoDeploy.Tray.csproj`:

```xml
<Target Name="PostBuild" AfterTargets="PostBuildEvent" Condition="'$(ShouldSign)' == 'true'">
  <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1&quot; -Path &quot;$(TargetPath)&quot; -Action Add -NoConfirm -Parallel" />
</Target>
```

## Example: Signing MSI from WiX project

Add to `IIS-AutoDeploy.Tray.Installer.wixproj`:

```xml
<Target Name="SignMsi" AfterTargets="Build">
  <PropertyGroup>
    <MsiPath>$(OutputPath)$(OutputName).msi</MsiPath>
  </PropertyGroup>
  <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1&quot; -Path &quot;$(MsiPath)&quot; -Action Add -NoConfirm"
        Condition="Exists('$(MsiPath)')" />
</Target>
```

## Example: Signing MSI from PowerShell

```powershell
# Direct script call
pwsh.exe -ExecutionPolicy Bypass -File "dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1" `
    -Path "C:\opt\src\DedgeAuth\src\IIS-AutoDeploy.Tray.Installer\bin\Release\IIS-AutoDeploy.Tray.Setup.msi" `
    -Action Add -NoConfirm

# Or via module (when DedgeSign module is available)
Import-Module DedgeSign -Force
Invoke-DedgeSign -Path "C:\path\to\Setup.msi" -Action Add -NoConfirm
```

---

## What Changed (2026-02-26)

Two bugs were fixed in `DedgeSign.psm1` that could cause MSI signing to fail:

1. **Operator precedence bug in `Set-Signature`** -- `-not $extension -match '...'` was evaluated as `(-not $extension) -match '...'` making the extension validation dead code. Fixed with parentheses.

2. **Unreliable MSI signature verification** -- `Get-AuthenticodeSignature` can be unreliable for MSI/MSP/MST files. `Test-FileSignature` now uses `signtool verify /pa` for these formats.

---

## Summary

| Question | Answer |
|---|---|
| Is the calling convention different for MSI? | **No.** Identical to EXE/DLL signing. |
| Do I need different parameters? | **No.** Same `-Path`, `-Action`, `-NoConfirm`. |
| What changed? | Internal bug fixes in the module only. |
| Where is the canonical module? | `_Modules\DedgeSign\DedgeSign.psm1` (single source of truth) |
