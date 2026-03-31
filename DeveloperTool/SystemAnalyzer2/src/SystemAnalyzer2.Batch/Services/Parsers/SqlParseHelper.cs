using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using SystemAnalyzer2.Batch.AutoDoc;

namespace SystemAnalyzer2.Batch.Parsers;

/// <summary>
/// Return type for SQL statement parsing results.
/// </summary>
public class SqlParseResult
{
    public string? SqlOperation { get; set; }
    public List<string> SqlTableNames { get; set; } = new();
    public string? CursorName { get; set; }
    public bool CursorForUpdate { get; set; }
    public List<string> UpdateFields { get; set; } = new();
}

/// <summary>
/// Static helper class for SQL statement detection and extraction.
/// Converted line-by-line from AutoDocFunctions.psm1 shared SQL functions.
/// </summary>
public static class SqlParseHelper
{
    /// <summary>
    /// Extracts SQL statements from db2/db2cmd command lines in BAT, REXX, and PS1 files.
    /// Converted line-by-line from FindSqlStatementInDb2Command (lines 6799-6947)
    /// </summary>
    public static SqlParseResult FindSqlStatementInDb2Command(string commandLine)
    {
        var result = new SqlParseResult();

        try
        {
            // Line 6816-6818: Null/empty check
            if (string.IsNullOrWhiteSpace(commandLine))
                return result;

            // Line 6820-6822: Initialize cursor variables
            result.CursorForUpdate = false;
            result.CursorName = null;

            // Line 6825: Normalize the command line
            string sqlRes = commandLine.ToLower().Trim();

            // Line 6828: Remove db2 command prefixes
            // Regex: ^(db2|db2cmd|start\s+db2cmd)\s+ - Match db2/db2cmd/start db2cmd at start of line
            sqlRes = Regex.Replace(sqlRes, @"^(db2|db2cmd|start\s+db2cmd)\s+", "");
            // Line 6829: Remove 'call' prefix
            sqlRes = Regex.Replace(sqlRes, @"^call\s+", "");
            // Line 6830: Remove 'start' prefix
            sqlRes = Regex.Replace(sqlRes, @"^start\s+", "");

            // Line 6833: Remove quotes and clean up whitespace
            sqlRes = sqlRes.Replace("\"", "").Replace("'", "").Trim();
            // Line 6834: Normalize multiple spaces to single
            sqlRes = Regex.Replace(sqlRes, @"\s+", " ");

            // Line 6836-6838
            if (sqlRes.Length == 0)
                return result;

            // Line 6841-6848: Check if line contains SQL keywords
            string[] sqlKeywords = { "select", "insert", "update", "delete", "fetch", "call", "declare", "cursor" };
            bool hasSqlKeyword = false;
            foreach (string keyword in sqlKeywords)
            {
                if (Regex.IsMatch(sqlRes, $@"\b{keyword}\b"))
                {
                    hasSqlKeyword = true;
                    break;
                }
            }

            // Line 6850-6852
            if (!hasSqlKeyword)
                return result;

            // Line 6855-6877: Extract SQL operation
            string restData = sqlRes;

            // Line 6858: Check for SELECT, INSERT, UPDATE, DELETE, FETCH, CALL
            var opMatch = Regex.Match(sqlRes, @"\b(select|insert|update|delete|fetch|call)\b");
            if (opMatch.Success)
            {
                result.SqlOperation = opMatch.Groups[1].Value.ToUpper();
                // Line 6861-6862: Get everything after the operation keyword
                int pos = sqlRes.IndexOf(opMatch.Groups[1].Value) + opMatch.Groups[1].Value.Length;
                restData = sqlRes.Substring(pos).Trim();
            }
            // Line 6864: DECLARE CURSOR
            else if (Regex.IsMatch(sqlRes, @"\bdeclare\s+cursor\b"))
            {
                result.SqlOperation = "SELECT";
                // Line 6867: Extract cursor name
                var cursorMatch = Regex.Match(sqlRes, @"\bdeclare\s+cursor\s+(\w+)");
                if (cursorMatch.Success)
                    result.CursorName = cursorMatch.Groups[1].Value;
                // Line 6871: Extract SELECT part after CURSOR ... FOR
                var forMatch = Regex.Match(sqlRes, @"\bfor\s+(.+)$");
                if (forMatch.Success)
                    restData = forMatch.Groups[1].Value.Trim();
            }

            // Line 6876-6878
            if (result.SqlOperation == null)
                return result;

            // Line 6881-6884: Check for FOR UPDATE in cursor declarations
            if (Regex.IsMatch(restData, @"\bfor\s+update\b"))
            {
                result.CursorForUpdate = true;
                restData = Regex.Replace(restData, @"\bfor\s+update\b", "");
            }

            // Line 6887-6910: Extract table names using schema.table pattern
            // Regex breakdown:
            //   (dbm\.|hst\.|log\.|crm\.|tv\.)  - Match schema prefix (capture group 1)
            //   ([a-z0-9_]+)                     - Match table name (capture group 2)
            //   (?=\s|;|\)|,|$)                  - Lookahead: stop at whitespace, semicolon, closing paren, comma, or end
            string pattern = @"(dbm\.|hst\.|log\.|crm\.|tv\.)([a-z0-9_]+)(?=\s|;|\)|,|$)";
            var tableMatches = Regex.Matches(restData, pattern, RegexOptions.IgnoreCase);

            if (tableMatches.Count > 0)
            {
                foreach (Match match in tableMatches)
                {
                    string schema = match.Groups[1].Value.ToLower();
                    string table = match.Groups[2].Value.ToLower();
                    string fullTableName = schema + table;

                    // Line 6903-6904: Clean up table name
                    fullTableName = Regex.Replace(fullTableName, @"[\)\]\};,]", "");
                    fullTableName = fullTableName.Replace(";", "");

                    if (fullTableName.Length > 0)
                        result.SqlTableNames.Add(fullTableName);
                }
            }

            // Line 6913-6936: Extract field names for UPDATE statements
            if (result.SqlOperation == "UPDATE" && result.SqlTableNames.Count > 0)
            {
                // Regex breakdown:
                //   \bset\b     - Match word "set" with word boundaries
                //   \s+         - One or more whitespace
                //   (.+?)       - Capture group: match any chars (non-greedy)
                //   (?=\bwhere\b|$) - Lookahead: stop at "where" or end of string
                string setPattern = @"\bset\b\s+(.+?)(?=\bwhere\b|$)";
                var setMatch = Regex.Match(restData, setPattern, RegexOptions.Singleline | RegexOptions.IgnoreCase);
                if (setMatch.Success)
                {
                    string setClause = setMatch.Groups[1].Value;
                    // Regex breakdown:
                    //   (\w+)     - Capture group: one or more word characters (field name)
                    //   \s*=      - Optional whitespace followed by equals sign
                    string fieldPattern = @"(\w+)\s*=";
                    var fieldMatches = Regex.Matches(setClause, fieldPattern);
                    foreach (Match fieldMatch in fieldMatches)
                    {
                        string fieldName = fieldMatch.Groups[1].Value.Trim();
                        if (fieldName.Length > 0)
                            result.UpdateFields.Add(fieldName);
                    }
                }
            }

            // Line 6939: Remove duplicates
            result.SqlTableNames = result.SqlTableNames.Distinct().OrderBy(x => x).ToList();
        }
        catch (Exception ex)
        {
            // Line 6944: Log warning
            AutoDocLogger.LogMessage($"Error in FindSqlStatementInDb2Command: {ex.Message}", LogLevel.WARN);
        }

        return result;
    }

