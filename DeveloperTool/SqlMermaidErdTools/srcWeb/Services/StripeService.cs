using ProductStore.Models;

namespace ProductStore.Services;

public interface IStripeService
{
    Task<string> CreateCheckoutSessionAsync(string productId, string tier, string userEmail);
}

public class StripeService : IStripeService
{
    private readonly IProductService _productService;
    private readonly ILogger<StripeService> _logger;
    private readonly IConfiguration _configuration;

    public StripeService(
        IProductService productService,
        ILogger<StripeService> logger,
        IConfiguration configuration)
    {
        _productService = productService;
        _logger = logger;
        _configuration = configuration;
    }

    public async Task<string> CreateCheckoutSessionAsync(string productId, string tier, string userEmail)
    {
        var catalog = await _productService.GetCatalogAsync();
        var product = await _productService.GetProductByIdAsync(productId);

        if (product == null)
        {
            throw new ArgumentException($"Product {productId} not found");
        }

        if (!product.Pricing.TryGetValue(tier, out var pricing) || pricing == null)
        {
            throw new ArgumentException($"Tier {tier} not available for product {productId}");
        }

        if (string.IsNullOrEmpty(pricing.StripePriceId))
        {
            throw new InvalidOperationException($"No Stripe price ID configured for {productId} - {tier}");
        }

        // Note: In a real implementation, you would use the Stripe .NET SDK here:
        // var options = new SessionCreateOptions
        // {
        //     Mode = "payment", // or "subscription" for recurring
        //     LineItems = new List<SessionLineItemOptions>
        //     {
        //         new SessionLineItemOptions
        //         {
        //             Price = pricing.StripePriceId,
        //             Quantity = 1,
        //         },
        //     },
        //     CustomerEmail = userEmail,
        //     SuccessUrl = catalog.Stripe.SuccessUrl,
        //     CancelUrl = catalog.Stripe.CancelUrl,
        //     Metadata = new Dictionary<string, string>
        //     {
        //         { "product_id", productId },
        //         { "tier", tier }
        //     }
        // };
        //
        // var service = new SessionService();
        // var session = await service.CreateAsync(options);
        // return session.Url;

        // For now, return a placeholder checkout URL
        var checkoutUrl = $"/checkout.html?product={productId}&tier={tier}&email={userEmail}";
        
        _logger.LogInformation(
            "Created checkout session for product: {ProductId}, tier: {Tier}, price ID: {PriceId}",
            productId, tier, pricing.StripePriceId);

        return checkoutUrl;
    }
}

