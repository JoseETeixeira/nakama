/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Loot System Migration
 *
 * Creates the loot tables for server-authoritative drop generation.
 * The loot system uses relational tables to define what items can drop
 * from NPCs, bosses, and resource nodes, with configurable drop chances
 * and quantity ranges.
 *
 * Schema Design:
 * - drop_tables: Defines named drop table configurations (e.g., "goblin_common")
 * - drop_table_items: Relates drop tables to items with drop chances and quantities
 * - Supports nested drop tables for rare loot via self-referencing
 *
 * Requirements: Requirement 17 (Drop Tables and Loot Generation)
 * Design Reference: Economy Service - Loot Generation (lines 390-422)
 * Task: 4.6.1 - Create drop table configuration
 */

-- +migrate Up

-- Drop tables define loot configurations for NPCs, bosses, resource nodes, etc.
CREATE TABLE drop_tables (
  drop_table_id VARCHAR(100) PRIMARY KEY,
  description TEXT,
  entity_type VARCHAR(50) NOT NULL, -- 'npc', 'boss', 'resource_node', 'chest'
  drop_policy VARCHAR(50) DEFAULT 'per_killer', -- 'per_killer', 'shared_party'
  metadata JSONB, -- additional configuration (level range, zone restrictions, etc.)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Drop table items define what can drop from a drop table
CREATE TABLE drop_table_items (
  id SERIAL PRIMARY KEY,
  drop_table_id VARCHAR(100) NOT NULL REFERENCES drop_tables(drop_table_id) ON DELETE CASCADE,
  item_id VARCHAR(100), -- item template ID (mutually exclusive with nested_table_id)
  nested_table_id VARCHAR(100) REFERENCES drop_tables(drop_table_id), -- for rare nested drops
  drop_chance DECIMAL(5,4) NOT NULL CHECK (drop_chance >= 0 AND drop_chance <= 1), -- 0.0 to 1.0
  quantity_min INT DEFAULT 1 CHECK (quantity_min > 0),
  quantity_max INT DEFAULT 1 CHECK (quantity_max >= quantity_min),
  is_guaranteed BOOLEAN DEFAULT FALSE, -- for boss guaranteed drops
  metadata JSONB, -- item-specific metadata (rarity, stats, description)
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Ensure either item_id or nested_table_id is set, but not both
  CHECK (
    (item_id IS NOT NULL AND nested_table_id IS NULL) OR
    (item_id IS NULL AND nested_table_id IS NOT NULL)
  )
);

-- Index for efficient drop table lookups
CREATE INDEX idx_drop_table_items_table ON drop_table_items(drop_table_id);

-- Index for nested table resolution
CREATE INDEX idx_drop_table_items_nested ON drop_table_items(nested_table_id) WHERE nested_table_id IS NOT NULL;

-- Index for guaranteed drops (boss loot)
CREATE INDEX idx_drop_table_items_guaranteed ON drop_table_items(drop_table_id, is_guaranteed) WHERE is_guaranteed = TRUE;

-- Table and column comments for documentation
COMMENT ON TABLE drop_tables IS 'MMORPG loot system - Drop table configurations for NPCs, bosses, and resource nodes';
COMMENT ON COLUMN drop_tables.drop_table_id IS 'Unique identifier for the drop table (e.g., "goblin_common", "boss_dragon")';
COMMENT ON COLUMN drop_tables.entity_type IS 'Type of entity this drop table is for: npc, boss, resource_node, chest';
COMMENT ON COLUMN drop_tables.drop_policy IS 'Loot distribution policy: per_killer (individual rolls) or shared_party (single roll shared)';
COMMENT ON COLUMN drop_tables.metadata IS 'Additional configuration: level range, zone restrictions, special conditions';

COMMENT ON TABLE drop_table_items IS 'MMORPG loot system - Items that can drop from drop tables with probabilities';
COMMENT ON COLUMN drop_table_items.drop_table_id IS 'Foreign key to drop_tables - which drop table this item belongs to';
COMMENT ON COLUMN drop_table_items.item_id IS 'Item template ID to drop (mutually exclusive with nested_table_id)';
COMMENT ON COLUMN drop_table_items.nested_table_id IS 'Nested drop table for rare loot (mutually exclusive with item_id)';
COMMENT ON COLUMN drop_table_items.drop_chance IS 'Probability of drop (0.0 = never, 1.0 = always) - independent rolls';
COMMENT ON COLUMN drop_table_items.quantity_min IS 'Minimum quantity if drop succeeds';
COMMENT ON COLUMN drop_table_items.quantity_max IS 'Maximum quantity if drop succeeds (RNG between min and max)';
COMMENT ON COLUMN drop_table_items.is_guaranteed IS 'TRUE for boss guaranteed drops (ignores drop_chance)';
COMMENT ON COLUMN drop_table_items.metadata IS 'Item-specific metadata: rarity, stats, description, bind status';

-- +migrate Down

DROP TABLE IF EXISTS drop_table_items CASCADE;
DROP TABLE IF EXISTS drop_tables CASCADE;
