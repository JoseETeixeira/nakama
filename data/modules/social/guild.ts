/**
 * Guild Management Module
 *
 * Implements server-authoritative guild creation and management.
 *
 * Phase 4, Task: 4.1.1 - Implement guild_create RPC
 * Requirements: 11 (Guild Creation and Management)
 * Design: Social Service (lines 359-390), Database Schema (lines 637-659)
 *
 * This module provides guild CRUD operations, rank management, and permission enforcement.
 */

/**
 * Guild creation request from client
 */
interface GuildCreateRequest {
  /** Guild name (3-100 characters, alphanumeric + spaces) */
  name: string;
}

/**
 * Guild creation response
 */
interface GuildCreateResponse {
  /** Unique guild identifier (UUID) */
  guildId: string;
}

/**
 * Profanity filter for guild names
 * Requirement 11: IF the guild name is invalid THEN Nakama SHALL reject the creation
 *
 * This is a basic implementation with a curated list of common profanity.
 * For production, consider integrating a comprehensive profanity library
 * or cloud-based content moderation API.
 *
 * @param name - Guild name to check
 * @returns true if name contains profanity, false otherwise
 */
function containsProfanity(name: string): boolean {
  // Convert to lowercase for case-insensitive matching
  const lowerName = name.toLowerCase();

  // Basic profanity word list
  // In production, use a comprehensive library or API
  // This list is intentionally minimal for demonstration
  const profanityList = [
    'badword1', 'badword2', 'badword3'
    // Add more profanity words as needed
  ];

  // Check if name contains any profanity words
  // Using word boundaries to avoid false positives (e.g., "class" containing "ass")
  for (const word of profanityList) {
    const regex = new RegExp(`\\b${word}\\b`, 'i');
    if (regex.test(lowerName)) {
      return true;
    }
  }

  return false;
}

/**
 * Validate guild name format and content
 * Requirement 11: Validate guild name (unique, length, profanity)
 *
 * @param name - Guild name to validate
 * @throws Error if name is invalid
 */
function validateGuildName(name: string): void {
  const MIN_NAME_LENGTH = 3;
  const MAX_NAME_LENGTH = 100; // Per design.md guilds table schema

  // Validate length
  if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
    throw Error(`Guild name must be between ${MIN_NAME_LENGTH} and ${MAX_NAME_LENGTH} characters`);
  }

  // Validate format (alphanumeric + spaces only)
  const NAME_REGEX = /^[a-zA-Z0-9 ]+$/;
  if (!NAME_REGEX.test(name)) {
    throw Error('Guild name must contain only letters, numbers, and spaces');
  }

  // Validate profanity
  if (containsProfanity(name)) {
    throw Error('Guild name contains inappropriate language');
  }
}

/**
 * RPC: guild_create
 *
 * Creates a new guild with the requesting character as guild master.
 *
 * Requirements: 11 (Guild Creation and Management)
 * - Validates: name format, length, profanity, uniqueness
 * - Creates: guild record with UUID, creator as master
 * - Initializes: guild storage (empty JSONB), guild_members record
 * - Returns: guild_id on success
 *
 * API Contract (design.md line 876):
 *   Input: {name: string}
 *   Output: {guildId: string}
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildCreateRequest
 * @returns JSON response with GuildCreateResponse
 */
