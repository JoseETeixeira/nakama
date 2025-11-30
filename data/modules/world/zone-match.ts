/**
 * Zone Match Handler
 *
 * Match handler for zone delta streaming with real-time entity updates.
 * Players join this match when entering a zone to receive delta updates.
 *
 * Task: 2.3.1 (Delta Streaming via Matches)
 * Requirements: 8 (AOI Management and Delta Streaming)
 */

import { EntitySnapshot, Position, Transform, Vitals } from './types';

/**
 * Match state structure
 */
interface MatchState {
  zoneId: string;
  players: Record<string, PlayerState>;
  entities: Record<string, EntitySnapshot>;
  previousEntities: Record<string, EntitySnapshot>;
  createdAt: number;
  version: number;
}

/**
 * Player state in match
 */
interface PlayerState {
  userId: string;
  sessionId: string;
  entityId: string;
  joinedAt: number;
  lastUpdate: number;
}

/**
 * Match initialization
 * Called when a new zone match is created
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param params - Match creation parameters (contains zoneId)
 * @returns Match state
 */
export function matchInit(
  ctx: any,
  logger: any,
  nk: any,
  params: { zoneId: string }
): { state: MatchState; tickRate: number; label: string } {
  const zoneId = params.zoneId;

  logger.info('[ZoneMatch] Initializing zone match for %s', zoneId);

  return {
    state: {
      zoneId,
      players: {},
      entities: {},
      previousEntities: {},
      createdAt: Date.now(),
      version: 0
    },
    tickRate: 20, // 20 Hz for delta streaming
    label: JSON.stringify({ zoneId })
  };
}

/**
 * Match join attempt
 * Called when a player tries to join the match
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param dispatcher - Match dispatcher
 * @param tick - Current match tick
 * @param state - Match state
 * @param presences - Joining presences
 * @returns Updated match state and allow/reject decision
 */
export function matchJoinAttempt(
  ctx: any,
  logger: any,
  nk: any,
  dispatcher: any,
  tick: number,
  state: MatchState,
  presences: any[]
): { state: MatchState; accept: boolean } | null {
  // Allow all joins (can add validation here later)
  return {
    state,
    accept: true
  };
}

/**
 * Match join
 * Called when a player successfully joins the match
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param dispatcher - Match dispatcher
 * @param tick - Current match tick
 * @param state - Match state
 * @param presences - Joined presences
 * @returns Updated match state
 */
export function matchJoin(
  ctx: any,
  logger: any,
  nk: any,
  dispatcher: any,
  tick: number,
  state: MatchState,
  presences: any[]
): { state: MatchState } | null {
  try {
    for (const presence of presences) {
      const entityId = `player_${presence.userId}`;
      
      state.players[presence.userId] = {
        userId: presence.userId,
        sessionId: presence.sessionId,
        entityId: entityId,
        joinedAt: Date.now(),
        lastUpdate: Date.now()
      };

      // Create an initial entity for this player
      // Position will be updated via movement RPCs
      state.entities[entityId] = {
        entityId: entityId,
        type: 'player',
        transform: {
          position: { x: 0, y: 0, z: 0 },
          rotation: { x: 0, y: 0, z: 0 }
        },
        vitals: {
          health: 100,
          maxHealth: 100,
          mana: 100,
          maxMana: 100
        },
        state: {
          userId: presence.userId,
          username: presence.username
        }
      };

      const playerCount = Object.keys(state.players).length;
      logger.info('[ZoneMatch] Player %s joined zone %s (now %d players)',
        presence.userId, state.zoneId, playerCount);
    }

    return { state };
  } catch (error) {
    logger.error('[ZoneMatch] Error in matchJoin: %s', error);
    return { state };
  }
}

/**
 * Match leave
 * Called when a player leaves the match
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param dispatcher - Match dispatcher
 * @param tick - Current match tick
 * @param state - Match state
 * @param presences - Left presences
 * @returns Updated match state
 */
export function matchLeave(
  ctx: any,
  logger: any,
  nk: any,
  dispatcher: any,
  tick: number,
  state: MatchState,
  presences: any[]
): { state: MatchState } | null {
  try {
    for (const presence of presences) {
      const playerState = state.players[presence.userId];
      if (playerState) {
        // Remove player's entity
        delete state.entities[playerState.entityId];
        delete state.players[presence.userId];
      }
      
      const playerCount = Object.keys(state.players).length;
      logger.info('[ZoneMatch] Player %s left zone %s (now %d players)',
        presence.userId, state.zoneId, playerCount);
    }

    return { state };
  } catch (error) {
    logger.error('[ZoneMatch] Error in matchLeave: %s', error);
    return { state };
  }
}

/**
 * Match loop
 * Called every tick to update match state and broadcast deltas
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param dispatcher - Match dispatcher
 * @param tick - Current match tick
 * @param state - Match state
 * @param messages - Messages received this tick
 * @returns Updated match state
 */
