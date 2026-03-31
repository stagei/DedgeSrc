using DedgeCommon;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using NLog;

namespace DedgeCommonTest
{
    [TestClass]
    public class RunExternalTests
    {


        [TestMethod]
        public void RunRexxScript_WithInvalidScriptPath_ThrowsFileNotFoundException()
        {
            // Arrange
            string invalidPath = "nonexistent.rex";

            // Act & Assert
            Assert.ThrowsExactly<FileNotFoundException>(() => 
                RunExternal.RunRexxScript(invalidPath));
        }

        // Add more tests for other methods...
    }
}