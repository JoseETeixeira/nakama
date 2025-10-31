/**
 * Zone Snapshot Service
 *
 * Handles zone snapshot generation for world entry.
 * Provides zone_snapshot RPC for fetching compressed zone state.
 * Supports both 2D and 3D worlds.
 *
 * Task: 2.1.3
 * Requirements: 4 (World Entry and Zone Snapshot), 8 (AOI Management)
 */

import { Position, ZoneState, EntitySnapshot, GlobalEffect } from './types';
import * as pako from 'pako';
import { registerPlayerJoin } from './zone-manager';

/**
 * Request format for zone_snapshot RPC
 * Task 2.1.5: Changed to accept character_id instead of client-provided aoi_seed
 */
interface ZoneSnapshotRequest {
  /** Zone identifier to fetch snapshot for */
  zone_id: string;

  /**
   * Character identifier
   * Task 2.1.5: Server determines AOI seed from character's position
   * This ensures server authority over visible entities
   */
  character_id: string;
}

/**
 * Response format for zone_snapshot RPC
 * Requirement 4: World Entry and Zone Snapshot
 */
interface ZoneSnapshotResponse {
  /** Base64-encoded, Deflate-compressed JSON snapshot */
  snapshot_blob: string;

  /** Version number of this snapshot */
  version: number;

  /** Uncompressed size in bytes (for debugging) */
  uncompressed_size?: number;

  /** Compressed size in bytes (for debugging) */
  compressed_size?: number;
}

/**
 * Raw snapshot data structure (before compression)
 * This is what gets serialized to JSON and compressed
 *
 * Task 2.1.4: Terrain Chunk Referencing
 * ======================================
 * The `terrain_chunks` field contains ONLY chunk IDs (references), not actual terrain data.
 * This keeps the snapshot size minimal (≤512KB requirement).
 *
 * Client-Side Chunk Fetching Pattern:
 * 1. Client receives snapshot with chunk IDs (e.g., ["forest_01_chunk_0_0", "forest_01_chunk_1_0"])
 * 2. Client checks local cache for each chunk ID
 * 3. For missing chunks, client fetches from CDN/server:
 *    - CDN URL: `https://cdn.example.com/terrain/{chunk_id}.dat`
 *    - Or RPC: `get_terrain_chunk(chunk_id)` for dynamic chunks
 * 4. Client caches chunks for reuse across sessions
 *
 * Chunk Data Format (fetched separately):
 * - 2D: TileMap data (tile IDs, collision, navigation)
 * - 3D: Heightmap + texture layers OR mesh data
 *
 * Benefits:
 * - Snapshot stays small regardless of terrain complexity
 * - Terrain chunks cached client-side (CDN-friendly)
 * - Same chunks reused across multiple zones
 * - Bandwidth optimization for players re-entering familiar zones
 */
interface RawSnapshot {
  zone_id: string;  // Zone identifier for client-side validation
  zone_time: number;

  /**
   * Terrain chunk IDs (references only, not full data)
   * Task 2.1.4: Client fetches actual chunk data separately
   *
   * Format:
   * - 2D: "{zoneId}_chunk_{x}_{y}" (e.g., "forest_01_chunk_0_0")
   * - 3D: "{zoneId}_chunk_{x}_{y}_{z}" (e.g., "dungeon_01_chunk_0_0_0")
   */
  terrain_chunks: string[];

  entities: EntitySnapshot[];
  aoi_seed: Position;
  active_effects: GlobalEffect[];
  version: number;
}

/**
 * Configuration constants
 * Requirement 4: 512 KB compressed size limit
 */
const MAX_COMPRESSED_SIZE = 512 * 1024; // 512 KB
const AOI_RADIUS = 50; // units (configurable per zone)
const DEFLATE_COMPRESSION_LEVEL = 6; // zlib compression level (0-9)

/**
 * Calculate 2D distance between two positions
 * Used for 2D AOI filtering
 */
function distance2D(a: Position, b: Position): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Calculate 3D distance between two positions
 * Used for 3D AOI filtering
 */
function distance3D(a: Position, b: Position): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = (a.z || 0) - (b.z || 0);
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

/**
 * Determine if position is 2D or 3D based on z coordinate
 */
function is2D(pos: Position): boolean {
  return pos.z === undefined || pos.z === 0;
}

/**
 * Filter entities within AOI radius of seed position
 * Requirement 8: AOI Management
 * Supports both 2D and 3D worlds
 *
 * @param entities - All entities in zone
 * @param aoiSeed - Player spawn position (AOI center)
 * @param radius - AOI radius in world units
 * @returns Entities within AOI
 */
