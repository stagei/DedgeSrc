using System;

namespace DedgeCommon
{
    /// <summary>
    /// WKMon monitoring system integration.
    /// 
    /// ⚠️ DEPRECATED: This class is deprecated as of DedgeCommon v1.5.33
    /// 
    /// Please use Notification.SendFkAlert() instead.
    /// 
    /// Migration Guide:
    /// OLD: WkMonitor.Alert(program, code, message)
    /// NEW: Notification.SendFkAlert(program, code, message)
    /// 
    /// This class is kept for backward compatibility and proxies to Notification.cs
    /// </summary>
    [Obsolete("Use Notification.SendWkMonAlert() instead. WkMonitor class will be removed in v2.0")]
    public static class WkMonitor
    {
        /// <summary>
        /// Sends a WKMon alert notification.
        /// 
        /// ⚠️ DEPRECATED: Use Notification.SendWkMonAlert() instead
        /// </summary>
        /// <param name="program">The name of the program sending the alert</param>
        /// <param name="code">The alert code</param>
        /// <param name="message">The alert message</param>
        [Obsolete("Use Notification.SendFkAlert(program, code, message) instead")]
        public static void Alert(string program, string code, string message)
        {
            // Proxy to Notification.SendFkAlert for backward compatibility
            Notification.SendFkAlert(program, code, message);
        }
    }
}
