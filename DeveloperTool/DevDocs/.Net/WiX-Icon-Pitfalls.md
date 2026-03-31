# WiX Installer Icon Pitfalls

Common icon-related mistakes discovered while building the DedgeRemoteConnect WiX v6 installer.
Share this with any project that uses a `.ico` file in a WiX MSI.

---

## 1. Broken `.ico` file — blank shortcut icon after install

### Symptom

Shortcuts on the Desktop and Start Menu show a **blank/generic page icon** after installation,
even though the `<Icon>` element in `Package.wxs` correctly references a `.ico` file.

### Root cause

Windows Shell requires an ICO file to contain **multiple square images** at standard sizes.
The ICO file was invalid in two ways:

| Problem | Value found | Required |
|---|---|---|
| Number of images | **1** | Minimum 3 (16, 32, 48) |
| Image dimensions | **256×240** (non-square!) | Must be square (N×N) |
| Compression | BMP/DIB uncompressed | PNG preferred for 48px+ |
| Small sizes present | None | 16×16 and 32×32 are mandatory |

When Windows tries to render the shortcut at 16×16 or 32×32, it cannot scale a single
non-square 256×240 image. Result: blank icon.

### How to detect this

Run this in PowerShell against any `.ico` you plan to embed:

```powershell
$bytes = [IO.File]::ReadAllBytes("path\to\app.ico")
$count = [BitConverter]::ToUInt16($bytes, 4)
Write-Output "Images: $count"
for ($i = 0; $i -lt $count; $i++) {
    $off = 6 + $i * 16
    $w = $bytes[$off];     if ($w -eq 0) { $w = 256 }
    $h = $bytes[$off + 1]; if ($h -eq 0) { $h = 256 }
    $sz = [BitConverter]::ToUInt32($bytes, $off + 8)
    $isPng = ($bytes[[BitConverter]::ToUInt32($bytes, $off + 12)] -eq 0x89)
    Write-Output "  [$i]: $($w)x$($h)  $sz bytes  $(if ($isPng) {'PNG'} else {'BMP'})"
}
```

**Good output** (what you need):

```
Images: 4
  [0]: 16x16   193 bytes  PNG
  [1]: 32x32   425 bytes  PNG
  [2]: 48x48   581 bytes  PNG
  [3]: 256x256 2951 bytes PNG
```

**Bad output** (what caused the blank icon):

```
Images: 1
  [0]: 256x240  253480 bytes  BMP   ← non-square, no small sizes
```

### Fix

Generate a standards-compliant ICO with all required sizes using
`DedgeRemoteConnect.Installer\Generate-Icon.ps1` as a reference.
Minimum required sizes: **16×16, 32×32, 48×48**. Recommended: also include **256×256 PNG**.

---

## 2. `REINSTALL=ALL` blocks `MajorUpgrade` — new components never installed

### Symptom

After publishing a new MSI version and running:

```powershell
msiexec /i new.msi /qb REINSTALL=ALL REINSTALLMODE=amus
```

- Old product version remains installed
- New components (e.g. changed registry keys, new shortcuts) are **never created**
- MSI log shows: `Skipping RemoveExistingProducts action: current configuration is maintenance mode`

### Root cause

When `REINSTALL=ALL` is passed to `msiexec /i`, the engine interprets it as a **repair/maintenance**
of the currently installed product — not a fresh install of the new package.
This causes `RemoveExistingProducts` to be skipped, so `MajorUpgrade` never fires and the
new package's components are never applied.

From the MSI log:
```
Component: AutoStartEntry; Installed: Absent; Request: Null; Action: Null
Skipping RemoveExistingProducts action: current configuration is maintenance mode or an uninstall
```

### Fix

Use a plain `/i` install. The `<MajorUpgrade>` element inside the MSI handles uninstalling
the old version automatically:

```powershell
# CORRECT — MajorUpgrade fires, old product removed, new product installed
msiexec /i new.msi /qb /l*v install.log

# WRONG — triggers maintenance mode, MajorUpgrade is skipped
msiexec /i new.msi /qb REINSTALL=ALL REINSTALLMODE=amus
```

`REINSTALL=ALL REINSTALLMODE=amus` is only appropriate for **same-version repairs** (e.g.
a user accidentally deleted a file and you want to restore it), not for version upgrades.

---

## 3. AutoStart registry — `HKCU` vs `HKLM`

### Symptom

The application does not start on login for users other than the one who ran the installer.

### Root cause

Using `Root="HKCU"` in the `AutoStart` component writes the Run entry to the installing
user's profile only. For machine-wide installs (the default for WiX), `HKLM` is correct.

```xml
<!-- Wrong: only starts for the user who installed -->
<RegistryValue Root="HKCU"
               Key="SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
               Name="My App" Type="string"
               Value="[INSTALLFOLDER]MyApp.exe" KeyPath="yes" />

<!-- Correct: starts for all users on the machine -->
<RegistryValue Root="HKLM"
               Key="SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
               Name="My App" Type="string"
               Value="[INSTALLFOLDER]MyApp.exe" KeyPath="yes" />
```

> **Note:** When changing `Root` from `HKCU` to `HKLM`, generate a **new component GUID**
> and bump the MSI version so `MajorUpgrade` removes the old HKCU entry cleanly.

---

## 4. Version must be bumped for `MajorUpgrade` to trigger

### Symptom

Reinstalling the MSI after making changes to `Package.wxs` (new shortcuts, changed registry
entries) has no effect — the old configuration persists.

### Root cause

`<MajorUpgrade>` only fires when the new MSI's `Version` attribute is **higher** than the
installed version. If the version is the same, Windows Installer treats it as the same
product and does a repair instead of an upgrade.

### Fix

Increment the `Version` in `Package.wxs` for every release that changes components:

```xml
<Package Version="1.4.0" ... />
```

The version is a 3-part number (`major.minor.patch`). WiX derives the `ProductCode` from
the version and `UpgradeCode`, so incrementing the version automatically produces a new
`ProductCode` — no manual GUID management needed for normal upgrades.

---

## Quick checklist before building an MSI

- [ ] `.ico` file has at least 16×16, 32×32, and 48×48 images
- [ ] All ICO images are **square** (width == height)
- [ ] ICO verified with the PowerShell snippet above
- [ ] `AutoStart` uses `Root="HKLM"` for machine-wide installs
- [ ] `Version` is incremented from the previous release
- [ ] Install command uses plain `/i` (not `REINSTALL=ALL`) for upgrades
- [ ] `<MajorUpgrade>` element is present in `Package.wxs`
