# Logging Tool Specification

## Overview
This document outlines the specifications for a comprehensive logging tool that can import, store, and search large volumes of log data (2+ million entries per day) with professional web-based interface for log analysis.

## 1. Log Import Functionality

### 1.1 Configuration Management
- **Configuration File**: JSON-based configuration file defining all import sources and settings
- **Dynamic Configuration**: Support for reloading configuration without service restart
- **Validation**: Configuration validation with detailed error reporting

### 1.2 Supported Import Sources

#### 1.2.1 File-Based Imports
- **JSON Files**: Native JSON parsing with customizable field mapping
- **Log Files**: Support for common log formats (Apache, IIS, custom formats)
- **XML Files**: XML parsing with XPath support for field extraction

#### 1.2.2 Database Imports
- **IBM DB2 12.1**: Direct connection using IBM DB2 client
- **ODBC Support**: Generic ODBC connectivity for other databases
- **Query Configuration**: Custom SQL queries defined in configuration

#### 1.2.3 Real-time Monitoring
- **File Watching**: Monitor directories for new files
- **Incremental Processing**: Track processing state to avoid duplicates
- **Error Handling**: Robust error handling with retry mechanisms

### 1.3 Data Processing Pipeline
- **Field Mapping**: Configurable field mapping from source to target schema
- **Data Transformation**: Built-in transformation functions (date parsing, text normalization)
- **Concatenated Strings**: Generate searchable concatenated strings for regex searches
- **Validation**: Data validation and cleansing before storage

## 2. Database Storage Solution

### 2.1 Primary Database: IBM DB2 12.1 Community Edition
**Rationale**: Enterprise-grade database with excellent performance for analytical workloads, capable of handling 2+ million records per day with robust reliability and advanced features.

#### Key Features:
- **Enterprise Reliability**: Proven enterprise database with high availability
- **Advanced Analytics**: Built-in analytical functions and optimization
- **Compression**: Advanced compression algorithms for log data
- **Scalability**: Vertical and horizontal scaling capabilities
- **SQL Support**: Full SQL compliance with advanced features
- **Free Community Edition**: No licensing costs for development and small deployments
- **Text Search**: Built-in full-text search capabilities
- **Partitioning**: Advanced table partitioning for large datasets

### 2.3 Database Schema Design
```sql
-- DB2 12.1 Community Edition Schema for Generic Log Handler
CREATE TABLE log_entries (
    -- Basic Information
    id CHAR(36) NOT NULL DEFAULT (GENERATE_UNIQUE()),
    timestamp TIMESTAMP(3) NOT NULL,
    level VARCHAR(10) NOT NULL CHECK (level IN ('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')),
    process_id INTEGER,
    location VARCHAR(255),
    function_name VARCHAR(255),
    line_number INTEGER,
    
    -- Environment Details
    computer_name VARCHAR(255),
    user_name VARCHAR(255),
    
    -- Message Content
    message CLOB,
    concatenated_search_string CLOB,
    
    -- Exception Details (nullable)
    error_id VARCHAR(255),
    exception_type VARCHAR(255),
    stack_trace CLOB,
    inner_exception CLOB,
    command_invocation VARCHAR(1000),
    script_line_number INTEGER,
    script_name VARCHAR(255),
    position INTEGER,
    
    -- Metadata
    source_file VARCHAR(255),
    import_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create primary key
ALTER TABLE log_entries ADD CONSTRAINT pk_log_entries PRIMARY KEY (id);

-- Create indexes for performance
CREATE INDEX idx_log_entries_timestamp ON log_entries (timestamp);
CREATE INDEX idx_log_entries_computer_name ON log_entries (computer_name);
CREATE INDEX idx_log_entries_level ON log_entries (level);
CREATE INDEX idx_log_entries_user_name ON log_entries (user_name);
CREATE INDEX idx_log_entries_import_timestamp ON log_entries (import_timestamp);

-- Create composite indexes for common queries
CREATE INDEX idx_log_entries_timestamp_level ON log_entries (timestamp, level);
CREATE INDEX idx_log_entries_computer_timestamp ON log_entries (computer_name, timestamp);

-- Create full-text search index (DB2 Text Search)
CREATE INDEX idx_log_entries_message_fts ON log_entries (message) 
    EXTEND USING (SYSTOOLS.ST_INDEX_EXTENSION);

-- Create statistics for query optimization
RUNSTATS ON TABLE log_entries;
```

