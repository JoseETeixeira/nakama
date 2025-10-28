# Implementation Tasks: MMORPG-grade Nakama (Godot-first)

**Feature:** MMORPG-grade Nakama with Godot 4 Integration  
**Requirements:** `.kiro/specs/mmorpg-nakama-godot/requirements.md`  
**Design:** `.kiro/specs/mmorpg-nakama-godot/design.md`  
**Status:** In Progress  
**Last Updated:** October 28, 2025

---

## Task Organization

Tasks are organized by implementation phase and trace back to specific requirements and design sections. Each task is marked with:
- `[ ]` = Not started
- `[~]` = In progress
- `[x]` = Completed

**Traceability Format:** `_Req: X, Design: Section Y_`

---

## Phase 1: Foundation (Weeks 1-2)

### 1.1 Database Schema Setup
_Req: 1-33, Design: Data Models_

- [ ] **1.1.1** Create database migration framework setup
  - Set up migration versioning in `migrate/sql/`
  - Create migration runner script
  - Add migration tracking table

- [ ] **1.1.2** Create accounts table migration
  - Table: `accounts` with columns: account_id, email, device_id, platform_token, created_at, last_login_at, permissions, banned
  - Indexes: email, device_id
  - _Req: 1_

- [ ] **1.1.3** Create characters table migration
  - Table: `characters` with columns: character_id, account_id, name, archetype_id, level, last_zone_id, last_position, stats, created_at, last_login_at, version
  - Unique constraint on name
  - Foreign key to accounts
  - _Req: 2, 3_

- [ ] **1.1.4** Create inventory table migration
  - Table: `inventory` with item_uid, character_id, item_id, slot_id, quantity, durability, metadata, version
  - Unique index on (character_id, slot_id)
  - _Req: 14_

- [ ] **1.1.5** Create world_state table migration
  - Table: `world_state` for zone checkpoints
  - Columns: zone_id, shard_id, state_json, version, updated_at, checkpoint_at
  - _Req: 7_

- [ ] **1.1.6** Create event_log table migration
  - Table: `event_log` for crash recovery
  - Columns: event_id, zone_id, event_type, event_data, timestamp
  - Index on (zone_id, timestamp)
  - _Req: 7_

- [ ] **1.1.7** Create guilds and guild_members tables migration
  - Tables: `guilds`, `guild_members`
  - Support for ranks, MOTD, storage
  - _Req: 11_

- [ ] **1.1.8** Create trade_sessions table migration
  - Table: `trade_sessions` for 2PC trading
  - Columns: trade_id, participant_1, participant_2, items_1, items_2, locked, expires_at
  - _Req: 15_

- [ ] **1.1.9** Create zone_boundaries table migration
  - Table: `zone_boundaries` with neighbors array
  - Support for handoff triggers
  - _Req: 18_

- [ ] **1.1.10** Create handoff_tokens table migration
  - Table: `handoff_tokens` for cross-region transfers
  - TTL-based expiration
  - _Req: 18, 19_

- [ ] **1.1.11** Create event_schedules table migration
  - Table: `event_schedules` for cron-based events
  - Support for script_id, params, enabled flag
  - _Req: 22_

- [ ] **1.1.12** Create audit_logs table migration
  - Table: `audit_logs` for GM actions and transactions
  - Indexed by actor_id and action
  - _Req: 20, 23, 25_

- [ ] **1.1.13** Create catalog and entitlements tables migration
  - Tables: `catalog`, `entitlements`
  - Support for SKU, pricing, regional filtering
  - _Req: 24, 25, 26_

- [ ] **1.1.14** Create wallets and wallet_transactions tables migration
  - Tables: `wallets`, `wallet_transactions`
  - Optimistic locking with version column
  - _Req: 27_

### 1.2 Authentication Service
_Req: 1, Design: Authentication Service_

- [ ] **1.2.1** Implement JWT token generation
  - Create `server/auth_jwt.go` with token issuance
  - Include account_id, permissions, expiration
  - Use TLS 1.2+ for transport