function filterEntitiesByAOI(
  entities: EntitySnapshot[],
  aoiSeed: Position,
  radius: number
): EntitySnapshot[] {
  // Detect if this is a 2D or 3D zone based on AOI seed
  const use2D = is2D(aoiSeed);

  return entities.filter(entity => {
    const entityPos = entity.transform.position;

    // Calculate distance based on dimensionality
    const distance = use2D
      ? distance2D(aoiSeed, entityPos)
      : distance3D(aoiSeed, entityPos);

    return distance <= radius;
  });
}

/**
 * Load zone state from database or in-memory cache
 * For now, returns mock data - will be replaced with actual zone process state
 * Task: Future (2.2.1 - ZoneProcess implementation)
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param zoneId - Zone identifier
 * @returns Zone state or null if zone not found
 */
function loadZoneState(nk: any, logger: any, zoneId: string): ZoneState | null {
  try {
    // Query world_state table for zone checkpoint
    const query = `
      SELECT shard_id, state_json, version, updated_at
      FROM world_state
      WHERE zone_id = $1
      ORDER BY version DESC
      LIMIT 1
    `;

    const result = nk.sqlQuery(query, [zoneId]);

    if (result.length === 0) {
      logger.warn('Zone state not found for zone %s, using default', zoneId);
      return createDefaultZoneState(zoneId);
    }

    const row = result[0];
    const stateJson = JSON.parse(row.state_json);

    logger.info('Loaded zone state for %s (version %d)', zoneId, row.version);

    return {
      zoneId: zoneId,
      shardId: row.shard_id,
      zoneTime: Date.now(), // Current server time
      version: row.version,
      entities: stateJson.entities || [],
      terrainChunks: stateJson.terrain_chunks || [],
      timers: stateJson.timers || {},
      activeEffects: stateJson.active_effects || []
    };
  } catch (error) {
    logger.error('Failed to load zone state for %s: %s', zoneId, error);
    return createDefaultZoneState(zoneId);
  }
}

/**
 * Load character's current position from database
 * Task 2.1.5: Implement AOI seed calculation
 * Requirement 8: Determine player's initial AOI based on spawn position
 *
 * This function loads the character's last known position, which serves as
 * the AOI seed for filtering visible entities in the zone snapshot.
 *
 * SECURITY: Validates character belongs to authenticated account
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param characterId - Character identifier
 * @param accountId - Account ID (for ownership validation)
 * @param zoneId - Expected zone ID (for validation)
 * @returns Character position or null if not found/invalid
 */
function loadCharacterPosition(
  nk: any,
  logger: any,
  characterId: string,
  accountId: string,
  zoneId: string
): Position | null {
  try {
    // Load character state from database
    // SECURITY: Validate character belongs to authenticated account
    const query = `
      SELECT
        character_id,
        account_id,
        last_zone_id,
        last_position
      FROM characters
      WHERE character_id = $1 AND account_id = $2
    `;

    const result = nk.sqlQuery(query, [characterId, accountId]);

    if (result.length === 0) {
      logger.error('Character %s not found or does not belong to account %s',
        characterId, accountId);
      return null;
    }

    const character = result[0];

    // Validate character is in the requested zone
    if (character.last_zone_id !== zoneId) {
      logger.error('Character %s is in zone %s, not requested zone %s',
        characterId, character.last_zone_id, zoneId);
      return null;
    }

    // Parse last_position from JSONB (supports both 2D and 3D)
    // Note: Nakama's sqlQuery returns JSONB as already-parsed object, not string
    if (character.last_position) {
      try {
        // Handle both parsed object (from JSONB) and string (from older data)
        const parsed = typeof character.last_position === 'string'
          ? JSON.parse(character.last_position)
          : character.last_position;

        const position: Position = {
          x: parsed.x || 0,
          y: parsed.y || 0,
          z: parsed.z  // z is optional for 2D worlds
        };

        logger.info('Loaded character position for %s: (%f, %f, %f)',
          characterId, position.x, position.y, position.z || 0);

        return position;
      } catch (parseError) {
        logger.error('Failed to parse last_position for character %s: %s',
          characterId, parseError);
        return null;
      }
    } else {
      logger.error('Character %s has no last_position stored', characterId);
      return null;
    }
  } catch (error) {
    logger.error('Failed to load character position for %s: %s', characterId, error);
    return null;
  }
}

