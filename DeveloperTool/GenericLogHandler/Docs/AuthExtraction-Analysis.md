# Authentication System Extraction Analysis

## Executive Summary

The GenericLogHandler authentication system is a comprehensive, custom JWT-based solution that **can be extracted** into a standalone authentication service. This document analyzes the current architecture, extraction complexity, and multi-application integration strategy.

---

## Current Security Architecture

### Where is Security Enforced?

**Security is enforced at the BACKEND (API endpoints)**, not the frontend. The frontend only provides UX conveniences.

| Layer | Security Role |
|-------|---------------|
| **Backend (API)** | **Primary enforcement** - JWT validation, policy-based authorization, token refresh |
| **Frontend (JS)** | **UX only** - Token storage, redirect to login, hide/show UI elements |

```mermaid
flowchart TB
    subgraph Frontend["Frontend (UX Only)"]
        UI[Web UI]
        LS[localStorage<br/>accessToken]
        API_JS[api.js<br/>Auth Helper]
    end
    
    subgraph Backend["Backend (Security Enforcement)"]
        MW[JWT Middleware]
        POL[Authorization Policies]
        CTRL[Controllers]
        SVC[AuthService]
        DB[(Database)]
    end
    
    UI -->|"Bearer Token"| MW
    MW -->|"Validate JWT"| POL
    POL -->|"Check AccessLevel"| CTRL
    CTRL --> SVC
    SVC --> DB
    
    LS -.->|"Stored Token"| API_JS
    API_JS -.->|"Add Header"| UI
    
    style Backend fill:#c8e6c9
    style Frontend fill:#fff3e0
```

### Current Auth Components

| File | Purpose |
|------|---------|
| `Core/Models/Auth/User.cs` | User entity with AccessLevel enum |
| `Core/Models/Auth/LoginToken.cs` | Magic links, password reset tokens |
| `Core/Models/Auth/RefreshToken.cs` | Session refresh tokens |
| `Core/Models/Auth/AuthConfiguration.cs` | JWT settings, rules |
| `WebApi/Services/AuthService.cs` | All auth business logic |
| `WebApi/Services/AuthEmailService.cs` | Email sending |
| `WebApi/Controllers/AuthController.cs` | Auth API endpoints |
| `Data/LoggingDbContext.cs` | User, LoginToken, RefreshToken DbSets |
| `wwwroot/login.html` | Login UI |
| `wwwroot/js/api.js` | Frontend token management |

### Authorization Policies

```mermaid
graph LR
    subgraph Policies
        RO[ReadOnlyAccess<br/>Level >= 0]
        U[UserAccess<br/>Level >= 1]
        PU[PowerUserAccess<br/>Level >= 2]
        A[AdminAccess<br/>Level == 3]
    end
    
    RO --> U --> PU --> A
    
    style RO fill:#e3f2fd
    style U fill:#bbdefb
    style PU fill:#90caf9
    style A fill:#42a5f5
```

---

## Extraction Feasibility

### Complexity Assessment: **MODERATE**

| Aspect | Complexity | Notes |
|--------|------------|-------|
| Code separation | Low | Auth code is well-isolated in Services + Controllers |
| Database schema | Low | 3 tables (users, login_tokens, refresh_tokens) easily separable |
| Configuration | Low | `AuthConfiguration` is self-contained |
| JWT integration | Low | Standard JWT Bearer, easy to share signing key |
| Multi-app support | Moderate | Requires shared token validation, centralized user store |
| Frontend reuse | Low | `login.html` + `api.js` auth functions are portable |

### What Needs Extraction

```mermaid
flowchart TB
    subgraph Extract["New Project: DedgeAuth"]
        subgraph Core["DedgeAuth.Core"]
            M1[User Model]
            M2[LoginToken Model]
            M3[RefreshToken Model]
            M4[AuthConfiguration]
            I1[IAuthService]
        end
        
        subgraph Data["DedgeAuth.Data"]
            CTX[AuthDbContext]
            MIG[Migrations]
        end
        
        subgraph API["DedgeAuth.Api"]
            AC[AuthController]
            AS[AuthService]
            AE[AuthEmailService]
        end
        
        subgraph UI["DedgeAuth.UI (optional)"]
            LH[login.html]
            AJS[auth.js]
        end
    end
    
    Core --> Data
    Core --> API
    API --> UI
```

