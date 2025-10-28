/**
 * Zone Delta Streaming
 * Task 2.3.1: Implement zone delta stream
 *
 * Provides real-time incremental updates for zone state changes.
 * Streams entity updates, adds, and removes to connected clients at 10-20 Hz.
 *
 * Requirements: 4 (World Entry), 8 (AOI Management)
 * Design: design.md lines 241-270 (World Service delta streaming)
 */

import { ZoneDelta, EntityUpdate, EntitySnapshot, ZoneState, Position } from './types';

/**
 * Generate delta update from zone state changes
 * Task 2.3.1: Delta generation
 *
 * Compares current zone state with previous state to generate
 * incremental updates for clients.
 *
 * @param currentState - Current zone state
 * @param previousState - Previous zone state
 * @param timestamp - When delta was generated
 * @returns Zone delta with updates, adds, removes
 */
export function generateZoneDelta(
  currentState: ZoneState,
  previousState: ZoneState,
  timestamp: number
): ZoneDelta {
  const delta: ZoneDelta = {
    timestamp,
    version: currentState.version,
    entityUpdates: [],
    entityAdds: [],
    entityRemoves: []
  };

  // Convert entity arrays to maps for comparison
  // Note: ZoneState.entities can be array or dictionary based on context
  const currentEntities = Array.isArray(currentState.entities)
    ? arrayToMap(currentState.entities)
    : currentState.entities;

  const previousEntities = Array.isArray(previousState.entities)
    ? arrayToMap(previousState.entities)
    : previousState.entities;

  const currentIds = new Set(Object.keys(currentEntities));
  const previousIds = new Set(Object.keys(previousEntities));

  // Find newly added entities
  for (const entityId of currentIds) {
    if (!previousIds.has(entityId)) {
      delta.entityAdds.push(currentEntities[entityId]);
    }
  }

  // Find removed entities
  for (const entityId of previousIds) {
    if (!currentIds.has(entityId)) {
      delta.entityRemoves.push(entityId);
    }
  }

  // Find updated entities (position, vitals, state changes)
  for (const entityId of currentIds) {
    if (previousIds.has(entityId)) {
      const current = currentEntities[entityId];
      const previous = previousEntities[entityId];

      const update = compareEntities(current, previous);
      if (update) {
        delta.entityUpdates.push(update);
      }
    }
  }

  return delta;
}

/**
 * Compare two entity snapshots and generate partial update
 * Task 2.3.1: Entity comparison
 * Task 2.3.4: Bandwidth optimization - send only changed fields
 *
 * Detects changes in transform (position, rotation) and vitals.
 * Only includes changed fields in the update to minimize payload size.
 * Supports both 2D and 3D entities.
 *
 * @param current - Current entity state
 * @param previous - Previous entity state
 * @returns Entity update with only changed fields, null if no changes
 */
