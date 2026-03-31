-- ============================================================================
-- Verification queries for Phase 7: Alert Verification
-- ============================================================================

-- 1. Total alert history records
SELECT 'alert_history_count' AS check_name, COUNT(*)::text AS check_value
FROM alert_history;

-- 2. Successful alerts
SELECT 'successful_alerts' AS check_name, COUNT(*)::text AS check_value
FROM alert_history WHERE success = true;

-- 3. Alert for ORDER_SYNC_FAIL filter
SELECT 'order_sync_fail_alerts' AS check_name, COUNT(*)::text AS check_value
FROM alert_history WHERE filter_name LIKE '%ORDER_SYNC_FAIL%';

-- 4. Alert for DB_CONN_LOST filter
SELECT 'db_conn_lost_alerts' AS check_name, COUNT(*)::text AS check_value
FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST%';

-- 5. Match count for ORDER_SYNC_FAIL (should be >= 3, the threshold)
SELECT 'order_sync_fail_match_count' AS check_name, COALESCE(MAX(match_count), 0)::text AS check_value
FROM alert_history WHERE filter_name LIKE '%ORDER_SYNC_FAIL%' AND success = true;

-- 6. Match count for DB_CONN_LOST (should be >= 2, the threshold)
SELECT 'db_conn_lost_match_count' AS check_name, COALESCE(MAX(match_count), 0)::text AS check_value
FROM alert_history WHERE filter_name LIKE '%DB_CONN_LOST%' AND success = true;

-- 7. Saved filters with alert enabled
SELECT 'alert_enabled_filters' AS check_name, COUNT(*)::text AS check_value
FROM saved_filters WHERE is_alert_enabled = true;

-- 8. Filters that have been evaluated
SELECT 'filters_evaluated' AS check_name, COUNT(*)::text AS check_value
FROM saved_filters WHERE is_alert_enabled = true AND last_evaluated_at IS NOT NULL;

-- 9. Filters that have been triggered
SELECT 'filters_triggered' AS check_name, COUNT(*)::text AS check_value
FROM saved_filters WHERE is_alert_enabled = true AND last_triggered_at IS NOT NULL;

-- 10. Alert detail view
SELECT
    ah.filter_name,
    ah.match_count,
    ah.action_type,
    ah.success,
    ah.triggered_at,
    ah.execution_duration_ms,
    sf.last_evaluated_at,
    sf.last_triggered_at
FROM alert_history ah
JOIN saved_filters sf ON ah.filter_id = sf.id
ORDER BY ah.triggered_at;
