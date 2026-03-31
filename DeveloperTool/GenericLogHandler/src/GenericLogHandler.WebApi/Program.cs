using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi;
using System.Text.Json.Serialization;
using System.Text;
using Serilog;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Data;
using GenericLogHandler.Data.Repositories;
using GenericLogHandler.WebApi.Services;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using IBM.EntityFrameworkCore;
using Npgsql;
using Npgsql.EntityFrameworkCore.PostgreSQL;
using Scalar.AspNetCore;
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/webapi-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();

// Add services to the container
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
        options.JsonSerializerOptions.PropertyNamingPolicy = null; // Keep PascalCase
    });

// Database - DB2 or PostgreSQL
var databaseType = builder.Configuration.GetValue<string>("ImportConfiguration:Database:Type") ??
    builder.Configuration.GetValue<string>("Database:Type") ??
    "db2";
var connectionString = ResolveConnectionString(builder.Configuration, databaseType);

builder.Services.AddDbContext<LoggingDbContext>(options =>
{
    if (IsPostgres(databaseType))
    {
        options.UseNpgsql(connectionString, npgsqlOptions =>
        {
            npgsqlOptions.CommandTimeout(30);
        });
    }
    else
    {
        options.UseDb2(connectionString, db2Options =>
        {
            // DB2-specific configuration options can be added here
            db2Options.CommandTimeout(30);
        });
    }
});

// Repository
builder.Services.AddScoped<ILogRepository, LogRepository>();

// Config editor (maintenance: appsettings, import-config, backups)
builder.Services.AddSingleton<ConfigEditorService>();

// Windows service control (Import Service, Alert Agent) - injectable for testability
builder.Services.AddSingleton<IWindowsServiceControlService, WindowsServiceControlService>();

// Database maintenance background service (runs ANALYZE daily to keep statistics fresh)
builder.Services.AddHostedService<DatabaseMaintenanceService>();

// Log sanitation service (deletes old unprotected entries based on retention policy)
builder.Services.AddSingleton<LogSanitationService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<LogSanitationService>());

// ===== DedgeAuth SSO Authentication =====
builder.Services.AddDedgeAuth(builder.Configuration);

// Authorization policies based on DedgeAuth globalAccessLevel claim
builder.Services.AddAuthorization(options =>
{
    // ReadOnly+ (level >= 0) - can view logs
    options.AddPolicy("ReadOnlyAccess", policy =>
        policy.RequireAssertion(context =>
        {
            var levelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            return int.TryParse(levelClaim, out var level) && level >= 0;
        }));

    // User+ (level >= 1) - can view dashboard, analytics, job status
    options.AddPolicy("UserAccess", policy =>
        policy.RequireAssertion(context =>
        {
            var levelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            return int.TryParse(levelClaim, out var level) && level >= 1;
        }));

    // PowerUser+ (level >= 2) - can export, maintenance, config
    options.AddPolicy("PowerUserAccess", policy =>
        policy.RequireAssertion(context =>
        {
            var levelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            return int.TryParse(levelClaim, out var level) && level >= 2;
        }));

    // Admin only (level >= 3) - can manage config
    options.AddPolicy("AdminAccess", policy =>
        policy.RequireAssertion(context =>
        {
            var levelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            return int.TryParse(levelClaim, out var level) && level >= 3;
        }));
});

// Rate Limiting
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.User?.Identity?.Name ?? httpContext.Request.Headers.Host.ToString(),
            factory: partition => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 1000,
                Window = TimeSpan.FromMinutes(1)
            }));
});

