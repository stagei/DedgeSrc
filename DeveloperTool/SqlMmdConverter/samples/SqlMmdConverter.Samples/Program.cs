using SqlMmdConverter.Converters;
using SqlMmdConverter.Exceptions;

// Command-line argument parsing
if (args.Length == 0)
{
    ShowHelp();
    return 0;
}

string? inputFile = null;
bool exportMarkdown = false;
bool showHelp = false;

// Parse arguments
for (int i = 0; i < args.Length; i++)
{
    switch (args[i].ToLower())
    {
        case "-h":
        case "--help":
        case "-?":
        case "/?":
            showHelp = true;
            break;
        case "-md":
        case "--markdown":
            exportMarkdown = true;
            break;
        default:
            if (!args[i].StartsWith("-") && inputFile == null)
            {
                inputFile = args[i];
            }
            break;
    }
}

if (showHelp)
{
    ShowHelp();
    return 0;
}

if (string.IsNullOrWhiteSpace(inputFile))
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine("✗ Error: No input file specified");
    Console.ResetColor();
    Console.WriteLine("\nUse --help for usage information");
    return 1;
}

if (!File.Exists(inputFile))
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine($"✗ Error: File not found: {inputFile}");
    Console.ResetColor();
    return 1;
}

// Display header
Console.WriteLine(@"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║           SqlMmdConverter - SQL to Mermaid ERD               ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
");

try
{
    // Read input file
    Console.ForegroundColor = ConsoleColor.Cyan;
    Console.WriteLine($"Reading: {Path.GetFileName(inputFile)}");
    Console.ResetColor();
    
    var sqlDdl = await File.ReadAllTextAsync(inputFile);
    
    // Convert to Mermaid
    Console.ForegroundColor = ConsoleColor.Cyan;
    Console.WriteLine("Converting SQL to Mermaid ERD...");
    Console.ResetColor();
    
    var converter = new SqlToMmdConverter();
    
    if (exportMarkdown)
    {
        // Export as Markdown
        var fileNameWithoutExtension = Path.GetFileNameWithoutExtension(inputFile);
        var markdownOutput = await converter.ConvertToMarkdownAsync(sqlDdl, fileNameWithoutExtension);
        
        // Save markdown file
        var outputPath = $"{inputFile}.md";
        await File.WriteAllTextAsync(outputPath, markdownOutput);
        
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"\n✓ Conversion successful!");
        Console.ResetColor();
        Console.WriteLine($"  Output: {outputPath}");
        Console.WriteLine($"  Format: Markdown with embedded Mermaid diagram");
        Console.WriteLine($"  Size: {new FileInfo(outputPath).Length:N0} bytes");
    }
    else
    {
        // Export as .mmd
        var mermaidOutput = await converter.ConvertAsync(sqlDdl);
        
        // Save mermaid file
        var outputPath = $"{inputFile}.mmd";
        await File.WriteAllTextAsync(outputPath, mermaidOutput);
        
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"\n✓ Conversion successful!");
        Console.ResetColor();
        Console.WriteLine($"  Output: {outputPath}");
        Console.WriteLine($"  Format: Mermaid ERD");
        Console.WriteLine($"  Size: {new FileInfo(outputPath).Length:N0} bytes");
    }
    
    return 0;
}
catch (SqlParseException ex)
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine($"\n✗ SQL Parsing Error:");
    Console.ResetColor();
    Console.WriteLine($"  {ex.Message}");
    return 1;
}
catch (ConversionException ex)
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine($"\n✗ Conversion Error:");
    Console.ResetColor();
    Console.WriteLine($"  {ex.Message}");
    return 1;
}
catch (Exception ex)
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine($"\n✗ Unexpected Error:");
    Console.ResetColor();
    Console.WriteLine($"  {ex.Message}");
    return 1;
}

static void ShowHelp()
{
    Console.WriteLine(@"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║           SqlMmdConverter - SQL to Mermaid ERD               ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

USAGE:
    SqlMmdConverter.Samples <input-file> [options]

ARGUMENTS:
    <input-file>        Path to SQL DDL file to convert

OPTIONS:
    -md, --markdown     Export as Markdown with embedded Mermaid diagram
    -h, --help          Show this help message

EXAMPLES:
    Convert SQL to .mmd file:
        SqlMmdConverter.Samples database.sql

    Convert SQL to .md file with Mermaid diagram:
        SqlMmdConverter.Samples database.sql --markdown

OUTPUT:
    Without --markdown: Creates <input-file>.mmd
    With --markdown:    Creates <input-file>.md with heading and code fence

SUPPORTED SQL FEATURES:
    • CREATE TABLE statements
    • Primary keys (PK)
    • Foreign keys (FK) with relationships
    • Column data types
    • NOT NULL constraints
    • DEFAULT values
    • T-SQL/MS SQL Server [bracket] notation (auto-cleaned)

");
}
