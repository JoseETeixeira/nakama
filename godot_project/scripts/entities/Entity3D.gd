## Entity3D.gd
## Base class for 3D entities in the game world.
## Handles entity state, vitals, and updates from server.
##
## Requirements: 4 (World Entry and Zone Snapshot)
## Phase 2, Task: 2.4.3 - Implement entity instantiation

extends CharacterBody3D
class_name Entity3D

## Unique entity identifier from server
var entity_id: String = ""

## Entity type (player, npc, item, etc.)
var entity_type: String = ""

## Entity vitals (health, mana, etc.)
var vitals: Dictionary = {
	"health": 100,
	"maxHealth": 100,
	"mana": 0,
	"maxMana": 0
}

## Entity state data
var state: String = ""


## Apply an update from server delta
##
## Parameters:
##   update_data: Dictionary with field updates (positionX, positionY, positionZ, health, etc.)
func apply_update(update_data: Dictionary) -> void:
	# Update position if changed
	if update_data.has("positionX") or update_data.has("positionY") or update_data.has("positionZ"):
		var new_x = update_data.get("positionX", position.x)
		var new_y = update_data.get("positionY", position.y)
		var new_z = update_data.get("positionZ", position.z)
		position = Vector3(new_x, new_y, new_z)

	# Update rotation if changed
	if update_data.has("rotationX") or update_data.has("rotationY") or update_data.has("rotationZ"):
		var new_x = update_data.get("rotationX", rotation.x)
		var new_y = update_data.get("rotationY", rotation.y)
		var new_z = update_data.get("rotationZ", rotation.z)
		rotation = Vector3(new_x, new_y, new_z)

	# Update vitals
	if update_data.has("health"):
		vitals["health"] = update_data.get("health")
	if update_data.has("maxHealth"):
		vitals["maxHealth"] = update_data.get("maxHealth")
	if update_data.has("mana"):
		vitals["mana"] = update_data.get("mana")
	if update_data.has("maxMana"):
		vitals["maxMana"] = update_data.get("maxMana")

	# Update state
	if update_data.has("state"):
		state = update_data.get("state")


## Set entity vitals from snapshot data
##
## Parameters:
##   vitals_data: Dictionary with health, maxHealth, mana, maxMana
func set_vitals(vitals_data: Dictionary) -> void:
	if vitals_data.has("health"):
		vitals["health"] = vitals_data["health"]
	if vitals_data.has("maxHealth"):
		vitals["maxHealth"] = vitals_data["maxHealth"]
	if vitals_data.has("mana"):
		vitals["mana"] = vitals_data.get("mana", 0)
	if vitals_data.has("maxMana"):
		vitals["maxMana"] = vitals_data.get("maxMana", 0)