/**
 * Create default zone state for new or reset zones
 * This provides a fallback for new or reset zones with sample entities
 */
function createDefaultZoneState(zoneId: string): ZoneState {
  // Create sample entities for testing (NPCs, resource nodes, etc.)
  const sampleEntities: EntitySnapshot[] = [
    // Friendly NPC
    {
      entityId: `${zoneId}_npc_guide`,
      type: 'npc',
      transform: {
        position: { x: 10, y: 5, z: 0 },
        rotation: { x: 0, y: 0, z: 0 }
      },
      vitals: {
        health: 100,
        maxHealth: 100,
        mana: 50,
        maxMana: 50
      },
      state: {
        behavior: 'idle',
        name: 'Village Guide',
        level: 10,
        faction: 'friendly',
        has_quest: true  // Show quest icon
      }
    },
    // Enemy mob
    {
      entityId: `${zoneId}_mob_goblin_1`,
      type: 'mob',
      transform: {
        position: { x: -15, y: 8, z: 0 },
        rotation: { x: 0, y: 0, z: 0 }
      },
      vitals: {
        health: 50,
        maxHealth: 50,
        mana: 0,
        maxMana: 0
      },
      state: {
        behavior: 'patrol',
        name: 'Goblin Scout',
        level: 3,
        faction: 'hostile',
        is_enemy: true  // Show aggro icon
      }
    },
    // Resource node
    {
      entityId: `${zoneId}_resource_tree_1`,
      type: 'resource',
      transform: {
        position: { x: 20, y: -10, z: 0 },
        rotation: { x: 0, y: 0, z: 0 }
      },
      vitals: {
        health: 100,
        maxHealth: 100,
        mana: 0,
        maxMana: 0
      },
      state: {
        behavior: 'active',
        name: 'Oak Tree',
        resourceType: 'wood',
        harvestable: true
      }
    }
  ];

  return {
    zoneId: zoneId,
    shardId: 'shard_01', // Default shard for single-shard deployment
    zoneTime: Date.now(),
    version: 1,
    entities: sampleEntities, // Include sample entities for testing
    terrainChunks: generateDefaultTerrainChunks(zoneId), // Task 2.1.4
    timers: {},
    activeEffects: []
  };
}

/**
 * Generate default terrain chunk IDs for a zone
 * Task 2.1.4: Add terrain chunk referencing
 * Requirement 4: Store chunk IDs (not full data) in snapshot
 *
 * Terrain chunks are referenced by ID to keep snapshot size minimal.
 * Clients fetch actual chunk data separately from CDN/cache.
 *
 * Chunk ID Format:
 * - 2D: `{zoneId}_chunk_{gridX}_{gridY}` (e.g., "forest_01_chunk_0_0")
 * - 3D: `{zoneId}_chunk_{gridX}_{gridY}_{gridZ}` (e.g., "dungeon_01_chunk_0_0_0")
 *
 * @param zoneId - Zone identifier
 * @returns Array of chunk IDs for this zone
 */
function generateDefaultTerrainChunks(zoneId: string): string[] {
  // For default zones, return a single origin chunk
  // In production, this would be loaded from zone_boundaries table
  // or calculated based on zone size and chunk dimensions
  return [`${zoneId}_chunk_0_0`];
}

/**
 * Generate terrain chunk IDs visible from a position
 * Task 2.1.4: Add terrain chunk referencing
 *
 * Calculates which terrain chunks are visible from the given position
 * based on chunk size and visibility radius.
 *
 * @param zoneId - Zone identifier
 * @param position - Camera/player position
 * @param chunkSize - Size of each terrain chunk (world units)
 * @param visibilityRadius - How far to load chunks (world units)
 * @returns Array of chunk IDs to load
 */