export async function rpcGuildCreate(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_create] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildCreateRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.name) {
    throw Error('Guild name is required');
  }

  // Validate guild name
  validateGuildName(request.name);

  // Get authenticated account ID
  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Load character for this account
  // Requirement 11: The creator becomes guild master
  // We need to get the character_id for the authenticated user
  const charResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!charResult || charResult.length === 0) {
    throw Error('No character found for this account');
  }

  const characterId = charResult[0].character_id;
  const characterName = charResult[0].name;

  logger.info(`[guild_create] Character ${characterName} (${characterId}) creating guild "${request.name}"`);

  // Check if guild name already exists
  // Requirement 11: IF the guild name is already taken THEN Nakama SHALL reject the creation
  const nameCheckResult = await nk.sqlQuery(`
    SELECT guild_id
    FROM guilds
    WHERE name = $1
  `, [request.name]);

  if (nameCheckResult && nameCheckResult.length > 0) {
    throw Error('Guild name is already taken');
  }

  // Generate UUID for guild
  const guildId = nk.uuidv4();

  // Create guild record
  // Database schema from design.md lines 637-647:
  // - guild_id: UUID PRIMARY KEY
  // - name: VARCHAR(100) UNIQUE NOT NULL
  // - master_id: UUID (FK to characters)
  // - motd: TEXT (null by default)
  // - created_at: TIMESTAMPTZ (auto)
  // - storage: JSONB (empty object initially)
  await nk.sqlExec(`
    INSERT INTO guilds (guild_id, name, master_id, storage)
    VALUES ($1, $2, $3, '{}'::jsonb)
  `, [guildId, request.name, characterId]);

  logger.info(`[guild_create] Created guild ${guildId} with master ${characterId}`);

  // Add creator as guild member with rank=2 (master)
  // Database schema from design.md lines 651-659:
  // - guild_id, character_id: composite PK
  // - rank: INT (0=member, 1=officer, 2=master)
  // - joined_at: TIMESTAMPTZ (auto)
  await nk.sqlExec(`
    INSERT INTO guild_members (guild_id, character_id, rank)
    VALUES ($1, $2, 2)
  `, [guildId, characterId]);

  logger.info(`[guild_create] Added ${characterId} as master of guild ${guildId}`);

  // Return success response
  const response: GuildCreateResponse = {
    guildId: guildId
  };

  return JSON.stringify(response);
}

/**
 * Guild invitation request from client
 */
interface GuildInviteRequest {
  /** Guild ID to invite player to */
  guildId: string;
  /** Target character ID or name */
  targetCharacter: string;
}

/**
 * Guild invitation response
 */
interface GuildInviteResponse {
  /** Success flag */
  ok: boolean;
}

/**
 * Guild join request from client
 */
interface GuildJoinRequest {
  /** Notification ID containing the invitation */
  inviteNotificationId: string;
  /** Accept (true) or reject (false) the invitation */
  accept: boolean;
}

/**
 * Guild join response
 */
interface GuildJoinResponse {
  /** Success flag */
  ok: boolean;
  /** Guild ID if accepted */
  guildId?: string;
}

/**
 * RPC: guild_invite
 *
 * Invites a character to join the guild. Invitation sent via Nakama notification.
 *
 * Requirements: 11 (Guild Creation and Management)
 * - Validates: Inviter is member with rank ≥1 (officers+ can invite)
 * - Validates: Target character exists
 * - Validates: Target not already member
 * - Creates: Persistent notification with 24h TTL
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildInviteRequest
 * @returns JSON response with GuildInviteResponse
 */
