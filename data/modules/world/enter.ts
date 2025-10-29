/**
 * World Entry Service
 *
 * Handles player entry into the persistent game world.
 * Provides world_enter RPC for transitioning characters from character select to in-game.
 * Supports both 2D and 3D worlds.
 *
 * Task: 2.1.2
 * Requirements: 2 (Character Selection - last_zone_id), 4 (World Entry)
 */

import { Position } from './types';

/**
 * Response format for world_enter RPC
 * Requirement 4: World Entry and Zone Snapshot
 * Supports both 2D and 3D worlds
 */
interface ZoneEntryResponse {
  /** Shard identifier for this zone instance */
  shardId: string;

  /** Zone identifier where player will spawn */
  zoneId: string;

  /**
   * Spawn coordinates
   * - For 2D worlds: {x, y} or {x, y, z: 0}
   * - For 3D worlds: {x, y, z}
   */
  spawn: Position;

  /** Optional handoff token (null for normal entry, set for cross-region transfers) */
  handoff?: null;
}

/**
 * Default spawn configuration
 * Used when character has no last_zone_id or when zone is unavailable
 * Works for both 2D and 3D (z defaults to 0 for 2D)
 */
const DEFAULT_SPAWN_ZONE = 'starter_plains_01';
const DEFAULT_SPAWN_POSITION: Position = { x: 0, y: 0, z: 0 };

/**
 * Default shard ID
 * TODO: In production, implement shard selection based on load balancing
 * Currently uses single shard for Phase 2 implementation
 */
const DEFAULT_SHARD_ID = 'shard_01';

/**
 * Module initialization function
 * Called by Nakama runtime to register RPCs
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
  logger.info('World Entry module initialized');

  // Register world_enter RPC (Task 2.1.2)
  initializer.registerRpc('world_enter', rpcWorldEnter);

  logger.info('world_enter RPC registered successfully');
}

/**
 * RPC: world_enter
 * Description: Enter the persistent game world with a character
 * Task: 2.1.2
 * Requirements: 2 (Character Selection), 4 (World Entry)
 *
 * Input: { character_id: string }
 * Output: { shard_id: string, zone_id: string, spawn: Vector3, handoff?: null }
 *
 * This RPC handles the transition from character selection to world entry.
 * It validates the character belongs to the authenticated account, loads the
 * character's last known zone and position, and returns the coordinates where
 * the client should enter the world.
 *
 * Flow:
 * 1. Validate character_id and account ownership
 * 2. Load character's last_zone_id and last_position from database
 * 3. Determine shard_id (currently single-shard, future: load balancing)
 * 4. Return zone entry coordinates to client
 * 5. Client will then call zone_snapshot RPC (Task 2.1.3) to get full state
 *
 * Note: This RPC does NOT generate the zone snapshot - that's handled by
 * zone_snapshot RPC. This only returns WHERE the player should enter.
 *
 * @param ctx - Execution context with userId (account_id)
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param payload - JSON: { character_id: string }
 * @returns JSON response with shard_id, zone_id, spawn coordinates
 */
