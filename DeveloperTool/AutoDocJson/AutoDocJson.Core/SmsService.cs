using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Text;
using AutoDocNew.Core;

namespace AutoDocNew.Core;

/// <summary>
/// SMS Service - converted line-by-line from Send-Sms function in GlobalFunctions.psm1 (lines 2014-2082)
/// Sends SMS messages via SOAP web service
/// </summary>
public static class SmsService
{
    /// <summary>
    /// Send SMS - converted from Send-Sms function
    /// </summary>
    public static void Send(object receiver, string message)
    {
        try
        {
            // Line 2024: Convert receiver to normalized array of strings
            List<string> receiverArray = new List<string>();

            // Line 2026-2032: Handle receiver with Count property
            if (receiver is System.Collections.ICollection collection && collection.Count > 0)
            {
                foreach (var item in collection)
                {
                    if (item is string strItem)
                    {
                        receiverArray.Add(strItem.Trim());
                    }
                }
            }
            // Line 2033-2040: Handle comma-separated string
            else if (receiver is string receiverStr)
            {
                if (receiverStr.Contains(","))
                {
                    receiverArray.AddRange(receiverStr.Split(',')
                        .Select(s => s.Trim())
                        .Where(s => !string.IsNullOrEmpty(s)));
                }
                else
                {
                    receiverArray.Add(receiverStr.Trim());
                }
            }
            // Line 2042-2048: Handle arrays and collections
            else if (receiver is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item is string strItem)
                    {
                        receiverArray.Add(strItem.Trim());
                    }
                }
            }
            // Line 2050-2052: Handle single non-string object
            else
            {
                receiverArray.Add(receiver.ToString()?.Trim() ?? "");
            }

            // Line 2056: Remove empty entries
            receiverArray = receiverArray.Where(r => !string.IsNullOrEmpty(r)).ToList();

            // Line 2058-2061: Check if any valid receivers
            if (receiverArray.Count == 0)
            {
                Logger.LogMessage("No valid receivers provided for SMS", LogLevel.WARN);
                return;
            }

            // Line 2064-2077: Process each receiver
            foreach (string receiverItem in receiverArray)
            {
                Logger.LogMessage($"Sending SMS to {receiverItem} with message: {message}", LogLevel.INFO);

                try
                {
                    // Line 2068-2071: Create web client and send SOAP request
                    using (var client = new WebClient())
                    {
                        client.Headers.Add("Content-Type", "application/xml");
                        
                        // Line 2070: Build XML payload
                        string xmlPayload = $@"<?xml version=""1.0""?><SESSION><CLIENT>fk</CLIENT><PW>fksmsnet</PW><MSGLST><MSG><TEXT>{EscapeXml(message)}</TEXT><RCV>{EscapeXml(receiverItem)}</RCV><SND>23022222</SND></MSG></MSGLST></SESSION>";
                        
                        // Line 2071: Upload to SMS service
                        string response = client.UploadString("http://sms3.pswin.com/sms", xmlPayload);
                        
                        Logger.LogMessage($"SMS sent successfully to {receiverItem}", LogLevel.INFO);
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Failed to process SMS for receiver {receiverItem}: {ex.Message}", LogLevel.ERROR, ex);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Failed to process SMS sending request: {ex.Message}", LogLevel.ERROR, ex);
        }
    }

    /// <summary>
    /// Escape XML special characters
    /// </summary>
    private static string EscapeXml(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return "";
        }

        return text.Replace("&", "&amp;")
                  .Replace("<", "&lt;")
                  .Replace(">", "&gt;")
                  .Replace("\"", "&quot;")
                  .Replace("'", "&#39;");
    }
}
