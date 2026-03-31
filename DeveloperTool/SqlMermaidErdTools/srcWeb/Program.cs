using ProductStore.Services;
using Microsoft.AspNetCore.StaticFiles;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddSingleton<IProductService, ProductService>();
builder.Services.AddScoped<IStripeService, StripeService>();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Configure products file path
builder.Configuration["ProductsFilePath"] = Path.Combine(
    builder.Environment.ContentRootPath, 
    "products.json");

var app = builder.Build();

// Enable CORS
app.UseCors();

// Configure static files
var provider = new FileExtensionContentTypeProvider();
provider.Mappings[".mmd"] = "text/plain";
app.UseDefaultFiles();
app.UseStaticFiles(new StaticFileOptions
{
    ContentTypeProvider = provider
});

// API Endpoints
app.MapGet("/api/products", async (IProductService productService) =>
{
    var catalog = await productService.GetCatalogAsync();
    return Results.Ok(new 
    { 
        products = catalog.Products.Where(p => p.IsActive).ToList(),
        categories = catalog.Categories,
        metadata = catalog.Metadata
    });
})
.WithName("GetAllProducts")
.WithTags("Products");

app.MapGet("/api/products/{id}", async (string id, IProductService productService) =>
{
    var product = await productService.GetProductByIdAsync(id);
    return product != null 
        ? Results.Ok(product) 
        : Results.NotFound(new { error = $"Product '{id}' not found" });
})
.WithName("GetProductById")
.WithTags("Products");

app.MapGet("/api/products/category/{category}", async (string category, IProductService productService) =>
{
    var products = await productService.GetProductsByCategoryAsync(category);
    return Results.Ok(new { category, products });
})
.WithName("GetProductsByCategory")
.WithTags("Products");

app.MapGet("/api/products/featured", async (IProductService productService) =>
{
    var products = await productService.GetFeaturedProductsAsync();
    return Results.Ok(new { products });
})
.WithName("GetFeaturedProducts")
.WithTags("Products");

app.MapGet("/api/products/search", async (string? q, IProductService productService) =>
{
    var products = await productService.SearchProductsAsync(q ?? "");
    return Results.Ok(new { query = q, products });
})
.WithName("SearchProducts")
.WithTags("Products");

app.MapGet("/api/health", () => Results.Ok(new 
{ 
    status = "healthy", 
    timestamp = DateTime.UtcNow 
}))
.WithName("HealthCheck")
.WithTags("Health");

// Stripe Checkout Endpoint
app.MapPost("/api/checkout/create-session", async (
    CheckoutRequest request,
    IStripeService stripeService) =>
{
    try
    {
        var checkoutUrl = await stripeService.CreateCheckoutSessionAsync(
            request.ProductId,
            request.Tier,
            request.Email);
        
        return Results.Ok(new { checkoutUrl });
    }
    catch (Exception ex)
    {
        app.Logger.LogError(ex, "Failed to create checkout session");
        return Results.BadRequest(new { error = ex.Message });
    }
})
.WithName("CreateCheckoutSession")
.WithTags("Stripe");

app.Logger.LogInformation("Product Store API started");
app.Logger.LogInformation("API available at: http://localhost:{Port}/api/products", 
    app.Configuration["ASPNETCORE_URLS"] ?? "5000");

app.Run();

// Request DTOs
record CheckoutRequest(string ProductId, string Tier, string Email);
