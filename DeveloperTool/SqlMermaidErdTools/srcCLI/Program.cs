using System.CommandLine;
using SqlMermaidErdTools.CLI.Commands;
using SqlMermaidErdTools.CLI.Services;

namespace SqlMermaidErdTools.CLI;

class Program
{
    static async Task<int> Main(string[] args)
    {
        // Initialize license service
        var licenseService = new LicenseService();
        
        // Create root command
        var rootCommand = new RootCommand("SqlMermaid ERD Tools - Bidirectional SQL DDL and Mermaid ERD converter");

        // Add commands
        rootCommand.AddCommand(SqlToMmdCommand.Create(licenseService));
        rootCommand.AddCommand(MmdToSqlCommand.Create(licenseService));
        rootCommand.AddCommand(DiffCommand.Create(licenseService));
        rootCommand.AddCommand(LicenseCommand.Create(licenseService));
        rootCommand.AddCommand(VersionCommand.Create());

        // Execute
        return await rootCommand.InvokeAsync(args);
    }
}

