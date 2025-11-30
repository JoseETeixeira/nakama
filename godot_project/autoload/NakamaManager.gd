## NakamaManager Singleton
##
## Autoload singleton for managing Nakama client connections,
## authentication, and RPC communications.
##
## Task: 1.4.1 - Set up Godot 4 project structure
## Requirements: 1 (Authentication), 2 (Character Selection), 3 (Character Creation)
##
## This singleton provides a centralized interface for all Nakama operations:
## - Client initialization and authentication
## - Session and socket management
## - Character RPCs (list, create, select, delete)
## - World entry and zone streaming
##
## Usage:
##   await NakamaManager.authenticate_device()
##   var characters = await NakamaManager.list_characters()
##   var character_id = await NakamaManager.create_character("HeroName", "warrior")
extends Node

## Nakama client instance for HTTP RPCs
var client: NakamaClient = null

## Current authenticated session
var session: NakamaSession = null

## WebSocket connection for real-time communication
var socket: NakamaSocket = null

## Currently selected character ID
## Task 2.1.5: Store character ID for zone_snapshot RPC
var current_character_id: String = ""

## Currently selected character name
var current_character_name: String = ""

## Currently joined match ID for delta streaming
var current_match_id: String = ""

## Network metrics tracking (Requirement 4 - Task 3.4)
var network_metrics: Dictionary = {
	"last_delta_size": 0,          # Size of last delta message in bytes
	"total_deltas_received": 0,    # Total number of delta messages received
	"total_bytes_received": 0,     # Total bytes received from deltas
	"last_delta_timestamp": 0,     # Timestamp of last delta received (msec)
	"average_delta_interval": 0.0, # Average time between deltas in seconds
	"estimated_latency": 0.0       # Estimated round-trip latency in milliseconds
}

## Delta interval tracking for metrics
var _delta_intervals: Array[float] = []
var _max_delta_intervals: int = 20  # Keep last 20 intervals for averaging

## Network logging toggle (Task 8.2 - Requirement 13)
## Press F4 to enable/disable detailed network logging to console
var network_logging_enabled: bool = false

## Server configuration (loaded from project settings)
## Task 1.4.2 - Configured via Project Settings -> Nakama
var server_key: String
var server_host: String
var server_port: int
var server_protocol: String

## Called when the node enters the scene tree
func _ready() -> void:
	print("[NakamaManager] Initializing Nakama client...")

	# Load configuration from project settings (Task 1.4.2)
	server_key = ProjectSettings.get_setting("nakama/server/key", "defaultkey")
	server_host = ProjectSettings.get_setting("nakama/server/host", "127.0.0.1")
	server_port = ProjectSettings.get_setting("nakama/server/port", 7350)
	server_protocol = ProjectSettings.get_setting("nakama/server/protocol", "http")

	print("[NakamaManager] Server config: %s://%s:%d (key: %s)" % [server_protocol, server_host, server_port, server_key])

	client = Nakama.create_client(server_key, server_host, server_port, server_protocol)
	print("[NakamaManager] Nakama client initialized")


## Process loop for F4 network logging toggle
## Task 8.2: Implement Network Logging (Requirement 13)
func _process(_delta: float) -> void:
	# F4 toggle for network logging
	if Input.is_action_just_pressed("ui_f4"):
		network_logging_enabled = not network_logging_enabled
		var status = "ENABLED" if network_logging_enabled else "DISABLED"
		print("\n========================================")
		print("[NakamaManager] Network Logging %s" % status)
		print("========================================\n")


## Log network activity to console with timestamp
## Task 8.2: Network logging helper function
##
## Parameters:
##   category: Log category (RPC, DELTA, etc.)
##   message: Log message
##   payload: Optional payload data to log
func _log_network(category: String, message: String, payload: Variant = null) -> void:
	if not network_logging_enabled:
		return
	
	var timestamp = Time.get_time_string_from_system()
	var log_msg = "[%s] [%s] %s" % [timestamp, category, message]
	
	print(log_msg)
	
	if payload != null:
		if payload is String:
			print("  Payload: %s" % payload)
		elif payload is Dictionary or payload is Array:
			print("  Payload: %s" % JSON.stringify(payload, "  "))
		else:
			print("  Payload: %s" % str(payload))


## Wrapper for RPC calls with automatic logging
## Task 8.2: Network logging for RPCs
##
## Parameters:
##   rpc_name: Name of the RPC function
##   payload: JSON payload string or Dictionary
##
## Returns: Parsed response data or null on error
func _rpc_with_logging(rpc_name: String, payload: Variant) -> Variant:
	if session == null:
		push_error("[NakamaManager] Cannot call RPC %s: not authenticated" % rpc_name)
		return null
	
	# Convert payload to string if needed
	var payload_str: String = ""
	if payload is String:
		payload_str = payload
	elif payload is Dictionary:
		payload_str = JSON.stringify(payload)
	else:
		payload_str = str(payload)
	
	# Log request
	_log_network("RPC", "%s -> Request" % rpc_name, payload_str)
	
	# Make RPC call
	var response = await client.rpc_async(session, rpc_name, payload_str)
	
	# Check for exception
	if response.is_exception():
		var error_msg = response.get_exception().message
		_log_network("RPC", "%s -> Error: %s" % [rpc_name, error_msg])
		return null
	
	# Parse response
	var data = JSON.parse_string(response.payload)
	
	# Log response
	_log_network("RPC", "%s -> Response" % rpc_name, data)
	
	return data


