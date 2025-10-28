# Requirements: Skills, Hotbar, and Party Systems

## Document Information

- **Feature Name:** Skills, Hotbar, and Party Systems
- **Version:** 1.0
- **Date:** October 28, 2025
- **Stakeholders:** Game Studios, Players, Game Designers, Backend Developers
- **Parent Spec:** MMORPG-grade Nakama with Godot 4 Integration

## Introduction

This feature extends the MMORPG-grade Nakama server with comprehensive skill management, hotbar customization, and party coordination systems. These systems are fundamental to MMORPG gameplay, enabling players to learn and upgrade skills, organize abilities for quick access during combat, and coordinate with other players in group content.

The skill system manages character abilities with progression mechanics (skill levels, unlock requirements, cooldowns). The hotbar system provides customizable action bars where players can assign skills, items, and macros for quick activation. The party system enables group formation, shared objectives, loot distribution, and coordinated instanced content entry.

All systems prioritize server-authoritative validation to prevent exploits, maintain fairness, and ensure consistent state across all clients. The design integrates seamlessly with existing character progression, combat, inventory, and instance systems.

## Feature Summary

Server-authoritative skill progression, customizable hotbar slots, and party coordination systems that enable MMORPG group gameplay with fair validation, persistent state, and Godot 4 client integration.

## Business Value

- **Player Engagement**: Skill progression and customization systems increase player investment and retention
- **Social Gameplay**: Party systems encourage cooperative play and community building
- **Content Accessibility**: Group coordination enables access to challenging instanced content (dungeons, raids)
- **Gameplay Depth**: Hotbar customization allows diverse playstyles and strategic choices
- **Monetization Opportunities**: Premium skill cosmetics, additional hotbar slots, and party convenience features

## Scope

**In Scope:**
- Skill learning, leveling, and unlock requirements
- Server-authoritative skill validation (cooldowns, costs, requirements)
- Customizable hotbar slots with skill/item/macro assignments
- Party creation, invitation, and membership management
- Party chat channel and shared objectives
- Party-based loot distribution modes (need/greed, master looter, round-robin)
- Party leader privileges and kick/promote mechanics
- Party instance entry coordination
- Persistent hotbar configurations per character
- Skill tree visualization data for client rendering

**Out of Scope:**
- Skill animations and visual effects (client-side implementation)
- Party voice chat (text-based only)
- Cross-server party formation (single-shard parties only)
- Raid groups (parties limited to 5 players)
- Skill talent specializations (future enhancement)

---

## Requirements

### Requirement 1: Skill Learning and Unlock

**User Story:** As a player, I want to learn new skills from trainers or through level progression, so that I can expand my character's abilities and customize my playstyle.

**Acceptance Criteria (EARS)**
- WHEN a player interacts with a skill trainer THEN Nakama SHALL return a list of available skills for the character's archetype with unlock requirements (level, prerequisite skills, currency cost)
- IF a player attempts to learn a skill without meeting requirements THEN Nakama SHALL reject the request and return specific missing requirements
- WHEN a player learns a skill THEN Nakama SHALL add the skill to the character's skill list, deduct currency, and persist the change atomically
- IF a skill has prerequisite skills THEN Nakama SHALL verify all prerequisites are learned before allowing unlock
- WHEN a character levels up THEN Nakama SHALL unlock any auto-learned skills for that level and notify the client

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Character progression system, archetype configuration, currency/wallet system
- **Assumptions:** Skill data is stored in game configuration (JSON/DB); skills are archetype-specific; trainers are NPCs or level-based auto-unlocks

---

### Requirement 2: Skill Leveling and Upgrades

**User Story:** As a player, I want to upgrade my skills to increase their effectiveness, so that my character becomes more powerful as I progress.

**Acceptance Criteria (EARS)**
- WHEN a player uses a skill repeatedly THEN Nakama SHALL track skill experience and level up the skill when thresholds are reached
- IF skill leveling is manual (trainer-based) THEN Nakama SHALL require currency payment and level requirements for each upgrade
- WHEN a skill levels up THEN Nakama SHALL update skill stats (damage, healing, duration, cooldown reduction) according to configuration tables
- IF a skill reaches maximum level THEN Nakama SHALL prevent further leveling and mark the skill as mastered
- WHILE a skill is leveling THEN Nakama SHALL broadcast progress notifications to the client for UI updates

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirement 1 (skill learning), skill configuration tables, character progression
- **Assumptions:** Skills have max level caps (e.g., level 5); leveling can be experience-based or manual; skill stats scale per level

