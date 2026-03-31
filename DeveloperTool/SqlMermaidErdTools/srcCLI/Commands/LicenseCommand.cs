using System.CommandLine;
using SqlMermaidErdTools.CLI.Services;

namespace SqlMermaidErdTools.CLI.Commands;

public static class LicenseCommand
{
    public static Command Create(LicenseService licenseService)
    {
        var command = new Command("license", "Manage your SqlMermaid license");

        // license activate
        var activateCommand = new Command("activate", "Activate a license key");
        
        var keyOption = new Option<string>(
            name: "--key",
            description: "License key"
        );
        keyOption.AddAlias("-k");
        keyOption.IsRequired = true;

        var emailOption = new Option<string>(
            name: "--email",
            description: "Email address"
        );
        emailOption.AddAlias("-e");
        emailOption.IsRequired = true;

        activateCommand.AddOption(keyOption);
        activateCommand.AddOption(emailOption);

        activateCommand.SetHandler(async (string key, string email) =>
        {
            Console.WriteLine("Activating license...");
            var result = await licenseService.ActivateLicenseAsync(key, email);

            if (result.Success)
            {
                Console.WriteLine($"✅ {result.Message}");
                
                if (result.License != null)
                {
                    Console.WriteLine();
                    Console.WriteLine("License Details:");
                    Console.WriteLine($"  Email:      {result.License.Email}");
                    Console.WriteLine($"  Tier:       {result.License.Tier}");
                    Console.WriteLine($"  Max Tables: {result.License.MaxTables?.ToString() ?? "Unlimited"}");
                    
                    if (result.License.ExpiryDate.HasValue)
                    {
                        Console.WriteLine($"  Expires:    {result.License.ExpiryDate.Value:yyyy-MM-dd}");
                    }
                    else
                    {
                        Console.WriteLine($"  Expires:    Never (Perpetual)");
                    }
                }
            }
            else
            {
                Console.Error.WriteLine($"❌ {result.Message}");
                Environment.Exit(1);
            }
        }, keyOption, emailOption);

        // license show
        var showCommand = new Command("show", "Show current license information");
        
        showCommand.SetHandler(() =>
        {
            var license = licenseService.GetLicense();

            Console.WriteLine("Current License:");
            Console.WriteLine($"  Tier:       {license.Tier}");
            Console.WriteLine($"  Email:      {license.Email ?? "N/A"}");
            Console.WriteLine($"  Max Tables: {license.MaxTables?.ToString() ?? "Unlimited"}");
            
            if (license.ExpiryDate.HasValue)
            {
                var daysRemaining = (license.ExpiryDate.Value - DateTime.UtcNow).Days;
                Console.WriteLine($"  Expires:    {license.ExpiryDate.Value:yyyy-MM-dd} ({daysRemaining} days remaining)");
                
                if (daysRemaining < 30)
                {
                    Console.WriteLine();
                    Console.WriteLine("⚠️  Your license will expire soon. Please renew to continue using Pro features.");
                }
            }
            else if (license.Tier != LicenseTier.Free)
            {
                Console.WriteLine($"  Expires:    Never (Perpetual)");
            }

            if (license.Tier == LicenseTier.Free)
            {
                Console.WriteLine();
                Console.WriteLine("ℹ️  You are using the Free tier.");
                Console.WriteLine(licenseService.GetUpgradeMessage());
            }
        });

        // license deactivate
        var deactivateCommand = new Command("deactivate", "Deactivate the current license");
        
        deactivateCommand.SetHandler(() =>
        {
            licenseService.DeactivateLicense();
            Console.WriteLine("✅ License deactivated successfully.");
            Console.WriteLine("   You are now using the Free tier.");
        });

        command.AddCommand(activateCommand);
        command.AddCommand(showCommand);
        command.AddCommand(deactivateCommand);

        return command;
    }
}

