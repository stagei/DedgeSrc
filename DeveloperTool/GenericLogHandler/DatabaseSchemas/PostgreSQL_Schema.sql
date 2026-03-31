-- PostgreSQL 12+ Schema for Generic Log Handler
-- Matches EF Core model; all content remains searchable as text.
-- Indexes can be extended later via config (e.g. GIN for full-text).

-- ============================================================================
-- LOG ENTRIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS log_entries (
    id uuid NOT NULL,
    timestamp timestamptz NOT NULL,
    level character varying(10) NOT NULL,
    process_id integer NOT NULL,
    location character varying(500) NOT NULL,
    function_name character varying(200) NOT NULL,
    line_number integer NOT NULL,
    computer_name character varying(100) NOT NULL,
    user_name character varying(200) NOT NULL,
    message text NOT NULL,
    concatenated_search_string text NOT NULL,
    error_id character varying(100),
    alert_id character varying(100),
    ordrenr character varying(50),
    avdnr character varying(50),
    job_name character varying(200),
    exception_type character varying(500),
    stack_trace text,
    inner_exception text,
    command_invocation character varying(1000),
    script_line_number integer,
    script_name character varying(500),
    position integer,
    source_file character varying(500) NOT NULL,
    source_type character varying(50) NOT NULL,
    import_timestamp timestamptz NOT NULL DEFAULT (NOW()),
    import_batch_id character varying(50) NOT NULL,
    CONSTRAINT "PK_log_entries" PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_log_entries_timestamp ON log_entries (timestamp);
CREATE INDEX IF NOT EXISTS idx_log_entries_timestamp_computer_level ON log_entries (timestamp, computer_name, level);
CREATE INDEX IF NOT EXISTS idx_log_entries_computer_name ON log_entries (computer_name);
CREATE INDEX IF NOT EXISTS idx_log_entries_level ON log_entries (level);
CREATE INDEX IF NOT EXISTS idx_log_entries_user_name ON log_entries (user_name);
CREATE INDEX IF NOT EXISTS idx_log_entries_source_type ON log_entries (source_type);
CREATE INDEX IF NOT EXISTS idx_log_entries_error_id ON log_entries (error_id) WHERE error_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_log_entries_alert_id ON log_entries (alert_id) WHERE alert_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_log_entries_ordrenr ON log_entries (ordrenr) WHERE ordrenr IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_log_entries_avdnr ON log_entries (avdnr) WHERE avdnr IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_log_entries_job_name ON log_entries (job_name) WHERE job_name IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_log_entries_import_timestamp ON log_entries (import_timestamp);
CREATE INDEX IF NOT EXISTS idx_log_entries_search_text ON log_entries (concatenated_search_string);

-- ============================================================================
-- IMPORT STATUS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS import_status (
    id uuid NOT NULL,
    source_name character varying(200) NOT NULL,
    source_type character varying(50) NOT NULL,
    file_path character varying(1000) NOT NULL,
    last_processed_timestamp timestamptz,
    last_import_timestamp timestamptz NOT NULL DEFAULT (NOW()),
    records_processed bigint NOT NULL,
    records_failed bigint NOT NULL,
    status text NOT NULL,
    error_message text NOT NULL,
    processing_duration_ms bigint NOT NULL,
    metadata text NOT NULL,
    last_processed_byte_offset bigint NOT NULL DEFAULT 0,
    file_hash character varying(64),
    last_file_size bigint NOT NULL DEFAULT 0,
    file_creation_date timestamp with time zone,
    last_processed_line bigint NOT NULL DEFAULT 0,
    CONSTRAINT "PK_import_status" PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_import_status_source_file ON import_status (source_name, file_path);
CREATE INDEX IF NOT EXISTS idx_import_status_last_import ON import_status (last_import_timestamp);
CREATE INDEX IF NOT EXISTS idx_import_status_status ON import_status (status);

-- ============================================================================
-- SAVED FILTERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS saved_filters (
    id uuid NOT NULL,
    name character varying(200) NOT NULL,
    description character varying(1000),
    filter_json text NOT NULL,
    created_by character varying(200) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT (NOW()),
    updated_at timestamptz,
    is_alert_enabled boolean NOT NULL DEFAULT false,
    alert_config text,
    last_evaluated_at timestamptz,
    last_triggered_at timestamptz,
    is_shared boolean NOT NULL DEFAULT false,
    category character varying(100),
    CONSTRAINT "PK_saved_filters" PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_saved_filters_name ON saved_filters (name);
CREATE INDEX IF NOT EXISTS idx_saved_filters_created_by ON saved_filters (created_by);
CREATE INDEX IF NOT EXISTS idx_saved_filters_alert_enabled ON saved_filters (is_alert_enabled) WHERE is_alert_enabled = true;
CREATE INDEX IF NOT EXISTS idx_saved_filters_category ON saved_filters (category) WHERE category IS NOT NULL;

-- ============================================================================
-- ALERT HISTORY TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS alert_history (
    id uuid NOT NULL,
    filter_id uuid NOT NULL,
    filter_name character varying(200) NOT NULL,
    triggered_at timestamptz NOT NULL DEFAULT (NOW()),
    match_count integer NOT NULL,
    action_type character varying(50) NOT NULL,
    action_taken character varying(2000),
    success boolean NOT NULL,
    error_message text,
    action_response text,
    execution_duration_ms bigint NOT NULL,
    sample_entry_ids text,
    CONSTRAINT "PK_alert_history" PRIMARY KEY (id),
    CONSTRAINT "FK_alert_history_saved_filters" FOREIGN KEY (filter_id) REFERENCES saved_filters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_alert_history_filter_id ON alert_history (filter_id);
CREATE INDEX IF NOT EXISTS idx_alert_history_triggered_at ON alert_history (triggered_at);
CREATE INDEX IF NOT EXISTS idx_alert_history_success ON alert_history (success);
