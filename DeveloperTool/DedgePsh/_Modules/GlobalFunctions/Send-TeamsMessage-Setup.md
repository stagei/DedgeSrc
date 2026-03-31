# Send-TeamsMessage Configuration Guide

This guide explains how to configure the `Send-TeamsMessage` function from GlobalFunctions to send messages to Microsoft Teams.

**Author:** Geir Helge Starholm, www.dEdge.no

---

## Overview

The `Send-TeamsMessage` function supports two modes:

| Mode | Use Case | Authentication |
|------|----------|----------------|
| **Webhook** | Post to a Teams channel | Webhook URL (no credentials needed) |
| **Graph API** | Send direct messages to users | Azure AD app credentials |

---

## Option 1: Webhook Mode (Channel Messages)

Use this mode to post messages to a Teams channel. No Azure AD configuration required.

### Step 1: Create an Incoming Webhook in Teams

1. Open **Microsoft Teams**
2. Navigate to the channel where you want to receive messages
3. Click the **"..."** (More options) next to the channel name
4. Select **"Connectors"** (or "Manage channel" → "Connectors")
5. Find **"Incoming Webhook"** and click **"Configure"**
6. Give your webhook a name (e.g., "Dedge Alerts")
7. Optionally upload a custom icon
8. Click **"Create"**
9. **Copy the webhook URL** - it looks like:
   ```
   https://outlook.office.com/webhook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx@xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/IncomingWebhook/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

### Step 2: Test the Webhook

```powershell
Import-Module GlobalFunctions -Force

Send-TeamsMessage `
    -WebhookUrl "https://outlook.office.com/webhook/YOUR-WEBHOOK-URL" `
    -Title "Test Message" `
    -Message "Hello from PowerShell! 🎉"
```

### Step 3: Use in Scripts

```powershell
# Simple message
Send-TeamsMessage -WebhookUrl $webhookUrl -Message "Deployment completed"

# Message with title and custom color
Send-TeamsMessage `
    -WebhookUrl $webhookUrl `
    -Title "Build Status" `
    -Message "Build #123 passed all tests" `
    -ThemeColor "00FF00"  # Green

# Message with sections
$sections = @(
    @{ title = "Details"; text = "Server: PROD-01`nDuration: 5 minutes" }
    @{ title = "Next Steps"; text = "Verify deployment in production" }
)
Send-TeamsMessage `
    -WebhookUrl $webhookUrl `
    -Title "Deployment Report" `
    -Message "Application deployed successfully" `
    -Sections $sections
