using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;
using DedgeAuth.Client.Options;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Options;
using System.Security.Claims;
using System.Text.Json;
using AutoDocNew.Core;
using AutoDocJson.Web.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();
builder.Services.AddDedgeAuth(builder.Configuration);

builder.Services
    .AddMcpServer()
    .WithHttpTransport()
    .WithToolsFromAssembly(typeof(Program).Assembly);

string searchOutputFolder = builder.Configuration.GetValue<string>("AutoDocJson:OutputFolder")
    ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "Webs", "AutoDocJson");
builder.Services.AddSingleton(new SearchEngine(searchOutputFolder));
builder.Services.AddSingleton<SchedulerService>();

var app = builder.Build();

var DedgeAuthEnabled = app.Services.GetRequiredService<IOptions<DedgeAuthOptions>>().Value.Enabled;

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
}

app.MapMcp("/mcp");

app.UseDedgeAuth();

app.UseDefaultFiles();
app.UseStaticFiles();

string autoDocOutputFolder = app.Configuration.GetValue<string>("AutoDocJson:OutputFolder")
    ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "Webs", "AutoDocJson");

if (Directory.Exists(autoDocOutputFolder))
{
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new PhysicalFileProvider(autoDocOutputFolder),
        RequestPath = "/docs"
    });
}

app.MapRazorPages();
app.MapDedgeAuthProxy();

if (!DedgeAuthEnabled)
{
    app.MapGet("/DedgeAuth/api/tenants/default", () =>
        Results.Ok(new { domain = "default", displayName = "Local", hasLogoData = false, hasIconData = false }));
}

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

// Search API endpoint
app.MapGet("/api/search", (HttpContext ctx, SearchEngine engine) =>
{
    var query = ctx.Request.Query;
    var request = new SearchRequest
    {
        Query = query["q"].FirstOrDefault(),
        Logic = query["logic"].FirstOrDefault() ?? "AND"
    };

    string? typesParam = query["types"].FirstOrDefault();
    if (!string.IsNullOrWhiteSpace(typesParam))
        request.Types = typesParam.Split(',', StringSplitOptions.RemoveEmptyEntries);

    var elements = new List<ElementFilter>();
    for (int i = 0; i < 50; i++)
    {
        string? field = query[$"elements[{i}].field"].FirstOrDefault();
        string? terms = query[$"elements[{i}].terms"].FirstOrDefault();
        if (field == null && terms == null) break;
        elements.Add(new ElementFilter
        {
            Field = field ?? "",
            Terms = (terms ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries)
                .Select(t => t.Trim()).ToArray()
        });
    }
    if (elements.Count > 0)
        request.Elements = elements;

    var results = engine.Search(request);
    return Results.Ok(results);
});

app.MapGet("/api/search/fields", (SearchEngine engine) =>
{
    return Results.Ok(engine.GetAvailableFields());
});

// Scheduler management API
app.MapGet("/api/scheduler/status", (HttpContext ctx, SchedulerService svc) =>
{
    var status = svc.GetStatus();
    var canManage = CanManageScheduler(ctx);
    return Results.Ok(new
    {
        status.Exists,
        status.TaskName,
        status.Status,
        status.IsRunning,
        status.IsEnabled,
        status.State,
        status.LastRunTime,
        status.LastResult,
        status.NextRunTime,
        status.ScheduleType,
        status.Error,
        canManage
    });
}).RequireAuthorization();

app.MapPost("/api/scheduler/start", (HttpContext ctx, SchedulerService svc) =>
{
    if (!CanManageScheduler(ctx)) return Results.Forbid();
    return Results.Ok(svc.RunNow());
}).RequireAuthorization();
app.MapPost("/api/scheduler/stop", (HttpContext ctx, SchedulerService svc) =>
{
    if (!CanManageScheduler(ctx)) return Results.Forbid();
    return Results.Ok(svc.Stop());
}).RequireAuthorization();
app.MapPost("/api/scheduler/enable", (HttpContext ctx, SchedulerService svc) =>
{
    if (!CanManageScheduler(ctx)) return Results.Forbid();
    return Results.Ok(svc.Enable());
}).RequireAuthorization();
app.MapPost("/api/scheduler/disable", (HttpContext ctx, SchedulerService svc) =>
{
    if (!CanManageScheduler(ctx)) return Results.Forbid();
    return Results.Ok(svc.Disable());
}).RequireAuthorization();

string autoDocDataFolder = Path.Combine(
    Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "data", "AutoDocJson");

app.MapPost("/api/scheduler/regenerate-all", (HttpContext ctx, SchedulerService svc) =>
{
    if (!CanManageScheduler(ctx)) return Results.Forbid();
    return Results.Ok(svc.RegenerateAll(autoDocDataFolder));
}).RequireAuthorization();

static bool CanManageScheduler(HttpContext ctx)
{
    var opts = ctx.RequestServices.GetRequiredService<IOptions<DedgeAuthOptions>>().Value;
    if (!opts.Enabled)
        return true;

    var user = ctx.User;
    if (!(user.Identity?.IsAuthenticated ?? false))
        return false;

    var appPermissionsRaw = user.FindFirst("appPermissions")?.Value;
    if (!string.IsNullOrWhiteSpace(appPermissionsRaw))
    {
        try
        {
            var appPermissions = JsonSerializer.Deserialize<Dictionary<string, string>>(appPermissionsRaw);
            if (appPermissions != null &&
                appPermissions.TryGetValue("AutoDocJson", out var role) &&
                string.Equals(role, "Admin", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        catch
        {
        }
    }

    var globalAccess = user.FindFirst("globalAccessLevel")?.Value;
    if (string.Equals(globalAccess, "Admin", StringComparison.OrdinalIgnoreCase))
        return true;
    if (int.TryParse(globalAccess, out var level) && level >= 3)
        return true;

    return false;
}

app.Run();
