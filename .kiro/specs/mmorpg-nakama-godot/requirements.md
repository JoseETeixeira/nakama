# Requirements: MMORPG-grade Nakama (Godot-first, no matchmaking)

## Document Information

- **Feature Name:** MMORPG-grade Nakama with Godot 4 Integration
- **Version:** 1.0
- **Date:** October 27, 2025
- **Stakeholders:** Game Studios, Live-Ops Teams, Players, System Operators

## Introduction

This feature transforms Nakama into an MMORPG-grade game server capable of supporting large-scale, persistent multiplayer worlds with Godot 4 clients. The system enables server-authoritative gameplay, seamless cross-region travel, live operations tooling, and integrated commerce—all without traditional matchmaking queues.

Players authenticate, manage multiple characters, and enter persistent open-world zones where they interact with other players, NPCs, and environmental systems. The architecture supports instanced content (dungeons, arenas) accessed via in-world portals or party commands, extensive social features (guilds, chat, trading), and robust live-ops capabilities for event management and content updates.

The design prioritizes crash-safe persistence, horizontal scalability, low-latency responsiveness, and fair play through server-side validation of all gameplay-critical operations.

## Feature Summary

A complete MMORPG backend built on Nakama, featuring persistent open worlds, server-authoritative combat, seamless zone handoffs, live-ops tools, and integrated payments—optimized for Godot 4 clients at massive scale (≥50k CCU/shard, scalable to 1M+ CCU).

## Business Value

- **Player Retention**: Persistent character progression and social systems increase long-term engagement
- **Operational Efficiency**: Centralized live-ops tools reduce content update cycles and enable dynamic events
- **Revenue Opportunities**: Integrated payment/entitlement systems support cosmetics, expansions, and soft currency
- **Developer Productivity**: Godot-first SDK examples and comprehensive RPC APIs accelerate game development
- **Competitive Advantage**: Industry-grade scalability and reliability enable AAA-quality multiplayer experiences

## Scope

**In Scope:**
- Authentication and multi-character account management
- Server-authoritative open-world zones with persistence
- Real-time movement, combat, and ability systems
- Instanced content (dungeons/arenas) without matchmaking
- Social features: guilds, parties, chat, friends, moderation
- Economy: inventory, trading, vendors, drop tables
- Seamless cross-region/shard handoffs
- Live-ops: GM console, event scheduling, hot-loadable scripts
- Payments: store catalogs, purchase verification, entitlements, wallets
- Observability: metrics, dashboards, alerts, deployment automation

**Out of Scope:**
- Traditional matchmaking queues (replaced by direct instance creation)
- Client-authoritative gameplay (all critical logic server-validated)
- Voice chat (text-based communication only)
- Mobile-specific optimizations (PC/console focus)

---

## Requirements

### Requirement 1: Player Authentication

**User Story:** As a player, I want to authenticate with my account credentials, so that I can access my characters and game progress securely.

**Acceptance Criteria (EARS)**
- WHEN a player provides valid authentication credentials THEN Nakama SHALL issue a JWT session token with account_id and permissions
- IF authentication credentials are invalid THEN Nakama SHALL reject the login attempt and return an error message
- WHEN a session token expires THEN Nakama SHALL invalidate the session and require re-authentication
- WHILE a player is authenticated THEN Nakama SHALL enforce per-RPC rate limits based on account_id
- WHERE a player authenticates from a new device THEN Nakama SHALL optionally trigger two-factor authentication (if enabled)

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** JWT library, account storage schema
- **Assumptions:** Players use device ID, email, or platform-specific authentication; TLS secures transport

---

### Requirement 2: Character List and Selection

**User Story:** As a player, I want to view my list of characters and select one to enter the world, so that I can resume my progress from where I left off.

**Acceptance Criteria (EARS)**
- WHEN a player successfully authenticates THEN Nakama SHALL return a list of all characters associated with the account
- IF the account has no characters THEN Nakama SHALL return an empty list and allow character creation
- WHEN a player selects an existing character THEN Nakama SHALL load the character's last known zone_id, position, stats, cooldowns, and inventory
- IF the character's last zone is unavailable THEN Nakama SHALL spawn the character at a fallback safe zone
- WHEN a player enters the world with a selected character THEN Nakama SHALL return shard_id, zone_id, and spawn coordinates

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 1 (authentication), character database schema
- **Assumptions:** Each account supports multiple character slots (configurable limit)

---

### Requirement 3: Character Creation

**User Story:** As a player, I want to create a new character with a name and archetype, so that I can start my adventure in the game world.

**Acceptance Criteria (EARS)**
- WHEN a player provides a valid character name and archetype_id THEN Nakama SHALL create a new character record with starter inventory and stats
- IF the character name is already taken or violates naming rules THEN Nakama SHALL reject the creation and return an error
- IF the account has reached the maximum character limit THEN Nakama SHALL reject the creation attempt
- WHEN a new character is created THEN Nakama SHALL assign the character to the default spawn zone with starter equipment
- WHEN the player enters the world with a new character THEN Nakama SHALL initialize the character at the default spawn location

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 2 (character selection), archetype configuration tables
- **Assumptions:** Starter inventory and stats are defined per archetype; naming rules (length, profanity filter) are configurable

---

### Requirement 4: World Entry and Zone Snapshot

**User Story:** As a player, I want to receive an immediate, authoritative snapshot of the zone when I enter, so that my client is synchronized with terrain, entities, and other players.

**Acceptance Criteria (EARS)**
- WHEN a player enters a zone THEN Nakama SHALL send a compressed zone snapshot containing: zone time, terrain chunk references, entity list (id, type, transform, vitals), AOI seed, and active effects
  - For 2D worlds: Transform contains position {x, y} or {x, y, z: 0} and rotation {z}
  - For 3D worlds: Transform contains position {x, y, z} and rotation {x, y, z}
  - Terrain references: TileMap chunk IDs (2D) or Terrain/Mesh chunk IDs (3D)
