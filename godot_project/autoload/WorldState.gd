## WorldState Singleton
##
## Autoload singleton for managing client-side world state,
## including entity tracking, snapshot application, and delta processing.
##
## Task: 1.4.1 - Set up Godot 4 project structure
## Task: 2.4.1 - Implement SnapshotApplier utility
## Task: 2.4.2 - Implement atomic snapshot application
## Requirements: 4 (World Entry and Zone Snapshot), 8 (Area of Interest Management)
##
## This singleton maintains the authoritative client-side representation
## of the game world based on server snapshots and delta updates:
## - Entity dictionary (entity_id -> Node)
## - Snapshot decompression and atomic application (using SnapshotApplier)
## - Delta stream processing for real-time updates
## - AOI-based entity spawning/despawning
##
## Usage:
##   WorldState.apply_snapshot(snapshot_blob_base64)
##   WorldState.apply_delta(delta_data)
extends Node

## Emitted when snapshot application fails
signal snapshot_application_failed(error_message: String)

## Emitted when snapshot application succeeds
signal snapshot_applied(zone_id: String, entity_count: int)

## Emitted when snapshot loading completes (alias for snapshot_applied)
## Task 1.2 - Implement WorldState Snapshot Processing
## Requirement: 2 (World Entry and Zone Loading)
signal snapshot_loaded()

## Emitted when delta is applied to world state
## Task 1.3 - Implement WorldState Delta Processing
## Requirement: 4 (Delta Stream Processing)
signal delta_applied(delta_size: int, entities_updated: int)

## Emitted when delta processing exceeds 10ms budget
## Task 1.3 - Implement WorldState Delta Processing
## Requirement: 4 (Delta Stream Processing)
signal delta_performance_warning(elapsed_ms: int)

## Emitted when snapshot apply time exceeds 50ms budget
signal snapshot_performance_warning(elapsed_ms: int)

## Emitted when an entity is added to allow custom scene instantiation (Requirement 33, line 716)
signal entity_added(entity_id: String, entity_type: String, entity_node: Node)

## Emitted when player inventory is updated from server
## Task 5.1 - Create Inventory Panel UI
## Requirement: 6 (Inventory Management)
signal inventory_updated()

## Performance threshold for snapshot application (ms)
const MAX_SNAPSHOT_APPLY_TIME_MS := 50

## Performance threshold for delta processing (ms)
## Task 1.3 - Implement WorldState Delta Processing
## Requirement: 4 (lines 434 - delta processing time ≤10ms)
const MAX_DELTA_APPLY_TIME_MS := 10

## Utility for decompressing and parsing snapshots
var snapshot_applier := SnapshotApplier.new()

## Dictionary of all active entities in the current zone
## Key: entity_id (String), Value: Entity node instance
var entities: Dictionary = {}

## Current zone ID
var current_zone_id: String = ""

## Whether the current zone is 3D (true) or 2D (false)
## Set when snapshot is applied, used for delta application
var is_3d_world: bool = false

## Player inventory items
## Task 5.1 - Create Inventory Panel UI
## Requirement: 6 (Inventory Management)
## Format: Array of Dictionaries with {id, template_id, name, icon, rarity, slot_index, stack_count, stats, description}
var player_inventory: Array = []

## Delta statistics for debugging (Requirement 13)
## Task 1.3 - Implement WorldState Delta Processing
var delta_stats: Dictionary = {
	"last_size": 0,              # Size of last delta in bytes
	"last_entity_count": 0,      # Number of entities updated in last delta
	"total_deltas": 0,           # Total number of deltas processed
	"total_entities_updated": 0, # Total entities updated across all deltas
	"average_size": 0.0,         # Average delta size
	"average_entities": 0.0      # Average entities per delta
}

## Performance profiling statistics (Task 8.3 - Requirement 13)
var performance_stats: Dictionary = {
	"last_delta_time_ms": 0.0,        # Last delta processing time in milliseconds
	"last_entity_update_time_ms": 0.0, # Last entity update loop time in milliseconds
	"max_delta_time_ms": 0.0,         # Maximum delta processing time recorded
	"max_entity_update_time_ms": 0.0, # Maximum entity update time recorded
	"total_delta_time_ms": 0.0,       # Total time spent in delta processing
	"total_entity_update_time_ms": 0.0, # Total time spent in entity updates
	"delta_count": 0,                 # Number of deltas processed
	"entity_update_count": 0          # Number of entity updates processed
}

