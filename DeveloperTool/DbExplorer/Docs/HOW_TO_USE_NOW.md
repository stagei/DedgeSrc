# How to Use DbExplorer - Quick Start Guide

**Your new DB2 DBA toolkit is ready to use!**

---

## 🚀 Getting Started

### Step 1: Launch the Application
```bash
bin\Debug\net10.0-windows\DbExplorer.exe
```

Or double-click `DbExplorer.exe` in File Explorer

### Step 2: Create a Connection
1. Click **"New Connection"** button (or File → New Connection)
2. Enter your DB2 connection details:
   - Connection Name: `My Database`
   - Server: `your-db2-server`
   - Port: `50000`
   - Database: `TESTDB`
   - Username: `your-username`
   - Password: `your-password`
3. **Optional:** Check "Read-Only Mode" for safe browsing
4. **Optional:** Uncheck "Auto-Commit" for manual transaction control
5. Click **"Connect"**

**Your access level badge will appear in the toolbar:**
- 🛡️ DBA (Green) - Full access
- 👤 USER (Orange) - DML access
- 🔒 READ-ONLY (Red) - SELECT only

---

## 📊 Available Features (View Menu)

### Database Load Monitor
**What it does:** Real-time table activity monitoring  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → Database Load Monitor
2. Select schema (* = all)
3. Select table (* = all)
4. Check "Exclude System Schemas"
5. Click Refresh
6. See reads/inserts/updates/deletes per table
7. Export to CSV if needed
8. Enable auto-refresh for real-time monitoring

### Lock Monitor
**What it does:** View and manage database locks  
**Access Level:** DBA only  
**How to use:**
1. View → Lock Monitor
2. Filter by schema/table if needed
3. Check "Show only blocked locks" for problem detection
4. Click Refresh to see current locks
5. Select locks → Generate Force Application script
6. Export lock data to CSV

### Statistics Manager
**What it does:** View table statistics and generate RUNSTATS  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → Statistics Manager
2. Select schema
3. Check "Show only outdated" to find stale stats
4. Click Refresh
5. Select tables → Generate RUNSTATS script
6. Copy script or save to file

### Active Sessions
**What it does:** Monitor active database connections  
**Access Level:** DBA only  
**How to use:**
1. View → Active Sessions
2. Filter by user or application
3. See connection duration for each session
4. Select sessions → Generate Force Application script
5. Export session list

### CDC Manager
**What it does:** Manage Change Data Capture settings  
**Access Level:** DBA only  
**How to use:**
1. View → CDC Manager
2. Select schema
3. Check "Show only disabled" to find tables without CDC
4. Generate ENABLE or DISABLE scripts
5. Review and execute ALTER TABLE commands

### Unused Objects Detector
**What it does:** Find tables/packages not used in X days  
**Access Level:** DBA only  
**How to use:**
1. View → Unused Objects
2. Set threshold (default: 365 days)
3. Check "Include Packages"
4. Click Refresh
5. Review unused objects
6. Generate DROP script (REVIEW CAREFULLY!)
7. Export list for review

### Source Code Browser
**What it does:** Browse and export DB2 source code  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → Source Code Browser
2. Select schema
3. Choose object type (Procedures/Functions/Views)
4. Click on object to view source code
5. Copy to clipboard or export to .sql file

### DDL Generator
**What it does:** Generate CREATE TABLE DDL  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → DDL Generator
2. Select schema
3. Select table
4. OR check "Generate entire schema DDL"
5. Click "Generate DDL"
6. Copy or save the DDL script

### Comment Manager
**What it does:** View and manage table/column comments  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → Comment Manager
2. Select schema
3. View all table and column comments
4. Generate COMMENT ON statements
5. Export comments to CSV

### Package Analyzer
**What it does:** Analyze DB2 packages and SQL statements  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → Package Analyzer
2. Select schema
3. Click on package to view embedded SQL statements
4. Export package list

### Dependency Analyzer
**What it does:** Analyze table dependencies  
**Access Level:** USER (Middle+)  
**How to use:**
1. View → Dependency Analyzer
2. Select schema and table
3. Click "Analyze"
4. View incoming and outgoing dependencies
5. Generate dependency-ordered DROP script
6. Export dependency map

### Migration Assistant
**What it does:** Plan schema migrations based on usage  
**Access Level:** DBA only  
**How to use:**
1. View → Migration Assistant
2. Select schema
3. Set activity threshold (years)
4. Click "Analyze"
5. See which tables are active vs. candidates for archiving
6. Generate migration plan
7. Export candidate list

---

## 🖥️ CLI Usage

### Execute Query and Export
```bash
DbExplorer.exe -Profile "TESTDB" -Sql "SELECT * FROM SYSCAT.TABLES FETCH FIRST 10 ROWS ONLY" -Outfile "tables.json"
```

### Export to CSV
```bash
DbExplorer.exe -Profile "TESTDB" -Sql "SELECT * FROM SYSCAT.COLUMNS WHERE TABNAME = 'CUSTOMERS'" -Outfile "columns.csv" -Format csv
```

### Collect Metadata
```bash
DbExplorer.exe -Profile "TESTDB" -CollectMetadata
```

### Show Help
```bash
DbExplorer.exe -Help
```

---

## 🔒 Access Levels Explained

**🛡️ DBA (Green Badge):**
- See all 12 panels
- Can execute DDL, DML, force disconnect, RUNSTATS
- Full access to everything

**👤 USER (Orange Badge):**
- See 9 panels (no force disconnect features)
- Can execute DML (INSERT, UPDATE, DELETE, SELECT)
- Cannot execute DDL (CREATE, DROP, ALTER)
- Cannot force disconnect sessions
- All monitoring is view-only

**🔒 READ-ONLY (Red Badge):**
- Can execute SELECT only
- Can view properties and metadata
- Cannot modify any data
- All features are view-only

---

## 💡 Tips

1. **Use Read-Only Mode** when browsing production databases
2. **Uncheck Auto-Commit** when making changes you want to review
3. **Enable Auto-Refresh** in monitoring panels for real-time updates
4. **Export to CSV** for further analysis in Excel
5. **Generate scripts** before executing to review changes
6. **Check your access badge** to know what operations are allowed

---

## 📝 Where Everything Is

**Connection Profiles:** `%LOCALAPPDATA%\DbExplorer\connection_profiles.json`  
**Metadata Cache:** `%LOCALAPPDATA%\DbExplorer\metadata\`  
**Logs:** `logs\` directory  
**Config:** `appsettings.json` and `nlog.config`

---

## 🎯 YOU'RE READY!

**Everything works. Start using your new DB2 DBA toolkit now!** 🚀

**For questions or issues:**
- Check logs in `logs\` directory
- All errors are logged with DEBUG level
- Review NEXTSTEPS.md for implementation details
- Review TASKLIST.md for feature checklist

---

**Enjoy your professional-grade DB2 management tool!** 🎊

