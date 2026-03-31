-- SQL Server Schema for Generic Log Handler
-- Optimized for SQL Server with columnstore indexes and partitioning

CREATE TABLE log_entries (
    -- Basic Information
    id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    timestamp DATETIME2(3) NOT NULL,
    level VARCHAR(10) NOT NULL CHECK (level IN ('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')),
    process_id INT,
    location NVARCHAR(255),
    function_name NVARCHAR(255),
    line_number INT,
    
    -- Environment Details
    computer_name NVARCHAR(255),
    user_name NVARCHAR(255),
    
    -- Message Content
    message NVARCHAR(MAX),
    concatenated_search_string NVARCHAR(MAX),
    
    -- Exception Details (nullable)
    error_id NVARCHAR(255),
    exception_type NVARCHAR(255),
    stack_trace NVARCHAR(MAX),
    inner_exception NVARCHAR(MAX),
    command_invocation NVARCHAR(MAX),
    script_line_number INT,
    script_name NVARCHAR(255),
    position INT,
    
    -- Metadata
    source_file NVARCHAR(255),
    import_timestamp DATETIME2 DEFAULT GETDATE()
);

-- Create primary key
ALTER TABLE log_entries ADD CONSTRAINT pk_log_entries PRIMARY KEY (id);

-- Create regular indexes for OLTP operations
CREATE INDEX idx_log_entries_timestamp ON log_entries (timestamp);
CREATE INDEX idx_log_entries_computer_name ON log_entries (computer_name);
CREATE INDEX idx_log_entries_level ON log_entries (level);
CREATE INDEX idx_log_entries_user_name ON log_entries (user_name);
CREATE INDEX idx_log_entries_import_timestamp ON log_entries (import_timestamp);

-- Create composite indexes for common query patterns
CREATE INDEX idx_log_entries_timestamp_level ON log_entries (timestamp, level);
CREATE INDEX idx_log_entries_computer_timestamp ON log_entries (computer_name, timestamp);

-- Create columnstore index for analytical queries (SQL Server 2012+)
-- This provides excellent compression and performance for analytical workloads
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_log_entries_columnstore 
ON log_entries (
    timestamp, level, computer_name, user_name, 
    message, concatenated_search_string, 
    error_id, exception_type, source_file
);

-- Create full-text search catalog and index
CREATE FULLTEXT CATALOG log_entries_ftc;
CREATE FULLTEXT INDEX ON log_entries (
    message, concatenated_search_string, stack_trace, 
    inner_exception, command_invocation
) KEY INDEX pk_log_entries ON log_entries_ftc;

-- Create partitioning function and scheme for time-based partitioning
-- This helps with data retention and query performance
CREATE PARTITION FUNCTION pf_log_entries_monthly (DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-02-01', '2024-03-01', '2024-04-01', 
    '2024-05-01', '2024-06-01', '2024-07-01', '2024-08-01',
    '2024-09-01', '2024-10-01', '2024-11-01', '2024-12-01'
);

CREATE PARTITION SCHEME ps_log_entries_monthly
AS PARTITION pf_log_entries_monthly
ALL TO ([PRIMARY]);

-- Note: To use partitioning, you would need to recreate the table with the partition scheme
-- This is a simplified version for demonstration

-- Create statistics for query optimization
UPDATE STATISTICS log_entries;

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON log_entries TO PUBLIC;
