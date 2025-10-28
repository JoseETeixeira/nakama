# MMORPG Migration Quick Reference

## Quick Start

```bash
# Linux/macOS
chmod +x migrate/mmorpg_migrate.sh
./migrate/mmorpg_migrate.sh status

# Windows PowerShell
.\migrate\mmorpg_migrate.ps1 status
```

## Common Commands

| Command | Linux/macOS | Windows | Description |
|---------|-------------|---------|-------------|
| Check status | `./mmorpg_migrate.sh status` | `.\mmorpg_migrate.ps1 status` | Show applied/pending migrations |
| Apply all | `./mmorpg_migrate.sh up` | `.\mmorpg_migrate.ps1 up` | Apply all pending migrations |
| Apply one | `./mmorpg_migrate.sh up 1` | `.\mmorpg_migrate.ps1 up 1` | Apply 1 migration |
| Rollback one | `./mmorpg_migrate.sh down 1` | `.\mmorpg_migrate.ps1 down 1` | Rollback 1 migration |
| Create new | `./mmorpg_migrate.sh create accounts` | `.\mmorpg_migrate.ps1 create accounts` | Create new migration file |
| Verify | `./mmorpg_migrate.sh verify` | `.\mmorpg_migrate.ps1 verify` | Check migration format |

## Migration Order (Phase 1)

1. ✅ **foundation** - Metadata tracking (completed)
2. ⏳ **accounts** - Account extensions (task 1.1.2)
3. ⏳ **characters** - Character profiles (task 1.1.3)
4. ⏳ **inventory** - Item storage (task 1.1.4)
5. ⏳ **world_state** - Zone checkpoints (task 1.1.5)
6. ⏳ **event_log** - Crash recovery (task 1.1.6)
7. ⏳ **guilds** - Social system (task 1.1.7-1.1.8)
8. ⏳ **trade** - Economy (task 1.1.9)
9. ⏳ **handoff** - Cross-region travel (task 1.1.10-1.1.11)
10. ⏳ **liveops** - Events and audit (task 1.1.12-1.1.13)
11. ⏳ **commerce** - Store and payments (task 1.1.14)

## Direct Nakama Commands

```bash
# Apply migrations
nakama migrate up --database.address nakama:nakama@localhost:5432/nakama

# Check status
nakama migrate status --database.address nakama:nakama@localhost:5432/nakama

# Rollback
nakama migrate down --limit 1 --database.address nakama:nakama@localhost:5432/nakama
```

## Environment Variables

Set these to customize database connection:

```bash
# Bash/Linux
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=nakama
export DB_PASS=nakama
export DB_NAME=nakama

# PowerShell
$env:DB_HOST = "localhost"
$env:DB_PORT = "5432"
$env:DB_USER = "nakama"
$env:DB_PASS = "nakama"
$env:DB_NAME = "nakama"
```

## Testing Migrations

```bash
# Run full test cycle (up/down/up)
./mmorpg_migrate.sh test           # Linux/macOS
.\mmorpg_migrate.ps1 test          # Windows

# Manual testing
nakama migrate up --limit 1        # Apply one
psql -U nakama -d nakama -c "\dt"  # Verify table exists
nakama migrate down --limit 1      # Rollback
psql -U nakama -d nakama -c "\dt"  # Verify table removed
nakama migrate up --limit 1        # Reapply
```

## Migration File Template

```sql
/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - <Name> Migration
 */

-- +migrate Up
CREATE TABLE IF NOT EXISTS mmorpg_<name> (
    id UUID PRIMARY KEY,
    -- columns here
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- +migrate Down
DROP TABLE IF EXISTS mmorpg_<name>;
```

## Troubleshooting

### Migration Failed
```bash
# Check migration status
nakama migrate status

# Review logs
tail -f nakama.log

# Rollback and retry
nakama migrate down --limit 1
nakama migrate up --limit 1
```

### Database Connection Error
```bash
# Test connection
psql -h localhost -U nakama -d nakama -c "SELECT version();"

# Check environment variables
echo $DB_HOST $DB_PORT $DB_USER $DB_NAME
```

## References

- **Full Documentation**: `migrate/README_MMORPG.md`
- **Design Schemas**: `.kiro/specs/mmorpg-nakama-godot/design.md` (Data Models section)
- **Requirements**: `.kiro/specs/mmorpg-nakama-godot/requirements.md`
- **Tasks**: `.kiro/specs/mmorpg-nakama-godot/tasks.md`
