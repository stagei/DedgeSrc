using System.Text.Json.Nodes;

namespace SystemAnalyzer2.Batch.Services.Discovery;

/// <summary>Collects REST-style hints from merged <c>dependency_master</c> programs (e.g. PowerShell <c>restCalls</c>, C# routes when present).</summary>
public static class RestApiDiscovery
{
    public static JsonObject BuildRestApiMap(JsonObject master)
    {
        var exposed = new JsonArray();
        var consumed = new JsonArray();
        foreach (var p in master["programs"]?.AsArray() ?? [])
        {
            var tech = p?["technology"]?.GetValue<string>() ?? "cobol";
            var prog = p?["program"]?.GetValue<string>() ?? "";
            foreach (var c in p?["restCalls"]?.AsArray() ?? [])
            {
                consumed.Add(new JsonObject
                {
                    ["technology"] = tech,
                    ["program"] = prog,
                    ["uri"] = c?["uri"]?.GetValue<string>() ?? ""
                });
            }

            foreach (var x in p?["restEndpoints"]?.AsArray() ?? [])
            {
                var route = x?["route"]?.GetValue<string>()
                    ?? x?["path"]?.GetValue<string>()
                    ?? x?["template"]?.GetValue<string>()
                    ?? "";
                var eo = new JsonObject
                {
                    ["technology"] = tech,
                    ["program"] = prog,
                    ["route"] = route,
                    ["method"] = x?["httpMethod"]?.GetValue<string>()
                        ?? x?["method"]?.GetValue<string>()
                        ?? "GET"
                };
                if (x?["port"] != null && int.TryParse(x["port"]?.ToString(), out var portNum))
                    eo["port"] = portNum;
                exposed.Add(eo);
            }
        }

        var matches = new JsonArray();
        foreach (var cNode in consumed)
        {
            var c = cNode as JsonObject;
            if (c == null) continue;
            var uri = c["uri"]?.GetValue<string>() ?? "";
            var cKey = NormalizeRestKey(uri);
            if (string.IsNullOrEmpty(cKey)) continue;
            foreach (var eNode in exposed)
            {
                var e = eNode as JsonObject;
                if (e == null) continue;
                var route = e["route"]?.GetValue<string>() ?? "";
                var eKey = NormalizeRestKey(route);
                if (string.IsNullOrEmpty(eKey)) continue;
                if (!string.Equals(cKey, eKey, StringComparison.OrdinalIgnoreCase)
                    && !cKey.EndsWith(eKey, StringComparison.OrdinalIgnoreCase)
                    && !eKey.EndsWith(cKey, StringComparison.OrdinalIgnoreCase))
                    continue;
                matches.Add(new JsonObject
                {
                    ["kind"] = "path-match",
                    ["consumerTechnology"] = c["technology"]?.DeepClone(),
                    ["consumerProgram"] = c["program"]?.DeepClone(),
                    ["consumerUri"] = c["uri"]?.DeepClone(),
                    ["exposedTechnology"] = e["technology"]?.DeepClone(),
                    ["exposedProgram"] = e["program"]?.DeepClone(),
                    ["exposedRoute"] = e["route"]?.DeepClone()
                });
            }
        }

        return new JsonObject
        {
            ["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            ["consumed"] = consumed,
            ["exposed"] = exposed,
            ["matches"] = matches
        };
    }

    /// <summary>Comparable path fragment for loose matching between full URIs and route templates.</summary>
    private static string NormalizeRestKey(string? uriOrRoute)
    {
        if (string.IsNullOrWhiteSpace(uriOrRoute)) return "";
        var s = uriOrRoute.Trim();
        if (Uri.TryCreate(s, UriKind.Absolute, out var abs))
        {
            var path = abs.AbsolutePath.TrimEnd('/');
            return string.IsNullOrEmpty(path) ? "/" : path;
        }

        var q = s.IndexOf('?', StringComparison.Ordinal);
        if (q >= 0) s = s[..q];
        s = s.Trim();
        if (!s.StartsWith('/')) s = "/" + s;
        return s.TrimEnd('/');
    }
}
