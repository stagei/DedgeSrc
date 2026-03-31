using System.Text.RegularExpressions;

namespace AutoDocNew.Web.Helpers;

/// <summary>
/// Counts unique Mermaid flowchart node IDs (not edges) and recommends
/// a renderer based on node count vs threshold.
/// </summary>
public static class MermaidNodeCounter
{
    private static readonly Regex EdgeArrowPattern = new(
        @"(-->|==>|-\.->|---->|====>|-\.\.->)", RegexOptions.Compiled);

    private static readonly Regex NodeIdPattern = new(
        @"^([\w.\-:]+)", RegexOptions.Compiled);

    private static readonly HashSet<string> SkipPrefixes = new(StringComparer.OrdinalIgnoreCase)
    {
        "flowchart", "graph", "subgraph", "end", "classDef", "class", "style",
        "click", "participant", "linkStyle", "%%", "erDiagram", "sequenceDiagram",
        "classDiagram", "direction"
    };

    /// <summary>
    /// Count unique node IDs in a Mermaid flowchart/graph text.
    /// Only counts node identifiers, not edges or directives.
    /// </summary>
    public static int CountNodes(string? mermaidText)
    {
        if (string.IsNullOrWhiteSpace(mermaidText))
            return 0;

        var nodeIds = new HashSet<string>(StringComparer.Ordinal);

        foreach (var rawLine in mermaidText.Split('\n'))
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line))
                continue;

            if (ShouldSkipLine(line))
                continue;

            if (EdgeArrowPattern.IsMatch(line))
            {
                ExtractEdgeNodeIds(line, nodeIds);
            }
            else
            {
                var m = NodeIdPattern.Match(line);
                if (m.Success)
                    nodeIds.Add(m.Groups[1].Value);
            }
        }

        return nodeIds.Count;
    }

    /// <summary>
    /// Recommend "gojs" or "mermaid" based on node count and threshold.
    /// Sequence diagrams always return "mermaid" (GoJS cannot render them).
    /// </summary>
    public static string RecommendRenderer(string? mermaidText, int maxNodes, string defaultRenderer)
    {
        if (string.IsNullOrWhiteSpace(mermaidText))
            return defaultRenderer;

        if (mermaidText.TrimStart().StartsWith("sequenceDiagram", StringComparison.Ordinal))
            return "mermaid";

        int count = CountNodes(mermaidText);
        if (count > maxNodes)
            return "gojs";

        return defaultRenderer;
    }

    private static bool ShouldSkipLine(string line)
    {
        foreach (var prefix in SkipPrefixes)
        {
            if (line.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    /// <summary>
    /// Extract from-ID and to-ID from an edge line like "A --> B" or "A -->|label| B".
    /// Strips shape brackets from the to-side so only the raw ID is captured.
    /// </summary>
    private static void ExtractEdgeNodeIds(string line, HashSet<string> nodeIds)
    {
        var parts = EdgeArrowPattern.Split(line, 2);
        if (parts.Length < 2) return;

        var leftPart = parts[0].Trim();
        var rightPart = parts[^1].Trim();

        var fromMatch = NodeIdPattern.Match(leftPart);
        if (fromMatch.Success)
            nodeIds.Add(fromMatch.Groups[1].Value);

        // Right side may have "|label| nodeId[shape]" — strip pipe labels first
        rightPart = Regex.Replace(rightPart, @"^\|[^|]*\|\s*", "");
        var toMatch = NodeIdPattern.Match(rightPart);
        if (toMatch.Success)
            nodeIds.Add(toMatch.Groups[1].Value);
    }
}
