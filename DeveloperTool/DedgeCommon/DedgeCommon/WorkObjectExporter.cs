using System.IO;
using System.Text;

namespace DedgeCommon
{
    /// <summary>
    /// Provides export functionality for WorkObject instances to JSON and HTML formats.
    /// Supports publishing to DevTools web paths for public access.
    /// </summary>
    /// <remarks>
    /// Mimics PowerShell functions:
    /// - Export-WorkObjectToJsonFile
    /// - Export-WorkObjectToHtmlFile
    /// - Save-HtmlOutput
    /// 
    /// Features:
    /// - Export to JSON with configurable formatting
    /// - Export to HTML using shared templates
    /// - Automatic directory creation
    /// - Optional publishing to web paths
    /// - Browser auto-open support
    /// </remarks>
    public class WorkObjectExporter
    {
        private readonly HtmlTemplateService _templateService;

        public WorkObjectExporter()
        {
            _templateService = new HtmlTemplateService();
        }

        /// <summary>
        /// Exports WorkObject to JSON file.
        /// </summary>
        /// <param name="workObject">WorkObject to export</param>
        /// <param name="filePath">Output file path</param>
        /// <param name="indented">Whether to format JSON with indentation (default: true)</param>
        public void ExportToJson(WorkObject workObject, string filePath, bool indented = true)
        {
            DedgeNLog.Info($"Exporting WorkObject to JSON file: {filePath}");

            try
            {
                // Ensure directory exists
                string? directory = Path.GetDirectoryName(filePath);
                if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                // Export to JSON
                string json = workObject.ToJson(indented);
                File.WriteAllText(filePath, json, Encoding.UTF8);

                DedgeNLog.Info($"WorkObject exported to JSON: {filePath}");
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to export WorkObject to JSON: {filePath}");
                throw;
            }
        }