---

## Multi-Application Architecture

### Option 1: Centralized Auth Service (Recommended)

A standalone authentication microservice that all applications use.

```mermaid
flowchart TB
    subgraph Clients
        GLH[GenericLogHandler<br/>:5000]
        SMD[ServerMonitorDashboard<br/>:8998]
        APP3[Future App<br/>:XXXX]
    end
    
    subgraph AuthService["DedgeAuth Service (:8100)"]
        AUTH_API[Auth API<br/>/api/auth/*]
        AUTH_DB[(Auth Database)]
        AUTH_UI[Login UI<br/>/login]
    end
    
    GLH -->|"Validate JWT"| AUTH_API
    SMD -->|"Validate JWT"| AUTH_API
    APP3 -->|"Validate JWT"| AUTH_API
    
    GLH -.->|"Redirect"| AUTH_UI
    SMD -.->|"Redirect"| AUTH_UI
    APP3 -.->|"Redirect"| AUTH_UI
    
    AUTH_API --> AUTH_DB
```

#### Authentication Flow

```mermaid
sequenceDiagram
    participant User
    participant App as Client App<br/>(GLH/SMD)
    participant Auth as DedgeAuth Service
    participant DB as Auth DB
    
    User->>App: Access protected resource
    App->>App: Check for valid JWT
    alt No valid token
        App-->>User: Redirect to Auth Service
        User->>Auth: Login (magic link/password)
        Auth->>DB: Validate credentials
        DB-->>Auth: User data
        Auth->>Auth: Generate JWT + Refresh Token
        Auth-->>User: Redirect back with token
        User->>App: Request with JWT
    end
    App->>App: Validate JWT locally<br/>(shared signing key)
    App-->>User: Protected resource
```

#### Key Benefits
- **Single user database** - Users register once, access all apps
- **Centralized management** - Admin UI in one place
- **Consistent security** - Same policies everywhere
- **Easy onboarding** - New apps just add JWT validation

#### Client App Integration

Each client app needs minimal code:

```csharp
// Program.cs in any client app
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidIssuer = "DedgeAuth",
            ValidAudience = "FKApps",  // or specific app
            IssuerSigningKey = new SymmetricSecurityKey(sharedKey)
        };
    });

// Add same authorization policies
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("PowerUserAccess", policy =>
        policy.RequireClaim("accessLevel", "2", "3"));
});
```

### Option 2: Shared Library (Simpler, Less Ideal)

Each app embeds the auth library but uses a shared database.

```mermaid
flowchart TB
    subgraph SharedDB["Shared Auth Database"]
        DB[(users<br/>login_tokens<br/>refresh_tokens)]
    end
    
    subgraph GLH["GenericLogHandler"]
        GLH_REF[DedgeAuth.Core<br/>DedgeAuth.Data<br/>DedgeAuth.Services]
        GLH_AUTH[/api/auth/*]
    end
    
    subgraph SMD["ServerMonitorDashboard"]
        SMD_REF[DedgeAuth.Core<br/>DedgeAuth.Data<br/>DedgeAuth.Services]
        SMD_AUTH[/api/auth/*]
    end
    
    GLH_REF --> DB
    SMD_REF --> DB
```

#### Drawbacks
- Duplicate auth endpoints in each app
- Code updates require redeploying all apps
- More complex versioning

---

## ServerMonitorDashboard Integration

### Current State
- No authentication (anonymous access)
- ASP.NET Core 10 Web API + static UI
- Port 8998

### Integration Steps

```mermaid
flowchart LR
    subgraph Before
        SMD1[ServerMonitorDashboard<br/>No Auth]
    end
    
    subgraph After
        SMD2[ServerMonitorDashboard]
        AUTH[DedgeAuth Service]
        SMD2 -->|"JWT Validation"| AUTH
    end
    
    Before --> After
```

1. **Add NuGet packages**: `Microsoft.AspNetCore.Authentication.JwtBearer`
2. **Configure JWT validation** in `Program.cs` (shared signing key with DedgeAuth)
3. **Add authorization policies** (same as GenericLogHandler)
4. **Add `[Authorize]` attributes** to controllers
5. **Update frontend** to use DedgeAuth login or embed auth.js

