using System.Text.Json;

namespace MouseJiggler;

public class DailyActivity
{
    public DateTime Date { get; set; }
    public DateTime FirstActivity { get; set; }
    public DateTime LastActivity { get; set; }
    public List<(DateTime Start, DateTime End)> ActivePeriods { get; set; } = new();
}

public class ActivityLogger
{
    private const int INACTIVITY_THRESHOLD_MINUTES = 15;
    private readonly string _baseDir;
    private DateTime _lastActivity;
    private DateTime? _currentPeriodStart;
    private DailyActivity? _currentDay;

    public ActivityLogger()
    {
        _baseDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MouseJiggler",
            "ActivityLogs"
        );
        Directory.CreateDirectory(_baseDir);
    }

    public void LogActivity()
    {
        var now = DateTime.Now;
        var today = now.Date;

        if (_currentDay == null || _currentDay.Date != today)
        {
            SaveCurrentDay();
            _currentDay = LoadOrCreateDay(today);
            _currentPeriodStart = now;
        }

        if (_currentDay.FirstActivity == DateTime.MinValue || now.Hour >= 4 && _currentDay.FirstActivity.Hour < 4)
        {
            _currentDay.FirstActivity = now;
        }

        if ((now - _lastActivity).TotalMinutes > INACTIVITY_THRESHOLD_MINUTES && _currentPeriodStart.HasValue)
        {
            _currentDay.ActivePeriods.Add((_currentPeriodStart.Value, _lastActivity));
            _currentPeriodStart = now;
        }

        _currentDay.LastActivity = now;
        _lastActivity = now;
    }

    private void SaveCurrentDay()
    {
        if (_currentDay == null) return;
        if (_currentPeriodStart.HasValue)
        {
            _currentDay.ActivePeriods.Add((_currentPeriodStart.Value, _lastActivity));
        }
        
        var filePath = GetDayFilePath(_currentDay.Date);
        File.WriteAllText(filePath, JsonSerializer.Serialize(_currentDay));
    }

    private DailyActivity LoadOrCreateDay(DateTime date)
    {
        var filePath = GetDayFilePath(date);
        if (File.Exists(filePath))
        {
            return JsonSerializer.Deserialize<DailyActivity>(File.ReadAllText(filePath)) ?? new DailyActivity { Date = date };
        }
        return new DailyActivity { Date = date };
    }

    private string GetDayFilePath(DateTime date) =>
        Path.Combine(_baseDir, $"activity_{date:yyyy-MM-dd}.json");
}
