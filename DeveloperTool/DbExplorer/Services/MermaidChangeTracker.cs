using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Represents a tracked table entry in the Mermaid diagram with hash-based change detection.
/// </summary>
public class TableMermaidEntry
{
    public string TableName { get; set; } = string.Empty;
    public string OriginalMermaidCode { get; set; } = string.Empty;
    public string OriginalHash { get; set; } = string.Empty;
    public string CurrentMermaidCode { get; set; } = string.Empty;
    public string CurrentHash { get; set; } = string.Empty;
    
    /// <summary>
    /// Returns true if the current code differs from the original.
    /// </summary>
    public bool HasChanges => !string.Equals(OriginalHash, CurrentHash, StringComparison.Ordinal);
    
    /// <summary>
    /// Returns true if this table was added after initial generation.
    /// </summary>
    public bool IsNewTable { get; set; }
    
    /// <summary>
    /// Returns true if this table was removed from the diagram.
    /// </summary>
    public bool IsRemoved { get; set; }
}

/// <summary>
/// Event args for change detection events.
/// </summary>
public class MermaidChangeEventArgs : EventArgs
{
    public bool HasChanges { get; set; }
    public int ChangedTableCount { get; set; }
    public int NewTableCount { get; set; }
    public int RemovedTableCount { get; set; }
    public List<string> ChangedTables { get; set; } = new();
    public List<string> NewTables { get; set; } = new();
    public List<string> RemovedTables { get; set; } = new();
}

