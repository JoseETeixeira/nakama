# MMORPG Migration Framework

## Overview

This directory contains database migrations for the MMORPG-grade Nakama feature set. Migrations use the `sql-migrate` library and are managed through Nakama's built-in migration commands.

## Migration System

- **Migration Files**: Located in `migrate/sql/` with format `YYYYMMDDHHMMSS_description.sql`
- **Tracking Table**: `migration_info` stores applied migration records
- **Runner**: `migrate/migrate.go` handles execution
- **Embedded FS**: Migrations are embedded at build time via `//go:embed sql/*`

## Commands

```bash
# Apply all pending migrations
nakama migrate up

# Apply migrations with limit
nakama migrate up --limit 5

# Revert last migration
nakama migrate down

# Revert N migrations
nakama migrate down --limit 3

# Redo last migration (down then up)
nakama migrate redo

# Check migration status
nakama migrate status
```

## Migration File Structure

Each migration file must follow this format:

```sql
/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set Migration
 */

-- +migrate Up
CREATE TABLE example (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- +migrate Down
DROP TABLE IF EXISTS example;
```

## MMORPG Schema Migrations

The MMORPG feature set adds the following tables (see `design.md` for full schema):

### Phase 1: Foundation (Tasks 1.1.2-1.1.14)
- `20250128140000_mmorpg_accounts.sql` - Account extensions for multi-character support
- `20250128140100_mmorpg_characters.sql` - Character profiles with archetype, stats, inventory refs
- `20250128140200_mmorpg_inventory.sql` - Item storage with optimistic locking
- `20250128140300_mmorpg_world_state.sql` - Zone checkpoints for crash recovery
- `20250128140400_mmorpg_event_log.sql` - Append-only event log (RPO ≤5s)
- `20250128140500_mmorpg_guilds.sql` - Guild system with members table
- `20250128140600_mmorpg_trade.sql` - Two-phase commit trade sessions
- `20250128140700_mmorpg_handoff.sql` - Cross-region transfer tokens
- `20250128140800_mmorpg_liveops.sql` - Event schedules and audit logs
- `20250128140900_mmorpg_commerce.sql` - Store catalog, entitlements, wallets

### Migration Naming Convention

Format: `YYYYMMDDHHMMSS_mmorpg_<feature>.sql`

Example: `20250128140000_mmorpg_accounts.sql`

### Creating New Migrations

1. Generate timestamp: `date +"%Y%m%d%H%M%S"`
2. Create file: `migrate/sql/<timestamp>_mmorpg_<description>.sql`
3. Add `-- +migrate Up` section with schema changes
4. Add `-- +migrate Down` section with rollback logic
5. Test locally: `nakama migrate status` then `nakama migrate up`

## Migration Dependencies

Migrations must be created in dependency order:

1. **accounts** (extends existing `users` table or creates `accounts` table)
2. **characters** (depends on accounts)
3. **inventory** (depends on characters)
4. **world_state** (independent)
5. **event_log** (independent)
6. **guilds** (depends on characters)
7. **trade** (depends on characters, inventory)
8. **handoff** (depends on characters)
9. **liveops** (depends on accounts)
10. **commerce** (depends on accounts)

## Rollback Strategy

- All migrations include `-- +migrate Down` for safe rollback
- Rollbacks are tested during development
- Production rollbacks require approval and backup verification
- Use `nakama migrate down --limit 1` to revert specific migrations

## Testing Migrations

```bash
# 1. Check current status
nakama migrate status

# 2. Apply single migration
nakama migrate up --limit 1

# 3. Verify schema changes
psql -h localhost -U nakama -d nakama -c "\dt"

# 4. Test rollback
nakama migrate down --limit 1

# 5. Verify rollback worked
psql -h localhost -U nakama -d nakama -c "\dt"

# 6. Reapply for final testing
nakama migrate up
```

## References

- **Requirements**: `.kiro/specs/mmorpg-nakama-godot/requirements.md`
- **Design**: `.kiro/specs/mmorpg-nakama-godot/design.md` (Data Models section)
- **Tasks**: `.kiro/specs/mmorpg-nakama-godot/tasks.md` (Phase 1)
- **sql-migrate docs**: https://github.com/rubenv/sql-migrate
