using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using AutoDocNew.Core;
using AutoDocNew.Models;

namespace AutoDocNew.Parsers;

/// <summary>
/// SQL Parser - complete line-by-line translation from AutoDocFunctions.psm1
/// Functions translated:
///   Get-SqlIndexMetadata           (lines 8011-8032)
///   Get-SqlConstraintMetadata      (lines 8034-8055)
///   Get-SqlKeyColumnMetadata       (lines 8057-8078)
///   Get-SqlForeignKeyMetadata      (lines 8080-8109)
///   Get-SqlTriggerMetadata         (lines 8111-8132)
///   Get-SqlCheckConstraintMetadata (lines 8134-8155)
///   New-SqlErDiagram               (lines 8157-8244)
///   New-SqlTableHtmlSections       (lines 8246-8429)
///   Get-SqlTableMetaData           (lines 8433-8664)
///   Search-HtmlFilesForSqlInteractions (lines 8666-8807)
///   Get-SqlTableInteractions       (lines 8809-8857)
///   New-SqlInteractionDiagram      (lines 8859-8932)
///   Start-SqlParse                 (lines 8934-9071)
/// </summary>
public static class SqlParser
{
    static SqlParser()
    {
        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
    }

    private static bool _errorOccurred = false;

    #region Data Models

    private class TableInfo
    {
        public string SchemaName { get; set; } = "";
        public string TableName { get; set; } = "";
        public string Comment { get; set; } = "";
        public string Type { get; set; } = "";
        public string AlterTime { get; set; } = "";
        public string Card { get; set; } = "";
        public string Npages { get; set; } = "";
        public string Colcount { get; set; } = "";
    }

    private class ColumnInfo
    {
        public string TabSchema { get; set; } = "";
        public string TabName { get; set; } = "";
        public string ColName { get; set; } = "";
        public string ColNo { get; set; } = "";
        public string TypeSchema { get; set; } = "";
        public string TypeName { get; set; } = "";
        public string Length { get; set; } = "";
        public string Scale { get; set; } = "";
        public string Remarks { get; set; } = "";
        public string Nulls { get; set; } = "";
    }

    private class IndexInfo
    {
        public string IndName { get; set; } = "";
        public string Colnames { get; set; } = "";
        public string UniqueRule { get; set; } = "";
        public string IndexType { get; set; } = "";
        public string Nlevels { get; set; } = "";
    }

    private class ConstraintInfo
    {
        public string ConstName { get; set; } = "";
        public string Type { get; set; } = "";
    }

    private class KeyColumnInfo
    {
        public string ConstName { get; set; } = "";
        public string ColName { get; set; } = "";
        public string ColSeq { get; set; } = "";
    }

    private class ForeignKeyInfo
    {
        public string ConstName { get; set; } = "";
        public string TabSchema { get; set; } = "";
        public string TabName { get; set; } = "";
        public string RefTabSchema { get; set; } = "";
        public string RefTabName { get; set; } = "";
        public string FkColnames { get; set; } = "";
        public string PkColnames { get; set; } = "";
        public string DeleteRule { get; set; } = "";
    }

    private class TriggerInfo
    {
        public string TrigName { get; set; } = "";
        public string TrigTime { get; set; } = "";
        public string TrigEvent { get; set; } = "";
        public string Granularity { get; set; } = "";
        public string Valid { get; set; } = "";
    }

    private class ForeignKeySet
    {
        public List<ForeignKeyInfo> Outgoing { get; set; } = new();
        public List<ForeignKeyInfo> Incoming { get; set; } = new();
    }

    private class HtmlSections
    {
        public string IndexInfo { get; set; } = "";
        public string PkInfo { get; set; } = "";
        public string UkInfo { get; set; } = "";
        public string FkOutgoing { get; set; } = "";
        public string FkIncoming { get; set; } = "";
        public string TriggerInfo { get; set; } = "";
        public int IndexCount { get; set; }
        public int UkCount { get; set; }
        public int FkCount { get; set; }
        public int TriggerCount { get; set; }
    }

    #endregion

    #region CSV Metadata Loaders (lines 8011-8155)

    /// <summary>Helper to clean a CSV field: trim whitespace and surrounding double-quotes.</summary>
    private static string CsvClean(string field) => field.Trim().Trim('"');

    private static List<IndexInfo> GetSqlIndexMetadata(string inputDbFileFolder, string schemaName, string tableName)
    {
        string indexFile = Path.Combine(inputDbFileFolder, "indexes.csv");
        if (!File.Exists(indexFile)) return new List<IndexInfo>();
        try
        {
            return (SourceFileCache.GetLines(indexFile) ?? File.ReadAllLines(indexFile, Encoding.UTF8))
                .Select(l => l.Split(';'))
                .Where(f => f.Length >= 10 && CsvClean(f[2]) == schemaName && CsvClean(f[3]) == tableName)
                .Select(f => new IndexInfo { IndName = CsvClean(f[1]), Colnames = CsvClean(f[4]), UniqueRule = CsvClean(f[5]), IndexType = CsvClean(f[7]), Nlevels = f.Length > 9 ? CsvClean(f[9]) : "" })
                .ToList();
        }
        catch { return new List<IndexInfo>(); }
    }

    private static List<ConstraintInfo> GetSqlConstraintMetadata(string inputDbFileFolder, string schemaName, string tableName)
    {
        string constFile = Path.Combine(inputDbFileFolder, "tabconst.csv");
        if (!File.Exists(constFile)) return new List<ConstraintInfo>();
        try
        {
            return (SourceFileCache.GetLines(constFile) ?? File.ReadAllLines(constFile, Encoding.UTF8))
                .Select(l => l.Split(';'))
                .Where(f => f.Length >= 4 && CsvClean(f[1]) == schemaName && CsvClean(f[2]) == tableName)
                .Select(f => new ConstraintInfo { ConstName = CsvClean(f[0]), Type = CsvClean(f[3]) })
                .ToList();
        }
        catch { return new List<ConstraintInfo>(); }
    }