function getVisibleTerrainChunks(
  zoneId: string,
  position: Position,
  chunkSize: number = 100,
  visibilityRadius: number = 150
): string[] {
  const chunks: string[] = [];

  // Calculate chunk grid coordinates for the position
  const centerChunkX = Math.floor(position.x / chunkSize);
  const centerChunkY = Math.floor(position.y / chunkSize);

  // Calculate how many chunks in each direction
  const chunkRadius = Math.ceil(visibilityRadius / chunkSize);

  // Determine if this is a 2D or 3D zone
  const is3D = position.z !== undefined && position.z !== 0;

  if (is3D && position.z !== undefined) {
    // 3D chunk generation
    const centerChunkZ = Math.floor(position.z / chunkSize);

    for (let x = centerChunkX - chunkRadius; x <= centerChunkX + chunkRadius; x++) {
      for (let y = centerChunkY - chunkRadius; y <= centerChunkY + chunkRadius; y++) {
        for (let z = centerChunkZ - chunkRadius; z <= centerChunkZ + chunkRadius; z++) {
          chunks.push(`${zoneId}_chunk_${x}_${y}_${z}`);
        }
      }
    }
  } else {
    // 2D chunk generation
    for (let x = centerChunkX - chunkRadius; x <= centerChunkX + chunkRadius; x++) {
      for (let y = centerChunkY - chunkRadius; y <= centerChunkY + chunkRadius; y++) {
        chunks.push(`${zoneId}_chunk_${x}_${y}`);
      }
    }
  }

  return chunks;
}

/**
 * Compress JSON data using Deflate (zlib)
 * Requirement 4: Deflate compression for zone snapshots
 *
 * Uses pako library (pure JavaScript zlib implementation) for Deflate compression.
 * The client-side decompression (Godot) expects Deflate format:
 *   compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
 *
 * @param jsonString - JSON string to compress
 * @returns Compressed binary data
 */
function compressSnapshot(jsonString: string): Uint8Array {
  try {
    // Compress using pako (Deflate, compression level 6 for balance)
    const compressed = pako.deflate(jsonString, { level: 6 });
    return compressed;
  } catch (error: any) {
    throw new Error(`Snapshot compression failed: ${error.message}`);
  }
}

/**
 * Encode binary data to hexadecimal string
 * Safer alternative to base64 for Nakama's JavaScript runtime
 * @param data - Binary data to encode
 * @returns Hex string
 */
function toHex(data: Uint8Array): string {
  let result = '';
  for (let i = 0; i < data.length; i++) {
    const hex = data[i].toString(16);
    result += (hex.length === 1 ? '0' + hex : hex);
  }
  return result;
}

/**
 * Encode binary data to base64 string using manual encoding
 * @param data - Binary data to encode
 * @returns Base64 string
 */
function toBase64(data: Uint8Array): string {
  // Manual base64 encoding
  const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  let i = 0;

  while (i < data.length) {
    const byte1 = data[i++];
    const byte2 = i < data.length ? data[i++] : 0;
    const byte3 = i < data.length ? data[i++] : 0;

    const encoded1 = byte1 >> 2;
    const encoded2 = ((byte1 & 0x03) << 4) | (byte2 >> 4);
    const encoded3 = ((byte2 & 0x0f) << 2) | (byte3 >> 6);
    const encoded4 = byte3 & 0x3f;

    result += base64Chars[encoded1];
    result += base64Chars[encoded2];
    result += i - 2 < data.length ? base64Chars[encoded3] : '=';
    result += i - 1 < data.length ? base64Chars[encoded4] : '=';
  }

  return result;
}

/**
 * Generate zone snapshot RPC handler
 * Requirement 4: World Entry and Zone Snapshot
 * Task 2.1.5: Implement AOI seed calculation from character position
 *
 * API Contract:
 * - Input: {zone_id: string, character_id: string}
 * - Output: {snapshot_blob: string, version: number}
 * - Errors: 404 if zone/character not found, 403 if character doesn't belong to account
 *
 * Security:
 * - Validates character belongs to authenticated account
 * - Server-side AOI calculation prevents client manipulation
 *
 * @param ctx - Nakama context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param payload - JSON request payload
 * @returns JSON response with compressed snapshot
 */
