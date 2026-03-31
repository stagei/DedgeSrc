using SqlMmdConverter.Exceptions;
using SqlMmdConverter.Runtime;

namespace SqlMmdConverter.Converters;

/// <summary>
/// Converts SQL DDL to Mermaid ERD diagrams using SQLGlot.
/// </summary>
public class SqlToMmdConverter : ISqlToMmdConverter
{
    /// <summary>
    /// Cleans SQL by removing T-SQL/MS SQL Server/MS Access syntax issues.
    /// This makes the SQL more compatible with SQLGlot's parser.
    /// </summary>
    /// <param name="sql">SQL DDL to clean</param>
    /// <returns>Cleaned SQL with brackets removed and syntax normalized</returns>
    private static string CleanSqlBrackets(string sql)
    {
        // Remove T-SQL brackets: [TableName] -> TableName
        sql = System.Text.RegularExpressions.Regex.Replace(
            sql,
            @"\[([^\]]+)\]",
            "$1"
        );
        
        // Fix MS Access DEFAULT =Function() to DEFAULT Function()
        sql = System.Text.RegularExpressions.Regex.Replace(
            sql,
            @"DEFAULT\s*=\s*",
            "DEFAULT ",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase
        );
        
        return sql;
    }

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format synchronously.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <returns>A Mermaid ERD diagram as a string</returns>
    /// <exception cref="SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public string Convert(string sqlDdl)
    {
        if (string.IsNullOrWhiteSpace(sqlDdl))
        {
            throw new ArgumentException("SQL DDL cannot be null or empty", nameof(sqlDdl));
        }

        try
        {
            // Clean SQL to remove T-SQL brackets
            var cleanedSql = CleanSqlBrackets(sqlDdl);
            
            // Write SQL to temp file for processing
            var tempSqlFile = Path.GetTempFileName();
            
            try
            {
                File.WriteAllText(tempSqlFile, cleanedSql);

                // Execute Python script via RuntimeManager
                var result = RuntimeManager.ExecutePythonScript(
                    "sql_to_mmd.py",
                    $"\"{tempSqlFile}\""
                );

                if (string.IsNullOrWhiteSpace(result))
                {
                    throw new ConversionException("SQL to Mermaid conversion produced no output");
                }

                return result.Trim();
            }
            finally
            {
                // Clean up temp file
                if (File.Exists(tempSqlFile))
                {
                    File.Delete(tempSqlFile);
                }
            }
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new SqlParseException(
                $"Failed to convert SQL to Mermaid ERD: {ex.Message}",
                ex);
        }
    }

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format asynchronously.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to a Mermaid ERD diagram as a string</returns>
    /// <exception cref="SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public async Task<string> ConvertAsync(string sqlDdl, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sqlDdl))
        {
            throw new ArgumentException("SQL DDL cannot be null or empty", nameof(sqlDdl));
        }

        try
        {
            // Clean SQL to remove T-SQL brackets
            var cleanedSql = CleanSqlBrackets(sqlDdl);
            
            // Write SQL to temp file for processing
            var tempSqlFile = Path.GetTempFileName();
            
            try
            {
                await File.WriteAllTextAsync(tempSqlFile, cleanedSql, cancellationToken);

                // Execute Python script via RuntimeManager
                var result = await RuntimeManager.ExecutePythonScriptAsync(
                    "sql_to_mmd.py",
                    $"\"{tempSqlFile}\"",
                    cancellationToken
                );

                if (string.IsNullOrWhiteSpace(result))
                {
                    throw new ConversionException("SQL to Mermaid conversion produced no output");
                }

                return result.Trim();
            }
            finally
            {
                // Clean up temp file
                if (File.Exists(tempSqlFile))
                {
                    File.Delete(tempSqlFile);
                }
            }
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new SqlParseException(
                $"Failed to convert SQL to Mermaid ERD: {ex.Message}",
                ex);
        }
    }

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format wrapped in Markdown.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="title">Title for the markdown document (typically the filename without extension)</param>
    /// <returns>A Markdown document containing the Mermaid ERD diagram</returns>
    /// <exception cref="SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public string ConvertToMarkdown(string sqlDdl, string title)
    {
        var mermaidDiagram = Convert(sqlDdl);
        return WrapInMarkdown(mermaidDiagram, title);
    }

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format wrapped in Markdown asynchronously.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="title">Title for the markdown document (typically the filename without extension)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to a Markdown document containing the Mermaid ERD diagram</returns>
    /// <exception cref="SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public async Task<string> ConvertToMarkdownAsync(string sqlDdl, string title, CancellationToken cancellationToken = default)
    {
        var mermaidDiagram = await ConvertAsync(sqlDdl, cancellationToken);
        return WrapInMarkdown(mermaidDiagram, title);
    }

    /// <summary>
    /// Wraps a Mermaid ERD diagram in Markdown format with proper code fencing.
    /// Extracts %% comments and places them outside the code fence.
    /// </summary>
    /// <param name="mermaidDiagram">The Mermaid ERD diagram content</param>
    /// <param name="title">Title for the markdown document</param>
    /// <returns>Markdown-formatted document</returns>
    private static string WrapInMarkdown(string mermaidDiagram, string title)
    {
        var markdown = new System.Text.StringBuilder();
        
        // Add title as heading
        markdown.AppendLine($"# {title}");
        markdown.AppendLine();
        
        // Split diagram and comments
        var lines = mermaidDiagram.Split('\n');
        var diagramLines = new System.Collections.Generic.List<string>();
        var commentLines = new System.Collections.Generic.List<string>();
        bool inCommentSection = false;
        
        foreach (var line in lines)
        {
            if (line.TrimStart().StartsWith("%%"))
            {
                inCommentSection = true;
                // Convert %% to markdown - remove %% prefix
                var commentText = line.TrimStart();
                if (commentText.StartsWith("%%"))
                {
                    commentText = commentText.Substring(2).TrimStart();
                }
                commentLines.Add(commentText);
            }
            else if (!inCommentSection)
            {
                diagramLines.Add(line);
            }
        }
        
        // Add Mermaid diagram in markdown code fence
        markdown.AppendLine("```mermaid");
        markdown.AppendLine(string.Join('\n', diagramLines).TrimEnd());
        markdown.AppendLine("```");
        
        // Add comments as regular markdown text
        if (commentLines.Count > 0)
        {
            markdown.AppendLine();
            markdown.AppendLine("---");
            markdown.AppendLine();
            foreach (var comment in commentLines)
            {
                markdown.AppendLine(comment);
            }
        }
        
        return markdown.ToString();
    }
}

