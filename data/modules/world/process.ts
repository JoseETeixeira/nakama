/**
 * Zone Process - Runtime Zone Management
 *
 * Manages in-memory zone state with tick loop for entity updates,
 * NPC AI, resource nodes, and environmental systems.
 *
 * Task: 2.2.1
 * Requirements: 7 (Persistent Zone State - foundation)
 * Design: Section "Zone Tick Loop" (lines 1265-1340)
 */

import { ZoneState, EntitySnapshot, Position } from './types';
import { generateZoneDelta, broadcastZoneDelta as broadcastDeltaToMatch, SpatialGrid, filterDeltaByAOI } from './delta';

/**
 * Configuration for ZoneProcess
 * Performance targets from design.md
 */
interface ZoneProcessConfig {
  /** Tick rate in Hz (10-20) */
  tickRate: number;

  /** Tick budget in milliseconds (target: ≤10ms p95) */
  tickBudgetMs: number;

  /** Checkpoint interval in milliseconds (default: 10 seconds) */
  checkpointIntervalMs: number;

  /** Zone identifier */
  zoneId: string;

  /** Shard identifier */
  shardId: string;
}

/**
 * Zone event for logging state changes
 * Task 2.2.3 will use this for event_log persistence
 */
interface ZoneEvent {
  type: string;
  timestamp: number;
  data: any;
}

/**
 * ZoneProcess manages the runtime state of a single zone.
 *
 * Responsibilities:
 * - Tick loop at 10-20 Hz for entity updates
 * - Manage in-memory ZoneState
 * - Track state-changing events (for Task 2.2.3)
 * - Checkpoint coordination (for Task 2.2.2)
 *
 * Design Pattern:
 * - One ZoneProcess instance per active zone
 * - Runs independently with own tick loop
 * - State persisted via checkpoints + event log (future tasks)
 *
 * Performance:
 * - Tick budget: ≤10ms p95 at 1k entities
 * - Tick rate: 20 Hz (configurable)
 * - Checkpoint interval: 10 seconds
 */
class ZoneProcess {
  /** Current zone state (in-memory) */
  private state: ZoneState;

  /** Previous zone state (for delta generation) */
  private previousState: ZoneState;

  /** Configuration */
  private config: ZoneProcessConfig;

  /** Nakama runtime API */
  private nk: any;

  /** Logger instance */
  private logger: any;

  /** Tick interval handle (for stopping) */
  private tickIntervalId: any = null;

  /** Last checkpoint timestamp */
  private lastCheckpointTime: number = 0;

  /** Pending events for logging (accumulated during tick) */
  private pendingEvents: ZoneEvent[] = [];

  /** Zone running state */
  private isRunning: boolean = false;

  /** Tick counter for diagnostics */
  private tickCount: number = 0;

  /** Last tick timestamp */
  private lastTickTime: number = 0;

  /** Match ID for delta streaming (Task 2.3.1) */
  private matchId: string | null = null;

  /** Player positions for AOI filtering (Task 2.3.2) */
  private playerPositions: Map<string, Position> = new Map();

  /** Player AOI tracking (Task 2.3.2) - stores entity IDs in each player's AOI */
  private playerAOIs: Map<string, Set<string>> = new Map();

  /** Spatial grid for AOI optimization (Task 2.3.2) */
  private spatialGrid: SpatialGrid | null = null;

  /** AOI radius in meters (Task 2.3.2) */
  private aoiRadius: number = 50; // Default 50 units

