using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.IdentityModel.Tokens;
using System.Diagnostics;
using System.Text;
using DedgeAuth.Data;
using DedgeAuth.Core.Models;
using Microsoft.AspNetCore.HttpOverrides;
using Scalar.AspNetCore;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Validate OptPath environment variable (required for log file location)
// ---------------------------------------------------------------------------
var optPath = Environment.GetEnvironmentVariable("OptPath");
if (string.IsNullOrEmpty(optPath))
{
    Console.WriteLine("FATAL: OptPath environment variable is not set. Application cannot start.");
    var smsNumber = builder.Configuration["LogFileSettings:AlertSmsNumber"] ?? "+4797188358";
    try
    {
        var psi = new ProcessStartInfo
        {
            FileName = "pwsh",
            Arguments = $"-NoProfile -Command \"Import-Module GlobalFunctions -Force; Send-Sms -Receiver '{smsNumber}' -Message 'DedgeAuth FATAL: OptPath environment variable is not set on {Environment.MachineName}. Application stopped.'\"",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var proc = Process.Start(psi);
        proc?.WaitForExit(15000);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Failed to send SMS alert: {ex.Message}");
    }
    Environment.Exit(1);
}

// ---------------------------------------------------------------------------
// Configure Serilog file + console logging
// ---------------------------------------------------------------------------
var logFolder = builder.Configuration["LogFileSettings:LogFolder"] ?? @"data\DedgeAuth.Api";
var logDirectory = Path.Combine(optPath, logFolder);
Directory.CreateDirectory(logDirectory);
var logFilePath = Path.Combine(logDirectory, "DedgeAuth-.log");

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .WriteTo.Console()
    .WriteTo.File(
        logFilePath,
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 31,
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {SourceContext} {Message:lj}{NewLine}{Exception}")
    .CreateLogger();

builder.Host.UseSerilog();

// Support running as Windows Service
builder.Host.UseWindowsService(options =>
{
    options.ServiceName = "DedgeAuth";
});

// Configure Kestrel
builder.WebHost.UseUrls("http://*:8100");

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddOpenApi();

// Add rate limiting
builder.Services.AddRateLimiter(options =>
{
    // Global rate limiter
    options.GlobalLimiter = System.Threading.RateLimiting.PartitionedRateLimiter.Create<HttpContext, string>(context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User.Identity?.Name ?? context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1)
            }));
    
    // Stricter rate limiting for login endpoint
    options.AddPolicy("login", context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1),
                AutoReplenishment = true
            }));
});

// Configure DbContext
var connectionString = builder.Configuration.GetConnectionString("AuthDb") 
    ?? "Host=t-no1fkxtst-db;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres";

builder.Services.AddDbContext<AuthDbContext>(options =>
    options.UseNpgsql(connectionString));

// Configure Authentication
var authConfig = builder.Configuration.GetSection("AuthConfiguration").Get<AuthConfiguration>() 
    ?? new AuthConfiguration();

builder.Services.Configure<AuthConfiguration>(builder.Configuration.GetSection("AuthConfiguration"));
builder.Services.Configure<SmtpConfiguration>(builder.Configuration.GetSection("SmtpConfiguration"));
builder.Services.Configure<DedgeAuth.Api.Options.ThemingOptions>(builder.Configuration.GetSection("Theming"));

var jwtSecret = authConfig.JwtSecret;
if (string.IsNullOrEmpty(jwtSecret))
{
    jwtSecret = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
}

var authBuilder = builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = authConfig.JwtIssuer,
            ValidAudience = authConfig.JwtAudience,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ClockSkew = TimeSpan.FromMinutes(5)
        };
        options.Events = new Microsoft.AspNetCore.Authentication.JwtBearer.JwtBearerEvents
        {
            OnChallenge = context =>
            {
                context.HandleResponse();
                context.Response.StatusCode = 401;
                context.Response.ContentType = "application/json";
                return context.Response.WriteAsync(System.Text.Json.JsonSerializer.Serialize(new { error = "Unauthorized" }));
            }
        };
    });