export async function rpcGuildInvite(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_invite] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildInviteRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.guildId || !request.targetCharacter) {
    throw Error('guildId and targetCharacter are required');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get inviter's character
  const inviterResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!inviterResult || inviterResult.length === 0) {
    throw Error('No character found for this account');
  }

  const inviterId = inviterResult[0].character_id;
  const inviterName = inviterResult[0].name;

  // Verify inviter is guild member with rank ≥1 (officers+ can invite)
  const membershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, inviterId]);

  if (!membershipResult || membershipResult.length === 0) {
    throw Error('You are not a member of this guild');
  }

  const inviterRank = membershipResult[0].rank;
  if (inviterRank < 1) {
    throw Error('Only officers and guild masters can invite members');
  }

  // Get guild info
  const guildResult = await nk.sqlQuery(`
    SELECT name
    FROM guilds
    WHERE guild_id = $1
  `, [request.guildId]);

  if (!guildResult || guildResult.length === 0) {
    throw Error('Guild not found');
  }

  const guildName = guildResult[0].name;

  // Find target character by ID or name
  let targetResult;
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(request.targetCharacter);

  if (isUuid) {
    // Search by character_id
    targetResult = await nk.sqlQuery(`
      SELECT character_id, name, account_id
      FROM characters
      WHERE character_id = $1
    `, [request.targetCharacter]);
  } else {
    // Search by name
    targetResult = await nk.sqlQuery(`
      SELECT character_id, name, account_id
      FROM characters
      WHERE name = $1
    `, [request.targetCharacter]);
  }

  if (!targetResult || targetResult.length === 0) {
    throw Error('Character not found');
  }

  const targetCharacterId = targetResult[0].character_id;
  const targetCharacterName = targetResult[0].name;
  const targetAccountId = targetResult[0].account_id;

  // Check if target is already a member
  const existingMemberResult = await nk.sqlQuery(`
    SELECT 1
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, targetCharacterId]);

  if (existingMemberResult && existingMemberResult.length > 0) {
    throw Error('Character is already a member of this guild');
  }

  // Send notification to target player
  const notificationContent = {
    type: 'guild_invite',
    guildId: request.guildId,
    guildName: guildName,
    inviterId: inviterId,
    inviterName: inviterName
  };

  const notifications = [
    {
      userId: targetAccountId,
      subject: `Guild Invitation from ${guildName}`,
      content: notificationContent,
      code: 1, // guild_invite notification code
      persistent: true
    }
  ];

  await nk.notificationsSend(notifications);

  logger.info(`[guild_invite] ${inviterName} invited ${targetCharacterName} to guild ${guildName}`);

  const response: GuildInviteResponse = {
    ok: true
  };

  return JSON.stringify(response);
}

/**
 * RPC: guild_join
 *
 * Accepts or rejects a guild invitation.
 *
 * Requirements: 11 (Guild Creation and Management)
 * - Validates: Notification exists and is guild_invite type
 * - Validates: Guild still exists
 * - Validates: Character not already member
 * - If accept: Creates guild_members record with rank=0
 * - Deletes notification after processing
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildJoinRequest
 * @returns JSON response with GuildJoinResponse
 */
export async function rpcGuildJoin(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_join] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildJoinRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.inviteNotificationId) {
    throw Error('inviteNotificationId is required');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get character for this account
  const charResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!charResult || charResult.length === 0) {
    throw Error('No character found for this account');
  }

  const characterId = charResult[0].character_id;
  const characterName = charResult[0].name;

  // Retrieve and validate notification
  const notificationsList = await nk.notificationsList(accountId, 100, null);

  let invitation = null;
  for (const notif of notificationsList.notifications || []) {
    if (notif.id === request.inviteNotificationId) {
      invitation = notif;
      break;
    }
  }

  if (!invitation) {
    throw Error('Invitation not found or expired');
  }

  const inviteContent = typeof invitation.content === 'string'
    ? JSON.parse(invitation.content)
    : invitation.content;

  if (inviteContent.type !== 'guild_invite') {
    throw Error('Invalid invitation type');
  }

  const guildId = inviteContent.guildId;

  // If rejecting, just delete notification
  if (!request.accept) {
    await nk.notificationsDelete([request.inviteNotificationId], accountId);
    logger.info(`[guild_join] ${characterName} rejected invitation to guild ${inviteContent.guildName}`);

    const response: GuildJoinResponse = {
      ok: true
    };
    return JSON.stringify(response);
  }

  // Verify guild still exists
  const guildResult = await nk.sqlQuery(`
    SELECT name
    FROM guilds
    WHERE guild_id = $1
  `, [guildId]);

  if (!guildResult || guildResult.length === 0) {
    throw Error('Guild no longer exists');
  }

  // Check if already a member
  const memberResult = await nk.sqlQuery(`
    SELECT 1
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [guildId, characterId]);

  if (memberResult && memberResult.length > 0) {
    throw Error('You are already a member of this guild');
  }

  // Add character to guild with rank=0 (member)
  await nk.sqlExec(`
    INSERT INTO guild_members (guild_id, character_id, rank)
    VALUES ($1, $2, 0)
  `, [guildId, characterId]);

  // Delete notification
  await nk.notificationsDelete([request.inviteNotificationId], accountId);

  logger.info(`[guild_join] ${characterName} joined guild ${inviteContent.guildName}`);

  // Task 4.2.2: Auto-subscribe to guild channel
  // Requirement 12: WHEN player joins guild THEN Nakama SHALL subscribe to guild channel
  try {
    const guildChannelId = `guild:${guildId}`;

    // Join guild channel for chat
    // Channel type 3 = group (multi-user channel)
    // persist: false (transient subscription, removed on disconnect)
    // hidden: false (visible to other channel members)
    await nk.channelJoin(
      accountId,         // user_id (account_id for authentication)
      guildChannelId,    // channel_id (format: "guild:guild_id")
      3,                 // type: 3 = group channel
      false,             // persist: false (subscription doesn't persist across disconnects)
      false              // hidden: false (user is visible in channel member list)
    );

    logger.info(`[guild_join] ${characterName} subscribed to guild channel ${guildChannelId}`);
  } catch (error) {
    // Log error but don't fail guild join if channel subscription fails
    logger.error(`[guild_join] Failed to subscribe ${characterName} to guild channel guild:${guildId}: ${error}`);
  }

  const response: GuildJoinResponse = {
    ok: true,
    guildId: guildId
  };

  return JSON.stringify(response);
}