  /**
   * Create a new ZoneProcess
   *
   * @param nk - Nakama module API
   * @param logger - Logger instance
   * @param config - Zone configuration
   * @param initialState - Initial zone state (from database or default)
   */
  constructor(
    nk: any,
    logger: any,
    config: ZoneProcessConfig,
    initialState: ZoneState
  ) {
    this.nk = nk;
    this.logger = logger;
    this.config = config;
    this.state = initialState;

    // Task 2.3.1: Initialize previous state for delta generation
    this.previousState = JSON.parse(JSON.stringify(initialState)); // Deep copy

    // Task 2.3.2: Initialize spatial grid for AOI optimization
    this.spatialGrid = new SpatialGrid(this.aoiRadius);

    // Task 2.3.2: Populate spatial grid with initial entities
    for (const entity of initialState.entities) {
      this.spatialGrid.insert(entity.entityId, entity.transform.position);
    }

    this.logger.info('[ZoneProcess] Created for zone %s (shard: %s, tick rate: %d Hz, AOI: %d m)',
      config.zoneId, config.shardId, config.tickRate, this.aoiRadius);
  }

  /**
   * Start the zone process
   *
   * This begins the main game loop for this zone at the configured tick rate.
   * The loop runs until stop() is called.
   *
   * Task 2.2.1: Implement tick loop at 10-20 Hz
   * Task 2.2.5: Restore zone state from checkpoint on startup
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      this.logger.warn('[ZoneProcess] Zone %s already running', this.config.zoneId);
      return;
    }

    // Task 2.2.5: Restore zone state from checkpoint + event log
    // Requirement 7: Load zone state from last checkpoint on startup
    try {
      await this.restore();
    } catch (err: any) {
      this.logger.error('[ZoneProcess] Failed to restore zone %s: %s',
        this.config.zoneId, err.message);
      throw new Error(`Zone restore failed: ${err.message}`);
    }

    this.isRunning = true;
    this.lastTickTime = Date.now();
    this.lastCheckpointTime = Date.now();
    this.tickCount = 0;

    const tickIntervalMs = 1000 / this.config.tickRate;

    this.logger.info('[ZoneProcess] Starting zone %s tick loop at %d Hz (%d ms interval)',
      this.config.zoneId, this.config.tickRate, tickIntervalMs);

    // Start tick loop
    // Note: In production, this would use Nakama's scheduler or a more precise timer
    // For now, using setInterval as placeholder
    this.tickIntervalId = setInterval(() => {
      this.executeTick();
    }, tickIntervalMs);

    this.logger.info('[ZoneProcess] Zone %s started successfully', this.config.zoneId);
  }  /**
   * Stop the zone process
   *
   * Performs a clean shutdown:
   * - Stops the tick loop
   * - Flushes pending events
   * - Saves final checkpoint (Task 2.2.2)
   * - Requirement 7: Safe shutdown
   */
  async stop(): Promise<void> {
    if (!this.isRunning) {
      this.logger.warn('[ZoneProcess] Zone %s not running', this.config.zoneId);
      return;
    }

    this.logger.info('[ZoneProcess] Stopping zone %s (total ticks: %d)',
      this.config.zoneId, this.tickCount);

    // Stop tick loop
    if (this.tickIntervalId) {
      clearInterval(this.tickIntervalId);
      this.tickIntervalId = null;
    }

    this.isRunning = false;

    // Task 2.2.3: Flush pending events before shutdown
    // Requirement 7: Flush all events to prevent data loss
    if (this.pendingEvents.length > 0) {
      try {
        this.logger.info('[ZoneProcess] Flushing %d pending events before shutdown',
          this.pendingEvents.length);
        await this.flushEvents();
      } catch (err: any) {
        this.logger.error('[ZoneProcess] Failed to flush events during shutdown: %s', err.message);
      }
    }

    // Task 2.2.2: Save final checkpoint on safe shutdown
    // Requirement 7: Safe shutdown SHALL persist final checkpoint
    try {
      this.logger.info('[ZoneProcess] Saving final checkpoint (version %d)', this.state.version);
      await this.saveCheckpoint();
      this.logger.info('[ZoneProcess] Zone %s stopped successfully with final checkpoint',
        this.config.zoneId);
    } catch (err: any) {
      this.logger.error('[ZoneProcess] Final checkpoint failed for zone %s: %s',
        this.config.zoneId, err.message);
    }
  }

