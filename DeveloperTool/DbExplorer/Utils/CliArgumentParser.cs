using NLog;

namespace DbExplorer.Utils;

/// <summary>
/// Parsed CLI arguments - EXTENDED for automated testing
/// </summary>
public class CliArguments
{
    // Existing parameters
    public string? ProfileName { get; set; }
    public string? Sql { get; set; }
    public string? OutFile { get; set; }
    public string? Format { get; set; } = "json"; // json, csv, tsv, xml
    public bool Help { get; set; }
    public bool CollectMetadata { get; set; }
    
    // NEW: Command-based execution for automated testing
    public string? Command { get; set; } // table-props, trigger-info, view-info, etc.
    public string? Object { get; set; } // SCHEMA.TABLE, SCHEMA.VIEW, etc.
    public string? Schema { get; set; } // Schema filter
    public string? ObjectType { get; set; } // TABLE, VIEW, PROCEDURE, FUNCTION, TRIGGER
    public int? Limit { get; set; } // Result limit (default: no limit)
    public bool IncludeDependencies { get; set; } // Include dependency analysis
    public bool IncludeSourceCode { get; set; } // Include source code
    
    // NEW: GUI Form Testing for automated validation
    public string? TestForm { get; set; } // table-details, object-details, package-details, etc.
    public string? Tab { get; set; } // Specific tab to test (columns, foreign-keys, indexes, ddl-script, etc.)
    
    // NEW: GUI mode with auto-open
    public string? Open { get; set; } // Element to open (SCHEMA.TABLE, SCHEMA.VIEW, etc.)
    public string? OpenType { get; set; } // Object type: table, view, procedure, function, package, user, etc.
    
    // NEW: AI Assistant parameters
    public string? Prompt { get; set; } // Natural language prompt for AI query generation
    
    // NEW: Missing FK Discovery parameters
    public string? Input { get; set; } // Input JSON file path for missing-fk-scan
    public string? Ignore { get; set; } // Ignore JSON file path (optional)

    // NEW: create-profile command (no connection required)
    public string? CreateName { get; set; }   // Profile name for new connection
    public string? CreateProvider { get; set; } // DB2 | PostgreSQL
    public string? CreateHost { get; set; }   // Host or server
    public int? CreatePort { get; set; }      // Port (default by provider: DB2 50000, PostgreSQL 5432)
    public string? CreateDatabase { get; set; }
    public string? CreateUsername { get; set; }
    public string? CreatePassword { get; set; }
    public string? CreateVersion { get; set; } // Optional: 12.1 for DB2, 18 for PostgreSQL
}