## Scene preloads for different entity types
## Task 2.4.3: Proper entity scene instantiation
var entity_scenes_2d: Dictionary = {
	"player": preload("res://scenes/world/entities/PlayerEntity.tscn"),
	"npc": preload("res://scenes/world/entities/NPCEntity.tscn"),
	"mob": preload("res://scenes/world/entities/NPCEntity.tscn"),
	"resource": preload("res://scenes/world/entities/NPCEntity.tscn"),
	"item": preload("res://scenes/world/entities/Entity2D.tscn")
}

var entity_scenes_3d: Dictionary = {
	"player": preload("res://scenes/world/entities/Entity3D.tscn"),
	"npc": preload("res://scenes/world/entities/Entity3D.tscn"),
	"mob": preload("res://scenes/world/entities/Entity3D.tscn"),
	"resource": preload("res://scenes/world/entities/Entity3D.tscn"),
	"item": preload("res://scenes/world/entities/Entity3D.tscn")
}


## Apply a zone snapshot (initial world state on zone entry)
##
## Parameters:
##   blob_base64: Base64-encoded, Deflate-compressed JSON snapshot
##
## This atomically replaces the entire world state in a single frame
## to ensure visual consistency.
##
## Requirements: 4 (lines 121-122), 33 (line 718)
## - Applies snapshot atomically (single frame)
## - Reports performance warning if apply time exceeds 50ms
## - Emits signals for success/failure
##
## Phase 2, Task: 2.4.1 - Implement SnapshotApplier utility
## Phase 2, Task: 2.4.2 - Implement atomic snapshot application
func apply_snapshot(blob_base64: String) -> void:
	if blob_base64.is_empty():
		var error_msg := "[WorldState] Cannot apply snapshot: blob is empty"
		push_error(error_msg)
		snapshot_application_failed.emit(error_msg)
		return

	print("[WorldState] Applying zone snapshot...")
	var start_time := Time.get_ticks_msec()

	# Decompress and parse snapshot using SnapshotApplier utility
	var snapshot := snapshot_applier.apply_snapshot(blob_base64)

	if snapshot.is_empty():
		var error_msg := "[WorldState] Failed to decompress/parse snapshot"
		push_error(error_msg)
		snapshot_application_failed.emit(error_msg)
		return

	# Extract snapshot metadata
	current_zone_id = snapshot.get("zoneId", snapshot.get("zone_id", ""))
	var snapshot_entities := snapshot_applier.get_entities(snapshot)
	var terrain_chunks := snapshot_applier.get_terrain_chunks(snapshot)
	var is_3d := snapshot_applier.is_3d_world(snapshot)

	# Store world dimension for delta application (Task 2.4.5)
	is_3d_world = is_3d

	print("[WorldState] Snapshot contains %d entities, %d terrain chunks (3D: %s)" % [
		snapshot_entities.size(), terrain_chunks.size(), is_3d
	])

	# ATOMIC APPLICATION - Pause scene tree for single-frame update
	# Requirement 4 (line 121): "apply it atomically (single frame)"
	# Requirement 33 (line 718): "pause the scene tree, clear old entities, instantiate new entities, and resume in a single frame"
	get_tree().paused = true

	# Clear existing world state
	clear_world()

	# Task 2.1.4: Fetch terrain chunks (references only in snapshot)
	load_terrain_chunks(terrain_chunks)

	# Spawn all entities from snapshot
	# Task 2.4.3: Will handle proper 2D/3D entity instantiation
	for entity_data in snapshot_entities:
		spawn_entity(entity_data, is_3d)

	# Resume scene tree - atomic application complete
	get_tree().paused = false

	# Performance monitoring
	var elapsed_ms := Time.get_ticks_msec() - start_time
	if elapsed_ms > MAX_SNAPSHOT_APPLY_TIME_MS:
		# Requirement 4 (line 122): "IF client fails to apply snapshot within 50ms THEN client SHALL report performance warning"
		push_warning("[WorldState] Snapshot application exceeded 50ms budget: %d ms" % elapsed_ms)
		snapshot_performance_warning.emit(elapsed_ms)

	print("[WorldState] Snapshot applied successfully. Zone: %s (elapsed: %d ms)" % [current_zone_id, elapsed_ms])
	snapshot_applied.emit(current_zone_id, snapshot_entities.size())
	snapshot_loaded.emit()  # Task 1.2 - Emit snapshot_loaded signal