    private static List<KeyColumnInfo> GetSqlKeyColumnMetadata(string inputDbFileFolder, string schemaName, string tableName)
    {
        string keycolFile = Path.Combine(inputDbFileFolder, "keycoluse.csv");
        if (!File.Exists(keycolFile)) return new List<KeyColumnInfo>();
        try
        {
            return (SourceFileCache.GetLines(keycolFile) ?? File.ReadAllLines(keycolFile, Encoding.UTF8))
                .Select(l => l.Split(';'))
                .Where(f => f.Length >= 5 && CsvClean(f[1]) == schemaName && CsvClean(f[2]) == tableName)
                .Select(f => new KeyColumnInfo { ConstName = CsvClean(f[0]), ColName = CsvClean(f[3]), ColSeq = CsvClean(f[4]) })
                .ToList();
        }
        catch { return new List<KeyColumnInfo>(); }
    }

    private static ForeignKeySet GetSqlForeignKeyMetadata(string inputDbFileFolder, string schemaName, string tableName)
    {
        string refFile = Path.Combine(inputDbFileFolder, "references.csv");
        if (!File.Exists(refFile)) return new ForeignKeySet();
        try
        {
            var allFks = (SourceFileCache.GetLines(refFile) ?? File.ReadAllLines(refFile, Encoding.UTF8))
                .Select(l => l.Split(';'))
                .Where(f => f.Length >= 9)
                .Select(f => new ForeignKeyInfo
                {
                    ConstName = CsvClean(f[0]), TabSchema = CsvClean(f[1]), TabName = CsvClean(f[2]),
                    RefTabSchema = CsvClean(f[3]), RefTabName = CsvClean(f[4]),
                    FkColnames = CsvClean(f[6]), PkColnames = CsvClean(f[7]), DeleteRule = CsvClean(f[8])
                }).ToList();

            return new ForeignKeySet
            {
                Outgoing = allFks.Where(f => f.TabSchema == schemaName && f.TabName == tableName).ToList(),
                Incoming = allFks.Where(f => f.RefTabSchema == schemaName && f.RefTabName == tableName).ToList()
            };
        }
        catch { return new ForeignKeySet(); }
    }

    private static List<TriggerInfo> GetSqlTriggerMetadata(string inputDbFileFolder, string schemaName, string tableName)
    {
        string trigFile = Path.Combine(inputDbFileFolder, "triggers.csv");
        if (!File.Exists(trigFile)) return new List<TriggerInfo>();
        try
        {
            return (SourceFileCache.GetLines(trigFile) ?? File.ReadAllLines(trigFile, Encoding.UTF8))
                .Select(l => l.Split(';'))
                .Where(f => f.Length >= 8 && CsvClean(f[2]) == schemaName && CsvClean(f[3]) == tableName)
                .Select(f => new TriggerInfo { TrigName = CsvClean(f[1]), TrigTime = CsvClean(f[4]), TrigEvent = CsvClean(f[5]), Granularity = CsvClean(f[6]), Valid = CsvClean(f[7]) })
                .ToList();
        }
        catch { return new List<TriggerInfo>(); }
    }

    #endregion

    #region New-SqlErDiagram (lines 8157-8244)

    private static string NewSqlErDiagram(string schemaName, string tableName, List<ColumnInfo> columns, List<string> pkColumns, ForeignKeySet foreignKeys)
    {
        var mmd = new List<string> { "erDiagram" };
        // Regex: [^a-zA-Z0-9_] - Remove non-alphanumeric characters for safe Mermaid node IDs
        string safeTableName = Regex.Replace($"{schemaName}_{tableName}", @"[^a-zA-Z0-9_]", "");

        mmd.Add($"    {safeTableName} {{");
        foreach (var col in columns)
        {
            string colName = col.ColName.Trim()
                .Replace("Æ", "AE", StringComparison.OrdinalIgnoreCase)
                .Replace("Ø", "OE", StringComparison.OrdinalIgnoreCase)
                .Replace("Å", "AA", StringComparison.OrdinalIgnoreCase);
            colName = Regex.Replace(colName, @"[^A-Za-z0-9_]", "_");
            if (colName.Length == 0) colName = "COL";
            if (char.IsDigit(colName[0])) colName = "C_" + colName;

            string dataType = Regex.Replace(col.TypeName.Trim(), @"[^a-zA-Z0-9]", "");
            bool isPk = pkColumns.Contains(col.ColName.Trim());
            string fkMarker = "";
            foreach (var fk in foreignKeys.Outgoing)
            {
                if (Regex.IsMatch(fk.FkColnames, $@"\b{Regex.Escape(col.ColName.Trim())}\b")) { fkMarker = "FK"; break; }
            }
            var markers = new List<string>();
            if (isPk) markers.Add("PK");
            if (!string.IsNullOrEmpty(fkMarker)) markers.Add(fkMarker);
            string markerStr = markers.Count > 0 ? $" \"{string.Join(",", markers)}\"" : "";
            mmd.Add($"        {dataType} {colName}{markerStr}");
        }
        mmd.Add("    }");

        foreach (var fk in foreignKeys.Outgoing)
        {
            string safeRefName = Regex.Replace($"{fk.RefTabSchema.Trim()}_{fk.RefTabName.Trim()}", @"[^a-zA-Z0-9_]", "");
            mmd.Add($"    {safeRefName} {{");
            mmd.Add("        string PK_COLUMN");
            mmd.Add("    }");
            // Collapse whitespace runs into comma-separated list for clean labels
            string fkCols = Regex.Replace(fk.FkColnames.Replace("+", "").Replace("-", "").Trim(), @"\s+", ", ");
            mmd.Add($"    {safeTableName} }}o--|| {safeRefName} : \"{fkCols}\"");
        }

        foreach (var fk in foreignKeys.Incoming)
        {
            string safeChildName = Regex.Replace($"{fk.TabSchema.Trim()}_{fk.TabName.Trim()}", @"[^a-zA-Z0-9_]", "");
            mmd.Add($"    {safeChildName} {{");
            mmd.Add("        string FK_COLUMN");
            mmd.Add("    }");
            string fkCols = Regex.Replace(fk.FkColnames.Replace("+", "").Replace("-", "").Trim(), @"\s+", ", ");
            mmd.Add($"    {safeChildName} }}o--|| {safeTableName} : \"{fkCols}\"");
        }

        return string.Join("\n", mmd);
    }

    #endregion

    #region New-SqlTableHtmlSections (lines 8246-8429)

