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

# Visual indicator icons (Requirement 12 - Task 7.2)
@onready var vendor_icon: ColorRect = $VendorIcon
@onready var quest_icon: ColorRect = $QuestIcon
@onready var aggro_icon: ColorRect = $AggroIcon

# Input detection for click interactions
var is_clickable: bool = true  # NPCs/players can be clicked, resources may not
var click_area: Area2D = null  # Area2D for detecting mouse clicks

# Animation state for pulsing icons
var icon_pulse_time: float = 0.0


func _ready() -> void:
	# Initialize target position to current position
	target_position = global_position

	# Set up collision shape for click detection
	if collision_shape:
		collision_shape.shape = RectangleShape2D.new()
		collision_shape.shape.size = Vector2(32, 32)
	
	# Create Area2D for mouse click detection
	click_area = Area2D.new()
	click_area.name = "ClickArea"
	click_area.input_pickable = true  # CRITICAL: Enable input detection
	click_area.monitorable = false  # Don't need collision monitoring
	click_area.monitoring = false   # Don't need to monitor other areas
	add_child(click_area)
	
	var click_shape = CollisionShape2D.new()
	click_shape.shape = RectangleShape2D.new()
	click_shape.shape.size = Vector2(32, 32)
	click_area.add_child(click_shape)
	
	# Connect mouse signals
	click_area.input_event.connect(_on_click_area_input_event)
	
	# Ensure sprite doesn't block input
	if sprite:
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	print("[NPCEntity] Click area created for entity (will be named in initialize())")


func _process(delta: float) -> void:
	# Smooth interpolation to target position (Requirement 4)
	if global_position.distance_to(target_position) > 1.0:
		# Use move_toward for smooth interpolation as specified in design.md
		global_position = global_position.move_toward(target_position, interpolation_speed * delta)

	# Animate icon pulsing effect (Task 7.2)
	animate_icons(delta)


# Called by WorldState.spawn_entity() during entity initialization
func initialize(id: String, data: Dictionary) -> void:
	entity_id = id
	entity_data = data

	# Set entity type for interaction behavior
	if "type" in data:
		entity_type = data.type

	# Extract transform data
	var transform_data = data.get("transform", {})
	var position_data = transform_data.get("position", data.get("position", {}))

	# Set initial position
	if not position_data.is_empty():
		if position_data is Vector2:
			global_position = position_data
			target_position = position_data
		elif position_data is Dictionary and "x" in position_data and "y" in position_data:
			global_position = Vector2(position_data.x, position_data.y)
			target_position = Vector2(position_data.x, position_data.y)

	# Extract vitals data
	var vitals_data = data.get("vitals", {})

	# Initialize visual components
	update_name_label()

	if not vitals_data.is_empty():
		var health = vitals_data.get("health", 100)
		var max_health = vitals_data.get("maxHealth", vitals_data.get("max_health", 100))
		update_health_bar(health, max_health)

	# Extract state data
	var state_data = data.get("state", {})
	if not state_data.is_empty():
		# Merge state data into entity_data for easy access
		for key in state_data.keys():
			entity_data[key] = state_data[key]
		update_animation_state(state_data)

	# Set clickable based on entity type
	is_clickable = entity_type in ["npc", "player", "mob"]
	
	# Update click area settings
	if click_area:
		click_area.input_pickable = is_clickable
		print("[NPCEntity] Click area configured for: ", entity_id, " (input_pickable: ", is_clickable, ")")
	
	print("[NPCEntity] Initialized: ", entity_id, " (clickable: ", is_clickable, ")")

	# Update visual indicators (Task 7.2)
	update_indicators()


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

	# Update visual indicators if capabilities changed (Task 7.2)
	if "is_vendor" in data or "has_quest" in data or "is_enemy" in data or "state" in data:
		update_indicators()

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
func update_animation_state(state) -> void:
	# Handle both String and Dictionary state formats
	var state_name: String = ""
	
	if state is String:
		state_name = state
	elif state is Dictionary:
		# Extract state name from Dictionary (server might send {name: "idle", ...})
		state_name = state.get("name", state.get("type", "idle"))
	else:
		push_warning("[NPCEntity] Invalid state type: " + str(typeof(state)))
		return
	
	# Placeholder for animation system integration
	# In production, this would trigger AnimationPlayer or AnimatedSprite2D
	# For now, change sprite color based on state for visual debugging
	if sprite:
		match state_name:
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


