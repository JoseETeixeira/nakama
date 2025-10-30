extends Node2D

## Ability Projectile Visual Effect
##
## Task: 4.2 - Implement Ability Targeting System
## Requirements: 5 (Combat and Ability System - projectile effects)
## Design: Combat System visual effects
##
## Projectile that travels from caster to target position with trail effect.

@onready var sprite: ColorRect = $Sprite
@onready var trail: Line2D = $Trail

var target_position: Vector2
var speed: float = 400.0
var max_trail_length: int = 20
var has_reached_target: bool = false

signal impact_reached

func _ready() -> void:
	set_process(true)

## Initialize projectile
##
## Parameters:
##   from_pos: Starting position (caster position)
##   to_pos: Target position
##   projectile_speed: Speed in pixels/second
##   color: Projectile color
func initialize(from_pos: Vector2, to_pos: Vector2, projectile_speed: float = 400.0, color: Color = Color.ORANGE) -> void:
	global_position = from_pos
	target_position = to_pos
	speed = projectile_speed
	sprite.color = color
	trail.default_color = Color(color.r, color.g, color.b, 0.5)

func _process(delta: float) -> void:
	if has_reached_target:
		return

	# Move toward target
	var direction = (target_position - global_position).normalized()
	var move_distance = speed * delta

	# Add current position to trail
	trail.add_point(global_position)
	if trail.get_point_count() > max_trail_length:
		trail.remove_point(0)

	# Check if reached target
	if global_position.distance_to(target_position) <= move_distance:
		global_position = target_position
		has_reached_target = true
		impact_reached.emit()
		# Fade out after impact
		await get_tree().create_timer(0.2).timeout
		queue_free()
	else:
		global_position += direction * move_distance