### Minimal Code Changes for SMD

| File | Change |
|------|--------|
| `Program.cs` | Add JWT authentication + policies (~30 lines) |
| `Controllers/*.cs` | Add `[Authorize(Policy = "...")]` attributes |
| `wwwroot/js/*.js` | Add token handling from api.js |
| `appsettings.json` | Add auth configuration section |

---

## Proposed Project Structure

```
C:\opt\src\DedgeAuth\
├── DedgeAuth.sln
├── src\
│   ├── DedgeAuth.Core\                    # Models, interfaces
│   │   ├── Models\
│   │   │   ├── User.cs
│   │   │   ├── LoginToken.cs
│   │   │   ├── RefreshToken.cs
│   │   │   └── AuthConfiguration.cs
│   │   └── Interfaces\
│   │       └── IAuthService.cs
│   │
│   ├── DedgeAuth.Data\                    # Database context, migrations
│   │   ├── AuthDbContext.cs
│   │   └── Migrations\
│   │
│   ├── DedgeAuth.Services\                # Shared services (can be used by client apps)
│   │   ├── AuthService.cs
│   │   ├── AuthEmailService.cs
│   │   └── JwtTokenService.cs
│   │
│   ├── DedgeAuth.Api\                     # Standalone auth service
│   │   ├── Controllers\
│   │   │   └── AuthController.cs
│   │   ├── Program.cs
│   │   └── wwwroot\
│   │       ├── login.html
│   │       └── js\
│   │           └── auth.js
│   │
│   └── DedgeAuth.Client\                  # NuGet package for client apps
│       ├── Extensions\
│       │   └── AuthServiceCollectionExtensions.cs
│       └── Middleware\
│           └── JwtValidationMiddleware.cs
```

---

## Implementation Roadmap

### Phase 1: Extract (Estimated: 2-3 hours)
- [ ] Create DedgeAuth solution structure
- [ ] Move auth models to DedgeAuth.Core
- [ ] Move DbContext tables to DedgeAuth.Data
- [ ] Move AuthService to DedgeAuth.Services
- [ ] Create DedgeAuth.Api with auth endpoints

### Phase 2: Integrate GenericLogHandler (Estimated: 1 hour)
- [ ] Add DedgeAuth.Client reference
- [ ] Update Program.cs to use DedgeAuth
- [ ] Remove embedded auth code (keep as fallback option)
- [ ] Test all auth flows

### Phase 3: Integrate ServerMonitorDashboard (Estimated: 1-2 hours)
- [ ] Add JWT authentication to Program.cs
- [ ] Add authorization policies
- [ ] Add `[Authorize]` attributes to controllers
- [ ] Add frontend token handling
- [ ] Test protected endpoints

### Phase 4: Polish (Estimated: 1 hour)
- [ ] Create DedgeAuth.Client NuGet package
- [ ] Add configuration documentation
- [ ] Create admin scripts

---

## Database & Deployment

### Database: PostgreSQL

DedgeAuth will use **PostgreSQL** (same as GenericLogHandler) for consistency and reliability.

#### Database Schema

```mermaid
erDiagram
    users {
        uuid id PK
        string email UK
        string display_name
        string password_hash
        int access_level
        string department
        bool email_verified
        bool is_locked
        int failed_login_attempts
        datetime locked_until
        datetime created_at
        datetime updated_at
        datetime last_login_at
    }
    
    login_tokens {
        uuid id PK
        uuid user_id FK
        string token UK
        string token_type
        datetime expires_at
        bool is_used
        string ip_address
        datetime created_at
    }
    
    refresh_tokens {
        uuid id PK
        uuid user_id FK
        string token UK
        datetime expires_at
        bool is_revoked
        string ip_address
        string user_agent
        datetime created_at
    }
    
    users ||--o{ login_tokens : has
    users ||--o{ refresh_tokens : has
```

### Automated Setup Script

The DedgeAuth project will include a self-sufficient setup script that:

1. Detects or installs PostgreSQL
2. Creates the database
3. Runs migrations
4. Seeds default admin users
5. Configures and starts the service