/// <summary>
/// Parser for command-line arguments
/// </summary>
public class CliArgumentParser
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    public static CliArguments Parse(string[] args)
    {
        Logger.Debug("Parsing CLI arguments: {Args}", string.Join(" ", args));
        
        var cliArgs = new CliArguments();
        
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "-profile":
                case "--profile":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.ProfileName = args[++i];
                        Logger.Debug("Profile: {Profile}", cliArgs.ProfileName);
                    }
                    break;
                    
                case "-sql":
                case "--sql":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Sql = args[++i];
                        Logger.Debug("SQL: {SQL}", cliArgs.Sql?.Substring(0, Math.Min(50, cliArgs.Sql.Length)));
                    }
                    break;
                    
                case "-outfile":
                case "--outfile":
                case "-out":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.OutFile = args[++i];
                        Logger.Debug("OutFile: {OutFile}", cliArgs.OutFile);
                    }
                    break;
                    
                case "-format":
                case "--format":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Format = args[++i].ToLowerInvariant();
                        Logger.Debug("Format: {Format}", cliArgs.Format);
                    }
                    break;
                    
                case "-collectmetadata":
                case "--collectmetadata":
                case "-metadata":
                    cliArgs.CollectMetadata = true;
                    Logger.Debug("CollectMetadata: true");
                    break;
                    
                case "-help":
                case "--help":
                case "-h":
                case "/?":
                case "/help":
                    cliArgs.Help = true;
                    Logger.Debug("Help requested");
                    break;
                    
                // NEW: Command-based parameters for automated testing
                case "-command":
                case "--command":
                case "-cmd":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Command = args[++i].ToLowerInvariant();
                        Logger.Debug("Command: {Command}", cliArgs.Command);
                    }
                    break;
                    
                case "-object":
                case "--object":
                case "-obj":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Object = args[++i];
                        Logger.Debug("Object: {Object}", cliArgs.Object);
                    }
                    break;
                    
                case "-schema":
                case "--schema":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Schema = args[++i];
                        Logger.Debug("Schema: {Schema}", cliArgs.Schema);
                    }
                    break;
                    
                // NEW: GUI Form Testing parameters
                case "-test-form":
                case "--test-form":
                case "-testform":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.TestForm = args[++i].ToLowerInvariant();
                        Logger.Debug("TestForm: {TestForm}", cliArgs.TestForm);
                    }
                    break;
                    
                case "-tab":
                case "--tab":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Tab = args[++i].ToLowerInvariant();
                        Logger.Debug("Tab: {Tab}", cliArgs.Tab);
                    }
                    break;
                    
                case "-objecttype":
                case "--objecttype":
                case "-type":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.ObjectType = args[++i].ToUpperInvariant();
                        Logger.Debug("ObjectType: {ObjectType}", cliArgs.ObjectType);
                    }
                    break;
                    
                case "-limit":
                case "--limit":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int limit))
                    {
                        cliArgs.Limit = limit;
                        Logger.Debug("Limit: {Limit}", cliArgs.Limit);
                    }
                    break;
                    
                case "-includedependencies":
                case "--includedependencies":
                case "-deps":
                    cliArgs.IncludeDependencies = true;
                    Logger.Debug("IncludeDependencies: true");
                    break;
                    
                case "-includesourcecode":
                case "--includesourcecode":
                case "-source":
                    cliArgs.IncludeSourceCode = true;
                    Logger.Debug("IncludeSourceCode: true");
                    break;
                    
                case "-open":
                case "--open":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Open = args[++i];
                        Logger.Debug("Open: {Open}", cliArgs.Open);
                    }
                    break;
                    
                case "-opentype":
                case "--opentype":
                case "--type":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.OpenType = args[++i].ToLowerInvariant();
                        Logger.Debug("OpenType: {OpenType}", cliArgs.OpenType);
                    }
                    break;
                    
                // NEW: AI Assistant parameters
                case "-prompt":
                case "--prompt":
                case "-p":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Prompt = args[++i];
                        Logger.Debug("Prompt: {Prompt}", cliArgs.Prompt);
                    }
                    break;
                    
                // NEW: Missing FK Discovery parameters
                case "-input":
                case "--input":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Input = args[++i];
                        Logger.Debug("Input: {Input}", cliArgs.Input);
                    }
                    break;
                    
                case "-ignore":
                case "--ignore":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.Ignore = args[++i];
                        Logger.Debug("Ignore: {Ignore}", cliArgs.Ignore);
                    }
                    break;

                // create-profile: --name, --provider, --host/--server, --port, --database, --username, --password, --version
                case "-name":
                case "--name":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreateName = args[++i];
                        Logger.Debug("CreateName: {Name}", cliArgs.CreateName);
                    }
                    break;
                case "-provider":
                case "--provider":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreateProvider = args[++i];
                        Logger.Debug("CreateProvider: {Provider}", cliArgs.CreateProvider);
                    }
                    break;
                case "-host":
                case "--host":
                case "-server":
                case "--server":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreateHost = args[++i];
                        Logger.Debug("CreateHost: {Host}", cliArgs.CreateHost);
                    }
                    break;
                case "-port":
                case "--port":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int port))
                    {
                        cliArgs.CreatePort = port;
                        Logger.Debug("CreatePort: {Port}", cliArgs.CreatePort);
                    }
                    break;
                case "-database":
                case "--database":
                case "-db":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreateDatabase = args[++i];
                        Logger.Debug("CreateDatabase: {Database}", cliArgs.CreateDatabase);
                    }
                    break;
                case "-username":
                case "--username":
                case "-user":
                case "-u":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreateUsername = args[++i];
                        Logger.Debug("CreateUsername: {User}", cliArgs.CreateUsername);
                    }
                    break;
                case "-password":
                case "--password":
                case "-pwd":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreatePassword = args[++i];
                        Logger.Debug("CreatePassword: (set)");
                    }
                    break;
                case "-version":
                case "--version":
                    if (i + 1 < args.Length)
                    {
                        cliArgs.CreateVersion = args[++i];
                        Logger.Debug("CreateVersion: {Version}", cliArgs.CreateVersion);
                    }
                    break;
            }
        }
        
        Logger.Info("CLI arguments parsed - Profile: {Profile}, Command: {Command}, Object: {Object}, HasSQL: {HasSQL}, TestForm: {TestForm}, Tab: {Tab}, Open: {Open}, OpenType: {OpenType}", 
            cliArgs.ProfileName, cliArgs.Command, cliArgs.Object, !string.IsNullOrEmpty(cliArgs.Sql), cliArgs.TestForm, cliArgs.Tab, cliArgs.Open, cliArgs.OpenType);
        
        return cliArgs;
    }
}

