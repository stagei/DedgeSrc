using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing SQL query history with encrypted storage
/// </summary>
public class QueryHistoryService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _historyFilePath;
    private List<QueryHistoryItem> _history;
    private readonly int _maxHistoryItems;

    public QueryHistoryService(int maxHistoryItems = 500)
    {
        Logger.Debug("QueryHistoryService initializing");

        _maxHistoryItems = maxHistoryItems;
        _historyFilePath = DetermineHistoryFilePath("query-history.json");

        _history = new List<QueryHistoryItem>();
        LoadHistory();

        Logger.Info($"QueryHistoryService initialized with max {_maxHistoryItems} items");
    }
    
    /// <summary>
    /// Determines the history file path.
    /// </summary>
    private static string DetermineHistoryFilePath(string fileName)
    {
        var path = UserDataFolderHelper.GetFilePath(fileName);
        Logger.Debug("Using {FileName} path: {Path}", fileName, path);
        return path;
    }

    /// <summary>
    /// Add query to history with connection information
    /// </summary>
    public void AddQuery(string sql, string connectionName, string database, bool success, double executionTimeMs, int? rowCount = null)
    {
        Logger.Debug($"Adding query to history: {sql.Substring(0, Math.Min(50, sql.Length))}...");

        try
        {
            var encryptedSql = EncryptSql(sql);
            
            var item = new QueryHistoryItem
            {
                EncryptedSql = encryptedSql,
                ConnectionName = connectionName,
                Database = database,
                ExecutedAt = DateTime.Now,
                Success = success,
                ExecutionTimeMs = executionTimeMs,
                RowCount = rowCount
            };

            _history.Insert(0, item); // Add to beginning

            // Trim history to max items
            if (_history.Count > _maxHistoryItems)
            {
                _history = _history.Take(_maxHistoryItems).ToList();
                Logger.Debug($"Trimmed history to {_maxHistoryItems} items");
            }

            SaveHistory();
            Logger.Info($"Query added to history (total: {_history.Count})");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to add query to history");
        }
    }

    /// <summary>
    /// Encrypt SQL statement using DPAPI
    /// </summary>
    private string EncryptSql(string sql)
    {
        if (string.IsNullOrEmpty(sql))
        {
            return string.Empty;
        }

        try
        {
            var plainBytes = Encoding.UTF8.GetBytes(sql);
            var encryptedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
            return Convert.ToBase64String(encryptedBytes);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to encrypt SQL");
            return string.Empty;
        }
    }

    /// <summary>
    /// Decrypt SQL statement using DPAPI
    /// </summary>
    private string DecryptSql(string encryptedSql)
    {
        if (string.IsNullOrEmpty(encryptedSql))
        {
            return string.Empty;
        }

        try
        {
            var encryptedBytes = Convert.FromBase64String(encryptedSql);
            var decryptedBytes = ProtectedData.Unprotect(encryptedBytes, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(decryptedBytes);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to decrypt SQL");
            return "[Decryption failed]";
        }
    }

    /// <summary>
    /// Get all query history (decrypts SQL on demand)
    /// </summary>
    public List<QueryHistoryItem> GetHistory()
    {
        return _history;
    }

    /// <summary>
    /// Get decrypted SQL for a history item
    /// </summary>
    public string GetDecryptedSql(QueryHistoryItem item)
    {
        return DecryptSql(item.EncryptedSql);
    }

    /// <summary>
    /// Search query history
    /// </summary>
    public List<QueryHistoryItem> SearchHistory(string searchTerm, string? connectionFilter = null)
    {
        var results = _history.AsEnumerable();

        // Filter by connection if specified
        if (!string.IsNullOrEmpty(connectionFilter))
        {
            results = results.Where(item => item.ConnectionName.Equals(connectionFilter, StringComparison.OrdinalIgnoreCase));
        }

        // Search in decrypted SQL if search term provided
        if (!string.IsNullOrWhiteSpace(searchTerm))
        {
            Logger.Debug($"Searching history for: {searchTerm}");
            results = results.Where(item =>
            {
                var decryptedSql = DecryptSql(item.EncryptedSql);
                return decryptedSql.Contains(searchTerm, StringComparison.OrdinalIgnoreCase) ||
                       item.Database.Contains(searchTerm, StringComparison.OrdinalIgnoreCase) ||
                       item.ConnectionName.Contains(searchTerm, StringComparison.OrdinalIgnoreCase);
            });
        }

        var resultList = results.ToList();
        Logger.Debug($"Found {resultList.Count} matching queries");
        return resultList;
    }

    /// <summary>
    /// Clear all history
    /// </summary>
    public void ClearHistory()
    {
        Logger.Info("Clearing query history");
        _history.Clear();
        SaveHistory();
    }

    /// <summary>
    /// Load history from file
    /// </summary>
    private void LoadHistory()
    {
        try
        {
            if (!File.Exists(_historyFilePath))
            {
                Logger.Debug($"History file not found: {_historyFilePath}");
                return;
            }

            var json = File.ReadAllText(_historyFilePath);
            _history = JsonSerializer.Deserialize<List<QueryHistoryItem>>(json) ?? new List<QueryHistoryItem>();

            Logger.Info($"Loaded {_history.Count} queries from history");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load query history");
            _history = new List<QueryHistoryItem>();
        }
    }

    /// <summary>
    /// Save history to file
    /// </summary>
    private void SaveHistory()
    {
        try
        {
            var directory = Path.GetDirectoryName(_historyFilePath);
            if (directory != null && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
                Logger.Debug($"Created history directory: {directory}");
            }

            var json = JsonSerializer.Serialize(_history, new JsonSerializerOptions
            {
                WriteIndented = true
            });

            File.WriteAllText(_historyFilePath, json);
            Logger.Debug($"Saved {_history.Count} queries to history file");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save query history");
        }
    }
}

/// <summary>
/// Model for query history item with encrypted SQL
/// </summary>
public class QueryHistoryItem
{
    public string EncryptedSql { get; set; } = string.Empty;
    public string ConnectionName { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public DateTime ExecutedAt { get; set; }
    public bool Success { get; set; }
    public double ExecutionTimeMs { get; set; }
    public int? RowCount { get; set; }
}

