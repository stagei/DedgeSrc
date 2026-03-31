using System.Data;
using System.Data.Common;
using Microsoft.Data.Sqlite;

namespace DbExplorer.Data.Providers.SQLite;

/// <summary>
/// Minimal DbDataAdapter for Microsoft.Data.Sqlite (which does not ship SqliteDataAdapter).
/// Used by IConnectionManager.CreateDataAdapter for Fill(DataTable) scenarios.
/// </summary>
internal sealed class SqliteDataAdapterWrapper : DbDataAdapter
{
    public SqliteDataAdapterWrapper(SqliteCommand selectCommand)
    {
        SelectCommand = selectCommand;
    }

    protected override int Fill(DataTable[] dataTables, int startRecord, int maxRecords, IDbCommand? command, CommandBehavior behavior)
    {
        if (command is not SqliteCommand sqliteCommand || dataTables == null || dataTables.Length == 0)
            return 0;
        using var reader = sqliteCommand.ExecuteReader(behavior);
        dataTables[0].Load(reader);
        return dataTables[0].Rows.Count;
    }
}
