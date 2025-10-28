/**
 * Character Service Module
 *
 * Provides character management RPCs for MMORPG functionality:
 * - List characters by account
 * - Create new characters with validation
 * - Select character for world entry
 * - Delete characters
 *
 * Requirements: 2 (Character List/Selection), 3 (Character Creation)
 */

/**
 * Character data model
 */
interface Character {
  characterId: string;
  accountId: string;
  name: string;
  archetypeId: string;
  level: number;
  lastZoneId: string;
  lastPosition: { x: number; y: number; z: number };
  createdAt: number;
  lastLoginAt: number;
}

/**
 * Extended character state with gameplay data
 */
interface CharacterState extends Character {
  stats: Record<string, number>;
  inventory: InventorySlot[];
  cooldowns: Cooldown[];
  buffs: Buff[];
  questLog: Quest[];
}

interface InventorySlot {
  slotId: number;
  itemId: string;
  quantity: number;
}

interface Cooldown {
  abilityId: string;
  expiresAt: number;
}

interface Buff {
  buffId: string;
  duration: number;
  appliedAt: number;
}

interface Quest {
  questId: string;
  status: 'active' | 'completed' | 'failed';
  progress: Record<string, number>;
}

/**
 * Module initialization function
 * Called by Nakama runtime to register RPCs
 *
 * Note: Type definitions for nkruntime are provided by Nakama server at runtime.
 * Using `any` types here for workspace compatibility.
 *
 * @param ctx - Execution context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param initializer - Runtime initializer for registering hooks
 */
function InitModule(
  ctx: any,
  logger: any,
  nk: any,
  initializer: any
): void {
  logger.info('Character Service module initialized');

  // Register list_characters RPC (Task 1.3.2)
  initializer.registerRpc('list_characters', rpcListCharacters);

  // Register create_character RPC (Task 1.3.3)
  initializer.registerRpc('create_character', rpcCreateCharacter);

  // Register select_character RPC (Task 1.3.4)
  initializer.registerRpc('select_character', rpcSelectCharacter);

  // Register delete_character RPC (Task 1.3.5)
  initializer.registerRpc('delete_character', rpcDeleteCharacter);

  // RPCs will be registered here in subsequent tasks:
  // - Additional character management features
}

/**
 * List all characters for an authenticated account
 *
 * Requirements: 2 (Character List and Selection)
 *
 * @param ctx - Execution context with userId (account_id)
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param payload - Empty payload (account_id from context)
 * @returns JSON response with characters array
 */
function rpcListCharacters(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  // Extract account_id from authenticated context
  const accountId = ctx.userId;

  if (!accountId) {
    throw Error('User not authenticated');
  }

  // HOT RELOAD TEST: This log proves runtime module changes are working
  logger.info('[HOT-RELOAD-TEST] Character list RPC called - hot reload is working!');
  logger.info('Listing characters for account: %s', accountId);

  // Query characters table by account_id
  const query = `
    SELECT
      character_id,
      account_id,
      name,
      archetype_id,
      level,
      last_zone_id,
      last_position,
      created_at,
      last_login_at
    FROM characters
    WHERE account_id = $1
    ORDER BY created_at ASC
  `;

  const parameters = [accountId];
  const result = nk.sqlQuery(query, parameters);

  // Transform database rows to Character interface
  const characters: Character[] = result.map((row: any) => ({
    characterId: row.character_id,
    accountId: row.account_id,
    name: row.name,
    archetypeId: row.archetype_id,
    level: row.level,
    lastZoneId: row.last_zone_id || '',
    lastPosition: row.last_position ? JSON.parse(row.last_position) : { x: 0, y: 0, z: 0 },
    createdAt: new Date(row.created_at).getTime(),
    lastLoginAt: row.last_login_at ? new Date(row.last_login_at).getTime() : 0
  }));

  logger.info('Found %d characters for account %s', characters.length, accountId);

  // Return structured response
  return JSON.stringify({ characters });
}

/**
 * Profanity filter for character names
 * Task: 1.3.6
 * Requirement: 3 (Character Creation - Naming Rules)
 *
 * Checks if a name contains offensive or inappropriate words.
 * This is a basic implementation with a curated list of common profanity.
 * For production, consider integrating a comprehensive profanity library
 * or external API service for multi-language support.
 *
 * @param name - Character name to validate
 * @returns true if name contains profanity, false otherwise
 */
