## Zone
##
## Main world scene for rendering the game zone (2D top-down).
##
## Phase 2, Task: 2.1.2 - Implement world_enter RPC
## Phase 2, Task: 2.1.3 - Implement zone snapshot generation
## Requirements: 4 (World Entry and Zone Snapshot), 8 (Area of Interest Management)
##
## This scene handles:
## - Zone entry and snapshot loading
## - Entity rendering based on WorldState (2D sprites)
## - Camera control and player movement (2D top-down)
extends Node2D

@onready var status_label: Label = $UILayer/Control/StatusLabel
@onready var hud: Control = $UILayer/Control/HUD


func _ready() -> void:
	print("[Zone] World scene loaded")

	# Phase 2: World entry and snapshot application already handled by CharacterSelect
	# CharacterSelect calls:
	#   1. NakamaManager.enter_world(character_id) → returns zone_id, spawn
	#   2. NakamaManager.join_zone(zone_id) → receives snapshot and subscribes to deltas
	#   3. WorldState.apply_snapshot(blob) → atomically applies snapshot to world
	# Delta updates are automatically received via zone_deltas stream subscription

	# Connect to WorldState signals for debugging (Phase 2, Task 2.4.2)
	if not WorldState.snapshot_applied.is_connected(_on_snapshot_applied):
		WorldState.snapshot_applied.connect(_on_snapshot_applied)
	if not WorldState.snapshot_application_failed.is_connected(_on_snapshot_failed):
		WorldState.snapshot_application_failed.connect(_on_snapshot_failed)
	if not WorldState.entity_added.is_connected(_on_entity_added):
		WorldState.entity_added.connect(_on_entity_added)

	# Display initial status
	update_status()


## Handle snapshot successfully applied
func _on_snapshot_applied(zone_id: String, entity_count: int) -> void:
	print("[Zone] Snapshot applied for zone: %s with %d entities" % [zone_id, entity_count])
	update_status()


## Handle snapshot application failure
func _on_snapshot_failed(error_message: String) -> void:
	push_error("[Zone] Snapshot failed: %s" % error_message)
	status_label.text = "Error loading zone: %s" % error_message


## Handle entity added to world
func _on_entity_added(entity_id: String, entity_type: String, entity_node: Node) -> void:
	print("[Zone] Entity added: %s (type: %s)" % [entity_id, entity_type])
	# Entities are already added to scene tree by WorldState.spawn_entity()
	# This signal allows for custom logic like attaching shaders, UI health bars, etc.

	# If this is the player entity, connect it to HUD
	if entity_type == "player" and entity_node.has_method("is_local_player"):
		if entity_node.is_local_player():
			hud.set_player_entity(entity_node)
			print("[Zone] Connected HUD to local player entity")


func _process(_delta: float) -> void:
	# Update status every frame (can be optimized to timer)
	if Engine.get_frames_drawn() % 60 == 0:  # Update once per second at 60 FPS
		update_status()


## Update status label with current world state
func update_status() -> void:
	var entity_count = WorldState.get_entity_count()
	var zone_id = WorldState.current_zone_id

	if zone_id.is_empty():
		status_label.text = "Zone: Not connected (Placeholder)"
	else:
		status_label.text = "Zone: %s | Entities: %d" % [zone_id, entity_count]
