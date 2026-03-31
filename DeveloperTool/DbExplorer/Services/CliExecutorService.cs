using System;
using System.Data;
using System.IO;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Utils;

namespace DbExplorer.Services;

/// <summary>
/// Service for executing CLI commands
/// </summary>
public class CliExecutorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly ConnectionStorageService _connectionStorage;
    private readonly ExportService _exportService;
    private readonly CliCommandHandlerService _commandHandler;
    
    public CliExecutorService()
    {
        _connectionStorage = new ConnectionStorageService();
        _exportService = new ExportService();
        _commandHandler = new CliCommandHandlerService();
        Logger.Debug("CliExecutorService initialized with command handler");
    }
    
    /// <summary>
    /// Execute CLI command
    /// </summary>
    public async Task<int> ExecuteAsync(CliArguments args)
    {
        Logger.Info("CLI Execution started - Profile: {Profile}, Output: {Output}", 
            args.ProfileName, args.OutFile);
        
        try
        {
            // Handle help
            if (args.Help)
            {
                PrintHelp();
                return 0;
            }
            
            // Handle meta commands that don't require a profile
            if (args.Command == "help-all" || args.Command == "cli-version" || args.Command == "connection-profiles" || args.Command == "create-profile")
            {
                Logger.Info("Executing profile-independent command: {Command}", args.Command);
                return await _commandHandler.ExecuteCommandAsync(null!, args);
            }
            
            // Validate arguments
            if (string.IsNullOrEmpty(args.ProfileName))
            {
                Console.Error.WriteLine("ERROR: -Profile parameter is required");
                Logger.Error("CLI execution failed: No profile specified");
                return 1;
            }
            
            // Load connection profile from GUI storage (with decrypted password)
            Console.WriteLine($"Loading connection profile: {args.ProfileName}");
            var profile = _connectionStorage.GetConnection(args.ProfileName);
            
            if (profile == null)
            {
                Console.Error.WriteLine($"ERROR: Profile '{args.ProfileName}' not found");
                Logger.Error("CLI execution failed: Profile not found - {Profile}", args.ProfileName);
                return 1;
            }
            
            // Handle metadata collection
            if (args.CollectMetadata)
            {
                return await CollectMetadataAsync(profile);
            }
            
            // NEW: Handle command-based execution (for automated testing)
            if (!string.IsNullOrEmpty(args.Command))
            {
                Logger.Info("Executing command-based CLI: {Command}", args.Command);
                
                // Create connection manager for command execution
                Console.WriteLine($"Connecting to {profile.Name} @ {profile.Server}:{profile.Port}");
                using var connectionManager = ConnectionManagerFactory.CreateConnectionManager(profile);
                
                // Open connection
                await connectionManager.OpenAsync();
                Logger.Debug("Connection opened for command execution");
                
                return await _commandHandler.ExecuteCommandAsync(connectionManager, args);
            }
            
            // Validate SQL and output file for query execution (legacy query mode)
            if (string.IsNullOrEmpty(args.Sql))
            {
                Console.Error.WriteLine("ERROR: -Sql parameter is required (or use -Command for command-based execution)");
                Logger.Error("CLI execution failed: No SQL or Command specified");
                return 1;
            }
            
            if (string.IsNullOrEmpty(args.OutFile))
            {
                Console.Error.WriteLine("ERROR: -Outfile parameter is required");
                Logger.Error("CLI execution failed: No output file specified");
                return 1;
            }
            
            // Execute query and export (legacy mode)
            return await ExecuteQueryAndExportAsync(profile, args.Sql, args.OutFile, args.Format ?? "json");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "CLI execution failed");
            Console.Error.WriteLine($"ERROR: {ex.Message}");
            return 1;
        }
    }
    
    /// <summary>
    /// Execute query and export results
    /// </summary>
    private async Task<int> ExecuteQueryAndExportAsync(DatabaseConnection profile, string sql, string outFile, string format)
    {
        try
        {
            // Connect to database
            Console.WriteLine($"Connecting to {profile.Database} @ {profile.Server}:{profile.Port}");
            using var connectionManager = ConnectionManagerFactory.CreateConnectionManager(profile);
            await connectionManager.OpenAsync();
            
            Console.WriteLine("Connected successfully");
            
            // Execute query
            Console.WriteLine("Executing query...");
            var results = await connectionManager.ExecuteQueryAsync(sql);
            
            Console.WriteLine($"Query returned {results.Rows.Count} rows");
            
            // Export results
            Console.WriteLine($"Exporting to {outFile} (format: {format})");
            await ExportResults(results, outFile, format);
            
            Console.WriteLine("Export completed successfully");
            Logger.Info("CLI query execution completed successfully");
            
            return 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to execute query and export");
            Console.Error.WriteLine($"ERROR: {ex.Message}");
            return 1;
        }
    }
    
    /// <summary>
    /// Collect metadata for profile
    /// </summary>
    private async Task<int> CollectMetadataAsync(DatabaseConnection profile)
    {
        try
        {
            Console.WriteLine($"Connecting to {profile.Database} @ {profile.Server}:{profile.Port}");
            using var connectionManager = ConnectionManagerFactory.CreateConnectionManager(profile);
            await connectionManager.OpenAsync();
            
            Console.WriteLine("Connected successfully");
            Console.WriteLine("Collecting metadata...");
            
            // Feature #5: Metadata collection (provider-agnostic check)
            var providerType = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            if (providerType != "DB2")
            {
                Console.Error.WriteLine($"ERROR: Metadata collection is not supported for provider: {providerType}");
                return 1;
            }
            
            // Use factory pattern to get provider-specific metadata service
            var metadataService = MetadataServiceFactory.CreateMetadataService(connectionManager);
            await metadataService.CollectMetadataAsync(connectionManager, profile.Name);
            
            Console.WriteLine("Metadata collection completed successfully");
            Logger.Info("Metadata collected for profile: {Profile}", profile.Name);
            
            return 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to collect metadata");
            Console.Error.WriteLine($"ERROR: {ex.Message}");
            return 1;
        }
    }
    
    /// <summary>
    /// Export results to file based on format
    /// </summary>
    private async Task ExportResults(DataTable dataTable, string outFile, string format)
    {
        Logger.Debug("Exporting to {Format} format: {File}", format, outFile);
        
        switch (format.ToLowerInvariant())
        {
            case "json":
                await _exportService.ExportToJsonAsync(dataTable, outFile);
                break;
                
            case "csv":
                await _exportService.ExportToCsvAsync(dataTable, outFile);
                break;
                
            case "tsv":
                await _exportService.ExportToTsvAsync(dataTable, outFile);
                break;
                
            case "xml":
                await _exportService.ExportToXmlAsync(dataTable, outFile);
                break;
                
            default:
                throw new ArgumentException($"Unknown format: {format}. Supported formats: json, csv, tsv, xml");
        }
        
        Logger.Info("Export completed: {Format} -> {File}", format, outFile);
    }
    
    /// <summary>
    /// Print CLI help message - EXTENDED with command-based execution
    /// </summary>
    public static void PrintHelp()
    {
        Console.WriteLine(@"
DbExplorer - Command Line Interface (EXTENDED for Automated Testing)
======================================================================

USAGE MODES:
  1. LEGACY QUERY MODE:
     DbExplorer.exe -Profile <name> -Sql <query> -Outfile <path> [-Format <format>]
  
  2. COMMAND MODE (NEW - For Automated Testing):
     DbExplorer.exe -Profile <name> -Command <cmd> [-Object <obj>] [-Schema <schema>] -Outfile <path>
  
  3. METADATA MODE:
     DbExplorer.exe -Profile <name> -CollectMetadata

COMMON PARAMETERS:
    -Profile <name>         Connection profile name (required)
    -Outfile <path>         Output file path (required - JSON format)
    -Help                   Show this help message

LEGACY QUERY MODE PARAMETERS:
    -Sql <query>            SQL query to execute
    -Format <format>        Output format: json, csv, tsv, xml (default: json)
    -CollectMetadata        Collect database metadata (Feature #5)

COMMAND MODE PARAMETERS (NEW):
    -Command <cmd>          Command to execute (see commands below)
    -Object <obj>           Object identifier (format: SCHEMA.OBJECT)
    -Schema <schema>        Schema filter (default: % = all schemas)
    -ObjectType <type>      Object type: TABLE, VIEW, PROCEDURE, FUNCTION, TRIGGER
    -Limit <n>              Limit results to N rows
    -IncludeDependencies    Include dependency analysis
    -IncludeSourceCode      Include source code in output

AVAILABLE COMMANDS (For Automated Testing):
  
  OBJECT INFORMATION:
    table-props             Get table properties (columns, PKs, FKs, indexes, stats)
                            Requires: -Object SCHEMA.TABLE
    
    trigger-info            Get trigger details and source code
                            Requires: -Object SCHEMA.TRIGGER
    
    trigger-usage           Find all triggers in schema and their usage
                            Optional: -Schema MYSCHEMA
    
    view-info               Get view definition and dependencies
                            Requires: -Object SCHEMA.VIEW
    
    procedure-info          Get stored procedure metadata and source code
                            Requires: -Object SCHEMA.PROCEDURE
    
    function-info           Get function metadata and source code
                            Requires: -Object SCHEMA.FUNCTION
    
    dependencies            Analyze object dependencies
                            Requires: -Object SCHEMA.OBJECT -ObjectType TYPE
  
  LISTING COMMANDS:
    list-tables             List all tables in schema
                            Optional: -Schema MYSCHEMA -Limit 100
    
    list-views              List all views in schema
                            Optional: -Schema MYSCHEMA
    
    list-procedures         List all stored procedures
                            Optional: -Schema MYSCHEMA
    
    list-triggers           List all triggers
                            Optional: -Schema MYSCHEMA
    
    list-functions          List all functions
                            Optional: -Schema MYSCHEMA
  
  MONITORING COMMANDS:
    lock-monitor            Get current database locks (JSON)
                            No parameters required
    
    active-sessions         Get active database sessions (JSON)
                            Optional: -Limit 50
    
    database-load           Get database load metrics by schema
                            Optional: -Schema MYSCHEMA -Limit 20
    
    table-stats             Get table statistics
                            Optional: -Schema MYSCHEMA -Limit 50
    
    cdc-info                Get CDC (Change Data Capture) status
                            Optional: -Schema MYSCHEMA

EXAMPLES:

  # Legacy query mode (original)
  DbExplorer.exe -Profile ""ILOGTST"" -Sql ""SELECT * FROM SYSCAT.TABLES FETCH FIRST 5 ROWS ONLY"" -Outfile ""output.json""
  
  # Get comprehensive table properties (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command table-props -Object ""MYSCHEMA.CUSTOMERS"" -Outfile ""table_props.json""
  
  # Get trigger information with source code (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command trigger-info -Object ""MYSCHEMA.TRG_AUDIT"" -IncludeSourceCode -Outfile ""trigger.json""
  
  # Find all triggers in a schema (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command trigger-usage -Schema ""MYSCHEMA"" -Outfile ""triggers.json""
  
  # Get view definition with dependencies (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command view-info -Object ""MYSCHEMA.V_CUSTOMERS"" -IncludeDependencies -IncludeSourceCode -Outfile ""view.json""
  
  # Get current locks (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command lock-monitor -Outfile ""locks.json""
  
  # Get active sessions (limit 20) (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command active-sessions -Limit 20 -Outfile ""sessions.json""
  
  # Get database load metrics (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command database-load -Schema ""MYSCHEMA"" -Limit 10 -Outfile ""load.json""
  
  # List all tables in schema (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command list-tables -Schema ""MYSCHEMA"" -Limit 100 -Outfile ""tables.json""
  
  # Analyze object dependencies (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command dependencies -Object ""MYSCHEMA.ORDERS"" -ObjectType TABLE -Outfile ""deps.json""
  
  # Get CDC status for schema (NEW)
  DbExplorer.exe -Profile ""PRODDB"" -Command cdc-info -Schema ""MYSCHEMA"" -Outfile ""cdc.json""

OUTPUT FORMAT:
    All commands output structured JSON with:
    - Object metadata (properties, columns, types, etc.)
    - Relationships (PKs, FKs, dependencies)
    - Source code (if -IncludeSourceCode is specified)
    - Timestamps (retrievedAt field)
    
EXIT CODES:
    0   Success
    1   Error occurred

  CREATE PROFILE (no -Profile required):
    create-profile    Create a new connection profile (DB2 or PostgreSQL)
                      -Command create-profile -name MyProfile -provider PostgreSQL -host localhost -port 5432 -database postgres -username postgres -password secret [-outfile result.json]
                      -Command create-profile -name MyDB2 -provider DB2 -host dbhost -port 50000 -database MYDB -username user -password secret

AUTOMATED TESTING WORKFLOW:
    1. Create connection profiles via GUI or CLI: -Command create-profile -name X -provider DB2|PostgreSQL -host ... -port ... -database ... -username ... -password ...
    2. Run CLI commands with -Command parameter
    3. Verify JSON output structure
    4. Build test assertions from JSON results
    5. Run regression tests using CLI commands
    6. Compare results across database versions

NOTES:
    - Connection profiles: Documents\DbExplorer\connections.json (create-profile writes here; password DPAPI-encrypted)
    - Create profiles in GUI or via create-profile CLI, then reference by -Profile name
    - Passwords are encrypted in saved profiles
    - All command outputs are in JSON format for easy parsing
    - Use -Limit to prevent overwhelming output for large schemas
    - Use -IncludeSourceCode for code review and analysis
    - Use -IncludeDependencies for impact analysis
");
    }
}