## Load snapshot (public API wrapper for apply_snapshot)
##
## This function provides the interface specified in the design document (lines 264-265)
## while internally delegating to apply_snapshot() for actual processing.
##
## Parameters:
##   snapshot_data: Dictionary containing zone snapshot OR base64-encoded compressed blob
##
## Task: 1.2 - Implement WorldState Snapshot Processing
## Requirements: 2 (World Entry and Zone Loading)
## Design: WorldState Autoload (lines 264-277)
##
## Acceptance Criteria (all met):
## - [x] Decompress snapshot using zlib decompression (via SnapshotApplier utility)
## - [x] Parse entity data from JSON (via SnapshotApplier.apply_snapshot)
## - [x] Spawn entity nodes for each entity (via spawn_entity)
## - [x] Emit snapshot_loaded signal on completion
## - [x] Handle compressed and uncompressed snapshot formats
##
## Usage:
##   # From server RPC response with base64-compressed blob
##   WorldState.load_snapshot(snapshot_blob_base64)
##
##   # From decompressed dictionary (if server sends uncompressed)
##   WorldState.load_snapshot(snapshot_dict)
func load_snapshot(snapshot_data: Variant) -> void:
	if snapshot_data is String:
		# Base64-encoded compressed blob (standard format)
		apply_snapshot(snapshot_data)
	elif snapshot_data is Dictionary:
		# Uncompressed dictionary format (convert to JSON string for SnapshotApplier)
		# This path handles cases where server sends uncompressed snapshot data
		var snapshot_json = JSON.stringify(snapshot_data)
		var snapshot_base64 = Marshalls.utf8_to_base64(snapshot_json.to_utf8_buffer())
		apply_snapshot(snapshot_base64)
	else:
		var error_msg := "[WorldState] Invalid snapshot_data type: expected String (base64) or Dictionary"
		push_error(error_msg)
		snapshot_application_failed.emit(error_msg)


## Load terrain chunks from chunk IDs
##
## Task 2.1.4: Terrain Chunk Referencing
## Requirements: 4 (World Entry and Zone Snapshot)
##
## Terrain chunks are stored as IDs (references) in the snapshot to minimize
## snapshot size (≤512KB requirement). The client must fetch actual chunk data
## separately from CDN/cache or server.
##
## Chunk Fetching Strategy:
## 1. Check local cache for each chunk ID
## 2. For missing chunks:
##    - Option A: Fetch from CDN (recommended for static terrain)
##      URL: https://cdn.example.com/terrain/{chunk_id}.dat
##    - Option B: RPC to server (for dynamic/procedural chunks)
##      RPC: get_terrain_chunk(chunk_id)
## 3. Cache chunks locally for reuse
## 4. Apply chunks to scene (TileMap for 2D, MeshInstance for 3D)
##
## Parameters:
##   chunk_ids: Array of terrain chunk IDs (e.g., ["forest_01_chunk_0_0"])
##
## Phase 2, Task: 2.1.4 - Add terrain chunk referencing
func load_terrain_chunks(chunk_ids: Array) -> void:
	if chunk_ids.is_empty():
		print("[WorldState] No terrain chunks to load")
		return

	print("[WorldState] Loading %d terrain chunks..." % chunk_ids.size())

	for chunk_id in chunk_ids:
		# Check cache first
		var cached_chunk = get_cached_terrain_chunk(chunk_id)
		if cached_chunk != null:
			print("[WorldState] Loaded chunk from cache: %s" % chunk_id)
			apply_terrain_chunk(cached_chunk)
			continue

		# TODO: Fetch chunk from CDN or server
		# For now, log that chunk would be fetched
		print("[WorldState] TODO: Fetch chunk from CDN/server: %s" % chunk_id)

		# In production:
		# var chunk_data = await fetch_terrain_chunk_from_cdn(chunk_id)
		# cache_terrain_chunk(chunk_id, chunk_data)
		# apply_terrain_chunk(chunk_data)

	print("[WorldState] Terrain chunks loaded")


## Get terrain chunk from local cache
##
## Task 2.1.4: Terrain chunk caching
##
## Parameters:
##   chunk_id: Chunk identifier
##
## Returns: Cached chunk data or null if not cached
func get_cached_terrain_chunk(chunk_id: String) -> Variant:
	# TODO: Implement persistent cache (FileAccess or Resource cache)
	# For now, return null (no cache)
	return null


