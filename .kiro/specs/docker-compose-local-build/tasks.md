# Tasks: Docker Compose Local Build Configuration

**Feature:** Docker Compose Local Build Configuration
**Requirements:** Requirements 1-7
**Design:** design.md

---

## Task Breakdown

### Phase 1: Core Configuration

- [x] **1.1** Update docker-compose.yml with build configuration
  - Replace `image:` directive with `build:` section
  - Set `context: .` and `dockerfile: build/Dockerfile`
  - Add build args for `COMMIT` and `VERSION` with defaults
  - **Requirement:** Requirement 1 (Local Source Build)
  - **Files:** `docker-compose.yml` (nakama service)

- [x] **1.2** Verify migration execution configuration
  - Test if migrations run successfully with current entrypoint
  - If needed, add `--migration.path /nakama/data/migrate/sql` flag
  - **Requirement:** Requirement 2 (Automatic Migrations)
  - **Files:** `docker-compose.yml` (nakama entrypoint)

### Phase 2: Testing and Validation

- [x] **2.1** Test local build from scratch
  - Run `docker compose down --volumes`
  - Run `docker compose up --build`
  - Verify image builds successfully
  - Verify build time is <5 minutes (cold build)
  - **Requirement:** Requirement 1 (Performance NFR)
  - **Verification:** `docker images | Select-String nakama`

- [x] **2.2** Test migration execution
  - Start stack with clean database
  - Check logs for migration success messages
  - Verify database schema is correctly initialized
  - **Requirement:** Requirement 2 (Migration Execution)
  - **Verification:** `docker compose logs nakama | Select-String migrate`
  - **Result:** All 30 migrations applied successfully, 34 tables created (15 Nakama core + 14 MMORPG + migration tracking)

- [x] **2.3** Test console accessibility
  - Navigate to `http://localhost:7351` in browser
  - Login with `admin` / `password`
  - Verify console UI loads and shows server status
  - **Requirement:** Requirement 3 (Console Access)
  - **Verification:** Manual browser test
  - **Result:** Console accessible at http://localhost:7351, HTTP 200, HTML UI served correctly, default credentials active (admin/password)

- [x] **2.4** Test runtime module hot reload
  - Modify `data/modules/character/character.ts` (add console.log)
  - Compile TypeScript to JavaScript (if needed)
  - Restart Nakama container: `docker compose restart nakama`
  - Call character RPC and verify log appears
  - **Requirement:** Requirement 4 (Volume Mounting)
  - **Verification:** `docker compose logs nakama | Select-String "console.log message"`
  - **Result:** ✅ Hot reload confirmed working.
  - **Automation Added:** Created automated build system with:
    - `npm run build` - Compile TypeScript modules
    - `npm run watch` - Auto-compile on file changes
    - `.\dev.ps1 restart` - Build + restart workflow (Windows)
    - `make restart` - Build + restart workflow (Linux/Mac)
    - See `DOCKER_DEVELOPMENT.md` and `data/modules/README.md` for full documentation

- [ ] **2.5** Test database persistence
  - Create test character via console or Godot client
  - Run `docker compose down`
  - Run `docker compose up`
  - Verify character still exists
  - **Requirement:** Requirement 5 (Database Persistence)
  - **Verification:** Query database or check console

- [ ] **2.6** Test health check ordering
  - Run `docker compose up` with logs: `docker compose up -d && docker compose logs -f`
  - Verify CockroachDB starts and health check passes first
  - Verify Nakama waits for DB health before starting
  - Verify no database connection errors in logs
  - **Requirement:** Requirement 6 (Service Dependencies)
  - **Verification:** Log timestamps show correct order

- [ ] **2.7** Test Prometheus metrics collection
  - Navigate to `http://localhost:9090` in browser
  - Execute PromQL query: `nakama_sessions_total`
  - Verify metrics appear and update every 15 seconds
  - **Requirement:** Requirement 7 (Metrics)
  - **Verification:** Prometheus UI shows Nakama target as UP

### Phase 3: Documentation and Cleanup

- [ ] **3.1** Add developer workflow documentation
  - Document `docker compose up --build` workflow
  - Document environment variables for version tagging
  - Add troubleshooting section for common issues
  - **Requirement:** Usability NFR
  - **Files:** README.md or new DOCKER_DEVELOPMENT.md

- [ ] **3.2** Add security warnings
  - Document that configuration is for local development only
  - Warn about insecure CockroachDB and default credentials
  - Provide guidance on production deployment differences
  - **Requirement:** Security NFR
  - **Files:** docker-compose.yml comments or README

