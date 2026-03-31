#Requires -Version 7.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls existing Rocket software, then installs COBOL Server 11.0
    (Full + Patch 3) with License Manager and license activation.
.DESCRIPTION
    Complete clean install sequence:
    0. Uninstall ALL existing Rocket / Micro Focus software (clean slate)
    1. Install Visual C++ Redistributables (x86 + x64) from SDK
    2. Install COBOL Server 11.0 base (cs_110.exe) — 32+64 bit
       This includes the License Manager automatically.
    3. Extract and activate the license file (XML from zip)
    4. Install COBOL Server 11.0 Patch Update 3 (cs_110_pu03_390812.exe)
    5. Verify all required executables exist

    After installation these executables are available:
      run.exe     — COBOL runtime executor, console mode
      runw.exe    — COBOL runtime executor, windowed mode
      dswin.exe   — Data File Editor

    NOTE: cobol.exe (compiler) and cobrun.exe are NOT included in
    COBOL Server. They require Visual COBOL Build Tools (vcbt_110.exe)
    or Visual COBOL for Visual Studio (vcvs2022_110.exe).

    Install path: C:\Program Files (x86)\Rocket Software\COBOL Server\
    (as shown by the installer dialog — may vary by version)

    Source: Rocket Visual COBOL Documentation Version 11
.PARAMETER SourceBaseFull
    UNC path to the Rocket Server 11 Full installation folder.
.PARAMETER SourcePatch3
    UNC path to the Rocket Server 11 Patch 3 folder.
.PARAMETER InstallFolder
    Custom install directory. If omitted, uses the installer default.
.PARAMETER SkipUninstall
    Skip the uninstall-existing-software step.
.PARAMETER SkipVcRedist
    Skip Visual C++ Redistributable installation.
.PARAMETER SkipLicense
    Skip license file extraction and activation.
.PARAMETER SkipPatch
    Skip Patch 3 installation.
.PARAMETER LicenseFile
    Path to the license XML file. Auto-detected from the license zip if omitted.
.EXAMPLE
    .\Install-RocketCobolServer.ps1
.EXAMPLE
    .\Install-RocketCobolServer.ps1 -SkipUninstall
.EXAMPLE
    .\Install-RocketCobolServer.ps1 -SkipPatch -SkipVcRedist
