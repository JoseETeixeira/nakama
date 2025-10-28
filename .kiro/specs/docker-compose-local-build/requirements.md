# Requirements: Docker Compose Local Build Configuration

**Document Information**
- **Feature Name:** Docker Compose Local Build Configuration
- **Version:** 1.0
- **Date:** October 28, 2025
- **Author:** Kiro (AI Assistant)
- **Stakeholders:** Development Team, DevOps, System Operators

## Introduction

The current `docker-compose.yml` configuration uses pre-built Nakama images from the Heroic Labs registry (`registry.heroiclabs.com/heroiclabs/nakama:3.30.0`). For active MMORPG development with custom TypeScript runtime modules, this creates a significant friction point: every code change requires manually rebuilding and restarting the container, or developers must run Nakama outside Docker entirely.

This feature transforms the Docker Compose configuration to automatically build Nakama from the local source directory, apply database migrations on startup, and run both the Nakama server (with console) and database in a seamless development workflow. This enables hot-reload workflows, eliminates manual build steps, and ensures the running server always reflects the latest local code changes.

## Feature Summary

Docker Compose will automatically build Nakama from the current working directory using the existing `build/Dockerfile`, apply migrations on container startup, and run the complete stack (database + Nakama server with console) with a single `docker compose up` command.

## Business Value

**Developer Productivity:**
- Eliminates manual `docker build` commands after every server or runtime module change
- Reduces iteration time from ~2-3 minutes (manual rebuild + restart) to <30 seconds (automatic rebuild on `docker compose up`)
- Provides consistent development environment across all team members

**Development Experience:**
- Single command (`docker compose up`) brings up the entire MMORPG development stack
- Automatic migration application ensures database schema is always in sync with code
- Console access included by default for debugging and live operations testing

**Expected Outcomes:**
- 50%+ reduction in developer friction during server-side feature development
- Zero "forgot to rebuild" incidents causing confusion with stale binaries
- Faster onboarding for new developers (one command to get started)

## Scope

**In Scope:**
- Modify `docker-compose.yml` to build Nakama from local source using `build/Dockerfile`
- Configure automatic database migration execution on Nakama container startup
- Ensure Nakama console is accessible (default port 7351)
- Preserve existing database (CockroachDB) and metrics (Prometheus) configuration
- Maintain health checks for both database and Nakama services
- Support development workflow with hot-reload capability

**Out of Scope:**
- Production deployment configurations (blue/green, canary, Kubernetes)
- Multi-region or multi-shard setups
- Custom Dockerfile modifications (use existing `build/Dockerfile`)
- CI/CD pipeline integration
- Secrets management or environment-specific configurations beyond local development
- Godot client Docker configuration

---

## Requirements

### Requirement 1: Local Source Build Configuration

**User Story:** As a developer, I want Docker Compose to automatically build Nakama from my local source code, so that I can test my server changes immediately without manual rebuild commands.

**Acceptance Criteria (EARS)**
- WHEN `docker compose up` is executed, THEN the Docker Compose configuration SHALL build the Nakama image using `build/Dockerfile` from the current working directory
- IF the local source code has changed since the last build, THEN Docker Compose SHALL detect the changes and rebuild the Nakama image automatically
- WHEN the build process completes successfully, THEN the system SHALL tag the built image with a recognizable local identifier (e.g., `nakama:local-dev`)
- IF the build process fails, THEN Docker Compose SHALL display the build error output and halt the startup process
- WHERE the Nakama service is defined in `docker-compose.yml`, the configuration SHALL use the `build` directive pointing to the repository root with `context: .` and `dockerfile: build/Dockerfile`

**Additional Details**
- **Priority:** High
- **Complexity:** Low
- **Dependencies:** Existing `build/Dockerfile` must remain functional
- **Assumptions:**
  - Developers have Docker and Docker Compose installed locally
  - The `build/Dockerfile` is capable of building Nakama from source
  - Git commit hash can be obtained via build args for versioning

---

### Requirement 2: Automatic Database Migration Execution

**User Story:** As a developer, I want database migrations to run automatically when the Nakama container starts, so that my database schema is always synchronized with the codebase without manual intervention.

**Acceptance Criteria (EARS)**
- WHEN the Nakama container starts, THEN the system SHALL execute `/nakama/nakama migrate up --database.address root@cockroachdb:26257` before starting the main server process
- IF migrations are already applied, THEN the migration command SHALL exit successfully with no-op behavior (idempotent)
- IF a migration fails, THEN the Nakama container SHALL exit with a non-zero status code and log the migration error
- WHEN all migrations complete successfully, THEN the system SHALL proceed to start the Nakama server process
- WHERE the database is not yet ready, THEN the Nakama container SHALL wait for the CockroachDB health check to pass before attempting migrations (via `depends_on` with health condition)

