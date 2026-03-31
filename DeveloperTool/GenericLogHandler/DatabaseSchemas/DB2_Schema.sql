-- DB2 12.1 Community Edition Schema for Generic Log Handler
-- This schema is optimized for DB2's capabilities and performance
-- Run this script after creating the database and user

-- Create schema if it doesn't exist
CREATE SCHEMA LOGHANDLER;

-- Set current schema
SET SCHEMA = LOGHANDLER;

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
    command_invocation CLOB,
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

-- Create composite index for common queries
CREATE INDEX idx_log_entries_timestamp_level ON log_entries (timestamp, level);
CREATE INDEX idx_log_entries_computer_timestamp ON log_entries (computer_name, timestamp);

-- Create full-text search index (DB2 Text Search)
CREATE INDEX idx_log_entries_message_fts ON log_entries (message) 
    EXTEND USING (SYSTOOLS.ST_INDEX_EXTENSION);

-- Create table partitioning by month (DB2 12.1 feature)
-- Note: This requires DB2 Enterprise Edition for automatic partitioning
-- For Community Edition, we'll use manual partitioning or rely on indexes

-- Create import status table
CREATE TABLE import_status (
    id INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
    source_name VARCHAR(200) NOT NULL,
    source_type VARCHAR(50) NOT NULL,
    file_path VARCHAR(1000),
    last_processed_timestamp TIMESTAMP,
    last_import_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    records_processed BIGINT DEFAULT 0,
    records_failed BIGINT DEFAULT 0,
    status VARCHAR(50),
    error_message CLOB,
    processing_duration_ms BIGINT,
    metadata CLOB
);

-- Create primary key for import_status
ALTER TABLE import_status ADD CONSTRAINT pk_import_status PRIMARY KEY (id);

-- Create indexes for import_status
CREATE INDEX idx_import_status_source_file ON import_status (source_name, file_path);
CREATE INDEX idx_import_status_last_import ON import_status (last_import_timestamp);
CREATE INDEX idx_import_status_status ON import_status (status);

-- Create statistics for query optimization
RUNSTATS ON TABLE log_entries;
RUNSTATS ON TABLE import_status;

-- Grant permissions (adjust as needed)
GRANT SELECT, INSERT, UPDATE, DELETE ON log_entries TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON import_status TO PUBLIC;