## Authenticate using device ID (auto-registration)
##
## Returns: NakamaSession on success
## Throws: Error if authentication fails
##
## Task: 1.4.3 - Implement authentication screen
func authenticate_device() -> void:
	print("[NakamaManager] Authenticating with device ID...")
	var device_id := OS.get_unique_id()

	# Authenticate with auto-create enabled (true)
	session = await client.authenticate_device_async(device_id, null, true)

	if session == null:
		push_error("[NakamaManager] Authentication failed: session is null")
		return

	print("[NakamaManager] Authenticated successfully. User ID: ", session.user_id)

	# Create socket connection for real-time communication
	socket = Nakama.create_socket_from(client)
	
	# Connect socket event handlers
	socket.closed.connect(_on_socket_closed)
	socket.connected.connect(_on_socket_connected)
	socket.received_error.connect(_on_socket_error)
	
	var connected = await socket.connect_async(session)

	if connected.is_exception():
		push_error("[NakamaManager] Socket connection failed: ", connected.get_exception().message)
		return

	print("[NakamaManager] Socket connected")


## List all characters for the authenticated account
##
## Returns: Array of Character dictionaries
## Throws: Error if RPC fails
##
## Task: 1.4.4 - Implement character selection screen
func list_characters() -> Array:
	if session == null:
		push_error("[NakamaManager] Cannot list characters: not authenticated")
		return []

	print("[NakamaManager] Listing characters...")
	
	# Log RPC call (Task 8.2)
	_log_network("RPC", "list_characters -> Request", "{}")
	
	var response = await client.rpc_async(session, "list_characters", "{}")

	if response.is_exception():
		var error_msg = response.get_exception().message
		_log_network("RPC", "list_characters -> Error: %s" % error_msg)
		push_error("[NakamaManager] list_characters RPC failed: ", error_msg)
		return []

	var data = JSON.parse_string(response.payload)
	var characters = data.get("characters", [])

	# Log RPC response (Task 8.2)
	_log_network("RPC", "list_characters -> Response: %d character(s)" % characters.size(), data)

	print("[NakamaManager] Found %d character(s)" % characters.size())
	return characters


## Create a new character
##
## Parameters:
##   name: Character name (3-20 chars, alphanumeric + spaces)
##   archetype_id: Archetype identifier (e.g., "warrior", "mage")
##
## Returns: Character ID string on success
## Throws: Error if RPC fails or validation fails
##
## Task: 1.4.5 - Implement character creation flow
func create_character(character_name: String, archetype_id: String) -> String:
	if session == null:
		push_error("[NakamaManager] Cannot create character: not authenticated")
		return ""

	print("[NakamaManager] Creating character '%s' with archetype '%s'..." % [character_name, archetype_id])

	var payload = JSON.stringify({
		"name": character_name,
		"archetype_id": archetype_id
	})

	# Log RPC call (Task 8.2)
	_log_network("RPC", "create_character -> Request", payload)

	var response = await client.rpc_async(session, "create_character", payload)

	if response.is_exception():
		var error_message = response.get_exception().message
		_log_network("RPC", "create_character -> Error: %s" % error_message)
		push_error("[NakamaManager] create_character RPC failed: ", error_message)
		return ""

	var data = JSON.parse_string(response.payload)
	var character_id = data.get("character_id", "")

	# Log RPC response (Task 8.2)
	_log_network("RPC", "create_character -> Response: character_id=%s" % character_id, data)

	print("[NakamaManager] Character created successfully. ID: ", character_id)
	return character_id


## Select a character for world entry
##
## Parameters:
##   character_id: UUID of character to select
##
## Returns: CharacterState dictionary with full character data
## Throws: Error if RPC fails
##
## Task: 1.4.6 - Implement character selection flow
func select_character(character_id: String) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot select character: not authenticated")
		return {}

	print("[NakamaManager] Selecting character: ", character_id)

	var payload = JSON.stringify({
		"character_id": character_id
	})

	# Log RPC call (Task 8.2)
	_log_network("RPC", "select_character -> Request", payload)

	var response = await client.rpc_async(session, "select_character", payload)

	if response.is_exception():
		var error_msg = response.get_exception().message
		_log_network("RPC", "select_character -> Error: %s" % error_msg)
		push_error("[NakamaManager] select_character RPC failed: ", error_msg)
		return {}

	var data = JSON.parse_string(response.payload)

	if not data.get("ok", false):
		_log_network("RPC", "select_character -> Error: ok=false", data)
		push_error("[NakamaManager] select_character returned ok=false")
		return {}

	var character = data.get("character", {})
	
	# Store current character ID and name
	current_character_id = character.get("characterId", "")
	current_character_name = character.get("name", "Unknown")
	
	# Log RPC response (Task 8.2)
	_log_network("RPC", "select_character -> Response: %s" % character.get("name", "Unknown"), data)
	
	print("[NakamaManager] Character selected: ", character.get("name", "Unknown"))
	return character