- [ ] **3.3** Performance verification
  - Measure and document cold build time
  - Measure and document warm build time (cached)
  - Measure and document full stack startup time
  - Verify all times meet NFR targets (<5min cold, <1min warm, <60s startup)
  - **Requirement:** Performance NFR
  - **Verification:** Time measurements with `Measure-Command`

---

## Completion Checklist

**Functional Requirements:**
- [ ] Nakama builds from local source automatically (Req 1)
- [ ] Migrations execute on startup (Req 2)
- [ ] Console accessible at localhost:7351 (Req 3)
- [ ] Runtime modules hot-reload capable (Req 4)
- [ ] Database persists across restarts (Req 5)
- [ ] Health checks enforce startup order (Req 6)
- [ ] Prometheus scrapes Nakama metrics (Req 7)

**Non-Functional Requirements:**
- [ ] Cold build completes in <5 minutes
- [ ] Warm build completes in <1 minute
- [ ] Full stack startup in <60 seconds
- [ ] Security warnings documented
- [ ] Developer workflows documented

**Testing:**
- [ ] All 7 acceptance tests pass
- [ ] No regression in existing functionality
- [ ] Team members can run stack on first try

---

## Task Dependencies

```
1.1 (Update docker-compose.yml)
  ↓
1.2 (Verify migration config)
  ↓
2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6 → 2.7
(Sequential testing of all requirements)
  ↓
3.1 → 3.2 → 3.3
(Documentation and performance verification)
```

---

## Implementation Notes

### Task 1.1 - Exact Changes

**File:** `docker-compose.yml`

**Line 20-21 (BEFORE):**
```yaml
  nakama:
    image: registry.heroiclabs.com/heroiclabs/nakama:3.30.0
```

**Line 20-25 (AFTER):**
```yaml
  nakama:
    build:
      context: .
      dockerfile: build/Dockerfile
      args:
        COMMIT: ${COMMIT:-dev}
        VERSION: ${VERSION:-local-dev}
```

**Preserve:** All other lines in the nakama service definition (entrypoint, volumes, ports, depends_on, healthcheck)

### Task 1.2 - Migration Path Investigation

**Test command:**
```powershell
docker compose up --build
docker compose logs nakama | Select-String migrate
```

**Expected success output:**
```
nakama_1 | migrate up --database.address root@cockroachdb:26257
nakama_1 | Migration successful
```

**If migrations fail:**

Update entrypoint to include explicit migration path:

```yaml
- >
    /nakama/nakama migrate up --database.address root@cockroachdb:26257 --migration.path /nakama/data/migrate/sql &&
    exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257 --logger.level DEBUG --session.token_expiry_sec 7200 --metrics.prometheus_port 9100
```

### Task 2.4 - TypeScript Compilation Note

Runtime modules are TypeScript but Nakama loads JavaScript. Before hot reload testing:

```powershell
# Compile TypeScript modules (one-time or when changed)
cd data/modules/character
tsc character.ts
# Or use project-wide build script if available
```

**Future Enhancement (out of scope):** Add TypeScript watch mode or automatic compilation to Docker Compose.

---

## Risk Mitigation

**Risk 1: Build failures due to missing Go dependencies**
- **Mitigation:** The existing Dockerfile uses `go build -mod=vendor`, which includes vendored dependencies
- **Fallback:** If build fails, run `go mod vendor` locally before building

**Risk 2: Migration files not accessible in container**
- **Mitigation:** Volume mount `./:/nakama/data` provides access to `migrate/sql/`
- **Fallback:** Add explicit `--migration.path` flag to entrypoint

**Risk 3: Developers forget to rebuild after code changes**
- **Mitigation:** Document `docker compose up --build` as standard workflow
- **Enhancement:** Consider adding shell alias or VS Code task

**Risk 4: Port conflicts on developer machines**
- **Mitigation:** Document how to check for port conflicts: `netstat -an | Select-String "7349|7350|7351"`
- **Fallback:** Allow port customization via environment variables (future enhancement)

---

## Success Metrics

**Quantitative:**
- Build time (cold): <5 minutes ✅
- Build time (warm): <1 minute ✅
- Startup time: <60 seconds ✅
- Team adoption: 100% of developers use Docker Compose for local dev
- Support requests: <2 per week after initial rollout

**Qualitative:**
- Developer feedback: "Easier than manual docker build commands"
- Onboarding time: New developers can start contributing same day
- Incident reduction: Zero "forgot to rebuild" bugs