```powershell
# Install-DedgeAuth.ps1 - Self-sufficient setup script

param(
    [string]$InstallPath = "C:\opt\apps\DedgeAuth",
    [int]$Port = 8100,
    [ValidateSet("Service", "IIS", "Kestrel")]
    [string]$HostingMode = "Service"
)

# --- PostgreSQL Detection/Installation ---

function Get-PostgresPath {
    # 1. Check if psql is in PATH
    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if ($psql) { return Split-Path $psql.Source -Parent }
    
    # 2. Check common installation paths
    $commonPaths = @(
        "C:\Program Files\PostgreSQL\18\bin",
        "C:\Program Files\PostgreSQL\17\bin",
        "C:\Program Files\PostgreSQL\16\bin"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path "$path\psql.exe") { return $path }
    }
    
    # 3. Ask user or install via winget
    $choice = Read-Host "PostgreSQL not found. [I]nstall via winget, or [P]rovide path?"
    if ($choice -eq 'I') {
        Write-Host "Installing PostgreSQL via winget..."
        winget install PostgreSQL.PostgreSQL.18 --accept-package-agreements
        return "C:\Program Files\PostgreSQL\18\bin"
    } else {
        return Read-Host "Enter path to PostgreSQL bin folder"
    }
}

$pgBin = Get-PostgresPath
$env:PATH = "$pgBin;$env:PATH"

# --- Database Creation ---

$dbName = "DedgeAuth"
$dbUser = "DedgeAuth_app"
$dbPassword = [System.Guid]::NewGuid().ToString("N").Substring(0, 16)

Write-Host "Creating database '$dbName'..."
psql -U postgres -c "CREATE DATABASE $dbName;" 2>$null
psql -U postgres -c "CREATE USER $dbUser WITH PASSWORD '$dbPassword';"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $dbName TO $dbUser;"

# --- Run EF Migrations ---

Write-Host "Running database migrations..."
dotnet ef database update --project "$InstallPath\DedgeAuth.Api"

# --- Seed Default Admins ---

# Configured in appsettings.json - seeded on first startup
# AdminEmails: ["geir.helge.starholm@Dedge.no", "svein.morten.erikstad@Dedge.no"]
```

### Default Admin Configuration

```json
// DedgeAuth appsettings.json
{
  "ConnectionStrings": {
    "AuthDb": "Host=localhost;Database=DedgeAuth;Username=DedgeAuth_app;Password=<generated>"
  },
  "AuthConfiguration": {
    "AdminEmails": [
      "geir.helge.starholm@Dedge.no",
      "svein.morten.erikstad@Dedge.no"
    ],
    "AllowedDomain": "Dedge.no",
    "JwtSecret": "<auto-generated-on-first-run>",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps",
    "AccessTokenExpiryMinutes": 30,
    "RefreshTokenExpiryDays": 7
  }
}
```

### First-Run Seeding Logic

```csharp
// DedgeAuth.Api/Services/DatabaseSeeder.cs
public class DatabaseSeeder
{
    public async Task SeedAsync(AuthDbContext db, IOptions<AuthConfiguration> config)
    {
        // Create admin users if they don't exist
        foreach (var email in config.Value.AdminEmails)
        {
            if (!await db.Users.AnyAsync(u => u.Email == email))
            {
                var user = new User
                {
                    Email = email,
                    DisplayName = email.Split('@')[0].Replace(".", " "),
                    AccessLevel = AccessLevel.Admin,
                    EmailVerified = true,  // Pre-verified for admins
                    CreatedAt = DateTime.UtcNow
                };
                db.Users.Add(user);
                
                // Send welcome email with password setup link
                await _emailService.SendPasswordSetupEmail(user);
            }
        }
        await db.SaveChangesAsync();
    }
}
```

---

## Hosting Options Comparison

### Option 1: Windows Service (Recommended for DedgeAuth)

```mermaid
flowchart TB
    subgraph Server["Windows Server"]
        SVC[DedgeAuth.exe<br/>Windows Service]
        KESTREL[Kestrel<br/>:8100]
        SVC --> KESTREL
    end
    
    CLIENT[Client Apps] -->|"HTTP/HTTPS"| KESTREL
```

