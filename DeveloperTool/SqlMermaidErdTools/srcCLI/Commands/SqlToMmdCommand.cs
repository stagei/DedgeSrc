using System.CommandLine;
using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.CLI.Services;

namespace SqlMermaidErdTools.CLI.Commands;

public static class SqlToMmdCommand
{
    public static Command Create(LicenseService licenseService)
    {
        var command = new Command("sql-to-mmd", "Convert SQL DDL to Mermaid ERD");

        var inputArgument = new Argument<FileInfo>(
            name: "input",
            description: "Input SQL file path"
        );

        var outputOption = new Option<FileInfo?>(
            name: "--output",
            description: "Output Mermaid file path (stdout if not specified)"
        );
        outputOption.AddAlias("-o");

        var exportDirOption = new Option<DirectoryInfo?>(
            name: "--export-dir",
            description: "Directory to export intermediate files (AST, etc.) for debugging"
        );

        command.AddArgument(inputArgument);
        command.AddOption(outputOption);
        command.AddOption(exportDirOption);

        command.SetHandler(async (FileInfo input, FileInfo? output, DirectoryInfo? exportDir) =>
        {
            try
            {
                // Read input SQL
                if (!input.Exists)
                {
                    Console.Error.WriteLine($"Error: Input file not found: {input.FullName}");
                    Environment.Exit(1);
                    return;
                }

                var sql = await File.ReadAllTextAsync(input.FullName);

                // Create converter
                var converter = new SqlToMmdConverter();
                
                if (exportDir != null)
                {
                    converter.ExportFolderPath = exportDir.FullName;
                }

                // Convert
                var mermaid = await converter.ConvertAsync(sql);

                // Count tables for license validation
                var tableCount = CountTables(mermaid);
                var validation = licenseService.ValidateOperation(tableCount);

                if (!validation.IsValid)
                {
                    Console.Error.WriteLine($"❌ {validation.Message}");
                    
                    if (validation.Tier == LicenseTier.Free)
                    {
                        Console.Error.WriteLine(licenseService.GetUpgradeMessage());
                    }
                    
                    Environment.Exit(2);
                    return;
                }

                // Output result
                if (output != null)
                {
                    await File.WriteAllTextAsync(output.FullName, mermaid);
                    Console.WriteLine($"✅ Converted successfully: {output.FullName}");
                    Console.WriteLine($"   Tables: {tableCount}");
                    Console.WriteLine($"   License: {validation.Tier}");
                }
                else
                {
                    Console.WriteLine(mermaid);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"❌ Conversion failed: {ex.Message}");
                if (ex.InnerException != null)
                {
                    Console.Error.WriteLine($"   Details: {ex.InnerException.Message}");
                }
                Environment.Exit(1);
            }
        }, inputArgument, outputOption, exportDirOption);

        return command;
    }

    private static int CountTables(string mermaid)
    {
        // Count entity definitions (simple regex-based counting)
        var lines = mermaid.Split('\n');
        return lines.Count(line => line.Trim().EndsWith("{") && !line.TrimStart().StartsWith("%%"));
    }
}

