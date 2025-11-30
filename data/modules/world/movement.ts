/**
 * Movement Validation Module
 *
 * Implements server-authoritative movement validation with client-side
 * prediction and reconciliation support.
 *
 * Phase 3, Task: 3.1.1 - Implement move_intent RPC
 * Phase 3, Task: 3.1.2 - Implement server-side physics
 * Phase 3, Task: 3.1.3 - Implement position broadcasting
 * Requirements: 5 (Server-Authoritative Movement)
 * Design: Movement & Combat Service (lines 277-310)
 *
 * This module processes movement intents from clients, validates them against
 * physics constraints, and returns authoritative position updates.
 * Supports both 2D and 3D movement validation.
 */

import { Position } from './types';
import { broadcastZoneDelta, createZoneMatch, getOrCreateZoneMatch } from './delta';
import { ZoneDelta, EntityUpdate } from './types';

/**
 * Character context loaded from database.
 * Includes position and zone for movement validation and broadcasting.
 */
interface CharacterContext {
  position: Position;
  zoneId: string;
  characterId: string;
}

/**
 * Client movement intent.
 * Sent by client using client-side prediction.
 */
export interface MoveIntent {
  /** Direction vector (horizontal plane, normalized) */
  direction: { x: number; y: number };

  /** Client timestamp when intent was generated (ms) */
  timestamp: number;

  /** Unique nonce for client reconciliation */
  nonce: number;

  /** Client's predicted position (for drift detection) */
  predictedPosition?: Position;
}

/**
 * Server response to movement intent.
 * Includes acknowledgment and optional correction.
 */
export interface MoveResult {
  /** Whether movement was accepted */
  ack: boolean;

  /** Authoritative position (sent if correction needed) */
  correction?: Position;

  /** Echo of client nonce for reconciliation */
  nonce: number;

  /** Optional error message if movement rejected */
  error?: string;
}

/**
 * Movement validation configuration.
 */
interface MovementConfig {
  /** Maximum movement speed (units per second) */
  maxSpeed: number;

  /** Tick rate for movement updates (Hz) */
  tickRate: number;

  /** Maximum allowed timestamp drift (ms) */
  maxTimestampDrift: number;

  /** Collision detection enabled */
  collisionEnabled: boolean;

  /** Position drift threshold for corrections (units) */
  driftThreshold: number;
}

/**
 * Default movement configuration.
 * Task 3.1.2: Full physics/collision validation enabled.
 * Task 3.1.4: Position drift detection enabled.
 */
const DEFAULT_CONFIG: MovementConfig = {
  maxSpeed: 10.0, // 10 units/second
  tickRate: 20, // 20 Hz server tick
  maxTimestampDrift: 1000, // 1 second max drift
  collisionEnabled: true, // Task 3.1.2: Collision detection enabled
  driftThreshold: 0.5, // Task 3.1.4: 0.5 units position drift threshold
};

/**
 * Validates a movement intent and calculates authoritative position.
 *
 * Validation steps:
 * 1. Verify player is in active zone
 * 2. Check timestamp drift (prevent replay attacks)
 * 3. Validate direction vector (magnitude ≤1)
 * 4. Validate speed (distance ≤ maxSpeed * deltaTime)
 * 5. Check collision (Task 3.1.2)
 * 6. Calculate authoritative position
 * 7. Return ack or correction
 *
 * @param ctx Nakama context
 * @param logger Nakama logger
 * @param nk Nakama runtime
 * @param payload JSON payload with move intent
 * @returns Move result with ack and optional correction
 */