| Aspect | Windows Service |
|--------|-----------------|
| **Startup** | Automatic on boot |
| **Reliability** | Auto-restart on failure |
| **Management** | `sc.exe`, Services MMC, PowerShell |
| **Port binding** | Direct Kestrel |
| **SSL/TLS** | Kestrel certificate or reverse proxy |
| **Complexity** | Low |
| **Best for** | Internal services, microservices |

**Installation:**

```powershell
# Create Windows Service
sc.exe create DedgeAuth binPath="C:\opt\apps\DedgeAuth\DedgeAuth.Api.exe" start=auto
sc.exe description DedgeAuth "FK Authentication Service"
sc.exe start DedgeAuth
```

**Program.cs configuration:**

```csharp
var builder = WebApplication.CreateBuilder(args);

// Support running as Windows Service
builder.Host.UseWindowsService(options =>
{
    options.ServiceName = "DedgeAuth";
});

builder.WebHost.UseUrls("http://*:8100", "https://*:5051");
```

### Option 2: IIS Hosted

```mermaid
flowchart TB
    subgraph Server["Windows Server + IIS"]
        IIS[IIS]
        POOL[App Pool<br/>DedgeAuth]
        APP[DedgeAuth.Api.dll]
        IIS --> POOL --> APP
    end
    
    CLIENT[Client Apps] -->|"HTTP/HTTPS"| IIS
```

| Aspect | IIS |
|--------|-----|
| **Startup** | IIS manages lifecycle |
| **Reliability** | IIS app pool recycling |
| **Management** | IIS Manager, PowerShell |
| **Port binding** | IIS bindings (80/443 shared) |
| **SSL/TLS** | IIS certificate management |
| **Complexity** | Medium |
| **Best for** | Integration with existing IIS infrastructure |

**Considerations:**
- Requires IIS + ASP.NET Core Hosting Bundle
- Shares port 80/443 with other sites (path-based routing)
- More complex setup but familiar to IIS admins

### Option 3: Standalone Kestrel (Development/Testing)

```mermaid
flowchart TB
    subgraph Dev["Developer Machine"]
        CONSOLE[DedgeAuth.Api.exe<br/>Console App]
        KESTREL[Kestrel<br/>:8100]
        CONSOLE --> KESTREL
    end
    
    BROWSER[Browser] -->|"http://localhost:8100"| KESTREL
```

| Aspect | Standalone Kestrel |
|--------|-------------------|
| **Startup** | Manual or scheduled task |
| **Reliability** | No auto-restart |
| **Management** | Manual process management |
| **Best for** | Development, testing |

---

### Recommendation: Windows Service

For DedgeAuth, **Windows Service** is recommended because:

| Reason | Benefit |
|--------|---------|
| **Always running** | Starts on boot, restarts on failure |
| **Independent** | Doesn't require IIS |
| **Simple** | Single executable, easy to deploy |
| **Consistent** | Same pattern as GenericLogHandler ImportService |
| **Portable** | Same deployment on dev/test/prod |

### Deployment Architecture

```mermaid
flowchart TB
    subgraph Production["Production Server"]
        subgraph Services["Windows Services"]
            DedgeAuth[DedgeAuth Service<br/>:8100]
            GLH_IMP[GLH ImportService]
        end
        
        subgraph IIS["IIS (Optional)"]
            GLH_WEB[GenericLogHandler<br/>:5000]
            SMD[ServerMonitorDashboard<br/>:8998]
        end
        
        PG[(PostgreSQL<br/>:5432)]
    end
    
    DedgeAuth --> PG
    GLH_IMP --> PG
    GLH_WEB --> PG
    
    GLH_WEB -->|"JWT Validation"| DedgeAuth
    SMD -->|"JWT Validation"| DedgeAuth
```

### Complete Install Script Structure

```
C:\opt\src\DedgeAuth\
├── scripts\
│   ├── Install-DedgeAuth.ps1          # Main installer
│   │   ├── Detect/install PostgreSQL (winget)
│   │   ├── Create database + user
│   │   ├── Run EF migrations
│   │   ├── Generate JWT secret
│   │   ├── Create Windows Service
│   │   └── Seed admin users
│   │
│   ├── Uninstall-DedgeAuth.ps1        # Clean removal
│   ├── Update-DedgeAuth.ps1           # In-place upgrade
│   └── Get-DedgeAuthStatus.ps1        # Health check
```

