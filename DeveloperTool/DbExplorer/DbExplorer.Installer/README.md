# DbExplorer WiX v6 Installer

## Quick Build

```powershell
# 1. Publish the app (self-contained, x64)
dotnet publish ..\DbExplorer.csproj -p:PublishProfile=WinApp

# 2. Build the installer (copies MSI to network share automatically)
dotnet build DbExplorer.Installer.wixproj -c Release
```

The MSI is output to `bin\x64\Release\DbExplorer.Setup.msi` and automatically copied to
`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\DbExplorer` on Release builds.

---

## How the Install Wizard Works

The installer uses `WixUI_InstallDir`, a built-in WiX dialog set that provides a standard
Windows Installer wizard experience. The wizard consists of a fixed sequence of pages that
the user navigates with Back/Next/Cancel buttons.

### Default Page Flow

```
WelcomeDlg ──> LicenseAgreementDlg ──> InstallDirDlg ──> VerifyReadyDlg ──> [Install] ──> ExitDlg
```

| # | Dialog | What the User Sees | Configured By |
|---|---|---|---|
| 1 | **WelcomeDlg** | Product name, welcome text, dialog bitmap on the left | `WixUIDialogBmp`, `Package.Name` |
| 2 | **LicenseAgreementDlg** | License text with "I accept" checkbox; Next is disabled until accepted | `WixUILicenseRtf` |
| 3 | **InstallDirDlg** | Install folder path with Browse/Change button | `InstallDirectory` attribute on `<ui:WixUI>` |
| 4 | **VerifyReadyDlg** | Summary "Ready to install" confirmation | Automatic |
| 5 | *Installation progress* | Progress bar while files are copied | Automatic |
| 6 | **ExitDlg** | "Installation complete" with optional launch checkbox | Automatic |

### What You Can Configure

#### 1. Product Name and Version

These appear in the wizard title bar and welcome text.

```xml
<Package Name="DbExplorer"
         Version="1.0.0"
         Manufacturer="Dedge AS" />
```

- `Name` — shown in the title bar of every dialog page
- `Version` — shown in Add/Remove Programs
- `Manufacturer` — shown in Add/Remove Programs

#### 2. License Agreement

The license page displays an RTF file. The user must check "I accept the terms" before
the Next button becomes enabled.

```xml
<WixVariable Id="WixUILicenseRtf" Value="License.rtf" />
```

The RTF file must use ASCII encoding. Norwegian characters must be encoded as RTF unicode
escapes:

| Character | RTF Escape |
|---|---|
| ø | `\u248\'f8` |
| å | `\u229\'e5` |
| æ | `\u230\'e6` |
| Ø | `\u216\'d8` |
| Å | `\u197\'c5` |
| Æ | `\u198\'c6` |

#### 3. Install Directory

The default install path is defined by the directory tree in the `.wxs` file:

```xml
<StandardDirectory Id="ProgramFiles64Folder">
  <Directory Id="DedgeFolder" Name="Dedge">
    <Directory Id="INSTALLFOLDER" Name="DbExplorer" />
  </Directory>
</StandardDirectory>
```

This produces `C:\Program Files\Dedge\DbExplorer` as the default. The user can change it
via the Browse button on the InstallDirDlg page.

To force a specific path (ignoring what the user picks), use `SetProperty`:

```xml
<SetProperty Id="INSTALLFOLDER"
             Value="C:\MyApps\DbExplorer\"
             Before="AppSearch"
             Sequence="both" />
```

To use an environment variable:

```xml
<SetProperty Id="INSTALLFOLDER"
             Value="[%MY_ENV_VAR]\Apps\DbExplorer\"
             Before="AppSearch"
             Sequence="both" />
```

#### 4. Dialog Bitmaps (Branding)

Two bitmaps control the visual appearance of the wizard:

| Variable | Size | Where It Appears |
|---|---|---|
| `WixUIBannerBmp` | 493 x 58 px | Top banner on all pages except Welcome and Exit |
| `WixUIDialogBmp` | 493 x 312 px | Left panel on the Welcome and Exit pages |

Add them to `Package.wxs`:

```xml
<WixVariable Id="WixUIBannerBmp" Value="Banner.bmp" />
<WixVariable Id="WixUIDialogBmp" Value="Dialog.bmp" />
```

**Banner bitmap (493x58):**
- White background
- Small app icon (40x40) right-aligned at position (445, 9)
- Leave the left area empty — WiX renders the page title text there

**Dialog bitmap (493x312):**
- Left panel (0–163 px): Dark branding area with app icon, product name, version
- Right panel (164–493 px): Plain white — WiX renders welcome/exit text here
- Built-in text renders in the system default font color (black), so the right panel must
  be white or very light

If these variables are not set, WiX uses its default blue/grey bitmaps.

#### 5. Application Icon

The icon shown in Add/Remove Programs:

```xml
<Icon Id="AppIcon" SourceFile="..\Resources\dEdge.ico" />
<Property Id="ARPPRODUCTICON" Value="AppIcon" />
```