export function rpcMoveIntent(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  // Parse and validate input
  let intent: MoveIntent;
  try {
    intent = JSON.parse(payload) as MoveIntent;
  } catch (error) {
    logger.error('[movement] Invalid JSON payload: %v', error);
    return JSON.stringify({
      ack: false,
      nonce: 0,
      error: 'Invalid JSON payload',
    } as MoveResult);
  }

  // Validate required fields
  if (
    !intent.direction ||
    typeof intent.direction.x !== 'number' ||
    typeof intent.direction.y !== 'number' ||
    typeof intent.timestamp !== 'number' ||
    typeof intent.nonce !== 'number'
  ) {
    logger.error('[movement] Missing required fields in move intent');
    return JSON.stringify({
      ack: false,
      nonce: intent.nonce || 0,
      error: 'Missing required fields: direction, timestamp, nonce',
    } as MoveResult);
  }

  // Require authentication
  if (!ctx.userId) {
    logger.warn('[movement] Unauthenticated move intent attempt');
    return JSON.stringify({
      ack: false,
      nonce: intent.nonce,
      error: 'Authentication required',
    } as MoveResult);
  }

    logger.info(
    '[movement] Processing move intent for user %s (nonce: %d, direction: [%f, %f])',
    ctx.userId,
    intent.nonce,
    intent.direction.x,
    intent.direction.y
  );

  // Load character context (position, zone) from database
  // In production (Phase 2.2), this would come from ZoneProcess in-memory state
  const characterCtx = loadCharacterContext(nk, logger, ctx.userId);

  if (!characterCtx) {
    logger.error('[movement] Character not found for user %s', ctx.userId);
    return JSON.stringify({
      ack: false,
      nonce: intent.nonce,
      error: 'Character not found or not in active zone',
    } as MoveResult);
  }

  // Validate movement against physics constraints
  const validation = validateMovement(
    intent,
    characterCtx.position,
    DEFAULT_CONFIG,
    logger
  );

  if (!validation.valid) {
    logger.warn('[movement] Invalid movement for user %s: %s', ctx.userId, validation.reason);
    return JSON.stringify({
      ack: false,
      correction: characterCtx.position, // Send current position as correction
      nonce: intent.nonce,
      error: validation.reason,
    } as MoveResult);
  }

  // Calculate authoritative position
  const newPosition = calculateNewPosition(
    characterCtx.position,
    intent,
    validation.deltaTime,
    DEFAULT_CONFIG
  );

  // Task 3.1.2: Collision detection
  if (DEFAULT_CONFIG.collisionEnabled) {
    const collisionResult = checkCollision(
      characterCtx.position,
      newPosition,
      ctx.userId,
      nk,
      logger
    );

    if (collisionResult.collision) {
      logger.warn(
        `Collision detected for user ${ctx.userId}: ${collisionResult.reason}`
      );

      // Update to safe position and send correction
      const safePosition = collisionResult.safePosition || characterCtx.position;
      updateCharacterPosition(nk, logger, ctx.userId, safePosition);

      return JSON.stringify({
        ack: false,
        correction: safePosition,
        nonce: intent.nonce,
        error: collisionResult.reason,
      } as MoveResult);
    }
  }

  // Task 3.1.4: Position drift detection
  // Check if client's prediction has drifted from server's calculation
  if (intent.predictedPosition) {
    const driftDetected = detectPositionDrift(
      intent.predictedPosition,
      newPosition,
      DEFAULT_CONFIG.driftThreshold,
      logger
    );

    if (driftDetected) {
      logger.info(
        '[movement] Sending position correction to user %s due to prediction drift',
        ctx.userId
      );

      // Update to authoritative position
      updateCharacterPosition(nk, logger, ctx.userId, newPosition);

      // Broadcast position to AOI subscribers
      broadcastPositionUpdate(
        nk,
        logger,
        characterCtx.zoneId,
        characterCtx.characterId,
        newPosition,
        intent.nonce
      );

      // Send correction to client for reconciliation
      return JSON.stringify({
        ack: true,
        correction: newPosition, // Server's authoritative position
        nonce: intent.nonce,
      } as MoveResult);
    }
  }

  // Update character position in database
  // In production (Phase 2.2), this would update ZoneProcess in-memory state
  // which would be persisted via checkpoint system
  updateCharacterPosition(nk, logger, ctx.userId, newPosition);

  // Task 3.1.3: Broadcast position to AOI subscribers
  broadcastPositionUpdate(
    nk,
    logger,
    characterCtx.zoneId,
    characterCtx.characterId,
    newPosition,
    intent.nonce
  );

  logger.info(
    '[movement] Move accepted for user %s: position [%f, %f%s]',
    ctx.userId,
    newPosition.x,
    newPosition.y,
    newPosition.z !== undefined ? ', ' + newPosition.z : ''
  );

  // Return acknowledgment (no correction needed)
  return JSON.stringify({
    ack: true,
    nonce: intent.nonce,
  } as MoveResult);
}

