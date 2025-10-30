extends Node

## Ability Targeting System
##
## Task: 4.2 - Implement Ability Targeting System
## Requirements: 5 (Combat and Ability System)
## Design: Combat System
##
## Manages ability targeting state, entity selection, and visual feedback.
## Autoload singleton accessible globally as AbilityTargeting.

# Targeting state
enum TargetingMode { NONE, WAITING_FOR_TARGET, TARGETING_GROUND }
var current_mode: TargetingMode = TargetingMode.NONE
var pending_ability_id: String = ""
var pending_ability_data: Dictionary = {}
var hovered_entity: Node = null
var selected_target: Node = null

# Visual feedback references
var targeting_reticle: Control = null
var vfx_container: Node2D = null

# Preloaded scenes
var damage_number_scene: PackedScene = preload("res://scenes/vfx/DamageNumber.tscn")
var projectile_scene: PackedScene = preload("res://scenes/vfx/AbilityProjectile.tscn")

# Signals
signal targeting_started(ability_id: String)
signal targeting_cancelled()
signal target_selected(target_entity: Node)

func _ready() -> void:
	# Create targeting reticle
	_create_targeting_reticle()
	set_process_input(true)

func _create_targeting_reticle() -> void:
	"""Create visual targeting reticle"""
	targeting_reticle = Control.new()
	targeting_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	targeting_reticle.visible = false
	add_child(targeting_reticle)

	# Create circle indicator
	var circle = ColorRect.new()
	circle.size = Vector2(64, 64)
	circle.position = Vector2(-32, -32)
	circle.color = Color(1, 1, 0, 0.3)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	targeting_reticle.add_child(circle)

## Set VFX container reference from Zone
##
## Parameters:
##   container: Node2D to spawn visual effects in
func set_vfx_container(container: Node2D) -> void:
	vfx_container = container

## Start targeting for an ability
##
## Parameters:
##   ability_id: Ability ID to use
##   ability_data: Ability configuration (targeting type, range, etc.)
##   caster: Entity using the ability
##
## Returns: true if targeting started, false if ability doesn't need targeting
func start_targeting(ability_id: String, ability_data: Dictionary, caster: Node) -> bool:
	var targeting_type = ability_data.get("targeting", "none")

	if targeting_type == "none" or targeting_type == "self":
		# No targeting needed, use immediately
		return false

	# Start targeting mode
	current_mode = TargetingMode.WAITING_FOR_TARGET
	pending_ability_id = ability_id
	pending_ability_data = ability_data.duplicate()
	pending_ability_data["caster"] = caster

	# Show targeting reticle
	if targeting_reticle:
		targeting_reticle.visible = true

	targeting_started.emit(ability_id)
	return true

## Cancel current targeting
func cancel_targeting() -> void:
	current_mode = TargetingMode.NONE
	pending_ability_id = ""
	pending_ability_data.clear()
	selected_target = null

	if targeting_reticle:
		targeting_reticle.visible = false

	targeting_cancelled.emit()

func _input(event: InputEvent) -> void:
	if current_mode == TargetingMode.NONE:
		return

	# Cancel targeting on right-click or Escape
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_targeting()
		return

	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		cancel_targeting()
		return

	# Handle left-click for target selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_target_click()

func _process(_delta: float) -> void:
	if current_mode == TargetingMode.WAITING_FOR_TARGET:
		# Update reticle position to mouse
		if targeting_reticle:
			targeting_reticle.global_position = get_viewport().get_mouse_position()

		# Check for hovered entity
		_update_hovered_entity()

