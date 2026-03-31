using System.Text.RegularExpressions;

namespace SqlMmdConverter.Tests.Utilities;

/// <summary>
/// Utility for comparing Mermaid ERD diagrams semantically.
/// </summary>
public static class MermaidDiagramComparer
{
    /// <summary>
    /// Compares two Mermaid ERD diagrams for semantic equivalence.
    /// </summary>
    public static SchemaComparisonResult Compare(string expectedMermaid, string actualMermaid)
    {
        var result = new SchemaComparisonResult();
        
        // Normalize both diagrams
        var normalizedExpected = NormalizeMermaid(expectedMermaid);
        var normalizedActual = NormalizeMermaid(actualMermaid);
        
        // Extract entities
        var expectedEntities = ExtractEntities(normalizedExpected);
        var actualEntities = ExtractEntities(normalizedActual);
        
        // Compare entity count
        if (expectedEntities.Count != actualEntities.Count)
        {
            result.Differences.Add($"Entity count mismatch: expected {expectedEntities.Count}, got {actualEntities.Count}");
        }
        
        // Compare each entity
        foreach (var expectedEntity in expectedEntities)
        {
            if (!actualEntities.ContainsKey(expectedEntity.Key))
            {
                result.Differences.Add($"Missing entity: {expectedEntity.Key}");
                continue;
            }
            
            var actualEntity = actualEntities[expectedEntity.Key];
            CompareEntityDefinitions(expectedEntity.Key, expectedEntity.Value, actualEntity, result);
        }
        
        // Check for extra entities
        foreach (var actualEntity in actualEntities)
        {
            if (!expectedEntities.ContainsKey(actualEntity.Key))
            {
                result.Differences.Add($"Extra entity: {actualEntity.Key}");
            }
        }
        
        // Compare relationships
        var expectedRelationships = ExtractRelationships(normalizedExpected);
        var actualRelationships = ExtractRelationships(normalizedActual);
        
        CompareRelationships(expectedRelationships, actualRelationships, result);
        
        // Calculate similarity score
        result.SimilarityScore = CalculateSimilarity(result.Differences.Count);
        result.IsMatch = result.Differences.Count == 0;
        
        return result;
    }
    
    private static string NormalizeMermaid(string mermaid)
    {
        if (string.IsNullOrWhiteSpace(mermaid))
            return string.Empty;
        
        // Remove comments
        mermaid = Regex.Replace(mermaid, @"%%[^\n]*", "");
        
        // Normalize whitespace
        mermaid = Regex.Replace(mermaid, @"\s+", " ");
        
        // Remove erDiagram declaration (keep content only)
        mermaid = Regex.Replace(mermaid, @"erDiagram\s*", "", RegexOptions.IgnoreCase);
        
        return mermaid.Trim();
    }
    
    private static Dictionary<string, List<string>> ExtractEntities(string mermaid)
    {
        var entities = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        
        // Match entity definitions: ENTITY_NAME { ... }
        var pattern = @"(\w+)\s*\{([^}]*)\}";
        var matches = Regex.Matches(mermaid, pattern, RegexOptions.Singleline);
        
        foreach (Match match in matches)
        {
            var entityName = match.Groups[1].Value.Trim();
            var attributesText = match.Groups[2].Value;
            
            var attributes = ParseAttributes(attributesText);
            entities[entityName] = attributes;
        }
        
        return entities;
    }
    
    private static List<string> ParseAttributes(string attributesText)
    {
        var attributes = new List<string>();
        
        // Split by newlines or semicolons
        var lines = attributesText.Split(new[] { '\n', ';' }, StringSplitOptions.RemoveEmptyEntries);
        
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (!string.IsNullOrWhiteSpace(trimmed))
            {
                // Normalize attribute format: type name constraint
                trimmed = Regex.Replace(trimmed, @"\s+", " ");
                attributes.Add(trimmed);
            }
        }
        
        return attributes;
    }
    
    private static List<string> ExtractRelationships(string mermaid)
    {
        var relationships = new List<string>();
        
        // Match relationship patterns: ENTITY1 ||--o{ ENTITY2 : label
        var pattern = @"(\w+)\s+([\|\}o][o\|\{]--[o\|\{][\|\}o][o\|\{])\s+(\w+)\s*:\s*(\w+)";
        var matches = Regex.Matches(mermaid, pattern);
        
        foreach (Match match in matches)
        {
            var entity1 = match.Groups[1].Value;
            var cardinality = match.Groups[2].Value;
            var entity2 = match.Groups[3].Value;
            var label = match.Groups[4].Value;
            
            // Normalize relationship representation
            var rel = $"{entity1} {cardinality} {entity2} : {label}";
            relationships.Add(rel);
        }
        
        return relationships;
    }
    
    private static void CompareEntityDefinitions(
        string entityName,
        List<string> expectedAttributes,
        List<string> actualAttributes,
        SchemaComparisonResult result)
    {
        // Compare attribute count
        if (expectedAttributes.Count != actualAttributes.Count)
        {
            result.Differences.Add(
                $"Entity '{entityName}': attribute count mismatch (expected {expectedAttributes.Count}, got {actualAttributes.Count})");
        }
        
        // Compare each attribute
        foreach (var expectedAttr in expectedAttributes)
        {
            if (!actualAttributes.Any(a => AttributesMatch(expectedAttr, a)))
            {
                result.Differences.Add($"Entity '{entityName}': missing or different attribute '{expectedAttr}'");
            }
        }
        
        // Check for extra attributes
        foreach (var actualAttr in actualAttributes)
        {
            if (!expectedAttributes.Any(a => AttributesMatch(a, actualAttr)))
            {
                result.Differences.Add($"Entity '{entityName}': extra attribute '{actualAttr}'");
            }
        }
    }
    
    private static bool AttributesMatch(string attr1, string attr2)
    {
        // Case-insensitive comparison
        if (string.Equals(attr1, attr2, StringComparison.OrdinalIgnoreCase))
            return true;
        
        // Compare attribute name (first word after type)
        var parts1 = attr1.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var parts2 = attr2.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        
        if (parts1.Length >= 2 && parts2.Length >= 2)
        {
            // Compare type and name
            return string.Equals(parts1[0], parts2[0], StringComparison.OrdinalIgnoreCase) &&
                   string.Equals(parts1[1], parts2[1], StringComparison.OrdinalIgnoreCase);
        }
        
        return false;
    }
    
    private static void CompareRelationships(
        List<string> expectedRelationships,
        List<string> actualRelationships,
        SchemaComparisonResult result)
    {
        if (expectedRelationships.Count != actualRelationships.Count)
        {
            result.Differences.Add(
                $"Relationship count mismatch: expected {expectedRelationships.Count}, got {actualRelationships.Count}");
        }
        
        foreach (var expectedRel in expectedRelationships)
        {
            if (!actualRelationships.Contains(expectedRel, StringComparer.OrdinalIgnoreCase))
            {
                result.Differences.Add($"Missing or different relationship: {expectedRel}");
            }
        }
        
        foreach (var actualRel in actualRelationships)
        {
            if (!expectedRelationships.Contains(actualRel, StringComparer.OrdinalIgnoreCase))
            {
                result.Differences.Add($"Extra relationship: {actualRel}");
            }
        }
    }
    
    private static double CalculateSimilarity(int differenceCount)
    {
        if (differenceCount == 0)
            return 1.0;
        
        // Each difference reduces similarity by 10%
        var penalty = differenceCount * 0.1;
        return Math.Max(0.0, 1.0 - penalty);
    }
}

