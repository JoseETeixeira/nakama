# Implementation Tasks: Skills, Hotbar, and Party Systems

**Feature:** Skills, Hotbar, and Party Systems
**Requirements:** `.kiro/specs/skills-hotbar-party/requirements.md`
**Design:** `.kiro/specs/skills-hotbar-party/design.md`
**Status:** Ready for Implementation
**Last Updated:** October 28, 2025

---

## Task Organization

Tasks are organized by implementation phase and trace back to specific requirements and design sections. Each task is marked with:
- `[ ]` = Not started
- `[~]` = In progress
- `[x]` = Completed

**Traceability Format:** `_Req: X, Design: Section Y_`

---

## Phase 1: Database Schema & Configuration (Week 1)

### 1.1 Skills Database Schema
_Req: 1-3, Design: Data Models_

- [ ] **1.1.1** Create character_skills table migration
  - Table: `character_skills` with character_id, skill_id, level, experience, learned_at
  - Composite primary key (character_id, skill_id)
  - Index on character_id
  - _Req: 1, 2_

- [ ] **1.1.2** Create skill_configs table migration
  - Table: `skill_configs` with skill_id, name, archetype_id, unlock_level, prerequisites, max_level, cooldown, resource_cost, cast_time, range, target_type, effects_per_level, currency_cost
  - Index on archetype_id
  - _Req: 1, 2, 3_

- [ ] **1.1.3** Create skill configuration seed data
  - Populate skill_configs with starter skills for each archetype (warrior, mage, rogue, etc.)
  - Define skill effects per level (damage scaling, healing scaling, duration)
  - Test data: at least 5 skills per archetype
  - _Req: 1, 2_

### 1.2 Hotbar Database Schema
_Req: 4-6, Design: Data Models_

- [ ] **1.2.1** Create character_hotbars table migration
  - Table: `character_hotbars` with character_id, config (JSONB), version, updated_at
  - Primary key on character_id
  - Optimistic locking via version column
  - _Req: 4, 6_

- [ ] **1.2.2** Add default hotbar configuration
  - Create migration to initialize empty hotbars for existing characters
  - Default: 3 bars × 12 slots, all slots empty
  - _Req: 4, 6_

### 1.3 Party Database Schema
_Req: 7-12, Design: Data Models_

- [ ] **1.3.1** Create parties table migration
  - Table: `parties` with party_id, leader_id, loot_mode, loot_round_robin_index, created_at, in_instance, instance_match_id
  - Index on leader_id
  - _Req: 7, 8, 10, 11_

- [ ] **1.3.2** Create party_members table migration
  - Table: `party_members` with party_id, character_id, joined_at
  - Composite primary key (party_id, character_id)
  - Index on character_id
  - Cascade delete on party_id and character_id
  - _Req: 7, 8_

- [ ] **1.3.3** Create party_invitations table migration
  - Table: `party_invitations` with invite_id, party_id, inviter_id, invitee_id, created_at, expires_at
  - Index on invitee_id and expires_at
  - _Req: 7_

---

## Phase 2: Skills System Implementation (Weeks 2-3)

### 2.1 Skills Service Core
_Req: 1-3, Design: System Components_

- [ ] **2.1.1** Create SkillsService interface and implementation
  - File: `data/modules/skills/skills_service.ts`
  - Implement: getAvailableSkills, learnSkill, upgradeSkill, getLearnedSkills
  - _Req: 1, 2_

- [ ] **2.1.2** Implement skill learning validation
  - Validate: level requirements, prerequisite skills, currency cost
  - Atomic transaction: deduct currency + persist skill
  - Error handling: return specific error codes
  - _Req: 1_

- [ ] **2.1.3** Implement skill leveling system
  - Experience-based leveling: track XP, level up on threshold
  - Manual leveling: currency cost per level
  - Skill stat scaling: load effects_per_level from config
  - _Req: 2_

### 2.2 Cooldown Management
_Req: 3, Design: State Management_