---

### Requirement 3: Server-Authoritative Skill Validation

**User Story:** As a game designer, I want all skill usage to be validated server-side, so that players cannot exploit cooldowns, resource costs, or targeting restrictions.

**Acceptance Criteria (EARS)**
- WHEN a player attempts to use a skill THEN Nakama SHALL validate: skill is learned, cooldown is ready, resource costs are available, target is valid, range/LoS requirements are met
- IF any validation check fails THEN Nakama SHALL reject the skill usage and return a specific error code (e.g., "COOLDOWN_ACTIVE", "INSUFFICIENT_MANA", "OUT_OF_RANGE")
- WHEN a skill is successfully activated THEN Nakama SHALL deduct resource costs, trigger cooldowns, apply effects, and broadcast results to clients in AOI
- IF a skill has cast time THEN Nakama SHALL track casting state and allow interruption from damage or movement
- WHILE a skill cooldown is active THEN Nakama SHALL reject attempts to use the skill and return remaining cooldown time

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Combat system (Requirement 6 from main spec), resource management, targeting/LoS validation
- **Assumptions:** Skills have cooldowns (global or per-skill), resource costs (mana, energy, rage), cast times, and targeting requirements

---

### Requirement 4: Hotbar Slot Assignment

**User Story:** As a player, I want to assign skills, items, and macros to customizable hotbar slots, so that I can quickly activate them during combat without navigating menus.

**Acceptance Criteria (EARS)**
- WHEN a player assigns a skill to a hotbar slot THEN Nakama SHALL validate the skill is learned and update the character's hotbar configuration
- IF a player assigns an item to a hotbar slot THEN Nakama SHALL verify the item exists in inventory and is usable
- WHEN a player assigns a macro to a hotbar slot THEN Nakama SHALL validate the macro syntax and store it with the hotbar configuration
- IF a hotbar slot is already occupied THEN Nakama SHALL allow overwriting or swapping with another slot
- WHEN hotbar configuration changes THEN Nakama SHALL persist the changes immediately and return confirmation to the client

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 1 (skill learning), inventory system (Requirement 14 from main spec), macro system
- **Assumptions:** Characters have multiple hotbars (e.g., 3 bars × 12 slots each); hotbar state is per-character; macros are text commands

---

### Requirement 5: Hotbar Activation and Validation

**User Story:** As a player, I want to activate hotbar slots during combat, so that I can use skills and items quickly without targeting errors or cooldown confusion.

**Acceptance Criteria (EARS)**
- WHEN a player activates a hotbar slot THEN Nakama SHALL determine the slot content (skill, item, macro) and execute the appropriate action
- IF the slot contains a skill THEN Nakama SHALL validate and activate the skill (per Requirement 3)
- IF the slot contains an item THEN Nakama SHALL validate item availability and trigger item usage (consumables, equipment)
- IF the slot contains a macro THEN Nakama SHALL parse and execute macro commands in sequence
- WHEN a hotbar activation fails THEN Nakama SHALL return a specific error (empty slot, skill on cooldown, item not in inventory, macro syntax error)

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 3 (skill validation), Requirement 4 (hotbar assignment), inventory system
- **Assumptions:** Hotbar slots are activated by index (0-11 for bar 1, 12-23 for bar 2, etc.); macros support skill casting and item usage

---

### Requirement 6: Persistent Hotbar Configuration

**User Story:** As a player, I want my hotbar configuration to persist across sessions, so that I don't have to reconfigure my action bars every time I log in.

**Acceptance Criteria (EARS)**
- WHEN a player logs in THEN Nakama SHALL load the character's hotbar configuration from the database and send it to the client
- WHEN a player modifies hotbar slots THEN Nakama SHALL persist changes immediately using optimistic locking to prevent race conditions
- IF a hotbar contains a skill the player no longer knows (e.g., after respec) THEN Nakama SHALL mark the slot as invalid but preserve the configuration
- WHEN a hotbar contains an item that was consumed THEN Nakama SHALL allow the slot to remain but mark it as unavailable until replenished
- IF database persistence fails THEN Nakama SHALL retry with exponential backoff and notify the client of temporary save failure

