/**
 * Main Entry Point for Nakama Runtime Modules
 *
 * This file serves as the single entry point for all TypeScript runtime modules.
 * It calls each module's InitModule function to register their RPCs.
 *
 * Configured via docker-compose.yml: --runtime.js_entrypoint main.js
 *
 * Note: All modules are compiled into the same global scope, so we can't use
 * require() or import. Instead, we manually call each module's initialization.
 */

// Declare global InitModule functions from each compiled module
// These are added to the global scope when each .js file is loaded by Nakama
declare function characterInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function worldEntryInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function snapshotInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function deltaInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function movementInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function processInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function abilityConfigInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function useAbilityInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function inventoryInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function chatInitModule(ctx: any, logger: any, nk: any, initializer: any): void;
declare function guildInitModule(ctx: any, logger: any, nk: any, initializer: any): void;

/**
 * Main initialization function called by Nakama runtime
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
  logger.info('=== Nakama MMORPG Runtime Initializing ===');

  // Initialize each module subsystem
  // Note: We can't use a loop here because the functions need to be explicitly named

  try {
    logger.info('Initializing Character Service...');
    characterInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Character Service: ${e}`);
  }

  try {
    logger.info('Initializing World Entry...');
    worldEntryInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize World Entry: ${e}`);
  }

  try {
    logger.info('Initializing Zone Snapshot...');
    snapshotInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Zone Snapshot: ${e}`);
  }

  try {
    logger.info('Initializing Delta Broadcasting...');
    deltaInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Delta Broadcasting: ${e}`);
  }

  try {
    logger.info('Initializing Movement...');
    movementInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Movement: ${e}`);
  }

  try {
    logger.info('Initializing World Processing...');
    processInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize World Processing: ${e}`);
  }

  try {
    logger.info('Initializing Combat - Ability Config...');
    abilityConfigInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Ability Config: ${e}`);
  }

  try {
    logger.info('Initializing Combat - Use Ability...');
    useAbilityInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Use Ability: ${e}`);
  }

  try {
    logger.info('Initializing Economy - Inventory...');
    inventoryInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Inventory: ${e}`);
  }

  try {
    logger.info('Initializing Social - Chat...');
    chatInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Chat: ${e}`);
  }

  try {
    logger.info('Initializing Social - Guild...');
    guildInitModule(ctx, logger, nk, initializer);
  } catch (e) {
    logger.error(`Failed to initialize Guild: ${e}`);
  }

  logger.info('=== Runtime Initialization Complete ===');
}