// When behind IIS with Windows Auth enabled, IIS handles Negotiate/NTLM natively
// and sets ASPNETCORE_IIS_HTTPAUTH. AddNegotiate() conflicts with that, so only
// register it for standalone Kestrel (dev) scenarios.
var iisWindowsAuth = Environment.GetEnvironmentVariable("ASPNETCORE_IIS_HTTPAUTH");
var windowsAuthScheme = string.IsNullOrEmpty(iisWindowsAuth)
    ? NegotiateDefaults.AuthenticationScheme   // "Negotiate" (Kestrel)
    : Microsoft.AspNetCore.Server.IISIntegration.IISDefaults.AuthenticationScheme; // "Windows" (IIS)

if (string.IsNullOrEmpty(iisWindowsAuth))
{
    authBuilder.AddNegotiate();
}

// Configure Authorization Policies
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("GlobalAdmin", policy =>
        policy.RequireClaim("globalAccessLevel", "3"));
    options.AddPolicy("TenantOrGlobalAdmin", policy =>
        policy.RequireClaim("globalAccessLevel", "3", "5"));
    options.AddPolicy("WindowsAuth", policy =>
    {
        policy.AddAuthenticationSchemes(windowsAuthScheme);
        policy.RequireAuthenticatedUser();
    });
});

// Configure Maintenance options
builder.Services.Configure<DedgeAuth.Core.Models.MaintenanceOptions>(builder.Configuration.GetSection("Maintenance"));
builder.Services.Configure<DedgeAuth.Core.Models.AdGroupSyncOptions>(builder.Configuration.GetSection("AdGroupSync"));

// Register services
builder.Services.AddScoped<DedgeAuth.Services.JwtTokenService>();
builder.Services.AddScoped<DedgeAuth.Services.EmailService>();
builder.Services.AddScoped<DedgeAuth.Services.AuthService>();
builder.Services.AddScoped<DedgeAuth.Services.DatabaseSeeder>();
builder.Services.AddScoped<DedgeAuth.Services.MaintenanceService>();
builder.Services.AddScoped<DedgeAuth.Services.AppGroupAccessService>();
builder.Services.AddScoped<DedgeAuth.Services.AdGroupSyncService>();

// Register background services
builder.Services.AddHostedService<DedgeAuth.Api.Services.MaintenanceBackgroundService>();
builder.Services.AddHostedService<DedgeAuth.Api.Services.AdGroupSyncBackgroundService>();

// Configure CORS based on environment
builder.Services.AddCors(options =>
{
    if (builder.Environment.IsDevelopment())
    {
        // Development: Allow localhost origins
        options.AddDefaultPolicy(policy =>
        {
            policy.WithOrigins("http://localhost:8100", "http://localhost:3000", "http://127.0.0.1:8100")
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        });
    }
    else
    {
        // Production: Restrict to configured origins
        var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() 
            ?? new[] { "https://portal.Dedge.no" };
        
        options.AddDefaultPolicy(policy =>
        {
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        });
    }
});

var app = builder.Build();

// Configure the HTTP request pipeline
app.MapOpenApi();
app.MapScalarApiReference(options =>
{
    options.WithTitle("DedgeAuth API");
});

// Forward headers from IIS / reverse proxies so Request.Host reflects the client's actual URL
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor
                     | ForwardedHeaders.XForwardedProto
                     | ForwardedHeaders.XForwardedHost
});

app.UseCors();
app.UseRateLimiter(); // Add rate limiting middleware
app.UseStaticFiles();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// Health endpoint
app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }));

// Ensure database is created and seeded
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
    var seeder = scope.ServiceProvider.GetRequiredService<DedgeAuth.Services.DatabaseSeeder>();
    try
    {
        await db.Database.MigrateAsync();
        await seeder.SeedAsync();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Database migration/seeding failed: {ex.Message}");
    }
}

app.Run();
