-- ============================================================================
-- Verification queries for Phase 4: Import Verification
-- Each query returns a label and value for assertion in the orchestrator.
-- ============================================================================

-- 1. Total log entries count
SELECT 'total_log_entries' AS check_name, COUNT(*)::text AS check_value FROM log_entries;

-- 2. TEST-SERVER file entries
SELECT 'test_server_entries' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE source_file LIKE '%TEST-SERVER%';

-- 3. PROD-DB01 file entries
SELECT 'prod_db01_entries' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE source_file LIKE '%PROD-DB01%';

-- 4. ALERT-TEST-SRV entries
SELECT 'alert_test_entries' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE source_file LIKE '%alert-trigger%';

-- 5. API ingest entries
SELECT 'api_ingest_entries' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE source_type = 'api-ingest';

-- 6. Level distribution
SELECT 'level_' || level::text AS check_name, COUNT(*)::text AS check_value
FROM log_entries GROUP BY level ORDER BY level;

-- 7. Ordrenr extraction (non-null ordrenr values)
SELECT 'ordrenr_extracted' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE ordrenr IS NOT NULL AND ordrenr != '';

-- 8. Avdnr extraction
SELECT 'avdnr_extracted' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE avdnr IS NOT NULL AND avdnr != '';

-- 9. AlertId extraction
SELECT 'alertid_extracted' AS check_name, COUNT(*)::text AS check_value
FROM log_entries WHERE alert_id IS NOT NULL AND alert_id != '';

-- 10. Job correlation records
SELECT 'job_executions_count' AS check_name, COUNT(*)::text AS check_value
FROM job_executions;

-- 11. Job status tracking
SELECT 'job_' || LOWER(REPLACE(job_name, ' ', '_')) AS check_name, status AS check_value
FROM job_executions ORDER BY started_at;

-- 12. Ingest queue drained
SELECT 'ingest_queue_remaining' AS check_name, COUNT(*)::text AS check_value
FROM ingest_queue;

-- 13. Import status records
SELECT 'import_status_count' AS check_name, COUNT(*)::text AS check_value
FROM import_status;

-- 14. Distinct computer names
SELECT 'distinct_computers' AS check_name, COUNT(DISTINCT computer_name)::text AS check_value
FROM log_entries;

-- 15. Distinct source files
SELECT 'distinct_source_files' AS check_name, COUNT(DISTINCT source_file)::text AS check_value
FROM log_entries;