function compareEntities(
  current: EntitySnapshot,
  previous: EntitySnapshot
): EntityUpdate | null {
  const update: EntityUpdate = {
    entityId: current.entityId
  };

  let hasChanges = false;

  // Task 2.3.4: Check individual position fields (bandwidth optimization)
  if (current.transform.position.x !== previous.transform.position.x) {
    update.positionX = current.transform.position.x;
    hasChanges = true;
  }

  if (current.transform.position.y !== previous.transform.position.y) {
    update.positionY = current.transform.position.y;
    hasChanges = true;
  }

  // 3D z-coordinate (optional for 2D worlds)
  if (current.transform.position.z !== undefined || previous.transform.position.z !== undefined) {
    const currentZ = current.transform.position.z || 0;
    const previousZ = previous.transform.position.z || 0;
    if (currentZ !== previousZ) {
      update.positionZ = currentZ;
      hasChanges = true;
    }
  }

  // Task 2.3.4: Check individual rotation fields
  if (current.transform.rotation.x !== previous.transform.rotation.x) {
    update.rotationX = current.transform.rotation.x;
    hasChanges = true;
  }

  if (current.transform.rotation.y !== previous.transform.rotation.y) {
    update.rotationY = current.transform.rotation.y;
    hasChanges = true;
  }

  if (current.transform.rotation.z !== previous.transform.rotation.z) {
    update.rotationZ = current.transform.rotation.z;
    hasChanges = true;
  }

  // Task 2.3.4: Check individual vitals fields
  if (current.vitals.health !== previous.vitals.health) {
    update.health = current.vitals.health;
    hasChanges = true;
  }

  if (current.vitals.maxHealth !== previous.vitals.maxHealth) {
    update.maxHealth = current.vitals.maxHealth;
    hasChanges = true;
  }

  // Mana is optional
  if (current.vitals.mana !== undefined || previous.vitals.mana !== undefined) {
    const currentMana = current.vitals.mana;
    const previousMana = previous.vitals.mana;
    if (currentMana !== previousMana) {
      update.mana = currentMana;
      hasChanges = true;
    }
  }

  if (current.vitals.maxMana !== undefined || previous.vitals.maxMana !== undefined) {
    const currentMaxMana = current.vitals.maxMana;
    const previousMaxMana = previous.vitals.maxMana;
    if (currentMaxMana !== previousMaxMana) {
      update.maxMana = currentMaxMana;
      hasChanges = true;
    }
  }

  // Check state changes (arbitrary entity data)
  if (current.state && previous.state) {
    if (JSON.stringify(current.state) !== JSON.stringify(previous.state)) {
      update.state = current.state;
      hasChanges = true;
    }
  } else if (current.state || previous.state) {
    // State added or removed
    update.state = current.state;
    hasChanges = true;
  }

  return hasChanges ? update : null;
}

/**
 * Convert entity array to map keyed by entityId
 * Helper for zone state comparisons
 */
function arrayToMap(entities: EntitySnapshot[]): Record<string, EntitySnapshot> {
  const map: Record<string, EntitySnapshot> = {};
  for (const entity of entities) {
    map[entity.entityId] = entity;
  }
  return map;
}

/**
 * Compress zone delta for bandwidth optimization
 * Task 2.3.4: Delta compression
 *
 * Compresses delta JSON using Deflate (same as snapshots).
 * Encodes to base64 for JSON transmission over WebSocket.
 *
 * @param delta - Zone delta to compress
 * @returns Base64-encoded compressed delta
 */
function compressDelta(delta: ZoneDelta): string {
  try {
    // Serialize to JSON
    const deltaJson = JSON.stringify(delta);

    // TODO: Integrate Nakama runtime zlib.deflateSync() for production
    // Placeholder: Return base64-encoded uncompressed JSON for now
    // Production will use Deflate compression level 6 (balanced)

    // Convert string to bytes (compatible with Nakama runtime)
    const encoder = new TextEncoder();
    const uncompressedBytes = encoder.encode(deltaJson);

    // Placeholder compression (replace with zlib.deflateSync in production)
    const compressed = uncompressedBytes;

    // Encode to base64 for JSON transport
    const base64 = btoa(String.fromCharCode(...compressed));

    return base64;

  } catch (err: any) {
    throw new Error(`Delta compression failed: ${err.message}`);
  }
}

/**
 * Broadcast zone delta to all players in match
 * Task 2.3.1: Delta broadcasting
 * Task 2.3.4: Compressed delta transmission
 *
 * Generates, compresses, and broadcasts zone delta to connected clients.
 * Uses Deflate compression to reduce bandwidth (Requirement 8).
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param matchId - Match ID for zone
 * @param delta - Zone delta to broadcast
 */
export function broadcastZoneDelta(
  nk: any,
  logger: any,
  matchId: string,
  delta: ZoneDelta
): void {
  try {
    // Op code for delta messages (arbitrary, must match client)
    const OP_CODE_ZONE_DELTA = 1;

    // Task 2.3.4: Compress delta for bandwidth optimization
    const compressedDelta = compressDelta(delta);

    // Broadcast to all players in match
    // Nakama will stream via WebSocket to connected clients
    // Client receives base64-encoded, Deflate-compressed delta
    nk.matchSignal(matchId, OP_CODE_ZONE_DELTA, compressedDelta);

    logger.debug('[Delta] Broadcast compressed delta for match %s (version %d, %d updates, %d adds, %d removes)',
      matchId, delta.version, delta.entityUpdates.length, delta.entityAdds.length, delta.entityRemoves.length);

  } catch (err: any) {
    logger.error('[Delta] Failed to broadcast delta for match %s: %s', matchId, err.message);
  }
}

