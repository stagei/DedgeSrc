using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace AutoDocNew.Core;

public class SearchRequest
{
    public string? Query { get; set; }
    public List<ElementFilter>? Elements { get; set; }
    public string[]? Types { get; set; }
    public string Logic { get; set; } = "AND";
}

public class ElementFilter
{
    public string Field { get; set; } = "";
    public string[] Terms { get; set; } = Array.Empty<string>();
}

public class SearchResult
{
    public string FileName { get; set; } = "";
    public string Type { get; set; } = "";
    public string JsonFile { get; set; } = "";
    public string Description { get; set; } = "";
    public List<FieldMatch> Matches { get; set; } = new();
}

public class FieldMatch
{
    public string Field { get; set; } = "";
    public string MatchedTerms { get; set; } = "";
}

/// <summary>
/// Loads the search index into memory and performs fast in-memory searches.
/// Used by both the REST API (Web) and CLI.
/// </summary>
public class SearchEngine
{
    private List<IndexEntry>? _entries;
    private readonly string _outputFolder;
    private DateTime _lastLoaded = DateTime.MinValue;

    public SearchEngine(string outputFolder)
    {
        _outputFolder = outputFolder;
    }

    public List<SearchResult> Search(SearchRequest request)
    {
        EnsureLoaded();
        if (_entries == null || _entries.Count == 0)
            return new List<SearchResult>();

        var candidates = _entries.AsEnumerable();

        if (request.Types != null && request.Types.Length > 0)
        {
            var typeSet = new HashSet<string>(request.Types, StringComparer.OrdinalIgnoreCase);
            candidates = candidates.Where(e => typeSet.Contains(e.Type));
        }

        var results = new List<SearchResult>();

        foreach (var entry in candidates)
        {
            var matches = new List<FieldMatch>();

            if (!string.IsNullOrWhiteSpace(request.Query))
            {
                SimpleMatch(entry, request.Query, matches);
            }

            if (request.Elements != null && request.Elements.Count > 0)
            {
                bool advancedOk = AdvancedMatch(entry, request.Elements, request.Logic, matches);
                if (!advancedOk) continue;
            }
            else if (matches.Count == 0)
            {
                continue;
            }

            results.Add(new SearchResult
            {
                FileName = entry.Name,
                Type = entry.Type,
                JsonFile = entry.File,
                Description = entry.Description,
                Matches = matches
            });
        }

        return results
            .OrderByDescending(r => r.Matches.Any(m => string.Equals(m.Field, "fileName", StringComparison.OrdinalIgnoreCase)) ? 1 : 0)
            .ThenBy(r => r.FileName)
            .ToList();
    }

    /// <summary>Returns the list of searchable field names from loaded entries.</summary>
    public List<string> GetAvailableFields()
    {
        EnsureLoaded();
        if (_entries == null) return new List<string>();

        return _entries
            .SelectMany(e => e.Fields.Keys)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(f => f)
            .ToList();
    }

    private void SimpleMatch(IndexEntry entry, string query, List<FieldMatch> matches)
    {
        string q = query.Trim();

        if (entry.Name.Contains(q, StringComparison.OrdinalIgnoreCase))
            matches.Add(new FieldMatch { Field = "fileName", MatchedTerms = q });

        if (!string.IsNullOrEmpty(entry.Description) &&
            entry.Description.Contains(q, StringComparison.OrdinalIgnoreCase))
            matches.Add(new FieldMatch { Field = "description", MatchedTerms = q });

        foreach (var kv in entry.Fields)
        {
            if (kv.Value.Contains(q, StringComparison.OrdinalIgnoreCase))
                matches.Add(new FieldMatch { Field = kv.Key, MatchedTerms = q });
        }
    }

