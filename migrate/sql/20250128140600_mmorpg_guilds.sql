/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Guilds Migration
 *
 * Creates the guilds and guild_members tables for MMORPG social features.
 * Guilds enable player communities with hierarchical permissions, shared
 * resources (guild storage), and communication channels (MOTD).
 *
 * Schema Design:
 * - guilds: Parent table with unique names, guild master, MOTD, shared storage
 * - guild_members: Junction table with composite PK (guild_id, character_id)
 * - Ranks: 0 = member, 1 = officer, 2 = master (for permission hierarchy)
 * - Cascade deletes: Guild deletion removes all members, character deletion
 *   removes from guild_members but sets master_id to NULL in guilds table
 *
 * Requirements: Requirement 11 (Guild Creation and Management)
 * Design Reference: Data Models section - Guilds Table (lines 590-616)
 * Task: 1.1.7 - Create guilds and guild_members tables migration
 */

-- +migrate Up

-- Guilds table for MMORPG social communities
-- Parent table for guild-based features: shared storage, MOTD, hierarchical permissions
CREATE TABLE guilds (
  guild_id UUID PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  master_id UUID REFERENCES characters(character_id) ON DELETE SET NULL,
  motd TEXT, -- Message of the Day, max 500 chars enforced at application layer
  created_at TIMESTAMPTZ DEFAULT NOW(),
  storage JSONB -- shared guild inventory as JSONB array of items
);

-- Index for guild name lookups and uniqueness validation
CREATE INDEX idx_guilds_name ON guilds(name);

-- Guild Members junction table for many-to-many relationship between guilds and characters
-- Supports hierarchical permissions via rank column
CREATE TABLE guild_members (
  guild_id UUID NOT NULL REFERENCES guilds(guild_id) ON DELETE CASCADE,
  character_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  rank INT DEFAULT 0, -- 0 = member, 1 = officer, 2 = master
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (guild_id, character_id)
);

-- Index for listing all guilds a character belongs to
CREATE INDEX idx_guild_members_character ON guild_members(character_id);

-- Table and column comments for documentation
COMMENT ON TABLE guilds IS 'MMORPG guild communities with hierarchical permissions, shared storage, and MOTD';
COMMENT ON COLUMN guilds.guild_id IS 'Unique guild identifier (primary key)';
COMMENT ON COLUMN guilds.name IS 'Unique guild name (enforced via UNIQUE constraint)';
COMMENT ON COLUMN guilds.master_id IS 'Guild master character_id (FK to characters, SET NULL on character deletion to preserve guild)';
COMMENT ON COLUMN guilds.motd IS 'Message of the Day - plain text, max 500 chars (enforced at application layer)';
COMMENT ON COLUMN guilds.created_at IS 'Guild creation timestamp';
COMMENT ON COLUMN guilds.storage IS 'Shared guild inventory as JSONB - accessible based on rank permissions';

COMMENT ON TABLE guild_members IS 'Guild membership junction table with hierarchical rank system';
COMMENT ON COLUMN guild_members.guild_id IS 'Foreign key to guilds table (CASCADE delete when guild disbanded)';
COMMENT ON COLUMN guild_members.character_id IS 'Foreign key to characters table (CASCADE delete when character deleted)';
COMMENT ON COLUMN guild_members.rank IS 'Hierarchical rank: 0 = member (default), 1 = officer, 2 = master';
COMMENT ON COLUMN guild_members.joined_at IS 'Timestamp when character joined the guild';

-- +migrate Down

DROP INDEX IF EXISTS idx_guild_members_character;
DROP TABLE IF EXISTS guild_members;
DROP INDEX IF EXISTS idx_guilds_name;
DROP TABLE IF EXISTS guilds;
