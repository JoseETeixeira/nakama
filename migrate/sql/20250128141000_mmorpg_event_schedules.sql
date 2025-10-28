/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Event Schedules Migration
 *
 * Creates the event_schedules table for managing automated, cron-based live-ops events.
 * This table enables game masters and live-ops teams to schedule recurring or one-time
 * in-game events (XP boosts, holiday content, boss spawns, limited-time offers) that
 * execute automatically without manual intervention.
 *
 * Schema Design:
 * - schedule_id: UUID primary key - unique identifier for each scheduled event
 * - cron_expr: Cron expression (standard 5-field format) defining execution schedule
 *   Examples: "0 0 * * *" (daily at midnight), "0 12 * * 5" (Fridays at noon)
 * - script_id: Reference to the hot-loadable script to execute when event triggers
 * - params: JSONB configuration passed to the script during execution (event-specific settings)
 * - enabled: Boolean flag to activate/deactivate schedules without deletion
 * - created_by: Foreign key to accounts table - tracks which GM created the schedule
 * - created_at: Timestamp of schedule creation for audit trail
 *
 * Event Scheduling Workflow:
 * 1. GM creates event schedule via console with cron expression and script reference
 * 2. Server validates cron syntax and script existence
 * 3. Background scheduler process evaluates active schedules (enabled=true)
 * 4. When cron condition matches, server executes the associated script with params
 * 5. Script performs event logic (spawn boss, enable double XP, start limited sale, etc.)
 * 6. Execution results logged to audit_logs for monitoring and troubleshooting
 * 7. Failed executions trigger alerts to live-ops team for manual intervention
 *
 * Cron Expression Format:
 * Standard 5-field cron syntax: "minute hour day month weekday"
 * - minute: 0-59
 * - hour: 0-23
 * - day: 1-31
 * - month: 1-12
 * - weekday: 0-7 (0 and 7 are Sunday)
 * Special characters: * (any), / (step), - (range), , (list)
 *
 * Live-Ops Use Cases:
 * - Daily login bonuses: "0 0 * * *" (midnight server time)
 * - Weekend XP events: "0 18 * * 5" (Friday 6pm start)
 * - Holiday events: One-time cron with enabled toggle on/off
 * - World boss spawns: "0 */4 * * *" (every 4 hours)
 * - Flash sales: Short-duration events with auto-disable after expiry
 *
 * Performance Considerations:
 * The idx_event_schedules_enabled index optimizes queries for active schedules,
 * allowing the scheduler to efficiently filter enabled=true without full table scans.
 * The scheduler runs at 1-minute intervals, evaluating all active schedules against
 * current time. For high-frequency events (< 1 minute), use in-memory timers instead.
 *
 * Requirements: Requirement 22 (Event Scheduling)
 * Design Reference: Data Models section - Event Schedules Table (lines 660-670)
 * Related: Requirement 23 (Hot-Loadable Scripts), Live-Ops Service (component #9)
 * Task: 1.1.11 - Create event_schedules table migration
 */

-- +migrate Up

-- Event Schedules table for automated cron-based event execution
-- Enables live-ops teams to schedule recurring in-game events without manual triggers
CREATE TABLE event_schedules (
  schedule_id UUID PRIMARY KEY,
  cron_expr VARCHAR(100) NOT NULL,
  script_id VARCHAR(100) NOT NULL,
  params JSONB,
  enabled BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES accounts(account_id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Performance index for efficient active schedule queries by the background scheduler
-- Filters enabled=true schedules without full table scan
CREATE INDEX idx_event_schedules_enabled ON event_schedules(enabled);

-- Table and column comments for documentation
COMMENT ON TABLE event_schedules IS 'Cron-based event schedules for automated live-ops content (XP boosts, boss spawns, holiday events) - evaluated by background scheduler';
COMMENT ON COLUMN event_schedules.schedule_id IS 'UUID primary key - unique identifier for this scheduled event';
COMMENT ON COLUMN event_schedules.cron_expr IS 'Standard 5-field cron expression (minute hour day month weekday) defining when the event triggers - e.g., "0 0 * * *" for daily midnight';
COMMENT ON COLUMN event_schedules.script_id IS 'Reference to hot-loadable script that executes when the schedule triggers - must exist in script registry';
COMMENT ON COLUMN event_schedules.params IS 'JSONB configuration parameters passed to the script during execution - event-specific settings like duration, multipliers, rewards';
COMMENT ON COLUMN event_schedules.enabled IS 'Boolean flag to activate/deactivate schedule - allows toggling events on/off without deletion, defaults to TRUE';
COMMENT ON COLUMN event_schedules.created_by IS 'Foreign key to accounts table - tracks which GM created this schedule for audit purposes';
COMMENT ON COLUMN event_schedules.created_at IS 'Timestamp when the schedule was created - used for audit trail and schedule history';

-- +migrate Down

DROP TABLE IF EXISTS event_schedules;
