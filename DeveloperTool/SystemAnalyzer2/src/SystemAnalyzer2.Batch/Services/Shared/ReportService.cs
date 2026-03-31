using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using NLog;

namespace SystemAnalyzer2.Batch.Services.Shared;

public sealed class ReportService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public static JsonNode? GetJsonFileContent(string path)
    {
        if (!File.Exists(path)) return null;
        try
        {
            var text = File.ReadAllText(path, Encoding.UTF8);
            return JsonNode.Parse(text);
        }
        catch { return null; }
    }

    public string WriteRunSummaryMarkdown(string runDir, string? outputPath = null)
    {
        if (!Directory.Exists(runDir))
            throw new DirectoryNotFoundException($"Run directory not found: {runDir}");

        outputPath ??= Path.Combine(runDir, "run_summary.md");

        var master = GetJsonFileContent(Path.Combine(runDir, "dependency_master.json"));
        var progs = GetJsonFileContent(Path.Combine(runDir, "all_total_programs.json"));
        var sql = GetJsonFileContent(Path.Combine(runDir, "all_sql_tables.json"));
        var copy = GetJsonFileContent(Path.Combine(runDir, "all_copy_elements.json"));
        var call = GetJsonFileContent(Path.Combine(runDir, "all_call_graph.json"));
        var fio = GetJsonFileContent(Path.Combine(runDir, "all_file_io.json"));
        var verify = GetJsonFileContent(Path.Combine(runDir, "source_verification.json"));
        var db2 = GetJsonFileContent(Path.Combine(runDir, "db2_table_validation.json"));
        var excl = GetJsonFileContent(Path.Combine(runDir, "applied_exclusions.json"));
        var classNode = GetJsonFileContent(Path.Combine(runDir, "classified_programs.json"));

        var sb = new StringBuilder();
        var generated = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");

        sb.AppendLine("# Pipeline Run Summary");
        sb.AppendLine();
        sb.AppendLine($"Generated: {generated}");
        sb.AppendLine($"Run folder: `{runDir}`");
        if (master?["database"] != null)
            sb.AppendLine($"Database: **{master["database"]}** (alias: {master["db2Alias"]})");
        sb.AppendLine();

        sb.AppendLine("## Main Statistics");
        sb.AppendLine();
        sb.AppendLine("| Metric | Value |");
        sb.AppendLine("|---|---:|");
        if (master != null) sb.AppendLine($"| Programs in dependency master | {master["totalPrograms"]} |");
        if (progs != null) sb.AppendLine($"| Total programs (all included) | {progs["totalPrograms"]} |");
        if (sql != null) sb.AppendLine($"| SQL references | {sql["totalReferences"]} |");
        if (sql != null) sb.AppendLine($"| Unique SQL tables | {sql["uniqueTables"]} |");
        if (copy != null) sb.AppendLine($"| Unique COPY elements | {copy["totalCopyElements"]} |");
        if (call != null) sb.AppendLine($"| Call graph edges | {call["totalEdges"]} |");
        if (fio != null) sb.AppendLine($"| File I/O references | {fio["totalFileReferences"]} |");
        if (fio != null) sb.AppendLine($"| Unique files | {fio["uniqueFiles"]} |");
        sb.AppendLine();

        File.WriteAllText(outputPath, sb.ToString(), Encoding.UTF8);
        return outputPath;
    }
}
