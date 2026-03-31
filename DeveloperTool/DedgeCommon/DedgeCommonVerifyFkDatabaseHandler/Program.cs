using DedgeCommon;
using System.Data;
using System.Text;
using System.Threading.Tasks;
using static DedgeCommon.DedgeConnection;

namespace VerifyFunctionality
{
    internal class Program
    {
        private static readonly DedgeConnection.ConnectionKey _ConnectionKey =
            new DedgeConnection.ConnectionKey(
                    DedgeConnection.FkApplication.FKM,
                    DedgeConnection.FkEnvironment.TST  // Changed from PRD to TST to match test database
                );
        private const string TestEmail = "geir.helge.starholm@Dedge.no";
        private const string TestMobile = "+4797188358";
        private static readonly string TestUser = Environment.UserName;


        static async Task Main(string[] args)
        {
            try
            {

                DedgeNLog.Info($"Starting database handler verification");
                //DedgeNLog.SetFileLogLevels(DedgeNLog.LogLevel.Debug, DedgeNLog.LogLevel.Fatal);
                //DedgeNLog.SetConsoleLogLevels(DedgeNLog.LogLevel.Debug, DedgeNLog.LogLevel.Fatal);
                DedgeNLog.EnableDatabaseLogging(_ConnectionKey);
                DedgeNLog.StartOperation("InsertTestData", 7);

                //var test1 = DedgeConnection.GetConnectionsForApplications(new List<DedgeConnection.FkApplication>() { DedgeConnection.FkApplication.FKM });
                //foreach (var item in test1)
                //{
                //    DedgeNLog.Info($"ConnectionKey: {item.Key.Environment}, {item.Key.Application}, {item.ConnectionInfo.Database}, {item.ConnectionInfo.Provider}");
                //}


                FkFolders fkFolders = new FkFolders();  
                string test = fkFolders.GetOptUncPath();
                using var dbHandler = DedgeDbHandler.Create(DedgeConnection.GetConnectionKeyByDatabaseName("INLTST"));
                try
                {
                    var json = dbHandler.ExecuteQueryAsXml("SELECT * FROM DBM.Z_AVDTAB FETCH FIRST 2 ROWS ONLY", throwException: true);
                    DedgeNLog.Info(json);
                }
                catch (Exception ex)
                {
                    DedgeNLog.Error(ex, $"Failed to execute query");
                    DedgeNLog.Error(ex, $"SqlInfo: {dbHandler._SqlInfo}");
                    throw;
                }

                // Step 0: Drop test table if it exists
                DedgeNLog.OperationProgression();
                DedgeNLog.Info($"Dropping test table if it exists");
                DropTestTable(dbHandler);
                DropTestTable(dbHandler);

                // Step 1: Create table
                DedgeNLog.OperationProgression();
                DedgeNLog.Info($"Creating test table");
                CreateTestTable(dbHandler);

                // Step 2: Grant permissions
                DedgeNLog.OperationProgression();
                DedgeNLog.Info($"Granting permissions");
                GrantPermissions(dbHandler);

                // Step 3: Insert test data
                DedgeNLog.OperationProgression();
                InsertTestData(dbHandler);

                // Step 4: Verify data
                DedgeNLog.OperationProgression();
                DedgeNLog.Info($"Verifying inserted data");
                VerifyData(dbHandler);

                // Step 5: Clean up
                DedgeNLog.OperationProgression();
                DedgeNLog.Info($"Cleaning up test data and table");
                CleanUp(dbHandler);

                // Step 6: Send notifications
                DedgeNLog.OperationProgression();
                DedgeNLog.Info($"Sending notifications");
                await SendNotifications(true);

                DedgeNLog.Info($"Verification completed successfully");
                DedgeNLog.EndOperation();

            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Verification failed");
                DedgeNLog.AbortOperation();
                await SendNotifications(false, ex.Message);
                throw;
            }
        }

        private static void DropTestTable(IDbHandler dbHandler)
        {
            try
            {
                const string dropTableSql = @"
                DROP TABLE DBM.TEST_FKDATABASEHANDLER";
                dbHandler.ExecuteNonQuery(dropTableSql, true);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to drop test table");
            }
        }


        private static void CreateTestTable(IDbHandler dbHandler)
        {
            dbHandler.BeginTransaction();
            const string createTableSql = @"
                CREATE TABLE DBM.TEST_FKDATABASEHANDLER (
                    ID INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
                    RANDOM_TEXT VARCHAR(100),
                    CREATED_DATE TIMESTAMP,
                    NUMERIC_VALUE DECIMAL(10,2),
                    PRIMARY KEY (ID)
                )";

            try
            {
                dbHandler.ExecuteNonQuery(createTableSql, true, true);
                DedgeNLog.Info($"Test table created successfully");
                dbHandler.CommitTransaction();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to create test table");
                dbHandler.RollbackTransaction();
                throw;
            }
        }

        private static void GrantPermissions(IDbHandler dbHandler)
        {
            dbHandler.BeginTransaction();
            string grantSql = $"GRANT CONTROL ON TABLE DBM.TEST_FKDATABASEHANDLER TO {TestUser}";

            try
            {
                dbHandler.ExecuteNonQuery(grantSql, true, true);
                DedgeNLog.Info($"Permissions granted to user {TestUser}");
                dbHandler.CommitTransaction();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to grant permissions");
                dbHandler.RollbackTransaction();
                throw;
            }
        }