**Additional Details**
- **Priority:** Medium
- **Complexity:** Medium
- **Dependencies:** Requirement 4 (hotbar assignment), database schema for hotbar storage, optimistic locking
- **Assumptions:** Hotbar data is stored as JSONB in characters table or separate hotbar table; version column prevents race conditions

---

### Requirement 7: Party Creation and Invitations

**User Story:** As a player, I want to create a party and invite other players, so that we can coordinate for group content and share objectives.

**Acceptance Criteria (EARS)**
- WHEN a player creates a party THEN Nakama SHALL assign a unique party_id, set the creator as party leader, and initialize party state
- WHEN a party leader invites a player THEN Nakama SHALL send an invitation to the target player with party details (leader name, current size)
- IF the invited player is already in a party THEN Nakama SHALL reject the invitation
- WHEN an invited player accepts THEN Nakama SHALL add them to the party roster and broadcast the update to all party members
- IF an invited player declines or the invitation expires (e.g., 60 seconds) THEN Nakama SHALL cancel the invitation and notify the inviter

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Character system, party state management
- **Assumptions:** Party size limit is 5 players; invitations are one-to-one (no mass invites); only party leader can invite

---

### Requirement 8: Party Membership Management

**User Story:** As a party leader, I want to manage party membership by kicking players or promoting new leaders, so that I can maintain party coordination and resolve conflicts.

**Acceptance Criteria (EARS)**
- WHEN a party leader kicks a member THEN Nakama SHALL remove the player from the party roster, notify all members, and return the kicked player to solo state
- IF a party leader leaves the party THEN Nakama SHALL promote another member to leader (longest tenure or next in roster) or disband if empty
- WHEN a party leader promotes another member to leader THEN Nakama SHALL transfer leadership privileges and notify all members
- IF a player leaves the party voluntarily THEN Nakama SHALL remove them from the roster and broadcast the update
- WHEN a party is reduced to 1 member THEN Nakama SHALL automatically disband the party after a grace period (e.g., 30 seconds)

**Additional Details**
- **Priority:** High
- **Complexity:** Medium
- **Dependencies:** Requirement 7 (party creation), party state persistence
- **Assumptions:** Only party leader can kick/promote; leadership transfer is explicit (not automatic unless leader leaves); grace period prevents instant disband

---

### Requirement 9: Party Chat Channel

**User Story:** As a party member, I want to communicate with my party via a dedicated chat channel, so that we can coordinate strategy and share information privately.

**Acceptance Criteria (EARS)**
- WHEN a player joins a party THEN Nakama SHALL automatically subscribe them to the party chat channel
- WHEN a party member sends a message to party chat THEN Nakama SHALL broadcast the message only to current party members
- IF a player leaves or is kicked from the party THEN Nakama SHALL unsubscribe them from the party chat channel immediately
- WHILE a player is in a party THEN Nakama SHALL maintain the subscription and deliver messages in real-time
- WHEN a party is disbanded THEN Nakama SHALL close the party chat channel and archive the chat history

**Additional Details**
- **Priority:** Medium
- **Complexity:** Low
- **Dependencies:** Requirement 7 (party creation), Requirement 8 (membership), chat system (Requirement 12 from main spec)
- **Assumptions:** Party chat uses existing channel infrastructure; messages are not persisted long-term; profanity filters apply

---

### Requirement 10: Party Loot Distribution

**User Story:** As a party member, I want to configure loot distribution rules, so that loot from defeated enemies is shared fairly according to our agreed method.

**Acceptance Criteria (EARS)**
- WHEN a party is created THEN Nakama SHALL default to a loot distribution mode (e.g., round-robin or need-before-greed)
- WHEN a party leader changes the loot mode THEN Nakama SHALL update the party configuration and notify all members
- IF loot mode is "round-robin" THEN Nakama SHALL assign loot to party members in rotation based on join order
- IF loot mode is "need-before-greed" THEN Nakama SHALL allow members to roll need/greed and award to highest need roll (or greed if no need)
- IF loot mode is "master looter" THEN Nakama SHALL assign all loot to the party leader for manual distribution

**Additional Details**
- **Priority:** Medium
- **Complexity:** High
- **Dependencies:** Requirement 7 (party creation), loot generation system (Requirement 17 from main spec)
- **Assumptions:** Supported modes: round-robin, need-before-greed, master looter, free-for-all; need rolls beat greed rolls; ties resolved by random

---

### Requirement 11: Party Instance Entry Coordination

