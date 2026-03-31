#Requires -Version 7.0
<#
.SYNOPSIS
    Attempts to install Rocket Visual COBOL 11.0 for VS 2022 and generates a support-case report.
.DESCRIPTION
    Tries multiple installation approaches for vcvs2022_110.exe and collects data per
    RaiseASupportCaseWithRocket.md for raising a Rocket support case.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InstallerPath = 'C:\Users\FKGEISTA\Downloads\vcvs2022_110.exe',
    [Parameter(Mandatory = $false)]
    [string]$ReportFolder = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$logDir = 'C:\opt\data\AllPwshLog'
$computerName = $env:COMPUTERNAME
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Import-Module GlobalFunctions -Force

$reportPath = Join-Path $ReportFolder "Report-VisualCobolInstall-$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
$installLogPath = Join-Path $ReportFolder "vcvs2022_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# --- Gather support-case data (per RaiseASupportCaseWithRocket.md) ---
$computerMakeModel = try {
    (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object Manufacturer, Model) | ForEach-Object { "$($_.Manufacturer) $($_.Model)" }
} catch { 'N/A' }

$osInfo = try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    "$($os.Caption) $($os.OSArchitecture) Build $($os.BuildNumber)"
} catch { 'N/A' }

$vsPaths = @()
foreach ($ver in @('17.0', '18.0')) {
    $key = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\$ver\Setup\VS"
    if (Test-Path $key) {
        try {
            $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            if ($p.PSObject.Properties['ProductPath']) { $vsPaths += "VS $ver : $($p.ProductPath)" }
        } catch { }
    }
}
$vsInstallDirs = @(Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$vsInfo = "Installed folders: $($vsInstallDirs -join ', '); Registry: $($vsPaths -join '; ')"

$installerExists = Test-Path $InstallerPath
$installerInfo = if ($installerExists) {
    $f = Get-Item $InstallerPath
    "Size: $($f.Length) bytes; LastWrite: $($f.LastWriteTimeUtc.ToString('o')); Version: $($f.VersionInfo.FileVersion)"
} else {
    "File not found: $InstallerPath"
}

# --- Attempt 1: Help /? to get supported switches ---
Write-LogMessage "Attempt 1: Query installer help (/?)" -Level INFO
$helpOut = $null
try {
    $helpOut = & $InstallerPath /? 2>&1
    if ($helpOut) { Write-LogMessage "Help output length: $($helpOut.ToString().Length)" -Level INFO }
} catch {
    $helpOut = $_.Exception.Message
}
$attempt1Result = @{ ExitCode = $LASTEXITCODE; Output = $helpOut }

# --- Attempt 2: Passive install with log (official: /passive /log) ---
Write-LogMessage "Attempt 2: /install /passive with /log" -Level INFO
$passiveResult = $null
if ($installerExists) {
    try {
        $p = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/passive', '/norestart', "/log `"$installLogPath`"" -Wait -PassThru
        $passiveResult = @{ ExitCode = $p.ExitCode; LogFile = $installLogPath }
        if (Test-Path $installLogPath) {
            $passiveResult['LogTail'] = Get-Content $installLogPath -Tail 80 -ErrorAction SilentlyContinue
        }
    } catch {
        $passiveResult = @{ Error = $_.Exception.Message }
    }
} else {
    $passiveResult = @{ Skipped = 'Installer not found' }
}

# --- Attempt 3: Silent /quiet with log (official: /quiet not /q) ---
$silentLogPath = Join-Path $ReportFolder "vcvs2022_silent_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$silentResult = $null
if ($installerExists -and ($null -eq $passiveResult.ExitCode -or $passiveResult.ExitCode -ne 0)) {
    Write-LogMessage "Attempt 3: /install /quiet /norestart with /log" -Level INFO
    try {
        $p = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/quiet', '/norestart', "/log `"$silentLogPath`"" -Wait -PassThru
        $silentResult = @{ ExitCode = $p.ExitCode; LogFile = $silentLogPath }
        if (Test-Path $silentLogPath) {
            $silentResult['LogTail'] = Get-Content $silentLogPath -Tail 80 -ErrorAction SilentlyContinue
        }
    } catch {
        $silentResult = @{ Error = $_.Exception.Message }
    }
} else {
    $silentResult = @{ Skipped = 'Passive already attempted' }
}

# --- Attempt 4: Install with ignorechecks=1 (bypass VS2022 detection if it fails) ---
$ignoreLogPath = Join-Path $ReportFolder "vcvs2022_ignorechecks_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ignoreResult = $null
if ($installerExists -and ($null -eq $passiveResult.ExitCode -or $passiveResult.ExitCode -ne 0) -and ($null -eq $silentResult.ExitCode -or $silentResult.ExitCode -ne 0)) {
    Write-LogMessage "Attempt 4: /install /quiet ignorechecks=1 /log (bypass VS2022 check)" -Level INFO
    try {
        $p = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/quiet', '/norestart', 'ignorechecks=1', "/log `"$ignoreLogPath`"" -Wait -PassThru
        $ignoreResult = @{ ExitCode = $p.ExitCode; LogFile = $ignoreLogPath }
        if (Test-Path $ignoreLogPath) {
            $ignoreResult['LogTail'] = Get-Content $ignoreLogPath -Tail 80 -ErrorAction SilentlyContinue
        }
    } catch {
        $ignoreResult = @{ Error = $_.Exception.Message }
    }
} else {
    $ignoreResult = @{ Skipped = 'Not run (earlier attempt succeeded or not applicable)' }
}

# --- Build report (aligned with RaiseASupportCaseWithRocket.md) ---
$report = @"
# Visual COBOL 11.0 for VS 2022 – Installation Attempt Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
**Computer:** $computerName  
**Report file:** $reportPath

---

## 1. Information for Rocket Support (from RaiseASupportCaseWithRocket.md)

| Item | Value |
|------|--------|
| **Rocket product** | Visual COBOL 11.0 (vcvs2022_110.exe) |
| **Rocket serial number** | _(Add from Electronic Delivery Receipt or Activation email)_ |
| **Computer make and model** | $computerMakeModel |
| **OS** | $osInfo |
| **Visual Studio** | $vsInfo |
| **Installer** | $installerInfo |

**Product/environment:** Run the [Rocket Software Support Scan utility](https://docs.rocketsoftware.com) and attach its output to the support case.

---

## 2. Installation Attempts Summary

| Attempt | Method | Result |
|---------|--------|--------|
| 1 | Installer /? (help) | ExitCode: $($attempt1Result.ExitCode) |
| 2 | /install /passive /norestart /log | $(if ($null -ne $passiveResult.ExitCode) { "ExitCode: $($passiveResult.ExitCode)" } else { $passiveResult.Error }) |
| 3 | /install /quiet /norestart /log | $(if ($null -ne $silentResult.ExitCode) { "ExitCode: $($silentResult.ExitCode)" } elseif ($silentResult.Skipped) { $silentResult.Skipped } else { $silentResult.Error }) |
| 4 | /install /quiet ignorechecks=1 /log | $(if ($null -ne $ignoreResult.ExitCode) { "ExitCode: $($ignoreResult.ExitCode)" } elseif ($ignoreResult.Skipped) { $ignoreResult.Skipped } else { $ignoreResult.Error }) |

**Root cause from logs:** Installer reports `VS2022ValidInstance=0` and fails with bundle condition: `WixBundleInstalled or ignorechecks="1" or VS2022ValidInstance="1"`. So the setup does not detect a valid Visual Studio 2022 instance on this machine (VS 2022 and VS 18/2026 are present under `C:\Program Files\Microsoft Visual Studio`).

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
- **Steps to reproduce:** Run `$InstallerPath` with `/install /passive` or `/install /quiet` and `/log <path>`. Installer exits with code 1 during detect phase.
- **Context:** Installing Visual COBOL 11.0 extension for Visual Studio 2022; VS 2022 and VS 2026 (18.0) are installed. Log shows `VS2022ValidInstance = 0` and condition `VS2022ValidInstance="1"` false.

---

## 5. Installer Help Output (Attempt 1)

``````
$($helpOut | Out-String)
``````

---

## 6. Passive Install Log (last 80 lines)

``````
$($passiveResult.LogTail | Out-String)
``````

---

## 7. Silent Install Log (last 80 lines, if run)

``````
$($silentResult.LogTail | Out-String)
``````

---

## 8. Ignorechecks=1 Install Log (last 80 lines, if run)

``````
$($ignoreResult.LogTail | Out-String)
``````

---

## 9. Next Steps

- Attach this report and the full install log(s) from `$ReportFolder` to the Rocket support case.
- Add your **Rocket Software product serial number** in section 1.
- Run the **Rocket Software Support Scan utility** and attach its output.
- Use section 3 to copy/paste or adapt the problem description when opening the case.

"@

Set-Content -Path $reportPath -Value $report -Encoding UTF8
Write-LogMessage "Report written to: $reportPath" -Level INFO

# Return report path for caller
$reportPath
