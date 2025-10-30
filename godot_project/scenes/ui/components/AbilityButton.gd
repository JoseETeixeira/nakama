extends Button

## AbilityButton - Reusable ability slot component for hotbar
##
## Task 4.1: Create Ability Hotbar UI
## Requirements: 5 (Combat and Ability System)
##
## Displays ability icon, cooldown timer, and mana cost.
## Handles tooltip display and disabled state management.

# Ability slot index (1-9)
var slot_index: int = 1

# Ability data
var ability_data: Dictionary = {}

# Cooldown tracking
var cooldown_remaining: float = 0.0
var cooldown_total: float = 0.0
var is_on_cooldown: bool = false

# UI references
@onready var icon_texture: TextureRect = $Icon
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var cooldown_label: Label = $CooldownLabel
@onready var mana_cost_label: Label = $ManaCostLabel
@onready var hotkey_label: Label = $HotkeyLabel


func _ready() -> void:
	# Set hotkey label
	hotkey_label.text = str(slot_index)

	# Initialize cooldown overlay (hidden by default)
	cooldown_overlay.visible = false
	cooldown_label.visible = false

	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_button_pressed)


func _process(delta: float) -> void:
	# Update cooldown timer
	if is_on_cooldown and cooldown_remaining > 0:
		cooldown_remaining -= delta

		if cooldown_remaining <= 0:
			# Cooldown finished
			cooldown_remaining = 0
			is_on_cooldown = false
			cooldown_overlay.visible = false
			cooldown_label.visible = false
			update_disabled_state()
		else:
			# Update cooldown display
			cooldown_label.text = "%.1f" % cooldown_remaining

			# Update cooldown overlay height (fills from bottom to top)
			var progress = 1.0 - (cooldown_remaining / cooldown_total)
			cooldown_overlay.size.y = icon_texture.size.y * (1.0 - progress)


## Set ability data for this slot
##
## Parameters:
##   data: Dictionary with ability info
##     - id: String (ability identifier)
##     - name: String (display name)
##     - icon: String (path to icon texture)
##     - mana_cost: int (mana required)
##     - cooldown: float (cooldown duration in seconds)
func set_ability(data: Dictionary) -> void:
	ability_data = data

	if ability_data.is_empty():
		# Empty slot
		icon_texture.texture = null
		mana_cost_label.text = ""
		disabled = true
	else:
		# Load ability icon
		if "icon" in ability_data and ability_data.icon != "":
			# For now, use placeholder colored rect
			# In production, would load actual texture: icon_texture.texture = load(ability_data.icon)
			icon_texture.visible = true

		# Set mana cost label
		if "mana_cost" in ability_data:
			mana_cost_label.text = str(ability_data.mana_cost)

		update_disabled_state()


## Start cooldown for this ability
##
## Parameters:
##   duration: Cooldown duration in seconds
func start_cooldown(duration: float) -> void:
	cooldown_remaining = duration
	cooldown_total = duration
	is_on_cooldown = true
	cooldown_overlay.visible = true
	cooldown_label.visible = true
	update_disabled_state()


## Update disabled state based on cooldown and mana
##
## Parameters:
##   current_mana: Player's current mana (optional)
func update_disabled_state(current_mana: int = 999999) -> void:
	if ability_data.is_empty():
		disabled = true
		return

	# Disable if on cooldown
	if is_on_cooldown:
		disabled = true
		return

	# Disable if insufficient mana
	var mana_cost = ability_data.get("mana_cost", 0)
	if current_mana < mana_cost:
		disabled = true
		return

	# Enable button
	disabled = false


## Show tooltip on mouse hover
func _on_mouse_entered() -> void:
	if ability_data.is_empty():
		return

	# Build tooltip text
	var tooltip_text = ""
	if "name" in ability_data:
		tooltip_text += "[b]%s[/b]\n" % ability_data.name
	if "description" in ability_data:
		tooltip_text += "%s\n" % ability_data.description
	if "mana_cost" in ability_data:
		tooltip_text += "\n[color=cyan]Mana Cost: %d[/color]" % ability_data.mana_cost
	if "cooldown" in ability_data:
		tooltip_text += "\n[color=yellow]Cooldown: %.1fs[/color]" % ability_data.cooldown

	# Show tooltip via UIManager
	# Position tooltip above button
	var tooltip_position = global_position + Vector2(0, -100)
	UIManager.show_tooltip({"text": tooltip_text}, tooltip_position)


## Hide tooltip on mouse exit
func _on_mouse_exited() -> void:
	UIManager.hide_tooltip()


## Handle button click
func _on_button_pressed() -> void:
	# Emit signal to HUD for ability activation
	# HUD will forward to PlayerEntity
	if not disabled and not ability_data.is_empty():
		get_parent().get_parent()._on_ability_button_clicked(slot_index)
