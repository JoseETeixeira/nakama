/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - World State Migration
 *
 * Creates the world_state table for MMORPG zone checkpoint persistence.
 * This table stores periodic snapshots of zone state (NPCs, resources, timers)
 * as JSONB. Combined with the event_log table (task 1.1.6), it enables crash
 * recovery with RPO ≤5s by loading the last checkpoint and replaying events.
 *
 * The checkpoint pattern:
 * - Every 10 seconds: full zone state snapshot persisted to world_state
 * - Real-time: state-changing events appended to event_log
 * - On crash: restore from last checkpoint + replay events since checkpoint
 * - On safe shutdown: persist final checkpoint before termination
 *
 * Requirements: Requirement 7 (Persistent Zone State)
 * Design Reference: Data Models section - World State Table (lines 563-575)
 * Task: 1.1.5 - Create world_state table migration
 */

-- +migrate Up

-- World State table for MMORPG zone checkpoint persistence
-- Stores periodic snapshots of zone state for crash recovery (RPO ≤5s, RTO ≤5min)
CREATE TABLE world_state (
  zone_id VARCHAR(100) PRIMARY KEY,
  shard_id VARCHAR(50) NOT NULL,
  state_json JSONB NOT NULL, -- full zone state snapshot: entities, NPCs, resources, timers
  version BIGINT DEFAULT 1,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  checkpoint_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for shard-based queries and filtering
CREATE INDEX idx_world_state_shard ON world_state(shard_id);

-- Table and column comments for documentation
COMMENT ON TABLE world_state IS 'MMORPG zone checkpoint persistence - stores periodic snapshots for crash recovery with RPO ≤5s';
COMMENT ON COLUMN world_state.zone_id IS 'Unique zone identifier (primary key)';
COMMENT ON COLUMN world_state.shard_id IS 'Shard identifier for multi-shard deployments and horizontal scaling';
COMMENT ON COLUMN world_state.state_json IS 'Full zone state snapshot as JSONB: entities, NPCs, resource nodes, environmental state, timers';
COMMENT ON COLUMN world_state.version IS 'Checkpoint version number - incremented on each snapshot for consistency tracking';
COMMENT ON COLUMN world_state.updated_at IS 'Timestamp of last state modification (any change to zone state)';
COMMENT ON COLUMN world_state.checkpoint_at IS 'Timestamp of last checkpoint persistence (typically every 10 seconds)';

-- +migrate Down

DROP INDEX IF EXISTS idx_world_state_shard;
DROP TABLE IF EXISTS world_state;
