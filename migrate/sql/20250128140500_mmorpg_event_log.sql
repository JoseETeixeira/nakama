/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Event Log Migration
 *
 * Creates the event_log table for MMORPG crash recovery event sourcing.
 * This table works in conjunction with world_state (task 1.1.5) to enable
 * crash recovery with RPO ≤5s through the checkpoint + event log pattern:
 *
 * Recovery Pattern:
 * 1. Load last checkpoint from world_state (periodic snapshot, every 10s)
 * 2. Replay events from event_log since last checkpoint timestamp
 * 3. Reconstruct zone state with at most 5 seconds of data loss
 *
 * The event_log is append-only (no updates/deletes) to ensure event ordering
 * and auditability. All state-changing events (entity moves, spawns, loot drops,
 * etc.) are written in real-time to this table.
 *
 * Requirements: Requirement 7 (Persistent Zone State)
 * Design Reference: Data Models section - Event Log Table (lines 577-588)
 * Task: 1.1.6 - Create event_log table migration
 */

-- +migrate Up

-- Event Log table for MMORPG crash recovery event sourcing
-- Append-only log of all state-changing events for checkpoint + event log pattern
CREATE TABLE event_log (
  event_id BIGSERIAL PRIMARY KEY,
  zone_id VARCHAR(100) NOT NULL,
  event_type VARCHAR(50) NOT NULL, -- 'entity_move', 'entity_spawn', 'loot_drop', 'npc_death', etc.
  event_data JSONB NOT NULL, -- event-specific payload: entity_id, position, loot_table, etc.
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Composite index for efficient event replay during crash recovery
-- Enables fast queries: SELECT * FROM event_log WHERE zone_id = ? AND timestamp > ? ORDER BY timestamp
CREATE INDEX idx_event_log_zone_time ON event_log(zone_id, timestamp);

-- Table and column comments for documentation
COMMENT ON TABLE event_log IS 'MMORPG crash recovery event log - append-only log of state-changing events for checkpoint + event log pattern (RPO ≤5s)';
COMMENT ON COLUMN event_log.event_id IS 'Auto-incrementing event identifier (primary key) - ensures event ordering';
COMMENT ON COLUMN event_log.zone_id IS 'Zone identifier for event partitioning and replay queries';
COMMENT ON COLUMN event_log.event_type IS 'Event type classifier: entity_move, entity_spawn, entity_despawn, loot_drop, npc_death, resource_harvest, etc.';
COMMENT ON COLUMN event_log.event_data IS 'Event-specific payload as JSONB: entity_id, position, target_id, item_id, quantity, etc.';
COMMENT ON COLUMN event_log.timestamp IS 'Event occurrence timestamp - used with zone_id index for crash recovery event replay';

-- +migrate Down

DROP INDEX IF EXISTS idx_event_log_zone_time;
DROP TABLE IF EXISTS event_log;
