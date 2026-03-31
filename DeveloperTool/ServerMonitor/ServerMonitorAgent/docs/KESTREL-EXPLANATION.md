# Kestrel Explanation

## What is Kestrel?

**Kestrel** is the **default cross-platform web server** for ASP.NET Core applications. It's the built-in HTTP server that handles incoming HTTP requests.

### Key Points:

1. **Built-in, not a NuGet package**: Kestrel is included automatically when you use the `Microsoft.NET.Sdk.Web` SDK (which your project uses - see line 1 of `ServerMonitor.csproj`)

2. **Part of ASP.NET Core**: When you reference ASP.NET Core packages (like `Microsoft.AspNetCore.OpenApi`), Kestrel comes along automatically

3. **Lightweight and fast**: Kestrel is designed to be a high-performance, cross-platform web server

4. **Used by default**: When you call `.ConfigureWebHostDefaults()`, ASP.NET Core automatically uses Kestrel as the web server

## Why Do We Need It?

Your ServerMonitor application needs to:
- **Host a REST API** (listening on port 8999)
- **Serve Swagger UI** (interactive API documentation)
- **Handle HTTP requests** from external systems submitting alerts

Kestrel is what makes this possible - it's the component that:
- Listens on the network port (8999)
- Accepts incoming HTTP requests
- Routes them to your controllers (like `AlertsController`, `SnapshotController`)
- Sends HTTP responses back

## Is It a NuGet Package?

**No, it's not a separate NuGet package you need to install.**

Kestrel is included in the **ASP.NET Core runtime** and comes automatically with:
- `Microsoft.NET.Sdk.Web` (your project SDK)
- ASP.NET Core packages (like `Microsoft.AspNetCore.OpenApi`)

You can see in your `ServerMonitor.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk.Web">  <!-- This includes Kestrel -->
```

And you have:
```xml
<PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="10.0.0" />
```

This package brings in Kestrel automatically.

## Why Didn't the Old Solution Work?

### The Problem

The REST API wasn't starting because **Kestrel wasn't being told which URL to listen on**.

### Previous Attempts (That Failed):

1. **Attempt 1**: Tried to set URL in `ConfigureServices`:
   ```csharp
   webBuilder.ConfigureServices((context, services) => {
       webBuilder.UseUrls($"http://0.0.0.0:{port}");  // ❌ Too late!
   })
   ```
   **Why it failed**: `UseUrls()` must be called **before** services are configured, not inside `ConfigureServices`.

2. **Attempt 2**: Tried to set URL in `Configure` method:
   ```csharp
   webBuilder.Configure((context, app) => {
       var serverAddressesFeature = app.ServerFeatures.Get<IServerAddressesFeature>();
       // ❌ This doesn't work - server already started
   })
   ```
   **Why it failed**: By the time `Configure` runs, Kestrel has already started listening. You can't change the URL after startup.

3. **Attempt 3**: Tried using a lambda with `UseUrls`:
   ```csharp
   webBuilder.UseUrls((context, urls) => { ... });  // ❌ Wrong signature
   ```
   **Why it failed**: `UseUrls()` doesn't accept a lambda - it only accepts a `string` or `string[]`.

### The Working Solution:

```csharp
.ConfigureWebHostDefaults(webBuilder =>
{
    // ✅ Configure URL EARLY, before services
    webBuilder.ConfigureAppConfiguration((hostingContext, config) =>
    {
        var apiConfig = hostingContext.Configuration.GetSection("RestApi");
        var enabled = apiConfig.GetValue<bool>("Enabled");
        var port = apiConfig.GetValue<int>("Port", 5000);
        if (enabled)
        {
            webBuilder.UseUrls($"http://localhost:{port}");  // ✅ Called early enough
        }
    });
    
    webBuilder.ConfigureServices((context, services) => {
        // Services configuration...
    });
})
```

### Why This Works:

1. **Timing**: `ConfigureAppConfiguration` runs **early** in the host builder pipeline, before Kestrel starts
2. **Access to Configuration**: We can read the port from `appsettings.json` at this point
3. **Direct Call**: `UseUrls()` is called directly on `webBuilder` with a simple string, which is the correct API

### The Host Builder Pipeline Order:

```
1. ConfigureAppConfiguration  ← We set UseUrls() here ✅
2. ConfigureServices          ← Services registered
3. Configure                  ← Middleware pipeline
4. Kestrel starts listening   ← Uses the URL we set in step 1
```

## Summary

- **Kestrel** = Built-in web server (comes with ASP.NET Core)
- **Not a NuGet package** = Included automatically
- **Why needed** = To host your REST API
- **Old solution failed** = Wrong timing - tried to configure URL too late
- **New solution works** = Configure URL early in `ConfigureAppConfiguration`

## Additional Notes

The change from `http://0.0.0.0:{port}` to `http://localhost:{port}` was also requested:
- `0.0.0.0` = Listen on all network interfaces (accessible from other machines)
- `localhost` = Listen only on local loopback (only accessible from the same machine)

For local testing, `localhost` is safer and what you requested.

