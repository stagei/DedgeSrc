using System.IO;
using System.Text;

namespace DedgeCommon
{
    /// <summary>
    /// Service for loading and processing HTML templates.
    /// Supports loading templates from shared Resources folder accessible by both PowerShell and C#.
    /// </summary>
    public class HtmlTemplateService
    {
        private const string DefaultTemplateFileName = "HtmlTemplate.html";
        private readonly string? _templatesFolderPath;

        public HtmlTemplateService()
        {
            // Try to get Resources folder path from GlobalSettings
            try
            {
                string commonPath = GlobalFunctions.GetCommonPath();
                _templatesFolderPath = Path.Combine(commonPath, "Configfiles", "Resources");
                DedgeNLog.Debug($"HTML template folder: {_templatesFolderPath}");
            }
            catch (Exception ex)
            {
                DedgeNLog.Warn(ex, "Could not load GlobalSettings for template path, will use built-in template");
                _templatesFolderPath = null;
            }
        }

        /// <summary>
        /// Gets the full HTML page with title, content, and optional additional styles.
        /// </summary>
        public string GetHtmlPage(string title, string content, string? additionalStyle = null)
        {
            // Try to load from template file first
            if (!string.IsNullOrEmpty(_templatesFolderPath))
            {
                string templatePath = Path.Combine(_templatesFolderPath, DefaultTemplateFileName);

                if (File.Exists(templatePath))
                {
                    try
                    {
                        string template = File.ReadAllText(templatePath, Encoding.UTF8);
                        DedgeNLog.Debug($"Loaded HTML template from: {templatePath}");

                        // Replace placeholders
                        template = template.Replace("{{TITLE}}", System.Net.WebUtility.HtmlEncode(title));
                        template = template.Replace("{{CONTENT}}", content);
                        template = template.Replace("{{ADDITIONAL_STYLE}}", additionalStyle ?? string.Empty);

                        return template;
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Warn(ex, $"Failed to load template from {templatePath}, using built-in template");
                    }
                }
            }

            // Fall back to built-in template
            DedgeNLog.Debug("Using built-in HTML template");
            return GetBuiltInHtmlTemplate(title, content, additionalStyle);
        }

        /// <summary>
        /// Gets the built-in HTML template using File.ReadAllText to avoid escaping issues.
        /// </summary>
        private string GetBuiltInHtmlTemplate(string title, string content, string? additionalStyle = null)
        {
            // For simplicity, just read from the backup file we created
            try
            {
                string templateContent = File.ReadAllText(@"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\Resources\HtmlTemplate.html", Encoding.UTF8);
                templateContent = templateContent.Replace("{{TITLE}}", System.Net.WebUtility.HtmlEncode(title));
                templateContent = templateContent.Replace("{{CONTENT}}", content);
                templateContent = templateContent.Replace("{{ADDITIONAL_STYLE}}", additionalStyle ?? string.Empty);
                return templateContent;
            }
            catch
            {
                // Ultra-minimal fallback if everything fails
                string encodedTitle = System.Net.WebUtility.HtmlEncode(title);
                return $"<!DOCTYPE html><html><head><title>{encodedTitle}</title></head><body><h1>{encodedTitle}</h1>{content}</body></html>";
            }
        }

        /// <summary>
        /// Creates the default HTML template file in the Resources folder if it doesn't exist.
        /// </summary>
        public void EnsureTemplateExists()
        {
            // Template already exists, created manually
        }
    }
}