- [ ] **2.2.1** Create CooldownManager module
  - File: `data/modules/skills/cooldown_manager.ts`
  - In-memory Map: character_id -> Map<skill_id, CooldownEntry>
  - Functions: triggerCooldown, getCooldownRemaining, clearCooldown
  - Auto-cleanup: setTimeout to remove expired cooldowns
  - _Req: 3_

- [ ] **2.2.2** Integrate cooldown tracking with skill activation
  - Check cooldown before skill validation
  - Trigger cooldown after successful activation
  - Broadcast cooldown_triggered notification to client
  - _Req: 3_

### 2.3 Skill Validation & Activation
_Req: 3, Design: System Components_

- [ ] **2.3.1** Create SkillValidator module
  - File: `data/modules/skills/skill_validator.ts`
  - Validate: skill learned, cooldown ready, resource cost, target validity, range, LoS
  - Return: ValidationResult with specific error codes
  - _Req: 3_

- [ ] **2.3.2** Implement activateSkill RPC
  - RPC: `skills_activate(skill_id, target_id, position?)`
  - Full validation pipeline
  - Apply skill effects via combat system integration
  - Deduct resources, trigger cooldown, broadcast result
  - _Req: 3_

- [ ] **2.3.3** Create SkillEffects module
  - File: `data/modules/skills/skill_effects.ts`
  - Apply damage, healing, buffs via combat system
  - Calculate critical hits, resistances
  - Broadcast combat events to AOI
  - _Req: 3, Integration with Req 6 from main spec_

### 2.4 Skills API Endpoints
_Req: 1-3, Design: API Contracts_

- [ ] **2.4.1** Register skills RPC endpoints
  - `skills_get_available`, `skills_learn`, `skills_upgrade`, `skills_list`, `skills_activate`, `skills_get_cooldowns`
  - Input validation and error handling
  - _Req: 1, 2, 3_

- [ ] **2.4.2** Implement skill configuration loader
  - File: `data/modules/skills/skill_configs_loader.ts`
  - Load skill templates from database
  - LRU cache: max 1000 skill templates
  - _Req: 1, 2, 3, Design: Performance Optimization_

---

## Phase 3: Hotbar System Implementation (Week 4)

### 3.1 Hotbar Service Core
_Req: 4-6, Design: System Components_

- [ ] **3.1.1** Create HotbarService interface and implementation
  - File: `data/modules/hotbar/hotbar_service.ts`
  - Implement: assignSlot, swapSlots, clearSlot, activateSlot, getHotbarConfig, saveHotbarConfig
  - _Req: 4, 5, 6_

- [ ] **3.1.2** Implement slot assignment validation
  - Validate: skill learned, item exists in inventory, macro syntax valid
  - Prevent slot overflow (barIndex ∈ [0, 2], slotIndex ∈ [0, 11])
  - _Req: 4_

- [ ] **3.1.3** Implement hotbar persistence with optimistic locking
  - File: `data/modules/hotbar/hotbar_persistence.ts`
  - Load config from database, update JSONB field
  - Version check: reject if version conflict
  - Retry logic: exponential backoff on conflict
  - _Req: 6_

### 3.2 Hotbar Activation
_Req: 5, Design: System Components_

- [ ] **3.2.1** Implement activateSlot routing logic
  - Route skill activations to SkillsService
  - Route item activations to InventoryService (use item)
  - Route macro activations to MacroExecutor
  - Return: ActivationResult with type-specific results
  - _Req: 5_

- [ ] **3.2.2** Integrate with inventory system for item usage
  - Validate item ownership via inventory module
  - Execute item effects (consumables, equipment)
  - Consume item (decrement quantity or delete)
  - _Req: 5, Integration with Req 14 from main spec_

### 3.3 Macro System
_Req: 4, 5, Design: System Components_

- [ ] **3.3.1** Create MacroParser module
  - File: `data/modules/hotbar/macro_parser.ts`
  - Parse macro commands: /cast, /use, /target, /wait
  - Validate syntax, return MacroValidation with errors
  - _Req: 4, 5_