- [ ] **1.2.2** Implement device authentication
  - Support device_id-based auth
  - Create account on first login (auto-registration)

- [ ] **1.2.3** Implement email authentication
  - Email + password validation
  - Password hashing (bcrypt)

- [ ] **1.2.4** Implement platform token authentication
  - Support Apple, Google, Steam tokens
  - Validate with platform APIs

- [ ] **1.2.5** Implement session token validation
  - Middleware for JWT verification
  - Extract account context from token

- [ ] **1.2.6** Implement rate limiting for authentication
  - Per-IP rate limits (e.g., 10 auth attempts per minute)
  - Redis-backed rate limiter

- [ ] **1.2.7** Add optional 2FA support
  - TOTP-based two-factor authentication
  - Enable/disable per account

### 1.3 Character Service
_Req: 2, 3, Design: Character Service_

- [ ] **1.3.1** Create TypeScript module structure
  - Set up `data/modules/character/` directory
  - Create module registration in runtime

- [ ] **1.3.2** Implement list_characters RPC
  - Query characters by account_id
  - Return array of Character objects
  - _Req: 2_

- [ ] **1.3.3** Implement create_character RPC
  - Validate name (length, profanity filter)
  - Check character slot limit per account
  - Assign default spawn zone and starter items
  - _Req: 3_

- [ ] **1.3.4** Implement select_character RPC
  - Load full character state (stats, inventory, cooldowns)
  - Return last_zone_id and spawn position
  - _Req: 2_

- [ ] **1.3.5** Implement delete_character RPC
  - Cascade delete inventory, guild memberships
  - Audit log the deletion
  - _Req: 29 (GDPR)_

- [ ] **1.3.6** Add character name validation
  - Profanity filter integration
  - Length constraints (3-20 chars)
  - Alphanumeric + spaces only

### 1.4 Basic Godot Client
_Req: 2, 3, Design: Client Integration_

- [ ] **1.4.1** Set up Godot 4 project structure
  - Create autoload singletons (NakamaManager, WorldState)
  - Set up scene hierarchy (auth, character_select, world)

- [ ] **1.4.2** Install nakama-godot plugin
  - Add plugin to project
  - Configure server connection (host, port, API key)

- [ ] **1.4.3** Implement authentication screen
  - UI for device login
  - Call `client.authenticate_device_async()`
  - Store session token

- [ ] **1.4.4** Implement character selection screen
  - Call `list_characters` RPC
  - Display character list with name, level, last login
  - Create character UI with name input and archetype dropdown

- [ ] **1.4.5** Implement character creation flow
  - Call `create_character` RPC
  - Validate name client-side (pre-validation)
  - Handle server errors (name taken, slot limit)

- [ ] **1.4.6** Implement character selection flow
  - Call `select_character` RPC
  - Transition to world scene on success

---

## Phase 2: World Entry (Weeks 3-4)

### 2.1 World Service - Zone Entry
_Req: 4, 7, Design: World Service_

- [ ] **2.1.1** Create zone state data structure
  - Define `ZoneState` interface in TypeScript
  - Include entities, terrain chunks, timers, effects

- [ ] **2.1.2** Implement world_enter RPC
  - Validate character_id and load character state
  - Determine shard_id and zone_id from last_zone_id or default spawn
  - Return shard_id, zone_id, spawn coordinates
  - _Req: 2, 4_

- [ ] **2.1.3** Implement zone snapshot generation
  - Create `zone_snapshot` RPC
  - Serialize zone state to JSON
  - Compress with Deflate (zlib)
  - Enforce 512 KB size limit (LOD filtering if exceeded)
  - _Req: 4_

- [ ] **2.1.4** Add terrain chunk referencing
  - Store terrain chunk IDs (not full data) in snapshot
  - Client fetches chunks separately (CDN/cache)

- [ ] **2.1.5** Implement AOI seed calculation
  - Determine player's initial AOI based on spawn position
  - Include visible entities in snapshot

### 2.2 Zone Tick Loop & Persistence
_Req: 7, Design: Persistence Strategy_

