-- Drop all Generic Log Handler tables (and EF migrations history) so the app can recreate from the latest model.
-- Run once when you want to reset schema to match the current EF model. After running, start the app; Migrate() will recreate tables.
-- Order: drop dependent table first (alert_history), then saved_filters, import_status, log_entries, then migrations history.

DROP TABLE IF EXISTS alert_history;
DROP TABLE IF EXISTS saved_filters;
DROP TABLE IF EXISTS import_status;
DROP TABLE IF EXISTS log_entries;
DROP TABLE IF EXISTS "__EFMigrationsHistory";
