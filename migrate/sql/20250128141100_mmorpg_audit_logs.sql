/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Audit Logs Migration
 *
 * Creates the audit_logs table for comprehensive tracking of all security-critical,
 * compliance-relevant, and debugging-worthy operations across the entire MMORPG system.
 * This append-only log captures GM actions, purchase transactions, trade commits,
 * script deployments, and moderation events for audit trails, fraud detection,
 * compliance reporting, and operational debugging.
 *
 * Schema Design:
 * - log_id: BIGSERIAL primary key - auto-incrementing 64-bit integer for high-volume writes
 *   (supports billions of log entries without collision or wraparound)
 * - actor_id: UUID of the account or character performing the action
 *   (nullable for system-initiated events like scheduled tasks)
 * - action: VARCHAR(100) categorizing the operation type
 *   Examples: 'gm_spawn', 'gm_despawn', 'purchase_verify', 'trade_commit', 'script_upload', 'player_ban'
 * - target_id: VARCHAR(255) identifying the entity affected by the action
 *   (flexible: can be entity_id, character_id, trade_id, script_id, etc.)
 * - metadata: JSONB storing action-specific context (e.g., spawned entity type, purchase amount, ban reason)
 * - timestamp: TIMESTAMPTZ when the action occurred (defaults to NOW() for automatic timestamping)
 *
 * Audit Use Cases by System Component:
 *
 * 1. Live-Ops Service (GM Console):
 *    - action='gm_spawn': actor_id=GM account, target_id=entity_id, metadata={entity_type, zone_id, position}
 *    - action='gm_despawn': actor_id=GM, target_id=entity_id, metadata={reason}
 *    - action='gm_modify': actor_id=GM, target_id=entity_id, metadata={property, old_value, new_value}
 *    - action='gm_broadcast': actor_id=GM, metadata={scope, message}
 *    - action='world_param_change': actor_id=GM, metadata={parameter, old_value, new_value, duration}
 *
 * 2. Commerce Service (Payments):
 *    - action='purchase_verify': actor_id=account_id, target_id=receipt_id, metadata={platform, sku, amount, valid}
 *    - action='entitlement_grant': actor_id=system, target_id=entitlement_id, metadata={sku, reason}
 *    - action='entitlement_revoke': actor_id=GM/system, target_id=entitlement_id, metadata={reason}
 *    - action='wallet_credit': actor_id=system/GM, target_id=account_id, metadata={currency, amount, source}
 *    - action='wallet_debit': actor_id=account_id, target_id=transaction_id, metadata={currency, amount, reason}
 *
 * 3. Social Service (Moderation & Trading):
 *    - action='player_mute': actor_id=moderator_id, target_id=player_id, metadata={channel_id, duration, reason}
 *    - action='player_kick': actor_id=moderator_id, target_id=player_id, metadata={channel_id, reason}
 *    - action='player_ban': actor_id=moderator_id, target_id=account_id, metadata={duration, reason}
 *    - action='trade_commit': actor_id=system, target_id=trade_id, metadata={participants, items_exchanged}
 *
 * 4. Live-Ops Service (Scripts):
 *    - action='script_upload': actor_id=GM, target_id=script_id, metadata={version, hash, size}
 *    - action='script_load': actor_id=system, target_id=script_id, metadata={success, error_details}
 *    - action='script_execute': actor_id=system/account_id, target_id=script_id, metadata={params, result}
 *
 * 5. Authentication Service:
 *    - action='login_attempt': actor_id=account_id, metadata={device_id, success, ip_address}
 *    - action='token_refresh': actor_id=account_id, metadata={old_token_expiry, new_token_expiry}
 *
 * Performance Considerations:
 * - BIGSERIAL uses 64-bit integers (vs UUID 128-bit) for faster inserts and smaller index size
 * - Composite indexes optimize common query patterns:
 *   - idx_audit_logs_actor_time: "Show me all actions by this GM in the last 24 hours"
 *   - idx_audit_logs_action_time: "Show me all purchase attempts in the last week"
 * - JSONB metadata enables flexible schema without ALTER TABLE migrations
 * - Append-only design (no UPDATEs/DELETEs) ensures immutable audit trail
 *
 * Retention and Archival Strategy:
 * - Hot logs: 90 days in primary table for fast queries
 * - Warm logs: 1 year in partitioned archive tables
 * - Cold logs: 7 years in compressed object storage (compliance requirement)
 * - Automated partition rotation and archival jobs run daily
 *
 * Compliance and Security:
 * - Immutable audit trail for SOC 2, GDPR, PCI-DSS compliance
 * - Fraud detection: Purchase verification failures, duplicate receipts
 * - Incident response: Root cause analysis for exploits, bugs, outages
 * - Player support: Dispute resolution for trades, bans, lost items
 *
 * Requirements: Requirement 20 (GM Console), Requirement 23 (Hot-Loadable Scripts), Requirement 25 (Purchase Verification)
 * Design Reference: Data Models section - Audit Logs Table (lines 675-686)
 * Related: Live-Ops Service (component #9), Commerce Service (component #10), Social Service (component #6)
 * Task: 1.1.12 - Create audit_logs table migration
 */

-- +migrate Up

-- Audit Logs table for comprehensive tracking of security-critical and compliance-relevant operations
-- Append-only immutable log for GM actions, purchases, trades, scripts, and moderation events
CREATE TABLE audit_logs (
  log_id BIGSERIAL PRIMARY KEY,
  actor_id UUID, -- account_id or character_id performing the action (nullable for system events)
  action VARCHAR(100) NOT NULL, -- operation type: 'gm_spawn', 'purchase_verify', 'trade_commit', etc.
  target_id VARCHAR(255), -- entity affected: entity_id, trade_id, script_id, receipt_id, etc.
  metadata JSONB, -- action-specific context (flexible schema)
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Composite index for actor-centric queries: "Show all actions by this user/GM in time range"
CREATE INDEX idx_audit_logs_actor_time ON audit_logs(actor_id, timestamp);

-- Composite index for action-centric queries: "Show all purchases/spawns/bans in time range"
CREATE INDEX idx_audit_logs_action_time ON audit_logs(action, timestamp);

-- Table and column comments for documentation
COMMENT ON TABLE audit_logs IS 'Append-only audit trail for GM actions, purchases, trades, moderation, and system events - used for compliance, fraud detection, and debugging';
COMMENT ON COLUMN audit_logs.log_id IS 'BIGSERIAL primary key - auto-incrementing 64-bit integer optimized for high-volume append-only writes';
COMMENT ON COLUMN audit_logs.actor_id IS 'UUID of account or character performing the action - nullable for system-initiated events (scheduled tasks, automated processes)';
COMMENT ON COLUMN audit_logs.action IS 'Operation type categorizing the event - examples: gm_spawn, purchase_verify, trade_commit, player_ban, script_upload';
COMMENT ON COLUMN audit_logs.target_id IS 'Identifier of the entity affected by the action - flexible VARCHAR to support entity_id, trade_id, script_id, receipt_id, etc.';
COMMENT ON COLUMN audit_logs.metadata IS 'JSONB context for the action - flexible schema for action-specific details (spawn position, purchase amount, ban reason, etc.)';
COMMENT ON COLUMN audit_logs.timestamp IS 'When the action occurred - defaults to NOW() for automatic timestamping, indexed for time-range queries';

-- +migrate Down

DROP TABLE IF EXISTS audit_logs;