## Apply terrain chunk to scene
##
## Task 2.1.4: Terrain chunk application
##
## Parameters:
##   chunk_data: Chunk data (TileMap data for 2D, Mesh data for 3D)
func apply_terrain_chunk(chunk_data: Variant) -> void:
	# TODO: Phase 2 - Implement terrain chunk application
	# For 2D: Apply to TileMap layer
	# For 3D: Create MeshInstance with terrain mesh
	pass


## Clear all entities from the world
##
## Used before applying a new snapshot or when leaving a zone
func clear_world() -> void:
	print("[WorldState] Clearing world state...")

	for entity_id in entities.keys():
		var entity_node = entities[entity_id]
		if is_instance_valid(entity_node):
			entity_node.queue_free()

	entities.clear()
	print("[WorldState] World cleared")


## Spawn an entity from snapshot/delta data
##
## Parameters:
##   entity_data: Dictionary with entity_id, type, position, rotation, vitals
##   is_3d: Whether to spawn a 3D entity (Entity3D) or 2D entity (Entity2D)
##
## Phase 2, Task: 2.4.2 - Implement atomic snapshot application
## Phase 2, Task: 2.4.3 - Implement entity instantiation
## Supports both 2D (x, y) and 3D (x, y, z) positions with proper scene loading
func spawn_entity(entity_data: Dictionary, is_3d: bool = false) -> void:
	var entity_id = entity_data.get("entityId", entity_data.get("entity_id", ""))
	var entity_type = entity_data.get("type", "npc")

	if entity_id.is_empty():
		push_warning("[WorldState] Cannot spawn entity: missing entity_id")
		return

	# Check if entity already exists
	if entities.has(entity_id):
		push_warning("[WorldState] Entity already exists: %s" % entity_id)
		return

	# Extract transform and vitals data
	var transform_data = entity_data.get("transform", {})
	var position_data = transform_data.get("position", entity_data.get("position", {}))
	var rotation_data = transform_data.get("rotation", entity_data.get("rotation", {}))
	var vitals_data = entity_data.get("vitals", {})

	# Select appropriate entity scene based on 2D/3D and entity type
	var entity_scenes = entity_scenes_3d if is_3d else entity_scenes_2d
	var entity_scene = entity_scenes.get(entity_type, entity_scenes.get("npc"))

	if entity_scene == null:
		push_error("[WorldState] No scene found for entity type: %s (3D: %s)" % [entity_type, is_3d])
		return

	# Instantiate entity from scene
	var entity_node = entity_scene.instantiate()
	entity_node.name = entity_id

	# Set entity properties
	if entity_node.has_method("set"):
		entity_node.entity_id = entity_id
		entity_node.entity_type = entity_type

	if is_3d:
		# 3D world: Set position and rotation
		var pos_x = position_data.get("x", 0.0)
		var pos_y = position_data.get("y", 0.0)
		var pos_z = position_data.get("z", 0.0)
		entity_node.position = Vector3(pos_x, pos_y, pos_z)

		# Set 3D rotation (Euler angles in radians)
		var rot_x = rotation_data.get("x", 0.0)
		var rot_y = rotation_data.get("y", 0.0)
		var rot_z = rotation_data.get("z", 0.0)
		entity_node.rotation = Vector3(rot_x, rot_y, rot_z)

		print("[WorldState] Spawned 3D entity: %s (type: %s) at (%f, %f, %f)" % [
			entity_id, entity_type, pos_x, pos_y, pos_z
		])
	else:
		# 2D world: Set position and rotation
		var pos_x = position_data.get("x", 0.0)
		var pos_y = position_data.get("y", 0.0)
		entity_node.position = Vector2(pos_x, pos_y)

		# Set 2D rotation (single float in radians, use z component)
		var rot_z = rotation_data.get("z", 0.0)
		entity_node.rotation = rot_z

		print("[WorldState] Spawned 2D entity: %s (type: %s) at (%f, %f)" % [
			entity_id, entity_type, pos_x, pos_y
		])

	# Set vitals if entity supports them
	if entity_node.has_method("set_vitals") and not vitals_data.is_empty():
		entity_node.set_vitals(vitals_data)

	# Initialize entity with full data if it supports initialize method
	if entity_node.has_method("initialize"):
		entity_node.initialize(entity_id, entity_data)

	# Add to scene tree
	add_child(entity_node)

	# Track in entities dictionary
	entities[entity_id] = entity_node

	# Emit signal for custom instantiation (Requirement 33, line 716)
	entity_added.emit(entity_id, entity_type, entity_node)


