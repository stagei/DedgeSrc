---
description: Team member configuration and SMS notifications
alwaysApply: true
---

# Team Member Configuration

**Current team members and their information:**

```yaml
Users:
  - Username: FKGEISTA
    FullName: Geir Helge Starholm
    Email: geir.helge.starholm@Dedge.no
    SecondaryEmail: geir@starholm.net
    SmsNumber: +4797188358
    AzurePatFile: C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json
    
  - Username: FKSVEERI
    FullName: Svein Morten Erikstad
    Email: svein.morten.erikstad@Dedge.no
    SmsNumber: +4795762742
    AzurePatFile: C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json
    
  - Username: FKMISTA
    FullName: Mina Marie Starholm
    Email: mina.marie.starholm@Dedge.no
    SmsNumber: +4799348397
    AzurePatFile: C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json
    
  - Username: FKCELERI
    FullName: Celine Andreassen Erikstad
    Email: Celine.Andreassen.Erikstad@Dedge.no
    SmsNumber: +4745269945
    AzurePatFile: C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json

ServiceAccounts:
  - Email: srv_Dedge_repo@Dedge.onmicrosoft.com
    Purpose: Azure DevOps service account for automation
    PatLocation: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json (AzureDevOps.Pat)
    RequiredScopes: Work Items (Read, Write & Manage); Code (Read & Write); Packaging (Read & Write)

AzureDevOpsPAT-RequiredScopes:
  Scopes:
    - Work Items: Read, Write & Manage
    - Code: Read & Write
    - Packaging: Read & Write
  DefaultExpiryDays: 90
```

## User Lookup Functions

**Use these patterns for user-specific lookups (single source of truth):**

```powershell
# Get user email
$userEmail = switch ($env:USERNAME) {
    "FKGEISTA" { "geir.helge.starholm@Dedge.no" }
    "FKSVEERI" { "svein.morten.erikstad@Dedge.no" }
    "FKMISTA"  { "mina.marie.starholm@Dedge.no" }
    "FKCELERI" { "Celine.Andreassen.Erikstad@Dedge.no" }
    default    { "geir.helge.starholm@Dedge.no" }
}

# Get user SMS number
$smsNumber = switch ($env:USERNAME) {
    "FKGEISTA" { "+4797188358" }
    "FKSVEERI" { "+4795762742" }
    "FKMISTA"  { "+4799348397" }
    "FKCELERI" { "+4745269945" }
    default    { "+4797188358" }
}

# Get user PAT file path
$patFile = "C:\opt\data\UserConfig\$env:USERNAME\AzureDevOpsPat.json"
```

**Auto-detection rules:**
- Use `$env:USERNAME` to identify current user
- If username not in list above, use FKGEISTA as default
- **If PAT file doesn't exist**, prompt to run: `.\DevTools\AzureTools\Azure-DevOpsPAT-Manager\Setup-AzureDevOpsPAT.ps1`

## Long-Running Operations Notification

When an agent operation takes more than **5 minutes**, automatically send SMS to current user.

**Use User Lookup Functions above** to get the SMS number.

```powershell
Send-Sms $smsNumber "<summary of what changed and short result>"
```

**SMS message format:**
- Keep under 1024 characters (160 is not a service limit)
- Include: operation type, files affected, and status (success/failure)

**When to send:** After operation completes (success or failure)
**Do NOT send for:** Operations under 5 minutes, interactive operations