**User Story:** As a party leader, I want to enter instanced content with my party, so that we can tackle challenging dungeons and arenas as a coordinated group.

**Acceptance Criteria (EARS)**
- WHEN a party leader initiates instance entry THEN Nakama SHALL validate all party members meet instance requirements (level, item level, location proximity)
- IF any party member fails requirements THEN Nakama SHALL reject entry and return specific failures per member
- WHEN all members meet requirements THEN Nakama SHALL create a match instance and teleport all party members simultaneously
- IF a party member is disconnected during entry THEN Nakama SHALL hold their slot for the rejoin grace period (Requirement 10 from main spec)
- WHILE in an instance THEN Nakama SHALL prevent party membership changes (no kicks, no new invites)

**Additional Details**
- **Priority:** High
- **Complexity:** High
- **Dependencies:** Requirement 7 (party creation), instance system (Requirement 9 from main spec), teleportation/handoff
- **Assumptions:** Instance entry requires proximity to portal or party leader command; all members must accept; party is locked during instance

---

### Requirement 12: Party Shared Objectives

**User Story:** As a party member, I want to share quest objectives and progress with my party, so that we can efficiently complete objectives together.

**Acceptance Criteria (EARS)**
- WHEN a party member accepts a quest THEN Nakama SHALL optionally share the quest with all party members who meet prerequisites
- WHILE party members share a quest THEN Nakama SHALL synchronize objective progress (kill counts, collection counts) across all members
- IF a party member completes a shared objective THEN Nakama SHALL credit all nearby party members with the completion
- WHEN the quest is completed THEN Nakama SHALL grant rewards to all eligible party members based on contribution or equal share
- IF a party member is too far away during objective completion THEN Nakama SHALL exclude them from credit based on configurable range

**Additional Details**
- **Priority:** Medium
- **Complexity:** High
- **Dependencies:** Requirement 7 (party creation), quest system (not yet specified, future requirement)
- **Assumptions:** Shared quest range is configurable (e.g., same zone or 100m radius); rewards scale or split based on configuration; credit is proximity-based

---

## Non-Functional Requirements

### Performance Requirements
- WHEN a player activates a skill THEN Nakama SHALL process validation and broadcast results within ≤50ms (p95)
- IF a hotbar configuration is modified THEN Nakama SHALL persist the change within ≤30ms (p95 database write latency)
- WHEN a party is formed or modified THEN Nakama SHALL broadcast updates to all members within ≤100ms
- IF 1000 concurrent players use skills simultaneously THEN Nakama SHALL maintain ≤10ms zone tick budget per Requirement 8 (main spec)

### Security Requirements
- WHEN a player attempts to use a skill THEN Nakama SHALL validate all preconditions server-side to prevent client-side exploits (cooldown manipulation, resource spoofing)
- IF a player modifies hotbar configuration THEN Nakama SHALL validate skill ownership and item existence to prevent invalid assignments
- WHEN a party leader kicks a member THEN Nakama SHALL verify leadership permissions before executing the action
- IF party loot is distributed THEN Nakama SHALL enforce the configured loot mode server-side to prevent loot theft

### Usability Requirements
- WHEN a skill validation fails THEN Nakama SHALL return human-readable error codes (e.g., "Skill on cooldown: 5.2s remaining") for client UI display
- IF a hotbar slot is activated but empty THEN Nakama SHALL return a specific error to prevent client confusion
- WHEN a party invitation is sent THEN Nakama SHALL include party details (leader name, size, objective) for informed acceptance
- IF a player is invited while already in a party THEN Nakama SHALL return a clear rejection reason

### Reliability Requirements
- WHEN hotbar configuration persistence fails THEN Nakama SHALL retry with exponential backoff and cache changes in memory until successful
- IF a party state becomes corrupted THEN Nakama SHALL detect inconsistencies and auto-disband or restore from last valid state
- WHEN a player disconnects from a party THEN Nakama SHALL maintain party state for rejoin grace period (configurable, default 5 minutes)
- IF a skill cooldown state is lost (server crash) THEN Nakama SHALL restore cooldowns from last checkpoint or default to ready state

---

## Constraints and Assumptions

### Technical Constraints
- Skills, hotbars, and parties must integrate with existing character, combat, inventory, and instance systems
- Database schema must support optimistic locking for concurrent hotbar modifications
- Party state must be in-memory for low-latency updates but persist periodically for crash recovery
- Skill configuration (stats, cooldowns, costs) is data-driven (JSON or database tables)

