# Rocket COBOL Server 11.0 — Installation Analysis

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Technology:** Rocket Visual COBOL 11.0, COBOL Server, License Manager

---

## 1. Installation Files Inventory

### Rocket Server 11 Full (`\\t-no1fkmvct-app\Opt\data\Rocket Server 11 Full\`)

| File | Size | Description |
|------|-----:|-------------|
| `cs_110.exe` | 417 MB | **COBOL Server 11.0 installer** — 32+64 bit. This is the main product. |
| `csx64_110.exe` | 307 MB | COBOL Server 11.0 — 64-bit only variant. Not needed when using `cs_110.exe`. |
| `cs_110_deployment_sdk.zip` | 539 MB | **Deployment SDK** — MSI/MSM packages for repackaging (see Section 3). |
| `license_manager_321310.zip` | 988 MB | Standalone License Manager installer (alternative to SDK method). |
| `AMC-COBS-LT-100-11.0.0-VCPU-670000127709.zip` | 19 KB | **License file** — contains XML authorization (see Section 4). |
| `cobol_server_11.0_release_notes.pdf` | 0.4 MB | Release notes. |

### Rocket Server 11 Patch 3 (`\\t-no1fkmvct-app\Opt\data\Rocket Server 11 Patch 3\`)

| File | Size | Description |
|------|-----:|-------------|
| `cs_110_pu03_390812.exe` | 140 MB | **Patch Update 3** — 32+64 bit. Apply AFTER base install. |
| `csx64_110_pu03_390812.exe` | 84 MB | Patch Update 3 — 64-bit only. Not needed when using `cs_110_pu03_390812.exe`. |
| `cs_110_pu03_390812_deployment_sdk.zip` | 548 MB | Updated Deployment SDK for Patch 3. |
| `license_manager_321350.zip` | 992 MB | Updated License Manager (Patch 3 version). |
| `cobol_server_11.0_patch_update_3_readme.pdf` | 0.3 MB | Patch readme. |
| `VC-CS-ED-ES-winversion-license.txt` | 1.8 MB | License compatibility matrix. |

---

## 2. What Is COBOL Server?

**COBOL Server** is the **runtime-only** deployment and execution environment for applications developed with Visual COBOL. It provides the run-time system needed to execute compiled COBOL programs (`.int`, `.gnt`, `.dll` files) on servers.

**CRITICAL: COBOL Server does NOT include the compiler (`cobol.exe`).** It is runtime only.

From the RAG documentation (source: **Product Overview.md**):

> *"COBOL Server is a companion to Visual COBOL. COBOL Server provides the run-time environment for running COBOL applications."*

### What It Installs (confirmed on t-no1fkmvct-app, 2026-03-10)