async function rpcWorldEnter(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  const accountId = ctx.userId;
  logger.info('world_enter RPC called by account %s', accountId);

  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Parse and validate input payload
  if (!payload) {
    throw Error('Missing character_id in request payload');
  }

  let input: { character_id: string };
  try {
    input = JSON.parse(payload);
  } catch (error) {
    logger.error('Invalid JSON payload for world_enter: %s', error);
    throw Error('Invalid JSON payload');
  }

  if (!input.character_id) {
    throw Error('character_id is required');
  }

  const characterId = input.character_id;
  logger.info('Character %s attempting to enter world', characterId);

  // Load character state from database
  // SECURITY: Validate character belongs to authenticated account
  const query = `
    SELECT
      character_id,
      account_id,
      name,
      last_zone_id,
      last_position
    FROM characters
    WHERE character_id = $1 AND account_id = $2
  `;

  const result = nk.sqlQuery(query, [characterId, accountId]);

  if (result.length === 0) {
    logger.warn('Character %s not found or does not belong to account %s', characterId, accountId);
    throw Error('Character not found or does not belong to your account');
  }

  const character = result[0];
  logger.info('Loaded character: %s (account: %s)', character.name, accountId);

  // Determine zone_id and spawn position
  // Requirement 2: Use last_zone_id from character state
  // Requirement 4: Fall back to default spawn if last_zone is unavailable
  // Supports both 2D (x, y) and 3D (x, y, z) positions
  let zoneId: string;
  let spawnPosition: Position;

  if (character.last_zone_id) {
    // Player has previously entered the world - use last known zone
    zoneId = character.last_zone_id;

    // Parse last_position from JSONB (supports both 2D and 3D)
    if (character.last_position) {
      try {
        const parsed = JSON.parse(character.last_position);
        spawnPosition = {
          x: parsed.x || 0,
          y: parsed.y || 0,
          z: parsed.z  // z is optional for 2D worlds
        };
        logger.info('Using last known position in zone %s: (%f, %f, %f)',
          zoneId, spawnPosition.x, spawnPosition.y, spawnPosition.z || 0);
      } catch (error) {
        logger.warn('Failed to parse last_position for character %s, using zone default', characterId);
        spawnPosition = getZoneDefaultSpawn(nk, logger, zoneId);
      }
    } else {
      // No last_position stored, use zone's default spawn
      logger.info('No last_position for character %s, using zone default spawn', characterId);
      spawnPosition = getZoneDefaultSpawn(nk, logger, zoneId);
    }
  } else {
    // New character or first login - use default starter zone
    logger.info('Character %s has no last_zone_id, using default spawn zone', characterId);
    zoneId = DEFAULT_SPAWN_ZONE;
    spawnPosition = DEFAULT_SPAWN_POSITION;
  }

  // Determine shard_id
  // TODO Phase 8: Implement load-based shard selection for horizontal scalability
  // For now, use single shard for Phase 2 implementation
  const shardId = DEFAULT_SHARD_ID;

  logger.info('Character %s entering world at zone %s (shard %s) at position (%f, %f, %f)',
    characterId, zoneId, shardId, spawnPosition.x, spawnPosition.y, spawnPosition.z);

  // Task 4.2.2: Auto-subscribe to zone channel
  // Requirement 12: WHEN player joins zone THEN Nakama SHALL subscribe to zone channel
  try {
    const zoneChannelId = `zone:${zoneId}`;

    // Join zone channel for chat
    // Channel type 3 = group (multi-user channel)
    // persist: false (transient subscription, removed on disconnect)
    // hidden: false (visible to other channel members)
    await nk.channelJoin(
      accountId,        // user_id (account_id for authentication)
      zoneChannelId,    // channel_id (format: "zone:zone_id")
      3,                // type: 3 = group channel
      false,            // persist: false (subscription doesn't persist across disconnects)
      false             // hidden: false (user is visible in channel member list)
    );

    logger.info('Character %s subscribed to zone channel %s', characterId, zoneChannelId);
  } catch (error) {
    // Log error but don't fail world entry if channel subscription fails
    logger.error('Failed to subscribe character %s to zone channel %s: %s',
      characterId, `zone:${zoneId}`, error);
  }

  // Build response
  const response: ZoneEntryResponse = {
    shardId: shardId,
    zoneId: zoneId,
    spawn: spawnPosition,
    handoff: null // null for normal entry (handoff tokens are for cross-region transfers - Phase 6)
  };

  return JSON.stringify(response);
}

/**
 * Get default spawn position for a zone from zone_boundaries table
 * Requirement 4: Fall back to safe zone if last_zone is unavailable
 * Supports both 2D and 3D positions
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param zoneId - Zone identifier
 * @returns Default spawn position for the zone (2D or 3D)
 */
function getZoneDefaultSpawn(nk: any, logger: any, zoneId: string): Position {
  try {
    // Query zone_boundaries table for default_spawn position
    const query = `
      SELECT default_spawn
      FROM zone_boundaries
      WHERE zone_id = $1
    `;

    const result = nk.sqlQuery(query, [zoneId]);

    if (result.length > 0 && result[0].default_spawn) {
      const parsed = JSON.parse(result[0].default_spawn);
      logger.info('Loaded default spawn for zone %s: (%f, %f, %f)',
        zoneId, parsed.x, parsed.y, parsed.z || 0);
      return {
        x: parsed.x || 0,
        y: parsed.y || 0,
        z: parsed.z  // z is optional for 2D zones
      };
    }
  } catch (error) {
    logger.warn('Failed to load default spawn for zone %s: %s', zoneId, error);
  }

  // If zone_boundaries entry doesn't exist or is invalid, use global default
  logger.info('Using global default spawn position for zone %s', zoneId);
  return DEFAULT_SPAWN_POSITION;
}