### Install Script Flow

```mermaid
flowchart TB
    START([Install-DedgeAuth.ps1])
    
    PG_CHECK{PostgreSQL<br/>installed?}
    PG_WINGET[winget install PostgreSQL]
    PG_PATH[Add to PATH]
    
    DB_CREATE[Create DedgeAuth database]
    DB_USER[Create DedgeAuth_app user]
    DB_MIGRATE[Run EF migrations]
    
    CONFIG[Generate appsettings.json<br/>- JWT secret<br/>- Connection string<br/>- Admin emails]
    
    HOSTING{Hosting mode?}
    SVC_CREATE[Create Windows Service]
    IIS_CREATE[Create IIS Site + App Pool]
    
    SEED[Start service<br/>Seed admin users]
    
    DONE([Complete])
    
    START --> PG_CHECK
    PG_CHECK -->|No| PG_WINGET --> PG_PATH
    PG_CHECK -->|Yes| PG_PATH
    PG_PATH --> DB_CREATE --> DB_USER --> DB_MIGRATE
    DB_MIGRATE --> CONFIG --> HOSTING
    HOSTING -->|Service| SVC_CREATE --> SEED
    HOSTING -->|IIS| IIS_CREATE --> SEED
    SEED --> DONE
```

---

## Security Considerations

### Token Sharing Security

| Concern | Mitigation |
|---------|------------|
| Shared signing key | Store in secure configuration (not in code) |
| Token scope | Use `audience` claim to restrict tokens to specific apps |
| Token theft | Short access token lifetime (15-30 min) + refresh tokens |
| Cross-app access | Optional: issue app-specific tokens with audience validation |

### Multi-Audience JWT Support

```mermaid
flowchart TB
    subgraph DedgeAuth
        TOKEN[JWT Token<br/>aud: ["GLH", "SMD", "FKApps"]]
    end
    
    subgraph GLH
        V1[Validate<br/>aud contains "GLH" OR "FKApps"]
    end
    
    subgraph SMD
        V2[Validate<br/>aud contains "SMD" OR "FKApps"]
    end
    
    TOKEN --> V1
    TOKEN --> V2
```

---

## Future: Windows AD/SSO Plugin Architecture

### Can AD Authentication Be Added Later?

**Yes.** The proposed DedgeAuth architecture can be designed with a **pluggable authentication provider pattern**, allowing:

1. Custom JWT auth (current implementation)
2. Windows AD/Negotiate SSO (future plugin)
3. Per-application provider selection

### Pluggable Provider Architecture

```mermaid
flowchart TB
    subgraph DedgeAuth["DedgeAuth Service"]
        subgraph Providers["Authentication Providers"]
            JWT[JwtAuthProvider<br/>Magic Link + Password]
            AD[WindowsAdProvider<br/>Negotiate/Kerberos]
            FUTURE[Future Provider<br/>OAuth, SAML, etc.]
        end
        
        RESOLVER[Provider Resolver]
        CONFIG[(App Config<br/>per-app provider)]
        
        RESOLVER --> JWT
        RESOLVER --> AD
        RESOLVER --> FUTURE
        CONFIG --> RESOLVER
    end
    
    subgraph Apps
        GLH[GenericLogHandler<br/>→ JWT Provider]
        SMD[ServerMonitorDashboard<br/>→ AD Provider]
        APP3[Internal App<br/>→ JWT Provider]
        APP4[Domain App<br/>→ AD Provider]
    end
    
    GLH --> RESOLVER
    SMD --> RESOLVER
    APP3 --> RESOLVER
    APP4 --> RESOLVER
```

### Per-Application Provider Configuration

Each client application can specify which auth provider to use:

