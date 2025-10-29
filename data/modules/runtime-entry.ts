/**
 * Nakama MMORPG Runtime - Combined Entry Point
 *
 * This file imports all RPC functions from separate modules and registers them.
 * TypeScript imports will be bundled into one file by our build script.
 */

// Import character module RPCs
import {
  rpcListCharacters,
  rpcCreateCharacter,
  rpcSelectCharacter,
  rpcDeleteCharacter
} from './character/character';

// Import world module RPCs
import { rpcWorldEnter } from './world/enter';
import { rpcMoveIntent } from './world/movement';
import { rpcZoneSnapshot } from './world/snapshot';

// Import combat module RPCs
import { rpcUseAbility } from './combat/use_ability';

// Import economy module RPCs
import { rpcInventoryMove, rpcInventoryCreateItem } from './economy/inventory';
import { rpcTradeOpen, rpcTradeAddItem, rpcTradeLock, rpcTradeCommit, rpcTradeCancel } from './economy/trading';

// Import social module RPCs
import {
  rpcChatSend,
  rpcSendDirectMessage,
  rpcModeratePlayer
} from './social/chat';
import {
  rpcGuildCreate,
  rpcGuildInvite,
  rpcGuildJoin,
  rpcGuildSetRank,
  rpcGuildKick,
  rpcGuildSetMotd,
  rpcGuildStorageDeposit,
  rpcGuildStorageWithdraw
} from './social/guild';

/**
 * Main initialization function called by Nakama runtime
 */
function InitModule(
  ctx: any,
  logger: any,
  nk: any,
  initializer: any
): void {
  logger.info('=== Nakama MMORPG Runtime Initializing ===');

  // Register character service RPCs
  logger.info('Registering character service RPCs...');
  initializer.registerRpc('list_characters', rpcListCharacters);
  initializer.registerRpc('create_character', rpcCreateCharacter);
  initializer.registerRpc('select_character', rpcSelectCharacter);
  initializer.registerRpc('delete_character', rpcDeleteCharacter);
  logger.info('Character service RPCs registered');

  // Register world entry RPCs
  logger.info('Registering world entry RPCs...');
  initializer.registerRpc('world_enter', rpcWorldEnter);
  logger.info('World entry RPCs registered');

  // Register world movement RPCs
  logger.info('Registering world movement RPCs...');
  initializer.registerRpc('move_intent', rpcMoveIntent);
  logger.info('World movement RPCs registered');

  // Register world snapshot RPCs
  logger.info('Registering world snapshot RPCs...');
  initializer.registerRpc('zone_snapshot', rpcZoneSnapshot);
  logger.info('World snapshot RPCs registered');

  // Register combat RPCs
  logger.info('Registering combat RPCs...');
  initializer.registerRpc('use_ability', rpcUseAbility);
  logger.info('Combat RPCs registered');

  // Register economy RPCs
  logger.info('Registering economy RPCs...');
  initializer.registerRpc('inventory_move', rpcInventoryMove);
  initializer.registerRpc('inventory_create_item', rpcInventoryCreateItem);
  initializer.registerRpc('trade_open', rpcTradeOpen);
  initializer.registerRpc('trade_add_item', rpcTradeAddItem);
  initializer.registerRpc('trade_lock', rpcTradeLock);
  initializer.registerRpc('trade_commit', rpcTradeCommit);
  initializer.registerRpc('trade_cancel', rpcTradeCancel);
  logger.info('Economy RPCs registered');

  // Register social chat RPCs
  logger.info('Registering social chat RPCs...');
  initializer.registerRpc('chat_send', rpcChatSend);
  initializer.registerRpc('send_direct_message', rpcSendDirectMessage);
  initializer.registerRpc('moderate_player', rpcModeratePlayer);
  logger.info('Social chat RPCs registered');

  // Register social guild RPCs
  logger.info('Registering social guild RPCs...');
  initializer.registerRpc('guild_create', rpcGuildCreate);
  initializer.registerRpc('guild_invite', rpcGuildInvite);
  initializer.registerRpc('guild_join', rpcGuildJoin);
  initializer.registerRpc('guild_set_rank', rpcGuildSetRank);
  initializer.registerRpc('guild_kick', rpcGuildKick);
  initializer.registerRpc('guild_set_motd', rpcGuildSetMotd);
  initializer.registerRpc('guild_storage_deposit', rpcGuildStorageDeposit);
  initializer.registerRpc('guild_storage_withdraw', rpcGuildStorageWithdraw);
  logger.info('Social guild RPCs registered');

  logger.info('=== Runtime Initialization Complete ===');
  logger.info('Total RPCs registered: 24');
}

// Expose InitModule globally for Nakama to find it
// @ts-ignore
globalThis.InitModule = InitModule;
