# WiX v6 MSI Installer Guide — FK Standard

Complete guide for creating professional Windows MSI installers for FK desktop apps,
based on the working `ServerMonitorDashboard.Tray` installer.

---

## First: Copy the Cursor Rules to Your New Project

The Cursor AI rules that encode all WiX v6 patterns, gotchas, and FK conventions are stored at:

```
C:\opt\src\ServerMonitor\.cursor\rules\wix-installer.mdc
```

Copy it to your new project's rules folder **before you start**, so Cursor AI will automatically
apply all the correct patterns when you work on the installer:

```powershell
# Replace C:\opt\src\MyNewApp with your actual project root
$dest = "C:\opt\src\MyNewApp\.cursor\rules"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item "C:\opt\src\ServerMonitor\.cursor\rules\wix-installer.mdc" $dest
```

Also copy this guide and the bitmap reference to your new project's docs folder:

```powershell
$docDest = "C:\opt\src\MyNewApp\docs"
New-Item -ItemType Directory -Path $docDest -Force | Out-Null
Copy-Item "C:\opt\src\ServerMonitor\docs\WiX-Installer-Guide.md" $docDest
Copy-Item "C:\opt\src\ServerMonitor\docs\WiX-Bitmap-Layout-Reference.md" $docDest
```

---

## Prerequisites

```powershell
# Install WiX CLI globally
dotnet tool install --global wix

# Verify (must be 6.x)
wix --version

# Verify .NET SDK
dotnet --version
```

---

## Project Structure

```
MyApp.Installer/
  MyApp.Installer.wixproj   # SDK-style WiX project
  NuGet.config              # nuget.org + Dedge feeds
  Package.wxs               # Main: package, dirs, components, features, custom actions, UI
  AppFiles.wxs              # File glob — all published binaries
  License.rtf               # EULA in RTF format (Norwegian)
  CustomConfigDlg.wxs       # (optional) Custom wizard dialog for user input
  WriteConfig.ps1           # (optional) Custom action PowerShell script
  WixBanner.bmp             # 493×58 — top banner on inner dialogs
  WixDialog.bmp             # 493×312 — welcome/finish full background
```

---

## Step 1 — Create the `.wixproj`

```xml
<Project Sdk="WixToolset.Sdk/6.0.2">

  <PropertyGroup>
    <OutputName>MyApp.Setup</OutputName>
    <Platform>x64</Platform>
    <!-- ICE61: allow same-version reinstall  ICE80: suppress 32/64-bit dir warning -->
    <SuppressIces>ICE61;ICE80</SuppressIces>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="WixToolset.UI.wixext"   Version="6.*" />
    <PackageReference Include="WixToolset.Util.wixext" Version="6.*" />
  </ItemGroup>

</Project>
```

> **Do NOT** add `HarvestDirectory` — it is silently ignored in WiX SDK 6.0.2.
> Files are included via `<Files>` glob in `AppFiles.wxs` (see Step 3).

---

## Step 2 — Create `NuGet.config`

The project needs both the public feed (for WiX extensions) and the FK private feed:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    <add key="Dedge" value="https://pkgs.dev.azure.com/Dedge/Dedge/_packaging/Dedge/nuget/v3/index.json" />
  </packageSources>
</configuration>
```

---

## Step 3 — Create `AppFiles.wxs` (file glob)

```xml
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Fragment>
    <ComponentGroup Id="AppFiles" Directory="INSTALLFOLDER">
      <Files Include="..\MyApp\bin\Release\net10.0-windows\win-x64\publish\**\*" />
    </ComponentGroup>
  </Fragment>
