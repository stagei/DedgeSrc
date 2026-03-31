using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace AutoDocNew.Core;

/// <summary>
/// Exports DB2 system catalog metadata to CSV files.
/// Converted from HandleCobdokExport (lines 1848-1962), ExportTableContentToFile (923-1070),
/// and ConvertFromAnsi1252ToUtf8 (901-922) in AutoDocBatchRunner.ps1.
/// </summary>
public static class CobdokExportService
{
    private const string SchemaFilter = "('DBM','HST','CRM','LOG','TV')";

    /// <summary>
    /// Export cobdok and fkavdnt DB2 metadata to CSV files, then convert from ANSI-1252 to UTF-8.
    /// </summary>
    public static void Export(string cobdokFolder)
    {
        Logger.LogMessage("Exporting tables from cobdok and fkavdnt databases", LogLevel.INFO);

        var commands = new List<string>();

        // Delete existing CSVs
        commands.Add($"del \"{cobdokFolder}\\*.csv\" /F /Q");

        // ── COBDOK Database (legacy COBOL metadata) ──
        commands.Add("db2 connect to cobdok");
        foreach (string t in new[] { "call", "cobdok_meny", "copy", "copyset", "delsystem", "modul", "modkom", "sqlxtab", "tiltp_log" })
            commands.Add(BuildExportCommand(t, cobdokFolder));

        // ── FKAVDNT Database (SQL table metadata) ──
        commands.Add("db2 connect to fkavdnt");
        foreach (string t in new[] { "tables", "columns", "indexes", "indexcoluse", "tabconst", "keycoluse", "references", "checks", "triggers", "packagedep", "routinedep" })
            commands.Add(BuildExportCommand(t, cobdokFolder));

        commands.Add("exit");

        // Write and execute the script
        string scriptPath = Path.Combine(cobdokFolder, "ExportTableContentToFile.cmd");
        File.WriteAllLines(scriptPath, commands, Encoding.Default);

        Logger.LogMessage($"Running db2cmd.exe with script: {scriptPath}", LogLevel.INFO);
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "db2cmd.exe",
                Arguments = $"-w \"{scriptPath}\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            using var process = Process.Start(psi);
            if (process != null)
            {
                process.WaitForExit(600_000); // 10 min timeout
                Logger.LogMessage($"db2cmd.exe exited with code {process.ExitCode}", LogLevel.INFO);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"db2cmd.exe failed: {ex.Message}", LogLevel.ERROR, ex);
        }

        // Convert all exported files from ANSI-1252 to UTF-8
        string[] filesToConvert = {
            "call", "cobdok_meny", "copy", "copyset", "delsystem", "modul", "modkom", "sqlxtab", "tiltp_log",
            "tables", "columns", "indexes", "indexcoluse", "tabconst", "keycoluse", "references", "checks",
            "triggers", "packagedep", "routinedep"
        };
        foreach (string name in filesToConvert)
            ConvertFromAnsi1252ToUtf8(name, cobdokFolder);

