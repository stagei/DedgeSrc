using System.Text.Json.Nodes;

namespace SystemAnalyzer2.Core.Models;

public record TechSectionConfig(
    string TechnologyId,
    string Vendor,
    string Product,
    string Version,
    string Platform);

public record TechAnalysisRequest(
    string Alias,
    string RunDir,
    JsonObject AllJson,
    IReadOnlyList<JsonObject> Entries,
    SystemAnalyzerOptions Options,
    TechSectionConfig TechConfig);

public record TechAnalysisResult(
    string TechnologyId,
    string VendorId,
    string ProductId,
    int ProgramCount,
    int SqlTableCount,
    int CallTargetCount,
    List<JsonObject> Programs);
