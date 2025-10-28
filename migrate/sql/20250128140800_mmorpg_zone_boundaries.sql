/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Zone Boundaries Migration
 *
 * Creates the zone_boundaries table for seamless cross-region/shard handoff detection.
 * This table defines geographical boundaries between zones, enabling players to travel
 * between regions without relogging by detecting when they cross zone edges.
 *
 * Schema Design:
 * - zone_id: Primary key identifying each zone
 * - neighbors: JSONB array of neighboring zones with boundary trigger boxes
 *   Format: [{zone_id: string, boundary_trigger_box: {min: {x,y,z}, max: {x,y,z}}}, ...]
 * - default_spawn: JSONB coordinates {x, y, z} for new character spawning or handoff fallback
 *
 * Handoff Flow:
 * 1. Server detects player position approaching boundary_trigger_box of a neighbor
 * 2. Server issues handoff token with target zone endpoint
 * 3. Client pre-connects to target zone and finalizes handoff
 * 4. On failure, player respawns at default_spawn coordinates
 *
 * The boundary_trigger_box defines 3D spatial regions where handoff initiation begins.
 * Typically set slightly inside the actual zone edge to give the client time to
 * pre-connect before the visual boundary is crossed (for seamless transition).
 *
 * Requirements: Requirement 18 (Seamless Region/Shard Handoff)
 * Design Reference: Data Models section - Zone Boundaries Table (lines 633-640)
 * Task: 1.1.9 - Create zone_boundaries table migration
 */

-- +migrate Up

-- Zone Boundaries table for cross-region handoff detection
-- Defines neighbor relationships and boundary trigger boxes for seamless zone transitions
CREATE TABLE zone_boundaries (
  zone_id VARCHAR(100) PRIMARY KEY,
  neighbors JSONB, -- array of {zone_id: string, boundary_trigger_box: {min: Vector3, max: Vector3}}
  default_spawn JSONB -- {x: number, y: number, z: number} for new characters or handoff fallback
);

-- Table and column comments for documentation
COMMENT ON TABLE zone_boundaries IS 'Zone neighbor relationships and boundary triggers for seamless cross-region handoffs';
COMMENT ON COLUMN zone_boundaries.zone_id IS 'Unique zone identifier (primary key)';
COMMENT ON COLUMN zone_boundaries.neighbors IS 'JSONB array of neighboring zones with boundary trigger boxes: [{zone_id, boundary_trigger_box: {min: {x,y,z}, max: {x,y,z}}}, ...]';
COMMENT ON COLUMN zone_boundaries.default_spawn IS 'Default spawn coordinates as JSONB {x, y, z} - used for new characters or handoff failure fallback';

-- +migrate Down

DROP TABLE IF EXISTS zone_boundaries;
