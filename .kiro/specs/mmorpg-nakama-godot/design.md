# Technical Design: MMORPG-grade Nakama (Godot-first)

## Document Information

- **Feature Name:** MMORPG-grade Nakama with Godot 4 Integration (2D/3D Support)
- **Version:** 1.1
- **Date:** October 28, 2025
- **Status:** In Design
- **Requirements Reference:** `.kiro/specs/mmorpg-nakama-godot/requirements.md`
- **Change Log:** Added dimension-agnostic support for both 2D and 3D worlds

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Components](#system-components)
3. [Data Models](#data-models)
4. [API Contracts](#api-contracts)
5. [Runtime Modules](#runtime-modules)
6. [Client Integration](#client-integration)
7. [Persistence Strategy](#persistence-strategy)
8. [Scalability & Performance](#scalability--performance)
9. [Security & Validation](#security--validation)
10. [Deployment Architecture](#deployment-architecture)
11. [Testing Strategy](#testing-strategy)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Godot 4 Clients                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Player 1     │  │ Player 2     │  │ Player N     │          │
│  │ - Prediction │  │ - Prediction │  │ - Prediction │          │
│  │ - Rendering  │  │ - Rendering  │  │ - Rendering  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          │  WebSocket/gRPC  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Load Balancer (TLS)                        │
└─────────────────────────────────────────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Nakama Server Cluster                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  API Layer (Go)                                          │  │
│  │  - Authentication (JWT)                                  │  │
│  │  - RPC Router                                            │  │
│  │  - Rate Limiting                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Runtime Layer (TypeScript/Lua)                         │  │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐          │  │
│  │  │ Character  │ │ World      │ │ Combat     │          │  │
│  │  │ Module     │ │ Module     │ │ Module     │          │  │
│  │  └────────────┘ └────────────┘ └────────────┘          │  │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐          │  │
│  │  │ Social     │ │ Economy    │ │ Instance   │          │  │
│  │  │ Module     │ │ Module     │ │ Module     │          │  │
│  │  └────────────┘ └────────────┘ └────────────┘          │  │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐          │  │
│  │  │ Handoff    │ │ Live-Ops   │ │ Commerce   │          │  │
│  │  │ Module     │ │ Module     │ │ Module     │          │  │
│  │  └────────────┘ └────────────┘ └────────────┘          │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Zone Processes (In-Memory State)                       │  │
│  │  - Tick Loop (10-20 Hz)                                 │  │
│  │  - AOI Management                                       │  │
│  │  - Entity State                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PostgreSQL Database                         │
│  - Accounts, Characters, Inventory                              │
│  - World State (Checkpoints + Event Logs)                       │
│  - Guilds, Social, Trade Sessions                               │
│  - Store Catalog, Entitlements, Wallets                         │
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

_Requirements: 1-33_

1. **Server Authority**: All gameplay-critical operations validated server-side (Req 5, 6)
2. **Crash-Safe Persistence**: Checkpoint + event log pattern for RPO ≤5s (Req 7)
3. **Horizontal Scalability**: Stateless API layer, sharded zones (Req 31, 32)
4. **Godot-First**: SDK examples, GDScript integration patterns (Req 2, 4, 5)
5. **No Matchmaking**: Direct instance creation, portal-based entry (Req 9)
6. **Seamless Handoffs**: Token-based cross-region transfers (Req 18, 19)
7. **Dimension-Agnostic**: Support both 2D and 3D worlds with unified data structures

---

### 2D/3D World Support

The system is designed to support both 2D and 3D game worlds using dimension-agnostic data structures. This allows game developers to build either 2D top-down/side-scrolling MMORPGs or traditional 3D MMORPGs using the same backend infrastructure.

**Position Representation:**
- **2D Worlds**: Position stored as `{x, y}` where `z` is omitted or set to `0`
- **3D Worlds**: Position stored as `{x, y, z}` with full 3D coordinates
- **Database**: JSONB columns flexibly store either format
- **Client**: Godot Vector2 (2D) or Vector3 (3D) based on game type

**Terrain/Map Representation:**
- **2D Worlds**: TileMap chunk IDs referencing tileset data
- **3D Worlds**: Terrain chunk IDs referencing heightmap/mesh data
- **Unified Storage**: Both use string array of chunk identifiers

**Spatial Indexing:**
- **2D Worlds**: Grid-based spatial partitioning (x, y cells)
- **3D Worlds**: Octree or 3D grid partitioning (x, y, z cells)
- **AOI Calculation**: Distance formula adapts to dimensionality

**Movement & Physics:**
- **2D Worlds**: Validate movement in x/y plane, collision against tilemap
- **3D Worlds**: Validate movement in x/y/z space, collision against terrain/meshes
- **Server Logic**: Same validation pipeline, dimension detected from position format

**Example Position Formats:**
```typescript
// 2D position (top-down RPG)
{
  "x": 128.5,
  "y": 256.0
}

// 3D position (traditional MMORPG)
{
  "x": 128.5,
  "y": 10.2,
  "z": 256.0
}
```

---

## System Components

### 1. Authentication Service

_Requirements: 1_

**Responsibilities:**
- Issue JWT session tokens on successful authentication
- Validate credentials (device ID, email, platform tokens)
- Enforce rate limits per account_id
- Optional 2FA for new devices

**Interfaces:**
```typescript
interface AuthenticationService {
  authenticate(credentials: Credentials): Promise<SessionToken>;
  validateToken(token: string): Promise<AccountContext>;
  refreshToken(oldToken: string): Promise<SessionToken>;
  revokeToken(token: string): Promise<void>;
}

interface Credentials {
  type: 'device' | 'email' | 'platform';
  identifier: string;
  secret?: string;
  platformToken?: string;
}

interface SessionToken {
  jwt: string;
  accountId: string;
  expiresAt: number;
  permissions: string[];
}
```

### 2. Character Service

_Requirements: 2, 3_

**Responsibilities:**
- List characters for authenticated account
- Create new characters with validation
- Load character state (zone, position, stats, inventory)
- Enforce character slot limits

**Interfaces:**
```typescript
interface CharacterService {
  listCharacters(accountId: string): Promise<Character[]>;
  createCharacter(accountId: string, name: string, archetypeId: string): Promise<CharacterId>;
  selectCharacter(characterId: string): Promise<CharacterState>;
  deleteCharacter(characterId: string): Promise<void>;
}

interface Character {
  characterId: string;
  accountId: string;
  name: string;
  archetypeId: string;
  level: number;
  lastZoneId: string;
  lastPosition: Vector3;
  createdAt: number;
  lastLoginAt: number;
}

interface CharacterState extends Character {
  stats: Stats;
  inventory: InventorySlot[];
  cooldowns: Cooldown[];
  buffs: Buff[];
  questLog: Quest[];
}
```

### 3. World Service (Zone Management)

_Requirements: 4, 7, 8_

**Responsibilities:**
- Manage zone processes (start, stop, checkpoint)
- Generate zone snapshots on player entry
- Stream delta updates (state diffs)
- Persist checkpoints + event logs
- Manage Area of Interest (AOI) per player

**Interfaces:**
```typescript
interface WorldService {
  enterZone(characterId: string, zoneId: string): Promise<ZoneEntryResponse>;
  getZoneSnapshot(zoneId: string, aoiSeed: Vector3): Promise<ZoneSnapshot>;
  subscribeToDeltas(zoneId: string, playerId: string): AsyncIterator<ZoneDelta>;
  persistCheckpoint(zoneId: string, state: ZoneState): Promise<void>;
  restoreZone(zoneId: string): Promise<ZoneState>;
}

interface ZoneEntryResponse {
  shardId: string;
  zoneId: string;
  spawnPosition: Vector3;
  handoffToken?: string; // null for normal entry
}

interface ZoneSnapshot {
  zoneTime: number;
  terrainChunks: string[]; // chunk IDs, not full data
  entities: EntitySnapshot[];
  aoiSeed: Vector3;
  activeEffects: GlobalEffect[];
  compressedBlob: Uint8Array; // Deflate-compressed
  version: number;
}

interface ZoneDelta {
  timestamp: number;
  version: number;
  entityUpdates: EntityUpdate[];
  entityAdds: EntitySnapshot[];
  entityRemoves: string[]; // entity IDs
}
```

### 4. Movement & Combat Service

_Requirements: 5, 6_

**Responsibilities:**
- Validate movement intents (physics, collision, speed)
- Process ability usage (cooldowns, costs, range, LoS)
- Calculate damage, healing, critical hits
- Broadcast authoritative state at 10-20 Hz
- Send corrections to clients when prediction drifts

**Interfaces:**
```typescript
interface MovementCombatService {
  processMoveIntent(playerId: string, intent: MoveIntent): Promise<MoveResult>;
  useAbility(playerId: string, ability: AbilityIntent): Promise<AbilityResult>;
  calculateDamage(ability: Ability, source: Entity, target: Entity): DamageResult;
  broadcastState(zoneId: string, updates: EntityUpdate[]): void;
}

interface MoveIntent {
  direction: Vector2;
  timestamp: number;
  nonce: number;
}

interface MoveResult {
  ack: boolean;
  correction?: Vector3; // if client prediction was wrong
  nonce: number;
}

interface AbilityIntent {
  abilityId: string;
  targetId: string;
  timestamp: number;
  nonce: number;
}

interface AbilityResult {
  success: boolean;
  damage?: number;
  healing?: number;
  criticalHit: boolean;
  cooldownTriggered: number;
  errorCode?: string;
}
```

### 5. Instance Service

_Requirements: 9, 10_

**Responsibilities:**
- Create match instances from templates
- Validate party requirements (size, level, items)
- Manage instance lifecycle (entry, exit, completion)
- Handle rejoin grace period for disconnects
- Persist rewards atomically on completion

**Interfaces:**
```typescript
interface InstanceService {
  enterInstance(templateId: string, partyId: string): Promise<InstanceEntry>;
  exitInstance(matchId: string, playerId: string): Promise<WorldAnchor>;
  completeInstance(matchId: string, results: InstanceResults): Promise<void>;
  rejoinInstance(matchId: string, playerId: string): Promise<InstanceState>;
}

interface InstanceEntry {
  matchId: string;
  entryAnchor: Vector3;
  snapshot: ZoneSnapshot;
}

interface WorldAnchor {
  zoneId: string;
  position: Vector3;
}

interface InstanceResults {
  completed: boolean;
  rewards: Reward[];
  partyMembers: string[];
}
```

### 6. Social Service

_Requirements: 11, 12, 13_

**Responsibilities:**
- Guild CRUD operations
- Rank/permission management
- Chat channel subscription/broadcast
- Direct messaging
- Moderation (mute, kick, ban)

**Interfaces:**
```typescript
interface SocialService {
  createGuild(name: string, masterId: string): Promise<GuildId>;
  setGuildRank(guildId: string, memberId: string, rank: number): Promise<void>;
  sendMessage(channelId: string, senderId: string, message: string): Promise<void>;
  sendDirectMessage(recipientId: string, senderId: string, message: string): Promise<void>;
  moderatePlayer(moderatorId: string, targetId: string, action: ModAction): Promise<void>;
}

interface ModAction {
  type: 'mute' | 'kick' | 'ban';
  channelId: string;
  reason: string;
  duration?: number; // seconds, null = permanent
}
```

### 7. Economy Service

_Requirements: 14, 15, 16, 17_

**Responsibilities:**
- Transactional inventory operations
- Player-to-player trading (2PC)
- Vendor buy/sell
- Loot generation from drop tables
- Item UID enforcement

**Interfaces:**
```typescript
interface EconomyService {
  moveInventoryItem(characterId: string, itemUid: string, src: SlotId, dst: SlotId, qty: number): Promise<void>;
  openTrade(initiatorId: string, targetId: string): Promise<TradeSession>;
  commitTrade(tradeId: string): Promise<void>;
  buyFromVendor(characterId: string, vendorId: string, itemId: string, qty: number): Promise<void>;
  generateLoot(dropTableId: string, context: LootContext): Promise<Item[]>;
}

interface TradeSession {
  tradeId: string;
  participants: [string, string];
  items: [Item[], Item[]];
  locked: boolean;
  expiresAt: number;
}

interface LootContext {
  entityId: string;
  killedBy: string[];
  seed: number;
}
```

### 8. Handoff Service

_Requirements: 18, 19_

**Responsibilities:**
- Issue handoff tokens for cross-region/shard transfers
- Validate handoff_finalize requests
- Lock inventory/combat during transfer
- Rollback to safe anchor on failure

**Interfaces:**
```typescript
interface HandoffService {
  requestHandoff(playerId: string, targetZoneId: string): Promise<HandoffToken>;
  finalizeHandoff(token: string, playerId: string): Promise<HandoffResult>;
  rollbackHandoff(token: string): Promise<void>;
}

interface HandoffToken {
  token: string;
  fromZone: string;
  toZone: string;
  endpoint: Endpoint;
  expiresAt: number;
}

interface Endpoint {
  host: string;
  port: number;
  protocol: 'ws' | 'wss';
}

interface HandoffResult {
  success: boolean;
  newZoneState: ZoneSnapshot;
  errorCode?: string;
}
```

### 9. Live-Ops Service

_Requirements: 20, 21, 22, 23_

**Responsibilities:**
- GM console commands (spawn, despawn, modify entities)
- World parameter tweaking (drop rates, buffs)
- Event scheduling (cron-based)
- Hot-load scripts (Lua/TS) with validation
- Audit logging for all GM actions

**Interfaces:**
```typescript
interface LiveOpsService {
  executeGMCommand(gmId: string, command: GMCommand): Promise<GMResult>;
  setWorldParameter(gmId: string, parameter: WorldParameter): Promise<void>;
  scheduleEvent(gmId: string, schedule: EventSchedule): Promise<ScheduleId>;
  uploadScript(gmId: string, script: ScriptPack): Promise<ScriptId>;
  previewEvent(gmId: string, scheduleId: string): Promise<EventPreview>;
}

interface GMCommand {
  type: 'spawn' | 'despawn' | 'modify' | 'broadcast';
  zoneId: string;
  entityId?: string;
  params: Record<string, any>;
}

interface WorldParameter {
  key: string; // e.g., "drop_table.goblin.gold_multiplier"
  value: any;
  duration?: number; // null = permanent
}

interface EventSchedule {
  cronExpr: string;
  scriptId: string;
  params: Record<string, any>;
  enabled: boolean;
}
```

### 10. Commerce Service

_Requirements: 24, 25, 26, 27_

**Responsibilities:**
- Serve store catalog
- Verify platform purchase receipts
- Grant/revoke entitlements
- Manage wallets (soft currency)
- Audit all transactions

**Interfaces:**
```typescript
interface CommerceService {
  getCatalog(region: string): Promise<CatalogItem[]>;
  verifyPurchase(platform: Platform, receipt: string): Promise<PurchaseResult>;
  grantEntitlement(accountId: string, sku: string, meta: EntitlementMeta): Promise<void>;
  revokeEntitlement(accountId: string, entitlementId: string): Promise<void>;
  creditWallet(accountId: string, currency: string, amount: number, source: string): Promise<void>;
  debitWallet(accountId: string, currency: string, amount: number, reason: string): Promise<void>;
}

interface PurchaseResult {
  valid: boolean;
  sku: string;
  entitlements: Entitlement[];
  receiptId: string;
}

interface Entitlement {
  entitlementId: string;
  accountId: string;
  sku: string;
  state: 'active' | 'expired' | 'revoked';
  purchaseDate: number;
  metadata: Record<string, any>;
}
```

---

## Data Models

### Database Schema

_Requirements: 1-33_

**Accounts Table**
```sql
CREATE TABLE accounts (
  account_id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE,
  device_id VARCHAR(255),
  platform_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  permissions TEXT[], -- ['player', 'gm', 'admin']
  banned BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_device ON accounts(device_id);
```

**Characters Table**
```sql
CREATE TABLE characters (
  character_id UUID PRIMARY KEY,
  account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
  name VARCHAR(50) NOT NULL,
  archetype_id VARCHAR(50) NOT NULL,
  level INT DEFAULT 1,
  last_zone_id VARCHAR(100),
  last_position JSONB, -- {x, y, z}
  stats JSONB, -- {hp, mp, str, dex, int, ...}
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  version INT DEFAULT 1, -- for optimistic locking
  CONSTRAINT unique_character_name UNIQUE(name)
);

CREATE INDEX idx_characters_account ON characters(account_id);
CREATE INDEX idx_characters_name ON characters(name);
```

**Inventory Table**
```sql
CREATE TABLE inventory (
  item_uid UUID PRIMARY KEY,
  character_id UUID REFERENCES characters(character_id) ON DELETE CASCADE,
  item_id VARCHAR(100) NOT NULL, -- references item templates
  slot_id VARCHAR(50), -- 'backpack_0', 'equipped_weapon', etc.
  quantity INT DEFAULT 1,
  durability INT,
  metadata JSONB, -- enchantments, sockets, etc.
  version INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_inventory_character ON inventory(character_id);
CREATE UNIQUE INDEX idx_inventory_slot ON inventory(character_id, slot_id);
```

**World State Table**
```sql
CREATE TABLE world_state (
  zone_id VARCHAR(100) PRIMARY KEY,
  shard_id VARCHAR(50) NOT NULL,
  state_json JSONB NOT NULL, -- full zone state snapshot
  version BIGINT DEFAULT 1,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  checkpoint_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_world_state_shard ON world_state(shard_id);
```

**Event Log Table** (for crash recovery)
```sql
CREATE TABLE event_log (
  event_id BIGSERIAL PRIMARY KEY,
  zone_id VARCHAR(100) NOT NULL,
  event_type VARCHAR(50) NOT NULL, -- 'entity_move', 'entity_spawn', 'loot_drop', etc.
  event_data JSONB NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_event_log_zone_time ON event_log(zone_id, timestamp);
```

**Guilds Table**
```sql
CREATE TABLE guilds (
  guild_id UUID PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  master_id UUID REFERENCES characters(character_id) ON DELETE SET NULL,
  motd TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  storage JSONB -- shared guild inventory
);

CREATE INDEX idx_guilds_name ON guilds(name);
```

**Guild Members Table**
```sql
CREATE TABLE guild_members (
  guild_id UUID REFERENCES guilds(guild_id) ON DELETE CASCADE,
  character_id UUID REFERENCES characters(character_id) ON DELETE CASCADE,
  rank INT DEFAULT 0, -- 0 = member, 1 = officer, 2 = master
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (guild_id, character_id)
);

CREATE INDEX idx_guild_members_character ON guild_members(character_id);
```

**Trade Sessions Table**
```sql
CREATE TABLE trade_sessions (
  trade_id UUID PRIMARY KEY,
  participant_1 UUID REFERENCES characters(character_id) ON DELETE CASCADE,
  participant_2 UUID REFERENCES characters(character_id) ON DELETE CASCADE,
  items_1 JSONB, -- array of {item_uid, quantity}
  items_2 JSONB,
  locked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

CREATE INDEX idx_trade_sessions_participants ON trade_sessions(participant_1, participant_2);
```

**Zone Boundaries Table**
```sql
CREATE TABLE zone_boundaries (
  zone_id VARCHAR(100) PRIMARY KEY,
  neighbors JSONB, -- array of {zone_id, boundary_trigger_box}
  default_spawn JSONB -- {x, y, z} for new characters
);
```

**Handoff Tokens Table**
```sql
CREATE TABLE handoff_tokens (
  token UUID PRIMARY KEY,
  player_id UUID REFERENCES characters(character_id) ON DELETE CASCADE,
  from_zone VARCHAR(100),
  to_zone VARCHAR(100),
  endpoint JSONB, -- {host, port, protocol}
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_handoff_tokens_player ON handoff_tokens(player_id);
CREATE INDEX idx_handoff_tokens_expires ON handoff_tokens(expires_at);
```

**Event Schedules Table**
```sql
CREATE TABLE event_schedules (
  schedule_id UUID PRIMARY KEY,
  cron_expr VARCHAR(100) NOT NULL,
  script_id VARCHAR(100) NOT NULL,
  params JSONB,
  enabled BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES accounts(account_id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_event_schedules_enabled ON event_schedules(enabled);
```

**Audit Logs Table**
```sql
CREATE TABLE audit_logs (
  log_id BIGSERIAL PRIMARY KEY,
  actor_id UUID, -- account_id or character_id
  action VARCHAR(100) NOT NULL, -- 'gm_spawn', 'purchase', 'trade_commit', etc.
  target_id VARCHAR(255),
  metadata JSONB,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_actor_time ON audit_logs(actor_id, timestamp);
CREATE INDEX idx_audit_logs_action_time ON audit_logs(action, timestamp);
```

**Catalog Table**
```sql
CREATE TABLE catalog (
  sku VARCHAR(100) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  price_usd DECIMAL(10, 2),
  preview_url TEXT,
  entitlements JSONB, -- array of {type, itemId, quantity}
  regions TEXT[], -- ['us', 'eu', 'asia'], null = all regions
  available_from TIMESTAMPTZ,
  available_until TIMESTAMPTZ,
  stock_limit INT -- null = unlimited
);

CREATE INDEX idx_catalog_regions ON catalog USING GIN(regions);
```

**Entitlements Table**
```sql
CREATE TABLE entitlements (
  entitlement_id UUID PRIMARY KEY,
  account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
  sku VARCHAR(100) REFERENCES catalog(sku),
  state VARCHAR(20) DEFAULT 'active', -- 'active', 'expired', 'revoked'
  purchase_date TIMESTAMPTZ DEFAULT NOW(),
  receipt_id VARCHAR(255),
  metadata JSONB
);

CREATE INDEX idx_entitlements_account ON entitlements(account_id);
CREATE INDEX idx_entitlements_state ON entitlements(state);
```

**Wallets Table**
```sql
CREATE TABLE wallets (
  account_id UUID PRIMARY KEY REFERENCES accounts(account_id) ON DELETE CASCADE,
  balances JSONB, -- {gold: 1000, gems: 50, event_tokens: 10}
  version INT DEFAULT 1 -- for optimistic locking
);
```

**Wallet Transactions Table**
```sql
CREATE TABLE wallet_transactions (
  transaction_id BIGSERIAL PRIMARY KEY,
  account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
  currency VARCHAR(50) NOT NULL,
  amount BIGINT NOT NULL, -- can be negative for debits
  balance_after BIGINT NOT NULL,
  source VARCHAR(100), -- 'quest_reward', 'vendor_sell', 'purchase', etc.
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_wallet_txn_account_time ON wallet_transactions(account_id, timestamp);
```

---

## API Contracts

### RPC Endpoints

_Requirements: All_

All RPCs use JSON payloads and return structured responses with error codes.

#### Authentication & Characters

```typescript
// List characters
rpc.list_characters(): Promise<{ characters: Character[] }>

// Create character
rpc.create_character(name: string, archetype_id: string): Promise<{ character_id: string }>

// Select character
rpc.select_character(character_id: string): Promise<{ ok: boolean }>

// Delete character
rpc.delete_character(character_id: string): Promise<{ ok: boolean }>
```

#### World Entry & State

```typescript
// Enter world
rpc.world_enter(character_id: string): Promise<{
  shard_id: string;
  zone_id: string;
  spawn: Vector3;
  handoff?: null;
}>

// Get zone snapshot
rpc.zone_snapshot(zone_id: string, aoi_seed: Vector3): Promise<{
  snapshot_blob: string; // base64-encoded compressed snapshot
  version: number;
}>

// Subscribe to zone deltas (stream)
stream.zone_deltas(zone_id: string): AsyncIterator<{
  diffs: ZoneDelta[];
}>
```

#### Movement & Combat

```typescript
// Send movement intent
rpc.move_intent(dir: Vector2, ts: number, nonce: number): Promise<{
  ack: boolean;
  correction?: Vector3;
}>

// Use ability
rpc.use_ability(ability_id: string, target_id: string, ts: number, nonce: number): Promise<{
  result: 'success' | 'fail';
  damage?: number;
  healing?: number;
  critical_hit: boolean;
  error_code?: string;
}>
```

#### Instances

```typescript
// Enter instance
rpc.instance_enter(template_id: string, party_id: string): Promise<{
  match_id: string;
  entry_anchor: Vector3;
}>

// Exit instance
rpc.instance_exit(match_id: string): Promise<{
  world_anchor: Vector3;
}>
```

#### Social

```typescript
// Create guild
rpc.guild_create(name: string): Promise<{ guild_id: string }>

// Set guild rank
rpc.guild_set_rank(guild_id: string, member_id: string, rank: number): Promise<{ ok: boolean }>

// Send chat message
rpc.chat_send(channel_id: string, message: string): Promise<{ ok: boolean }>

// Moderate player
rpc.moderate_player(target_id: string, action: ModAction): Promise<{ ok: boolean }>
```

#### Economy

```typescript
// Move inventory item
rpc.inventory_move(item_uid: string, src: string, dst: string, qty: number): Promise<{ ok: boolean }>

// Open trade
rpc.trade_open(target_char_id: string): Promise<{ trade_id: string }>

// Commit trade
rpc.trade_commit(trade_id: string): Promise<{ ok: boolean }>

// Buy from vendor
rpc.vendor_buy(vendor_id: string, item_id: string, qty: number): Promise<{ ok: boolean }>

// Sell to vendor
rpc.vendor_sell(vendor_id: string, item_uid: string): Promise<{ gold: number }>
```

#### Handoff

```typescript
// Request handoff
rpc.handoff_request(target_zone_id: string): Promise<{
  handoff_token: string;
  endpoint: Endpoint;
  timeout_ms: number;
}>

// Finalize handoff
rpc.handoff_finalize(token: string): Promise<{ ok: boolean }>
```

#### Live-Ops (GM Only)

```typescript
// Execute GM command
rpc.gm_exec(script_id: string, args: Record<string, any>): Promise<{ result: any }>

// Schedule event
rpc.event_schedule(action: 'create' | 'update' | 'delete', payload: EventSchedule): Promise<{ ok: boolean }>
```

#### Commerce

```typescript
// Get store catalog
rpc.store_catalog(): Promise<{ items: CatalogItem[] }>

// Verify purchase
rpc.purchase_verify(platform: string, receipt: string): Promise<{
  ok: boolean;
  entitlements: Entitlement[];
}>
```

---

## Runtime Modules

### Module Structure

All runtime modules are organized under `data/modules/`:

```
data/modules/
├── character/
│   ├── list.ts
│   ├── create.ts
│   └── select.ts
├── world/
│   ├── enter.ts
│   ├── snapshot.ts
│   ├── delta_stream.ts
│   └── zone_tick.ts
├── combat/
│   ├── move_intent.ts
│   ├── use_ability.ts
│   └── damage_calc.ts
├── social/
│   ├── guild.ts
│   ├── chat.ts
│   └── moderation.ts
├── economy/
│   ├── inventory.ts
│   ├── trading.ts
│   └── vendor.ts
├── instance/
│   ├── enter.ts
│   ├── exit.ts
│   └── lifecycle.ts
├── handoff/
│   ├── request.ts
│   └── finalize.ts
├── liveops/
│   ├── gm_commands.ts
│   ├── event_scheduler.ts
│   └── script_loader.ts
└── commerce/
    ├── catalog.ts
    ├── purchase.ts
    └── entitlements.ts
```

### Module Registration

Each module registers its RPC handlers in `main.go`:

```go
// Example: Register character module RPCs
initializer.RegisterRpc("list_characters", modules.ListCharactersRPC)
initializer.RegisterRpc("create_character", modules.CreateCharacterRPC)
initializer.RegisterRpc("select_character", modules.SelectCharacterRPC)
```

### TypeScript Module Example

```typescript
// data/modules/character/list.ts

import { nkruntime } from '@heroiclabs/nakama-runtime';

function listCharactersRPC(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  const accountId = ctx.userId;

  // Query characters table
  const result = nk.sqlQuery(`
    SELECT character_id, name, archetype_id, level, last_zone_id, last_position, last_login_at
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
  `, [accountId]);

  const characters = result.map(row => ({
    character_id: row.character_id,
    name: row.name,
    archetype_id: row.archetype_id,
    level: row.level,
    last_zone_id: row.last_zone_id,
    last_position: JSON.parse(row.last_position),
    last_login_at: row.last_login_at
  }));

  return JSON.stringify({ characters });
}
```

---

## Client Integration

### Godot 4 SDK Integration

_Requirements: 2, 3, 4, 5, 6, 18_

**Project Structure:**
```
godot_project/
├── autoload/
│   ├── NakamaManager.gd
│   └── WorldState.gd
├── scenes/
│   ├── auth/
│   │   ├── LoginScreen.tscn
│   │   └── CharacterSelect.tscn
│   ├── world/
│   │   ├── Zone.tscn
│   │   └── Player.tscn
│   └── ui/
│       ├── ChatPanel.tscn
│       └── InventoryUI.tscn
└── scripts/
    ├── prediction/
    │   ├── ClientPrediction.gd
    │   └── Reconciliation.gd
    └── networking/
        ├── SnapshotApplier.gd
        └── DeltaProcessor.gd
```

**NakamaManager Singleton:**
```gdscript
# autoload/NakamaManager.gd
extends Node

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

func _ready() -> void:
    client = Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")

func authenticate_device() -> void:
    session = await client.authenticate_device_async(OS.get_unique_id(), null, true)
    socket = Nakama.create_socket_from(client)
    await socket.connect_async(session, true, 30)
    print("Authenticated: ", session.user_id)

func list_characters() -> Array:
    var response = await client.rpc_async(session, "list_characters", "{}")
    return JSON.parse_string(response.payload)["characters"]

func create_character(name: String, archetype_id: int) -> String:
    var payload = JSON.stringify({"name": name, "archetype_id": archetype_id})
    var response = await client.rpc_async(session, "create_character", payload)
    return JSON.parse_string(response.payload)["character_id"]

func enter_world(character_id: String) -> void:
    var payload = JSON.stringify({"character_id": character_id})
    var response = await client.rpc_async(session, "world_enter", payload)
    var data = JSON.parse_string(response.payload)
    await join_zone(data["zone_id"])

func join_zone(zone_id: String) -> void:
    # Get snapshot
    var snap_payload = JSON.stringify({"zone_id": zone_id, "aoi_seed": [0, 0, 0]})
    var snap_response = await client.rpc_async(session, "zone_snapshot", snap_payload)
    var snapshot_blob = JSON.parse_string(snap_response.payload)["snapshot_blob"]

    # Apply snapshot
    WorldState.apply_snapshot(snapshot_blob)

    # Subscribe to deltas
    socket.connect("received_stream_state", Callable(self, "_on_zone_delta"))
    await socket.join_stream_async("zone", zone_id)

func _on_zone_delta(mode: int, stream_id: String, subject: String, data: PackedByteArray, receive_time: int) -> void:
    var diff = JSON.parse_string(data.get_string_from_utf8())
    WorldState.apply_diffs(diff)
```

**Snapshot Application:**
```gdscript
# autoload/WorldState.gd
extends Node

var entities: Dictionary = {} # entity_id -> Entity node

func apply_snapshot(blob_base64: String) -> void:
    var compressed_data = Marshalls.base64_to_raw(blob_base64)
    var json_data = compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
    var snapshot = JSON.parse_string(json_data.get_string_from_utf8())

    get_tree().paused = true
    clear_world()

    for entity_data in snapshot["entities"]:
        spawn_entity(entity_data)

    get_tree().paused = false

func clear_world() -> void:
    for entity in entities.values():
        entity.queue_free()
    entities.clear()

func spawn_entity(data: Dictionary) -> void:
    var entity_scene = load("res://scenes/world/Entity.tscn")
    var entity = entity_scene.instantiate()
    entity.entity_id = data["id"]
    entity.position = Vector3(data["transform"][0], data["transform"][1], data["transform"][2])
    entity.vitals = data["vitals"]
    get_tree().root.add_child(entity)
    entities[data["id"]] = entity

func apply_diffs(diffs: Dictionary) -> void:
    for update in diffs.get("entityUpdates", []):
        if entities.has(update["id"]):
            entities[update["id"]].apply_update(update)

    for add in diffs.get("entityAdds", []):
        spawn_entity(add)

    for remove_id in diffs.get("entityRemoves", []):
        if entities.has(remove_id):
            entities[remove_id].queue_free()
            entities.erase(remove_id)
```

**Client-Side Prediction:**
```gdscript
# scripts/prediction/ClientPrediction.gd
extends Node

var pending_moves: Array = []
var last_ack_nonce: int = 0

func predict_move(direction: Vector2) -> void:
    var nonce = Time.get_ticks_msec()
    var move = {"direction": direction, "nonce": nonce, "timestamp": Time.get_ticks_msec()}
    pending_moves.append(move)

    # Apply locally
    Player.position += Vector3(direction.x, 0, direction.y) * Player.speed * get_process_delta_time()

    # Send to server
    send_move_intent(direction, move["timestamp"], nonce)

func send_move_intent(dir: Vector2, ts: int, nonce: int) -> void:
    var payload = JSON.stringify({"dir": [dir.x, dir.y], "ts": ts, "nonce": nonce})
    var response = await NakamaManager.client.rpc_async(NakamaManager.session, "move_intent", payload)
    var result = JSON.parse_string(response.payload)

    if result.has("correction"):
        reconcile(result["correction"], result["nonce"])

    # Clear acked moves
    pending_moves = pending_moves.filter(func(m): return m["nonce"] > result["nonce"])

func reconcile(correction: Array, ack_nonce: int) -> void:
    # Server says we're at a different position
    Player.position = Vector3(correction[0], correction[1], correction[2])

    # Replay un-acked moves
    for move in pending_moves:
        if move["nonce"] > ack_nonce:
            Player.position += Vector3(move["direction"].x, 0, move["direction"].y) * Player.speed * 0.016 # assume 60fps
```

**Handoff Handling:**
```gdscript
# scripts/networking/Handoff.gd
extends Node

func request_handoff(to_zone: String) -> void:
    var payload = JSON.stringify({"target_zone_id": to_zone})
    var response = await NakamaManager.client.rpc_async(NakamaManager.session, "handoff_request", payload)
    var data = JSON.parse_string(response.payload)

    var token = data["handoff_token"]
    var endpoint = data["endpoint"]

    # Show transition UI (portal effect)
    UI.show_portal_transition()

    # Pre-connect to new zone
    var new_client = Nakama.create_client("defaultkey", endpoint["host"], endpoint["port"], endpoint["scheme"])
    var new_socket = Nakama.create_socket_from(new_client)
    await new_socket.connect_async(NakamaManager.session, true, 10)

    # Finalize handoff
    var finalize_payload = JSON.stringify({"token": token})
    var finalize_response = await new_client.rpc_async(NakamaManager.session, "handoff_finalize", finalize_payload)

    if JSON.parse_string(finalize_response.payload)["ok"]:
        # Swap sockets
        NakamaManager.socket.close()
        NakamaManager.socket = new_socket
        NakamaManager.client = new_client
        UI.hide_portal_transition()
    else:
        # Rollback - stay in current zone
        UI.show_error("Handoff failed, please try again")
```

---

## Persistence Strategy

### Checkpoint + Event Log Pattern

_Requirements: 7_

**Goal:** Achieve RPO ≤5s, RTO ≤5min for zone crashes.

**Mechanism:**
1. **Checkpoints**: Full zone state snapshots written to `world_state` table every 10 seconds
2. **Event Log**: Append-only log of all state-changing events written to `event_log` table in real-time
3. **Recovery**: On zone restart, load last checkpoint + replay events since checkpoint timestamp

**Zone Tick Loop:**
```typescript
class ZoneProcess {
  private state: ZoneState;
  private lastCheckpointTime: number = 0;
  private checkpointInterval: number = 10000; // 10 seconds

  async tick(deltaMs: number): Promise<void> {
    // Update entities, NPC AI, resource nodes
    this.updateEntities(deltaMs);

    // Log all state-changing events
    for (const event of this.pendingEvents) {
      await this.logEvent(event);
    }
    this.pendingEvents = [];

    // Checkpoint if interval elapsed
    if (Date.now() - this.lastCheckpointTime > this.checkpointInterval) {
      await this.saveCheckpoint();
      this.lastCheckpointTime = Date.now();
    }
  }

  async logEvent(event: ZoneEvent): Promise<void> {
    await nk.sqlExec(`
      INSERT INTO event_log (zone_id, event_type, event_data)
      VALUES ($1, $2, $3)
    `, [this.zoneId, event.type, JSON.stringify(event.data)]);
  }

  async saveCheckpoint(): Promise<void> {
    await nk.sqlExec(`
      UPDATE world_state
      SET state_json = $1, version = version + 1, checkpoint_at = NOW()
      WHERE zone_id = $2
    `, [JSON.stringify(this.state), this.zoneId]);
  }

  async restore(): Promise<void> {
    // Load last checkpoint
    const checkpoint = await nk.sqlQuery(`
      SELECT state_json, checkpoint_at
      FROM world_state
      WHERE zone_id = $1
    `, [this.zoneId]);

    this.state = JSON.parse(checkpoint[0].state_json);
    const checkpointTime = checkpoint[0].checkpoint_at;

    // Replay events since checkpoint
    const events = await nk.sqlQuery(`
      SELECT event_type, event_data
      FROM event_log
      WHERE zone_id = $1 AND timestamp > $2
      ORDER BY event_id ASC
    `, [this.zoneId, checkpointTime]);

    for (const event of events) {
      this.applyEvent(event.event_type, JSON.parse(event.event_data));
    }
  }
}
```

---

## Scalability & Performance

### Horizontal Scaling

_Requirements: 31, 32_

**Stateless API Layer:**
- Multiple Nakama server instances behind load balancer
- Session state stored in database (JWT for authentication)
- No sticky sessions required

**Sharded Zones:**
- Each zone process runs on a specific shard (server instance)
- Zone assignment via consistent hashing or manual allocation
- Cross-shard handoffs via handoff tokens

**Database Sharding:**
- Characters/inventory sharded by `account_id`
- World state sharded by `zone_id`
- Social data (guilds, chat) sharded by `guild_id`

**Performance Targets:**
```typescript
// Zone tick budget
const TICK_RATE = 20; // Hz
const TICK_BUDGET_MS = 10; // p95

// Database writes
const DB_WRITE_LATENCY_MS = 30; // p95

// Snapshot generation
const SNAPSHOT_SIZE_LIMIT_KB = 512;
const SNAPSHOT_APPLY_TIME_MS = 50;

// Handoff duration
const HANDOFF_DURATION_MS = 1000;
```

### AOI Optimization

_Requirements: 8_

Use spatial grid for entity culling:

```typescript
class SpatialGrid {
  private cellSize: number = 50; // meters
  private cells: Map<string, Set<string>> = new Map(); // cell_key -> entity_ids

  getCellKey(pos: Vector3): string {
    const x = Math.floor(pos.x / this.cellSize);
    const z = Math.floor(pos.z / this.cellSize);
    return `${x},${z}`;
  }

  getVisibleEntities(playerPos: Vector3, radius: number): string[] {
    const cellRadius = Math.ceil(radius / this.cellSize);
    const centerCell = this.getCellKey(playerPos);
    const [cx, cz] = centerCell.split(',').map(Number);

    const visible = new Set<string>();
    for (let dx = -cellRadius; dx <= cellRadius; dx++) {
      for (let dz = -cellRadius; dz <= cellRadius; dz++) {
        const key = `${cx + dx},${cz + dz}`;
        const entities = this.cells.get(key) || new Set();
        entities.forEach(id => visible.add(id));
      }
    }
    return Array.from(visible);
  }
}
```

---

## Security & Validation

### Rate Limiting

_Requirements: 1_

Per-account rate limits for all RPCs:

```typescript
const RATE_LIMITS = {
  'move_intent': { requests: 30, window: 1000 }, // 30/sec
  'use_ability': { requests: 10, window: 1000 }, // 10/sec
  'chat_send': { requests: 5, window: 1000 },    // 5/sec
  'purchase_verify': { requests: 1, window: 60000 } // 1/min
};

function enforceRateLimit(accountId: string, rpcName: string): boolean {
  const limit = RATE_LIMITS[rpcName];
  const key = `ratelimit:${accountId}:${rpcName}`;

  const count = cache.get(key) || 0;
  if (count >= limit.requests) {
    return false; // rate limit exceeded
  }

  cache.set(key, count + 1, limit.window);
  return true;
}
```

### Server-Side Validation

_Requirements: 5, 6, 14, 15_

All gameplay-critical operations validated:

```typescript
function validateAbilityUse(ability: Ability, source: Entity, target: Entity): ValidationResult {
  // Check cooldown
  if (source.cooldowns[ability.id] > Date.now()) {
    return { valid: false, error: 'ABILITY_ON_COOLDOWN' };
  }

  // Check resource cost
  if (source.stats.mp < ability.cost) {
    return { valid: false, error: 'INSUFFICIENT_MANA' };
  }

  // Check range
  const distance = Vector3.distance(source.position, target.position);
  if (distance > ability.range) {
    return { valid: false, error: 'OUT_OF_RANGE' };
  }

  // Check line of sight
  if (!hasLineOfSight(source.position, target.position)) {
    return { valid: false, error: 'NO_LINE_OF_SIGHT' };
  }

  return { valid: true };
}
```

### Transaction Integrity

_Requirements: 14, 15, 27_

Use optimistic locking for inventory/wallet operations:

```typescript
async function moveInventoryItem(characterId: string, itemUid: string, src: string, dst: string): Promise<void> {
  // Start transaction
  await nk.sqlExec('BEGIN');

  try {
    // Lock character row
    const char = await nk.sqlQuery(`
      SELECT version FROM characters WHERE character_id = $1 FOR UPDATE
    `, [characterId]);

    // Validate source slot has item
    const srcItem = await nk.sqlQuery(`
      SELECT * FROM inventory WHERE character_id = $1 AND slot_id = $2 AND item_uid = $3
    `, [characterId, src, itemUid]);

    if (srcItem.length === 0) {
      throw new Error('ITEM_NOT_IN_SOURCE_SLOT');
    }

    // Check destination slot
    const dstItem = await nk.sqlQuery(`
      SELECT * FROM inventory WHERE character_id = $1 AND slot_id = $2
    `, [characterId, dst]);

    if (dstItem.length > 0) {
      throw new Error('DESTINATION_SLOT_OCCUPIED');
    }

    // Move item
    await nk.sqlExec(`
      UPDATE inventory SET slot_id = $1 WHERE item_uid = $2
    `, [dst, itemUid]);

    // Increment character version
    await nk.sqlExec(`
      UPDATE characters SET version = version + 1 WHERE character_id = $1
    `, [characterId]);

    await nk.sqlExec('COMMIT');
  } catch (error) {
    await nk.sqlExec('ROLLBACK');
    throw error;
  }
}
```

---

## Deployment Architecture

### Kubernetes Deployment

_Requirements: 32, 33_

**Namespace**: `nakama-mmorpg`

**Deployments:**
1. **nakama-api** (stateless, auto-scaling)
   - 3+ replicas
   - HPA: CPU > 70% → scale up
   - Rolling updates, max surge 1, max unavailable 0

2. **nakama-zones** (stateful, manual scaling)
   - 1 replica per zone shard
   - StatefulSet with persistent volumes for checkpoints
   - Crash recovery via init container

3. **postgres** (StatefulSet)
   - Primary + read replicas
   - PVC for data persistence

**Services:**
- `nakama-api-service` (LoadBalancer, external)
- `nakama-zones-service` (ClusterIP, internal)
- `postgres-service` (ClusterIP, internal)

**ConfigMaps:**
- `nakama-config` (server config, rate limits, tick rates)
- `zone-config` (zone definitions, spawn points, boundaries)

**Secrets:**
- `nakama-secrets` (JWT keys, DB credentials, platform API keys)

**Canary Deployment:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nakama-api-canary
spec:
  selector:
    app: nakama-api
    version: canary
  ports:
  - protocol: TCP
    port: 7350
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nakama-ingress
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10" # 10% traffic to canary
spec:
  rules:
  - host: api.mmorpg.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nakama-api-canary
            port:
              number: 7350
```

---

## Testing Strategy

### Unit Tests

_Requirements: All_

- Test each RPC handler in isolation
- Mock database calls with fixtures
- Validate input parsing, error handling, business logic

Example:
```typescript
// tests/character/create.test.ts
describe('create_character', () => {
  it('should create character with valid input', async () => {
    const result = await createCharacterRPC(mockContext, mockLogger, mockNk, JSON.stringify({
      name: 'TestHero',
      archetype_id: 'warrior'
    }));

    const data = JSON.parse(result);
    expect(data.character_id).toBeDefined();
  });

  it('should reject duplicate character names', async () => {
    mockNk.sqlQuery.mockReturnValueOnce([{ name: 'TestHero' }]); // name taken

    await expect(createCharacterRPC(...)).rejects.toThrow('CHARACTER_NAME_TAKEN');
  });
});
```

### Integration Tests

- Test full RPC flows (auth → list → create → enter world)
- Use test database with migrations applied
- Verify database state after operations

### Load Tests

_Requirements: 31_

- Simulate 50k CCU per shard
- Measure: p95 latency, tick time, DB query time
- Tools: k6, Locust, custom Godot bots

Example k6 script:
```javascript
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  vus: 50000,
  duration: '10m',
};

export default function() {
  // Simulate player movement
  const payload = JSON.stringify({ dir: [1, 0], ts: Date.now(), nonce: Math.random() });
  const res = http.post('https://api.mmorpg.example.com/v2/rpc/move_intent', payload);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 150ms': (r) => r.timings.duration < 150,
  });
}
```

### Chaos Tests

_Requirements: 33_

- Randomly kill zone processes
- Verify recovery within RTO (≤5 min)
- Verify data loss ≤ RPO (≤5s)

Tool: Chaos Mesh on Kubernetes

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- Database schema migrations
- Authentication service
- Character service (list, create, select)
- Basic Godot client (auth, character select)

### Phase 2: World Entry (Weeks 3-4)
- World service (zone entry, snapshots)
- Zone tick loop with checkpoints
- Godot snapshot application
- Delta streaming

### Phase 3: Movement & Combat (Weeks 5-6)
- Movement validation
- Client-side prediction + reconciliation
- Ability system
- Combat calculations

### Phase 4: Social & Economy (Weeks 7-8)
- Guild system
- Chat channels
- Inventory transactions
- Trading (2PC)
- Vendor system

### Phase 5: Instances (Week 9)
- Instance templates
- Entry/exit flow
- Rejoin grace period

### Phase 6: Handoffs (Week 10)
- Handoff tokens
- Cross-region transfers
- Failure recovery

### Phase 7: Live-Ops & Commerce (Weeks 11-12)
- GM console
- Event scheduler
- Script hot-loading
- Store catalog
- Purchase verification

### Phase 8: Ops & Scale (Weeks 13-14)
- Metrics & dashboards
- Blue/green deployment
- Load testing
- Chaos testing

---

## Next Steps

1. Review and approve this design document
2. Generate implementation tasks in `tasks.md`
3. Begin Phase 1 implementation

---

**Design approved?** If yes, I'll generate the detailed `tasks.md` file to begin implementation.
