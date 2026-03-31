using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using AutoDocNew.Core;

namespace AutoDocNew.Tests;

/// <summary>
/// HTML Comparer - compares HTML files from PowerShell and C# versions
/// Identifies show-stopper differences and calculates similarity percentage
/// </summary>
public class HtmlComparer
{
    /// <summary>
    /// Compare two HTML files and return comparison result
    /// </summary>
    public static ComparisonResult CompareHtmlFiles(string powershellHtmlPath, string csharpHtmlPath)
    {
        var result = new ComparisonResult
        {
            PowershellPath = powershellHtmlPath,
            CsharpPath = csharpHtmlPath,
            Similarity = 0.0,
            ShowStoppers = new List<string>(),
            AcceptableDifferences = new List<string>(),
            Status = "Unknown"
        };

        try
        {
            if (!File.Exists(powershellHtmlPath))
            {
                result.ShowStoppers.Add($"PowerShell HTML file not found: {powershellHtmlPath}");
                result.Status = "Error";
                return result;
            }

            if (!File.Exists(csharpHtmlPath))
            {
                result.ShowStoppers.Add($"C# HTML file not found: {csharpHtmlPath}");
                result.Status = "Error";
                return result;
            }

            string psHtml = File.ReadAllText(powershellHtmlPath, Encoding.UTF8);
            string csHtml = File.ReadAllText(csharpHtmlPath, Encoding.UTF8);

            // Normalize HTML (remove timestamps, normalize whitespace)
            psHtml = NormalizeHtml(psHtml);
            csHtml = NormalizeHtml(csHtml);

            // Check for show-stopper differences
            CheckShowStoppers(psHtml, csHtml, result);

            // Calculate structural similarity
            double structuralSimilarity = CalculateStructuralSimilarity(psHtml, csHtml);

            // Calculate content similarity
            double contentSimilarity = CalculateContentSimilarity(psHtml, csHtml);

            // Calculate Mermaid similarity
            double mermaidSimilarity = CalculateMermaidSimilarity(psHtml, csHtml);

            // Weighted average: Structure 40%, Content 40%, Mermaid 20%
            result.Similarity = (structuralSimilarity * 0.4) + (contentSimilarity * 0.4) + (mermaidSimilarity * 0.2);

            // Determine status
            if (result.ShowStoppers.Count > 0)
            {
                result.Status = "ShowStopper";
            }
            else if (result.Similarity >= 0.98)
            {
                result.Status = "Match";
            }
            else if (result.Similarity >= 0.90)
            {
                result.Status = "Acceptable";
            }
            else
            {
                result.Status = "LowSimilarity";
            }
        }
        catch (Exception ex)
        {
            result.ShowStoppers.Add($"Comparison error: {ex.Message}");
            result.Status = "Error";
            Logger.LogMessage($"Error comparing HTML files: {ex.Message}", LogLevel.ERROR, ex);
        }

        return result;
    }

    /// <summary>
    /// Normalize HTML for comparison - remove timestamps, normalize whitespace
    /// </summary>
    private static string NormalizeHtml(string html)
    {
        // Remove timestamp comments (e.g., <!-- Generated: 2026-02-04 12:34:56 -->)
        html = Regex.Replace(html, @"<!--\s*Generated:.*?-->", "", RegexOptions.IgnoreCase | RegexOptions.Singleline);
        html = Regex.Replace(html, @"<!--\s*.*?\d{4}-\d{2}-\d{2}.*?-->", "", RegexOptions.IgnoreCase | RegexOptions.Singleline);

        // Remove cache-busting query strings (?v=YYYYMMDDHHmm)
        html = Regex.Replace(html, @"\?v=\d{12}", "", RegexOptions.IgnoreCase);

        // Normalize whitespace (multiple spaces/tabs/newlines to single space)
        html = Regex.Replace(html, @"\s+", " ", RegexOptions.Multiline);

        // Normalize line endings
        html = html.Replace("\r\n", "\n").Replace("\r", "\n");

        return html.Trim();
    }

