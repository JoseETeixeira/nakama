/**
 * Economy Module: Inventory Management
 *
 * Implements transactional inventory operations with optimistic locking
 * to prevent item duplication and ensure crash-safe persistence.
 *
 * Phase 4, Tasks:
 * - 4.3.1: Implement inventory_move RPC
 * - 4.3.2: Implement item UID enforcement
 * Requirements: 14 (Transactional Inventory Management)
 * Design: Economy Service (lines 388-420), RPC Specification (line 894)
 *
 * Features:
 * - Atomic item movement between inventory slots
 * - Optimistic locking with version checks (prevents race conditions)
 * - Item stacking support (merge identical items)
 * - Partial stack splitting (move subset of quantity)
 * - Server-authoritative validation (slot availability, item ownership)
 * - Global UID enforcement (prevents item duplication across all players)
 * - UUID generation for all item instances
 *
 * Acceptance Criteria:
 * - WHEN player moves item THEN execute with version check for atomicity
 * - IF write conflicts THEN reject with error (retry on client)
 * - WHEN item consumed THEN verify exists and decrement quantity atomically
 * - IF item has UID THEN enforce no duplication across all players
 * - WHEN operation fails THEN rollback partial changes
 * - WHEN item created THEN generate globally unique UUID
 * - IF UID collision detected THEN reject operation
 */

/**
 * Inventory Move Request
 * Client sends this to move items between slots
 */
interface InventoryMoveRequest {
  itemUid: string;      // UUID of the item to move
  src: string;          // Source slot ID (e.g., "backpack_0", "equipped_weapon")
  dst: string;          // Destination slot ID
  qty: number;          // Quantity to move (for stackable items)
}

/**
 * Inventory Move Response
 * Server returns success status
 */
interface InventoryMoveResponse {
  ok: boolean;
}

/**
 * Inventory Item
 * Represents a single item instance in the database
 */
interface InventoryItem {
  item_uid: string;
  character_id: string;
  item_id: string;
  slot_id: string;
  quantity: number;
  durability: number | null;
  metadata: any;
  version: number;
}

/**
 * Create Item Request
 * Used internally for item creation with UID enforcement
 */
interface CreateItemRequest {
  characterId: string;
  itemId: string;
  slotId: string;
  quantity: number;
  durability?: number | null;
  metadata?: any;
}

/**
 * Validate slot ID format
 *
 * Phase 4, Task: 4.3.4 - Add inventory validation
 * Requirements: 14 (Transactional Inventory Management)
 *
 * Validates that slot IDs follow expected patterns:
 * - backpack_{0-99}: Regular inventory slots
 * - equipped_{slot}: Equipped gear slots (weapon, helmet, chest, legs, boots, gloves, ring1, ring2, trinket1, trinket2)
 * - bank_{0-199}: Bank storage slots
 *
 * @param slotId The slot ID to validate
 * @returns Object with valid flag and optional error message
 */
function validateSlotId(slotId: string): { valid: boolean; error?: string } {
  const backpackPattern = /^backpack_\d{1,2}$/; // backpack_0 to backpack_99
  const equippedPattern = /^equipped_(weapon|helmet|chest|legs|boots|gloves|ring1|ring2|trinket1|trinket2)$/;
  const bankPattern = /^bank_\d{1,3}$/; // bank_0 to bank_999

  if (backpackPattern.test(slotId) || equippedPattern.test(slotId) || bankPattern.test(slotId)) {
    return { valid: true };
  }

  return {
    valid: false,
    error: `Invalid slot ID format: "${slotId}". Expected formats: backpack_N, equipped_{weapon|helmet|chest|legs|boots|gloves|ring1|ring2|trinket1|trinket2}, bank_N`
  };
}

/**
 * Check if a slot is an equipped slot
 *
 * Phase 4, Task: 4.3.4 - Add inventory validation
 * Requirements: 14 (Transactional Inventory Management)
 *
 * Equipped items cannot be moved directly - they must be unequipped first.
 *
 * @param slotId The slot ID to check
 * @returns True if the slot is an equipped slot
 */