The same icon is also used for Start Menu and Desktop shortcuts via the `Icon` attribute
on `<Shortcut>` elements.

#### 6. Add/Remove Programs Metadata

These properties control what is displayed in Windows Settings > Apps:

```xml
<Property Id="ARPCOMMENTS"      Value="Description of the app" />
<Property Id="ARPCONTACT"       Value="Dedge AS" />
<Property Id="ARPHELPLINK"      Value="https://www.dedge.no" />
<Property Id="ARPURLINFOABOUT"  Value="https://www.dedge.no" />
<Property Id="ARPHELPTELEPHONE" Value="+47 ..." />
```

#### 7. Launch After Install

The installer launches the app automatically after a fresh install completes:

```xml
<CustomAction Id="LaunchApp"
              Directory="INSTALLFOLDER"
              Execute="immediate"
              Return="asyncNoWait"
              ExeCommand="&quot;[INSTALLFOLDER]DbExplorer.exe&quot;" />

<InstallUISequence>
  <Custom Action="LaunchApp" After="ExecuteAction"
          Condition="NOT Installed AND NOT REMOVE" />
</InstallUISequence>
```

- `asyncNoWait` — the installer does not wait for the app to close
- The condition ensures it only runs on first install, not on upgrade or uninstall

---

### Adding a Custom Dialog Page

WiX v6 does not allow child elements inside `<ui:WixUI>` or overriding built-in dialogs.
To insert a custom page, add a **separate `<UI>` block** that rewires the navigation.

Example: insert a custom dialog between Welcome and License Agreement:

```xml
<!-- Keep the standard dialog set -->
<ui:WixUI Id="WixUI_InstallDir" InstallDirectory="INSTALLFOLDER" />

<!-- Rewire navigation to insert MyCustomDlg -->
<UI>
  <DialogRef Id="MyCustomDlg" />

  <!-- Welcome -> MyCustomDlg (instead of LicenseAgreementDlg) -->
  <Publish Dialog="WelcomeDlg" Control="Next"
           Event="NewDialog" Value="MyCustomDlg"
           Order="2" Condition="1" />

  <!-- MyCustomDlg -> back to Welcome -->
  <Publish Dialog="MyCustomDlg" Control="Back"
           Event="NewDialog" Value="WelcomeDlg"
           Condition="1" />

  <!-- MyCustomDlg -> forward to LicenseAgreementDlg -->
  <Publish Dialog="MyCustomDlg" Control="Next"
           Event="NewDialog" Value="LicenseAgreementDlg"
           Condition="1" />
</UI>
```

The `Order="2"` attribute ensures this publish action takes priority over the default
navigation defined in WixUI_InstallDir.

To insert after the License Agreement page instead:

```xml
<Publish Dialog="LicenseAgreementDlg" Control="Next"
         Event="NewDialog" Value="MyCustomDlg"
         Order="2"
         Condition="LicenseAccepted = &quot;1&quot;" />
```

---

### Available WixUI Dialog Sets

The `WixUI` extension provides several pre-built dialog sets. Change the `Id` attribute
to switch:

| Id | Pages | Use Case |
|---|---|---|
| `WixUI_InstallDir` | Welcome, License, Install Dir, Verify, Exit | **Current** — user can choose install folder |
| `WixUI_Minimal` | Welcome+License (combined), Verify, Exit | Simplest wizard with no directory choice |
| `WixUI_FeatureTree` | Welcome, License, Feature selection, Verify, Exit | Let user pick which features to install |
| `WixUI_Mondo` | Welcome, License, Setup Type (Typical/Custom/Complete), Feature tree, Dir, Verify, Exit | Full enterprise installer |
| `WixUI_Advanced` | Welcome, License, Install Scope (per-user/machine), Dir, Verify, Exit | Per-user vs per-machine choice |

To switch, change the single line in `Package.wxs`:

```xml
<!-- Example: switch to minimal (no directory choice) -->
<ui:WixUI Id="WixUI_Minimal" />
```

---

### Silent Install / Uninstall

The wizard can be bypassed entirely for automated deployments:

```powershell
# Silent install (elevated, with verbose log)
Start-Process msiexec -ArgumentList "/i `"DbExplorer.Setup.msi`" /quiet /norestart /l*v `"C:\temp\install.log`"" -Verb RunAs -Wait

# Silent uninstall
$app = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
       Where-Object { $_.DisplayName -like "*DbExplorer*" } | Select-Object -First 1
Start-Process msiexec -ArgumentList "/x $($app.PSChildName) /quiet /norestart" -Verb RunAs -Wait
```

### Upgrade Behaviour

The installer uses `<MajorUpgrade>` which automatically uninstalls the previous version
before installing the new one. The `UpgradeCode` GUID must remain the same across all
versions. Never change the `UpgradeCode` — it is what links different versions together.

If a user tries to install an older version over a newer one, they see the message defined
in `DowngradeErrorMessage`.