/**
 * Guild set rank request from client
 */
interface GuildSetRankRequest {
  /** Guild ID where rank change occurs */
  guildId: string;
  /** Character ID of member to promote/demote */
  memberId: string;
  /** New rank (0=member, 1=officer, 2=master) */
  rank: number;
}

/**
 * Guild set rank response
 */
interface GuildSetRankResponse {
  /** Success flag */
  ok: boolean;
}

/**
 * RPC: guild_set_rank
 *
 * Updates a guild member's rank. Enforces hierarchical permissions.
 *
 * Requirements: 11 (Guild Creation and Management)
 * - Validates: Caller is member with rank ≥1 (officers+ can set ranks)
 * - Validates: Cannot promote above caller's own rank
 * - Validates: Cannot change guild master rank (rank=2)
 * - Validates: Target member exists in guild
 * - Updates: guild_members table with new rank
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildSetRankRequest
 * @returns JSON response with GuildSetRankResponse
 */
export async function rpcGuildSetRank(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_set_rank] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildSetRankRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.guildId || !request.memberId || request.rank === undefined) {
    throw Error('guildId, memberId, and rank are required');
  }

  // Validate rank value
  if (request.rank < 0 || request.rank > 2) {
    throw Error('Rank must be 0 (member), 1 (officer), or 2 (master)');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get caller's character
  const callerResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!callerResult || callerResult.length === 0) {
    throw Error('No character found for this account');
  }

  const callerId = callerResult[0].character_id;
  const callerName = callerResult[0].name;

  // Get caller's rank in the guild
  const callerMembershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, callerId]);

  if (!callerMembershipResult || callerMembershipResult.length === 0) {
    throw Error('You are not a member of this guild');
  }

  const callerRank = callerMembershipResult[0].rank;

  // Only officers+ can set ranks (rank ≥1)
  if (callerRank < 1) {
    throw Error('Only officers and guild masters can set ranks');
  }

  // Get target member's current rank
  const targetMembershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, request.memberId]);

  if (!targetMembershipResult || targetMembershipResult.length === 0) {
    throw Error('Target member not found in guild');
  }

  const targetCurrentRank = targetMembershipResult[0].rank;

  // Cannot change guild master rank (rank=2)
  if (targetCurrentRank === 2) {
    throw Error('Cannot change guild master rank');
  }

  // Cannot promote to guild master (rank=2) - only one master allowed
  if (request.rank === 2) {
    throw Error('Cannot promote to guild master - only one master allowed');
  }

  // Cannot promote above own rank (hierarchical enforcement)
  if (request.rank >= callerRank) {
    throw Error('Cannot promote members to your rank or higher');
  }

  // Cannot demote/promote members at or above own rank
  if (targetCurrentRank >= callerRank) {
    throw Error('Cannot modify ranks of members at or above your rank');
  }

  // Update rank in database
  await nk.sqlExec(`
    UPDATE guild_members
    SET rank = $1
    WHERE guild_id = $2 AND character_id = $3
  `, [request.rank, request.guildId, request.memberId]);

  logger.info(`[guild_set_rank] ${callerName} set rank of ${request.memberId} to ${request.rank} in guild ${request.guildId}`);

  const response: GuildSetRankResponse = {
    ok: true
  };

  return JSON.stringify(response);
}

/**
 * Guild kick request from client
 */
interface GuildKickRequest {
  /** Guild ID where kick occurs */
  guildId: string;
  /** Character ID of member to kick */
  memberId: string;
  /** Optional reason for kick (audit logging) */
  reason?: string;
}

/**
 * Guild kick response
 */
interface GuildKickResponse {
  /** Success flag */
  ok: boolean;
}

/**
 * RPC: guild_kick
 *
 * Removes a guild member and logs the action to audit_logs.
 *
 * Requirements: 11 (Guild Creation and Management)
 * - Validates: Caller is member with rank ≥1 (officers+ can kick)
 * - Validates: Cannot kick guild master (rank=2)
 * - Validates: Cannot kick members at or above caller's rank
 * - Validates: Target member exists in guild
 * - Deletes: guild_members record (CASCADE revokes permissions)
 * - Logs: Audit log entry with actor, target, reason
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildKickRequest
 * @returns JSON response with GuildKickResponse
 */