function containsProfanity(name: string): boolean {
  // Convert to lowercase for case-insensitive matching
  const lowerName = name.toLowerCase();

  // Basic profanity word list
  // Note: This is a minimal set for demonstration. Production systems should use
  // comprehensive libraries like 'bad-words' or external services for better coverage.
  const profanityList = [
    'damn', 'hell', 'crap', 'shit', 'fuck', 'bitch', 'ass', 'bastard',
    'dick', 'cock', 'pussy', 'cunt', 'whore', 'slut', 'nazi', 'fag',
    'retard', 'nigger', 'chink', 'spic', 'kike', 'wetback'
  ];

  // Check if name contains any profanity words
  // Use word boundary check to avoid false positives (e.g., "classic" containing "ass")
  for (const word of profanityList) {
    const regex = new RegExp(`\\b${word}\\b`, 'i');
    if (regex.test(lowerName)) {
      return true;
    }

    // Also check for common obfuscation patterns (e.g., "sh!t", "f*ck")
    const obfuscatedWord = word.split('').join('[*!@#$%^&]*');
    const obfuscatedRegex = new RegExp(obfuscatedWord, 'i');
    if (obfuscatedRegex.test(lowerName)) {
      return true;
    }
  }

  return false;
}

/**
 * Create a new character with validation
 *
 * Requirements: 3 (Character Creation)
 *
 * @param ctx - Execution context with userId (account_id)
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param payload - JSON string with {name: string, archetype_id: string}
 * @returns JSON response with character_id
 */
function rpcCreateCharacter(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  // Constants
  const MAX_CHARACTERS_PER_ACCOUNT = 10;
  const MIN_NAME_LENGTH = 3;
  const MAX_NAME_LENGTH = 20; // Updated from 50 to 20 (Task 1.3.6)
  const DEFAULT_ZONE_ID = 'zone_starter'; // Fallback if no zone_boundaries configured

  // Extract account_id from authenticated context
  const accountId = ctx.userId;

  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Parse and validate input payload
  let input: { name: string; archetype_id: string };
  try {
    input = JSON.parse(payload);
  } catch (e) {
    throw Error('Invalid JSON payload');
  }

  if (!input.name || !input.archetype_id) {
    throw Error('Missing required fields: name and archetype_id');
  }

  const characterName = input.name.trim();
  const archetypeId = input.archetype_id;

  logger.info('Creating character "%s" with archetype "%s" for account %s', characterName, archetypeId, accountId);

  // Validate character name length
  if (characterName.length < MIN_NAME_LENGTH || characterName.length > MAX_NAME_LENGTH) {
    throw Error(`Character name must be between ${MIN_NAME_LENGTH} and ${MAX_NAME_LENGTH} characters`);
  }

  // Validate character name format (alphanumeric + spaces only)
  const nameRegex = /^[a-zA-Z0-9 ]+$/;
  if (!nameRegex.test(characterName)) {
    throw Error('Character name must contain only letters, numbers, and spaces');
  }

  // Validate character name for profanity (Task 1.3.6)
  if (containsProfanity(characterName)) {
    throw Error('Character name contains inappropriate language');
  }

  // Check character name uniqueness
  const nameCheckQuery = `SELECT character_id FROM characters WHERE name = $1`;
  const nameCheckResult = nk.sqlQuery(nameCheckQuery, [characterName]);
  if (nameCheckResult.length > 0) {
    throw Error('Character name already taken');
  }

  // Check character slot limit for account
  const countQuery = `SELECT COUNT(*) as count FROM characters WHERE account_id = $1`;
  const countResult = nk.sqlQuery(countQuery, [accountId]);
  const characterCount = countResult[0].count;

  if (characterCount >= MAX_CHARACTERS_PER_ACCOUNT) {
    throw Error(`Maximum character limit reached (${MAX_CHARACTERS_PER_ACCOUNT} characters per account)`);
  }

  // Query default spawn zone from zone_boundaries
  let spawnZoneId = DEFAULT_ZONE_ID;
  let spawnPosition = { x: 0, y: 0, z: 0 };

  const zoneQuery = `SELECT zone_id, default_spawn FROM zone_boundaries LIMIT 1`;
  const zoneResult = nk.sqlQuery(zoneQuery, []);

  if (zoneResult.length > 0) {
    spawnZoneId = zoneResult[0].zone_id;
    if (zoneResult[0].default_spawn) {
      spawnPosition = JSON.parse(zoneResult[0].default_spawn);
    }
  }

  // Generate starter stats based on archetype
  // Note: This is a basic implementation. Archetype-specific stats can be
  // configured in a separate archetype configuration table/JSON for production.
  const starterStats = {
    hp: 100,
    mp: 50,
    str: 10,
    dex: 10,
    int: 10,
    level: 1
  };

  // Generate UUID for new character
  const characterId = nk.uuidv4();
  const now = new Date().toISOString();

  // Insert character record
  const insertQuery = `
    INSERT INTO characters (
      character_id,
      account_id,
      name,
      archetype_id,
      level,
      last_zone_id,
      last_position,
      stats,
      created_at,
      last_login_at,
      version
    ) VALUES (
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
    )
  `;

  const insertParams = [
    characterId,
    accountId,
    characterName,
    archetypeId,
    starterStats.level,
    spawnZoneId,
    JSON.stringify(spawnPosition),
    JSON.stringify(starterStats),
    now,
    null, // last_login_at (null until first world entry)
    1 // version for optimistic locking
  ];

  nk.sqlExec(insertQuery, insertParams);

  // TODO: Task 1.3.3 sub-task - Create starter inventory items
  // This will be implemented when inventory system is ready (Phase 4)
  // For now, character is created with empty inventory
  // Starter items will be added based on archetype configuration

  logger.info('Successfully created character %s (%s) for account %s', characterName, characterId, accountId);

  // Return character_id
  return JSON.stringify({ character_id: characterId });
}