  /**
   * Execute a single tick
   *
   * This is the main game loop iteration. Each tick:
   * 1. Calculates delta time since last tick
   * 2. Updates entities (movement, AI, timers)
   * 3. Logs state-changing events
   * 4. Triggers checkpoint if interval elapsed
   *
   * Performance target: ≤10ms p95
   */
  private executeTick(): void {
    const tickStartTime = Date.now();
    const deltaMs = tickStartTime - this.lastTickTime;
    this.lastTickTime = tickStartTime;
    this.tickCount++;

    // Update zone time
    this.state.zoneTime = tickStartTime;

    // TODO: Update entities, NPC AI, resource nodes
    // This will be implemented in later tasks (Phase 3: Movement & Combat)
    // For now, just manage the tick loop infrastructure
    this.updateEntities(deltaMs);

    // Task 2.3.1: Generate and broadcast zone delta
    if (this.matchId) {
      this.broadcastDelta(tickStartTime);
    }

    // Task 2.2.3: Flush pending events to event_log table
    if (this.pendingEvents.length > 0) {
      this.flushEvents().catch(err => {
        this.logger.error('[ZoneProcess] Event flush failed for zone %s: %s',
          this.config.zoneId, err);
      });
    }

    // Task 2.2.2: Checkpoint if interval elapsed
    if (tickStartTime - this.lastCheckpointTime > this.config.checkpointIntervalMs) {
      this.saveCheckpoint().catch(err => {
        this.logger.error('[ZoneProcess] Checkpoint failed for zone %s: %s',
          this.config.zoneId, err);
      });
      this.lastCheckpointTime = tickStartTime;
    }

    // Performance monitoring
    const tickDuration = Date.now() - tickStartTime;
    if (tickDuration > this.config.tickBudgetMs) {
      this.logger.warn('[ZoneProcess] Tick %d exceeded budget: %d ms > %d ms',
        this.tickCount, tickDuration, this.config.tickBudgetMs);
    }

    // Periodic diagnostics (every 100 ticks = ~5 seconds at 20 Hz)
    if (this.tickCount % 100 === 0) {
      this.logger.debug('[ZoneProcess] Zone %s tick %d: %d entities, %d ms',
        this.config.zoneId, this.tickCount, this.state.entities.length, tickDuration);
    }
  }

  /**
   * Update all entities in the zone
   *
   * Task 2.3.2: Update spatial grid when entities move
   *
   * Placeholder for entity update logic.
   * Will be implemented in Phase 3 tasks:
   * - Task 3.1: Movement system
   * - Task 3.2: Combat system
   * - Task 3.3: NPC AI
   * - Task 3.4: Resource nodes
   *
   * @param deltaMs - Time since last tick in milliseconds
   */
  private updateEntities(deltaMs: number): void {
    // Placeholder: Update entity logic
    // For now, just increment zone time

    // Task 2.3.2: Update spatial grid when entities move
    // This will be called in Phase 3 when actual entity movement is implemented
    // Example of what will be implemented later:
    // for (const entity of this.state.entities) {
    //   // Update entity position based on movement
    //   // ...
    //   // Update spatial grid with new position
    //   if (this.spatialGrid) {
    //     this.spatialGrid.update(entity.entityId, entity.transform.position);
    //   }
    // }
    //   if (entity.type === 'npc') {
    //     this.updateNpcAI(entity, deltaMs);
    //   } else if (entity.type === 'player') {
    //     this.updatePlayerMovement(entity, deltaMs);
    //   }
    // }
  }