- [ ] **2.2.1** Create ZoneProcess class
  - Implement tick loop at 10-20 Hz
  - Manage in-memory zone state

- [ ] **2.2.2** Implement checkpoint system
  - Serialize zone state to JSON every 10 seconds
  - Write to `world_state` table with version increment
  - _Req: 7_

- [ ] **2.2.3** Implement event logging
  - Log all state-changing events to `event_log` table
  - Event types: entity_move, entity_spawn, entity_despawn, loot_drop, etc.

- [ ] **2.2.4** Implement zone crash recovery
  - On startup, load last checkpoint from `world_state`
  - Replay events from `event_log` since checkpoint timestamp
  - Verify RPO ≤5s, RTO ≤5min
  - _Req: 7_

- [ ] **2.2.5** Implement safe shutdown
  - Persist final checkpoint on SIGTERM
  - Close database connections gracefully

### 2.3 Delta Streaming
_Req: 4, 8, Design: World Service_

- [ ] **2.3.1** Implement zone delta stream
  - Create server-to-client stream for `zone_deltas`
  - Send entity updates, adds, removes at 10-20 Hz
  - _Req: 4_

- [ ] **2.3.2** Implement AOI filtering
  - Use spatial grid (50m cell size) for entity culling
  - Only send deltas for entities in player's AOI radius
  - _Req: 8_

- [ ] **2.3.3** Implement entity add/remove messages
  - When entity enters AOI, send full entity snapshot
  - When entity exits AOI, send removal message

- [ ] **2.3.4** Optimize delta bandwidth
  - Send only changed fields (not full entity state)
  - Apply compression to delta stream

### 2.4 Godot Snapshot Application
_Req: 4, Design: Client Integration_

- [ ] **2.4.1** Implement SnapshotApplier utility
  - Decompress blob using `Marshalls.base64_to_raw()` and `decompress_dynamic()`
  - Parse JSON snapshot

- [ ] **2.4.2** Implement atomic snapshot application
  - Pause scene tree (`get_tree().paused = true`)
  - Clear existing entities
  - Instantiate entities from snapshot
  - Resume scene tree in single frame
  - Verify apply time ≤50ms

- [ ] **2.4.3** Implement entity instantiation
  - Load entity scenes based on type
  - Set position, rotation, vitals from snapshot

- [ ] **2.4.4** Implement delta stream subscription
  - Subscribe to `zone_deltas` stream on socket
  - Connect signal `received_stream_state` to delta handler

- [ ] **2.4.5** Implement delta application
  - Apply entity updates (position, vitals, effects)
  - Add new entities to scene
  - Remove entities from scene

---

## Phase 3: Movement & Combat (Weeks 5-6)

### 3.1 Movement Validation
_Req: 5, Design: Movement & Combat Service_

- [ ] **3.1.1** Implement move_intent RPC
  - Accept direction vector, timestamp, nonce
  - Validate physics constraints (speed, collision)
  - Calculate authoritative position

- [ ] **3.1.2** Implement server-side physics
  - Collision detection against terrain and entities
  - Speed limiting (prevent speed hacks)

- [ ] **3.1.3** Implement position broadcasting
  - Broadcast authoritative position at 10-20 Hz to AOI subscribers
  - Include nonce for client reconciliation

- [ ] **3.1.4** Implement position correction
  - Detect client prediction drift
  - Send correction message with authoritative position and nonce

### 3.2 Client-Side Prediction
_Req: 5, Design: Client Integration_

- [ ] **3.2.1** Implement ClientPrediction module (Godot)
  - Queue pending moves with nonces
  - Apply moves locally for responsive feel

- [ ] **3.2.2** Implement move acknowledgment handling
  - Remove acked moves from pending queue based on nonce
  - Track last_ack_nonce

- [ ] **3.2.3** Implement reconciliation
  - When correction received, set position to server truth
  - Replay un-acked moves from pending queue

- [ ] **3.2.4** Add correction warning
  - Emit signal when correction delta > 2 frames
  - Display lag indicator to player

### 3.3 Combat & Abilities
_Req: 6, Design: Movement & Combat Service_

