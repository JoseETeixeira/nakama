# Docker Compose Development Workflow

This document describes the complete Docker Compose development workflow for Nakama, including:
1. **Local Source Build** - Building Nakama from source code instead of using pre-built images
2. **TypeScript Runtime Modules** - Hot-reload development for custom game logic
3. **Database Migrations** - Automatic migration execution on startup
4. **Development Tools** - Prometheus metrics, console access, and troubleshooting

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Local Source Build Configuration](#local-source-build-configuration)
3. [TypeScript Module Development](#typescript-module-development)
4. [Database Migrations](#database-migrations)
5. [Monitoring and Debugging](#monitoring-and-debugging)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Node.js (v16+)
- npm

### Setup

```powershell
# Install Node.js dependencies
npm install

# Build TypeScript modules
npm run build

# Start the stack
docker compose up
```

Or use the automated helper:

```powershell
# Windows PowerShell
.\dev.ps1 up

# Linux/Mac
make up
```

## Automated TypeScript Compilation

The project now includes an automated build system that compiles TypeScript runtime modules before starting Docker Compose.

### Available Commands

#### Windows (PowerShell)

```powershell
.\dev.ps1 help              # Show all commands
.\dev.ps1 build-modules     # Compile TypeScript modules
.\dev.ps1 up                # Build + start stack
.\dev.ps1 up-build          # Build + start with image rebuild
.\dev.ps1 restart           # Rebuild modules + restart Nakama
.\dev.ps1 watch-modules     # Auto-compile on file changes
.\dev.ps1 logs              # View Nakama logs
.\dev.ps1 clean             # Remove compiled files
```

#### Linux/Mac (Makefile)

```bash
make help              # Show all commands
make build-modules     # Compile TypeScript modules
make up                # Build + start stack
make up-build          # Build + start with image rebuild
make restart           # Rebuild modules + restart Nakama
make watch-modules     # Auto-compile on file changes
make logs              # View Nakama logs
make clean             # Remove compiled files
```

#### npm Scripts

```bash
npm run build          # Compile TypeScript modules once
npm run watch          # Watch and auto-compile
npm run dev            # Build + start (docker compose up)
npm run dev:build      # Build + start with image rebuild
```

## Development Workflow

### Option 1: Watch Mode (Recommended)

Run watch mode in one terminal to auto-compile TypeScript on save:

```powershell
# Terminal 1: Auto-compile
npm run watch
# or
.\dev.ps1 watch-modules

# Terminal 2: Docker Compose
docker compose up
```

When you modify TypeScript files, they'll auto-compile. Then restart Nakama:

```powershell
docker compose restart nakama
```

### Option 2: Manual Rebuild

```powershell
# 1. Modify TypeScript files
# 2. Build and restart
.\dev.ps1 restart
```

### Option 3: One Command Startup

```powershell
# Automatically builds TypeScript then starts Docker
.\dev.ps1 up
```

## TypeScript Module Structure

```
data/modules/
├── character/
│   ├── character.ts       # TypeScript source (tracked in git)
│   ├── character.js       # Compiled output (gitignored)
│   └── README.md
├── character.js           # Copied to root for Nakama (gitignored)
├── build.sh               # Bash build script
├── build.ps1              # PowerShell build script
└── README.md              # TypeScript build documentation
```

**Key Points:**
- Write TypeScript in subdirectories (`data/modules/character/character.ts`)
- Build system compiles `.ts` → `.js` in the same directory
- Build system copies `.js` files to `data/modules/` root
- Nakama loads from `data/modules/` root via volume mount

## Docker Configuration

The `docker-compose.yml` includes:

```yaml
volumes:
  - ./:/nakama/data
entrypoint:
  - /bin/sh
  - -ecx
  - >
    /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
    exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257
    --runtime.path /nakama/data/data/modules
    --runtime.js_entrypoint character.js
```

**Why these settings?**
- `./:/nakama/data` - Mounts repo root to `/nakama/data/` in container
- `--runtime.path /nakama/data/data/modules` - Points to modules directory
- `--runtime.js_entrypoint character.js` - Specifies which JS file to load

## Troubleshooting

### Modules not loading in Nakama

```powershell
# 1. Verify compilation succeeded
npm run build

# 2. Check JavaScript files exist
ls data\modules\*.js

# 3. Check Nakama logs for errors
docker compose logs nakama | Select-String "runtime|module|error"
```

### TypeScript compilation errors

```powershell
# Manually compile to see detailed errors
npx tsc data\modules\character\character.ts --target ES2015 --module commonjs
```

### Clean rebuild

```powershell
# Remove all compiled files
.\dev.ps1 clean

# Fresh build and start
.\dev.ps1 up-build
```

### Container won't start

```powershell
# Check for port conflicts
netstat -an | Select-String "7349|7350|7351|26257|9090"

# Full reset
docker compose down --volumes
.\dev.ps1 up-build
```

### Common Issues and Solutions

#### Issue: Build fails with "Go module not found"

**Symptom:**
```
ERROR: failed to solve: process "/bin/sh -c go build ..." did not complete successfully
```

**Solution:**
```powershell
# The Dockerfile uses vendored dependencies
# If build fails, vendor dependencies may be missing
# Clone repository again or check build/Dockerfile
```

#### Issue: Migrations fail on startup

**Symptom:**
```
nakama_1 | ERROR: migration failed: pq: relation "users" does not exist
```

**Solution:**
```powershell
# 1. Check migration files exist
ls migrate\sql\

# 2. Reset database and retry
docker compose down --volumes
docker compose up

# 3. If still failing, check database connectivity
docker compose logs cockroachdb
```

#### Issue: Runtime modules not loading

**Symptom:**
```
nakama_1 | ERROR: failed to load runtime module
```

**Solution:**
```powershell
# 1. Verify TypeScript compiled successfully
npm run build

# 2. Check JavaScript files exist in correct location
ls data\modules\*.js

# 3. Verify volume mount path in docker-compose.yml
# Should be: ./:/nakama/data

# 4. Check Nakama runtime configuration
docker compose logs nakama | Select-String "runtime"
```

#### Issue: Database connection refused

**Symptom:**
```
nakama_1 | ERROR: dial tcp: lookup cockroachdb: no such host
```

**Solution:**
```powershell
# The depends_on configuration ensures correct startup order
# If this error appears, health check may have failed

# 1. Check CockroachDB is healthy
docker compose ps

# 2. View CockroachDB logs
docker compose logs cockroachdb

# 3. Restart services in correct order
docker compose down
docker compose up
```

#### Issue: Console returns 404 or won't load

**Symptom:** Browser shows "Cannot GET /" at `http://localhost:7351`

**Solution:**
```powershell
# 1. Verify Nakama started successfully
docker compose logs nakama | Select-String "Console server gateway"

# Expected: "Starting Console server gateway for HTTP requests" port:7351

# 2. Check port mapping
docker compose ps
# Should show: 0.0.0.0:7351->7351/tcp

# 3. Try different browser or clear cache
# Console may be cached with old version
```

#### Issue: Prometheus shows Nakama target as DOWN

**Symptom:** Prometheus targets page shows `health: down` for Nakama

**Solution:**
```powershell
# 1. Verify Nakama exposes metrics port
docker compose logs nakama | Select-String "metrics"

# Expected: "Starting Prometheus server for metrics requests" port:9100

# 2. Check if port 9100 is accessible inside Docker network
docker compose exec prometheus wget -O- http://nakama:9100

# 3. Verify scrape configuration in docker-compose.yml
# Should have: - targets: ['nakama:9100']
```

#### Issue: Changes to server code not reflected after rebuild

**Symptom:** Code changes don't appear even after `docker compose up --build`

**Solution:**
```powershell
# 1. Force complete rebuild without cache
docker compose build --no-cache nakama
docker compose up

# 2. Verify Docker isn't using old image
docker images | Select-String nakama
# Should show recent timestamp

# 3. Remove old containers and images
docker compose down
docker system prune -af  # ⚠️ Removes ALL unused Docker data
docker compose up --build
```

#### Issue: "Database is still in use" error when resetting

**Symptom:**
```
ERROR: network nakama_default has active endpoints
```

**Solution:**
```powershell
# 1. Stop all containers first
docker compose down

# 2. Wait a few seconds for cleanup
Start-Sleep -Seconds 3

# 3. Remove volumes
docker compose down --volumes

# 4. If still failing, force remove
docker network prune -f
docker volume prune -f
```

---

## Security Warnings

### ⚠️ Development-Only Configuration

**This Docker Compose setup is for LOCAL DEVELOPMENT ONLY. Never deploy to production.**

**Insecure settings included:**
- CockroachDB runs with `--insecure` flag (no TLS, no authentication)
- Nakama uses default server key (`defaultkey`)
- Console has default credentials (`admin`/`password`)
- All ports exposed to localhost (no firewall rules)
- Database root user has no password

### Production Deployment Differences

For production, you must:
- ✅ Enable TLS encryption for CockroachDB
- ✅ Use custom Nakama server keys (not `defaultkey`)
- ✅ Set secure console credentials (not `admin`/`password`)
- ✅ Configure firewall rules and network policies
- ✅ Use secrets management (not environment variables)
- ✅ Enable database authentication with strong passwords
- ✅ Use managed database services (not single-node CockroachDB)
- ✅ Implement rate limiting and DDoS protection
- ✅ Configure log aggregation and alerting
- ✅ Use container orchestration (Kubernetes, not Docker Compose)

**Recommended production guides:**
- [Nakama Deployment Checklist](https://heroiclabs.com/docs/nakama/guides/deployment/)
- [CockroachDB Production Deployment](https://www.cockroachlabs.com/docs/stable/recommended-production-settings)

---

## Additional Resources

- **Nakama Documentation:** https://heroiclabs.com/docs
- **Docker Compose Reference:** https://docs.docker.com/compose/
- **CockroachDB Documentation:** https://www.cockroachlabs.com/docs/
- **Prometheus Query Guide:** https://prometheus.io/docs/prometheus/latest/querying/basics/
- **TypeScript Handbook:** https://www.typescriptlang.org/docs/

---

## File Ownership & Permissions

The compiled JavaScript files are:
- ✅ Generated automatically by build scripts
- ✅ Owned by the user running the build scripts
- ✅ Git-ignored (only source TypeScript files are tracked)

---

## Local Source Build Configuration

### Overview

The Docker Compose configuration automatically builds Nakama from your local source code instead of using pre-built images. This enables testing server changes immediately without manual rebuild commands.

### Build Configuration

The `docker-compose.yml` uses the following build configuration:

```yaml
nakama:
  build:
    context: .
    dockerfile: build/Dockerfile
    args:
      COMMIT: ${COMMIT:-dev}
      VERSION: ${VERSION:-local-dev}
```

**What this means:**
- **`context: .`** - Uses repository root as build context
- **`dockerfile: build/Dockerfile`** - Uses existing Dockerfile without modifications
- **`COMMIT`** - Git commit hash for version tracking (defaults to "dev")
- **`VERSION`** - Version identifier (defaults to "local-dev")

### Development Workflows

#### First-Time Setup

```powershell
# 1. Clone repository
git clone https://github.com/JoseETeixeira/nakama.git
cd nakama

# 2. Install Node.js dependencies (for TypeScript modules)
npm install

# 3. Build TypeScript modules
npm run build

# 4. Start entire stack (builds Nakama automatically)
docker compose up

# Wait for startup:
# - First build: ~2-5 minutes (downloads dependencies, compiles Go code)
# - Subsequent builds: ~30 seconds (cached layers)
```

**Services started:**
- CockroachDB (database) - `localhost:26257`
- Nakama Server (gRPC) - `localhost:7349`
- Nakama Server (HTTP) - `localhost:7350`
- Nakama Console (Web UI) - `localhost:7351`
- Prometheus (Metrics) - `localhost:9090`

#### Daily Development

**Scenario 1: Server Code Changes (Go)**

```powershell
# 1. Modify server code
code server/api_character.go

# 2. Rebuild and restart (Docker detects Go file changes)
docker compose up --build

# Or force complete rebuild
docker compose build --no-cache nakama
docker compose up
```

**Scenario 2: Runtime Module Changes (TypeScript)**

```powershell
# Option A: Watch mode (recommended)
# Terminal 1: Auto-compile TypeScript
npm run watch

# Terminal 2: Run Docker Compose
docker compose up

# When you save .ts files, they auto-compile
# Then restart Nakama to load changes:
docker compose restart nakama

# Option B: Manual rebuild
.\dev.ps1 restart  # Windows
make restart       # Linux/Mac
```

**Scenario 3: Database Migration Development**

```powershell
# 1. Create new migration file
cd migrate/sql
# Add: 20251028_add_guilds_table.sql

# 2. Restart Nakama (migrations run automatically on startup)
docker compose restart nakama

# 3. Check migration logs
docker compose logs nakama | Select-String migrate

# Expected: "Successfully applied migration"
```

### Build Environment Variables

You can customize build versioning using environment variables:

```powershell
# Windows PowerShell
$env:COMMIT = $(git rev-parse --short HEAD)
$env:VERSION = "v1.0.0-$(git rev-parse --short HEAD)"
docker compose up --build

# Linux/Mac Bash
export COMMIT=$(git rev-parse --short HEAD)
export VERSION="v1.0.0-$(git rev-parse --short HEAD)"
docker compose up --build
```

**Use cases:**
- Tag builds with git commit hashes for debugging
- Create versioned builds for internal testing
- Differentiate between feature branches

### Build Performance

| Build Type | Expected Time | Notes |
|-----------|---------------|-------|
| Cold build (first time) | 2-5 minutes | Downloads Go modules, compiles from scratch |
| Warm build (code changes) | 30-60 seconds | Uses Docker layer caching |
| No changes (restart) | 5-10 seconds | Reuses existing image |

**Optimization tips:**
- Use `docker compose up` (without `--build`) if no code changes
- Enable Docker BuildKit for faster builds: `$env:DOCKER_BUILDKIT=1`
- Don't use `--no-cache` unless absolutely necessary

---

## Database Migrations

### Automatic Execution

Migrations run automatically when Nakama container starts:

```yaml
entrypoint:
  - "/bin/sh"
  - "-ecx"
  - >
    /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
    exec /nakama/nakama --name nakama1 ...
```

**Behavior:**
- ✅ Migrations run before server starts
- ✅ Idempotent (safe to run multiple times)
- ✅ Container exits if migration fails
- ✅ No manual intervention required

### Migration Files Location

```
migrate/sql/
├── 20241001_initial_schema.sql
├── 20241015_add_characters.sql
├── 20241028_add_guilds.sql        ← Your new migrations
└── ...
```

**Naming convention:** `YYYYMMDD_description.sql`

### Checking Migration Status

```powershell
# View migration logs
docker compose logs nakama | Select-String migrate

# Expected output:
# nakama_1 | {"level":"info","msg":"Applying database migrations","count":30}
# nakama_1 | {"level":"info","msg":"Successfully applied migration","count":30}
```

### Resetting Database

```powershell
# ⚠️ WARNING: Deletes all data
docker compose down --volumes
docker compose up

# Fresh database with all migrations applied
```

---

## Monitoring and Debugging

### Nakama Console (Admin UI)

**URL:** `http://localhost:7351`
**Credentials:** `admin` / `password` (development mode)

**Features:**
- View server status and connected users
- Execute runtime RPCs manually
- Query database storage
- Monitor matches and leaderboards
- Reload runtime modules without restart

### Prometheus Metrics

**URL:** `http://localhost:9090`

**Available metrics:**
- `nakama_presences` - Active user sessions
- `nakama_db_*` - Database connection pool stats
- `nakama_lua_runtimes` / `nakama_javascript_runtimes` - Runtime module performance
- `nakama_matchmaker_*` - Matchmaker metrics

**Example queries:**
```promql
# Active sessions
nakama_presences

# Database connections
nakama_db_in_use_conns

# Runtime performance
rate(nakama_javascript_runtimes[5m])
```

**Scrape interval:** 15 seconds (configured in `docker-compose.yml`)

### Viewing Logs

```powershell
# All services
docker compose logs -f

# Specific service
docker compose logs -f nakama
docker compose logs -f cockroachdb

# Filter by keyword
docker compose logs nakama | Select-String "error|warning|migration"

# Last 100 lines
docker compose logs --tail=100 nakama
```

### Service Health Checks

```powershell
# Check service status
docker compose ps

# Expected output:
# NAME                   STATUS
# nakama-nakama-1        Up (healthy)
# nakama-cockroachdb-1   Up (healthy)
# nakama-prometheus-1    Up
```

---

## Troubleshooting
- ✅ Gitignored (not tracked in version control)
- ✅ Recreated on every build
- ❌ Should NOT be manually edited (edit `.ts` files instead)

## Performance

- **TypeScript compilation**: ~1-2 seconds (single module)
- **Watch mode incremental**: ~100-300ms
- **Container restart**: ~2-3 seconds
- **Full stack startup**: ~10-15 seconds

## Next Steps

- See `data/modules/README.md` for detailed TypeScript build documentation
- See `.kiro/specs/docker-compose-local-build/` for feature specifications
- See main `README.md` for Nakama usage documentation
