using DedgeCommon;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using NLog;

namespace DedgeCommonTest
{
    [TestClass]
    public class FkFoldersTests
    {
        private Mock<DedgeNLog> _loggerMock = null!;
        private FkFolders _sut = null!;
        private string _testNamespace = string.Empty;

        [TestInitialize]
        public void Setup()
        {
            _loggerMock = new Mock<DedgeNLog>();
            _testNamespace = "TestNamespace";
            _sut = new FkFolders();
        }

        [TestMethod]
        public void GetOptPath_ReturnsValidPath()
        {
            // Act
            string result = _sut.GetOptPath();

            // Assert
            Assert.IsFalse(string.IsNullOrEmpty(result));
        }

        [TestMethod]
        public void GetDataFolder_CreatesDirectoryIfNotExists()
        {
            // Arrange
            string expectedPath = Path.Combine(_sut.GetOptPath(), "data", _testNamespace);
            if (Directory.Exists(expectedPath))
                Directory.Delete(expectedPath, true);

            // Act
            string result = _sut.GetDataFolder();

            // Assert
            Assert.IsTrue(Directory.Exists(result));
            Assert.AreEqual(expectedPath, result);
        }

        [TestMethod]
        public void GetCobolIntFolder_WithValidDatabase_ReturnsCorrectPath()
        {
            // Arrange
            string connectionString = "Database=BASISPRO;Server=testserver;UID=user;PWD=pass;";

            // Act
            string result = _sut.GetCobolIntFolder(connectionString);

            // Assert
            Assert.AreEqual(@"\\DEDGE.fk.no\erpprog\cobnt", result);
        }

        [TestMethod]
        public void GetCobolIntFolder_WithInvalidConnectionString_ThrowsException()
        {
            // Act & Assert
            Assert.ThrowsExactly<ArgumentNullException>(() => 
                _sut.GetCobolIntFolder(""));
        }

        [TestMethod]
        public void GetOptUncPath_ReturnsValidUncPath()
        {
            // Act
            string result = _sut.GetOptUncPath();

            // Assert
            Assert.IsTrue(result.StartsWith(@"\\"));
            Assert.IsTrue(result.Contains(Environment.MachineName));
        }

        [TestMethod]
        public void GetAppFolder_CreatesDirectoryIfNotExists()
        {
            // Arrange
            string expectedPath = Path.Combine(_sut.GetOptPath(), "apps", _testNamespace);
            if (Directory.Exists(expectedPath))
                Directory.Delete(expectedPath, true);

            // Act
            string result = _sut.GetAppFolder();

            // Assert
            Assert.IsTrue(Directory.Exists(result));
            Assert.AreEqual(expectedPath, result);
        }
    }
}