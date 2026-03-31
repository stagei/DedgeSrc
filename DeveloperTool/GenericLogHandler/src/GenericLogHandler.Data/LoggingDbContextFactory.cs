using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace GenericLogHandler.Data;

/// <summary>
/// Used by EF Core tools (e.g. dotnet ef migrations add) to create a DbContext at design time.
/// Uses PostgreSQL by default; connection string from environment or appsettings at repo root.
/// </summary>
internal sealed class LoggingDbContextFactory : IDesignTimeDbContextFactory<LoggingDbContext>
{
    public LoggingDbContext CreateDbContext(string[] args)
    {
        var basePath = FindRepositoryRoot();
        var config = new ConfigurationBuilder()
            .SetBasePath(basePath)
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        var connectionString = config.GetConnectionString("Postgres")
            ?? config.GetConnectionString("DefaultConnection")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
            ?? "Host=t-no1fkxtst-db;Port=8432;Database=GenericLogHandler;Username=postgres;Password=postgres";

        var optionsBuilder = new DbContextOptionsBuilder<LoggingDbContext>();
        optionsBuilder.UseNpgsql(connectionString, npgsql => { npgsql.CommandTimeout(30); });

        return new LoggingDbContext(optionsBuilder.Options);
    }

    private static string FindRepositoryRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 10 && dir != null; i++)
        {
            if (File.Exists(Path.Combine(dir.FullName, "GenericLogHandler.sln")))
                return dir.FullName;
            if (File.Exists(Path.Combine(dir.FullName, "appsettings.json")))
                return dir.FullName;
            dir = dir.Parent;
        }
        return AppContext.BaseDirectory;
    }
}
