using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using AutoDocNew.Core;

namespace AutoDocNew.Parsers;

/// <summary>
/// Execution path helper - finds and diagrams how scripts/programs are called.
/// Converted line-by-line from AutoDocFunctions.psm1:
///   Test-ExecutedFromScheduledTask (lines 329-414)
///   Get-AutodocExecutionPath (lines 416-504)
///   Find-AutodocExecutionPaths / IsExecutedFromAny (lines 506-603)
///   New-AutodocSvgFile / GenerateSvgFile (lines 605-688)
/// </summary>
public static class ExecutionPathHelper
{
    // Line 164-166: Precompiled regex patterns (same as in ParserBase)
    private static readonly Regex SkipFilesPattern = new Regex(
        @"(deploy\.(bat|ps1)|dirt\.bat|dell\.bat|ttt\.bat|tfselect\.bat|launch\.json|tr_rx)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>
    /// Checks if a script is executed from Windows Task Scheduler.
    /// Converted line-by-line from Test-ExecutedFromScheduledTask (lines 329-414)
    /// </summary>
    public static (bool ProgramInUse, List<string> ReturnMmdArray, HashSet<string> SearchFiles)
        TestExecutedFromScheduledTask(
            bool programInUse,
            List<string> returnMmdArray,
            HashSet<string> searchFiles,
            string srcRootFolder,
            string filename)
    {
        // Line 367: $findpath = Join-Path $SrcRootFolder "Dedge\ExportScheduledTasks\"
        string findPath = Path.Combine(srcRootFolder, "Dedge", "ExportScheduledTasks");

        // Line 369-371: Check if path exists
        if (!Directory.Exists(findPath))
            return (programInUse, returnMmdArray, searchFiles);

        // Line 373-375: Find usages in XML files
        var (resultArray1, _) = ParserBase.FindAutodocUsages(
            filename, findPath, "*.xml");

        // Line 378-383: Ensure searchFiles is initialized
        if (searchFiles == null)
            searchFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Line 385-386: Ensure mmdList is initialized
        var mmdList = new List<string>(returnMmdArray);

        // Line 388
        string filenameLower = filename.Trim().ToLower();

        // Line 390-410: Process each result
        foreach (string item in resultArray1)
        {
            if (string.IsNullOrWhiteSpace(item))
                continue;

            // Line 393-397: Extract server name from path
            // Path format: ...ExportScheduledTasks\SERVERNAME\taskname.xml
            string[] temp1 = item.ToLower().Trim().Split("exportscheduledtasks");
            if (temp1.Length < 2)
                continue;

            string[] temp2 = temp1[1].Split('\\');
            if (temp2.Length < 2)
                continue;

            string server = temp2[1].ToUpper().Trim();
            string itemFilenameLower = Path.GetFileNameWithoutExtension(item).ToLower().Trim();
            // Line 401: Create unique search key
            string searchKey = $"{itemFilenameLower}¤{filenameLower}";

            // Line 403: Skip duplicates
            if (searchFiles.Contains(searchKey))
                continue;

            // Line 405-409
            searchFiles.Add(searchKey);
            programInUse = true;

            string scheduledTask = $"ScheduledTask on server {server}\n{itemFilenameLower}";
            mmdList.Add($"{itemFilenameLower}>\"{scheduledTask}\"]-.-> {filenameLower}");
        }

        return (programInUse, mmdList, searchFiles);
    }

    /// <summary>
    /// Common handling for execution path analysis.
    /// Converted line-by-line from Get-AutodocExecutionPath (lines 416-504)
    /// Returns: (itemLower, searchItem, searchFiles, skipLine, returnMmdArray, programInUse)
    /// </summary>
    public static (string ItemLower, string SearchItem, HashSet<string> SearchFiles, bool SkipLine, List<string> ReturnMmdArray, bool ProgramInUse)
        GetAutoDocExecutionPath(
            HashSet<string> searchFiles,
            string? item,
            string? prevItem,
            List<string> returnMmdArray,
            bool programInUse,
            string srcRootFolder)
    {
        try
        {
            bool skipLine = false;

            // Line 440-444: Handle null or empty Item
            if (string.IsNullOrWhiteSpace(item))
            {
                var emptyMmdList = new List<string>(returnMmdArray);
                return ("", "", searchFiles, true, emptyMmdList, programInUse);
            }

            // Line 447-448
            string itemLower = item.ToLower().Trim();
            // Regex: \.(cbl|rex)$ - Remove .cbl or .rex extension from end
            string searchItem = Regex.Replace(itemLower, @"\.(cbl|rex)$", "");

            // Line 451-453: Skip utility files
            if (SkipFilesPattern.IsMatch(itemLower) || itemLower.Contains(" "))
                skipLine = true;

            // Line 456-467: Ensure searchFiles is a HashSet
            if (searchFiles == null)
                searchFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // Line 469-470
            var mmdList = new List<string>(returnMmdArray);

            // Line 472-488: Process previous item connection
            if (!string.IsNullOrWhiteSpace(prevItem))
            {
                string prevItemLower = prevItem.Trim().ToLower();
                // Line 474: Create search key
                string searchKey = $"{itemLower}¤{prevItemLower}";

                // Line 476-478: Check for duplicate
                if (searchFiles.Contains(searchKey))
                {
                    skipLine = true;
                }
                else
                {
                    // Line 480
                    searchFiles.Add(searchKey);
                }

                // Line 483-488: Generate mermaid lines
                if (!skipLine)
                {
                    mmdList.Add($"{itemLower}[[{itemLower}]]-.-> {prevItemLower}");
                    string link = $"./{itemLower.Trim()}.html";
                    mmdList.Add($"click {itemLower} \"{link}\" \"{itemLower}\" _blank");
                    mmdList.Add($"style {itemLower} stroke:dark-blue,stroke-width:4px");
                }
            }

            // Line 491-493: Check scheduled tasks
            if (!skipLine)
            {
                (programInUse, mmdList, searchFiles) = TestExecutedFromScheduledTask(
                    programInUse, mmdList, searchFiles, srcRootFolder, itemLower);
            }

            return (itemLower, searchItem, searchFiles, skipLine, mmdList, programInUse);
        }
        catch
        {
            // Line 499-502: On error, return skip=true
            var errorMmdList = new List<string>(returnMmdArray);
            return ("", "", searchFiles, true, errorMmdList, programInUse);
        }
    }

    /// <summary>
    /// Finds all execution paths for a script/program.
    /// Converted line-by-line from Find-AutodocExecutionPaths / IsExecutedFromAny (lines 506-603)
    /// </summary>
    public static (bool ProgramInUse, List<string> ReturnMmdArray) FindAutoDocExecutionPaths(
        string findPath,
        string[] includeFilters,
        string filename,
        bool programInUse,
        string srcRootFolder)
    {
        // Line 547-549: Initialize
        var searchFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var returnMmdArray = new List<string>();

        // Line 551: Initial processing
        string itemLower, searchItem;
        bool skipLine;
        (itemLower, searchItem, searchFiles, skipLine, returnMmdArray, programInUse) =
            GetAutoDocExecutionPath(searchFiles, filename, null, returnMmdArray, programInUse, srcRootFolder);

        // Line 554: Find primary usages (search in all filter types)
        var allResults = new List<string>();
        foreach (string filter in includeFilters)
        {
            var (results, _) = ParserBase.FindAutodocUsages(searchItem, findPath, filter);
            allResults.AddRange(results);
        }

        // Line 556-558: Check for results
        if (allResults.Count == 0)
            return (programInUse, returnMmdArray);

        // Line 561-569: Filter and sort unique results
        var resultArray1 = allResults
            .Where(r => !string.IsNullOrWhiteSpace(r))
            .Distinct()
            .OrderBy(x => x)
            .ToList();

        // Line 571-599: Process each result (two levels deep)
        foreach (string item1 in resultArray1)
        {
            if (string.IsNullOrWhiteSpace(item1))
                continue;

            // Line 574: Process first level
            (itemLower, var searchItem1, searchFiles, skipLine, returnMmdArray, programInUse) =
                GetAutoDocExecutionPath(searchFiles, item1, filename, returnMmdArray, programInUse, srcRootFolder);

            if (skipLine)
                continue;

            programInUse = true;

            // Line 580: Find secondary usages
            var allResults2 = new List<string>();
            foreach (string filter in includeFilters)
            {
                var (results2, _) = ParserBase.FindAutodocUsages(searchItem1, findPath, filter);
                allResults2.AddRange(results2);
            }

            // Line 588-589: Filter and sort
            var resultArray2 = allResults2
                .Where(r => !string.IsNullOrWhiteSpace(r))
                .Distinct()
                .OrderBy(x => x)
                .ToList();

            // Line 591-597: Process second level
            foreach (string item2 in resultArray2)
            {
                if (string.IsNullOrWhiteSpace(item2))
                    continue;

                (_, _, searchFiles, skipLine, returnMmdArray, programInUse) =
                    GetAutoDocExecutionPath(searchFiles, item2, item1, returnMmdArray, programInUse, srcRootFolder);

                if (skipLine)
                    continue;

                programInUse = true;
                // Line 598: Tertiary usages skipped for performance
            }
        }

        return (programInUse, returnMmdArray);
    }

    /// <summary>
    /// Generates SVG file from Mermaid diagram using mmdc.cmd.
    /// Converted line-by-line from New-AutodocSvgFile / GenerateSvgFile (lines 605-688)
    /// </summary>
    public static bool GenerateSvgFile(string mmdFilename, string? configPath = null)
    {
        try
        {
            // Line 633: SVG filename
            string svgFilename = mmdFilename.Replace(".mmd", ".svg");

            // Line 635-637: Remove existing SVG
            if (File.Exists(svgFilename))
                File.Delete(svgFilename);

            // Line 640-645: Determine config path
            if (string.IsNullOrEmpty(configPath))
            {
                string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
                configPath = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "config.json");
                if (!File.Exists(configPath))
                    configPath = ".\\config.json";
            }

            // Line 647: Call mmdc.cmd
            var psi = new ProcessStartInfo
            {
                FileName = "mmdc.cmd",
                Arguments = $"-i \"{mmdFilename}\" -o \"{svgFilename}\" --configFile \"{configPath}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process == null)
            {
                Logger.LogMessage("Failed to start mmdc.cmd", LogLevel.ERROR);
                return false;
            }

            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            process.WaitForExit();

            string processOutput = output + error;

            // Line 649-655: Check for errors
            if (processOutput.Contains("Error:"))
            {
                Logger.LogMessage($"Error in mmdc.cmd. SVG not generated. See: {mmdFilename}", LogLevel.ERROR);
                return false;
            }

            // Line 658-681: Read SVG content and apply replacements
            if (!File.Exists(svgFilename))
                return false;

            string content = File.ReadAllText(svgFilename);

            // Line 661-674: Define replacement pairs for target="_blank"
            var replacements = new (string Old, string New)[]
            {
                (".cbl.html\">", ".cbl.html\" target=\"_blank\">"),
                (".sql.html\">", ".sql.html\" target=\"_blank\">"),
                (".rex.html\">", ".rex.html\" target=\"_blank\">"),
                (".bat.html\">", ".bat.html\" target=\"_blank\">"),
                (".ps1.html\">", ".ps1.html\" target=\"_blank\">"),
                (".cbl\">", ".cbl\" target=\"_blank\">"),
                (".sql\">", ".sql\" target=\"_blank\">"),
                (".rex\">", ".rex\" target=\"_blank\">"),
                (".bat\">", ".bat\" target=\"_blank\">"),
                (".ps1\">", ".ps1\" target=\"_blank\">"),
                ("ProjectFilters%7BDedge%7D\">", "ProjectFilters%7BDedge%7D\" target=\"_blank\">"),
                ("lineStartColumn=1&amp;lineEndColumn=1&amp;lineStyle=plain&amp;_a=contents\">",
                 "lineStartColumn=1&amp;lineEndColumn=1&amp;lineStyle=plain&amp;_a=contents\" target=\"_blank\">"),
                ("Dedgeopath=", "Dedge?path=")
            };

            foreach (var (old, @new) in replacements)
            {
                content = content.Replace(old, @new);
            }

            File.WriteAllText(svgFilename, content);
            return true;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GenerateSvgFile: {ex.Message}", LogLevel.ERROR, ex);
            return false;
        }
    }
}