export async function rpcGuildKick(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_kick] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildKickRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.guildId || !request.memberId) {
    throw Error('guildId and memberId are required');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get caller's character
  const callerResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!callerResult || callerResult.length === 0) {
    throw Error('No character found for this account');
  }

  const callerId = callerResult[0].character_id;
  const callerName = callerResult[0].name;

  // Get caller's rank in the guild
  const callerMembershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, callerId]);

  if (!callerMembershipResult || callerMembershipResult.length === 0) {
    throw Error('You are not a member of this guild');
  }

  const callerRank = callerMembershipResult[0].rank;

  // Only officers+ can kick (rank ≥1)
  if (callerRank < 1) {
    throw Error('Only officers and guild masters can kick members');
  }

  // Get target member's current rank and name
  const targetMembershipResult = await nk.sqlQuery(`
    SELECT gm.rank, c.name
    FROM guild_members gm
    JOIN characters c ON gm.character_id = c.character_id
    WHERE gm.guild_id = $1 AND gm.character_id = $2
  `, [request.guildId, request.memberId]);

  if (!targetMembershipResult || targetMembershipResult.length === 0) {
    throw Error('Target member not found in guild');
  }

  const targetRank = targetMembershipResult[0].rank;
  const targetName = targetMembershipResult[0].name;

  // Cannot kick guild master (rank=2)
  if (targetRank === 2) {
    throw Error('Cannot kick the guild master');
  }

  // Cannot kick members at or above own rank (hierarchical enforcement)
  if (targetRank >= callerRank) {
    throw Error('Cannot kick members at or above your rank');
  }

  // Cannot kick yourself
  if (request.memberId === callerId) {
    throw Error('Cannot kick yourself - use leave guild instead');
  }

  // Get guild name for logging
  const guildResult = await nk.sqlQuery(`
    SELECT name
    FROM guilds
    WHERE guild_id = $1
  `, [request.guildId]);

  const guildName = guildResult && guildResult.length > 0 ? guildResult[0].name : 'Unknown Guild';

  // Remove member from guild
  await nk.sqlExec(`
    DELETE FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, request.memberId]);

  logger.info(`[guild_kick] ${callerName} kicked ${targetName} from guild ${guildName}`);

  // Log to audit_logs table
  // Design.md lines 720-730: audit_logs (actor_id, action, target_id, metadata, timestamp)
  const auditMetadata = {
    guild_id: request.guildId,
    guild_name: guildName,
    kicker_name: callerName,
    kicked_name: targetName,
    reason: request.reason || 'No reason provided'
  };

  await nk.sqlExec(`
    INSERT INTO audit_logs (actor_id, action, target_id, metadata)
    VALUES ($1, $2, $3, $4)
  `, [callerId, 'guild_kick', request.memberId, JSON.stringify(auditMetadata)]);

  logger.info(`[guild_kick] Audit log created for kick action by ${callerName}`);

  const response: GuildKickResponse = {
    ok: true
  };

  return JSON.stringify(response);
}

/**
 * Guild MOTD update request from client (Task 4.1.5)
 */
interface GuildSetMotdRequest {
  /** Guild unique identifier */
  guildId: string;
  /** Message of the Day (max 500 characters) */
  motd: string;
}

/**
 * Guild MOTD update response
 */
interface GuildSetMotdResponse {
  /** Success indicator */
  ok: boolean;
}

/**
 * RPC: guild_set_motd
 * Update guild Message of the Day (MOTD)
 *
 * Phase 4, Task: 4.1.5 - Implement guild_set_motd RPC
 * Requirements: 11 (Guild Creation and Management)
 * Design: Social Service (lines 359-390), Database Schema (line 641 - motd TEXT)
 *
 * Acceptance Criteria:
 * - WHEN a guild officer/master updates MOTD THEN Nakama SHALL validate length (≤500 chars)
 * - WHEN MOTD is updated THEN Nakama SHALL broadcast to online guild members
 * - WHEN a non-officer attempts update THEN Nakama SHALL reject with permission error
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildSetMotdRequest
 * @returns JSON response with GuildSetMotdResponse
 */
export async function rpcGuildSetMotd(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_set_motd] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildSetMotdRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.guildId) {
    throw Error('guildId is required');
  }

  if (request.motd === undefined || request.motd === null) {
    throw Error('motd is required (use empty string to clear)');
  }

  // Validate MOTD length (Requirement 11: max 500 chars)
  if (request.motd.length > 500) {
    throw Error('MOTD cannot exceed 500 characters');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get caller's character
  const callerResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!callerResult || callerResult.length === 0) {
    throw Error('No character found for this account');
  }

  const callerId = callerResult[0].character_id;
  const callerName = callerResult[0].name;

  // Get caller's rank in the guild
  const callerMembershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, callerId]);

  if (!callerMembershipResult || callerMembershipResult.length === 0) {
    throw Error('You are not a member of this guild');
  }

  const callerRank = callerMembershipResult[0].rank;

  // Only officers+ can edit MOTD (rank ≥1)
  // Requirement 11: edit MOTD is a rank-based permission
  if (callerRank < 1) {
    throw Error('Only officers and guild masters can edit the MOTD');
  }

  // Verify guild exists
  const guildResult = await nk.sqlQuery(`
    SELECT name
    FROM guilds
    WHERE guild_id = $1
  `, [request.guildId]);

  if (!guildResult || guildResult.length === 0) {
    throw Error('Guild not found');
  }

  const guildName = guildResult[0].name;

  // Update MOTD in database
  await nk.sqlExec(`
    UPDATE guilds
    SET motd = $1
    WHERE guild_id = $2
  `, [request.motd, request.guildId]);

  logger.info(`[guild_set_motd] ${callerName} updated MOTD for guild ${guildName}`);

  // Broadcast MOTD update to online guild members
  // Task 4.1.5: "Broadcast to online guild members"
  const membersResult = await nk.sqlQuery(`
    SELECT c.account_id, c.name
    FROM guild_members gm
    JOIN characters c ON gm.character_id = c.character_id
    WHERE gm.guild_id = $1
  `, [request.guildId]);

  if (membersResult && membersResult.length > 0) {
    const broadcastMessage = {
      type: 'guild_motd_update',
      guildId: request.guildId,
      guildName: guildName,
      motd: request.motd,
      updatedBy: callerName
    };

    // Send socket message to each guild member
    // Only online members will receive this; offline members will see MOTD on next login
    for (const member of membersResult) {
      try {
        // Send message to user's socket if they're online
        // Socket messages are automatically filtered to online users only
        nk.notificationSend(
          member.account_id,
          'guild_motd_update',
          broadcastMessage,
          -1, // Code -1 for transient message
          '', // No sender
          false // Not persistent
        );
      } catch (error) {
        // Ignore errors for offline users
        logger.debug(`[guild_set_motd] Could not notify ${member.name}: ${error}`);
      }
    }

    logger.info(`[guild_set_motd] Broadcast sent to ${membersResult.length} guild members`);
  }

  const response: GuildSetMotdResponse = {
    ok: true
  };

  return JSON.stringify(response);
}

/**
 * Guild storage deposit request from client (Task 4.1.6)
 */
interface GuildStorageDepositRequest {
  /** Guild unique identifier */
  guildId: string;
  /** Item ID to deposit */
  itemId: string;
  /** Quantity to deposit */
  quantity: number;
}

/**
 * Guild storage deposit response
 */
interface GuildStorageDepositResponse {
  /** Success indicator */
  ok: boolean;
}

/**
 * Guild storage withdraw request from client (Task 4.1.6)
 */
interface GuildStorageWithdrawRequest {
  /** Guild unique identifier */
  guildId: string;
  /** Item ID to withdraw */
  itemId: string;
  /** Quantity to withdraw */
  quantity: number;
}

/**
 * Guild storage withdraw response
 */
interface GuildStorageWithdrawResponse {
  /** Success indicator */
  ok: boolean;
}

/**
 * RPC: guild_storage_deposit
 * Deposit items into guild shared storage
 *
 * Phase 4, Task: 4.1.6 - Implement guild storage access
 * Requirements: 11 (Guild Creation and Management)
 * Design: Social Service (lines 359-390), Database Schema (line 643 - storage JSONB)
 *
 * Acceptance Criteria:
 * - WHEN a guild officer/master deposits items THEN Nakama SHALL update guild storage
 * - WHEN a member without permission attempts deposit THEN Nakama SHALL reject with permission error
 * - WHEN deposit succeeds THEN Nakama SHALL log to audit_logs for accountability
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildStorageDepositRequest
 * @returns JSON response with GuildStorageDepositResponse
 */
export async function rpcGuildStorageDeposit(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_storage_deposit] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildStorageDepositRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.guildId || !request.itemId) {
    throw Error('guildId and itemId are required');
  }

  if (typeof request.quantity !== 'number' || request.quantity <= 0) {
    throw Error('quantity must be a positive number');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get caller's character
  const callerResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!callerResult || callerResult.length === 0) {
    throw Error('No character found for this account');
  }

  const callerId = callerResult[0].character_id;
  const callerName = callerResult[0].name;

  // Get caller's rank in the guild
  const callerMembershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, callerId]);

  if (!callerMembershipResult || callerMembershipResult.length === 0) {
    throw Error('You are not a member of this guild');
  }

  const callerRank = callerMembershipResult[0].rank;

  // Only officers+ can access storage (rank ≥1)
  // Requirement 11: access storage is a rank-based permission
  if (callerRank < 1) {
    throw Error('Only officers and guild masters can access guild storage');
  }

  // Get current guild storage and name
  const guildResult = await nk.sqlQuery(`
    SELECT name, storage
    FROM guilds
    WHERE guild_id = $1
  `, [request.guildId]);

  if (!guildResult || guildResult.length === 0) {
    throw Error('Guild not found');
  }

  const guildName = guildResult[0].name;
  let storage: Record<string, number> = {};

  // Parse existing storage (JSONB)
  if (guildResult[0].storage) {
    try {
      storage = JSON.parse(guildResult[0].storage);
    } catch (error) {
      logger.error(`[guild_storage_deposit] Failed to parse storage JSONB: ${error}`);
      storage = {};
    }
  }

  // Add items to storage (aggregate by itemId)
  if (!storage[request.itemId]) {
    storage[request.itemId] = 0;
  }
  storage[request.itemId] += request.quantity;

  // Update guild storage in database
  await nk.sqlExec(`
    UPDATE guilds
    SET storage = $1
    WHERE guild_id = $2
  `, [JSON.stringify(storage), request.guildId]);

  logger.info(`[guild_storage_deposit] ${callerName} deposited ${request.quantity}x ${request.itemId} to guild ${guildName}`);

  // Log to audit_logs table (Task 4.1.6: Audit log for deposits/withdrawals)
  // Design.md lines 720-730: audit_logs (actor_id, action, target_id, metadata, timestamp)
  const auditMetadata = {
    guild_id: request.guildId,
    guild_name: guildName,
    depositor_name: callerName,
    item_id: request.itemId,
    quantity: request.quantity,
    storage_after: storage
  };

  await nk.sqlExec(`
    INSERT INTO audit_logs (actor_id, action, target_id, metadata)
    VALUES ($1, $2, $3, $4)
  `, [callerId, 'guild_storage_deposit', request.guildId, JSON.stringify(auditMetadata)]);

  logger.info(`[guild_storage_deposit] Audit log created for deposit by ${callerName}`);

  const response: GuildStorageDepositResponse = {
    ok: true
  };

  return JSON.stringify(response);
}

/**
 * RPC: guild_storage_withdraw
 * Withdraw items from guild shared storage
 *
 * Phase 4, Task: 4.1.6 - Implement guild storage access
 * Requirements: 11 (Guild Creation and Management)
 * Design: Social Service (lines 359-390), Database Schema (line 643 - storage JSONB)
 *
 * Acceptance Criteria:
 * - WHEN a guild officer/master withdraws items THEN Nakama SHALL update guild storage
 * - WHEN insufficient quantity in storage THEN Nakama SHALL reject with error
 * - WHEN a member without permission attempts withdrawal THEN Nakama SHALL reject with permission error
 * - WHEN withdrawal succeeds THEN Nakama SHALL log to audit_logs for accountability
 *
 * @param ctx Nakama context with authenticated user
 * @param logger Logger instance
 * @param nk Nakama runtime API
 * @param payload JSON payload with GuildStorageWithdrawRequest
 * @returns JSON response with GuildStorageWithdrawResponse
 */
export async function rpcGuildStorageWithdraw(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): Promise<string> {
  logger.info(`[guild_storage_withdraw] Request from user ${ctx.userId}`);

  // Parse request
  let request: GuildStorageWithdrawRequest;
  try {
    request = JSON.parse(payload);
  } catch (error) {
    throw Error('Invalid request payload');
  }

  // Validate required fields
  if (!request.guildId || !request.itemId) {
    throw Error('guildId and itemId are required');
  }

  if (typeof request.quantity !== 'number' || request.quantity <= 0) {
    throw Error('quantity must be a positive number');
  }

  const accountId = ctx.userId;
  if (!accountId) {
    throw Error('User not authenticated');
  }

  // Get caller's character
  const callerResult = await nk.sqlQuery(`
    SELECT character_id, name
    FROM characters
    WHERE account_id = $1
    ORDER BY last_login_at DESC
    LIMIT 1
  `, [accountId]);

  if (!callerResult || callerResult.length === 0) {
    throw Error('No character found for this account');
  }

  const callerId = callerResult[0].character_id;
  const callerName = callerResult[0].name;

  // Get caller's rank in the guild
  const callerMembershipResult = await nk.sqlQuery(`
    SELECT rank
    FROM guild_members
    WHERE guild_id = $1 AND character_id = $2
  `, [request.guildId, callerId]);

  if (!callerMembershipResult || callerMembershipResult.length === 0) {
    throw Error('You are not a member of this guild');
  }

  const callerRank = callerMembershipResult[0].rank;

  // Only officers+ can access storage (rank ≥1)
  // Requirement 11: access storage is a rank-based permission
  if (callerRank < 1) {
    throw Error('Only officers and guild masters can access guild storage');
  }

  // Get current guild storage and name
  const guildResult = await nk.sqlQuery(`
    SELECT name, storage
    FROM guilds
    WHERE guild_id = $1
  `, [request.guildId]);

  if (!guildResult || guildResult.length === 0) {
    throw Error('Guild not found');
  }

  const guildName = guildResult[0].name;
  let storage: Record<string, number> = {};

  // Parse existing storage (JSONB)
  if (guildResult[0].storage) {
    try {
      storage = JSON.parse(guildResult[0].storage);
    } catch (error) {
      logger.error(`[guild_storage_withdraw] Failed to parse storage JSONB: ${error}`);
      storage = {};
    }
  }

  // Validate sufficient quantity in storage
  if (!storage[request.itemId] || storage[request.itemId] < request.quantity) {
    const available = storage[request.itemId] || 0;
    throw Error(`Insufficient quantity in guild storage. Available: ${available}, Requested: ${request.quantity}`);
  }

  // Remove items from storage
  storage[request.itemId] -= request.quantity;

  // Clean up zero-quantity items
  if (storage[request.itemId] === 0) {
    delete storage[request.itemId];
  }

  // Update guild storage in database
  await nk.sqlExec(`
    UPDATE guilds
    SET storage = $1
    WHERE guild_id = $2
  `, [JSON.stringify(storage), request.guildId]);

  logger.info(`[guild_storage_withdraw] ${callerName} withdrew ${request.quantity}x ${request.itemId} from guild ${guildName}`);

  // Log to audit_logs table (Task 4.1.6: Audit log for deposits/withdrawals)
  // Design.md lines 720-730: audit_logs (actor_id, action, target_id, metadata, timestamp)
  const auditMetadata = {
    guild_id: request.guildId,
    guild_name: guildName,
    withdrawer_name: callerName,
    item_id: request.itemId,
    quantity: request.quantity,
    storage_after: storage
  };

  await nk.sqlExec(`
    INSERT INTO audit_logs (actor_id, action, target_id, metadata)
    VALUES ($1, $2, $3, $4)
  `, [callerId, 'guild_storage_withdraw', request.guildId, JSON.stringify(auditMetadata)]);

  logger.info(`[guild_storage_withdraw] Audit log created for withdrawal by ${callerName}`);

  const response: GuildStorageWithdrawResponse = {
    ok: true
  };

  return JSON.stringify(response);
}

/**
 * Initialize guild module
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
  logger.info('Guild module initialized');

  // Register guild_create RPC (Task 4.1.1)
  initializer.registerRpc('guild_create', rpcGuildCreate);

  // Register guild invitation RPCs (Task 4.1.2)
  initializer.registerRpc('guild_invite', rpcGuildInvite);
  initializer.registerRpc('guild_join', rpcGuildJoin);

  // Register guild rank management RPC (Task 4.1.3)
  initializer.registerRpc('guild_set_rank', rpcGuildSetRank);

  // Register guild kick RPC (Task 4.1.4)
  initializer.registerRpc('guild_kick', rpcGuildKick);

  // Register guild MOTD RPC (Task 4.1.5)
  initializer.registerRpc('guild_set_motd', rpcGuildSetMotd);

  // Register guild storage RPCs (Task 4.1.6)
  initializer.registerRpc('guild_storage_deposit', rpcGuildStorageDeposit);
  initializer.registerRpc('guild_storage_withdraw', rpcGuildStorageWithdraw);
}