## 3. Data Retention Management

### 3.1 Automated Cleanup
- **DB2 Partitioning**: Table partitioning by time periods for efficient data management
- **Configurable Retention**: Retention period defined in JSON configuration
- **Archival Options**: Optional archival to cold storage before deletion using DB2 utilities
- **Monitoring**: Retention monitoring and alerting with DB2 system tables
- **Automated Cleanup**: Scheduled jobs for data purging based on retention policies

### 3.2 Configuration Example
```json
{
  "retention": {
    "default_days": 90,
    "by_level": {
      "ERROR": 180,
      "WARN": 120,
      "INFO": 90,
      "DEBUG": 30
    },
    "archive_before_delete": true,
    "archive_location": "C:\\opt\\data\\LogArchive"
  }
}
```

## 4. Web Interface Specifications

### 4.1 Technology Stack Recommendation
- **Backend**: ASP.NET Core Web API (for Windows Server integration)
- **Frontend**: React.js with TypeScript
- **Authentication**: Windows Authentication integration
- **Deployment**: IIS hosting on Windows Server 2025

### 4.2 Core Features

#### 4.2.1 Search and Filtering
- **Date Range Picker**: Calendar-based date selection
- **Field Filters**: 
  - Computer Name (dropdown with autocomplete)
  - Exception Text (text search)
  - Username (dropdown with autocomplete)
  - Log Level (multi-select)
  - Message Text (full-text search)
- **Advanced Search**: Regex support on concatenated search strings
- **Saved Searches**: Save and recall frequently used search criteria

#### 4.2.2 Results Display
- **Grid View**: Paginated results with configurable page size
- **Quick Filters**: One-click filters from result columns
- **Export Options**: CSV, JSON, Excel export
- **Real-time Updates**: Optional auto-refresh for recent logs

#### 4.2.3 Detail View
- **Popup Modal**: Click on any log entry opens detailed view in modal
- **Full Field Display**: All available fields with proper formatting
- **Related Logs**: Links to related log entries (same process, timeframe)
- **Actions**: Copy, export single entry, create filter from values

### 4.3 User Interface Mockup
```
┌─────────────────────────────────────────────────────────┐
│ Log Analysis Dashboard                    [User] [Logout]│
├─────────────────────────────────────────────────────────┤
│ Search Filters:                                         │
│ [Date From] [Date To] [Computer▼] [Level▼] [User▼]     │
│ Message: [____________] Regex: [____________] [Search]   │
├─────────────────────────────────────────────────────────┤
│ Timestamp        │Level│Computer│User   │Message         │
│ 2024-01-15 10:30 │ERR  │SRV001  │admin  │Database conn...│
│ 2024-01-15 10:29 │WARN │SRV002  │user1  │High memory...  │
│ 2024-01-15 10:28 │INFO │SRV001  │admin  │Service started │
├─────────────────────────────────────────────────────────┤
│ [Prev] Page 1 of 50 [Next]     Export: [CSV][JSON][XLS]│
└─────────────────────────────────────────────────────────┘
```

## 5. Configuration File Specifications

### 5.1 Master Configuration Structure
```json
{
  "version": "1.0",
  "general": {
    "service_name": "LoggingService",
    "log_level": "INFO",
    "max_concurrent_imports": 4
  },
  "database": {
    "connection_string": "tcp://localhost:9000",
    "database_name": "logs",
    "connection_timeout": 30,
    "batch_size": 1000
  },
  "retention": {
    "default_days": 90,
    "cleanup_schedule": "0 2 * * *"
  },
  "import_sources": [
    {
      "name": "PowerShell Logs",
      "type": "file",
      "enabled": true,
      "config": {
        "path": "C:\\opt\\data\\AllPwshLog\\*.log",
        "format": "custom",
        "parser": "powershell_log_parser",
        "watch_directory": true,
        "encoding": "utf-8"
      }
    },
    {
      "name": "Application JSON Logs",
      "type": "file",
      "enabled": true,
      "config": {
        "path": "C:\\opt\\logs\\app\\*.json",
        "format": "json",
        "watch_directory": true
      }
    },
    {
      "name": "DB2 Application Logs",
      "type": "database",
      "enabled": true,
      "config": {
        "connection_string": "Server=db2server;Database=LOGDB;Uid=loguser;Pwd=password;",
        "query": "SELECT * FROM APPLICATION_LOGS WHERE LOG_DATE > ?",
        "poll_interval": 300,
        "incremental_column": "LOG_DATE"
      }
    }
  ],
  "field_mappings": {
    "powershell_log_parser": {
      "timestamp": "$.timestamp",
      "level": "$.level",
      "computer_name": "$.computerName",
      "message": "$.message",
      "concatenated_search": "CONCAT(computerName, ' ', user, ' ', message)"
    }
  }
}
```