- IF the snapshot size exceeds 512 KB compressed THEN Nakama SHALL chunk the data or apply LOD (level of detail) filtering
- WHEN the client receives the snapshot THEN the client SHALL apply it atomically (single frame) and subscribe to delta updates
- IF the client fails to apply the snapshot within 50 ms THEN the client SHALL report a performance warning
- WHEN the snapshot is successfully applied THEN Nakama SHALL begin streaming state diffs (deltas) for entities within the player's Area of Interest (AOI)

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 2/3 (character entry), zone state storage, compression library
- **Assumptions:** Snapshots use Deflate compression; terrain chunks are referenced by ID (not sent inline); target hardware is mid-range PC/console; system supports both 2D and 3D game worlds

---

### Requirement 5: Server-Authoritative Movement

**User Story:** As a player, I want my movement to be validated server-side, so that exploits like speed hacking cannot be used to gain unfair advantages.

**Acceptance Criteria (EARS)**
- WHEN a player sends a movement intent (direction, timestamp, nonce) THEN Nakama SHALL validate the input, calculate the authoritative position, and broadcast the result at 10-20 Hz
  - For 2D worlds: Validate position {x, y} within terrain bounds using 2D collision
  - For 3D worlds: Validate position {x, y, z} within terrain bounds using 3D collision
- IF a movement intent violates physics constraints (speed, collision) THEN Nakama SHALL reject or correct the input and send a correction to the client
- WHEN the client receives a position correction THEN the client SHALL reconcile its predicted state with the server truth
- IF the reconciliation delta exceeds 2 frames (p95) THEN the client SHALL report a lag warning
- WHILE a player is moving THEN Nakama SHALL continuously validate inputs and update the player's position in the zone state

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 4 (zone snapshot), physics/collision system
- **Assumptions:** Client uses client-side prediction + server reconciliation; nonces prevent replay attacks

---

### Requirement 6: Server-Authoritative Combat and Abilities

**User Story:** As a player, I want my combat actions (attacks, abilities, healing) to be validated server-side, so that hit detection, critical hits, and resource consumption are fair and consistent.

**Acceptance Criteria (EARS)**
- WHEN a player uses an ability THEN Nakama SHALL validate: ability_id, target_id, cooldown state, resource costs, range, and line of sight
- IF any validation check fails THEN Nakama SHALL reject the ability and return an error code to the client
- WHEN an ability is successfully validated THEN Nakama SHALL apply damage/healing, update vitals, trigger cooldowns, and broadcast the result
- IF a target is killed THEN Nakama SHALL update the target's state, trigger death logic (respawn, loot drops), and notify all clients in AOI
- WHEN damage is calculated THEN Nakama SHALL apply server-side formulas for base damage, critical hits, resistances, and buffs/debuffs

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 5 (movement), ability/combat configuration tables
- **Assumptions:** Ability data (cooldowns, costs, ranges) is data-driven; crit chance/damage multipliers are configurable

---

### Requirement 7: Persistent Zone State

**User Story:** As an explorer, I want zones to persist NPC positions, resource node states, and environmental changes, so that the world feels alive and consistent across sessions.

**Acceptance Criteria (EARS)**
- WHEN a zone process starts THEN Nakama SHALL load the zone state from the last checkpoint and replay events from the event log
- WHILE a zone is active THEN Nakama SHALL persist checkpoints at regular intervals (e.g., every 10 seconds) and log all state-changing events
- IF a zone process crashes THEN Nakama SHALL restore the zone from the last checkpoint + event log, losing at most 5 seconds of progress
- WHEN a zone process performs a safe shutdown THEN Nakama SHALL persist a final checkpoint and event log before terminating
- WHEN a zone is cold-started THEN Nakama SHALL restore the zone to its last known state (NPCs, resources, timers) within the RTO (≤5 minutes)

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Database schema for world_state, event logging framework
- **Assumptions:** Checkpoints are serialized JSON or binary; event logs are append-only; RPO ≤5s, RTO ≤5min

---

### Requirement 8: Area of Interest (AOI) Management

**User Story:** As a player, I want to receive updates only for entities near me, so that my client is not overwhelmed with irrelevant data.

**Acceptance Criteria (EARS)**
- WHEN a player enters a zone THEN Nakama SHALL calculate the player's Area of Interest (AOI) based on position and visibility radius
  - For 2D worlds: AOI is calculated as a circle around position {x, y} with configured radius (e.g., 50 units)
  - For 3D worlds: AOI is calculated as a sphere around position {x, y, z} with configured radius (e.g., 50 units)
- WHILE a player is in a zone THEN Nakama SHALL send delta updates only for entities within the player's AOI
- WHEN an entity enters the player's AOI THEN Nakama SHALL send an entity-add message with initial state
- WHEN an entity exits the player's AOI THEN Nakama SHALL send an entity-remove message
- IF the outbound bandwidth for a client exceeds a configurable limit THEN Nakama SHALL apply LOD filtering or reduce update frequency

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 4 (zone snapshot), spatial indexing (e.g., grid, quadtree)
- **Assumptions:** AOI radius is configurable per zone type; bandwidth limit is per-client

---

### Requirement 9: Instanced Content Entry (No Matchmaking)

**User Story:** As a party member, I want to enter a private dungeon or arena via an in-world portal or party command, so that we get an isolated instance without waiting in matchmaking queues.

**Acceptance Criteria (EARS)**
- WHEN a party interacts with a portal or issues an instance command THEN Nakama SHALL create a new match instance (template_id, party_id) and return match_id and entry_anchor
- IF the party does not meet instance requirements (size, level, items) THEN Nakama SHALL reject the entry and return an error
- WHEN the instance is created THEN Nakama SHALL transition all party members to the instance and send them the instance snapshot
- WHEN party members complete or exit the instance THEN Nakama SHALL return them to the world at the exit anchor coordinates
- IF instance rewards are granted THEN Nakama SHALL persist them atomically (all-or-nothing) to prevent partial credit

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 4 (snapshots), party system, match/instance templates
- **Assumptions:** Instances use Nakama match runtime under the hood; no external matchmaker service

---

### Requirement 10: Instance Rejoin Grace Period

**User Story:** As a player, I want to rejoin my instance if I disconnect, so that brief network issues don't result in lost progress or rewards.