- [ ] **3.3.1** Create ability configuration data
  - JSON files for ability templates (id, name, cooldown, cost, range, damage, effects)
  - Load into runtime on startup

- [ ] **3.3.2** Implement use_ability RPC
  - Validate ability_id, target_id, cooldown, resource cost (MP/stamina)
  - Check range and line-of-sight

- [ ] **3.3.3** Implement damage calculation
  - Server-side formula: base damage + crit chance + resistances + buffs/debuffs
  - Apply damage to target vitals (HP)

- [ ] **3.3.4** Implement cooldown management
  - Store cooldown state per character
  - Persist cooldowns to database on checkpoint

- [ ] **3.3.5** Implement death logic
  - When HP ≤ 0, trigger death event
  - Drop loot based on drop table
  - Respawn logic (grace period, respawn anchor)

- [ ] **3.3.6** Broadcast ability results
  - Send ability result (damage, healing, crit, effects) to AOI subscribers
  - Animate on client (particle effects, damage numbers)

---

## Phase 4: Social & Economy (Weeks 7-8)

### 4.1 Guild System
_Req: 11, Design: Social Service_

- [ ] **4.1.1** Implement guild_create RPC
  - Validate guild name (unique, length, profanity)
  - Create guild record with creator as master
  - Initialize guild storage (shared inventory)

- [ ] **4.1.2** Implement guild_invite and guild_join RPCs
  - Invite by character_id or name
  - Join with acceptance flow

- [ ] **4.1.3** Implement guild_set_rank RPC
  - Update member rank (0=member, 1=officer, 2=master)
  - Enforce permissions (only officers+ can promote)

- [ ] **4.1.4** Implement guild_kick RPC
  - Remove member from guild_members table
  - Log action to audit_logs

- [ ] **4.1.5** Implement guild_set_motd RPC
  - Update MOTD (max 500 chars)
  - Broadcast to online guild members

- [ ] **4.1.6** Implement guild storage access
  - Shared inventory with permission checks
  - Audit log for deposits/withdrawals

### 4.2 Chat System
_Req: 12, 13, Design: Social Service_

- [ ] **4.2.1** Implement chat_send RPC
  - Validate message (length, profanity filter)
  - Broadcast to channel subscribers (world, zone, party, guild, DM)

- [ ] **4.2.2** Implement channel subscription
  - Auto-subscribe to zone channel on zone entry
  - Subscribe to party/guild channels on join

- [ ] **4.2.3** Implement direct messages
  - Send DM to target if online
  - Queue for offline delivery (7-day expiration)

- [ ] **4.2.4** Implement moderation commands
  - `moderate_player` RPC for mute, kick, ban
  - Duration-based mutes (e.g., 1 hour, 1 day, permanent)
  - Log all moderation actions to audit_logs

- [ ] **4.2.5** Add profanity filter
  - Integrate library or custom filter
  - Reject messages violating content policy

### 4.3 Inventory System
_Req: 14, Design: Economy Service_

- [ ] **4.3.1** Implement inventory_move RPC
  - Validate source slot has item
  - Check destination slot availability
  - Use optimistic locking (version column)
  - Execute atomically within transaction

- [ ] **4.3.2** Implement item UID enforcement
  - Generate UUIDs for all items
  - Prevent duplication across all players

- [ ] **4.3.3** Implement item stacking
  - Stack identical items (same item_id, metadata)
  - Split stacks on move

- [ ] **4.3.4** Add inventory validation
  - Reject invalid slot IDs
  - Prevent moving equipped items without unequip

### 4.4 Trading System
_Req: 15, Design: Economy Service_

- [ ] **4.4.1** Implement trade_open RPC
  - Create trade_session record
  - Lock both players' inventories (prevent external modifications)
  - Set 5-minute expiration

- [ ] **4.4.2** Implement trade_add_item RPC
  - Add item to participant's offer
  - Update trade_session.items_1 or items_2

- [ ] **4.4.3** Implement trade_lock RPC
  - Mark trade as locked (both parties confirmed)
  - Cannot add/remove items after lock