**Additional Details**
- **Priority:** High
- **Complexity:** Low
- **Dependencies:**
  - CockroachDB container must be healthy before Nakama starts
  - Migration files in `migrate/sql/` must be present in the container
- **Assumptions:**
  - Migrations are versioned and safe to run multiple times
  - Database connection string `root@cockroachdb:26257` is correct for the Docker network

---

### Requirement 3: Nakama Console Accessibility

**User Story:** As a developer, I want the Nakama admin console to be accessible on my local machine, so that I can debug server state, inspect runtime modules, and test live operations features during development.

**Acceptance Criteria (EARS)**
- WHEN the Nakama server starts successfully, THEN the console SHALL be accessible at `http://localhost:7351` on the host machine
- IF the Nakama container is running, THEN port 7351 SHALL be mapped from the container to the host using the `ports` directive
- WHEN a developer navigates to `http://localhost:7351` in a browser, THEN the Nakama console web UI SHALL load without authentication errors (development mode)
- WHERE multiple developers run the stack simultaneously, THEN each developer's console SHALL remain isolated to their respective containers (no port conflicts assumed)

**Additional Details**
- **Priority:** Medium
- **Complexity:** Low
- **Dependencies:** Nakama binary must be built with console support enabled (default)
- **Assumptions:**
  - Port 7351 is not already in use on the host machine
  - Console is enabled by default in Nakama (no additional flags required)

---

### Requirement 4: Runtime Module Volume Mounting

**User Story:** As a developer, I want my local TypeScript runtime modules to be accessible inside the Nakama container, so that I can edit module code and reload the server without rebuilding the Docker image.

**Acceptance Criteria (EARS)**
- WHEN the Nakama container starts, THEN the local `data/modules/` directory SHALL be mounted to `/nakama/data/modules` inside the container
- IF a developer modifies a TypeScript file in `data/modules/`, THEN the changes SHALL be visible inside the container immediately (live mount)
- WHEN Nakama runtime reloads modules (via console or automatic reload), THEN the updated module code SHALL be used
- WHERE TypeScript modules require compilation, THEN developers SHALL be responsible for compiling modules before Nakama loads them (out of scope for Docker Compose automation)
- IF the `data/modules/` directory does not exist, THEN the Nakama container SHALL start successfully with an empty modules directory

**Additional Details**
- **Priority:** High
- **Complexity:** Low
- **Dependencies:** Existing volume mount configuration `./:/nakama/data` already provides this functionality
- **Assumptions:**
  - Current volume mount `./:/nakama/data` mounts the entire repository root, which includes `data/modules/`
  - TypeScript runtime modules are compiled to JavaScript before Nakama loads them (build step not automated)

---

### Requirement 5: Database Persistence Across Restarts

**User Story:** As a developer, I want my database data to persist across `docker compose down` and `docker compose up` cycles, so that I don't lose test characters, world state, or migrations every time I restart the stack.

**Acceptance Criteria (EARS)**
- WHEN `docker compose down` is executed without `--volumes` flag, THEN the database data SHALL be preserved in a Docker named volume
- WHEN `docker compose up` is executed after a previous shutdown, THEN the CockroachDB container SHALL restore data from the persisted volume
- IF a developer wants to reset the database, THEN running `docker compose down --volumes` SHALL delete the persisted data volume
- WHERE the volume is named `data` in the `volumes` section, THEN the CockroachDB container SHALL mount this volume at `/var/lib/cockroach`
- WHEN the volume does not exist (first run), THEN Docker SHALL create the named volume automatically

**Additional Details**
- **Priority:** Medium
- **Complexity:** Low
- **Dependencies:** Existing volume configuration already provides this (volume named `data`)
- **Assumptions:**
  - Developers understand `docker compose down` vs `docker compose down --volumes` behavior
  - The named volume `data` is sufficient for development persistence needs

---

### Requirement 6: Service Health Checks and Startup Order

**User Story:** As a developer, I want the Nakama container to wait for the database to be fully ready before starting, so that I don't encounter connection errors during startup.

