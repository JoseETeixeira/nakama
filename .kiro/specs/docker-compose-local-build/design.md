# Design: Docker Compose Local Build Configuration

**Document Information**
- **Feature Name:** Docker Compose Local Build Configuration
- **Version:** 1.0
- **Date:** October 28, 2025
- **Author:** Kiro (AI Assistant)
- **Related Requirements:** Requirements 1-7 from `requirements.md`

---

## Overview

This design document specifies the technical implementation for transforming the current `docker-compose.yml` from using pre-built Nakama images to automatically building Nakama from the local source repository. The implementation requires minimal changes to the existing Docker Compose configuration while maintaining all current functionality (health checks, migrations, console access, metrics).

### Design Goals

1. **Zero Manual Steps:** Developers run `docker compose up` to build, migrate, and start the entire stack
2. **Preserve Existing Behavior:** Database persistence, health checks, and service dependencies remain unchanged
3. **Minimal Configuration Changes:** Leverage existing `build/Dockerfile` without modifications
4. **Fast Iteration:** Support cached builds and hot-reload for runtime modules

---

## Architecture

### Current State

```yaml
nakama:
  image: registry.heroiclabs.com/heroiclabs/nakama:3.30.0
  # ... rest of configuration
```

**Problems:**
- Uses pre-built image (version 3.30.0) that doesn't include local code changes
- Requires manual `docker build` and image tagging for custom builds
- No automatic versioning of local builds

### Target State

```yaml
nakama:
  build:
    context: .
    dockerfile: build/Dockerfile
    args:
      COMMIT: ${COMMIT:-dev}
      VERSION: ${VERSION:-local-dev}
  # ... rest of configuration (unchanged)
```

**Benefits:**
- Builds from current repository state automatically
- Supports build-time versioning via environment variables
- Integrates seamlessly with existing entrypoint (migrations + server startup)

---

## Component Design

### 1. Nakama Service Build Configuration

**Requirement Traceability:** Requirement 1 (Local Source Build Configuration)

#### Build Context

```yaml
build:
  context: .
  dockerfile: build/Dockerfile
```

**Rationale:**
- `context: .` sets the build context to the repository root, giving Docker access to all source files
- `dockerfile: build/Dockerfile` uses the existing Dockerfile without modifications
- Repository root context required because Dockerfile uses `COPY . .` to copy source code

#### Build Arguments

```yaml
args:
  COMMIT: ${COMMIT:-dev}
  VERSION: ${VERSION:-local-dev}
```

**Rationale:**
- `COMMIT` defaults to `"dev"` if not set (developers can override with git commit hash)
- `VERSION` defaults to `"local-dev"` for easy identification in logs/console
- Build args match the Dockerfile's `ARG COMMIT` and `ARG VERSION` declarations
- Developers can set environment variables before `docker compose up`:
  ```powershell
  $env:COMMIT = $(git rev-parse --short HEAD)
  $env:VERSION = "$(git rev-parse --short HEAD)"
  docker compose up --build
  ```

#### Image Tagging

Docker Compose automatically tags the built image as `nakama-nakama:latest` (project-service format). Developers can verify with `docker images | Select-String nakama`.

---

### 2. Migration Execution Strategy

**Requirement Traceability:** Requirement 2 (Automatic Database Migration Execution)

#### Current Entrypoint (PRESERVED)

```yaml
entrypoint:
  - "/bin/sh"
  - "-ecx"
  - >
      /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
      exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257 --logger.level DEBUG --session.token_expiry_sec 7200 --metrics.prometheus_port 9100
```

**Design Decision:** No changes required. The existing entrypoint already:
1. Runs `migrate up` before starting the server (idempotent)
2. Uses `&&` to ensure migrations succeed before server starts
3. Uses `exec` to replace the shell with the Nakama process (proper signal handling)

#### Migration File Availability

The `build/Dockerfile` copies the entire repository (including `migrate/sql/`) into the container:

```dockerfile
WORKDIR /go/build/nakama
COPY . .
```

After the build stage, the final image contains the Nakama binary but **not** the migration files. This is a critical issue.

**Problem Identified:** The existing Dockerfile's final stage only copies the binary:

```dockerfile
COPY --from=builder "/go/build-out/nakama" /nakama/
```

**Solution:** Migrations must be accessible via the volume mount:

```yaml
volumes:
  - ./:/nakama/data
```

The migration command must be updated to reference the correct path:

```yaml
/nakama/nakama migrate up --database.address root@cockroachdb:26257 --migration.path /nakama/data/migrate/sql
```

