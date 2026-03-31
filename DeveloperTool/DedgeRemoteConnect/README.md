# DedgeRemoteConnect

A Windows Forms application for managing remote desktop connections with enhanced security features and customizable connection profiles.

## Overview

DedgeRemoteConnect is a system tray application that provides a convenient way to manage and initiate Remote Desktop Protocol (RDP) connections. It combines centrally managed computer configurations with local RDP profiles, offering both enterprise-wide standardization and personal customization options.

## Features

### 1. System Tray Integration
- Runs as a system tray application with a dark-themed context menu
- Auto-refreshes computer list every 5 minutes
- Provides quick access to all configured remote connections

### 2. Computer List Management
- Reads computer configurations from a central JSON file (`\\p-Dedge-vm02\DedgeCommon\Configfiles\ComputerInfo.json`)
- Supports both centrally managed and local RDP profiles
- Filters computers based on:
  - Active status
  - User permissions (SingleUser attribute)
  - Environment grouping

### 3. RDP Profile Management
- Stores RDP profiles in the user's Documents folder
- Supports password encryption using Windows Data Protection API (DPAPI)
- Allows customization of connection settings:
  - Multi-monitor support
  - Printer redirection
  - Clipboard sharing
  - Audio settings

### 4. Security Features
- Secure password storage using DPAPI encryption
- User-specific access control through SingleUser attribute
- Support for environment-based grouping
- Automatic credential management

### 5. User Interface
- Dark mode support
- Hierarchical menu organization by environment
- Visual indicators for saved profiles (bold text)
- Easy access to local RDP files

## Usage

### Adding a New Connection
1. Select a computer from the context menu
2. Enter credentials when prompted
3. Configure connection settings:
   - Username and password
   - Display settings (multi-monitor)
   - Redirection options (printers, clipboard)
   - Audio preferences
4. Choose whether to save the credentials

### Managing Local RDP Files
- Local RDP profiles appear at the top of the menu
- Each profile has a submenu with options:
  - Connect: Launch the RDP session
  - Add password: Securely add/update the stored password
- Access all RDP files through the "Open RDP Files Folder" option

### Connection Groups
- Computers are grouped by environment
- Custom (local) RDP files are shown in a separate "Local RDP profiles" section
- Each group is clearly separated with headers

## Technical Details

### File Structure
- RDP files: Stored in `%UserProfile%\Documents`
- Central configuration: Network share JSON file
- Executable location: Program Files (x86)

### Security Implementation
- Password encryption: Windows DPAPI
- Credential storage: Per-user encrypted RDP files
- Access control: Username-based filtering

### Configuration Format
The central JSON configuration supports the following attributes for each computer:
```json
{
    "Name": "Computer name",
    "Type": "Server type",
    "Platform": "OS Platform",
    "Purpose": "Usage description",
    "ApplicationList": ["App1", "App2"],
    "Comments": "Additional notes",
    "DomainName": "FQDN",
    "IsActive": true,
    "Environment": "Production",
    "RequiredPorts": {
        "RDP": 3389,
        "DB2": [50000]
    },
    "SingleUser": "username"
}
```

## Installation

### System Requirements
- Windows 10/11
- .NET 8.0 Runtime
- Network access to central configuration share

### Installation Steps
1. Run the installer (DedgeRemoteConnectSetup.msi)
2. Application will be installed to Program Files (x86)
3. Shortcuts are created in:
   - Start Menu
   - Desktop

## Troubleshooting

### Common Issues
1. Cannot see computer list:
   - Check network connection to configuration share
   - Verify user permissions

2. RDP connection fails:
   - Verify target computer is accessible
   - Check stored credentials
   - Ensure required ports are open

3. Password issues:
   - Use "Add password" option to update stored credentials
   - Delete and recreate RDP file if needed

### Support
For technical support or to report issues, contact the Dedge IT Development Team.