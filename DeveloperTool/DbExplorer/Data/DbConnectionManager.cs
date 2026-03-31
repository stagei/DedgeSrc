using System;
using System.Data;
using System.Data.Common;
using System.Threading.Tasks;
using IBM.Data.Db2;
using NLog;
using DbExplorer.Models;
using DbExplorer.Services;
using Db2Conn = IBM.Data.Db2.DB2Connection;
using ConnectionProfile = DbExplorer.Models.SavedConnection;

namespace DbExplorer.Data;

/// <summary>
/// Provider-agnostic database connection manager
/// Supports multiple database providers through runtime dispatch
/// </summary>
public class DbConnectionManager : IDisposable
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _provider;
    private readonly string _version;
    private DbConnection? _connection;
    private readonly MetadataHandler? _metadataHandler;
    private bool _disposed;
    
    // DB2-specific connection (for now, only DB2 is supported)
    private Db2Conn? _db2Connection;
    
    public string Provider => _provider;
    public string Version => _version;
    public bool IsConnected => _connection?.State == ConnectionState.Open;
    public UserAccessLevel UserAccessLevel { get; private set; } = UserAccessLevel.Standard;
    
    public DbConnectionManager(ConnectionProfile profile, MetadataHandler? metadataHandler = null)
    {
        _provider = profile.Provider ?? "DB2";
        _version = profile.Version ?? "12.1";
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
        
        Logger.Debug("DbConnectionManager initializing - Provider: {Provider}, Version: {Version}", _provider, _version);
        
        // Initialize provider-specific connection
        InitializeProviderConnection(profile);
    }
    
    private void InitializeProviderConnection(ConnectionProfile profile)
    {
        switch (_provider.ToUpperInvariant())
        {
            case "DB2":
                InitializeDb2Connection(profile);
                break;
            default:
                throw new NotSupportedException($"Database provider '{_provider}' is not supported");
        }
    }
    
    private void InitializeDb2Connection(ConnectionProfile profile)
    {
        Logger.Debug("Initializing DB2 connection");
        
        var connectionString = BuildDb2ConnectionString(profile);
        _db2Connection = new Db2Conn(connectionString);
        _connection = _db2Connection;
        
        Logger.Debug("DB2 connection initialized");
    }
    
    private string BuildDb2ConnectionString(ConnectionProfile profile)
    {
        var maskedPwd = string.IsNullOrEmpty(profile.Password) ? "" : "***";
        Logger.Debug("Building DB2 connection string - Server: {Server}:{Port}, Database: {Database}, User: {User}, Password: {Pwd}",
                     profile.Server, profile.Port, profile.Database, profile.Username, maskedPwd);
        
        return $"Server={profile.Server}:{profile.Port};Database={profile.Database};UID={profile.Username};PWD={profile.Password};ConnectTimeout=30;";
    }
    
    public async Task<bool> OpenAsync()
    {
        Logger.Info("Opening database connection - Provider: {Provider}", _provider);
        
        try
        {
            if (_connection == null)
            {
                Logger.Error("Connection object is null");
                return false;
            }
            
            await _connection.OpenAsync();
            Logger.Info("Database connection opened successfully - State: {State}", _connection.State);
            
            // Determine user access level
            await DetermineUserAccessLevelAsync();
            
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open database connection");
            return false;
        }
    }
    
    private async Task DetermineUserAccessLevelAsync()
    {
        Logger.Debug("Determining user access level");
        
        try
        {
            // TODO: Implement access level determination
            // For now, default to Standard
            UserAccessLevel = UserAccessLevel.Standard;
            Logger.Info("User access level set to: {Level}", UserAccessLevel);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to determine user access level, defaulting to Standard");
            UserAccessLevel = UserAccessLevel.Standard;
        }
    }
    
    public async Task<string> GetCurrentUserAsync()
    {
        try
        {
            var sql = GetQuery("GetCurrentUser") ?? "SELECT CURRENT USER FROM SYSIBM.SYSDUMMY1";
            using var command = CreateCommand(sql);
            var result = await command.ExecuteScalarAsync();
            return result?.ToString()?.Trim() ?? "UNKNOWN";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get current user");
            return "UNKNOWN";
        }
    }
    
    public string? GetQuery(string statementKey)
    {
        if (_metadataHandler != null)
        {
            var query = _metadataHandler.GetQuery(_provider, _version, statementKey);
            if (!string.IsNullOrEmpty(query))
            {
                Logger.Debug("Retrieved query from MetadataHandler: {Key}", statementKey);
                return query;
            }
        }
        
        Logger.Warn("Query not found in MetadataHandler: {Key}", statementKey);
        return null;
    }
    
    public DbCommand CreateCommand(string sql)
    {
        if (_connection == null)
        {
            throw new InvalidOperationException("Connection is not initialized");
        }
        
        var command = _connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = 30;
        
        return command;
    }
    
    public async Task<DataTable> ExecuteQueryAsync(string sql, int maxRows = 0, int offset = 0)
    {
        Logger.Info("Executing SQL query");
        Logger.Debug("SQL: {Sql}... MaxRows: {MaxRows}, Offset: {Offset}", 
                     sql.Substring(0, Math.Min(100, sql.Length)), maxRows, offset);
        
        try
        {
            var dataTable = new DataTable("Results");
            
            using var command = CreateCommand(sql);
            
            switch (_provider.ToUpperInvariant())
            {
                case "DB2":
                    await ExecuteDb2QueryAsync(command, dataTable);
                    break;
                default:
                    throw new NotSupportedException($"Provider '{_provider}' not supported");
            }
            
            Logger.Info("Query executed successfully, {Count} rows returned", dataTable.Rows.Count);
            return dataTable;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to execute query");
            throw;
        }
    }
    
    private async Task ExecuteDb2QueryAsync(DbCommand command, DataTable dataTable)
    {
        using var adapter = new DB2DataAdapter((DB2Command)command);
        await Task.Run(() => adapter.Fill(dataTable));
    }
    
    public void Close()
    {
        if (_connection != null && _connection.State == ConnectionState.Open)
        {
            Logger.Info("Closing database connection");
            _connection.Close();
            Logger.Info("Database connection closed successfully");
        }
    }
    
    public void Dispose()
    {
        if (_disposed) return;
        
        Logger.Debug("Disposing DbConnectionManager");
        Close();
        _connection?.Dispose();
        _disposed = true;
    }
}

