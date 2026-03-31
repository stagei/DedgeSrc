using System.CommandLine;
using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;
using SqlMermaidErdTools.CLI.Services;

namespace SqlMermaidErdTools.CLI.Commands;

public static class DiffCommand
{
    public static Command Create(LicenseService licenseService)
    {
        var command = new Command("diff", "Generate SQL migration from Mermaid diagram changes");

        var beforeArgument = new Argument<FileInfo>(
            name: "before",
            description: "Before Mermaid file (original schema)"
        );

        var afterArgument = new Argument<FileInfo>(
            name: "after",
            description: "After Mermaid file (modified schema)"
        );

        var outputOption = new Option<FileInfo?>(
            name: "--output",
            description: "Output SQL migration file (stdout if not specified)"
        );
        outputOption.AddAlias("-o");

        var dialectOption = new Option<SqlDialect>(
            name: "--dialect",
            description: "Target SQL dialect",
            getDefaultValue: () => SqlDialect.AnsiSql
        );
        dialectOption.AddAlias("-d");

        var exportDirOption = new Option<DirectoryInfo?>(
            name: "--export-dir",
            description: "Directory to export intermediate files for debugging"
        );

        command.AddArgument(beforeArgument);
        command.AddArgument(afterArgument);
        command.AddOption(outputOption);
        command.AddOption(dialectOption);
        command.AddOption(exportDirOption);

        command.SetHandler(async (FileInfo before, FileInfo after, FileInfo? output, SqlDialect dialect, DirectoryInfo? exportDir) =>
        {
            try
            {
                // Read input files
                if (!before.Exists)
                {
                    Console.Error.WriteLine($"Error: Before file not found: {before.FullName}");
                    Environment.Exit(1);
                    return;
                }

                if (!after.Exists)
                {
                    Console.Error.WriteLine($"Error: After file not found: {after.FullName}");
                    Environment.Exit(1);
                    return;
                }

                var beforeMermaid = await File.ReadAllTextAsync(before.FullName);
                var afterMermaid = await File.ReadAllTextAsync(after.FullName);

                // Create diff generator
                var generator = new MmdDiffToSqlGenerator();
                
                if (exportDir != null)
                {
                    generator.ExportFolderPath = exportDir.FullName;
                }

                // Generate migration
                var migration = await generator.GenerateAlterStatementsAsync(beforeMermaid, afterMermaid, dialect);

                // Count tables for license validation
                var tableCount = Math.Max(CountTables(beforeMermaid), CountTables(afterMermaid));
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
                    await File.WriteAllTextAsync(output.FullName, migration);
                    Console.WriteLine($"✅ Migration generated successfully: {output.FullName}");
                    Console.WriteLine($"   Dialect: {dialect}");
                    Console.WriteLine($"   Tables: {tableCount}");
                    Console.WriteLine($"   License: {validation.Tier}");
                }
                else
                {
                    Console.WriteLine(migration);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"❌ Migration generation failed: {ex.Message}");
                if (ex.InnerException != null)
                {
                    Console.Error.WriteLine($"   Details: {ex.InnerException.Message}");
                }
                Environment.Exit(1);
            }
        }, beforeArgument, afterArgument, outputOption, dialectOption, exportDirOption);

        return command;
    }

    private static int CountTables(string mermaid)
    {
        var lines = mermaid.Split('\n');
        return lines.Count(line => line.Trim().EndsWith("{") && !line.TrimStart().StartsWith("%%"));
    }
}