  /**
   * Broadcast zone delta to players
   * Task 2.3.1: Delta broadcasting
   * Task 2.3.2: Per-player AOI filtering
   * Task 2.3.3: Entity add/remove messages
   *
   * Generates and broadcasts zone state delta to all connected players.
   * Filters delta per-player based on AOI (Requirement 8).
   * Sends full EntitySnapshot when entity enters AOI (Requirement 8).
   * Sends entity ID only when entity exits AOI (Requirement 8).
   *
   * @param timestamp - Current tick timestamp
   */
  private broadcastDelta(timestamp: number): void {
    try {
      // Generate full zone delta from state changes
      const delta = generateZoneDelta(this.state, this.previousState, timestamp);

      // Only broadcast if there are changes
      if (delta.entityUpdates.length > 0 ||
          delta.entityAdds.length > 0 ||
          delta.entityRemoves.length > 0) {

        // Task 2.3.2: Per-player AOI filtering
        // Task 2.3.3: Send full snapshots for entities entering AOI
        // Instead of broadcasting to all, filter delta for each player's AOI
        if (this.playerPositions.size > 0) {
          for (const [playerId, playerPos] of this.playerPositions.entries()) {
            // Get player's previous AOI set
            const previousAOI = this.playerAOIs.get(playerId) || new Set<string>();

            // Filter delta by player's AOI
            // Task 2.3.3: Pass current state so filterDeltaByAOI can construct full snapshots
            const filteredDelta = filterDeltaByAOI(delta, playerPos, this.aoiRadius, previousAOI, this.state);

            // Only send if there are relevant changes for this player
            if (filteredDelta.entityUpdates.length > 0 ||
                filteredDelta.entityAdds.length > 0 ||
                filteredDelta.entityRemoves.length > 0) {

              // Broadcast filtered delta to this specific player
              // Note: This requires per-player message send (implement in future task)
              // For now, broadcast to match (will be optimized in production)
              broadcastDeltaToMatch(this.nk, this.logger, this.matchId!, filteredDelta);

              // Update player's AOI set for next tick
              const currentAOI = new Set<string>();
              for (const update of filteredDelta.entityUpdates) {
                currentAOI.add(update.entityId);
              }
              for (const add of filteredDelta.entityAdds) {
                currentAOI.add(add.entityId);
              }
              this.playerAOIs.set(playerId, currentAOI);
            }
          }
        } else {
          // No players in zone - skip broadcast (optimization)
          // Requirement 8: Only send deltas when players present
        }
      }

      // Update previous state for next delta
      // Deep copy to preserve snapshot
      this.previousState = JSON.parse(JSON.stringify(this.state));

    } catch (err: any) {
      this.logger.error('[ZoneProcess] Delta broadcast failed for zone %s: %s',
        this.config.zoneId, err.message);
    }
  }  /**
   * Get current zone state (read-only snapshot)
   *
   * Used by snapshot.ts for zone_snapshot RPC
   * Task 2.1.3 integration point
   *
   * @returns Current zone state
   */
  getState(): ZoneState {
    return { ...this.state }; // Return shallow copy
  }

  /**
   * Get zone ID
   */
  getZoneId(): string {
    return this.config.zoneId;
  }

  /**
   * Check if zone is running
   */
  isActive(): boolean {
    return this.isRunning;
  }

  /**
   * Set match ID for delta streaming
   * Task 2.3.1: Delta streaming integration
   *
   * @param matchId - Match ID for zone
   */
  setMatchId(matchId: string): void {
    this.matchId = matchId;
    this.logger.info('[ZoneProcess] Match ID set for zone %s: %s', this.config.zoneId, matchId);
  }

  /**
   * Update player position for AOI tracking
   * Task 2.3.2: Player position tracking
   *
   * Called when player moves or enters zone.
   * Updates spatial grid and player AOI tracking.
   *
   * @param playerId - Player identifier
   * @param position - Player's new position
   */
  updatePlayerPosition(playerId: string, position: Position): void {
    this.playerPositions.set(playerId, position);

    this.logger.debug('[ZoneProcess] Updated player %s position in zone %s: (%f, %f, %f)',
      playerId, this.config.zoneId, position.x, position.y, position.z || 0);
  }

