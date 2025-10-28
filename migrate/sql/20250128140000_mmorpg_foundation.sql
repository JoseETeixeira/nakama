/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Foundation Migration
 *
 * This migration establishes the foundation for MMORPG-grade features.
 * It creates a metadata table to track MMORPG schema version and configuration.
 *
 * Requirements: All (1-33)
 * Design Reference: Data Models section
 * Task: 1.1.1 - Create database migration framework setup
 */

-- +migrate Up

-- MMORPG schema metadata table
-- Tracks feature flags, schema version, and configuration
CREATE TABLE IF NOT EXISTS mmorpg_schema_meta (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert initial metadata
INSERT INTO mmorpg_schema_meta (key, value) VALUES
    ('schema_version', '{"version": "1.0.0", "phase": "foundation"}'::JSONB),
    ('feature_flags', '{"accounts": false, "characters": false, "world": false, "combat": false, "social": false, "economy": false, "instances": false, "handoffs": false, "liveops": false, "commerce": false}'::JSONB),
    ('performance_targets', '{"zone_tick_hz": 20, "max_entities_per_zone": 1000, "max_ccu_per_shard": 50000, "snapshot_max_kb": 512, "db_write_p95_ms": 30}'::JSONB),
    ('deployment_config', '{"blue_green_enabled": true, "canary_percentage": 10, "rollback_enabled": true}'::JSONB)
ON CONFLICT (key) DO NOTHING;

-- Create index for fast metadata lookups
CREATE INDEX IF NOT EXISTS idx_mmorpg_meta_updated ON mmorpg_schema_meta(updated_at);

COMMENT ON TABLE mmorpg_schema_meta IS 'MMORPG feature set metadata and configuration tracking';

-- +migrate Down

DROP INDEX IF EXISTS idx_mmorpg_meta_updated;
DROP TABLE IF EXISTS mmorpg_schema_meta;
