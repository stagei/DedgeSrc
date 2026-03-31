-- Drop ALL GenericLogHandler tables and EF migration history.
-- Order: dependent tables first (FK constraints), then parent tables.
-- After running, start any service to trigger MigrateAsync() which recreates everything.

DROP TABLE IF EXISTS alert_history;
DROP TABLE IF EXISTS ingest_queue;
DROP TABLE IF EXISTS job_executions;
DROP TABLE IF EXISTS import_status;
DROP TABLE IF EXISTS import_level_filters;
DROP TABLE IF EXISTS import_sources;
DROP TABLE IF EXISTS login_tokens;
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS saved_filters;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS log_entries;
DROP TABLE IF EXISTS "__EFMigrationsHistory";
