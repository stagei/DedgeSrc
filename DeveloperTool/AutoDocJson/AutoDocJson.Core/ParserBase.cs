using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace AutoDocNew.Core;

/// <summary>
/// Base parser class with shared functionality
/// Converted line-by-line from AutoDocFunctions.psm1 shared functions
/// </summary>
public abstract class ParserBase
{
    // Line 164-166: Precompiled regex patterns for performance
    private static readonly Regex YearPattern = new Regex(@"20[0-2][0-9]", RegexOptions.Compiled);
    private static readonly Regex SkipSuffixPattern = new Regex(@"-(ferdig|gml|old)$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex SkipFilesPattern = new Regex(@"(deploy\.(bat|ps1)|dirt\.bat|dell\.bat|ttt\.bat|tfselect\.bat|launch\.json|tr_rx)", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Line 42-44: Cached shared folder
    private static string? _sharedFolder = null;
    private static string? _outputFolder = null;
    private static string? _webFolderRoot = null;

    /// <summary>
    /// Get AutoDoc shared folder
    /// Converted from Get-AutodocSharedFolder function (lines 46-90)
    /// </summary>
    public static string GetAutodocSharedFolder()
    {
        // Line 59: Check cache
        if (_sharedFolder == null)
        {
            // Line 61-65: Try multiple locations
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string[] sharedLocations = new[]
            {
                Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc"),  // Development
                Path.Combine(optPath, "DedgePshApps", "AutoDoc"),                                        // Server deployment
                AppDomain.CurrentDomain.BaseDirectory                                                 // Fallback
            };

            // Line 67-75: Check each location for _css subfolder
            foreach (string sharedPath in sharedLocations)
            {
                // Line 69-70: Verify by checking for _css subfolder
                string cssFolder = Path.Combine(sharedPath, "_css");
                if (Directory.Exists(cssFolder))
                {
                    _sharedFolder = sharedPath;
                    Logger.LogMessage($"Set shared folder to: {sharedPath}", LogLevel.DEBUG);
                    break;
                }
            }

            // Line 78-86: If still not found, use first existing path
            if (_sharedFolder == null)
            {
                foreach (string sharedPath in sharedLocations)
                {
                    if (Directory.Exists(sharedPath))
                    {
                        _sharedFolder = sharedPath;
                        Logger.LogMessage($"Set shared folder to (fallback): {sharedPath}", LogLevel.DEBUG);
                        break;
                    }
                }
            }
        }

        // Line 89: return $script:sharedFolder
        return _sharedFolder ?? "";
    }

    /// <summary>
    /// Get AutoDoc templates folder
    /// Converted from Get-AutodocTemplatesFolder function (lines 92-111)
    /// </summary>
    public static string GetAutodocTemplatesFolder()
    {
        // Line 103: $sharedFolder = Get-AutodocSharedFolder
        string sharedFolder = GetAutodocSharedFolder();
        // Line 104: $templatesFolder = Join-Path $sharedFolder "_templates"
        string templatesFolder = Path.Combine(sharedFolder, "_templates");

        // Line 106-108: Check if exists
        if (!Directory.Exists(templatesFolder))
        {
            Logger.LogMessage($"Templates folder not found: {templatesFolder}", LogLevel.WARN);
        }

        // Line 110: return $templatesFolder
        return templatesFolder;
    }

    /// <summary>
    /// Set AutoDoc template - applies common replacements
    /// Converted from Set-AutodocTemplate function (lines 113-161)
    /// </summary>
    public static string SetAutodocTemplate(string template, string outputFolder)
    {
        // Line 136: Load and inject shared CSS from OutputFolder\_css subfolder
        string cssFolder = Path.Combine(outputFolder, "_css");
        string sharedCssPath = Path.Combine(cssFolder, "autodoc-shared.css");
        string sharedCss = File.ReadAllText(sharedCssPath, Encoding.UTF8);
        // Line 139: Replace [css] placeholder
        template = template.Replace("[css]", sharedCss);

        // Line 143-144: Use relative paths for images
        template = template.Replace("[iconurl]", "./_images/dedge.ico");
        template = template.Replace("[imageurl]", "./_images/dedge.svg");

        // Line 146: Add cache-busting timestamp
        string cacheBust = DateTime.Now.ToString("yyyyMMddHHmm");

        // Line 154-157: Relative URL for JS files (bundled with output)
        string jsBaseUrl = "./_js";
        template = template.Replace("[mermaidconfigurl]", $"{jsBaseUrl}/autodoc-mermaid-config.js?v={cacheBust}");
        template = template.Replace("[controlsscripturl]", $"{jsBaseUrl}/autodoc-diagram-controls.js?v={cacheBust}");
        template = template.Replace("[functionscripturl]", $"{jsBaseUrl}/autodoc-function-navigation.js?v={cacheBust}");
        template = template.Replace("[autodochomepageurl]", "index.html");

        // Line 160: return $Template
        return template;
    }

    /// <summary>
    /// Find AutoDoc usages - finds usages of a pattern across source files
    /// Converted line-by-line from Find-AutodocUsages function (lines 185-327)
    /// </summary>
    public static (List<string> ResultArray, List<object> ResultArrayFull) FindAutodocUsages(
        string pattern,
        string findPath,
        string includeFilter,
        List<string>? resultArray = null,
        List<object>? resultArrayFull = null)
    {
        // Line 227-233: Early exit for invalid patterns
        int pos = pattern.IndexOf(".");
        int length = (pos != -1) ? pos : pattern.Length;

        if (string.IsNullOrEmpty(pattern) || length < 4)
        {
            return (resultArray ?? new List<string>(), resultArrayFull ?? new List<object>());
        }

        // Line 236-238: Extract base pattern without extension
        if (pattern.Contains(".cbl") || pattern.Contains(".rex"))
        {
            pattern = pattern.Split(".")[0];
        }

        // Line 241-244: Use List for O(1) additions (equivalent to ArrayList)
        List<string> resultList = resultArray != null ? new List<string>(resultArray) : new List<string>();
        List<object> resultFullList = resultArrayFull != null ? new List<object>(resultArrayFull) : new List<object>();

        // Line 246: $patternLower = $Pattern.Trim().ToLower()
        string patternLower = pattern.Trim().ToLower();

        // Line 248-263: XML file search for scheduled tasks
        if (includeFilter == "*.xml")
        {
            if (Directory.Exists(findPath))
            {
                // Use cache for file enumeration if available, fall back to disk
                IEnumerable<string> xmlFiles = SourceFileCache.IsEnabled
                    ? SourceFileCache.EnumerateFiles(findPath, "*.xml")
                    : Directory.EnumerateFiles(findPath, "*.xml", SearchOption.AllDirectories);
                foreach (string filePath in xmlFiles)
                {
                    try
                    {
                        string[] lines = SourceFileCache.GetLines(filePath) ?? File.ReadAllLines(filePath);
                        foreach (string line in lines)
                        {
                            if ((line.Contains("<Command>") && line.Contains("</Command>")) ||
                                (line.Contains("<Arguments>") && line.Contains("</Arguments>")))
                            {
                                if (line.Contains(pattern, StringComparison.OrdinalIgnoreCase))
                                {
                                    string filenameLower = Path.GetFileName(filePath).Trim().ToLower();
                                    if (filenameLower == patternLower)
                                    {
                                        continue;
                                    }

                                    if (!resultList.Contains(filenameLower))
                                    {
                                        resultList.Add(filenameLower);
                                        resultFullList.Add(new { Path = filePath, Line = line, Filename = Path.GetFileName(filePath) });
                                    }
                                }
                            }
                        }
                    }
                    catch
                    {
                        // Skip files that can't be read
                    }
                }
            }
        }
        else
        {
            // Line 267-318: Source file search
            if (Directory.Exists(findPath))
            {
                string searchPattern = includeFilter.Replace("*", "");
                // Use cache for file enumeration and reading if available, fall back to disk
                IEnumerable<string> files = SourceFileCache.IsEnabled
                    ? SourceFileCache.EnumerateFiles(findPath, includeFilter)
                    : Directory.EnumerateFiles(findPath, includeFilter, SearchOption.AllDirectories)
                        .Where(f => !f.Contains("\\bin\\") && !f.Contains("\\obj\\") && !f.Contains("\\.vs\\") && !f.Contains("\\.git\\"));

                foreach (string filePath in files)
                {
                    try
                    {
                        string[] lines = SourceFileCache.GetLines(filePath) ?? File.ReadAllLines(filePath);
                        string filename = Path.GetFileName(filePath);
                        string filenameLower = filename.ToLower().Trim();

                        int dotPos = filenameLower.LastIndexOf(".");
                        string extension = (dotPos == -1) ? "" : filenameLower.Substring(dotPos);
                        string baseName = (dotPos == -1) ? filenameLower : filenameLower.Substring(0, dotPos);

                        for (int lineNum = 0; lineNum < lines.Length; lineNum++)
                        {
                            string line = lines[lineNum];
                            string lineLower = line.ToLower().Trim();

                            // Line 281-287: Skip comments based on file type
                            bool skipLine = false;
                            switch (extension)
                            {
                                case ".bat":
                                    if (lineLower.StartsWith("rem"))
                                    {
                                        skipLine = true;
                                    }
                                    break;
                                case ".ps1":
                                case ".rex":
                                    if (lineLower.StartsWith("#"))
                                    {
                                        skipLine = true;
                                    }
                                    break;
                                case ".cbl":
                                    if (lineLower.Length > 6 && lineLower.Substring(6, 1) == "*")
                                    {
                                        skipLine = true;
                                    }
                                    break;
                                case ".xml":
                                    if (lineLower.StartsWith("<!--"))
                                    {
                                        skipLine = true;
                                    }
                                    break;
                                case ".cs":
                                    if (lineLower.TrimStart().StartsWith("//"))
                                    {
                                        skipLine = true;
                                    }
                                    break;
                                case ".psm1":
                                    if (lineLower.StartsWith("#"))
                                    {
                                        skipLine = true;
                                    }
                                    break;
                            }

                            if (skipLine)
                            {
                                continue;
                            }

                            // Line 290-295: Verify exact pattern match
                            int patternPos = lineLower.IndexOf(patternLower);
                            if (patternPos == -1)
                            {
                                continue;
                            }

                            string temp = (lineLower.Substring(patternPos).Trim().Replace("'", "").Replace("\"", "") + " ").Split(' ')[0];
                            if (temp != patternLower)
                            {
                                continue;
                            }

                            // Line 298-299: Skip self-references
                            if (baseName == patternLower && (extension == ".cbl" || extension == ".rex"))
                            {
                                continue;
                            }
                            if (filenameLower == patternLower)
                            {
                                continue;
                            }

                            // Line 302: Skip utility files using precompiled regex
                            if (SkipFilesPattern.IsMatch(filenameLower))
                            {
                                continue;
                            }

                            // Line 305-307: Skip year-based and old files using precompiled regex
                            if (YearPattern.IsMatch(baseName) || SkipSuffixPattern.IsMatch(baseName))
                            {
                                continue;
                            }

                            // Line 309-317: Add to results
                            if (!resultList.Contains(filenameLower))
                            {
                                try
                                {
                                    resultList.Add(filenameLower);
                                    resultFullList.Add(new { Path = filePath, Line = line, LineNumber = lineNum + 1, Filename = filename, Extension = extension, BaseName = baseName });
                                }
                                catch (Exception ex)
                                {
                                    Logger.LogMessage($"Error in FindAutodocUsages: {ex.Message}", LogLevel.ERROR, ex);
                                }
                            }
                        }
                    }
                    catch
                    {
                        // Skip files that can't be read
                    }
                }
            }
        }

        // Line 323-324: Return unique sorted results
        List<string> uniqueResults = resultList.Distinct().OrderBy(x => x).Where(x => Regex.IsMatch(x, @"^[\x00-\x7F]+$")).ToList();
        List<object> uniqueResultsFull = resultFullList.Distinct().ToList();

        // Line 326: return @($uniqueResults), @($uniqueResultsFull)
        return (uniqueResults, uniqueResultsFull);
    }
}