## Update visual indicators based on entity capabilities
##
## Task: 7.2 - Add NPC Visual Indicators
## Requirements: 12
##
## Shows/hides icons above NPC based on entity_data flags:
## - Vendor icon (gold $) for is_vendor = true
## - Quest icon (blue !) for has_quest = true
## - Aggro icon (red ⚔) for is_enemy = true or entity in combat state
func update_indicators() -> void:
	if not vendor_icon or not quest_icon or not aggro_icon:
		return

	# Vendor icon: Show if entity is a vendor
	var is_vendor = entity_data.get("is_vendor", false)
	vendor_icon.visible = is_vendor

	# Quest icon: Show if entity has quest available
	var has_quest = entity_data.get("has_quest", false)
	quest_icon.visible = has_quest and not is_vendor  # Don't show quest icon if vendor icon is showing

	# Aggro icon: Show if entity is enemy or in attacking state
	var is_enemy = entity_data.get("is_enemy", false) or entity_type == "mob"
	var is_attacking = entity_data.get("state", "") == "attacking"
	aggro_icon.visible = (is_enemy or is_attacking) and not is_vendor and not has_quest  # Priority: vendor > quest > aggro


## Animate icon pulsing effect
##
## Task: 7.2 - Add NPC Visual Indicators
## Requirements: 12
##
## Creates subtle pulsing animation on visible icons for visual appeal
func animate_icons(delta: float) -> void:
	icon_pulse_time += delta * 2.0  # Pulse speed

	# Calculate pulse scale (1.0 to 1.2)
	var pulse_scale = 1.0 + (sin(icon_pulse_time) * 0.1)

	# Apply pulse to visible icons
	if vendor_icon and vendor_icon.visible:
		vendor_icon.scale = Vector2(pulse_scale, pulse_scale)

	if quest_icon and quest_icon.visible:
		quest_icon.scale = Vector2(pulse_scale, pulse_scale)

	if aggro_icon and aggro_icon.visible:
		aggro_icon.scale = Vector2(pulse_scale, pulse_scale)


# Handle global input for click detection (Fallback/Primary method)
func _unhandled_input(event: InputEvent) -> void:
	if not is_clickable:
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		# Check distance to entity center (assuming 32x32 size, radius ~25)
		if global_position.distance_to(mouse_pos) < 25.0:
			print("[NPCEntity] _unhandled_input CLICK detected on: %s (dist: %.2f)" % [entity_data.get("name", entity_id), global_position.distance_to(mouse_pos)])
			show_interaction_menu()
			get_viewport().set_input_as_handled()


# Handle Area2D input events for click detection
func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	print("[NPCEntity] _on_click_area_input_event called for: ", entity_id, " | event: ", event, " | clickable: ", is_clickable)
	
	if not is_clickable:
		print("[NPCEntity] Entity not clickable, ignoring input")
		return
	
	if event is InputEventMouseButton:
		print("[NPCEntity] Mouse button event: pressed=", event.pressed, " button=", event.button_index)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("[NPCEntity] ✓ LEFT CLICK detected on entity: %s" % entity_data.get("name", entity_id))
			show_interaction_menu()


