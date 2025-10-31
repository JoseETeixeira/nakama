## PlayerEntity Scene Script
##
## Local player character with client-side prediction and server reconciliation.
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3 (Player Movement & Prediction), 5 (Combat Abilities)
## Design: PlayerEntity (lines 330-365)
##
## This entity provides:
## - WASD/arrow key movement input
## - Client-side prediction (move immediately)
## - move_intent RPC to server
## - Server position reconciliation (snap or interpolate)
## - Ability hotkey input (1-9)
## - Health/mana bar display
##
## Usage:
##   Spawned by WorldState.spawn_entity() for player entities
##   Updated by WorldState delta updates for server position
extends CharacterBody2D

## Movement speed in pixels per second
const MOVE_SPEED: float = 200.0

## Distance threshold for snapping to server position (in pixels)
## If distance > SNAP_THRESHOLD, teleport to server position
const SNAP_THRESHOLD: float = 100.0

## Distance threshold for interpolation (in pixels)
## If distance > INTERPOLATE_THRESHOLD but < SNAP_THRESHOLD, smooth interpolate
const INTERPOLATE_THRESHOLD: float = 10.0

## Interpolation speed factor (0.0 - 1.0)
const INTERPOLATION_SPEED: float = 0.3

## Entity ID from server
var entity_id: String = ""

## Entity type (player, npc, mob, resource, etc.)
var entity_type: String = "player"

## Entity data from server (health, mana, buffs, etc.)
var entity_data: Dictionary = {}

## Current health and max health
var health: float = 100.0
var max_health: float = 100.0

## Current mana and max mana
var mana: float = 100.0
var max_mana: float = 100.0

## Last server position for reconciliation
var server_position: Vector2 = Vector2.ZERO

## Time since last move_intent RPC (throttling)
var move_intent_cooldown: float = 0.0
const MOVE_INTENT_INTERVAL: float = 0.05  # Send move_intent every 50ms max

## Character data from server (for abilities, name, etc.)
var character_data: Dictionary = {}

# Signals
signal ability_cooldown_started(ability_id: String, cooldown_duration: float)

## References to UI nodes
@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var mana_bar: ProgressBar = $ManaBar
@onready var name_label: Label = $NameLabel


## ============================================================================
## LIFECYCLE
## ============================================================================

## Initialize entity
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3
## Design: PlayerEntity (lines 330-365)
func _ready() -> void:
	print("[PlayerEntity] Player entity ready: ", entity_id)

	# Update UI elements
	update_health_bar()
	update_mana_bar()
	update_name_label()


## Process each frame
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3, 5
## Design: PlayerEntity (lines 330-365)
##
## Handles movement input, ability input, and move_intent throttling.
func _process(delta: float) -> void:
	# Decrement move_intent cooldown
	if move_intent_cooldown > 0.0:
		move_intent_cooldown -= delta

	# Handle input
	handle_movement_input(delta)
	handle_ability_input()


## ============================================================================
## MOVEMENT & INPUT
## ============================================================================

## Handle movement input with client-side prediction
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3.1 (Client-side prediction), 3.2 (move_intent RPC)
## Design: PlayerEntity (lines 334-343)
##
## This function implements client-side prediction by moving the player
## immediately on input, then sending move_intent to server for validation.
func handle_movement_input(delta: float) -> void:
	# Get input vector from WASD or arrow keys
	var input_vector = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if input_vector.length() > 0:
		# Normalize to prevent faster diagonal movement
		input_vector = input_vector.normalized()

		# Client-side prediction: move immediately
		velocity = input_vector * MOVE_SPEED
		move_and_slide()

		# Send move_intent to server (throttled)
		if move_intent_cooldown <= 0.0:
			NakamaManager.move_intent(global_position, velocity)
			move_intent_cooldown = MOVE_INTENT_INTERVAL
	else:
		# No input, stop moving
		velocity = Vector2.ZERO


## Handle ability input from hotkeys
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 5 (Combat Abilities)
## Design: PlayerEntity (lines 360-365)
##
## Detects 1-9 key presses and calls use_ability RPC.
## Actual ability validation is done by server.
func handle_ability_input() -> void:
	# Check hotkeys 1-9
	for i in range(1, 10):
		var key = "ability_" + str(i)
		if Input.is_action_just_pressed(key):
			use_ability(str(i), "")
			break


## Use an ability
##
## Parameters:
##   ability_id: Ability slot ID (1-9) or ability template ID
##   target_id: Target entity ID (empty for self-cast or ground-target)
##
## Task: 3.2 - Create PlayerEntity Scene, Task 4.2 - Targeting System
## Requirements: 5
## Design: PlayerEntity (lines 360-365)
##
## Calls use_ability RPC and handles cooldown/animation/visual effects on response.
func use_ability(ability_id: String, target_id: String = "") -> void:
	print("[PlayerEntity] Using ability: %s on target: %s" % [ability_id, target_id])

	# Call RPC (returns result with success, cooldown, damage, etc.)
	var result = await NakamaManager.use_ability(ability_id, target_id, global_position)

	if result.is_empty():
		print("[PlayerEntity] Ability failed: no response")
		return

	var success = result.get("success", false)
	if success:
		print("[PlayerEntity] Ability succeeded!")

		# Play ability animation (placeholder)
		play_ability_animation(ability_id)

		# Start cooldown if applicable
		var cooldown = result.get("cooldown", 0.0)
		if cooldown > 0:
			start_ability_cooldown(ability_id, cooldown)

		# Handle visual effects via AbilityTargeting
		if AbilityTargeting:
			AbilityTargeting.handle_ability_result(result, global_position)
	else:
		var error = result.get("error", "Unknown error")
		print("[PlayerEntity] Ability failed: ", error)
		# Show error message to player
		if UIManager:
			UIManager.show_floating_text(error, global_position, Color.RED)


