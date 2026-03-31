using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace AutoDocNew.Core;

/// <summary>
/// Builds a unified work queue of files/tables to process.
/// Supports both legacy per-file scanning and the new worklist-based approach.
/// Non-CBL items come first (faster to parse), CBL items last.
/// </summary>
public static class WorkQueueBuilder
{
    /// <summary>
    /// Build work queue from pre-detected worklist items (new optimized path).
    /// Converts WorklistItems to WorkItems, maintaining non-CBL-first ordering.
    /// </summary>
    public static List<WorkItem> BuildFromWorklist(List<WorklistItem> worklistItems, int maxPerType)
    {
        int limit = maxPerType > 0 ? maxPerType : int.MaxValue;
        var nonCbl = new List<WorkItem>();
        var cbl = new List<WorkItem>();
        var typeCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var wl in worklistItems)
        {
            string type = wl.ParserType ?? "";
            typeCounts.TryGetValue(type, out int count);
            if (count >= limit)
                continue;
            typeCounts[type] = count + 1;

            var workItem = new WorkItem
            {
                ParserType = type.ToUpperInvariant(),
                FilePath = wl.LocalPath,
                FileName = wl.FileName,
                TableName = wl.TableName,
                AlterTime = wl.AlterTime
            };

            if (string.Equals(type, "CBL", StringComparison.OrdinalIgnoreCase))
                cbl.Add(workItem);
            else
                nonCbl.Add(workItem);
        }

        var queue = new List<WorkItem>(nonCbl.Count + cbl.Count);
        queue.AddRange(nonCbl);
        queue.AddRange(cbl);

        int rexCount = queue.Count(i => i.ParserType == "REX");
        int batCount = queue.Count(i => i.ParserType == "BAT");
        int ps1Count = queue.Count(i => i.ParserType == "PS1");
        int sqlCount = queue.Count(i => i.ParserType == "SQL");
        int gsCount = queue.Count(i => i.ParserType == "GS");
        int cblCount = cbl.Count;
        Logger.LogMessage(
            $"Work queue (from worklist): CBL={cblCount} | Non-CBL={nonCbl.Count} " +
            $"(REX={rexCount} BAT={batCount} PS1={ps1Count} SQL={sqlCount} GS={gsCount}) | Total={queue.Count}",
            LogLevel.INFO);

        return queue;
    }

    /// <summary>
    /// Legacy build method: scans file system for .err files (Errors mode only).
    /// For all other modes, use BuildFromWorklist() with GitChangeDetector results.
    /// </summary>
    public static List<WorkItem> Build(
        string workFolder, string cobdokFolder, string outputFolder,
        HashSet<string> fileTypes, string regenerate, int lastGenerationDate, int maxPerType)
    {
        int limit = maxPerType > 0 ? maxPerType : int.MaxValue;
        var nonCbl = new List<WorkItem>();
        var cbl = new List<WorkItem>();

        string DedgeFolder = Path.Combine(workFolder, "Dedge");
        string DedgePshFolder = Path.Combine(workFolder, "DedgePsh");

        // ── REX ─────────────────────────────────────────────────────────
        if (fileTypes.Contains("Rex"))
        {
            string rexDir = Path.Combine(DedgeFolder, "rexx_prod");
            if (Directory.Exists(rexDir))
            {
                int n = 0;
                foreach (var fi in new DirectoryInfo(rexDir).GetFiles("*.rex").OrderBy(f => f.Name))
                {
                    if (n >= limit) break;
                    if (ShouldIncludeForErrors(fi.Name, regenerate, outputFolder))
                    {
                        nonCbl.Add(new WorkItem { ParserType = "REX", FilePath = fi.FullName, FileName = fi.Name });
                        n++;
                    }
                }
            }
        }

        // ── BAT ─────────────────────────────────────────────────────────
        if (fileTypes.Contains("Bat"))
        {
            string batDir = Path.Combine(DedgeFolder, "bat_prod");
            if (Directory.Exists(batDir))
            {
                int n = 0;
                foreach (var fi in new DirectoryInfo(batDir).GetFiles("*.bat")
                    .Where(f => !Regex.IsMatch(f.Name, @"^[_-]"))
                    .OrderBy(f => f.Name))
                {
                    if (n >= limit) break;
                    if (ShouldIncludeForErrors(fi.Name, regenerate, outputFolder))
                    {
                        nonCbl.Add(new WorkItem { ParserType = "BAT", FilePath = fi.FullName, FileName = fi.Name });
                        n++;
                    }
                }
            }
        }

        // ── PS1 ─────────────────────────────────────────────────────────
        if (fileTypes.Contains("Ps1") && Directory.Exists(DedgePshFolder))
        {
            int n = 0;
            foreach (var fi in new DirectoryInfo(DedgePshFolder).GetFiles("*.ps1", SearchOption.AllDirectories)
                .Where(f => !Regex.IsMatch(f.Name, @"^[_-]"))
                .OrderBy(f => f.FullName))
            {
                if (n >= limit) break;
                if (ShouldIncludeForErrors(fi.Name, regenerate, outputFolder))
                {
                    nonCbl.Add(new WorkItem { ParserType = "PS1", FilePath = fi.FullName, FileName = fi.Name });
                    n++;
                }
            }
        }

        // SQL is skipped in Errors mode (existing behavior)

        // ── CBL ─────────────────────────────────────────────────────────
        if (fileTypes.Contains("Cbl"))
        {
            string cblDir = Path.Combine(DedgeFolder, "cbl");
            if (Directory.Exists(cblDir))
            {
                int n = 0;
                foreach (var fi in new DirectoryInfo(cblDir).GetFiles("*.cbl")
                    .Where(f => !f.Name.Contains("-"))
                    .OrderBy(f => f.Name))
                {
                    if (n >= limit) break;
                    if (ShouldIncludeForErrors(fi.Name, regenerate, outputFolder))
                    {
                        cbl.Add(new WorkItem { ParserType = "CBL", FilePath = fi.FullName, FileName = fi.Name });
                        n++;
                    }
                }
            }
        }

        var queue = new List<WorkItem>(nonCbl.Count + cbl.Count);
        queue.AddRange(nonCbl);
        queue.AddRange(cbl);

        int rexCount = queue.Count(i => i.ParserType == "REX");
        int batCount = queue.Count(i => i.ParserType == "BAT");
        int ps1Count = queue.Count(i => i.ParserType == "PS1");
        int cblCount = cbl.Count;
        Logger.LogMessage($"Work queue (legacy/Errors): CBL={cblCount} | Non-CBL={nonCbl.Count} (REX={rexCount} BAT={batCount} PS1={ps1Count}) | Total={queue.Count}", LogLevel.INFO);

        return queue;
    }

    /// <summary>
    /// For Errors mode: include file only if a matching .err file exists in output folder.
    /// </summary>
    private static bool ShouldIncludeForErrors(string fileName, string regenerate, string outputFolder)
    {
        if (!string.Equals(regenerate, "Errors", StringComparison.OrdinalIgnoreCase))
            return true;
        string errPath = Path.Combine(outputFolder, fileName + ".err");
        return File.Exists(errPath);
    }
}
