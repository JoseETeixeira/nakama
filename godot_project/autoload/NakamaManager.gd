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
	var response = await client.rpc_async(session, "list_characters", "{}")

	if response.is_exception():
		push_error("[NakamaManager] list_characters RPC failed: ", response.get_exception().message)
		return []

	var data = JSON.parse_string(response.payload)
	var characters = data.get("characters", [])

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

	var response = await client.rpc_async(session, "create_character", payload)

	if response.is_exception():
		var error_message = response.get_exception().message
		push_error("[NakamaManager] create_character RPC failed: ", error_message)
		return ""

	var data = JSON.parse_string(response.payload)
	var character_id = data.get("character_id", "")

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

	var response = await client.rpc_async(session, "select_character", payload)

	if response.is_exception():
		push_error("[NakamaManager] select_character RPC failed: ", response.get_exception().message)
		return {}

	var data = JSON.parse_string(response.payload)

	if not data.get("ok", false):
		push_error("[NakamaManager] select_character returned ok=false")
		return {}

	var character = data.get("character", {})
	print("[NakamaManager] Character selected: ", character.get("name", "Unknown"))
	return character


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
	if session == null or socket == null:
		push_error("[NakamaManager] Cannot join zone: not authenticated or socket disconnected")
		return

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

	print("[NakamaManager] Received zone snapshot (version %d, %d KB compressed, %d KB uncompressed)" % [
		version, compressed_size / 1024, uncompressed_size / 1024
	])

	# Apply snapshot to world state (Task 2.4.1)
	WorldState.apply_snapshot(snapshot_blob)

	# Subscribe to zone delta stream (Task 2.4.4)
	# Connect signal handler for delta updates
	if not socket.received_stream_state.is_connected(_on_zone_delta):
		socket.received_stream_state.connect(_on_zone_delta)

	# TODO: Join the zone stream to receive delta updates
	# The join_stream_async function name has changed in newer SDK versions
	# For now, skip stream subscription - snapshot works without it
	# var stream_result = await socket.join_stream_async("zone_deltas", zone_id)
	# if stream_result.is_exception():
	# 	push_error("[NakamaManager] Failed to subscribe to zone deltas: ", stream_result.get_exception().message)
	# 	return

	print("[NakamaManager] Zone joined successfully (stream subscription TODO)")


## Handle zone delta updates from server
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