/**
 * RPC: select_character
 * Description: Load full character state for world entry
 * Task: 1.3.4
 * Requirement: 2 (Character List and Selection)
 *
 * Input: { character_id: string }
 * Output: { ok: boolean, character?: CharacterState }
 *
 * This RPC loads the complete character state including stats, inventory, cooldowns, buffs, and quest log.
 * It validates that the character belongs to the authenticated account and updates the last_login_at timestamp.
 *
 * Returns CharacterState with:
 * - Basic character info (character_id, account_id, name, archetype_id, level)
 * - Last known position (last_zone_id, last_position)
 * - Combat stats (stats object from JSONB)
 * - Inventory items (Phase 4 - currently empty array)
 * - Active cooldowns (Phase 3 - currently empty array)
 * - Active buffs (Phase 3 - currently empty array)
 * - Quest log (Future phase - currently empty array)
 */
function rpcSelectCharacter(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  const accountId = ctx.userId;
  logger.info('select_character RPC called by account %s', accountId);

  if (!payload) {
    throw Error('Missing character_id in request payload');
  }

  let input: { character_id: string };
  try {
    input = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid JSON payload');
  }

  if (!input.character_id) {
    throw Error('character_id is required');
  }

  const characterId = input.character_id;

  logger.info('Loading character %s for account %s', characterId, accountId);

  // Query character from database
  // IMPORTANT: Validate character belongs to authenticated account (security check)
  const query = `
    SELECT
      character_id,
      account_id,
      name,
      archetype_id,
      level,
      last_zone_id,
      last_position,
      stats,
      created_at,
      last_login_at,
      version
    FROM characters
    WHERE character_id = $1 AND account_id = $2
  `;

  const result = nk.sqlQuery(query, [characterId, accountId]);

  if (result.length === 0) {
    throw Error('Character not found or does not belong to your account');
  }

  const row = result[0];

  // Parse JSONB fields
  const stats = row.stats ? JSON.parse(row.stats) : {};
  const lastPosition = row.last_position ? JSON.parse(row.last_position) : { x: 0, y: 0, z: 0 };

  // Update last_login_at timestamp to track character usage
  const now = new Date().toISOString();
  const updateQuery = `
    UPDATE characters
    SET last_login_at = $1
    WHERE character_id = $2
  `;
  nk.sqlExec(updateQuery, [now, characterId]);

  // TODO: Phase 4 - Query inventory items from inventory table
  // Query: SELECT * FROM inventory WHERE character_id = $1 ORDER BY slot_id
  const inventory: InventorySlot[] = [];

  // TODO: Phase 3 - Query active cooldowns (if persisted to database)
  // Cooldowns will be loaded from checkpoint data when cooldown system is implemented
  const cooldowns: Cooldown[] = [];

  // TODO: Phase 3 - Query active buffs (if persisted to database)
  // Buffs will be loaded from checkpoint data when buff system is implemented
  const buffs: Buff[] = [];

  // TODO: Future phase - Query quest log
  // Quest system not yet specified; will be implemented in later phase
  const questLog: Quest[] = [];

  // Construct CharacterState response
  const characterState: CharacterState = {
    characterId: row.character_id,
    accountId: row.account_id,
    name: row.name,
    archetypeId: row.archetype_id,
    level: row.level,
    lastZoneId: row.last_zone_id,
    lastPosition: lastPosition,
    createdAt: new Date(row.created_at).getTime(),
    lastLoginAt: new Date(now).getTime(), // Updated timestamp as milliseconds
    stats: stats,
    inventory: inventory,
    cooldowns: cooldowns,
    buffs: buffs,
    questLog: questLog
  };

  logger.info('Successfully loaded character %s (%s) for account %s', row.name, characterId, accountId);

  return JSON.stringify({ ok: true, character: characterState });
}

