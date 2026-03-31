using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using Serilog;
using Serilog.Events;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Data;
using GenericLogHandler.Data.Repositories;
using IBM.EntityFrameworkCore;
using Npgsql.EntityFrameworkCore.PostgreSQL;

namespace GenericLogHandler.AlertAgent;

public class Program
{
    public static async Task Main(string[] args)
    {
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Information)
            .Enrich.FromLogContext()
            .WriteTo.Console()
            .WriteTo.File("logs/alert-agent-.txt", rollingInterval: RollingInterval.Day)
            .CreateLogger();

        try
        {
            Log.Information("Starting Generic Log Handler Alert Agent");

            var builder = CreateHostBuilder(args);
            var host = builder.Build();

            await EnsureDatabase(host);

            await host.RunAsync();
        }
        catch (Exception ex)
        {
            Log.Fatal(ex, "Alert Agent terminated unexpectedly");
            return;
        }
        finally
        {
            Log.CloseAndFlush();
        }
    }

    public static IHostBuilder CreateHostBuilder(string[] args) =>
        Host.CreateDefaultBuilder(args)
            .UseWindowsService(options =>
            {
                options.ServiceName = "Generic Log Handler Alert Agent";
            })
            .UseSerilog()
            .ConfigureAppConfiguration((context, config) =>
            {
                var repoRoot = GetRepositoryRoot();

                config.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);
                config.AddJsonFile(Path.Combine(repoRoot, "appsettings.json"), optional: false, reloadOnChange: true);

                config.AddJsonFile($"appsettings.{context.HostingEnvironment.EnvironmentName}.json",
                    optional: true, reloadOnChange: true);
                config.AddJsonFile(Path.Combine(repoRoot, $"appsettings.{context.HostingEnvironment.EnvironmentName}.json"),
                    optional: true, reloadOnChange: true);

                config.AddEnvironmentVariables();
                config.AddCommandLine(args);
            })
            .ConfigureServices((context, services) =>
            {
                var databaseType = context.Configuration.GetValue<string>("ImportConfiguration:Database:Type")
                    ?? context.Configuration.GetValue<string>("Database:Type")
                    ?? "db2";
                var connectionString = ResolveConnectionString(context.Configuration, databaseType);

                services.AddDbContext<LoggingDbContext>(options =>
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
                            db2Options.CommandTimeout(30);
                        });
                    }
                });

                services.AddScoped<ILogRepository, LogRepository>();
                services.AddHostedService<AlertAgentService>();

                services.AddLogging(builder =>
                {
                    builder.ClearProviders();
                    builder.AddSerilog();
                });
            });

    private static async Task EnsureDatabase(IHost host)
    {
        using var scope = host.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();

        try
        {
            logger.LogInformation("Ensuring database exists and is up to date...");
            await context.Database.EnsureCreatedAsync();
            if ((await context.Database.GetPendingMigrationsAsync()).Any())
            {
                logger.LogInformation("Applying pending database migrations...");
                await context.Database.MigrateAsync();
            }
            logger.LogInformation("Database initialization completed");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error initializing database");
            throw;
        }
    }

    private static string GetRepositoryRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 8 && current != null; i++)
        {
            var solutionPath = Path.Combine(current.FullName, "GenericLogHandler.sln");
            var appSettingsPath = Path.Combine(current.FullName, "appsettings.json");
            if (File.Exists(solutionPath) || File.Exists(appSettingsPath))
                return current.FullName;
            current = current.Parent;
        }
        return AppContext.BaseDirectory;
    }

    private static bool IsPostgres(string databaseType)
    {
        return databaseType.Trim().Equals("postgres", StringComparison.OrdinalIgnoreCase)
            || databaseType.Trim().Equals("postgresql", StringComparison.OrdinalIgnoreCase)
            || databaseType.Trim().Equals("pgsql", StringComparison.OrdinalIgnoreCase);
    }

    private static string ResolveConnectionString(IConfiguration configuration, string databaseType)
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
                ?? "Server=localhost:50000;Database=LOGS;UID=loghandler;PWD=SecurePassword123!;Security=SSL;";
        }
        return configuration.GetConnectionString("DefaultConnection")
            ?? "Server=localhost:50000;Database=LOGS;UID=loghandler;PWD=SecurePassword123!;Security=SSL;";
    }
}
