using System;
using System.Windows.Media;

namespace DbExplorer.Models
{
    /// <summary>
    /// ViewModel for displaying query history items in UI
    /// </summary>
    public class QueryHistoryViewModel
    {
        public string SqlStatement { get; set; } = string.Empty;
        public string SqlPreview { get; set; } = string.Empty;
        public string ConnectionName { get; set; } = string.Empty;
        public string ExecutedAt { get; set; } = string.Empty;
        public string ExecutionTime { get; set; } = string.Empty;
        public string StatusIcon { get; set; } = string.Empty;
        public string StatusText { get; set; } = string.Empty;
        public Brush StatusColor { get; set; } = Brushes.Gray;
        public string RowCountText { get; set; } = string.Empty;
        
        public Services.QueryHistoryItem OriginalItem { get; set; } = null!;

        /// <summary>
        /// Create ViewModel from QueryHistoryItem
        /// </summary>
        public static QueryHistoryViewModel FromHistoryItem(Services.QueryHistoryItem item, string decryptedSql)
        {
            // Create SQL preview (first 80 characters)
            var preview = decryptedSql.Length > 80 
                ? decryptedSql.Substring(0, 80) + "..." 
                : decryptedSql;
            
            // Replace newlines and multiple spaces for preview
            preview = preview.Replace("\r\n", " ").Replace("\n", " ").Replace("\t", " ");
            while (preview.Contains("  "))
            {
                preview = preview.Replace("  ", " ");
            }

            // Format execution time
            var execTime = item.ExecutionTimeMs < 1000 
                ? $"{item.ExecutionTimeMs:F0}ms" 
                : $"{(item.ExecutionTimeMs / 1000):F2}s";

            // Status icon and color
            var statusIcon = item.Success ? "✓" : "✗";
            var statusText = item.Success ? "Success" : "Failed";
            var statusColor = item.Success 
                ? new SolidColorBrush(Color.FromRgb(0, 200, 0))  // Green
                : new SolidColorBrush(Color.FromRgb(255, 80, 80)); // Red

            // Row count text
            var rowCountText = item.RowCount.HasValue 
                ? $"• {item.RowCount.Value:N0} rows" 
                : string.Empty;

            // Format date/time
            var executedAt = item.ExecutedAt.ToString("yyyy-MM-dd HH:mm:ss");

            return new QueryHistoryViewModel
            {
                SqlStatement = decryptedSql,
                SqlPreview = preview,
                ConnectionName = item.ConnectionName,
                ExecutedAt = executedAt,
                ExecutionTime = execTime,
                StatusIcon = statusIcon,
                StatusText = statusText,
                StatusColor = statusColor,
                RowCountText = rowCountText,
                OriginalItem = item
            };
        }
    }
}