**Acceptance Criteria (EARS)**
- WHEN a player disconnects from an instance THEN Nakama SHALL hold the player's slot for a configurable grace period (e.g., 5 minutes)
- IF the player reconnects within the grace period THEN Nakama SHALL restore the player to the instance at their last known state
- IF the grace period expires THEN Nakama SHALL remove the player from the instance and forfeit their rewards
- WHEN a player rejoins THEN Nakama SHALL send the current instance state snapshot to re-synchronize the client

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirement 9 (instance entry), session management
- **Assumptions:** Grace period is configurable per instance type; party can continue or pause during disconnect

---

### Requirement 11: Guild Creation and Management

**User Story:** As a social player, I want to create and manage a guild, so that I can organize a community, share resources, and coordinate activities.

**Acceptance Criteria (EARS)**
- WHEN a player creates a guild THEN Nakama SHALL assign a unique guild_id, set the creator as guild master, and initialize guild storage
- IF the guild name is already taken or invalid THEN Nakama SHALL reject the creation
- WHEN a guild master assigns ranks THEN Nakama SHALL update member permissions (invite, kick, edit MOTD, access storage)
- WHEN a guild member is kicked THEN Nakama SHALL remove them from the guild roster and revoke guild permissions
- WHEN a guild is disbanded THEN Nakama SHALL delete the guild record and notify all members

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Guild database schema (guilds, guild_members)
- **Assumptions:** Guild ranks are hierarchical; MOTD is plain text (max 500 chars); guild storage is shared inventory

---

### Requirement 12: Chat Channels and Direct Messages

**User Story:** As a social player, I want to communicate via world, zone, party, and guild chat channels, as well as send direct messages, so that I can coordinate and socialize.

**Acceptance Criteria (EARS)**
- WHEN a player sends a chat message THEN Nakama SHALL validate the message (length, profanity filter) and broadcast it to the appropriate channel subscribers
- IF the message violates content policy THEN Nakama SHALL reject it and log the attempt for moderation
- WHEN a player joins a zone THEN Nakama SHALL automatically subscribe them to the zone channel
- WHEN a player joins a party or guild THEN Nakama SHALL subscribe them to the corresponding channels
- WHEN a player sends a direct message THEN Nakama SHALL deliver it only to the target recipient if they are online, or queue it for offline delivery

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Channel/messaging infrastructure, profanity filter library
- **Assumptions:** Messages are plain text; offline messages expire after 7 days; moderation is manual or automated

---

### Requirement 13: Moderation Tools

**User Story:** As a moderator, I want to mute, kick, or ban players from chat channels, so that I can enforce community standards and maintain a positive environment.

**Acceptance Criteria (EARS)**
- WHEN a moderator mutes a player THEN Nakama SHALL prevent the player from sending messages in the specified channel for a configurable duration
- WHEN a moderator kicks a player from a channel THEN Nakama SHALL unsubscribe the player and prevent rejoining for a configurable cooldown
- WHEN a moderator bans a player THEN Nakama SHALL permanently block the player from the channel and log the action for audit
- IF a player is muted/kicked/banned THEN Nakama SHALL notify the player with the reason and duration
- WHEN a moderation action is taken THEN Nakama SHALL log the moderator_id, target_id, action, reason, and timestamp

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirement 12 (chat), moderation database schema
- **Assumptions:** Moderators have elevated permissions; actions are reversible; audit logs are queryable

---

### Requirement 14: Transactional Inventory Management

**User Story:** As a player, I want my inventory actions (move, use, drop, trade) to be transactional, so that items are never duplicated or lost due to race conditions.

**Acceptance Criteria (EARS)**
- WHEN a player moves an item THEN Nakama SHALL execute an idempotent RPC with version checks to ensure atomicity
- IF an inventory write conflicts with a concurrent operation THEN Nakama SHALL retry or reject the operation with an error
- WHEN an item is consumed (used, dropped, traded) THEN Nakama SHALL verify the item exists, decrement quantity, and persist the change atomically
- IF an item has a unique ID (UID) THEN Nakama SHALL enforce that the UID cannot be duplicated across all players
- WHEN an inventory operation fails THEN Nakama SHALL roll back any partial changes and leave inventory in a consistent state

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Inventory database schema with versioning, transaction isolation
- **Assumptions:** Each item has metadata (UID, type, quantity, durability); operations are serialized per character

---

### Requirement 15: Player-to-Player Trading

**User Story:** As a player, I want to trade items safely with another player, so that both parties receive their agreed items without risk of duplication or loss.

**Acceptance Criteria (EARS)**
- WHEN a player initiates a trade THEN Nakama SHALL create a trade_session and lock both players' inventories from external modifications
- WHEN both players confirm the trade THEN Nakama SHALL execute a two-phase commit: verify items, deduct from source inventories, add to target inventories
- IF any step of the two-phase commit fails THEN Nakama SHALL roll back the entire trade and unlock inventories
- WHEN the trade completes successfully THEN Nakama SHALL log the transaction (trade_id, participants, items, timestamp) for audit
- IF either player disconnects during the trade THEN Nakama SHALL cancel the trade and unlock inventories after a timeout

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 14 (inventory), trade_sessions schema
- **Assumptions:** Trade UI shows real-time item previews; items are locked during trade; UIDs prevent duplication

---

### Requirement 16: Vendor Systems

**User Story:** As a player, I want to buy and sell items from NPC vendors, so that I can acquire gear and offload unwanted loot.

**Acceptance Criteria (EARS)**
- WHEN a player interacts with a vendor THEN Nakama SHALL return the vendor's catalog (items, prices, stock limits)
- WHEN a player purchases an item THEN Nakama SHALL verify the player has sufficient currency, deduct the cost, add the item to inventory, and update vendor stock
- IF the vendor is out of stock THEN Nakama SHALL reject the purchase
- WHEN a player sells an item THEN Nakama SHALL verify the item is sellable, remove it from inventory, and credit the player's wallet
- WHEN vendor stock resets THEN Nakama SHALL refresh inventory based on vendor configuration (reset interval, item lists)

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirement 14 (inventory), vendor catalog schema, wallet system
- **Assumptions:** Vendor catalogs are data-driven (JSON/DB); stock limits are per-vendor or global; prices are fixed or dynamic