export function rpcZoneSnapshot(ctx: any, logger: any, nk: any, payload: string): string {
  // Verify user is authenticated
  if (!ctx.userId) {
    logger.warn('Unauthenticated zone_snapshot request');
    throw new Error('Unauthenticated');
  }

  const accountId = ctx.userId;

  // Parse request
  let request: ZoneSnapshotRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    logger.error('Invalid zone_snapshot request payload: %s', error);
    throw new Error('Invalid request format');
  }

  const { zone_id, character_id } = request;

  // Validate request parameters
  if (!zone_id || !character_id) {
    logger.error('Invalid zone_snapshot parameters: zone_id=%s, character_id=%s',
      zone_id, character_id);
    throw new Error('Missing required parameters: zone_id and character_id');
  }

  logger.info('Generating zone snapshot for zone %s, character %s (account %s)',
    zone_id, character_id, accountId);

  // Task 2.1.5: Load character position to determine AOI seed
  // Requirement 8: Calculate player's initial AOI based on spawn position
  // SECURITY: This prevents clients from manipulating AOI to see entities
  // they shouldn't be able to see (e.g., bosses behind walls)
  const aoiSeed = loadCharacterPosition(nk, logger, character_id, accountId, zone_id);

  if (!aoiSeed) {
    logger.error('Failed to load character position for %s in zone %s',
      character_id, zone_id);
    throw new Error('Character not found in requested zone or does not belong to your account');
  }

  logger.info('AOI seed calculated from character position: (%f, %f, %f)',
    aoiSeed.x, aoiSeed.y, aoiSeed.z || 0);

  // Load zone state from database or cache
  const zoneState = loadZoneState(nk, logger, zone_id);

  if (!zoneState) {
    logger.error('Zone not found: %s', zone_id);
    throw new Error('Zone not found');
  }

  // Filter entities by AOI
  // Requirement 8: Only include entities within player's AOI radius
  const visibleEntities = filterEntitiesByAOI(
    zoneState.entities,
    aoiSeed,
    AOI_RADIUS
  );

  logger.info('Filtered %d entities to %d within AOI radius %d',
    zoneState.entities.length, visibleEntities.length, AOI_RADIUS);

  // Build raw snapshot data structure
  const rawSnapshot: RawSnapshot = {
    zone_id: zone_id,  // Include zone_id so client knows which zone this snapshot is for
    zone_time: zoneState.zoneTime,
    terrain_chunks: zoneState.terrainChunks,
    entities: visibleEntities,
    aoi_seed: aoiSeed, // Include AOI seed for client state sync
    active_effects: zoneState.activeEffects,
    version: zoneState.version
  };

  // Serialize to JSON
  const jsonString = JSON.stringify(rawSnapshot);
  const uncompressedSize = jsonString.length;

  logger.debug('Snapshot JSON size: %d bytes', uncompressedSize);

  // Compress using Deflate
  const compressedData = compressSnapshot(jsonString);
  const compressedSize = compressedData.length;

  logger.info('Compressed snapshot: %d bytes -> %d bytes (%.1f%% reduction)',
    uncompressedSize, compressedSize,
    (1 - compressedSize / uncompressedSize) * 100);

  // Check size limit
  // Requirement 4: If snapshot exceeds 512 KB, apply LOD filtering
  if (compressedSize > MAX_COMPRESSED_SIZE) {
    logger.warn('Snapshot exceeds size limit: %d KB > %d KB',
      compressedSize / 1024, MAX_COMPRESSED_SIZE / 1024);

    // TODO: Task 2.1.4+ - Implement LOD filtering for oversized snapshots
    // For now, log warning and return full snapshot
    // In production: reduce entity count, lower precision, chunk terrain, etc.
  }

  // Encode to HEX instead of base64 (safer for Nakama's JavaScript runtime)
  // Base64 encoding was causing Nakama HTTP layer to hang
  const snapshotBlob = toHex(compressedData);

  // Task 2.3.1: Register player joining zone and get match ID for delta streaming
  const matchId = registerPlayerJoin(nk, logger, zone_id, accountId, ctx.sessionId || '');

  // Build response
  const response: ZoneSnapshotResponse = {
    snapshot_blob: snapshotBlob,
    version: zoneState.version,
    uncompressed_size: uncompressedSize,
    compressed_size: compressedSize
  };

  // Add match_id to response so client can join the match for delta streaming
  (response as any).match_id = matchId;

  logger.info('Zone snapshot generated successfully for zone %s (version %d, match %s)',
    zone_id, zoneState.version, matchId);

  // HACK: Build JSON manually to avoid potential JSON.stringify issues with large base64 strings
  // This bypasses any potential encoding issues in Nakama's JSON stringifier
  const responseJson = `{"snapshot_blob":"${snapshotBlob}","version":${zoneState.version},"uncompressed_size":${uncompressedSize},"compressed_size":${compressedSize},"match_id":"${matchId}"}`;

  logger.debug('Returning full response (%d bytes, blob length: %d)', responseJson.length, snapshotBlob.length);

  return responseJson;
}

/**
 * Initialize the Zone Snapshot module
 * Registers the zone_snapshot RPC with Nakama runtime
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
  logger.info('Zone Snapshot module initialized');

  // Register zone_snapshot RPC (Task 2.1.3)
  initializer.registerRpc('zone_snapshot', rpcZoneSnapshot);

  logger.info('zone_snapshot RPC registered successfully');
}
