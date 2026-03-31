using System.Diagnostics;
using Microsoft.Extensions.Hosting.WindowsServices;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;
using Scalar.AspNetCore;
using ServerMonitorDashboard.Models;
using ServerMonitorDashboard.Services;
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;

// Ensure the Content Root is set to the executable's directory
// This is critical for production deployments where wwwroot is next to the exe
// NOTE: Environment.ProcessPath returns w3wp.exe path under IIS InProcess hosting,
// so we must use AppContext.BaseDirectory which always returns the app's directory
var isIIS = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APP_POOL_ID"));
var exePath = isIIS 
    ? AppContext.BaseDirectory 
    : (Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory);

// Use WebApplicationOptions with Windows Service support
var options = new WebApplicationOptions
{
    Args = args,
    ContentRootPath = exePath,
    WebRootPath = Path.Combine(exePath, "wwwroot")
};

var builder = WebApplication.CreateBuilder(options);

// Add Windows Service support - required for running as a Windows Service
// This implements the Windows Service protocol (SCM communication)
builder.Host.UseWindowsService(cfg =>
{
    cfg.ServiceName = "ServerMonitorDashboard";
});

// ═══════════════════════════════════════════════════════════════════════════════
// Configure appsettings.json with auto-reload support
// This enables the Dashboard to reload settings when the file is modified
// ═══════════════════════════════════════════════════════════════════════════════
builder.Configuration
    .SetBasePath(exePath)
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true);

// ═══════════════════════════════════════════════════════════════════════════════
// Configure local firewall rules for Dashboard API port
// Skip when running under IIS -- IIS-DeployApp handles firewall rules during deployment
// ═══════════════════════════════════════════════════════════════════════════════
if (!isIIS)
{
    ConfigureFirewall(8998);
}

// Load configuration
builder.Services.Configure<DashboardConfig>(
    builder.Configuration.GetSection("Dashboard"));

// Register services
builder.Services.AddSingleton<ComputerInfoService>();
builder.Services.AddSingleton<VersionService>();
builder.Services.AddSingleton<ServerStatusService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<ServerStatusService>());

// Register alert polling service (monitors all servers for alerts)
builder.Services.AddSingleton<ServerMonitorDashboard.Services.AlertPollingService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<ServerMonitorDashboard.Services.AlertPollingService>());

// Register reinstall trigger service (monitors for trigger file and launches install script)
// This allows Dashboard updates even when no user is logged in (unlike the tray app)
builder.Services.AddHostedService<ServerMonitorDashboard.Services.ReinstallTriggerService>();

// Register configuration reload service (monitors appsettings.json for changes)
// This logs when settings are reloaded and enables dynamic configuration
builder.Services.AddHostedService<ServerMonitorDashboard.Services.ConfigurationReloadService>();
builder.Services.AddScoped<SnapshotProxyService>();
builder.Services.AddScoped<LogFilesProxyService>();
builder.Services.AddScoped<ReinstallService>();
builder.Services.AddScoped<ITrayApiService, TrayApiService>();
builder.Services.AddSingleton<ConfigEditorService>();
builder.Services.AddSingleton<SnapshotAnalysisService>();

// HTTP client factory
builder.Services.AddHttpClient("ServerMonitor", client =>
{
    client.Timeout = TimeSpan.FromSeconds(10);
});

// HTTP client for Tray API (port 8997 on each server)
builder.Services.AddHttpClient("TrayApi", client =>
{
    client.Timeout = TimeSpan.FromSeconds(10);
});

// Add controllers
builder.Services.AddControllers();

// ═══════════════════════════════════════════════════════════════════════════════
// DedgeAuth Authentication
// ═══════════════════════════════════════════════════════════════════════════════
builder.Services.AddDedgeAuth(builder.Configuration);