---

### Requirement 17: Drop Tables and Loot Generation

**User Story:** As a player, I want defeated enemies and opened chests to drop loot based on server-validated drop tables, so that rewards are fair and cannot be exploited.

**Acceptance Criteria (EARS)**
- WHEN an NPC is killed or a loot container is opened THEN Nakama SHALL roll loot based on the associated drop table (item_id, drop_chance, quantity_range)
- IF a drop is successful THEN Nakama SHALL generate item instances with UIDs and add them to the world or player inventory
- WHEN loot is generated THEN Nakama SHALL apply server-side RNG (seeded, non-client-predictable) to determine drops
- IF a drop table references a nested table (e.g., rare drops) THEN Nakama SHALL recursively resolve the drops
- WHEN loot is awarded THEN Nakama SHALL log the event (entity_id, drop_table_id, items, player_id, timestamp) for analytics

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Drop table schema, RNG library, event logging
- **Assumptions:** Drop tables are versioned and data-driven; loot is instanced or shared per party policy; analytics track drop rates

---

### Requirement 18: Seamless Region/Shard Handoff

**User Story:** As a traveler, I want to cross region or shard boundaries without relogging, so that the world feels continuous and immersive.

**Acceptance Criteria (EARS)**
- WHEN a player crosses a zone boundary THEN Nakama SHALL issue a handoff token and return the target zone's endpoint (host, port, protocol)
- WHEN the client receives the handoff token THEN the client SHALL pre-connect to the target endpoint and issue a handoff_finalize RPC
- IF the handoff_finalize succeeds THEN Nakama SHALL transfer the player's state to the new zone and close the old connection
- IF the handoff fails THEN Nakama SHALL roll back the player to a safe anchor in the original zone and notify the client to retry
- WHILE the handoff is in progress THEN Nakama SHALL lock the player's inventory and combat state to prevent exploits
- WHEN the handoff completes THEN the client SHALL mask the transition with a visual effect (portal, fog, bridge) and swap sockets within ≤1 second

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Zone boundary schema (zone_boundaries, handoff_tokens), multi-region infrastructure
- **Assumptions:** Handoff tokens expire after a timeout (e.g., 30s); visual masking is client-side; network latency ≤500ms

---

### Requirement 19: Handoff Failure Recovery

**User Story:** As a player, I want the system to recover gracefully if a region handoff fails, so that I don't lose items, XP, or progress.

**Acceptance Criteria (EARS)**
- IF a handoff_finalize RPC fails (network error, target zone unavailable) THEN Nakama SHALL roll back the player to the safe anchor in the source zone
- WHEN a rollback occurs THEN Nakama SHALL preserve all inventory, XP, stats, and cooldowns from before the handoff attempt
- IF the rollback fails THEN Nakama SHALL log a critical error and notify operators for manual recovery
- WHEN the client detects a handoff failure THEN the client SHALL display a retry prompt and allow the player to attempt the handoff again
- WHEN operators receive a handoff failure alert THEN they SHALL investigate zone availability and network connectivity

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 18 (handoff), error logging, operator alerts
- **Assumptions:** Safe anchors are predefined coordinates in each zone; rollback is idempotent

---

### Requirement 20: GM Console - Entity Management

**User Story:** As a live-ops GM, I want to spawn, despawn, and modify entities in real time, so that I can respond to live events, fix bugs, and run dynamic content.

**Acceptance Criteria (EARS)**
- WHEN a GM issues a spawn command THEN Nakama SHALL validate the GM's permissions, create the entity in the target zone, and broadcast the entity to clients
- IF the GM lacks permissions THEN Nakama SHALL reject the command and log the attempt
- WHEN a GM despawns an entity THEN Nakama SHALL remove it from the zone state and notify clients
- WHEN a GM modifies entity properties (health, buffs, loot table) THEN Nakama SHALL apply the changes immediately and persist them if the entity is persistent
- WHEN a GM command is executed THEN Nakama SHALL log the GM's account_id, command, target entity, and timestamp for audit

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** GM permission system, entity schema, audit logs
- **Assumptions:** GM commands use a secure console interface (web/CLI); permissions are role-based (RBAC)

---

### Requirement 21: GM Console - World Parameter Tweaking

**User Story:** As a live-ops GM, I want to change drop rates, buff values, and other world parameters in real time, so that I can run limited-time events and balance gameplay dynamically.

**Acceptance Criteria (EARS)**
- WHEN a GM updates a drop rate THEN Nakama SHALL apply the change to the target drop table and notify affected zones
- WHEN a GM toggles a global buff THEN Nakama SHALL broadcast the buff state to all active zones and clients
- IF a parameter change affects gameplay (damage, XP multipliers) THEN Nakama SHALL log the change and its duration for rollback
- WHEN a temporary parameter change expires THEN Nakama SHALL automatically revert to the baseline configuration
- WHEN a GM broadcasts a message THEN Nakama SHALL send it to all online players in the specified scope (world, zone, guild)

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Configuration schema, broadcast messaging, scheduler for expiration
- **Assumptions:** Parameter changes are versioned; rollback is manual or scheduled; GMs can preview changes before applying

---

### Requirement 22: Event Scheduling

**User Story:** As a live-ops GM, I want to schedule events (XP boosts, holiday content, boss spawns) with cron-like syntax, so that content runs automatically without manual intervention.

**Acceptance Criteria (EARS)**
- WHEN a GM creates an event schedule THEN Nakama SHALL validate the cron expression, script_id, and parameters, then store the schedule
- WHEN a scheduled event triggers THEN Nakama SHALL execute the associated server function (Lua/TS) with the configured parameters
- IF an event execution fails THEN Nakama SHALL log the error, alert operators, and optionally retry based on retry policy
- WHEN a GM previews an event THEN Nakama SHALL simulate the execution (dry-run) and return the expected outcome without side effects
- WHEN an event schedule is deleted THEN Nakama SHALL cancel future executions and archive the schedule for audit

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Event scheduler (cron parser), script runtime, audit logs
- **Assumptions:** Scripts are versioned and hot-loadable; dry-run uses sandbox environment; schedules are timezone-aware