func _update_hovered_entity() -> void:
	"""Check if mouse is hovering over a targetable entity"""
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	var world_mouse_pos = camera.get_global_mouse_position()

	# Find entity at mouse position
	var space_state = get_viewport().get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = world_mouse_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var results = space_state.intersect_point(query, 1)
	if results.size() > 0:
		var collider = results[0].collider
		# Check if it's a valid target (has is_targetable function)
		if collider.has_method("is_targetable"):
			hovered_entity = collider
			# Change reticle color to green for valid target
			if targeting_reticle and targeting_reticle.get_child_count() > 0:
				targeting_reticle.get_child(0).color = Color(0, 1, 0, 0.5)
			return

	hovered_entity = null
	# Reset reticle color
	if targeting_reticle and targeting_reticle.get_child_count() > 0:
		targeting_reticle.get_child(0).color = Color(1, 1, 0, 0.3)

func _handle_target_click() -> void:
	"""Handle left-click for target selection"""
	if hovered_entity:
		selected_target = hovered_entity
		target_selected.emit(selected_target)

		# Execute ability with selected target
		var caster = pending_ability_data.get("caster")
		if caster and caster.has_method("use_ability"):
			caster.use_ability(pending_ability_id, selected_target.entity_id)

		# Clear targeting state
		cancel_targeting()

## Spawn damage number at position
##
## Parameters:
##   damage: Damage amount
##   position: World position to spawn at
##   is_critical: Whether this was a critical hit
##   is_healing: Whether this is healing or damage
func spawn_damage_number(damage: int, position: Vector2, is_critical: bool = false, is_healing: bool = false) -> void:
	if not vfx_container:
		print("[AbilityTargeting] No VFX container set, cannot spawn damage number")
		return

	var damage_number = damage_number_scene.instantiate()
	vfx_container.add_child(damage_number)
	damage_number.global_position = position
	damage_number.initialize(damage, is_critical, is_healing)

## Spawn projectile from caster to target
##
## Parameters:
##   from_pos: Starting position (caster)
##   to_pos: Target position
##   ability_id: Ability ID for color/speed customization
##
## Returns: The projectile instance
func spawn_projectile(from_pos: Vector2, to_pos: Vector2, ability_id: String = "") -> Node2D:
	if not vfx_container:
		print("[AbilityTargeting] No VFX container set, cannot spawn projectile")
		return null

	var projectile = projectile_scene.instantiate()
	vfx_container.add_child(projectile)

	# Customize based on ability (could use ability_config data)
	var color = Color.ORANGE
	var speed = 400.0

	projectile.initialize(from_pos, to_pos, speed, color)
	return projectile

## Handle ability result from server
##
## Parameters:
##   result: Ability result dictionary from use_ability RPC
##   caster_pos: Position of the caster
func handle_ability_result(result: Dictionary, caster_pos: Vector2) -> void:
	if not result.get("success", false):
		return

	var targets_hit = result.get("targets_hit", [])
	var damage_dealt = result.get("damage_dealt", 0)
	var is_critical = result.get("critical", false)

	# Spawn projectile if ability has targets
	if targets_hit.size() > 0:
		# Get first target entity
		var target_entity = WorldState.get_entity(targets_hit[0])
		if target_entity:
			var projectile = spawn_projectile(caster_pos, target_entity.global_position)
			if projectile:
				# Wait for impact, then spawn damage number
				await projectile.impact_reached
				spawn_damage_number(damage_dealt, target_entity.global_position, is_critical, false)
	elif damage_dealt > 0:
		# Self-cast or instant ability, show damage at caster position
		spawn_damage_number(damage_dealt, caster_pos, is_critical, false)

	# Process effects
	var effects = result.get("effects", [])
	for effect in effects:
		_apply_visual_effect(effect, caster_pos)

func _apply_visual_effect(effect: Dictionary, position: Vector2) -> void:
	"""Apply visual feedback for ability effects"""
	var effect_type = effect.get("type", "")

	match effect_type:
		"heal":
			var heal_amount = effect.get("value", 0)
			spawn_damage_number(heal_amount, position, false, true)
		"buff":
			# TODO: Show buff icon
			print("[AbilityTargeting] Buff applied: ", effect)
		"debuff":
			# TODO: Show debuff icon
			print("[AbilityTargeting] Debuff applied: ", effect)
