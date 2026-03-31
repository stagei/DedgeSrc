namespace ProductStore.Models;

public record Product
{
    public required string Id { get; init; }
    public required string Category { get; init; }
    public required string Name { get; init; }
    public required string ShortDescription { get; init; }
    public required string FullDescription { get; init; }
    public required string Icon { get; init; }
    public List<string> Screenshots { get; init; } = [];
    public required Dictionary<string, List<string>?> Features { get; init; }
    public required Dictionary<string, PricingTier?> Pricing { get; init; }
    public required ProductLinks Links { get; init; }
    public required ProductMetadata Metadata { get; init; }
    public List<string> Tags { get; init; } = [];
    public bool IsActive { get; init; }
    public bool IsFeatured { get; init; }
}

public record PricingTier
{
    public decimal Price { get; init; }
    public required string Currency { get; init; }
    public required string Label { get; init; }
    public required string BillingPeriod { get; init; }
    public string? StripePriceId { get; init; }
    public string? StripeProductId { get; init; }
    public string? DownloadUrl { get; init; }
    public string? PurchaseUrl { get; init; }
    public string? ContactEmail { get; init; }
    public required string Action { get; init; }
    public List<string> Limitations { get; init; } = [];
}

public record ProductLinks
{
    public string? Documentation { get; init; }
    public string? Github { get; init; }
    public string? Nuget { get; init; }
    public string? Marketplace { get; init; }
}

public record ProductMetadata
{
    public required string Version { get; init; }
    public required string ReleaseDate { get; init; }
    public required string LastUpdated { get; init; }
    public int Downloads { get; init; }
    public double Rating { get; init; }
    public int ReviewCount { get; init; }
}

public record Category
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required string Icon { get; init; }
}

public record ProductCatalog
{
    public List<Product> Products { get; init; } = [];
    public List<Category> Categories { get; init; } = [];
    public required StripeConfig Stripe { get; init; }
    public required CatalogMetadata Metadata { get; init; }
}

public record CatalogMetadata
{
    public required string LastUpdated { get; init; }
    public required string Version { get; init; }
    public required string Currency { get; init; }
    public required string CompanyName { get; init; }
    public required string SupportEmail { get; init; }
    public required string SalesEmail { get; init; }
}

public record StripeConfig
{
    public required string PublishableKey { get; init; }
    public bool Enabled { get; init; }
    public required string SuccessUrl { get; init; }
    public required string CancelUrl { get; init; }
}

