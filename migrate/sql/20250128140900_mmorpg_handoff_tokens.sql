/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Handoff Tokens Migration
 *
 * Creates the handoff_tokens table for managing seamless cross-region and cross-shard
 * player transfers. When a player approaches a zone boundary (detected via zone_boundaries),
 * the server issues a time-limited handoff token that contains routing information for
 * transferring the player's session to a different game server region or shard.
 *
 * Schema Design:
 * - token: UUID primary key - cryptographically secure, single-use transfer token
 * - player_id: Foreign key to characters table - identifies the transferring character
 * - from_zone: Source zone identifier where handoff initiated
 * - to_zone: Destination zone identifier for transfer target
 * - endpoint: JSONB routing information {host, port, protocol} for target server connection
 * - expires_at: TTL timestamp - tokens expire after a short window (typically 10-30 seconds)
 * - created_at: Token issuance timestamp for audit and cleanup purposes
 *
 * Handoff Flow:
 * 1. Server detects player crossing zone boundary (via zone_boundaries table)
 * 2. Server generates unique handoff token and stores in this table
 * 3. Server sends token + endpoint to client
 * 4. Client pre-connects to target endpoint using token for authentication
 * 5. Target server validates token (checks expiry, marks as consumed)
 * 6. On success, player session transfers; on failure, rollback to safe anchor
 * 7. Expired/consumed tokens are periodically cleaned up
 *
 * TTL Strategy:
 * The expires_at column enables automatic token invalidation, preventing replay attacks
 * and stale token usage. Typical TTL is 10-30 seconds - long enough for network handoff,
 * short enough to minimize security risk. A background cleanup job periodically deletes
 * expired tokens to prevent table bloat.
 *
 * Performance Indexes:
 * - idx_handoff_tokens_player: Fast lookups by player_id during handoff validation
 * - idx_handoff_tokens_expires: Efficient cleanup queries for expired token removal
 *
 * Requirements: Requirement 18 (Seamless Region/Shard Handoff), Requirement 19 (Handoff Finalization)
 * Design Reference: Data Models section - Handoff Tokens Table (lines 644-655)
 * Task: 1.1.10 - Create handoff_tokens table migration
 */

-- +migrate Up

-- Handoff Tokens table for cross-region/shard player transfers
-- Stores time-limited tokens issued during zone boundary crossings
CREATE TABLE handoff_tokens (
  token UUID PRIMARY KEY,
  player_id UUID REFERENCES characters(character_id) ON DELETE CASCADE,
  from_zone VARCHAR(100),
  to_zone VARCHAR(100),
  endpoint JSONB, -- {host, port, protocol}
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Performance index for player-based token lookups during handoff validation
CREATE INDEX idx_handoff_tokens_player ON handoff_tokens(player_id);

-- Performance index for efficient cleanup of expired tokens
CREATE INDEX idx_handoff_tokens_expires ON handoff_tokens(expires_at);

-- Table and column comments for documentation
COMMENT ON TABLE handoff_tokens IS 'Time-limited tokens for seamless cross-region/shard player transfers - issued when players cross zone boundaries';
COMMENT ON COLUMN handoff_tokens.token IS 'UUID primary key - unique, single-use handoff token for secure session transfer';
COMMENT ON COLUMN handoff_tokens.player_id IS 'Foreign key to characters table - identifies the character being transferred';
COMMENT ON COLUMN handoff_tokens.from_zone IS 'Source zone identifier where the handoff was initiated';
COMMENT ON COLUMN handoff_tokens.to_zone IS 'Destination zone identifier for transfer target';
COMMENT ON COLUMN handoff_tokens.endpoint IS 'JSONB routing information: {host: string, port: number, protocol: "ws"|"wss"} - target server connection details';
COMMENT ON COLUMN handoff_tokens.expires_at IS 'TTL timestamp - tokens expire after 10-30 seconds to prevent replay attacks and stale usage';
COMMENT ON COLUMN handoff_tokens.created_at IS 'Token issuance timestamp for audit trail and cleanup coordination';

-- +migrate Down

DROP TABLE IF EXISTS handoff_tokens;