## Play ability animation
##
## Parameters:
##   ability_id: Ability ID for animation lookup
##
## Placeholder function for ability visual effects.
func play_ability_animation(ability_id: String) -> void:
	# TODO: Implement ability animations (particles, sprite animation, etc.)
	print("[PlayerEntity] Playing animation for ability: ", ability_id)


## Start ability cooldown
##
## Parameters:
##   ability_id: Ability ID for cooldown tracking
##   cooldown: Cooldown duration in seconds
##
## Task: 4.1 - Ability Hotbar, Task 4.2 - Targeting System
## Requirements: 5
##
## Emits signal for HUD to update cooldown visuals.
func start_ability_cooldown(ability_id: String, cooldown: float) -> void:
	print("[PlayerEntity] Starting cooldown for ability %s: %f seconds" % [ability_id, cooldown])
	ability_cooldown_started.emit(ability_id, cooldown)


## ============================================================================
## SERVER RECONCILIATION
## ============================================================================

## Apply server position with reconciliation
##
## Parameters:
##   server_pos: Authoritative position from server
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3.3 (Server Reconciliation)
## Design: PlayerEntity (lines 344-351)
##
## This function reconciles client-predicted position with server position:
## - If distance > SNAP_THRESHOLD: Teleport (major desync)
## - If distance > INTERPOLATE_THRESHOLD: Smooth interpolate (minor desync)
## - Else: No correction needed (client prediction accurate)
func apply_server_position(server_pos: Vector2) -> void:
	var distance = global_position.distance_to(server_pos)

	if distance > SNAP_THRESHOLD:
		# Major desync - snap to server position
		print("[PlayerEntity] Snapping to server position (distance: %f)" % distance)
		global_position = server_pos
		server_position = server_pos
	elif distance > INTERPOLATE_THRESHOLD:
		# Minor desync - smooth interpolation
		global_position = global_position.lerp(server_pos, INTERPOLATION_SPEED)
		server_position = server_pos
	else:
		# Client prediction accurate, no correction needed
		server_position = server_pos


## ============================================================================
## ENTITY DATA UPDATES
## ============================================================================

## Update entity data from delta
##
## Parameters:
##   data: Dictionary with updated entity fields
##
## Called by WorldState when delta update contains changes for this entity.
func apply_update(data: Dictionary) -> void:
	# Update position if present
	if data.has("position"):
		var pos_data = data.position
		var new_pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
		apply_server_position(new_pos)

	# Update health if present
	if data.has("health"):
		health = data.health
		update_health_bar()

	# Update max health if present
	if data.has("maxHealth"):
		max_health = data.maxHealth
		update_health_bar()

	# Update mana if present
	if data.has("mana"):
		mana = data.mana
		update_mana_bar()

	# Update max mana if present
	if data.has("maxMana"):
		max_mana = data.maxMana
		update_mana_bar()

	# Update entity data dictionary
	for key in data.keys():
		entity_data[key] = data[key]


## ============================================================================
## UI UPDATES
## ============================================================================

## Update health bar display
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3
## Design: PlayerEntity (health bar display)
func update_health_bar() -> void:
	if health_bar == null:
		return

	health_bar.max_value = max_health
	health_bar.value = health


## Update mana bar display
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3
## Design: PlayerEntity (mana bar display)
func update_mana_bar() -> void:
	if mana_bar == null:
		return

	mana_bar.max_value = max_mana
	mana_bar.value = mana


## Update name label
##
## Task: 3.2 - Create PlayerEntity Scene
## Requirements: 3
## Design: PlayerEntity (name display)
func update_name_label() -> void:
	if name_label == null:
		return

	var character_name = entity_data.get("name", "Player")
	name_label.text = character_name


## Check if this entity is targetable for abilities
##
## Task: 4.2 - Implement Ability Targeting System
## Requirements: 5
##
## Returns: true (players can be targeted by abilities)
func is_targetable() -> bool:
	return true


## Check if this is the local player
##
## Returns: true if this is the local player entity
func is_local_player() -> bool:
	# Local player has input handling enabled
	return true


## ============================================================================
## INITIALIZATION
## ============================================================================

## Initialize entity with data from snapshot/delta
##
## Parameters:
##   id: Entity ID from server
##   data: Entity data dictionary
##
## Called by WorldState.spawn_entity() when creating this entity.
func initialize(id: String, data: Dictionary) -> void:
	entity_id = id
	entity_data = data

	# Extract transform data
	var transform_data = data.get("transform", {})
	var position_data = transform_data.get("position", data.get("position", {}))

	# Set initial position
	if not position_data.is_empty():
		global_position = Vector2(position_data.get("x", 0), position_data.get("y", 0))
		server_position = global_position
	
	# Extract vitals data
	var vitals_data = data.get("vitals", {})

	# Set initial health/mana from vitals
	health = vitals_data.get("health", 100.0)
	max_health = vitals_data.get("maxHealth", vitals_data.get("max_health", 100.0))
	mana = vitals_data.get("mana", 100.0)
	max_mana = vitals_data.get("maxMana", vitals_data.get("max_mana", 100.0))

	# Extract character data from state
	var state_data = data.get("state", {})
	if state_data.has("character_id"):
		character_data["character_id"] = state_data.character_id

	# Update UI
	if is_node_ready():
		update_health_bar()
		update_mana_bar()
		update_name_label()

	print("[PlayerEntity] Initialized player entity: %s at (%f, %f)" % [entity_id, global_position.x, global_position.y])
