using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.OpenApi;
using Scalar.AspNetCore;
using NLog;
using NLog.Extensions.Logging;
using ServerMonitor.Core.AlertChannels;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Monitors;
using ServerMonitor.Core.Services;
using ServerMonitor.Services;
using System.Diagnostics;

namespace ServerMonitor;

public class Program
{
    public static void Main(string[] args)
    {
        // Load configuration BEFORE initializing NLog
        // Use AppContext.BaseDirectory instead of GetCurrentDirectory() to find appsettings.json
        var basePath = AppContext.BaseDirectory;
        var environment = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? "Production";
        var baseConfigFile = Path.Combine(basePath, "appsettings.json");
        var envConfigFile = Path.Combine(basePath, $"appsettings.{environment}.json");
        
        var config = new Microsoft.Extensions.Configuration.ConfigurationBuilder()
            .SetBasePath(basePath)
            .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
            .AddJsonFile($"appsettings.{environment}.json", optional: true, reloadOnChange: true)
            .Build();

        // Determine log directory based on available drives:
        // - If E: drive exists → E:\opt\data\ServerMonitor (typical for servers with data drive)
        // - Otherwise → C:\ServerMonitorLogs (fallback for single-drive systems)
        string logDirectory;
        var appName = "ServerMonitor";
        
        if (Directory.Exists(@"E:\"))
        {
            logDirectory = @"E:\opt\data\ServerMonitor";
        }
        else
        {
            logDirectory = @"C:\ServerMonitorLogs";
        }
        
        // Ensure log directory exists BEFORE NLog initializes
        try
        {
            Directory.CreateDirectory(logDirectory);
        }
        catch (Exception ex)
        {
            // If primary path fails, try fallback to exe directory
            try
            {
                logDirectory = Path.Combine(basePath, "logs");
                Directory.CreateDirectory(logDirectory);
            }
            catch
            {
                // Last resort: write to Windows Event Log
                try
                {
                    System.Diagnostics.EventLog.WriteEntry("ServerMonitor", 
                        $"Failed to create log directory: {ex.Message}", 
                        System.Diagnostics.EventLogEntryType.Error);
                }
                catch { /* Ignore if event log also fails */ }
            }
        }
        
        // Set environment variables so NLog can use them
        Environment.SetEnvironmentVariable("LOG_DIRECTORY", logDirectory);
        Environment.SetEnvironmentVariable("LOG_APPNAME", appName);
        
        // Set REST API port as environment variable for early configuration
        // This MUST be set before CreateDefaultBuilder() is called, as it reads ASPNETCORE_URLS
        var restApiConfig = config.GetSection("RestApi");
        var restApiEnabled = restApiConfig.GetValue<bool>("Enabled", false);
        var restApiPort = restApiConfig.GetValue<int>("Port", 5000);
        if (restApiEnabled)
        {
            // Bind to all network interfaces using wildcard (*) to allow external access
            // Using * requires URL reservation or admin rights, but works more reliably than 0.0.0.0
            // Alternative: http://+:port (requires netsh http add urlacl)
            Environment.SetEnvironmentVariable("ASPNETCORE_URLS", $"http://*:{restApiPort}");
        }

        // Initialize NLog configuration from appsettings.json
        // This must be done before GetCurrentClassLogger() is called
        var nlogConfigSection = config.GetSection("NLog");
        if (nlogConfigSection.Exists())
        {
            var nlogConfig = new NLog.Extensions.Logging.NLogLoggingConfiguration(nlogConfigSection);
            LogManager.Configuration = nlogConfig;
        }
        else
        {
            // Fallback: try to load from NLog.config if appsettings.json doesn't have NLog section
            LogManager.Setup().LoadConfigurationFromFile("NLog.config");
        }

        var logger = LogManager.GetCurrentClassLogger();
        logger.Info("LOG_DIRECTORY set to: {LogDirectory}", logDirectory);
        logger.Info("LOG_APPNAME set to: {AppName}", appName);
        try
        {
            logger.Info("═══════════════════════════════════════════════════════");
            logger.Info("Starting Server Health Monitor Check Tool");
            logger.Info($"Configuration Directory: {basePath}");
            logger.Info($"Base Configuration File: {baseConfigFile} ({(File.Exists(baseConfigFile) ? "✓ Found" : "✗ Missing")})");
            logger.Info($"Environment: {environment}");
            logger.Info($"Environment Configuration File: {envConfigFile} ({(File.Exists(envConfigFile) ? "✓ Found" : "✗ Not found (using base config only)")})");
            logger.Info($"Log Directory: {logDirectory}");
            logger.Info($"Log File: {appName}_{{date}}.log");
            logger.Info("═══════════════════════════════════════════════════════");

            // Check for global disable file before starting
            const string ConfigBasePath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor";
            var disableFilePath = Path.Combine(ConfigBasePath, "DisableServerMonitor.txt");
            try
            {
                if (File.Exists(disableFilePath))
                {
                    logger.Warn("═══════════════════════════════════════════════════════");
                    logger.Warn("⛔ AGENTS ARE DISABLED - DisableServerMonitor.txt exists");
                    logger.Warn("   File: {DisableFile}", disableFilePath);
                    try
                    {
                        var content = File.ReadAllText(disableFilePath);
                        if (content.Contains("Reason="))
                        {
                            var reason = content.Split('\n')
                                .FirstOrDefault(l => l.StartsWith("Reason="))
                                ?.Substring(7).Trim() ?? "No reason specified";
                            logger.Warn("   Reason: {Reason}", reason);
                        }
                    }
                    catch { /* Ignore read errors */ }
                    logger.Warn("═══════════════════════════════════════════════════════");
                    logger.Warn("Agent will NOT start. Remove the disable file to enable.");
                    return; // Exit without starting
                }
            }
            catch (Exception ex)
            {
                // If we can't check the disable file (network issue), log and continue
                logger.Debug(ex, "Could not check disable file (network may be unavailable)");
            }

            // Kill any existing instances of this application
            KillExistingInstances(logger);
            
            // Build the host - pass preloaded config so we can configure URL early
            logger.Info("Building host with REST API configuration...");
            var apiConfigForLogging = config.GetSection("RestApi");
            var apiEnabledForLogging = apiConfigForLogging.GetValue<bool>("Enabled", false);
            var apiPortForLogging = apiConfigForLogging.GetValue<int>("Port", 5000);
            logger.Info("REST API Config: Enabled={Enabled}, Port={Port}", apiEnabledForLogging, apiPortForLogging);
            
            var host = CreateHostBuilder(args, config).Build();
            logger.Info("Host built successfully");
            
            // Check for test timeout configuration
            var surveillanceConfig = host.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<SurveillanceConfiguration>>().Value;
            var testTimeout = surveillanceConfig.Runtime.TestTimeoutSeconds;
            
            if (testTimeout.HasValue && testTimeout.Value > 0)
            {
                logger.Info("═══════════════════════════════════════════════════════");
                logger.Info("⏰ TEST MODE: Auto-kill after {TestTimeout} seconds", testTimeout.Value);
                logger.Info("═══════════════════════════════════════════════════════");
                
                // Start test timeout in background task
                _ = Task.Run(async () =>
                {
                    var startTime = DateTime.Now;
                    for (int i = 0; i < testTimeout.Value; i++)
                    {
                        await Task.Delay(1000);
                        if (i % 5 == 0 && i > 0)
                        {
                            var elapsed = (DateTime.Now - startTime).TotalSeconds;
                            logger.Info("⏱️  Test running: {Elapsed:F0}s / {TestTimeout}s", elapsed, testTimeout.Value);
                        }
                    }
                    
                    logger.Info("═══════════════════════════════════════════════════════");
                    logger.Info("⏱️ TEST TIMEOUT REACHED ({TestTimeout}s) - AUTO KILL", testTimeout.Value);
                    logger.Info("═══════════════════════════════════════════════════════");
                    
                    // Force exit
                    Environment.Exit(0);
                });
            }
            
            host.Run();
        }
        catch (Exception ex)
        {
            logger.Fatal(ex, "Application terminated unexpectedly");
            
            // Log detailed error information
            logger.Fatal("═══════════════════════════════════════════════════════");
            logger.Fatal("❌ FATAL ERROR - Application terminated unexpectedly");
            logger.Fatal("═══════════════════════════════════════════════════════");
            logger.Fatal("Exception Type: {ExceptionType}", ex.GetType().Name);
            logger.Fatal("Message: {Message}", ex.Message);
            logger.Fatal("Stack Trace: {StackTrace}", ex.StackTrace);
            if (ex.InnerException != null)
            {
                logger.Fatal("Inner Exception Type: {InnerType}", ex.InnerException.GetType().Name);
                logger.Fatal("Inner Exception Message: {InnerMessage}", ex.InnerException.Message);
            }
            logger.Fatal("═══════════════════════════════════════════════════════");
            logger.Info("Press any key to exit (or wait 30 seconds to auto-close)...");
            
            // Only wait for key if running interactively (not as a service)
            if (Environment.UserInteractive)
            {
                try
                {
                    WaitForKeyPressWithTimeout(TimeSpan.FromSeconds(30));
                }
                catch
                {
                    // Ignore if console is not available
                }
            }
            
            throw;
        }
        finally
        {
            LogManager.Shutdown();
            
            // Keep console open for debugging (only if running interactively)
            if (Environment.UserInteractive)
            {
                try
                {
                    logger.Info("Application is shutting down. Press any key to exit (or wait 30 seconds to auto-close)...");
                    WaitForKeyPressWithTimeout(TimeSpan.FromSeconds(30));
                }
                catch
                {
                    // Ignore if console is not available
                }
            }
        }
    }

    private static void WaitForKeyPressWithTimeout(TimeSpan timeout)
    {
        var startTime = DateTime.Now;
        var remainingSeconds = (int)timeout.TotalSeconds;
        
        while ((DateTime.Now - startTime) < timeout)
        {
            if (Console.KeyAvailable)
            {
                Console.ReadKey(true); // Consume the key
                return;
            }
            
            // Update countdown every second
            var elapsed = (int)(DateTime.Now - startTime).TotalSeconds;
            var newRemaining = remainingSeconds - elapsed;
            if (newRemaining != remainingSeconds && newRemaining > 0)
            {
                remainingSeconds = newRemaining;
                Console.Write($"\rAuto-closing in {remainingSeconds} seconds... (press any key to exit immediately)");
            }
            
            Thread.Sleep(100); // Check every 100ms
        }
        
        Console.WriteLine("\rAuto-closing...                                    ");
    }

    private static void KillExistingInstances(Logger logger)
    {
        try
        {
            var currentProcess = Process.GetCurrentProcess();
            var currentProcessName = currentProcess.ProcessName;
            var currentProcessId = currentProcess.Id;

            var existingProcesses = Process.GetProcessesByName(currentProcessName)
                .Where(p => p.Id != currentProcessId)
                .ToList();

            if (existingProcesses.Any())
            {
                logger.Info($"Found {existingProcesses.Count} existing instance(s) of {currentProcessName}. Terminating...");
                
                foreach (var process in existingProcesses)
                {
                    try
                    {
                        logger.Info($"Killing process {process.ProcessName} (PID: {process.Id})");
                        process.Kill(entireProcessTree: true);
                        process.WaitForExit(5000); // Wait up to 5 seconds for graceful exit
                        logger.Info($"Successfully terminated PID: {process.Id}");
                    }
                    catch (Exception ex)
                    {
                        logger.Warn(ex, $"Failed to kill process {process.Id}: {ex.Message}");
                    }
                    finally
                    {
                        process.Dispose();
                    }
                }

                // Give the OS time to fully clean up
                System.Threading.Thread.Sleep(1000);
                logger.Info("All existing instances terminated successfully");
            }
            else
            {
                logger.Info("No existing instances found");
            }
        }
        catch (Exception ex)
        {
            logger.Warn(ex, $"Error while checking for existing instances: {ex.Message}");
        }
    }

    private static void AddSectionToDictionary(Microsoft.Extensions.Configuration.IConfigurationSection section, Dictionary<string, string?> dictionary, string prefix)
    {
        if (!section.Exists())
            return;
            
        foreach (var item in section.GetChildren())
        {
            var key = string.IsNullOrEmpty(prefix) ? item.Key : $"{prefix}:{item.Key}";
            
            if (item.GetChildren().Any())
            {
                // Nested section - recurse
                AddSectionToDictionary(item, dictionary, key);
            }
            else
            {
                // Leaf value
                dictionary[key] = item.Value;
            }
        }
    }

    public static IHostBuilder CreateHostBuilder(string[] args, Microsoft.Extensions.Configuration.IConfiguration? preloadedConfig = null) =>
        Host.CreateDefaultBuilder(args)
            .UseContentRoot(AppContext.BaseDirectory) // FIX: Use EXE directory for config files
            .ConfigureAppConfiguration((context, config) =>
            {
                // Ensure appsettings.json is loaded from EXE directory
                config.SetBasePath(AppContext.BaseDirectory);
            })
            // Windows Service support - enables running as a Windows Service
            // This implements the Windows Service protocol required for service installation
            .UseWindowsService(options =>
            {
                options.ServiceName = "ServerMonitor";
            })
            .ConfigureWebHostDefaults(webBuilder =>
            {
                // Configure URL early - read from preloaded config if available
                if (preloadedConfig != null)
                {
                    var restApiConfig = preloadedConfig.GetSection("RestApi");
                    var enabled = restApiConfig.GetValue<bool>("Enabled", false);
                    var port = restApiConfig.GetValue<int>("Port", 5000);
                    if (enabled)
                    {
                        // Bind to all network interfaces using wildcard (*) to allow external access
                        webBuilder.UseUrls($"http://*:{port}");
                    }
                }
                else
                {
                    // Fallback: configure in ConfigureAppConfiguration
                    webBuilder.ConfigureAppConfiguration((hostingContext, config) =>
                    {
                        var restApiConfig = hostingContext.Configuration.GetSection("RestApi");
                        var enabled = restApiConfig.GetValue<bool>("Enabled", false);
                        var port = restApiConfig.GetValue<int>("Port", 5000);
                        if (enabled)
                        {
                            // Bind to all network interfaces using wildcard (*) to allow external access
                            webBuilder.UseUrls($"http://*:{port}");
                        }
                    });
                }

                webBuilder.ConfigureServices((context, services) =>
                {
                    var apiConfig = context.Configuration.GetSection("RestApi");
                    var enabled = apiConfig.GetValue<bool>("Enabled");
                    var port = apiConfig.GetValue<int>("Port", 5000);
                    var enableSwagger = apiConfig.GetValue<bool>("EnableSwagger", true);

                    // Log REST API configuration
                    var loggerFactory = services.BuildServiceProvider().GetService<ILoggerFactory>();
                    var logger = loggerFactory?.CreateLogger("Program") ?? Microsoft.Extensions.Logging.Abstractions.NullLogger.Instance;
                    logger.LogInformation("REST API Configuration in ConfigureServices: Enabled={Enabled}, Port={Port}", enabled, port);

                    if (enabled)
                    {
                        logger.LogInformation("Configuring REST API services...");
                        
                        // Add CORS for cross-origin requests from dashboard (port 8998) to agent (port 8999)
                        services.AddCors(options =>
                        {
                            options.AddDefaultPolicy(policy =>
                            {
                                policy.AllowAnyOrigin()
                                      .AllowAnyMethod()
                                      .AllowAnyHeader();
                            });
                        });
                        
                        // Add API controllers with JSON enum serialization as strings
                        services.AddControllers()
                            .AddJsonOptions(options =>
                            {
                                // Serialize enums as camelCase strings (e.g., "critical" instead of 2)
                                options.JsonSerializerOptions.Converters.Add(
                                    new System.Text.Json.Serialization.JsonStringEnumConverter(
                                        System.Text.Json.JsonNamingPolicy.CamelCase));
                                options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
                            });
                        // Add OpenAPI document generation (replaces Swashbuckle)
                        if (enableSwagger)
                        {
                            services.AddOpenApi(options =>
                            {
                                // Set document metadata via document transformer
                                options.AddDocumentTransformer((document, context, cancellationToken) =>
                                {
                                    document.Info = new()
                                    {
                                        Title = "Server Health Monitor Check Tool API",
                                        Version = "v1",
                                        Description = @"Live REST API for querying server monitoring data, alerts, and system health.

## Alert Severity Levels
- **Informational** (0): Informational events
- **Warning** (1): Warning-level events requiring attention
- **Critical** (2): Critical events requiring immediate action

## Channel Types
- **SMS**: SMS text message notifications
- **Email**: Email notifications
- **EventLog**: Windows Event Log entries
- **File**: File-based alert logging
- **WKMonitor**: WKMonitor integration files

## External Event Throttling
External events support per-event-code throttling:
- **maxOccurrences**: Number of occurrences before alerting (0 = immediate, 1 = first occurrence, 3 = third occurrence, etc.)
- **timeWindowMinutes**: Time window to count occurrences (1-1440 minutes)
- Once threshold is reached, only one alert is sent per time window to prevent alert storms

## Channel Suppression
You can suppress specific channels per event code using `suppressedChannels`. Invalid channel names are logged and ignored.",
                                        Contact = new()
                                        {
                                            Name = "Server Health Monitor Check Tool"
                                        }
                                    };
                                    return Task.CompletedTask;
                                });

                                // Inline enum schemas (don't extract to $ref)
                                options.CreateSchemaReferenceId = (type) =>
                                    type.Type.IsEnum ? null : Microsoft.AspNetCore.OpenApi.OpenApiOptions.CreateDefaultSchemaReferenceId(type);
                            });
                        }

                        // Register firewall service
                        services.AddSingleton<FirewallService>();
                    }
                });

                webBuilder.Configure((context, app) =>
                {
                    var apiConfig = context.Configuration.GetSection("RestApi");
                    var enabled = apiConfig.GetValue<bool>("Enabled");
                    var enableSwagger = apiConfig.GetValue<bool>("EnableSwagger", true);

                    if (enabled)
                    {
                        // Enable CORS for cross-origin requests from dashboard
                        app.UseCors();

                        app.UseRouting();
                        app.UseEndpoints(endpoints =>
                        {
                            endpoints.MapControllers();

                            // OpenAPI document + Scalar API Reference UI (replaces Swagger)
                            if (enableSwagger)
                            {
                                endpoints.MapOpenApi();
                                endpoints.MapScalarApiReference();
                            }
                        });
                    }
                });
            })
            .ConfigureServices((hostContext, services) =>
            {
                // Configure NLog from appsettings.json instead of NLog.config
                services.AddLogging(loggingBuilder =>
                {
                    loggingBuilder.ClearProviders();
                    loggingBuilder.SetMinimumLevel(Microsoft.Extensions.Logging.LogLevel.Trace);
                    // Load NLog configuration from appsettings.json
                    var nlogConfig = new NLog.Extensions.Logging.NLogLoggingConfiguration(hostContext.Configuration.GetSection("NLog"));
                    LogManager.Configuration = nlogConfig;
                    loggingBuilder.AddNLog(nlogConfig);
                });

                // Configure application settings
                // General, Runtime, RestApi, ExportSettings, and Alerting are at root level
                // Monitoring sections (ProcessorMonitoring, MemoryMonitoring, etc.) are under Surveillance section
                var rootConfig = hostContext.Configuration;
                var surveillanceSection = hostContext.Configuration.GetSection("Surveillance");
                
                // DEBUG: Verify configuration binding (logged via ILogger after host is built)
                var alertingSection = rootConfig.GetSection("Alerting");
                var channelsSection = alertingSection.GetSection("Channels");
                var channelCount = channelsSection.GetChildren().Count();
                
                // Note: Debug logging moved to after host is built - see CommonConfigSyncService or similar
                // These debug statements were removed in favor of proper logging infrastructure
                
                // Create merged configuration: combine Surveillance section with root-level General/Runtime/RestApi
                // Build a merged in-memory configuration where all properties are at root level
                var mergedData = new Dictionary<string, string?>();
                
                // Add all Surveillance section properties at root level (without "Surveillance" prefix)
                AddSectionToDictionary(surveillanceSection, mergedData, "");
                
                // Override/add root-level General, Runtime, RestApi, ExportSettings, Alerting (these take precedence)
                AddSectionToDictionary(rootConfig.GetSection("General"), mergedData, "General");
                AddSectionToDictionary(rootConfig.GetSection("Runtime"), mergedData, "Runtime");
                AddSectionToDictionary(rootConfig.GetSection("RestApi"), mergedData, "RestApi");
                AddSectionToDictionary(rootConfig.GetSection("ExportSettings"), mergedData, "ExportSettings");
                AddSectionToDictionary(rootConfig.GetSection("Alerting"), mergedData, "Alerting");
                
                // Create merged configuration and bind
                var mergedConfig = new Microsoft.Extensions.Configuration.ConfigurationBuilder()
                    .AddInMemoryCollection(mergedData)
                    .Build();
                
                services.Configure<SurveillanceConfiguration>(mergedConfig);
                
                // Configure individual monitoring settings that need IOptions access
                services.Configure<Db2InstanceMonitoringSettings>(mergedConfig.GetSection("Db2InstanceMonitoring"));
                services.Configure<Db2DiagMonitoringSettings>(mergedConfig.GetSection("Db2DiagMonitoring"));
                services.Configure<IisMonitoringSettings>(mergedConfig.GetSection("IisMonitoring"));

                // Register monitors
                services.AddSingleton<IMonitor, ProcessorMonitor>();
                services.AddSingleton<IMonitor, MemoryMonitor>();
                services.AddSingleton<IMonitor, VirtualMemoryMonitor>();
                services.AddSingleton<IMonitor, DiskMonitor>();
                services.AddSingleton<IMonitor, NetworkMonitor>();
                services.AddSingleton<IMonitor, UptimeMonitor>();
                services.AddSingleton<IMonitor, WindowsUpdateMonitor>();
                services.AddSingleton<IMonitor, EventLogMonitor>();
                services.AddSingleton<IMonitor, ScheduledTaskMonitor>();
                
                // DB2 diagnostic monitoring with pattern matching
                services.AddSingleton<Db2DiagPatternMatcher>();
                services.AddSingleton<Db2SqlErrorLogger>();
                services.AddSingleton<Db2DiagMonitor>();
                services.AddSingleton<IMonitor>(sp => sp.GetRequiredService<Db2DiagMonitor>());
                
                // DB2 instance monitoring (sessions, long-running queries, blocking)
                services.AddSingleton<Db2InstanceDataCollector>();
                services.AddSingleton<IMonitor, Db2InstanceMonitor>();

                // IIS monitoring (sites, app pools, worker processes)
                services.AddSingleton<IisDataCollector>();
                services.AddSingleton<IMonitor, IisMonitor>();

                // Register services
                services.AddSingleton<ServerMonitor.Core.Interfaces.IConfigurationManager, ServerMonitor.Core.Services.ConfigurationManager>();
                services.AddSingleton<GlobalSnapshotService>(); // Global snapshot - always available
                services.AddSingleton<SnapshotHtmlExporter>();
                services.AddSingleton<ISnapshotExporter, SnapshotExporter>();
                
                // Register alert accumulator for deduplication and cooldown management
                services.AddSingleton<IAlertAccumulator, AlertAccumulator>();
                
                // Notification recipient management
                services.AddSingleton<ServerMonitor.Core.Services.NotificationRecipientService>();
                
                // Performance scaling for low-capacity servers
                services.AddSingleton<ServerMonitor.Core.Services.PerformanceScalingService>();

                // Register HttpClient for SMS
                services.AddHttpClient();

                // Register alert channels
                services.AddSingleton<IAlertChannel, EventLogAlertChannel>();
                services.AddSingleton<IAlertChannel, FileAlertChannel>();
                services.AddSingleton<IAlertChannel, EmailAlertChannel>();
                services.AddSingleton<IAlertChannel, SmsAlertChannel>();
                services.AddSingleton<IAlertChannel, WkMonitorAlertChannel>();

                // Register alert manager
                services.AddSingleton<AlertManager>();

                // Register orchestrator
                services.AddSingleton<SurveillanceOrchestrator>();

                // Register worker service
                services.AddHostedService<SurveillanceWorker>();

                // Register config reload service
                services.AddHostedService<ConfigReloadService>();

                // Register common config sync service (syncs both appsettings.json and NotificationRecipients.json from UNC path if configured)
                // Both files are synced and reloaded together
                services.AddHostedService<CommonConfigSyncService>();
                
                // Note: NotificationRecipientsSyncService is no longer needed - CommonConfigSyncService handles both files

                // Register shutdown interceptor service (real-time hooks for Event ID 1074 - shutdown detection)
                services.AddHostedService<ShutdownInterceptorService>();
                
                // Register EventLogWatcher service (real-time monitoring for ALL events)
                // This replaces the polling-based EventLogMonitor for better performance
                services.AddHostedService<EventLogWatcherService>();

                // Register stop file monitor service (checks for stop file and shuts down gracefully)
                services.AddHostedService<StopFileMonitorService>();
                
                // Register reinstall trigger service (monitors for trigger file and launches install script)
                // This allows updates even when no user is logged in (unlike the tray app)
                services.AddHostedService<ReinstallTriggerService>();
                
                // Register accumulator flush service (flushes alert data based on configured schedule)
                services.AddHostedService<AccumulatorFlushService>();

                // Configure and log REST API startup
                var apiConfig = hostContext.Configuration.GetSection("RestApi");
                var enabled = apiConfig.GetValue<bool>("Enabled");
                var port = apiConfig.GetValue<int>("Port", 5000);
                var enableSwagger = apiConfig.GetValue<bool>("EnableSwagger", true);
                var autoFirewall = apiConfig.GetValue<bool>("AutoConfigureFirewall", true);

                if (enabled)
                {
                    // Register firewall service in main services too
                    services.AddSingleton<FirewallService>();

                    // Configure firewall rule automatically if enabled
                    // Register a hosted service to configure firewall after host starts
                    if (autoFirewall)
                    {
                        services.AddHostedService(sp =>
                        {
                            var logger = sp.GetRequiredService<ILogger<FirewallConfigurationService>>();
                            var firewallService = sp.GetRequiredService<FirewallService>();
                            return new FirewallConfigurationService(logger, firewallService, port);
                        });
                    }

                    // Add a hosted service to log the API URLs at startup
                    services.AddHostedService<RestApiStartupLogger>();
                }
            });
}