// Add OpenAPI document generation (replaces Swashbuckle)
builder.Services.AddOpenApi(options =>
{
    // Set document metadata and JWT security definition via document transformer
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info = new()
        {
            Title = "ServerMonitor Dashboard API",
            Version = "v1"
        };

        // Add JWT Bearer authentication security scheme
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes = new Dictionary<string, IOpenApiSecurityScheme>
        {
            ["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "JWT",
                In = ParameterLocation.Header,
                Description = "Enter 'Bearer' followed by a space and your JWT token"
            }
        };

        // Apply Bearer security requirement to all operations
        if (document.Paths is not null)
        foreach (var operation in document.Paths.Values.Where(p => p.Operations is not null).SelectMany(path => path.Operations!))
        {
            operation.Value.Security ??= [];
            operation.Value.Security.Add(new OpenApiSecurityRequirement
            {
                [new OpenApiSecuritySchemeReference("Bearer", document)] = []
            });
        }

        return Task.CompletedTask;
    });
});

// CORS for local development
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Configure server URL -- only when NOT running under IIS InProcess hosting
// Under IIS InProcess, the ASP.NET Core Module handles URL binding via ASPNETCORE_URLS
// in web.config; calling UseUrls() here would conflict with that
var serverUrl = builder.Configuration["Kestrel:Endpoints:Http:Url"] ?? "http://0.0.0.0:8998";
if (!isIIS)
{
    builder.WebHost.UseUrls(serverUrl);
}

var app = builder.Build();

app.UseCors();

// DedgeAuth authentication, authorization, session validation, and redirect middleware
// UseRouting() is implicit in .NET 6+ minimal hosting — do NOT call it explicitly
app.UseDedgeAuth();

// Serve static files AFTER authentication check
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapControllers();

// DedgeAuth proxy endpoints (token exchange, session validation, UI assets)
app.MapDedgeAuthProxy();

// OpenAPI document + Scalar API Reference UI (after DedgeAuth proxy)
app.MapOpenApi();
app.MapScalarApiReference();

var displayUrl = serverUrl.Replace("0.0.0.0", "localhost");

var DedgeAuthEnabled = app.Configuration.GetValue<bool>("DedgeAuth:Enabled", false);

Console.WriteLine("========================================");
Console.WriteLine("  ServerMonitor Dashboard");
Console.WriteLine("========================================");
Console.WriteLine($"  Dashboard: {displayUrl}");
Console.WriteLine($"  API Docs: {displayUrl}/scalar/v1");
Console.WriteLine($"  Listening on: {serverUrl}");
Console.WriteLine($"  Auth: {(DedgeAuthEnabled ? "DedgeAuth SSO" : "Disabled")}");
if (DedgeAuthEnabled)
{
    Console.WriteLine($"  DedgeAuth: {app.Configuration["DedgeAuth:AuthServerUrl"]}");
}
Console.WriteLine("========================================");

app.Run();

// ═══════════════════════════════════════════════════════════════════════════════
// Firewall Configuration Helper
// ═══════════════════════════════════════════════════════════════════════════════
static void ConfigureFirewall(int port)
{
    try
    {
        var ruleName = $"ServerMonitorDashboard_Port{port}";
        
        // Check if rule already exists
        var checkProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall show rule name=\"{ruleName}_Inbound\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        
        checkProcess.Start();
        var output = checkProcess.StandardOutput.ReadToEnd();
        checkProcess.WaitForExit();
        
        if (output.Contains(ruleName))
        {
            Console.WriteLine($"  Firewall: Port {port} rule already exists");
            return;
        }
        
        // Create inbound rule
        var inboundProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall add rule name=\"{ruleName}_Inbound\" dir=in action=allow protocol=TCP localport={port}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        
        inboundProcess.Start();
        inboundProcess.WaitForExit();
        
        if (inboundProcess.ExitCode == 0)
        {
            Console.WriteLine($"  Firewall: Opened inbound port {port}");
        }
        
        // Create outbound rule
        var outboundProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall add rule name=\"{ruleName}_Outbound\" dir=out action=allow protocol=TCP localport={port}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        
        outboundProcess.Start();
        outboundProcess.WaitForExit();
        
        if (outboundProcess.ExitCode == 0)
        {
            Console.WriteLine($"  Firewall: Opened outbound port {port}");
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  Firewall: Could not configure (may need admin rights): {ex.Message}");
    }
}
