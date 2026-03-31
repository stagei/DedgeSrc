using System.Text.Json.Serialization;
using Microsoft.OpenApi;
using Scalar.AspNetCore;
using Serilog;
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;
using AiDoc.WebNew.Options;
using AiDoc.WebNew.Services;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/aidoc-webnew-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();
builder.Host.UseWindowsService();

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 200_000_000;
});

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
        options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
    });

builder.Services.Configure<AiDocOptions>(builder.Configuration.GetSection("AiDoc"));
builder.Services.AddSingleton<RagManagementService>();
builder.Services.AddSingleton<EnvironmentService>();
builder.Services.AddSingleton<IndexBuildService>();
builder.Services.AddSingleton<ServiceManagementService>();
builder.Services.AddSingleton<BackupService>();
builder.Services.AddSingleton<OllamaQueryService>();
builder.Services.AddSingleton<ConfigurationService>();
builder.Services.AddHttpClient("RagProxy", client =>
{
    client.Timeout = TimeSpan.FromSeconds(30);
});
builder.Services.AddHttpClient("OllamaClient", client =>
{
    client.Timeout = TimeSpan.FromSeconds(120);
});

builder.Services.AddDedgeAuth(builder.Configuration);

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("UserAccess", policy =>
        policy.RequireAssertion(context =>
        {
            var levelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            return int.TryParse(levelClaim, out var level) && level >= 1;
        }));

    options.AddPolicy("AdminAccess", policy =>
        policy.RequireAssertion(context =>
        {
            var levelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            return int.TryParse(levelClaim, out var level) && level >= 3;
        }));
});

builder.Services.AddOpenApi("v1", options =>
{
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "AiDocNew RAG Management API",
            Version = "v1",
            Description = "REST API for managing RAG indexes, sources, and AI platform integrations",
            Contact = new OpenApiContact
            {
                Name = "AiDoc Team",
                Email = "geir.helge.starholm@Dedge.no"
            }
        };

        var bearerScheme = new OpenApiSecurityScheme
        {
            Name = "Authorization",
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            In = ParameterLocation.Header,
            Description = "DedgeAuth JWT token"
        };

        document.Components ??= new OpenApiComponents();
        document.AddComponent("Bearer", bearerScheme);

        var securityRequirement = new OpenApiSecurityRequirement
        {
            [new OpenApiSecuritySchemeReference("Bearer", document)] = new List<string>()
        };

        foreach (var operation in document.Paths?.Values
            .Where(path => path.Operations is not null)
            .SelectMany(path => path.Operations!) ?? [])
        {
            operation.Value.Security ??= new List<OpenApiSecurityRequirement>();
            operation.Value.Security.Add(securityRequirement);
        }

        return Task.CompletedTask;
    });
});

builder.Services.AddHealthChecks();

var app = builder.Build();

var pathBase = builder.Configuration["PathBase"] ?? "";
if (!string.IsNullOrEmpty(pathBase))
    app.UsePathBase(pathBase);

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseDedgeAuth();

app.UseDefaultFiles();
app.UseStaticFiles();

app.UseSerilogRequestLogging();

app.MapControllers();
app.MapDedgeAuthProxy();

app.MapOpenApi();
app.MapScalarApiReference();

app.MapHealthChecks("/health");

// SPA fallback: serve index.html for any route not matched by controllers or static files
app.MapFallbackToFile("index.html");

Log.Information("AiDoc WebNew v{Version} starting...",
    typeof(Program).Assembly.GetName().Version?.ToString() ?? "?");
await app.RunAsync();
Log.Information("AiDoc WebNew stopped");
Log.CloseAndFlush();
