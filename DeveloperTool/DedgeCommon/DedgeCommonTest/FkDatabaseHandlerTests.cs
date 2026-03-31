using DedgeCommon;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DedgeCommonTest
{
    [TestClass]
    public class FkDatabaseHandlerTests
    {
        private static readonly DedgeConnection.ConnectionKey? _defaultKey = new(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.DEV);
        private static readonly DedgeNLog Logger = new DedgeNLog();
        private static bool _test = DedgeNLog.EnableDatabaseLogging(_defaultKey);

        [TestMethod]
        public void Create_WithConnectionKey_ReturnsCorrectHandlerType()
        {
            // Arrange
            var db2Key = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.DEV);
            var sqlKey = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.DBQA, DedgeConnection.FkEnvironment.PRD);

            // Act
            var db2Handler = DedgeDbHandler.Create(db2Key);
            var sqlHandler = DedgeDbHandler.Create(sqlKey);

            // Assert
            Assert.AreEqual(DedgeConnection.DatabaseProvider.DB2, db2Handler.Provider);
            Assert.AreEqual(DedgeConnection.DatabaseProvider.SQLSERVER, sqlHandler.Provider);
        }

        [TestMethod]
        public void Create_WithEnvironmentAndApplication_ReturnsCorrectHandler()
        {
            // Arrange & Act
            var handler = DedgeDbHandler.Create(
                DedgeConnection.FkEnvironment.DEV,
                DedgeConnection.FkApplication.FKM);

            // Assert
            Assert.AreEqual(DedgeConnection.DatabaseProvider.DB2, handler.Provider);
        }



        [TestMethod]
        public void Create_WithDifferentVersions_ReturnsCorrectHandlers()
        {
            // Arrange
            var v1Key = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.DEV, "2.0");
            var v2Key = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.DEV, "2.0");

            // Act
            var v1Handler = DedgeDbHandler.Create(v1Key);
            var v2Handler = DedgeDbHandler.Create(v2Key);

            // Assert
            Assert.AreEqual(DedgeConnection.DatabaseProvider.DB2, v1Handler.Provider);
            Assert.AreEqual(DedgeConnection.DatabaseProvider.DB2, v2Handler.Provider);
            Assert.AreNotEqual(v1Handler.ConnectionString, v2Handler.ConnectionString);
        }

        [TestMethod]
        public void Create_WithEnvironmentAndVersion_ReturnsCorrectHandler()
        {
            // Arrange & Act
            var handler = DedgeDbHandler.Create(
                DedgeConnection.FkEnvironment.DEV,
                DedgeConnection.FkApplication.FKM,
                "2.0");

            // Assert
            Assert.AreEqual(DedgeConnection.DatabaseProvider.DB2, handler.Provider);
            Assert.IsTrue(handler.ConnectionString.Contains("FKAVDNT"));
        }

        [TestMethod]
        public void Create_WithDefaultParameters_ReturnsPrdHandler()
        {
            // Arrange & Act
            var handler = DedgeDbHandler.Create(
                DedgeConnection.FkEnvironment.DEV);  // Using default application and version

            // Assert
            Assert.AreEqual(DedgeConnection.DatabaseProvider.DB2, handler.Provider);
            Assert.IsTrue(handler.ConnectionString.Contains("FKAVDNT"));
        }

        [TestMethod]
        public void Create_WithUnsupportedProvider_ThrowsException()
        {
            // Arrange
            var connectionKey = new DedgeConnection.ConnectionKey(DedgeConnection.FkApplication.FKM, DedgeConnection.FkEnvironment.DEV);
            var connectionInfo = DedgeConnection.GetConnectionStringInfo(connectionKey);

            // Use reflection to set an invalid provider value
            var providerField = connectionInfo.GetType().GetProperty("Provider");
            providerField?.SetValue(connectionInfo, (DedgeConnection.DatabaseProvider)999);

            // Act & Assert - this should throw
            Assert.ThrowsExactly<ArgumentException>(() => 
                DedgeDbHandler.Create(connectionKey));
        }
    }
}