```json
// DedgeAuth appsettings.json
{
  "AuthProviders": {
    "Default": "Jwt",
    "Applications": {
      "GenericLogHandler": {
        "Provider": "Jwt",
        "AllowedDomains": ["Dedge.no"]
      },
      "ServerMonitorDashboard": {
        "Provider": "WindowsAd",
        "FallbackProvider": "Jwt",
        "AdGroups": {
          "Admin": "FK-IT-Admins",
          "PowerUser": "FK-IT-PowerUsers",
          "User": "FK-IT-Users"
        }
      },
      "ExternalApp": {
        "Provider": "Jwt",
        "RequireEmailVerification": true
      }
    }
  }
}
```

### Windows AD Provider Flow

```mermaid
sequenceDiagram
    participant User
    participant App as Client App<br/>(AD-enabled)
    participant Auth as DedgeAuth Service
    participant AD as Active Directory
    
    User->>App: Access protected resource
    App->>Auth: Request with Negotiate header
    Auth->>Auth: Detect AD-configured app
    Auth->>AD: Validate Windows credentials
    AD-->>Auth: User + Groups
    Auth->>Auth: Map AD groups to AccessLevel
    Auth->>Auth: Generate JWT with claims
    Auth-->>App: JWT Token
    App->>App: Standard JWT validation
    App-->>User: Protected resource
```

### Hybrid Authentication Support

For environments transitioning to AD or with mixed clients:

```mermaid
flowchart TB
    subgraph Client["Client Request"]
        REQ[Request]
    end
    
    subgraph DedgeAuth
        DETECT{Detect Auth<br/>Method}
        
        subgraph ADPath["AD Path (Domain-joined)"]
            NEG[Negotiate Header?]
            AD_VAL[Validate with AD]
            AD_MAP[Map Groups → Roles]
        end
        
        subgraph JWTPath["JWT Path (Non-domain)"]
            JWT_HDR[Bearer Token?]
            JWT_VAL[Validate JWT]
        end
        
        subgraph LoginPath["Login Path (No creds)"]
            LOGIN[Show Login UI]
            CHOOSE{User Choice}
            WIN_BTN[Windows SSO Button]
            PWD_BTN[Email/Password]
        end
        
        ISSUE[Issue JWT]
    end
    
    REQ --> DETECT
    DETECT -->|"Has Negotiate"| NEG
    DETECT -->|"Has Bearer"| JWT_HDR
    DETECT -->|"No Auth"| LOGIN
    
    NEG --> AD_VAL --> AD_MAP --> ISSUE
    JWT_HDR --> JWT_VAL
    LOGIN --> CHOOSE
    CHOOSE --> WIN_BTN --> AD_VAL
    CHOOSE --> PWD_BTN --> JWT_VAL
    
    ISSUE -->|"Return JWT"| Client
```

### Implementation: IAuthenticationProvider Interface

```csharp
// DedgeAuth.Core/Interfaces/IAuthenticationProvider.cs
public interface IAuthenticationProvider
{
    string ProviderName { get; }
    bool CanHandle(HttpContext context, string appId);
    Task<AuthResult> AuthenticateAsync(HttpContext context);
    Task<ClaimsPrincipal?> ValidateTokenAsync(string token);
}

// DedgeAuth.Providers.Jwt/JwtAuthProvider.cs
public class JwtAuthProvider : IAuthenticationProvider
{
    public string ProviderName => "Jwt";
    // Magic link, password, email verification...
}

// DedgeAuth.Providers.WindowsAd/WindowsAdProvider.cs  
public class WindowsAdProvider : IAuthenticationProvider
{
    public string ProviderName => "WindowsAd";
    // Negotiate/Kerberos, AD group mapping...
}
```

### AD Group to AccessLevel Mapping

| AD Group | AccessLevel | Notes |
|----------|-------------|-------|
| `FK-IT-Admins` | Admin (3) | Full access to all apps |
| `FK-IT-PowerUsers` | PowerUser (2) | Configuration access |
| `FK-IT-Users` | User (1) | Standard access |
| `Domain Users` | ReadOnly (0) | View-only access |
| *(no group match)* | Denied | Or fallback to JWT login |

### Benefits of Plugin Architecture

| Benefit | Description |
|---------|-------------|
| **Gradual migration** | Add AD support without breaking existing JWT auth |
| **Per-app flexibility** | Some apps use AD, others use JWT |
| **Fallback support** | AD fails → offer JWT login |
| **Future-proof** | Add OAuth, SAML, etc. later |
| **Consistent output** | All providers issue same JWT format |

