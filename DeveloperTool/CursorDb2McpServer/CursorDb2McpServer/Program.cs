using Serilog;
using CursorDb2McpServer.Services;
using DedgeCommon;

var logDir = Environment.GetEnvironmentVariable("OptPath");
if (string.IsNullOrWhiteSpace(logDir))
{
    logDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
}

var logBase = Path.Combine(logDir, "Data", "CursorDb2McpServer", "logs");
Directory.CreateDirectory(logBase);

var logFile = Path.Combine(logBase, $"CursorDb2McpServer_{DateTime.UtcNow:yyyyMMdd}.log");

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Debug()
    .WriteTo.Console()
    .WriteTo.File(logFile, rollingInterval: RollingInterval.Day, retainedFileCountLimit: 31)
    .CreateLogger();

FkFolders fkFolders = new("CursorDb2McpServer");
DedgeNLog.SetFileLogLevels(DedgeNLog.LogLevel.Info, DedgeNLog.LogLevel.Fatal);
DedgeNLog.SetConsoleLogLevels(DedgeNLog.LogLevel.Info, DedgeNLog.LogLevel.Fatal);

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSerilog(Log.Logger, dispose: true);

builder.Services.AddSingleton<DatabaseConfigService>();
builder.Services
    .AddMcpServer()
    .WithHttpTransport()
    .WithToolsFromAssembly(typeof(Program).Assembly);

var app = builder.Build();

app.MapMcp();

app.Run();
