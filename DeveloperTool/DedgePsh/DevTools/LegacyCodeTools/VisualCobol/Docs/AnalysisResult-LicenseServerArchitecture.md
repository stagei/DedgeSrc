# Visual COBOL 11.0 — License Server Architecture Analysis

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Customer:** Dedge AS  
**Order ID:** 1016403  
**Related:** [License & Product Availability Analysis](AnalysisResult-RocketLicenseAndProductAvailability.md)  
**Support Case:** 01158531

---

## 1. Executive Summary

**A centralized license server is NOT required.** Local (per-machine) licensing is fully supported and is the simplest approach for Dedge's setup. However, a centralized license server (RocketPass) is an *option* that provides usage tracking and floating license management — it may become relevant as the team grows.

---

## 2. How Visual COBOL 11.0 Licensing Works

Visual COBOL 11.0 uses **Rocket Software RocketPass License Server Technology** (rebranded from AutoPass in version 11.0). RocketPass supports AutoPass-era licenses.

The licensing system supports **two modes**:

| Mode | How It Works | License Server Required? |
|------|-------------|:------------------------:|
| **Local (per-machine)** | License XML file is imported directly on each machine via Rocket License Administration (`cesadmintool.exe`) or the IDE dialog. The license is stored locally. | **No** |
| **Centralized (network)** | A standalone RocketPass License Server runs on a dedicated machine. Products on other machines connect to this server to check out licenses at runtime. | **Yes** (separate install) |

The key sentence from the official documentation:

> *"To manage your product licenses you need to use Rocket License Administration. The tool allows you to authorize, view and revoke licenses. You can set up your license locally or **request a license from a central license server (if your site is using one)**."*
>
> — Source: Visual COBOL Editions and Activating Licenses.md (RAG: user-visual-cobol-docs)

This confirms that the centralized server is **optional** — "if your site is using one."

---

## 3. Our License Inventory

| SKU | Product | License Model | Capacity | What Gets Licensed |
|-----|---------|:------------:|:--------:|-------------------|
| `AMC-VCDR-LT-100` | Visual COBOL Developer Subscription | **Named User** | 11 users | Developer machines (IDE, Build Tools) |
| `AMC-COBS-LT-100` | COBOL Server for Windows Subscription | **vCPU** | 45 vCPU | Application servers (runtime) |

### Named User (Developer License)

- Licensed per **individual developer** — not per machine, not floating.
- Each named user can install on multiple machines (e.g., desktop + laptop), but the license tracks the *person*, not the *seat*.
- 11 named users means up to 11 developers can use the compiler tools.
- Products covered: Visual COBOL for VS, Visual COBOL for Eclipse, Build Tools, Development Hub.

### vCPU (Server License)

- Licensed per **virtual CPU core** on the server running COBOL Server.
- 45 vCPU is the total pool across all servers.
- Each server where COBOL Server is installed consumes vCPUs from this pool.
- The license XML has `IpAddress = "*.*.*.*"` — it is not IP-locked.

---

## 4. Local Licensing — How It Works (Recommended)

### On Developer Machines (Named User)

1. Install Visual COBOL for Visual Studio (or Build Tools) on the machine.
2. The installer automatically includes the License Manager.
3. Import the appropriate license XML via one of:
   - **IDE:** Help > Visual COBOL Product Help > Product Licensing > Browse to `.xml` file > Authorize
   - **CLI:** `cesadmintool.exe -term install -f "path\to\Visual-COBOL-Visual-Studio-Named-User-RPv1.xml"`
4. License is stored locally. No network connection to a license server needed at runtime.

### On Application Servers (vCPU)

1. Install COBOL Server (`cs_110.exe`) on the server.
2. The installer automatically includes the License Manager.
3. Import the license XML:
   - `cesadmintool.exe -term install -f "path\to\COBOL-Server-SOA-Server-vCPU-RPv1.xml"`