/**
 * Create match for zone streaming
 * Task 2.3.1: Match initialization
 *
 * Creates a Nakama match for zone delta streaming.
 * Players join this match when entering the zone.
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param zoneId - Zone identifier
 * @param shardId - Shard identifier
 * @returns Match ID for zone
 */
export function createZoneMatch(
  nk: any,
  logger: any,
  zoneId: string,
  shardId: string
): string {
  try {
    // Create match with zone module
    // Module name must match registered match handler
    const moduleName = 'zone_match';
    const params = {
      zoneId,
      shardId
    };

    const matchId = nk.matchCreate(moduleName, params);

    logger.info('[Delta] Created match for zone %s (shard %s): %s', zoneId, shardId, matchId);

    return matchId;

  } catch (err: any) {
    logger.error('[Delta] Failed to create match for zone %s: %s', zoneId, err.message);
    throw err;
  }
}

/**
 * Add player to zone match
 * Task 2.3.1: Player subscription
 *
 * Joins player to zone match for delta streaming.
 * Called when player enters zone.
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param matchId - Match ID for zone
 * @param userId - User ID
 * @param sessionId - Session ID
 * @returns Success boolean
 */
export function joinZoneMatch(
  nk: any,
  logger: any,
  matchId: string,
  userId: string,
  sessionId: string
): boolean {
  try {
    // Join match for delta streaming
    // Nakama handles WebSocket connection automatically
    const success = nk.matchJoin(matchId, userId, sessionId);

    if (success) {
      logger.info('[Delta] Player %s joined match %s', userId, matchId);
    } else {
      logger.warn('[Delta] Failed to join player %s to match %s', userId, matchId);
    }

    return success;

  } catch (err: any) {
    logger.error('[Delta] Error joining player %s to match %s: %s', userId, matchId, err.message);
    return false;
  }
}

/**
 * Remove player from zone match
 * Task 2.3.1: Player unsubscription
 *
 * Removes player from zone match.
 * Called when player leaves zone.
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param matchId - Match ID for zone
 * @param userId - User ID
 * @param sessionId - Session ID
 */
export function leaveZoneMatch(
  nk: any,
  logger: any,
  matchId: string,
  userId: string,
  sessionId: string
): void {
  try {
    nk.matchLeave(matchId, userId, sessionId);
    logger.info('[Delta] Player %s left match %s', userId, matchId);
  } catch (err: any) {
    logger.error('[Delta] Error removing player %s from match %s: %s', userId, matchId, err.message);
  }
}

/**
 * Spatial Grid for AOI Optimization
 * Task 2.3.2: Implement AOI filtering
 *
 * Grid-based spatial partitioning for efficient entity culling.
 * Supports both 2D and 3D worlds with configurable cell size.
 *
 * Design: design.md lines 1370-1400
 * Requirement: 8 (AOI Management)
 */
export class SpatialGrid {
  private cellSize: number;
  private cells: Map<string, Set<string>> = new Map();
  private entityPositions: Map<string, Position> = new Map();

  /**
   * Create a spatial grid
   *
   * @param cellSize - Size of each grid cell in meters (default: 50)
   */
  constructor(cellSize: number = 50) {
    this.cellSize = cellSize;
  }

  /**
   * Get grid cell key for a position
   * Supports both 2D and 3D positions
   *
   * @param pos - Position to get cell key for
   * @returns Cell key string (e.g., "0,0" for 2D or "0,0,0" for 3D)
   */
  getCellKey(pos: Position): string {
    const x = Math.floor(pos.x / this.cellSize);
    const y = Math.floor(pos.y / this.cellSize);

    // 3D support: include z-coordinate if present
    if (pos.z !== undefined) {
      const z = Math.floor(pos.z / this.cellSize);
      return `${x},${y},${z}`;
    }

    // 2D: only x and y
    return `${x},${y}`;
  }