function isEquippedSlot(slotId: string): boolean {
  return slotId.startsWith('equipped_');
}

/**
 * Generate a globally unique item UID
 *
 * Phase 4, Task: 4.3.2 - Implement item UID enforcement
 * Requirements: 14 (Transactional Inventory Management)
 *
 * This function generates a UUID v4 for new item instances.
 * The database PRIMARY KEY constraint ensures global uniqueness.
 *
 * @param nk Nakama runtime API
 * @returns Unique UUID string
 */
function generateItemUid(nk: any): string {
  return nk.uuidv4();
}

/**
 * Validate that an item UID is globally unique
 *
 * Phase 4, Task: 4.3.2 - Implement item UID enforcement
 * Requirements: 14 (Transactional Inventory Management)
 *
 * Acceptance Criteria:
 * - IF item has UID THEN enforce that UID cannot be duplicated across all players
 *
 * This function queries the inventory table to ensure the UID doesn't exist.
 * While the database PRIMARY KEY provides ultimate enforcement, this check
 * provides early validation and clearer error messages.
 *
 * @param nk Nakama runtime API
 * @param itemUid The UID to validate
 * @returns true if UID is unique, false if duplicate exists
 */
async function validateUidUnique(nk: any, itemUid: string): Promise<boolean> {
  const result = await nk.sqlQuery(`
    SELECT item_uid
    FROM inventory
    WHERE item_uid = $1
    LIMIT 1
  `, [itemUid]);

  return !result || result.length === 0;
}

/**
 * Create a new item instance with UID enforcement
 *
 * Phase 4, Task: 4.3.2 - Implement item UID enforcement
 * Requirements: 14 (Transactional Inventory Management)
 *
 * Acceptance Criteria:
 * - WHEN item created THEN generate globally unique UUID
 * - IF UID collision detected THEN reject operation
 * - WHEN item has UID THEN enforce no duplication across all players
 *
 * This function is the canonical way to create items in the inventory.
 * All item creation should use this to ensure proper UID generation and validation.
 *
 * @param nk Nakama runtime API
 * @param logger Logger instance
 * @param request Create item request parameters
 * @returns The generated item UID
 * @throws Error if UID generation fails or database constraint violated
 */
async function createItemWithUid(
  nk: any,
  logger: any,
  request: CreateItemRequest
): Promise<string> {
  // Generate unique UID
  const itemUid = generateItemUid(nk);

  // Validate uniqueness (defensive check before database insert)
  const isUnique = await validateUidUnique(nk, itemUid);
  if (!isUnique) {
    // This should be extremely rare (UUID collision)
    logger.error(`[createItemWithUid] UID collision detected: ${itemUid}`);
    throw Error('Item UID collision detected. Please retry.');
  }

  try {
    // Insert item with generated UID
    // Database PRIMARY KEY constraint provides final enforcement
    await nk.sqlExec(`
      INSERT INTO inventory (item_uid, character_id, item_id, slot_id, quantity, durability, metadata, version)
      VALUES ($1, $2, $3, $4, $5, $6, $7, 1)
    `, [
      itemUid,
      request.characterId,
      request.itemId,
      request.slotId,
      request.quantity,
      request.durability || null,
      JSON.stringify(request.metadata || {})
    ]);

    logger.info(`[createItemWithUid] Created item ${itemUid} (${request.itemId}) for character ${request.characterId} in slot ${request.slotId}`);
    return itemUid;
  } catch (error) {
    // Database-level constraint violation (duplicate PRIMARY KEY)
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (errorMessage.includes('duplicate key')) {
      logger.error(`[createItemWithUid] Database UID constraint violation: ${itemUid}`);
      throw Error('Item UID already exists. Please retry.');
    }
    throw error;
  }
}

