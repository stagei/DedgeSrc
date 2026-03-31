using DedgeCommon;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using NLog;

namespace DedgeCommonTest
{
    [TestClass]
    public class RunCblProgramTests
    {
        private Mock<DedgeNLog> _loggerMock = null!;
        private string _testConnectionString = string.Empty;

        [TestInitialize]
        public void Setup()
        {
            _loggerMock = new Mock<DedgeNLog>();
            _testConnectionString = "Database=TESTDB;Server=testserver:3700;UID=testuser;PWD=testpass;";
        }

        [TestMethod]
        public void Constructor_WithNullLogger_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsExactly<ArgumentNullException>(() => 
                RunCblProgram.CblRun(_testConnectionString, "TESTPROG", new[] { "param1", "param2" }, RunCblProgram.ExecutionMode.Batch));
        }

    }
}