    private static HtmlSections NewSqlTableHtmlSections(
        List<IndexInfo> indexes, List<ConstraintInfo> constraints, List<KeyColumnInfo> keyColumns,
        ForeignKeySet foreignKeys, List<TriggerInfo> triggers)
    {
        var sections = new HtmlSections
        {
            IndexCount = indexes.Count,
            TriggerCount = triggers.Count
        };

        // Indexes
        if (indexes.Count > 0)
        {
            sections.IndexInfo = "<table><tr><th>Index Name</th><th>Type</th><th>Unique</th><th>Columns</th><th>Levels</th></tr>";
            foreach (var idx in indexes)
            {
                string uniqueType = idx.UniqueRule switch { "P" => "Primary Key", "U" => "Unique", "D" => "Non-Unique", _ => idx.UniqueRule };
                string idxType = idx.IndexType switch { "REG" => "Regular", "CLUS" => "Clustering", _ => idx.IndexType };

                // Regex: (?=[+-]) - Lookahead split for ASC/DESC column indicators
                string[] colParts = Regex.Split(idx.Colnames, @"(?=[+-])").Where(s => s != "").ToArray();
                var formattedCols = new List<string>();
                foreach (string colPart in colParts)
                {
                    string cp = colPart.Trim();
                    if (cp.StartsWith("+")) { string cn = cp.Substring(1).Trim(); if (cn.Length > 0) formattedCols.Add(cn + " ASC"); }
                    else if (cp.StartsWith("-")) { string cn = cp.Substring(1).Trim(); if (cn.Length > 0) formattedCols.Add(cn + " DESC"); }
                    else if (cp.Length > 0) formattedCols.Add(cp + " ASC");
                }
                string colnames = string.Join(", ", formattedCols);
                sections.IndexInfo += $"<tr><td>{idx.IndName}</td><td>{idxType}</td><td>{uniqueType}</td><td><code>{colnames}</code></td><td>{idx.Nlevels}</td></tr>";
            }
            sections.IndexInfo += "</table>";
        }
        else
            sections.IndexInfo = "<div class='empty-state'><i class='bi bi-list-ol'></i><p>No indexes defined</p></div>";

        // Primary Key
        var pkConstraints = constraints.Where(c => c.Type == "P").ToList();
        if (pkConstraints.Count > 0)
        {
            sections.PkInfo = "<table><tr><th>Constraint Name</th><th>Columns</th></tr>";
            foreach (var pk in pkConstraints)
            {
                var pkCols = keyColumns.Where(k => k.ConstName == pk.ConstName)
                    .OrderBy(k => int.TryParse(k.ColSeq, out int n) ? n : 999)
                    .Select(k => k.ColName).ToList();
                sections.PkInfo += $"<tr><td>{pk.ConstName}</td><td><code>{string.Join(", ", pkCols)}</code></td></tr>";
            }
            sections.PkInfo += "</table>";
        }
        else
            sections.PkInfo = "<div class='empty-state'><i class='bi bi-key'></i><p>No primary key defined</p></div>";

        // Unique Constraints
        var ukConstraints = constraints.Where(c => c.Type == "U").ToList();
        sections.UkCount = ukConstraints.Count;
        if (ukConstraints.Count > 0)
        {
            sections.UkInfo = "<table><tr><th>Constraint Name</th><th>Columns</th></tr>";
            foreach (var uk in ukConstraints)
            {
                var ukCols = keyColumns.Where(k => k.ConstName == uk.ConstName)
                    .OrderBy(k => int.TryParse(k.ColSeq, out int n) ? n : 999)
                    .Select(k => k.ColName).ToList();
                sections.UkInfo += $"<tr><td>{uk.ConstName}</td><td><code>{string.Join(", ", ukCols)}</code></td></tr>";
            }
            sections.UkInfo += "</table>";
        }
        else
            sections.UkInfo = "<div class='empty-state'><i class='bi bi-asterisk'></i><p>No unique constraints defined</p></div>";

        // Foreign Keys
        sections.FkCount = foreignKeys.Outgoing.Count + foreignKeys.Incoming.Count;

        if (foreignKeys.Outgoing.Count > 0)
        {
            sections.FkOutgoing = $"<div class='data-section'><h5><i class='bi bi-arrow-right-circle'></i> References ({foreignKeys.Outgoing.Count} parent tables)</h5>";
            sections.FkOutgoing += "<table><tr><th>FK Name</th><th>FK Columns</th><th>References Table</th><th>PK Columns</th><th>On Delete</th></tr>";
            foreach (var fk in foreignKeys.Outgoing)
            {
                string refTable = $"{fk.RefTabSchema.Trim()}.{fk.RefTabName.Trim()}";
                string refFileName = refTable.Replace(".", "_").ToLower() + ".sql.html";
                string fkCols = fk.FkColnames.Replace("+", "").Replace("-", "");
                string pkCols = fk.PkColnames.Replace("+", "").Replace("-", "");
                string deleteRule = fk.DeleteRule switch { "A" => "No Action", "C" => "Cascade", "N" => "Set Null", "R" => "Restrict", _ => fk.DeleteRule };
                sections.FkOutgoing += $"<tr><td>{fk.ConstName}</td><td><code>{fkCols}</code></td><td><a href='{refFileName}'><strong>{refTable}</strong></a></td><td><code>{pkCols}</code></td><td>{deleteRule}</td></tr>";
            }
            sections.FkOutgoing += "</table></div>";
        }

        if (foreignKeys.Incoming.Count > 0)
        {
            sections.FkIncoming = $"<div class='data-section'><h5><i class='bi bi-arrow-left-circle'></i> Referenced By ({foreignKeys.Incoming.Count} child tables)</h5>";
            sections.FkIncoming += "<table><tr><th>Child Table</th><th>FK Name</th><th>FK Columns</th><th>On Delete</th></tr>";
            foreach (var fk in foreignKeys.Incoming)
            {
                string childTable = $"{fk.TabSchema.Trim()}.{fk.TabName.Trim()}";
                string childFileName = childTable.Replace(".", "_").ToLower() + ".sql.html";
                string fkCols = fk.FkColnames.Replace("+", "").Replace("-", "");
                string deleteRule = fk.DeleteRule switch { "A" => "No Action", "C" => "Cascade", "N" => "Set Null", "R" => "Restrict", _ => fk.DeleteRule };
                sections.FkIncoming += $"<tr><td><a href='{childFileName}'><strong>{childTable}</strong></a></td><td>{fk.ConstName}</td><td><code>{fkCols}</code></td><td>{deleteRule}</td></tr>";
            }
            sections.FkIncoming += "</table></div>";
        }

        if (foreignKeys.Outgoing.Count == 0 && foreignKeys.Incoming.Count == 0)
            sections.FkOutgoing = "<div class='data-section'><div class='empty-state'><i class='bi bi-link-45deg'></i><p>No foreign key relationships</p></div></div>";

        // Triggers
        if (triggers.Count > 0)
        {
            sections.TriggerInfo = "<table><tr><th>Trigger Name</th><th>Timing</th><th>Event</th><th>Granularity</th><th>Valid</th></tr>";
            foreach (var trig in triggers)
            {
                string timing = trig.TrigTime switch { "A" => "AFTER", "B" => "BEFORE", "I" => "INSTEAD OF", _ => trig.TrigTime };
                string trigEvent = trig.TrigEvent switch { "I" => "INSERT", "D" => "DELETE", "U" => "UPDATE", _ => trig.TrigEvent };
                string granularity = trig.Granularity == "R" ? "Row" : "Statement";
                string valid = trig.Valid == "Y" ? "Yes" : "No";
                sections.TriggerInfo += $"<tr><td>{trig.TrigName}</td><td>{timing}</td><td>{trigEvent}</td><td>{granularity}</td><td>{valid}</td></tr>";
            }
            sections.TriggerInfo += "</table>";
        }
        else
            sections.TriggerInfo = "<div class='empty-state'><i class='bi bi-lightning'></i><p>No triggers defined</p></div>";

        return sections;
    }