**Acceptance Criteria (EARS)**
- WHEN `docker compose up` is executed, THEN the CockroachDB container SHALL start first
- IF the CockroachDB container's health check passes (HTTP 200 from `/health?ready=1`), THEN the Nakama container SHALL be allowed to start
- WHEN the Nakama container starts before the database is ready, THEN Docker Compose SHALL delay the Nakama startup until the `condition: service_healthy` is satisfied
- WHERE the CockroachDB health check fails after 5 retries (15 seconds total), THEN the Nakama container SHALL not start and Docker Compose SHALL report the health check failure
- WHEN the Nakama container is running, THEN its own health check (`/nakama/nakama healthcheck`) SHALL report the server's readiness for traffic

**Additional Details**
- **Priority:** High
- **Complexity:** Low
- **Dependencies:**
  - CockroachDB must expose the `/health?ready=1` endpoint
  - Nakama binary must support the `healthcheck` subcommand
- **Assumptions:**
  - Health check intervals and timeouts are reasonable for local development (3s interval, 3s timeout for DB)
  - Existing health check configuration is sufficient (already defined in current docker-compose.yml)

---

### Requirement 7: Prometheus Metrics for Development Monitoring

**User Story:** As a developer, I want Prometheus metrics collection to be included in the development stack, so that I can monitor server performance, RPC latency, and resource usage during local testing.

**Acceptance Criteria (EARS)**
- WHEN `docker compose up` is executed, THEN the Prometheus container SHALL start and begin scraping metrics from the Nakama server
- IF Nakama exposes metrics on port 9100 (configured via `--metrics.prometheus_port 9100`), THEN Prometheus SHALL scrape this endpoint every 15 seconds
- WHEN a developer navigates to `http://localhost:9090`, THEN the Prometheus web UI SHALL be accessible for querying metrics and viewing targets
- WHERE the Prometheus configuration is defined inline in `docker-compose.yml`, THEN the scrape configuration SHALL include both the Prometheus self-monitoring job and the Nakama metrics job
- IF the Nakama container is not yet healthy, THEN Prometheus SHALL mark the target as `DOWN` but continue attempting scrapes

**Additional Details**
- **Priority:** Low
- **Complexity:** Low
- **Dependencies:**
  - Nakama must be started with `--metrics.prometheus_port 9100` flag
  - Existing Prometheus configuration already provides this functionality
- **Assumptions:**
  - Developers are familiar with Prometheus query language (PromQL) or can learn as needed
  - Grafana dashboards are out of scope for this feature (developers can add manually if needed)

---

## Non-Functional Requirements

### Performance Requirements

- WHEN Docker Compose builds the Nakama image from scratch, THEN the build process SHALL complete within 5 minutes on a typical developer workstation (4-core CPU, 16GB RAM, SSD)
- IF the Docker build cache is warm (no code changes), THEN `docker compose up` SHALL start all services within 30 seconds
- WHEN migrations are applied on startup, THEN the migration step SHALL complete within 10 seconds for typical development schemas (<100 migrations)

### Reliability Requirements

- WHEN the Nakama build fails due to compilation errors, THEN Docker Compose SHALL display the Go compiler error output and exit with a non-zero status code
- IF the database container crashes during Nakama startup, THEN the Nakama container SHALL retry the database connection according to the health check retry policy (5 retries, 3s interval)
- WHEN `docker compose up` is interrupted (Ctrl+C), THEN all containers SHALL shut down gracefully within 10 seconds

### Usability Requirements

- WHEN a new developer clones the repository, THEN running `docker compose up` SHALL be sufficient to start the entire development environment (no manual configuration required)
- IF a developer modifies server code and wants to test changes, THEN running `docker compose up --build` SHALL rebuild and restart the Nakama container with updated code
- WHEN errors occur during startup (build failures, migration errors, health check failures), THEN the error messages SHALL be displayed in the terminal with sufficient context for debugging

### Security Requirements

- WHEN the CockroachDB container is started, THEN it SHALL run in `--insecure` mode for local development (no TLS or authentication required)
- IF the Nakama server is started, THEN it SHALL use the default server key (`defaultkey`) for development (not suitable for production)
- WHERE ports are exposed to the host machine, THEN they SHALL bind to `localhost` only (implicit Docker Compose behavior) to prevent external network access

---

## Constraints and Assumptions

### Technical Constraints

- Docker Compose version 2.x or higher must be installed (required for `depends_on` with health conditions)
- The existing `build/Dockerfile` must remain functional and cannot be modified as part of this feature
- Go 1.25.0 is required for building Nakama (defined in Dockerfile)
- CockroachDB version 24.1 is the target database (defined in current docker-compose.yml)
- The repository root must be the build context to access both source code and migrations

### Business Constraints