#>
[CmdletBinding()]
param(
    [string]$SourceBaseFull = '\\t-no1fkmvct-app\Opt\data\Rocket Server 11 Full',

    [string]$SourcePatch3 = '\\t-no1fkmvct-app\Opt\data\Rocket Server 11 Patch 3',

    [string]$InstallFolder = '',

    [switch]$SkipUninstall,

    [switch]$SkipVcRedist,

    [switch]$SkipLicense,

    [switch]$SkipPatch,

    [string]$LicenseFile = ''
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$tempBase = 'C:\TEMPFK\RocketCobolServer'
$sdkZip = Join-Path $SourceBaseFull 'cs_110_deployment_sdk.zip'
$licenseZip = Join-Path $SourceBaseFull 'AMC-COBS-LT-100-11.0.0-VCPU-670000127709.zip'

Write-LogMessage '====================================================' -Level INFO
Write-LogMessage 'Rocket COBOL Server 11.0 — Automated Clean Install' -Level INFO
Write-LogMessage '====================================================' -Level INFO
Write-LogMessage "Computer : $($env:COMPUTERNAME)" -Level INFO
Write-LogMessage "User     : $($env:USERNAME)" -Level INFO
Write-LogMessage "Source (base) : $($SourceBaseFull)" -Level INFO
Write-LogMessage "Source (patch): $($SourcePatch3)" -Level INFO

if (-not (Test-Path $SourceBaseFull)) {
    Write-LogMessage "Base source folder not accessible: $($SourceBaseFull)" -Level ERROR
    exit 1
}

if (-not (Test-Path $tempBase)) {
    New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
}

# ============================================================
# STEP 0: Uninstall ALL existing Rocket / Micro Focus software
# ============================================================

if (-not $SkipUninstall) {
    Write-LogMessage '--- Step 0: Uninstall existing Rocket / Micro Focus software ---' -Level INFO

    $uninstallPatterns = @('*Rocket*', '*Micro Focus*', '*COBOL*')
    $packagesToRemove = @()

    foreach ($pattern in $uninstallPatterns) {
        $found = Get-Package -Name $pattern -ErrorAction SilentlyContinue
        if ($found) { $packagesToRemove += $found }
    }

    $packagesToRemove = $packagesToRemove |
        Sort-Object Name -Unique |
        Where-Object { $_.Name -notmatch 'Visual C\+\+' }

    if ($packagesToRemove.Count -eq 0) {
        Write-LogMessage '  No existing Rocket/Micro Focus packages found.' -Level INFO
    } else {
        Write-LogMessage "  Found $($packagesToRemove.Count) package(s) to remove:" -Level INFO
        foreach ($pkg in $packagesToRemove) {
            Write-LogMessage "    - $($pkg.Name) ($($pkg.Version))" -Level INFO
        }

        foreach ($pkg in $packagesToRemove) {
            Write-LogMessage "  Uninstalling: $($pkg.Name) ..." -Level INFO
            try {
                $pkg | Uninstall-Package -Force -ErrorAction Stop
                Write-LogMessage "    Removed: $($pkg.Name)" -Level INFO
            } catch {
                Write-LogMessage "    Uninstall-Package failed for $($pkg.Name), trying MSI fallback..." -Level WARN

                $uninstallString = $null
                $regPaths = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                )
                foreach ($regPath in $regPaths) {
                    $entry = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -eq $pkg.Name }
                    if ($entry -and $entry.UninstallString) {
                        $uninstallString = $entry.UninstallString
                        break
                    }
                }

                if ($uninstallString) {
                    # Extract GUID from msiexec uninstall string
                    # Regex: match a GUID in {xxxxxxxx-...} format inside the uninstall string
                    if ($uninstallString -match '\{[0-9A-Fa-f\-]+\}') {
                        $guid = $Matches[0]
                        Write-LogMessage "    MSI uninstall GUID: $($guid)" -Level INFO
                        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/qn /x $($guid)" -Wait -PassThru
                        Write-LogMessage "    msiexec /x exit: $($proc.ExitCode)" -Level INFO
                    } else {
                        Write-LogMessage "    Running uninstall string directly..." -Level INFO
                        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$($uninstallString) /quiet`"" -Wait -PassThru
                        Write-LogMessage "    Uninstall exit: $($proc.ExitCode)" -Level INFO
                    }
                } else {
                    Write-LogMessage "    No uninstall string found for $($pkg.Name). May need manual removal." -Level WARN
                }
            }
        }

        Write-LogMessage '  Waiting 5 seconds for cleanup...' -Level INFO
        Start-Sleep -Seconds 5

        $remaining = @()
        foreach ($pattern in $uninstallPatterns) {
            $found = Get-Package -Name $pattern -ErrorAction SilentlyContinue
            if ($found) { $remaining += $found }
        }
        $remaining = $remaining |
            Sort-Object Name -Unique |
            Where-Object { $_.Name -notmatch 'Visual C\+\+' }

        if ($remaining.Count -gt 0) {
            Write-LogMessage "  WARNING: $($remaining.Count) package(s) still remain after uninstall:" -Level WARN
            foreach ($r in $remaining) {
                Write-LogMessage "    - $($r.Name) ($($r.Version))" -Level WARN
            }
        } else {
            Write-LogMessage '  All Rocket/Micro Focus packages removed successfully.' -Level INFO
        }
    }

    $rocketDirs = @(
        'C:\Program Files (x86)\Rocket Software',
        'C:\Program Files (x86)\Micro Focus',
        'C:\Program Files\Rocket Software',
        'C:\Program Files\Micro Focus'
    )
    foreach ($dir in $rocketDirs) {
        if (Test-Path $dir) {
            Write-LogMessage "  Removing leftover directory: $($dir)" -Level INFO
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-LogMessage '--- Step 0: Uninstall (SKIPPED) ---' -Level INFO
}

# ============================================================
# STEP 1: Extract Deployment SDK (for VC++ Redistributables)
# ============================================================

Write-LogMessage '--- Step 1: Extract Deployment SDK (VC++ Redist) ---' -Level INFO
$sdkExtracted = Join-Path $tempBase 'sdk'
if (Test-Path $sdkZip) {
    if (-not (Test-Path (Join-Path $sdkExtracted 'VC_redist.x64.exe'))) {
        Write-LogMessage "Extracting SDK from: $($sdkZip)" -Level INFO
        if (Test-Path $sdkExtracted) { Remove-Item -Path $sdkExtracted -Recurse -Force }
        Expand-Archive -Path $sdkZip -DestinationPath $sdkExtracted -Force
        Write-LogMessage 'SDK extracted.' -Level INFO
    } else {
        Write-LogMessage 'SDK already extracted (skipping).' -Level DEBUG
    }
} else {
    Write-LogMessage "Deployment SDK zip not found: $($sdkZip)" -Level WARN
    Write-LogMessage 'VC++ Redistributables will need to be present already.' -Level WARN
}

# ============================================================
# STEP 2: Install Visual C++ Redistributables
# ============================================================

if (-not $SkipVcRedist) {
    Write-LogMessage '--- Step 2: Visual C++ Redistributables ---' -Level INFO

    $vcRedistX64 = Join-Path $sdkExtracted 'VC_redist.x64.exe'
    $vcRedistX86 = Join-Path $sdkExtracted 'VC_redist.x86.exe'

    if (Test-Path $vcRedistX64) {
        Write-LogMessage 'Installing VC++ Redistributable x64...' -Level INFO
        $proc = Start-Process -FilePath $vcRedistX64 -ArgumentList '/quiet /norestart' -Wait -PassThru
        Write-LogMessage "  VC_redist.x64: exit $($proc.ExitCode)" -Level INFO
    } else {
        Write-LogMessage "  VC_redist.x64.exe not found (SDK not extracted?)" -Level WARN
    }

    if (Test-Path $vcRedistX86) {
        Write-LogMessage 'Installing VC++ Redistributable x86...' -Level INFO
        $proc = Start-Process -FilePath $vcRedistX86 -ArgumentList '/quiet /norestart' -Wait -PassThru
        Write-LogMessage "  VC_redist.x86: exit $($proc.ExitCode)" -Level INFO
    } else {
        Write-LogMessage "  VC_redist.x86.exe not found (SDK not extracted?)" -Level WARN
    }
} else {
    Write-LogMessage '--- Step 2: Visual C++ Redistributables (SKIPPED) ---' -Level INFO
}

# ============================================================
# STEP 3: Install COBOL Server 11.0 Base (includes License Manager)
# ============================================================

Write-LogMessage '--- Step 3: COBOL Server 11.0 Base (+ License Manager) ---' -Level INFO
$csInstaller = Join-Path $SourceBaseFull 'cs_110.exe'

if (-not (Test-Path $csInstaller)) {
    Write-LogMessage "Base installer not found: $($csInstaller)" -Level ERROR
    exit 1
}

$csArgs = '/quiet'
if (-not [string]::IsNullOrWhiteSpace($InstallFolder)) {
    $csArgs = "/quiet InstallFolder=`"$($InstallFolder)`""
}

Write-LogMessage "Running: cs_110.exe $($csArgs)" -Level INFO
Write-LogMessage 'This may take 5-15 minutes...' -Level INFO
$proc = Start-Process -FilePath $csInstaller -ArgumentList $csArgs -Wait -PassThru
Write-LogMessage "cs_110.exe exit code: $($proc.ExitCode)" -Level INFO

if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
    Write-LogMessage "COBOL Server base install FAILED (exit $($proc.ExitCode))" -Level ERROR
    exit 1
}

if ($proc.ExitCode -eq 3010) {
    Write-LogMessage 'Exit 3010 = success, reboot recommended (continuing).' -Level INFO
}

# ============================================================
# STEP 4: Extract and Activate License
# ============================================================

if (-not $SkipLicense) {
    Write-LogMessage '--- Step 4: License Activation ---' -Level INFO

    if ([string]::IsNullOrWhiteSpace($LicenseFile)) {
        $licExtractDir = Join-Path $tempBase 'license'
        if (Test-Path $licenseZip) {
            Write-LogMessage "Extracting license zip: $($licenseZip)" -Level INFO
            if (Test-Path $licExtractDir) { Remove-Item -Path $licExtractDir -Recurse -Force }
            Expand-Archive -Path $licenseZip -DestinationPath $licExtractDir -Force

            $xmlFiles = @(Get-ChildItem -Path $licExtractDir -Recurse -Filter '*.xml')
            if ($xmlFiles.Count -gt 0) {
                $LicenseFile = $xmlFiles[0].FullName
                Write-LogMessage "Auto-detected license XML: $($LicenseFile)" -Level INFO
                if ($xmlFiles.Count -gt 1) {
                    Write-LogMessage "  (found $($xmlFiles.Count) XML files, using first)" -Level INFO
                    foreach ($xf in $xmlFiles) {
                        Write-LogMessage "    $($xf.Name)" -Level DEBUG
                    }
                }
            } else {
                Write-LogMessage 'No XML license files found in the zip.' -Level WARN
            }
        } else {
            Write-LogMessage "License zip not found: $($licenseZip)" -Level WARN
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LicenseFile) -and (Test-Path $LicenseFile)) {
        $cesadminPaths = @(
            'C:\Program Files (x86)\Rocket Software\License Manager\cesadmintool.exe',
            'C:\Program Files (x86)\Micro Focus\Licensing\cesadmintool.exe',
            'C:\Program Files (x86)\Rocket Software\COBOL Server\License Manager\cesadmintool.exe',
            'C:\Program Files (x86)\Common Files\SafeNet Sentinel\Sentinel RMS License Manager\WinNT\cesadmintool.exe'
        )
        $adminTool = $cesadminPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($adminTool) {
            Write-LogMessage "Activating license via: $($adminTool)" -Level INFO

            foreach ($xf in @(Get-ChildItem -Path (Split-Path $LicenseFile) -Filter '*.xml')) {
                Write-LogMessage "  Installing license: $($xf.Name)" -Level INFO
                $proc = Start-Process -FilePath $adminTool -ArgumentList "-term install -f `"$($xf.FullName)`"" -Wait -PassThru
                Write-LogMessage "    cesadmintool exit: $($proc.ExitCode)" -Level INFO
            }
        } else {
            Write-LogMessage 'cesadmintool.exe not found at any known path.' -Level WARN
            Write-LogMessage 'Open the Rocket License Administration GUI and import:' -Level WARN
            Write-LogMessage "  $($LicenseFile)" -Level WARN
        }
    } else {
        Write-LogMessage 'No license file available. Activate manually.' -Level WARN
    }
} else {
    Write-LogMessage '--- Step 4: License Activation (SKIPPED) ---' -Level INFO
}

# ============================================================
# STEP 5: Install COBOL Server 11.0 Patch Update 3
# ============================================================

if (-not $SkipPatch) {
    Write-LogMessage '--- Step 5: COBOL Server 11.0 Patch Update 3 ---' -Level INFO

    if (-not (Test-Path $SourcePatch3)) {
        Write-LogMessage "Patch folder not accessible: $($SourcePatch3)" -Level WARN
    } else {
        $patchInstaller = Join-Path $SourcePatch3 'cs_110_pu03_390812.exe'
        if (-not (Test-Path $patchInstaller)) {
            Write-LogMessage "Patch installer not found: $($patchInstaller)" -Level ERROR
        } else {
            $patchArgs = '/quiet'
            if (-not [string]::IsNullOrWhiteSpace($InstallFolder)) {
                $patchArgs = "/quiet InstallFolder=`"$($InstallFolder)`""
            }

            Write-LogMessage "Running: cs_110_pu03_390812.exe $($patchArgs)" -Level INFO
            Write-LogMessage 'This may take 3-5 minutes...' -Level INFO
            $proc = Start-Process -FilePath $patchInstaller -ArgumentList $patchArgs -Wait -PassThru
            Write-LogMessage "cs_110_pu03_390812.exe exit code: $($proc.ExitCode)" -Level INFO

            if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
                Write-LogMessage "Patch install may have failed (exit $($proc.ExitCode))" -Level WARN
            }
        }
    }
} else {
    Write-LogMessage '--- Step 5: COBOL Server Patch 3 (SKIPPED) ---' -Level INFO
}

# ============================================================
# STEP 6: Verification
# ============================================================

Write-LogMessage '--- Step 6: Verification ---' -Level INFO

$rocketBase = 'C:\Program Files (x86)\Rocket Software\COBOL Server'
$rocketBaseAlt = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$mfBase = 'C:\Program Files (x86)\Micro Focus\Visual COBOL'

$detectedBase = if (Test-Path $rocketBase) { $rocketBase }
               elseif (Test-Path $rocketBaseAlt) { $rocketBaseAlt }
               elseif (Test-Path $mfBase) { $mfBase }
               else { $null }

if ($detectedBase) {
    Write-LogMessage "  Detected install path: $($detectedBase)" -Level INFO
} else {
    Write-LogMessage '  Could not detect install path!' -Level ERROR
}

$checks = @(
    @{ Name = 'run.exe (32-bit)';    RelPath = 'bin\run.exe';      Required = $true }
    @{ Name = 'run.exe (64-bit)';    RelPath = 'bin64\run.exe';    Required = $true }
    @{ Name = 'runw.exe (32-bit)';   RelPath = 'bin\runw.exe';     Required = $true }
    @{ Name = 'runw.exe (64-bit)';   RelPath = 'bin64\runw.exe';   Required = $true }
    @{ Name = 'dswin.exe';           RelPath = 'bin\dswin.exe';    Required = $false }
    @{ Name = 'cobol.exe (32-bit)';  RelPath = 'bin\cobol.exe';    Required = $false }
    @{ Name = 'cobol.exe (64-bit)';  RelPath = 'bin64\cobol.exe';  Required = $false }
    @{ Name = 'cobrun.exe (32-bit)'; RelPath = 'bin\cobrun.exe';   Required = $false }
)

$allOk = $true
$requiredOk = $true

foreach ($check in $checks) {
    $fullPath = if ($detectedBase) { Join-Path $detectedBase $check.RelPath } else { "UNKNOWN\$($check.RelPath)" }
    $found = Test-Path $fullPath

    if (-not $found -and $detectedBase) {
        $altPaths = @($rocketBase, $rocketBaseAlt, $mfBase) | Where-Object { $_ -ne $detectedBase }
        foreach ($alt in $altPaths) {
            $altFull = Join-Path $alt $check.RelPath
            if (Test-Path $altFull) {
                $found = $true
                $fullPath = $altFull
                break
            }
        }
    }

    if (-not $found) {
        $searchResult = Get-ChildItem -Path 'C:\Program Files (x86)' -Recurse -Filter (Split-Path $check.RelPath -Leaf) -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Rocket|Micro Focus|COBOL' } |
            Select-Object -First 1
        if ($searchResult) {
            $found = $true
            $fullPath = $searchResult.FullName
        }
    }

    $status = if ($found) { 'OK' } else { 'MISSING' }
    $level = if ($found) { 'INFO' } elseif ($check.Required) { 'ERROR' } else { 'WARN' }
    Write-LogMessage "  [$($status)] $($check.Name) — $($fullPath)" -Level $level
    if (-not $found) {
        $allOk = $false
        if ($check.Required) { $requiredOk = $false }
    }
}

$lmPaths = @(
    'C:\Program Files (x86)\Rocket Software\License Manager\cesadmintool.exe',
    'C:\Program Files (x86)\Micro Focus\Licensing\cesadmintool.exe'
)
$lmFound = $lmPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($lmFound) {
    Write-LogMessage "  [OK] License Manager — $($lmFound)" -Level INFO
} else {
    Write-LogMessage '  [WARN] License Manager cesadmintool.exe not found' -Level WARN
}

# ============================================================
# Summary and Notification
# ============================================================

Write-LogMessage '====================================================' -Level INFO
if ($requiredOk) {
    Write-LogMessage 'Installation COMPLETE — all required executables verified.' -Level INFO
    if (-not $allOk) {
        Write-LogMessage '  (Some optional executables missing — see above)' -Level WARN
    }
} else {
    Write-LogMessage 'Installation completed with ERRORS — required executables missing.' -Level ERROR
}
Write-LogMessage '====================================================' -Level INFO

$smsNumber = switch ($env:USERNAME) {
    'FKGEISTA' { '+4797188358' }
    'FKSVEERI' { '+4795762742' }
    'FKMISTA'  { '+4799348397' }
    'FKCELERI' { '+4745269945' }
    default    { '+4797188358' }
}

$statusText = if ($requiredOk) { 'SUCCESS' } else { 'FAILED — missing executables' }
$msg = "COBOL Server 11.0 install on $($env:COMPUTERNAME): $($statusText). " +
       "Patch3=$(if($SkipPatch){'SKIP'}else{'YES'}). " +
       "run/runw verified=$($requiredOk)"

Send-Sms -Receiver $smsNumber -Message $msg

if ($requiredOk) { exit 0 } else { exit 1 }
