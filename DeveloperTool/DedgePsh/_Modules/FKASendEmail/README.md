# FKASendEmail Module

[DEPRECATED] This module is deprecated. Please use GlobalFunctions\Send-Email instead.

## Exported Functions

### FKASendEmail
Sends emails using the GlobalFunctions Send-Email functionality.

```powershell
FKASendEmail -To <string> -From <string> -Subject <string> [-Body <string>] [-HtmlBody <string>] [-Attachments <string[]>]
```

#### Parameters
- `To`: The email address of the recipient
- `From`: The email address of the sender
- `Subject`: The subject line of the email
- `Body`: (Optional) The plain text body of the email
- `HtmlBody`: (Optional) The HTML formatted body of the email
- `Attachments`: (Optional) An array of file paths to attach to the email

#### Example
```powershell
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Test" -Body "Hello World"
```

## Overview
The FKASendEmail module provides a simplified interface for sending emails through the organization's SMTP server. It wraps the PowerShell Send-MailMessage cmdlet with predefined server settings and error handling.

> **⚠️ Important Note**: This module uses the deprecated `Send-MailMessage` cmdlet, which Microsoft has marked for deprecation due to security concerns. In future versions, it may be updated to use alternative methods for sending emails.

## Usage Examples
```powershell
# Send a simple text email
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Test Email" -Body "This is a test email."

# Send an HTML formatted email
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "HTML Test" -Body "<h1>Hello World</h1><p>This is an HTML email.</p>" -HtmlBody

# Send an email with attachments
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Report" -Body "Please find the attached report." -Attachments @("C:\Reports\report.pdf", "C:\Reports\data.xlsx")
```

## Notes
- The module does not support authentication or TLS/SSL configuration as it's designed for internal use with a preconfigured SMTP server.
- Error handling is silent by default. If you need to capture errors, you may need to modify the function or implement your own error handling. 