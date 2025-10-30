extends Node2D

## Damage Number Visual Effect
##
## Task: 4.2 - Implement Ability Targeting System
## Requirements: 5 (Combat and Ability System - damage numbers)
## Design: Combat System visual effects
##
## Displays floating damage/healing numbers that animate upward and fade out.

@onready var label: Label = $Label

var lifetime: float = 1.5  # Total animation duration
var rise_speed: float = 50.0  # Pixels per second upward
var fade_start: float = 0.5  # When to start fading (seconds)
var elapsed: float = 0.0

func _ready() -> void:
	# Start animation
	set_process(true)

## Initialize damage number
##
## Parameters:
##   damage: Damage amount to display
##   is_critical: Whether this was a critical hit
##   is_healing: Whether this is healing (green) or damage (red)
func initialize(damage: int, is_critical: bool = false, is_healing: bool = false) -> void:
	label.text = str(damage)

	# Color based on type
	if is_healing:
		label.modulate = Color.GREEN
	else:
		label.modulate = Color.RED

	# Critical hits are larger and yellow
	if is_critical:
		label.add_theme_font_size_override("font_size", 32)
		label.modulate = Color.YELLOW
		label.text = str(damage) + "!"

func _process(delta: float) -> void:
	elapsed += delta

	# Move upward
	position.y -= rise_speed * delta

	# Fade out after fade_start time
	if elapsed > fade_start:
		var fade_progress = (elapsed - fade_start) / (lifetime - fade_start)
		label.modulate.a = 1.0 - fade_progress

	# Remove when lifetime expires
	if elapsed >= lifetime:
		queue_free()
