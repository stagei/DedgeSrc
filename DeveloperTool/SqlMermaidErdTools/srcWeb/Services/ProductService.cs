using System.Text.Json;
using System.Text.Json.Serialization;
using ProductStore.Models;

namespace ProductStore.Services;

public interface IProductService
{
    Task<ProductCatalog> GetCatalogAsync();
    Task<Product?> GetProductByIdAsync(string id);
    Task<List<Product>> GetProductsByCategoryAsync(string category);
    Task<List<Product>> GetFeaturedProductsAsync();
    Task<List<Product>> SearchProductsAsync(string query);
}

public class ProductService : IProductService, IDisposable
{
    private readonly string _productsFilePath;
    private readonly ILogger<ProductService> _logger;
    private ProductCatalog? _cachedCatalog;
    private FileSystemWatcher? _fileWatcher;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private readonly JsonSerializerOptions _jsonOptions;

    public ProductService(IConfiguration configuration, ILogger<ProductService> _logger)
    {
        _productsFilePath = configuration["ProductsFilePath"] ?? "products.json";
        this._logger = _logger;
        
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        // Initial load
        _ = LoadCatalogAsync();

        // Watch for file changes
        SetupFileWatcher();
    }

    private void SetupFileWatcher()
    {
        try
        {
            var directory = Path.GetDirectoryName(_productsFilePath) ?? Environment.CurrentDirectory;
            var fileName = Path.GetFileName(_productsFilePath);

            _fileWatcher = new FileSystemWatcher(directory, fileName)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName
            };

            _fileWatcher.Changed += async (sender, e) => await OnFileChanged(e);
            _fileWatcher.EnableRaisingEvents = true;

            _logger.LogInformation("File watcher started for: {FilePath}", _productsFilePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to setup file watcher for {FilePath}", _productsFilePath);
        }
    }

    private async Task OnFileChanged(FileSystemEventArgs e)
    {
        _logger.LogInformation("Product file changed, reloading catalog...");
        
        // Debounce: wait a bit for file to be fully written
        await Task.Delay(500);
        
        await LoadCatalogAsync();
    }

    private async Task LoadCatalogAsync()
    {
        await _lock.WaitAsync();
        try
        {
            if (!File.Exists(_productsFilePath))
            {
                _logger.LogWarning("Products file not found: {FilePath}", _productsFilePath);
                _cachedCatalog = new ProductCatalog
                {
                    Products = [],
                    Categories = [],
                    Stripe = new StripeConfig
                    {
                        PublishableKey = "",
                        Enabled = false,
                        SuccessUrl = "",
                        CancelUrl = ""
                    },
                    Metadata = new CatalogMetadata
                    {
                        LastUpdated = DateTime.UtcNow.ToString("O"),
                        Version = "1.0.0",
                        Currency = "USD",
                        CompanyName = "CodeMonkey by Dedge",
                        SupportEmail = "support@codemonkey.dedge.no",
                        SalesEmail = "sales@codemonkey.dedge.no"
                    }
                };
                return;
            }

            var json = await File.ReadAllTextAsync(_productsFilePath);
            _cachedCatalog = JsonSerializer.Deserialize<ProductCatalog>(json, _jsonOptions);

            _logger.LogInformation("Loaded {ProductCount} products from {FilePath}", 
                _cachedCatalog?.Products.Count ?? 0, _productsFilePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load products from {FilePath}", _productsFilePath);
            throw;
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<ProductCatalog> GetCatalogAsync()
    {
        if (_cachedCatalog == null)
        {
            await LoadCatalogAsync();
        }
        return _cachedCatalog ?? new ProductCatalog
        {
            Products = [],
            Categories = [],
            Stripe = new StripeConfig
            {
                PublishableKey = "",
                Enabled = false,
                SuccessUrl = "",
                CancelUrl = ""
            },
            Metadata = new CatalogMetadata
            {
                LastUpdated = DateTime.UtcNow.ToString("O"),
                Version = "1.0.0",
                Currency = "USD",
                CompanyName = "SqlMermaid Tools",
                SupportEmail = "support@sqlmermaid.tools",
                SalesEmail = "sales@sqlmermaid.tools"
            }
        };
    }

    public async Task<Product?> GetProductByIdAsync(string id)
    {
        var catalog = await GetCatalogAsync();
        return catalog.Products.FirstOrDefault(p => 
            p.Id.Equals(id, StringComparison.OrdinalIgnoreCase) && p.IsActive);
    }

    public async Task<List<Product>> GetProductsByCategoryAsync(string category)
    {
        var catalog = await GetCatalogAsync();
        return catalog.Products
            .Where(p => p.Category.Equals(category, StringComparison.OrdinalIgnoreCase) && p.IsActive)
            .OrderBy(p => p.Name)
            .ToList();
    }

    public async Task<List<Product>> GetFeaturedProductsAsync()
    {
        var catalog = await GetCatalogAsync();
        return catalog.Products
            .Where(p => p.IsFeatured && p.IsActive)
            .OrderByDescending(p => p.Metadata.Rating)
            .ThenByDescending(p => p.Metadata.Downloads)
            .ToList();
    }

    public async Task<List<Product>> SearchProductsAsync(string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            var catalog = await GetCatalogAsync();
            return catalog.Products.Where(p => p.IsActive).ToList();
        }

        var catalog2 = await GetCatalogAsync();
        var lowerQuery = query.ToLower();
        
        return catalog2.Products
            .Where(p => p.IsActive && (
                p.Name.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase) ||
                p.ShortDescription.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase) ||
                p.FullDescription.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase) ||
                p.Tags.Any(t => t.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase))
            ))
            .OrderByDescending(p => p.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ? 1 : 0)
            .ThenByDescending(p => p.Metadata.Rating)
            .ToList();
    }

    public void Dispose()
    {
        _fileWatcher?.Dispose();
        _lock?.Dispose();
        GC.SuppressFinalize(this);
    }
}

