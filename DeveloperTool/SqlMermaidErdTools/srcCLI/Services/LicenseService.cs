using System.Text.Json;

namespace SqlMermaidErdTools.CLI.Services;

/// <summary>
/// Handles license validation and management for the CLI tool.
/// </summary>
public class LicenseService
{
    private const string LicenseFileName = ".sqlmermaid-license";
    private static readonly string UserLicensePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        LicenseFileName
    );

    private LicenseInfo? _cachedLicense;

    /// <summary>
    /// Gets the current license information.
    /// </summary>
    public LicenseInfo GetLicense()
    {
        if (_cachedLicense != null)
        {
            return _cachedLicense;
        }

        if (File.Exists(UserLicensePath))
        {
            try
            {
                var json = File.ReadAllText(UserLicensePath);
                var license = JsonSerializer.Deserialize<LicenseInfo>(json);
                
                if (license != null)
                {
                    _cachedLicense = license;
                    return license;
                }
            }
            catch (Exception)
            {
                // License file corrupted or invalid - fall back to free tier
            }
        }

        // No license file found - return free tier
        _cachedLicense = new LicenseInfo
        {
            Tier = LicenseTier.Free,
            Email = null,
            LicenseKey = null,
            ExpiryDate = null,
            MaxTables = 10
        };

        return _cachedLicense;
    }

    /// <summary>
    /// Validates if the current license allows the operation.
    /// </summary>
    public ValidationResult ValidateOperation(int tableCount)
    {
        var license = GetLicense();

        // Check if license is expired
        if (license.ExpiryDate.HasValue && license.ExpiryDate.Value < DateTime.UtcNow)
        {
            return new ValidationResult
            {
                IsValid = false,
                Message = $"License expired on {license.ExpiryDate.Value:yyyy-MM-dd}. Please renew your license.",
                Tier = license.Tier
            };
        }

        // Check table limit
        if (license.MaxTables.HasValue && tableCount > license.MaxTables.Value)
        {
            return new ValidationResult
            {
                IsValid = false,
                Message = $"Table limit exceeded. Your {license.Tier} license allows {license.MaxTables} tables, but this schema has {tableCount} tables. Upgrade to Pro for unlimited tables.",
                Tier = license.Tier
            };
        }

        return new ValidationResult
        {
            IsValid = true,
            Message = null,
            Tier = license.Tier
        };
    }

    /// <summary>
    /// Activates a license key.
    /// </summary>
    public async Task<ActivationResult> ActivateLicenseAsync(string licenseKey, string email)
    {
        // TODO: Implement actual license server validation
        // For now, this is a placeholder for future implementation
        
        // Validate license key format
        if (string.IsNullOrWhiteSpace(licenseKey) || !licenseKey.StartsWith("SQLMMD-"))
        {
            return new ActivationResult
            {
                Success = false,
                Message = "Invalid license key format. License keys start with 'SQLMMD-'."
            };
        }

        // Parse license key to determine tier
        var tier = ParseLicenseKeyTier(licenseKey);
        
        var license = new LicenseInfo
        {
            Tier = tier,
            Email = email,
            LicenseKey = licenseKey,
            ExpiryDate = tier == LicenseTier.Pro ? DateTime.UtcNow.AddYears(1) : null,
            MaxTables = tier == LicenseTier.Free ? 10 : null
        };

        // Save license to file
        try
        {
            var json = JsonSerializer.Serialize(license, new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(UserLicensePath, json);
            
            _cachedLicense = license;

            return new ActivationResult
            {
                Success = true,
                Message = $"License activated successfully! Tier: {tier}",
                License = license
            };
        }
        catch (Exception ex)
        {
            return new ActivationResult
            {
                Success = false,
                Message = $"Failed to save license: {ex.Message}"
            };
        }
    }

    /// <summary>
    /// Deactivates the current license.
    /// </summary>
    public void DeactivateLicense()
    {
        if (File.Exists(UserLicensePath))
        {
            File.Delete(UserLicensePath);
        }

        _cachedLicense = null;
    }

    /// <summary>
    /// Shows upgrade information for free tier users.
    /// </summary>
    public string GetUpgradeMessage()
    {
        return @"
╔══════════════════════════════════════════════════════════════════════╗
║                    UPGRADE TO PRO                                    ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  🚀 Unlimited Tables                                                 ║
║  🎯 All SQL Dialects                                                 ║
║  ⚡ Priority Support                                                 ║
║  🔄 Commercial Use License                                           ║
║                                                                      ║
║  Individual: $99/year or $249 perpetual                             ║
║  Team (5):   $399/year                                              ║
║  Enterprise: $1,999/year                                            ║
║                                                                      ║
║  Visit: https://sqlmermaid.tools/pricing                            ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
";
    }

    private LicenseTier ParseLicenseKeyTier(string licenseKey)
    {
        // Simple key format: SQLMMD-{TIER}-{GUID}
        // Example: SQLMMD-PRO-XXXX-XXXX-XXXX
        
        var parts = licenseKey.Split('-');
        if (parts.Length >= 2)
        {
            return parts[1].ToUpperInvariant() switch
            {
                "PRO" => LicenseTier.Pro,
                "TEAM" => LicenseTier.Team,
                "ENT" or "ENTERPRISE" => LicenseTier.Enterprise,
                _ => LicenseTier.Free
            };
        }

        return LicenseTier.Free;
    }
}

public class LicenseInfo
{
    public LicenseTier Tier { get; set; }
    public string? Email { get; set; }
    public string? LicenseKey { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public int? MaxTables { get; set; }
}

public enum LicenseTier
{
    Free,
    Pro,
    Team,
    Enterprise
}

public class ValidationResult
{
    public bool IsValid { get; set; }
    public string? Message { get; set; }
    public LicenseTier Tier { get; set; }
}

public class ActivationResult
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public LicenseInfo? License { get; set; }
}

