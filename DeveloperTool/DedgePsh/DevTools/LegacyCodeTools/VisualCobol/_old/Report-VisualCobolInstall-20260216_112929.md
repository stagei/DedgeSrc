# Visual COBOL 11.0 for VS 2022 – Installation Attempt Report

**Generated:** 2026-02-16 11:29:49  
**Computer:** 30237-FK  
**Report file:** C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\Report-VisualCobolInstall-20260216_112929.md

---

## 1. Information for Rocket Support (from RaiseASupportCaseWithRocket.md)

| Item | Value |
|------|--------|
| **Rocket product** | Visual COBOL 11.0 (vcvs2022_110.exe) |
| **Rocket serial number** | _(Add from Electronic Delivery Receipt or Activation email)_ |
| **Computer make and model** | LENOVO 21FBS2YV00 |
| **OS** | Microsoft Windows 11 Pro 64-bit Build 26100 |
| **Visual Studio** | Installed folders: 18, 2022; Registry:  |
| **Installer** | Size: 819564904 bytes; LastWrite: 2026-02-11T15:44:42.1933020Z; Version: 11.0.250 |

**Product/environment:** Run the [Rocket Software Support Scan utility](https://docs.rocketsoftware.com) and attach its output to the support case.

---

## 2. Installation Attempts Summary

| Attempt | Method | Result |
|---------|--------|--------|
| 1 | Installer /? (help) | ExitCode: (GUI; no console exit code) |
| 2 | /install /passive /norestart /log | ExitCode: 1 |
| 3 | /install /quiet /norestart /log | ExitCode: 1 |
| 4 | /install /quiet ignorechecks=1 /log | _(run script again to test)_ |

**Root cause from logs:** The installer sets `VS2022ValidInstance=0` and fails with:
`Error 0x81f40001: Bundle condition evaluated to false: WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"`. So the setup does not detect a valid Visual Studio 2022 instance (VS 2022 and VS 18 are present under `C:\Program Files\Microsoft Visual Studio`). Ask Rocket which registry/path they use for VS 2022 detection.

---

## 3. Official Installer Command-Line Options (Setup Help)

| Argument | Description |
|----------|-------------|
| `/install` \| `/repair` \| `/uninstall` | Primary action; `/install` is default. |
| `/passive` \| `/quiet` | `/passive` = minimal UI, no prompts; `/quiet` = no UI. |
| `/norestart` | Suppress automatic restart. |
| `/log log.txt` | Custom log path (default: %TEMP%). |
| `InstallFolder=path` | Main product install folder. |
| `InstallFolder2=path` | Eclipse components folder (if applicable). |
| `ignorechecks=1` | Bypass preconditions (e.g. VS2022 detection); use only if advised by support. |

---

## 4. Problem Description (for support case)

- **Subject line suggestion:** `Visual COBOL 11.0 for VS 2022 installer fails: VS2022ValidInstance=0 (no valid VS 2022 detected)`
- **Steps to reproduce:** Run the installer with `/install /passive` or `/install /quiet` and `/log <path>`. It exits with code 1 during detect; log shows `VS2022ValidInstance = 0`.
- **Context:** Installing Visual COBOL 11.0 for Visual Studio 2022; VS 2022 and VS 2026 (18.0) are installed. Request: what registry/path does the installer use for VS 2022 validation, and is `ignorechecks=1` supported for this scenario?

---

## 5. Installer Help Output (Attempt 1)

```

```

---

## 6. Passive Install Log (last 80 lines)

```
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse90<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Test Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx6490<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx6490<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Visual COBOL Build Tools for Windows"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Enterprise Developer Build Tools for Windows"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Visual COBOL for Eclipse"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus COBOL Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Test Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64100<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64100<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Visual COBOL Build Tools for Windows"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Enterprise Developer Build Tools for Windows"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regComPatAddPack230<>"Micro Focus Compatibility AddPack For Visual COBOL"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Visual COBOL for Eclipse" or WixBundleName="Rocket Visual COBOL for Visual Studio 2022"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket COBOL Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Enterprise Developer for Eclipse" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Test Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Visual COBOL for Visual Studio 2022" or WixBundleName="Rocket Visual COBOL for Eclipse"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Eclipse" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64Latest<>"Rocket COBOL Server 64-bit"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64Latest<>"Rocket Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server Stored Procedures"' evaluates to true.
[444C:6998][2026-02-16T11:29:44]i052: Condition 'WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"' evaluates to false.
[444C:6998][2026-02-16T11:29:44]e000: Error 0x81f40001: Bundle condition evaluated to false: WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"
[444C:6998][2026-02-16T11:29:44]i199: Detect complete, result: 0x0
[444C:6998][2026-02-16T11:29:44]i500: Shutting down, exit code: 0x1
[444C:6998][2026-02-16T11:29:44]i410: Variable: 32BitOSEclipseMsgState = disable
[444C:6998][2026-02-16T11:29:44]i410: Variable: accepteula = no
[444C:6998][2026-02-16T11:29:44]i410: Variable: BrowseButton2State = disable
[444C:6998][2026-02-16T11:29:44]i410: Variable: DockerService = SYSTEM\CurrentControlSet\Services\cexecsvc
[444C:6998][2026-02-16T11:29:44]i410: Variable: EclipseLabelState = disable
[444C:6998][2026-02-16T11:29:44]i410: Variable: FolderEditbox2State = disable
[444C:6998][2026-02-16T11:29:44]i410: Variable: HFDetected = 1
[444C:6998][2026-02-16T11:29:44]i410: Variable: ignorechecks = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: InstallFolder = C:\Program Files (x86)\Rocket Software\Visual COBOL
[444C:6998][2026-02-16T11:29:44]i410: Variable: isdocker = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: issandbox = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: NetfxFullVersion = 533320
[444C:6998][2026-02-16T11:29:44]i410: Variable: novsix = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: Privileged = 1
[444C:6998][2026-02-16T11:29:44]i410: Variable: ProductRevision = 11.0.00250
[444C:6998][2026-02-16T11:29:44]i410: Variable: ProgramFilesFolder = C:\Program Files (x86)\
[444C:6998][2026-02-16T11:29:44]i410: Variable: regMS = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: SafeNetCheck = yes
[444C:6998][2026-02-16T11:29:44]i410: Variable: skipautopass = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: skipces = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: skipdotnet = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: UpgradeRegKey = SOFTWARE\Micro Focus\Visual COBOL\11.0
[444C:6998][2026-02-16T11:29:44]i410: Variable: UsingSafeNetMsgState = disable
[444C:6998][2026-02-16T11:29:44]i410: Variable: vcredist20152022x64 = v14.50.35719.00
[444C:6998][2026-02-16T11:29:44]i410: Variable: vcredist20152022x86 = v14.50.35719.00
[444C:6998][2026-02-16T11:29:44]i410: Variable: VS2022ValidCheck = yes
[444C:6998][2026-02-16T11:29:44]i410: Variable: VS2022ValidInstance = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: Windows10Build = 26100
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleAction = 5
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleElevated = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleInstalled = 0
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleLog = C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_install_20260216_112929.log
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleManufacturer = Rocket Software
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleName = Rocket Visual COBOL for Visual Studio 2022
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleOriginalSource = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleOriginalSourceFolder = C:\Users\FKGEISTA\Downloads\
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleProviderKey = {0b835cba-a870-4460-b1d0-2902564c6b9b}
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleSourceProcessFolder = C:\Users\FKGEISTA\Downloads\
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleSourceProcessPath = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleTag = 
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleUILevel = 3
[444C:6998][2026-02-16T11:29:44]i410: Variable: WixBundleVersion = 11.0.250.0
[444C:6998][2026-02-16T11:29:44]i007: Exit code: 0x1, restarting: No

```

---

## 7. Silent Install Log (last 80 lines, if run)

```
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse90<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Test Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx6490<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx6490<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Visual COBOL Build Tools for Windows"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Enterprise Developer Build Tools for Windows"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Visual COBOL for Eclipse"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus COBOL Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Test Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64100<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64100<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Visual COBOL Build Tools for Windows"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Enterprise Developer Build Tools for Windows"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regComPatAddPack230<>"Micro Focus Compatibility AddPack For Visual COBOL"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Visual COBOL for Eclipse" or WixBundleName="Rocket Visual COBOL for Visual Studio 2022"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket COBOL Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Enterprise Developer for Eclipse" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Test Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Visual COBOL for Visual Studio 2022" or WixBundleName="Rocket Visual COBOL for Eclipse"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Eclipse" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64Latest<>"Rocket COBOL Server 64-bit"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64Latest<>"Rocket Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server Stored Procedures"' evaluates to true.
[ADF8:AE34][2026-02-16T11:29:49]i052: Condition 'WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"' evaluates to false.
[ADF8:AE34][2026-02-16T11:29:49]e000: Error 0x81f40001: Bundle condition evaluated to false: WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"
[ADF8:AE34][2026-02-16T11:29:49]i199: Detect complete, result: 0x0
[ADF8:AE34][2026-02-16T11:29:49]i500: Shutting down, exit code: 0x1
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: 32BitOSEclipseMsgState = disable
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: accepteula = no
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: BrowseButton2State = disable
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: DockerService = SYSTEM\CurrentControlSet\Services\cexecsvc
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: EclipseLabelState = disable
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: FolderEditbox2State = disable
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: HFDetected = 1
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: ignorechecks = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: InstallFolder = C:\Program Files (x86)\Rocket Software\Visual COBOL
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: isdocker = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: issandbox = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: NetfxFullVersion = 533320
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: novsix = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: Privileged = 1
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: ProductRevision = 11.0.00250
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: ProgramFilesFolder = C:\Program Files (x86)\
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: regMS = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: SafeNetCheck = yes
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: skipautopass = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: skipces = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: skipdotnet = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: UpgradeRegKey = SOFTWARE\Micro Focus\Visual COBOL\11.0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: UsingSafeNetMsgState = disable
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: vcredist20152022x64 = v14.50.35719.00
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: vcredist20152022x86 = v14.50.35719.00
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: VS2022ValidCheck = yes
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: VS2022ValidInstance = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: Windows10Build = 26100
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleAction = 5
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleElevated = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleInstalled = 0
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleLog = C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_silent_20260216_112945.log
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleManufacturer = Rocket Software
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleName = Rocket Visual COBOL for Visual Studio 2022
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleOriginalSource = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleOriginalSourceFolder = C:\Users\FKGEISTA\Downloads\
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleProviderKey = {0b835cba-a870-4460-b1d0-2902564c6b9b}
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleSourceProcessFolder = C:\Users\FKGEISTA\Downloads\
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleSourceProcessPath = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleTag = 
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleUILevel = 2
[ADF8:AE34][2026-02-16T11:29:49]i410: Variable: WixBundleVersion = 11.0.250.0
[ADF8:AE34][2026-02-16T11:29:49]i007: Exit code: 0x1, restarting: No

```

---

## 8. Next Steps

- Attach this report and the full install log(s) from $ReportFolder to the Rocket support case.
- Add your **Rocket Software product serial number** in section 1.
- Run the **Rocket Software Support Scan utility** and attach its output.
- Use section 3 to copy/paste or adapt the problem description when opening the case.

