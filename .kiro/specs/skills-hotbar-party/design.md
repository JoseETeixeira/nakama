# Technical Design: Skills, Hotbar, and Party Systems

## Document Information

- **Feature Name:** Skills, Hotbar, and Party Systems
- **Version:** 1.0
- **Date:** October 28, 2025
- **Status:** In Design
- **Requirements Reference:** `.kiro/specs/skills-hotbar-party/requirements.md`
- **Parent Spec:** MMORPG-grade Nakama with Godot 4 Integration

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Components](#system-components)
3. [Data Models](#data-models)
4. [API Contracts](#api-contracts)
5. [Runtime Modules](#runtime-modules)
6. [State Management](#state-management)
7. [Performance Optimization](#performance-optimization)
8. [Security & Validation](#security--validation)
9. [Integration Points](#integration-points)
10. [Client SDK Examples](#client-sdk-examples)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Godot 4 Clients                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Skill Bar UI                                            │  │
│  │  - Hotbar Slots (Skills, Items, Macros)                 │  │
│  │  - Cooldown Overlays                                     │  │
│  │  - Skill Tree Visualization                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Party UI                                                │  │
│  │  - Member List (HP/MP bars)                             │  │
│  │  - Party Chat                                            │  │
│  │  - Loot Roll Windows                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          │                  │                  │
          │  RPC Calls       │  State Updates   │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Nakama Server Cluster                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Skills Module (TypeScript/Lua)                         │  │
│  │  - Skill Learning/Validation                            │  │
│  │  - Cooldown Tracking                                     │  │
│  │  - Skill Effect Application                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Hotbar Module (TypeScript/Lua)                         │  │
│  │  - Slot Assignment/Activation                           │  │
│  │  - Macro Parsing/Execution                              │  │
│  │  - Persistent Configuration                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Party Module (TypeScript/Lua)                          │  │
│  │  - Party Formation/Management                            │  │
│  │  - Loot Distribution                                     │  │
│  │  - Shared Objectives Sync                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  In-Memory State Cache                                   │  │
│  │  - Active Cooldowns (per character)                     │  │
│  │  - Party Rosters (per party_id)                         │  │
│  │  - Skill Buffs/Debuffs                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PostgreSQL Database                         │
│  - character_skills (learned skills, levels)                   │
│  - character_hotbars (slot configurations)                      │
│  - parties (party state, loot mode, leader)                     │
│  - party_members (membership roster)                            │
│  - skill_configs (templates, stats, requirements)               │
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

_Requirements: 1-12_

1. **Server Authority**: All skill usage, hotbar activation, and party actions validated server-side (Req 3, 5)
2. **Low-Latency State**: In-memory cooldowns and party rosters for ≤50ms response times (Req 3, Performance)
3. **Persistent Configuration**: Hotbar and skill state persist across sessions with optimistic locking (Req 6)
4. **Fair Loot Distribution**: Server-enforced loot modes prevent theft/exploits (Req 10, Security)
5. **Godot-First Integration**: SDK examples for skill bars, party UI, and macro systems (Req 1-12)
6. **Graceful Degradation**: Cached state survives temporary DB outages; retry logic for persistence failures (Reliability)

---

## System Components

### 1. Skills Service

_Requirements: 1, 2, 3_

**Responsibilities:**
- Manage skill learning, leveling, and validation
- Track cooldowns and resource costs in-memory
- Apply skill effects (damage, healing, buffs) via combat system integration
- Persist learned skills and levels to database

**Interfaces:**
```typescript
interface SkillsService {
  // Skill Learning (Req 1)
  getAvailableSkills(characterId: string, archetypeId: string): Promise<SkillTemplate[]>;
  learnSkill(characterId: string, skillId: string, trainerId?: string): Promise<LearnResult>;

  // Skill Leveling (Req 2)
  upgradeSkill(characterId: string, skillId: string, cost: CurrencyCost): Promise<UpgradeResult>;
  addSkillExperience(characterId: string, skillId: string, exp: number): Promise<LevelUpResult | null>;

  // Skill Validation (Req 3)
  validateSkillUse(characterId: string, skillId: string, targetId: string, position: Vector3): Promise<ValidationResult>;
  activateSkill(characterId: string, skillId: string, targetId: string): Promise<SkillResult>;

  // Cooldown Management
  getCooldowns(characterId: string): Map<string, number>; // skill_id -> remaining_ms
  triggerCooldown(characterId: string, skillId: string, duration: number): void;

  // State Queries
  getLearnedSkills(characterId: string): Promise<CharacterSkill[]>;
  getSkillTemplate(skillId: string): SkillTemplate;
}

interface SkillTemplate {
  skillId: string;
  name: string;
  archetypeId: string;
  unlockLevel: number;
  prerequisiteSkills: string[]; // skill_ids
  maxLevel: number;
  baseCooldown: number; // milliseconds
  resourceCost: { type: 'mana' | 'energy' | 'rage'; amount: number };
  castTime: number; // milliseconds, 0 = instant
  range: number; // meters
  targetType: 'self' | 'ally' | 'enemy' | 'ground';
  effectsPerLevel: SkillEffect[]; // damage, healing, duration scale by level
  currencyCost: CurrencyCost; // cost to learn
}

interface CharacterSkill {
  characterId: string;
  skillId: string;
  level: number;
  experience: number;
  learnedAt: number; // timestamp
}

interface LearnResult {
  success: boolean;
  skillId?: string;
  error?: 'INSUFFICIENT_LEVEL' | 'MISSING_PREREQUISITE' | 'INSUFFICIENT_CURRENCY' | 'ALREADY_LEARNED';
}

interface ValidationResult {
  valid: boolean;
  error?: 'SKILL_NOT_LEARNED' | 'COOLDOWN_ACTIVE' | 'INSUFFICIENT_RESOURCE' | 'OUT_OF_RANGE' | 'INVALID_TARGET' | 'CASTING';
  remainingCooldown?: number; // milliseconds
}

interface SkillResult {
  success: boolean;
  damage?: number;
  healing?: number;
  buffsApplied: Buff[];
  cooldownTriggered: number;
  resourceConsumed: number;
}
```

### 2. Hotbar Service

_Requirements: 4, 5, 6_

**Responsibilities:**
- Manage hotbar slot assignments (skills, items, macros)
- Validate hotbar activations and route to appropriate systems
- Parse and execute macro commands
- Persist hotbar configurations with optimistic locking

**Interfaces:**
```typescript
interface HotbarService {
  // Slot Assignment (Req 4)
  assignSlot(characterId: string, barIndex: number, slotIndex: number, content: HotbarContent): Promise<AssignResult>;
  swapSlots(characterId: string, slot1: SlotCoord, slot2: SlotCoord): Promise<void>;
  clearSlot(characterId: string, barIndex: number, slotIndex: number): Promise<void>;

  // Slot Activation (Req 5)
  activateSlot(characterId: string, barIndex: number, slotIndex: number, targetId?: string): Promise<ActivationResult>;

  // Configuration Management (Req 6)
  getHotbarConfig(characterId: string): Promise<HotbarConfig>;
  saveHotbarConfig(characterId: string, config: HotbarConfig, version: number): Promise<SaveResult>;

  // Macro Parsing
  validateMacro(macroText: string): MacroValidation;
  executeMacro(characterId: string, macroText: string, context: MacroContext): Promise<MacroResult>;
}

interface HotbarContent {
  type: 'skill' | 'item' | 'macro' | 'empty';
  skillId?: string;
  itemId?: string;
  macroText?: string;
}

interface SlotCoord {
  barIndex: number; // 0-2 for 3 bars
  slotIndex: number; // 0-11 for 12 slots per bar
}

interface HotbarConfig {
  characterId: string;
  bars: HotbarBar[]; // array of 3 bars
  version: number; // for optimistic locking
  updatedAt: number;
}

interface HotbarBar {
  barIndex: number;
  slots: HotbarContent[]; // array of 12 slots
}

interface ActivationResult {
  success: boolean;
  type: 'skill' | 'item' | 'macro';
  skillResult?: SkillResult;
  itemResult?: ItemUseResult;
  macroResult?: MacroResult;
  error?: 'EMPTY_SLOT' | 'SKILL_FAILED' | 'ITEM_NOT_FOUND' | 'MACRO_ERROR';
}

interface MacroValidation {
  valid: boolean;
  commands: MacroCommand[];
  errors: string[];
}

interface MacroCommand {
  type: 'cast' | 'use' | 'target' | 'wait';
  skillId?: string;
  itemId?: string;
  targetType?: 'self' | 'target' | 'focus';
  delay?: number;
}

interface MacroResult {
  executed: MacroCommand[];
  failed: MacroCommand[];
  totalDuration: number; // milliseconds
}
```

### 3. Party Service

_Requirements: 7, 8, 9, 10, 11, 12_

**Responsibilities:**
- Manage party creation, invitations, and membership
- Maintain in-memory party rosters for low-latency updates
- Implement loot distribution algorithms (round-robin, need/greed, master looter)
- Coordinate instance entry for all party members
- Synchronize shared quest objectives

**Interfaces:**
```typescript
interface PartyService {
  // Party Creation & Invitations (Req 7)
  createParty(leaderId: string): Promise<PartyId>;
  invitePlayer(partyId: string, inviterId: string, targetId: string): Promise<InviteResult>;
  acceptInvite(partyId: string, playerId: string): Promise<JoinResult>;
  declineInvite(partyId: string, playerId: string): Promise<void>;

  // Membership Management (Req 8)
  kickMember(partyId: string, leaderId: string, targetId: string): Promise<KickResult>;
  leaveParty(partyId: string, playerId: string): Promise<void>;
  promoteLeader(partyId: string, currentLeaderId: string, newLeaderId: string): Promise<void>;

  // Party Configuration
  setLootMode(partyId: string, leaderId: string, mode: LootMode): Promise<void>;
  getPartyState(partyId: string): Promise<PartyState>;

  // Loot Distribution (Req 10)
  distributeLoot(partyId: string, loot: Item[], sourceEntityId: string): Promise<LootDistribution>;
  rollNeed(partyId: string, playerId: string, lootId: string): Promise<RollResult>;
  rollGreed(partyId: string, playerId: string, lootId: string): Promise<RollResult>;
  passLoot(partyId: string, playerId: string, lootId: string): Promise<void>;

  // Instance Entry (Req 11)
  initiateInstanceEntry(partyId: string, leaderId: string, templateId: string): Promise<InstanceEntryResult>;

  // Shared Objectives (Req 12)
  shareQuest(partyId: string, playerId: string, questId: string): Promise<ShareResult>;
  syncObjectiveProgress(partyId: string, questId: string, objectiveId: string, progress: number): Promise<void>;
}

interface PartyState {
  partyId: string;
  leaderId: string;
  members: PartyMember[];
  lootMode: LootMode;
  createdAt: number;
  inInstance: boolean;
  sharedQuests: string[]; // quest_ids
}

interface PartyMember {
  characterId: string;
  name: string;
  level: number;
  archetypeId: string;
  hp: number;
  maxHp: number;
  mp: number;
  maxMp: number;
  joinedAt: number;
}

type LootMode = 'round-robin' | 'need-before-greed' | 'master-looter' | 'free-for-all';

interface LootDistribution {
  assignments: Map<string, Item[]>; // character_id -> items
  pendingRolls: PendingRoll[]; // for need/greed mode
}

interface PendingRoll {
  lootId: string;
  item: Item;
  rolls: Map<string, { type: 'need' | 'greed' | 'pass'; value: number }>;
  expiresAt: number;
}

interface InstanceEntryResult {
  success: boolean;
  matchId?: string;
  failedMembers?: { characterId: string; reason: string }[];
}
```

---

## Data Models

### Database Schema

_Requirements: 1-12_

**Character Skills Table**
```sql
CREATE TABLE character_skills (
  character_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  skill_id VARCHAR(100) NOT NULL, -- references skill_configs
  level INT DEFAULT 1,
  experience INT DEFAULT 0,
  learned_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (character_id, skill_id)
);

CREATE INDEX idx_character_skills_character ON character_skills(character_id);
```

**Character Hotbars Table**
```sql
CREATE TABLE character_hotbars (
  character_id UUID PRIMARY KEY REFERENCES characters(character_id) ON DELETE CASCADE,
  config JSONB NOT NULL, -- HotbarConfig structure
  version INT DEFAULT 1, -- optimistic locking
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Skill Configurations Table** (game data)
```sql
CREATE TABLE skill_configs (
  skill_id VARCHAR(100) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  archetype_id VARCHAR(50) NOT NULL,
  unlock_level INT DEFAULT 1,
  prerequisite_skills JSONB, -- array of skill_ids
  max_level INT DEFAULT 5,
  base_cooldown INT NOT NULL, -- milliseconds
  resource_cost JSONB NOT NULL, -- {type, amount}
  cast_time INT DEFAULT 0, -- milliseconds
  range DECIMAL(10, 2) DEFAULT 0, -- meters
  target_type VARCHAR(20) NOT NULL, -- 'self', 'ally', 'enemy', 'ground'
  effects_per_level JSONB NOT NULL, -- array of effects by level
  currency_cost JSONB, -- cost to learn
  icon_url VARCHAR(255)
);

CREATE INDEX idx_skill_configs_archetype ON skill_configs(archetype_id);
```

**Parties Table**
```sql
CREATE TABLE parties (
  party_id UUID PRIMARY KEY,
  leader_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  loot_mode VARCHAR(20) DEFAULT 'round-robin', -- 'round-robin', 'need-before-greed', 'master-looter', 'free-for-all'
  loot_round_robin_index INT DEFAULT 0, -- for round-robin distribution
  created_at TIMESTAMPTZ DEFAULT NOW(),
  in_instance BOOLEAN DEFAULT FALSE,
  instance_match_id UUID -- references match instances
);

CREATE INDEX idx_parties_leader ON parties(leader_id);
```

**Party Members Table**
```sql
CREATE TABLE party_members (
  party_id UUID NOT NULL REFERENCES parties(party_id) ON DELETE CASCADE,
  character_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (party_id, character_id)
);

CREATE INDEX idx_party_members_character ON party_members(character_id);
```

**Party Invitations Table** (ephemeral, cleaned up periodically)
```sql
CREATE TABLE party_invitations (
  invite_id UUID PRIMARY KEY,
  party_id UUID NOT NULL REFERENCES parties(party_id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  invitee_id UUID NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL -- default NOW() + 60 seconds
);

CREATE INDEX idx_party_invitations_invitee ON party_invitations(invitee_id);
CREATE INDEX idx_party_invitations_expires ON party_invitations(expires_at);
```

### In-Memory State

**Cooldown Cache**
```typescript
// Per-character cooldown tracking (in-memory only, ephemeral)
interface CooldownState {
  characterId: string;
  cooldowns: Map<string, CooldownEntry>; // skill_id -> CooldownEntry
}

interface CooldownEntry {
  skillId: string;
  triggeredAt: number; // timestamp
  duration: number; // milliseconds
  expiresAt: number; // timestamp
}
```

**Party Cache**
```typescript
// In-memory party roster for low-latency updates
interface PartyCacheEntry {
  partyId: string;
  state: PartyState;
  lastUpdated: number;
  pendingRolls: Map<string, PendingRoll>; // loot_id -> PendingRoll
}
```

---

## API Contracts

### RPC Endpoints

_Requirements: All_

All RPCs use JSON payloads and return structured responses with error codes.

#### Skills API

```typescript
// Get available skills for learning (Req 1)
rpc.skills_get_available(archetype_id: string): Promise<{
  skills: SkillTemplate[];
}>

// Learn a skill (Req 1)
rpc.skills_learn(skill_id: string, trainer_id?: string): Promise<{
  success: boolean;
  error?: string;
  skill?: CharacterSkill;
}>

// Upgrade skill level (Req 2)
rpc.skills_upgrade(skill_id: string): Promise<{
  success: boolean;
  new_level?: number;
  error?: string;
}>

// Get learned skills
rpc.skills_list(): Promise<{
  skills: CharacterSkill[];
}>

// Activate skill (Req 3, 5)
rpc.skills_activate(skill_id: string, target_id: string, position?: Vector3): Promise<{
  success: boolean;
  result?: SkillResult;
  error?: string;
  remaining_cooldown?: number;
}>

// Get active cooldowns
rpc.skills_get_cooldowns(): Promise<{
  cooldowns: Map<string, number>; // skill_id -> remaining_ms
}>
```

#### Hotbar API

```typescript
// Assign slot (Req 4)
rpc.hotbar_assign_slot(bar_index: number, slot_index: number, content: HotbarContent): Promise<{
  success: boolean;
  version: number;
}>

// Swap slots (Req 4)
rpc.hotbar_swap_slots(slot1: SlotCoord, slot2: SlotCoord): Promise<{
  success: boolean;
  version: number;
}>

// Activate slot (Req 5)
rpc.hotbar_activate(bar_index: number, slot_index: number, target_id?: string): Promise<{
  success: boolean;
  result: ActivationResult;
}>

// Get hotbar configuration (Req 6)
rpc.hotbar_get_config(): Promise<{
  config: HotbarConfig;
}>

// Validate macro
rpc.hotbar_validate_macro(macro_text: string): Promise<{
  valid: boolean;
  commands: MacroCommand[];
  errors: string[];
}>
```

#### Party API

```typescript
// Create party (Req 7)
rpc.party_create(): Promise<{
  party_id: string;
}>

// Invite player (Req 7)
rpc.party_invite(target_name: string): Promise<{
  success: boolean;
  invite_id?: string;
  error?: string;
}>

// Accept/decline invite (Req 7)
rpc.party_accept_invite(invite_id: string): Promise<{
  success: boolean;
  party_state?: PartyState;
}>

rpc.party_decline_invite(invite_id: string): Promise<{
  success: boolean;
}>

// Kick member (Req 8)
rpc.party_kick(character_id: string): Promise<{
  success: boolean;
  error?: string;
}>

// Leave party (Req 8)
rpc.party_leave(): Promise<{
  success: boolean;
}>

// Promote leader (Req 8)
rpc.party_promote_leader(character_id: string): Promise<{
  success: boolean;
}>

// Set loot mode (Req 10)
rpc.party_set_loot_mode(mode: LootMode): Promise<{
  success: boolean;
}>

// Loot rolling (Req 10)
rpc.party_roll_need(loot_id: string): Promise<{
  roll_value: number;
}>

rpc.party_roll_greed(loot_id: string): Promise<{
  roll_value: number;
}>

rpc.party_pass_loot(loot_id: string): Promise<{
  success: boolean;
}>

// Initiate instance entry (Req 11)
rpc.party_enter_instance(template_id: string): Promise<{
  success: boolean;
  match_id?: string;
  failed_members?: { character_id: string; reason: string }[];
}>

// Share quest (Req 12)
rpc.party_share_quest(quest_id: string): Promise<{
  success: boolean;
  shared_with: string[]; // character_ids
}>
```

### Real-time Notifications

```typescript
// Skill cooldown updates (broadcast to client)
notification.skill_cooldown_triggered {
  skill_id: string;
  duration: number;
  expires_at: number;
}

notification.skill_cooldown_ready {
  skill_id: string;
}

// Party updates (broadcast to all party members)
notification.party_member_joined {
  party_id: string;
  member: PartyMember;
}

notification.party_member_left {
  party_id: string;
  character_id: string;
}

notification.party_leader_changed {
  party_id: string;
  new_leader_id: string;
}

notification.party_loot_mode_changed {
  party_id: string;
  new_mode: LootMode;
}

notification.party_loot_roll_request {
  loot_id: string;
  item: Item;
  expires_at: number;
}

notification.party_loot_awarded {
  loot_id: string;
  winner_id: string;
  item: Item;
}

notification.party_member_hp_update {
  character_id: string;
  hp: number;
  max_hp: number;
}

notification.party_objective_progress {
  quest_id: string;
  objective_id: string;
  progress: number;
  max_progress: number;
}
```

---

## Runtime Modules

### Skills Module (`data/modules/skills/`)

**File Structure:**
```
data/modules/skills/
├── skills_service.ts         # Main skills service implementation
├── cooldown_manager.ts        # In-memory cooldown tracking
├── skill_validator.ts         # Validation logic (req, cooldown, range, LoS)
├── skill_effects.ts           # Effect application (damage, healing, buffs)
└── skill_configs_loader.ts    # Load skill templates from DB/config
```

**Key Functions:**

```typescript
// skills_service.ts
export function learnSkill(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: { character_id: string; skill_id: string; trainer_id?: string }
): LearnResult {
  // 1. Load skill template
  const template = loadSkillTemplate(nk, payload.skill_id);

  // 2. Load character data
  const character = loadCharacter(nk, payload.character_id);

  // 3. Validate requirements
  if (character.level < template.unlockLevel) {
    return { success: false, error: 'INSUFFICIENT_LEVEL' };
  }

  // 4. Check prerequisites
  const learnedSkills = getLearnedSkills(nk, payload.character_id);
  for (const prereq of template.prerequisiteSkills) {
    if (!learnedSkills.has(prereq)) {
      return { success: false, error: 'MISSING_PREREQUISITE' };
    }
  }

  // 5. Deduct currency
  const wallet = getWallet(nk, character.account_id);
  if (!deductCurrency(nk, wallet, template.currencyCost)) {
    return { success: false, error: 'INSUFFICIENT_CURRENCY' };
  }

  // 6. Persist skill
  const skill: CharacterSkill = {
    character_id: payload.character_id,
    skill_id: payload.skill_id,
    level: 1,
    experience: 0,
    learned_at: Date.now()
  };

  nk.sqlExec(`
    INSERT INTO character_skills (character_id, skill_id, level, experience, learned_at)
    VALUES ($1, $2, $3, $4, $5)
  `, [skill.character_id, skill.skill_id, skill.level, skill.experience, new Date(skill.learned_at)]);

  return { success: true, skill };
}

// cooldown_manager.ts
const activeCooldowns = new Map<string, Map<string, CooldownEntry>>();

export function triggerCooldown(characterId: string, skillId: string, duration: number): void {
  if (!activeCooldowns.has(characterId)) {
    activeCooldowns.set(characterId, new Map());
  }

  const now = Date.now();
  activeCooldowns.get(characterId).set(skillId, {
    skillId,
    triggeredAt: now,
    duration,
    expiresAt: now + duration
  });

  // Set timeout to clean up expired cooldown
  setTimeout(() => {
    const cdMap = activeCooldowns.get(characterId);
    if (cdMap) {
      cdMap.delete(skillId);
      if (cdMap.size === 0) {
        activeCooldowns.delete(characterId);
      }
    }
  }, duration);
}

export function getCooldownRemaining(characterId: string, skillId: string): number {
  const cdMap = activeCooldowns.get(characterId);
  if (!cdMap) return 0;

  const cd = cdMap.get(skillId);
  if (!cd) return 0;

  const remaining = cd.expiresAt - Date.now();
  return Math.max(0, remaining);
}

// skill_validator.ts
export function validateSkillUse(
  nk: nkruntime.Nakama,
  characterId: string,
  skillId: string,
  targetId: string,
  position: Vector3
): ValidationResult {
  // 1. Check if skill is learned
  const learned = isSkillLearned(nk, characterId, skillId);
  if (!learned) {
    return { valid: false, error: 'SKILL_NOT_LEARNED' };
  }

  // 2. Check cooldown
  const cooldownRemaining = getCooldownRemaining(characterId, skillId);
  if (cooldownRemaining > 0) {
    return { valid: false, error: 'COOLDOWN_ACTIVE', remainingCooldown: cooldownRemaining };
  }

  // 3. Load skill template and character state
  const template = loadSkillTemplate(nk, skillId);
  const character = loadCharacterState(nk, characterId);

  // 4. Check resource cost
  const resourceType = template.resourceCost.type;
  const resourceAmount = character.resources[resourceType] || 0;
  if (resourceAmount < template.resourceCost.amount) {
    return { valid: false, error: 'INSUFFICIENT_RESOURCE' };
  }

  // 5. Check range (if target-based)
  if (template.targetType !== 'self') {
    const target = loadEntityState(nk, targetId);
    const distance = calculateDistance(character.position, target.position);
    if (distance > template.range) {
      return { valid: false, error: 'OUT_OF_RANGE' };
    }
  }

  // 6. Check line of sight (future enhancement)
  // const hasLoS = checkLineOfSight(character.position, target.position);

  return { valid: true };
}
```

### Hotbar Module (`data/modules/hotbar/`)

**File Structure:**
```
data/modules/hotbar/
├── hotbar_service.ts          # Main hotbar service
├── macro_parser.ts            # Macro validation and parsing
├── macro_executor.ts          # Macro command execution
└── hotbar_persistence.ts      # DB persistence with optimistic locking
```

**Key Functions:**

```typescript
// hotbar_service.ts
export function assignSlot(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: { bar_index: number; slot_index: number; content: HotbarContent }
): AssignResult {
  const characterId = ctx.userId;

  // 1. Validate content
  if (payload.content.type === 'skill') {
    const learned = isSkillLearned(nk, characterId, payload.content.skillId);
    if (!learned) {
      return { success: false, error: 'SKILL_NOT_LEARNED' };
    }
  } else if (payload.content.type === 'item') {
    const hasItem = hasInventoryItem(nk, characterId, payload.content.itemId);
    if (!hasItem) {
      return { success: false, error: 'ITEM_NOT_FOUND' };
    }
  } else if (payload.content.type === 'macro') {
    const validation = validateMacro(payload.content.macroText);
    if (!validation.valid) {
      return { success: false, error: 'INVALID_MACRO', details: validation.errors };
    }
  }

  // 2. Load hotbar config with optimistic lock
  const config = loadHotbarConfig(nk, characterId);

  // 3. Update slot
  config.bars[payload.bar_index].slots[payload.slot_index] = payload.content;
  config.version++;
  config.updatedAt = Date.now();

  // 4. Persist with version check
  const saved = saveHotbarConfig(nk, characterId, config);
  if (!saved) {
    return { success: false, error: 'VERSION_CONFLICT' };
  }

  return { success: true, version: config.version };
}

export function activateSlot(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: { bar_index: number; slot_index: number; target_id?: string }
): ActivationResult {
  const characterId = ctx.userId;

  // 1. Load hotbar config
  const config = loadHotbarConfig(nk, characterId);
  const content = config.bars[payload.bar_index].slots[payload.slot_index];

  if (content.type === 'empty') {
    return { success: false, error: 'EMPTY_SLOT' };
  }

  // 2. Route to appropriate system
  if (content.type === 'skill') {
    const skillResult = activateSkill(nk, characterId, content.skillId, payload.target_id);
    return { success: skillResult.success, type: 'skill', skillResult };
  } else if (content.type === 'item') {
    const itemResult = useItem(nk, characterId, content.itemId);
    return { success: itemResult.success, type: 'item', itemResult };
  } else if (content.type === 'macro') {
    const macroResult = executeMacro(nk, characterId, content.macroText);
    return { success: true, type: 'macro', macroResult };
  }
}

// macro_parser.ts
export function validateMacro(macroText: string): MacroValidation {
  const lines = macroText.split(';').map(l => l.trim()).filter(l => l.length > 0);
  const commands: MacroCommand[] = [];
  const errors: string[] = [];

  for (const line of lines) {
    if (line.startsWith('/cast ')) {
      const skillName = line.substring(6).trim();
      commands.push({ type: 'cast', skillId: skillName });
    } else if (line.startsWith('/use ')) {
      const itemName = line.substring(5).trim();
      commands.push({ type: 'use', itemId: itemName });
    } else if (line.startsWith('/target ')) {
      const targetType = line.substring(8).trim() as 'self' | 'target' | 'focus';
      commands.push({ type: 'target', targetType });
    } else if (line.startsWith('/wait ')) {
      const delay = parseInt(line.substring(6).trim());
      if (isNaN(delay) || delay < 0 || delay > 5000) {
        errors.push(`Invalid wait duration: ${line}`);
      } else {
        commands.push({ type: 'wait', delay });
      }
    } else {
      errors.push(`Unknown command: ${line}`);
    }
  }

  return { valid: errors.length === 0, commands, errors };
}
```

### Party Module (`data/modules/party/`)

**File Structure:**
```
data/modules/party/
├── party_service.ts           # Main party service
├── party_cache.ts             # In-memory party roster cache
├── loot_distributor.ts        # Loot distribution algorithms
├── party_invitations.ts       # Invitation management
└── shared_objectives.ts       # Quest sync logic
```

**Key Functions:**

```typescript
// party_service.ts
export function createParty(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama
): { party_id: string } {
  const leaderId = ctx.userId;
  const partyId = nk.uuidv4();

  // 1. Create party in database
  nk.sqlExec(`
    INSERT INTO parties (party_id, leader_id, loot_mode, created_at)
    VALUES ($1, $2, 'round-robin', NOW())
  `, [partyId, leaderId]);

  // 2. Add leader as first member
  nk.sqlExec(`
    INSERT INTO party_members (party_id, character_id, joined_at)
    VALUES ($1, $2, NOW())
  `, [partyId, leaderId]);

  // 3. Cache party state
  const state = loadPartyState(nk, partyId);
  cachePartyState(partyId, state);

  // 4. Subscribe leader to party chat channel
  subscribeToPartyChat(nk, partyId, leaderId);

  return { party_id: partyId };
}

export function invitePlayer(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: { party_id: string; target_name: string }
): InviteResult {
  const inviterId = ctx.userId;

  // 1. Verify inviter is party leader
  const party = loadPartyState(nk, payload.party_id);
  if (party.leaderId !== inviterId) {
    return { success: false, error: 'NOT_PARTY_LEADER' };
  }

  // 2. Find target character
  const target = findCharacterByName(nk, payload.target_name);
  if (!target) {
    return { success: false, error: 'CHARACTER_NOT_FOUND' };
  }

  // 3. Check if target is already in a party
  const targetParty = getCharacterParty(nk, target.character_id);
  if (targetParty) {
    return { success: false, error: 'ALREADY_IN_PARTY' };
  }

  // 4. Create invitation
  const inviteId = nk.uuidv4();
  const expiresAt = new Date(Date.now() + 60000); // 60 seconds

  nk.sqlExec(`
    INSERT INTO party_invitations (invite_id, party_id, inviter_id, invitee_id, created_at, expires_at)
    VALUES ($1, $2, $3, $4, NOW(), $5)
  `, [inviteId, payload.party_id, inviterId, target.character_id, expiresAt]);

  // 5. Send notification to target
  sendPartyInviteNotification(nk, target.character_id, {
    invite_id: inviteId,
    party_id: payload.party_id,
    inviter_name: getCharacterName(nk, inviterId),
    party_size: party.members.length
  });

  return { success: true, invite_id: inviteId };
}

// loot_distributor.ts
export function distributeLoot(
  nk: nkruntime.Nakama,
  partyId: string,
  loot: Item[],
  sourceEntityId: string
): LootDistribution {
  const party = loadPartyState(nk, partyId);

  if (party.lootMode === 'round-robin') {
    return distributeRoundRobin(nk, party, loot);
  } else if (party.lootMode === 'need-before-greed') {
    return distributeNeedGreed(nk, party, loot);
  } else if (party.lootMode === 'master-looter') {
    return distributeMasterLooter(nk, party, loot);
  } else {
    return distributeFreeForAll(nk, party, loot);
  }
}

function distributeRoundRobin(
  nk: nkruntime.Nakama,
  party: PartyState,
  loot: Item[]
): LootDistribution {
  const assignments = new Map<string, Item[]>();

  // Load current round-robin index from DB
  const result = nk.sqlQuery(`
    SELECT loot_round_robin_index FROM parties WHERE party_id = $1
  `, [party.partyId]);

  let index = result[0].loot_round_robin_index || 0;

  // Assign loot in rotation
  for (const item of loot) {
    const memberId = party.members[index % party.members.length].characterId;
    if (!assignments.has(memberId)) {
      assignments.set(memberId, []);
    }
    assignments.get(memberId).push(item);
    index++;
  }

  // Update index in DB
  nk.sqlExec(`
    UPDATE parties SET loot_round_robin_index = $1 WHERE party_id = $2
  `, [index, party.partyId]);

  return { assignments, pendingRolls: [] };
}

function distributeNeedGreed(
  nk: nkruntime.Nakama,
  party: PartyState,
  loot: Item[]
): LootDistribution {
  const pendingRolls: PendingRoll[] = [];

  // Create pending rolls for each item
  for (const item of loot) {
    const lootId = nk.uuidv4();
    pendingRolls.push({
      lootId,
      item,
      rolls: new Map(),
      expiresAt: Date.now() + 30000 // 30 seconds to roll
    });

    // Broadcast roll request to all members
    for (const member of party.members) {
      sendLootRollRequest(nk, member.characterId, { lootId, item, expiresAt: Date.now() + 30000 });
    }
  }

  // Cache pending rolls
  cachePartyPendingRolls(party.partyId, pendingRolls);

  return { assignments: new Map(), pendingRolls };
}
```

---

## State Management

### Cooldown State (In-Memory)

- **Storage**: `Map<character_id, Map<skill_id, CooldownEntry>>`
- **Lifecycle**: Created on skill activation, auto-cleaned on expiration
- **Recovery**: Not persisted; cooldowns default to ready after server restart
- **Optimization**: O(1) lookups for cooldown validation

### Party State (Hybrid)

- **In-Memory Cache**: `Map<party_id, PartyCacheEntry>`
  - Fast reads for party roster, loot mode, pending rolls
  - Updated on membership changes, broadcasts to all members
  - TTL: 5 minutes of inactivity (auto-evict)

- **Database Persistence**: `parties` and `party_members` tables
  - Single source of truth for party state
  - Loaded on cache miss or server restart
  - Updated on leadership changes, loot mode changes, disbanding

### Hotbar State (Database + Cache)

- **Database**: `character_hotbars` table with JSONB config
  - Optimistic locking with `version` column
  - Persisted immediately on slot assignment changes

- **Client Cache**: Client maintains local copy of hotbar config
  - Updated on server confirmation after slot changes
  - Validated against server state on character login

---

## Performance Optimization

### Skill Activation Latency

_Target: ≤50ms p95_

**Strategies:**
1. **In-Memory Cooldowns**: No DB reads for cooldown validation
2. **Skill Template Caching**: Load skill configs once, cache in memory (LRU, max 1000 entries)
3. **Batch Broadcasts**: Combine skill result + cooldown trigger + entity update into single broadcast
4. **Async Persistence**: Skill XP gains written asynchronously (eventual consistency acceptable)

**Implementation:**
```typescript
// Cached skill template loader
const skillTemplateCache = new LRU<string, SkillTemplate>({ max: 1000 });

function loadSkillTemplate(nk: nkruntime.Nakama, skillId: string): SkillTemplate {
  if (skillTemplateCache.has(skillId)) {
    return skillTemplateCache.get(skillId);
  }

  const result = nk.sqlQuery(`SELECT * FROM skill_configs WHERE skill_id = $1`, [skillId]);
  const template = parseSkillTemplate(result[0]);
  skillTemplateCache.set(skillId, template);
  return template;
}
```

### Hotbar Persistence Latency

_Target: ≤30ms p95 (existing DB target)_

**Strategies:**
1. **Single Row Update**: Entire hotbar config stored as JSONB in one row (no joins)
2. **Optimistic Locking**: Version check prevents long locks
3. **Connection Pooling**: Reuse DB connections for low overhead
4. **Retry Logic**: Exponential backoff on version conflicts

**Implementation:**
```typescript
function saveHotbarConfig(nk: nkruntime.Nakama, characterId: string, config: HotbarConfig): boolean {
  const result = nk.sqlExec(`
    UPDATE character_hotbars
    SET config = $1, version = $2, updated_at = NOW()
    WHERE character_id = $3 AND version = $4
  `, [JSON.stringify(config), config.version, characterId, config.version - 1]);

  return result.rowsAffected === 1;
}
```

### Party Update Broadcast Latency

_Target: ≤100ms p95_

**Strategies:**
1. **In-Memory Roster**: Party state cached in memory, no DB reads for broadcasts
2. **Presence Tracking**: Maintain online member list to skip offline players
3. **Delta Updates**: Broadcast only changes (member joined/left, HP update), not full state
4. **Presence Channels**: Use Nakama presence system for real-time member tracking

---

## Security & Validation

### Server-Side Validation Rules

_Requirements: 3, 5, Security NFRs_

**Skill Activation:**
1. ✅ Verify skill is learned (DB query)
2. ✅ Check cooldown status (in-memory)
3. ✅ Validate resource costs (character state)
4. ✅ Verify target validity (entity exists, in range, not dead)
5. ✅ Check line of sight (spatial query)
6. ✅ Prevent spam (rate limit: max 10 skill activations per second per character)

**Hotbar Assignment:**
1. ✅ Validate skill ownership (DB query)
2. ✅ Validate item existence (inventory query)
3. ✅ Validate macro syntax (parser)
4. ✅ Prevent slot overflow (bar_index ∈ [0, 2], slot_index ∈ [0, 11])

**Party Actions:**
1. ✅ Verify leadership (party state check)
2. ✅ Validate member count (max 5 players)
3. ✅ Prevent duplicate invitations (DB unique constraint)
4. ✅ Validate loot roll eligibility (member of party, loot not expired)

### Anti-Cheat Measures

**Cooldown Manipulation Prevention:**
- Cooldowns stored server-side only (no client trust)
- Timestamp validation on skill activation (reject stale requests)
- Nonce-based replay attack prevention

**Item Duplication Prevention:**
- Hotbar slots reference item UIDs (not item templates)
- Item usage validates inventory ownership before activation
- Atomic inventory transactions (optimistic locking)

**Loot Theft Prevention:**
- Loot mode enforced server-side (no client override)
- Need/greed rolls use server-side RNG (seeded, non-predictable)
- Master looter verified as party leader before distribution

---

## Integration Points

### Combat System Integration

_Requirements: 3, 5_

**Skill Effect Application:**
```typescript
// After skill validation, apply effects via combat system
function applySkillEffects(
  nk: nkruntime.Nakama,
  skillResult: SkillResult,
  sourceId: string,
  targetId: string
): void {
  // Delegate to combat module (from main spec, Requirement 6)
  if (skillResult.damage > 0) {
    applyDamage(nk, targetId, skillResult.damage, sourceId);
  }

  if (skillResult.healing > 0) {
    applyHealing(nk, targetId, skillResult.healing, sourceId);
  }

  for (const buff of skillResult.buffsApplied) {
    applyBuff(nk, targetId, buff);
  }

  // Broadcast combat result to AOI
  broadcastCombatEvent(nk, sourceId, targetId, skillResult);
}
```

### Inventory System Integration

_Requirements: 5, 14 (main spec)_

**Item Usage from Hotbar:**
```typescript
function useItem(nk: nkruntime.Nakama, characterId: string, itemId: string): ItemUseResult {
  // 1. Validate item ownership via inventory system
  const inventoryItem = getInventoryItemByTemplateId(nk, characterId, itemId);
  if (!inventoryItem) {
    return { success: false, error: 'ITEM_NOT_FOUND' };
  }

  // 2. Execute item effect
  const itemTemplate = loadItemTemplate(nk, itemId);
  const effect = executeItemEffect(nk, characterId, itemTemplate);

  // 3. Consume item (decrement quantity or delete)
  consumeInventoryItem(nk, characterId, inventoryItem.item_uid, 1);

  return { success: true, effect };
}
```

### Instance System Integration

_Requirements: 11, 9 (main spec)_

**Party Instance Entry:**
```typescript
function initiateInstanceEntry(
  nk: nkruntime.Nakama,
  partyId: string,
  leaderId: string,
  templateId: string
): InstanceEntryResult {
  const party = loadPartyState(nk, partyId);

  // 1. Validate all members meet instance requirements
  const failedMembers = [];
  for (const member of party.members) {
    const validation = validateInstanceRequirements(nk, member.characterId, templateId);
    if (!validation.valid) {
      failedMembers.push({ characterId: member.characterId, reason: validation.error });
    }
  }

  if (failedMembers.length > 0) {
    return { success: false, failedMembers };
  }

  // 2. Create match instance (from main spec, Requirement 9)
  const matchId = createMatchInstance(nk, templateId, party.partyId);

  // 3. Teleport all members simultaneously
  for (const member of party.members) {
    teleportToInstance(nk, member.characterId, matchId);
  }

  // 4. Lock party (prevent membership changes during instance)
  nk.sqlExec(`UPDATE parties SET in_instance = TRUE, instance_match_id = $1 WHERE party_id = $2`, [matchId, partyId]);

  return { success: true, matchId };
}
```

---

## Client SDK Examples

### Godot 4 GDScript - Skill Bar UI

```gdscript
extends Control

# Skill bar with 12 slots
@onready var skill_slots: Array[SkillSlot] = []
var hotbar_config: Dictionary = {}
var active_cooldowns: Dictionary = {}

func _ready():
	# Initialize skill slots
	for i in range(12):
		var slot = $HBoxContainer.get_child(i) as SkillSlot
		skill_slots.append(slot)
		slot.slot_activated.connect(_on_slot_activated.bind(i))

	# Load hotbar configuration
	await _load_hotbar_config()

	# Subscribe to cooldown notifications
	socket.received_notification.connect(_on_notification)

func _load_hotbar_config():
	var result = await socket.rpc("hotbar_get_config", "")
	if result.is_exception():
		push_error("Failed to load hotbar: " + result.get_exception().message)
		return

	hotbar_config = JSON.parse_string(result.payload)
	_update_skill_slots()

func _update_skill_slots():
	var bar_index = 0 # First bar (0-11 slots)
	var bar_data = hotbar_config.config.bars[bar_index]

	for i in range(12):
		var slot_data = bar_data.slots[i]
		skill_slots[i].set_content(slot_data)

func _on_slot_activated(slot_index: int):
	# Get current target (or null for self-targeted skills)
	var target_id = get_current_target_id()

	# Send activation RPC
	var payload = JSON.stringify({
		"bar_index": 0,
		"slot_index": slot_index,
		"target_id": target_id
	})

	var result = await socket.rpc("hotbar_activate", payload)
	if result.is_exception():
		_show_error(result.get_exception().message)
	else:
		var activation_result = JSON.parse_string(result.payload)
		if activation_result.success:
			_handle_skill_result(activation_result.result)

func _on_notification(notif: NakamaAPI.ApiNotification):
	match notif.code:
		NotificationCodes.SKILL_COOLDOWN_TRIGGERED:
			var data = JSON.parse_string(notif.content)
			_start_cooldown_overlay(data.skill_id, data.duration)

		NotificationCodes.SKILL_COOLDOWN_READY:
			var data = JSON.parse_string(notif.content)
			_clear_cooldown_overlay(data.skill_id)

func _start_cooldown_overlay(skill_id: String, duration: float):
	# Find slot with this skill
	for slot in skill_slots:
		if slot.content_type == "skill" and slot.skill_id == skill_id:
			slot.start_cooldown(duration / 1000.0) # Convert ms to seconds

# Input handling for keybinds
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		# Keybinds: 1-9, 0, -, =
		var key_to_slot = {
			KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4, KEY_6: 5,
			KEY_7: 6, KEY_8: 7, KEY_9: 8, KEY_0: 9, KEY_MINUS: 10, KEY_EQUAL: 11
		}

		if event.keycode in key_to_slot:
			var slot_index = key_to_slot[event.keycode]
			_on_slot_activated(slot_index)
			get_viewport().set_input_as_handled()
```

### Godot 4 GDScript - Party UI

```gdscript
extends Control

@onready var member_list: VBoxContainer = $MemberList
@onready var party_chat: RichTextLabel = $PartyChat
@onready var loot_roll_popup: PopupPanel = $LootRollPopup

var party_state: Dictionary = {}
var party_members: Dictionary = {} # character_id -> PartyMemberUI

func _ready():
	socket.received_notification.connect(_on_notification)

func create_party():
	var result = await socket.rpc("party_create", "")
	if result.is_exception():
		push_error("Failed to create party: " + result.get_exception().message)
		return

	var data = JSON.parse_string(result.payload)
	party_state.party_id = data.party_id
	await _refresh_party_state()

func invite_player(player_name: String):
	var payload = JSON.stringify({"target_name": player_name})
	var result = await socket.rpc("party_invite", payload)

	if result.is_exception():
		_show_error(result.get_exception().message)

func _refresh_party_state():
	# Party state is updated via notifications, but can request manually
	pass

func _on_notification(notif: NakamaAPI.ApiNotification):
	match notif.code:
		NotificationCodes.PARTY_MEMBER_JOINED:
			var data = JSON.parse_string(notif.content)
			_add_party_member(data.member)

		NotificationCodes.PARTY_MEMBER_LEFT:
			var data = JSON.parse_string(notif.content)
			_remove_party_member(data.character_id)

		NotificationCodes.PARTY_MEMBER_HP_UPDATE:
			var data = JSON.parse_string(notif.content)
			_update_member_hp(data.character_id, data.hp, data.max_hp)

		NotificationCodes.PARTY_LOOT_ROLL_REQUEST:
			var data = JSON.parse_string(notif.content)
			_show_loot_roll_popup(data.loot_id, data.item, data.expires_at)

func _add_party_member(member_data: Dictionary):
	var member_ui = preload("res://ui/party_member.tscn").instantiate()
	member_ui.set_member_data(member_data)
	member_list.add_child(member_ui)
	party_members[member_data.character_id] = member_ui

func _update_member_hp(character_id: String, hp: int, max_hp: int):
	if character_id in party_members:
		party_members[character_id].update_hp(hp, max_hp)

func _show_loot_roll_popup(loot_id: String, item: Dictionary, expires_at: int):
	loot_roll_popup.set_item(item)
	loot_roll_popup.loot_id = loot_id
	loot_roll_popup.expires_at = expires_at
	loot_roll_popup.popup_centered()

func roll_need(loot_id: String):
	var payload = JSON.stringify({"loot_id": loot_id})
	await socket.rpc("party_roll_need", payload)
	loot_roll_popup.hide()

func roll_greed(loot_id: String):
	var payload = JSON.stringify({"loot_id": loot_id})
	await socket.rpc("party_roll_greed", payload)
	loot_roll_popup.hide()
```

---

**Design document complete. Ready to generate tasks.md for implementation tracking.**