- [ ] **4.4.4** Implement trade_commit RPC (2PC)
  - Phase 1: Verify both inventories still have offered items
  - Phase 2: Deduct from source inventories, add to target inventories
  - Rollback on any failure
  - Log transaction to audit_logs

- [ ] **4.4.5** Implement trade cancellation
  - Cancel if either player disconnects
  - Cancel on timeout (5 min)
  - Unlock inventories

### 4.5 Vendor System
_Req: 16, Design: Economy Service_

- [ ] **4.5.1** Create vendor configuration data
  - JSON files for vendor catalogs (vendor_id, items, prices, stock)
  - Load into runtime

- [ ] **4.5.2** Implement vendor_buy RPC
  - Verify player has sufficient currency (wallet)
  - Deduct cost, add item to inventory
  - Update vendor stock (if limited)

- [ ] **4.5.3** Implement vendor_sell RPC
  - Verify item is sellable (check metadata)
  - Remove item from inventory
  - Credit player wallet

- [ ] **4.5.4** Implement vendor stock refresh
  - Cron job or event-based refresh (e.g., daily reset)
  - Restore stock limits per vendor config

### 4.6 Loot System
_Req: 17, Design: Economy Service_

- [ ] **4.6.1** Create drop table configuration
  - JSON files for drop tables (drop_table_id, items, drop_chance, quantity_range)
  - Support nested tables (rare drops)

- [ ] **4.6.2** Implement loot generation
  - Server-side RNG (seeded, non-client-predictable)
  - Roll drops based on drop_chance percentages
  - Generate item instances with UIDs

- [ ] **4.6.3** Implement loot drops on NPC death
  - Associate NPCs with drop_table_id
  - Generate loot on death event
  - Spawn loot in world or directly to killer's inventory

- [ ] **4.6.4** Add loot analytics
  - Log all loot drops to event_log
  - Track drop rates for balancing

---

## Phase 5: Instances (Week 9)

### 5.1 Instance System
_Req: 9, 10, Design: Instance Service_

- [ ] **5.1.1** Create instance template configuration
  - JSON files for instance templates (template_id, requirements, max_party_size, loot_table, rewards)

- [ ] **5.1.2** Implement instance_enter RPC
  - Validate party requirements (size, level, items)
  - Create Nakama match instance
  - Transition party members to instance
  - Return match_id and entry_anchor

- [ ] **5.1.3** Implement instance state management
  - Separate zone state for each match instance
  - Isolated tick loop per instance

- [ ] **5.1.4** Implement instance_exit RPC
  - Return party to world at exit_anchor
  - Persist completion state and rewards

- [ ] **5.1.5** Implement instance completion flow
  - Detect victory conditions (boss defeated, objectives complete)
  - Award rewards atomically to all party members
  - Log completion to audit_logs

- [ ] **5.1.6** Implement rejoin grace period
  - Hold player slot for 5 minutes on disconnect
  - Restore player state on rejoin
  - Forfeit rewards if grace period expires

---

## Phase 6: Handoffs (Week 10)

### 6.1 Cross-Region Handoff
_Req: 18, 19, Design: Handoff Service_

- [ ] **6.1.1** Implement handoff_request RPC
  - Validate target_zone_id exists
  - Generate handoff token (UUID, 30s TTL)
  - Store in `handoff_tokens` table
  - Return token, endpoint, timeout_ms

- [ ] **6.1.2** Implement handoff_finalize RPC
  - Validate token (not expired, matches player_id)
  - Transfer player state to new zone
  - Delete token from table
  - Close old connection

- [ ] **6.1.3** Implement inventory/combat locking during handoff
  - Set player state to `in_handoff`
  - Reject inventory and combat RPCs during handoff

- [ ] **6.1.4** Implement handoff rollback
  - On finalize failure, rollback player to safe_anchor in source zone
  - Preserve inventory, XP, stats
  - Log failure to audit_logs

- [ ] **6.1.5** Add handoff retry UX
  - Client displays retry prompt on failure
  - Allow manual retry with same or new token