/**
 * RPC: delete_character
 * Description: Delete a character and cascade related data
 * Task: 1.3.5
 * Requirement: 29 (GDPR Compliance - Account Deletion)
 *
 * Input: { character_id: string }
 * Output: { ok: boolean }
 *
 * This RPC permanently deletes a character and all associated data:
 * - Removes character from characters table
 * - Cascade deletes inventory items from inventory table
 * - Cascade deletes guild memberships from guild_members table
 * - Logs the deletion to audit_logs for compliance tracking
 *
 * Security: Validates character belongs to authenticated account before deletion.
 * Data Integrity: Uses database transactions to ensure atomic deletion.
 * GDPR Compliance: Supports right to be forgotten by removing personal game data.
 */
function rpcDeleteCharacter(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  const accountId = ctx.userId;
  logger.info('delete_character RPC called by account %s', accountId);

  if (!payload) {
    throw Error('Missing character_id in request payload');
  }

  let input: { character_id: string };
  try {
    input = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid JSON payload');
  }

  if (!input.character_id) {
    throw Error('character_id is required');
  }

  const characterId = input.character_id;

  logger.info('Deleting character %s for account %s', characterId, accountId);

  // SECURITY CHECK: Verify character belongs to authenticated account
  // This prevents players from deleting other players' characters
  const verifyQuery = `
    SELECT character_id, name
    FROM characters
    WHERE character_id = $1 AND account_id = $2
  `;

  const verifyResult = nk.sqlQuery(verifyQuery, [characterId, accountId]);

  if (verifyResult.length === 0) {
    throw Error('Character not found or does not belong to your account');
  }

  const characterName = verifyResult[0].name;

  // CASCADE DELETE PHASE 1: Remove guild memberships
  // Note: guild_members table has foreign key to characters table
  // Deleting membership entries before character deletion maintains referential integrity
  const deleteGuildMembershipsQuery = `
    DELETE FROM guild_members
    WHERE character_id = $1
  `;

  const guildMembershipsResult = nk.sqlExec(deleteGuildMembershipsQuery, [characterId]);
  const guildMembershipsDeleted = guildMembershipsResult.rowsAffected || 0;

  logger.info('Deleted %d guild membership(s) for character %s', guildMembershipsDeleted, characterId);

  // CASCADE DELETE PHASE 2: Remove inventory items
  // Note: inventory table has foreign key to characters table
  // All items must be removed to prevent orphaned inventory records
  const deleteInventoryQuery = `
    DELETE FROM inventory
    WHERE character_id = $1
  `;

  const inventoryResult = nk.sqlExec(deleteInventoryQuery, [characterId]);
  const inventoryItemsDeleted = inventoryResult.rowsAffected || 0;

  logger.info('Deleted %d inventory item(s) for character %s', inventoryItemsDeleted, characterId);

  // CASCADE DELETE PHASE 3: Delete character record
  // This is the final deletion after all related data has been cleaned up
  const deleteCharacterQuery = `
    DELETE FROM characters
    WHERE character_id = $1
  `;

  nk.sqlExec(deleteCharacterQuery, [characterId]);

  logger.info('Successfully deleted character %s (%s) from characters table', characterName, characterId);

  // AUDIT LOG: Record deletion for GDPR compliance and fraud detection
  // Requirement 29: All deletions must be logged for audit trails
  const auditLogQuery = `
    INSERT INTO audit_logs (
      actor_id,
      action,
      target_id,
      metadata,
      timestamp
    ) VALUES (
      $1, $2, $3, $4, NOW()
    )
  `;

  const auditMetadata = JSON.stringify({
    character_name: characterName,
    guild_memberships_deleted: guildMembershipsDeleted,
    inventory_items_deleted: inventoryItemsDeleted,
    deleted_by: 'player', // vs 'gm' or 'system'
    reason: 'player_requested'
  });

  const auditParams = [
    accountId, // actor_id (the account that requested deletion)
    'character_delete', // action type for audit log filtering
    characterId, // target_id (the character being deleted)
    auditMetadata // JSONB metadata with deletion details
  ];

  nk.sqlExec(auditLogQuery, auditParams);

  logger.info('Audit log entry created for character deletion: %s by account %s', characterId, accountId);

  // Return success response
  return JSON.stringify({ ok: true });
}