        private static void InsertTestData(IDbHandler dbHandler)
        {
            dbHandler.BeginTransaction();
            const string insertSql = @"
                INSERT INTO DBM.TEST_FKDATABASEHANDLER 
                (RANDOM_TEXT, CREATED_DATE, NUMERIC_VALUE) 
                VALUES (@text, @date, @value)";

            try
            {
                DedgeNLog.Info($"Starting data insertion");
                var random = new Random();

                for (int i = 0; i < 100; i++)
                {
                    var parameters = new Dictionary<string, object>
                    {
                        { "@text", GenerateRandomString(random, 50) },
                        { "@date", DateTime.Now },
                        { "@value", Math.Round(random.NextDouble() * 100, 2) }
                    };

                    dbHandler.ExecuteNonQuery(insertSql, parameters, true, true);


                    if ((i + 1) % 100 == 0)
                    {
                        DedgeNLog.Info($"Inserted {i + 1} rows");
                    }
                }
                DedgeNLog.Info($"Data insertion completed");
                dbHandler.CommitTransaction();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to insert test data");
                dbHandler.RollbackTransaction();
                throw;
            }
        }

        private static void VerifyData(IDbHandler dbHandler)
        {
            const string countSql = "SELECT COUNT(*) FROM DBM.TEST_FKDATABASEHANDLER";
            const string sampleSql = "SELECT * FROM DBM.TEST_FKDATABASEHANDLER FETCH FIRST 5 ROWS ONLY";
            dbHandler.BeginTransaction();
            try
            {

                // Verify count
                var count = dbHandler.ExecuteScalar<long>(countSql, new Dictionary<string, object>());
                DedgeNLog.Info($"Total rows in table: {count}");

                // Sample some data
                var data = dbHandler.ExecuteQueryAsDataTable(sampleSql, true, true);
                DedgeNLog.Info($"Sample data from table:");
                foreach (DataRow row in data.Rows)
                {
                    DedgeNLog.Info($"ID: {row["ID"]}, Text: {row["RANDOM_TEXT"]}, Date: {row["CREATED_DATE"]}, Value: {row["NUMERIC_VALUE"]}");
                }
                dbHandler.CommitTransaction();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to verify data");
                dbHandler.RollbackTransaction();
                throw;
            }
        }

        private static void CleanUp(IDbHandler dbHandler)
        {
            dbHandler.BeginTransaction();
            try
            {
                // Drop table
                const string dropSql = "DROP TABLE DBM.TEST_FKDATABASEHANDLER";
                dbHandler.ExecuteNonQuery(dropSql, true, true);
                DedgeNLog.Info($"Test table dropped");
                dbHandler.RollbackTransaction();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to clean up");
                dbHandler.RollbackTransaction();
                throw;
            }
        }

        private static async Task SendNotifications(bool success, string? errorMessage = null)
        {
            string machineName = Environment.MachineName;
            string userName = Environment.UserName;
            string timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            
            var subject = success 
                ? "[DedgeCommon Test] ✓ VerifyFunctionality Completed Successfully" 
                : "[DedgeCommon Test] ✗ VerifyFunctionality Failed";
            
            var message = success
                ? $"DedgeCommon VerifyFunctionality Test - SUCCESS\n\n" +
                  $"The DedgeCommon database handler verification test completed successfully.\n\n" +
                  $"Test Details:\n" +
                  $"- Program: DedgeCommonVerifyFkDatabaseHandler/VerifyFunctionality\n" +
                  $"- Database: FKMTST (BASISTST)\n" +
                  $"- Operations Verified: Table creation, permissions, data insertion, queries, cleanup\n" +
                  $"- Machine: {machineName}\n" +
                  $"- User: {userName}\n" +
                  $"- Timestamp: {timestamp}\n\n" +
                  $"All database operations completed successfully. The DedgeCommon library is functioning correctly."
                : $"DedgeCommon VerifyFunctionality Test - FAILED\n\n" +
                  $"The DedgeCommon database handler verification test encountered an error.\n\n" +
                  $"Test Details:\n" +
                  $"- Program: DedgeCommonVerifyFkDatabaseHandler/VerifyFunctionality\n" +
                  $"- Database: FKMTST (BASISTST)\n" +
                  $"- Machine: {machineName}\n" +
                  $"- User: {userName}\n" +
                  $"- Timestamp: {timestamp}\n\n" +
                  $"ERROR:\n{errorMessage}\n\n" +
                  $"Please review the log files for detailed error information.";

            var smsMessage = success
                ? $"[DedgeCommon Test] ✓ VerifyFunctionality test PASSED on {machineName} at {timestamp}"
                : $"[DedgeCommon Test] ✗ VerifyFunctionality test FAILED on {machineName}. Error: {errorMessage?.Substring(0, Math.Min(100, errorMessage?.Length ?? 0))}";

            try
            {
                // Send email
                Notification.SendHtmlEmail(TestEmail, subject, message);
                DedgeNLog.Info($"Email notification sent to {TestEmail}");

                // Send SMS
                await Notification.SendSmsMessage(TestMobile, smsMessage);
                DedgeNLog.Info($"SMS notification sent to {TestMobile}");
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to send notifications");
                throw;
            }
        }

        private static string GenerateRandomString(Random random, int length)
        {
            const string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
            var stringBuilder = new StringBuilder(length);

            for (int i = 0; i < length; i++)
            {
                stringBuilder.Append(chars[random.Next(chars.Length)]);
            }

            return stringBuilder.ToString();
        }
    }
}
