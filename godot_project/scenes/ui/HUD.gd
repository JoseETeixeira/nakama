extends Control

# References to ability buttons
@onready var ability_buttons: Array[Node] = []
@onready var health_bar: ProgressBar = $BottomPanel/MarginContainer/VBoxContainer/ResourceBar/HealthBar
@onready var mana_bar: ProgressBar = $BottomPanel/MarginContainer/VBoxContainer/ResourceBar/ManaBar

# Player reference (set when zone loads)
var player_entity: Node = null

# Current player stats (updated from delta stream)
var current_health: float = 100.0
var max_health: float = 100.0
var current_mana: float = 100.0
var max_mana: float = 100.0

func _ready() -> void:
	# Gather all ability button references
	var hotbar = $BottomPanel/MarginContainer/VBoxContainer/AbilityHotbar
	for i in range(1, 10):
		var button = hotbar.get_node("AbilityButton" + str(i))
		if button:
			ability_buttons.append(button)
			button.slot_index = i
			button.pressed.connect(_on_ability_button_clicked.bind(i))

	# Connect to WorldState for player stat updates
	if WorldState:
		WorldState.entity_updated.connect(_on_entity_updated)

func set_player_entity(entity: Node) -> void:
	"""Called by Zone when PlayerEntity is spawned"""
	player_entity = entity

	# Connect to player's ability signals
	if player_entity and player_entity.has_signal("ability_cooldown_started"):
		player_entity.ability_cooldown_started.connect(_on_ability_cooldown_started)

	# Load player's abilities from character data
	_load_player_abilities()

func _load_player_abilities() -> void:
	"""Load abilities from player's character data into hotbar slots"""
	if not player_entity or not player_entity.character_data:
		return

	var abilities = player_entity.character_data.get("abilities", [])
	for i in range(min(abilities.size(), 9)):
		var ability_data = abilities[i]
		if ability_data and i < ability_buttons.size():
			ability_buttons[i].set_ability(ability_data)

func _on_ability_button_clicked(slot_index: int) -> void:
	"""Forward ability button clicks to PlayerEntity"""
	if not player_entity:
		return

	# Get ability data from button
	var button_idx = slot_index - 1
	if button_idx < 0 or button_idx >= ability_buttons.size():
		return

	var button = ability_buttons[button_idx]
	if not button.ability_data or button.disabled:
		return

	# Check mana cost
	var mana_cost = button.ability_data.get("mana_cost", 0)
	if current_mana < mana_cost:
		UIManager.show_floating_text("Not enough mana!", player_entity.global_position, Color.CYAN)
		return

	# Forward to PlayerEntity to send use_ability RPC
	var ability_id = button.ability_data.get("id", "")
	if player_entity.has_method("use_ability"):
		player_entity.use_ability(ability_id)

func _on_ability_cooldown_started(ability_id: String, cooldown_duration: float) -> void:
	"""Handle cooldown start signal from PlayerEntity"""
	# Find the button with this ability and start its cooldown visual
	for button in ability_buttons:
		if button.ability_data and button.ability_data.get("id") == ability_id:
			button.start_cooldown(cooldown_duration)
			break

func _on_entity_updated(entity_id: String, data: Dictionary) -> void:
	"""Update HUD when player entity state changes"""
	if not player_entity or entity_id != player_entity.entity_id:
		return

	# Update health/mana from delta data
	if data.has("health"):
		current_health = data.health
		health_bar.value = (current_health / max_health) * 100.0

	if data.has("max_health"):
		max_health = data.max_health
		health_bar.max_value = max_health
		health_bar.value = (current_health / max_health) * 100.0

	if data.has("mana"):
		current_mana = data.mana
		mana_bar.value = (current_mana / max_mana) * 100.0

		# Update ability button disabled states based on mana
		for button in ability_buttons:
			button.update_disabled_state(current_mana)

	if data.has("max_mana"):
		max_mana = data.max_mana
		mana_bar.max_value = max_mana
		mana_bar.value = (current_mana / max_mana) * 100.0

func update_abilities(abilities_data: Array) -> void:
	"""Update hotbar abilities (called when player changes equipped abilities)"""
	for i in range(min(abilities_data.size(), ability_buttons.size())):
		ability_buttons[i].set_ability(abilities_data[i])

	# Clear remaining slots
	for i in range(abilities_data.size(), ability_buttons.size()):
		ability_buttons[i].set_ability(null)