  /**
   * Remove player from zone tracking
   * Task 2.3.2: Player cleanup
   *
   * Called when player leaves zone.
   * Removes from position tracking and AOI sets.
   *
   * @param playerId - Player identifier
   */
  removePlayer(playerId: string): void {
    this.playerPositions.delete(playerId);
    this.playerAOIs.delete(playerId);

    this.logger.info('[ZoneProcess] Removed player %s from zone %s',
      playerId, this.config.zoneId);
  }

  /**
   * Get player count in zone
   * Task 2.3.2: Diagnostics
   *
   * @returns Number of players currently in zone
   */
  getPlayerCount(): number {
    return this.playerPositions.size;
  }

  /**
   * Add an event to the pending event log
   * Task 2.2.3: Event logging for crash recovery
   *
   * Events are accumulated in memory during the tick and flushed
   * to the database asynchronously to avoid blocking the tick loop.
   * Design: design.md lines 1290-1295
   *
   * @param eventType - Event type identifier
   * @param eventData - Event payload
   */
  private logEvent(eventType: string, eventData: any): void {
    this.pendingEvents.push({
      type: eventType,
      timestamp: Date.now(),
      data: eventData
    });
  }

  /**
   * Flush pending events to event_log table
   * Task 2.2.3: Implement event logging
   * Requirement 7: Log all state-changing events
   *
   * Writes accumulated events from this tick to the database.
   * Uses batch INSERT for performance.
   * Design: design.md lines 1290-1295
   */
  private async flushEvents(): Promise<void> {
    if (this.pendingEvents.length === 0) {
      return;
    }

    const flushStartTime = Date.now();
    const eventsToFlush = [...this.pendingEvents];
    this.pendingEvents = []; // Clear buffer immediately

    try {
      // Batch insert all events
      // Requirement 7: INSERT INTO event_log (zone_id, event_type, event_data)
      const params: any[] = [];
      const valuesClauses: string[] = [];

      eventsToFlush.forEach((event, index) => {
        const baseIndex = index * 3;
        valuesClauses.push(`($${baseIndex + 1}, $${baseIndex + 2}, $${baseIndex + 3})`);
        params.push(this.config.zoneId);
        params.push(event.type);
        params.push(JSON.stringify(event.data));
      });

      const sql = `
        INSERT INTO event_log (zone_id, event_type, event_data)
        VALUES ${valuesClauses.join(', ')}
      `;

      await this.nk.sqlExec(sql, params);

      // Performance monitoring
      const flushDuration = Date.now() - flushStartTime;
      if (flushDuration > 50) {
        this.logger.warn('[ZoneProcess] Event flush slow for zone %s: %d ms (%d events)',
          this.config.zoneId, flushDuration, eventsToFlush.length);
      }

      this.logger.debug('[ZoneProcess] Flushed %d events for zone %s in %d ms',
        eventsToFlush.length, this.config.zoneId, flushDuration);

    } catch (err: any) {
      this.logger.error('[ZoneProcess] Failed to flush events for zone %s: %s',
        this.config.zoneId, err.message);
      // Re-queue events for retry
      this.pendingEvents.unshift(...eventsToFlush);
      throw err;
    }
  }