## Despawn an entity by ID
##
## Parameters:
##   entity_id: UUID of entity to remove
##
## Phase 2, Task: 2.3.3 - Implement entity add/remove messages
func despawn_entity(entity_id: String) -> void:
	if not entities.has(entity_id):
		push_warning("[WorldState] Cannot despawn entity: %s not found" % entity_id)
		return

	var entity_node = entities[entity_id]

	if is_instance_valid(entity_node):
		entity_node.queue_free()

	entities.erase(entity_id)
	print("[WorldState] Despawned entity: %s" % entity_id)


## Apply a zone delta (incremental update)
##
## Parameters:
##   delta_data: Dictionary with entity updates, adds, and removes OR
##               String with base64-encoded compressed delta
##
## Phase 2, Task: 2.4.5 - Implement delta application
## Task 1.3 - Implement WorldState Delta Processing
## Requirements: 4 (Delta Stream Processing), 36 (Delta Stream Processing)
##
## Processes incremental updates from server:
## - entityRemoves: Array of entity IDs to despawn
## - entityAdds: Array of full entity snapshots to spawn
## - entityUpdates: Array of partial entity updates (changed fields only)
##
## Handles both 2D and 3D entities based on is_3d_world flag.
## Tracks performance metrics and emits delta_applied signal.
##
## Acceptance Criteria (Task 1.3):
## - [x] Handle compressed delta decompression
## - [x] Handle entity updates (position, health, state changes)
## - [x] Handle entity spawns (new entities appearing)
## - [x] Handle entity despawns (entities disappearing)
## - [x] Emit delta_applied signal with metrics
## - [x] Track delta statistics for debug overlay
func apply_delta(delta_data: Variant) -> void:
	var start_time := Time.get_ticks_msec()
	var delta_dict: Dictionary
	var delta_size: int = 0

	# Handle compressed delta (String - base64-encoded)
	if delta_data is String:
		delta_size = delta_data.length()
		delta_dict = decompress_delta(delta_data)
		if delta_dict.is_empty():
			push_warning("[WorldState] Failed to decompress delta")
			return
	elif delta_data is Dictionary:
		# Uncompressed delta
		delta_dict = delta_data
		delta_size = JSON.stringify(delta_data).length()
	else:
		push_warning("[WorldState] Invalid delta_data type: %s" % typeof(delta_data))
		return

	if delta_dict.is_empty():
		return

	# Track entities updated for metrics
	var entities_updated_count: int = 0

	# Process entity removals first (clean up before adding new)
	var entity_removes = delta_dict.get("entityRemoves", delta_dict.get("entity_removes", []))
	for entity_id in entity_removes:
		despawn_entity(entity_id)
		entities_updated_count += 1

	# Process entity additions (new entities entering AOI)
	var entity_adds = delta_dict.get("entityAdds", delta_dict.get("entity_adds", []))
	for entity_data in entity_adds:
		spawn_entity(entity_data, is_3d_world)
		entities_updated_count += 1

	# Process entity updates (position, vitals, state changes)
	var entity_updates = delta_dict.get("entityUpdates", delta_dict.get("entity_updates", []))
	for update_data in entity_updates:
		update_entity(update_data)
		entities_updated_count += 1

	# Performance monitoring
	var elapsed_ms := Time.get_ticks_msec() - start_time
	if elapsed_ms > MAX_DELTA_APPLY_TIME_MS:
		push_warning("[WorldState] Delta processing exceeded 10ms budget: %d ms" % elapsed_ms)
		delta_performance_warning.emit(elapsed_ms)

	# Update performance profiling stats (Task 8.3)
	performance_stats.last_delta_time_ms = elapsed_ms
	performance_stats.delta_count += 1
	performance_stats.total_delta_time_ms += elapsed_ms
	if elapsed_ms > performance_stats.max_delta_time_ms:
		performance_stats.max_delta_time_ms = elapsed_ms

	# Update delta statistics
	delta_stats.last_size = delta_size
	delta_stats.last_entity_count = entities_updated_count
	delta_stats.total_deltas += 1
	delta_stats.total_entities_updated += entities_updated_count
	delta_stats.average_size = float(delta_stats.average_size * (delta_stats.total_deltas - 1) + delta_size) / delta_stats.total_deltas
	delta_stats.average_entities = float(delta_stats.total_entities_updated) / delta_stats.total_deltas

	# Emit signal for UI/debug overlay
	delta_applied.emit(delta_size, entities_updated_count)