## 6. Recommended Tool Evaluation

### 6.1 Option 1: Custom Solution (Recommended)
**Components**:
- **Import Service**: Custom .NET service using the configuration above
- **Database**: ClickHouse for storage
- **Web Interface**: ASP.NET Core + React

**Pros**:
- Full control over functionality
- Perfect fit for requirements
- Windows Server 2025 native integration
- Leverages existing PowerShell infrastructure

**Cons**:
- Development effort required
- Ongoing maintenance

### 6.2 Option 2: Graylog (Alternative)
**Open-source log management platform**

**Pros**:
- Mature platform with web interface
- Good search capabilities
- Active community

**Cons**:
- May require significant configuration
- Less control over data schema
- Additional complexity for DB2 integration

### 6.3 Option 3: ELK Stack (Elasticsearch, Logstash, Kibana)
**Popular open-source logging stack**

**Pros**:
- Excellent search capabilities
- Rich visualization options
- Large ecosystem

**Cons**:
- Resource intensive
- Complex configuration
- Java dependency

## 7. Implementation Phases

### Phase 1: Core Infrastructure
1. Set up ClickHouse database
2. Implement basic import service
3. Create configuration management
4. Implement file-based imports (JSON, logs, XML)

### Phase 2: Database Integration
1. Add DB2 connectivity
2. Implement incremental processing
3. Add data validation and transformation

### Phase 3: Web Interface
1. Create basic search interface
2. Implement filtering and pagination
3. Add detail view popup
4. Implement export functionality

### Phase 4: Advanced Features
1. Add real-time monitoring
2. Implement advanced search (regex)
3. Add user management
4. Performance optimization

## 8. Deployment Requirements

### 8.1 System Requirements
- **OS**: Windows Server 2025
- **RAM**: 16GB minimum (32GB recommended for 2M+ daily logs)
- **Storage**: SSD recommended, 1TB+ for log storage
- **CPU**: 4+ cores recommended

### 8.2 Software Dependencies
- **.NET 8 Runtime**
- **ClickHouse Server**
- **IIS** (for web interface)
- **IBM DB2 Client** (for DB2 connectivity)

### 8.3 Security Considerations
- **Windows Authentication** integration
- **HTTPS** enforcement
- **Input validation** for all user inputs
- **SQL injection** protection
- **Access logging** for audit trails

## 9. Estimated Development Timeline

- **Phase 1**: 4-6 weeks
- **Phase 2**: 2-3 weeks  
- **Phase 3**: 6-8 weeks
- **Phase 4**: 3-4 weeks
- **Testing & Deployment**: 2-3 weeks

**Total**: 17-24 weeks for complete custom solution

## 10. Alternative: Quick Start with Existing Tools

If immediate deployment is needed, consider starting with **Graylog** or **Grafana Loki** as they can be configured to meet most requirements with less development effort, then migrate to a custom solution later if needed.

## 11. COBNT / WKMONIT log format (4-digit severity code)

Log files such as `\\DEDGE.fk.no\erpprog\COBNT\WKMONIT.LOG` use a fixed-width style with a **4-digit numeric code** in place of a text level. When parsing or mapping these logs to the generic schema (`level` = TRACE, DEBUG, INFO, WARN, ERROR, FATAL), use this mapping:

| Code range   | Severity  | Map to generic level |
|--------------|-----------|----------------------|
| **0000**     | Info      | INFO                 |
| **0001–0016**| Warning   | WARN                 |
| **0017–9999**| Error     | ERROR (or FATAL for 9999 if desired) |

Example line: `00:01 P-NO1FKMPR 0000 00:01:00 STARTER PRODSETTING!` → code **0000** = Info.  
Example: `02:01 WKOPTORD 9999 OSBSEOP FEIL VED START AV DATABASE` → code **9999** = Error.
