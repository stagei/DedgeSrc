# DedgeAuth - Centralized Authentication Service

DedgeAuth is a centralized JWT-based authentication service for Dedge applications.

## Features

- **Multi-application support**: Single auth service for multiple applications
- **Per-app role management**: Users can have different roles per application
- **Multi-tenancy**: Domain-based tenant configuration with custom branding
- **JWT authentication**: Secure token-based authentication
- **Magic link login**: Passwordless email-based authentication
- **Flexible hosting**: Run as process or Windows Service on port 8100

## Architecture

```
DedgeAuth Solution
├── DedgeAuth.Core         - Models, interfaces, configurations
├── DedgeAuth.Data         - PostgreSQL DbContext, migrations
├── DedgeAuth.Services     - AuthService, JwtTokenService, DatabaseSeeder
├── DedgeAuth.Api          - REST API, controllers, login UI
└── DedgeAuth.Client       - Client library for consumer applications
```

## Quick Start

### 1. Install PostgreSQL
```powershell
winget install -e --id PostgreSQL.PostgreSQL
```

### 2. Setup Database
```powershell
.\scripts\Setup-Database.ps1 -ConfigureAppSettings
```

This creates the `DedgeAuth` database and configures `appsettings.json` with connection string and JWT secret.

### 3. Build and Run
```powershell
.\Build-And-Publish.ps1
```

This builds, publishes, starts DedgeAuth.Api, and opens the login page in your browser.

### 4. Verify Installation
```powershell
Invoke-WebRequest http://localhost:8100/health
```

## Configuration

### appsettings.json
```json
{
  "ConnectionStrings": {
    "AuthDb": "Host=t-no1fkxtst-db;Database=DedgeAuth;Username=postgres;Password=postgres"
  },
  "AuthConfiguration": {
    "JwtSecret": "your-secure-secret-key",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps",
    "AllowedDomain": "Dedge.no",
    "AdminEmails": ["admin@Dedge.no"]
  }
}
```

## Integration

### Add DedgeAuth.Client to your application

1. Reference the DedgeAuth.Client project
2. Configure in Program.cs:

```csharp
builder.Services.AddDedgeAuth(options =>
{
    options.AuthServerUrl = "http://localhost:8100";
    options.JwtSecret = "your-jwt-secret";
    options.JwtIssuer = "DedgeAuth";
    options.JwtAudience = "FKApps";
    options.AppId = "YourAppId";
});
```

3. Use `[RequireAppPermission]` attribute on controllers:

```csharp
[RequireAppPermission("Admin", "PowerUser")]
public IActionResult AdminEndpoint() { }

[RequireAppPermission("User")]
public IActionResult UserEndpoint() { }
```

## API Endpoints

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login with password
- `POST /api/auth/request-login` - Request magic link
- `GET /api/auth/verify` - Verify magic link
- `POST /api/auth/refresh` - Refresh access token
- `GET /api/auth/me` - Get current user

### Applications
- `GET /api/apps` - List applications
- `POST /api/apps` - Register application (admin)

### Permissions
- `GET /api/permissions/user/{userId}` - Get user permissions
- `POST /api/permissions` - Grant permission (admin)

### Tenants
- `GET /api/tenants` - List tenants
- `GET /api/tenants/by-domain/{domain}` - Get tenant by domain

## Database Schema

- `users` - User accounts
- `apps` - Registered applications
- `app_permissions` - User-App-Role mappings
- `tenants` - Tenant configurations
- `login_tokens` - Magic link tokens
- `refresh_tokens` - Session tokens

## License

Internal use only - Dedge
