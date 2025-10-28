/**
 * Zone State Data Structures
 *
 * Defines the core data structures for zone management, snapshots, and deltas.
 * Supports both 2D and 3D worlds with dimension-agnostic position types.
 *
 * Requirements: 4 (World Entry and Zone Snapshot), 7 (Persistent Zone State)
 */

/**
 * Position vector supporting both 2D and 3D worlds.
 * For 2D games: z is optional (omit or set to 0)
 * For 3D games: all three coordinates are used
 *
 * Examples:
 * - 2D top-down: {x: 100, y: 200} or {x: 100, y: 200, z: 0}
 * - 3D world: {x: 100, y: 50, z: 200}
 */
export interface Position {
  x: number;
  y: number;
  z?: number; // Optional for 2D compatibility
}

/**
 * Legacy Vector3 type alias for backward compatibility.
 * @deprecated Use Position instead for new code
 */
export type Vector3 = Position & { z: number };

/**
 * Entity transform supporting both 2D and 3D orientations.
 * For 2D: rotation can be a single angle or {x: 0, y: 0, z: angle}
 * For 3D: rotation uses full Euler angles
 */
export interface Transform {
  position: Position;
  rotation: Position; // Euler angles in radians (2D uses z only)
}

/**
 * Legacy Transform3D type alias for backward compatibility.
 * @deprecated Use Transform instead for new code
 */
export type Transform3D = Transform;

/**
 * Core zone state containing all persistent and runtime data for a zone.
 * This represents the authoritative state of a zone shard.
 * Supports both 2D and 3D zones.
 */
export interface ZoneState {
  /** Zone identifier (e.g., "forest_01", "dungeon_crypt") */
  zoneId: string;

  /** Shard identifier for this zone instance */
  shardId: string;

  /** Current in-game time for this zone (server timestamp ms) */
  zoneTime: number;

  /** Version number for optimistic locking and persistence */
  version: number;

  /** All entities currently in this zone (players, NPCs, objects) */
  entities: EntitySnapshot[];

  /**
   * Terrain/map chunk identifiers (references, not full chunk data)
   * - For 2D: TileMap chunk IDs
   * - For 3D: Terrain mesh/heightmap chunk IDs
   */
  terrainChunks: string[];

  /** Named timers for zone events (boss spawns, event triggers, etc.) */
  timers: Record<string, number>;

  /** Zone-wide effects (weather, day/night cycle modifiers, etc.) */
  activeEffects: GlobalEffect[];
}

/**
 * Snapshot of a single entity in the zone.
 * Includes all state needed to reconstruct the entity client-side.
 * Works for both 2D and 3D entities.
 */
export interface EntitySnapshot {
  /** Unique entity identifier */
  entityId: string;

  /** Entity type (player, npc, resource_node, etc.) */
  type: string;

  /** Transform (position, rotation) - works for 2D and 3D */
  transform: Transform;

  /** Current vitals (health, mana, etc.) */
  vitals: Vitals;

  /** Optional: Additional entity-specific state */
  state?: Record<string, any>;
}

/**
 * Entity vitals (health, mana, etc.) */
export interface Vitals {
  health: number;
  maxHealth: number;
  mana?: number;
  maxMana?: number;
}

/**
 * Zone-wide environmental effect
 */
export interface GlobalEffect {
  /** Effect identifier */
  effectId: string;

  /** Effect type (weather, time_modifier, zone_buff, etc.) */
  type: string;

  /** Effect parameters */
  params: Record<string, any>;

  /** When effect expires (server timestamp ms, -1 = permanent) */
  expiresAt: number;
}

/**
 * Delta update representing changes to zone state.
 * Used for streaming incremental updates to clients.
 */
export interface ZoneDelta {
  /** When this delta was generated (server timestamp ms) */
  timestamp: number;

  /** Version number this delta applies to */
  version: number;

  /** Updated entities (partial state) */
  entityUpdates: EntityUpdate[];

  /** Newly spawned entities */
  entityAdds: EntitySnapshot[];

  /** Despawned entity IDs */
  entityRemoves: string[];
}

/**
 * Partial entity state update (only changed fields)
 * Task 2.3.4: Bandwidth optimization
 *
 * Sends only individual changed fields instead of complete objects.
 * This significantly reduces delta payload size.
 *
 * Supports both 2D and 3D entities:
 * - 2D: position fields use x, y (z is undefined)
 * - 3D: position fields use x, y, z
 *
 * Examples:
 * - Only X position changed: {entityId: "123", positionX: 10.5}
 * - Health and position changed: {entityId: "123", positionX: 10.5, positionY: 20.0, health: 50}
 * - Full transform change: {entityId: "123", positionX, positionY, positionZ, rotationX, rotationY, rotationZ}
 */
export interface EntityUpdate {
  entityId: string;

  // Position fields (sent individually for bandwidth optimization)
  positionX?: number;
  positionY?: number;
  positionZ?: number; // Optional for 2D worlds

  // Rotation fields (sent individually)
  rotationX?: number;
  rotationY?: number;
  rotationZ?: number;

  // Vitals fields (sent individually)
  health?: number;
  maxHealth?: number;
  mana?: number;
  maxMana?: number;

  // Arbitrary entity state (if changed)
  state?: Record<string, any>;
}

/**
 * Compressed zone snapshot for client transmission.
 * Requirements: 4.3 (512KB budget, Deflate compression)
 * Supports both 2D and 3D zones
 */
export interface ZoneSnapshot {
  /** Current in-game time for this zone */
  zoneTime: number;

  /**
   * Terrain/map chunk IDs (references, not full chunk data)
   * - For 2D: TileMap chunk IDs
   * - For 3D: Terrain mesh/heightmap chunk IDs
   */
  terrainChunks: string[];

  /** Entities visible from AOI seed position */
  entities: EntitySnapshot[];

  /**
   * Area of Interest seed (player spawn/camera position)
   * - For 2D: {x, y} or {x, y, z: 0}
   * - For 3D: {x, y, z}
   */
  aoiSeed: Position;

  /** Active zone-wide effects */
  activeEffects: GlobalEffect[];

  /** Deflate-compressed binary blob of the above data */
  compressedBlob: Uint8Array;

  /** Version number for this snapshot */
  version: number;
}
