# Visual COBOL 11.0 for VS 2022 – Installation Attempt Report

**Generated:** 2026-02-16 11:53:33  
**Computer:** 30237-FK  
**Report file:** C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\Report-VisualCobolInstall-20260216_113143.md

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
| 1 | Installer /? (help) | ExitCode:  |
| 2 | /install /passive /norestart /log | ExitCode: 1 |
| 3 | /install /quiet /norestart /log | ExitCode: 1 |
| 4 | /install /quiet ignorechecks=1 /log | ExitCode: 1 |

**Root cause from logs:** Installer reports VS2022ValidInstance=0 and fails with bundle condition: WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1". So the setup does not detect a valid Visual Studio 2022 instance on this machine (VS 2022 and VS 18/2026 are present under C:\Program Files\Microsoft Visual Studio).

---

## 3. Official Installer Command-Line Options (Setup Help)

| Argument | Description |
|----------|-------------|
| /install \| /repair \| /uninstall | Primary action; /install is default. |
| /passive \| /quiet | /passive = minimal UI, no prompts; /quiet = no UI. |
| /norestart | Suppress automatic restart. |
| /log log.txt | Custom log path (default: %TEMP%). |
| InstallFolder=path | Main product install folder. |
| InstallFolder2=path | Eclipse components folder (if applicable). |
| ignorechecks=1 | Bypass preconditions (e.g. VS2022 detection); use only if advised by support. |

---

## 4. Problem Description (for support case)

- **Subject line suggestion:** Visual COBOL 11.0 for VS 2022 installer fails: VS2022ValidInstance=0 (no valid VS 2022 detected)
- **Steps to reproduce:** Run $InstallerPath with /install /passive or /install /quiet and /log <path>. Installer exits with code 1 during detect phase.
- **Context:** Installing Visual COBOL 11.0 extension for Visual Studio 2022; VS 2022 and VS 2026 (18.0) are installed. Log shows VS2022ValidInstance = 0 and condition VS2022ValidInstance="1" false.

---

## 5. Installer Help Output (Attempt 1)

```

```

---

## 6. Passive Install Log (last 80 lines)

```
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse90<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Test Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx6490<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx6490<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Visual COBOL Build Tools for Windows"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Enterprise Developer Build Tools for Windows"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Visual COBOL for Eclipse"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus COBOL Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Test Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64100<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64100<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Visual COBOL Build Tools for Windows"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Enterprise Developer Build Tools for Windows"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regComPatAddPack230<>"Micro Focus Compatibility AddPack For Visual COBOL"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Visual COBOL for Eclipse" or WixBundleName="Rocket Visual COBOL for Visual Studio 2022"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket COBOL Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Enterprise Developer for Eclipse" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Test Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Visual COBOL for Visual Studio 2022" or WixBundleName="Rocket Visual COBOL for Eclipse"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Eclipse" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64Latest<>"Rocket COBOL Server 64-bit"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64Latest<>"Rocket Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server Stored Procedures"' evaluates to true.
[8B34:5FC8][2026-02-16T11:31:58]i052: Condition 'WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"' evaluates to false.
[8B34:5FC8][2026-02-16T11:31:58]e000: Error 0x81f40001: Bundle condition evaluated to false: WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"
[8B34:5FC8][2026-02-16T11:31:58]i199: Detect complete, result: 0x0
[8B34:5FC8][2026-02-16T11:31:58]i500: Shutting down, exit code: 0x1
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: 32BitOSEclipseMsgState = disable
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: accepteula = no
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: BrowseButton2State = disable
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: DockerService = SYSTEM\CurrentControlSet\Services\cexecsvc
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: EclipseLabelState = disable
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: FolderEditbox2State = disable
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: HFDetected = 1
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: ignorechecks = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: InstallFolder = C:\Program Files (x86)\Rocket Software\Visual COBOL
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: isdocker = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: issandbox = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: NetfxFullVersion = 533320
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: novsix = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: Privileged = 1
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: ProductRevision = 11.0.00250
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: ProgramFilesFolder = C:\Program Files (x86)\
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: regMS = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: SafeNetCheck = yes
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: skipautopass = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: skipces = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: skipdotnet = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: UpgradeRegKey = SOFTWARE\Micro Focus\Visual COBOL\11.0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: UsingSafeNetMsgState = disable
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: vcredist20152022x64 = v14.50.35719.00
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: vcredist20152022x86 = v14.50.35719.00
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: VS2022ValidCheck = yes
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: VS2022ValidInstance = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: Windows10Build = 26100
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleAction = 5
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleElevated = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleInstalled = 0
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleLog = C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_install_20260216_113143.log
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleManufacturer = Rocket Software
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleName = Rocket Visual COBOL for Visual Studio 2022
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleOriginalSource = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleOriginalSourceFolder = C:\Users\FKGEISTA\Downloads\
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleProviderKey = {0b835cba-a870-4460-b1d0-2902564c6b9b}
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleSourceProcessFolder = C:\Users\FKGEISTA\Downloads\
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleSourceProcessPath = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleTag = 
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleUILevel = 3
[8B34:5FC8][2026-02-16T11:31:58]i410: Variable: WixBundleVersion = 11.0.250.0
[8B34:5FC8][2026-02-16T11:31:58]i007: Exit code: 0x1, restarting: No

```

