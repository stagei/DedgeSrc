using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using AutoDocNew.Core;
using AutoDocNew.Models;

namespace AutoDocNew.Parsers;

/// <summary>
/// REX Parser - complete line-by-line translation from AutoDocFunctions.psm1
/// Functions translated:
///   Get-RexExecutionPathDiagram  (lines 3983-3999)
///   Test-RexFunction             (lines 4001-4018)
///   Get-RexDecodedConcat         (lines 4020-4033)
///   DecodeQuote                  (lines 4034-4048)
///   Get-RexDecodedSubstr         (lines 4050-4069)
///   Get-RexVariableValue         (lines 4071-4083)
///   New-RexNodes                 (lines 4085-4620)
///   New-RexMmdLinks              (lines 4622-4661)
///   Get-RexMetaData              (lines 4663-4838)
///   Write-RexMmd                 (lines 4840-4856)
///   Find-RexFunctionCode         (lines 4858-4894)
///   Start-RexParse               (lines 4912-5239)
/// </summary>
public static class RexParser
{
    /// <summary>Strip surrounding double-quotes and trim whitespace from CSV fields.</summary>
    private static string CsvClean(string field) => field.Trim().Trim('"').Trim();

    /// <summary>
    /// Match result class for Select-String equivalent.
    /// </summary>
    private class MatchResult
    {
        public int LineNumber { get; set; }
        public string Line { get; set; } = "";
        public string Pattern { get; set; } = "";
    }

    #region Variable Resolution Chain (lines 4020-4083)

    // Maximum recursion depth to prevent infinite loops when variables reference themselves
    private const int MaxResolveDepth = 10;

    /// <summary>
    /// Handles variable concatenation with || operator.
    /// Converted line-by-line from Get-RexDecodedConcat (lines 4020-4033)
    /// </summary>
    private static string GetRexDecodedConcat(string decodeString, Dictionary<string, string> assignmentsDict, int depth = 0)
    {
        if (depth > MaxResolveDepth) return decodeString;
        if (decodeString.Contains("||"))
        {
            string[] temp1 = decodeString.Split("||");
            string returnString = "";
            foreach (string item in temp1)
            {
                string resolved = GetRexVariableValue(item, assignmentsDict, depth + 1);
                returnString += resolved;
            }
            return returnString;
        }
        return decodeString;
    }

    /// <summary>
    /// Handles single-quote decoding for REXX strings.
    /// Converted line-by-line from DecodeQuote (lines 4034-4048)
    /// </summary>
    private static string DecodeQuote(string decodeString, Dictionary<string, string> assignmentsDict, int depth = 0)
    {
        if (depth > MaxResolveDepth) return decodeString;
        if (decodeString.Contains("'"))
        {
            string[] temp1 = decodeString.Split("'");
            string returnString = "";
            foreach (string item in temp1)
            {
                returnString = returnString.Trim();
                string resolved = GetRexVariableValue(item, assignmentsDict, depth + 1);
                returnString += " " + resolved.Trim();
            }
            // Line 4047: Clean up
            return returnString.Trim().Replace("'", "").Replace("  ", " ").Replace("  ", " ")
                .Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
        }
        return decodeString;
    }

    /// <summary>
    /// Handles SUBSTR operations in variable values.
    /// Converted line-by-line from Get-RexDecodedSubstr (lines 4050-4069)
    /// </summary>
    private static string GetRexDecodedSubstr(string decodeString)
    {
        if (decodeString.ToLower().Contains("substr"))
        {
            string[] temp1 = decodeString.ToLower().Split("substr");
            string returnString = "";
            foreach (string item in temp1)
            {
                string processed = item;
                if (processed.Contains("("))
                {
                    processed = processed.Replace("(", "").Replace(")", "");
                    string temp2 = processed.Split(",")[0];
                    processed = temp2;
                }
                returnString += processed;
            }
            return returnString;
        }
        return decodeString;
    }

    /// <summary>
    /// Resolves variable values from assignments dictionary.
    /// Converted line-by-line from Get-RexVariableValue (lines 4071-4083)
    /// </summary>
    private static string GetRexVariableValue(string decodeString, Dictionary<string, string> assignmentsDict, int depth = 0)
    {
        if (depth > MaxResolveDepth) return decodeString;
        if (decodeString.Length > 0)
        {
            string returnString = decodeString;
            string key = decodeString.Trim().ToUpper();
            if (assignmentsDict.ContainsKey(key))
            {
                returnString = assignmentsDict[key];
                returnString = GetRexDecodedConcat(returnString, assignmentsDict, depth + 1);
            }
            return returnString;
        }
        return decodeString;
    }

    #endregion

    #region Test-RexFunction (lines 4001-4018)

    /// <summary>
    /// Validates if a string is a valid REXX function (ends with colon).
    /// Converted line-by-line from Test-RexFunction (lines 4001-4018)
    /// </summary>
    private static bool TestRexFunction(string functionName, List<string> functions)
    {
        // Line 4006: Must contain ':'
        if (!functionName.Contains(":"))
            return false;
        // Line 4009: Remove ':' and uppercase
        string functionTemp = functionName.Replace(":", "").ToUpper().Trim();
        // Line 4011: Check if in functions list
        return functions.Contains(functionTemp);
    }

    #endregion

    #region Find-RexFunctionCode (lines 4858-4894)

    /// <summary>
    /// Extracts code lines for a specific REXX function.
    /// Converted line-by-line from Find-RexFunctionCode (lines 4858-4894)
    /// </summary>
    private static List<string> FindRexFunctionCode(List<MatchResult> array, string functionName, List<string> functions)
    {
        bool foundStart = false;
        try { functionName = functionName.ToLower(); } catch { }

        var extractedElements = new List<string>();
        int lineNumber = 0;

        foreach (var objectItem in array)
        {
            string item = objectItem.Line;
            lineNumber++;

            // Line 4878: Check for function start (FUNCNAME:)
            if (item.Trim().StartsWith(functionName.ToUpper() + ":"))
            {
                foundStart = true;
                extractedElements = new List<string>();
            }
            else if (foundStart)
            {
                // Line 4883: Check if next function
                if (TestRexFunction(item, functions))
                {
                    foundStart = false;
                    break;
                }
                else
                {
                    extractedElements.Add(item);
                }
            }
        }
        return extractedElements;
    }

    #endregion

    #region Write-RexMmd (lines 4840-4856)