</Wix>
```

> **Publish with `--self-contained true`** so all DLLs are included.
> Framework-dependent publish produces only 4–5 files and the app won't run.

```powershell
dotnet publish "src\MyApp\MyApp.csproj" -c Release -r win-x64 --self-contained true
```

---

## Step 4 — Create `Package.wxs`

Full working template. Replace all `GENERATE-*` values with your own.

```xml
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"
     xmlns:ui="http://wixtoolset.org/schemas/v4/wxs/ui"
     xmlns:util="http://wixtoolset.org/schemas/v4/wxs/util">

  <Package Name="My App"
           Language="1033"
           Version="1.0.0"
           Manufacturer="Dedge"
           UpgradeCode="GENERATE-A-NEW-GUID-HERE"
           Compressed="yes">

    <MajorUpgrade DowngradeErrorMessage="A newer version of My App is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <!-- ── Kill running instance before file copy ── -->
    <util:CloseApplication Id="CloseExisting"
                           Target="MyApp.exe"
                           CloseMessage="yes"
                           RebootPrompt="no"
                           TerminateProcess="0"
                           Timeout="5" />

    <!-- ── PRODUCT METADATA (visible in Add/Remove Programs) ── -->
    <Property Id="ARPCOMMENTS"      Value="Description. For internal use within Dedge AS." />
    <Property Id="ARPCONTACT"       Value="IT-support, Dedge AS" />
    <Property Id="ARPHELPLINK"      Value="https://www.Dedge.no" />
    <Property Id="ARPURLINFOABOUT"  Value="https://www.Dedge.no" />
    <Property Id="ARPHELPTELEPHONE" Value="+47 22 31 50 00" />

    <!-- ── CUSTOM PROPERTIES ── -->
    <Property Id="MY_PROPERTY" Value="default-value" />
    <SetProperty Id="WriteConfig" Value="[MY_PROPERTY]" Before="WriteConfig" Sequence="execute" />

    <!-- ── DIRECTORIES ──
         ProgramFiles64Folder is needed so WiX can auto-generate component GUIDs.
         SetProperty overrides INSTALLFOLDER to the AppLocker-approved path at runtime.
         [%OptPath] = C:\opt (environment variable). -->
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="MyApp" />
    </StandardDirectory>

    <SetProperty Id="INSTALLFOLDER"
                 Value="[%OptPath]\DedgeWinApps\MyApp\"
                 Before="AppSearch"
                 Sequence="both" />

    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="AppMenuFolder" Name="Dedge" />
    </StandardDirectory>

    <StandardDirectory Id="DesktopFolder" />

    <!-- ── COMPONENTS ── -->

    <!-- Start Menu shortcut -->
    <ComponentGroup Id="Shortcuts" Directory="AppMenuFolder">
      <Component Id="StartMenuShortcut" Guid="GENERATE-GUID-1">
        <Shortcut Id="AppStartMenuShortcut"
                  Name="My App"
                  Description="Short description"
                  Target="[INSTALLFOLDER]MyApp.exe"
                  WorkingDirectory="INSTALLFOLDER"
                  Icon="AppIcon" />
        <RemoveFolder Id="RemoveAppMenuFolder" Directory="AppMenuFolder" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\Dedge\MyApp"
                       Name="StartMenuInstalled" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </ComponentGroup>

    <!-- Desktop shortcut -->
    <ComponentGroup Id="DesktopShortcuts" Directory="DesktopFolder">
      <Component Id="DesktopShortcut" Guid="GENERATE-GUID-2">
        <Shortcut Id="AppDesktopShortcut"
                  Name="My App"
                  Description="Short description"
                  Target="[INSTALLFOLDER]MyApp.exe"
                  WorkingDirectory="INSTALLFOLDER"
                  Icon="AppIcon" />
        <RegistryValue Root="HKCU" Key="Software\Dedge\MyApp"
                       Name="DesktopInstalled" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </ComponentGroup>

    <!-- Auto-start on Windows login -->
    <ComponentGroup Id="AutoStart" Directory="INSTALLFOLDER">
      <Component Id="AutoStartEntry" Guid="GENERATE-GUID-3">
        <RegistryValue Root="HKCU"
                       Key="SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
                       Name="My App" Type="string"
                       Value="[INSTALLFOLDER]MyApp.exe" KeyPath="yes" />
      </Component>
      <!-- Config-writer script -->
      <Component Id="WriteConfigScript" Guid="GENERATE-GUID-4">
        <File Id="WriteConfigPs1" Source="WriteConfig.ps1" Name="WriteConfig.ps1" KeyPath="yes" />
      </Component>
    </ComponentGroup>

    <!-- ── FEATURE ── -->
    <Feature Id="ProductFeature" Title="My App" Level="1">
      <ComponentGroupRef Id="AppFiles" />
      <ComponentGroupRef Id="Shortcuts" />
      <ComponentGroupRef Id="DesktopShortcuts" />
      <ComponentGroupRef Id="AutoStart" />
    </Feature>

    <!-- ── CUSTOM ACTIONS ── -->

    <!-- Write config file (deferred, runs as installing user) -->
    <CustomAction Id="WriteConfig"
                  Directory="INSTALLFOLDER" Execute="deferred" Impersonate="yes" Return="ignore"
                  ExeCommand="pwsh.exe -NonInteractive -ExecutionPolicy Bypass -File &quot;[INSTALLFOLDER]WriteConfig.ps1&quot; -MyParam &quot;[MY_PROPERTY]&quot;" />

    <!-- Launch app after install (fire and forget, user context) -->
    <CustomAction Id="LaunchApp"
                  Directory="INSTALLFOLDER" Execute="immediate" Return="asyncNoWait"
                  ExeCommand="&quot;[INSTALLFOLDER]MyApp.exe&quot;" />

    <InstallExecuteSequence>
      <Custom Action="WriteConfig" After="InstallFiles" Condition="NOT Installed" />
    </InstallExecuteSequence>

    <InstallUISequence>
      <Custom Action="LaunchApp" After="ExecuteAction" Condition="NOT Installed AND NOT REMOVE" />
    </InstallUISequence>

    <!-- ── UI ── -->
    <Icon Id="AppIcon" SourceFile="..\MyApp\app.ico" />
    <Property Id="ARPPRODUCTICON" Value="AppIcon" />

    <WixVariable Id="WixUIBannerBmp"   Value="WixBanner.bmp" />
    <WixVariable Id="WixUIDialogBmp"   Value="WixDialog.bmp" />
    <WixVariable Id="WixUILicenseRtf"  Value="License.rtf" />

    <!-- WixUI_InstallDir provides: Welcome → Licence → InstallDir → Ready → Progress → Finish.
         To insert a custom dialog, add a <UI> block with Order="2" publishes. -->
    <ui:WixUI Id="WixUI_InstallDir" InstallDirectory="INSTALLFOLDER" />

    <!-- Insert custom dialog between LicenceAgreement and InstallDir -->
    <UI>
      <DialogRef Id="MyConfigDlg" />
      <Publish Dialog="LicenseAgreementDlg" Control="Next" Event="NewDialog" Value="MyConfigDlg"
               Order="2" Condition="LicenseAccepted = &quot;1&quot;" />
      <Publish Dialog="MyConfigDlg" Control="Back" Event="NewDialog" Value="LicenseAgreementDlg" Condition="1" />
      <Publish Dialog="MyConfigDlg" Control="Next" Event="NewDialog" Value="InstallDirDlg" Condition="1" />
    </UI>

  </Package>