---

## 7. Silent Install Log (last 80 lines, if run)

```
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse90<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Test Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs202290<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx6490<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx6490<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer90<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Visual COBOL Build Tools for Windows"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbt100<>"Micro Focus Enterprise Developer Build Tools for Windows"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Visual COBOL for Eclipse"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus COBOL Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipse100<>"Micro Focus Enterprise Developer for Eclipse"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Test Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Visual COBOL for Visual Studio 2022"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022100<>"Micro Focus Enterprise Developer for Visual Studio 2022"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64100<>"Micro Focus COBOL Server 64-bit"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64100<>"Micro Focus Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServer100<>"Micro Focus Enterprise Server Stored Procedures"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Visual COBOL Build Tools for Windows"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Enterprise Developer Build Tools for Windows"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regComPatAddPack230<>"Micro Focus Compatibility AddPack For Visual COBOL"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Visual COBOL for Eclipse" or WixBundleName="Rocket Visual COBOL for Visual Studio 2022"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket COBOL Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Enterprise Developer for Eclipse" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Test Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Visual COBOL for Visual Studio 2022" or WixBundleName="Rocket Visual COBOL for Eclipse"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Eclipse" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64Latest<>"Rocket COBOL Server 64-bit"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64Latest<>"Rocket Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server Stored Procedures"' evaluates to true.
[8B54:7A64][2026-02-16T11:32:03]i052: Condition 'WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"' evaluates to false.
[8B54:7A64][2026-02-16T11:32:03]e000: Error 0x81f40001: Bundle condition evaluated to false: WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"
[8B54:7A64][2026-02-16T11:32:03]i199: Detect complete, result: 0x0
[8B54:7A64][2026-02-16T11:32:03]i500: Shutting down, exit code: 0x1
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: 32BitOSEclipseMsgState = disable
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: accepteula = no
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: BrowseButton2State = disable
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: DockerService = SYSTEM\CurrentControlSet\Services\cexecsvc
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: EclipseLabelState = disable
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: FolderEditbox2State = disable
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: HFDetected = 1
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: ignorechecks = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: InstallFolder = C:\Program Files (x86)\Rocket Software\Visual COBOL
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: isdocker = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: issandbox = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: NetfxFullVersion = 533320
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: novsix = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: Privileged = 1
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: ProductRevision = 11.0.00250
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: ProgramFilesFolder = C:\Program Files (x86)\
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: regMS = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: SafeNetCheck = yes
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: skipautopass = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: skipces = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: skipdotnet = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: UpgradeRegKey = SOFTWARE\Micro Focus\Visual COBOL\11.0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: UsingSafeNetMsgState = disable
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: vcredist20152022x64 = v14.50.35719.00
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: vcredist20152022x86 = v14.50.35719.00
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: VS2022ValidCheck = yes
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: VS2022ValidInstance = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: Windows10Build = 26100
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleAction = 5
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleElevated = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleInstalled = 0
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleLog = C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_silent_20260216_113159.log
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleManufacturer = Rocket Software
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleName = Rocket Visual COBOL for Visual Studio 2022
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleOriginalSource = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleOriginalSourceFolder = C:\Users\FKGEISTA\Downloads\
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleProviderKey = {0b835cba-a870-4460-b1d0-2902564c6b9b}
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleSourceProcessFolder = C:\Users\FKGEISTA\Downloads\
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleSourceProcessPath = C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleTag = 
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleUILevel = 2
[8B54:7A64][2026-02-16T11:32:03]i410: Variable: WixBundleVersion = 11.0.250.0
[8B54:7A64][2026-02-16T11:32:03]i007: Exit code: 0x1, restarting: No

```