/**
 * Validation result from physics checks.
 */
interface ValidationResult {
  valid: boolean;
  reason?: string;
  deltaTime: number; // Time since last update (ms)
}

/**
 * Validates movement intent against physics constraints.
 *
 * Checks:
 * 1. Timestamp drift (prevent replay attacks)
 * 2. Direction vector magnitude (must be ≤1)
 * 3. Speed limit (distance ≤ maxSpeed * deltaTime)
 *
 * @param intent Client movement intent
 * @param currentPosition Current character position
 * @param config Movement configuration
 * @param logger Nakama logger
 * @returns Validation result
 */
function validateMovement(
  intent: MoveIntent,
  currentPosition: Position,
  config: MovementConfig,
  logger: any
): ValidationResult {
  const serverTime = Date.now();
  const deltaTime = serverTime - intent.timestamp;

  // Check timestamp drift
  if (Math.abs(deltaTime) > config.maxTimestampDrift) {
    return {
      valid: false,
      reason: `Timestamp drift too large: ${deltaTime}ms`,
      deltaTime: 0,
    };
  }

  // Validate direction vector magnitude
  const dirMagnitude = Math.sqrt(
    intent.direction.x * intent.direction.x +
      intent.direction.y * intent.direction.y
  );

  if (dirMagnitude > 1.1) {
    // Allow small epsilon for floating point errors
    return {
      valid: false,
      reason: `Direction magnitude exceeds 1.0: ${dirMagnitude}`,
      deltaTime: 0,
    };
  }

  // Calculate expected maximum distance for this frame
  const maxDistance = config.maxSpeed * (Math.abs(deltaTime) / 1000.0);

  // Normalize direction if needed
  let normalizedDir = intent.direction;
  if (dirMagnitude > 1.0) {
    normalizedDir = {
      x: intent.direction.x / dirMagnitude,
      y: intent.direction.y / dirMagnitude,
    };
  }

  // Calculate actual distance player would move
  const actualDistance = Math.sqrt(
    normalizedDir.x * normalizedDir.x + normalizedDir.y * normalizedDir.y
  );

  if (actualDistance * config.maxSpeed * (Math.abs(deltaTime) / 1000.0) > maxDistance * 1.1) {
    return {
      valid: false,
      reason: `Speed limit exceeded: ${actualDistance} > ${maxDistance}`,
      deltaTime: Math.abs(deltaTime),
    };
  }

  return {
    valid: true,
    deltaTime: Math.abs(deltaTime),
  };
}

/**
 * Calculates new authoritative position based on validated movement.
 *
 * Supports both 2D and 3D worlds:
 * - 2D: Updates x, y; z remains 0 or undefined
 * - 3D: Updates x, z (horizontal plane); y (vertical) unchanged for horizontal movement
 *
 * @param currentPos Current position
 * @param intent Movement intent
 * @param deltaTime Time delta (ms)
 * @param config Movement configuration
 * @returns New authoritative position
 */
function calculateNewPosition(
  currentPos: Position,
  intent: MoveIntent,
  deltaTime: number,
  config: MovementConfig
): Position {
  // Normalize direction
  const dirMagnitude = Math.sqrt(
    intent.direction.x * intent.direction.x +
      intent.direction.y * intent.direction.y
  );

  let normalizedDir = intent.direction;
  if (dirMagnitude > 1.0) {
    normalizedDir = {
      x: intent.direction.x / dirMagnitude,
      y: intent.direction.y / dirMagnitude,
    };
  } else if (dirMagnitude === 0) {
    // No movement
    return currentPos;
  }

  // Calculate movement delta
  const speed = config.maxSpeed;
  const distance = speed * (deltaTime / 1000.0);

  // Determine if 3D world (has z coordinate)
  const is3D = currentPos.z !== undefined;

  if (is3D) {
    // 3D world: direction.x/y map to horizontal plane (x/z in 3D space)
    // direction.x → world X axis
    // direction.y → world Z axis
    // Y axis (vertical) unchanged for horizontal movement
    return {
      x: currentPos.x + normalizedDir.x * distance,
      y: currentPos.y!, // Vertical position unchanged
      z: currentPos.z! + normalizedDir.y * distance,
    };
  } else {
    // 2D world: direction.x/y map to x/y coordinates
    return {
      x: currentPos.x + normalizedDir.x * distance,
      y: currentPos.y + normalizedDir.y * distance,
    };
  }
}