</Wix>
```

> Generate fresh GUIDs with `[System.Guid]::NewGuid()` in PowerShell.
> **Never reuse GUIDs** from another installer — MSI uses them for component tracking.

---

## Step 5 — Create a Custom Dialog (optional)

Custom dialogs capture user input during installation (e.g. server name, licence key).

```xml
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Fragment>
    <UI>
      <Dialog Id="MyConfigDlg" Width="370" Height="270" Title="Configuration">
        <Control Id="BannerBitmap" Type="Bitmap" X="0" Y="0" Width="370" Height="44"
                 TabSkip="no" Text="WixUI_Bmp_Banner" />
        <Control Id="BannerLine"   Type="Line"   X="0" Y="44"  Width="370" Height="0" />
        <Control Id="BottomLine"   Type="Line"   X="0" Y="234" Width="370" Height="0" />

        <Control Id="Title" Type="Text" X="15" Y="15" Width="300" Height="15"
                 Transparent="yes" NoPrefix="yes">
          <Text Value="{\WixUI_Font_Title}My Setting" />
        </Control>

        <Control Id="Description" Type="Text" X="25" Y="35" Width="320" Height="30"
                 Transparent="yes" NoPrefix="yes">
          <Text Value="Enter the value for MY_PROPERTY." />
        </Control>

        <Control Id="EditLabel" Type="Text" X="25" Y="95" Width="320" Height="15" NoPrefix="yes">
          <Text Value="&amp;Value:" />
        </Control>

        <!-- Text input bound to installer property -->
        <Control Id="EditField" Type="Edit" X="25" Y="112" Width="250" Height="18"
                 Property="MY_PROPERTY" Indirect="no">
          <Text Value="{80}" />
        </Control>

        <Control Id="Back"   Type="PushButton" X="180" Y="243" Width="56" Height="17" Text="&amp;Back" />
        <Control Id="Next"   Type="PushButton" X="236" Y="243" Width="56" Height="17"
                 Default="yes" Text="&amp;Next" />
        <Control Id="Cancel" Type="PushButton" X="304" Y="243" Width="56" Height="17"
                 Cancel="yes" Text="Cancel">
          <Publish Event="SpawnDialog" Value="CancelDlg" Condition="1" />
        </Control>
      </Dialog>
    </UI>
  </Fragment>