    #endregion

    #region New-SqlInteractionDiagram (lines 8859-8932)

    private static string NewSqlInteractionDiagram(string tableName, Dictionary<string, List<Dictionary<string, string>>>? interactions)
    {
        if (interactions == null || interactions.Count == 0) return "";

        var diagram = new List<string> { "flowchart TD" };
        string safeTableName = tableName.Replace(".", "_").ToLower();
        string tableNodeId = "sql_" + safeTableName;
        string tableDisplayName = tableName.ToUpper();
        diagram.Add($"    {tableNodeId}[({tableDisplayName})]");

        string[] operations = { "SELECT", "INSERT", "UPDATE", "DELETE", "FETCH", "CALL", "REFERENCES" };
        foreach (string operation in operations)
        {
            if (!interactions.ContainsKey(operation)) continue;
            var programs = interactions[operation];
            if (programs.Count == 0) continue;

            string safeOpName = operation.ToLower();
            diagram.Add($"    subgraph {safeOpName}[\"{operation}\"]");

            foreach (var program in programs)
            {
                string programName = program.ContainsKey("Name") ? program["Name"] : "unknown";
                string fileType = program.ContainsKey("FileType") ? program["FileType"] : "";
                string filePath = program.ContainsKey("FilePath") ? program["FilePath"] : "";
                // Regex: [^a-zA-Z0-9] - Remove non-alphanumeric for safe node ID
                string safeProgramName = Regex.Replace(programName, @"[^a-zA-Z0-9]", "_");
                string programNodeId = $"{safeOpName}_{safeProgramName}";

                string nodeShape = fileType switch
                {
                    "COBOL" => $"([\"{programName}\"])",
                    "CSharp" => $"([\"{programName}\"])",
                    _ => $"[\"{programName}\"]"
                };

                diagram.Add($"        {programNodeId}{nodeShape}");
                diagram.Add($"        {programNodeId} -->|\"{operation}\"| {tableNodeId}");
                if (!string.IsNullOrEmpty(filePath))
                    diagram.Add($"        click {programNodeId} \"./{filePath}\"");
            }
            diagram.Add("    end");
        }

        return string.Join("\n", diagram);
    }

    #endregion

    #region Get-SqlTableInteractions (lines 8809-8857)

    private static Dictionary<string, List<Dictionary<string, string>>>? GetSqlTableInteractions(string tableName, string outputFolder, string jsonCachePath)
    {
        if (string.IsNullOrEmpty(jsonCachePath))
            jsonCachePath = Path.Combine(outputFolder, "_json", "_sql_interactions.json");

        string tableNameLower = tableName.ToLower();
        if (!File.Exists(jsonCachePath)) return null;

        try
        {
            string jsonContent = File.ReadAllText(jsonCachePath, Encoding.UTF8);
            var entries = DeserializeInteractions(jsonContent, tableNameLower);
            if (entries == null || entries.Count == 0) return null;

            var result = new Dictionary<string, List<Dictionary<string, string>>>();
            var refList = entries.Select(e => new Dictionary<string, string>
            {
                ["Name"] = e.ProgramName,
                ["FileType"] = e.FileType,
                ["FilePath"] = e.FilePath
            }).ToList();

            if (refList.Count > 0)
                result["REFERENCES"] = refList;

            return result.Count > 0 ? result : null;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error loading SQL interactions JSON cache: {ex.Message}", LogLevel.WARN);
        }
        return null;
    }

