using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SqlMermaidApi.Models;

namespace SqlMermaidApi.Services;

public interface IApiKeyService
{
    Task<ApiKey?> GetApiKeyAsync(string apiKey);
    Task<ApiKey> CreateApiKeyAsync(string email, string licenseKey, LicenseTier tier);
    Task<bool> ValidateApiKeyAsync(string apiKey);
    Task IncrementRequestCountAsync(string apiKey);
    Task<ApiKeyInfo> GetApiKeyInfoAsync(string apiKey);
}

public class ApiKeyService : IApiKeyService
{
    private readonly string _apiKeysFilePath;
    private readonly ILogger<ApiKeyService> _logger;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private Dictionary<string, ApiKey> _apiKeys = new();

    public ApiKeyService(IConfiguration configuration, ILogger<ApiKeyService> logger)
    {
        _apiKeysFilePath = configuration["ApiKeysFilePath"] ?? "apikeys.json";
        _logger = logger;
        _ = LoadApiKeysAsync();
    }

    private async Task LoadApiKeysAsync()
    {
        await _lock.WaitAsync();
        try
        {
            if (!File.Exists(_apiKeysFilePath))
            {
                _apiKeys = new Dictionary<string, ApiKey>();
                await SaveApiKeysAsync();
                return;
            }

            var json = await File.ReadAllTextAsync(_apiKeysFilePath);
            _apiKeys = JsonSerializer.Deserialize<Dictionary<string, ApiKey>>(json) ?? new();
            
            _logger.LogInformation("Loaded {Count} API keys", _apiKeys.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load API keys");
            _apiKeys = new Dictionary<string, ApiKey>();
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task SaveApiKeysAsync()
    {
        await _lock.WaitAsync();
        try
        {
            var json = JsonSerializer.Serialize(_apiKeys, new JsonSerializerOptions 
            { 
                WriteIndented = true 
            });
            await File.WriteAllTextAsync(_apiKeysFilePath, json);
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<ApiKey?> GetApiKeyAsync(string apiKey)
    {
        await _lock.WaitAsync();
        try
        {
            // Reset daily counters if it's a new day
            var now = DateTime.UtcNow;
            foreach (var apiKeyData in _apiKeys.Values.Where(k => k.LastRequestAt.Date < now.Date))
            {
                _apiKeys[apiKeyData.Key] = apiKeyData with { RequestsToday = 0 };
            }

            return _apiKeys.TryGetValue(apiKey, out var key) ? key : null;
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<ApiKey> CreateApiKeyAsync(string email, string licenseKey, LicenseTier tier)
    {
        var apiKey = GenerateApiKey();
        var now = DateTime.UtcNow;
        
        var key = new ApiKey
        {
            Key = apiKey,
            Email = email,
            LicenseKey = licenseKey,
            Tier = tier,
            CreatedAt = now,
            ExpiresAt = tier == LicenseTier.Free ? now.AddYears(1) : now.AddYears(10),
            IsActive = true,
            RequestsToday = 0,
            LastRequestAt = now
        };

        await _lock.WaitAsync();
        try
        {
            _apiKeys[apiKey] = key;
            await SaveApiKeysAsync();
        }
        finally
        {
            _lock.Release();
        }

        _logger.LogInformation("Created API key for {Email} with tier {Tier}", email, tier);
        return key;
    }

    public async Task<bool> ValidateApiKeyAsync(string apiKey)
    {
        var key = await GetApiKeyAsync(apiKey);
        if (key == null || !key.IsActive || key.ExpiresAt < DateTime.UtcNow)
        {
            return false;
        }

        // Check rate limits
        var limits = GetRateLimits(key.Tier);
        if (key.RequestsToday >= limits.DailyLimit)
        {
            _logger.LogWarning("Rate limit exceeded for API key {Key}", apiKey);
            return false;
        }

        return true;
    }

    public async Task IncrementRequestCountAsync(string apiKey)
    {
        await _lock.WaitAsync();
        try
        {
            if (_apiKeys.TryGetValue(apiKey, out var key))
            {
                _apiKeys[apiKey] = key with 
                { 
                    RequestsToday = key.RequestsToday + 1,
                    LastRequestAt = DateTime.UtcNow
                };
                await SaveApiKeysAsync();
            }
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<ApiKeyInfo> GetApiKeyInfoAsync(string apiKey)
    {
        var key = await GetApiKeyAsync(apiKey);
        if (key == null)
        {
            throw new UnauthorizedAccessException("Invalid API key");
        }

        var limits = GetRateLimits(key.Tier);
        var tableLimits = GetTableLimits(key.Tier);

        return new ApiKeyInfo
        {
            Tier = key.Tier.ToString(),
            Email = key.Email,
            TableLimit = tableLimits,
            RequestsToday = key.RequestsToday,
            DailyLimit = limits.DailyLimit,
            ExpiresAt = key.ExpiresAt,
            IsActive = key.IsActive
        };
    }

    private static string GenerateApiKey()
    {
        var bytes = new byte[32];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(bytes);
        return $"sk_sqlmmd_{Convert.ToBase64String(bytes).Replace("+", "").Replace("/", "").Replace("=", "")[..40]}";
    }

    private static (int DailyLimit, int RatePerMinute) GetRateLimits(LicenseTier tier)
    {
        return tier switch
        {
            LicenseTier.Free => (100, 10),
            LicenseTier.Pro => (10000, 100),
            LicenseTier.Enterprise => (100000, 1000),
            _ => (100, 10)
        };
    }

    private static int GetTableLimits(LicenseTier tier)
    {
        return tier switch
        {
            LicenseTier.Free => 10,
            LicenseTier.Pro => int.MaxValue,
            LicenseTier.Enterprise => int.MaxValue,
            _ => 10
        };
    }
}

