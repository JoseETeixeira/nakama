/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Trade Sessions Migration
 *
 * Creates the trade_sessions table for secure player-to-player trading.
 * Implements a two-phase commit (2PC) protocol to ensure atomicity: both
 * players receive their agreed items without risk of duplication or loss.
 *
 * Schema Design:
 * - trade_id: Unique identifier for the trade session
 * - participant_1, participant_2: Characters involved in the trade
 * - items_1, items_2: JSONB arrays of {item_uid, quantity} proposed by each participant
 * - locked: Boolean flag indicating both parties have confirmed (ready for commit)
 * - expires_at: TTL for trade session to prevent indefinite locks
 * - Foreign keys cascade delete if either participant is deleted
 * - Index on participants for efficient lookup of active trades per character
 *
 * Trading Flow:
 * 1. Create trade_session with locked=false
 * 2. Both players add/remove items until ready
 * 3. Both players confirm → locked=true
 * 4. Server executes 2PC: verify items exist, deduct from inventories, add to recipients
 * 5. If any step fails, rollback and unlock inventories
 * 6. On success, delete trade_session and log transaction
 *
 * Requirements: Requirement 15 (Player-to-Player Trading)
 * Design Reference: Data Models section - Trade Sessions Table (lines 618-630)
 * Task: 1.1.8 - Create trade_sessions table migration
 */

-- +migrate Up

-- Trade Sessions table for two-phase commit player-to-player trading
-- Ensures atomic item transfers without duplication or loss
CREATE TABLE trade_sessions (
  trade_id UUID PRIMARY KEY,
  participant_1 UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  participant_2 UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  items_1 JSONB, -- array of {item_uid: string, quantity: number} proposed by participant_1
  items_2 JSONB, -- array of {item_uid: string, quantity: number} proposed by participant_2
  locked BOOLEAN DEFAULT FALSE, -- true when both parties have confirmed (ready for 2PC)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ -- timeout for trade session (configurable, e.g., 5 minutes)
);

-- Index for finding active trades involving specific characters
-- Supports queries like "show me all trades for character X"
CREATE INDEX idx_trade_sessions_participants ON trade_sessions(participant_1, participant_2);

-- Table and column comments for documentation
COMMENT ON TABLE trade_sessions IS 'Two-phase commit trade sessions for secure player-to-player item trading';
COMMENT ON COLUMN trade_sessions.trade_id IS 'Unique trade session identifier (primary key)';
COMMENT ON COLUMN trade_sessions.participant_1 IS 'First participant character_id (FK to characters, CASCADE delete)';
COMMENT ON COLUMN trade_sessions.participant_2 IS 'Second participant character_id (FK to characters, CASCADE delete)';
COMMENT ON COLUMN trade_sessions.items_1 IS 'JSONB array of items proposed by participant_1: [{item_uid, quantity}, ...]';
COMMENT ON COLUMN trade_sessions.items_2 IS 'JSONB array of items proposed by participant_2: [{item_uid, quantity}, ...]';
COMMENT ON COLUMN trade_sessions.locked IS 'Confirmation flag: false = negotiating, true = both confirmed and ready for 2PC';
COMMENT ON COLUMN trade_sessions.created_at IS 'Trade session creation timestamp';
COMMENT ON COLUMN trade_sessions.expires_at IS 'Expiration timestamp - trade auto-cancels if not completed by this time';

-- +migrate Down

DROP INDEX IF EXISTS idx_trade_sessions_participants;
DROP TABLE IF EXISTS trade_sessions;