## Delete a character
##
## Parameters:
##   character_id: UUID of character to delete
##
## Returns: true on success, false on failure
##
## Task: 2.2 - Create Character Selection Screen (delete functionality)
## Requirements: 1.2 (Character Management - delete operation)
## Design: CharacterSelect.tscn (lines 164-168)
##
## This function calls the delete_character RPC to permanently remove a character.
## The server validates ownership before deletion.
func delete_character(character_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot delete character: not authenticated")
		return false

	print("[NakamaManager] Deleting character: ", character_id)

	var payload = JSON.stringify({
		"character_id": character_id
	})

	var response = await client.rpc_async(session, "delete_character", payload)

	if response.is_exception():
		push_error("[NakamaManager] delete_character RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if not data.get("ok", false):
		push_error("[NakamaManager] delete_character returned ok=false")
		return false

	print("[NakamaManager] Character deleted successfully")
	return true


## Enter the game world with selected character
##
## Parameters:
##   character_id: UUID of character entering world
##
## Returns: Zone entry data with:
##   - shardId: Shard identifier
##   - zoneId: Zone identifier where player will spawn
##   - spawn: Position coordinates {x, y} for 2D or {x, y, z} for 3D
##   - handoff: null for normal entry (or token for cross-region transfers)
##
## Throws: Error if RPC fails
##
## Phase 2, Task: 2.1.2 - world_enter RPC (IMPLEMENTED ✅)
## Requirements: 2 (Character Selection), 4 (World Entry)
func enter_world(character_id: String) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot enter world: not authenticated")
		return {}

	print("[NakamaManager] Entering world with character: ", character_id)

	# Task 2.1.5: Store current character ID for zone_snapshot RPC
	current_character_id = character_id

	var payload = JSON.stringify({
		"character_id": character_id
	})

	var response = await client.rpc_async(session, "world_enter", payload)

	if response.is_exception():
		push_error("[NakamaManager] world_enter RPC failed: ", response.get_exception().message)
		return {}

	var data = JSON.parse_string(response.payload)
	var zone_id = data.get("zoneId", "unknown")
	var shard_id = data.get("shardId", "unknown")
	var spawn = data.get("spawn", {})

	print("[NakamaManager] Entered world. Shard: %s, Zone: %s, Spawn: (%f, %f, %f)" % [
		shard_id, zone_id, spawn.get("x", 0), spawn.get("y", 0), spawn.get("z", 0)
	])

	return data


## Join a zone and receive snapshot
##
## Parameters:
##   zone_id: Zone identifier to join
##   spawn_position: DEPRECATED - Server now calculates AOI from character position
##
## Phase 2, Task: 2.1.3 - zone_snapshot RPC (IMPLEMENTED ✅)
## Phase 2, Task: 2.1.5 - AOI seed calculation (UPDATED ✅)
## Requirements: 4 (World Entry and Zone Snapshot), 8 (AOI Management)
##
## Task 2.1.5: Updated to pass character_id instead of client-provided aoi_seed.
## Server now calculates AOI seed from character's position (server-authoritative).
func join_zone(zone_id: String, spawn_position: Variant = Vector2(0, 0)) -> void:
	if session == null:
		push_error("[NakamaManager] Cannot join zone: not authenticated")
		return
	
	if socket == null:
		push_error("[NakamaManager] Cannot join zone: socket is null")
		return
	
	# Check if socket is connected, if not try to reconnect
	if not socket.is_connected_to_host():
		print("[NakamaManager] Socket not connected, attempting to reconnect...")
		var reconnect_result = await socket.connect_async(session)
		if reconnect_result.is_exception():
			push_error("[NakamaManager] Socket reconnection failed: ", reconnect_result.get_exception().message)
			return
		print("[NakamaManager] Socket reconnected")

	if current_character_id == "":
		push_error("[NakamaManager] Cannot join zone: no character selected")
		return

	print("[NakamaManager] Joining zone: %s with character: %s" % [zone_id, current_character_id])

	# Task 2.1.5: Send character_id instead of aoi_seed
	# Server determines AOI seed from character position (server-authoritative)
	var snap_payload = JSON.stringify({
		"zone_id": zone_id,
		"character_id": current_character_id
	})

	var snap_response = await client.rpc_async(session, "zone_snapshot", snap_payload)

	if snap_response.is_exception():
		push_error("[NakamaManager] zone_snapshot RPC failed: ", snap_response.get_exception().message)
		return

	var snapshot_data = JSON.parse_string(snap_response.payload)
	var snapshot_blob = snapshot_data.get("snapshot_blob", "")
	var version = snapshot_data.get("version", 0)
	var compressed_size = snapshot_data.get("compressed_size", 0)
	var uncompressed_size = snapshot_data.get("uncompressed_size", 0)
	var match_id = snapshot_data.get("match_id", "")

	print("[NakamaManager] Received zone snapshot (version %d, %d KB compressed, %d KB uncompressed)" % [
		version, compressed_size / 1024, uncompressed_size / 1024
	])

	# Apply snapshot to world state (Task 2.4.1)
	WorldState.apply_snapshot(snapshot_blob)

	# Spawn the local player character entity
	# The snapshot only contains zone entities (NPCs, mobs, resources)
	# We need to spawn the player character separately using the spawn position
	print("[NakamaManager] Spawning player character entity: %s" % current_character_id)
	
	# Convert spawn_position to Vector2/Vector3 if it's a Dictionary
	var actual_spawn_position = spawn_position
	if spawn_position is Dictionary:
		var z_val = spawn_position.get("z", 0.0)
		if z_val != 0.0:
			# 3D position
			actual_spawn_position = Vector3(
				spawn_position.get("x", 0.0),
				spawn_position.get("y", 0.0),
				z_val
			)
		else:
			# 2D position
			actual_spawn_position = Vector2(
				spawn_position.get("x", 0.0),
				spawn_position.get("y", 0.0)
			)
	
	WorldState.spawn_player_character(current_character_id, actual_spawn_position, current_character_name)

	# Join zone match for delta streaming (Task 2.3.1)
	if match_id != "":
		print("[NakamaManager] Joining zone match: %s" % match_id)
		
		var match_joined = false
		var retry_count = 0
		var max_retries = 3
		
		while not match_joined and retry_count < max_retries:
			if not socket.is_connected_to_host():
				print("[NakamaManager] Socket disconnected, waiting for reconnection...")
				await get_tree().create_timer(1.0).timeout
				if not socket.is_connected_to_host():
					# Try explicit reconnect if still disconnected
					await socket.connect_async(session)
			
			var match_result = await socket.join_match_async(match_id)
			
			if match_result.is_exception():
				retry_count += 1
				push_warning("[NakamaManager] Failed to join zone match (attempt %d/%d): %s" % [retry_count, max_retries, match_result.get_exception().message])
				if retry_count < max_retries:
					await get_tree().create_timer(1.0).timeout
			else:
				match_joined = true
				current_match_id = match_id
				print("[NakamaManager] Successfully joined zone match for delta streaming")

				# Connect signal handler for match state updates (delta updates)
				if not socket.received_match_state.is_connected(_on_zone_delta_match):
					socket.received_match_state.connect(_on_zone_delta_match)
		
		if not match_joined:
			push_error("[NakamaManager] Failed to join zone match after %d attempts" % max_retries)
	else:
		push_warning("[NakamaManager] No match_id in snapshot response, delta streaming unavailable")

	print("[NakamaManager] Zone joined successfully")


## Handle zone delta updates from server (legacy stream-based)
##
## Phase 2, Task: 2.4.4 - Implement delta stream subscription
## Phase 2, Task: 2.4.5 - Implement delta application
##
## Signal handler for Nakama's received_stream_state signal.
## Receives real-time delta updates from the server and applies them to the world state.
##
## Parameters (from Nakama SDK):
##   stream: NakamaRTAPI.Stream object containing delta data
func _on_zone_delta(stream: NakamaRTAPI.Stream) -> void:
	# Parse delta data from stream
	var delta_json = stream.data.get_string_from_utf8()
	var delta_data = JSON.parse_string(delta_json)

	if delta_data == null or typeof(delta_data) != TYPE_DICTIONARY:
		push_warning("[NakamaManager] Invalid delta data received")
		return

	# Apply delta to world state (Task 2.4.5)
	WorldState.apply_delta(delta_data)


## Handle zone delta updates from match state (Task 2.3.1)
##
## Phase 2, Task: 2.3.1 - Implement zone delta stream via matches
## Phase 2, Task: 2.4.5 - Implement delta application
## Task 3.4: Added network metrics tracking (Requirement 4)
##
## Signal handler for Nakama's received_match_state signal.
## Receives real-time delta updates via match and applies them to the world state.
##
## Parameters (from Nakama SDK):
##   match_state: NakamaRTAPI.MatchData object containing delta data
func _on_zone_delta_match(match_state: NakamaRTAPI.MatchData) -> void:
	# Track network metrics (Task 3.4)
	var current_time = Time.get_ticks_msec()
	var delta_size = match_state.data.length()

	# Update delta interval tracking
	if network_metrics.last_delta_timestamp > 0:
		var interval = (current_time - network_metrics.last_delta_timestamp) / 1000.0  # Convert to seconds
		_delta_intervals.append(interval)

		# Keep only last N intervals
		if _delta_intervals.size() > _max_delta_intervals:
			_delta_intervals.pop_front()

		# Calculate average interval
		var sum = 0.0
		for i in _delta_intervals:
			sum += i
		network_metrics.average_delta_interval = sum / _delta_intervals.size()

	# Update metrics
	network_metrics.last_delta_size = delta_size
	network_metrics.total_deltas_received += 1
	network_metrics.total_bytes_received += delta_size
	network_metrics.last_delta_timestamp = current_time

	# Estimate latency (simple heuristic: half of average delta interval)
	# More accurate latency would require ping-pong messages with server timestamps
	if network_metrics.average_delta_interval > 0:
		network_metrics.estimated_latency = (network_metrics.average_delta_interval / 2.0) * 1000.0  # Convert to ms

	# Parse delta data from match state
	# Note: match_state.data is already a String in Nakama Godot SDK
	var delta_json: String
	delta_json = match_state.data

	var delta_data = JSON.parse_string(delta_json)

	if delta_data == null or typeof(delta_data) != TYPE_DICTIONARY:
		push_warning("[NakamaManager] Invalid delta data received from match")
		return

	# Log delta message (Task 8.2)
	var entity_count = 0
	if "entities" in delta_data:
		entity_count = delta_data.entities.size()
	_log_network("DELTA", "Received delta: %d bytes, %d entities, interval: %.3fs" % [
		delta_size, entity_count, network_metrics.average_delta_interval
	], delta_data)

	# Apply delta to world state (Task 2.4.5)
	WorldState.apply_delta(delta_data)


## ============================================================================
## MOVEMENT RPCs
## ============================================================================

## Nonce counter for move_intent deduplication
var _move_intent_nonce: int = 0

## Send player movement intent to server
##
## Parameters:
##   position: Current position Vector2(x, y) - used to calculate predicted position
##   velocity: Movement velocity Vector2(x, y) - used to derive direction
##
## Returns: void (fire-and-forget, server validates and sends delta updates)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 3 (Player Movement and Synchronization)
## Design: Network Communication - RPC Call Pattern
func move_intent(position: Vector2, velocity: Vector2) -> void:
	if session == null:
		push_error("[NakamaManager] Cannot send move_intent: not authenticated")
		return

	# Calculate normalized direction from velocity
	var direction = velocity.normalized() if velocity.length() > 0 else Vector2.ZERO
	
	# Increment nonce for deduplication
	_move_intent_nonce += 1
	
	var payload = JSON.stringify({
		"direction": {"x": direction.x, "y": direction.y},
		"timestamp": Time.get_ticks_msec(),
		"nonce": _move_intent_nonce,
		"predictedPosition": {"x": position.x, "y": position.y}
	})

	# Fire-and-forget RPC (no await needed, server responds via delta stream)
	client.rpc_async(session, "move_intent", payload)


## Send position update to zone match for delta streaming
##
## Parameters:
##   position: Current player position Vector2(x, y)
##
## Returns: void (fire-and-forget to match)
##
## Task: 2.3.1 - Delta Streaming via Matches
## Requirement: 8 (AOI Management and Delta Streaming)
##
## Sends position updates to the zone match so other players can see this player move
func send_match_position(position: Vector2) -> void:
	if socket == null or not socket.is_connected_to_host():
		return
	
	if current_match_id == "":
		return
	
	var payload = JSON.stringify({
		"position": {"x": position.x, "y": position.y, "z": 0.0}
	})
	
	# Send as match data message (opcode 2 for position updates)
	socket.send_match_state_async(current_match_id, 2, payload)


## ============================================================================
## COMBAT RPCs
## ============================================================================

## Use an ability on a target
##
## Parameters:
##   ability_id: Ability identifier (e.g., "fireball")
##   target_id: Target entity ID (can be empty for self/ground-targeted)
##   position: Ability cast position Vector2(x, y)
##
## Returns: Ability result dictionary with:
##   - success: bool
##   - ability_id: string
##   - damage_dealt: int
##   - critical: bool
##   - effects: array of effect dictionaries
##   - cooldown: float (seconds)
##   - mana_cost: int
##   - targets_hit: array of entity IDs
##
## Task: 1.1 - RPC Wrappers
## Requirement: 5 (Combat and Ability System)
## Design: Combat System
func use_ability(ability_id: String, target_id: String, position: Vector2) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot use ability: not authenticated")
		return {}

	print("[NakamaManager] Using ability '%s' on target '%s'" % [ability_id, target_id])

	var payload = JSON.stringify({
		"ability_id": ability_id,
		"target_id": target_id,
		"position": {"x": position.x, "y": position.y}
	})

	var response = await client.rpc_async(session, "use_ability", payload)

	if response.is_exception():
		push_error("[NakamaManager] use_ability RPC failed: ", response.get_exception().message)
		return {"success": false, "error": response.get_exception().message}

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] use_ability returned error: ", data.error)
		return {"success": false, "error": data.error}

	print("[NakamaManager] Ability used successfully")
	return data


## ============================================================================
## INVENTORY RPCs
## ============================================================================

## Move item between inventory slots
##
## Parameters:
##   from_slot: Source slot index (0-49)
##   to_slot: Target slot index (0-49)
##
## Returns: bool (true if successful, false if failed)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 6 (Inventory Management)
## Design: Inventory System
func inventory_move(from_slot: int, to_slot: int) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot move inventory item: not authenticated")
		return false

	print("[NakamaManager] Moving item from slot %d to slot %d" % [from_slot, to_slot])

	var payload = JSON.stringify({
		"from_slot": from_slot,
		"to_slot": to_slot
	})

	var response = await client.rpc_async(session, "inventory_move", payload)

	if response.is_exception():
		push_error("[NakamaManager] inventory_move RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] inventory_move returned error: ", data.error)
		return false

	print("[NakamaManager] Item moved successfully")
	return data.get("success", false)


## Create item in inventory (debug/admin function)
##
## Parameters:
##   item_template_id: Item template identifier (e.g., "sword_iron")
##
## Returns: Item dictionary with:
##   - id: string (item instance ID)
##   - template_id: string
##   - name: string
##   - rarity: string
##   - slot_index: int
##   - stack_count: int
##   - stats: dictionary
##
## Task: 1.1 - RPC Wrappers
## Requirement: 6 (Inventory Management)
## Design: Inventory System
func inventory_create_item(item_template_id: String) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot create item: not authenticated")
		return {}

	print("[NakamaManager] Creating item with template '%s'" % item_template_id)

	var payload = JSON.stringify({
		"item_template_id": item_template_id
	})

	var response = await client.rpc_async(session, "inventory_create_item", payload)

	if response.is_exception():
		push_error("[NakamaManager] inventory_create_item RPC failed: ", response.get_exception().message)
		return {}

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] inventory_create_item returned error: ", data.error)
		return {}

	print("[NakamaManager] Item created successfully: ", data.get("name", "Unknown"))
	return data