</Wix>
```

---

## Step 6 — Create `WriteConfig.ps1` (custom action script)

Keep the inline MSI command short (< 255 chars) — put all logic in this script.

```powershell
param(
    [Parameter(Mandatory)]
    [string]$MyParam
)
$dir  = Join-Path $env:APPDATA "MyApp"
$file = Join-Path $dir "config.json"
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$json = "{`"MySetting`":`"$MyParam`"}"
Set-Content -Path $file -Value $json -Encoding UTF8
```

---

## Step 7 — Create `License.rtf`

Norwegian Dedge licence agreement. RTF must use ASCII encoding with Norwegian
chars as RTF unicode escapes.

Key unicode escapes for Norwegian:

| Char | RTF escape |
|---|---|
| ø | `\u248\'f8` |
| æ | `\u230\'e6` |
| å | `\u229\'e5` |
| Ø | `\u216\'d8` |
| Æ | `\u198\'c6` |
| Å | `\u197\'c5` |
| é | `\u233\'e9` |

Standard clauses: Licence rights, Restrictions, Ownership, Confidentiality, Termination,
Disclaimer, Governing law (Oslo tingrett).

Footer: Dedge AS, Pb. 1504 Vika 0117 Oslo, Org.nr. 938 752 648.

---

## Step 8 — Generate Branded Bitmaps

See `docs/WiX-Bitmap-Layout-Reference.md` for the full pixel-precise zone map.

### Quick summary of safe zones

**Banner (493×58 px)** — used on all inner dialogs:

| Zone | Pixels | Safe? |
|---|---|---|
| WiX title + description | X: 20–413, Y: 6–50 | NO — WiX text renders here |
| Icon area (right) | X: 413–493, Y: 0–58 | YES — place small icon here |

**Dialog (493×312 px)** — used on Welcome + Finish pages:

