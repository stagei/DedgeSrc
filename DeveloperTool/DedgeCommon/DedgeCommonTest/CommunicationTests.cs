using DedgeCommon;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using NLog;
using System.Net;

namespace DedgeCommonTest
{
    [TestClass]
    public class CommunicationTests
    {

        [TestInitialize]
        public void Setup()
        {
        }


        [TestMethod]
        public void SendSmsMessage_WithEmptyReceiver_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsExactly<ArgumentNullException>(() => 
                Notification.SendSmsMessage("", "Test message"));
        }

      
        [TestMethod]
        public void SendHtmlEmail_WithEmptyToEmail_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsExactly<ArgumentNullException>(() => 
                Notification.SendHtmlEmail("", "Subject", "Body"));
        }

        [TestMethod]
        public void SendHtmlEmail_WithEmptySubject_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsExactly<ArgumentNullException>(() => 
                Notification.SendHtmlEmail("test@test.com", "", "Body"));
        }

        [TestMethod]
        public void SendHtmlEmail_WithEmptyBody_ThrowsArgumentNullException()
        {
            // Act & Assert
            Assert.ThrowsExactly<ArgumentNullException>(() => 
                Notification.SendHtmlEmail("test@test.com", "Subject", ""));
        }

       
    }
}