| Component | Present? | Location | Purpose |
|-----------|:--------:|----------|---------|
| `run.exe` | Yes | `bin\` / `bin64\` | Console runtime executor |
| `runw.exe` | Yes | `bin\` / `bin64\` | Windowed runtime executor |
| `dswin.exe` | Yes | `bin\` | Data File Editor |
| `cobol.exe` | **No** | — | Compiler — NOT in COBOL Server |
| `cobrun.exe` | **No** | — | INT code runner — NOT in COBOL Server |
| Runtime DLLs | Yes | `bin\` / `bin64\` | Shared libraries for execution |
| License Manager | Yes | separate folder | Installed automatically with cs_110.exe |

Default install path: `C:\Program Files (x86)\Rocket Software\COBOL Server\`

### Rocket Product Comparison

| Product | Installer | Has `cobol.exe`? | Has `run.exe`? | Needs VS? |
|---------|-----------|:----------------:|:--------------:|:---------:|
| **COBOL Server** | `cs_110.exe` | No | Yes | No |
| **Build Tools** | `vcbt_110.exe` | **Yes** | Yes | No |
| **Visual COBOL for VS 2022** | `vcvs2022_110.exe` | Yes | Yes | **Yes** |
| **Development Hub** | N/A | Yes | Yes | Linux only |

### Architecture Decision

Since `vcbt_110.exe` (Build Tools) is not currently available:
1. **Compile locally** on the developer machine (Visual COBOL for VS 2022)
2. **Transfer compiled output** to `t-no1fkmvct-app` via UNC
3. **Run on the server** using COBOL Server runtime

### cs_110.exe vs csx64_110.exe

| Installer | Bitness | Includes |
|-----------|---------|----------|
| `cs_110.exe` | 32+64 bit | Both `bin\` and `bin64\` directories. **Use this one.** |
| `csx64_110.exe` | 64-bit only | Only `bin64\`. No 32-bit support. |

**Recommendation:** Use `cs_110.exe` (32+64 bit) since the legacy COBOL programs use 32-bit compilation by default (`$SET MF ANS85`, `COBMODE=32`).

---

## 3. Deployment SDK Analysis

The file `cs_110_deployment_sdk.zip` contains the **COBOL Server Deployment Toolkit** — a set of components for repackaging COBOL Server with your own applications. It is NOT required for a standard server installation.

### SDK Contents

| File | Size | Purpose |
|------|-----:|---------|
| `cobolserver_110x64.msi` | 211 MB | COBOL Server as MSI package (for embedding in bundle installers) |
| `cobolserver_110x64.msm` | 240 MB | COBOL Server merge module (for embedding in MSI-based app installers) |
| `lmsetupx64.msi` | 58 MB | **License Manager MSI** — installs the Rocket License Administration tool |
| `Microsoft_VC143_CRT_x64.msm` | 0.6 MB | Visual C++ Runtime merge module (x64) |
| `Microsoft_VC143_CRT_x86.msm` | 0.5 MB | Visual C++ Runtime merge module (x86) |
| `VC_redist.x64.exe` | 25 MB | Visual C++ Redistributable x64 |
| `VC_redist.x86.exe` | 13 MB | Visual C++ Redistributable x86 |
| `NetworkDeploy_Server.bat` | <1 KB | Legacy batch script for network deployment (interactive, not useful for automation) |
| `NetworkDeploy_Client.bat` | <1 KB | Legacy batch script for client PATH setup (interactive) |
| `COBOL_Server_Deployment_Toolkit.html` | 43 KB | **Documentation** — explains merge modules and license manager install |

### Do We Need the SDK?

**Yes, but only for two components:**

1. **`lmsetupx64.msi`** — The License Manager is NOT included in `cs_110.exe` and must be installed separately. The SDK provides the MSI for this.
2. **`VC_redist.x64.exe` / `VC_redist.x86.exe`** — The Visual C++ Redistributables are prerequisites. If not already installed on the target machine, these must be installed first.

**Not needed:**

- `cobolserver_110x64.msi` / `.msm` — These are for embedding COBOL Server in custom application installers (InstallShield, WiX). We install COBOL Server directly via `cs_110.exe`.
- `NetworkDeploy_*.bat` — Legacy interactive scripts for sharing the COBOL Server directory over the network. Not relevant for our automated installation.

### SDK Merge Modules — When to Use

From the Deployment Toolkit documentation:

| Application Type | Required Merge Modules |
|------------------|----------------------|
| Native COBOL (our case) | `cobolserver_core_*.msm` only |
| .NET COBOL | `cobolserver_core_*.msm` + `cobolserver_net_*.msm` |
| JVM COBOL / CTF | Full `cobolserver_*.msm` |

**For our use case** (native COBOL recompilation and execution): We install `cs_110.exe` directly, which includes everything. The SDK merge modules are only needed if packaging for distribution.

---

## 4. License Configuration

### License File

The license ZIP (`AMC-COBS-LT-100-11.0.0-VCPU-670000127709.zip`) contains two XML files:

| File | License Type |
|------|-------------|
| `COBOL-Server-SOA-Server-vCPU-RPv1.xml` | COBOL Server — SOA Server vCPU license |
| `COBOL-Server-SOA-Docker-Server-vCPU-RPv1.xml` | COBOL Server — SOA Docker Server vCPU license |

**Key license properties** (from the XML):

| Property | Value |
|----------|-------|
| Capacity | 45 vCPU |
| Validity | Temporary |
| Creation | 2026-02-13 |
| Expiration | **2027-12-17** |
| IP Lock | `*.*.*.*` (any IP) |
| Order ID | 1016403 |

### Do We Need a Separate License Manager Install?

**No.** The `cs_110.exe` installer **includes the License Manager automatically** (confirmed by manual install on t-no1fkmvct-app, 2026-03-10). The SDK's `lmsetupx64.msi` is only needed when deploying COBOL Server via merge modules (`.msm`) in custom application installers.

The Deployment Toolkit documentation states:

> *"License Manager is only provided as installer packages (.msi) and must be supplied separately where you are using the COBOL Server merge modules."*

This means: separate MSI only when using merge modules. The standalone `cs_110.exe` bundles it.

### License Manager Installation

The License Manager MSI is inside the Deployment SDK:

```powershell
# Silent install (from SDK documentation):
msiexec /qn /i lmsetupx64.msi

# With no SafeNet (if another Rocket product already has SafeNet):
msiexec /qn /i lmsetupx64.msi NOSAFENET=1