### Considerations for Non-AD Clients

For clients not enrolled in Active Directory:

| Scenario | Solution |
|----------|----------|
| External contractors | Use JWT provider with email verification |
| BYOD devices | JWT provider (magic link works everywhere) |
| Linux/Mac workstations | JWT provider or Kerberos (if configured) |
| Mobile devices | JWT provider with password login |
| Mixed environment | Hybrid mode with login UI choice |

### Updated Project Structure with Providers

```
C:\opt\src\DedgeAuth\
├── src\
│   ├── DedgeAuth.Core\
│   │   └── Interfaces\
│   │       └── IAuthenticationProvider.cs    # Provider contract
│   │
│   ├── DedgeAuth.Providers.Jwt\                 # Current implementation
│   │   ├── JwtAuthProvider.cs
│   │   ├── MagicLinkService.cs
│   │   └── PasswordService.cs
│   │
│   ├── DedgeAuth.Providers.WindowsAd\           # Future AD plugin
│   │   ├── WindowsAdProvider.cs
│   │   ├── AdGroupMapper.cs
│   │   └── NegotiateHandler.cs
│   │
│   ├── DedgeAuth.Api\
│   │   ├── Middleware\
│   │   │   └── MultiProviderAuthMiddleware.cs
│   │   └── Configuration\
│   │       └── ProviderConfiguration.cs
```

### Complexity for Adding AD Provider

| Task | Effort | Notes |
|------|--------|-------|
| Create IAuthenticationProvider interface | 1 hour | Already partially exists in AuthService |
| Refactor JwtAuthProvider | 2 hours | Extract from AuthService |
| Implement WindowsAdProvider | 3-4 hours | Negotiate handler + group mapping |
| Multi-provider middleware | 2 hours | Route to correct provider |
| Per-app configuration | 1 hour | Config file + database option |
| **Total** | **9-10 hours** | After initial extraction |

---

## Conclusion

**The extraction is feasible and recommended.** The current auth system is well-structured and can be cleanly separated into a standalone service. The centralized auth service approach (Option 1) provides the best long-term value:

- **Complexity**: Moderate (8-12 hours initial, +9-10 hours for AD plugin)
- **Risk**: Low (no breaking changes if done incrementally)
- **Value**: High (reusable across all FK internal applications)
- **Future-proof**: Pluggable provider architecture supports AD, OAuth, SAML, etc.

### Recommendation

1. Start with **Option 1 (Centralized Auth Service)**
2. Deploy DedgeAuth as a separate service on its own port
3. Design with `IAuthenticationProvider` interface from the start
4. Migrate GenericLogHandler first (already has the code)
5. Then integrate ServerMonitorDashboard (start with JWT, add AD later)
6. Package DedgeAuth.Client as internal NuGet for future apps
7. Add WindowsAdProvider when AD access becomes available for non-domain clients

---

## Appendix: Current File References

### GenericLogHandler Auth Files

```
src/GenericLogHandler.Core/Models/Auth/
├── User.cs                    # User entity with AccessLevel enum
├── LoginToken.cs              # Magic link tokens
├── RefreshToken.cs            # Session tokens
└── AuthConfiguration.cs       # JWT/auth settings

src/GenericLogHandler.WebApi/Services/
├── AuthService.cs             # Core auth logic (~600 lines)
└── AuthEmailService.cs        # Email sending (~150 lines)

src/GenericLogHandler.WebApi/Controllers/
└── AuthController.cs          # Auth endpoints (~400 lines)

src/GenericLogHandler.WebApi/wwwroot/
├── login.html                 # Login UI
└── js/api.js                  # Token handling (Auth helper lines 288-328)

src/GenericLogHandler.Data/
└── LoggingDbContext.cs        # DbSets for User, LoginToken, RefreshToken
```

### ServerMonitorDashboard Files to Modify

```
src/ServerMonitorDashboard/
├── Program.cs                 # Add JWT auth config
├── Controllers/*.cs           # Add [Authorize] attributes
├── appsettings.json           # Add auth section
└── wwwroot/js/*.js            # Add token handling
```