/**
 * Collision detection result.
 */
interface CollisionResult {
  /** Whether a collision was detected */
  collision: boolean;

  /** Safe position if collision occurred */
  safePosition?: Position;

  /** Collision reason (for debugging) */
  reason?: string;
}

/**
 * Checks for terrain collisions at the target position.
 *
 * Task 3.1.2: Basic terrain boundary collision detection.
 * Future enhancement: Load terrain chunks from database/ZoneProcess
 * and check against actual terrain geometry.
 *
 * For now, implements simple boundary box collision:
 * - 2D: Rectangular boundary
 * - 3D: Cuboid boundary
 *
 * @param position Target position to check
 * @param nk Nakama runtime
 * @param logger Nakama logger
 * @returns True if position collides with terrain
 */
function checkTerrainCollision(
  position: Position,
  nk: any,
  logger: any
): boolean {
  // Basic world boundaries (production would load from zone config)
  const WORLD_MIN_X = -1000;
  const WORLD_MAX_X = 1000;
  const WORLD_MIN_Y = -1000;
  const WORLD_MAX_Y = 1000;
  const WORLD_MIN_Z = -1000;
  const WORLD_MAX_Z = 1000;

  // Check 2D boundaries
  if (position.x < WORLD_MIN_X || position.x > WORLD_MAX_X) {
    return true;
  }
  if (position.y < WORLD_MIN_Y || position.y > WORLD_MAX_Y) {
    return true;
  }

  // Check 3D boundaries if applicable
  if (position.z !== undefined) {
    if (position.z < WORLD_MIN_Z || position.z > WORLD_MAX_Z) {
      return true;
    }
  }

  // Future: Check against terrain chunks loaded from database
  // const terrainCollision = checkTerrainChunkCollision(position, terrainData);

  return false;
}

/**
 * Checks for entity-entity collisions.
 *
 * Task 3.1.2: Basic entity collision detection using circle/sphere overlap.
 * - 2D: Circle collision (distance check on x/y plane)
 * - 3D: Sphere collision (distance check in 3D space)
 *
 * Production implementation (Phase 2.2) would query ZoneProcess for
 * nearby entities using spatial partitioning (quadtree/octree).
 *
 * @param position Target position to check
 * @param userId Current user ID (exclude self)
 * @param nk Nakama runtime
 * @param logger Nakama logger
 * @returns True if position collides with another entity
 */
function checkEntityCollision(
  position: Position,
  userId: string,
  nk: any,
  logger: any
): boolean {
  // Entity collision radius (production: load from character data)
  const COLLISION_RADIUS = 0.5;

  // Future: Query ZoneProcess for nearby entities within AOI
  // For now, skip entity collision (would require zone state query)
  // Production: const nearbyEntities = zoneProcess.getEntitiesInRadius(position, AOI_RADIUS);

  // Placeholder: No entity collision for Task 3.1.2
  // Real implementation needs ZoneProcess integration (Phase 2.2)
  return false;
}

/**
 * Finds the nearest safe position when a collision is detected.
 *
 * Task 3.1.2: Basic collision resolution - clamp to boundaries.
 * Future enhancement: Slide along collision surface, pathfinding to nearest safe spot.
 *
 * @param targetPos The attempted position that collided
 * @param currentPos The current safe position
 * @returns Nearest safe position
 */
