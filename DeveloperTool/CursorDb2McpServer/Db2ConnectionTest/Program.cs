using System.Data;
using DedgeCommon;

// Minimal DB2 connection test for FKMTST - verifies DedgeCommon/DedgeDbHandler works
// SELECT: CURRENT SERVER, CURRENT USER from SYSIBM.SYSDUMMY1

const string VerifySql = "SELECT CURRENT SERVER AS DB, CURRENT USER AS USR FROM SYSIBM.SYSDUMMY1";

try
{
    // DedgeCommon requires DedgeNLog and FkFolders before DedgeDbHandler.Create
    _ = new FkFolders("Db2ConnectionTest");
    DedgeNLog.SetFileLogLevels(DedgeNLog.LogLevel.Info, DedgeNLog.LogLevel.Fatal);
    DedgeNLog.SetConsoleLogLevels(DedgeNLog.LogLevel.Info, DedgeNLog.LogLevel.Fatal);

    // FKMTST = FKM / TST
    var connectionKey = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.TST);

    using var dbHandler = DedgeDbHandler.Create(connectionKey);
    DataTable table = dbHandler.ExecuteQueryAsDataTable(VerifySql);

    if (table.Rows.Count == 0)
    {
        Console.WriteLine("JOB_FAILED|No rows returned");
        DedgeNLog.Error("Query returned no rows");
        Environment.Exit(1);
    }

    var row = table.Rows[0];
    string db = row["DB"]?.ToString()?.Trim() ?? "";
    string usr = row["USR"]?.ToString()?.Trim() ?? "";

    string msg = $"DB2 connection OK: Server={db}, User={usr}";
    Console.WriteLine(msg);
    Console.WriteLine("JOB_COMPLETED");
    DedgeNLog.Info(msg);

    Environment.Exit(0);
}
catch (Exception ex)
{
    Console.WriteLine($"JOB_FAILED|{ex.Message}");
    Console.Error.WriteLine(ex.ToString());
    DedgeNLog.Error(ex, "DB2 connection test failed");
    Environment.Exit(1);
}