### 6.2 Godot Handoff Manager
_Req: 18, 38, Design: Client Integration_

- [ ] **6.2.1** Implement HandoffManager singleton (Godot)
  - Orchestrate handoff request → pre-connect → finalize flow

- [ ] **6.2.2** Implement pre-connection to target zone
  - Create new NakamaClient and NakamaSocket
  - Connect in background while handoff token is valid

- [ ] **6.2.3** Implement socket swap
  - On finalize success, atomically swap active socket
  - Close old socket

- [ ] **6.2.4** Add visual transition masking
  - Show portal/fog/loading screen during handoff
  - Hide when handoff complete (≤1s)

- [ ] **6.2.5** Implement failure recovery
  - On finalize failure, maintain old connection
  - Emit `handoff_failed(error)` signal
  - Display error message to player

---

## Phase 7: Live-Ops & Commerce (Weeks 11-12)

### 7.1 GM Console
_Req: 20, 21, Design: Live-Ops Service_

- [ ] **7.1.1** Implement GM permission system
  - RBAC (roles: admin, moderator, analyst)
  - Check permissions on all GM RPCs

- [ ] **7.1.2** Implement gm_exec RPC
  - Execute GM commands: spawn, despawn, modify entities
  - Validate GM permissions
  - Log all commands to audit_logs

- [ ] **7.1.3** Implement entity spawning
  - Create entity in target zone from GM command
  - Broadcast to clients in AOI

- [ ] **7.1.4** Implement entity despawning
  - Remove entity from zone state
  - Broadcast removal to clients

- [ ] **7.1.5** Implement world parameter tweaking
  - Update drop rates, buff values, XP multipliers in real-time
  - Notify affected zones of config changes
  - Support temporary changes with auto-revert

- [ ] **7.1.6** Implement broadcast messaging
  - Send message to all online players (world, zone, guild scope)
  - Display as system message on client

### 7.2 Event Scheduler
_Req: 22, Design: Live-Ops Service_

- [ ] **7.2.1** Implement event_schedule RPC
  - Create event schedule with cron expression
  - Validate cron syntax
  - Store in `event_schedules` table

- [ ] **7.2.2** Implement cron executor
  - Background process to poll event_schedules
  - Trigger server functions at scheduled times

- [ ] **7.2.3** Implement event dry-run preview
  - Simulate event execution without side effects
  - Return expected outcome to GM

- [ ] **7.2.4** Add event enable/disable toggle
  - Allow GMs to pause/resume events without deletion

- [ ] **7.2.5** Implement event deletion
  - Cancel future executions
  - Archive schedule for audit

### 7.3 Script Hot-Loading
_Req: 23, Design: Live-Ops Service_

- [ ] **7.3.1** Implement script upload RPC
  - Accept Lua/TypeScript script packs
  - Validate syntax and dependencies

- [ ] **7.3.2** Implement script sandboxing
  - Restrict direct DB access (use Nakama APIs only)
  - Limit execution time and memory

- [ ] **7.3.3** Implement hot-loading
  - Load script into runtime without restart
  - Make available for RPC/event execution

- [ ] **7.3.4** Add script versioning
  - Track script versions for rollback
  - Log script_id, version, uploader to audit_logs

- [ ] **7.3.5** Implement script deprecation
  - Unload script from runtime
  - Archive for historical reference

### 7.4 Store & Payments
_Req: 24, 25, 26, 27, Design: Commerce Service_

- [ ] **7.4.1** Implement store_catalog RPC
  - Return filtered catalog based on region and date/time
  - Exclude out-of-stock or deprecated items

- [ ] **7.4.2** Implement purchase_verify RPC
  - Validate platform receipt (Apple, Google, Steam APIs)
  - Prevent duplicate receipts (check receipt_id)

- [ ] **7.4.3** Implement entitlement granting
  - Create entitlement records in `entitlements` table
  - Apply cosmetics to character loadout server-side

- [ ] **7.4.4** Implement entitlement revocation
  - Revoke on refund or ban
  - Unequip cosmetics from characters
  - Log to audit_logs