# Show context menu for NPC interaction (Requirement 12)
func show_interaction_menu() -> void:
	print("[NPCEntity] show_interaction_menu called for: %s (type: %s)" % [entity_data.get("name", entity_id), entity_type])
	
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

	if entity_type == "mob" or entity_data.get("is_enemy", false):
		menu_items.append("Attack")

	# Default interaction if no specific options
	if menu_items.is_empty():
		menu_items.append("Talk")

	print("[NPCEntity] Context menu items: %s" % menu_items)

	# Get mouse position for context menu placement
	var mouse_pos = get_viewport().get_mouse_position()

	print("[NPCEntity] Showing context menu at: %s" % mouse_pos)

	# Show context menu via UIManager
	UIManager.show_context_menu(menu_items, self, mouse_pos, self, "_on_menu_item_selected")


# Handle context menu selection
func _on_menu_item_selected(item: String) -> void:
	match item:
		"Trade":
			_open_vendor_or_trade()
		"Talk":
			_open_dialogue()
		"Inspect":
			_inspect_player()
		"Attack":
			_target_for_combat()


# Interaction handlers
func _open_vendor_or_trade() -> void:
	if entity_data.get("is_vendor", false):
		print("[NPCEntity] Opening vendor UI for %s" % entity_data.get("name", entity_id))

		# Get vendor ID from entity data
		var vendor_id = entity_data.get("vendor_id", entity_id)

		# Open VendorPanel
		var vendor_panel = get_tree().get_root().get_node_or_null("Zone/UILayer/Control/VendorPanel")
		if vendor_panel:
			vendor_panel.open_vendor(vendor_id, entity_data.get("name", "Vendor"))
			UIManager.show_panel("vendor")
		else:
			push_warning("[NPCEntity] VendorPanel not found in scene tree")
	else:
		print("[NPCEntity] Opening trade UI with %s" % entity_data.get("name", entity_id))

		# Open TradePanel for player-to-player trade
		var trade_panel = get_tree().get_root().get_node_or_null("Zone/UILayer/Control/TradePanel")
		if trade_panel:
			trade_panel.initiate_trade(entity_id, entity_data.get("name", "Player"))
			UIManager.show_panel("trade")
		else:
			push_warning("[NPCEntity] TradePanel not found in scene tree")


func _open_dialogue() -> void:
	print("[NPCEntity] Opening dialogue for %s" % entity_data.get("name", entity_id))

	# Dialogue system not yet implemented
	# Show simple message for now
	var npc_name = entity_data.get("name", "NPC")
	var dialogue_text = entity_data.get("dialogue", "Hello, traveler!")

	UIManager.show_error("%s: %s" % [npc_name, dialogue_text])


func _inspect_player() -> void:
	print("[NPCEntity] Inspecting player %s" % entity_data.get("name", entity_id))

	# Player inspection UI not yet implemented
	# Show simple info dialog for now
	var player_name = entity_data.get("name", "Unknown Player")
	var player_level = entity_data.get("level", 1)
	var info_text = "Player: %s\nLevel: %d" % [player_name, player_level]

	UIManager.show_error(info_text)


func _target_for_combat() -> void:
	print("[NPCEntity] Targeting %s for combat" % entity_data.get("name", entity_id))

	# Set this entity as the player's current target
	# The ability hotbar (Task 4.1) will use this target when abilities are activated
	if WorldState.has_method("set_target"):
		WorldState.set_target(entity_id, self)

	# Show visual feedback that entity is targeted
	_show_target_indicator()

	# Display target in HUD
	var hud = get_tree().get_root().get_node_or_null("Zone/UILayer/Control/HUD")
	if hud and hud.has_method("set_target_info"):
		var target_name = entity_data.get("name", "Unknown")
		var target_health = entity_data.get("health", 100)
		var target_max_health = entity_data.get("maxHealth", 100)
		hud.set_target_info(target_name, target_health, target_max_health)


func _show_target_indicator() -> void:
	# Visual indication that this entity is targeted
	# Could add a highlight effect, selection circle, etc.
	# For now, just modify the sprite slightly
	if sprite:
		sprite.modulate = Color(1.2, 1.2, 1.0)  # Slight yellow tint


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