  /**
   * Save checkpoint to database
   * Task 2.2.2: Implement checkpoint persistence
   * Requirement 7: Checkpoint every 10 seconds
   *
   * Serializes zone state to JSON and writes to world_state table.
   * Increments version number for optimistic locking.
   * Design: design.md lines 1297-1302
   */
  private async saveCheckpoint(): Promise<void> {
    const checkpointStartTime = Date.now();

    try {
      // Serialize zone state to JSON
      // Requirement 7: Checkpoints are serialized JSON
      const stateJson = JSON.stringify({
        entities: this.state.entities,
        terrain_chunks: this.state.terrainChunks,
        timers: this.state.timers,
        active_effects: this.state.activeEffects,
        zone_time: this.state.zoneTime
      });

      // Write to world_state table with version increment
      // Design.md lines 1297-1302
      const result = this.nk.sqlExec(`
        UPDATE world_state
        SET state_json = $1, version = version + 1, checkpoint_at = NOW()
        WHERE zone_id = $2
      `, [stateJson, this.config.zoneId]);

      // Update in-memory version to match database
      this.state.version++;

      const checkpointDuration = Date.now() - checkpointStartTime;

      this.logger.info('[ZoneProcess] Checkpoint saved for zone %s (version %d, %d ms, %d KB)',
        this.config.zoneId, this.state.version, checkpointDuration, stateJson.length / 1024);

      // Warn if checkpoint took too long (could block tick loop)
      if (checkpointDuration > 50) {
        this.logger.warn('[ZoneProcess] Checkpoint slow for zone %s: %d ms (target: <50ms)',
          this.config.zoneId, checkpointDuration);
      }
    } catch (error) {
      this.logger.error('[ZoneProcess] Failed to save checkpoint for zone %s: %s',
        this.config.zoneId, error);
      throw error;
    }
  }

  /**
   * Restore zone from checkpoint + event log
   * Task 2.2.4: Implement crash recovery
   * Requirement 7: RPO ≤5s, RTO ≤5min
   *
   * Loads the last checkpoint from world_state and replays events
   * from event_log since the checkpoint timestamp to restore zone state.
   * Design: design.md lines 1305-1325
   */
  private async restore(): Promise<void> {
    const restoreStartTime = Date.now();

    try {
      this.logger.info('[ZoneProcess] Starting restore for zone %s', this.config.zoneId);

      // 1. Load last checkpoint from world_state
      // Design.md lines 1307-1311
      const checkpointResult = await this.nk.sqlQuery(`
        SELECT state_json, checkpoint_at, version
        FROM world_state
        WHERE zone_id = $1
      `, [this.config.zoneId]);

      if (!checkpointResult || checkpointResult.length === 0) {
        this.logger.warn('[ZoneProcess] No checkpoint found for zone %s, initializing empty state',
          this.config.zoneId);
        // Zone has no previous state - this is expected for new zones
        return;
      }

      const checkpoint = checkpointResult[0];
      const stateJson = checkpoint.state_json;
      const checkpointTime = checkpoint.checkpoint_at;
      const checkpointVersion = checkpoint.version;

      // Parse checkpoint JSON to restore state
      const restoredState = JSON.parse(stateJson);
      this.state.entities = restoredState.entities || {};
      this.state.terrainChunks = restoredState.terrain_chunks || {};
      this.state.timers = restoredState.timers || {};
      this.state.activeEffects = restoredState.active_effects || [];
      this.state.zoneTime = restoredState.zone_time || Date.now();
      this.state.version = checkpointVersion;

      this.logger.info('[ZoneProcess] Loaded checkpoint for zone %s (version %d, checkpoint_at %s)',
        this.config.zoneId, checkpointVersion, checkpointTime);

      // 2. Replay events from event_log since checkpoint timestamp
      // Design.md lines 1318-1323
      const eventsResult = await this.nk.sqlQuery(`
        SELECT event_type, event_data, timestamp
        FROM event_log
        WHERE zone_id = $1 AND timestamp > $2
        ORDER BY event_id ASC
      `, [this.config.zoneId, checkpointTime]);

      if (eventsResult && eventsResult.length > 0) {
        this.logger.info('[ZoneProcess] Replaying %d events since checkpoint for zone %s',
          eventsResult.length, this.config.zoneId);

        for (const eventRow of eventsResult) {
          const eventType = eventRow.event_type;
          const eventData = JSON.parse(eventRow.event_data);

          try {
            this.applyEvent(eventType, eventData);
          } catch (err: any) {
            this.logger.error('[ZoneProcess] Failed to apply event %s for zone %s: %s',
              eventType, this.config.zoneId, err.message);
            // Continue with remaining events - partial recovery better than none
          }
        }

        this.logger.info('[ZoneProcess] Event replay completed for zone %s (%d events)',
          this.config.zoneId, eventsResult.length);
      } else {
        this.logger.info('[ZoneProcess] No events to replay for zone %s', this.config.zoneId);
      }

      // 3. Verify state consistency
      const restoreDuration = Date.now() - restoreStartTime;
      this.logger.info('[ZoneProcess] Restore completed for zone %s (version %d, %d ms, %d entities)',
        this.config.zoneId, this.state.version, restoreDuration, Object.keys(this.state.entities).length);

      // Warn if restore took too long (RTO target is ≤5min, but should be much faster)
      if (restoreDuration > 5000) {
        this.logger.warn('[ZoneProcess] Restore slow for zone %s: %d ms (target: <5000ms)',
          this.config.zoneId, restoreDuration);
      }

    } catch (err: any) {
      this.logger.error('[ZoneProcess] Restore failed for zone %s: %s',
        this.config.zoneId, err.message);
      throw err;
    }
  }

