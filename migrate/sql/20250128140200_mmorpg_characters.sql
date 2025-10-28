/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Characters Migration
 *
 * Creates the characters table for MMORPG multi-character accounts.
 * Each account can have multiple characters with unique names, persistent
 * state (zone, position, stats), and optimistic locking for concurrent updates.
 *
 * Requirements: Requirement 2 (Character List and Selection), Requirement 3 (Character Creation)
 * Design Reference: Data Models section - Characters Table (lines 523-540)
 * Task: 1.1.3 - Create characters table migration
 */

-- +migrate Up

-- Characters table for MMORPG character management
-- Supports multiple characters per account with persistent world state
CREATE TABLE characters (
  character_id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
  name VARCHAR(50) NOT NULL,
  archetype_id VARCHAR(50) NOT NULL,
  level INT DEFAULT 1,
  last_zone_id VARCHAR(100),
  last_position JSONB, -- {x, y, z}
  stats JSONB, -- {hp, mp, str, dex, int, ...}
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  version INT DEFAULT 1, -- for optimistic locking
  CONSTRAINT unique_character_name UNIQUE(name)
);

-- Index for listing characters by account
CREATE INDEX idx_characters_account ON characters(account_id);

-- Index for character name lookups (name validation, uniqueness checks)
CREATE INDEX idx_characters_name ON characters(name);

-- Table and column comments for documentation
COMMENT ON TABLE characters IS 'MMORPG character profiles with persistent world state and multi-character account support';
COMMENT ON COLUMN characters.character_id IS 'Unique character identifier';
COMMENT ON COLUMN characters.account_id IS 'Foreign key to accounts table - supports multiple characters per account';
COMMENT ON COLUMN characters.name IS 'Unique character name (global uniqueness enforced)';
COMMENT ON COLUMN characters.archetype_id IS 'Character class/archetype identifier (references game data)';
COMMENT ON COLUMN characters.level IS 'Character level for progression tracking';
COMMENT ON COLUMN characters.last_zone_id IS 'Last known zone for world entry spawning';
COMMENT ON COLUMN characters.last_position IS 'Last known position as JSONB {x, y, z} for spawn coordinates';
COMMENT ON COLUMN characters.stats IS 'Character stats as JSONB (hp, mp, str, dex, int, etc.)';
COMMENT ON COLUMN characters.version IS 'Optimistic locking version for concurrent update safety';

-- +migrate Down

DROP INDEX IF EXISTS idx_characters_name;
DROP INDEX IF EXISTS idx_characters_account;
DROP TABLE IF EXISTS characters;
