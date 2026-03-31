using System.CommandLine;
using System.Reflection;

namespace SqlMermaidErdTools.CLI.Commands;

public static class VersionCommand
{
    public static Command Create()
    {
        var command = new Command("version", "Show version information");

        command.SetHandler(() =>
        {
            var assembly = Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            var informationalVersion = assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                .InformationalVersion ?? version?.ToString() ?? "Unknown";

            Console.WriteLine($"SqlMermaid ERD Tools CLI");
            Console.WriteLine($"Version: {informationalVersion}");
            Console.WriteLine($"Runtime: .NET {Environment.Version}");
            Console.WriteLine($"Platform: {Environment.OSVersion}");
            Console.WriteLine();
            Console.WriteLine("https://github.com/yourusername/SqlMermaidErdTools");
        });

        return command;
    }
}

