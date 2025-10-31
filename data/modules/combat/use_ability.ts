/**
 * Ability Usage Module
 *
 * Implements server-authoritative ability validation and execution.
 *
 * Phase 3, Task: 3.3.2 - Implement use_ability RPC
 * Requirements: 6 (Server-Authoritative Combat and Abilities)
 * Design: Movement & Combat Service (lines 272-318), Validation (lines 1440-1462)
 *
 * This module processes ability usage requests from clients, validates them against
 * cooldowns, resource costs, range, and line-of-sight, then applies effects and
 * broadcasts results to all clients in the Area of Interest.
 */

import { Position } from '../world/types';
import { getAbility, AbilityConfig } from './ability_config';

// Helper to work around Object.entries typing issue in ES2015
function objectEntries<T>(obj: { [key: string]: T }): [string, T][] {
  return Object.keys(obj).map(key => [key, obj[key]] as [string, T]);
}

/**
 * Client ability usage intent.
 * Sent by client when player attempts to use an ability.
 */
export interface AbilityIntent {
  /** Ability identifier from ability configuration */
  abilityId: string;

  /** Target entity ID */
  targetId: string;

  /** Client timestamp when intent was generated (ms) */
  timestamp: number;

  /** Unique nonce for client reconciliation */
  nonce: number;
}

/**
 * Server response to ability usage.
 * Includes success status, damage/healing values, and cooldown information.
 */
export interface AbilityResult {
  /** Whether ability was successfully executed */
  success: boolean;

  /** Damage dealt (if applicable) */
  damage?: number;

  /** Healing applied (if applicable) */
  healing?: number;

  /** Whether a critical hit occurred */
  criticalHit: boolean;

  /** Cooldown duration triggered (milliseconds) */
  cooldownTriggered: number;

  /** Error code if ability failed */
  errorCode?: string;

  /** Echo of client nonce for reconciliation */
  nonce: number;
}

/**
 * Character stats for combat calculations.
 * Task 3.3.3: Used for damage formula (base damage + crit chance + resistances + buffs/debuffs)
 */
interface CombatStats {
  attack: number; // Base attack power
  defense: number; // Physical defense
  critChance: number; // Critical hit chance (0.0 - 1.0)
  critDamage: number; // Critical damage multiplier
  fireResist: number; // Fire element resistance (0.0 - 1.0)
  iceResist: number; // Ice element resistance
  poisonResist: number; // Poison element resistance
  physicalResist: number; // Physical damage resistance
}

/**
 * Active buff/debuff effect.
 * Task 3.3.3: Applied during damage calculation
 */
interface ActiveEffect {
  effectId: string;
  type: 'buff' | 'debuff';
  stat: string; // attack, defense, critChance, etc.
  modifier: number; // Additive modifier (can be negative for debuffs)
  expiresAt: number; // Timestamp when effect expires
}

/**
 * Character context loaded from database.
 * Includes position, stats, cooldown state, and active effects.
 * Task 3.3.3: Enhanced with combat stats for damage calculation
 */
interface CharacterContext {
  characterId: string;
  position: Position;
  zoneId: string;
  vitals: {
    health: number;
    maxHealth: number;
    mana: number;
    maxMana: number;
  };
  stats: CombatStats;
  activeEffects: ActiveEffect[];
  cooldowns: Record<string, number>; // ability_id -> expires_at timestamp
}

/**
 * Target entity context.
 * Includes position, vitals, and defensive stats for damage calculation.
 * Task 3.3.3: Enhanced with combat stats and active effects
 */
interface TargetContext {
  entityId: string;
  position: Position;
  vitals: {
    health: number;
    maxHealth: number;
  };
  stats: CombatStats;
  activeEffects: ActiveEffect[];
}

/**
 * Validation result for ability usage.
 */
interface ValidationResult {
  valid: boolean;
  error?: string;
}

/**
 * Calculate 3D distance between two positions.
 * Handles both 2D (z optional) and 3D positions.
 *
 * @param pos1 First position
 * @param pos2 Second position
 * @returns Distance in units
 */