```

### Theme Colors

| Color | Hex Code | Use Case |
|-------|----------|----------|
| Blue (default) | `0076D7` | Information |
| Green | `00FF00` | Success |
| Yellow | `FFFF00` | Warning |
| Red | `FF0000` | Error/Alert |
| Orange | `FFA500` | Attention |

---

## Option 2: Graph API Mode (Direct Messages)

Use this mode to send direct chat messages to specific users by email address.

### Prerequisites

- Azure AD (Entra ID) app registration with appropriate permissions
- Admin consent for the app
- GlobalSettings.json configuration file

### Step 1: Create Azure AD App Registration

1. Go to **Azure Portal** → **Microsoft Entra ID** → **App registrations**
2. Click **"New registration"**
3. Configure:
   - **Name:** `Dedge-TeamsMessaging` (or similar)
   - **Supported account types:** "Accounts in this organizational directory only"
   - **Redirect URI:** Leave blank (not needed for daemon/service apps)
4. Click **"Register"**

### Step 2: Configure API Permissions

1. In your app registration, go to **"API permissions"**
2. Click **"Add a permission"**
3. Select **"Microsoft Graph"**
4. Choose **"Application permissions"** (not Delegated)
5. Add these permissions:
   - `Chat.ReadWrite.All` - Required to create chats and send messages
   - `User.Read.All` - Required to look up users by email
6. Click **"Add permissions"**
7. Click **"Grant admin consent for [Your Organization]"** (requires admin)

### Step 3: Create Client Secret

1. Go to **"Certificates & secrets"**
2. Click **"New client secret"**
3. Add a description (e.g., "Dedge Teams Messaging")
4. Choose expiration (recommended: 24 months)
5. Click **"Add"**
6. **⚠️ IMPORTANT:** Copy the secret value immediately - it won't be shown again!

### Step 4: Collect App Information

You need these three values:

| Setting | Where to Find |
|---------|---------------|
| **Tenant ID** | App registration → Overview → "Directory (tenant) ID" |
| **Client ID** | App registration → Overview → "Application (client) ID" |
| **Client Secret** | The secret value you copied in Step 3 |

### Step 5: Create GlobalSettings.json

Create the configuration file at:
```
C:\opt\DedgeCommon\ConfigFiles\GlobalSettings.json
```

Content:
```json
{
    "MicrosoftGraph": {
        "TenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ClientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ClientSecret": "your-client-secret-value"
    }
}
```

**Security notes:**
- Restrict file permissions to service accounts and admins only
- Consider using Azure Key Vault for production environments
- Rotate client secrets before expiration

### Step 6: Deploy to Servers

Copy `GlobalSettings.json` to all servers that need to send Teams messages:

```powershell
# Example: Copy to app servers
$servers = @("p-no1fkmprd-db", "p-no1inlprd-db", "dedge-server")
foreach ($server in $servers) {
    Copy-Item "C:\opt\DedgeCommon\ConfigFiles\GlobalSettings.json" `
              "\\$server\c$\opt\DedgeCommon\ConfigFiles\GlobalSettings.json" -Force
}
```

### Step 7: Test Graph API Mode

```powershell
Import-Module GlobalFunctions -Force

# Send to single user
Send-TeamsMessage `
    -To "geir.helge.starholm@Dedge.no" `
    -Message "Test message from PowerShell" `
    -Title "Agent Test" `
    -UseGraphApi

# Send to multiple users
Send-TeamsMessage `
    -To "user1@Dedge.no,user2@Dedge.no" `
    -Message "Group notification" `
    -UseGraphApi
```

---

## Troubleshooting

### Error: "GlobalSettings.json not found"

```
GlobalSettings.json not found at C:\opt\DedgeCommon\ConfigFiles\GlobalSettings.json
```

**Solution:** Create the file as described in Step 5, or copy from a server that has it:
```powershell
Copy-Item "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\ConfigFiles\GlobalSettings.json" `
          "C:\opt\DedgeCommon\ConfigFiles\GlobalSettings.json"
```

### Error: "AADSTS7000215: Invalid client secret"

**Solution:** The client secret has expired or is incorrect. Generate a new secret in Azure AD.

### Error: "AADSTS700016: Application not found"

**Solution:** Verify the ClientId in GlobalSettings.json matches your app registration.

### Error: "Insufficient privileges to complete the operation"

**Solution:** Ensure admin consent was granted for the Graph API permissions.

### Webhook returns error

**Solution:** 
- Verify the webhook URL is complete and not truncated
- Check if the webhook connector is still enabled in Teams
- Create a new webhook if the old one was deleted

---

## Best Practices

1. **Use Webhook mode** for:
   - Channel notifications
   - Build/deploy alerts
   - Monitoring dashboards
   - When you don't need to target specific users

2. **Use Graph API mode** for:
   - Direct user notifications
   - Personal alerts
   - When recipients aren't in a common channel
   - Automated user-specific messaging

3. **Error Handling:**
   ```powershell
   try {
       Send-TeamsMessage -To $email -Message $msg -UseGraphApi
       Write-LogMessage "Teams message sent to $email" -Level INFO
   }
   catch {
       Write-LogMessage "Failed to send Teams message" -Level ERROR -Exception $_
       # Fallback to SMS or email
   }
   ```

4. **Rate Limiting:**
   - Microsoft Graph has rate limits
   - For bulk messaging, add delays between messages
   - Consider batching notifications

---

## Quick Reference

```powershell
# Webhook mode (channel)
Send-TeamsMessage -WebhookUrl $url -Message "Hello" -Title "Alert"

# Graph API mode (direct message)
Send-TeamsMessage -To "email@domain.com" -Message "Hello" -UseGraphApi

# With custom color
Send-TeamsMessage -WebhookUrl $url -Message "Success!" -ThemeColor "00FF00"

# With sections
Send-TeamsMessage -WebhookUrl $url -Message "Report" -Sections @(
    @{ title = "Status"; text = "Complete" }
)
```