function findSafePosition(targetPos: Position, currentPos: Position): Position {
  // Basic world boundaries (match checkTerrainCollision)
  const WORLD_MIN_X = -1000;
  const WORLD_MAX_X = 1000;
  const WORLD_MIN_Y = -1000;
  const WORLD_MAX_Y = 1000;
  const WORLD_MIN_Z = -1000;
  const WORLD_MAX_Z = 1000;

  const safePos: Position = {
    x: Math.max(WORLD_MIN_X, Math.min(WORLD_MAX_X, targetPos.x)),
    y: Math.max(WORLD_MIN_Y, Math.min(WORLD_MAX_Y, targetPos.y)),
  };

  if (targetPos.z !== undefined) {
    safePos.z = Math.max(WORLD_MIN_Z, Math.min(WORLD_MAX_Z, targetPos.z));
  }

  return safePos;
}

/**
 * Performs comprehensive collision detection.
 *
 * Task 3.1.2: Checks both terrain and entity collisions.
 * Returns collision result with safe position if collision detected.
 *
 * @param currentPos Current character position
 * @param targetPos Target position after movement
 * @param userId User ID performing movement
 * @param nk Nakama runtime
 * @param logger Nakama logger
 * @returns Collision result with safe position if needed
 */
function checkCollision(
  currentPos: Position,
  targetPos: Position,
  userId: string,
  nk: any,
  logger: any
): CollisionResult {
  // Check terrain collision
  const terrainCollision = checkTerrainCollision(targetPos, nk, logger);
  if (terrainCollision) {
    const safePos = findSafePosition(targetPos, currentPos);
    return {
      collision: true,
      safePosition: safePos,
      reason: 'Terrain boundary collision',
    };
  }

  // Check entity collision
  const entityCollision = checkEntityCollision(targetPos, userId, nk, logger);
  if (entityCollision) {
    // Entity collision: stay at current position
    return {
      collision: true,
      safePosition: currentPos,
      reason: 'Entity collision',
    };
  }

  // No collision
  return {
    collision: false,
  };
}

/**
 * Detects position drift between client prediction and server calculation.
 * Task 3.1.4: Position correction
 *
 * Compares the client's predicted position with the server's authoritative
 * calculation. If drift exceeds threshold, returns true to trigger correction.
 *
 * Supports both 2D and 3D position comparison:
 * - 2D: Euclidean distance on x/y plane
 * - 3D: Euclidean distance in 3D space
 *
 * @param clientPredicted Client's predicted position
 * @param serverCalculated Server's authoritative calculated position
 * @param threshold Maximum allowed drift (units)
 * @param logger Nakama logger
 * @returns True if drift exceeds threshold, false otherwise
 */
function detectPositionDrift(
  clientPredicted: Position,
  serverCalculated: Position,
  threshold: number,
  logger: any
): boolean {
  // Calculate Euclidean distance between positions
  const is3D = serverCalculated.z !== undefined || clientPredicted.z !== undefined;

  let distance: number;

  if (is3D) {
    // 3D distance calculation
    const dx = serverCalculated.x - clientPredicted.x;
    const dy = (serverCalculated.y || 0) - (clientPredicted.y || 0);
    const dz = (serverCalculated.z || 0) - (clientPredicted.z || 0);
    distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
  } else {
    // 2D distance calculation
    const dx = serverCalculated.x - clientPredicted.x;
    const dy = serverCalculated.y - clientPredicted.y;
    distance = Math.sqrt(dx * dx + dy * dy);
  }

  const driftDetected = distance > threshold;

  if (driftDetected) {
    logger.debug(
      '[movement] Position drift detected: %.2f units (threshold: %.2f)',
      distance,
      threshold
    );
  }

  return driftDetected;
}

/**
 * Loads character context (position, zone) from database.
 *
 * In production (Phase 2.2), this would query the active ZoneProcess
 * in-memory state instead of database.
 *
 * @param nk Nakama runtime
 * @param logger Nakama logger
 * @param userId User ID
 * @returns Character context or null if not found
 */
function loadCharacterContext(
  nk: any,
  logger: any,
  userId: string
): CharacterContext | null {
  try {
    // Query character position and zone from database
    // Assumes player has selected a character (Phase 1)
    const result = nk.sqlQuery(`
      SELECT character_id, last_position, last_zone_id
      FROM characters
      WHERE account_id = $1
      ORDER BY last_login_at DESC
      LIMIT 1
    `, [userId]);

    if (result.length === 0) {
      logger.warn('[movement] No character found for user %s', userId);
      return null;
    }

    // Parse JSONB position
    const positionJson = result[0].last_position;
    const position: Position = JSON.parse(positionJson);
    const zoneId: string = result[0].last_zone_id;
    const characterId: string = result[0].character_id;

    return {
      position,
      zoneId,
      characterId
    };
  } catch (error) {
    logger.error('[movement] Failed to load character context: %v', error);
    return null;
  }
}