4. License is stored locally. COBOL Server runtime checks the local license at startup.

### Advantages of Local Licensing

| Advantage | Detail |
|-----------|--------|
| **Simplicity** | No additional infrastructure to maintain |
| **No single point of failure** | Each machine has its own license — no dependency on a license server |
| **Offline capable** | Machines work without network connectivity to a license server |
| **Fast to set up** | Import XML, done |
| **Our license allows it** | `IpAddress = "*.*.*.*"` — not IP-locked |

### What to Watch Out For

| Concern | Mitigation |
|---------|-----------|
| **Named User tracking** | With local licensing, Rocket trusts the customer to manage named user count. Keep a registry of which developers have installed licenses. |
| **vCPU count** | Each server install consumes vCPUs. Track total vCPU usage across all servers to stay within 45 vCPU. |
| **License expiration** | Licenses expire 2027-12-17. Set a calendar reminder for renewal ~60 days before. |
| **License file distribution** | Store license XMLs in a secure, backed-up location (not in git). Distribute to machines during install scripts. |

---

## 5. Centralized License Server (RocketPass) — Optional

### What It Is

RocketPass (formerly AutoPass) is a web-based license server that can be installed on a dedicated machine. Products on other machines connect to it to check out licenses dynamically.

### Features

| Feature | Description |
|---------|------------|
| **Floating licenses** | Licenses are checked out at runtime and returned when no longer needed |
| **Usage tracking** | Captures hourly license consumption statistics per user and machine |
| **Usage reports** | Pre-defined and custom reports showing concurrent users, machine cores |
| **Central management** | Single dashboard to view, install, and revoke all licenses |
| **License reservation** | Reserve licenses for specific users or machines |
| **License borrowing** | Users can "borrow" a license for disconnected work |

### When a Central Server Makes Sense

| Scenario | Recommendation |
|----------|---------------|
| **< 15 developers, < 5 servers** | Local licensing is fine |
| **> 15 developers, shared pool** | Consider centralized for better tracking |
| **Strict compliance audit requirements** | Centralized provides usage logs |
| **Docker/container deployments at scale** | Centralized helps manage dynamic workloads |
| **Frequent onboarding/offboarding** | Centralized simplifies license reassignment |

### Setup Requirements (if needed later)

1. Install RocketPass License Server on a dedicated Windows or Linux machine
2. Import all license XMLs into the central server
3. Configure each product machine to point to the central server URL
4. The `cesadmintool.exe` can configure the server address

### Known Issues

- AutoPass error logs can output continuously every minute when Enterprise Server's `mfds` service runs, consuming disk space (documented issue in versions 7.0–9.0, check if resolved in 11.0).
- License coexistence: Installing 11.0 on machines with older Rocket/Micro Focus products using SafeNet Sentinel or AutoPass licensing may cause compatibility issues. See "Licensing Coexistence when Upgrading to Release 11.0" in the installation documentation.

---

## 6. Licensing Technology History

Understanding the evolution helps avoid confusion with older documentation:

| Era | Technology | Version Range |
|-----|-----------|--------------|
| Legacy (Micro Focus) | **SafeNet Sentinel** | Visual COBOL 1.0 – 5.x |
| Transition (Micro Focus → Rocket) | **AutoPass** | Visual COBOL 6.0 – 10.0 |
| Current (Rocket Software) | **RocketPass** (rebranded AutoPass) | Visual COBOL 11.0+ |

> *"AutoPass has been rebranded as Rocket Software RocketPass License Server Technology. RocketPass supports AutoPass licenses."*
>
> — Source: New Features in 11.0.md (RAG: user-visual-cobol-docs)

RocketPass is backward compatible with AutoPass licenses, but **not with SafeNet Sentinel** licenses. If upgrading from a very old Visual COBOL version, new license files are needed.

---

## 7. Recommendation for Dedge

### Phase 1: Now (Test Pipeline)

**Use local licensing on each machine.**

