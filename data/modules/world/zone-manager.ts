/**
 * Zone Manager
 *
 * Manages lifecycle of ZoneProcess instances and their associated matches.
 * Starts zone processes when players enter, stops them when empty.
 * Creates Nakama matches for delta streaming.
 *
 * Task: 2.3.1 (Delta Streaming via Matches)
 * Requirements: 7 (Persistent Zone State), 8 (AOI Management)
 */

import { ZoneState } from './types';

/**
 * Active zone tracking
 */
interface ActiveZone {
  /** Zone identifier */
  zoneId: string;

  /** Nakama match ID for delta streaming */
  matchId: string;

  /** Number of active players */
  playerCount: number;

  /** Zone process instance (placeholder - will be ZoneProcess class instance) */
  process: any;

  /** When zone was started */
  startedAt: number;
}

/**
 * Global zone registry
 * Maps zone_id -> ActiveZone
 */
const activeZones: Map<string, ActiveZone> = new Map();

/**
 * Start a zone process if not already running
 * Creates a Nakama match for delta streaming
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param zoneId - Zone identifier
 * @returns Match ID for delta streaming
 */
export function ensureZoneRunning(nk: any, logger: any, zoneId: string): string {
  let activeZone = activeZones.get(zoneId);

  if (activeZone) {
    logger.debug('[ZoneManager] Zone %s already running (match %s, %d players)',
      zoneId, activeZone.matchId, activeZone.playerCount);
    return activeZone.matchId;
  }

  logger.info('[ZoneManager] Starting zone %s', zoneId);

  // Create a Nakama match for this zone (for delta streaming)
  // Match module name must match a registered match handler (or use simple relayed match)
  const matchId = nk.matchCreate('zone_match', { zoneId });

  logger.info('[ZoneManager] Created match %s for zone %s', matchId, zoneId);

  // TODO: Create and start ZoneProcess instance
  // For now, we'll use a placeholder
  const process = null; // Will be: new ZoneProcess(config, nk, logger)

  activeZone = {
    zoneId,
    matchId,
    playerCount: 0,
    process,
    startedAt: Date.now()
  };

  activeZones.set(zoneId, activeZone);

  logger.info('[ZoneManager] Zone %s started successfully (match %s)', zoneId, matchId);

  return matchId;
}

/**
 * Register a player joining a zone
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param zoneId - Zone identifier
 * @param userId - Player user ID
 * @param sessionId - Player session ID
 * @returns Match ID for client to join
 */
export function registerPlayerJoin(
  nk: any,
  logger: any,
  zoneId: string,
  userId: string,
  sessionId: string
): string {
  const matchId = ensureZoneRunning(nk, logger, zoneId);
  const activeZone = activeZones.get(zoneId)!;

  activeZone.playerCount++;

  logger.info('[ZoneManager] Player %s joined zone %s (match %s, now %d players)',
    userId, zoneId, matchId, activeZone.playerCount);

  return matchId;
}

/**
 * Register a player leaving a zone
 *
 * @param nk - Nakama module API
 * @param logger - Logger instance
 * @param zoneId - Zone identifier
 * @param userId - Player user ID
 */
export function registerPlayerLeave(
  nk: any,
  logger: any,
  zoneId: string,
  userId: string
): void {
  const activeZone = activeZones.get(zoneId);

  if (!activeZone) {
    logger.warn('[ZoneManager] Player %s left zone %s but zone not active', userId, zoneId);
    return;
  }

  activeZone.playerCount = Math.max(0, activeZone.playerCount - 1);

  logger.info('[ZoneManager] Player %s left zone %s (match %s, now %d players)',
    userId, zoneId, activeZone.matchId, activeZone.playerCount);

  // Shutdown zone if empty (with grace period)
  if (activeZone.playerCount === 0) {
    logger.info('[ZoneManager] Zone %s is empty, scheduling shutdown in 60s', zoneId);

    // Delayed shutdown to avoid thrashing if player reconnects
    // TODO: Use nk.runOnce or setTimeout equivalent
    // For now, keep zone running (will be garbage collected eventually)
  }
}

/**
 * Get match ID for a zone (if running)
 *
 * @param zoneId - Zone identifier
 * @returns Match ID or null if zone not active
 */
export function getZoneMatchId(zoneId: string): string | null {
  const activeZone = activeZones.get(zoneId);
  return activeZone ? activeZone.matchId : null;
}

/**
 * Get statistics for all active zones
 *
 * @returns Array of zone statistics
 */
export function getActiveZones(): Array<{ zoneId: string; matchId: string; playerCount: number; uptime: number }> {
  const now = Date.now();
  const result: Array<{ zoneId: string; matchId: string; playerCount: number; uptime: number }> = [];

  for (const [zoneId, zone] of activeZones.entries()) {
    result.push({
      zoneId,
      matchId: zone.matchId,
      playerCount: zone.playerCount,
      uptime: now - zone.startedAt
    });
  }

  return result;
}
