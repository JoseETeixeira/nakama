## WorldState Singleton
##
## Autoload singleton for managing client-side world state,
## including entity tracking, snapshot application, and delta processing.
##
## Task: 1.4.1 - Set up Godot 4 project structure
## Requirements: 4 (World Entry and Zone Snapshot), 8 (Area of Interest Management)
##
## This singleton maintains the authoritative client-side representation
## of the game world based on server snapshots and delta updates:
## - Entity dictionary (entity_id -> Node)
## - Snapshot decompression and atomic application
## - Delta stream processing for real-time updates
## - AOI-based entity spawning/despawning
##
## Usage:
##   WorldState.apply_snapshot(snapshot_blob_base64)
##   WorldState.apply_delta(delta_data)
extends Node

## Dictionary of all active entities in the current zone
## Key: entity_id (String), Value: Entity node instance
var entities: Dictionary = {}

## Current zone ID
var current_zone_id: String = ""

## Scene preloads for different entity types
## TODO: Task 1.4.1+ - Add entity scene paths when implemented
var entity_scenes: Dictionary = {
	"player": null,  # Will be preload("res://scenes/world/Player.tscn")
	"npc": null,     # Will be preload("res://scenes/world/NPC.tscn")
	"item": null     # Will be preload("res://scenes/world/Item.tscn")
}


## Apply a zone snapshot (initial world state on zone entry)
##
## Parameters:
##   blob_base64: Base64-encoded, Deflate-compressed JSON snapshot
##
## This atomically replaces the entire world state in a single frame
## to ensure visual consistency.
##
## Phase 2, Task: 2.4.2 - Implement atomic snapshot application
func apply_snapshot(blob_base64: String) -> void:
	if blob_base64.is_empty():
		push_error("[WorldState] Cannot apply snapshot: blob is empty")
		return

	print("[WorldState] Applying zone snapshot...")

	# Decode Base64 to raw bytes
	var compressed_data: PackedByteArray = Marshalls.base64_to_raw(blob_base64)

	if compressed_data.is_empty():
		push_error("[WorldState] Failed to decode Base64 snapshot")
		return

	# Decompress using Deflate
	var json_data: PackedByteArray = compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)

	if json_data.is_empty():
		push_error("[WorldState] Failed to decompress snapshot")
		return

	# Parse JSON
	var json_string = json_data.get_string_from_utf8()
	var snapshot = JSON.parse_string(json_string)

	if snapshot == null:
		push_error("[WorldState] Failed to parse snapshot JSON")
		return

	# Pause scene tree for atomic application (single frame update)
	get_tree().paused = true

	# Clear existing world state
	clear_world()

	# Extract snapshot data
	current_zone_id = snapshot.get("zone_id", "")
	var snapshot_entities = snapshot.get("entities", [])
	var terrain_chunks = snapshot.get("terrain_chunks", [])

	print("[WorldState] Snapshot contains %d entities" % snapshot_entities.size())

	# Spawn all entities from snapshot
	for entity_data in snapshot_entities:
		spawn_entity(entity_data)

	# TODO: Phase 2 - Load terrain chunks (chunk IDs, fetch from CDN/cache)
	# For now, terrain is handled by static scenes

	# Resume scene tree
	get_tree().paused = false

	print("[WorldState] Snapshot applied successfully. Zone: %s" % current_zone_id)


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
##   entity_data: Dictionary with entity_id, type, position, rotation, etc.
##
## Phase 2, Task: 2.4.3 - Implement entity instantiation
func spawn_entity(entity_data: Dictionary) -> void:
	var entity_id = entity_data.get("entity_id", "")
	var entity_type = entity_data.get("type", "npc")

	if entity_id.is_empty():
		push_warning("[WorldState] Cannot spawn entity: missing entity_id")
		return

	# Check if entity already exists
	if entities.has(entity_id):
		push_warning("[WorldState] Entity already exists: %s" % entity_id)
		return

	# TODO: Task 1.4.1+ - Implement entity scene instantiation
	# For now, we'll create placeholder nodes
	var entity_node = Node3D.new()
	entity_node.name = entity_id

	# Set position
	var pos = entity_data.get("position", {"x": 0, "y": 0, "z": 0})
	entity_node.position = Vector3(pos.x, pos.y, pos.z)

	# Set rotation
	var rot = entity_data.get("rotation", {"x": 0, "y": 0, "z": 0})
	entity_node.rotation = Vector3(rot.x, rot.y, rot.z)

	# Add to scene tree
	add_child(entity_node)

	# Track in entities dictionary
	entities[entity_id] = entity_node

	print("[WorldState] Spawned entity: %s (type: %s)" % [entity_id, entity_type])


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
##   delta_data: Dictionary with entity_updates, entity_adds, entity_removes
##
## Phase 2, Task: 2.4.5 - Implement delta application
func apply_delta(delta_data: Dictionary) -> void:
	if delta_data.is_empty():
		return

	# Process entity removals first (clean up before adding new)
	var entity_removes = delta_data.get("entity_removes", [])
	for entity_id in entity_removes:
		despawn_entity(entity_id)

	# Process entity additions
	var entity_adds = delta_data.get("entity_adds", [])
	for entity_data in entity_adds:
		spawn_entity(entity_data)

	# Process entity updates (position, rotation, vitals, etc.)
	var entity_updates = delta_data.get("entity_updates", [])
	for update_data in entity_updates:
		update_entity(update_data)


## Update an existing entity with new data
##
## Parameters:
##   update_data: Dictionary with entity_id and fields to update
##
## Phase 2, Task: 2.4.5 - Implement delta application
func update_entity(update_data: Dictionary) -> void:
	var entity_id = update_data.get("entity_id", "")

	if not entities.has(entity_id):
		# Entity not in AOI yet, might need to spawn
		if update_data.has("type"):
			spawn_entity(update_data)
		return

	var entity_node = entities[entity_id]

	if not is_instance_valid(entity_node):
		push_warning("[WorldState] Entity node invalid: %s" % entity_id)
		entities.erase(entity_id)
		return

	# Update position if provided
	if update_data.has("position"):
		var pos = update_data.position
		entity_node.position = Vector3(pos.x, pos.y, pos.z)

	# Update rotation if provided
	if update_data.has("rotation"):
		var rot = update_data.rotation
		entity_node.rotation = Vector3(rot.x, rot.y, rot.z)

	# TODO: Phase 2 - Update vitals, buffs, animations, etc.


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
