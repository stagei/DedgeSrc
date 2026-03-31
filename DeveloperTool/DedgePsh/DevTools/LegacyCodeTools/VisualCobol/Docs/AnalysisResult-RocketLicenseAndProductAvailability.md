# Rocket Software — License vs Download Availability Analysis

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Customer:** Dedge AS  
**Order ID:** 1016403

**Support Case:** 01158531 — [Licensed products missing from download portal, Visual Studio compatibility, and portal access](https://my.rocketsoftware.com/RocketCommunity/s/case/500Vx00000nRIj7IAG/licensed-products-missing-from-download-portal-visual-studio-compatibility-and-portal-access)

---

## 1. License Inventory — Two Separate SKUs

Dedge holds **two license packages** under the same Order ID (1016403):

| # | SKU | Ordered Product | Serial | UOM | Capacity | Expiration |
|:-:|-----|----------------|--------|-----|:--------:|:----------:|
| 1 | `AMC-COBS-LT-100` | Rocket COBOL Server for Windows Subscription License | 670000127709 | vCPU | **45 vCPU** | 2027-12-17 |
| 2 | `AMC-VCDR-LT-100` | Rocket Visual COBOL Developer Subscription License | 670000127708 | Named User | **11 users** | 2027-12-17 |

---

## 2. Products Available for Download (Rocket Portal)

From the Rocket Electronic Product Delivery portal, the following products are listed:

| # | Portal Product | Available for Download? |
|:-:|----------------|:----------------------:|
| 1 | **COBOL Server** | Yes |
| 2 | Open AppDev for Z | Yes |
| 3 | Reflection | Yes |
| 4 | Visual COBOL Development Hub | Yes |
| 5 | Visual COBOL Visual Studio | Yes |
| 6 | Visual COBOL for Eclipse | Yes |

### NOT listed in the download portal:

| Product | Available? | Licensed? | Needed? |
|---------|:----------:|:---------:|:-------:|
| **Visual COBOL Build Tools for Windows** (`vcbt_110.exe`) | **No** | **YES** (see section 3) | **YES** |

---

## 3. License File Details — AMC-VCDR-LT-100 (Developer License)

The developer license ZIP (`AMC-VCDR-LT-100-11.0.0-Named User-670000127708`) contains **5 XML files** covering **5 distinct product license groups**:

### 3.1 Visual-COBOL-Eclipse-Named-User-RPv1.xml

**License Group:** `Visual-COBOL-Eclipse-Named-User-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 1 | IMTK-Development | 11 Named Users |
| 2 | SOADevelopment | 11 Named Users |
| 3 | SolarJVMRuntime | 11 Named Users |
| 4 | SolarLocalProject | 11 Named Users |
| 5 | SolarManagedChecker | 11 Named Users |
| 6 | SolarNativeChecker | 11 Named Users |
| 7 | SolarNativeRuntime | 11 Named Users |

**Covers:** Visual COBOL for Eclipse IDE — compile, debug, run COBOL natively and on JVM.

### 3.2 Visual-COBOL-Visual-Studio-Named-User-RPv1.xml

**License Group:** `Visual-COBOL-Visual-Studio-Named-User-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 1 | IMTK-Development | 11 Named Users |
| 2 | SOADevelopment | 11 Named Users |
| 3 | SolarManagedChecker | 11 Named Users |
| 4 | SolarNativeChecker | 11 Named Users |
| 5 | SolarNativeRuntime | 11 Named Users |
| 6 | SolarVisualStudio2010 | 11 Named Users |

**Covers:** Visual COBOL for Visual Studio — compile, debug, run COBOL inside Visual Studio IDE. Includes the compiler (`cobol.exe`).

### 3.3 Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml

**License Group:** `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 1 | IMTK-DevelopmentDocker | 11 Named Users |
| 2 | ManagedCheckerDocker | 11 Named Users |
| 3 | NativeCheckerDocker | 11 Named Users |
| 4 | NativeRuntimeDocker | 11 Named Users |
| 5 | SOADevelopmentDocker | 11 Named Users |

**Covers:** Visual COBOL Build Tools for Windows (+ Docker). This is the headless compiler product (`vcbt_110.exe`) — compile COBOL without IDE overhead. Includes `cobol.exe`.

### 3.4 Visual-COBOL-Development-Hub-RPv1.xml

**License Group:** `Visual-COBOL-Development-Hub-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 1 | IMTK-Development | 11 Named Users |
| 2 | SOADevelopment | 11 Named Users |
| 3 | SolarJVMRuntime | 11 Named Users |
| 4 | SolarManagedChecker | 11 Named Users |
| 5 | SolarNativeChecker | 11 Named Users |
| 6 | SolarNativeRuntime | 11 Named Users |

**Covers:** Visual COBOL Development Hub — server-side COBOL development environment (Linux/UNIX).

### 3.5 Visual-COBOL-Development-Hub-Docker-RPv1.xml

**License Group:** `Visual-COBOL-Development-Hub-Docker-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 1 | IMTK-DevelopmentDocker | 11 Named Users |
| 2 | ManagedCheckerDocker | 11 Named Users |
| 3 | NativeCheckerDocker | 11 Named Users |
| 4 | NativeRuntimeDocker | 11 Named Users |
| 5 | SOADevelopmentDocker | 11 Named Users |
| 6 | JVMRuntimeDocker | 11 Named Users |

**Covers:** Visual COBOL Development Hub Docker variant.

---

## 4. License File Details — AMC-COBS-LT-100 (COBOL Server)

The COBOL Server license ZIP (`AMC-COBS-LT-100-11.0.0-VCPU-670000127709`) contains **2 XML files**:

### 4.1 COBOL-Server-SOA-Server-vCPU-RPv1.xml

**License Group:** `COBOL-Server-SOA-Server-vCPU-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 1 | IMTK-Runtime | 45 vCPU |
| 2 | SOADevelopment | 45 vCPU |
| 3 | SolarNativeRuntimeDeploy | 45 vCPU |

### 4.2 COBOL-Server-SOA-Docker-Server-vCPU-RPv1.xml

**License Group:** `COBOL-Server-SOA-Docker-Server-vCPU-RPv1`

| # | Description | Capacity |
|:-:|-------------|:--------:|
| 4 | SOADevelopmentDocker | 45 vCPU |
| 5 | IMTK-RuntimeDocker | 45 vCPU |
| 6 | NativeRuntimeDployDocker | 45 vCPU |

**Covers:** COBOL Server runtime only — `run.exe`, `runw.exe`, `dswin.exe`, Enterprise Server, IMTK. Does NOT include the compiler.

---

## 5. License Entry Descriptions Explained

Based on RAG documentation (Visual COBOL version 11, sources: Product Overview.md, Continuous Integration Development Tools.md, Interface Mapping Toolkit, Licensing Considerations.md):

| License Description | What It Enables |
|---------------------|----------------|
| `SolarNativeRuntime` / `SolarNativeRuntimeDeploy` / `NativeRuntimeDocker` | Native COBOL runtime — execute compiled `.int`, `.gnt`, `.exe`, `.dll` |
| `SolarManagedChecker` / `ManagedCheckerDocker` | .NET managed code compilation and syntax checking |
| `SolarNativeChecker` / `NativeCheckerDocker` | Native COBOL compilation and syntax checking (`cobol.exe`) |
| `SolarLocalProject` | Local project/workspace support in IDE |
| `SolarJVMRuntime` / `JVMRuntimeDocker` | JVM COBOL runtime — compile and run COBOL on JVM |
| `SolarVisualStudio2010` | Visual Studio integration (IDE shell, project system) |
| `SOADevelopment` / `SOADevelopmentDocker` | Enterprise Server SOA features — CICS, JCL, Web Services, regions, ESCWA |
| `IMTK-Development` / `IMTK-DevelopmentDocker` | Interface Mapping Toolkit — expose COBOL as SOAP/JSON/YAML services |
| `IMTK-Runtime` / `IMTK-RuntimeDocker` | IMTK runtime (server-side service hosting only) |
| `JVMRuntimeDocker` | JVM COBOL runtime in Docker containers |

### What Does "SOA" Mean in the License Files?

The term **"SOA"** (Service-Oriented Architecture) in the license file names and groups (e.g. `COBOL-Server-SOA-Server-vCPU-RPv1`) refers to the **Enterprise Server** feature set within COBOL Server. It is **not a separate product** — it is a capability tier of COBOL Server.

When the COBOL Server license includes SOA entries, it enables:

| Feature | Description |
|---------|------------|
| **Enterprise Server regions** | CICS and JCL-compatible transaction processing environments on Windows |
| **ESCWA** | Enterprise Server Common Web Administration — browser-based management console |
| **Web Services hosting** | Expose COBOL programs as SOAP, JSON, or YAML services |
| **IMTK (Interface Mapping Toolkit)** | Map COBOL program interfaces to service definitions |
| **Service deployment** | Deploy COBOL applications as managed services under Enterprise Server |

Without the SOA entries, COBOL Server would only provide the base native runtime (`run.exe`, `runw.exe`, `dswin.exe`). With SOA, it becomes a full application server capable of hosting COBOL-based services.

**Both our license packages include SOA:**
- **AMC-COBS-LT-100** (COBOL Server, 45 vCPU) — `COBOL-Server-SOA-Server-vCPU-RPv1` and Docker variant
- **AMC-VCDR-LT-100** (Developer, 11 users) — `SOADevelopment` entries in all 5 developer license files

---

## 6. Product-to-License Mapping — What We Should Have vs What We Can Download

| Product | License Group in XML | Licensed? | In Download Portal? | Has Compiler? | Status |
|---------|---------------------|:---------:|:-------------------:|:------------:|:------:|
| **Visual COBOL for Visual Studio** | Visual-COBOL-Visual-Studio-Named-User-RPv1 | Yes (11 users) | Yes | Yes | OK |
| **Visual COBOL for Eclipse** | Visual-COBOL-Eclipse-Named-User-RPv1 | Yes (11 users) | Yes | Yes | OK |
| **Visual COBOL Build Tools** | Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1 | **Yes (11 users)** | **NO** | **Yes** | **MISSING** |
| **Visual COBOL Development Hub** | Visual-COBOL-Development-Hub-RPv1 | Yes (11 users) | Yes | Yes (Linux) | OK |
| **Development Hub Docker** | Visual-COBOL-Development-Hub-Docker-RPv1 | Yes (11 users) | Yes | Yes (Linux) | OK |
| **COBOL Server** | COBOL-Server-SOA-Server-vCPU-RPv1 | Yes (45 vCPU) | Yes | No | OK |
| Open AppDev for Z | — | ? | Yes | — | Not needed |
| Reflection | — | ? | Yes | — | Not needed |

---

## 7. The Critical Finding

### We ARE licensed for Visual COBOL Build Tools — but it is NOT available for download

The license file `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml` explicitly contains a license group named `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1` with 5 license entries for 11 Named Users, under the product **"Rocket Visual COBOL Developer Subscription License"** (SKU `AMC-VCDR-LT-100`).

This means:
- **We have paid for and are licensed to use** Visual COBOL Build Tools for Windows
- **Rocket's download portal does not list Build Tools** as a downloadable product
- The installer (`vcbt_110.exe` / `vcbtx64_110.exe`) is needed to install the compiler on build/CI servers without requiring the full Visual Studio IDE

### What Visual COBOL Build Tools provides (from RAG docs)

> *"Visual COBOL Build Tools for Windows is a separately-installable component of Visual COBOL that has been designed to be used in environments where you want to work with your COBOL projects but you don't want the overheads associated with the Visual Studio IDE."*

- Available in two variants: standard (32+64-bit) and 64-bit only
- Includes the compiler (`cobol.exe`) — both 32-bit and 64-bit
- Supports MSBuild for CI/CD pipeline integration
- Can coexist with COBOL Server on the same machine
- Cannot coexist with Visual COBOL IDE on the same machine
- License requirement: same as Visual COBOL IDE (which we have: AMC-VCDR-LT-100)

---

## 8. Support Case — Visual COBOL Build Tools and Portal Access

### Subject: Licensed Products Missing from Download Portal, Visual Studio Compatibility, and Portal Access

### Support Case Text

---

Dear Rocket Software Support,

**Customer:** Dedge AS  
**Order ID:** 1016403  
**Serials:** 670000127708 (Developer), 670000127709 (COBOL Server)

We are writing regarding three issues with our Visual COBOL 11.0 subscription.

#### Issue 1: Licensed Products Missing from Download Portal

We hold two license packages under Order ID 1016403:

| SKU | Product | Serial | Capacity |
|-----|---------|--------|:--------:|
| AMC-VCDR-LT-100 | Rocket Visual COBOL Developer Subscription License | 670000127708 | 11 Named Users |
| AMC-COBS-LT-100 | Rocket COBOL Server for Windows Subscription License | 670000127709 | 45 vCPU |

Our developer license ZIP (`AMC-VCDR-LT-100-11.0.0-Named User-670000127708`) contains **5 XML license files** covering the following product license groups:

| License XML File | License Group |
|------------------|---------------|
| `Visual-COBOL-Visual-Studio-Named-User-RPv1.xml` | Visual-COBOL-Visual-Studio-Named-User-RPv1 |
| `Visual-COBOL-Eclipse-Named-User-RPv1.xml` | Visual-COBOL-Eclipse-Named-User-RPv1 |
| `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml` | Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1 |
| `Visual-COBOL-Development-Hub-RPv1.xml` | Visual-COBOL-Development-Hub-RPv1 |
| `Visual-COBOL-Development-Hub-Docker-RPv1.xml` | Visual-COBOL-Development-Hub-Docker-RPv1 |

However, the Rocket Electronic Product Delivery portal currently only lists **6 products** for download:

1. COBOL Server
2. Open AppDev for Z
3. Reflection
4. Visual COBOL Development Hub
5. Visual COBOL Visual Studio
6. Visual COBOL for Eclipse

The following licensed products are **missing from the download portal**:

| Licensed Product | License XML Proof | Available in Portal? |
|-----------------|-------------------|:--------------------:|
| **Visual COBOL Build Tools for Windows** | `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml` | **NO** |

The Build Tools license file contains 5 explicit license entries (IMTK-DevelopmentDocker, ManagedCheckerDocker, NativeCheckerDocker, NativeRuntimeDocker, SOADevelopmentDocker) for 11 Named Users.

**Request:** Please make the following available for download under our order:

- `vcbt_110.exe` — Visual COBOL Build Tools for Windows 11.0 (32+64-bit)
- `vcbtx64_110.exe` — Visual COBOL Build Tools for Windows 11.0 (64-bit only)
- The corresponding Patch 3 update for Build Tools

We need Build Tools to compile COBOL on our Windows build/CI servers without installing the full Visual Studio IDE. According to Rocket documentation, Build Tools is a separately-installable component designed for exactly this purpose, and it requires the same license as the Visual COBOL IDE products — which we hold (AMC-VCDR-LT-100).

Additionally, please confirm that we have access to download the **full version + Patch 3 update** for all of the following products — not just the ones currently visible in the portal:

| Product | Installer (Full) | Installer (Patch 3) | Status |
|---------|-------------------|---------------------|:------:|
| Visual COBOL for Visual Studio | `vcvs2022_110.exe` | Patch 3 update | Visible in portal |
| Visual COBOL for Eclipse | `vceclipse_110.exe` | Patch 3 update | Visible in portal |
| **Visual COBOL Build Tools** | **`vcbt_110.exe`** | **Patch 3 update** | **NOT in portal** |
| Visual COBOL Development Hub | — | — | Visible in portal |
| COBOL Server | `cs_110.exe` | Patch 3 update | Visible in portal |

#### Issue 2: Visual Studio Edition Compatibility

Our development machines currently run **Microsoft Visual Studio Community 2026** (GA November 2025). Starting with Visual Studio 2026, Microsoft has moved to an in-place update model and no longer recommends running multiple major versions side-by-side. Installing an older Visual Studio version (such as VS 2022) alongside VS 2026 is not a supported configuration going forward.

Downgrading to Visual Studio 2022 — a product that is now over four years old — should not be necessary to use Visual COBOL for Visual Studio 11.0. Previous versions of Visual COBOL (under Micro Focus) required Visual Studio Professional or Enterprise edition.

We need clarification on the following:

1. Is **Visual COBOL for Visual Studio 11.0** compatible with **Visual Studio Community 2026**?
2. If not yet supported, when is Visual Studio 2026 support planned?
3. Is **Visual Studio Community Edition** a supported edition, or does Visual COBOL require Professional or Enterprise?

#### Issue 3: Windows Server 2025 Not Listed as Supported Operating System

When filing this support case, the "Operating System" field only lists MS Windows 2012, 2016, 2019, and 2022. **Windows Server 2025 is not available as an option.** Our servers are running or being migrated to Windows Server 2025, which has been generally available since November 2024.

1. Is **Visual COBOL 11.0 / COBOL Server 11.0** supported on **Windows Server 2025**?
2. If not yet supported, when is Windows Server 2025 support planned?
3. Please update the support portal form to include Windows Server 2025 as a selectable operating system.

#### Issue 4: Download Portal and License Access for Team Members

Please ensure that both product downloads and license files are accessible to the following email addresses in the Rocket Electronic Product Delivery portal:

- **geir.helge.starholm@Dedge.no**
- **svein.morten.erikstad@Dedge.no**

Both users are active developers who need access to download installers and license files for **all products** under Order ID 1016403 (both AMC-VCDR-LT-100 and AMC-COBS-LT-100).

Thank you for your assistance.

Best regards,  
Geir Helge Starholm  
Dedge AS  
geir.helge.starholm@Dedge.no

---

---

## 9. Complete License File Inventory

### Source files analyzed:

| # | File | SKU | License Group |
|:-:|------|-----|---------------|
| 1 | `COBOL-Server-SOA-Server-vCPU-RPv1.xml` | AMC-COBS-LT-100 | COBOL-Server-SOA-Server-vCPU-RPv1 |
| 2 | `COBOL-Server-SOA-Docker-Server-vCPU-RPv1.xml` | AMC-COBS-LT-100 | COBOL-Server-SOA-Docker-Server-vCPU-RPv1 |
| 3 | `Visual-COBOL-Eclipse-Named-User-RPv1.xml` | AMC-VCDR-LT-100 | Visual-COBOL-Eclipse-Named-User-RPv1 |
| 4 | `Visual-COBOL-Visual-Studio-Named-User-RPv1.xml` | AMC-VCDR-LT-100 | Visual-COBOL-Visual-Studio-Named-User-RPv1 |
| 5 | `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml` | AMC-VCDR-LT-100 | Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1 |
| 6 | `Visual-COBOL-Development-Hub-Docker-RPv1.xml` | AMC-VCDR-LT-100 | Visual-COBOL-Development-Hub-Docker-RPv1 |
| 7 | `Visual-COBOL-Development-Hub-RPv1.xml` | AMC-VCDR-LT-100 | Visual-COBOL-Development-Hub-RPv1 |

**Total license entries:** 7 files, 43 individual license entries (across both SKUs)

---

## RAG Sources

| Source | Used For |
|--------|----------|
| Product Overview.md | COBOL Server vs Visual COBOL relationship |
| Visual COBOL Build Tools for Windows.md | Build Tools description and variants |
| Installing Visual COBOL Build Tools for Windows.md | Installer names (`vcbt_110.exe`, `vcbtx64_110.exe`) |
| Licensing Considerations.md | Build Tools requires same license as IDE |
| Restrictions when Using Visual COBOL Build Tools for Windows 11.0.md | Coexistence rules |
| Continuous Integration Development Tools.md | COBOL Server and CI feature descriptions |
| Interface Mapping Toolkit (IMTK).md | IMTK license entry explanation |

All sources from: Rocket-Visual-Cobol-Documentation-Version-11 (RAG MCP: user-visual-cobol-docs)