export function matchLoop(
  ctx: any,
  logger: any,
  nk: any,
  dispatcher: any,
  tick: number,
  state: MatchState,
  messages: any[]
): { state: MatchState } | null {
  try {
    // Process incoming messages (movement updates, etc.)
    for (const message of messages) {
      try {
        const payload = JSON.parse(nk.binaryToString(message.data));
        const playerState = state.players[message.sender.userId];
        
        if (playerState && payload.position) {
          // Update player entity position
          const entity = state.entities[playerState.entityId];
          if (entity) {
            entity.transform.position.x = payload.position.x;
            entity.transform.position.y = payload.position.y;
            if (payload.position.z !== undefined) {
              entity.transform.position.z = payload.position.z;
            }
            playerState.lastUpdate = Date.now();
          }
        }
      } catch (e) {
        // Ignore malformed messages
        logger.warn('[ZoneMatch] Malformed message from %s', message.sender.userId);
      }
    }

    // Generate and broadcast delta every tick
    if (Object.keys(state.players).length > 0) {
      const delta = generateDelta(state, tick);
      
      // Only broadcast if there are changes
      if (delta.entityUpdates.length > 0 || delta.entityAdds.length > 0 || delta.entityRemoves.length > 0) {
        broadcastDelta(dispatcher, state, delta, logger);
      }
      
      // Update previous state for next delta
      state.previousEntities = JSON.parse(JSON.stringify(state.entities));
      state.version++;
    }

    return { state };
  } catch (error) {
    logger.error('[ZoneMatch] Error in matchLoop: %s', error);
    return { state };
  }
}

/**
 * Generate delta from state changes
 */
function generateDelta(state: MatchState, tick: number): any {
  const delta = {
    timestamp: Date.now(),
    version: state.version,
    tick: tick,
    entityUpdates: [] as any[],
    entityAdds: [] as any[],
    entityRemoves: [] as string[]
  };

  const currentIds = Object.keys(state.entities);
  const previousIds = Object.keys(state.previousEntities);

  // Find new entities
  for (const entityId of currentIds) {
    if (!previousIds.includes(entityId)) {
      delta.entityAdds.push(state.entities[entityId]);
    }
  }

  // Find removed entities
  for (const entityId of previousIds) {
    if (!currentIds.includes(entityId)) {
      delta.entityRemoves.push(entityId);
    }
  }

  // Find updated entities
  for (const entityId of currentIds) {
    if (previousIds.includes(entityId)) {
      const current = state.entities[entityId];
      const previous = state.previousEntities[entityId];
      
      const update: any = { entityId };
      let hasChanges = false;

      // Check position changes
      if (current.transform.position.x !== previous.transform.position.x) {
        update.position = current.transform.position;
        hasChanges = true;
      } else if (current.transform.position.y !== previous.transform.position.y) {
        update.position = current.transform.position;
        hasChanges = true;
      } else if (current.transform.position.z !== previous.transform.position.z) {
        update.position = current.transform.position;
        hasChanges = true;
      }

      // Check vitals changes
      if (current.vitals.health !== previous.vitals.health ||
          current.vitals.maxHealth !== previous.vitals.maxHealth) {
        update.health = current.vitals.health;
        update.maxHealth = current.vitals.maxHealth;
        hasChanges = true;
      }

      if (hasChanges) {
        delta.entityUpdates.push(update);
      }
    }
  }

  return delta;
}

/**
 * Broadcast delta to all players in match
 */
function broadcastDelta(dispatcher: any, state: MatchState, delta: any, logger: any): void {
  try {
    const OP_CODE_ZONE_DELTA = 1;
    const deltaJson = JSON.stringify(delta);
    
    // Broadcast to all presences in the match
    dispatcher.broadcastMessage(OP_CODE_ZONE_DELTA, deltaJson);
    
    logger.debug('[ZoneMatch] Broadcast delta v%d: %d updates, %d adds, %d removes',
      delta.version, delta.entityUpdates.length, delta.entityAdds.length, delta.entityRemoves.length);
  } catch (error) {
    logger.error('[ZoneMatch] Failed to broadcast delta: %s', error);
  }
}

/**
 * Match terminate
 * Called when the match is ending
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param dispatcher - Match dispatcher
 * @param tick - Current match tick
 * @param state - Match state
 * @param graceSeconds - Grace period before termination
 * @returns Updated match state
 */
export function matchTerminate(
  ctx: any,
  logger: any,
  nk: any,
  dispatcher: any,
  tick: number,
  state: MatchState,
  graceSeconds: number
): { state: MatchState } | null {
  logger.info('[ZoneMatch] Terminating zone match for %s', state.zoneId);
  return { state };
}

/**
 * Match signal
 * Called when a signal is sent to the match
 *
 * @param ctx - Match context
 * @param logger - Logger instance
 * @param nk - Nakama module API
 * @param dispatcher - Match dispatcher
 * @param tick - Current match tick
 * @param state - Match state
 * @param data - Signal data
 * @returns Updated match state
 */
export function matchSignal(
  ctx: any,
  logger: any,
  nk: any,
  dispatcher: any,
  tick: number,
  state: MatchState,
  data: string
): { state: MatchState; data?: string } | null {
  return { state };
}