### Business Constraints
- Party size is limited to 5 players (no raid groups in initial release)
- Hotbar slots are limited to 36 per character (3 bars × 12 slots), with potential for premium expansion
- Skill trees and talent specializations are out of scope (future enhancement)
- Cross-server party formation is not supported (single-shard limitation)

### Assumptions
- Players have limited skill slots (e.g., 20-30 learned skills max) to prevent hotbar clutter
- Macros are text-based command sequences, not scriptable (to prevent exploits)
- Party loot distribution defaults to "round-robin" for simplicity
- Skill cooldowns are per-skill (no global cooldown in initial release)
- Hotbar state persists across character relogs but not across character deletion

---

## Success Criteria

### Definition of Done
- All acceptance criteria are met and validated through integration tests
- Skills can be learned, leveled, and validated server-side without exploits
- Hotbar configurations persist and activate skills/items/macros correctly
- Parties can be formed, managed, and used for instance entry and loot distribution
- Performance benchmarks are met (≤50ms skill activation, ≤30ms hotbar persistence)
- Godot client SDK examples demonstrate skill usage, hotbar management, and party UI

### Acceptance Metrics
- Skill validation latency: p95 ≤50ms, p99 ≤100ms
- Hotbar persistence latency: p95 ≤30ms (per existing DB target)
- Party update broadcast latency: p95 ≤100ms
- Zero skill cooldown exploits in penetration testing
- Zero item duplication exploits via hotbar or party loot
- ≥95% hotbar configuration save success rate
- ≥99% party state consistency (no corrupted party rosters)

---

## Glossary

| Term | Definition |
|---|---|
| **Skill** | A character ability with specific effects (damage, healing, buffs), resource costs, cooldowns, and targeting requirements |
| **Hotbar** | Customizable action bar with slots (typically 12 per bar) for quick activation of skills, items, and macros |
| **Macro** | Text-based command sequence stored in a hotbar slot (e.g., "/cast Fireball; /use Mana Potion") |
| **Party** | Group of up to 5 players with shared chat, objectives, loot distribution, and instance entry |
| **Party Leader** | Player with elevated privileges (invite, kick, promote, change loot mode, initiate instance entry) |
| **Loot Mode** | Party configuration for distributing loot (round-robin, need-before-greed, master looter, free-for-all) |
| **Skill Tree** | Visual representation of skill dependencies and progression (client-side rendering, server-side data) |
| **Cooldown** | Time period after skill usage during which the skill cannot be activated again |
| **Cast Time** | Duration required to channel a skill before activation (can be interrupted) |
| **LoS** | Line of Sight - spatial validation ensuring no obstacles block skill targeting |
| **AOI** | Area of Interest - spatial region around a player for receiving entity updates (per Requirement 8, main spec) |

---

## Requirements Review Checklist

### Completeness
- ✅ All user stories have clear roles, features, and benefits
- ✅ Each requirement has specific acceptance criteria using EARS format
- ✅ Non-functional requirements are addressed (performance, security, usability, reliability)
- ✅ Success criteria are defined and measurable
- ✅ Integration with existing systems (combat, inventory, instance) is specified

### Quality
- ✅ Requirements are written in active voice with SHALL statements
- ✅ Each acceptance criterion is testable (validation, latency, persistence)
- ✅ Requirements avoid implementation details (focus on what, not how)
- ✅ Terminology is consistent and defined in glossary

### EARS Format Validation
- ✅ WHEN statements describe specific events (player activates skill, hotbar modified)
- ✅ IF statements describe clear conditions (skill meets requirements, slot is empty)
- ✅ WHILE statements describe continuous behaviors (cooldown is active, in party)
- ✅ WHERE statements are used contextually (not heavily used in this spec)
- ✅ All system responses use SHALL

### Clarity
- ✅ Requirements are unambiguous with specific examples
- ✅ Technical jargon is explained in glossary
- ✅ Stakeholders can understand all requirements
- ✅ No conflicting requirements (party size, loot modes, skill validation)

### Traceability
- ✅ Requirements are numbered (Requirement 1-12)
- ✅ Dependencies on main spec requirements are clearly stated (Requirement 6, 9, 12, 14, 17)
- ✅ Requirements link to business objectives (engagement, social gameplay, content accessibility)
- ✅ Assumptions and constraints are documented

---

**Do the requirements look good? If so, we can move on to the next phase.**
