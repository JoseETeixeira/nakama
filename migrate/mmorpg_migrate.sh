#!/usr/bin/env bash
# MMORPG Migration Helper Script
# Provides convenience commands for managing MMORPG database migrations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
MMORPG Migration Helper

Usage: $0 <command> [options]

Commands:
    create <name>       Create new MMORPG migration with timestamp
    status              Show migration status
    up [limit]          Apply migrations (optional: limit count)
    down [limit]        Rollback migrations (optional: limit count)
    redo                Redo last migration
    test                Run migration test cycle (up/down/up)
    verify              Verify migration files are properly formatted

Examples:
    $0 create accounts           # Creates 20250128HHMMSS_mmorpg_accounts.sql
    $0 status                    # Show applied/pending migrations
    $0 up                        # Apply all pending migrations
    $0 up 1                      # Apply 1 migration
    $0 down 1                    # Rollback 1 migration
    $0 test                      # Test migration cycle
    $0 verify                    # Check migration file format

Environment Variables:
    DB_HOST      Database host (default: localhost)
    DB_PORT      Database port (default: 5432)
    DB_USER      Database user (default: nakama)
    DB_PASS      Database password (default: nakama)
    DB_NAME      Database name (default: nakama)

EOF
}

generate_timestamp() {
    date +"%Y%m%d%H%M%S"
}

create_migration() {
    local name="$1"
    if [[ -z "$name" ]]; then
        error "Migration name required"
        echo "Usage: $0 create <name>"
        exit 1
    fi

    local timestamp=$(generate_timestamp)
    local filename="${timestamp}_mmorpg_${name}.sql"
    local filepath="$PROJECT_ROOT/migrate/sql/$filename"

    if [[ -f "$filepath" ]]; then
        error "Migration file already exists: $filename"
        exit 1
    fi

    cat > "$filepath" << EOF
/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - ${name^} Migration
 *
 * Description: TODO
 *
 * Requirements: TODO (list requirement numbers)
 * Design Reference: Data Models section
 * Task: TODO (e.g., 1.1.2)
 */

-- +migrate Up

-- TODO: Add schema changes here
CREATE TABLE IF NOT EXISTS mmorpg_${name} (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- +migrate Down

DROP TABLE IF EXISTS mmorpg_${name};
EOF

    info "Created migration: $filename"
    info "Edit file: $filepath"
}

run_nakama_migrate() {
    local cmd="$1"
    local limit="$2"

    local db_host="${DB_HOST:-localhost}"
    local db_port="${DB_PORT:-5432}"
    local db_user="${DB_USER:-nakama}"
    local db_pass="${DB_PASS:-nakama}"
    local db_name="${DB_NAME:-nakama}"

    if [[ ! -x "$PROJECT_ROOT/nakama" ]] && ! command -v nakama &> /dev/null; then
        error "Nakama binary not found. Build it first or ensure it's in PATH."
        exit 1
    fi

    local nakama_cmd="${PROJECT_ROOT}/nakama"
    if [[ ! -x "$nakama_cmd" ]]; then
        nakama_cmd="nakama"
    fi

    local args=("migrate" "$cmd")

    if [[ -n "$limit" ]]; then
        args+=("--limit" "$limit")
    fi

    args+=(
        "--database.address" "$db_user:$db_pass@$db_host:$db_port/$db_name"
    )

    info "Running: $nakama_cmd ${args[*]}"
    "$nakama_cmd" "${args[@]}"
}

verify_migrations() {
    local errors=0

    info "Verifying MMORPG migration files..."

    for file in "$PROJECT_ROOT/migrate/sql"/20*_mmorpg_*.sql; do
        [[ -f "$file" ]] || continue

        local filename=$(basename "$file")

        # Check for +migrate Up directive
        if ! grep -q "^-- +migrate Up" "$file"; then
            error "$filename: Missing '-- +migrate Up' directive"
            ((errors++))
        fi

        # Check for +migrate Down directive
        if ! grep -q "^-- +migrate Down" "$file"; then
            error "$filename: Missing '-- +migrate Down' directive"
            ((errors++))
        fi

        # Check timestamp format
        if [[ ! "$filename" =~ ^[0-9]{14}_mmorpg_.+\.sql$ ]]; then
            warn "$filename: Filename doesn't match expected format (YYYYMMDDHHMMSS_mmorpg_*.sql)"
        fi
    done

    if [[ $errors -eq 0 ]]; then
        info "All MMORPG migrations verified successfully"
    else
        error "Found $errors error(s) in migration files"
        exit 1
    fi
}

test_migration_cycle() {
    info "Running migration test cycle..."

    warn "This will apply and rollback migrations. Ensure you're using a test database!"
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Test cancelled"
        exit 0
    fi

    info "Step 1: Apply migrations"
    run_nakama_migrate "up" "1"

    info "Step 2: Rollback migrations"
    run_nakama_migrate "down" "1"

    info "Step 3: Reapply migrations"
    run_nakama_migrate "up" "1"

    info "Migration test cycle completed successfully"
}

# Main command dispatcher
case "${1:-}" in
    create)
        create_migration "$2"
        ;;
    status)
        run_nakama_migrate "status"
        ;;
    up)
        run_nakama_migrate "up" "$2"
        ;;
    down)
        run_nakama_migrate "down" "$2"
        ;;
    redo)
        run_nakama_migrate "redo"
        ;;
    verify)
        verify_migrations
        ;;
    test)
        test_migration_cycle
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Unknown command: ${1:-}"
        echo ""
        show_help
        exit 1
        ;;
esac
