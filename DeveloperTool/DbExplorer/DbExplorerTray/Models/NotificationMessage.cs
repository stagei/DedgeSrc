using System.Text.Json.Serialization;

namespace DbExplorerTray.Models;

/// <summary>
/// Notification message model for JSON files
/// </summary>
public class NotificationMessage
{
    /// <summary>
    /// Unique message identifier
    /// </summary>
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>
    /// Icon type: Info, Warning, Error, Success
    /// </summary>
    [JsonPropertyName("icon")]
    public string Icon { get; set; } = "Info";

    /// <summary>
    /// Notification title
    /// </summary>
    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    /// <summary>
    /// Notification message text
    /// </summary>
    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Timeout in milliseconds (default: 5000)
    /// </summary>
    [JsonPropertyName("timeout")]
    public int Timeout { get; set; } = 5000;

    /// <summary>
    /// Optional action command
    /// </summary>
    [JsonPropertyName("action")]
    public string? Action { get; set; }
}
