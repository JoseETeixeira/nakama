/**
 * Ability Configuration Loader
 *
 * Loads ability templates from JSON config files at runtime startup.
 * Provides server-side ability validation for use_ability RPC.
 *
 * Phase 3, Task: 3.3.1 - Create ability configuration data
 * Requirements: 6 (Server-Authoritative Combat and Abilities)
 * Design: Movement & Combat Service (lines 272-318)
 */

// Nakama runtime global declarations
declare const require: any;
declare const __dirname: any;

/**
 * Ability effect definition
 */
export interface AbilityEffect {
  type: 'damage' | 'heal' | 'buff' | 'debuff';
  element?: string; // fire, ice, poison, physical, etc.
  stat?: string; // hp_regen, defense, attack, etc.
  value: number;
  duration?: number; // milliseconds (for buffs/debuffs)
}

/**
 * Ability configuration template
 * Loaded from abilities.json
 */
export interface AbilityConfig {
  id: string;
  name: string;
  cooldown: number; // milliseconds
  cost: number; // resource cost (mana/MP)
  range: number; // units
  damage?: number; // optional base damage
  healing?: number; // optional healing amount
  effects: AbilityEffect[];
}

interface AbilityData {
  abilities: AbilityConfig[];
}

// In-memory ability registry
const abilityRegistry = new Map<string, AbilityConfig>();

/**
 * Initialize ability configuration from JSON file
 * Called during runtime startup (InitModule)
 *
 * @param logger Nakama logger instance
 */
export function initAbilityConfig(logger: any): void {
  try {
    // Load abilities from JSON config
    // Note: abilities.json is loaded via Nakama's module system
    const fs: any = require('fs');
    const path: any = require('path');

    // Path relative to data/modules/combat/
    const configPath = path.join(__dirname as any, 'abilities.json');
    const configData = fs.readFileSync(configPath, 'utf8');
    const abilityData: AbilityData = JSON.parse(configData);

    // Register all abilities
    for (const ability of abilityData.abilities) {
      abilityRegistry.set(ability.id, ability);
      logger.info(`Registered ability: ${ability.id} (${ability.name})`);
    }

    logger.info(`Ability configuration loaded: ${abilityRegistry.size} abilities`);
  } catch (error) {
    logger.error(`Failed to load ability configuration: ${error}`);
    throw error;
  }
}

/**
 * Get ability configuration by ID
 * Returns null if ability doesn't exist
 */
export function getAbility(abilityId: string): AbilityConfig | null {
  return abilityRegistry.get(abilityId) || null;
}

/**
 * Get all registered abilities
 */
export function getAllAbilities(): AbilityConfig[] {
  return Array.from(abilityRegistry.values());
}

/**
 * Check if ability exists
 */
export function hasAbility(abilityId: string): boolean {
  return abilityRegistry.has(abilityId);
}

/**
 * Get ability count (for diagnostics)
 */
export function getAbilityCount(): number {
  return abilityRegistry.size;
}