**Wait—Verification Needed:** Let me check if the Nakama binary embeds migrations or requires external files.

**Alternative Design (if migrations are embedded):** If Nakama embeds migrations at build time, no entrypoint changes are needed. The `COPY . .` in the builder stage would include migrations, and the Go build would embed them.

**Recommendation:** Test the current setup first. If migrations fail, add `--migration.path` flag.

---

### 3. Service Dependencies and Health Checks

**Requirement Traceability:** Requirement 6 (Service Health Checks and Startup Order)

#### Dependency Graph

```
prometheus (metrics collector)
    ↓
cockroachdb (database) → [health check] → nakama (server + console)
```

#### Current Configuration (PRESERVED)

```yaml
depends_on:
  cockroachdb:
    condition: service_healthy
  prometheus:
    condition: service_started
```

**Design Decision:** No changes required. This configuration ensures:
1. CockroachDB starts first and waits for health check to pass
2. Prometheus starts in parallel (doesn't block Nakama startup)
3. Nakama waits for database health before attempting migrations

#### Health Check Specifications

**CockroachDB Health Check:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health?ready=1"]
  interval: 3s
  timeout: 3s
  retries: 5
```

**Analysis:**
- Maximum startup wait: 3s × 5 = 15 seconds
- Checks database readiness (not just process running)
- Uses CockroachDB's built-in health endpoint

**Nakama Health Check:**
```yaml
healthcheck:
  test: ["CMD", "/nakama/nakama", "healthcheck"]
  interval: 10s
  timeout: 5s
  retries: 5
```

**Analysis:**
- Maximum startup wait: 10s × 5 = 50 seconds
- Uses Nakama's built-in healthcheck subcommand
- Verifies server is ready to accept connections

---

### 4. Volume Mounts and Runtime Module Access

**Requirement Traceability:** Requirement 4 (Runtime Module Volume Mounting)

#### Current Volume Configuration (PRESERVED)

```yaml
volumes:
  - ./:/nakama/data
```

**Design Analysis:**

This mount provides:
- ✅ Access to `data/modules/` for TypeScript runtime modules
- ✅ Access to `migrate/sql/` for database migrations (if needed)
- ✅ Access to any other `data/` directory contents (logs, configs, etc.)

**Hot Reload Behavior:**

1. **TypeScript Modules:** Changes to `data/modules/*.ts` are visible inside the container immediately
2. **Compilation Required:** Nakama loads JavaScript, not TypeScript. Developers must compile `.ts` → `.js` before Nakama reloads
3. **Module Reload:** Nakama console provides "Reload Modules" button, or restart the container

**Design Decision:** No changes required. The current volume mount is sufficient for development workflows.

---

### 5. Port Mapping and Console Access

**Requirement Traceability:** Requirement 3 (Nakama Console Accessibility)

#### Current Port Configuration (PRESERVED)

```yaml
expose:
  - "7349"  # gRPC API
  - "7350"  # HTTP API
  - "7351"  # Console
  - "9100"  # Prometheus metrics
ports:
  - "7349:7349"
  - "7350:7350"
  - "7351:7351"
```

**Console Access:**
- URL: `http://localhost:7351`
- Default credentials: `admin` / `password` (development mode)
- No additional configuration required

**Design Decision:** No changes required. All ports are correctly exposed.

---

### 6. Database Persistence

**Requirement Traceability:** Requirement 5 (Database Persistence Across Restarts)

#### Named Volume Configuration (PRESERVED)

```yaml
volumes:
  data:

services:
  cockroachdb:
    volumes:
      - data:/var/lib/cockroach
```

**Persistence Behavior:**

| Command | Database State |
|---------|---------------|
| `docker compose down` | ✅ Data persists in named volume `data` |
| `docker compose up` | ✅ Data restored from volume |
| `docker compose down --volumes` | ❌ Data deleted (intentional reset) |

**Design Decision:** No changes required. Named volume provides the required persistence.

---

### 7. Prometheus Metrics Collection

**Requirement Traceability:** Requirement 7 (Prometheus Metrics for Development Monitoring)

#### Current Configuration (PRESERVED)

```yaml
prometheus:
  image: prom/prometheus
  entrypoint: /bin/sh -c
  command: |
    'sh -s <<EOF
      cat > ./prometheus.yml <<EON
    global:
      scrape_interval:     15s
      evaluation_interval: 15s

    scrape_configs:
      - job_name: prometheus
        static_configs:
        - targets: ['localhost:9090']

      - job_name: nakama
        metrics_path: /
        static_configs:
        - targets: ['nakama:9100']
    EON
    prometheus --config.file=./prometheus.yml
    EOF'
```

**Metrics Flow:**

1. Nakama exposes metrics on port 9100 (configured via `--metrics.prometheus_port 9100`)
2. Prometheus scrapes `http://nakama:9100/` every 15 seconds
3. Metrics available at `http://localhost:9090/graph`

**Design Decision:** No changes required. Metrics collection works with both pre-built and locally-built Nakama images.

---

## Implementation Plan

### Changes Required

**File:** `docker-compose.yml`

**Section:** Nakama service

**Before:**
```yaml
nakama:
  image: registry.heroiclabs.com/heroiclabs/nakama:3.30.0
  entrypoint:
    - "/bin/sh"
    - "-ecx"
    - >
        /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
        exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257 --logger.level DEBUG --session.token_expiry_sec 7200 --metrics.prometheus_port 9100
  # ... rest unchanged
```

**After:**
```yaml
nakama:
  build:
    context: .
    dockerfile: build/Dockerfile
    args:
      COMMIT: ${COMMIT:-dev}
      VERSION: ${VERSION:-local-dev}
  entrypoint:
    - "/bin/sh"
    - "-ecx"
    - >
        /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
        exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257 --logger.level DEBUG --session.token_expiry_sec 7200 --metrics.prometheus_port 9100
  # ... rest unchanged
```

**Change Summary:**
- Remove `image:` directive
- Add `build:` section with context, dockerfile, and args
- Preserve all other configuration (entrypoint, volumes, ports, health checks, dependencies)

---

## Developer Workflows

### Initial Setup (First-Time Developer)

```powershell
# Clone repository
git clone https://github.com/JoseETeixeira/nakama.git
cd nakama

# Start the entire stack (builds Nakama automatically)
docker compose up

# Wait for startup (~2 minutes first build, ~30s subsequent)
# Console available at http://localhost:7351
```

### Daily Development Workflow

```powershell
# Make changes to server code or runtime modules
code server/api_character.go
code data/modules/character/character.ts

# Rebuild and restart (Docker detects changes)
docker compose up --build

# Or force clean rebuild
docker compose build --no-cache nakama
docker compose up
```

### Migration Development Workflow

```powershell
# Create new migration
cd migrate/sql
# Add new .sql file (e.g., 20251028_add_guilds_table.sql)

# Restart stack (migrations run automatically)
docker compose restart nakama

# Check migration logs
docker compose logs nakama | Select-String migrate
```

### Troubleshooting Commands

```powershell
# Check service status
docker compose ps

# View logs
docker compose logs nakama
docker compose logs cockroachdb

# Reset database (deletes all data)
docker compose down --volumes
docker compose up

# Rebuild without cache
docker compose build --no-cache nakama
docker compose up
```

---

## Testing Plan

### Acceptance Tests (Verify Requirements)

**Test 1: Local Build Verification (Requirement 1)**
```powershell
# Start stack
docker compose up --build

# Verify image built locally
docker images | Select-String nakama

# Expected: nakama-nakama:latest tagged with recent timestamp
```

**Test 2: Migration Execution (Requirement 2)**
```powershell
# Start stack with clean database
docker compose down --volumes
docker compose up

# Check logs for migration success
docker compose logs nakama | Select-String "migrate up"

# Expected: "Migration successful" or similar message
```

**Test 3: Console Accessibility (Requirement 3)**
```powershell
# Start stack
docker compose up

# Open browser to http://localhost:7351
# Login with admin/password

# Expected: Console UI loads, can view server status
```

**Test 4: Runtime Module Hot Reload (Requirement 4)**
```powershell
# Start stack
docker compose up

# Modify data/modules/character/character.ts
# Compile TypeScript to JavaScript (if needed)
# Reload modules via console or restart container

docker compose restart nakama

# Expected: Changes reflected in RPC behavior
```

**Test 5: Database Persistence (Requirement 5)**
```powershell
# Start stack and create test character
docker compose up
# Use console to create character "TestUser"

# Stop and restart
docker compose down
docker compose up

# Expected: "TestUser" character still exists
```

**Test 6: Health Check Ordering (Requirement 6)**
```powershell
# Start stack from scratch
docker compose up

# Monitor startup order
docker compose logs -f

# Expected:
# 1. CockroachDB starts and health check passes
# 2. Nakama starts after DB is healthy
# 3. No connection errors
```

**Test 7: Prometheus Metrics (Requirement 7)**
```powershell
# Start stack
docker compose up

# Open browser to http://localhost:9090
# Query: nakama_sessions_total

# Expected: Metrics visible and updating every 15s
```

---

## Performance Considerations

### Build Time Optimization

**Cold Build (first time):**
- Go module download: ~1 minute
- Nakama compilation: ~2-3 minutes
- Total: ~5 minutes

**Warm Build (cached):**
- Docker layer cache hit: ~10 seconds
- Changed files recompile: ~30 seconds
- Total: <1 minute

**Optimization Strategies:**

1. **Multi-Stage Dockerfile:** The existing `build/Dockerfile` already uses multi-stage builds (builder + final image)
2. **Go Module Caching:** Docker caches the `go mod vendor` layer unless `go.mod` changes
3. **BuildKit:** Enable Docker BuildKit for faster builds:
   ```powershell
   $env:DOCKER_BUILDKIT = 1
   docker compose build
   ```

### Startup Time Targets

| Phase | Time Budget | Actual (Expected) |
|-------|-------------|-------------------|
| CockroachDB startup | 15s max | ~5-10s |
| Nakama build (cached) | 60s max | ~30s |
| Migration execution | 10s max | ~2-5s |
| Nakama startup | 20s max | ~5-10s |
| **Total (warm restart)** | **60s** | **~30s** ✅ |

---

## Security Considerations

### Development-Only Configuration

**Insecure Settings (acceptable for local dev):**
- CockroachDB runs with `--insecure` (no TLS, no authentication)
- Nakama uses default server key (`defaultkey`)
- Console has default credentials (`admin`/`password`)
- All ports exposed to localhost (no external access)

**Warning for Developers:**

> ⚠️ This Docker Compose configuration is **for local development only**. Never deploy this to production or expose ports to public networks. Production deployments require:
> - TLS encryption for CockroachDB
> - Custom Nakama server keys
> - Secure console credentials
> - Firewall rules restricting port access

### Data Security

- Database data persists in Docker named volume (encrypted at rest if host system uses disk encryption)
- No sensitive data should be committed to the repository (use `.env` files for secrets, add to `.gitignore`)

---

## Migration Path

### Rollback Plan

If the local build configuration causes issues, developers can revert to the pre-built image:

```yaml
nakama:
  image: registry.heroiclabs.com/heroiclabs/nakama:3.30.0
  # Comment out build section
  # build:
  #   context: .
  #   dockerfile: build/Dockerfile
```

### Compatibility

**Backward Compatibility:**
- All existing runtime modules continue to work (volume mount unchanged)
- Database schema unchanged (same migrations)
- API endpoints unchanged (same Nakama version baseline)

**Forward Compatibility:**
- Future Nakama upstream updates can be merged into the codebase
- Build configuration supports version tagging via environment variables

---

## Open Questions and Decisions

### Question 1: Migration File Location

**Issue:** Does the Nakama binary embed migrations at build time, or does it require external files?

**Investigation Required:**
1. Test current setup: Start stack and check if migrations run successfully
2. If migrations fail with "migration path not found":
   - Add `--migration.path /nakama/data/migrate/sql` to entrypoint
   - Verify migrations are accessible via volume mount

**Decision:** Defer to testing. Most likely, migrations need explicit path since the Dockerfile only copies the binary to the final image.

### Question 2: TypeScript Compilation Automation

**Issue:** Runtime modules are written in TypeScript but Nakama loads JavaScript. Should Docker Compose automate compilation?

**Options:**
1. **Manual Compilation (Current):** Developers run `tsc` or build script before running Nakama
2. **Docker Multi-Stage Build:** Add TypeScript compilation to Dockerfile
3. **Watch Mode:** Run `tsc --watch` in a separate container

**Decision:** Out of scope for this feature. TypeScript compilation is a separate build step. Document the manual workflow in the design.

---

## Conclusion

This design transforms the Docker Compose configuration from using pre-built Nakama images to building from local source with minimal changes. The implementation requires modifying only the `nakama` service definition in `docker-compose.yml`, replacing the `image:` directive with a `build:` section.

**Key Design Principles:**
1. **Minimal Changes:** Preserve all existing functionality (health checks, migrations, volumes, ports)
2. **Zero Manual Steps:** `docker compose up` handles build, migrate, and startup automatically
3. **Developer-Friendly:** Fast cached builds, hot-reload for modules, single command workflow
4. **Production-Safe:** Clear separation between development and production configurations

**Next Steps:**
1. Implement the changes in `docker-compose.yml`
2. Test all acceptance criteria (7 requirements)
3. Document workflows in project README
4. Train team members on new workflow