| Machine | Product | License File |
|---------|---------|-------------|
| Developer machines (up to 11) | Visual COBOL for VS | `Visual-COBOL-Visual-Studio-Named-User-RPv1.xml` |
| `t-no1fkmvct-app` (test) | COBOL Server | `COBOL-Server-SOA-Server-vCPU-RPv1.xml` |
| Build server (when Build Tools available) | Build Tools | `Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml` |

### Phase 2: Production Rollout (Future)

When rolling out to production servers:
- **Still use local licensing** unless the number of servers grows beyond easy manual tracking
- Track vCPU consumption in a simple spreadsheet or config file
- Consider RocketPass only if audit/compliance requirements demand it

### Phase 3: At Scale (If Needed)

If the organization grows to 20+ developers or 10+ COBOL Server instances:
- Evaluate installing a RocketPass License Server
- Migrate from local to centralized licensing
- This is a non-breaking change — licenses can be moved from local to central

---

## 8. License File Storage and Distribution

### Recommended Secure Storage

```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\VisualCobol\Licenses\
├── AMC-VCDR-LT-100\
│   ├── Visual-COBOL-Visual-Studio-Named-User-RPv1.xml
│   ├── Visual-COBOL-Eclipse-Named-User-RPv1.xml
│   ├── Visual-COBOL-Build-Tools-Docker-Windows-Named-User-RPv1.xml
│   ├── Visual-COBOL-Development-Hub-RPv1.xml
│   └── Visual-COBOL-Development-Hub-Docker-RPv1.xml
├── AMC-COBS-LT-100\
│   ├── COBOL-Server-SOA-Server-vCPU-RPv1.xml
│   └── COBOL-Server-SOA-Docker-Server-vCPU-RPv1.xml
└── README.txt    (expiration date, order ID, contact info)
```

### Do NOT Store In

- Git repositories (license files are sensitive)
- Individual user profiles (hard to update centrally)
- Temp folders (risk of accidental deletion)

### Automated Installation

The `Install-RocketCobolServer.ps1` script already handles license import for COBOL Server. Similar automation should be created for developer machine setup.

---

## 9. Named User Registry

Since Named User licenses are trust-based (Rocket does not enforce a specific tracking mechanism), maintain a simple registry:

| # | User | Email | Product Installed | Machine(s) | Date Activated |
|:-:|------|-------|------------------|------------|:--------------:|
| 1 | Geir Helge Starholm | geir.helge.starholm@Dedge.no | Visual COBOL for VS | 30237-FK | 2026-03-xx |
| 2 | Svein Morten Erikstad | svein.morten.erikstad@Dedge.no | Visual COBOL for VS | TBD | TBD |
| ... | ... | ... | ... | ... | ... |

**Capacity:** 11 named users. Update this registry whenever a new developer is onboarded.

---

## RAG Sources

| Source | Used For |
|--------|----------|
| Visual COBOL Editions and Activating Licenses.md | Local vs central licensing model |
| New Features in 11.0.md | RocketPass rebranding from AutoPass |
| Significant Changes in Behavior or Usage.md | Licensing coexistence warnings |
| To buy and activate a full license.md | License activation procedures |
| Managing Licenses.md | License management overview |
| Setup and Licensing.md | Setup and licensing section reference |

All sources from: Rocket-Visual-Cobol-Documentation-Version-11 (RAG MCP: user-visual-cobol-docs)

### Web Sources

| Source | Used For |
|--------|----------|
| [Rocket Forum: Visual COBOL 11.0 released](https://community.rocketsoftware.com/product-updates/visual-cobol-11-0-released-27315) | Release confirmation |
| [AutoPass License Server (Micro Focus docs)](https://marketplace.microfocus.com/itom/content/autopass-license-server) | Central server feature description |
| [Rocket Additional Licensing Terms](https://www.rocketsoftware.com/additional-licensing-terms) | Server license definition (per-machine, 30-day reassignment) |