- [ ] **3.3.2** Create MacroExecutor module
  - File: `data/modules/hotbar/macro_executor.ts`
  - Execute macro commands sequentially
  - Handle waits (async delays)
  - Return: MacroResult with executed/failed commands
  - _Req: 5_

### 3.4 Hotbar API Endpoints
_Req: 4-6, Design: API Contracts_

- [ ] **3.4.1** Register hotbar RPC endpoints
  - `hotbar_assign_slot`, `hotbar_swap_slots`, `hotbar_activate`, `hotbar_get_config`, `hotbar_validate_macro`
  - Input validation and error handling
  - _Req: 4, 5, 6_

---

## Phase 4: Party System Implementation (Weeks 5-6)

### 4.1 Party Service Core
_Req: 7-12, Design: System Components_

- [ ] **4.1.1** Create PartyService interface and implementation
  - File: `data/modules/party/party_service.ts`
  - Implement: createParty, invitePlayer, acceptInvite, declineInvite, kickMember, leaveParty, promoteLeader
  - _Req: 7, 8_

- [ ] **4.1.2** Implement party creation and invitation management
  - Create party in database, add leader as first member
  - Create invitations with 60s expiration
  - Send invitation notification to target player
  - _Req: 7_

- [ ] **4.1.3** Implement party membership management
  - Kick member: verify leadership, remove from roster, broadcast update
  - Leave party: remove self, auto-promote if leader, disband if 1 member
  - Promote leader: transfer leadership, broadcast update
  - _Req: 8_

### 4.2 Party Cache & State Management
_Req: 7-12, Design: State Management_

- [ ] **4.2.1** Create PartyCacheManager module
  - File: `data/modules/party/party_cache.ts`
  - In-memory cache: Map<party_id, PartyCacheEntry>
  - Load party state from database on cache miss
  - TTL: 5 minutes of inactivity, auto-evict
  - _Req: 7-12_

- [ ] **4.2.2** Implement party state broadcast system
  - Broadcast updates to all online party members
  - Notifications: member_joined, member_left, leader_changed, loot_mode_changed, hp_update
  - Use Nakama presence system for online member tracking
  - _Req: 7, 8, 9_

### 4.3 Party Chat Integration
_Req: 9, Design: System Components_

- [ ] **4.3.1** Integrate party chat with existing chat system
  - Auto-subscribe members to party channel on join
  - Auto-unsubscribe on leave/kick
  - Close channel on party disband
  - _Req: 9, Integration with Req 12 from main spec_

### 4.4 Loot Distribution System
_Req: 10, Design: System Components_

- [ ] **4.4.1** Create LootDistributor module
  - File: `data/modules/party/loot_distributor.ts`
  - Implement: distributeLoot, distributeRoundRobin, distributeNeedGreed, distributeMasterLooter, distributeFreeForAll
  - _Req: 10_

- [ ] **4.4.2** Implement round-robin loot distribution
  - Track loot_round_robin_index in database
  - Assign loot in rotation based on join order
  - Update index after each distribution
  - _Req: 10_

- [ ] **4.4.3** Implement need-before-greed loot distribution
  - Create pending rolls with 30s expiration
  - Broadcast loot_roll_request to all members
  - Collect rolls (need/greed/pass)
  - Award to highest need roll (or greed if no need)
  - Ties resolved by RNG
  - _Req: 10_

- [ ] **4.4.4** Implement master looter and free-for-all modes
  - Master looter: assign all loot to party leader
  - Free-for-all: first to loot wins (no distribution logic)
  - _Req: 10_

### 4.5 Party Instance Entry Coordination
_Req: 11, Design: Integration Points_

- [ ] **4.5.1** Implement initiateInstanceEntry
  - Validate all members meet instance requirements (level, item level, proximity)
  - Create match instance via instance system
  - Teleport all members simultaneously
  - Lock party (prevent membership changes during instance)
  - _Req: 11, Integration with Req 9 from main spec_

- [ ] **4.5.2** Handle instance rejoin grace period for party members
  - Maintain party slot during disconnect
  - Allow rejoin within grace period (5 minutes)
  - _Req: 11, Integration with Req 10 from main spec_

