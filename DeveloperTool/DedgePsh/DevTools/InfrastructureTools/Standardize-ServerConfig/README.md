# Standardize-ServerConfig

## Overview

A PowerShell script that standardizes server configurations by migrating scheduled tasks to use new username conventions and ensuring proper server initialization with correct permissions.

## Purpose

This script performs server configuration standardization tasks, primarily focused on:
- Updating scheduled task credentials to current username standards
- Initializing server directories and permissions
- Managing secure password storage for service accounts
- Applying database-specific grants on DB2 servers

## General Tasks

### 1. **Pre-Flight Validation**
- Verifies script is running with administrator privileges
- Confirms execution on a server (not workstation)
- Validates username based on server type:
  - **Database servers (-db)**: Must run as **old service username** (e.g., FKPRDSVR, FKTSTSVR)
  - **Application servers**: Must run as **admin account** (FKPRDADM, FKTSTADM, or FKDEVADM)

### 2. **Password Management**
- Retrieves existing secure password for current user
- Prompts for password setup if not found
- Converts password to SecureString format for credential updates

### 3. **Server Initialization**
- Calls `Initialize-Server` with current user as additional admin
- Skips Windows installation components
- Sets up proper directory structure and permissions

### 4. **Scheduled Task Credential Migration**
- Updates scheduled tasks to new username standards:
  - **Database servers**: Migrates FROM admin accounts (FKPRDADM/FKTSTADM/FKDEVADM) TO old service username (current user)
  - **Application servers**: Migrates FROM old service username TO admin account (current user)
- Applies current user's domain credentials to all matching tasks
- Ensures proper separation of duties and security standards

### 5. **Database-Specific Configuration** (DB2 servers only)
- Identifies all primary databases on the current server
- Retrieves default work objects for each database
- Applies specific database grants for each work object

## Requirements

### Modules
- GlobalFunctions
- Infrastructure
- ScheduledTask-Handler
- Deploy-Handler

### Prerequisites
- **Administrator privileges** (mandatory)
- **Server environment** (not supported on workstations)
- **Correct user context**:
  - DB servers: Old service username (e.g., FKPRDSVR, FKTSTSVR, FKDEVSVR)
  - App servers: Admin accounts (FKPRDADM, FKTSTADM, or FKDEVADM)

## Usage

```powershell
# Run as administrator with appropriate username
.\Standardize-ServerConfig.ps1
```

## Username Migration Logic

### Database Servers
- Script must be run as: **Old service username** (e.g., FKPRDSVR, FKTSTSVR, FKDEVSVR)
- Migrates scheduled tasks **FROM** admin accounts (FKPRDADM/FKTSTADM/FKDEVADM) **TO** old service username (current user)
- **Why**: DB servers should run tasks under service accounts, not admin accounts

### Application Servers
- Script must be run as: **Admin account** (FKPRDADM, FKTSTADM, or FKDEVADM)
- Migrates scheduled tasks **FROM** old service username **TO** admin account (current user)
- **Why**: App servers should run tasks under admin accounts for proper permissions

## Exit Codes

| Code | Description |
|------|-------------|
| 0    | Success - all configurations applied |
| 1    | Not running as administrator |
| 1    | Not running on a server |
| 1    | Invalid username for database server |
| 1    | Invalid username for application server |
| 1    | Password not found after prompt |

## Error Handling

The script includes error handling for:
- Service credential updates
- Scheduled task credential updates
- Missing or invalid passwords
- Database grant operations

All errors are logged using `Write-LogMessage` with appropriate severity levels.

## Security Notes

- Passwords are stored securely using Windows Data Protection API (DPAPI)
- Credentials are converted to SecureString before use
- Only authorized administrators can execute this script
- Changes are logged for audit purposes

## Related Functions

- `Test-IsAdmin` - Validates administrator privileges
- `Test-IsServer` - Confirms server environment
- `Test-IsDb2Server` - Identifies DB2 database servers
- `Get-OldServiceUsernameFromServerName` - Retrieves legacy service username pattern
- `Initialize-Server` - Sets up server directory structure and permissions
- `Update-ScheduledTaskCredentials` - Migrates task credentials
- `Add-SpecificGrants` - Applies database-specific grants

## Log Files

Logs are written to standard AllPwshLog directory:
```
C:\opt\data\AllPwshLog\<ComputerName>_<Date>.log
```

## Notes

- This script is part of infrastructure standardization efforts
- Should be run during server maintenance windows
- Backs up scheduled task configurations before modifications
- DB2 grant operations only execute on database servers with primary database access points
