namespace ServerMonitorDashboard.Models;

/// <summary>
/// Model for entries in ComputerInfo.json
/// </summary>
public class ComputerInfo
{
    public string? Name { get; set; }
    public string? DisplayName { get; set; }
    public string? Type { get; set; }
    public string? IpAddress { get; set; }
    public string? Description { get; set; }
    public string? Environment { get; set; }
    public string? Location { get; set; }
    public string? Platform { get; set; }
    public string? Purpose { get; set; }
    public List<string>? Environments { get; set; }
    public List<string>? Applications { get; set; }
    
    /// <summary>
    /// IsActive field from ComputerInfo.json - indicates if the server is active
    /// </summary>
    public bool IsActive { get; set; }
}
