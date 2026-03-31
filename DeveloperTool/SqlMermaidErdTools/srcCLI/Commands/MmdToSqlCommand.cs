using System.CommandLine;
using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;
using SqlMermaidErdTools.CLI.Services;

namespace SqlMermaidErdTools.CLI.Commands;

public static class MmdToSqlCommand
{
    public static Command Create(LicenseService licenseService)
    {
        var command = new Command("mmd-to-sql", "Convert Mermaid ERD to SQL DDL");

        var inputArgument = new Argument<FileInfo>(
            name: "input",
            description: "Input Mermaid file path"
        );

        var outputOption = new Option<FileInfo?>(
            name: "--output",
            description: "Output SQL file path (stdout if not specified)"
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

        command.AddArgument(inputArgument);
        command.AddOption(outputOption);
        command.AddOption(dialectOption);
        command.AddOption(exportDirOption);

        command.SetHandler(async (FileInfo input, FileInfo? output, SqlDialect dialect, DirectoryInfo? exportDir) =>
        {
            try
            {
                // Read input Mermaid
                if (!input.Exists)
                {
                    Console.Error.WriteLine($"Error: Input file not found: {input.FullName}");
                    Environment.Exit(1);
                    return;
                }

                var mermaid = await File.ReadAllTextAsync(input.FullName);

                // Create converter
                var converter = new MmdToSqlConverter();
                
                if (exportDir != null)
                {
                    converter.ExportFolderPath = exportDir.FullName;
                }

                // Convert
                var sql = await converter.ConvertAsync(mermaid, dialect);

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
                    await File.WriteAllTextAsync(output.FullName, sql);
                    Console.WriteLine($"✅ Converted successfully: {output.FullName}");
                    Console.WriteLine($"   Dialect: {dialect}");
                    Console.WriteLine($"   Tables: {tableCount}");
                    Console.WriteLine($"   License: {validation.Tier}");
                }
                else
                {
                    Console.WriteLine(sql);
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
        }, inputArgument, outputOption, dialectOption, exportDirOption);

        return command;
    }

    private static int CountTables(string mermaid)
    {
        var lines = mermaid.Split('\n');
        return lines.Count(line => line.Trim().EndsWith("{") && !line.TrimStart().StartsWith("%%"));
    }
}

