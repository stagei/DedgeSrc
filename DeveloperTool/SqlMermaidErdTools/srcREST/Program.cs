using SqlMermaidApi.Middleware;
using SqlMermaidApi.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Configure API keys file path
builder.Configuration["ApiKeysFilePath"] = Path.Combine(
    builder.Environment.ContentRootPath,
    "apikeys.json");

// Add custom services
builder.Services.AddSingleton<IApiKeyService, ApiKeyService>();
builder.Services.AddScoped<IConversionService, ConversionService>();

var app = builder.Build();

// Configure middleware pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();

// Add API key authentication middleware
app.UseApiKeyAuthentication();

app.UseAuthorization();

app.MapControllers();

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new 
{ 
    status = "healthy", 
    service = "SqlMermaid ERD Tools API",
    version = "1.0.0",
    timestamp = DateTime.UtcNow 
}))
.WithName("HealthCheck")
.WithTags("Health");

app.Logger.LogInformation("SqlMermaid API started");
app.Logger.LogInformation("Swagger UI available at: /swagger");
app.Logger.LogInformation("API Base URL: http://localhost:{Port}/api/v1", 
    app.Configuration["ASPNETCORE_URLS"] ?? "5001");

app.Run();