## ============================================================================
## TRADING RPCs
## ============================================================================

## Open trade session with another player
##
## Parameters:
##   target_player_id: User ID of player to trade with
##
## Returns: Trade session ID string (or empty string if failed)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 7 (Player Trading System)
## Design: Trade System - 2PC (Two-Phase Commit)
func trade_open(target_player_id: String) -> String:
	if session == null:
		push_error("[NakamaManager] Cannot open trade: not authenticated")
		return ""

	print("[NakamaManager] Opening trade with player '%s'" % target_player_id)

	var payload = JSON.stringify({
		"target_player_id": target_player_id
	})

	var response = await client.rpc_async(session, "trade_open", payload)

	if response.is_exception():
		push_error("[NakamaManager] trade_open RPC failed: ", response.get_exception().message)
		return ""

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] trade_open returned error: ", data.error)
		return ""

	var session_id = data.get("session_id", "")
	print("[NakamaManager] Trade session opened: ", session_id)
	return session_id


## Add item to trade session
##
## Parameters:
##   session_id: Trade session identifier
##   item_id: Item instance ID to add to trade
##
## Returns: bool (true if successful)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 7 (Player Trading System)
## Design: Trade System - 2PC
func trade_add_item(session_id: String, item_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot add trade item: not authenticated")
		return false

	print("[NakamaManager] Adding item '%s' to trade session '%s'" % [item_id, session_id])

	var payload = JSON.stringify({
		"session_id": session_id,
		"item_id": item_id
	})

	var response = await client.rpc_async(session, "trade_add_item", payload)

	if response.is_exception():
		push_error("[NakamaManager] trade_add_item RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] trade_add_item returned error: ", data.error)
		return false

	print("[NakamaManager] Item added to trade successfully")
	return data.get("success", false)


## Lock trade (confirm items, ready for commit)
##
## Parameters:
##   session_id: Trade session identifier
##
## Returns: bool (true if successfully locked)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 7 (Player Trading System)
## Design: Trade System - 2PC Phase 1
func trade_lock(session_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot lock trade: not authenticated")
		return false

	print("[NakamaManager] Locking trade session '%s'" % session_id)

	var payload = JSON.stringify({
		"session_id": session_id
	})

	var response = await client.rpc_async(session, "trade_lock", payload)

	if response.is_exception():
		push_error("[NakamaManager] trade_lock RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] trade_lock returned error: ", data.error)
		return false

	print("[NakamaManager] Trade locked successfully")
	return data.get("success", false)


## Commit trade (execute 2PC transaction)
##
## Parameters:
##   session_id: Trade session identifier
##
## Returns: bool (true if trade completed successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 7 (Player Trading System)
## Design: Trade System - 2PC Phase 2
func trade_commit(session_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot commit trade: not authenticated")
		return false

	print("[NakamaManager] Committing trade session '%s'" % session_id)

	var payload = JSON.stringify({
		"session_id": session_id
	})

	var response = await client.rpc_async(session, "trade_commit", payload)

	if response.is_exception():
		push_error("[NakamaManager] trade_commit RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] trade_commit returned error: ", data.error)
		return false

	print("[NakamaManager] Trade committed successfully")
	return data.get("success", false)


## Cancel trade session
##
## Parameters:
##   session_id: Trade session identifier
##
## Returns: bool (true if cancelled successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 7 (Player Trading System)
## Design: Trade System - Cancellation
func trade_cancel(session_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot cancel trade: not authenticated")
		return false

	print("[NakamaManager] Cancelling trade session '%s'" % session_id)

	var payload = JSON.stringify({
		"session_id": session_id
	})

	var response = await client.rpc_async(session, "trade_cancel", payload)

	if response.is_exception():
		push_error("[NakamaManager] trade_cancel RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] trade_cancel returned error: ", data.error)
		return false

	print("[NakamaManager] Trade cancelled successfully")
	return data.get("success", false)


## ============================================================================
## VENDOR RPCs
## ============================================================================

## Get vendor catalog (items for sale)
##
## Parameters:
##   vendor_id: NPC vendor identifier
##
## Returns: Array of vendor item dictionaries with:
##   - item_template_id: string
##   - name: string
##   - price: int
##   - stock: int (-1 for unlimited)
##   - rarity: string
##
## Task: 1.1 - RPC Wrappers
## Requirement: 8 (Vendor Interactions)
## Design: Vendor System
func get_vendor_catalog(vendor_id: String) -> Array:
	if session == null:
		push_error("[NakamaManager] Cannot get vendor catalog: not authenticated")
		return []

	print("[NakamaManager] Getting catalog for vendor '%s'" % vendor_id)

	var payload = JSON.stringify({
		"vendor_id": vendor_id
	})

	var response = await client.rpc_async(session, "get_vendor_catalog", payload)

	if response.is_exception():
		push_error("[NakamaManager] get_vendor_catalog RPC failed: ", response.get_exception().message)
		return []

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] get_vendor_catalog returned error: ", data.error)
		return []

	var catalog = data.get("catalog", [])
	print("[NakamaManager] Vendor catalog loaded: %d items" % catalog.size())
	return catalog


## Buy item from vendor
##
## Parameters:
##   vendor_id: NPC vendor identifier
##   item_id: Item template ID to purchase
##
## Returns: bool (true if purchase successful)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 8 (Vendor Interactions)
## Design: Vendor System
func vendor_buy(vendor_id: String, item_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot buy from vendor: not authenticated")
		return false

	print("[NakamaManager] Buying item '%s' from vendor '%s'" % [item_id, vendor_id])

	var payload = JSON.stringify({
		"vendor_id": vendor_id,
		"item_id": item_id
	})

	var response = await client.rpc_async(session, "vendor_buy", payload)

	if response.is_exception():
		push_error("[NakamaManager] vendor_buy RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] vendor_buy returned error: ", data.error)
		return false

	print("[NakamaManager] Item purchased successfully")
	return data.get("success", false)


## Sell item to vendor
##
## Parameters:
##   vendor_id: NPC vendor identifier
##   item_id: Item instance ID to sell
##
## Returns: Sale result dictionary with:
##   - success: bool
##   - currency_received: int
##
## Task: 1.1 - RPC Wrappers
## Requirement: 8 (Vendor Interactions)
## Design: Vendor System
func vendor_sell(vendor_id: String, item_id: String) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot sell to vendor: not authenticated")
		return {}

	print("[NakamaManager] Selling item '%s' to vendor '%s'" % [item_id, vendor_id])

	var payload = JSON.stringify({
		"vendor_id": vendor_id,
		"item_id": item_id
	})

	var response = await client.rpc_async(session, "vendor_sell", payload)

	if response.is_exception():
		push_error("[NakamaManager] vendor_sell RPC failed: ", response.get_exception().message)
		return {"success": false}

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] vendor_sell returned error: ", data.error)
		return {"success": false, "error": data.error}

	print("[NakamaManager] Item sold successfully for %d currency" % data.get("currency_received", 0))
	return data


## ============================================================================
## LOOT RPCs
## ============================================================================

## Generate loot from NPC template
##
## Parameters:
##   npc_template_id: NPC template identifier (e.g., "goblin_warrior")
##
## Returns: Array of generated item dictionaries
##
## Task: 1.1 - RPC Wrappers
## Requirement: 9 (Loot Generation and Drops)
## Design: Loot System
func generate_loot(npc_template_id: String) -> Array:
	if session == null:
		push_error("[NakamaManager] Cannot generate loot: not authenticated")
		return []

	print("[NakamaManager] Generating loot for NPC template '%s'" % npc_template_id)

	var payload = JSON.stringify({
		"npc_template_id": npc_template_id
	})

	var response = await client.rpc_async(session, "generate_loot", payload)

	if response.is_exception():
		push_error("[NakamaManager] generate_loot RPC failed: ", response.get_exception().message)
		return []

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] generate_loot returned error: ", data.error)
		return []

	var loot_items = data.get("loot", [])
	print("[NakamaManager] Generated %d loot item(s)" % loot_items.size())
	return loot_items


## ============================================================================
## GUILD RPCs
## ============================================================================

## Create new guild
##
## Parameters:
##   name: Guild name
##   tag: Guild tag (2-4 characters)
##
## Returns: Guild dictionary with:
##   - guild_id: string
##   - name: string
##   - tag: string
##   - leader_id: string
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_create(name: String, tag: String) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot create guild: not authenticated")
		return {}

	print("[NakamaManager] Creating guild '%s' [%s]" % [name, tag])

	var payload = JSON.stringify({
		"name": name,
		"tag": tag
	})

	var response = await client.rpc_async(session, "guild_create", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_create RPC failed: ", response.get_exception().message)
		return {}

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_create returned error: ", data.error)
		return {}

	print("[NakamaManager] Guild created successfully: ", data.get("guild_id", "Unknown"))
	return data


## Invite player to guild
##
## Parameters:
##   player_id: User ID of player to invite
##
## Returns: bool (true if invite sent successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_invite(player_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot send guild invite: not authenticated")
		return false

	print("[NakamaManager] Inviting player '%s' to guild" % player_id)

	var payload = JSON.stringify({
		"player_id": player_id
	})

	var response = await client.rpc_async(session, "guild_invite", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_invite RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_invite returned error: ", data.error)
		return false

	print("[NakamaManager] Guild invite sent successfully")
	return data.get("success", false)


## Join guild (accept invite)
##
## Parameters:
##   guild_id: Guild identifier to join
##
## Returns: bool (true if joined successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_join(guild_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot join guild: not authenticated")
		return false

	print("[NakamaManager] Joining guild '%s'" % guild_id)

	var payload = JSON.stringify({
		"guild_id": guild_id
	})

	var response = await client.rpc_async(session, "guild_join", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_join RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_join returned error: ", data.error)
		return false

	print("[NakamaManager] Joined guild successfully")
	return data.get("success", false)


## Set member rank in guild
##
## Parameters:
##   member_id: User ID of guild member
##   rank_id: Rank identifier (0 = leader, 1 = officer, 2 = member)
##
## Returns: bool (true if rank set successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_set_rank(member_id: String, rank_id: int) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot set guild rank: not authenticated")
		return false

	print("[NakamaManager] Setting rank %d for member '%s'" % [rank_id, member_id])

	var payload = JSON.stringify({
		"member_id": member_id,
		"rank_id": rank_id
	})

	var response = await client.rpc_async(session, "guild_set_rank", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_set_rank RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_set_rank returned error: ", data.error)
		return false

	print("[NakamaManager] Member rank set successfully")
	return data.get("success", false)


## Kick member from guild
##
## Parameters:
##   member_id: User ID of guild member to kick
##
## Returns: bool (true if kicked successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_kick(member_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot kick guild member: not authenticated")
		return false

	print("[NakamaManager] Kicking member '%s' from guild" % member_id)

	var payload = JSON.stringify({
		"member_id": member_id
	})

	var response = await client.rpc_async(session, "guild_kick", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_kick RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_kick returned error: ", data.error)
		return false

	print("[NakamaManager] Member kicked successfully")
	return data.get("success", false)


## Set guild message of the day
##
## Parameters:
##   message: MOTD text
##
## Returns: bool (true if MOTD set successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_set_motd(message: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot set guild MOTD: not authenticated")
		return false

	print("[NakamaManager] Setting guild MOTD")

	var payload = JSON.stringify({
		"message": message
	})

	var response = await client.rpc_async(session, "guild_set_motd", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_set_motd RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_set_motd returned error: ", data.error)
		return false

	print("[NakamaManager] Guild MOTD set successfully")
	return data.get("success", false)


## Deposit item into guild storage
##
## Parameters:
##   item_id: Item instance ID to deposit
##
## Returns: bool (true if deposited successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_storage_deposit(item_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot deposit to guild storage: not authenticated")
		return false

	print("[NakamaManager] Depositing item '%s' to guild storage" % item_id)

	var payload = JSON.stringify({
		"item_id": item_id
	})

	var response = await client.rpc_async(session, "guild_storage_deposit", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_storage_deposit RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_storage_deposit returned error: ", data.error)
		return false

	print("[NakamaManager] Item deposited to guild storage successfully")
	return data.get("success", false)


## Withdraw item from guild storage
##
## Parameters:
##   item_id: Item instance ID to withdraw
##
## Returns: bool (true if withdrawn successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 10 (Guild Management)
## Design: Guild System
func guild_storage_withdraw(item_id: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot withdraw from guild storage: not authenticated")
		return false

	print("[NakamaManager] Withdrawing item '%s' from guild storage" % item_id)

	var payload = JSON.stringify({
		"item_id": item_id
	})

	var response = await client.rpc_async(session, "guild_storage_withdraw", payload)

	if response.is_exception():
		push_error("[NakamaManager] guild_storage_withdraw RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] guild_storage_withdraw returned error: ", data.error)
		return false

	print("[NakamaManager] Item withdrawn from guild storage successfully")
	return data.get("success", false)


## ============================================================================
## CHAT/SOCIAL RPCs
## ============================================================================

## Send chat message to channel
##
## Parameters:
##   message: Message text
##   channel: Channel name ("zone", "guild", "party", etc.)
##
## Returns: bool (true if message sent successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 11 (Chat Systems)
## Design: Chat System
func chat_send(message: String, channel: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot send chat message: not authenticated")
		return false

	print("[NakamaManager] Sending message to channel '%s'" % channel)

	var payload = JSON.stringify({
		"message": message,
		"channel": channel
	})

	var response = await client.rpc_async(session, "chat_send", payload)

	if response.is_exception():
		push_error("[NakamaManager] chat_send RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] chat_send returned error: ", data.error)
		return false

	print("[NakamaManager] Chat message sent successfully")
	return data.get("success", false)


## Send direct message to player
##
## Parameters:
##   recipient_id: User ID of recipient
##   message: Message text
##
## Returns: bool (true if message sent successfully)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 11 (Chat Systems)
## Design: Chat System
func send_direct_message(recipient_id: String, message: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot send direct message: not authenticated")
		return false

	print("[NakamaManager] Sending direct message to '%s'" % recipient_id)

	var payload = JSON.stringify({
		"recipient_id": recipient_id,
		"message": message
	})

	var response = await client.rpc_async(session, "send_direct_message", payload)

	if response.is_exception():
		push_error("[NakamaManager] send_direct_message RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] send_direct_message returned error: ", data.error)
		return false

	print("[NakamaManager] Direct message sent successfully")
	return data.get("success", false)


## Moderate player (mute, kick, ban)
##
## Parameters:
##   target_id: User ID of player to moderate
##   action: Moderation action ("mute", "kick", "ban")
##
## Returns: bool (true if moderation action successful)
##
## Task: 1.1 - RPC Wrappers
## Requirement: 11 (Chat Systems)
## Design: Chat System
func moderate_player(target_id: String, action: String) -> bool:
	if session == null:
		push_error("[NakamaManager] Cannot moderate player: not authenticated")
		return false

	print("[NakamaManager] Moderating player '%s' with action '%s'" % [target_id, action])

	var payload = JSON.stringify({
		"target_id": target_id,
		"action": action
	})

	var response = await client.rpc_async(session, "moderate_player", payload)

	if response.is_exception():
		push_error("[NakamaManager] moderate_player RPC failed: ", response.get_exception().message)
		return false

	var data = JSON.parse_string(response.payload)

	if "error" in data:
		push_warning("[NakamaManager] moderate_player returned error: ", data.error)
		return false

	print("[NakamaManager] Player moderated successfully")
	return data.get("success", false)


## ============================================================================
## NETWORK METRICS (Task 3.4)
## ============================================================================

## Get current network metrics for delta stream
##
## Returns: Dictionary with network statistics:
##   - last_delta_size: Size of last delta message in bytes
##   - total_deltas_received: Total number of delta messages received
##   - total_bytes_received: Total bytes received from deltas
##   - last_delta_timestamp: Timestamp of last delta (msec)
##   - average_delta_interval: Average time between deltas (seconds)
##   - estimated_latency: Estimated round-trip latency (milliseconds)
##
## Task 3.4: Network metrics tracking (Requirement 4)
func get_network_metrics() -> Dictionary:
	return network_metrics.duplicate()


## Get estimated latency in milliseconds
##
## Returns: float - Estimated round-trip latency in milliseconds
##
## Note: This is a heuristic estimate based on delta intervals.
## For accurate latency, server would need to include timestamps in deltas.
##
## Task 3.4: Network metrics tracking (Requirement 4)
func get_latency() -> float:
	return network_metrics.estimated_latency


## Reset network metrics (useful for testing or zone transitions)
##
## Task 3.4: Network metrics tracking (Requirement 4)
func reset_network_metrics() -> void:
	network_metrics = {
		"last_delta_size": 0,
		"total_deltas_received": 0,
		"total_bytes_received": 0,
		"last_delta_timestamp": 0,
		"average_delta_interval": 0.0,
		"estimated_latency": 0.0
	}
	_delta_intervals.clear()
	print("[NakamaManager] Network metrics reset")


## Socket event handlers for connection monitoring
func _on_socket_connected() -> void:
	print("[NakamaManager] Socket connected successfully")


func _on_socket_closed() -> void:
	push_warning("[NakamaManager] Socket connection closed. Attempting to reconnect...")
	if session != null and socket != null:
		var reconnect_result = await socket.connect_async(session)
		if reconnect_result.is_exception():
			push_error("[NakamaManager] Socket reconnection failed: ", reconnect_result.get_exception().message)
		else:
			print("[NakamaManager] Socket reconnected successfully")


func _on_socket_error(error) -> void:
	push_error("[NakamaManager] Socket error: ", str(error))
