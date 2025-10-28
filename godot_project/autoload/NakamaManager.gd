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
## Returns: Zone entry data (zone_id, shard_id, spawn_position)
## Throws: Error if RPC fails
##
## Phase 2, Task: 2.1.2 - Implement world_enter RPC
func enter_world(character_id: String) -> Dictionary:
	if session == null:
		push_error("[NakamaManager] Cannot enter world: not authenticated")
		return {}

	print("[NakamaManager] Entering world with character: ", character_id)

	var payload = JSON.stringify({
		"character_id": character_id
	})

	# TODO: Phase 2 - This RPC will be implemented in Task 2.1.2
	var response = await client.rpc_async(session, "world_enter", payload)

	if response.is_exception():
		push_error("[NakamaManager] world_enter RPC failed: ", response.get_exception().message)
		return {}

	var data = JSON.parse_string(response.payload)
	print("[NakamaManager] Entered world. Zone: ", data.get("zone_id", "unknown"))
	return data


## Join a zone and receive snapshot
##
## Parameters:
##   zone_id: Zone identifier to join
##
## Phase 2, Task: 2.1.3 - Implement zone snapshot generation
func join_zone(zone_id: String) -> void:
	if session == null or socket == null:
		push_error("[NakamaManager] Cannot join zone: not authenticated or socket disconnected")
		return

	print("[NakamaManager] Joining zone: ", zone_id)

	# Request zone snapshot
	var snap_payload = JSON.stringify({
		"zone_id": zone_id,
		"aoi_seed": [0, 0, 0] # Player's initial position
	})

	# TODO: Phase 2 - This RPC will be implemented in Task 2.1.3
	var snap_response = await client.rpc_async(session, "zone_snapshot", snap_payload)

	if snap_response.is_exception():
		push_error("[NakamaManager] zone_snapshot RPC failed: ", snap_response.get_exception().message)
		return

	var snapshot_data = JSON.parse_string(snap_response.payload)
	var snapshot_blob = snapshot_data.get("snapshot_blob", "")

	# Apply snapshot to world state
	WorldState.apply_snapshot(snapshot_blob)

	# Subscribe to zone delta stream
	socket.received_stream_state.connect(_on_zone_delta)
	var stream_result = await socket.send_match_state_async(zone_id, 0, "")

	if stream_result.is_exception():
		push_error("[NakamaManager] Failed to subscribe to zone deltas: ", stream_result.get_exception().message)
		return

	print("[NakamaManager] Subscribed to zone delta stream")


## Handle zone delta updates from server
##
## Phase 2, Task: 2.3.1 - Implement zone delta stream
func _on_zone_delta(stream: NakamaRTAPI.Stream) -> void:
	var delta_data = JSON.parse_string(stream.data.get_string_from_utf8())
	WorldState.apply_delta(delta_data)