| Zone | Pixels | Safe? |
|---|---|---|
| Left panel | X: 0–163, Y: 0–312 | YES — WiX never renders here |
| Gap / margin | X: 164–179 | Separator, avoid content |
| WiX title | X: 180–473, Y: 27–107 | NO — WiX renders title text |
| WiX description | X: 180–473, Y: 107–187 | NO — WiX renders description |
| Dead zone (below text) | X: 180–473, Y: 187–312 | YES — safe for copyright etc. |

### Generation script

```powershell
Add-Type -AssemblyName System.Drawing

# CRITICAL: Never use DrawIcon() — it renders at native size (often 256x256).
# Always convert .ico to Bitmap and use DrawImage() with explicit w,h.
function Get-IconBitmap([string]$path, [int]$size) {
    $ico = New-Object System.Drawing.Icon($path, $size, $size)
    $bmp = $ico.ToBitmap(); $ico.Dispose()
    $result = New-Object System.Drawing.Bitmap($size, $size)
    $gr = [System.Drawing.Graphics]::FromImage($result)
    $gr.InterpolationMode = 'HighQualityBicubic'
    $gr.DrawImage($bmp, 0, 0, $size, $size)
    $gr.Dispose(); $bmp.Dispose()
    return $result
}

$outDir  = "src\MyApp.Installer"
$icoPath = "src\MyApp\app.ico"

# ── Banner: 493x58, white, small icon right-aligned ──────────────────
$iconSmall = Get-IconBitmap $icoPath 40
$banner = New-Object System.Drawing.Bitmap(493, 58)
$g = [System.Drawing.Graphics]::FromImage($banner)
$g.Clear([System.Drawing.Color]::White)
$g.DrawImage($iconSmall, 445, 9, 40, 40)
$g.Dispose()
$banner.Save("$outDir\WixBanner.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)
$banner.Dispose(); $iconSmall.Dispose()

# ── Dialog: 493x312, branded left panel, white right ─────────────────
$iconMed = Get-IconBitmap $icoPath 48
$dialog = New-Object System.Drawing.Bitmap(493, 312)
$g = [System.Drawing.Graphics]::FromImage($dialog)
$g.SmoothingMode = 'HighQuality'
$g.InterpolationMode = 'HighQualityBicubic'
$g.TextRenderingHint = 'ClearTypeGridFit'
$g.Clear([System.Drawing.Color]::White)

# Left panel: FK green (0-163px)
$fkGreen = [System.Drawing.Color]::FromArgb(0, 98, 65)
$g.FillRectangle((New-Object System.Drawing.SolidBrush($fkGreen)), 0, 0, 163, 312)

# Icon: centered in left panel (48x48, explicitly sized)
$g.DrawImage($iconMed, [int]((163 - 48) / 2), 30, 48, 48)

# Product name (white on dark)
$fontProd = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = 'Center'
$rect = New-Object System.Drawing.RectangleF(4, 92, 155, 40)
$g.DrawString("My App`nProduct Name", $fontProd, $white, $rect, $sf)

# Tagline + manufacturer
$fontTag = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Regular)
$lightGreen = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 220, 180))
$rect2 = New-Object System.Drawing.RectangleF(4, 148, 155, 30)
$g.DrawString("Description line`nDedge AS", $fontTag, $lightGreen, $rect2, $sf)

# Version at bottom of left panel
$fontVer = New-Object System.Drawing.Font("Segoe UI", 6.5, [System.Drawing.FontStyle]::Italic)
$dimGreen = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 180, 140))
$rect3 = New-Object System.Drawing.RectangleF(4, 288, 155, 16)
$g.DrawString("v1.0 - $(Get-Date -Format yyyy)", $fontVer, $dimGreen, $rect3, $sf)

# Right panel: DO NOT paint anything. WiX renders Welcome title/description here.

