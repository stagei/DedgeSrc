using SqlMermaidErdTools.Exceptions;
using SqlMermaidErdTools.Models;
using SqlMermaidErdTools.Runtime;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Generates SQL ALTER statements from differences between two Mermaid ERD diagrams.
/// </summary>
public class MmdDiffToSqlGenerator : BaseConverter, IMmdDiffToSqlGenerator
{
    /// <summary>
    /// Generates SQL ALTER statements from differences between two Mermaid ERD diagrams synchronously.
    /// </summary>
    /// <param name="beforeMermaid">The original/before Mermaid ERD diagram</param>
    /// <param name="afterMermaid">The modified/after Mermaid ERD diagram</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <returns>SQL ALTER statements representing the differences</returns>
    /// <exception cref="MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public string GenerateAlterStatements(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect dialect = SqlDialect.AnsiSql)
    {
        ValidateInput(beforeMermaid, nameof(beforeMermaid));
        ValidateInput(afterMermaid, nameof(afterMermaid));

        try
        {
            var dialectStr = MapDialectToSqlGlot(dialect);
            var dialectName = string.IsNullOrEmpty(dialectStr) ? "AnsiSql" : dialect.ToString();
            
            // Export inputs
            ExportToFile(
                beforeMermaid, 
                $"<In>MmdDiff_{dialectName}_Before.mmd", 
                "Before Mermaid diagram"
            );
            
            ExportToFile(
                afterMermaid, 
                $"<In>MmdDiff_{dialectName}_After.mmd", 
                "After Mermaid diagram"
            );
            
            // Write both files and execute script
            var beforeFile = Path.GetTempFileName();
            var afterFile = Path.GetTempFileName();
            
            try
            {
                File.WriteAllText(beforeFile, beforeMermaid);
                File.WriteAllText(afterFile, afterMermaid);
                
                var result = RuntimeManager.ExecutePythonScript(
                    "mmd_diff_to_sql.py",
                    $"\"{beforeFile}\" \"{afterFile}\" {dialectStr}"
                );
                
                if (string.IsNullOrWhiteSpace(result))
                {
                    return "-- No changes detected";
                }
                
                var trimmedResult = result.Trim();
                
                // Export outputs
                var timestamp = GetTimestamp();
                ExportToFile(
                    trimmedResult,
                    $"<Out>MmdDiff_{dialectName}FromSqlGlot{timestamp}.sql",
                    "ALTER statements from SQLGlot"
                );
                
                ExportToFile(
                    trimmedResult,
                    $"<Out>MmdDiff_{dialectName}.sql",
                    "Final ALTER statements"
                );
                
                return trimmedResult;
            }
            finally
            {
                if (File.Exists(beforeFile)) File.Delete(beforeFile);
                if (File.Exists(afterFile)) File.Delete(afterFile);
            }
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new MmdParseException(
                $"Failed to generate ALTER statements from Mermaid diff: {ex.Message}",
                ex);
        }
    }

    /// <summary>
    /// Generates SQL ALTER statements from differences between two Mermaid ERD diagrams asynchronously.
    /// </summary>
    /// <param name="beforeMermaid">The original/before Mermaid ERD diagram</param>
    /// <param name="afterMermaid">The modified/after Mermaid ERD diagram</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to SQL ALTER statements representing the differences</returns>
    /// <exception cref="MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public async Task<string> GenerateAlterStatementsAsync(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect dialect = SqlDialect.AnsiSql,
        CancellationToken cancellationToken = default)
    {
        ValidateInput(beforeMermaid, nameof(beforeMermaid));
        ValidateInput(afterMermaid, nameof(afterMermaid));

        try
        {
            var dialectStr = MapDialectToSqlGlot(dialect);
            var dialectName = string.IsNullOrEmpty(dialectStr) ? "AnsiSql" : dialect.ToString();
            
            // Export inputs
            await ExportToFileAsync(
                beforeMermaid, 
                $"MmdDiff_{dialectName}-In_Before.mmd", 
                "Before Mermaid diagram",
                cancellationToken
            );
            
            await ExportToFileAsync(
                afterMermaid, 
                $"MmdDiff_{dialectName}-In_After.mmd", 
                "After Mermaid diagram",
                cancellationToken
            );
            
            // Write both files and execute script
            var beforeFile = Path.GetTempFileName();
            var afterFile = Path.GetTempFileName();
            
            try
            {
                await File.WriteAllTextAsync(beforeFile, beforeMermaid, cancellationToken);
                await File.WriteAllTextAsync(afterFile, afterMermaid, cancellationToken);
                
                var timestamp = GetTimestamp();
                var result = await RuntimeManager.ExecutePythonScriptAsync(
                    "mmd_diff_to_sql.py",
                    $"\"{beforeFile}\" \"{afterFile}\" {dialectStr}",
                    cancellationToken
                );
                
                if (string.IsNullOrWhiteSpace(result))
                {
                    return "-- No changes detected";
                }
                
                var trimmedResult = result.Trim();
                
                // Export outputs
                await ExportToFileAsync(
                    trimmedResult,
                    $"MmdDiff_{dialectName}-OutFromSqlGlot{timestamp}.sql",
                    "ALTER statements from SQLGlot",
                    cancellationToken
                );
                
                await ExportToFileAsync(
                    trimmedResult,
                    $"MmdDiff_{dialectName}-Out.sql",
                    "Final ALTER statements",
                    cancellationToken
                );
                
                return trimmedResult;
            }
            finally
            {
                if (File.Exists(beforeFile)) File.Delete(beforeFile);
                if (File.Exists(afterFile)) File.Delete(afterFile);
            }
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new MmdParseException(
                $"Failed to generate ALTER statements from Mermaid diff: {ex.Message}",
                ex);
        }
    }
}

