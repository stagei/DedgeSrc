using System.Text.Json.Nodes;

namespace SystemAnalyzer2.Batch.Services.Discovery;

/// <summary>Cross-technology links (shared SQL tables, REST URIs) appended to the master document.</summary>
public static class CrossTechLinker
{
    private static string RestPathKey(string uri)
    {
        if (Uri.TryCreate(uri, UriKind.Absolute, out var a))
            return a.AbsolutePath.TrimEnd('/');
        var s = uri.Trim();
        var q = s.IndexOf('?', StringComparison.Ordinal);
        if (q >= 0) s = s[..q];
        return s.Trim().TrimEnd('/');
    }

    public static void Apply(JsonObject master)
    {
        var links = new JsonArray();
        var tableUsers = new Dictionary<string, List<(string tech, string prog)>>(StringComparer.OrdinalIgnoreCase);

        foreach (var p in master["programs"]?.AsArray() ?? [])
        {
            var prog = p?["program"]?.GetValue<string>() ?? "";
            var tech = p?["technology"]?.GetValue<string>() ?? "cobol";
            foreach (var s in p?["sqlOperations"]?.AsArray() ?? [])
            {
                var schema = s?["schema"]?.GetValue<string>() ?? "";
                var table = s?["tableName"]?.GetValue<string>() ?? "";
                if (string.IsNullOrEmpty(table)) continue;
                var key = string.IsNullOrEmpty(schema) ? table : $"{schema}.{table}";
                if (!tableUsers.TryGetValue(key, out var list))
                {
                    list = [];
                    tableUsers[key] = list;
                }

                list.Add((tech, prog));
            }
        }

        foreach (var kv in tableUsers.Where(k => k.Value.Select(v => v.tech).Distinct().Count() > 1))
        {
            var arr = new JsonArray();
            foreach (var v in kv.Value)
                arr.Add(new JsonObject { ["technology"] = v.tech, ["program"] = v.prog });
            links.Add(new JsonObject
            {
                ["kind"] = "sql-table",
                ["table"] = kv.Key,
                ["programs"] = arr
            });
        }

        var restByPath = new Dictionary<string, List<(string tech, string prog, string raw)>>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in master["programs"]?.AsArray() ?? [])
        {
            var prog = p?["program"]?.GetValue<string>() ?? "";
            var tech = p?["technology"]?.GetValue<string>() ?? "cobol";
            foreach (var c in p?["restCalls"]?.AsArray() ?? [])
            {
                var uri = c?["uri"]?.GetValue<string>() ?? "";
                if (string.IsNullOrEmpty(uri)) continue;
                var key = RestPathKey(uri);
                if (string.IsNullOrEmpty(key)) continue;
                if (!restByPath.TryGetValue(key, out var list))
                {
                    list = [];
                    restByPath[key] = list;
                }

                list.Add((tech, prog, uri));
            }
        }

        foreach (var kv in restByPath.Where(k => k.Value.Select(v => v.tech).Distinct().Count() > 1))
        {
            var arr = new JsonArray();
            foreach (var v in kv.Value)
                arr.Add(new JsonObject { ["technology"] = v.tech, ["program"] = v.prog, ["uri"] = v.raw });
            links.Add(new JsonObject
            {
                ["kind"] = "rest-uri",
                ["pathKey"] = kv.Key,
                ["programs"] = arr
            });
        }

        master["crossTechLinks"] = links;
    }
}