---

## 8. Ignorechecks=1 Install Log (last 80 lines, if run)

```
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Visual COBOL Build Tools for Windows"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtLatest<>"Rocket Enterprise Developer Build Tools for Windows"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regComPatAddPack230<>"Micro Focus Compatibility AddPack For Visual COBOL"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Visual COBOL for Eclipse" or WixBundleName="Rocket Visual COBOL for Visual Studio 2022"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket COBOL Server"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regEclipseLatest<>"Rocket Enterprise Developer for Eclipse" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Test Server"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Visual COBOL for Visual Studio 2022" or WixBundleName="Rocket Visual COBOL for Eclipse"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regvs2022Latest<>"Rocket Enterprise Developer for Visual Studio 2022" or WixBundleName="Rocket AMB AddPack" or WixBundleName="Rocket Enterprise Developer for Eclipse" or WixBundleName="Remote Data Tools for Enterprise Server"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerx64Latest<>"Rocket COBOL Server 64-bit"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regbtx64Latest<>"Rocket Visual COBOL Build Tools for Windows 64-bit"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or regServerLatest<>"Rocket Enterprise Server Stored Procedures"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i199: Detect complete, result: 0x0
[BA2C:9E94][2026-02-16T11:32:08]i000: Running plan BA function
[BA2C:9E94][2026-02-16T11:32:08]i000: Setting numeric variable 'RadioButton' to value 0
[BA2C:6B30][2026-02-16T11:32:08]i200: Plan begin, 9 packages, action: Install
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'NOT vcredist20152022x86 OR vcredist20152022x86 < v14.42.34438.00' evaluates to false.
[BA2C:6B30][2026-02-16T11:32:08]w321: Skipping dependency registration on package with no dependency providers: vcredist2015_2022_x86
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'VersionNT64 AND (NOT vcredist20152022x64 OR vcredist20152022x64 < v14.42.34438.00)' evaluates to false.
[BA2C:6B30][2026-02-16T11:32:08]w321: Skipping dependency registration on package with no dependency providers: vcredist2015_2022_x64
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'skipdotnet=0 AND ((VersionNT >= v6.1) OR (VersionNT64 >= v6.1) AND (NOT NetfxFullVersion OR NetfxFullVersion < 528049))' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]w321: Skipping dependency registration on package with no dependency providers: dotnetfx48
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'skipces=0 AND VersionNT64' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleLog_lmsetupx64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_000_lmsetupx64.log'
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'VersionNT64' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleRollbackLog_visualcobol_110x64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_001_visualcobol_110x64_rollback.log'
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleLog_visualcobol_110x64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_001_visualcobol_110x64.log'
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'VersionNT64' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleRollbackLog_visualcobolvisualstudio2022_110x64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_002_visualcobolvisualstudio2022_110x64_rollback.log'
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleLog_visualcobolvisualstudio2022_110x64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_002_visualcobolvisualstudio2022_110x64.log'
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleRollbackLog_asintegrationx64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_003_asintegrationx64_rollback.log'
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleLog_asintegrationx64' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_003_asintegrationx64.log'
[BA2C:6B30][2026-02-16T11:32:08]i052: Condition 'novsix=0' evaluates to true.
[BA2C:6B30][2026-02-16T11:32:08]w321: Skipping dependency registration on package with no dependency providers: MFVSIXINSTALL
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleLog_MFVSIXINSTALL' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_004_MFVSIXINSTALL.log'
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleRollbackLog_MFVSIXINSTALL' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_004_MFVSIXINSTALL_rollback.log'
[BA2C:6B30][2026-02-16T11:32:08]w321: Skipping dependency registration on package with no dependency providers: cblms_x86
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleLog_cblms_x86' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_005_cblms_x86.log'
[BA2C:6B30][2026-02-16T11:32:08]i000: Setting string variable 'WixBundleRollbackLog_cblms_x86' to value 'C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\vcvs2022_ignorechecks_20260216_113204_005_cblms_x86_rollback.log'
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: vcredist2015_2022_x86, state: Present, default requested: Absent, ba requested: Absent, execute: None, rollback: None, cache: No, uncache: No, dependency: None
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: vcredist2015_2022_x64, state: Present, default requested: Absent, ba requested: Absent, execute: None, rollback: None, cache: No, uncache: No, dependency: None
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: dotnetfx48, state: Present, default requested: Present, ba requested: Present, execute: None, rollback: None, cache: No, uncache: No, dependency: None
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: lmsetupx64, state: Absent, default requested: Present, ba requested: Present, execute: Install, rollback: None, cache: Yes, uncache: No, dependency: Register
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: visualcobol_110x64, state: Absent, default requested: Present, ba requested: Present, execute: Install, rollback: Uninstall, cache: Yes, uncache: No, dependency: Register
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: visualcobolvisualstudio2022_110x64, state: Absent, default requested: Present, ba requested: Present, execute: Install, rollback: Uninstall, cache: Yes, uncache: No, dependency: Register
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: asintegrationx64, state: Absent, default requested: Present, ba requested: Present, execute: Install, rollback: Uninstall, cache: Yes, uncache: No, dependency: Register
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: MFVSIXINSTALL, state: Absent, default requested: Present, ba requested: Present, execute: Install, rollback: Uninstall, cache: Yes, uncache: No, dependency: None
[BA2C:6B30][2026-02-16T11:32:08]i201: Planned package: cblms_x86, state: Absent, default requested: Present, ba requested: Present, execute: Install, rollback: Uninstall, cache: Yes, uncache: No, dependency: None
[BA2C:6B30][2026-02-16T11:32:08]i000: Running plan complete BA function
[BA2C:6B30][2026-02-16T11:32:08]i299: Plan complete, result: 0x0
[BA2C:6B30][2026-02-16T11:32:08]i300: Apply begin
[BA2C:6B30][2026-02-16T11:32:08]i010: Launching elevated engine process.
[BA2C:6B30][2026-02-16T11:49:09]i011: Launched elevated engine process.
[BA2C:6B30][2026-02-16T11:49:09]i012: Connected to elevated engine.
[8300:49FC][2026-02-16T11:49:09]i358: Pausing automatic updates.
[8300:49FC][2026-02-16T11:49:09]i359: Paused automatic updates.
[8300:49FC][2026-02-16T11:49:09]i360: Creating a system restore point.
[8300:49FC][2026-02-16T11:49:09]w363: Could not create system restore point, error: 0x80070422. Continuing...
[8300:49FC][2026-02-16T11:49:09]i370: Session begin, registration key: SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{0b835cba-a870-4460-b1d0-2902564c6b9b}, options: 0x7, disable resume: No
[8300:49FC][2026-02-16T11:49:11]i000: Caching bundle from: 'C:\Users\FKGEISTA\AppData\Local\Temp\{EBC9EDF3-345F-4590-B137-970A454F3323}\.be\vcvs2022_110.exe' to: 'C:\ProgramData\Package Cache\{0b835cba-a870-4460-b1d0-2902564c6b9b}\vcvs2022_110.exe'
[8300:49FC][2026-02-16T11:49:11]i320: Registering bundle dependency provider: {0b835cba-a870-4460-b1d0-2902564c6b9b}, version: 11.0.250.0
[8300:49FC][2026-02-16T11:49:11]i371: Updating session, registration key: SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{0b835cba-a870-4460-b1d0-2902564c6b9b}, resume: Active, restart initiated: No, disable resume: No
[8300:5420][2026-02-16T11:49:13]i305: Verified acquired payload: lmsetupx64 at path: C:\ProgramData\Package Cache\.unverified\lmsetupx64, moving to: C:\ProgramData\Package Cache\{F2613288-FA3A-4B22-822D-14EBD4539B95}v100.3.21310\lmsetup\lmsetupx64.msi.
[8300:49FC][2026-02-16T11:49:13]i323: Registering package dependency provider: {F2613288-FA3A-4B22-822D-14EBD4539B95}, version: 100.3.21310, package: lmsetupx64
[8300:49FC][2026-02-16T11:49:13]i301: Applying execute package: lmsetupx64, action: Install, path: C:\ProgramData\Package Cache\{F2613288-FA3A-4B22-822D-14EBD4539B95}v100.3.21310\lmsetup\lmsetupx64.msi, arguments: ' MSIFASTINSTALL="7" SKIPAUTOPASS="0"'
[8300:5420][2026-02-16T11:49:14]i305: Verified acquired payload: visualcobol_110x64 at path: C:\ProgramData\Package Cache\.unverified\visualcobol_110x64, moving to: C:\ProgramData\Package Cache\{43F53378-874B-4355-ABC8-B7329A511EF4}v11.0.00250\visualcobolvisualstudio2022\visualcobol_110x64.msi.
[8300:5420][2026-02-16T11:49:17]i305: Verified acquired payload: visualcobolvisualstudio2022_110x64 at path: C:\ProgramData\Package Cache\.unverified\visualcobolvisualstudio2022_110x64, moving to: C:\ProgramData\Package Cache\{D92F3B2D-E15B-477D-8BD4-908AAA0AF302}v11.0.00250\visualcobolvisualstudio2022\visualcobolvisualstudio2022_110x64.msi.
[8300:5420][2026-02-16T11:49:17]i305: Verified acquired payload: asintegrationx64 at path: C:\ProgramData\Package Cache\.unverified\asintegrationx64, moving to: C:\ProgramData\Package Cache\{CC5E380A-CDB5-42F8-9E3A-41A8EDFA324E}v11.0.00250\asintegration\asintegration_110x64.msi.
[8300:5420][2026-02-16T11:49:18]i305: Verified acquired payload: MFVSIXINSTALL at path: C:\ProgramData\Package Cache\.unverified\MFVSIXINSTALL, moving to: C:\ProgramData\Package Cache\DA02E719B27E1DEF678CE69BA4E27863A535AEFE\MFVSIXInstall.exe.
[8300:5420][2026-02-16T11:49:18]i305: Verified acquired payload: cblms_x86 at path: C:\ProgramData\Package Cache\.unverified\cblms_x86, moving to: C:\ProgramData\Package Cache\0F259B1C88F49352BAA87F4E78728450CEF5235F\cblms.exe.
[BA2C:6B30][2026-02-16T11:49:30]i319: Applied execute package: lmsetupx64, result: 0x0, restart: None
[8300:49FC][2026-02-16T11:49:30]i325: Registering dependency: {0b835cba-a870-4460-b1d0-2902564c6b9b} on package provider: {F2613288-FA3A-4B22-822D-14EBD4539B95}, package: lmsetupx64
[8300:49FC][2026-02-16T11:49:30]i323: Registering package dependency provider: {43F53378-874B-4355-ABC8-B7329A511EF4}, version: 11.0.00250, package: visualcobol_110x64
[8300:49FC][2026-02-16T11:49:30]i301: Applying execute package: visualcobol_110x64, action: Install, path: C:\ProgramData\Package Cache\{43F53378-874B-4355-ABC8-B7329A511EF4}v11.0.00250\visualcobolvisualstudio2022\visualcobol_110x64.msi, arguments: ' ARPSYSTEMCOMPONENT="1" MSIFASTINSTALL="7" INSTALLDIR="C:\Program Files (x86)\Rocket Software\Visual COBOL" ECLIPSEINSTALLDIR="" BUILDSERVER=""'
[BA2C:6B30][2026-02-16T11:53:12]i319: Applied execute package: visualcobol_110x64, result: 0x0, restart: None
[8300:49FC][2026-02-16T11:53:12]i325: Registering dependency: {0b835cba-a870-4460-b1d0-2902564c6b9b} on package provider: {43F53378-874B-4355-ABC8-B7329A511EF4}, package: visualcobol_110x64
[8300:49FC][2026-02-16T11:53:12]i323: Registering package dependency provider: {D92F3B2D-E15B-477D-8BD4-908AAA0AF302}, version: 11.0.00250, package: visualcobolvisualstudio2022_110x64
[8300:49FC][2026-02-16T11:53:12]i301: Applying execute package: visualcobolvisualstudio2022_110x64, action: Install, path: C:\ProgramData\Package Cache\{D92F3B2D-E15B-477D-8BD4-908AAA0AF302}v11.0.00250\visualcobolvisualstudio2022\visualcobolvisualstudio2022_110x64.msi, arguments: ' ARPSYSTEMCOMPONENT="1" MSIFASTINSTALL="7" INSTALLDIR="C:\Program Files (x86)\Rocket Software\Visual COBOL" ECLIPSEINSTALLDIR=""'

```

---

## 9. Next Steps

- Attach this report and the full install log(s) from $ReportFolder to the Rocket support case.
- Add your **Rocket Software product serial number** in section 1.
- Run the **Rocket Software Support Scan utility** and attach its output.
- Use section 3 to copy/paste or adapt the problem description when opening the case.