    /// <summary>
    /// Writes REX-specific Mermaid content with sanitization.
    /// Converted line-by-line from Write-RexMmd (lines 4840-4856)
    /// </summary>
    private static void WriteRexMmd(MermaidWriter mmdWriter, string mmdString)
    {
        if (string.IsNullOrEmpty(mmdString))
            return;

        // Line 4842: Replace literal newlines with <br/>
        mmdString = mmdString.Replace("\n", "<br/>").Replace("\r", "");
        // Line 4843: Handle __MAIN__
        mmdString = mmdString.Replace("__MAIN__", "main").Replace("__main__", "main");
        // Line 4844: Normalize multiple spaces
        // Regex: \s{2,} - Replace 2+ whitespace chars with single space
        mmdString = Regex.Replace(mmdString, @"\s{2,}", " ");

        mmdWriter.WriteLine(mmdString);
    }

    #endregion

    #region New-RexMmdLinks (lines 4622-4661)

    /// <summary>
    /// Generates Azure DevOps source code links for REXX functions.
    /// Converted line-by-line from New-RexMmdLinks (lines 4622-4661)
    /// </summary>
    private static void NewRexMmdLinks(MermaidWriter mmdWriter, string baseFileName, List<MatchResult> sourceFile, List<string> functions)
    {
        try
        {
            // Line 4627-4629: Main file link
            string link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + baseFileName.ToLower();
            string baseName = baseFileName.ToLower().Split(".")[0];
            string statement = "click " + baseName + " \"" + link + "\" \"" + baseName + "\" _blank";
            WriteRexMmd(mmdWriter, statement);

            int counter = 0;
            // Line 4632-4651: Function links
            foreach (var item in sourceFile)
            {
                string line = item.Line;
                counter++;
                if (line.Trim().Length == 0)
                    continue;

                // Line 4645: Check if function label
                if (TestRexFunction(line.Trim(), functions))
                {
                    string funcName = line.Replace("--", "-").Replace(":", "").ToLower();
                    link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/"
                        + baseFileName.ToLower() + "&version=GBmaster&line=" + item.LineNumber
                        + "&lineEnd=" + (item.LineNumber + 1) + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents";
                    statement = "click " + funcName + " \"" + link + "\" \"" + funcName + "\" _blank";
                    WriteRexMmd(mmdWriter, statement);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in NewRexMmdLinks: {ex.Message}", LogLevel.ERROR, ex);
        }
    }

    #endregion

    #region Get-RexExecutionPathDiagram (lines 3983-3999)

    /// <summary>
    /// Generates execution path diagram for a REXX file.
    /// Converted line-by-line from Get-RexExecutionPathDiagram (lines 3983-3999)
    /// </summary>
    private static void GetRexExecutionPathDiagram(MermaidWriter mmdWriter, string srcRootFolder, string baseFileName)
    {
        bool programInUse = false;

        // Line 3989: Find execution paths in *.ps1, *.bat, *.rex, *.cs, *.psm1, *.cbl files
        (programInUse, var returnArray) = ExecutionPathHelper.FindAutoDocExecutionPaths(
            srcRootFolder,
            new[] { "*.ps1", "*.bat", "*.rex", "*.cs", "*.psm1", "*.cbl" },
            baseFileName,
            programInUse,
            srcRootFolder);

        foreach (string item in returnArray)
        {
            WriteRexMmd(mmdWriter, item);
        }

        if (!programInUse)
        {
            Logger.LogMessage($"Program is never called from any other program or script: {baseFileName}", LogLevel.INFO);
        }
    }

    #endregion

    #region New-RexNodes (lines 4085-4620)

    /// <summary>
    /// Main node generation function for REXX - processes function code and generates Mermaid nodes.
    /// Converted line-by-line from New-RexNodes (lines 4085-4620)
    /// </summary>
    private static void NewRexNodes(
        List<MatchResult> functionCode,
        string[] fileContent,
        string functionName,
        MermaidWriter mmdWriter,
        string baseFileName,
        List<string> functions,
        Dictionary<string, string> assignmentsDict,
        List<string> sqlTableArray,
        List<string> htmlCallListCbl,
        List<string> htmlCallList)
    {
        if (string.IsNullOrEmpty(functionName))
            return;

        int uniqueCounter = 0;

        foreach (var lineObject in functionCode)
        {
            // Line 4099-4104: First iteration - add source link
            if (uniqueCounter == 0)
            {
                string link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/"
                    + baseFileName.ToLower() + "&version=GBmaster&line=" + lineObject.LineNumber
                    + "&lineEnd=" + (lineObject.LineNumber + 1) + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents";
                string stmt = "click " + functionName.ToLower() + " \"" + link + "\" \"" + functionName.ToLower() + "\" _blank";
                WriteRexMmd(mmdWriter, stmt);
                stmt = "style " + functionName.ToLower() + " stroke:dark-blue,stroke-width:3px";
                WriteRexMmd(mmdWriter, stmt);
            }
            uniqueCounter++;
            string line = lineObject.Line.Trim();

            if (line.Length == 0) continue;

            // Line 4114-4116: Skip RXFUNCADD
            if (line.ToUpper().Contains("RXFUNCADD")) continue;

            // Line 4117-4120: Extract call target
            string testCallfunction = line.ToUpper().Replace(":", "");
            if (testCallfunction.Contains("CALL ") && testCallfunction.Contains(" "))
            {
                string[] parts = testCallfunction.Split(new[] { "CALL " }, StringSplitOptions.None);
                if (parts.Length > 1)
                    testCallfunction = parts[1].Trim();
            }

            // Line 4125-4139: Direct function call
            if (functions.Contains(line.ToUpper().Replace(":", "")) || functions.Contains(testCallfunction))
            {
                string toNode = functions.Contains(testCallfunction) ? testCallfunction : line.ToUpper().Replace(":", "");
                if (toNode.ToLower() == functionName.Trim().ToLower()) continue;

                string stmt = functionName.Trim().ToLower() + " --call--> " + toNode.ToLower().Replace(" ", "_") + "(\"" + toNode + "\")";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            string lineLower = line.ToLower();

            // Line 4141-4166: REXX script invocation ('start or 'rexx)
            if ((lineLower.StartsWith("'start") || lineLower.Contains("rexx")) && !lineLower.Contains("system32"))
            {
                string temp1 = DecodeQuote(line, assignmentsDict);
                temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                temp1 = temp1.ToLower().Replace("'", "").Replace("\"", "").Replace("start", "")
                    .Replace("rexx", "").Replace("call ", "").Replace("  ", " ").Trim();
                string rexFilename = temp1.Trim().ToLower();
                if (rexFilename.Contains(" "))
                    rexFilename = temp1.Trim().ToLower().Split(" ")[0];
                if (!rexFilename.Contains(".rex"))
                    rexFilename += ".rex";

                string itemName = functionName.Trim().ToLower() + "_rexxrun" + uniqueCounter;
                htmlCallList.Add(rexFilename);
                string stmt = functionName.Trim().ToLower() + " --start rexx script-->" + itemName + "[[" + rexFilename + "]]";
                WriteRexMmd(mmdWriter, stmt);

                string rLink = "./" + rexFilename + ".html";
                stmt = "click " + itemName + " \"" + rLink + "\" \"" + itemName + "\" _blank";
                WriteRexMmd(mmdWriter, stmt);
                stmt = "style " + itemName + " stroke:dark-blue,stroke-width:4px";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4170-4204: Windows commands ('@copy, 'pause, 'del, etc.)
            if (lineLower.Contains("'@copy") || lineLower.StartsWith("'pause") || lineLower.StartsWith("'reg")
                || lineLower.StartsWith("'regedit") || lineLower.StartsWith("'notepad") || lineLower.StartsWith("'del")
                || lineLower.StartsWith("'icacls") || lineLower.StartsWith("'@del") || lineLower.StartsWith("'path")
                || lineLower.StartsWith("'set") || lineLower.StartsWith("'start") || lineLower.StartsWith("'net")
                || lineLower.StartsWith("'ren") || lineLower.StartsWith("'xcopy") || lineLower.StartsWith("'adfind")
                || lineLower.Contains("'copy") || lineLower.Contains("system32") || lineLower.StartsWith("'postiecgi")
                || lineLower.StartsWith("'postie") || lineLower.Contains("'xcopy") || lineLower.Contains("psexec")
                || lineLower.Contains("robocopy"))
            {
                string temp1 = DecodeQuote(line, assignmentsDict);
                temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                temp1 = temp1.Replace("\"", "").Replace("\\\\", "\n \\\\").Replace("C:\\", "\n C:\\").Replace("N:\\", "\n N:\\");
                string[] temp3 = temp1.Split(" ");
                string temp2 = "\"" + temp3[0] + "\n" + temp1.Replace(temp3[0], "").Trim() + "\"";

                string stmt = functionName.Trim().ToLower() + " --windows command-->" + functionName.Trim().ToLower() + "_ren" + uniqueCounter + "(" + temp2 + ")";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4205-4218: .bat file invocation
            if (lineLower.Contains(".bat"))
            {
                string temp1 = DecodeQuote(line, assignmentsDict);
                temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                temp1 = temp1.Replace("\"", "").Replace("\\\\", "\n \\\\").Replace("C:\\", "\n C:\\").Replace("N:\\", "\n N:\\");
                string[] temp3 = temp1.Split(" ");
                string temp2 = "\"" + temp3[0] + "\n parameters: " + temp1.Replace(temp3[0], "").Trim() + "\"";

                string stmt = functionName.Trim().ToLower() + " --windows batch script-->" + functionName.Trim().ToLower() + "_ren" + uniqueCounter + "(" + temp2 + ")";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4220-4247: 'RUN - COBOL program invocation
            if (lineLower.Contains("'run"))
            {
                string temp1 = DecodeQuote(line, assignmentsDict);
                temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                temp1 = temp1.ToUpper().Trim().Replace("RUN", "").Trim().Replace("  ", " ");
                string[] temp2 = temp1.Split(" ");
                string cblProgram = temp2[0].ToLower().Trim() + ".cbl";

                string displayName;
                if (temp2.Length > 1)
                    displayName = "\"" + cblProgram + "\nparameters: " + temp2[1].Trim().Replace(" ", ", ") + "\"";
                else
                    displayName = "\"" + cblProgram + "\"";

                htmlCallListCbl.Add(cblProgram);
                string stmt = functionName.Trim().ToLower() + " --start cobol program-->" + functionName.Trim().ToLower() + "_run" + uniqueCounter + "[[" + displayName + "]]";
                WriteRexMmd(mmdWriter, stmt);

                string runItemName = functionName.Trim().ToLower() + "_run" + uniqueCounter;
                string cblLink = "./" + cblProgram + ".html";
                stmt = "click " + runItemName + " \"" + cblLink + "\" \"" + runItemName + "\" _blank";
                WriteRexMmd(mmdWriter, stmt);
                stmt = "style " + runItemName + " stroke:dark-blue,stroke-width:4px";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4249-4314: 'DB2 command handling
            if (lineLower.Contains("'db2"))
            {
                string temp1 = DecodeQuote(line, assignmentsDict);
                temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                string itemName = functionName.Trim().ToLower() + "_db2" + uniqueCounter;
                temp1 = temp1.Replace("\"", "").Replace("'", "").Trim();
                string[] temp3 = temp1.Split(" ");
                string temp1Display = temp3[0] + "\n" + temp1.ToLower().Replace(temp3[0], "").Trim();

                // Line 4260: Try SQL extraction
                var sqlResult = SqlParseHelper.FindSqlStatementInDb2Command(line);

                if (sqlResult.SqlOperation != null && sqlResult.SqlTableNames.Count > 0)
                {
                    SqlParseHelper.WriteSqlTableNodes(mmdWriter, sqlResult, functionName.Trim().ToLower(), sqlTableArray);
                    continue;
                }

                // No SQL - regular DB2 command
                string stmt = functionName.Trim().ToLower() + " --DB2 command-->" + itemName + "(\"" + temp1Display + "\")";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4316-4320: FtpLogoff
            if (lineLower.Contains("ftplogoff"))
            {
                string stmt = functionName.Trim().ToLower() + " ---->" + functionName.Trim().ToLower() + "_FtpLogoff" + uniqueCounter + "[[FtpLogoff]]";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4322-4375: FtpPut
            if (lineLower.Contains("ftpput"))
            {
                string optionsText = "";
                int pos = lineLower.IndexOf("ftpput");
                string temp = line.Substring(pos + 6).Replace("(", "").Replace(")", "");
                string[] tempParts = temp.Split(",");
                int counter = 0;
                bool ok = false;

                foreach (string item in tempParts)
                {
                    string resolved = item.Trim();
                    counter++;
                    string key = resolved.ToUpper();
                    if (assignmentsDict.ContainsKey(key))
                    {
                        string temp2 = assignmentsDict[key];
                        if (temp2.Contains("||"))
                        {
                            string[] temp3 = temp2.Split("||");
                            string temp4 = "";
                            foreach (string item2Part in temp3)
                            {
                                string item2 = GetRexVariableValue(item2Part, assignmentsDict);
                                item2 = GetRexVariableValue(item2, assignmentsDict);
                                if (item2.ToLower().Contains("filespec"))
                                {
                                    item2 = item2.Replace("filespec", "").Replace("(", "").Replace(")", "").Split(",")[1].Trim();
                                    item2 = GetRexVariableValue(item2, assignmentsDict);
                                }
                                temp4 += item2.Replace("'", "");
                            }
                            temp2 = temp4;
                        }
                        resolved = temp2.Trim();
                    }

                    if (counter == 1)
                        optionsText += "source file: " + resolved.Trim() + "\n";
                    if (counter == 2)
                    {
                        optionsText += "destination file: " + resolved.Trim() + "\n";
                        ok = true;
                    }
                    if (counter == 3)
                    {
                        resolved = resolved.Replace("'", "").Replace("\"", "").Trim();
                        optionsText += "encoding: " + resolved.Trim() + "\n";
                    }
                }

                if (ok)
                {
                    string stmt = functionName.Trim().ToLower() + " --" + optionsText + "-->" + functionName.Trim().ToLower() + uniqueCounter + "_FtpPut[[FtpPut]]";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }
            }

            // Line 4378-4596: Call handling
            if (line.Trim().ToLower().StartsWith("call"))
            {
                // Line 4379-4390: Skip certain calls
                string[] skipCallList = { "rxfuncadd", "sysloadfuncs" };
                bool shouldSkip = false;
                foreach (string skipItem in skipCallList)
                {
                    if (lineLower.Contains(skipItem)) { shouldSkip = true; break; }
                }
                if (shouldSkip) continue;

                string callLine = line.Trim().ToLower().Replace("call ", "");

                // Line 4394-4440: LineOut (file write)
                if (callLine.Contains("lineout"))
                {
                    string filename = (callLine.Replace("lineout", "").Trim() + "\"").Split(",")[0];
                    filename = GetRexVariableValue(filename, assignmentsDict);
                    filename = DecodeQuote(filename, assignmentsDict);
                    if (string.IsNullOrEmpty(filename))
                    {
                        filename = (callLine.Replace("lineout", "").Trim() + "\"").Split("'")[0];
                    }
                    filename = GetRexVariableValue(filename, assignmentsDict);
                    filename = DecodeQuote(filename, assignmentsDict);

                    string writeVariable = "";
                    try
                    {
                        writeVariable = (callLine.Replace("lineout", "").Trim() + "\"").Split(",")[1].Replace("\"", "").Replace("'", "");
                    }
                    catch { }

                    string writeContent = GetRexVariableValue(writeVariable, assignmentsDict);

                    string optionsText;
                    if (!string.IsNullOrEmpty(writeContent) && !writeContent.Contains("---------------") && !writeContent.Contains("substr"))
                        optionsText = "\"write file\ncontent: " + writeContent + "\"";
                    else
                        optionsText = "\"write file\"";

                    filename = filename.Replace("'", "").Replace("\"", "");
                    if (!filename.Contains("\\") && !filename.Contains("/"))
                        filename = filename.ToLower();

                    // Sanitize node ID
                    string itemName = "file" + filename.Trim().ToLower()
                        .Replace("(", "").Replace(")", "").Replace(",", "").Replace(".", "")
                        .Replace(" ", "_").Replace("\\", "_").Replace("/", "_").Replace(":", "_")
                        .TrimEnd('_').Replace("__", "_");

                    string stmt = functionName.Trim().ToLower() + " --" + optionsText + "-->" + itemName + "[/\"" + filename + "\"/]";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }

                // Line 4442-4476: Stream (file operation)
                if (callLine.Contains("stream"))
                {
                    string filename = (callLine.Replace("stream", "").Trim() + "\"").Split(",")[0];
                    filename = GetRexVariableValue(filename, assignmentsDict);
                    if (filename.Contains("'"))
                    {
                        string[] tempParts = filename.Split("'");
                        string temp3 = GetRexVariableValue(tempParts[0], assignmentsDict);
                        filename = temp3 + (tempParts.Length > 1 ? tempParts[1] : "");
                        filename = filename.Replace("'", "").Replace("\"", "");
                    }

                    string fileOperation = "";
                    try
                    {
                        fileOperation = (callLine.Replace("stream", "").Trim() + "\"").Split(",")[2]
                            .Replace("\"", "").Replace("'", "").Trim() + " file";
                    }
                    catch { }

                    filename = filename.Replace("'", "").Replace("\"", "");
                    if (!filename.Contains("\\") && !filename.Contains("/"))
                        filename = filename.ToLower();

                    string itemName = "file" + filename.Trim().ToLower()
                        .Replace("(", "").Replace(")", "").Replace(",", "").Replace(".", "")
                        .Replace(" ", "_").Replace("\\", "_").Replace("/", "_").Replace(":", "_")
                        .TrimEnd('_').Replace("__", "_");

                    string stmt = functionName.Trim().ToLower() + " --" + fileOperation + "-->" + itemName + "[/\"" + filename + "\"/]";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }

                // Line 4478-4490: FtpSetUser
                if (callLine.Contains("ftpsetuser"))
                {
                    string[] tempParts = (callLine.Replace("FtpSetUser", "").Trim() + "\"").Split(",");
                    string temp1 = tempParts[0].Split(" ").Length > 1 ? tempParts[0].Split(" ")[1] : tempParts[0];
                    string temp2 = GetRexVariableValue(temp1, assignmentsDict);
                    temp2 = temp2.Replace("'", "").Replace("\"", "");
                    string operation = "\"host: " + temp2 + "\"";

                    string stmt = functionName.Trim().ToLower() + " --" + operation + "-->" + functionName.Trim().ToLower() + "_FtpSetUser[[FtpSetUser]]";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }

                // Line 4492-4505: SysFileTree
                if (callLine.Contains("sysfiletree"))
                {
                    string toNode = "SysFileTree";
                    string temp1 = (callLine.Replace("sysfiletree", "").Trim() + "\"").Split("'")[0];
                    string optionsText = "";
                    if (!string.IsNullOrEmpty(temp1) && assignmentsDict.ContainsKey(temp1.ToUpper()))
                    {
                        string temp2 = assignmentsDict[temp1.ToUpper()];
                        optionsText = "\"call\n" + temp2 + "\n" + callLine.Replace("sysfiletree", "").Replace(temp1, "").Trim() + "\"";
                    }

                    string safeToNode = toNode.Trim().ToLower().Replace(" ", "_").Replace(",", "_").Replace("(", "_").Replace(")", "_").TrimEnd('_').Replace("__", "_");
                    string stmt = functionName.Trim().ToLower() + " --" + optionsText + "-->" + safeToNode + "(\"" + toNode.Trim().ToLower() + "\")";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }

                // Line 4507-4568: SqlExec
                if (callLine.Contains("sqlexec"))
                {
                    string temp1 = DecodeQuote(callLine, assignmentsDict);
                    temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                    string itemName = functionName.Trim().ToLower() + "_sqlexec" + uniqueCounter;

                    // Try SQL extraction
                    var sqlResult = SqlParseHelper.FindSqlStatementInDb2Command(line);

                    if (sqlResult.SqlOperation != null && sqlResult.SqlTableNames.Count > 0)
                    {
                        SqlParseHelper.WriteSqlTableNodes(mmdWriter, sqlResult, functionName.Trim().ToLower(), sqlTableArray);
                        continue;
                    }

                    // No SQL - regular SqlExec
                    temp1 = temp1.Trim().ToLower().Replace("sqlexec", "'").Trim();
                    string stmt = functionName.Trim().ToLower() + " --database command-->" + itemName + "(\"DB2 SqlExec Command\n" + temp1 + "\")";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }

                // Line 4570-4589: REXX script call with quote
                if (callLine.Contains("'"))
                {
                    string temp1 = DecodeQuote(callLine, assignmentsDict);
                    temp1 = GetRexDecodedConcat(temp1, assignmentsDict);
                    string itemName = functionName.Trim().ToLower() + "_rexx2run" + uniqueCounter;
                    string rexFilename = temp1.Trim().ToLower() + ".rex";
                    if (rexFilename.Contains(" "))
                        rexFilename = temp1.Trim().ToLower().Split(" ")[0] + ".rex";

                    htmlCallList.Add(rexFilename);
                    string stmt = functionName.Trim().ToLower() + " --start rexx script-->" + itemName + "[[" + rexFilename + "]]";
                    WriteRexMmd(mmdWriter, stmt);

                    string rLink = "./" + rexFilename + ".html";
                    stmt = "click " + itemName + " \"" + rLink + "\" \"" + itemName + "\" _blank";
                    WriteRexMmd(mmdWriter, stmt);
                    stmt = "style " + itemName + " stroke:dark-blue,stroke-width:4px";
                    WriteRexMmd(mmdWriter, stmt);
                    continue;
                }

                // Line 4591-4595: Generic call
                string genericToNode = callLine.Replace("\"", "").Replace("'", "").Trim();
                string genericItemName = genericToNode.Trim().ToLower().Replace(" ", "_").Replace(",", "_").Replace("(", "_").Replace(")", "_").TrimEnd('_').Replace("__", "_");
                string genericStmt = functionName.Trim().ToLower() + " --call-->" + genericItemName + "(\"" + genericToNode.Trim().ToLower() + "\")";
                WriteRexMmd(mmdWriter, genericStmt);
                continue;
            }

            // Line 4598-4609: SysFileDelete
            if (lineLower.Contains("sysfiledelete"))
            {
                int pos = lineLower.IndexOf("sysfiledelete");
                string temp = line.Substring(pos + 13).Replace("(", "").Replace(")", "").Replace("\"", "").Replace("'", "").Trim();
                temp = GetRexVariableValue(temp, assignmentsDict);
                temp = temp.Replace("(", "").Replace(")", "").Replace("\"", "").Replace("'", "").Trim();

                string toNode = functionName.Trim().ToLower() + "SysFileDelete" + uniqueCounter;
                string stmt = functionName.Trim().ToLower() + " --rexx command-->" + toNode + "(\"SysFileDelete\n" + temp.Trim() + "\")";
                WriteRexMmd(mmdWriter, stmt);
                continue;
            }

            // Line 4610-4617: Log unhandled lines
            if (!(line.Trim().EndsWith(":") || line.Contains("=") || lineLower.StartsWith("say")
                || lineLower.StartsWith("\":") || lineLower.StartsWith("if ") || lineLower.StartsWith("parse ")))
            {
                Logger.LogMessage($"Unhandled line in module: {baseFileName}, in function: {functionName}, at line: {line.Trim()}", LogLevel.WARN);
            }
        }
    }

    #endregion

    #region Get-RexMetaData (lines 4663-4838)

    /// <summary>
    /// Generates metadata and HTML output for the REXX file.
    /// Converted line-by-line from Get-RexMetaData (lines 4663-4838)
    /// </summary>
    private static void GetRexMetaData(
        string tmpRootFolder,
        string baseFileName,
        string outputFolder,
        string[] completeFileContent,
        string inputDbFileFolder,
        bool clientSideRender,
        MermaidWriter mmdWriter,
        List<string> htmlCallListCbl,
        List<string> htmlCallList,
        ref bool errorOccurred,
        string sourceFile = "",
        bool generateHtml = false)
    {
        string title = "";
        string htmlCreatedDateTime = "";
        var commentArray = new List<string>();
        var cblArray = new List<string>();
        var scriptArray = new List<string>();
        string htmlUseSql = "";
        string htmlUseFtp = "";

        try
        {
            // Line 4669-4674: Extract title from first non-empty line
            foreach (string line in completeFileContent)
            {
                if (Regex.IsMatch(line, "[A-Za-z]"))
                {
                    title = line.Replace("/*", "").Replace("*/", "").Trim();
                    break;
                }
            }

            // Line 4675-4725: Parse changelog comments
            bool startCommentFound = false;
            var rawComments = new List<string>();
            foreach (string line in completeFileContent)
            {
                if ((Regex.IsMatch(line, @"(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])") ||
                     Regex.IsMatch(line, @"(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}") ||
                     Regex.IsMatch(line, @"(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])"))
                    && line.Contains("/*"))
                {
                    startCommentFound = true;
                }
                if (startCommentFound && line.Contains("*/"))
                    rawComments.Add(line.Replace("*/", "").Replace("/*", "").Trim());
                if (startCommentFound && !line.Contains("/*"))
                    break;
            }

            // Process comments into HTML table rows (same logic as BatParser)
            string newComment = "";
            foreach (string item in rawComments)
            {
                if (item.Trim().Contains("-----------") || item.Trim().Contains("**********") || item.Trim().Contains("=========="))
                    break;

                if (Regex.IsMatch(item, @"(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])") ||
                    Regex.IsMatch(item, @"(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}") ||
                    Regex.IsMatch(item, @"(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])"))
                {
                    if (newComment.Length > 0)
                    {
                        newComment = newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                        string[] temp = newComment.Split(" ");
                        if (string.IsNullOrEmpty(htmlCreatedDateTime))
                            htmlCreatedDateTime = temp[0];
                        string tempComment = "<tr><td>" + temp[0] + "</td><td>" + (temp.Length > 1 ? temp[1] : "") + "</td><td>";
                        string temp2 = newComment.Replace(temp[0] + " " + (temp.Length > 1 ? temp[1] : ""), "").Trim();
                        commentArray.Add((tempComment + temp2 + "</td></tr>").Trim());
                    }
                    newComment = item;
                }
                else
                {
                    newComment += " " + item.Trim();
                }
            }
            if (newComment.Length > 0)
            {
                newComment = newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                string[] temp = newComment.Split(" ");
                string tempComment = "<tr><td>" + temp[0] + "</td><td>" + (temp.Length > 1 ? temp[1] : "") + "</td><td>";
                string temp2 = newComment.Replace(temp[0] + " " + (temp.Length > 1 ? temp[1] : ""), "").Trim();
                commentArray.Add((tempComment + temp2 + "</td></tr>").Trim());
            }

            // Line 4727-4766: Load modul.csv for COBOL program metadata
            string modulCsvPath = Path.Combine(inputDbFileFolder, "modul.csv");
            System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
            if (File.Exists(modulCsvPath))
            {
                string[] csvLines = SourceFileCache.GetLines(modulCsvPath) ?? File.ReadAllLines(modulCsvPath, Encoding.UTF8);
                foreach (string cblItem in htmlCallListCbl)
                {
                    string cblUpper = cblItem.Replace(".cbl", "").ToUpper();
                    string cblSystem = "N/A", cblDesc = "N/A", cblType = "N/A";

                    foreach (string csvLine in csvLines)
                    {
                        string[] fields = csvLine.Split(';');
                        if (fields.Length > 5 && CsvClean(fields[2]).Contains(cblUpper))
                        {
                            cblSystem = CsvClean(fields[1]);
                            cblDesc = CsvClean(fields[3]);
                            string typeCode = CsvClean(fields[4]);
                            cblType = typeCode switch
                            {
                                "B" => "B - Batchprogram",
                                "H" => "H - Main user interface",
                                "S" => "S - Webservice",
                                "V" => "V - Validation module for user interface",
                                "A" => "A - Common module",
                                "F" => "F - Search module for user interface",
                                _ => typeCode
                            };
                            break;
                        }
                    }

                    string link = "<a href=\"./" + cblItem.Trim() + ".html\">" + cblItem.Trim() + "</a>";
                    cblArray.Add("<tr><td>" + link + "</td><td>" + cblDesc + "</td><td>" + cblType + "</td><td>" + cblSystem + "</td></tr>");
                }
            }

            // Line 4768-4773: Build script call list
            foreach (string item in htmlCallList)
            {
                string link = "<a href=\"./" + item.Trim() + ".html\">" + item.Trim() + "</a>";
                scriptArray.Add("<tr><td>" + link + "</td></tr>");
            }

            // Line 4777-4786: Check usage flags
            if (completeFileContent.Any(l => l.ToLower().Contains("sqlexec")))
                htmlUseSql = "checked";
            if (completeFileContent.Any(l => l.ToLower().Contains("ftpsetuser")))
                htmlUseFtp = "checked";
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GetRexMetaData: {ex.Message}", LogLevel.ERROR, ex);
            errorOccurred = true;
        }

        // Line 4796-4836: Generate HTML file
        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        string templatePath = Path.Combine(outputFolder, "_templates");
        string mmdTemplateFilename = Path.Combine(templatePath, "rexmmdtemplate.html");
        string myDescription = "AutoDoc Flowchart - Object Rexx Script - " + baseFileName.ToLower();

        string templateContent = "";
        if (File.Exists(mmdTemplateFilename))
            templateContent = File.ReadAllText(mmdTemplateFilename, Encoding.UTF8);
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "rexmmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                templateContent = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else
            {
                Logger.LogMessage($"Template not found: {mmdTemplateFilename}", LogLevel.ERROR);
                return;
            }
        }

        try
        {
            string doc = ParserBase.SetAutodocTemplate(templateContent, outputFolder);
            doc = doc.Replace("[title]", myDescription);
            doc = doc.Replace("[desc]", title);
            doc = doc.Replace("[generated]", DateTime.Now.ToString());
            doc = doc.Replace("[type]", "Object Rexx Script");
            doc = doc.Replace("[usesql]", htmlUseSql);
            doc = doc.Replace("[useftp]", htmlUseFtp);
            doc = doc.Replace("[created]", htmlCreatedDateTime);
            doc = doc.Replace("[changelog]", string.Join("\n", commentArray));
            doc = doc.Replace("[calllist]", string.Join("\n", scriptArray));
            doc = doc.Replace("[calllistcbl]", string.Join("\n", cblArray));
            doc = doc.Replace("[diagram]", "./" + baseFileName + ".flow.svg");
            doc = doc.Replace("[sourcefile]", baseFileName.ToLower());
            doc = doc.Replace("[githistory]", GitStatsService.RenderHtmlRows(GitStatsService.GetStats(sourceFile, Path.GetDirectoryName(sourceFile) ?? "")));

            if (clientSideRender)
            {
                string flowMmdContent = mmdWriter.GetContent();
                doc = doc.Replace("[flowmmd_content]", flowMmdContent);
                doc = doc.Replace("[sequencemmd_content]", "");
            }

            if (generateHtml)
            {
                File.WriteAllText(htmlFilename, doc, Encoding.UTF8);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error generating HTML: {ex.Message}", LogLevel.ERROR, ex);
            errorOccurred = true;
        }

        // Write JSON result alongside HTML
        try
        {
            var jsonScripts = new List<ScriptRef>();
            foreach (string s in scriptArray)
            {
                var m = Regex.Match(s, @"href=""([^""]+)"">([^<]+)</a>");
                if (m.Success) jsonScripts.Add(new ScriptRef { Name = m.Groups[2].Value, Link = m.Groups[1].Value });
            }
            var jsonPrograms = new List<SubprogramRef>();
            foreach (string s in cblArray)
            {
                var m = Regex.Match(s, @"href=""([^""]+)"">([^<]+)</a></td><td>([^<]*)</td><td>([^<]*)</td><td>([^<]*)");
                if (m.Success) jsonPrograms.Add(new SubprogramRef { Module = m.Groups[2].Value, Description = m.Groups[3].Value, Type = m.Groups[4].Value, System = m.Groups[5].Value, Link = m.Groups[1].Value });
            }
            var jsonChangelog = new List<ChangeLogEntry>();
            foreach (string s in commentArray)
            {
                var m = Regex.Match(s, @"<td>([^<]*)</td><td>([^<]*)</td><td>([^<]*)");
                if (m.Success) jsonChangelog.Add(new ChangeLogEntry { Date = m.Groups[1].Value, User = m.Groups[2].Value, Comment = m.Groups[3].Value });
            }

            var rexResult = new RexResult
            {
                Type = "REX",
                FileName = baseFileName,
                Title = "AutoDoc Flowchart - Object Rexx Script - " + baseFileName.ToLower(),
                Description = title,
                GeneratedAt = DateTime.Now.ToString("o"),
                SourceFile = baseFileName.ToLower(),
                Metadata = new RexMetadata
                {
                    UsesSql = htmlUseSql == "checked",
                    UsesFtp = htmlUseFtp == "checked",
                    Created = htmlCreatedDateTime
                },
                Diagrams = new DiagramData
                {
                    FlowMmd = mmdWriter.GetContent()
                },
                CalledScripts = jsonScripts,
                CalledPrograms = jsonPrograms,
                ChangeLog = jsonChangelog
            };
            rexResult.GitHistory = GitStatsService.GetStats(sourceFile, Path.GetDirectoryName(sourceFile) ?? "");
            JsonResultWriter.WriteResult(rexResult, outputFolder, baseFileName);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing JSON result for {baseFileName}: {ex.Message}", LogLevel.WARN);
        }
    }

    #endregion

    #region Start-RexParse (lines 4912-5239)

    /// <summary>
    /// Main entry point for Object Rexx file parsing.
    /// Converted line-by-line from Start-RexParse (lines 4912-5239)
    /// </summary>
    public static string? StartRexParse(
        string sourceFile,
        bool show = false,
        string outputFolder = "",
        bool cleanUp = true,
        string tmpRootFolder = "",
        string srcRootFolder = "",
        bool clientSideRender = false,
        bool saveMmdFiles = false,
        bool generateHtml = false)
    {
        // Default folders
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder))
            outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder))
            tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        if (string.IsNullOrEmpty(srcRootFolder))
            srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

        // Line 4966: Initialize
        string baseFileName = Path.GetFileName(sourceFile);
        Logger.LogMessage($"Starting parsing of filename: {sourceFile}", LogLevel.INFO);

        // Line 4971-4980: Validate filename
        if (baseFileName.Contains(" "))
        {
            Logger.LogMessage($"Filename is not valid. Contains spaces: {baseFileName}", LogLevel.ERROR);
            return null;
        }
        if (!baseFileName.ToLower().Contains(".rex"))
        {
            Logger.LogMessage($"Filetype is not valid for parsing of Object-Rexx script (.rex): {baseFileName}", LogLevel.ERROR);
            return null;
        }

        // Line 4983-4991: Initialize variables
        DateTime startTime = DateTime.Now;
        string mmdFilename = Path.Combine(outputFolder, baseFileName + ".flow.mmd");
        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        bool errorOccurred = false;
        var sqlTableArray = new List<string>();
        string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");

        Logger.LogMessage($"Started for: {baseFileName}", LogLevel.INFO);

        // Line 5001-5011: Initialize MMD
        string mmdHeader = "%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%\nflowchart LR";
        var mmdWriter = new MermaidWriter(clientSideRender, mmdFilename, mmdHeader);

        // Line 5013-5014
        string programName = Path.GetFileName(sourceFile).ToLower();

        // Line 5016-5029: Read source file
        string[] fileContentOriginal;
        string[] completeFileContent;

        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);

        if (File.Exists(sourceFile))
        {
            fileContentOriginal = SourceFileCache.GetLines(sourceFile) ?? File.ReadAllLines(sourceFile, Encoding.GetEncoding(1252));
            completeFileContent = (string[])fileContentOriginal.Clone();

            // Remove block comments
            string test = string.Join("¤", fileContentOriginal);
            test = Regex.Replace(test, @"/\*.*?\*/", "", RegexOptions.Singleline);
            fileContentOriginal = test.Split("¤");
        }
        else
        {
            Logger.LogMessage($"File not found: {sourceFile}", LogLevel.ERROR);
            return null;
        }

        // Line 5035-5047: Extract relevant code using Select-String patterns
        string[] patterns = { @"^.*:", @"call\s*", "SysFileDelete", "'RUN", "'REXX", "'START ", "'DB2",
                              "'COPY", "'REN", "FtpLogoff", "ftpput", "ftpget", "ftpdel", "if " };

        var workContent2 = new List<MatchResult>();
        for (int i = 0; i < fileContentOriginal.Length; i++)
        {
            string line = fileContentOriginal[i];
            foreach (string pattern in patterns)
            {
                if (Regex.IsMatch(line, pattern, RegexOptions.IgnoreCase))
                {
                    workContent2.Add(new MatchResult { LineNumber = i + 1, Line = line, Pattern = pattern });
                    break;
                }
            }
        }

        var workContent = new List<MatchResult>();
        if (workContent2.Count > 0)
        {
            workContent.Add(new MatchResult { LineNumber = 1, Line = "__MAIN__:", Pattern = @"^.*:" });
        }
        workContent.AddRange(workContent2);

        // Line 5050-5056: Create list of all functions
        var functions = new List<string>();
        if (workContent.Count > 0)
            functions.Add("__MAIN__");

        foreach (string line in fileContentOriginal)
        {
            // Lines ending with ':'  are function labels in REXX
            if (Regex.IsMatch(line.Trim(), @"^.*:$"))
            {
                string funcName = line.Trim().Replace(":", "").ToUpper();
                if (!string.IsNullOrEmpty(funcName) && !functions.Contains(funcName))
                    functions.Add(funcName);
            }
        }

        // Line 5058-5068: Create assignments dictionary
        var assignmentsDict = new Dictionary<string, string>();
        foreach (string line in fileContentOriginal)
        {
            if (line.Contains("=") && !Regex.IsMatch(line, @"\bif\b", RegexOptions.IgnoreCase))
            {
                string[] temp = line.Split('=');
                if (temp.Length >= 2)
                {
                    string key = temp[0].Trim().ToUpper();
                    try { assignmentsDict[key] = temp[1].Trim().Replace("\"", "'"); } catch { }
                }
            }
        }

        // Line 5070-5080: Initialize lists
        var htmlCallListCbl = new List<string>();
        var htmlCallList = new List<string>();
        string currentParticipant = "";
        string currentFunctionName = "";
        int loopCounter = 0;
        string previousParticipant = "";
        var functionCodeExceptLoopCode = new List<MatchResult>();
        var loopLevel = new List<string>();
        var loopNodeContent = new List<string>();
        var loopCode = new List<List<MatchResult>>();
        List<string>? functionCode = null;

        // Line 5082-5174: Main processing loop
        foreach (var lineObject in workContent)
        {
            string line = lineObject.Line;
            previousParticipant = currentFunctionName;

            // Line 5093: Check if function
            if (TestRexFunction(line, functions))
            {
                if (functionCodeExceptLoopCode.Count > 0)
                {
                    loopCounter = 0;
                    NewRexNodes(functionCodeExceptLoopCode, fileContentOriginal, previousParticipant,
                        mmdWriter, baseFileName, functions, assignmentsDict,
                        sqlTableArray, htmlCallListCbl, htmlCallList);
                }

                // Line 5099-5101: Extract function name (before colon)
                int pos = line.IndexOf(":");
                currentParticipant = (pos >= 0) ? line.Substring(0, pos).Trim() : line.Trim();
                currentFunctionName = currentParticipant.Trim();
                var functionCodeRaw = FindRexFunctionCode(workContent, currentParticipant, functions);
                functionCode = functionCodeRaw;

                // Reset loop tracking
                loopLevel = new List<string>();
                loopNodeContent = new List<string>();
                loopCode = new List<List<MatchResult>>();
                functionCodeExceptLoopCode = new List<MatchResult>();

                // Line 5110-5118: Handle program name to initial function
                if (previousParticipant.Length == 0 && currentParticipant.Length > 0)
                {
                    string stmt = programName.Trim().ToLower() + "[[" + programName.Trim().ToLower() + "]]"
                        + " --initiated-->" + currentParticipant.Trim().ToLower()
                        + "(" + currentParticipant.Trim().ToLower() + ")";
                    WriteRexMmd(mmdWriter, stmt);

                    stmt = "style " + programName.Trim().ToLower() + " stroke:red,stroke-width:4px";
                    WriteRexMmd(mmdWriter, stmt);

                    string link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + baseFileName.ToLower();
                    stmt = "click " + programName.Trim().ToLower() + " \"" + link + "\" \"" + programName.Trim().ToLower() + "\" _blank";
                    WriteRexMmd(mmdWriter, stmt);
                }
            }

            if (functionCode == null || functionCode.Count == 0)
                continue;

            bool skipLine = false;

            // Line 5128-5158: Loop handling (DO WHILE/UNTIL, END)
            string lineTrimLower = line.Trim().ToLower();
            if (lineTrimLower.Contains("do ") && (lineTrimLower.Contains(" while") || lineTrimLower.Contains(" until")))
            {
                loopCounter++;
                string fromNode, toNode;
                if (loopCounter > 1 && loopLevel.Count >= loopCounter - 1)
                {
                    fromNode = loopLevel[loopCounter - 2];
                    toNode = loopLevel[loopCounter - 2] + loopCounter + "((" + loopLevel[loopCounter - 2] + loopCounter + "))";
                    loopLevel.Add(currentParticipant + "-loop" + loopCounter);
                }
                else
                {
                    fromNode = currentParticipant;
                    toNode = currentParticipant + "-loop((" + currentParticipant + "-loop))";
                    loopLevel.Add(currentParticipant + "-loop");
                }
                loopNodeContent.Add(toNode);
                loopCode.Add(new List<MatchResult>());
                string stmt = fromNode + "--\"call\"-->" + toNode;
                WriteRexMmd(mmdWriter, stmt);
                skipLine = true;
            }
            else if (loopCounter > 0 && lineTrimLower.StartsWith("end"))
            {
                if (loopCode.Count >= loopCounter)
                {
                    NewRexNodes(loopCode[loopCounter - 1], fileContentOriginal,
                        loopLevel[loopCounter - 1], mmdWriter, baseFileName, functions,
                        assignmentsDict, sqlTableArray, htmlCallListCbl, htmlCallList);

                    loopLevel.RemoveAt(loopCounter - 1);
                    loopNodeContent.RemoveAt(loopCounter - 1);
                    loopCode.RemoveAt(loopCounter - 1);
                    loopCounter--;
                }
                skipLine = true;
            }

            // Line 5160-5173: Accumulate lines
            if (!skipLine)
            {
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    loopCode[loopCounter - 1].Add(lineObject);
                }
                else
                {
                    functionCodeExceptLoopCode.Add(lineObject);
                }
            }
        }

        // Line 5178-5179: Generate nodes for last function
        if (functionCodeExceptLoopCode.Count > 0)
        {
            NewRexNodes(functionCodeExceptLoopCode, fileContentOriginal, currentFunctionName,
                mmdWriter, baseFileName, functions, assignmentsDict,
                sqlTableArray, htmlCallListCbl, htmlCallList);
        }

        // Line 5182: Generate source code links
        NewRexMmdLinks(mmdWriter, baseFileName, workContent, functions);

        // Line 5185: Generate execution path diagram
        GetRexExecutionPathDiagram(mmdWriter, srcRootFolder, baseFileName);

        // Line 5188-5190: Generate SVG (skip when client-side rendering)
        if (!clientSideRender)
        {
            ExecutionPathHelper.GenerateSvgFile(mmdFilename);
        }

        // Line 5193-5194: Generate metadata and HTML
        if (!errorOccurred)
        {
            GetRexMetaData(tmpRootFolder, baseFileName, outputFolder, completeFileContent,
                inputDbFileFolder, clientSideRender, mmdWriter, htmlCallListCbl, htmlCallList, ref errorOccurred, sourceFile, generateHtml);
        }

        // Line 5205-5211: Save MMD files
        if (saveMmdFiles)
        {
            string flowMmdOutputPath = Path.Combine(outputFolder, baseFileName + ".mmd");
            File.WriteAllLines(flowMmdOutputPath, mmdWriter.GetContentList(), Encoding.UTF8);
            Logger.LogMessage($"Saved flow MMD file: {flowMmdOutputPath}", LogLevel.INFO);
        }

        // Line 5213-5238: Log result and return
        DateTime endTime = DateTime.Now;
        TimeSpan timeDiff = endTime - startTime;
        string dummyFile = Path.Combine(outputFolder, baseFileName + ".err");
        string jsonFilePath = Path.Combine(outputFolder, baseFileName + ".json");
        bool htmlWasGenerated = File.Exists(htmlFilename) || File.Exists(jsonFilePath);

        if (htmlWasGenerated)
        {
            if (File.Exists(dummyFile))
                try { File.Delete(dummyFile); } catch { }

            if (errorOccurred)
            {
                Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
                Logger.LogMessage($"Completed with warnings: {baseFileName}", LogLevel.WARN);
            }
            else
            {
                Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
                Logger.LogMessage($"Completed successfully: {baseFileName}", LogLevel.INFO);
            }
            return htmlFilename;
        }
        else
        {
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            Logger.LogMessage($"Failed - HTML not generated: {sourceFile}", LogLevel.ERROR);
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            File.WriteAllText(dummyFile, $"Error: HTML file was not generated for {baseFileName}");
            return null;
        }
    }

    #endregion
}
