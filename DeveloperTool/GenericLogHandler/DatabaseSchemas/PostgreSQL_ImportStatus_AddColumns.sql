-- Add columns to import_status if they are missing (e.g. DB created from older schema).
-- Run once against your PostgreSQL database. Safe to run multiple times (IF NOT EXISTS).

ALTER TABLE import_status ADD COLUMN IF NOT EXISTS last_processed_byte_offset bigint NOT NULL DEFAULT 0;
ALTER TABLE import_status ADD COLUMN IF NOT EXISTS file_hash character varying(64);
ALTER TABLE import_status ADD COLUMN IF NOT EXISTS last_file_size bigint NOT NULL DEFAULT 0;
ALTER TABLE import_status ADD COLUMN IF NOT EXISTS file_creation_date timestamp with time zone;
ALTER TABLE import_status ADD COLUMN IF NOT EXISTS last_processed_line bigint NOT NULL DEFAULT 0;
