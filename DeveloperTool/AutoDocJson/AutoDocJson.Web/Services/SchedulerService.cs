using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AutoDocJson.Web.Services;

public class SchedulerService
{
    private const string TaskName = @"\DevTools\AutoDocJsonBatchRunner";
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public ScheduledTaskStatus GetStatus()
    {
        try
        {
            var (exitCode, output) = RunSchtasks($"/Query /TN \"{TaskName}\" /FO CSV /V");
            if (exitCode != 0)
                return new ScheduledTaskStatus { Exists = false, Error = output.Trim() };

            return ParseCsvStatus(output);
        }
        catch (Exception ex)
        {
            return new ScheduledTaskStatus { Exists = false, Error = ex.Message };
        }
    }

    public SchedulerActionResult RunNow()
    {
        var (exitCode, output) = RunSchtasks($"/Run /TN \"{TaskName}\"");
        return new SchedulerActionResult
        {
            Success = exitCode == 0,
            Message = output.Trim()
        };
    }

    public SchedulerActionResult Stop()
    {
        var (exitCode, output) = RunSchtasks($"/End /TN \"{TaskName}\"");
        return new SchedulerActionResult
        {
            Success = exitCode == 0,
            Message = output.Trim()
        };
    }

    public SchedulerActionResult Enable()
    {
        var (exitCode, output) = RunSchtasks($"/Change /TN \"{TaskName}\" /ENABLE");
        return new SchedulerActionResult
        {
            Success = exitCode == 0,
            Message = output.Trim()
        };
    }

    public SchedulerActionResult Disable()
    {
        var (exitCode, output) = RunSchtasks($"/Change /TN \"{TaskName}\" /DISABLE");
        return new SchedulerActionResult
        {
            Success = exitCode == 0,
            Message = output.Trim()
        };
    }

    public SchedulerActionResult RegenerateAll(string dataFolder)
    {
        try
        {
            Directory.CreateDirectory(dataFolder);
            string triggerFile = Path.Combine(dataFolder, "regenerate-all.trigger");
            File.WriteAllText(triggerFile, $"Requested at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        }
        catch (Exception ex)
        {
            return new SchedulerActionResult { Success = false, Message = "Failed to create trigger file: " + ex.Message };
        }

        return RunNow();
    }

    private static (int exitCode, string output) RunSchtasks(string arguments)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = "schtasks.exe",
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        process.Start();
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        process.WaitForExit(10_000);

        string output = string.IsNullOrWhiteSpace(stderr) ? stdout : $"{stdout}\n{stderr}";
        return (process.ExitCode, output);
    }

    private static ScheduledTaskStatus ParseCsvStatus(string csvOutput)
    {
        var lines = csvOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length < 2)
            return new ScheduledTaskStatus { Exists = false, Error = "Unexpected schtasks output" };

        var headers = ParseCsvLine(lines[0]);
        var values = ParseCsvLine(lines[1]);

        string Get(string header) =>
            headers.IndexOf(header) is int i and >= 0 && i < values.Count ? values[i] : "";

        var status = new ScheduledTaskStatus
        {
            Exists = true,
            TaskName = Get("TaskName"),
            Status = Get("Status"),
            LastRunTime = Get("Last Run Time"),
            LastResult = Get("Last Result"),
            NextRunTime = Get("Next Run Time"),
            ScheduleType = Get("Schedule Type"),
            State = Get("Scheduled Task State")
        };

        status.IsRunning = status.Status?.Equals("Running", StringComparison.OrdinalIgnoreCase) == true;
        status.IsEnabled = status.State?.Equals("Enabled", StringComparison.OrdinalIgnoreCase) == true;

        return status;
    }

    private static List<string> ParseCsvLine(string line)
    {
        var fields = new List<string>();
        bool inQuotes = false;
        var current = new System.Text.StringBuilder();

        foreach (char c in line.Trim())
        {
            if (c == '"')
            {
                inQuotes = !inQuotes;
            }
            else if (c == ',' && !inQuotes)
            {
                fields.Add(current.ToString());
                current.Clear();
            }
            else
            {
                current.Append(c);
            }
        }
        fields.Add(current.ToString());
        return fields;
    }
}

public class ScheduledTaskStatus
{
    public bool Exists { get; set; }
    public string? TaskName { get; set; }
    public string? Status { get; set; }
    public bool IsRunning { get; set; }
    public bool IsEnabled { get; set; }
    public string? State { get; set; }
    public string? LastRunTime { get; set; }
    public string? LastResult { get; set; }
    public string? NextRunTime { get; set; }
    public string? ScheduleType { get; set; }
    public string? Error { get; set; }
}

public class SchedulerActionResult
{
    public bool Success { get; set; }
    public string? Message { get; set; }
}