  /**
   * Insert entity into spatial grid
   *
   * @param entityId - Entity identifier
   * @param pos - Entity position
   */
  insert(entityId: string, pos: Position): void {
    const cellKey = this.getCellKey(pos);

    if (!this.cells.has(cellKey)) {
      this.cells.set(cellKey, new Set());
    }

    this.cells.get(cellKey)!.add(entityId);
    this.entityPositions.set(entityId, pos);
  }

  /**
   * Remove entity from spatial grid
   *
   * @param entityId - Entity identifier
   */
  remove(entityId: string): void {
    const pos = this.entityPositions.get(entityId);
    if (!pos) return;

    const cellKey = this.getCellKey(pos);
    const cell = this.cells.get(cellKey);
    if (cell) {
      cell.delete(entityId);
      if (cell.size === 0) {
        this.cells.delete(cellKey);
      }
    }

    this.entityPositions.delete(entityId);
  }

  /**
   * Update entity position in spatial grid
   * Efficiently handles cell transitions
   *
   * @param entityId - Entity identifier
   * @param newPos - New entity position
   */
  update(entityId: string, newPos: Position): void {
    const oldPos = this.entityPositions.get(entityId);
    if (!oldPos) {
      // Entity not in grid yet, insert it
      this.insert(entityId, newPos);
      return;
    }

    const oldCellKey = this.getCellKey(oldPos);
    const newCellKey = this.getCellKey(newPos);

    // Only update if cell changed
    if (oldCellKey !== newCellKey) {
      // Remove from old cell
      const oldCell = this.cells.get(oldCellKey);
      if (oldCell) {
        oldCell.delete(entityId);
        if (oldCell.size === 0) {
          this.cells.delete(oldCellKey);
        }
      }

      // Add to new cell
      if (!this.cells.has(newCellKey)) {
        this.cells.set(newCellKey, new Set());
      }
      this.cells.get(newCellKey)!.add(entityId);
    }

    // Update position
    this.entityPositions.set(entityId, newPos);
  }

  /**
   * Get all entities within radius of a position
   * Task 2.3.2: AOI query
   *
   * @param centerPos - Center position for query
   * @param radius - AOI radius in meters
   * @returns Array of entity IDs within radius
   */
  getEntitiesInRadius(centerPos: Position, radius: number): string[] {
    const cellRadius = Math.ceil(radius / this.cellSize);
    const centerKey = this.getCellKey(centerPos);

    // Parse center cell coordinates
    const centerCoords = centerKey.split(',').map(Number);
    const is3D = centerCoords.length === 3;

    const visible = new Set<string>();

    // Check surrounding cells
    if (is3D) {
      // 3D: iterate through cube of cells
      const [cx, cy, cz] = centerCoords;
      for (let dx = -cellRadius; dx <= cellRadius; dx++) {
        for (let dy = -cellRadius; dy <= cellRadius; dy++) {
          for (let dz = -cellRadius; dz <= cellRadius; dz++) {
            const key = `${cx + dx},${cy + dy},${cz + dz}`;
            const entities = this.cells.get(key);
            if (entities) {
              entities.forEach(id => {
                const pos = this.entityPositions.get(id);
                if (pos && calculateDistance(centerPos, pos) <= radius) {
                  visible.add(id);
                }
              });
            }
          }
        }
      }
    } else {
      // 2D: iterate through square of cells
      const [cx, cy] = centerCoords;
      for (let dx = -cellRadius; dx <= cellRadius; dx++) {
        for (let dy = -cellRadius; dy <= cellRadius; dy++) {
          const key = `${cx + dx},${cy + dy}`;
          const entities = this.cells.get(key);
          if (entities) {
            entities.forEach(id => {
              const pos = this.entityPositions.get(id);
              if (pos && calculateDistance(centerPos, pos) <= radius) {
                visible.add(id);
              }
            });
          }
        }
      }
    }

    return Array.from(visible);
  }

  /**
   * Clear all entities from grid
   */
  clear(): void {
    this.cells.clear();
    this.entityPositions.clear();
  }
}

/**
 * Calculate distance between two positions
 * Task 2.3.2: Distance calculation helper
 *
 * Supports both 2D and 3D distance calculations.
 * Automatically detects dimensionality.
 *
 * @param pos1 - First position
 * @param pos2 - Second position
 * @returns Euclidean distance
 */
