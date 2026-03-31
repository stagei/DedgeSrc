using Microsoft.AspNetCore.Mvc;
using SqlMermaidApi.Models;
using SqlMermaidApi.Services;

namespace SqlMermaidApi.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public class ConversionController : ControllerBase
{
    private readonly IConversionService _conversionService;
    private readonly IApiKeyService _apiKeyService;
    private readonly ILogger<ConversionController> _logger;

    public ConversionController(
        IConversionService conversionService,
        IApiKeyService apiKeyService,
        ILogger<ConversionController> logger)
    {
        _conversionService = conversionService;
        _apiKeyService = apiKeyService;
        _logger = logger;
    }

    /// <summary>
    /// Convert SQL DDL to Mermaid ERD
    /// </summary>
    [HttpPost("sql-to-mermaid")]
    [ProducesResponseType(typeof(ConversionResponse), 200)]
    [ProducesResponseType(typeof(ApiErrorResponse), 400)]
    [ProducesResponseType(401)]
    public async Task<IActionResult> SqlToMermaid([FromBody] ConvertSqlToMmdRequest request)
    {
        var apiKey = HttpContext.Items["ApiKey"]?.ToString();
        if (apiKey == null)
        {
            return Unauthorized(new ApiErrorResponse 
            { 
                Error = "Unauthorized", 
                StatusCode = 401 
            });
        }

        // KRAKEN dev mode - unlimited access
        var tableLimit = int.MaxValue;
        if (apiKey != "KRAKEN-DEV-MODE")
        {
            var keyInfo = await _apiKeyService.GetApiKeyInfoAsync(apiKey);
            tableLimit = keyInfo.TableLimit;
        }

        var result = await _conversionService.ConvertSqlToMermaidAsync(
            request.Sql, 
            request.IncludeAst, 
            tableLimit);

        if (!result.Success)
        {
            return BadRequest(new ApiErrorResponse 
            { 
                Error = result.Error ?? "Conversion failed",
                StatusCode = 400 
            });
        }

        return Ok(result);
    }

    /// <summary>
    /// Convert Mermaid ERD to SQL DDL
    /// </summary>
    [HttpPost("mermaid-to-sql")]
    [ProducesResponseType(typeof(ConversionResponse), 200)]
    [ProducesResponseType(typeof(ApiErrorResponse), 400)]
    [ProducesResponseType(401)]
    public async Task<IActionResult> MermaidToSql([FromBody] ConvertMmdToSqlRequest request)
    {
        var apiKey = HttpContext.Items["ApiKey"]?.ToString();
        if (apiKey == null)
        {
            return Unauthorized(new ApiErrorResponse 
            { 
                Error = "Unauthorized", 
                StatusCode = 401 
            });
        }

        // KRAKEN dev mode - unlimited access
        var tableLimit = int.MaxValue;
        if (apiKey != "KRAKEN-DEV-MODE")
        {
            var keyInfo = await _apiKeyService.GetApiKeyInfoAsync(apiKey);
            tableLimit = keyInfo.TableLimit;
        }
        
        var result = await _conversionService.ConvertMermaidToSqlAsync(
            request.Mermaid, 
            request.Dialect, 
            request.IncludeAst, 
            tableLimit);

        if (!result.Success)
        {
            return BadRequest(new ApiErrorResponse 
            { 
                Error = result.Error ?? "Conversion failed",
                StatusCode = 400 
            });
        }

        return Ok(result);
    }

    /// <summary>
    /// Generate SQL migration from Mermaid diff
    /// </summary>
    [HttpPost("generate-migration")]
    [ProducesResponseType(typeof(ConversionResponse), 200)]
    [ProducesResponseType(typeof(ApiErrorResponse), 400)]
    [ProducesResponseType(401)]
    public async Task<IActionResult> GenerateMigration([FromBody] GenerateMigrationRequest request)
    {
        var apiKey = HttpContext.Items["ApiKey"]?.ToString();
        if (apiKey == null)
        {
            return Unauthorized(new ApiErrorResponse 
            { 
                Error = "Unauthorized", 
                StatusCode = 401 
            });
        }

        // KRAKEN dev mode - unlimited access
        var tableLimit = int.MaxValue;
        if (apiKey != "KRAKEN-DEV-MODE")
        {
            var keyInfo = await _apiKeyService.GetApiKeyInfoAsync(apiKey);
            tableLimit = keyInfo.TableLimit;
        }
        
        var result = await _conversionService.GenerateMigrationAsync(
            request.BeforeMermaid, 
            request.AfterMermaid, 
            request.Dialect, 
            tableLimit);

        if (!result.Success)
        {
            return BadRequest(new ApiErrorResponse 
            { 
                Error = result.Error ?? "Migration generation failed",
                StatusCode = 400 
            });
        }

        return Ok(result);
    }
}