    private bool AdvancedMatch(IndexEntry entry, List<ElementFilter> elements, string logic, List<FieldMatch> matches)
    {
        bool isAnd = string.Equals(logic, "AND", StringComparison.OrdinalIgnoreCase);
        int matched = 0;

        foreach (var filter in elements)
        {
            bool fieldMatched = false;

            if (string.IsNullOrWhiteSpace(filter.Field) || string.Equals(filter.Field, "all", StringComparison.OrdinalIgnoreCase))
            {
                fieldMatched = MatchTermsInAllFields(entry, filter.Terms, matches);
            }
            else
            {
                string? fieldValue = null;

                if (string.Equals(filter.Field, "fileName", StringComparison.OrdinalIgnoreCase))
                    fieldValue = entry.Name;
                else if (string.Equals(filter.Field, "description", StringComparison.OrdinalIgnoreCase))
                    fieldValue = entry.Description;
                else if (entry.Fields.TryGetValue(filter.Field, out var fv))
                    fieldValue = fv;

                if (fieldValue != null)
                {
                    bool allTermsMatch = filter.Terms.All(t =>
                        fieldValue.Contains(t.Trim(), StringComparison.OrdinalIgnoreCase));

                    if (allTermsMatch)
                    {
                        matches.Add(new FieldMatch
                        {
                            Field = filter.Field,
                            MatchedTerms = string.Join(", ", filter.Terms)
                        });
                        fieldMatched = true;
                    }
                }
            }

            if (fieldMatched) matched++;
            else if (isAnd) return false;
        }

        return isAnd ? matched == elements.Count : matched > 0;
    }

    private bool MatchTermsInAllFields(IndexEntry entry, string[] terms, List<FieldMatch> matches)
    {
        bool anyMatch = false;
        var allText = new List<(string field, string value)>
        {
            ("fileName", entry.Name),
            ("description", entry.Description)
        };
        foreach (var kv in entry.Fields)
            allText.Add((kv.Key, kv.Value));

        foreach (var (field, value) in allText)
        {
            if (string.IsNullOrEmpty(value)) continue;
            bool allTermsMatch = terms.All(t =>
                value.Contains(t.Trim(), StringComparison.OrdinalIgnoreCase));
            if (allTermsMatch)
            {
                matches.Add(new FieldMatch { Field = field, MatchedTerms = string.Join(", ", terms) });
                anyMatch = true;
            }
        }
        return anyMatch;
    }

    private void EnsureLoaded()
    {
        string indexPath = Path.Combine(_outputFolder, "_json", "search-index.json");
        if (!File.Exists(indexPath))
        {
            _entries = new List<IndexEntry>();
            return;
        }

        var lastWrite = File.GetLastWriteTimeUtc(indexPath);
        if (_entries != null && lastWrite <= _lastLoaded)
            return;

        try
        {
            string json = File.ReadAllText(indexPath, System.Text.Encoding.UTF8);
            using var doc = JsonDocument.Parse(json);
            var list = new List<IndexEntry>();

            foreach (var el in doc.RootElement.EnumerateArray())
            {
                var entry = new IndexEntry
                {
                    File = GetStr(el, "f"),
                    Type = GetStr(el, "t"),
                    Name = GetStr(el, "n"),
                    Description = GetStr(el, "d")
                };

                if (el.TryGetProperty("fields", out var fields) && fields.ValueKind == JsonValueKind.Object)
                {
                    foreach (var prop in fields.EnumerateObject())
                    {
                        if (prop.Value.ValueKind == JsonValueKind.String)
                            entry.Fields[prop.Name] = prop.Value.GetString() ?? "";
                    }
                }

                list.Add(entry);
            }

            _entries = list;
            _lastLoaded = lastWrite;
            Logger.LogMessage($"SearchEngine: Loaded {list.Count} entries from search index", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"SearchEngine: Failed to load index: {ex.Message}", LogLevel.ERROR);
            _entries = new List<IndexEntry>();
        }
    }

    private static string GetStr(JsonElement el, string prop)
    {
        if (el.TryGetProperty(prop, out var val) && val.ValueKind == JsonValueKind.String)
            return val.GetString() ?? "";
        return "";
    }

    private class IndexEntry
    {
        public string File { get; set; } = "";
        public string Type { get; set; } = "";
        public string Name { get; set; } = "";
        public string Description { get; set; } = "";
        public Dictionary<string, string> Fields { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }
}