---

### Requirement 23: Hot-Loadable Scripts

**User Story:** As a live-ops developer, I want to deploy new scripts (Lua/TypeScript) to the server without downtime, so that I can iterate quickly on events and content.

**Acceptance Criteria (EARS)**
- WHEN a GM uploads a script pack THEN Nakama SHALL validate the script syntax, permissions, and dependencies
- IF the script is valid THEN Nakama SHALL load it into the runtime and make it available for RPC/event execution
- WHEN a script is hot-loaded THEN Nakama SHALL log the script_id, version, uploader, and timestamp for audit
- IF a script fails validation THEN Nakama SHALL reject the upload and return error details
- WHEN a script is deprecated THEN Nakama SHALL unload it from the runtime and archive it for rollback

**Additional Details**
- **Priority:** Medium
- **Complexity:** High
- **Dependencies:** Script runtime sandbox, versioning system, audit logs
- **Assumptions:** Scripts are sandboxed (no direct DB access); hot-loading uses atomic replacement; rollback to previous version is supported

---

### Requirement 24: Store Catalog

**User Story:** As a player, I want to view the in-game store catalog and see available cosmetics, expansions, and currency packs, so that I can make informed purchase decisions.

**Acceptance Criteria (EARS)**
- WHEN a player requests the store catalog THEN Nakama SHALL return the list of items (SKU, name, description, price, preview_url, entitlements)
- IF the catalog has regional or time-limited items THEN Nakama SHALL filter items based on player region and current date/time
- WHEN the catalog is updated THEN Nakama SHALL push the new version to clients or invalidate cached catalogs
- IF an item is out of stock or deprecated THEN Nakama SHALL exclude it from the catalog response

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Catalog schema, regional configuration, versioning
- **Assumptions:** Catalog is versioned; preview URLs point to CDN assets; prices are in local currency

---

### Requirement 25: Purchase Verification

**User Story:** As a player, I want my in-app purchases to be verified server-side, so that my entitlements are secure and cannot be forged.

**Acceptance Criteria (EARS)**
- WHEN a player completes a purchase THEN the client SHALL send the platform receipt (Apple, Google, Steam) to Nakama
- WHEN Nakama receives a receipt THEN Nakama SHALL validate it with the platform's verification API
- IF the receipt is valid THEN Nakama SHALL grant the entitlements (cosmetics, currency, expansions) and persist them to the player's account
- IF the receipt is invalid or duplicated THEN Nakama SHALL reject the purchase and log the attempt for fraud detection
- WHEN entitlements are granted THEN Nakama SHALL notify the client and update the player's loadout/wallet atomically

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Platform receipt validation APIs (Apple, Google, Steam), entitlements schema
- **Assumptions:** Receipts are platform-specific; validation is async; entitlements are durable and queryable

---

### Requirement 26: Entitlements and Cosmetics

**User Story:** As a player, I want my purchased cosmetics and expansions to persist across sessions and devices, so that my purchases are enforceable and server-side.

**Acceptance Criteria (EARS)**
- WHEN a player logs in THEN Nakama SHALL load all active entitlements (cosmetics, expansions, boosts) for the account
- WHEN a player equips a cosmetic THEN Nakama SHALL validate ownership, apply it to the character loadout, and broadcast the visual to other clients
- IF a player's entitlement is revoked (refund, ban) THEN Nakama SHALL remove it from the account and unequip it from all characters
- WHEN an entitlement is queried THEN Nakama SHALL return the state (active, expired, revoked), purchase date, and metadata
- WHEN a cosmetic is applied THEN Nakama SHALL enforce server-side validation (only owned cosmetics can be equipped)

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 25 (purchase verification), entitlements schema, loadout system
- **Assumptions:** Cosmetics are appearance-only (no gameplay impact); entitlements are account-wide or character-specific

---

### Requirement 27: Soft Currency and Wallets

**User Story:** As a player, I want to earn and spend soft currency (gold, gems) with transactional guarantees, so that my balance is always accurate and auditable.

**Acceptance Criteria (EARS)**
- WHEN a player earns currency THEN Nakama SHALL credit the wallet atomically and log the transaction (source, amount, timestamp)
- WHEN a player spends currency THEN Nakama SHALL verify sufficient balance, deduct atomically, and log the transaction
- IF a wallet operation fails mid-transaction THEN Nakama SHALL roll back any partial changes
- WHEN a wallet is queried THEN Nakama SHALL return all currency balances (gold, gems, event tokens) with version numbers
- WHEN a wallet transaction is audited THEN Nakama SHALL provide a queryable log of all credits/debits per account

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Wallet schema with versioning, transaction log, audit queries
- **Assumptions:** Wallets support multiple currency types; transactions are idempotent; logs are append-only

---

### Requirement 28: GDPR Compliance - Data Export

**User Story:** As a player, I want to export all my personal data, so that I can exercise my GDPR right to data portability.

**Acceptance Criteria (EARS)**
- WHEN a player requests a data export THEN Nakama SHALL generate a JSON file containing account info, characters, inventory, transactions, chat logs, and entitlements
- IF the export exceeds size limits THEN Nakama SHALL split it into multiple files or provide a download link
- WHEN the export is ready THEN Nakama SHALL notify the player via email or in-game notification with a secure download link
- IF the player is not authenticated THEN Nakama SHALL reject the export request
- WHEN the export is downloaded THEN Nakama SHALL log the export event for audit

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** GDPR compliance framework, export generation pipeline, secure file storage
- **Assumptions:** Exports expire after 7 days; data is anonymized where required by regulation

---

### Requirement 29: GDPR Compliance - Account Deletion

**User Story:** As a player, I want to delete my account and all associated data, so that I can exercise my GDPR right to be forgotten.

