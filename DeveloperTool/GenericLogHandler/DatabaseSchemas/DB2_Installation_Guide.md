# IBM DB2 12.1 Community Edition Installation Guide

## Overview
This guide covers the installation and configuration of IBM DB2 12.1 Community Edition for the Generic Log Handler system.

## Prerequisites
- Windows Server 2019/2022 or Windows 10/11
- Minimum 4GB RAM (8GB recommended)
- 10GB free disk space
- Administrator privileges

## Installation Steps

### 1. Download DB2 Community Edition
1. Visit: https://www.ibm.com/support/pages/db2-community-edition
2. Download: `db2-community-edition-12.1.0.0-windows-x64.exe`
3. File size: ~1.2GB

### 2. Install DB2
```powershell
# Run the installer with silent installation
.\db2-community-edition-12.1.0.0-windows-x64.exe /SILENT
```

### 3. Post-Installation Configuration

#### 3.1 Create Database Instance
```cmd
# Open DB2 Command Line Processor
db2cmd

# Create database for logs
db2 CREATE DATABASE LOGS

# Connect to the database
db2 CONNECT TO LOGS

# Create schema
db2 CREATE SCHEMA LOGHANDLER
```

#### 3.2 Create Database User
```sql
-- Create user for application
CREATE USER loghandler IDENTIFIED BY 'SecurePassword123!';

-- Grant necessary privileges
GRANT CONNECT ON DATABASE TO loghandler;
GRANT CREATETAB ON DATABASE TO loghandler;
GRANT IMPLICIT_SCHEMA ON DATABASE TO loghandler;
GRANT USE ON TABLESPACE USERSPACE1 TO loghandler;
```

### 4. Configure Connection String
Update your `appsettings.json`:
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost:50000;Database=LOGS;UID=loghandler;PWD=SecurePassword123!;Security=SSL;"
  }
}
```

### 5. Create Database Schema
Run the schema creation script:
```sql
-- Execute the DB2_Schema.sql file
db2 -tf DatabaseSchemas/DB2_Schema.sql
```

## Configuration Options

### Memory Settings
```sql
-- Configure buffer pool size (adjust based on available RAM)
UPDATE DBM CFG USING SORTHEAP 256
UPDATE DBM CFG USING SHEAPTHRES 0
```

### Logging Settings
```sql
-- Enable audit logging
UPDATE DBM CFG USING AUDIT_BUF_SZ 1024
UPDATE DBM CFG USING AUDIT_ERR_CONTINUE ON
```

## Troubleshooting

### Common Issues

#### 1. Connection Refused
- Ensure DB2 service is running: `db2start`
- Check port 50000 is not blocked by firewall
- Verify user credentials

#### 2. Permission Denied
- Ensure user has CONNECT privilege
- Check database permissions
- Verify schema access

#### 3. Performance Issues
- Run `RUNSTATS` on tables regularly
- Monitor buffer pool hit ratio
- Consider table partitioning for large datasets

### Useful Commands
```cmd
# Start DB2 instance
db2start

# Stop DB2 instance
db2stop

# Check instance status
db2 get dbm cfg

# List databases
db2 list db directory

# Connect to database
db2 connect to LOGS user loghandler using 'SecurePassword123!'

# Run statistics
db2 runstats on table LOGHANDLER.LOG_ENTRIES
```

## Security Considerations

### 1. User Management
- Use strong passwords
- Implement least privilege principle
- Regular password rotation

### 2. Network Security
- Enable SSL connections
- Restrict network access
- Use firewall rules

### 3. Database Security
- Enable audit logging
- Regular security updates
- Monitor access logs

## Performance Optimization

### 1. Indexing Strategy
- Create indexes on frequently queried columns
- Use composite indexes for multi-column queries
- Regular index maintenance

### 2. Partitioning
- Consider table partitioning for large datasets
- Use date-based partitioning for time-series data
- Implement partition pruning

### 3. Monitoring
- Monitor buffer pool performance
- Track query execution times
- Regular statistics updates

## Backup and Recovery

### 1. Database Backup
```cmd
# Full database backup
db2 backup database LOGS to /backup/path

# Incremental backup
db2 backup database LOGS incremental to /backup/path
```

### 2. Restore Database
```cmd
# Restore from backup
db2 restore database LOGS from /backup/path
```

## Support Resources

- IBM DB2 Documentation: https://www.ibm.com/docs/en/db2
- DB2 Community Forum: https://community.ibm.com/community/user/hybriddatamanagement/communities/community-home
- Stack Overflow: Tag `db2`