/**
 * Updates character position in database.
 *
 * In production (Phase 2.2), this would update ZoneProcess in-memory state
 * which gets persisted via the checkpoint system.
 *
 * @param nk Nakama runtime
 * @param logger Nakama logger
 * @param userId User ID
 * @param newPosition New authoritative position
 */
function updateCharacterPosition(
  nk: any,
  logger: any,
  userId: string,
  newPosition: Position
): void {
  try {
    nk.sqlExec(`
      UPDATE characters
      SET last_position = $1
      WHERE account_id = $2
    `, [JSON.stringify(newPosition), userId]);

    logger.debug(
      '[movement] Updated position for user %s to [%f, %f%s]',
      userId,
      newPosition.x,
      newPosition.y,
      newPosition.z !== undefined ? ', ' + newPosition.z : ''
    );
  } catch (error) {
    logger.error('[movement] Failed to update character position: %v', error);
  }
}

/**
 * Register movement RPC handlers.
 *
 * @param ctx Nakama context
 * @param logger Nakama logger
 * @param nk Nakama runtime
 * @param initializer Nakama initializer
 */
/**
 * Broadcasts position update to AOI subscribers.
 * Task 3.1.3: Position broadcasting at 10-20 Hz
 *
 * Creates an EntityUpdate with the new position and broadcasts it
 * via the zone delta streaming system to all players in AOI.
 *
 * In production (Phase 2.2), ZoneProcess tick loop would handle broadcasting
 * at a fixed 10-20 Hz rate. For Phase 3.1.3, we broadcast immediately on
 * each move_intent to satisfy the requirement.
 *
 * @param nk Nakama runtime
 * @param logger Nakama logger
 * @param zoneId Zone identifier
 * @param entityId Character/entity ID
 * @param position New authoritative position
 * @param nonce Client nonce for reconciliation
 */
function broadcastPositionUpdate(
  nk: any,
  logger: any,
  zoneId: string,
  entityId: string,
  position: Position,
  nonce: number
): void {
  try {
    // Create entity update with new position
    // Task 2.3.4: Send only changed fields (bandwidth optimization)
    const entityUpdate: EntityUpdate = {
      entityId,
      positionX: position.x,
      positionY: position.y,
    };

    // Include z-coordinate for 3D worlds
    if (position.z !== undefined) {
      entityUpdate.positionZ = position.z;
    }

    // Create zone delta with this single position update
    const delta: ZoneDelta = {
      timestamp: Date.now(),
      version: 0, // Version tracking in production via ZoneProcess
      entityUpdates: [entityUpdate],
      entityAdds: [],
      entityRemoves: [],
    };

    // Get or create match for this zone
    // In production, match would be created when zone starts
    // and stored in ZoneProcess state
    const matchId = getOrCreateZoneMatch(nk, logger, zoneId);

    if (matchId) {
      // Broadcast delta to all players in zone match
      // Delta system handles AOI filtering and compression
      broadcastZoneDelta(nk, logger, matchId, delta);

      logger.debug(
        '[movement] Broadcast position update for entity %s in zone %s (nonce: %d)',
        entityId,
        zoneId,
        nonce
      );
    } else {
      logger.warn(
        '[movement] No active match for zone %s, skipping broadcast',
        zoneId
      );
    }
  } catch (err: any) {
    logger.error(
      '[movement] Failed to broadcast position update: %s',
      err.message
    );
  }
}



/**
 * Module initialization.
 * Registers RPCs with Nakama runtime.
 */
function InitModule(
  ctx: any,
  logger: any,
  nk: any,
  initializer: any
) {
  // Register move_intent RPC
  initializer.registerRpc('move_intent', rpcMoveIntent);

  logger.info('[movement] Movement module initialized');
}

// Export init function for Nakama runtime
export { InitModule };
