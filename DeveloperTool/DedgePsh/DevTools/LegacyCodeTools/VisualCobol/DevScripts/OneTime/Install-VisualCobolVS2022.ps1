#Requires -Version 7.0
<#
.SYNOPSIS
    Installs Rocket Visual COBOL 11.0 for VS 2022 and generates a support-case report.
.DESCRIPTION
    Tries multiple installation approaches for vcvs2022_110.exe and collects diagnostics
    per RaiseASupportCaseWithRocket.md for opening a Rocket support case.

    Installation attempts (in order):
    1. Query installer help (/?)
    2. /install /passive /norestart /log
    3. /install /quiet /norestart /log (if attempt 2 failed)
    4. /install /quiet ignorechecks=1 /log (if attempts 2+3 failed, bypasses VS2022 detection)

    Source: Rocket Visual COBOL Documentation Version 11 - Installing Visual COBOL Build Tools for Windows
.EXAMPLE
    .\Install-VisualCobolVS2022.ps1
    .\Install-VisualCobolVS2022.ps1 -InstallerPath 'D:\Downloads\vcvs2022_110.exe'
#>
[CmdletBinding()]
param(
    [string]$InstallerPath = "C:\Users\$($env:USERNAME)\Downloads\vcvs2022_110.exe",
    [string]$ReportFolder = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$reportPath = Join-Path $ReportFolder "Report-VisualCobolInstall-$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
$installLogPath = Join-Path $ReportFolder "vcvs2022_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$computerMakeModel = try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    "$($cs.Manufacturer) $($cs.Model)"
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
            if ($p.PSObject.Properties['ProductPath']) { $vsPaths += "VS $($ver): $($p.ProductPath)" }
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
    "File not found: $($InstallerPath)"
}

# --- Attempt 1: Query help ---
Write-LogMessage "Attempt 1: Query installer help (/?)" -Level INFO
$helpOut = $null
try {
    $helpOut = & $InstallerPath /? 2>&1
    if ($helpOut) { Write-LogMessage "Help output length: $($helpOut.ToString().Length)" -Level INFO }
} catch {
    $helpOut = $_.Exception.Message
}
$attempt1Result = @{ ExitCode = $LASTEXITCODE; Output = $helpOut }

# --- Attempt 2: Passive install ---
Write-LogMessage "Attempt 2: /install /passive /norestart /log" -Level INFO
$passiveResult = $null
if ($installerExists) {
    try {
        $p = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/passive', '/norestart', "/log `"$($installLogPath)`"" -Wait -PassThru
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

# --- Attempt 3: Silent install ---
$silentLogPath = Join-Path $ReportFolder "vcvs2022_silent_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$silentResult = $null
if ($installerExists -and ($null -eq $passiveResult.ExitCode -or $passiveResult.ExitCode -ne 0)) {
    Write-LogMessage "Attempt 3: /install /quiet /norestart /log" -Level INFO
    try {
        $p = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/quiet', '/norestart', "/log `"$($silentLogPath)`"" -Wait -PassThru
        $silentResult = @{ ExitCode = $p.ExitCode; LogFile = $silentLogPath }
        if (Test-Path $silentLogPath) {
            $silentResult['LogTail'] = Get-Content $silentLogPath -Tail 80 -ErrorAction SilentlyContinue
        }
    } catch {
        $silentResult = @{ Error = $_.Exception.Message }
    }
} else {
    $silentResult = @{ Skipped = 'Passive install already attempted' }
}

# --- Attempt 4: Install with ignorechecks=1 ---
$ignoreLogPath = Join-Path $ReportFolder "vcvs2022_ignorechecks_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ignoreResult = $null
if ($installerExists -and ($null -eq $passiveResult.ExitCode -or $passiveResult.ExitCode -ne 0) -and ($null -eq $silentResult.ExitCode -or $silentResult.ExitCode -ne 0)) {
    Write-LogMessage "Attempt 4: /install /quiet ignorechecks=1 /log (bypass VS2022 detection)" -Level INFO
    try {
        $p = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/quiet', '/norestart', 'ignorechecks=1', "/log `"$($ignoreLogPath)`"" -Wait -PassThru
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

# --- Build report ---
$report = @"
# Visual COBOL 11.0 for VS 2022 - Installation Attempt Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Computer:** $($env:COMPUTERNAME)
**Report file:** $($reportPath)

---

## 1. Information for Rocket Support

| Item | Value |
|------|--------|
| **Rocket product** | Visual COBOL 11.0 (vcvs2022_110.exe) |
| **Rocket serial number** | _(Add from Electronic Delivery Receipt or Activation email)_ |
| **Computer make and model** | $($computerMakeModel) |
| **OS** | $($osInfo) |
| **Visual Studio** | $($vsInfo) |
| **Installer** | $($installerInfo) |

---

## 2. Installation Attempts Summary

| Attempt | Method | Result |
|---------|--------|--------|
| 1 | Installer /? (help) | ExitCode: $($attempt1Result.ExitCode) |
| 2 | /install /passive /norestart /log | $(if ($null -ne $passiveResult.ExitCode) { "ExitCode: $($passiveResult.ExitCode)" } else { $passiveResult.Error ?? $passiveResult.Skipped }) |
| 3 | /install /quiet /norestart /log | $(if ($null -ne $silentResult.ExitCode) { "ExitCode: $($silentResult.ExitCode)" } elseif ($silentResult.Skipped) { $silentResult.Skipped } else { $silentResult.Error }) |
| 4 | /install /quiet ignorechecks=1 /log | $(if ($null -ne $ignoreResult.ExitCode) { "ExitCode: $($ignoreResult.ExitCode)" } elseif ($ignoreResult.Skipped) { $ignoreResult.Skipped } else { $ignoreResult.Error }) |

---

## 3. Official Installer Command-Line Options

| Argument | Description |
|----------|-------------|
| ``/install`` \| ``/repair`` \| ``/uninstall`` | Primary action; ``/install`` is default |
| ``/passive`` \| ``/quiet`` | ``/passive`` = minimal UI; ``/quiet`` = no UI |
| ``/norestart`` | Suppress automatic restart |
| ``/log log.txt`` | Custom log path (default: %TEMP%) |
| ``InstallFolder=path`` | Main product install folder |
| ``ignorechecks=1`` | Bypass preconditions (e.g. VS2022 detection) |

---

## 4. Installer Help Output (Attempt 1)

``````
$($helpOut | Out-String)
``````

---

## 5. Passive Install Log (last 80 lines)

``````
$($passiveResult.LogTail | Out-String)
``````

---

## 6. Silent Install Log (last 80 lines, if run)

``````
$($silentResult.LogTail | Out-String)
``````

---

## 7. Ignorechecks Install Log (last 80 lines, if run)

``````
$($ignoreResult.LogTail | Out-String)
``````

---

## 8. Next Steps

- Attach this report and the full install log(s) to the Rocket support case.
- Add your **Rocket Software product serial number** in section 1.
- Run the **Rocket Software Support Scan utility** and attach its output.
"@

Set-Content -Path $reportPath -Value $report -Encoding UTF8
Write-LogMessage "Report written to: $($reportPath)" -Level INFO
$reportPath
