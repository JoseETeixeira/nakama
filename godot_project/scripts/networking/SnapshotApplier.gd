## SnapshotApplier.gd
## Utility for decompressing and parsing zone snapshots from Nakama server.
## Handles both 2D and 3D world formats with performance monitoring.
##
## Requirements: Requirement 4
## Design: Client Integration > SnapshotApplier

class_name SnapshotApplier
extends RefCounted

## Performance monitoring threshold (ms)
const MAX_APPLY_TIME_MS := 50.0

## Decompress a base64-encoded, Deflate-compressed snapshot blob.
##
## @param blob_base64: Base64-encoded compressed snapshot from server
## @return Dictionary: Parsed snapshot data or null on failure
func decompress_snapshot(blob_base64: String) -> Dictionary:
	var start_time := Time.get_ticks_msec()

	# Step 1: Decode base64 to raw bytes
	var compressed_data := Marshalls.base64_to_raw(blob_base64)
	if compressed_data.is_empty():
		push_error("[SnapshotApplier] Failed to decode base64 snapshot")
		return {}

	# Step 2: Decompress using Deflate
	var json_bytes := compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if json_bytes.is_empty():
		push_error("[SnapshotApplier] Failed to decompress snapshot (Deflate)")
		return {}

	# Step 3: Convert bytes to string
	var json_string := json_bytes.get_string_from_utf8()
	if json_string.is_empty():
		push_error("[SnapshotApplier] Failed to decode UTF-8 from decompressed data")
		return {}

	# Step 4: Parse JSON
	var snapshot := parse_snapshot(json_string)

	# Performance monitoring
	var elapsed_ms := Time.get_ticks_msec() - start_time
	if elapsed_ms > MAX_APPLY_TIME_MS:
		push_warning("[SnapshotApplier] Snapshot decompression exceeded 50ms budget: %d ms" % elapsed_ms)

	return snapshot


## Parse JSON string into a structured snapshot dictionary.
##
## @param json_string: JSON-encoded snapshot data
## @return Dictionary: Parsed snapshot with entities, terrain, etc.
func parse_snapshot(json_string: String) -> Dictionary:
	var json := JSON.new()
	var error := json.parse(json_string)

	if error != OK:
		push_error("[SnapshotApplier] JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}

	var data: Dictionary = json.data
	if not data.has("entities"):
		push_error("[SnapshotApplier] Snapshot missing 'entities' field")
		return {}

	# Detect 2D vs 3D based on first entity's position format
	var is_3d := _detect_3d_world(data.get("entities", []))
	data["is_3d"] = is_3d

	return data


## Apply a compressed snapshot blob atomically.
## This is the main entry point for client integration.
##
## @param blob_base64: Base64-encoded compressed snapshot from server
## @return Dictionary: Parsed snapshot data or empty dictionary on failure
func apply_snapshot(blob_base64: String) -> Dictionary:
	var snapshot := decompress_snapshot(blob_base64)

	if snapshot.is_empty():
		push_error("[SnapshotApplier] Cannot apply empty snapshot")
		return {}

	print("[SnapshotApplier] Snapshot applied: zone_time=%d, entities=%d, is_3d=%s" % [
		snapshot.get("zoneTime", 0),
		snapshot.get("entities", []).size(),
		snapshot.get("is_3d", false)
	])

	return snapshot


## Detect if the world is 3D based on entity position format.
##
## @param entities: Array of entity snapshots
## @return bool: True if 3D world (has position.z), false otherwise
func _detect_3d_world(entities: Array) -> bool:
	for entity in entities:
		if not entity is Dictionary:
			continue

		var transform_data = entity.get("transform", {})
		if not transform_data is Dictionary:
			continue

		var position = transform_data.get("position", {})
		if not position is Dictionary:
			continue

		# 3D worlds have a z coordinate that is not 0
		if position.has("z") and position["z"] != 0:
			return true

		# If z exists and is 0, it's 2D with explicit z=0
		# If z doesn't exist, it's definitely 2D

	return false


## Extract entity list from snapshot for instantiation.
##
## @param snapshot: Parsed snapshot dictionary
## @return Array: Array of entity dictionaries with id, type, transform, vitals
func get_entities(snapshot: Dictionary) -> Array:
	return snapshot.get("entities", [])


## Extract terrain chunk references from snapshot.
##
## @param snapshot: Parsed snapshot dictionary
## @return Array: Array of terrain chunk IDs
func get_terrain_chunks(snapshot: Dictionary) -> Array:
	return snapshot.get("terrainChunks", [])


## Extract zone time from snapshot.
##
## @param snapshot: Parsed snapshot dictionary
## @return int: Server zone time (ms)
func get_zone_time(snapshot: Dictionary) -> int:
	return snapshot.get("zoneTime", 0)


## Extract AOI seed position from snapshot.
##
## @param snapshot: Parsed snapshot dictionary
## @return Dictionary: AOI seed position {x, y, z}
func get_aoi_seed(snapshot: Dictionary) -> Dictionary:
	var aoi_seed = snapshot.get("aoiSeed", {})
	if aoi_seed is Dictionary:
		return aoi_seed
	elif aoi_seed is Array and aoi_seed.size() >= 2:
		# Convert array [x, y, z] to dictionary
		return {
			"x": aoi_seed[0],
			"y": aoi_seed[1],
			"z": aoi_seed[2] if aoi_seed.size() > 2 else 0
		}
	return {"x": 0, "y": 0, "z": 0}


## Extract active effects from snapshot.
##
## @param snapshot: Parsed snapshot dictionary
## @return Array: Array of active global effects
func get_active_effects(snapshot: Dictionary) -> Array:
	return snapshot.get("activeEffects", [])


## Check if snapshot is for a 3D world.
##
## @param snapshot: Parsed snapshot dictionary
## @return bool: True if 3D world, false otherwise
func is_3d_world(snapshot: Dictionary) -> bool:
	return snapshot.get("is_3d", false)