**Acceptance Criteria (EARS)**
- WHEN a player requests account deletion THEN Nakama SHALL prompt for confirmation and initiate a grace period (e.g., 30 days)
- IF the player does not cancel during the grace period THEN Nakama SHALL permanently delete the account, characters, inventory, transactions, and entitlements
- WHEN deletion is complete THEN Nakama SHALL anonymize or delete chat logs, guild memberships, and trade history
- IF the account has pending transactions or disputes THEN Nakama SHALL delay deletion until resolved
- WHEN deletion is finalized THEN Nakama SHALL log the event for audit and send a confirmation email

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** GDPR compliance framework, data retention policies, audit logs
- **Assumptions:** Grace period is configurable; deletion is irreversible; anonymization preserves analytics integrity

---

### Requirement 30: Purchase Refunds and Revocation

**User Story:** As a player, I want to request refunds for in-app purchases within a grace period, so that I can undo accidental or unwanted purchases.

**Acceptance Criteria (EARS)**
- WHEN a player requests a refund THEN Nakama SHALL verify the purchase is within the refund window (e.g., 14 days) and has not been consumed
- IF the refund is approved THEN Nakama SHALL revoke the entitlements, credit the platform refund, and log the transaction
- IF the entitlements have been used/consumed THEN Nakama SHALL reject the refund request
- WHEN a refund is processed THEN Nakama SHALL notify the player and update their wallet/loadout to reflect the revocation
- WHEN a fraudulent refund is detected THEN Nakama SHALL flag the account for review and optionally suspend it

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirement 25/26 (purchases/entitlements), platform refund APIs, fraud detection
- **Assumptions:** Refund window is platform-specific; consumed items cannot be refunded; fraudulent refunds trigger manual review

---

### Requirement 31: Observability - Metrics and Dashboards

**User Story:** As an operator, I want real-time metrics and dashboards for CCU, zone performance, database latency, and handoff success rates, so that I can monitor system health and detect issues proactively.

**Acceptance Criteria (EARS)**
- WHEN Nakama is running THEN the system SHALL expose Prometheus-compatible metrics endpoints
- WHEN metrics are scraped THEN Grafana dashboards SHALL display: CCU per zone, zone tick time (p50/p95/p99), DB write latency, snapshot size, bandwidth per client, handoff success rate
- IF a metric exceeds a threshold (e.g., tick time >10ms p95) THEN Nakama SHALL trigger an alert (PagerDuty, Slack, email)
- WHEN an operator views a dashboard THEN they SHALL see real-time and historical trends (1h, 6h, 24h, 7d)
- WHEN a critical alert fires THEN Nakama SHALL include context (zone_id, affected players, error logs) for rapid triage

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Prometheus, Grafana, alerting integrations (PagerDuty, Slack)
- **Assumptions:** Metrics are sampled every 10-15 seconds; dashboards are pre-configured; alerts are tiered (warning, critical)

---

### Requirement 32: Blue/Green Deployments

**User Story:** As an operator, I want to deploy new server versions using blue/green deployments, so that I can minimize downtime and rollback quickly if issues arise.

**Acceptance Criteria (EARS)**
- WHEN a new version is deployed THEN Nakama SHALL spin up a parallel "green" environment and route a small percentage of traffic (canary)
- IF the canary metrics (error rate, latency, CCU) are healthy THEN Nakama SHALL gradually shift traffic from "blue" to "green"
- IF the canary detects issues THEN Nakama SHALL halt the rollout, route traffic back to "blue", and alert operators
- WHEN the rollout is complete THEN Nakama SHALL decommission the old "blue" environment after a grace period
- WHEN a rollback is triggered THEN Nakama SHALL revert traffic to "blue" within ≤2 minutes

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Kubernetes or container orchestration, load balancer with traffic shaping, health checks
- **Assumptions:** Canary phase is 5-10% traffic for 10-15 minutes; rollback is automated; database schema is backward-compatible

---

### Requirement 33: Chaos Engineering - Zone Kill Recovery

**User Story:** As an operator, I want to test zone crash recovery by killing zone processes randomly, so that I can verify persistence and RTO guarantees.

**Acceptance Criteria (EARS)**
- WHEN a chaos test is triggered THEN Nakama SHALL randomly terminate a zone process
- WHEN a zone is killed THEN Nakama SHALL detect the failure and restart the zone from the last checkpoint + event log
- IF the recovery completes within RTO (≤5 minutes) THEN the test SHALL pass
- IF progress loss exceeds RPO (≤5 seconds) THEN the test SHALL fail and alert operators
- WHEN the zone is restored THEN players SHALL be reconnected automatically and resume gameplay without manual intervention

**Additional Details**
- **Priority:** Medium
- **Complexity:** High
- **Dependencies:** Requirement 7 (persistence), chaos testing framework (e.g., Chaos Monkey), health checks
- **Assumptions:** Chaos tests run in staging or low-traffic production windows; alerts are suppressed during tests

---

### Requirement 34: Godot Client Plugin Updates

