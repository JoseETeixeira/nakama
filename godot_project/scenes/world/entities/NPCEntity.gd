extends CharacterBody2D

# NPCEntity represents remote players, NPCs, mobs, and other server-controlled entities
# Uses server-driven position interpolation (no client-side prediction)
# Requirement 4: Delta stream processing for remote entity updates
# Requirement 12: Click interaction for NPC context menus

# Entity identification
var entity_id: String = ""
var entity_type: String = ""  # "player", "npc", "mob", "resource"
var entity_data: Dictionary = {}

# Movement interpolation
var target_position: Vector2 = Vector2.ZERO
var interpolation_speed: float = 200.0  # Pixels per second (matches MOVE_SPEED from design)

# UI references
@onready var sprite: ColorRect = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Input detection for click interactions
var is_clickable: bool = true  # NPCs/players can be clicked, resources may not


func _ready() -> void:
	# Enable input events for click detection
	set_process_input(true)

	# Initialize target position to current position
	target_position = global_position

	# Set up collision shape for click detection
	if collision_shape:
		collision_shape.shape = RectangleShape2D.new()
		collision_shape.shape.size = Vector2(32, 32)


func _process(delta: float) -> void:
	# Smooth interpolation to target position (Requirement 4)
	if global_position.distance_to(target_position) > 1.0:
		# Use move_toward for smooth interpolation as specified in design.md
		global_position = global_position.move_toward(target_position, interpolation_speed * delta)


# Called by WorldState.spawn_entity() during entity initialization
func initialize(id: String, data: Dictionary) -> void:
	entity_id = id
	entity_data = data

	# Set entity type for interaction behavior
	if "type" in data:
		entity_type = data.type

	# Set initial position
	if "position" in data:
		var pos = data.position
		if pos is Vector2:
			global_position = pos
			target_position = pos
		elif pos is Dictionary and "x" in pos and "y" in pos:
			global_position = Vector2(pos.x, pos.y)
			target_position = Vector2(pos.x, pos.y)

	# Initialize visual components
	update_name_label()

	if "health" in data and "maxHealth" in data:
		update_health_bar(data.health, data.maxHealth)

	if "state" in data:
		update_animation_state(data.state)

	# Set clickable based on entity type
	is_clickable = entity_type in ["npc", "player", "mob"]


# Called by WorldState.update_entity() when delta updates arrive (Requirement 4)
func apply_update(data: Dictionary) -> void:
	# Position update - set target for interpolation
	if "position" in data:
		var pos = data.position
		if pos is Vector2:
			target_position = pos
		elif pos is Dictionary and "x" in pos and "y" in pos:
			target_position = Vector2(pos.x, pos.y)

	# Health update
	if "health" in data:
		var max_health = data.get("maxHealth", entity_data.get("maxHealth", 100))
		update_health_bar(data.health, max_health)
		# Update cached data
		entity_data["health"] = data.health
		if "maxHealth" in data:
			entity_data["maxHealth"] = data.maxHealth

	# Animation state update
	if "state" in data:
		update_animation_state(data.state)
		entity_data["state"] = data.state

	# Update cached entity data
	for key in data.keys():
		entity_data[key] = data[key]

	# Check for death state and spawn loot (Task 5.5)
	if "state" in data and data.state == "dead":
		check_and_spawn_loot()


# Update health bar display
func update_health_bar(health: float, max_health: float) -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
		health_bar.visible = true  # Show health bar when entity has health


# Update name label display
func update_name_label() -> void:
	if name_label and "name" in entity_data:
		name_label.text = entity_data.name


# Update animation state based on server state (e.g., "idle", "walking", "attacking")
func update_animation_state(state: String) -> void:
	# Placeholder for animation system integration
	# In production, this would trigger AnimationPlayer or AnimatedSprite2D
	# For now, change sprite color based on state for visual debugging
	if sprite:
		match state:
			"idle":
				sprite.color = Color(0.8, 0.8, 0.8)  # Gray
			"walking":
				sprite.color = Color(0.6, 0.8, 1.0)  # Light blue
			"attacking":
				sprite.color = Color(1.0, 0.4, 0.4)  # Red
			"dead":
				sprite.color = Color(0.3, 0.3, 0.3)  # Dark gray
				sprite.modulate.a = 0.5  # Semi-transparent
			_:
				sprite.color = Color(0.8, 0.8, 0.8)


# Handle click input for NPC interaction (Requirement 12)
func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if not is_clickable:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Player clicked on this entity
		show_interaction_menu()