// OpenAPI + Scalar
builder.Services.AddOpenApi("v1", options =>
{
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "Generic Log Handler API",
            Version = "v1",
            Description = "REST API for accessing and searching log data",
            Contact = new OpenApiContact
            {
                Name = "System Administrator",
                Email = "admin@company.com"
            }
        };

        // JWT Bearer authentication
        var bearerScheme = new OpenApiSecurityScheme
        {
            Name = "Authorization",
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            In = ParameterLocation.Header,
            Description = "Enter 'Bearer' followed by a space and your JWT token"
        };

        document.Components ??= new OpenApiComponents();
        document.AddComponent("Bearer", bearerScheme);

        // Apply Bearer requirement to all operations
        var securityRequirement = new OpenApiSecurityRequirement
        {
            [new OpenApiSecuritySchemeReference("Bearer", document)] = new List<string>()
        };

        foreach (var operation in document.Paths?.Values
            .Where(path => path.Operations is not null)
            .SelectMany(path => path.Operations!) ?? [])
        {
            operation.Value.Security ??= new List<OpenApiSecurityRequirement>();
            operation.Value.Security.Add(securityRequirement);
        }

        return Task.CompletedTask;
    });
});

// Health Checks
builder.Services.AddHealthChecks()
    .AddDbContextCheck<LoggingDbContext>("database", tags: new[] { "ready" });

var app = builder.Build();

// Configure the HTTP request pipeline
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
    app.UseHttpsRedirection();
}

app.UseRateLimiter();

app.UseDedgeAuth();

// Serve static files
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseSerilogRequestLogging();

app.MapControllers();
app.MapDedgeAuthProxy();

// OpenAPI JSON endpoint (/openapi/v1.json) + Scalar API reference UI (/scalar/v1)
app.MapOpenApi();
app.MapScalarApiReference();

// Health check endpoint
app.MapHealthChecks("/health");

// Auto-migrate: apply any pending EF Core migrations on startup
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();

    try
    {
        var pending = await context.Database.GetPendingMigrationsAsync();
        if (pending.Any())
        {
            logger.LogInformation("Applying pending migrations: {Migrations}", string.Join(", ", pending));
            try
            {
                await context.Database.MigrateAsync();
            }
            catch (PostgresException pe) when (pe.SqlState == "42P07")
            {
                // Relation already exists: DB has tables but no __EFMigrationsHistory. Drop and re-migrate.
                var provider = context.Database.ProviderName ?? string.Empty;
                if (provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
                {
                    logger.LogWarning("Tables exist without migrations history (42P07). Dropping and re-migrating.");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS import_sources");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS job_executions");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS import_level_filters");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS refresh_tokens");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS login_tokens");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS users");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS audit_log");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS alert_history");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS saved_filters");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS import_status");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS log_entries");
                    await context.Database.ExecuteSqlRawAsync("DROP TABLE IF EXISTS \"__EFMigrationsHistory\"");
                    await context.Database.MigrateAsync();
                }
                else
                    throw;
            }
        }
        logger.LogInformation("Database initialization completed");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error initializing database");
        throw;
    }
}

Log.Information("Generic Log Handler Web API starting...");
await app.RunAsync();
Log.Information("Generic Log Handler Web API stopped");
Log.CloseAndFlush();

static bool IsPostgres(string databaseType)
{
    return databaseType.Trim().Equals("postgres", StringComparison.OrdinalIgnoreCase)
        || databaseType.Trim().Equals("postgresql", StringComparison.OrdinalIgnoreCase)
        || databaseType.Trim().Equals("pgsql", StringComparison.OrdinalIgnoreCase);
}

static string ResolveConnectionString(IConfiguration configuration, string databaseType)
{
    if (IsPostgres(databaseType))
    {
        return configuration.GetConnectionString("Postgres")
            ?? configuration.GetConnectionString("DefaultConnection")
            ?? "Host=t-no1fkxtst-db;Port=8432;Database=GenericLogHandler;Username=postgres;Password=postgres";
    }

    if (databaseType.Trim().Equals("db2", StringComparison.OrdinalIgnoreCase))
    {
        return configuration.GetConnectionString("Db2")
            ?? configuration.GetConnectionString("DefaultConnection")
            ?? "Server=localhost:50000;Database=LOGS;UID=db2admin;PWD=password;Security=SSL;";
    }

    return configuration.GetConnectionString("DefaultConnection")
        ?? "Server=localhost:50000;Database=LOGS;UID=db2admin;PWD=password;Security=SSL;";
}
