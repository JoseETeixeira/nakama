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


func _ready() -> void:
	print("[Zone] World scene loaded")

	# TODO: Phase 2, Task 2.1.2 - Call world_enter RPC
	# TODO: Phase 2, Task 2.1.3 - Load zone snapshot
	# TODO: Phase 2, Task 2.3.1 - Subscribe to zone delta stream

	status_label.text = "Zone: Starter Zone (Placeholder)"

	# Display entity count from WorldState
	update_status()


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