        Logger.LogMessage($"Exported {filesToConvert.Length} metadata files to {cobdokFolder}", LogLevel.INFO);
    }

    /// <summary>
    /// Build the db2 export command for a given table type.
    /// Converted from ExportTableContentToFile (lines 923-1070).
    /// </summary>
    private static string BuildExportCommand(string tableName, string folderPath)
    {
        string file = Path.Combine(folderPath, tableName + ".csv");
        string prefix = $"db2 export to {file} of del modified by coldel; ";

        return tableName switch
        {
            "tables" => prefix +
                $"SELECT TRIM(tabschema), TRIM(tabname), TRIM(COALESCE(remarks,'')), TRIM(type), " +
                $"alter_time, create_time, COALESCE(card,-1), COALESCE(npages,-1), colcount, " +
                $"TRIM(COALESCE(tbspace,'')), parents, children, keycolumns " +
                $"FROM syscat.tables WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname",

            "columns" => prefix +
                $"SELECT TRIM(tabschema), TRIM(tabname), TRIM(colname), colno, TRIM(typeschema), " +
                $"TRIM(typename), length, scale, TRIM(COALESCE(remarks,'')), TRIM(nulls), " +
                $"TRIM(COALESCE(CAST(default AS VARCHAR(254)),'')), TRIM(identity), TRIM(generated) " +
                $"FROM syscat.columns WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname, colno",

            "indexes" => prefix +
                $"SELECT TRIM(indschema), TRIM(indname), TRIM(tabschema), TRIM(tabname), " +
                $"TRIM(colnames), TRIM(uniquerule), colcount, TRIM(indextype), " +
                $"COALESCE(nleaf,-1), nlevels, COALESCE(fullkeycard,-1), create_time, " +
                $"TRIM(COALESCE(remarks,'')) " +
                $"FROM syscat.indexes WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname, indname",

            "indexcoluse" => prefix +
                $"SELECT TRIM(i.indschema), TRIM(i.indname), TRIM(i.tabschema), TRIM(i.tabname), " +
                $"TRIM(c.colname), c.colseq, TRIM(c.colorder) " +
                $"FROM syscat.indexes i JOIN syscat.indexcoluse c " +
                $"ON TRIM(i.indschema) = TRIM(c.indschema) AND TRIM(i.indname) = TRIM(c.indname) " +
                $"WHERE i.tabschema IN {SchemaFilter} ORDER BY i.tabschema, i.tabname, c.indname, c.colseq",

            "tabconst" => prefix +
                $"SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), TRIM(type), " +
                $"TRIM(enforced), TRIM(COALESCE(remarks,'')) " +
                $"FROM syscat.tabconst WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname, constname",

            "keycoluse" => prefix +
                $"SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), TRIM(colname), colseq " +
                $"FROM syscat.keycoluse WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname, constname, colseq",

            "references" => prefix +
                $"SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), " +
                $"TRIM(reftabschema), TRIM(reftabname), TRIM(refkeyname), " +
                $"TRIM(fk_colnames), TRIM(pk_colnames), TRIM(deleterule), TRIM(updaterule), " +
                $"colcount, create_time " +
                $"FROM syscat.references WHERE tabschema IN {SchemaFilter} " +
                $"OR reftabschema IN {SchemaFilter} ORDER BY tabschema, tabname, constname",

            "checks" => prefix +
                $"SELECT TRIM(constname), TRIM(tabschema), TRIM(tabname), create_time, " +
                $"TRIM(COALESCE(CAST(text AS VARCHAR(1000)),'')) " +
                $"FROM syscat.checks WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname, constname",

            "triggers" => prefix +
                $"SELECT TRIM(trigschema), TRIM(trigname), TRIM(tabschema), TRIM(tabname), " +
                $"TRIM(trigtime), TRIM(trigevent), TRIM(granularity), TRIM(valid), create_time, " +
                $"TRIM(COALESCE(remarks,'')) " +
                $"FROM syscat.triggers WHERE tabschema IN {SchemaFilter} ORDER BY tabschema, tabname, trigname",

            "packagedep" => prefix +
                $"SELECT TRIM(pkgschema), TRIM(pkgname), TRIM(btype), TRIM(bschema), TRIM(bname) " +
                $"FROM syscat.packagedep WHERE bschema IN {SchemaFilter} AND btype = 'T' " +
                $"ORDER BY bschema, bname, pkgschema, pkgname",

            "routinedep" => prefix +
                $"SELECT TRIM(routineschema), TRIM(routinename), TRIM(btype), TRIM(bschema), TRIM(bname) " +
                $"FROM syscat.routinedep WHERE bschema IN {SchemaFilter} AND btype = 'T' " +
                $"ORDER BY bschema, bname, routineschema, routinename",

            // Legacy cobdok tables (call, modul, copy, etc.)
            _ => prefix + $"select * from dbm.{tableName}"
        };
    }

    /// <summary>
    /// Convert a CSV file from Windows-1252 (ANSI) encoding to UTF-8.
    /// Converted from ConvertFromAnsi1252ToUtf8 (lines 901-922).
    /// </summary>
    private static void ConvertFromAnsi1252ToUtf8(string tableName, string folderPath)
    {
        string filePath = Path.Combine(folderPath, tableName + ".csv");
        if (!File.Exists(filePath))
        {
            Logger.LogMessage($"File {filePath} does not exist", LogLevel.WARN);
            return;
        }

        try
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            var ansi1252 = Encoding.GetEncoding(1252);
            string content = File.ReadAllText(filePath, ansi1252);
            File.WriteAllText(filePath, content, new UTF8Encoding(false));
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error converting {filePath} to UTF-8: {ex.Message}", LogLevel.WARN, ex);
        }
    }
}