# Install to a specific license server IP:
msiexec /qn /i lmsetupx64.msi NOSAFENET=<ServerIPAddress>
```

### License Activation (Silent)

After License Manager is installed:

```powershell
# Using cesadmintool.exe for silent activation:
cesadmintool.exe -term install -f "path\to\COBOL-Server-SOA-Server-vCPU-RPv1.xml"
```

The `cesadmintool.exe` is installed by the License Manager at:
- `C:\Program Files (x86)\Rocket Software\License Manager\cesadmintool.exe`
- Or: `C:\Program Files (x86)\Micro Focus\Licensing\cesadmintool.exe` (legacy path)

---

## 5. Complete Installation Order

**Updated after manual install on t-no1fkmvct-app (2026-03-10):**
- `cs_110.exe` **installs the License Manager automatically** — no separate `lmsetupx64.msi` needed.
- The license ZIP must be **unzipped before** starting License Administration.
- Install path observed: `C:\Program Files (x86)\Rocket Software\COBOL Server\`

| Step | Component | Installer | Arguments |
|:----:|-----------|-----------|-----------|
| 0 | **Uninstall existing Rocket/MF software** | `Get-Package` + `msiexec /x` | `/qn` |
| 1 | VC++ Redist x64 | `VC_redist.x64.exe` (from SDK) | `/quiet /norestart` |
| 2 | VC++ Redist x86 | `VC_redist.x86.exe` (from SDK) | `/quiet /norestart` |
| 3 | **COBOL Server 11.0 base** (includes License Manager) | `cs_110.exe` | `/quiet` |
| 4 | **License activation** (unzip first!) | `cesadmintool.exe` | `-term install -f <xml>` |
| 5 | **COBOL Server 11.0 Patch 3** | `cs_110_pu03_390812.exe` | `/quiet` |

**Total install time estimate:** 15-25 minutes (depending on server I/O speed).

**Exit code 3010** means "success, reboot required" — this is normal for runtime installations and should be treated as success.

---

## 6. What We Do NOT Need

| Component | Reason |
|-----------|--------|
| `csx64_110.exe` | We use `cs_110.exe` (32+64 bit) instead |
| `csx64_110_pu03_390812.exe` | Same — the non-x64 patch covers both |
| `cobolserver_110x64.msi` | Only for MSI-based repackaging (we install directly) |
| `cobolserver_110x64.msm` | Only for merge into custom installers |
| `lmsetupx64.msi` | License Manager is bundled with `cs_110.exe` |
| `NetworkDeploy_*.bat` | Interactive legacy scripts for network shares |
| `license_manager_321310.zip` (988 MB) | License Manager comes with `cs_110.exe` |
| `license_manager_321350.zip` (992 MB) | Same |

---

## 7. Post-Installation Verification

After installation, verify all required executables. The base path may be either
`C:\Program Files (x86)\Rocket Software\COBOL Server\` (observed on t-no1fkmvct-app)
or `C:\Program Files (x86)\Rocket Software\Visual COBOL\`.

```powershell
$base = 'C:\Program Files (x86)\Rocket Software\COBOL Server'

# Compilation
Test-Path "$base\bin\cobol.exe"      # 32-bit compiler
Test-Path "$base\bin64\cobol.exe"    # 64-bit compiler

# Runtime executors
Test-Path "$base\bin\run.exe"        # Console runtime
Test-Path "$base\bin\runw.exe"       # Windowed runtime
Test-Path "$base\bin64\run.exe"
Test-Path "$base\bin64\runw.exe"
Test-Path "$base\bin\cobrun.exe"     # Intermediate code runner

# Data File Editor
Test-Path "$base\bin\dswin.exe"

# License Manager
Test-Path 'C:\Program Files (x86)\Rocket Software\License Manager\cesadmintool.exe'

# Check license status
& 'C:\Program Files (x86)\Rocket Software\License Manager\cesadmintool.exe' -term list
```

---

## 8. Automated Install Script

An automated installation script has been created:

```
DevTools/LegacyCodeTools/VisualCobol/Install-RocketCobolServer.ps1
```

It performs all 7 steps (extract SDK, install VC++ Redist, install base, install License Manager, activate license, install patch, verify). Run as Administrator.

**RAG Sources used:** Installing Visual COBOL Build Tools for Windows.md, COBOL_Server_Deployment_Toolkit.html, To buy and activate a full license.md, Visual COBOL Editions and Activating Licenses.md, Continuous Integration Development Tools.md, Want to deploy an application.md (all from Rocket-Visual-Cobol-Documentation-Version-11).