        /// <summary>
        /// Exports WorkObject to HTML file using template.
        /// </summary>
        /// <param name="workObject">WorkObject to export</param>
        /// <param name="filePath">Output file path</param>
        /// <param name="title">HTML page title</param>
        /// <param name="additionalStyle">Optional additional CSS</param>
        /// <param name="addToDevToolsWebPath">Whether to also publish to DevTools web path</param>
        /// <param name="devToolsWebDirectory">Subdirectory under DevTools web path</param>
        /// <param name="autoOpen">Whether to open in browser after export</param>
        public void ExportToHtml(
            WorkObject workObject,
            string filePath,
            string title = "Work Object Report",
            string? additionalStyle = null,
            bool addToDevToolsWebPath = false,
            string? devToolsWebDirectory = null,
            bool autoOpen = false)
        {
            DedgeNLog.Info($"Exporting WorkObject to HTML file: {filePath}");

            try
            {
                // Generate HTML content from WorkObject
                string content = GenerateHtmlContent(workObject);

                // Get HTML template with content
                string html = _templateService.GetHtmlPage(title, content, additionalStyle);

                // Ensure directory exists
                string? directory = Path.GetDirectoryName(filePath);
                if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                // Write to local file
                File.WriteAllText(filePath, html, Encoding.UTF8);
                DedgeNLog.Info($"Local HTML saved to: {filePath}");

                string fileToOpen = filePath;

                // Optionally publish to DevTools web path
                if (addToDevToolsWebPath)
                {
                    try
                    {
                        string devToolsWebPath;
                        string devToolsWebUrl;
                        string devToolsWebContentPath;
                        
                        // Try to get DevTools paths (may fail if GlobalSettings not accessible)
                        try
                        {
                            devToolsWebPath = GlobalFunctions.GetDevToolsWebPath();
                            devToolsWebUrl = GlobalFunctions.GetDevToolsWebPathUrl();
                            devToolsWebContentPath = GlobalFunctions.GetDevToolsWebContent();
                        }
                        catch (Exception ex)
                        {
                            DedgeNLog.Warn(ex, "Could not access GlobalSettings for web publishing - skipping web publish");
                            DedgeNLog.Info("HTML report saved locally only (web publishing unavailable)");
                            return; // Skip web publishing, but local file is already saved
                        }
                        
                        // Combine DevToolsWebContent with subdirectory (handle null/empty)
                        string webDirectory = string.IsNullOrEmpty(devToolsWebDirectory)
                            ? devToolsWebContentPath
                            : Path.Combine(devToolsWebContentPath, devToolsWebDirectory);

                        if (!Directory.Exists(webDirectory))
                        {
                            Directory.CreateDirectory(webDirectory);
                        }

                        string webFileName = Path.GetFileNameWithoutExtension(filePath) + ".html";
                        string webFilePath = Path.Combine(webDirectory, webFileName);
                        
                        File.WriteAllText(webFilePath, html, Encoding.UTF8);
                        DedgeNLog.Info($"Remote HTML saved to DevTools web path: {webFilePath}");

                        // // Construct web URL
                        // string relativeUrl = string.IsNullOrEmpty(devToolsWebDirectory)
                        //     ? webFileName
                        //     : $"{devToolsWebDirectory.Trim('\\')}\\{webFileName}".Replace('\\', '/');
                        
                        // fileToOpen = $"{devToolsWebUrl}/{relativeUrl}".Replace(" ", "%20");
                        // DedgeNLog.Info($"Web URL: {fileToOpen}");
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Warn(ex, "Failed to publish to DevTools web path");
                    }
                }

                // Auto-open in browser if requested
                if (autoOpen && !string.IsNullOrEmpty(fileToOpen))
                {
                    try
                    {
                        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                        {
                            FileName = fileToOpen,
                            UseShellExecute = true
                        });
                        DedgeNLog.Info($"Opened in browser: {fileToOpen}");
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Warn(ex, $"Failed to open in browser: {fileToOpen}");
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to export WorkObject to HTML: {filePath}");
                throw;
            }
        }

        /// <summary>
        /// Generates HTML content from WorkObject properties and ScriptArray with tabbed interface.
        /// </summary>
        private string GenerateHtmlContent(WorkObject workObject)
        {
            var sb = new StringBuilder();

            // Add timestamp
            sb.AppendLine($"<div class='timestamp'>Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss} on {Environment.MachineName}</div>");
            sb.AppendLine();

            // Start tabbed interface
            sb.AppendLine("<div class='tab-container'>");
            
            // Tab headers (left sidebar)
            sb.AppendLine("<div class='tab-headers'>");
            
            // Properties tab button (always first and active)
            sb.AppendLine("<button class='tab-button active' onclick='showTab(0)'>Properties</button>");
            
            // ScriptArray tab buttons
            var sortedScripts = workObject.ScriptArray.OrderByDescending(s => s.FirstTimestamp).ToList();
            for (int i = 0; i < sortedScripts.Count; i++)
            {
                var script = sortedScripts[i];
                int tabIndex = i + 1; // Offset by 1 since Properties is tab 0
                
                string buttonText = HtmlEncode(script.Name);
                if (script.FirstTimestamp == script.LastTimestamp)
                {
                    buttonText += $"<br><small>Created: {HtmlEncode(script.FirstTimestamp)}</small>";
                }
                else
                {
                    buttonText += $"<br><small>Created: {HtmlEncode(script.FirstTimestamp)}</small>" +
                                 $"<br><small>Modified: {HtmlEncode(script.LastTimestamp)}</small>";
                }
                
                sb.AppendLine($"<button class='tab-button' onclick='showTab({tabIndex})'>{buttonText}</button>");
            }
            
            sb.AppendLine("</div>"); // Close tab-headers
            
            // Tab contents
            sb.AppendLine("<div style='flex-grow: 1; position: relative;'>");
            
            // Properties tab content (first tab, index 0)
            sb.AppendLine("<div id='tab-0' class='tab-content' style='display: block;'>");
            
            if (workObject.Properties.Any())
            {
                sb.AppendLine("<h2>Properties</h2>");
                sb.AppendLine("<table>");
                sb.AppendLine("<thead><tr><th>Property</th><th>Value</th></tr></thead>");
                sb.AppendLine("<tbody>");

                foreach (var prop in workObject.Properties.OrderBy(p => p.Key))
                {
                    string value = FormatPropertyValue(prop.Value);
                    sb.AppendLine($"<tr><td><strong>{HtmlEncode(prop.Key)}</strong></td><td>{value}</td></tr>");
                }

                sb.AppendLine("</tbody>");
                sb.AppendLine("</table>");
            }
            else
            {
                sb.AppendLine("<p><em>No properties</em></p>");
            }
            
            sb.AppendLine("</div>"); // Close tab-0
            
            // ScriptArray tab contents with Monaco Editor and fallback
            for (int i = 0; i < sortedScripts.Count; i++)
            {
                var script = sortedScripts[i];
                int tabIndex = i + 1;
                
                sb.AppendLine($"<div id='tab-{tabIndex}' class='tab-content' style='display: none;'>");
                
                // Store content in JSON script tags (safer than HTML attributes)
                string scriptJson = System.Text.Json.JsonSerializer.Serialize(script.Script);
                string outputJson = System.Text.Json.JsonSerializer.Serialize(script.Output);
                
                sb.AppendLine($"<script type='application/json' id='data-script-{i}'>{scriptJson}</script>");
                sb.AppendLine($"<script type='application/json' id='data-output-{i}'>{outputJson}</script>");
                
                // Script section with Monaco Editor and fallback
                sb.AppendLine("<h3>Script</h3>");
                sb.AppendLine($"<div id='editor-script-{i}' class='monaco-editor-container'></div>");
                sb.AppendLine($"<pre id='fallback-script-{i}' class='code-block' style='display:none;'></pre>");
                
                // Output section with Monaco Editor and fallback
                sb.AppendLine("<h3>Output</h3>");
                sb.AppendLine($"<div id='editor-output-{i}' class='monaco-editor-container'></div>");
                sb.AppendLine($"<pre id='fallback-output-{i}' class='code-block' style='display:none;'></pre>");
                
                sb.AppendLine("</div>"); // Close tab content
            }
            
            sb.AppendLine("</div>"); // Close flex-grow div
            sb.AppendLine("</div>"); // Close tab-container

            return sb.ToString();
        }

        /// <summary>
        /// Formats a property value for HTML display.
        /// </summary>
        private string FormatPropertyValue(object? value)
        {
            if (value == null) return "<em>null</em>";

            // Handle collections
            if (value is System.Collections.IEnumerable enumerable and not string)
            {
                var items = enumerable.Cast<object>().ToList();
                if (items.Count == 0) return "<em>empty</em>";
                
                return "<ul>" + string.Join("", items.Select(item => 
                    $"<li>{HtmlEncode(item?.ToString() ?? "null")}</li>")) + "</ul>";
            }

            // Handle booleans with visual indicators
            if (value is bool boolValue)
            {
                return boolValue
                    ? "<span class='success'>✓ True</span>"
                    : "<span class='failure'>✗ False</span>";
            }

            // Handle DateTime
            if (value is DateTime dateTime)
            {
                return HtmlEncode(dateTime.ToString("yyyy-MM-dd HH:mm:ss"));
            }

            // Default string representation
            string stringValue = value.ToString() ?? string.Empty;
            
            // Detect and format as URL if applicable
            if (stringValue.StartsWith("http://") || stringValue.StartsWith("https://"))
            {
                return $"<a href='{HtmlEncode(stringValue)}' target='_blank'>{HtmlEncode(stringValue)}</a>";
            }

            return HtmlEncode(stringValue);
        }

        /// <summary>
        /// HTML-encodes a string to prevent XSS and display issues.
        /// </summary>
        private string HtmlEncode(string text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            
            return System.Net.WebUtility.HtmlEncode(text);
        }
    }
}
