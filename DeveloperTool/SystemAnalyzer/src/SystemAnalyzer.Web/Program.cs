using DedgeAuth.Client.Endpoints;
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Options;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi;
using Scalar.AspNetCore;
using SystemAnalyzer.Core.Models;
using SystemAnalyzer.Core.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<SystemAnalyzerOptions>(builder.Configuration.GetSection("SystemAnalyzer"));
builder.Services.AddSingleton<AnalysisIndexService>();
builder.Services.AddSingleton<JsonDataService>();
builder.Services.AddSingleton<SystemAnalyzerJobService>();
builder.Services.AddControllers();

builder.Services.AddDedgeAuth(builder.Configuration);
builder.Services.AddAuthorization();

builder.Services.AddOpenApi("v1", options =>
{
    options.AddDocumentTransformer((document, _, _) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "SystemAnalyzer API",
            Version = "v1",
            Description = "SystemAnalyzer analysis browse and orchestration API"
        };
        return Task.CompletedTask;
    });
});

var app = builder.Build();

app.UseDedgeAuth();
app.UseDefaultFiles();

if (app.Environment.IsDevelopment())
{
    app.UseStaticFiles(new StaticFileOptions
    {
        OnPrepareResponse = ctx =>
            ctx.Context.Response.Headers.CacheControl = "no-cache, no-store, must-revalidate"
    });
}
else
{
    app.UseStaticFiles();
}

app.MapControllers();
app.MapDedgeAuthProxy();

var DedgeAuthOpts = app.Services.GetRequiredService<IOptions<DedgeAuthOptions>>().Value;
if (!DedgeAuthOpts.Enabled)
{
    app.MapGet("/DedgeAuth/api/tenants/default", () =>
        Results.Ok(new { domain = "default", displayName = "Local", hasLogoData = false, hasIconData = false }));
}

app.MapOpenApi();
app.MapScalarApiReference();
app.MapGet("/health", () => Results.Ok(new { ok = true }));

app.Run();