- [ ] **7.4.5** Implement wallet credit/debit
  - Atomic updates to `wallets` table with optimistic locking
  - Log all transactions to `wallet_transactions`

- [ ] **7.4.6** Add GDPR data export
  - Generate JSON export of account data, characters, inventory, transactions
  - Secure download link with 7-day expiration
  - _Req: 28_

- [ ] **7.4.7** Add GDPR account deletion
  - 30-day grace period for cancellation
  - Cascade delete or anonymize all user data
  - Log deletion event
  - _Req: 29_

- [ ] **7.4.8** Implement purchase refunds
  - Verify refund within window (14 days for Apple, 48h for Google)
  - Revoke entitlements, credit platform refund
  - Flag fraudulent refunds for review
  - _Req: 30_

---

## Phase 8: Ops & Scale (Weeks 13-14)

### 8.1 Observability
_Req: 31, Design: Deployment Architecture_

- [ ] **8.1.1** Implement Prometheus metrics exporter
  - Expose `/metrics` endpoint
  - Metrics: CCU per zone, tick time, DB latency, snapshot size, bandwidth per client, handoff success rate

- [ ] **8.1.2** Create Grafana dashboards
  - Dashboard 1: Zone performance (tick time p50/p95/p99, entity count)
  - Dashboard 2: Database (write latency, query count, connection pool)
  - Dashboard 3: Player metrics (CCU, handoff success, snapshot apply time)

- [ ] **8.1.3** Set up alerting
  - Alert on tick time >10ms p95
  - Alert on DB write latency >30ms p95
  - Alert on handoff failure rate >5%
  - Integrate with PagerDuty/Slack

- [ ] **8.1.4** Add structured logging
  - JSON-formatted logs with correlation IDs
  - Log levels: DEBUG, INFO, WARN, ERROR, CRITICAL

### 8.2 Blue/Green Deployment
_Req: 32, Design: Deployment Architecture_

- [ ] **8.2.1** Set up Kubernetes infrastructure
  - Create `nakama-api` deployment (stateless, HPA)
  - Create `nakama-zones` statefulset (per-zone pods)
  - Create `postgres` statefulset (primary + replicas)

- [ ] **8.2.2** Implement canary deployment
  - Deploy new version to separate pod set (10% traffic)
  - Monitor canary metrics (error rate, latency, CCU)

- [ ] **8.2.3** Implement traffic shifting
  - Gradual shift from blue to green (10% → 50% → 100%)
  - Rollback to blue on canary failure

- [ ] **8.2.4** Add health checks
  - Liveness probe: HTTP `/health` endpoint
  - Readiness probe: DB connection + zone state check

- [ ] **8.2.5** Implement automated rollback
  - Trigger on canary metrics threshold breach
  - Revert traffic to blue within 2 minutes

### 8.3 Load Testing
_Req: 31, Design: Testing Strategy_

- [ ] **8.3.1** Create k6 load test scripts
  - Simulate 50k CCU per shard
  - Test scenarios: login, move, combat, handoff

- [ ] **8.3.2** Run baseline performance tests
  - Measure p95 latency for movement/combat (target: ≤150ms)
  - Measure zone tick time (target: ≤10ms at 1k entities)
  - Measure DB write latency (target: ≤30ms)

- [ ] **8.3.3** Create Godot bot clients
  - Scripted bots for realistic player behavior
  - Movement, combat, chat, trading

- [ ] **8.3.4** Run horizontal scalability tests
  - Test 1M+ CCU across multiple shards
  - Verify linear scaling

### 8.4 Chaos Testing
_Req: 33, Design: Testing Strategy_

- [ ] **8.4.1** Set up Chaos Mesh on Kubernetes
  - Install Chaos Mesh operator
  - Create chaos experiments (pod kill, network delay, disk failure)

- [ ] **8.4.2** Create zone kill experiment
  - Randomly terminate zone pods
  - Verify recovery within RTO (≤5 min)

- [ ] **8.4.3** Validate RPO guarantees
  - Measure data loss after crash (target: ≤5s)
  - Verify checkpoint + event log recovery