    /// <summary>
    /// Extracts SQL statements from EXEC SQL...END-EXEC blocks in COBOL files.
    /// Converted line-by-line from FindSqlStatementInExecSql (lines 6949-7049)
    /// </summary>
    public static SqlParseResult FindSqlStatementInExecSql(string[] inCode, string fileContent, string procedureContent)
    {
        var result = new SqlParseResult();

        try
        {
            // Line 6952-6957: Check for empty input
            if (inCode == null || inCode.Length == 0)
                return result;

            result.CursorForUpdate = false;

            // Line 6961-6962: Join and normalize
            string sqlRes = " " + string.Join(" ", inCode);
            sqlRes = " " + sqlRes.ToLower().Trim() + " ";

            // Line 6964-6968: Clean up
            sqlRes = sqlRes.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
            sqlRes = sqlRes.Replace("exec sql", "").Replace("end-exec", "").Trim();

            // Line 6970-6972
            if (sqlRes.Length <= 0)
                return result;

            // Line 6974-6977: Find first space to split operation from rest
            int pos = sqlRes.IndexOf(" ");
            if (pos <= 0)
                return result;

            // Line 6979-6980: Extract operation and rest data
            result.SqlOperation = sqlRes.Substring(0, pos).ToUpper();
            string restData = sqlRes.Substring(pos + 1).ToLower();

            // Line 6983-6992: Handle FETCH - resolve cursor to its SELECT
            if (result.SqlOperation == "FETCH")
            {
                int pos2 = restData.IndexOf(" ");
                if (pos2 > 0)
                {
                    result.CursorName = restData.Substring(0, pos2);
                    string? cursorContent = GetSqlDeclareCursorPart(fileContent, result.CursorName);
                    if (cursorContent != null)
                    {
                        string cursorContentJoin = " " + cursorContent;
                        restData = cursorContentJoin.ToLower().Trim();
                        // Line 6989-6991: Check for FOR UPDATE
                        if (restData.Contains("for update"))
                            result.CursorForUpdate = true;
                    }
                }
            }

            // Line 6995-7010: Extract table names using schema.table pattern
            // Regex breakdown:
            //   (dbm\.|hst\.|log\.|crm\.|tv\.)  - Match schema prefix (group 1)
            //   (.*?)                             - Match table name non-greedy (group 2)
            //   \s                                - Stop at whitespace
            string tablePattern = @"(dbm\.|hst\.|log\.|crm\.|tv\.)(.*?)\s";
            var matches1 = Regex.Matches(restData, tablePattern);

            if (matches1.Count > 0)
            {
                foreach (Match currentMatch in matches1)
                {
                    string temp = currentMatch.Captures[0].Value;
                    // Line 7002-7007: Clean up
                    temp = temp.Replace(")", "").Replace(";", "").Trim();
                    if (temp.Length > 0)
                        result.SqlTableNames.Add(temp);
                }
            }

            // Line 7015-7038: Extract field names for UPDATE statements
            if (result.SqlOperation == "UPDATE")
            {
                // Regex breakdown:
                //   \bset\b     - Match word "set" with word boundaries
                //   \s+         - One or more whitespace
                //   (.+?)       - Capture group: match any chars (non-greedy)
                //   (?=\bwhere\b|$) - Lookahead: stop at "where" or end of string
                string setPattern = @"\bset\b\s+(.+?)(?=\bwhere\b|$)";
                var setMatch = Regex.Match(restData, setPattern, RegexOptions.Singleline);
                if (setMatch.Success)
                {
                    string setClause = setMatch.Groups[1].Value;
                    // Regex breakdown:
                    //   (\w+)     - Capture group: one or more word characters (field name)
                    //   \s*=      - Optional whitespace followed by equals sign
                    string fieldPattern = @"(\w+)\s*=";
                    var fieldMatches = Regex.Matches(setClause, fieldPattern);
                    foreach (Match fieldMatch in fieldMatches)
                    {
                        string fieldName = fieldMatch.Groups[1].Value.Trim();
                        if (fieldName.Length > 0)
                            result.UpdateFields.Add(fieldName);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Error in FindSqlStatementInExecSql: {ex.Message}", LogLevel.ERROR, ex);
        }

        return result;
    }

    /// <summary>
    /// Extracts the SQL from a DECLARE CURSOR statement in COBOL.
    /// Converted line-by-line from GetSqlDeclareCursorPart (lines 6673-6693)
    /// </summary>
    public static string? GetSqlDeclareCursorPart(string fileContent, string cursorName)
    {
        // Line 6676: Pattern: cursorName(.*?)end-exec
        // Regex breakdown:
        //   cursorName  - Literal cursor name
        //   (.*?)       - Capture group: match any chars non-greedy (the cursor SQL)
        //   end-exec    - Literal "end-exec" to end match
        string pattern = cursorName + "(.*?)end-exec";
        var matches = Regex.Matches(fileContent, pattern, RegexOptions.Singleline);

        // Line 6682-6692: Return first match if found
        if (matches.Count > 0)
        {
            string extracted = matches[0].Groups[0].Value;
            if (extracted.Length > 0)
                return extracted.ToLower();
        }

        return null;
    }

    /// <summary>
    /// Generates SQL table node connections in Mermaid diagram.
    /// Common logic shared by BAT, REX, PS1 parsers for DB2 SQL commands.
    /// Extracted from New-BatNodes/New-RexNodes/New-Ps1Nodes SQL handling blocks.
    /// </summary>
    public static void WriteSqlTableNodes(
        MermaidWriter mmdWriter,
        SqlParseResult sqlResult,
        string functionNameLower,
        List<string> sqlTableArray)
    {
        if (sqlResult.SqlOperation == null || sqlResult.SqlTableNames.Count == 0)
            return;

        string[] supportedSqlExpressions = { "SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL" };
        if (!supportedSqlExpressions.Contains(sqlResult.SqlOperation))
            return;

        int tableCounter = 0;
        foreach (string sqlTable in sqlResult.SqlTableNames)
        {
            sqlTableArray.Add(sqlTable);
            tableCounter++;
            string statementText = sqlResult.SqlOperation.ToLower();

            // Handle cursor logic
            if (!string.IsNullOrEmpty(sqlResult.CursorName))
            {
                if (tableCounter == 1)
                {
                    statementText = "Cursor " + sqlResult.CursorName.ToUpper() + " select";
                    if (sqlResult.CursorForUpdate)
                        statementText = "Primary table for cursor " + sqlResult.CursorName.ToUpper() + " select for update";
                }
                else
                {
                    statementText = "Sub-select in cursor " + sqlResult.CursorName.ToUpper();
                }
            }
            else
            {
                // Handle multiple tables in non-cursor statements
                if (tableCounter > 1)
                {
                    if (sqlResult.SqlOperation == "UPDATE" || sqlResult.SqlOperation == "INSERT" || sqlResult.SqlOperation == "DELETE")
                        statementText = "Sub-select related to " + sqlResult.SqlTableNames[0].Trim();
                    if (sqlResult.SqlOperation == "SELECT")
                        statementText = "Join or Sub-select related to " + sqlResult.SqlTableNames[0].Trim();
                }
                // Add field names for UPDATE statements (primary table only)
                else if (sqlResult.SqlOperation == "UPDATE" && sqlResult.UpdateFields.Count > 0)
                {
                    string fieldList = string.Join(", ", sqlResult.UpdateFields);
                    statementText = $"update [{fieldList}]";
                }
            }

            // Create SQL table node connection
            string statement = functionNameLower + "--\"" + statementText + "\"-->sql_" + sqlTable.Replace(".", "_").Trim() + "[(" + sqlTable.Trim() + ")]";
            mmdWriter.WriteLine(statement);
        }
    }
}
