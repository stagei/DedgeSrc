# Web Sites — From Code to Live Website in One Command

## What These Tools Do

Imagine you are a restaurant chain opening a new location. You need the dining area (the website), the kitchen (the backend API), the login system (authentication), the security cameras (logging), and the menu with photos (an icon browser). For each location, someone has to install the kitchen equipment, connect the gas lines, set up the point-of-sale system, configure the security system, and make sure the health inspector approves everything.

Now imagine doing that for every restaurant — the same setup, verified the same way, every single time, without forgetting a single step.

The Web Sites tools are that installation crew. They handle deploying web applications to IIS (Internet Information Services — Microsoft's web server), setting up databases, configuring authentication, and managing the infrastructure that keeps web applications running. Four tool groups cover the complete lifecycle from empty server to live, authenticated, monitored web application.

## Overview Diagram

```mermaid
graph TB
    subgraph "Application Source"
        A1[.NET API Projects<br/>C# Web Applications]
        A2[Static HTML/CSS/JS<br/>Documentation Sites]
    end

    subgraph "Web Sites Tools"
        B[IIS-DeployApp<br/>Universal IIS Deployer]
        C[DedgeAuth<br/>Authentication Platform]
        D[GenericLogHandler<br/>Centralized Logging API]
        E[IconBrowser<br/>Icon Library Reference]
    end

    subgraph "Infrastructure"
        F[IIS Web Server<br/>Default Web Site]
        G[PostgreSQL Database<br/>Auth + Log Storage]
        H[SSL Certificates<br/>HTTPS Security]
    end

    subgraph "Live Applications"
        I[/DedgeAuth<br/>Login Portal]
        J[/GenericLogHandler<br/>Log API]
        K[/AutoDoc<br/>Documentation]
        L[/IconBrowser<br/>Icon Reference]
        M[/YourApp<br/>Any Application]
    end

    A1 --> B
    A2 --> B
    B --> F
    C --> G
    D --> G
    B -->|Deploy| I
    B -->|Deploy| J
    B -->|Deploy| K
    B -->|Deploy| L
    B -->|Deploy| M
    C -->|Manages| I
    D -->|Manages| J
```

## Tool-by-Tool Guide

### IIS-DeployApp — Universal web application deployer

The flagship deployment tool. Give it an application name and it handles everything: tearing down any previous installation, deploying files, creating IIS application pools, creating virtual applications, generating web.config, setting permissions, starting the app, and verifying it responds to health checks.

Supports two application types:
- **AspNetCore** — .NET web applications hosted in-process via the ASP.NET Core Module (always running, no idle timeout)
- **Static** — HTML/CSS/JS files served directly by IIS (with optional directory browsing)

Three installation sources:
- **WinApp** — Deploys from the DedgeWinApps repository (compiled .NET applications)
- **PshApp** — Deploys from the DedgePshApps repository (PowerShell-based applications)
- **None** — Uses existing files at a specified path (for pre-built content like AutoDoc)

Key features:
- **Profile-based deployment** — JSON templates define each application's configuration. Run with no parameters to see a menu of available profiles and pick one interactively.
- **Full teardown + recreate** — Every deployment is clean. No leftover configuration from previous versions.
- **Root site protection** — The DefaultWebSite profile bootstraps the root site with a redirect page. No other profile can deploy to the root path.
- **Health verification** — For AspNetCore apps, hits the /health endpoint after deployment to confirm the app is running.
- **Anonymous access control** — Can enable public access or enforce Windows Authentication per application.

Supporting scripts:
- **IIS-RedeployAll** — Redeploys every application from all profiles in one operation
- **Install-IIS-Prerequisites** — Installs IIS, ASP.NET Core Hosting Bundle, and URL Rewrite module
- **New-IISSslCertificate** — Creates and binds SSL certificates for HTTPS
- **Remove-DefaultWebSite** — Cleans up the default IIS site before custom deployment
- **Test-AllApps** — Verifies every deployed application responds correctly
- **Test-IISSite** — Tests a single site's availability
- **Show-DeployPorts** — Lists all port assignments across deployed applications
- **IIS-UninstallApp** — Cleanly removes a single application and its pool
- **Export-FolderPermissions** — Documents NTFS permissions for audit compliance

Think of IIS-DeployApp as a general contractor who builds out any type of restaurant (fast food, fine dining, café) from the same set of blueprints, and then inspects the work before handing over the keys.

**Who needs it:** Any organization deploying .NET web applications or static sites to IIS. Particularly valuable for teams managing multiple applications on shared web servers.

**Can it be sold standalone?** Yes — high standalone value. "One-command IIS deployment with profiles" is a significant productivity tool. The profile-based approach makes it reusable across any application. Could be a core product offering.

---

### DedgeAuth — Complete authentication platform setup

DedgeAuth is a multi-tenant authentication service. The Web Sites tools include everything needed to set up and manage it:

**DedgeAuth-DatabaseSetup** — Sets up the PostgreSQL database for DedgeAuth:
- Detects existing PostgreSQL installation or installs it
- Creates the DedgeAuth database if it does not exist
- Configures local PostgreSQL settings (port, listen addresses, pg_hba rules, firewall)
- Optionally updates appsettings.json with connection strings and generates JWT secrets

**DedgeAuth-AddAppSupport** — Interactive wizard to register new applications:
- Point it at a source project folder and it auto-detects everything: project type (ASP.NET Core or Static), DLL name, API port, server name, and roles
- Scans for appsettings.json and lets you choose which one to configure
- Presents a verification screen where every auto-detected value can be overridden
- Executes: database registration, .deploy.json profile generation, configuration deployment
- Supports non-interactive mode for automation

**DedgeAuth-RemoveAppSupport** — Removes an application's registration from DedgeAuth

**Database management scripts** — Backup, restore, and configuration tools for the DedgeAuth PostgreSQL database

Think of DedgeAuth as the identity management system for the entire restaurant chain. Every new location (application) gets registered, assigned access cards (tokens), and connected to the central security system.

**Who needs it:** Organizations deploying multiple web applications that need centralized authentication with multi-tenancy, role-based access, and JWT tokens.

**Can it be sold standalone?** Yes — very high standalone value. "Self-hosted multi-tenant authentication service" competes with Auth0, Keycloak, and Azure AD B2C. The setup automation (wizard, auto-detection, database provisioning) is a significant differentiator.

---

### GenericLogHandler — Centralized logging API with database backend

A web API that collects and stores log entries from all applications in a PostgreSQL database. The setup tools handle:

**GenericLogHandler-DatabaseSetup** — Creates the PostgreSQL database:
- Safe to run alongside existing databases (DedgeAuth, etc.)
- Detects or installs PostgreSQL
- Configures connection strings in appsettings.json
- Handles firewall rules and PostgreSQL authentication

**Database management scripts** — Backup, restore, repair, and configuration tools

Think of it as the security camera system for the restaurant chain — every location sends its footage to one central monitoring room where everything can be reviewed, searched, and archived.

**Who needs it:** Organizations needing centralized application logging across multiple services. Especially valuable when combined with DedgeAuth to correlate authentication events with application activity.

**Can it be sold standalone?** Moderate — centralized logging APIs compete with Seq, Application Insights, and ELK. The value is in the tight integration with the deployment pipeline and DedgeAuth.

---

### IconBrowser — Visual reference for free icon libraries

A beautifully designed HTML application that lets developers browse, search, and preview icons from five major free icon libraries:
- **Font Awesome 6.6** — The industry standard
- **Bootstrap Icons 1.11** — Bootstrap ecosystem
- **Material Symbols** — Google's design system
- **Remix Icon 4.3** — Clean, modern icons
- **Tabler Icons 3.11** — Developer-focused

The browser includes live preview, search, and the exact CDN import code you need to add each library to your project. Deployed as a static IIS application.

Think of it as a paint chip display at a hardware store — you can see every available color (icon) and get the exact product code to order it.

**Who needs it:** Frontend developers and designers choosing icons for web applications.

**Can it be sold standalone?** No — reference tool. But it adds polish to the overall developer experience and demonstrates the static site deployment capability.

---

## Revenue Potential

| Revenue Tier | Tools | Est. Annual Value |
|---|---|---|
| **High — Core Product** | IIS-DeployApp | $150K–$400K as "IIS Deployment Manager" product |
| **High — Platform** | DedgeAuth (full platform) | $200K–$500K as self-hosted auth service |
| **Medium — Integration** | GenericLogHandler | $50K–$100K as logging add-on |
| **Bundle** | All 4 as "Web Application Platform" | $400K–$1M per enterprise deployment |
| **Recurring** | Managed service (deploy + auth + logging) | $10K–$30K/month per customer |

The Web Sites tools have the highest revenue potential of any category because they form a complete platform: deploy any application, authenticate its users, and collect its logs — all managed through PowerShell automation.

## What Makes This Special

1. **Profile-driven deployment eliminates human error** — Every application's configuration is stored as a JSON template. Deploying is just picking a profile from a menu. No manual IIS configuration, no missed steps, no "works on one server but not the other."

2. **Full teardown + recreate guarantees consistency** — IIS-DeployApp never patches an existing installation. It removes everything and rebuilds from scratch. This means the 100th deployment is identical to the 1st. Configuration drift is impossible.

3. **DedgeAuth wizard auto-detects everything** — Point AddAppSupport at a project folder and it finds the project type, DLL, port, roles, and settings files automatically. The developer just confirms or adjusts. This reduces a 30-minute manual setup to a 2-minute wizard.

4. **PostgreSQL provisioning included** — Both DedgeAuth and GenericLogHandler automatically detect, install, configure, and provision PostgreSQL databases. The setup scripts handle everything from downloading PostgreSQL to creating databases to configuring firewall rules. Zero manual database administration required.

5. **Composition, not monolith** — Every application is a virtual application under the Default Web Site. Deploying one never breaks another. No port conflicts, no binding removals, no shared state. This architecture is fundamentally more reliable than per-site IIS deployments.