$g.Dispose()
$dialog.Save("$outDir\WixDialog.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)
$dialog.Dispose(); $iconMed.Dispose()
```

---

## Step 9 — Build the Installer

```powershell
# 1. Publish the app (self-contained, all DLLs included)
dotnet publish "src\MyApp\MyApp.csproj" -c Release -r win-x64 --self-contained true

# 2. Build the MSI
dotnet build "src\MyApp.Installer\MyApp.Installer.wixproj" -c Release

# Output: src\MyApp.Installer\bin\x64\Release\MyApp.Setup.msi
```

---

## Step 10 — Install / Uninstall

### Interactive install (shows wizard UI — must run elevated)

```powershell
$msi = "src\MyApp.Installer\bin\x64\Release\MyApp.Setup.msi"
Start-Process msiexec -ArgumentList "/i `"$msi`"" -Verb RunAs
```

### Silent install (no UI, elevated, verbose log, custom properties)

```powershell
Start-Process msiexec `
    -ArgumentList "/i `"MyApp.Setup.msi`" /quiet /norestart /l*v `"C:\temp\install.log`" MY_PROPERTY=value" `
    -Verb RunAs -Wait
```

### Silent uninstall

```powershell
$prod = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -like "*My App*" } | Select-Object -First 1
Start-Process msiexec -ArgumentList "/x $($prod.PSChildName) /quiet /norestart" -Verb RunAs -Wait
```

---

## Known WiX v6 Gotchas

| Issue | Wrong | Correct |
|---|---|---|
| Including app files | `HarvestDirectory` in `.wixproj` (silently ignored) | `<Files Include="...\**\*" />` in `.wxs` |
| Custom dialog in built-in UI | Child elements of `<ui:WixUI>` (schema error) | Separate `<UI>` block with `Order="2"` |
| Override built-in dialog | `Dialog override="yes"` (not supported) | Cannot override; use bitmap + `Order` tricks |
| Terminate process | `TerminateProcess="yes"` (not an integer) | `TerminateProcess="0"` |
| Custom directory root | `Directory Id="TARGETDIR"` (conflicts) | `StandardDirectory Id="TARGETDIR"` |
| Install path | `C:\Program Files\...` (AppLocker blocked) | `[%OptPath]\DedgeWinApps\AppName\` |
| Self-contained publish | Framework-dependent (4 files) | `--self-contained true` (200+ files) |
| PowerShell | `powershell.exe` (5.1) | `pwsh.exe` (7+) |
| GUID reuse | Copying GUIDs from another installer | `[System.Guid]::NewGuid()` for each |
| Icon rendering | `DrawIcon()` — native size (256px) | `ToBitmap()` + `DrawImage()` with explicit w×h |
| Custom action too long | Inline PS command > 255 chars (ICE03) | Extract to `.ps1` file, call with `-File` |
| MSI service locked | Build fails with error 1631 | Kill `msiexec` process, then rebuild |

---

## File Reference — ServerMonitorDashboard.Tray

| File | Purpose |
|---|---|
| `ServerMonitorDashboard.Tray.Installer.wixproj` | SDK project, extensions, platform |
| `NuGet.config` | nuget.org + Dedge feeds |
| `Package.wxs` | Package, directories, components, features, custom actions, UI |
| `TrayFiles.wxs` | `<Files>` glob for all published binaries |
| `ServerConfigDlg.wxs` | Custom dialog asking for dashboard server hostname |
| `WriteTrayConfig.ps1` | Custom action: writes `user-prefs.json` to `%APPDATA%` |
| `License.rtf` | Norwegian Dedge licence agreement |
| `WixBanner.bmp` | 493×58 banner, FK icon right-aligned |
| `WixDialog.bmp` | 493×312 dialog, left panel branded, right panel white |

---

## Related Documentation

| Document | Location |
|---|---|
| Bitmap pixel-precise zone maps | `docs/WiX-Bitmap-Layout-Reference.md` |
| Cursor AI rules | `.cursor/rules/wix-installer.mdc` |
| ServerMonitorDashboard.Tray installer source | `src/ServerMonitorDashboard.Tray.Installer/` |
