# FKASendSMSDirect Module

[DEPRECATED] This module is deprecated. Please use GlobalFunctions\Send-Sms instead.

## Overview
The FKASendSMSDirect module provides functionality for sending SMS messages via the LinkMobility (formerly PSWinCom) service. It uses a predefined account and sender ID to send text messages to specified recipients.

## Dependencies
- Logger module (for logging SMS sending activities)

## Exported Functions

### FKASendSMSDirect
Sends SMS messages directly using the GlobalFunctions Send-Sms functionality.

```powershell
FKASendSMSDirect -receiver <string> -message <string>
```

#### Parameters
- `receiver`: The phone number of the SMS recipient
- `message`: The text message to be sent

#### Example
```powershell
FKASendSMSDirect -receiver "+4712345678" -message "Hello World"
```

## Usage Examples
```powershell
# Send a simple SMS message
FKASendSMSDirect -receiver "4712345678" -message "This is a test message"

# Send an alert notification
FKASendSMSDirect -receiver "4712345678" -message "System alert: Server XYZ is down"
```

## Notes
- The module uses hardcoded credentials and sender ID. In a production environment, these should be stored securely.
- The function does not currently handle or return error messages from the SMS service.
- The SMS service endpoint is configured to use HTTP. Consider updating to HTTPS for better security. 