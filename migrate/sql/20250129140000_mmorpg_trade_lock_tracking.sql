/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Trade Lock Tracking Migration
 *
 * Adds individual lock tracking columns to trade_sessions table.
 * Allows tracking which participant has confirmed the trade before
 * setting the global locked flag.
 *
 * Trading Flow Enhancement:
 * 1. trade_open: Creates trade_session with participant_1_ready=false, participant_2_ready=false, locked=false
 * 2. trade_add_item: Both players add items
 * 3. trade_lock: Each participant calls this RPC to set their ready flag
 *    - First participant: Sets participant_X_ready=true
 *    - Second participant: Sets participant_Y_ready=true AND locked=true (both confirmed)
 * 4. trade_commit: Can only proceed if locked=true (both ready)
 *
 * Requirements: Requirement 15 (Player-to-Player Trading)
 * Design Reference: Economy Service - Trading System
 * Task: 4.4.3 - Implement trade_lock RPC
 */

-- +migrate Up

-- Add individual ready flags for each participant
ALTER TABLE trade_sessions
  ADD COLUMN participant_1_ready BOOLEAN DEFAULT FALSE,
  ADD COLUMN participant_2_ready BOOLEAN DEFAULT FALSE;

-- Add comments for documentation
COMMENT ON COLUMN trade_sessions.participant_1_ready IS 'True when participant_1 has confirmed they are ready for 2PC';
COMMENT ON COLUMN trade_sessions.participant_2_ready IS 'True when participant_2 has confirmed they are ready for 2PC';

-- +migrate Down

ALTER TABLE trade_sessions
  DROP COLUMN IF EXISTS participant_1_ready,
  DROP COLUMN IF EXISTS participant_2_ready;