- [ ] **8.4.4** Test player reconnection
  - Ensure players auto-reconnect after zone recovery
  - No manual intervention required

---

## Phase 9: Godot Client Plugin (Weeks 15-16)

### 9.1 Plugin Architecture
_Req: 34, Design: Client Integration_

- [ ] **9.1.1** Fork nakama-godot repository
  - Create `mmorpg-extensions` branch
  - Set up plugin directory structure

- [ ] **9.1.2** Create SnapshotApplier class
  - Decompress Deflate blobs
  - Parse JSON snapshots
  - Emit signals for entity_added
  - _Req: 35_

- [ ] **9.1.3** Create DeltaStreamProcessor class
  - Parse zone deltas
  - Emit entity_updated, entity_added, entity_removed signals
  - Queue and throttle updates at configurable rate
  - _Req: 36_

- [ ] **9.1.4** Create ClientPrediction module
  - Move queuing with nonces
  - Reconciliation with replay
  - Emit correction_warning signal
  - _Req: 37_

- [ ] **9.1.5** Create HandoffManager class
  - Orchestrate handoff_request → pre-connect → finalize
  - Lock player input during handoff
  - Emit handoff_completed and handoff_failed signals
  - _Req: 38_

### 9.2 Helper Utilities
_Req: 34_

- [ ] **9.2.1** Implement AOI filtering utility
  - Calculate visible entities based on distance
  - Client-side culling for rendering optimization

- [ ] **9.2.2** Implement entity state cache
  - Cache entity states to reduce memory churn
  - Update cache on deltas

- [ ] **9.2.3** Implement bandwidth optimization
  - Delta compression (only changed fields)
  - Deduplication of repeated values

- [ ] **9.2.4** Add interpolation helpers
  - Linear interpolation for position
  - Smoothing for rotation

### 9.3 Documentation & Examples
_Req: 39_

- [ ] **9.3.1** Write API reference documentation
  - Document all new classes, methods, signals
  - Include parameter descriptions and return values

- [ ] **9.3.2** Create GDScript examples
  - Example 1: Authentication + character select
  - Example 2: Zone entry + snapshot application
  - Example 3: Movement with prediction
  - Example 4: Ability usage
  - Example 5: Cross-region handoff

- [ ] **9.3.3** Create sample MMORPG project
  - Minimal playable demo with 2 zones
  - Player character, NPC entities
  - Movement, combat, zone handoff

- [ ] **9.3.4** Write migration guide
  - How to upgrade from standard nakama-godot to MMORPG plugin
  - Breaking changes and compatibility notes

- [ ] **9.3.5** Add troubleshooting guide
  - Common issues: snapshot size limits, handoff failures, prediction drift
  - Solutions and debugging tips

- [ ] **9.3.6** Create changelog
  - Version history with new features and breaking changes

### 9.4 Plugin Release
_Req: 34, 39_

- [ ] **9.4.1** Run plugin tests
  - Unit tests for SnapshotApplier, DeltaStreamProcessor, ClientPrediction, HandoffManager
  - Integration tests with live Nakama server

- [ ] **9.4.2** Create pull request to nakama-godot
  - Submit PR with MMORPG extensions
  - Include documentation and examples

- [ ] **9.4.3** Publish sample project
  - MIT license
  - Upload to GitHub with README

- [ ] **9.4.4** Announce release
  - Blog post or forum announcement
  - Highlight MMORPG features

---

## Completion Criteria

**All tasks complete when:**
- [ ] All 39 requirements are implemented and tested
- [ ] Load tests pass at ≥50k CCU with p95 latency ≤150ms
- [ ] Chaos tests verify RPO ≤5s, RTO ≤5min
- [ ] Godot demo client works end-to-end: login → character select → zone entry → movement/combat → handoff → purchase/cosmetic → relog
- [ ] GM console functional with RBAC and audit logs
- [ ] Dashboards and alerts operational in production
- [ ] Godot plugin merged and released with documentation

---

**Next Step:** Begin Phase 1, Task 1.1.1 (Database migration framework setup)