/// <summary>
/// Service to track changes in Mermaid ERD code with per-table hash comparison.
/// Enables precise detection of which tables have been modified, added, or removed.
/// </summary>
public class MermaidChangeTracker
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    // Original tables from database load
    private readonly Dictionary<string, TableMermaidEntry> _originalTables = new();
    
    // Current state of all tables (including user modifications)
    private readonly Dictionary<string, TableMermaidEntry> _currentTables = new();
    
    // Relationship tracking
    private readonly List<string> _originalRelationships = new();
    private readonly List<string> _currentRelationships = new();
    
    /// <summary>
    /// Event fired when change status changes (enables/disables diff buttons).
    /// </summary>
    public event EventHandler<MermaidChangeEventArgs>? ChangeStatusChanged;
    
    /// <summary>
    /// Returns true if any changes exist compared to original.
    /// </summary>
    public bool HasAnyChanges => GetChangeStatus().HasChanges;
    
    /// <summary>
    /// Initialize tracking with original Mermaid code from database.
    /// Called when user first loads tables from DB.
    /// </summary>
    public void InitializeFromOriginal(string mermaidCode, List<string> selectedTables)
    {
        Logger.Info("=== MermaidChangeTracker.InitializeFromOriginal START ===");
        Logger.Info("Initializing change tracker with {Count} tables", selectedTables.Count);
        Logger.Debug("Tables: {Tables}", string.Join(", ", selectedTables));
        Logger.Debug("Mermaid code length: {Length} chars", mermaidCode?.Length ?? 0);
        
        if (string.IsNullOrEmpty(mermaidCode))
        {
            Logger.Warn("Mermaid code is null or empty!");
        }
        
        _originalTables.Clear();
        _currentTables.Clear();
        _originalRelationships.Clear();
        _currentRelationships.Clear();
        
        // Parse the Mermaid code into per-table blocks
        var parsedTables = ParseMermaidIntoTables(mermaidCode);
        var relationships = ParseMermaidRelationships(mermaidCode);
        
        _originalRelationships.AddRange(relationships);
        _currentRelationships.AddRange(relationships);
        
        foreach (var tableName in selectedTables)
        {
            var tableCode = parsedTables.GetValueOrDefault(ExtractTableName(tableName), string.Empty);
            var hash = ComputeHash(tableCode);
            
            var entry = new TableMermaidEntry
            {
                TableName = tableName,
                OriginalMermaidCode = tableCode,
                OriginalHash = hash,
                CurrentMermaidCode = tableCode,
                CurrentHash = hash,
                IsNewTable = false,
                IsRemoved = false
            };
            
            _originalTables[tableName] = entry;
            _currentTables[tableName] = CloneEntry(entry);
            
            Logger.Debug("Tracking table {Table} with hash {Hash}", tableName, 
                string.IsNullOrEmpty(hash) ? "(empty)" : hash.Substring(0, Math.Min(8, hash.Length)));
        }
        
        Logger.Info("Change tracker initialized - {TableCount} tables, {RelCount} relationships",
            _originalTables.Count, _originalRelationships.Count);
        
        // Fire initial status (no changes)
        OnChangeStatusChanged();
    }
    
    /// <summary>
    /// Add new tables to tracking (when user adds more tables later).
    /// </summary>
    public void AddNewTables(string mermaidCode, List<string> newTables)
    {
        Logger.Info("Adding {Count} new tables to tracker", newTables.Count);
        
        var parsedTables = ParseMermaidIntoTables(mermaidCode);
        var relationships = ParseMermaidRelationships(mermaidCode);
        
        // Update relationships
        _currentRelationships.Clear();
        _currentRelationships.AddRange(relationships);
        
        foreach (var tableName in newTables)
        {
            if (_currentTables.ContainsKey(tableName))
            {
                Logger.Debug("Table {Table} already tracked, skipping", tableName);
                continue;
            }
            
            var tableCode = parsedTables.GetValueOrDefault(ExtractTableName(tableName), string.Empty);
            var hash = ComputeHash(tableCode);
            
            var entry = new TableMermaidEntry
            {
                TableName = tableName,
                OriginalMermaidCode = string.Empty, // New table has no original
                OriginalHash = string.Empty,
                CurrentMermaidCode = tableCode,
                CurrentHash = hash,
                IsNewTable = true, // Mark as new
                IsRemoved = false
            };
            
            _currentTables[tableName] = entry;
            
            Logger.Debug("Added new table {Table} with hash {Hash}", tableName, 
                string.IsNullOrEmpty(hash) ? "(empty)" : hash.Substring(0, Math.Min(8, hash.Length)));
        }
        
        OnChangeStatusChanged();
    }
    
    /// <summary>
    /// Update current state from editor content.
    /// Called whenever editor content changes (debounced).
    /// </summary>
    public void UpdateFromEditor(string currentMermaidCode)
    {
        if (string.IsNullOrEmpty(currentMermaidCode))
        {
            Logger.Debug("Empty Mermaid code received, skipping update");
            return;
        }
        
        Logger.Debug("Updating tracker from editor content ({Length} chars)", currentMermaidCode.Length);
        
        var parsedTables = ParseMermaidIntoTables(currentMermaidCode);
        var relationships = ParseMermaidRelationships(currentMermaidCode);
        
        // Update relationships
        _currentRelationships.Clear();
        _currentRelationships.AddRange(relationships);
        
        // Track which tables are in the current code
        var tablesInCurrentCode = new HashSet<string>(parsedTables.Keys);
        
        // Update existing tracked tables
        foreach (var kvp in _currentTables.ToList())
        {
            var shortName = ExtractTableName(kvp.Key);
            
            if (parsedTables.TryGetValue(shortName, out var tableCode))
            {
                // Table still exists - update its current code
                kvp.Value.CurrentMermaidCode = tableCode;
                kvp.Value.CurrentHash = ComputeHash(tableCode);
                kvp.Value.IsRemoved = false;
            }
            else
            {
                // Table was removed from editor
                kvp.Value.CurrentMermaidCode = string.Empty;
                kvp.Value.CurrentHash = string.Empty;
                kvp.Value.IsRemoved = true;
                
                Logger.Debug("Table {Table} removed from editor", kvp.Key);
            }
        }
        
        // Check for completely new tables in editor (user typed them manually)
        foreach (var tableName in parsedTables.Keys)
        {
            var fullName = FindFullTableName(tableName);
            if (fullName == null)
            {
                // This is a manually typed table not in our tracking
                var tableCode = parsedTables[tableName];
                var hash = ComputeHash(tableCode);
                
                var entry = new TableMermaidEntry
                {
                    TableName = tableName,
                    OriginalMermaidCode = string.Empty,
                    OriginalHash = string.Empty,
                    CurrentMermaidCode = tableCode,
                    CurrentHash = hash,
                    IsNewTable = true,
                    IsRemoved = false
                };
                
                _currentTables[tableName] = entry;
                Logger.Debug("Detected manually added table: {Table}", tableName);
            }
        }
        
        OnChangeStatusChanged();
    }
    
    /// <summary>
    /// Get the current change status.
    /// </summary>
    public MermaidChangeEventArgs GetChangeStatus()
    {
        var changedTables = _currentTables.Values
            .Where(t => !t.IsNewTable && !t.IsRemoved && t.HasChanges)
            .Select(t => t.TableName)
            .ToList();
        
        var newTables = _currentTables.Values
            .Where(t => t.IsNewTable && !t.IsRemoved)
            .Select(t => t.TableName)
            .ToList();
        
        var removedTables = _currentTables.Values
            .Where(t => t.IsRemoved)
            .Select(t => t.TableName)
            .ToList();
        
        // Also check for relationship changes
        var relationshipsChanged = !_originalRelationships.SequenceEqual(_currentRelationships);
        
        var hasChanges = changedTables.Any() || newTables.Any() || removedTables.Any() || relationshipsChanged;
        
        return new MermaidChangeEventArgs
        {
            HasChanges = hasChanges,
            ChangedTableCount = changedTables.Count,
            NewTableCount = newTables.Count,
            RemovedTableCount = removedTables.Count,
            ChangedTables = changedTables,
            NewTables = newTables,
            RemovedTables = removedTables
        };
    }
    
    /// <summary>
    /// Get list of all currently tracked tables.
    /// </summary>
    public List<string> GetTrackedTables()
    {
        return _currentTables.Keys.ToList();
    }
    
    /// <summary>
    /// Get original Mermaid code for a specific table.
    /// </summary>
    public string? GetOriginalTableCode(string tableName)
    {
        return _originalTables.TryGetValue(tableName, out var entry) ? entry.OriginalMermaidCode : null;
    }
    
    /// <summary>
    /// Get current Mermaid code for a specific table.
    /// </summary>
    public string? GetCurrentTableCode(string tableName)
    {
        return _currentTables.TryGetValue(tableName, out var entry) ? entry.CurrentMermaidCode : null;
    }
    
    /// <summary>
    /// Clear all tracking data.
    /// </summary>
    public void Clear()
    {
        _originalTables.Clear();
        _currentTables.Clear();
        _originalRelationships.Clear();
        _currentRelationships.Clear();
        
        Logger.Debug("Change tracker cleared");
        OnChangeStatusChanged();
    }
    
    /// <summary>
    /// Parse Mermaid ERD code into per-table dictionary.
    /// </summary>
    private Dictionary<string, string> ParseMermaidIntoTables(string mermaidCode)
    {
        var tables = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        
        if (string.IsNullOrWhiteSpace(mermaidCode))
            return tables;
        
        // Match table definitions: TableName { ... }
        var tablePattern = new Regex(
            @"^\s*(\w+)\s*\{([^}]*)\}",
            RegexOptions.Multiline | RegexOptions.Singleline);
        
        var matches = tablePattern.Matches(mermaidCode);
        
        foreach (Match match in matches)
        {
            var tableName = match.Groups[1].Value.Trim();
            var tableBody = match.Groups[2].Value.Trim();
            var fullTableDef = $"{tableName} {{\n{tableBody}\n}}";
            
            tables[tableName] = NormalizeTableCode(fullTableDef);
        }
        
        Logger.Debug("Parsed {Count} tables from Mermaid code", tables.Count);
        return tables;
    }
    
    /// <summary>
    /// Parse relationship lines from Mermaid ERD.
    /// </summary>
    private List<string> ParseMermaidRelationships(string mermaidCode)
    {
        var relationships = new List<string>();
        
        if (string.IsNullOrWhiteSpace(mermaidCode))
            return relationships;
        
        // Match relationship lines: TABLE1 ||--o{ TABLE2 : "label"
        var relPattern = new Regex(
            @"^\s*(\w+)\s*(\|\|--|--\|\||\|\|--o\{|o\{--\|\||\}o--\|\||\|\|--\}o|--)\s*(\w+)\s*:\s*""([^""]*)""",
            RegexOptions.Multiline);
        
        var matches = relPattern.Matches(mermaidCode);
        
        foreach (Match match in matches)
        {
            var normalizedRel = $"{match.Groups[1].Value}|{match.Groups[2].Value}|{match.Groups[3].Value}|{match.Groups[4].Value}";
            relationships.Add(normalizedRel);
        }
        
        relationships.Sort();
        return relationships;
    }
    
    /// <summary>
    /// Normalize table code for consistent hashing.
    /// </summary>
    private string NormalizeTableCode(string tableCode)
    {
        if (string.IsNullOrWhiteSpace(tableCode))
            return string.Empty;
        
        // Remove extra whitespace, normalize line endings
        var normalized = Regex.Replace(tableCode, @"\s+", " ").Trim();
        normalized = normalized.Replace(" {", "{").Replace("{ ", "{");
        normalized = normalized.Replace(" }", "}").Replace("} ", "}");
        
        return normalized;
    }
    
    /// <summary>
    /// Compute SHA256 hash of table code.
    /// </summary>
    private string ComputeHash(string content)
    {
        if (string.IsNullOrEmpty(content))
            return string.Empty;
        
        using var sha256 = SHA256.Create();
        var bytes = Encoding.UTF8.GetBytes(content);
        var hashBytes = sha256.ComputeHash(bytes);
        return Convert.ToHexString(hashBytes);
    }
    
    /// <summary>
    /// Extract short table name from full name (e.g., "SCHEMA.TABLE" -> "TABLE").
    /// </summary>
    private string ExtractTableName(string fullName)
    {
        var parts = fullName.Split('.');
        return parts.Length > 1 ? parts[^1] : fullName;
    }
    
    /// <summary>
    /// Find full table name in tracking from short name.
    /// </summary>
    private string? FindFullTableName(string shortName)
    {
        return _currentTables.Keys.FirstOrDefault(k => 
            ExtractTableName(k).Equals(shortName, StringComparison.OrdinalIgnoreCase));
    }
    
    /// <summary>
    /// Clone a table entry.
    /// </summary>
    private TableMermaidEntry CloneEntry(TableMermaidEntry entry)
    {
        return new TableMermaidEntry
        {
            TableName = entry.TableName,
            OriginalMermaidCode = entry.OriginalMermaidCode,
            OriginalHash = entry.OriginalHash,
            CurrentMermaidCode = entry.CurrentMermaidCode,
            CurrentHash = entry.CurrentHash,
            IsNewTable = entry.IsNewTable,
            IsRemoved = entry.IsRemoved
        };
    }
    
    /// <summary>
    /// Fire change status event.
    /// </summary>
    private void OnChangeStatusChanged()
    {
        var status = GetChangeStatus();
        Logger.Debug("Change status: HasChanges={HasChanges}, Changed={Changed}, New={New}, Removed={Removed}",
            status.HasChanges, status.ChangedTableCount, status.NewTableCount, status.RemovedTableCount);
        
        ChangeStatusChanged?.Invoke(this, status);
    }
}
