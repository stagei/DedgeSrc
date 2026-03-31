using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for parsing and applying ignore rules from Missing FK Discovery ignore JSON.
/// Supports wildcards, regex patterns, and data type exclusions.
/// </summary>
public class MissingFKIgnoreService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private MissingFKIgnoreModel? _ignoreModel;
    private List<Regex>? _columnPatternRegexes;
    
    /// <summary>
    /// Load ignore rules from JSON file.
    /// </summary>
    public void LoadIgnoreRules(string jsonFilePath)
    {
        Logger.Info("Loading ignore rules from: {Path}", jsonFilePath);
        
        if (!File.Exists(jsonFilePath))
        {
            Logger.Warn("Ignore JSON file not found: {Path}, using empty ignore rules", jsonFilePath);
            _ignoreModel = new MissingFKIgnoreModel();
            return;
        }
        
        try
        {
            var json = File.ReadAllText(jsonFilePath);
            _ignoreModel = JsonSerializer.Deserialize<MissingFKIgnoreModel>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            }) ?? new MissingFKIgnoreModel();
            
            // Compile regex patterns for column names
            _columnPatternRegexes = new List<Regex>();
            foreach (var pattern in _ignoreModel.IgnoreColumnPatterns)
            {
                try
                {
                    /*
                     * Regex Pattern Explanation:
                     * ^ - Start of string anchor
                     * pattern - The user-provided pattern (e.g., "^TMP_", "_HASH$")
                     * $ - End of string anchor (implicit if pattern ends with $)
                     * 
                     * Examples:
                     * "^TMP_" matches columns starting with "TMP_"
                     * "_HASH$" matches columns ending with "_HASH"
                     * ".*LOG.*" matches columns containing "LOG"
                     */
                    var regex = new Regex(pattern, RegexOptions.Compiled | RegexOptions.IgnoreCase);
                    _columnPatternRegexes.Add(regex);
                    Logger.Debug("Compiled regex pattern: {Pattern}", pattern);
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, "Invalid regex pattern in ignore JSON: {Pattern}", pattern);
                }
            }
            
            Logger.Info("Loaded ignore rules: {TableCount} table rules, {ColumnCount} column rules, {PatternCount} patterns, {DataTypeCount} data types",
                _ignoreModel.IgnoreTables.Count, _ignoreModel.IgnoreColumns.Count, 
                _ignoreModel.IgnoreColumnPatterns.Count, _ignoreModel.IgnoreDataTypes.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load ignore rules from {Path}", jsonFilePath);
            _ignoreModel = new MissingFKIgnoreModel();
        }
    }
    
    /// <summary>
    /// Check if a table should be ignored.
    /// </summary>
    public bool ShouldIgnoreTable(string schema, string tableName)
    {
        if (_ignoreModel == null)
            return false;
        
        foreach (var ignoreTable in _ignoreModel.IgnoreTables)
        {
            if (MatchesWildcard(schema, ignoreTable.Schema) && 
                MatchesWildcard(tableName, ignoreTable.Name))
            {
                Logger.Debug("Table {Schema}.{Table} matches ignore rule: {IgnoreSchema}.{IgnoreName}",
                    schema, tableName, ignoreTable.Schema, ignoreTable.Name);
                return true;
            }
        }
        
        return false;
    }
    
    /// <summary>
    /// Check if a column should be ignored.
    /// </summary>
    public bool ShouldIgnoreColumn(string schema, string tableName, string columnName, string dataType)
    {
        if (_ignoreModel == null)
            return false;
        
        // Check data type exclusion
        if (_ignoreModel.IgnoreDataTypes.Contains(dataType, StringComparer.OrdinalIgnoreCase))
        {
            Logger.Debug("Column {Schema}.{Table}.{Column} ignored due to data type: {DataType}",
                schema, tableName, columnName, dataType);
            return true;
        }
        
        // Check column name patterns (regex)
        if (_columnPatternRegexes != null)
        {
            foreach (var regex in _columnPatternRegexes)
            {
                if (regex.IsMatch(columnName))
                {
                    Logger.Debug("Column {Schema}.{Table}.{Column} ignored due to regex pattern: {Pattern}",
                        schema, tableName, columnName, regex.ToString());
                    return true;
                }
            }
        }
        
        // Check explicit column rules
        foreach (var ignoreColumn in _ignoreModel.IgnoreColumns)
        {
            if (MatchesWildcard(schema, ignoreColumn.Schema) &&
                MatchesWildcard(tableName, ignoreColumn.Table) &&
                MatchesWildcard(columnName, ignoreColumn.Name))
            {
                Logger.Debug("Column {Schema}.{Table}.{Column} ignored due to rule: {IgnoreSchema}.{IgnoreTable}.{IgnoreName}",
                    schema, tableName, columnName, ignoreColumn.Schema, ignoreColumn.Table, ignoreColumn.Name);
                return true;
            }
        }
        
        return false;
    }
    
    /// <summary>
    /// Check if a string matches a wildcard pattern.
    /// Supports "*" as wildcard (matches any sequence of characters).
    /// </summary>
    private bool MatchesWildcard(string value, string pattern)
    {
        if (string.IsNullOrEmpty(pattern) || pattern == "*")
            return true;
        
        if (string.IsNullOrEmpty(value))
            return false;
        
        // Convert wildcard pattern to regex
        /*
         * Wildcard Pattern Matching:
         * "*" - Matches any sequence of characters (including empty)
         * 
         * Conversion to Regex:
         * "*" becomes ".*" (any character, any number of times)
         * Other characters are escaped for literal matching
         * 
         * Examples:
         * "LOG_*" matches "LOG_TABLE", "LOG_DATA", etc.
         * "*_TMP" matches "TABLE_TMP", "DATA_TMP", etc.
         * "SYSIBM" matches exactly "SYSIBM"
         */
        var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
        return Regex.IsMatch(value, regexPattern, RegexOptions.IgnoreCase);
    }
}
