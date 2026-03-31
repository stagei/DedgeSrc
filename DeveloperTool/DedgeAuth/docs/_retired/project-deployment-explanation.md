# Project Deployment Explanation

This document explains how the different projects in the DedgeAuth solution are deployed and which ones are included when you publish `DedgeAuth.Api`.

## Project Structure

The DedgeAuth solution contains 5 projects:

```
DedgeAuth Solution
├── DedgeAuth.Core         - Models, interfaces, configurations
├── DedgeAuth.Data         - PostgreSQL DbContext, migrations
├── DedgeAuth.Services     - AuthService, JwtTokenService, DatabaseSeeder
├── DedgeAuth.Api          - REST API, controllers, login UI (MAIN DEPLOYABLE)
└── DedgeAuth.Client       - Client library for consumer applications
```

## Dependency Chain

```
DedgeAuth.Api
├── References: DedgeAuth.Core
├── References: DedgeAuth.Data
└── References: DedgeAuth.Services
    ├── References: DedgeAuth.Core
    └── References: DedgeAuth.Data
        └── References: DedgeAuth.Core

DedgeAuth.Client (SEPARATE - not referenced by Api)
└── References: DedgeAuth.Core
```

## What Gets Deployed with DedgeAuth.Api?

When you publish `DedgeAuth.Api` using Visual Studio or the publish profiles, **the following projects are automatically included**:

### ✅ Automatically Included (via Project References)

1. **DedgeAuth.Core.dll**
   - Models (User, Tenant, App, etc.)
   - Configuration classes
   - **Included because**: Referenced by Api, Data, and Services

2. **DedgeAuth.Data.dll**
   - AuthDbContext
   - Entity Framework migrations
   - **Included because**: Referenced by Api and Services

3. **DedgeAuth.Services.dll**
   - AuthService
   - JwtTokenService
   - EmailService
   - DatabaseSeeder
   - **Included because**: Referenced by Api

### ❌ NOT Included

4. **DedgeAuth.Client**
   - **NOT included** because it's not referenced by `DedgeAuth.Api`
   - **Purpose**: This is a library for OTHER applications that want to integrate with DedgeAuth
   - **Deployment**: Deployed separately as a NuGet package or referenced by client applications

## How .NET Publishing Works

When you publish `DedgeAuth.Api`:

1. **Build Process**:
   - Visual Studio builds `DedgeAuth.Api` and all its project references
   - Transitive dependencies are automatically resolved
   - All referenced projects are compiled to DLLs

2. **Publish Output**:
   - The publish folder contains:
     ```
     DedgeAuth.Api.dll          (main application)
     DedgeAuth.Core.dll         (automatically included)
     DedgeAuth.Data.dll         (automatically included)
     DedgeAuth.Services.dll     (automatically included)
     appsettings.json
     wwwroot/                    (static files)
     [NuGet package DLLs]        (dependencies like EF Core, etc.)
     ```

3. **No Separate Deployment Needed**:
   - You don't need to deploy Core, Data, or Services separately
   - They're bundled with the Api project automatically
   - The publish process handles all dependencies

## DedgeAuth.Client - Separate Deployment

`DedgeAuth.Client` is **NOT deployed with the API**. It's a separate library:

### Purpose
- Used by **other applications** that want to authenticate users via DedgeAuth
- Provides authentication middleware and authorization handlers
- Allows client apps to integrate with DedgeAuth without implementing JWT validation themselves

### Deployment Options

1. **As a NuGet Package** (Recommended for multiple consumers):
   ```powershell
   # Build and pack the client library
   dotnet pack src\DedgeAuth.Client\DedgeAuth.Client.csproj -c Release
   ```

2. **As a Project Reference** (For local development):
   ```xml
   <ProjectReference Include="..\..\DedgeAuth\src\DedgeAuth.Client\DedgeAuth.Client.csproj" />
   ```

3. **As a DLL** (Copy the compiled DLL):
   - Build the Client project separately
   - Copy `DedgeAuth.Client.dll` and `DedgeAuth.Core.dll` to consuming applications

### Example: Using DedgeAuth.Client in Another App

```csharp
// In another application's Program.cs
using DedgeAuth.Client.Extensions;

var builder = WebApplication.CreateBuilder(args);

// Add DedgeAuth authentication
builder.Services.AddDedgeAuth(builder.Configuration);
```

See [Client Integration Guide](../docs/integration/client-integration.md) for details.

## Summary

| Project | Included in Api Deploy? | How? | Separate Deploy Needed? |
|---------|------------------------|------|------------------------|
| **DedgeAuth.Core** | ✅ Yes | Project reference | ❌ No |
| **DedgeAuth.Data** | ✅ Yes | Project reference | ❌ No |
| **DedgeAuth.Services** | ✅ Yes | Project reference | ❌ No |
| **DedgeAuth.Api** | ✅ Yes | Main project | ❌ No |
| **DedgeAuth.Client** | ❌ No | Not referenced | ✅ Yes (for client apps) |

## Conclusion

**When deploying DedgeAuth.Api:**
- ✅ Just publish `DedgeAuth.Api` - everything else is included automatically
- ✅ No need to deploy Core, Data, or Services separately
- ✅ All dependencies are resolved and bundled during publish

**DedgeAuth.Client:**
- ❌ Not included in Api deployment
- ✅ Deploy separately only if you have other applications that need to integrate with DedgeAuth
- ✅ Typically distributed as a NuGet package or project reference

## Verification

After publishing, you can verify what was included:

1. Navigate to the publish output folder
2. Look for these DLLs:
   - `DedgeAuth.Api.dll` ✅
   - `DedgeAuth.Core.dll` ✅
   - `DedgeAuth.Data.dll` ✅
   - `DedgeAuth.Services.dll` ✅
   - `DedgeAuth.Client.dll` ❌ (should NOT be present)

All required dependencies are automatically included by the .NET build system!