    /// <summary>
    /// Check for show-stopper differences
    /// </summary>
    private static void CheckShowStoppers(string psHtml, string csHtml, ComparisonResult result)
    {
        // Check for CSS inclusion
        bool psHasCss = psHtml.Contains("autodoc-shared.css") || psHtml.Contains(":root") || psHtml.Contains("--bg-primary");
        bool csHasCss = csHtml.Contains("autodoc-shared.css") || csHtml.Contains(":root") || csHtml.Contains("--bg-primary");
        if (psHasCss && !csHasCss)
        {
            result.ShowStoppers.Add("C# HTML missing CSS styles");
        }
        if (!psHasCss && csHasCss)
        {
            result.AcceptableDifferences.Add("CSS inclusion differs (PowerShell missing CSS)");
        }

        // Check for Mermaid diagrams
        bool psHasMermaid = psHtml.Contains("class=\"mermaid\"") || psHtml.Contains("<div class=\"mermaid\">");
        bool csHasMermaid = csHtml.Contains("class=\"mermaid\"") || csHtml.Contains("<div class=\"mermaid\">");
        if (psHasMermaid && !csHasMermaid)
        {
            result.ShowStoppers.Add("C# HTML missing Mermaid diagrams");
        }
        if (!psHasMermaid && csHasMermaid)
        {
            result.ShowStoppers.Add("C# HTML has Mermaid diagrams but PowerShell doesn't");
        }

        // Check for JavaScript includes
        bool psHasJs = psHtml.Contains("autodoc-mermaid-config.js") || psHtml.Contains("autodoc-diagram-controls.js");
        bool csHasJs = csHtml.Contains("autodoc-mermaid-config.js") || csHtml.Contains("autodoc-diagram-controls.js");
        if (psHasJs && !csHasJs)
        {
            result.ShowStoppers.Add("C# HTML missing JavaScript includes");
        }

        // Check for key HTML sections (tabs)
        string[] keySections = { "Overview", "Source Code", "Diagrams", "Functions", "Metadata" };
        foreach (string section in keySections)
        {
            bool psHasSection = Regex.IsMatch(psHtml, $"<div[^>]*{section}", RegexOptions.IgnoreCase) || 
                                Regex.IsMatch(psHtml, $"tab[^>]*{section}", RegexOptions.IgnoreCase) ||
                                psHtml.Contains(section, StringComparison.OrdinalIgnoreCase);
            bool csHasSection = Regex.IsMatch(csHtml, $"<div[^>]*{section}", RegexOptions.IgnoreCase) || 
                                Regex.IsMatch(csHtml, $"tab[^>]*{section}", RegexOptions.IgnoreCase) ||
                                csHtml.Contains(section, StringComparison.OrdinalIgnoreCase);
            if (psHasSection && !csHasSection)
            {
                result.ShowStoppers.Add($"C# HTML missing section: {section}");
            }
        }

        // Check for icon/image references
        bool psHasIcon = psHtml.Contains("dedge.ico") || psHtml.Contains("rel=\"icon\"");
        bool csHasIcon = csHtml.Contains("dedge.ico") || csHtml.Contains("rel=\"icon\"");
        if (psHasIcon && !csHasIcon)
        {
            result.AcceptableDifferences.Add("Icon reference differs");
        }
    }

    /// <summary>
    /// Calculate structural similarity (HTML element structure)
    /// </summary>
    private static double CalculateStructuralSimilarity(string psHtml, string csHtml)
    {
        // Extract HTML tags structure
        var psTags = ExtractHtmlTags(psHtml);
        var csTags = ExtractHtmlTags(csHtml);

        if (psTags.Count == 0 && csTags.Count == 0)
        {
            return 1.0;
        }

        if (psTags.Count == 0 || csTags.Count == 0)
        {
            return 0.0;
        }

        // Calculate Jaccard similarity
        int intersection = psTags.Intersect(csTags).Count();
        int union = psTags.Union(csTags).Count();

        return union > 0 ? (double)intersection / union : 0.0;
    }

    /// <summary>
    /// Extract HTML tags for structural comparison
    /// </summary>
    private static HashSet<string> ExtractHtmlTags(string html)
    {
        var tags = new HashSet<string>();
        var matches = Regex.Matches(html, @"<(\w+)[^>]*>", RegexOptions.IgnoreCase);
        foreach (Match match in matches)
        {
            if (match.Groups.Count > 1)
            {
                tags.Add(match.Groups[1].Value.ToLower());
            }
        }
        return tags;
    }

    /// <summary>
    /// Calculate content similarity (text content, ignoring structure)
    /// </summary>
    private static double CalculateContentSimilarity(string psHtml, string csHtml)
    {
        // Extract text content (remove HTML tags)
        string psText = Regex.Replace(psHtml, @"<[^>]+>", " ");
        string csText = Regex.Replace(csHtml, @"<[^>]+>", " ");

        // Normalize whitespace
        psText = Regex.Replace(psText, @"\s+", " ").Trim();
        csText = Regex.Replace(csText, @"\s+", " ").Trim();

        if (string.IsNullOrEmpty(psText) && string.IsNullOrEmpty(csText))
        {
            return 1.0;
        }

        if (string.IsNullOrEmpty(psText) || string.IsNullOrEmpty(csText))
        {
            return 0.0;
        }

        // Use Levenshtein distance for content similarity
        int maxLength = Math.Max(psText.Length, csText.Length);
        if (maxLength == 0)
        {
            return 1.0;
        }

        int distance = LevenshteinDistance(psText, csText);
        return 1.0 - ((double)distance / maxLength);
    }