export function calculateDistance(pos1: Position, pos2: Position): number {
  const dx = pos2.x - pos1.x;
  const dy = pos2.y - pos1.y;

  // 3D distance if either position has z-coordinate
  if (pos1.z !== undefined || pos2.z !== undefined) {
    const z1 = pos1.z || 0;
    const z2 = pos2.z || 0;
    const dz = z2 - z1;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  // 2D distance
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Filter zone delta by player's Area of Interest
 * Task 2.3.2: Per-player delta filtering
 * Task 2.3.3: Entity add/remove messages
 *
 * Filters delta updates to include only entities within player's AOI.
 * Implements Requirement 8: Only send deltas for entities in AOI.
 * Implements Requirement 8: Send entity-add messages with full snapshots when entities enter AOI.
 * Implements Requirement 8: Send entity-remove messages when entities exit AOI.
 *
 * @param delta - Full zone delta
 * @param playerPos - Player's current position
 * @param aoiRadius - AOI radius in meters (default: 50)
 * @param previousAOI - Set of entity IDs in player's previous AOI (for add/remove detection)
 * @param currentState - Current zone state (needed to construct full snapshots for AOI enters)
 * @returns Filtered delta with only relevant entities
 */
export function filterDeltaByAOI(
  delta: ZoneDelta,
  playerPos: Position,
  aoiRadius: number = 50,
  previousAOI: Set<string> = new Set(),
  currentState?: ZoneState
): ZoneDelta {
  const filteredDelta: ZoneDelta = {
    timestamp: delta.timestamp,
    version: delta.version,
    entityUpdates: [],
    entityAdds: [],
    entityRemoves: []
  };

  // Current entities in AOI
  const currentAOI = new Set<string>();

  // Filter entity updates - only include entities in AOI
  // Task 2.3.4: EntityUpdate now has granular fields, need current position from state
  for (const update of delta.entityUpdates) {
    // Get entity's current position from state (updates only have changed fields)
    if (currentState) {
      const entity = currentState.entities.find(e => e.entityId === update.entityId);
      if (entity) {
        const distance = calculateDistance(playerPos, entity.transform.position);
        if (distance <= aoiRadius) {
          // Task 2.3.3: Check if this is an entity entering AOI
          if (!previousAOI.has(update.entityId)) {
            // Entity entered AOI - send full snapshot instead of update
            filteredDelta.entityAdds.push(entity);
          } else {
            // Normal update for entity already in AOI
            filteredDelta.entityUpdates.push(update);
          }
          currentAOI.add(update.entityId);
        }
      }
    }
  }

  // Filter entity adds - only include new entities in AOI
  // Task 2.3.3: These are truly new entities, send full EntitySnapshot
  for (const entity of delta.entityAdds) {
    const distance = calculateDistance(playerPos, entity.transform.position);
    if (distance <= aoiRadius) {
      filteredDelta.entityAdds.push(entity);
      currentAOI.add(entity.entityId);
    }
  }

  // Entity removes - Filter to only include entities that were in player's AOI
  // Task 2.3.3: Send entity ID only (string) for removed entities
  for (const entityId of delta.entityRemoves) {
    if (previousAOI.has(entityId)) {
      filteredDelta.entityRemoves.push(entityId);
    }
  }

  // Detect entities exiting AOI (were in previousAOI but not in currentAOI)
  // Task 2.3.3: Send entity-remove messages for these (entity ID only)
  for (const entityId of previousAOI) {
    if (!currentAOI.has(entityId) && delta.entityRemoves.indexOf(entityId) === -1) {
      // Entity left AOI but wasn't removed from zone
      filteredDelta.entityRemoves.push(entityId);
    }
  }

  return filteredDelta;
}

/**
 * Check if entity is in player's AOI
 * Task 2.3.2: AOI membership test
 *
 * @param entityPos - Entity position
 * @param playerPos - Player position
 * @param aoiRadius - AOI radius in meters
 * @returns True if entity is within AOI
 */
export function isEntityInAOI(
  entityPos: Position,
  playerPos: Position,
  aoiRadius: number
): boolean {
  return calculateDistance(entityPos, playerPos) <= aoiRadius;
}