- This configuration is intended for **local development only**, not production deployments
- Developers must have sufficient disk space for Docker images (~2GB for Nakama + CockroachDB)
- Network ports 7349, 7350, 7351, 8080, 9090, 26257 must be available on the host machine

### Assumptions

- Developers are running Docker Desktop (Windows/macOS) or Docker Engine (Linux) with Docker Compose plugin
- The `data/modules/` directory contains pre-compiled JavaScript runtime modules (TypeScript compilation is a separate build step)
- Developers understand basic Docker Compose commands (`up`, `down`, `logs`, `ps`)
- The current `docker-compose.yml` structure (services, volumes, networks) is generally acceptable and only needs build configuration adjustments
- Git is installed and the repository is a valid Git repository (for obtaining commit hashes via build args)

---

## Success Criteria

### Definition of Done

- All acceptance criteria are met and verified
- The `docker-compose.yml` file builds Nakama from local source instead of pulling pre-built images
- Database migrations run automatically on Nakama container startup
- Nakama console is accessible at `http://localhost:7351`
- Prometheus metrics are scraped from Nakama and visible at `http://localhost:9090`
- The entire stack can be started with a single `docker compose up` command
- The stack can be stopped and restarted with database persistence intact
- Integration testing confirms character creation/selection works with the local-built Nakama

### Acceptance Metrics

- **Build Time:** Initial build completes in <5 minutes; cached rebuild in <1 minute
- **Startup Time:** Full stack startup (cold) in <60 seconds; warm restart in <30 seconds
- **Migration Success Rate:** 100% of migration runs succeed without manual intervention
- **Developer Adoption:** 100% of team members can run the stack on first try without assistance

---

## Glossary

| Term | Definition |
|---|---|
| Nakama | Open-source server for social and real-time games, extended for MMORPG features |
| CockroachDB | Distributed SQL database used for persistent storage in this project |
| Console | Nakama's web-based admin interface for debugging and live operations |
| Runtime Module | TypeScript or Lua code that extends Nakama's functionality with custom game logic |
| Migration | Versioned SQL script that modifies the database schema (stored in `migrate/sql/`) |
| Prometheus | Open-source monitoring system that scrapes metrics from Nakama |
| Health Check | Docker mechanism to determine if a container's service is ready to accept traffic |
| Named Volume | Docker persistent storage mechanism that survives container restarts |
| Build Context | The directory tree Docker uses to access files during image builds |
| Hot Reload | Ability to update code without full container rebuild (limited to runtime modules) |

---

## Requirements Review Checklist

### Completeness
- ✅ All user stories have clear roles, features, and benefits
- ✅ Each requirement has specific acceptance criteria using EARS format
- ✅ Non-functional requirements are addressed (performance, reliability, usability, security)
- ✅ Success criteria are defined and measurable

### Quality
- ✅ Requirements are written in active voice
- ✅ Each acceptance criterion is testable
- ✅ Requirements avoid implementation details (focus on "what" not "how")
- ✅ Terminology is consistent throughout

### EARS Format Validation
- ✅ WHEN statements describe specific events or triggers
- ✅ IF statements describe clear conditions or states
- ✅ WHERE statements describe specific contexts
- ✅ All statements use **SHALL** for system responses

### Clarity
- ✅ Requirements are unambiguous
- ✅ Technical jargon is explained in glossary
- ✅ Stakeholders can understand all requirements
- ✅ No conflicting requirements exist

### Traceability
- ✅ Requirements are numbered and organized
- ✅ Dependencies between requirements are clear
- ✅ Requirements link to business objectives (developer productivity, faster iteration)
- ✅ Assumptions and constraints are documented

---

## Implementation Notes

**Current State Analysis:**

The existing `docker-compose.yml` uses:
```yaml
nakama:
  image: registry.heroiclabs.com/heroiclabs/nakama:3.30.0
  entrypoint:
    - "/bin/sh"
    - "-ecx"
    - >
      /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
      exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257 ...
```

**Required Changes:**

1. Replace `image:` with `build:` directive pointing to `build/Dockerfile`
2. Add build args for commit hash and version (`$(git rev-parse --short HEAD)`)
3. Preserve existing entrypoint for migration execution
4. Ensure volume mounts include the repository root for runtime modules
5. Verify all ports are correctly exposed (7349, 7350, 7351, 9100)

**Migration Strategy:**

- The current entrypoint already runs migrations before starting the server ✅
- Health check configuration already exists and is correct ✅
- Volume mount `./:/nakama/data` already provides runtime module access ✅
- Minimal changes required to switch from pre-built image to local build