  /**
   * Apply event to zone state during replay
   * Task 2.2.4: Event replay helper
   *
   * Mutates zone state according to event type and data.
   * Design: design.md lines 1323-1325
   *
   * @param eventType - Event type identifier
   * @param eventData - Event payload
   */
  private applyEvent(eventType: string, eventData: any): void {
    switch (eventType) {
      case 'entity_move':
        // Update entity position
        if (eventData.entity_id && this.state.entities[eventData.entity_id]) {
          const entity = this.state.entities[eventData.entity_id] as any;
          if (eventData.position) {
            entity.transform.position = eventData.position;
          }
        }
        break;

      case 'entity_spawn':
        // Add new entity to state
        if (eventData.entity_id) {
          (this.state.entities as any)[eventData.entity_id] = {
            entityId: eventData.entity_id,
            type: eventData.entity_type || 'unknown',
            transform: {
              position: eventData.position || { x: 0, y: 0, z: 0 },
              rotation: { x: 0, y: 0, z: 0 }
            },
            vitals: {
              health: eventData.health || 100,
              maxHealth: eventData.max_health || 100
            },
            state: eventData.state || {}
          };
        }
        break;

      case 'entity_despawn':
        // Remove entity from state
        if (eventData.entity_id && this.state.entities[eventData.entity_id]) {
          delete (this.state.entities as any)[eventData.entity_id];
        }
        break;

      case 'loot_drop':
        // Add loot as entity (Phase 3 will implement proper loot system)
        if (eventData.item_id && eventData.position) {
          const lootEntityId = `loot_${eventData.item_id}`;
          (this.state.entities as any)[lootEntityId] = {
            entityId: lootEntityId,
            type: 'loot',
            transform: {
              position: eventData.position,
              rotation: { x: 0, y: 0, z: 0 }
            },
            vitals: {
              health: 1,
              maxHealth: 1
            },
            state: { item_id: eventData.item_id }
          };
        }
        break;

      default:
        this.logger.warn('[ZoneProcess] Unknown event type during replay: %s', eventType);
        // Don't throw - continue with remaining events
        break;
    }
  }
}

/**
 * Create default zone process configuration
 *
 * @param zoneId - Zone identifier
 * @param shardId - Shard identifier
 * @returns Default configuration with performance targets from design.md
 */
function createDefaultConfig(zoneId: string, shardId: string): ZoneProcessConfig {
  return {
    zoneId: zoneId,
    shardId: shardId,
    tickRate: 20, // 20 Hz as per design.md performance targets
    tickBudgetMs: 10, // ≤10ms p95 target
    checkpointIntervalMs: 10000 // 10 seconds
  };
}

// Export for use by other modules
export { ZoneProcess, ZoneProcessConfig, ZoneEvent, createDefaultConfig };
