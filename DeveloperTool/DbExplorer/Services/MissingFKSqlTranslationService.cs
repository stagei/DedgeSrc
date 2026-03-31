using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Service for retrieving SQL statements for Missing FK Discovery.
/// Delegates to MetadataHandler which handles all provider-specific SQL loading.
/// This service is provider-agnostic - MetadataHandler centralizes provider awareness.
/// </summary>
public class MissingFKSqlTranslationService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    private readonly Dictionary<string, string> _cache = new();
    
    public MissingFKSqlTranslationService(MetadataHandler? metadataHandler = null)
    {
        _metadataHandler = metadataHandler ?? new MetadataHandler();
        Logger.Debug("MissingFKSqlTranslationService initialized");
    }
    
    // Legacy constructor for backward compatibility
    public MissingFKSqlTranslationService(SqlMermaidIntegrationService? sqlMermaidService, MetadataHandler? metadataHandler = null)
        : this(metadataHandler)
    {
        // sqlMermaidService no longer needed - MetadataHandler provides provider-specific SQL
    }
    
    /// <summary>
    /// Get SQL statement from MetadataHandler.
    /// MetadataHandler handles all provider/version awareness - this service is provider-agnostic.
    /// </summary>
    /// <param name="connectionManager">Connection manager (unused - MetadataHandler knows current provider)</param>
    /// <param name="statementName">Name of the SQL statement to retrieve</param>
    /// <returns>Provider-specific SQL statement from MetadataHandler</returns>
    public Task<string> GetTranslatedStatementAsync(IConnectionManager connectionManager, string statementName)
    {
        Logger.Debug("Getting SQL statement: {Statement}", statementName);
        
        // Check cache first
        if (_cache.TryGetValue(statementName, out var cachedSql))
        {
            Logger.Debug("Returning cached SQL for {Statement}", statementName);
            return Task.FromResult(cachedSql);
        }
        
        // Use MetadataHandler - it knows the current provider/version from connection context
        try
        {
            var sql = _metadataHandler.GetStatement(statementName);
            Logger.Debug("Loaded SQL for {Statement} via MetadataHandler ({Length} chars)", statementName, sql.Length);
            _cache[statementName] = sql;
            return Task.FromResult(sql);
        }
        catch (KeyNotFoundException ex)
        {
            Logger.Error(ex, "SQL statement {Statement} not found", statementName);
            throw;
        }
    }
    
    /// <summary>
    /// Clear cache (useful for testing or when SQL statements are updated).
    /// </summary>
    public void ClearCache()
    {
        _cache.Clear();
        Logger.Debug("Cache cleared");
    }
}
