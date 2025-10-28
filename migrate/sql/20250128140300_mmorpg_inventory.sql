/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Inventory Migration
 *
 * Creates the inventory table for MMORPG transactional item management.
 * Each item has a unique ID (UID) to prevent duplication exploits, and
 * uses optimistic locking (version column) for safe concurrent operations.
 * The unique index on (character_id, slot_id) ensures slot-based inventory
 * validation and prevents race conditions during item moves.
 *
 * Requirements: Requirement 14 (Transactional Inventory Management)
 * Design Reference: Data Models section - Inventory Table (lines 541-560)
 * Task: 1.1.4 - Create inventory table migration
 */

-- +migrate Up

-- Inventory table for MMORPG transactional item management
-- Supports unique item instances (UIDs), slot-based organization, and optimistic locking
CREATE TABLE inventory (
  item_uid UUID PRIMARY KEY,
  character_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  item_id VARCHAR(100) NOT NULL, -- references item templates in game data
  slot_id VARCHAR(50), -- 'backpack_0', 'equipped_weapon', 'bank_5', etc.
  quantity INT DEFAULT 1,
  durability INT,
  metadata JSONB, -- enchantments, sockets, bound status, custom properties
  version INT DEFAULT 1, -- for optimistic locking
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for listing all items for a character
CREATE INDEX idx_inventory_character ON inventory(character_id);

-- Unique index to enforce one item per slot (prevents slot conflicts)
CREATE UNIQUE INDEX idx_inventory_slot ON inventory(character_id, slot_id);

-- Table and column comments for documentation
COMMENT ON TABLE inventory IS 'MMORPG inventory system with unique item IDs (UIDs), slot-based organization, and optimistic locking for transactional safety';
COMMENT ON COLUMN inventory.item_uid IS 'Unique item instance identifier - prevents item duplication exploits';
COMMENT ON COLUMN inventory.character_id IS 'Foreign key to characters table - supports per-character inventory';
COMMENT ON COLUMN inventory.item_id IS 'Item template identifier (references game data/catalog)';
COMMENT ON COLUMN inventory.slot_id IS 'Inventory slot identifier (backpack_N, equipped_slot, bank_N, etc.) - nullable for unslotted items';
COMMENT ON COLUMN inventory.quantity IS 'Item stack quantity (for stackable items like consumables)';
COMMENT ON COLUMN inventory.durability IS 'Item durability/condition (for equipment wear, nullable if not applicable)';
COMMENT ON COLUMN inventory.metadata IS 'Item-specific metadata as JSONB: enchantments, sockets, bind status, custom properties';
COMMENT ON COLUMN inventory.version IS 'Optimistic locking version - incremented on each update to prevent race conditions';

-- +migrate Down

DROP INDEX IF EXISTS idx_inventory_slot;
DROP INDEX IF EXISTS idx_inventory_character;
DROP TABLE IF EXISTS inventory;