**User Story:** As a Godot game developer, I want the nakama-godot plugin (https://github.com/heroiclabs/nakama-godot) to support MMORPG-specific features, so that I can easily integrate zone snapshots, delta streaming, client prediction, and handoff flows into my game.

**Acceptance Criteria (EARS)**
- WHEN the plugin is updated THEN it SHALL include helper classes for snapshot deserialization and decompression (Deflate)
- WHEN a developer uses the plugin THEN it SHALL provide a DeltaStreamProcessor class to handle zone delta updates with automatic entity interpolation
- WHEN client-side prediction is needed THEN the plugin SHALL include a ClientPrediction module with move queuing, reconciliation, and correction handling
- WHEN a handoff is initiated THEN the plugin SHALL provide a HandoffManager class to orchestrate pre-connection, token exchange, and socket swapping
- IF the plugin API is extended THEN it SHALL maintain backward compatibility with existing nakama-godot projects
- WHEN helper utilities are added THEN the plugin SHALL include AOI (Area of Interest) filtering, entity state caching, and bandwidth optimization helpers
- WHEN documentation is updated THEN it SHALL include GDScript examples for zone entry, movement prediction, combat intents, and cross-region handoffs
- WHEN the plugin is released THEN it SHALL include a sample MMORPG project demonstrating authentication, character select, zone snapshot application, and movement reconciliation

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** All client-side requirements (2, 4, 5, 6, 18), Godot 4.x compatibility
- **Assumptions:** Plugin is open-source and accepts community contributions; sample project uses GDScript (not C#); compression libraries are available in Godot standard library

---

### Requirement 35: Client Plugin - Snapshot Utilities

**User Story:** As a Godot developer, I want built-in utilities to decompress, parse, and apply zone snapshots, so that I don't have to write boilerplate networking code.

**Acceptance Criteria (EARS)**
- WHEN a zone snapshot is received THEN the SnapshotApplier utility SHALL automatically decompress the blob using Deflate
- WHEN the snapshot is parsed THEN the utility SHALL deserialize JSON data into typed GDScript objects (ZoneSnapshot, EntitySnapshot, etc.)
- WHEN entities are spawned from snapshot THEN the utility SHALL emit signals for entity_added(entity_data) to allow custom scene instantiation
- IF the snapshot exceeds size limits THEN the utility SHALL support chunked/streamed decompression
- WHEN a snapshot is applied THEN the utility SHALL pause the scene tree, clear old entities, instantiate new entities, and resume in a single frame
- WHEN snapshot application fails THEN the utility SHALL emit an error signal with diagnostic information

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 4 (zone snapshots), Godot StreamPeerBuffer, Marshalls API
- **Assumptions:** Snapshots use Deflate compression; JSON is the serialization format; developers can override default entity instantiation logic

---

### Requirement 36: Client Plugin - Delta Stream Processing

**User Story:** As a Godot developer, I want automatic delta update handling, so that my game world stays synchronized with the server without manual streaming code.

**Acceptance Criteria (EARS)**
- WHEN zone deltas are received THEN the DeltaStreamProcessor SHALL parse entity updates, adds, and removes
- WHEN an entity update is processed THEN the processor SHALL emit entity_updated(entity_id, update_data) signals
- WHEN an entity is added THEN the processor SHALL emit entity_added(entity_data) signals
- WHEN an entity is removed THEN the processor SHALL emit entity_removed(entity_id) signals
- IF updates arrive faster than the client can process THEN the processor SHALL queue deltas and apply them at a configurable rate (e.g., 20 Hz)
- WHEN interpolation is needed THEN the processor SHALL provide optional linear interpolation between entity positions
- WHEN bandwidth optimization is enabled THEN the processor SHALL support delta compression and deduplication

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 4 (delta updates), Requirement 8 (AOI), Nakama streaming API
- **Assumptions:** Deltas are JSON-encoded; interpolation is client-side only; developers connect to signals for custom entity handling

---

### Requirement 37: Client Plugin - Prediction & Reconciliation

**User Story:** As a Godot developer, I want built-in client-side prediction and server reconciliation, so that movement feels responsive even with network latency.

**Acceptance Criteria (EARS)**
- WHEN a player inputs movement THEN the ClientPrediction module SHALL immediately apply the move locally and queue it for server validation
- WHEN the server acknowledges a move THEN the module SHALL remove the move from the pending queue
- WHEN the server sends a position correction THEN the module SHALL reconcile the client state by replaying unacknowledged moves
- IF the correction delta exceeds a configurable threshold THEN the module SHALL emit a correction_warning(delta) signal
- WHEN nonces are used THEN the module SHALL automatically generate and track nonces to prevent replay attacks
- WHEN prediction is disabled THEN the module SHALL fall back to direct server-authoritative movement
- WHEN physics is involved THEN the module SHALL support custom physics callbacks for move prediction (e.g., collision detection)

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 5 (movement validation), Requirement 6 (combat), Godot physics engine
- **Assumptions:** Prediction uses local physics simulation; reconciliation replays moves at fixed timestep; nonces are monotonically increasing

---

### Requirement 38: Client Plugin - Handoff Manager

**User Story:** As a Godot developer, I want a HandoffManager to orchestrate seamless cross-region transfers, so that I can implement world boundaries without complex networking logic.

**Acceptance Criteria (EARS)**
- WHEN a handoff is requested THEN the HandoffManager SHALL call the handoff_request RPC and store the returned token and endpoint
- WHEN the token is received THEN the manager SHALL pre-connect a new socket to the target endpoint in the background
- WHEN the new socket is ready THEN the manager SHALL call handoff_finalize and swap the active connection atomically
- IF the handoff fails THEN the manager SHALL emit handoff_failed(error) and maintain the existing connection
- WHEN a handoff is in progress THEN the manager SHALL lock player input and display a transition UI (configurable callback)
- WHEN the handoff completes THEN the manager SHALL emit handoff_completed(new_zone_id) and unlock player input
- WHEN a visual mask is needed THEN the manager SHALL support optional transition effects (fade, portal, loading screen)

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 18, 19 (handoffs), Nakama WebSocket/gRPC client
- **Assumptions:** Handoff timeout is configurable; transition UI is developer-provided; rollback on failure is automatic

---

### Requirement 39: Client Plugin - API Documentation & Examples

**User Story:** As a Godot developer, I want comprehensive documentation and code examples, so that I can quickly integrate MMORPG features into my game without trial and error.

**Acceptance Criteria (EARS)**
- WHEN the plugin documentation is published THEN it SHALL include API references for all new classes (SnapshotApplier, DeltaStreamProcessor, ClientPrediction, HandoffManager)
- WHEN examples are provided THEN they SHALL demonstrate: authentication flow, character selection, zone entry with snapshot, movement with prediction, ability usage, and cross-region handoff
- WHEN a sample project is included THEN it SHALL be a minimal MMORPG demo with a playable character, NPC entities, and at least two connected zones
- IF developers need integration guidance THEN the documentation SHALL include migration guides from standard nakama-godot usage to MMORPG patterns
- WHEN API changes are made THEN the documentation SHALL include a changelog with breaking changes clearly marked
- WHEN troubleshooting is needed THEN the documentation SHALL include common issues and solutions (snapshot size limits, handoff failures, prediction drift)

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirements 34-38 (all client plugin features)
- **Assumptions:** Documentation is hosted on GitHub wiki or separate docs site; examples use GDScript 2.0 syntax; sample project is MIT-licensed

---

## Non-Functional Requirements

### Performance Requirements
- WHEN a zone has 1k active entities THEN Nakama SHALL maintain a zone tick budget ≤10 ms (p95)
- WHEN a player sends a movement/ability RPC THEN Nakama SHALL respond within ≤150 ms (p95) within the same region
- WHEN a database write is executed THEN Nakama SHALL complete within ≤30 ms (p95)
- WHEN a zone snapshot is generated THEN Nakama SHALL compress it to ≤512 KB and allow client apply time ≤50 ms on target hardware

### Security Requirements
- WHEN a player authenticates THEN Nakama SHALL issue a signed JWT with expiration and enforce TLS 1.2+ for transport
- WHEN an RPC is invoked THEN Nakama SHALL enforce per-account rate limits to prevent abuse
- WHEN critical operations occur (purchases, GM commands) THEN Nakama SHALL log them with account_id, IP, and timestamp for audit
- WHEN secrets are managed THEN Nakama SHALL use least-privilege access (e.g., K8s secrets, environment variables) and rotate them regularly

### Usability Requirements
- WHEN a player encounters an error THEN Nakama SHALL return user-friendly error messages (not stack traces)
- WHEN a handoff fails THEN the client SHALL display a retry prompt with clear instructions
- WHEN a purchase is completed THEN the client SHALL show immediate visual feedback (entitlement granted, cosmetic equipped)

### Reliability Requirements
- WHEN Nakama is operational THEN the system SHALL achieve ≥99.9% weekly uptime for zone services
- WHEN a zone crashes THEN Nakama SHALL restore it with RPO ≤5 seconds and RTO ≤5 minutes
- WHEN a database write fails THEN Nakama SHALL retry with exponential backoff and alert operators after 3 failures
- WHEN unplanned data loss occurs THEN Nakama SHALL trigger a critical alert and initiate manual recovery

---

## Constraints and Assumptions

### Technical Constraints
- Nakama server must run on Linux (Docker/K8s)
- PostgreSQL 12+ required for database
- Godot 4.x clients required for full feature support
- WebSocket or gRPC transport for real-time communication
- Zone tick rate limited by server hardware (10-20 Hz target)

### Business Constraints
- Compliance with GDPR, CCPA for player data
- Platform-specific payment integration (Apple, Google, Steam)
- Localization support for catalogs and error messages (future scope)
- Refund policies aligned with platform guidelines (Apple 14 days, Google 48 hours, etc.)

### Assumptions
- Players have stable internet (≤500ms latency to nearest region)
- Target hardware: mid-range PC/console (Godot 4 min specs)
- Database sharding/replication handled by external infrastructure (K8s, cloud providers)
- NPC AI logic is data-driven (scriptable, not hardcoded)
- Drop tables and vendor catalogs are managed via CMS or JSON files
- GM permissions are role-based (admin, moderator, analyst)

---

## Success Criteria

### Definition of Done
- All functional requirements (1-33) have automated or manual test coverage
- Load tests pass at ≥50k CCU per shard with p95 latency ≤150ms
- Chaos tests verify RPO ≤5s and RTO ≤5min for zone crashes
- Dashboards and alerts are operational in production
- Godot 4 demo client demonstrates: login → character select/create → zone entry → movement/combat → instance entry/exit → cross-region handoff → purchase & equip cosmetic → relog (persistence verified)
- GM console is functional with RBAC and audit logs
- GDPR data export/deletion flows are tested and documented

### Acceptance Metrics
- **Scalability**: ≥50k CCU per shard, horizontally scalable to 1M+ CCU across regions
- **Latency**: p95 movement/ability round-trip ≤150ms within region
- **Uptime**: ≥99.9% weekly zone availability
- **Persistence**: RPO ≤5s, RTO ≤5min for zone crashes
- **Data Integrity**: Zero unplanned data loss during deployments or crashes
- **Fair Play**: 100% of critical gameplay operations validated server-side (no client authority)

---

## Glossary

| Term | Definition |
|---|---|
| AOI (Area of Interest) | The spatial region around a player from which they receive entity updates |
| CCU (Concurrent Users) | Number of players online simultaneously |
| EARS | Easy Approach to Requirements Syntax (industry-standard format) |
| Godot | Open-source game engine (version 4.x) |
| GM (Game Master) | Live-ops operator with elevated permissions for world/content management |
| JWT (JSON Web Token) | Signed authentication token with expiration |
| Nakama | Open-source game server runtime |
| NPC (Non-Player Character) | AI-controlled entity in the game world |
| RPC (Remote Procedure Call) | Client-to-server function invocation |
| RPO (Recovery Point Objective) | Maximum acceptable data loss (≤5s) |
| RTO (Recovery Time Objective) | Maximum acceptable downtime (≤5min) |
| Shard | Isolated server instance hosting a subset of players/zones |
| Snapshot | Compressed zone state sent to clients on entry |
| UID (Unique Identifier) | Server-generated ID for items to prevent duplication |
| Zone | Persistent game area (region, instance, dungeon) |

---

## Requirements Review Checklist

**Completeness**
✅ All user stories have clear roles, features, and benefits
✅ Each requirement has specific acceptance criteria using EARS format
✅ Non-functional requirements are addressed (performance, security, reliability, usability)
✅ Success criteria are defined and measurable

**Quality**
✅ Requirements are written in active voice
✅ Each acceptance criterion is testable
✅ Requirements avoid implementation details (focus on "what", not "how")
✅ Terminology is consistent throughout (see Glossary)

**EARS Format Validation**
✅ WHEN statements describe specific events or triggers
✅ IF statements describe clear conditions or states
✅ WHILE statements describe continuous behaviors
✅ WHERE statements describe specific contexts
✅ All statements use **SHALL** for system responses

**Clarity**
✅ Requirements are unambiguous
✅ Technical jargon is explained in glossary
✅ Stakeholders (players, studios, operators) can understand all requirements
✅ No conflicting requirements exist

**Traceability**
✅ Requirements are numbered and organized (1-33)
✅ Dependencies between requirements are documented
✅ Requirements link to business objectives (scalability, persistence, fair play)
✅ Assumptions and constraints are documented

---

**Do the requirements look good? If so, we can move on to the next phase.**