### 4.6 Shared Quest Objectives
_Req: 12, Design: System Components_

- [ ] **4.6.1** Create SharedObjectives module
  - File: `data/modules/party/shared_objectives.ts`
  - Implement: shareQuest, syncObjectiveProgress
  - _Req: 12_

- [ ] **4.6.2** Implement quest sharing and progress synchronization
  - Share quest with all eligible party members
  - Sync objective progress (kill counts, collection counts)
  - Credit nearby party members with completions
  - Proximity-based credit (configurable range)
  - _Req: 12_

### 4.7 Party API Endpoints
_Req: 7-12, Design: API Contracts_

- [ ] **4.7.1** Register party RPC endpoints
  - `party_create`, `party_invite`, `party_accept_invite`, `party_decline_invite`, `party_kick`, `party_leave`, `party_promote_leader`
  - _Req: 7, 8_

- [ ] **4.7.2** Register party loot and instance RPC endpoints
  - `party_set_loot_mode`, `party_roll_need`, `party_roll_greed`, `party_pass_loot`, `party_enter_instance`
  - _Req: 10, 11_

- [ ] **4.7.3** Register party quest RPC endpoint
  - `party_share_quest`
  - _Req: 12_

---

## Phase 5: Performance Optimization & Testing (Week 7)

### 5.1 Performance Optimization
_Design: Performance Optimization_

- [ ] **5.1.1** Implement skill template caching
  - LRU cache: max 1000 skill templates
  - Cache hit measurement: log cache hit rate
  - Target: ≥95% cache hit rate
  - _Design: Performance Optimization_

- [ ] **5.1.2** Optimize hotbar persistence latency
  - Measure p95 latency for hotbar saves
  - Implement connection pooling for DB writes
  - Target: p95 ≤30ms
  - _Design: Performance Optimization_

- [ ] **5.1.3** Optimize party update broadcast latency
  - Measure p95 latency for party broadcasts
  - Implement delta updates (only changes, not full state)
  - Use presence tracking to skip offline players
  - Target: p95 ≤100ms
  - _Design: Performance Optimization_

- [ ] **5.1.4** Benchmark skill activation latency
  - Load test: 1000 concurrent skill activations
  - Measure: validation time, cooldown check time, broadcast time
  - Target: p95 ≤50ms, p99 ≤100ms
  - _Design: Performance Optimization_

### 5.2 Integration Testing
_All Requirements_

- [ ] **5.2.1** Test skills system end-to-end
  - Test: learn skill, upgrade skill, activate skill, cooldown tracking
  - Validate: error codes, resource consumption, cooldown enforcement
  - Edge cases: invalid targets, out of range, insufficient resources
  - _Req: 1, 2, 3_

- [ ] **5.2.2** Test hotbar system end-to-end
  - Test: assign slots (skill/item/macro), activate slots, persist config
  - Validate: optimistic locking, macro parsing, item consumption
  - Edge cases: empty slots, invalid skills, version conflicts
  - _Req: 4, 5, 6_

- [ ] **5.2.3** Test party system end-to-end
  - Test: create party, invite/accept/decline, kick/leave, promote leader
  - Validate: membership limits, leadership transfers, party disbanding
  - Edge cases: expired invitations, double invitations, leader leaving
  - _Req: 7, 8_

- [ ] **5.2.4** Test party loot distribution
  - Test: all loot modes (round-robin, need-before-greed, master looter, free-for-all)
  - Validate: fair distribution, roll resolution, expired rolls
  - Edge cases: ties, all pass, master looter offline
  - _Req: 10_

- [ ] **5.2.5** Test party instance entry
  - Test: initiate entry, validate members, teleport simultaneously
  - Validate: requirement failures, party locking, rejoin grace period
  - Edge cases: member disconnects during entry, failed requirements
  - _Req: 11_

### 5.3 Security & Anti-Cheat Testing
_Design: Security & Validation_

- [ ] **5.3.1** Penetration testing for skill cooldown exploits
  - Test: client-side cooldown manipulation, timestamp tampering
  - Validate: server rejects stale requests, cooldowns enforced server-side
  - _Req: 3, Security NFRs_