    private static string InferFileType(string programName)
    {
        if (programName.EndsWith(".cbl.html", StringComparison.OrdinalIgnoreCase) ||
            programName.EndsWith(".cbl", StringComparison.OrdinalIgnoreCase))
            return "COBOL";
        if (programName.EndsWith(".bat.html", StringComparison.OrdinalIgnoreCase) ||
            programName.EndsWith(".bat", StringComparison.OrdinalIgnoreCase))
            return "Batch";
        if (programName.EndsWith(".ps1.html", StringComparison.OrdinalIgnoreCase) ||
            programName.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) ||
            programName.EndsWith(".psm1.html", StringComparison.OrdinalIgnoreCase))
            return "PowerShell";
        if (programName.EndsWith(".rex.html", StringComparison.OrdinalIgnoreCase) ||
            programName.EndsWith(".rex", StringComparison.OrdinalIgnoreCase))
            return "REXX";
        if (programName.EndsWith(".csharp.html", StringComparison.OrdinalIgnoreCase))
            return "CSharp";
        return "";
    }

    private static string CleanProgramName(string name)
    {
        foreach (var ext in new[] { ".cbl.html", ".bat.html", ".ps1.html", ".psm1.html",
            ".rex.html", ".csharp.html", ".sql.html", ".screen.html", ".gs.html", ".html" })
        {
            if (name.EndsWith(ext, StringComparison.OrdinalIgnoreCase))
                return name.Substring(0, name.Length - ext.Length);
        }
        return name;
    }

    #endregion

    #region Get-SqlTableMetaData (lines 8433-8664)

    /// <summary>Helper to regenerate interaction diagram MMD for JSON output</summary>
    private static string GetInteractionDiagramForJson(string sqlTable, string outputFolder)
    {
        try
        {
            string tableNameLower = sqlTable.ToLower();
            string jsonCachePath = Path.Combine(outputFolder, "_json", "_sql_interactions.json");
            var interactions = GetSqlTableInteractions(tableNameLower, outputFolder, jsonCachePath);
            if (interactions != null && interactions.Count > 0)
            {
                int count = interactions.Values.Sum(v => v.Count);
                if (count > 0) return NewSqlInteractionDiagram(tableNameLower, interactions);
            }
        }
        catch { }
        return "";
    }

    private static List<SqlUsageDef> GetUsedByList(string sqlTable, string outputFolder)
    {
        var usedBy = new List<SqlUsageDef>();
        try
        {
            string jsonCachePath = Path.Combine(outputFolder, "_json", "_sql_interactions.json");
            if (!File.Exists(jsonCachePath)) return usedBy;

            string jsonContent = File.ReadAllText(jsonCachePath, Encoding.UTF8);
            string tableNameLower = sqlTable.ToLower();
            var entries = DeserializeInteractions(jsonContent, tableNameLower);
            if (entries == null) return usedBy;

            foreach (var e in entries)
            {
                usedBy.Add(new SqlUsageDef
                {
                    ProgramName = e.ProgramName,
                    FileType = e.FileType,
                    FilePath = e.FilePath,
                    Description = e.Description,
                    GeneratedAt = e.GeneratedAt
                });
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error loading UsedBy for {sqlTable}: {ex.Message}", LogLevel.WARN);
        }
        return usedBy;
    }

    /// <summary>
    /// Deserializes _sql_interactions.json supporting both the new enriched format
    /// (List&lt;InteractionEntry&gt;) and the legacy flat format (List&lt;string&gt;).
    /// </summary>
    private static List<SqlUsageDef>? DeserializeInteractions(string jsonContent, string tableNameLower)
    {
        using var doc = System.Text.Json.JsonDocument.Parse(jsonContent);
        if (!doc.RootElement.TryGetProperty(tableNameLower, out var tableElement))
            return null;

        if (tableElement.ValueKind != System.Text.Json.JsonValueKind.Array || tableElement.GetArrayLength() == 0)
            return null;

        var first = tableElement[0];
        if (first.ValueKind == System.Text.Json.JsonValueKind.Object)
        {
            return tableElement.EnumerateArray().Select(e => new SqlUsageDef
            {
                ProgramName = e.TryGetProperty("programName", out var pn) ? pn.GetString() ?? "" :
                              e.TryGetProperty("ProgramName", out var pn2) ? pn2.GetString() ?? "" : "",
                FileType = e.TryGetProperty("fileType", out var ft) ? ft.GetString() ?? "" :
                           e.TryGetProperty("FileType", out var ft2) ? ft2.GetString() ?? "" : "",
                FilePath = e.TryGetProperty("filePath", out var fp) ? fp.GetString() ?? "" :
                           e.TryGetProperty("FilePath", out var fp2) ? fp2.GetString() ?? "" : "",
                Description = e.TryGetProperty("description", out var d) ? d.GetString() ?? "" :
                              e.TryGetProperty("Description", out var d2) ? d2.GetString() ?? "" : "",
                GeneratedAt = e.TryGetProperty("generatedAt", out var g) ? g.GetString() ?? "" :
                              e.TryGetProperty("GeneratedAt", out var g2) ? g2.GetString() ?? "" : ""
            }).ToList();
        }

        if (first.ValueKind == System.Text.Json.JsonValueKind.String)
        {
            return tableElement.EnumerateArray()
                .Select(e => e.GetString() ?? "")
                .Where(s => !string.IsNullOrEmpty(s))
                .Select(prog => new SqlUsageDef
                {
                    ProgramName = CleanProgramName(prog),
                    FileType = InferFileType(prog),
                    FilePath = prog.EndsWith(".json", StringComparison.OrdinalIgnoreCase) ? prog : prog + ".json"
                }).ToList();
        }

        return null;
    }

    private static string GetSqlTableMetaData(
        string tmpRootFolder, string outputFolder, string inputDbFileFolder,
        string sqlTable, TableInfo tableInfo, List<ColumnInfo> columnsArray,
        bool generateHtml = false)
    {
        string schemaName = tableInfo.SchemaName.Trim().ToUpper();
        string tableName = tableInfo.TableName.Trim().ToUpper();
        string htmlTable = "";
        string erDiagram = "";
        string statsHtml = "";
        string htmlType = "";
        int columnCount = columnsArray.Count;
        HtmlSections sections = new();
        List<string> pkColumnNames = new();

        try
        {
            // Load enhanced metadata
            var indexes = GetSqlIndexMetadata(inputDbFileFolder, schemaName, tableName);
            var constraints = GetSqlConstraintMetadata(inputDbFileFolder, schemaName, tableName);
            var keyColumns = GetSqlKeyColumnMetadata(inputDbFileFolder, schemaName, tableName);
            var foreignKeys = GetSqlForeignKeyMetadata(inputDbFileFolder, schemaName, tableName);
            var triggers = GetSqlTriggerMetadata(inputDbFileFolder, schemaName, tableName);

            // Get PK columns
            var pkConstraint = constraints.FirstOrDefault(c => c.Type == "P");
            if (pkConstraint != null)
                pkColumnNames = keyColumns.Where(k => k.ConstName == pkConstraint.ConstName).Select(k => k.ColName).ToList();

            // Build column table HTML
            htmlTable = "<table><tr><th>Column</th><th>#</th><th>Data Type</th><th>Length</th><th>Scale</th><th>Null</th><th>Key</th><th>Remarks</th></tr>";
            foreach (var item in columnsArray)
            {
                string colName = item.ColName.Trim();
                string nullable = item.Nulls.Trim() == "Y" ? "Yes" : "No";
                string keyType = "";
                if (pkColumnNames.Contains(colName))
                    keyType = "<span class='badge bg-primary'>PK</span>";
                if (foreignKeys.Outgoing.Any(fk => Regex.IsMatch(fk.FkColnames, $@"\b{Regex.Escape(colName)}\b")))
                    keyType += " <span class='badge bg-warning text-dark'>FK</span>";

                htmlTable += $"<tr><td class='column-name'>{colName}</td><td>{item.ColNo}</td><td class='column-type'>{item.TypeName.Trim()}</td><td>{item.Length}</td><td>{item.Scale}</td><td>{nullable}</td><td>{keyType}</td><td>{item.Remarks}</td></tr>";
            }
            htmlTable += "</table>";

            // Generate sections
            sections = NewSqlTableHtmlSections(indexes, constraints, keyColumns, foreignKeys, triggers);

            // ER diagram
            if (foreignKeys.Outgoing.Count > 0 || foreignKeys.Incoming.Count > 0)
                erDiagram = NewSqlErDiagram(schemaName, tableName, columnsArray, pkColumnNames, foreignKeys);

            // Table type
            htmlType = tableInfo.Type switch { "T" => "Sql Table", "V" => "Sql View", _ => "Sql Unknown" };

            // Statistics
            if (int.TryParse(tableInfo.Card, out int rowCount) && rowCount >= 0)
            {
                int pageCount = int.TryParse(tableInfo.Npages, out int np) ? np : 0;
                int colCount = int.TryParse(tableInfo.Colcount, out int cc) ? cc : columnsArray.Count;
                statsHtml = "<div class='info-card stats-card'><table class='info-table'>"
                    + "<tr><td><i class='bi bi-bar-chart'></i> Statistics</td><td></td></tr>"
                    + $"<tr><td>Row Count</td><td><strong>{rowCount:N0}</strong></td></tr>"
                    + $"<tr><td>Data Pages</td><td>{pageCount:N0}</td></tr>"
                    + $"<tr><td>Column Count</td><td>{colCount}</td></tr>"
                    + $"<tr><td>Indexes</td><td>{indexes.Count}</td></tr>"
                    + $"<tr><td>Triggers</td><td>{triggers.Count}</td></tr>"
                    + $"<tr><td>Parent Tables</td><td>{foreignKeys.Outgoing.Count}</td></tr>"
                    + $"<tr><td>Child Tables</td><td>{foreignKeys.Incoming.Count}</td></tr>"
                    + "</table></div>";
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GetSqlTableMetaData: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }

        // Generate HTML file
        string htmlFilename = Path.Combine(outputFolder, sqlTable.Replace(".", "_") + ".sql.html");
        htmlFilename = htmlFilename.Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower();

        string templatePath = Path.Combine(outputFolder, "_templates");
        string mmdTemplateFilename = Path.Combine(templatePath, "sqlmmdtemplate.html");
        string templateContent = "";

        if (File.Exists(mmdTemplateFilename))
            templateContent = File.ReadAllText(mmdTemplateFilename, Encoding.UTF8);
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "sqlmmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                templateContent = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else { Logger.LogMessage($"Template not found: {mmdTemplateFilename}", LogLevel.ERROR); return htmlFilename; }
        }

        try
        {
            string tableFullName = schemaName + "." + tableName;
            string doc = ParserBase.SetAutodocTemplate(templateContent, outputFolder);

            doc = doc.Replace("[title]", "AutoDoc Sql Info - " + sqlTable.ToLower());
            doc = doc.Replace("[tablename]", tableFullName.ToUpper());
            doc = doc.Replace("[comment]", tableInfo.Comment.ToUpper());
            doc = doc.Replace("[type]", htmlType);
            doc = doc.Replace("[ddltime]", tableInfo.AlterTime);
            doc = doc.Replace("[generated]", DateTime.Now.ToString());
            doc = doc.Replace("[columninfo]", htmlTable);
            doc = doc.Replace("[statsinfo]", statsHtml);
            doc = doc.Replace("[erdiagram]", erDiagram);
            doc = doc.Replace("[haserdiagram]", !string.IsNullOrEmpty(erDiagram) ? "true" : "false");
            doc = doc.Replace("[indexinfo]", sections.IndexInfo);
            doc = doc.Replace("[pkinfo]", sections.PkInfo);
            doc = doc.Replace("[ukinfo]", sections.UkInfo);
            doc = doc.Replace("[fkoutgoing]", sections.FkOutgoing);
            doc = doc.Replace("[fkincoming]", sections.FkIncoming);
            doc = doc.Replace("[triggerinfo]", sections.TriggerInfo);

            // Interaction diagram
            string interactionDiagram = "";
            int interactionCount = 0;
            string hasInteractionDiagram = "false";
            string interactionTabStyle = "display: none;";

            try
            {
                string tableNameLower = sqlTable.ToLower();
                string jsonCachePath = Path.Combine(outputFolder, "_sql_interactions.json");
                var interactions = GetSqlTableInteractions(tableNameLower, outputFolder, jsonCachePath);
                if (interactions != null && interactions.Count > 0)
                {
                    foreach (var operation in interactions.Keys)
                        interactionCount += interactions[operation].Count;

                    if (interactionCount > 0)
                    {
                        interactionDiagram = NewSqlInteractionDiagram(tableNameLower, interactions);
                        hasInteractionDiagram = "true";
                        interactionTabStyle = "";
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"Error generating interaction diagram: {ex.Message}", LogLevel.WARN);
            }

            doc = doc.Replace("[columncount]", columnCount.ToString());
            doc = doc.Replace("[indexcount]", sections.IndexCount.ToString());
            doc = doc.Replace("[ukcount]", sections.UkCount.ToString());
            doc = doc.Replace("[fkcount]", sections.FkCount.ToString());
            doc = doc.Replace("[triggercount]", sections.TriggerCount.ToString());
            doc = doc.Replace("[interactioncount]", interactionCount.ToString());
            doc = doc.Replace("[interactiondiagram]", interactionDiagram);
            doc = doc.Replace("[hasinteractiondiagram]", hasInteractionDiagram);
            doc = doc.Replace("[interactionstabstyle]", interactionTabStyle);
            doc = doc.Replace("[additionalsections]", "");
            doc = doc.Replace("[usedbylist]", "");

            // Legacy placeholders
            doc = doc.Replace("[desc]", tableInfo.Comment);
            doc = doc.Replace("[schema]", schemaName);
            doc = doc.Replace("[altertime]", tableInfo.AlterTime);
            doc = doc.Replace("[columns]", "");
            doc = doc.Replace("[sourcefile]", sqlTable.ToLower());
            doc = doc.Replace("[githistory]", "");

            if (generateHtml)
            {
                File.WriteAllText(htmlFilename, doc, Encoding.UTF8);
                Logger.LogMessage($"Generated HTML file: {htmlFilename}", LogLevel.INFO);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error generating HTML file: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }

        // Write JSON result alongside HTML
        try
        {
            string schemaUp = tableInfo.SchemaName.Trim().ToUpper();
            string tableUp = tableInfo.TableName.Trim().ToUpper();
            string fullName = schemaUp + "." + tableUp;

            // Re-load structured data from CSVs (cached) for JSON
            var jsonIndexes = GetSqlIndexMetadata(inputDbFileFolder, schemaUp, tableUp);
            var jsonConstraints = GetSqlConstraintMetadata(inputDbFileFolder, schemaUp, tableUp);
            var jsonKeyColumns = GetSqlKeyColumnMetadata(inputDbFileFolder, schemaUp, tableUp);
            var jsonForeignKeys = GetSqlForeignKeyMetadata(inputDbFileFolder, schemaUp, tableUp);
            var jsonTriggers = GetSqlTriggerMetadata(inputDbFileFolder, schemaUp, tableUp);

            var pkConst = jsonConstraints.FirstOrDefault(c => c.Type == "P");
            var pkCols = pkConst != null ? jsonKeyColumns.Where(k => k.ConstName == pkConst.ConstName).Select(k => k.ColName).ToList() : new List<string>();

            var sqlResult = new SqlResult
            {
                Type = "SQL",
                FileName = sqlTable,
                Title = "AutoDoc Sql Info - " + sqlTable.ToLower(),
                Description = tableInfo.Comment,
                GeneratedAt = DateTime.Now.ToString("o"),
                SourceFile = sqlTable.ToLower(),
                Metadata = new SqlMetadata
                {
                    Schema = schemaUp,
                    TableName = tableUp,
                    FullName = fullName,
                    Comment = tableInfo.Comment,
                    TableType = htmlType,
                    AlterTime = tableInfo.AlterTime
                },
                Columns = columnsArray.Select(c => new SqlColumnDef
                {
                    Name = c.ColName.Trim(),
                    Number = int.TryParse(c.ColNo, out int n) ? n : 0,
                    DataType = c.TypeName.Trim(),
                    Length = c.Length,
                    Scale = c.Scale,
                    Nullable = c.Nulls.Trim() == "Y",
                    IsPrimaryKey = pkCols.Contains(c.ColName.Trim()),
                    IsForeignKey = jsonForeignKeys.Outgoing.Any(fk => Regex.IsMatch(fk.FkColnames, $@"\b{Regex.Escape(c.ColName.Trim())}\b")),
                    Remarks = c.Remarks
                }).ToList(),
                ErDiagramMmd = erDiagram,
                Indexes = jsonIndexes.Select(i => new SqlIndexDef
                {
                    Name = i.IndName,
                    IndexType = i.IndexType switch { "REG" => "Regular", "CLUS" => "Clustering", _ => i.IndexType },
                    IsUnique = i.UniqueRule == "U" || i.UniqueRule == "P",
                    Columns = i.Colnames,
                    Levels = i.Nlevels
                }).ToList(),
                PrimaryKey = pkConst != null ? new SqlPrimaryKeyDef { ConstraintName = pkConst.ConstName, Columns = pkCols } : null,
                UniqueKeys = jsonConstraints.Where(c => c.Type == "U").Select(uk => new SqlUniqueKeyDef
                {
                    ConstraintName = uk.ConstName,
                    Columns = jsonKeyColumns.Where(k => k.ConstName == uk.ConstName).OrderBy(k => int.TryParse(k.ColSeq, out int s) ? s : 999).Select(k => k.ColName).ToList()
                }).ToList(),
                ForeignKeysOutgoing = jsonForeignKeys.Outgoing.Select(fk => new SqlForeignKeyDef
                {
                    ConstraintName = fk.ConstName,
                    FkColumns = fk.FkColnames.Replace("+", "").Replace("-", ""),
                    ReferencedTable = $"{fk.RefTabSchema.Trim()}.{fk.RefTabName.Trim()}",
                    PkColumns = fk.PkColnames.Replace("+", "").Replace("-", ""),
                    DeleteRule = fk.DeleteRule switch { "A" => "No Action", "C" => "Cascade", "N" => "Set Null", "R" => "Restrict", _ => fk.DeleteRule },
                    Link = ("./" + $"{fk.RefTabSchema.Trim()}.{fk.RefTabName.Trim()}".Replace(".", "_").ToLower() + ".sql.html")
                }).ToList(),
                ForeignKeysIncoming = jsonForeignKeys.Incoming.Select(fk => new SqlForeignKeyDef
                {
                    ConstraintName = fk.ConstName,
                    FkColumns = fk.FkColnames.Replace("+", "").Replace("-", ""),
                    ReferencedTable = $"{fk.TabSchema.Trim()}.{fk.TabName.Trim()}",
                    DeleteRule = fk.DeleteRule switch { "A" => "No Action", "C" => "Cascade", "N" => "Set Null", "R" => "Restrict", _ => fk.DeleteRule },
                    Link = ("./" + $"{fk.TabSchema.Trim()}.{fk.TabName.Trim()}".Replace(".", "_").ToLower() + ".sql.html")
                }).ToList(),
                Triggers = jsonTriggers.Select(t => new SqlTriggerDef
                {
                    Name = t.TrigName,
                    Timing = t.TrigTime switch { "A" => "AFTER", "B" => "BEFORE", "I" => "INSTEAD OF", _ => t.TrigTime },
                    Event = t.TrigEvent switch { "I" => "INSERT", "D" => "DELETE", "U" => "UPDATE", _ => t.TrigEvent },
                    Granularity = t.Granularity == "R" ? "Row" : "Statement",
                    IsValid = t.Valid == "Y"
                }).ToList(),
                InteractionDiagramMmd = GetInteractionDiagramForJson(sqlTable, outputFolder),
                UsedBy = GetUsedByList(sqlTable, outputFolder),
                Stats = int.TryParse(tableInfo.Card, out int rc) && rc >= 0 ? new SqlStatsDef
                {
                    RowCount = rc,
                    DataPages = int.TryParse(tableInfo.Npages, out int np2) ? np2 : 0,
                    ColumnCount = columnCount,
                    IndexCount = jsonIndexes.Count,
                    TriggerCount = jsonTriggers.Count,
                    ParentTableCount = jsonForeignKeys.Outgoing.Count,
                    ChildTableCount = jsonForeignKeys.Incoming.Count
                } : null
            };

            string jsonBaseFileName = sqlTable.Replace(".", "_").Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower() + ".sql";
            JsonResultWriter.WriteResult(sqlResult, outputFolder, jsonBaseFileName);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing JSON result for {sqlTable}: {ex.Message}", LogLevel.WARN);
        }

        return htmlFilename;
    }

    #endregion

    #region Start-SqlParse (lines 8934-9071)

    /// <summary>
    /// Main entry point for SQL table parsing.
    /// Converted line-by-line from Start-SqlParse (lines 8934-9071)
    /// </summary>
    public static string? StartSqlParse(
        string sqlTable,
        bool show = false,
        string outputFolder = "",
        bool cleanUp = true,
        string tmpRootFolder = "",
        string srcRootFolder = "",
        bool generateHtml = false)
    {
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder)) outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder)) tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        if (string.IsNullOrEmpty(srcRootFolder)) srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

        _errorOccurred = false;

        // Strip surrounding quotes from table names like "CRM"."A_ORDREHODE"
        // WorkQueueBuilder provides them as quoted identifiers from cobdok CSV
        sqlTable = sqlTable.Replace("\"", "");

        Logger.LogMessage($"Starting parsing of table: {sqlTable}", LogLevel.INFO);

        if (!sqlTable.Contains("."))
        { Logger.LogMessage($"Filename is not valid. Do not contain period in tablename: {sqlTable}", LogLevel.ERROR); return null; }

        DateTime startTime = DateTime.Now;
        string htmlFilename = Path.Combine(outputFolder, sqlTable.Replace(".", "_").ToLower() + ".sql.html");
        string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");
        Logger.LogMessage($"Started for: {sqlTable}", LogLevel.INFO);

        // Parse table name
        string[] temp1 = sqlTable.ToUpper().Split('.');
        string schemaName = temp1[0];
        string tableName = temp1[1];

        // Load table metadata
        var tableArray = new List<TableInfo>();
        string tablesCsvPath = Path.Combine(inputDbFileFolder, "tables.csv");
        if (File.Exists(tablesCsvPath))
        {
            try
            {
                foreach (string line in SourceFileCache.GetLines(tablesCsvPath) ?? File.ReadAllLines(tablesCsvPath, Encoding.UTF8))
                {
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    string[] parts = line.Split(';');
                    if (parts.Length >= 5 && parts[0].Trim().Trim('"') == schemaName && parts[1].Trim().Trim('"') == tableName)
                    {
                        tableArray.Add(new TableInfo
                        {
                            SchemaName = parts[0].Trim().Trim('"'), TableName = parts[1].Trim().Trim('"'),
                            Comment = parts[2].Trim().Trim('"'), Type = parts[3].Trim().Trim('"'),
                            AlterTime = parts[4].Trim().Trim('"')
                        });
                    }
                }
            }
            catch { tableArray = new List<TableInfo>(); }
        }

        // Load column metadata
        var columnsArray = new List<ColumnInfo>();
        string columnsCsvPath = Path.Combine(inputDbFileFolder, "columns.csv");
        if (File.Exists(columnsCsvPath))
        {
            try
            {
                foreach (string line in SourceFileCache.GetLines(columnsCsvPath) ?? File.ReadAllLines(columnsCsvPath, Encoding.UTF8))
                {
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    string[] parts = line.Split(';');
                    if (parts.Length >= 9 && parts[0].Trim().Trim('"').Contains(schemaName) && parts[1].Trim().Trim('"') == tableName)
                    {
                        columnsArray.Add(new ColumnInfo
                        {
                            TabSchema = parts[0].Trim().Trim('"'), TabName = parts[1].Trim().Trim('"'),
                            ColName = parts[2].Trim().Trim('"'), ColNo = parts[3].Trim().Trim('"'),
                            TypeSchema = parts[4].Trim().Trim('"'), TypeName = parts[5].Trim().Trim('"'),
                            Length = parts[6].Trim().Trim('"'), Scale = parts[7].Trim().Trim('"'),
                            Remarks = parts.Length > 8 ? parts[8].Trim().Trim('"') : ""
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"Failed to load columns.csv: {ex.Message}", LogLevel.WARN);
                columnsArray = new List<ColumnInfo>();
            }
        }
        else
            Logger.LogMessage($"Columns CSV file not found: {columnsCsvPath}", LogLevel.WARN);

        // Generate HTML
        if (!_errorOccurred && tableArray.Count > 0)
        {
            htmlFilename = GetSqlTableMetaData(tmpRootFolder, outputFolder, inputDbFileFolder, sqlTable, tableArray[0], columnsArray, generateHtml);

            if (show)
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = htmlFilename, UseShellExecute = true
                });
            }
        }

        // Log result
        DateTime endTime = DateTime.Now;
        TimeSpan timeDiff = endTime - startTime;
        string dummyFile = htmlFilename.Replace(".html", ".err");
        string jsonFilePath = htmlFilename.Replace(".html", ".json");
        bool htmlWasGenerated = File.Exists(htmlFilename) || File.Exists(jsonFilePath);

        if (htmlWasGenerated)
        {
            if (File.Exists(dummyFile)) try { File.Delete(dummyFile); } catch { }
            Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
            Logger.LogMessage(_errorOccurred ? $"Completed with warnings: {sqlTable}" : $"Completed successfully: {sqlTable}",
                _errorOccurred ? LogLevel.WARN : LogLevel.INFO);
            return htmlFilename;
        }
        else
        {
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            Logger.LogMessage($"Failed - HTML not generated: {sqlTable}", LogLevel.ERROR);
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            File.WriteAllText(dummyFile, $"Error: HTML file was not generated for {sqlTable}");
            return null;
        }
    }

    #endregion
}
