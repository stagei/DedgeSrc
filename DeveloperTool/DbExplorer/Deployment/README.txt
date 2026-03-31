================================================================================
                    DbExplorer v1.0.0
                Modern DB2 Database Editor for Windows 11
================================================================================

INSTALLATION INSTRUCTIONS
================================================================================

1. REQUIREMENTS:
   - Windows 11 or Windows 10 (version 1809 or later)
   - Network access to DB2 database server
   - NO .NET installation required (included in package)
   - NO DB2 client installation required (uses Net.IBM.Data.Db2)

2. INSTALLATION:
   
   Option A: Simple Copy (Recommended)
   ------------------------------------
   a) Copy this entire folder to your desired location:
      Example: C:\Program Files\DbExplorer\
   
   b) Run DbExplorer.exe
   
   Option B: Using PowerShell Script
   ----------------------------------
   a) Run PowerShell as Administrator
   b) Navigate to this directory
   c) Execute: .\deploy.ps1
   
   The script will:
   - Copy files to C:\Program Files\DbExplorer\
   - Create logs directory
   - Create desktop shortcut
   - Verify installation

3. FIRST RUN:
   a) Launch DbExplorer.exe
   b) Click "New Connection" or press Ctrl+N
   c) Enter your DB2 connection details:
      - Host: Your DB2 server hostname or IP
      - Port: Default is 50000
      - Database: Your database name
      - Username: Your DB2 username
      - Password: Your password
   d) Click "Test Connection" to verify
   e) Click "Connect" to open the connection

================================================================================

FILE STRUCTURE
================================================================================

DbExplorer.exe       - Main application
appsettings.json           - Application configuration
nlog.config                - Logging configuration
Resources\                 - Application resources
  └─ DB2SQL.xshd          - SQL syntax highlighting
Samples\                   - Sample SQL scripts
  └─ sample-queries.sql   - Example queries to get started
logs\                      - Application logs (created on first run)
deploy.ps1                 - PowerShell deployment script (optional)
README.txt                 - This file

================================================================================

FEATURES
================================================================================

✓ Multiple Connection Tabs     - Work with multiple databases simultaneously
✓ SQL Syntax Highlighting       - Custom DB2 SQL syntax highlighting
✓ SQL Auto-Formatting           - Format SQL with Ctrl+Shift+F
✓ Query History                 - Automatic tracking of all queries
✓ Database Browser              - Browse schemas and tables
✓ Export Results                - Export to CSV, TSV, JSON, or SQL
✓ Dark/Light/System Themes      - Choose your preferred theme
✓ Settings Dialog               - Customize editor, database, logging
✓ Offline Capable               - No internet connection required
✓ Enterprise Logging            - Comprehensive NLog logging

================================================================================

KEYBOARD SHORTCUTS
================================================================================

Connection Management:
  Ctrl+N              - New Connection
  Ctrl+W              - Close Current Tab
  Ctrl+Tab            - Next Tab
  Ctrl+Shift+Tab      - Previous Tab

SQL Editor:
  F5                  - Execute Query
  Ctrl+Enter          - Execute Current Statement (at cursor)
  Ctrl+Shift+F        - Format SQL
  Ctrl+S              - Save Script
  Ctrl+O              - Open Script

Application:
  Ctrl+D              - Cycle Theme (Dark/Light/System)
  Ctrl+H              - Query History
  Alt+F4              - Exit

================================================================================

CONFIGURATION
================================================================================

Configuration File: appsettings.json

You can customize:
- Editor theme, font, font size, tab size
- Database timeout, pool size
- Logging level, retention period

After making changes, restart the application.

================================================================================

LOGS
================================================================================

Location: logs\db2editor-YYYY-MM-DD.log

The application automatically logs:
- All connection attempts (success/failure)
- Query executions with timing
- Errors and exceptions with details
- Application lifecycle events

Passwords are automatically masked in logs.

Log files are archived daily and retained for 30 days (configurable).

================================================================================

TROUBLESHOOTING
================================================================================

Problem: Application won't start
Solution: 
  - Check Windows Event Viewer for .NET errors
  - Ensure all files from the package are present
  - Try running as Administrator

Problem: Cannot connect to database
Solution:
  - Verify DB2 server is accessible (ping hostname)
  - Check port is open (telnet hostname 50000)
  - Verify credentials are correct
  - Check logs\db2editor-YYYY-MM-DD.log for details

Problem: Syntax highlighting not working
Solution:
  - Verify Resources\DB2SQL.xshd file exists
  - Check logs for file loading errors
  - Restart application

Problem: Queries timeout
Solution:
  - Increase timeout in View → Settings → Database
  - Default is 30 seconds
  - Check network latency to DB2 server

For more troubleshooting, see:
  DEPLOYMENT_GUIDE.md (if included)

================================================================================

SAMPLE QUERIES
================================================================================

Sample SQL queries are included in:
  Samples\sample-queries.sql

These include:
- Basic SELECT statements
- JOIN operations
- Aggregate functions
- System catalog queries
- Date/time functions
- String operations
- And more...

Open these queries in the editor to get started quickly!

================================================================================

SUPPORT
================================================================================

For issues or questions:
1. Check logs\db2editor-YYYY-MM-DD.log
2. Enable DEBUG logging in View → Settings → Logging
3. Review DEPLOYMENT_GUIDE.md for detailed troubleshooting

================================================================================

VERSION INFORMATION
================================================================================

Version:        1.0.0
Framework:      .NET 10
DB2 Package:    Net.IBM.Data.Db2 9.0.0.400
Target:         Windows 11 / Windows 10 (64-bit)
Release Date:   November 2025

================================================================================

LICENSE
================================================================================

Internal use only.

================================================================================

ADDITIONAL DOCUMENTATION
================================================================================

Additional documentation may be available:

- README.md              - Full feature documentation
- DEPLOYMENT_GUIDE.md    - Comprehensive deployment guide
- PROJECT_SUMMARY.md     - Technical implementation details

================================================================================

Thank you for using DbExplorer!

================================================================================

