using System.Data;
using System.Diagnostics;
using System.Net;
using System.Net.Mail;
using System.Text;

namespace DedgeCommon
{

    /// <summary>
    /// Provides functionality for sending SMS messages and emails within the Dedge system.
    /// This class handles all external communication needs with standardized methods for
    /// sending notifications through different channels.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - SMS messaging with retry logic and error handling
    /// - HTML email support with multiple recipient handling
    /// - Configurable SMTP settings
    /// - Detailed logging of all communication attempts
    /// - Support for both plain text and HTML message formats
    /// </remarks>
    /// <author>Geir Helge Starholm</author>



    public static class Notification
    {
        private static readonly DedgeNLog _Logger = new DedgeNLog();
        private static bool _test = DedgeNLog.EnableDatabaseLogging();
        private static readonly string wkmonPath = @"C:\Program Files (x86)\WKMon\WKMon.exe";
        /// <summary>
        /// Sends a FK Alert to the monitoring system.
        /// Replaces PowerShell Send-FkAlert function.
        /// </summary>
        /// <param name="program">The name of the program generating the alert.</param>
        /// <param name="code">The alert code.</param>
        /// <param name="message">The alert message.</param>
        public static void SendFkAlert(string program, string code, string message)
        {
            // Check if WKMon.exe exists
            if (!File.Exists(wkmonPath))
            {
                DedgeNLog.Warn($"WKMon executable not found at: {wkmonPath}. Alert not sent.");
                DedgeNLog.Info($"Alert would have been: {program} {code} {message}");
                return;
            }

            try
            {
                string arguments = $"-program \"{program}\" -kode \"{code}\" -melding \"{message}\"";

                using (Process process = new Process())
                {
                    process.StartInfo.FileName = wkmonPath;
                    process.StartInfo.Arguments = arguments;
                    process.StartInfo.UseShellExecute = false;
                    process.StartInfo.RedirectStandardOutput = true;
                    process.StartInfo.RedirectStandardError = true;

                    process.Start();
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    process.WaitForExit();

                    if (!string.IsNullOrEmpty(error))
                    {
                        DedgeNLog.Error($"Error alerting WKMon: {error}");
                    }
                    else
                    {
                        DedgeNLog.Info($"WKMon alerted successfully: {output}");
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Warn(ex, $"Failed to send WKMon alert: {message}");
            }
        }
        // ══════════════════════════════════════════════════════════
        // WKMon Integration (moved from WkMonitor.cs)
        // ══════════════════════════════════════════════════════════

        /// <summary>
        /// Sends a WKMon alert notification.
        /// This was moved from WkMonitor.cs for better organization.
        /// </summary>
        /// <param name="program">The name of the program sending the alert</param>
        /// <param name="code">The alert code</param>
        /// <param name="message">The alert message</param>
        public static void SendWkMonAlert(string program, string code, string message)
        {
            string wkmonPath = @"C:\Program Files (x86)\WKMon\WKMon.exe";
            
            if (!File.Exists(wkmonPath))
            {
                DedgeNLog.Warn($"WKMon executable not found at: {wkmonPath}");
                return;
            }

            try
            {
                string timestamp = DateTime.Now.ToString("yyyyMMddHHmmss");
                string computerName = Environment.MachineName;
                string wkmonCommand = $"{timestamp} {program} {code} {computerName}: {message}";

                var startInfo = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = wkmonPath,
                    Arguments = $"\"{wkmonCommand}\"",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                };

                using (var process = System.Diagnostics.Process.Start(startInfo))
                {
                    if (process != null)
                    {
                        string output = process.StandardOutput.ReadToEnd();
                        process.WaitForExit();
                        DedgeNLog.Info($"WKMon alerted successfully: {output}");
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Warn(ex, $"Failed to send WKMon alert: {message}");
            }
        }

        // ══════════════════════════════════════════════════════════
        // SMS Messaging
        // ══════════════════════════════════════════════════════════

        /// <summary>
        /// Sends an SMS message to one or more recipients.
        /// </summary>
        /// <param name="receiver">A string representing the recipient's phone number(s). Multiple numbers can be separated by semicolons or commas.</param>
        /// <param name="message">The content of the SMS message.</param>
        /// <returns>True if the SMS message was sent successfully, otherwise false.</returns>
        /// <exception cref="ArgumentNullException">Thrown when the receiver or message is null or empty.</exception>
        public static async Task<bool> SendSmsMessage(string receiver, string message)
        {
            bool result = false;
            try
            {
                if (string.IsNullOrEmpty(receiver))
                {
                    throw new ArgumentNullException(nameof(receiver) + " is null or empty. Receiver is required.");
                }
                List<string> receivers = new List<string>();
                if (receiver.Contains(';'))
                {
                    receiver = receiver.Replace(';', ',');
                }

                if (receiver.Contains(','))
                {
                    receivers = receiver.Split(',').ToList();
                }
                else
                {
                    receivers.Add(receiver);
                }
                DedgeNLog.Info($"Sending SMS to {receiver} with message: {message}");
                
                // Use WebClient like PowerShell (HttpClient wasn't working)
                using (var webClient = new System.Net.WebClient())
                {
                    webClient.Headers.Add("Content-Type", "application/xml");
                    
                    foreach (var rec in receivers)
                    {
                        try
                        {
                            // XML payload - MUST match PowerShell exactly (version 1.0, no whitespace)
                            string xmlPayload = $"<?xml version=\"1.0\"?><SESSION><CLIENT>fk</CLIENT><PW>fksmsnet</PW><MSGLST><MSG><TEXT>{message}</TEXT><RCV>{rec.Trim()}</RCV><SND>23022222</SND></MSG></MSGLST></SESSION>";
                            
                            // Use UploadString like PowerShell
                            string response = webClient.UploadString("http://sms3.pswin.com/sms", xmlPayload);
                            
                            DedgeNLog.Info($"SMS sent successfully to {rec}");
                            result = true;
                        }
                        catch (Exception smsEx)
                        {
                            DedgeNLog.Error(smsEx, $"Failed to send SMS to {rec}");
                            result = false;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Error when sending SMS to " + receiver + " with message: " + message);
                throw;
            }
            return result;
        }



        /// <summary>
        /// Sends an HTML email to one or more recipients with optional CC and BCC.
        /// </summary>
        /// <param name="toEmail">A string representing the recipient's email address(es). Multiple addresses can be separated by semicolons or commas.</param>
        /// <param name="subject">The subject of the email.</param>
        /// <param name="htmlBody">The HTML content of the email.</param>
        /// <param name="fromEmail">The sender's email address. Defaults to "Dedge Automatisk Epost&lt;email.donotreply@Dedge.no&gt;".</param>
        /// <param name="ccEmail">Optional CC recipients. Multiple addresses can be separated by semicolons or commas.</param>
        /// <param name="bccEmail">Optional BCC recipients. Multiple addresses can be separated by semicolons or commas.</param>
        /// <returns>True if the email was sent successfully, otherwise false.</returns>
        /// <exception cref="ArgumentNullException">Thrown when any of the required parameters (toEmail, subject, htmlBody, fromEmail) are null or empty.</exception>
        public static bool SendHtmlEmail(
            string toEmail, 
            string subject, 
            string htmlBody, 
            string fromEmail = "Dedge Automatisk Epost<email.donotreply@Dedge.no>",
            string? ccEmail = null,
            string? bccEmail = null)
        {
            bool mailSent = false;
            try
            {
                // Validate the required fields
                if (string.IsNullOrEmpty(toEmail))
                {
                    throw new ArgumentNullException(nameof(toEmail) + " is null or empty. Email is required.");
                }
                if (string.IsNullOrEmpty(subject))
                {
                    throw new ArgumentNullException(nameof(subject) + " is null or empty. Subject is required.");
                }
                if (string.IsNullOrEmpty(htmlBody))
                {
                    throw new ArgumentNullException(nameof(htmlBody) + " is null or empty. Body is required.");
                }
                if (string.IsNullOrEmpty(fromEmail))
                {
                    throw new ArgumentNullException(nameof(fromEmail) + " is null or empty. From email is required.");
                }

                // Split the toEmail string into an array of individual email addresses
                string[] toEmails;
                if (toEmail.Contains(";"))
                {
                    toEmails = toEmail.Split(';');
                }
                else if (toEmail.Contains(","))
                {
                    toEmails = toEmail.Split(',');
                }
                else
                {
                    toEmails = new string[] { toEmail };
                }

                toEmails = toEmails.Where(x => !string.IsNullOrEmpty(x)).ToArray();

                // Parse CC emails
                string[] ccEmails = new string[0];
                if (!string.IsNullOrEmpty(ccEmail))
                {
                    if (ccEmail.Contains(";"))
                    {
                        ccEmails = ccEmail.Split(';');
                    }
                    else if (ccEmail.Contains(","))
                    {
                        ccEmails = ccEmail.Split(',');
                    }
                    else
                    {
                        ccEmails = new string[] { ccEmail };
                    }
                    ccEmails = ccEmails.Where(x => !string.IsNullOrEmpty(x)).Select(x => x.Trim()).ToArray();
                }

                // Parse BCC emails
                string[] bccEmails = new string[0];
                if (!string.IsNullOrEmpty(bccEmail))
                {
                    if (bccEmail.Contains(";"))
                    {
                        bccEmails = bccEmail.Split(';');
                    }
                    else if (bccEmail.Contains(","))
                    {
                        bccEmails = bccEmail.Split(',');
                    }
                    else
                    {
                        bccEmails = new string[] { bccEmail };
                    }
                    bccEmails = bccEmails.Where(x => !string.IsNullOrEmpty(x)).Select(x => x.Trim()).ToArray();
                }

                int retryCount = 0;
                int mailSentCount = 0;
                while (retryCount < 6)
                {
                    var smtpClient = new SmtpClient
                    {
                        Host = "smtp.DEDGE.fk.no",
                        Port = 25,
                        EnableSsl = false,
                        DeliveryMethod = SmtpDeliveryMethod.Network,
                        UseDefaultCredentials = false,
                        Credentials = new NetworkCredential(domain: "DEDGE", userName: "fkbatch", password: "7KK7DN4XxB2mBBuFdU9XjdKqSTyAG4"),
                        Timeout = 20000
                    };

                    using (var message = new MailMessage()
                    {
                        From = new MailAddress(fromEmail),
                        Subject = subject,
                        Body = htmlBody,
                        IsBodyHtml = true,
                        DeliveryNotificationOptions = DeliveryNotificationOptions.OnSuccess
                    })
                    {
                        try
                        {
                            // Add TO recipients
                            for (int i = 0; i < toEmails.Length; i++)
                            {
                                message.To.Add(toEmails[i]);
                            }

                            // Add CC recipients
                            for (int i = 0; i < ccEmails.Length; i++)
                            {
                                message.CC.Add(ccEmails[i]);
                            }

                            // Add BCC recipients
                            for (int i = 0; i < bccEmails.Length; i++)
                            {
                                message.Bcc.Add(bccEmails[i]);
                            }

                            smtpClient.Send(message);
                            mailSentCount++;
                            string toEmailsString = string.Join(", ", toEmails);
                            string logMessage = $"Email with {subject} sent to {toEmailsString} from {fromEmail}.";
                            
                            if (ccEmails.Length > 0)
                            {
                                logMessage += $" CC: {string.Join(", ", ccEmails)}.";
                            }
                            if (bccEmails.Length > 0)
                            {
                                logMessage += $" BCC: {bccEmails.Length} recipient(s).";
                            }
                            
                            DedgeNLog.Info(logMessage);
                            mailSent = true;
                        }
                        catch (Exception ex)
                        {
                            DedgeNLog.Warn(ex, "Error when sending email");
                            retryCount++;
                            mailSent = false;
                        }
                    }
                    if (mailSent == false)
                    {
                        int sleepTime = 0;
                        if (retryCount == 1)
                        {
                            sleepTime = 5000;
                        }
                        else if (retryCount == 2)
                        {
                            sleepTime = 10000;
                        }
                        else if (retryCount == 3)
                        {
                            sleepTime = 15000;
                        }
                        else if (retryCount == 4)
                        {
                            sleepTime = 20000;
                        }
                        else if (retryCount == 5)
                        {
                            sleepTime = 120000;
                        }
                        DedgeNLog.Warn($"Will try again in {sleepTime / 1000} seconds");
                        Thread.Sleep(15000);
                        continue;
                    }
                    mailSent = true;
                    break;
                }
                if (!mailSent)
                {
                    DedgeNLog.Error($"Error. Only {mailSentCount} of {toEmails.Length} mails sent of these:" + toEmail);
                    mailSent = false;
                }
                else
                {
                    mailSent = true;
                }

            }
            catch (Exception)
            {
                throw;
            }
            return mailSent;
        }
    }
}
