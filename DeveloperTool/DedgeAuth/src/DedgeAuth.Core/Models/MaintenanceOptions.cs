namespace DedgeAuth.Core.Models;

public class MaintenanceOptions
{
    public int VisitRetentionDays { get; set; } = 30;
    public int CleanupIntervalHours { get; set; } = 24;
}