# Show context menu for NPC interaction (Requirement 12)
func show_interaction_menu() -> void:
	# Build context menu items based on entity type and data
	var menu_items: Array[String] = []

	# Check entity capabilities from entity_data
	if entity_data.get("is_vendor", false):
		menu_items.append("Trade")

	if entity_data.get("has_quest", false):
		menu_items.append("Talk")

	if entity_type == "player":
		menu_items.append("Trade")
		menu_items.append("Inspect")
		menu_items.append("Add Friend")

	if entity_type == "mob":
		menu_items.append("Attack")

	if entity_type == "resource":
		menu_items.append("Gather")

	# Default interaction if no specific options
	if menu_items.is_empty():
		menu_items.append("Interact")

	# Trigger context menu via UIManager
	# UIManager will handle menu display and callback routing
	# For now, print debug message (context menu UI will be implemented in later tasks)
	print("NPCEntity interaction menu for %s (%s): %s" % [entity_data.get("name", entity_id), entity_type, menu_items])

	# TODO: Task 6.4 will implement actual context menu UI via UIManager
	# UIManager.show_context_menu(global_position, menu_items, self, "_on_menu_item_selected")


# Handle context menu selection
func _on_menu_item_selected(item: String) -> void:
	match item:
		"Trade":
			_open_vendor_or_trade()
		"Talk":
			_open_quest_dialog()
		"Inspect":
			_inspect_player()
		"Add Friend":
			_send_friend_request()
		"Attack":
			_target_for_combat()
		"Gather":
			_gather_resource()
		"Interact":
			_generic_interact()


# Interaction handlers (placeholders for future task implementation)
func _open_vendor_or_trade() -> void:
	if entity_data.get("is_vendor", false):
		print("Opening vendor UI for %s" % entity_data.get("name", entity_id))
		# TODO: Task 5.4 - VendorPanel integration
	else:
		print("Opening trade UI with %s" % entity_data.get("name", entity_id))
		# TODO: Task 5.3 - TradePanel integration


func _open_quest_dialog() -> void:
	print("Opening quest dialog for %s" % entity_data.get("name", entity_id))
	# TODO: Task 6.3 - Quest dialog UI


func _inspect_player() -> void:
	print("Inspecting player %s" % entity_data.get("name", entity_id))
	# TODO: Task 9.4 - Player inspection UI


func _send_friend_request() -> void:
	print("Sending friend request to %s" % entity_data.get("name", entity_id))
	# TODO: Task 7.1 - Friend system integration


func _target_for_combat() -> void:
	print("Targeting %s for combat" % entity_data.get("name", entity_id))
	# TODO: Task 4.2 - Ability targeting system


func _gather_resource() -> void:
	print("Gathering resource %s" % entity_data.get("name", entity_id))
	# TODO: Task 6.2 - Resource gathering integration


func _generic_interact() -> void:
	print("Interacting with %s" % entity_data.get("name", entity_id))


## Check if this entity is targetable for abilities
##
## Task: 4.2 - Implement Ability Targeting System
## Requirements: 5
##
## Returns: true for NPCs, players, mobs (combat targets)
func is_targetable() -> bool:
	return entity_type in ["npc", "player", "mob"]


## Check and spawn loot container when NPC dies
##
## Task: 5.5 - Implement Loot Container System
## Requirements: 9
##
## Called when entity state changes to "dead"
func check_and_spawn_loot() -> void:
	# Only spawn loot for mobs/NPCs with templates (not players)
	if entity_type not in ["npc", "mob"]:
		return

	# Check if loot already spawned for this death
	if entity_data.get("loot_spawned", false):
		return

	# Mark loot as spawned
	entity_data["loot_spawned"] = true

	# Get NPC template ID for loot generation
	var npc_template_id = entity_data.get("npc_template_id", entity_data.get("template_id", ""))
	if npc_template_id.is_empty():
		print("[NPCEntity] No template ID for loot generation: %s" % entity_id)
		return

	# Call generate_loot RPC
	spawn_loot_async(npc_template_id)


## Async function to generate and spawn loot
func spawn_loot_async(npc_template_id: String) -> void:
	# Call generate_loot RPC via NakamaManager
	var loot_items = await NakamaManager.generate_loot(npc_template_id)

	if loot_items == null or loot_items.is_empty():
		print("[NPCEntity] No loot generated for NPC: %s" % npc_template_id)
		return

	# Spawn loot container at entity position
	var loot_container_scene = preload("res://scenes/world/entities/LootContainer.tscn")
	var loot_container = loot_container_scene.instantiate()

	# Get Zone node to add container
	var zone = get_tree().get_root().get_node_or_null("Zone")
	if zone:
		zone.add_child(loot_container)
		loot_container.initialize(loot_items, global_position, npc_template_id)
		print("[NPCEntity] Spawned loot container with %d items at %s" % [loot_items.size(), global_position])
	else:
		print("[NPCEntity] Error: Zone node not found, cannot spawn loot")
		loot_container.queue_free()


# Called when entity should be removed from world (Requirement 4)
func despawn() -> void:
	# Clean up and remove from scene
	queue_free()