    /// <summary>
    /// Calculate Mermaid diagram similarity
    /// </summary>
    private static double CalculateMermaidSimilarity(string psHtml, string csHtml)
    {
        var psMermaid = ExtractMermaidContent(psHtml);
        var csMermaid = ExtractMermaidContent(csHtml);

        if (psMermaid.Count == 0 && csMermaid.Count == 0)
        {
            return 1.0; // Both have no Mermaid (acceptable)
        }

        if (psMermaid.Count == 0 || csMermaid.Count == 0)
        {
            return 0.0; // One has Mermaid, other doesn't (show-stopper)
        }

        if (psMermaid.Count != csMermaid.Count)
        {
            return 0.5; // Different number of diagrams
        }

        // Compare each diagram
        double totalSimilarity = 0.0;
        for (int i = 0; i < Math.Min(psMermaid.Count, csMermaid.Count); i++)
        {
            string psDiagram = NormalizeMermaid(psMermaid[i]);
            string csDiagram = NormalizeMermaid(csMermaid[i]);

            if (psDiagram == csDiagram)
            {
                totalSimilarity += 1.0;
            }
            else
            {
                // Calculate similarity for diagram content
                int maxLength = Math.Max(psDiagram.Length, csDiagram.Length);
                if (maxLength > 0)
                {
                    int distance = LevenshteinDistance(psDiagram, csDiagram);
                    totalSimilarity += 1.0 - ((double)distance / maxLength);
                }
            }
        }

        return totalSimilarity / Math.Max(psMermaid.Count, csMermaid.Count);
    }

    /// <summary>
    /// Extract Mermaid diagram content from HTML
    /// </summary>
    private static List<string> ExtractMermaidContent(string html)
    {
        var diagrams = new List<string>();
        var pattern = @"<div[^>]*class=[""']mermaid[""'][^>]*>(.*?)</div>";
        var matches = Regex.Matches(html, pattern, RegexOptions.IgnoreCase | RegexOptions.Singleline);

        foreach (Match match in matches)
        {
            if (match.Groups.Count > 1)
            {
                string content = match.Groups[1].Value.Trim();
                if (!string.IsNullOrWhiteSpace(content) && !content.StartsWith("[") && !content.EndsWith("]"))
                {
                    diagrams.Add(content);
                }
            }
        }

        return diagrams;
    }

    /// <summary>
    /// Normalize Mermaid diagram content for comparison
    /// </summary>
    private static string NormalizeMermaid(string mermaid)
    {
        // Decode HTML entities
        mermaid = mermaid.Replace("&lt;", "<")
                        .Replace("&gt;", ">")
                        .Replace("&amp;", "&")
                        .Replace("&quot;", "\"")
                        .Replace("&#39;", "'");

        // Normalize whitespace
        mermaid = Regex.Replace(mermaid, @"\s+", " ").Trim();

        return mermaid;
    }

    /// <summary>
    /// Calculate Levenshtein distance between two strings
    /// </summary>
    private static int LevenshteinDistance(string s, string t)
    {
        if (string.IsNullOrEmpty(s))
        {
            return string.IsNullOrEmpty(t) ? 0 : t.Length;
        }

        if (string.IsNullOrEmpty(t))
        {
            return s.Length;
        }

        int n = s.Length;
        int m = t.Length;
        int[,] d = new int[n + 1, m + 1];

        for (int i = 0; i <= n; i++)
        {
            d[i, 0] = i;
        }

        for (int j = 0; j <= m; j++)
        {
            d[0, j] = j;
        }

        for (int i = 1; i <= n; i++)
        {
            for (int j = 1; j <= m; j++)
            {
                int cost = (t[j - 1] == s[i - 1]) ? 0 : 1;
                d[i, j] = Math.Min(
                    Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1),
                    d[i - 1, j - 1] + cost
                );
            }
        }

        return d[n, m];
    }
}

/// <summary>
/// Comparison result
/// </summary>
public class ComparisonResult
{
    public string PowershellPath { get; set; } = "";
    public string CsharpPath { get; set; } = "";
    public double Similarity { get; set; }
    public List<string> ShowStoppers { get; set; } = new List<string>();
    public List<string> AcceptableDifferences { get; set; } = new List<string>();
    public string Status { get; set; } = "";
}