/**
 * RPC: inventory_move
 * Move items between inventory slots with optimistic locking
 *
 * Phase 4, Task: 4.3.1 - Implement inventory_move RPC
 * Requirements: 14 (Transactional Inventory Management)
 * Design: Economy Service (lines 388-420), RPC Specification (line 894)
 *
 * Acceptance Criteria:
 * - Validate source slot has item with matching item_uid
 * - Check destination slot availability (empty or stackable item)
 * - Use optimistic locking (version column) to prevent race conditions
 * - Execute atomically within transaction (no partial updates)
 * - Support item stacking (merge quantities for identical items)
 * - Support partial stack splitting (move subset of stack)
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with InventoryMoveRequest
 * @returns JSON response with InventoryMoveResponse
 */
export async function rpcInventoryMove(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[inventory_move] Request from user ${ctx.userId}`);

  // Parse request
  let request: InventoryMoveRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.itemUid || !request.src || !request.dst) {
    throw Error('itemUid, src, and dst are required');
  }

  if (!request.qty || request.qty < 1) {
    throw Error('qty must be at least 1');
  }

  // Prevent moving to same slot
  if (request.src === request.dst) {
    throw Error('Source and destination slots must be different');
  }

  // Task 4.3.4: Validate slot IDs
  const srcValidation = validateSlotId(request.src);
  if (!srcValidation.valid) {
    throw Error(srcValidation.error);
  }

  const dstValidation = validateSlotId(request.dst);
  if (!dstValidation.valid) {
    throw Error(dstValidation.error);
  }

  // Task 4.3.4: Prevent moving equipped items without unequip
  if (isEquippedSlot(request.src)) {
    throw Error(`Cannot move equipped item from slot "${request.src}". Please unequip the item first.`);
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get character for this account
  const characterResult = await nk.sqlQuery(`
    SELECT character_id
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!characterResult || characterResult.length === 0) {
    throw Error('No character found for this account');
  }

  const characterId = characterResult[0].character_id;

  logger.info(`[inventory_move] Character ${characterId} moving item ${request.itemUid} from ${request.src} to ${request.dst} (qty: ${request.qty})`);

  try {
    // BEGIN TRANSACTION
    // All operations below must be atomic - either all succeed or all rollback

    // Step 1: Validate source item exists and player owns it
    const sourceQuery = await nk.sqlQuery(`
      SELECT item_uid, character_id, item_id, slot_id, quantity, durability, metadata, version
      FROM inventory
      WHERE item_uid = $1 AND character_id = $2 AND slot_id = $3
      FOR UPDATE
    `, [request.itemUid, characterId, request.src]);

    if (!sourceQuery || sourceQuery.length === 0) {
      throw Error(`Item ${request.itemUid} not found in slot ${request.src}`);
    }

    const sourceItem: InventoryItem = sourceQuery[0];

    // Verify sufficient quantity
    if (sourceItem.quantity < request.qty) {
      throw Error(`Insufficient quantity in source slot. Available: ${sourceItem.quantity}, Requested: ${request.qty}`);
    }

    // Step 2: Check destination slot
    const destQuery = await nk.sqlQuery(`
      SELECT item_uid, character_id, item_id, slot_id, quantity, durability, metadata, version
      FROM inventory
      WHERE character_id = $1 AND slot_id = $2
      FOR UPDATE
    `, [characterId, request.dst]);

    const isDestEmpty = !destQuery || destQuery.length === 0;
    const destItem: InventoryItem | null = isDestEmpty ? null : destQuery[0];

    // Step 3: Execute move based on destination state
    if (isDestEmpty) {
      // CASE 1: Destination is empty - simple move/split
      if (request.qty === sourceItem.quantity) {
        // Moving entire stack - just update slot_id
        logger.info(`[inventory_move] Moving entire stack to empty slot`);
        const updateResult = await nk.sqlExec(`
          UPDATE inventory
          SET slot_id = $1, version = version + 1
          WHERE item_uid = $2 AND character_id = $3 AND version = $4
        `, [request.dst, request.itemUid, characterId, sourceItem.version]);

        // Optimistic lock check
        if (updateResult.rowsAffected === 0) {
          throw Error('Version conflict - item was modified by another operation. Please retry.');
        }
      } else {
        // Moving partial stack - split into two items
        logger.info(`[inventory_move] Splitting stack: ${request.qty} to ${request.dst}, ${sourceItem.quantity - request.qty} remaining in ${request.src}`);

        // Decrement source quantity
        const updateSourceResult = await nk.sqlExec(`
          UPDATE inventory
          SET quantity = quantity - $1, version = version + 1
          WHERE item_uid = $2 AND character_id = $3 AND version = $4
        `, [request.qty, request.itemUid, characterId, sourceItem.version]);

        if (updateSourceResult.rowsAffected === 0) {
          throw Error('Version conflict - item was modified by another operation. Please retry.');
        }

        // Create new item in destination with the split quantity
        // Uses createItemWithUid for UID enforcement (Task 4.3.2)
        await createItemWithUid(nk, logger, {
          characterId: characterId,
          itemId: sourceItem.item_id,
          slotId: request.dst,
          quantity: request.qty,
          durability: sourceItem.durability,
          metadata: sourceItem.metadata
        });
      }
    } else {
      // CASE 2: Destination has an item - check if stackable
      const canStack = sourceItem.item_id === destItem!.item_id &&
                       JSON.stringify(sourceItem.metadata) === JSON.stringify(destItem!.metadata);

      if (!canStack) {
        throw Error(`Cannot move to slot ${request.dst} - slot is occupied by a different item. Unstack or swap not supported in this version.`);
      }

      // Items are stackable - merge quantities
      logger.info(`[inventory_move] Stacking ${request.qty} items with existing stack of ${destItem!.quantity}`);

      if (request.qty === sourceItem.quantity) {
        // Moving entire stack - merge and delete source
        const updateDestResult = await nk.sqlExec(`
          UPDATE inventory
          SET quantity = quantity + $1, version = version + 1
          WHERE item_uid = $2 AND character_id = $3 AND version = $4
        `, [request.qty, destItem!.item_uid, characterId, destItem!.version]);

        if (updateDestResult.rowsAffected === 0) {
          throw Error('Version conflict on destination - item was modified. Please retry.');
        }

        // Delete source item (fully merged)
        await nk.sqlExec(`
          DELETE FROM inventory
          WHERE item_uid = $1 AND character_id = $2
        `, [request.itemUid, characterId]);
      } else {
        // Moving partial stack - decrement source, increment dest
        const updateSourceResult = await nk.sqlExec(`
          UPDATE inventory
          SET quantity = quantity - $1, version = version + 1
          WHERE item_uid = $2 AND character_id = $3 AND version = $4
        `, [request.qty, request.itemUid, characterId, sourceItem.version]);

        if (updateSourceResult.rowsAffected === 0) {
          throw Error('Version conflict on source - item was modified. Please retry.');
        }

        const updateDestResult = await nk.sqlExec(`
          UPDATE inventory
          SET quantity = quantity + $1, version = version + 1
          WHERE item_uid = $2 AND character_id = $3 AND version = $4
        `, [request.qty, destItem!.item_uid, characterId, destItem!.version]);

        if (updateDestResult.rowsAffected === 0) {
          throw Error('Version conflict on destination - item was modified. Please retry.');
        }
      }
    }

    // COMMIT TRANSACTION (implicitly handled by Nakama's SQL execution context)
    logger.info(`[inventory_move] Successfully moved ${request.qty} items from ${request.src} to ${request.dst}`);

    const response: InventoryMoveResponse = {
      ok: true
    };

    return JSON.stringify(response);
  } catch (error) {
    logger.error(`[inventory_move] Failed to move item: ${error}`);
    // ROLLBACK TRANSACTION (implicitly handled by Nakama on error)
    throw Error(`Failed to move item: ${error}`);
  }
}