- [ ] **5.3.2** Penetration testing for item duplication via hotbar
  - Test: rapid hotbar activations, concurrent item usage
  - Validate: atomic inventory transactions, item UIDs prevent duplication
  - _Req: 5, Security NFRs_

- [ ] **5.3.3** Penetration testing for loot theft
  - Test: client-side loot mode override, roll value manipulation
  - Validate: server-enforced loot mode, server-side RNG for rolls
  - _Req: 10, Security NFRs_

---

## Phase 6: Client SDK & Documentation (Week 8)

### 6.1 Godot 4 SDK Examples
_Design: Client SDK Examples_

- [ ] **6.1.1** Create Skill Bar UI example
  - GDScript: skill slot management, cooldown overlays, keybind handling
  - Integration: RPC calls for skill activation, notification handling
  - _Design: Client SDK Examples_

- [ ] **6.1.2** Create Party UI example
  - GDScript: party member list, HP/MP bars, loot roll windows
  - Integration: RPC calls for party management, notification handling
  - _Design: Client SDK Examples_

- [ ] **6.1.3** Create Macro Editor UI example
  - GDScript: macro text editor, syntax validation, command suggestions
  - Integration: RPC calls for macro validation, hotbar assignment
  - _Design: Client SDK Examples_

### 6.2 Documentation
_All Requirements_

- [ ] **6.2.1** Write Skills System API documentation
  - Document: all RPC endpoints, request/response formats, error codes
  - Examples: learning a skill, activating a skill, handling cooldowns
  - _Req: 1, 2, 3_

- [ ] **6.2.2** Write Hotbar System API documentation
  - Document: all RPC endpoints, hotbar configuration format, macro syntax
  - Examples: assigning slots, activating slots, creating macros
  - _Req: 4, 5, 6_

- [ ] **6.2.3** Write Party System API documentation
  - Document: all RPC endpoints, party state format, loot modes
  - Examples: creating a party, loot distribution, instance entry
  - _Req: 7-12_

- [ ] **6.2.4** Create deployment guide
  - Database migrations checklist
  - Configuration parameters (loot mode defaults, cooldown settings)
  - Performance tuning recommendations
  - _All Requirements_

---

## Success Criteria

**Phase 1-2 Complete:**
- ✅ All database migrations applied successfully
- ✅ Skills can be learned, leveled, and activated server-side
- ✅ Cooldowns tracked in-memory and enforced correctly
- ✅ Skill validation prevents exploits (≥95% penetration test pass rate)

**Phase 3 Complete:**
- ✅ Hotbar configurations persist across sessions
- ✅ Slots activate skills, items, and macros correctly
- ✅ Optimistic locking prevents race conditions (zero config corruption)
- ✅ Macro parser handles all supported commands

**Phase 4 Complete:**
- ✅ Parties can be formed, managed, and disbanded
- ✅ All loot modes distribute loot fairly (zero loot theft in testing)
- ✅ Party instance entry coordinates all members successfully
- ✅ Shared quest objectives sync progress correctly

**Phase 5 Complete:**
- ✅ Performance targets met (≤50ms skill activation, ≤30ms hotbar persistence, ≤100ms party broadcast)
- ✅ Zero critical security vulnerabilities in penetration testing
- ✅ All integration tests pass (100% coverage of acceptance criteria)

**Phase 6 Complete:**
- ✅ Godot 4 SDK examples demonstrate all features
- ✅ API documentation covers all endpoints with examples
- ✅ Deployment guide tested on staging environment

---

## Notes

- **Dependencies:** This feature depends on existing systems (combat, inventory, instance, chat) from the main MMORPG spec
- **Integration Points:** Coordinate with teams working on Requirement 6 (combat), Requirement 9 (instances), Requirement 12 (chat), Requirement 14 (inventory)
- **Performance Monitoring:** Set up Prometheus metrics for skill activation latency, hotbar persistence latency, party broadcast latency
- **Rollout Strategy:** Deploy to staging first, canary release to 10% of production, monitor for 48 hours before full rollout