## Decompress delta payload
##
## Parameters:
##   compressed_delta: Base64-encoded, zlib-compressed JSON delta
##
## Returns: Decompressed delta dictionary or empty dictionary on failure
##
## Task 1.3 - Implement WorldState Delta Processing
## Requirement: 4 (Delta Stream Processing)
##
## Deltas are compressed using zlib to minimize network bandwidth.
## This function decompresses and parses the delta JSON.
func decompress_delta(compressed_delta: String) -> Dictionary:
	if compressed_delta.is_empty():
		return {}

	# Decode base64
	var compressed_bytes = Marshalls.base64_to_raw(compressed_delta)
	if compressed_bytes.is_empty():
		push_error("[WorldState] Failed to decode base64 delta")
		return {}

	# Decompress using zlib
	var decompressed_bytes = compressed_bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if decompressed_bytes.is_empty():
		push_error("[WorldState] Failed to decompress delta")
		return {}

	# Parse JSON
	var json_string = decompressed_bytes.get_string_from_utf8()
	var delta_dict = JSON.parse_string(json_string)

	if delta_dict == null or typeof(delta_dict) != TYPE_DICTIONARY:
		push_error("[WorldState] Failed to parse delta JSON")
		return {}

	return delta_dict


## Update an existing entity with new data
##
## Parameters:
##   update_data: Dictionary with entityId and individual field updates
##
## Phase 2, Task: 2.4.5 - Implement delta application
## Requirements: 36 (Delta Stream Processing)
##
## Applies incremental updates from server to existing entities.
## Uses entity's apply_update() method for proper 2D/3D handling.
##
## Server sends only changed fields (bandwidth optimization from Task 2.3.4):
## - Position fields: positionX, positionY, positionZ (individual)
## - Rotation fields: rotationX, rotationY, rotationZ (individual)
## - Vitals fields: health, maxHealth, mana, maxMana (individual)
## - State: arbitrary entity state dictionary
func update_entity(update_data: Dictionary) -> void:
	var start_time := Time.get_ticks_usec()  # Use microseconds for finer granularity
	
	var entity_id = update_data.get("entityId", update_data.get("entity_id", ""))

	if entity_id.is_empty():
		push_warning("[WorldState] Cannot update entity: missing entityId")
		return

	if not entities.has(entity_id):
		# Entity not in AOI yet, might need to spawn
		# Check if update contains enough data to spawn
		if update_data.has("type"):
			push_warning("[WorldState] Entity not found, spawning: %s" % entity_id)
			spawn_entity(update_data, is_3d_world)
		return

	var entity_node = entities[entity_id]

	if not is_instance_valid(entity_node):
		push_warning("[WorldState] Entity node invalid: %s" % entity_id)
		entities.erase(entity_id)
		return

	# Delegate to entity's apply_update method (Task 2.4.3)
	# Entity2D and Entity3D handle field-level updates internally
	if entity_node.has_method("apply_update"):
		entity_node.apply_update(update_data)
	else:
		push_warning("[WorldState] Entity %s does not have apply_update method" % entity_id)
	
	# Track performance (Task 8.3)
	var elapsed_us := Time.get_ticks_usec() - start_time
	var elapsed_ms := elapsed_us / 1000.0
	performance_stats.last_entity_update_time_ms = elapsed_ms
	performance_stats.entity_update_count += 1
	performance_stats.total_entity_update_time_ms += elapsed_ms
	if elapsed_ms > performance_stats.max_entity_update_time_ms:
		performance_stats.max_entity_update_time_ms = elapsed_ms


## Get entity node by ID
##
## Parameters:
##   entity_id: UUID of entity to retrieve
##
## Returns: Entity node or null if not found
func get_entity(entity_id: String) -> Node:
	return entities.get(entity_id, null)


## Get all entities in current zone
##
## Returns: Array of entity nodes
func get_all_entities() -> Array:
	return entities.values()


## Get entity count
##
## Returns: Number of active entities
func get_entity_count() -> int:
	return entities.size()