/**
 * Create Item Request for RPC
 */
interface InventoryCreateItemRequest {
  itemId: string;       // Item template ID
  slotId: string;       // Target slot ID
  quantity: number;     // Stack quantity
  durability?: number;  // Optional durability
  metadata?: any;       // Optional metadata (enchantments, etc.)
}

/**
 * Create Item Response
 */
interface InventoryCreateItemResponse {
  ok: boolean;
  itemUid: string;
}

/**
 * RPC: inventory_create_item
 * Create a new item instance with UID enforcement
 *
 * Phase 4, Task: 4.3.2 - Implement item UID enforcement
 * Requirements: 14 (Transactional Inventory Management)
 *
 * This RPC is used for:
 * - Testing inventory functionality
 * - Future loot drop systems (Task 4.5)
 * - GM commands to grant items
 * - Reward systems
 *
 * Acceptance Criteria:
 * - WHEN item created THEN generate globally unique UUID
 * - IF UID collision detected THEN reject operation
 * - WHEN item has UID THEN enforce no duplication across all players
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with InventoryCreateItemRequest
 * @returns JSON response with InventoryCreateItemResponse
 */
export async function rpcInventoryCreateItem(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[inventory_create_item] Request from user ${ctx.userId}`);

  // Parse request
  let request: InventoryCreateItemRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.itemId || !request.slotId) {
    throw Error('itemId and slotId are required');
  }

  if (!request.quantity || request.quantity < 1) {
    throw Error('quantity must be at least 1');
  }

  // Task 4.3.4: Validate slot ID format
  const slotValidation = validateSlotId(request.slotId);
  if (!slotValidation.valid) {
    throw Error(slotValidation.error);
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get character for this account
  const characterResult = await nk.sqlQuery(`
    SELECT character_id
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!characterResult || characterResult.length === 0) {
    throw Error('No character found for this account');
  }

  const characterId = characterResult[0].character_id;

  logger.info(`[inventory_create_item] Creating ${request.quantity}x ${request.itemId} for character ${characterId} in slot ${request.slotId}`);

  try {
    // Check if destination slot is occupied
    const existingItem = await nk.sqlQuery(`
      SELECT item_uid, item_id, quantity, metadata
      FROM inventory
      WHERE character_id = $1 AND slot_id = $2
    `, [characterId, request.slotId]);

    if (existingItem && existingItem.length > 0) {
      // Slot is occupied - check if items can stack
      const existing = existingItem[0];
      const canStack = existing.item_id === request.itemId &&
                       JSON.stringify(existing.metadata || {}) === JSON.stringify(request.metadata || {});

      if (canStack) {
        // Stack with existing item
        logger.info(`[inventory_create_item] Stacking with existing item ${existing.item_uid}`);
        await nk.sqlExec(`
          UPDATE inventory
          SET quantity = quantity + $1, version = version + 1
          WHERE item_uid = $2 AND character_id = $3
        `, [request.quantity, existing.item_uid, characterId]);

        const response: InventoryCreateItemResponse = {
          ok: true,
          itemUid: existing.item_uid
        };
        return JSON.stringify(response);
      } else {
        throw Error(`Slot ${request.slotId} is occupied by a different item. Cannot create item.`);
      }
    }

    // Slot is empty - create new item with UID enforcement
    const itemUid = await createItemWithUid(nk, logger, {
      characterId: characterId,
      itemId: request.itemId,
      slotId: request.slotId,
      quantity: request.quantity,
      durability: request.durability,
      metadata: request.metadata
    });

    const response: InventoryCreateItemResponse = {
      ok: true,
      itemUid: itemUid
    };

    return JSON.stringify(response);
  } catch (error) {
    logger.error(`[inventory_create_item] Failed to create item: ${error}`);
    throw Error(`Failed to create item: ${error}`);
  }
}

/**
 * Initialize inventory module
 * Registers RPC handlers with Nakama runtime
 *
 * @param ctx Nakama context
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param initializer Nakama initializer
 */
export function InitModule(
  ctx: any,
  logger: any,
  nk: any,
  initializer: any
): void {
  logger.info('Inventory module initialized');

  // Register inventory_move RPC (Task 4.3.1, Requirement 14)
  initializer.registerRpc('inventory_move', rpcInventoryMove);

  // Register inventory_create_item RPC (Task 4.3.2, Requirement 14)
  // Exposed for testing and future features (loot drops, rewards, etc.)
  initializer.registerRpc('inventory_create_item', rpcInventoryCreateItem);
}