function calculateDistance(pos1: Position, pos2: Position): number {
  const dx = pos1.x - pos2.x;
  const dy = pos1.y - pos2.y;
  const dz = (pos1.z || 0) - (pos2.z || 0);
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

/**
 * Check if there is line-of-sight between two positions.
 *
 * Simplified implementation for Phase 3.3.2.
 * TODO: Implement proper raycast collision detection in future phases.
 *
 * @param source Source position
 * @param target Target position
 * @returns true if line-of-sight exists
 */
function hasLineOfSight(source: Position, target: Position): boolean {
  // Placeholder: Always return true for initial implementation
  // In production, this would raycast through terrain/obstacles
  // TODO Phase 4: Integrate with physics engine for actual LoS checks
  return true;
}

/**
 * Validate ability usage against all server-side checks.
 *
 * Requirement 6: Validates ability_id, target_id, cooldown state,
 * resource costs, range, and line-of-sight.
 *
 * @param ability Ability configuration
 * @param source Source character context
 * @param target Target entity context
 * @returns Validation result with error if invalid
 */
function validateAbilityUse(
  ability: AbilityConfig,
  source: CharacterContext,
  target: TargetContext
): ValidationResult {
  // Check cooldown
  const cooldownExpiry = source.cooldowns[ability.id] || 0;
  if (cooldownExpiry > Date.now()) {
    return { valid: false, error: 'ABILITY_ON_COOLDOWN' };
  }

  // Check resource cost
  if (source.vitals.mana < ability.cost) {
    return { valid: false, error: 'INSUFFICIENT_MANA' };
  }

  // Check range
  const distance = calculateDistance(source.position, target.position);
  if (distance > ability.range) {
    return { valid: false, error: 'OUT_OF_RANGE' };
  }

  // Check line of sight
  if (!hasLineOfSight(source.position, target.position)) {
    return { valid: false, error: 'NO_LINE_OF_SIGHT' };
  }

  return { valid: true };
}

/**
 * Calculate effective stat value with active buffs/debuffs.
 *
 * Task 3.3.3: Applies all active effects that modify the specified stat.
 *
 * @param baseStat Base stat value
 * @param statName Stat name to check (attack, defense, critChance, etc.)
 * @param effects Active effects to apply
 * @returns Modified stat value
 */
function applyStatModifiers(
  baseStat: number,
  statName: string,
  effects: ActiveEffect[]
): number {
  let modifiedStat = baseStat;

  for (const effect of effects) {
    if (effect.stat === statName && effect.expiresAt > Date.now()) {
      modifiedStat += effect.modifier;
    }
  }

  return modifiedStat;
}

/**
 * Calculate critical hit chance and damage multiplier.
 *
 * Task 3.3.3: Enhanced to use source character stats with buffs/debuffs.
 *
 * @param source Source character context
 * @returns Object with isCrit flag and damage multiplier
 */
function calculateCritical(source: CharacterContext): { isCrit: boolean; multiplier: number } {
  // Get effective crit chance with buffs/debuffs
  const effectiveCritChance = applyStatModifiers(
    source.stats.critChance,
    'critChance',
    source.activeEffects
  );

  // Get effective crit damage multiplier
  const effectiveCritDamage = applyStatModifiers(
    source.stats.critDamage,
    'critDamage',
    source.activeEffects
  );

  // Clamp crit chance between 0% and 100%
  const critChance = Math.max(0, Math.min(1.0, effectiveCritChance));

  const isCrit = Math.random() < critChance;
  return {
    isCrit,
    multiplier: isCrit ? effectiveCritDamage : 1.0,
  };
}

/**
 * Calculate final damage with formula: base damage + crit + resistances + buffs/debuffs.
 *
 * Task 3.3.3: Server-side damage formula per Requirement 6 and design.md.
 *
 * Formula:
 * - Base damage from ability effect
 * - Critical hit multiplier (from source stats)
 * - Element resistance reduction (target resistances)
 * - Attack buffs (source buffs)
 * - Vulnerability debuffs (target debuffs)
 *
 * @param baseDamage Base damage from ability effect
 * @param element Damage element type
 * @param critMultiplier Critical hit damage multiplier
 * @param source Source character context
 * @param target Target entity context
 * @returns Final calculated damage
 */
function calculateDamage(
  baseDamage: number,
  element: string,
  critMultiplier: number,
  source: CharacterContext,
  target: TargetContext
): number {
  // Apply critical hit multiplier
  let damage = baseDamage * critMultiplier;

  // Get effective attack stat with buffs/debuffs
  const effectiveAttack = applyStatModifiers(
    source.stats.attack,
    'attack',
    source.activeEffects
  );
  const attackModifier = effectiveAttack / 10.0; // Scale attack (10 attack = 1.0x, 20 attack = 2.0x)
  damage *= attackModifier;

  // Apply element resistance
  let resistance = 0;
  switch (element) {
    case 'fire':
      resistance = target.stats.fireResist;
      break;
    case 'ice':
      resistance = target.stats.iceResist;
      break;
    case 'poison':
      resistance = target.stats.poisonResist;
      break;
    case 'physical':
    default:
      resistance = target.stats.physicalResist;
      break;
  }

  // Clamp resistance between 0 and 0.9 (max 90% reduction)
  resistance = Math.max(0, Math.min(0.9, resistance));
  damage *= (1.0 - resistance);

  // Apply vulnerability debuffs on target
  const vulnerabilityModifier = applyStatModifiers(
    0,
    'vulnerability',
    target.activeEffects
  );
  damage *= (1.0 + vulnerabilityModifier);

  return Math.max(0, Math.floor(damage)); // Minimum 0, round down
}

/**
 * Apply ability effects to target.
 *
 * Task 3.3.3: Enhanced damage calculation with resistances and buffs/debuffs.
 * Requirement 6: Server-side formula: base damage + crit chance + resistances + buffs/debuffs.
 *
 * @param ability Ability configuration
 * @param source Source character context
 * @param target Target entity context
 * @param critMultiplier Critical hit damage multiplier
 * @returns Object with damage and healing values
 */
function applyAbilityEffects(
  ability: AbilityConfig,
  source: CharacterContext,
  target: TargetContext,
  critMultiplier: number
): { damage: number; healing: number } {
  let totalDamage = 0;
  let totalHealing = 0;

  for (const effect of ability.effects) {
    switch (effect.type) {
      case 'damage':
        const element = effect.element || 'physical';
        const damage = calculateDamage(
          effect.value,
          element,
          critMultiplier,
          source,
          target
        );
        totalDamage += damage;
        break;
      case 'heal':
        totalHealing += effect.value;
        break;
      case 'buff':
      case 'debuff':
        // TODO Phase 3.3.4: Implement buff/debuff application to active effects
        break;
    }
  }

  return { damage: totalDamage, healing: totalHealing };
}

/**
 * Load character context from database.
 *
 * @param nk Nakama runtime API
 * @param userId User ID from context
 * @param logger Logger instance
 * @returns Character context or null if not found
 */
function loadCharacterContext(
  nk: any,
  userId: string,
  logger: any
): CharacterContext | null {
  try {
    const result = nk.sqlQuery(`
      SELECT character_id, last_position, last_zone_id, stats
      FROM characters
      WHERE account_id = $1
      ORDER BY last_login_at DESC
      LIMIT 1
    `, [userId]);

    if (result.length === 0) {
      return null;
    }

    const row = result[0];
    const position = JSON.parse(row.last_position);
    const stats = JSON.parse(row.stats);

    // Load cooldowns from character state (Task 3.3.4: Persistent cooldown storage)
    const cooldowns: Record<string, number> = {};
    if (stats.cooldowns && typeof stats.cooldowns === 'object') {
      // Parse cooldowns from JSONB: { ability_id: expires_at_timestamp }
      for (const [abilityId, expiresAt] of objectEntries(stats.cooldowns)) {
        cooldowns[abilityId] = Number(expiresAt);
      }
    }

    // Parse combat stats (Task 3.3.3)
    const combatStats: CombatStats = {
      attack: stats.attack || 10,
      defense: stats.defense || 5,
      critChance: stats.critChance || 0.10, // Default 10%
      critDamage: stats.critDamage || 2.0, // Default 2.0x
      fireResist: stats.fireResist || 0,
      iceResist: stats.iceResist || 0,
      poisonResist: stats.poisonResist || 0,
      physicalResist: stats.physicalResist || 0,
    };

    // Load active effects (Task 3.3.3)
    const activeEffects: ActiveEffect[] = (stats.activeEffects || []).map((e: any) => ({
      effectId: e.effectId,
      type: e.type,
      stat: e.stat,
      modifier: e.modifier,
      expiresAt: e.expiresAt,
    }));

    return {
      characterId: row.character_id,
      position,
      zoneId: row.last_zone_id,
      vitals: {
        health: stats.health || 100,
        maxHealth: stats.maxHealth || 100,
        mana: stats.mana || 100,
        maxMana: stats.maxMana || 100,
      },
      stats: combatStats,
      activeEffects,
      cooldowns,
    };
  } catch (error) {
    logger.error(`Failed to load character context: ${error}`);
    return null;
  }
}

/**
 * Load target entity context.
 *
 * @param nk Nakama runtime API
 * @param targetId Target entity ID
 * @param zoneId Zone ID for validation
 * @param logger Logger instance
 * @returns Target context or null if not found
 */
function loadTargetContext(
  nk: any,
  targetId: string,
  zoneId: string,
  logger: any
): TargetContext | null {
  try {
    // Query target from characters table (player targets)
    const result = nk.sqlQuery(`
      SELECT character_id, last_position, stats
      FROM characters
      WHERE character_id = $1 AND last_zone_id = $2
    `, [targetId, zoneId]);

    if (result.length === 0) {
      // TODO: Query NPCs/entities from zone state in future phases
      logger.warn(`Target not found: ${targetId} in zone ${zoneId}`);
      return null;
    }

    const row = result[0];
    const position = JSON.parse(row.last_position);
    const stats = JSON.parse(row.stats);

    // Parse combat stats (Task 3.3.3)
    const combatStats: CombatStats = {
      attack: stats.attack || 10,
      defense: stats.defense || 5,
      critChance: stats.critChance || 0.10,
      critDamage: stats.critDamage || 2.0,
      fireResist: stats.fireResist || 0,
      iceResist: stats.iceResist || 0,
      poisonResist: stats.poisonResist || 0,
      physicalResist: stats.physicalResist || 0,
    };

    // Load active effects (Task 3.3.3)
    const activeEffects: ActiveEffect[] = (stats.activeEffects || []).map((e: any) => ({
      effectId: e.effectId,
      type: e.type,
      stat: e.stat,
      modifier: e.modifier,
      expiresAt: e.expiresAt,
    }));

    return {
      entityId: row.character_id,
      position,
      vitals: {
        health: stats.health || 100,
        maxHealth: stats.maxHealth || 100,
      },
      stats: combatStats,
      activeEffects,
    };
  } catch (error) {
    logger.error(`Failed to load target context: ${error}`);
    return null;
  }
}

/**
 * Update character stats after ability usage.
 *
 * @param nk Nakama runtime API
 * @param characterId Character ID
 * @param manaCost Mana cost to deduct
 * @param cooldownExpiry Cooldown expiry timestamp
 * @param abilityId Ability ID
 * @param logger Logger instance
 */
function updateCharacterStats(
  nk: any,
  characterId: string,
  manaCost: number,
  cooldownExpiry: number,
  abilityId: string,
  logger: any
): void {
  try {
    // Task 3.3.4: Persist cooldown to database with mana update
    nk.sqlExec(`
      UPDATE characters
      SET stats = jsonb_set(
        jsonb_set(
          stats,
          '{mana}',
          to_jsonb((stats->>'mana')::int - $1)
        ),
        '{cooldowns, ${abilityId}}',
        to_jsonb($3)
      )
      WHERE character_id = $2
    `, [manaCost, characterId, cooldownExpiry]);

    logger.info(`Applied ability ${abilityId} for character ${characterId}, mana cost: ${manaCost}, cooldown expires: ${cooldownExpiry}`);
  } catch (error) {
    logger.error(`Failed to update character stats: ${error}`);
    throw error;
  }
}

/**
 * Update target vitals after damage/healing.
 *
 * Task 3.3.5: Returns final health for death check.
 *
 * @param nk Nakama runtime API
 * @param targetId Target entity ID
 * @param damage Damage to apply
 * @param healing Healing to apply
 * @param logger Logger instance
 * @returns Final health value after damage/healing
 */
function updateTargetVitals(
  nk: any,
  targetId: string,
  damage: number,
  healing: number,
  logger: any
): number {
  try {
    let finalHealth = 0;

    if (damage > 0) {
      const result = nk.sqlQuery(`
        UPDATE characters
        SET stats = jsonb_set(
          stats,
          '{health}',
          to_jsonb(GREATEST(0, (stats->>'health')::int - $1))
        )
        WHERE character_id = $2
        RETURNING (stats->>'health')::int AS health
      `, [damage, targetId]);

      finalHealth = result.length > 0 ? result[0].health : 0;
    }

    if (healing > 0) {
      const result = nk.sqlQuery(`
        UPDATE characters
        SET stats = jsonb_set(
          stats,
          '{health}',
          to_jsonb(LEAST((stats->>'maxHealth')::int, (stats->>'health')::int + $1))
        )
        WHERE character_id = $2
        RETURNING (stats->>'health')::int AS health
      `, [healing, targetId]);

      finalHealth = result.length > 0 ? result[0].health : 0;
    }

    logger.info(`Updated target ${targetId} vitals: damage=${damage}, healing=${healing}, finalHealth=${finalHealth}`);
    return finalHealth;
  } catch (error) {
    logger.error(`Failed to update target vitals: ${error}`);
    throw error;
  }
}

/**
 * Check if target died and trigger death logic.
 *
 * Task 3.3.5: Death logic implementation.
 * Requirement 6: Trigger death logic (respawn, loot drops) when HP ≤ 0.
 *
 * @param nk Nakama runtime API
 * @param targetId Target entity ID
 * @param finalHealth Final health after damage
 * @param sourceId Source character ID (attacker)
 * @param logger Logger instance
 * @returns True if target died
 */
function checkDeath(
  nk: any,
  targetId: string,
  finalHealth: number,
  sourceId: string,
  logger: any
): boolean {
  if (finalHealth > 0) {
    return false; // Target still alive
  }

  logger.info(`[death] Character ${targetId} died, killed by ${sourceId}`);

  try {
    // Set respawn timer (grace period: 10 seconds)
    const respawnTime = Date.now() + 10000; // 10 seconds grace period

    // Update character with death state and respawn timer
    nk.sqlExec(`
      UPDATE characters
      SET stats = jsonb_set(
        jsonb_set(
          stats,
          '{isDead}',
          'true'
        ),
        '{respawnAt}',
        to_jsonb($1)
      )
      WHERE character_id = $2
    `, [respawnTime, targetId]);

    // TODO Phase 4, Task 4.6.3: Generate loot from drop tables
    // For now, log a placeholder loot event
    logger.info(`[death] Loot generation placeholder for ${targetId} (full implementation in Phase 4)`);

    // Log death event for analytics and zone persistence
    // This will be picked up by ZoneProcess event logging (Task 2.2.3)
    logger.info(`[death] Death event: target=${targetId}, killer=${sourceId}, respawnAt=${respawnTime}`);

    return true;
  } catch (error) {
    logger.error(`Failed to process death logic: ${error}`);
    throw error;
  }
}

/**
 * Respawn character at respawn anchor.
 *
 * Task 3.3.5: Respawn logic (grace period completed).
 * Note: This function will be called by a scheduled job or when player requests respawn.
 *
 * @param nk Nakama runtime API
 * @param characterId Character ID to respawn
 * @param logger Logger instance
 */
async function respawnCharacter(
  nk: any,
  characterId: string,
  logger: any
): Promise<void> {
  try {
    // Get character's last zone for respawn anchor
    const charResult = nk.sqlQuery(`
      SELECT last_zone_id, stats
      FROM characters
      WHERE character_id = $1
    `, [characterId]);

    if (charResult.length === 0) {
      logger.error(`[respawn] Character not found: ${characterId}`);
      return;
    }

    const stats = JSON.parse(charResult[0].stats);
    const maxHealth = stats.maxHealth || 100;

    // Respawn at full health, clear death state
    // TODO: Fetch respawn anchor position from zone_boundaries table
    // For now, use last known position
    nk.sqlExec(`
      UPDATE characters
      SET stats = jsonb_set(
        jsonb_set(
          jsonb_set(
            stats,
            '{health}',
            to_jsonb($1)
          ),
          '{isDead}',
          'false'
        ),
        '{respawnAt}',
        'null'
      )
      WHERE character_id = $2
    `, [maxHealth, characterId]);

    logger.info(`[respawn] Character ${characterId} respawned at full health`);
  } catch (error) {
    logger.error(`Failed to respawn character: ${error}`);
    throw error;
  }
}

/**
 * Broadcast ability result to players in AOI
 * Task 3.3.6: Broadcast ability results
 *
 * Sends ability result event to all players in the same zone.
 * This enables nearby players to see combat effects (damage numbers, particles, etc.)
 *
 * Requirements: 6 (Server-Authoritative Combat - broadcast results)
 * Requirements: 8 (AOI Management - filter by proximity)
 *
 * @param nk Nakama runtime API
 * @param logger Logger instance
 * @param zoneId Zone where ability was used
 * @param sourceId Character who used the ability
 * @param targetId Character who was targeted
 * @param abilityId Ability identifier
 * @param damage Damage dealt (0 if none)
 * @param healing Healing applied (0 if none)
 * @param criticalHit Whether a critical hit occurred
 * @param isDead Whether target died from this ability
 */
function broadcastAbilityResult(
  nk: any,
  logger: any,
  zoneId: string,
  sourceId: string,
  targetId: string,
  abilityId: string,
  damage: number,
  healing: number,
  criticalHit: boolean,
  isDead: boolean
): void {
  try {
    // Create ability result event
    const event = {
      type: 'ability_result',
      zoneId,
      sourceId,
      targetId,
      abilityId,
      damage,
      healing,
      criticalHit,
      isDead,
      timestamp: Date.now()
    };

    // Query all characters in the same zone to get their user IDs
    const result = nk.sqlQuery(`
      SELECT user_id
      FROM characters
      WHERE last_zone_id = $1 AND user_id IS NOT NULL
    `, [zoneId]);

    if (result.rows && result.rows.length > 0) {
      // Send notification to all users in zone
      // This broadcasts combat results to nearby players for visualization
      const notifications = result.rows.map((row: any) => ({
        userId: row.user_id,
        subject: 'ability_result',
        content: event,
        code: 100, // Op code for ability result events
        persistent: false, // Don't persist to database
        senderId: '' // System event
      }));

      // Send all notifications
      nk.notificationsSend(notifications);

      logger.debug(`[use_ability] Broadcast ability result to ${result.rows.length} players in zone ${zoneId}`);
    }

  } catch (error) {
    // Non-critical error - log but don't throw
    logger.error(`Failed to broadcast ability result: ${error}`);
  }
}

/**
 * RPC: use_ability
 *
 * Server-authoritative ability validation and execution.
 *
 * Requirements: 6 (Server-Authoritative Combat and Abilities)
 * - Validates: ability_id, target_id, cooldown, resource cost, range, line-of-sight
 * - Applies: damage/healing, updates vitals, triggers cooldowns
 * - Broadcasts: result to AOI subscribers
 *
 * @param ctx Nakama context
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with AbilityIntent
 * @returns JSON response with AbilityResult
 */
export function rpcUseAbility(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  logger.info(`[use_ability] Request from user ${ctx.userId}`);

  // Parse request
  let intent: AbilityIntent;
  try {
    intent = JSON.parse(payload) as AbilityIntent;
  } catch (error) {
    logger.error(`[use_ability] Invalid JSON payload: ${error}`);
    return JSON.stringify({
      success: false,
      criticalHit: false,
      cooldownTriggered: 0,
      errorCode: 'INVALID_PAYLOAD',
      nonce: 0,
    });
  }

  // Validate ability exists
  const ability = getAbility(intent.abilityId);
  if (!ability) {
    logger.warn(`[use_ability] Unknown ability: ${intent.abilityId}`);
    return JSON.stringify({
      success: false,
      criticalHit: false,
      cooldownTriggered: 0,
      errorCode: 'UNKNOWN_ABILITY',
      nonce: intent.nonce,
    });
  }

  // Load source character context
  const source = loadCharacterContext(nk, ctx.userId, logger);
  if (!source) {
    logger.warn(`[use_ability] Character not found for user ${ctx.userId}`);
    return JSON.stringify({
      success: false,
      criticalHit: false,
      cooldownTriggered: 0,
      errorCode: 'CHARACTER_NOT_FOUND',
      nonce: intent.nonce,
    });
  }

  // Load target context
  const target = loadTargetContext(nk, intent.targetId, source.zoneId, logger);
  if (!target) {
    logger.warn(`[use_ability] Target not found: ${intent.targetId}`);
    return JSON.stringify({
      success: false,
      criticalHit: false,
      cooldownTriggered: 0,
      errorCode: 'TARGET_NOT_FOUND',
      nonce: intent.nonce,
    });
  }

  // Validate ability usage
  const validation = validateAbilityUse(ability, source, target);
  if (!validation.valid) {
    logger.info(`[use_ability] Validation failed: ${validation.error}`);
    return JSON.stringify({
      success: false,
      criticalHit: false,
      cooldownTriggered: 0,
      errorCode: validation.error,
      nonce: intent.nonce,
    });
  }

  // Calculate critical hit (Task 3.3.3: Enhanced with source stats)
  const crit = calculateCritical(source);

  // Apply ability effects (Task 3.3.3: Enhanced damage formula)
  const effects = applyAbilityEffects(ability, source, target, crit.multiplier);

  // Update character stats (mana cost, cooldown)
  const cooldownExpiry = Date.now() + ability.cooldown;
  updateCharacterStats(nk, source.characterId, ability.cost, cooldownExpiry, ability.id, logger);

  // Update target vitals (Task 3.3.5: Returns final health for death check)
  const finalHealth = updateTargetVitals(nk, target.entityId, effects.damage, effects.healing, logger);

  // Check for death (Task 3.3.5: Death logic)
  const targetDied = checkDeath(nk, target.entityId, finalHealth, source.characterId, logger);

  // Task 3.3.6: Broadcast ability result to AOI subscribers
  broadcastAbilityResult(
    nk,
    logger,
    source.zoneId,
    source.characterId,
    target.entityId,
    ability.id,
    effects.damage,
    effects.healing,
    crit.isCrit,
    targetDied
  );

  // Return success result
  const result: AbilityResult = {
    success: true,
    damage: effects.damage > 0 ? effects.damage : undefined,
    healing: effects.healing > 0 ? effects.healing : undefined,
    criticalHit: crit.isCrit,
    cooldownTriggered: ability.cooldown,
    nonce: intent.nonce,
  };

  logger.info(`[use_ability] Success: ability=${ability.id}, damage=${effects.damage}, healing=${effects.healing}, crit=${crit.isCrit}`);
  return JSON.stringify(result);
}

/**
 * Initialize use_ability module
 * Registers RPC handler with Nakama runtime
 *
 * @param ctx Nakama context
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param initializer Nakama initializer
 */
export function InitModule(
  ctx: any,
  logger: any,
  nk: any,
  initializer: any
): void {
  initializer.registerRpc('use_ability', rpcUseAbility);
  logger.info('[use_ability] Module initialized');
}
